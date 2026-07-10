import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// Home screen: the daily calorie meter, goal gauge, and today's log.
struct TodayView: View {
    @State private var model = TodayModel()
    @Environment(\.scenePhase) private var scenePhase
    @Query private var goals: [GoalSettings]
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "drop"
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "plate"
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "balance"
    @State private var activeSheet: TodaySheet?
    @State private var quickActions = QuickActions.shared
    @State private var toastCenter = ToastCenter.shared
    // Collapsed by default: a full day is four one-line totals; expand what
    // you want to inspect.
    @State private var collapsedSections: Set<FoodCategory> = Set(FoodCategory.allCases)
    @State private var waterCollapsed = true
    @State private var isLoggingWater = false
    /// The headline number follows the user's text size (Dynamic Type);
    /// minimumScaleFactor keeps huge accessibility sizes on one line.
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 60.0

    /// One sheet slot: multiple .sheet modifiers chained on the same view
    /// compete and only one reliably presents. The kind is part of the
    /// identity so a "Log Food" shortcut re-presents a sheet stuck on Meals.
    private enum TodaySheet: Identifiable {
        case settings
        case quickLog(QuickActions.QuickLogKind)

        var id: String {
            switch self {
            case .settings: "settings"
            case .quickLog(let kind): "quickLog-\(kind)"
            }
        }
    }

