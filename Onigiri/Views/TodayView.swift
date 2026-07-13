import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// Home screen: the daily calorie meter, goal gauge, and today's log.
struct TodayView: View {
    @State private var model = TodayModel()
    /// Backs the goal card's month-detail push; refreshed on push.
    @State private var monthModel = CalendarModel()
    @Environment(\.scenePhase) private var scenePhase
    @Query private var goals: [GoalSettings]
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "balance"
    @AppStorage(SharedStore.progressGaugesKey, store: SharedStore.defaults) private var progressGauges = false
    // The two tracked-metric slots; @AppStorage so a Settings change
    // re-renders the row (SharedStore reads alone wouldn't).
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric1ModeKey, store: SharedStore.defaults) private var trackedMetric1Mode = ""
    @AppStorage(SharedStore.trackedMetric1TargetKey, store: SharedStore.defaults) private var trackedMetric1Target = 0.0
    @AppStorage(SharedStore.trackedMetric1IconKey, store: SharedStore.defaults) private var trackedMetric1Icon = ""
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"
    @AppStorage(SharedStore.trackedMetric2ModeKey, store: SharedStore.defaults) private var trackedMetric2Mode = ""
    @AppStorage(SharedStore.trackedMetric2TargetKey, store: SharedStore.defaults) private var trackedMetric2Target = 0.0
    @AppStorage(SharedStore.trackedMetric2IconKey, store: SharedStore.defaults) private var trackedMetric2Icon = ""
    @AppStorage(SharedStore.energyStatsStyleKey, store: SharedStore.defaults) private var energyStatsStyle = "cards"
    @State private var activeSheet: TodaySheet?
    @State private var quickActions = QuickActions.shared
    @State private var toastCenter = ToastCenter.shared
    // Collapsed by default: a full day is four one-line totals; expand what
    // you want to inspect.
    @State private var collapsedSections: Set<FoodCategory> = Set(FoodCategory.allCases)
    @State private var waterCollapsed = true
    /// True while a log row is mid swipe-to-delete, so the day-paging
    /// swipe on the whole screen stands down.
    @State private var rowSwipeActive = false
    /// The headline number follows the user's text size (Dynamic Type);
    /// minimumScaleFactor keeps huge accessibility sizes on one line.
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 60.0

    /// One sheet slot: multiple .sheet modifiers chained on the same view
    /// compete and only one reliably presents. The kind is part of the
    /// identity so a "Log Food" shortcut re-presents a sheet stuck on Meals.
    private enum TodaySheet: Identifiable {
        case settings
        case quickLog(QuickActions.QuickLogKind)
        case datePicker
        case portion(PortionTarget)
        case editEntry(FoodLogEntry)
        case editWater(WaterLogEntry)

        var id: String {
            switch self {
            case .settings: "settings"
            case .quickLog(let kind): "quickLog-\(kind)"
            case .datePicker: "datePicker"
            case .portion(let target): "portion-\(target.name)"
            case .editEntry(let entry): "edit-\(entry.id.uuidString)"
            case .editWater(let entry): "editWater-\(entry.id.uuidString)"
            }
        }
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Layout.screenSpacing) {
                    // The day title is the date-jump door (one tap to the
                    // month grid); "Details" under the headline is the one
                    // door to the day summary. Only captions are tappable —
                    // a link around the whole headline swallowed half of
                    // the day-paging swipes.
                    dayTitleButton
                    VStack(spacing: 8) {
                        // Compact energy mode: Burned/Eaten flank the
                        // headline and the meter cards below disappear —
                        // one row less between the user and the log.
                        HStack(spacing: 12) {
                            if energyStatsStyle == "compact" {
                                energyFlank(model.summary.totalBurnKcal, "Burned")
                            }
                            if progressGauges {
                                gaugedHeadline
                            } else {
                                balanceHeadline
                            }
                            if energyStatsStyle == "compact" {
                                energyFlank(model.summary.intakeKcal, "Eaten")
                            }
                        }
                        nutritionLink {
                            HStack(spacing: 4) {
                                Text("Details")
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .contentShape(.rect)
                        }
                    }
                    hydrationRow
                    // Pure display: its numbers are on its face, and the
                    // day summary already has its one door ("Details").
                    goalCard
                    if energyStatsStyle == "cards" {
                        meterGrid
                    }
                    loggedSection

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    // Denied write access fails every log with an opaque
                    // toast; iOS can't deep-link the Health sharing pane,
                    // so instructions are the recovery path.
                    if model.healthWriteDenied {
                        Text("Health access is off, so logging can't save. Turn it on in the Health app: Profile → Apps → Onigiri.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .padding(.bottom, 24)
            }
            .readableContentWidth()
            .expandsTabBarAtTop()
            // The large title is rendered in-content (dayTitleButton) so
            // one tap opens the month grid directly — the system title
            // menu forced an intermediate "Jump to date…" tap. The bar
            // itself stays (day chevrons, gear); its title is empty.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
            // No onDismiss refresh: every mutation a sheet can make lands
            // in didMutate → mutationVersion → refresh below; a second
            // full refresh per dismissal was pure duplication.
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .settings:
                    SettingsView()
                case .quickLog(let kind):
                    QuickLogSheet(
                        initialKind: kind,
                        logDate: DayBounds.logTimestamp(for: model.selectedDate)
                    )
                case .datePicker:
                    DayJumpSheet(
                        selected: model.selectedDate,
                        earned: monthModel.earned,
                        tracked: monthModel.trackedDaySet
                    ) { day in
                        Task { await model.select(day: day) }
                    }
                    // Earned badges for the grid; refreshes on present.
                    .task {
                        await monthModel.refresh(goal: goals.first.map {
                            SyncedGoal(
                                targetWeightLb: $0.targetWeightLb,
                                targetDate: $0.targetDate,
                                fallbackCurrentWeightLb: $0.fallbackCurrentWeightLb,
                                mode: $0.mode
                            )
                        })
                    }
                case .portion(let target):
                    PortionSheet(target: target) { quantity, category, _ in
                        Task {
                            await LogActions.logFood(
                                name: target.name,
                                kcal: target.kcal * quantity,
                                sodiumMg: target.sodiumMg * quantity,
                                nutrients: target.nutrients.scaled(by: quantity),
                                category: category,
                                date: DayBounds.logTimestamp(for: model.selectedDate)
                            )
                        }
                    }
                    .presentationDetents([.medium, .large])
                case .editEntry(let entry):
                    // Rescale a logged entry: the sheet treats what was
                    // logged as one serving; confirming replaces the entry
                    // (chosen slot, and now a movable date/time), Undo
                    // restores it.
                    PortionSheet(target: PortionTarget(
                        name: entry.name, kcal: entry.kcal,
                        sodiumMg: entry.sodiumMg, nutrients: entry.nutrients,
                        serving: "as logged", defaultCategory: entry.category
                    ), editDate: entry.date) { quantity, category, date in
                        Task {
                            await LogActions.editFoodEntry(
                                entry, quantity: quantity, category: category, date: date
                            )
                        }
                    }
                    .presentationDetents([.medium, .large])
                case .editWater(let entry):
                    WaterEditSheet(entry: entry)
                        .presentationDetents([.medium])
                }
            }
            .onChange(of: quickActions.quickLogRequest) { _, _ in
                consumeQuickLogRequest()
            }
            .onChange(of: quickActions.dayRequest) { _, _ in
                consumeQuickLogRequest()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    guard !rowSwipeActive else { return }
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
        // A slot's nutrient changed in Settings: its day total needs a
        // fresh Health query.
        .onChange(of: trackedMetric1) { _, _ in
            Task { await model.refresh() }
        }
        .onChange(of: trackedMetric2) { _, _ in
            Task { await model.refresh() }
        }
        .refreshable { await model.refresh() }
        // No refresh on appear: .task { start() } covers first appearance
        // (and itself ends in a refresh), and the foreground gate covers
        // re-activations — the onAppear refresh just doubled both.
        .onAppear {
            consumeQuickLogRequest()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                let healthWriteVersion = toastCenter.healthWriteVersion
                Task { await model.foregrounded(healthWriteVersion: healthWriteVersion) }
                consumeQuickLogRequest()
            }
        }
    }

    /// Present the quick-log sheet if an app-icon shortcut asked for it,
    /// and browse to a requested day (Calendar's "View day"). Checked on
    /// change, on appear, and on foregrounding: a request raised before
    /// this view existed must not be lost.
    private func consumeQuickLogRequest() {
        if let day = quickActions.dayRequest {
            quickActions.dayRequest = nil
            Task { await model.select(day: day) }
        }
        guard let kind = quickActions.quickLogRequest else { return }
        quickActions.quickLogRequest = nil
        activeSheet = .quickLog(kind)
    }

    // MARK: - Sections

    private var dayTitle: String {
        if model.isToday { return "Today" }
        if Calendar.current.isDateInYesterday(model.selectedDate) { return "Yesterday" }
        return model.selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.wide).day())
    }

    /// The large title, rendered in-content so it's a one-tap door to
    /// the month grid (the system title menu forced a "Jump to date…"
    /// intermediate tap).
    private var dayTitleButton: some View {
        Button {
            activeSheet = .datePicker
        } label: {
            HStack(spacing: 8) {
                Text(dayTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Measured against Foods/Goal screenshots: the system large
        // title sits at a 16pt leading inset and ~4pt lower than this
        // in-content title's natural position — matched exactly so the
        // header doesn't jump when switching tabs.
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .accessibilityLabel("\(dayTitle). Jump to date")
        .accessibilityIdentifier("dayTitleButton")
    }

    /// Budget remaining for the day, when the user prefers the countdown
    /// headline and a plan exists; nil falls back to the ± balance.
    private var remainingHeadlineKcal: Double? {
        guard balanceStyle == "remaining",
              let goal = goals.first, let plan = plan(for: goal) else { return nil }
        return plan.dailyBudget - model.summary.intakeKcal
    }

    /// Progress-gauges mode: the headline wears a ring showing how much
    /// of the day's calorie budget is eaten (needs a plan; without one
    /// the plain headline renders).
    @ViewBuilder
    private var gaugedHeadline: some View {
        if let goal = goals.first, let plan = plan(for: goal), plan.dailyBudget > 0 {
            let eaten = min(1, max(0, model.summary.intakeKcal / plan.dailyBudget))
            let over = model.summary.intakeKcal > plan.dailyBudget
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: eaten)
                    .stroke(
                        over ? Color.orange : Color.riceToast,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                balanceHeadline
                    .padding(24)
            }
            .frame(width: 190, height: 190)
            .accessibilityElement(children: .combine)
            .accessibilityValue("\((eaten * 100).formatted(.number.precision(.fractionLength(0)))) percent of today's budget eaten")
        } else {
            balanceHeadline
        }
    }

    private var balanceHeadline: some View {
        VStack(spacing: 4) {
            if let remaining = remainingHeadlineKcal {
                let headline = CalorieBudget.remainingHeadline(remaining)
                Text(headline.value, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color.remainingStatus(kcal: remaining))
                    .contentTransition(.numericText())
                Text(headline.caption)
                    .font(.subheadline)
                    // Scale down inside the ring at accessibility sizes,
                    // like the number above — truncated to "kcal bala…".
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
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
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
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
                showsRemaining: model.isToday,
                weeklyTrendLb: model.weeklyTrendLb
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
        // Maintenance needs no weight or date — the budget IS the burn.
        if goal.isMaintenance {
            return CalorieBudget.maintenancePlan(averageDailyBurn: model.expectedDailyBurnKcal)
        }
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

    /// Push to the day's full nutrient breakdown.
    private func nutritionLink(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationLink {
            DayNutritionView(model: model)
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the day's full nutrient breakdown")
    }


    /// One side of the compact energy mode: total burned or eaten kcal.
    private func energyFlank(_ value: Double, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value, format: .number.precision(.fractionLength(0)))")
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var meterGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                // Intake wears the user's food icon — one food icon
                // everywhere content means "food".
                MeterCell(label: "Intake", value: model.summary.intakeKcal) {
                    FoodIconView(raw: foodIcon)
                }
                MeterCell(label: "Active", value: model.summary.activeBurnKcal) {
                    Image(systemName: "flame.fill").foregroundStyle(.red)
                }
                MeterCell(label: "Resting", value: model.summary.restingBurnKcal) {
                    Image(systemName: "bed.double.fill").foregroundStyle(.indigo)
                }
            }
        }
        .padding(.horizontal)
    }

    /// A slot's nutrient from the reactive raw key; nil when set to None.
    private func slotNutrient(_ slot: Int) -> TrackedNutrient? {
        let raw = slot == 1 ? trackedMetric1 : trackedMetric2
        if raw == SharedStore.trackedMetricNone { return nil }
        return TrackedNutrient(key: raw) ?? (slot == 1 ? .sodium : .water)
    }

    /// The two configurable tracked-metric readouts (sodium and water by
    /// default) — a slot set to None disappears; a lone survivor centers.
    @ViewBuilder
    private var hydrationRow: some View {
        let first = slotNutrient(1)
        let second = slotNutrient(2)
        if first != nil || second != nil {
            HStack(spacing: 12) {
                if let first {
                    trackedMetricView(slot: 1, nutrient: first,
                                      alignment: second != nil ? .leading : .center)
                }
                if let second {
                    trackedMetricView(slot: 2, nutrient: second,
                                      alignment: first != nil ? .trailing : .center)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, progressGauges ? 20 : 28)
        }
    }

    /// One tracked metric: limit mode reads and colors like sodium always
    /// has (total only, green → red as the ceiling nears); goal mode like
    /// water ("x / target", green when met). Fill grows from the left in
    /// both (matching fill direction beats mirrored symmetry).
    @ViewBuilder
    private func trackedMetricView(slot: Int, nutrient: TrackedNutrient, alignment: Alignment) -> some View {
        let storedMode = slot == 1 ? trackedMetric1Mode : trackedMetric2Mode
        let mode = TrackedMetricMode(rawValue: storedMode) ?? nutrient.defaultMode
        let target = trackedTarget(slot: slot, nutrient: nutrient)
        let total = model.trackedTotals[slot - 1]
        let met = total >= target
        let tint: Color = mode == .limit
            ? Color.sodiumStatus(mg: total, limitMg: target)
            : (nutrient == .water ? .blue : .green)

        Label {
            switch mode {
            case .limit:
                Text("\(total, format: .number.precision(.fractionLength(0))) \(nutrient.unitSymbol) \(metricName(nutrient))")
                    .foregroundStyle(Color.sodiumStatus(mg: total, limitMg: target))
                    .fontWeight(.medium)
            case .goal:
                Text("\(total, format: .number.precision(.fractionLength(0))) / \(target, format: .number.precision(.fractionLength(0))) \(nutrient.unitSymbol) \(metricName(nutrient))")
                    .foregroundStyle(met ? Color.green : Color.secondary)
                    .fontWeight(met ? .medium : .regular)
            }
        } icon: {
            metricIcon(slot: slot, nutrient: nutrient)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .gaugeFill(
            enabled: progressGauges,
            fraction: target > 0 ? total / target : 0,
            tint: tint
        )
    }

    /// Sodium/water targets live on their long-standing keys (one source
    /// with the calendar, nutrition detail, and reminders).
    private func trackedTarget(slot: Int, nutrient: TrackedNutrient) -> Double {
        switch nutrient {
        case .sodium: return sodiumLimitMg
        case .water: return waterGoalOz
        default:
            let stored = slot == 1 ? trackedMetric1Target : trackedMetric2Target
            return stored > 0 ? stored : nutrient.defaultTarget
        }
    }

    private func metricName(_ nutrient: TrackedNutrient) -> String {
        nutrient.inlineName
    }

    /// Water renders the app-wide water icon (SF droplet option incl.);
    /// every other metric shows its slot emoji — the custom pick or the
    /// nutrient's default (🧂 for sodium, as always).
    @ViewBuilder
    private func metricIcon(slot: Int, nutrient: TrackedNutrient) -> some View {
        if nutrient == .water {
            WaterIconView(raw: waterIcon)
        } else {
            let stored = slot == 1 ? trackedMetric1Icon : trackedMetric2Icon
            Text(SharedStore.isCustomEmoji(stored) ? stored : nutrient.defaultEmoji)
        }
    }

    private var loggedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ALL logging lives behind the corner + pill now — water is
            // the sheet's pinned top row (Micheal's final water home;
            // widget/watch/app icon keep the 1-tap paths).
            HStack {
                // The title is the master toggle: any group open →
                // collapse everything; all closed → open everything
                // (categories and water alike).
                Button {
                    withAnimation(.snappy) {
                        let anyExpanded = collapsedSections.count < FoodCategory.allCases.count
                            || !waterCollapsed
                        if anyExpanded {
                            collapsedSections = Set(FoodCategory.allCases)
                            waterCollapsed = true
                        } else {
                            collapsedSections = []
                            waterCollapsed = false
                        }
                    }
                } label: {
                    Text("Log")
                        .font(.sectionHeader)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log. Collapses or expands every group")
                Spacer()
            }
            .padding(.horizontal)

            if model.foodLog.isEmpty {
                Text(model.isToday ? "Nothing logged yet." : "Nothing was logged this day.")
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
        .accessibilityLabel("Water, \(model.summary.waterOz.formatted(.number.precision(.fractionLength(0)))) ounces, \(waterCollapsed ? "collapsed" : "expanded")")

        if !waterCollapsed {
            ForEach(model.waterLog) { entry in
                HStack(alignment: .firstTextBaseline) {
                    WaterIconView(raw: waterIcon)
                    Text(entry.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(entry.oz, format: .number.precision(.fractionLength(0))) oz")
                        .monospacedDigit()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .logRowSwipeActions(
                    active: $rowSwipeActive,
                    itemName: "\(entry.oz.formatted(.number.precision(.fractionLength(0)))) ounce entry",
                    onTap: { activeSheet = .editWater(entry) },
                    onEdit: { activeSheet = .editWater(entry) }
                ) {
                    Task { await LogActions.deleteWaterEntry(entry) }
                }
                .accessibilityAction(named: "Edit") {
                    activeSheet = .editWater(entry)
                }
                .accessibilityAction(named: "Delete") {
                    Task { await LogActions.deleteWaterEntry(entry) }
                }
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
        .accessibilityLabel("\(category.rawValue), \(total.formatted(.number.precision(.fractionLength(0)))) kcal, \(isCollapsed ? "collapsed" : "expanded")")

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
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .logRowSwipeActions(
                    active: $rowSwipeActive,
                    itemName: entry.name,
                    onTap: { activeSheet = .editEntry(entry) },
                    onEdit: { activeSheet = .editEntry(entry) }
                ) {
                    Task { await LogActions.deleteFoodEntry(entry) }
                }
                .accessibilityAction(named: "Edit") {
                    activeSheet = .editEntry(entry)
                }
                .accessibilityAction(named: "Delete") {
                    Task { await LogActions.deleteFoodEntry(entry) }
                }
                .padding(.horizontal)
            }
        }
    }
}

private extension View {
    /// Progress-gauges mode: a soft fill bar behind a metric, its width
    /// the fraction of the goal/limit reached. `anchor` picks which edge
    /// the fill grows from (water mirrors sodium from the trailing side).
    /// No-op when the toggle is off so the default layout stays intact.
    @ViewBuilder
    func gaugeFill(enabled: Bool, fraction: Double, tint: Color, anchor: Alignment = .leading) -> some View {
        if enabled {
            self
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tint.opacity(0.18))
                            .frame(width: geo.size.width * min(1, max(0, fraction)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: anchor)
                    }
                }
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
        } else {
            self
        }
    }

    func logRowSwipeActions(
        active: Binding<Bool>,
        itemName: String,
        onTap: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(LogRowSwipeActions(
            rowSwipeActive: active, itemName: itemName,
            onTap: onTap, onEdit: onEdit, onDelete: onDelete
        ))
    }
}

/// Swipe actions for log rows, matching the library lists: swipe right
/// (leading) to edit, swipe left (trailing) to delete, full swipes commit
/// the action outright. Today's log lives in a ScrollView (collapsible
/// custom sections), so there are no native swipeActions — this drags the
/// row over button reveals instead, and reports drag activity through the
/// binding so the day-paging swipe stands down.
private struct LogRowSwipeActions: ViewModifier {
    @Binding var rowSwipeActive: Bool
    let itemName: String
    /// Tap on a closed row (an open row's tap just settles it shut) —
    /// free discoverability for the edit hidden behind the swipe.
    var onTap: (() -> Void)?
    var onEdit: (() -> Void)?
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    /// Where the row currently rests: 0, or ±revealWidth when open.
    @State private var restOffset: CGFloat = 0

    /// Floating circular buttons, like the system's iOS 26 swipe pills.
    private static let buttonSize: CGFloat = 44
    private static let revealWidth: CGFloat = 60
    private static let fullSwipe: CGFloat = 220

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background {
                ZStack {
                    if offset > 0, onEdit != nil {
                        HStack {
                            actionButton("pencil", tint: .riceToast) {
                                settle(0)
                                onEdit?()
                            }
                            .accessibilityLabel("Edit \(itemName)")
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 8)
                        .opacity(min(1, offset / 40))
                    }
                    if offset < 0 {
                        HStack {
                            Spacer(minLength: 0)
                            actionButton("trash.fill", tint: .red) {
                                settle(0)
                                onDelete()
                            }
                            .accessibilityLabel("Delete \(itemName)")
                        }
                        .padding(.trailing, 8)
                        .opacity(min(1, -offset / 40))
                    }
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                if restOffset != 0 {
                    settle(0)
                } else {
                    onTap?()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        var next = restOffset + value.translation.width
                        if onEdit == nil { next = min(0, next) }
                        offset = next
                        if abs(offset) > 10 { rowSwipeActive = true }
                    }
                    .onEnded { _ in
                        if offset < -Self.fullSwipe {
                            settle(0)
                            onDelete()
                        } else if offset > Self.fullSwipe, let onEdit {
                            settle(0)
                            onEdit()
                        } else if offset < -Self.revealWidth * 0.6 {
                            settle(-Self.revealWidth)
                        } else if offset > Self.revealWidth * 0.6, onEdit != nil {
                            settle(Self.revealWidth)
                        } else {
                            settle(0)
                        }
                        // After the outer day-swipe's onEnded has run.
                        DispatchQueue.main.async { rowSwipeActive = false }
                    }
            )
    }

    private func actionButton(
        _ symbol: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(tint, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func settle(_ value: CGFloat) {
        withAnimation(.snappy) { offset = value }
        restOffset = value
    }
}

/// Edit a logged water serving: amount and time. Save replaces the
/// entry (write-then-delete in LogActions), Undo restores it.
private struct WaterEditSheet: View {
    let entry: WaterLogEntry
    @Environment(\.dismiss) private var dismiss
    @State private var oz: Double
    @State private var date: Date
    @FocusState private var amountFocused: Bool

    init(entry: WaterLogEntry) {
        self.entry = entry
        _oz = State(initialValue: entry.oz)
        _date = State(initialValue: entry.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $oz, in: 1...128, step: 4) {
                        LabeledContent("Amount (oz)") {
                            TextField("0", value: Binding(
                                get: { oz },
                                set: { oz = min(max($0, 1), 128) }
                            ), format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                                .focused($amountFocused)
                        }
                        .padding(.trailing, 8)
                    }
                    DatePicker(
                        "Time",
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            .navigationTitle("Edit Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Same commit dance as PortionSheet: the field
                        // commits on focus resignation.
                        amountFocused = false
                        DispatchQueue.main.async {
                            Task {
                                await LogActions.editWaterEntry(entry, oz: oz, date: date)
                            }
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(oz <= 0)
                }
            }
        }
        .presentationCornerRadius(28)
        .presentationBackground {
            ZStack {
                Rectangle().fill(.thickMaterial)
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            }
        }
    }
}

/// Graphical date picker for jumping straight to a day's record.
private struct DayJumpSheet: View {
    let selected: Date
    let earned: Set<Date>
    let tracked: Set<Date>
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth: Date

    private let calendar = Calendar.current

    init(selected: Date, earned: Set<Date>, tracked: Set<Date>, onPick: @escaping (Date) -> Void) {
        self.selected = selected
        self.earned = earned
        self.tracked = tracked
        self.onPick = onPick
        _displayedMonth = State(initialValue: Calendar.current.startOfMonth(for: selected))
    }

    var body: some View {
        NavigationStack {
            // The Calendar tab's own grid — earned badges, selection
            // tint — so day browsing looks the same everywhere. Tapping
            // a day IS the pick; no confirm step.
            MonthGridView(
                month: displayedMonth,
                earned: earned,
                tracked: tracked,
                selectedDay: calendar.startOfDay(for: selected),
                onSelect: { day in
                    onPick(day)
                    dismiss()
                }
            )
            .padding(.horizontal)
            .navigationTitle(displayedMonth.formatted(.dateTime.month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        shiftMonth(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous month")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shiftMonth(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month))
                    .accessibilityLabel("Next month")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.thickMaterial)
    }

    private func shiftMonth(_ delta: Int) {
        guard let month = calendar.date(byAdding: .month, value: delta, to: displayedMonth),
              month <= calendar.startOfMonth(for: .now) else { return }
        displayedMonth = month
    }
}

struct DailyGoalCard: View {
    let bankedKcal: Double
    let intakeKcal: Double
    let plan: CalorieBudget.Plan
    var showsRemaining = true
    /// Actual scale movement over the past week (negative = down);
    /// nil when Health has too few weigh-ins to say.
    var weeklyTrendLb: Double? = nil
    @AppStorage(SharedStore.rewardIconKey, store: SharedStore.defaults) private var rewardIcon = "onigiri"

    /// A zero-deficit plan is maintenance: the gauge tracks budget left
    /// instead of deficit banked, and the copy talks budget, not goal.
    private var isMaintenance: Bool { plan.requiredDailyDeficit <= 0 }

    private var progress: Double {
        if isMaintenance {
            return plan.dailyBudget > 0 ? max(0, min(1, 1 - intakeKcal / plan.dailyBudget)) : 0
        }
        return plan.requiredDailyDeficit > 0 ? bankedKcal / plan.requiredDailyDeficit : 1
    }
    private var remainingKcal: Double { plan.dailyBudget - intakeKcal }
    /// `max(0, -0.0)` keeps IEEE negative zero, which formats as "-0".
    private var displayBankedKcal: Double { bankedKcal == 0 ? 0 : bankedKcal }

    var body: some View {
        HStack(spacing: 16) {
            OnigiriGauge(progress: progress, emoji: SharedStore.rewardEmoji(for: rewardIcon))
                .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isMaintenance ? "Daily budget" : "Daily goal")
                        .font(.headline)
                    Text("\(((max(0, min(1, progress))) * 100).formatted(.number.precision(.fractionLength(0))))%")
                        .font(.headline)
                        .foregroundStyle(progress >= 1 ? Color.green : Color.secondary)
                }
                if isMaintenance {
                    Text("\(intakeKcal, format: .number.precision(.fractionLength(0))) of \(plan.dailyBudget, format: .number.precision(.fractionLength(0))) kcal eaten")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(displayBankedKcal, format: .number.precision(.fractionLength(0))) of \(plan.requiredDailyDeficit, format: .number.precision(.fractionLength(0))) kcal deficit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                } else if isMaintenance ? bankedKcal > 0 : progress >= 1 {
                    Text("\(SharedStore.rewardEmoji(for: rewardIcon)) earned")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    // An untracked day isn't a failed day.
                    Text(intakeKcal == 0 ? "nothing logged" : "goal not met")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let trend = weeklyTrendLb {
                    Label {
                        Text("Scale: \(trend < 0 ? "down" : "up") \(abs(trend), format: .number.precision(.fractionLength(1))) lb this week")
                    } icon: {
                        Image(systemName: trend < 0 ? "arrow.down.right" : "arrow.up.right")
                    }
                    .font(.caption)
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

struct MeterCell<Icon: View>: View {
    let label: String
    let value: Double
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: 6) {
            icon
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
