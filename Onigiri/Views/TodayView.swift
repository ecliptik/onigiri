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
    @Query(filter: #Predicate<Food> { $0.isFavorite }, sort: \Food.name)
    private var favoriteFoods: [Food]
    @Query(filter: #Predicate<Meal> { $0.isFavorite }, sort: \Meal.name)
    private var favoriteMeals: [Meal]
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "balance"
    @AppStorage(SharedStore.progressGaugesKey, store: SharedStore.defaults) private var progressGauges = false
    @AppStorage(SharedStore.showSodiumKey, store: SharedStore.defaults) private var showSodium = true
    @AppStorage(SharedStore.showWaterKey, store: SharedStore.defaults) private var showWater = true
    @State private var activeSheet: TodaySheet?
    @State private var quickActions = QuickActions.shared
    @State private var toastCenter = ToastCenter.shared
    // Collapsed by default: a full day is four one-line totals; expand what
    // you want to inspect.
    @State private var collapsedSections: Set<FoodCategory> = Set(FoodCategory.allCases)
    @State private var waterCollapsed = true
    @State private var isLoggingWater = false
    /// True while a log row is mid swipe-to-delete, so the day-paging
    /// swipe on the whole screen stands down.
    @State private var rowSwipeActive = false
    /// Log deletes confirm first, like the library's (and the
    /// confirmation is what lets the delete toast drop its Undo).
    @State private var pendingLogDelete: PendingLogDelete?

    private enum PendingLogDelete: Identifiable {
        case food(FoodLogEntry)
        case water(WaterLogEntry)

        var id: UUID {
            switch self {
            case .food(let entry): entry.id
            case .water(let entry): entry.id
            }
        }

        var title: String {
            switch self {
            case .food(let entry): "Delete “\(entry.name)”?"
            case .water(let entry): "Delete the \(Int(entry.oz)) oz water entry?"
            }
        }
    }
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

        var id: String {
            switch self {
            case .settings: "settings"
            case .quickLog(let kind): "quickLog-\(kind)"
            case .datePicker: "datePicker"
            case .portion(let target): "portion-\(target.name)"
            case .editEntry(let entry): "edit-\(entry.id.uuidString)"
            }
        }
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Layout.screenSpacing) {
                    // Two doors, split by meaning: "Nutrition details" is
                    // what you ate (→ day detail), the goal card is how
                    // the plan is going (→ the month story). Only the
                    // caption is tappable — a link around the whole
                    // headline swallowed half of the day-paging swipes.
                    VStack(spacing: 8) {
                        if progressGauges {
                            gaugedHeadline
                        } else {
                            balanceHeadline
                        }
                        nutritionLink {
                            HStack(spacing: 4) {
                                Text("Nutrition details")
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
                    monthDetailLink { goalCard }
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
            .readableContentWidth()
            .expandsTabBarAtTop()
            .navigationTitle(dayTitle)
            // Tapping the title offers fast day jumps (Calendar-style
            // picker) and a way home from deep browsing.
            .toolbarTitleMenu {
                Button("Jump to date…", systemImage: "calendar") {
                    activeSheet = .datePicker
                }
                if !model.isToday {
                    Button("Go to today", systemImage: "arrow.uturn.backward") {
                        Task { await model.select(day: .now) }
                    }
                }
            }
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
                case .datePicker:
                    DayJumpSheet(selected: model.selectedDate) { day in
                        Task { await model.select(day: day) }
                    }
                case .portion(let target):
                    PortionSheet(target: target) { quantity, category in
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
                    // in place (same time, chosen slot), Undo restores it.
                    PortionSheet(target: PortionTarget(
                        name: entry.name, kcal: entry.kcal,
                        sodiumMg: entry.sodiumMg, nutrients: entry.nutrients,
                        serving: "as logged", defaultCategory: entry.category
                    )) { quantity, category in
                        Task {
                            await LogActions.editFoodEntry(entry, quantity: quantity, category: category)
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .alert(
                pendingLogDelete?.title ?? "",
                isPresented: .init(
                    get: { pendingLogDelete != nil },
                    set: { if !$0 { pendingLogDelete = nil } }
                ),
                presenting: pendingLogDelete
            ) { pending in
                Button("Delete", role: .destructive) {
                    Task {
                        switch pending {
                        case .food(let entry): await LogActions.deleteFoodEntry(entry)
                        case .water(let entry): await LogActions.deleteWaterEntry(entry)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This can't be undone.")
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

    /// Outline glass with a toast-tinted stroke: the glass alone nearly
    /// vanishes on white, so the ring is what says "button" in light mode.
    private func logButtonLabel(@ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.riceToast)
            icon()
                .font(.title3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay(
            Capsule().strokeBorder(Color.riceToast.opacity(0.5), lineWidth: 1)
        )
    }

    /// Favorite meals log one-tap with their own slot, like the Log sheet.
    private func logFavorite(meal: Meal) {
        Task {
            await LogActions.logFood(
                name: meal.name,
                kcal: meal.totalKcal,
                sodiumMg: meal.totalSodiumMg,
                nutrients: meal.totalNutrients,
                category: PortionTarget.category(from: meal.category),
                date: DayBounds.logTimestamp(for: model.selectedDate)
            )
        }
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
            .accessibilityValue("\(Int(eaten * 100)) percent of today's budget eaten")
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

    /// Push to the same month story Calendar's summary card shows; the
    /// model refreshes on push so Today doesn't pay for it up front.
    private func monthDetailLink(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationLink {
            MonthDetailView(model: monthModel, month: .now)
                .task {
                    await monthModel.refresh(goal: goals.first.map {
                        SyncedGoal(
                            targetWeightLb: $0.targetWeightLb,
                            targetDate: $0.targetDate,
                            fallbackCurrentWeightLb: $0.fallbackCurrentWeightLb
                        )
                    })
                }
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows this month's deficit, weight change, and records")
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

    /// Sodium and water readouts — each hideable in Settings (the metric
    /// itself, not just its fill bar). A lone survivor centers.
    @ViewBuilder
    private var hydrationRow: some View {
        if showSodium || showWater {
            HStack(spacing: 12) {
                if showSodium {
                    Label {
                        Text("\(model.summary.sodiumMg, format: .number.precision(.fractionLength(0))) mg sodium")
                            .foregroundStyle(Color.sodiumStatus(mg: model.summary.sodiumMg, limitMg: sodiumLimitMg))
                            .fontWeight(.medium)
                    } icon: {
                        // Salt shaker, matching the emoji water icon beside
                        // it (aqi.medium was an air-quality glyph).
                        Text("🧂")
                    }
                    .frame(maxWidth: .infinity, alignment: showWater ? .leading : .center)
                    .gaugeFill(
                        enabled: progressGauges,
                        fraction: sodiumLimitMg > 0 ? model.summary.sodiumMg / sodiumLimitMg : 0,
                        tint: Color.sodiumStatus(mg: model.summary.sodiumMg, limitMg: sodiumLimitMg)
                    )
                }

                if showWater {
                    Label {
                        Text("\(model.summary.waterOz, format: .number.precision(.fractionLength(0))) / \(waterGoalOz, format: .number.precision(.fractionLength(0))) oz water")
                            .foregroundStyle(model.summary.waterOz >= waterGoalOz ? Color.green : Color.secondary)
                            .fontWeight(model.summary.waterOz >= waterGoalOz ? .medium : .regular)
                    } icon: {
                        WaterIconView(raw: waterIcon)
                    }
                    .frame(maxWidth: .infinity, alignment: showSodium ? .trailing : .center)
                    // Fill grows from the left like sodium's (Micheal:
                    // matching fill direction beats mirrored symmetry).
                    .gaugeFill(
                        enabled: progressGauges,
                        fraction: waterGoalOz > 0 ? model.summary.waterOz / waterGoalOz : 0,
                        tint: .blue
                    )
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, progressGauges ? 20 : 28)
        }
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
                // the primary logging actions. Tap opens the Log sheet;
                // long-press offers favorites and the scanner — the food
                // parallel of the water button's amounts.
                Menu {
                    ForEach(favoriteMeals.prefix(6)) { meal in
                        Button("⭐ \(meal.name)") {
                            logFavorite(meal: meal)
                        }
                    }
                    ForEach(favoriteFoods.prefix(6)) { food in
                        Button("⭐ \(food.name)") {
                            activeSheet = .portion(PortionTarget(
                                name: food.name, kcal: food.kcal,
                                sodiumMg: food.sodiumMg, nutrients: food.nutrients,
                                serving: food.servingDescription,
                                defaultCategory: PortionTarget.category(from: food.category)
                            ))
                        }
                    }
                    Divider()
                    Button("Scan barcode", systemImage: "barcode.viewfinder") {
                        QuickActions.shared.pending = .scanBarcode
                    }
                } label: {
                    logButtonLabel { FoodIconView(raw: foodIcon) }
                } primaryAction: {
                    activeSheet = .quickLog(.all)
                }
                .buttonStyle(.plain)
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
                    logButtonLabel { WaterIconView(raw: waterIcon) }
                } primaryAction: {
                    logWater(oz: SharedStore.waterServingOz)
                }
                .buttonStyle(.plain)
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
                    itemName: "\(Int(entry.oz)) ounce entry"
                ) {
                    pendingLogDelete = .water(entry)
                }
                .accessibilityAction(named: "Delete") {
                    pendingLogDelete = .water(entry)
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
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .logRowSwipeActions(
                    active: $rowSwipeActive,
                    itemName: entry.name,
                    onEdit: { activeSheet = .editEntry(entry) }
                ) {
                    pendingLogDelete = .food(entry)
                }
                .accessibilityAction(named: "Edit") {
                    activeSheet = .editEntry(entry)
                }
                .accessibilityAction(named: "Delete") {
                    pendingLogDelete = .food(entry)
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
        onEdit: (() -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(LogRowSwipeActions(
            rowSwipeActive: active, itemName: itemName,
            onEdit: onEdit, onDelete: onDelete
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
                if restOffset != 0 { settle(0) }
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

/// Graphical date picker for jumping straight to a day's record.
private struct DayJumpSheet: View {
    @State var selected: Date
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "Day",
                selection: $selected,
                in: ...Date.now,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding(.horizontal)
            .navigationTitle("Jump to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("View Day") {
                        onPick(selected)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct DailyGoalCard: View {
    let bankedKcal: Double
    let intakeKcal: Double
    let plan: CalorieBudget.Plan
    var showsRemaining = true
    @AppStorage(SharedStore.rewardIconKey, store: SharedStore.defaults) private var rewardIcon = "onigiri"

    private var progress: Double {
        plan.requiredDailyDeficit > 0 ? bankedKcal / plan.requiredDailyDeficit : 1
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
                    Text("Daily goal")
                        .font(.headline)
                    Text("\(Int((max(0, min(1, progress))) * 100))%")
                        .font(.headline)
                        .foregroundStyle(progress >= 1 ? Color.green : Color.secondary)
                }
                Text("\(displayBankedKcal, format: .number.precision(.fractionLength(0))) of \(plan.requiredDailyDeficit, format: .number.precision(.fractionLength(0))) kcal deficit")
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
                    Text("\(SharedStore.rewardEmoji(for: rewardIcon)) earned")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    // An untracked day isn't a failed day.
                    Text(intakeKcal == 0 ? "nothing logged" : "goal not met")
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