    private var waterEmoji: String { waterIcon == "wave" ? "🌊" : "💧" }
    private var foodEmoji: String { foodIcon == "onigiri" ? "🍙" : "🍽️" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Layout.screenSpacing) {
                    balanceHeadline
                    hydrationRow
                    goalCard
                    meterGrid
                    loggedSection

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle(dayTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await model.goToPreviousDay() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous day")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    Button {
                        Task { await model.goToNextDay() }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(model.isToday)
                    .accessibilityLabel("Next day")
                }
            }
            .sheet(item: $activeSheet, onDismiss: {
                Task { await model.refresh() }
            }) { sheet in
                switch sheet {
                case .settings:
                    SettingsView()
                case .quickLog(let kind):
                    QuickLogSheet(
                        initialKind: kind,
                        logDate: DayBounds.logTimestamp(for: model.selectedDate)
                    )
                }
            }
            .onChange(of: quickActions.quickLogRequest) { _, _ in
                consumeQuickLogRequest()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -60 {
                        Task { await model.goToNextDay() }
                    } else if value.translation.width > 60 {
                        Task { await model.goToPreviousDay() }
                    }
                }
            )
        }
        .task { await model.start() }
        .onChange(of: toastCenter.mutationVersion) { _, _ in
            Task { await model.refresh() }
        }
        .refreshable { await model.refresh() }
        .onAppear {
            Task { await model.refresh() }
            consumeQuickLogRequest()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await model.loadStatic()
                    await model.refresh()
                }
                consumeQuickLogRequest()
            }
        }
    }

    private func logButtonLabel(_ emoji: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
            Text(emoji)
                .font(.title3)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }

    /// Water logs into the browsed day (backfill included).
    private func logWater(oz: Double) {
        guard !isLoggingWater else { return }
        isLoggingWater = true
        Task {
            defer { isLoggingWater = false }
            await LogActions.logWater(
                oz: oz,
                date: DayBounds.logTimestamp(for: model.selectedDate)
            )
        }
    }

    /// Present the quick-log sheet if an app-icon shortcut asked for it.
    /// Checked on change, on appear, and on foregrounding: a request raised
    /// before this view existed must not be lost.
    private func consumeQuickLogRequest() {
        guard let kind = quickActions.quickLogRequest else { return }
        quickActions.quickLogRequest = nil
        activeSheet = .quickLog(kind)
    }

    // MARK: - Sections

    private var dayTitle: String {
        if model.isToday { return "Today" }
        if Calendar.current.isDateInYesterday(model.selectedDate) { return "Yesterday" }
        return model.selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Budget remaining for the day, when the user prefers the countdown
    /// headline and a plan exists; nil falls back to the ± balance.
    private var remainingHeadlineKcal: Double? {
        guard balanceStyle == "remaining",
              let goal = goals.first, let plan = plan(for: goal) else { return nil }
        return plan.dailyBudget - model.summary.intakeKcal
    }

    private var balanceHeadline: some View {
        VStack(spacing: 4) {
            if let remaining = remainingHeadlineKcal {
                Text(remaining, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(remaining >= 0 ? Color.green : Color.orange)
                    .contentTransition(.numericText())
                Text("kcal left")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(model.summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                    .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(model.summary.balanceKcal <= 0 ? Color.green : Color.orange)
                    .contentTransition(.numericText())
                Text("kcal balance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var goalCard: some View {
        if let goal = goals.first, let plan = plan(for: goal) {
            DailyGoalCard(
                bankedKcal: max(0, -model.summary.balanceKcal),
                intakeKcal: model.summary.intakeKcal,
                plan: plan,
                showsRemaining: model.isToday
            )
        } else {
            Text(goals.isEmpty
                 ? "Set a weight goal in the Goal tab to track your daily deficit here."
                 : "Add a weigh-in (or set your current weight in the Goal tab) to track your daily deficit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func plan(for goal: GoalSettings) -> CalorieBudget.Plan? {
        guard let weight = model.currentWeightLb ?? goal.fallbackCurrentWeightLb else { return nil }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: .now), to: goal.targetDate
        ).day ?? 0
        return CalorieBudget.plan(
            currentWeightLb: weight,
            targetWeightLb: goal.targetWeightLb,
            daysRemaining: days,
            averageDailyBurn: model.expectedDailyBurnKcal
        )
    }

    private var meterGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MeterCell(label: "Intake", value: model.summary.intakeKcal, systemImage: "fork.knife", tint: .orange)
                MeterCell(label: "Active", value: model.summary.activeBurnKcal, systemImage: "flame.fill", tint: .red)
                MeterCell(label: "Resting", value: model.summary.restingBurnKcal, systemImage: "bed.double.fill", tint: .indigo)
            }
        }
        .padding(.horizontal)
    }

    private var hydrationRow: some View {
        HStack(spacing: 12) {
            Label {
                Text("\(model.summary.sodiumMg, format: .number.precision(.fractionLength(0))) mg sodium")
                    .foregroundStyle(Color.sodiumStatus(mg: model.summary.sodiumMg, limitMg: sodiumLimitMg))
                    .fontWeight(.medium)
            } icon: {
                // Salt shaker, matching the emoji water icon beside it
                // (aqi.medium was an air-quality glyph).
                Text("🧂")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("\(model.summary.waterOz, format: .number.precision(.fractionLength(0))) / \(waterGoalOz, format: .number.precision(.fractionLength(0))) oz water")
                        .foregroundStyle(model.summary.waterOz >= waterGoalOz ? Color.green : Color.secondary)
                        .fontWeight(model.summary.waterOz >= waterGoalOz ? .medium : .regular)
                } icon: {
                    Text(waterEmoji)
                }
                ProgressView(value: min(1, waterGoalOz > 0 ? model.summary.waterOz / waterGoalOz : 0))
                    .tint(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 28)
    }

    private var loggedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Log")
                    .font(.sectionHeader)
                Spacer()
                // Present on past days too: forgotten meals get backfilled
                // into the browsed day (noon timestamp, slot picked in the
                // portion sheet). Prominent glass, sized for their role as
                // the primary logging actions.
                Button {
                    activeSheet = .quickLog(.all)
                } label: {
                    logButtonLabel(foodEmoji)
                }
                .buttonStyle(.glassProminent)
                .tint(.ricePaper)
                .accessibilityLabel("Log food or meal")

                // Tap logs the default serving; long-press offers the
                // other amounts (the old Water tab's menu).
                Menu {
                    ForEach([8.0, 12, 16, 20, 24, 32], id: \.self) { oz in
                        Button("\(oz, format: .number.precision(.fractionLength(0))) oz") {
                            logWater(oz: oz)
                        }
                    }
                } label: {
                    logButtonLabel(waterEmoji)
                } primaryAction: {
                    logWater(oz: SharedStore.waterServingOz)
                }
                .buttonStyle(.glassProminent)
                .tint(.ricePaper)
                .disabled(isLoggingWater)
                .accessibilityLabel("Log \(Int(SharedStore.waterServingOz)) ounces of water")
            }
            .padding(.horizontal)

            if model.foodLog.isEmpty {
                Text(model.isToday ? "Nothing Logged" : "Nothing was logged this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            ForEach(FoodCategory.allCases) { category in
                let entries = model.foodLog.filter { $0.category == category }
                if !entries.isEmpty {
                    mealSection(category, entries: entries)
                }
            }

            if !model.waterLog.isEmpty {
                waterSection
            }
        }
        // Full width regardless of content, so the header stays left-pinned
        // even when the day has no entries.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The day's water servings, folded into the log like a meal slot.
    @ViewBuilder
    private var waterSection: some View {
        Button {
            withAnimation(.snappy) { waterCollapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(waterCollapsed ? 0 : 90))
                Text("Water")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.summary.waterOz, format: .number.precision(.fractionLength(0))) oz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityLabel("Water, \(Int(model.summary.waterOz)) ounces, \(waterCollapsed ? "collapsed" : "expanded")")

        if !waterCollapsed {
            ForEach(model.waterLog) { entry in
                HStack(alignment: .firstTextBaseline) {
                    Text(waterEmoji)
                    Text(entry.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(entry.oz, format: .number.precision(.fractionLength(0))) oz")
                        .monospacedDigit()
                    Button {
                        Task { await LogActions.deleteWaterEntry(entry) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(Int(entry.oz)) ounce entry")
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    /// One meal-slot group: a tappable header with the slot's total that
    /// collapses its entries to keep long days readable.
    @ViewBuilder
    private func mealSection(_ category: FoodCategory, entries: [FoodLogEntry]) -> some View {
        let total = entries.reduce(0) { $0 + $1.kcal }
        let isCollapsed = collapsedSections.contains(category)

        Button {
            withAnimation(.snappy) {
                if isCollapsed {
                    collapsedSections.remove(category)
                } else {
                    collapsedSections.insert(category)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(category.rawValue)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(total, format: .number.precision(.fractionLength(0))) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityLabel("\(category.rawValue), \(Int(total)) kcal, \(isCollapsed ? "collapsed" : "expanded")")

        if !isCollapsed {
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                        Text(entry.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(entry.kcal, format: .number.precision(.fractionLength(0))) kcal")
                            .monospacedDigit()
                        Text("\(entry.sodiumMg, format: .number.precision(.fractionLength(0))) mg Na")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button {
                        Task { await LogActions.deleteFoodEntry(entry) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(entry.name)")
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}

struct DailyGoalCard: View {
    let bankedKcal: Double
    let intakeKcal: Double
    let plan: CalorieBudget.Plan
    var showsRemaining = true

    private var progress: Double {
        plan.requiredDailyDeficit > 0 ? bankedKcal / plan.requiredDailyDeficit : 1
    }
    private var remainingKcal: Double { plan.dailyBudget - intakeKcal }

    var body: some View {
        HStack(spacing: 16) {
            OnigiriGauge(progress: progress)
                .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Daily goal")
                        .font(.headline)
                    Text("\(Int((max(0, min(1, progress))) * 100))%")
                        .font(.headline)
                        .foregroundStyle(progress >= 1 ? Color.green : Color.secondary)
                }
                Text("\(bankedKcal, format: .number.precision(.fractionLength(0))) of \(plan.requiredDailyDeficit, format: .number.precision(.fractionLength(0))) kcal deficit")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                // Keep the card the same height across days: today shows the
                // remaining budget; past days show the day's outcome.
                if showsRemaining {
                    if remainingKcal >= 0 {
                        Text("≈ \(remainingKcal, format: .number.precision(.fractionLength(0))) kcal left to eat today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("≈ \(-remainingKcal, format: .number.precision(.fractionLength(0))) kcal over budget")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                } else if progress >= 1 {
                    Text("🍙 earned")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    Text("goal not met")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if plan.isAggressive {
                    Label("Aggressive pace — consider a later date", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        .padding(.horizontal)
    }
}

struct MeterCell: View {
    let label: String
    let value: Double
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
