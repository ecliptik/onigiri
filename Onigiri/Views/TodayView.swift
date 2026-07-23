import SwiftUI
import UIKit
import SwiftData
import WidgetKit
import OnigiriKit

/// Home screen: the daily calorie meter, goal gauge, and today's log.
struct TodayView: View {
    @State private var model = TodayModel()
    /// Backs the goal card's month-detail push; refreshed on push.
    @State private var monthModel = CalendarModel()
    @Environment(\.scenePhase) private var scenePhase
    /// Regular width lays the summary beside the log (two panes).
    @Environment(\.horizontalSizeClass) private var hSizeClass
    /// Reduce Motion swaps every custom spring/glide for an instant cut
    /// (nil animation) — the layouts land identically, nothing moves.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Status stays color-only on screen by ruling — EXCEPT under
    /// Differentiate Without Color, where a small glyph twin appears
    /// (the VoiceOver twins never render, so sighted colorblind users
    /// otherwise get nothing).
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Query private var goals: [GoalSettings]
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "remaining"
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

    /// The log rows' secondary caption metric — the first tracked slot
    /// that applies to foods (sodium unless customized; the user).
    private var entryMetric: TrackedNutrient {
        .firstFoodMetric(slot1: trackedMetric1, slot2: trackedMetric2)
    }
    @AppStorage(SharedStore.trackedMetric2IconKey, store: SharedStore.defaults) private var trackedMetric2Icon = ""
    @AppStorage(SharedStore.energyStatsStyleKey, store: SharedStore.defaults) private var energyStatsStyle = "cards"
    @AppStorage(SharedStore.waterUnitKey, store: SharedStore.defaults) private var waterUnitRaw = SharedStore.unitAutomatic
    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults) private var sodiumUnitRaw = SharedStore.unitAutomatic
    private var waterUnit: WaterUnit { WaterUnit.resolve(waterUnitRaw) }
    private var sodiumUnit: SodiumUnit { SodiumUnit.resolve(sodiumUnitRaw) }
    @State private var activeSheet: TodaySheet?
    @State private var quickActions = QuickActions.shared
    /// Value-routed push so the deep-link path can force-pop: a bare
    /// NavigationLink push isn't addressable, so the quick-log sheet
    /// used to present OVER a stale Day Nutrition push (and dismissing
    /// stranded the user there instead of on Today).
    private enum Route: Hashable { case nutrition }
    @State private var navPath: [Route] = []
    @State private var toastCenter = ToastCenter.shared
    // Collapsed by default: a full day is four one-line totals; expand what
    // you want to inspect.
    @State private var collapsedSections: Set<FoodCategory> = Set(FoodCategory.allCases)
    @State private var waterCollapsed = true
    /// True while a log row is mid swipe-to-delete, so the day-paging
    /// swipe on the whole screen stands down. Held in an @Observable box,
    /// NOT a plain @State the body reads: a row's swipe writes it, but the
    /// only reader is the day-paging gesture's onEnded closure (evaluated
    /// at gesture-end, not during body eval), so flipping it no longer
    /// invalidates the whole screen mid-gesture — the old shared @State
    /// turned every swipe into a full-body re-render (dead taps).
    @State private var rowSwipe = RowSwipeState()
    /// The headline number follows the user's text size (Dynamic Type);
    /// minimumScaleFactor keeps huge accessibility sizes on one line.
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 60.0
    /// The headline ring's frame follows Dynamic Type (capped — the
    /// gauge emoji inside scales with the frame, so a fixed 190 left
    /// the badge frozen while @ScaledMetric text grew around it).
    @ScaledMetric(relativeTo: .largeTitle) private var ringDiameter = 190.0

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
        NavigationStack(path: $navPath) {
            // The reader serves the Log master toggle: expanding scrolls
            // the log to the top of the viewport, collapsing returns to
            // the day headline (both anchors always exist — they're the
            // non-lazy tops of their stacks, so scrollTo is deterministic).
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: Layout.screenSpacing) {
                    // The day title is the date-jump door (one tap to the
                    // month grid); "Details" under the headline is the one
                    // door to the day summary. Only captions are tappable —
                    // a link around the whole headline swallowed half of
                    // the day-paging swipes.
                    dayTitleButton
                        .id(ScrollTarget.dayTop)
                    if hSizeClass == .regular {
                        // iPad/regular width: the summary beside the log,
                        // not a phone column stretched across the canvas.
                        HStack(alignment: .top, spacing: Layout.screenSpacing) {
                            VStack(spacing: Layout.screenSpacing) { summaryStack }
                                .frame(maxWidth: .infinity)
                            VStack(spacing: Layout.screenSpacing) { logStack(scrollProxy) }
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        summaryStack
                        logStack(scrollProxy)
                    }
                }
                .padding(.bottom, 24)
            }
            // Grouped surface idiom, app-wide (the user, 2026-07-13):
            // gray page + secondarySystemGroupedBackground cards, so
            // every card in the app matches the List screens' cells in
            // both modes (quaternary-over-background diverged in dark).
            // Two panes need more canvas than one phone column.
            .readableContentWidth(max: hSizeClass == .regular ? 1100 : 700, groupedBackground: true)
            // The large title is rendered in-content (dayTitleButton) so
            // one tap opens the month grid directly — the system title
            // menu forced an intermediate "Jump to date…" tap. The bar
            // itself stays (day chevrons, gear); its title is empty.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Nothing lives on the leading edge: the left ~20pt is iOS's
                // back-swipe zone, and a control there (the old previous-day
                // chevron) had its taps intermittently stolen by that gesture
                // — the button highlighted but the action never fired ("takes
                // 3 taps", the user). Today is this stack's root, so back-swipe
                // does nothing here anyway. All controls sit on the trailing
                // edge, which has no such gesture; Settings keeps its top-right
                // corner and the day chevrons pair up just to its left.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await model.goToPreviousDay() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous day")
                    Button {
                        Task { await model.goToNextDay() }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(model.isToday)
                    .accessibilityLabel("Next day")
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .nutrition: DayNutritionView(
                    model: model,
                    dailyBudget: model.isToday ? goals.first.flatMap { plan(for: $0) }?.dailyBudget : nil
                )
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
                                date: DayBounds.logTimestamp(for: model.selectedDate),
                                quantity: quantity * target.baseQuantity
                            )
                        }
                    }
                    .presentationDetents([.medium, .large])
                case .editEntry(let entry):
                    // Rescale a logged entry ON ITS PER-PORTION BASIS:
                    // the sheet opens at the stored portion count (3 hot
                    // dogs edit as Serving 3, not as one triple-sized
                    // serving); confirming replaces the entry (chosen
                    // slot, and now a movable date/time), Undo restores
                    // it. "as logged" only fits single-portion entries —
                    // for the rest the row hides and the Will-log
                    // preview carries the per-portion math.
                    PortionSheet(target: PortionTarget(
                        name: entry.name, kcal: entry.kcal / entry.quantity,
                        sodiumMg: entry.sodiumMg / entry.quantity,
                        nutrients: entry.nutrients.scaled(by: 1 / entry.quantity),
                        serving: entry.quantity == 1 ? "as logged" : "",
                        defaultCategory: entry.category
                    ), editDate: entry.date, initialQuantity: entry.quantity) { quantity, category, date in
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
            // Day-paging is the nav-bar chevrons, by design (the user,
            // 2026-07-16: more discoverable, no false movement). The old
            // left/right SWIPE (a .simultaneousGesture DragGesture over
            // the whole scroll) engaged during vertical scrolls too and
            // perturbed the scroll phase the iOS 26 tab bar reads —
            // stranding the bar minimized after a gesture-less section
            // expand/collapse (confirmed on device by removing it).
            // Don't reintroduce a scroll-spanning swipe here.
            }
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
            let kind = quickActions.quickLogRequest
            quickActions.quickLogRequest = nil
            // Pop any pushed Day Nutrition first: the sheet must open
            // over Today's root, not over a stale detail push.
            navPath.removeAll()
            Task {
                // A paired log request (the widget's + deep link) waits
                // for the browse: the sheet's logDate must be the
                // requested day's, not the day the view was already on.
                await model.select(day: day)
                if let kind { activeSheet = .quickLog(kind) }
            }
            return
        }
        guard let kind = quickActions.quickLogRequest else { return }
        quickActions.quickLogRequest = nil
        navPath.removeAll()
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
                // A calendar glyph, not a chevron: it SAYS what the tap
                // opens (the month grid) instead of just "something
                // drops down" (the user).
                Image(systemName: "calendar")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.nori)
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

    /// What the big number shows, and its budget — the two inputs the
    /// shared readout needs. `dailyBudgetKcal` is nil without a usable
    /// goal, which collapses the tap cycle to balance ↔ eaten.
    private var headlineMode: HeadlineMode { HeadlineMode(rawValue: balanceStyle) ?? .remaining }

    private var dailyBudgetKcal: Double? {
        goals.first.flatMap { plan(for: $0) }?.dailyBudget
    }

    /// Progress-gauges mode: the headline wears a ring showing how much
    /// of the day's calorie budget is eaten (needs a plan; without one
    /// the plain headline renders). The ring is mode-independent — it
    /// tracks budget eaten no matter which number the tap is showing.
    @ViewBuilder
    private var gaugedHeadline: some View {
        if let budget = dailyBudgetKcal, budget > 0 {
            let eaten = min(1, max(0, model.summary.intakeKcal / budget))
            let over = model.summary.intakeKcal > budget
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
                // The circles carry no accessibility of their own, so the
                // tappable headline button below stays reachable and
                // actionable inside the ring.
                balanceHeadline
                    .padding(24)
            }
            .frame(width: min(ringDiameter, 260), height: min(ringDiameter, 260))
        } else {
            balanceHeadline
        }
    }

    /// Everything above the log in the phone column: headline (ringed
    /// or plain, with compact flanks), hydration, goal card, meters.
    @ViewBuilder
    private var summaryStack: some View {
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
                // The shared "Details ›" caption — 2.1 restored
                // the trailing chevron here to match the month
                // and day cards (the 2026-07-13 removal reversed
                // deliberately).
                DetailsCaption()
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
    }

    /// Scroll anchors for the Log master toggle. Both are the non-lazy
    /// tops of their stacks, so they always exist and scrollTo can't
    /// miss (a lazy target below the fold wouldn't be in the tree yet).
    private enum ScrollTarget: Hashable {
        case dayTop, logHeader
    }

    /// The log and its trouble states — the second pane on regular width.
    @ViewBuilder
    private func logStack(_ proxy: ScrollViewProxy) -> some View {
        loggedSection(proxy)

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

    /// The big number, tappable to cycle what it shows (kcal left →
    /// balance → eaten → budget, skipping the two that need a goal when
    /// none is set). A plain Button, so it yields to the scroll pan and
    /// never false-fires mid-fling — unlike a raw gesture. The choice
    /// persists on `balanceStyle` and drives the watch and widgets too.
    private var balanceHeadline: some View {
        let readout = CalorieBudget.headlineReadout(
            mode: headlineMode, summary: model.summary, dailyBudgetKcal: dailyBudgetKcal
        )
        let valueFormat: FloatingPointFormatStyle<Double> = readout.signed
            ? .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))
            : .number.precision(.fractionLength(0))
        return Button {
            balanceStyle = headlineMode.next(hasBudget: dailyBudgetKcal != nil).rawValue
        } label: {
            VStack(spacing: 4) {
                Text(readout.value, format: valueFormat)
                    .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(readout.tint)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    if differentiateWithoutColor, let symbol = readout.statusSymbol {
                        Image(systemName: symbol)
                            .font(.caption)
                            .foregroundStyle(readout.tint)
                            .accessibilityHidden(true)
                    }
                    Text(readout.caption)
                        .font(.subheadline)
                        // Scale down inside the ring at accessibility sizes,
                        // like the number above — truncated to "kcal bala…".
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Read number + caption as one element, carrying the near/over
        // budget (or deficit/surplus) status the tint alone can't.
        .accessibilityLabel("\(readout.value.formatted(valueFormat)) \(readout.caption)")
        .accessibilityValue(readout.statusLabel ?? "")
        .accessibilityHint("Changes what this number shows")
    }

    @ViewBuilder
    private var goalCard: some View {
        // The whole card is a door to the Goal tab — a plain Button, so it
        // scrolls without false-firing. The no-goal copy already points at
        // the Goal tab, so it opens it too.
        Button {
            QuickActions.shared.goalRequest = true
        } label: {
            if let goal = goals.first, let plan = plan(for: goal) {
                DailyGoalCard(
                    bankedKcal: max(0, -model.summary.balanceKcal),
                    deficitKcal: -model.summary.balanceKcal,
                    intakeKcal: model.summary.intakeKcal,
                    plan: plan,
                    isMaintenanceMode: goal.isMaintenance,
                    showsRemaining: model.isToday,
                    weeklyTrendLb: model.weeklyTrendLb
                )
                .equatable()
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
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityHint("Opens the Goal screen")
    }

    private func plan(for goal: GoalSettings) -> CalorieBudget.Plan? {
        // The shared kit derivation — one clamp, one days-to-target rule
        // for Today, Goal, onboarding, the widgets, and the watch.
        CalorieBudget.derivePlan(
            isMaintenance: goal.isMaintenance,
            currentWeightLb: model.currentWeightLb ?? goal.fallbackCurrentWeightLb,
            targetWeightLb: goal.targetWeightLb,
            targetDate: goal.targetDate,
            averageDailyBurnKcal: model.averageBurnKcal,
            // Day-ratcheted: Health revising burn down (watch↔phone
            // sample reconciliation) must not move the budget against
            // the user mid-day. Display totals stay raw.
            todayActualBurnKcal: TodayBurnFloor.ratcheted(model.summary.totalBurnKcal)
        )
    }

    /// Push to the day's full nutrient breakdown (value-routed so the
    /// path binding tracks it — see `Route`).
    private func nutritionLink(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationLink(value: Route.nutrition) {
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
        // One VoiceOver stop ("1,505, Burned"), not two — the
        // CalendarView.slotMetric grouping discipline.
        .accessibilityElement(children: .combine)
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
                // Color-only ON SCREEN by ruling (the user vetoed a
                // visible "· near limit" tail — the traffic light IS the
                // status); VoiceOver still hears it via the value, and
                // Differentiate Without Color gets the glyph twin.
                HStack(spacing: 4) {
                    // Status color/gauge judge canonical totals; only
                    // the readout converts (sodium → salt g).
                    Text("\(nutrient.displayValue(total, water: waterUnit, sodium: sodiumUnit), format: .number.precision(.fractionLength(nutrient.displayFractionDigits(sodium: sodiumUnit)))) \(nutrient.displayUnitSymbol(water: waterUnit, sodium: sodiumUnit)) \(metricName(nutrient))")
                        .foregroundStyle(Color.sodiumStatus(mg: total, limitMg: target))
                        .fontWeight(.medium)
                        .accessibilityValue(Color.sodiumStatusLabel(mg: total, limitMg: target) ?? "")
                    if differentiateWithoutColor,
                       let symbol = Color.sodiumStatusSymbol(mg: total, limitMg: target) {
                        Image(systemName: symbol)
                            .font(.caption)
                            .foregroundStyle(Color.sodiumStatus(mg: total, limitMg: target))
                            .accessibilityHidden(true)
                    }
                }
            case .goal:
                let digits = nutrient.displayFractionDigits(sodium: sodiumUnit)
                Text("\(nutrient.displayValue(total, water: waterUnit, sodium: sodiumUnit), format: .number.precision(.fractionLength(digits))) / \(nutrient.displayValue(target, water: waterUnit, sodium: sodiumUnit), format: .number.precision(.fractionLength(digits))) \(nutrient.displayUnitSymbol(water: waterUnit, sodium: sodiumUnit)) \(metricName(nutrient))")
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
        nutrient.displayInlineName(sodium: sodiumUnit)
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

    private func loggedSection(_ proxy: ScrollViewProxy) -> some View {
        // A plain VStack ON PURPOSE (was Lazy): during the master-toggle
        // glide, lazily-created rows materialized mid-scroll at full size
        // with no animation — visible "pop-in" on bigger days (the user).
        // Non-lazy, every row exists before the scroll passes over it and
        // the whole unfold animates. Scroll perf is carried by the
        // per-section Equatable views below, not by laziness.
        VStack(alignment: .leading, spacing: 10) {
            // ALL logging lives behind the corner + pill now — water is
            // the sheet's pinned top row (Micheal's final water home;
            // widget/watch/app icon keep the 1-tap paths).
            HStack {
                // The title is the master toggle: any group open →
                // collapse everything; all closed → open everything
                // (categories and water alike).
                Button {
                    let anyExpanded = collapsedSections.count < FoodCategory.allCases.count
                        || !waterCollapsed
                    // .smooth, not the log's usual .snappy: this toggle
                    // pairs with a viewport glide below, and spring
                    // bounce on either half reads as stutter ("a little
                    // jerky", the user — device-tested).
                    withAnimation(reduceMotion ? nil : .smooth) {
                        if anyExpanded {
                            collapsedSections = Set(FoodCategory.allCases)
                            waterCollapsed = true
                        } else {
                            collapsedSections = []
                            waterCollapsed = false
                        }
                    }
                    // Follow the toggle with the viewport (the user:
                    // expanding used to leave the log below the fold,
                    // collapsing left the screen scrolled past it):
                    // expand pins the log to the top, collapse returns
                    // to the day headline. Compact only — on regular
                    // width the log pane already sits beside the summary.
                    // The ~100 ms wait is load-bearing AND tuned: scrollTo
                    // in the same turn resolves before the render commit
                    // and clamps against the pre-toggle content height
                    // (lands nowhere, sim-verified twice) — but layout
                    // COMMITS on the next frame even while the animation
                    // plays, so just past the commit the target is exact
                    // and the glide overlaps the still-running expansion:
                    // one continuous motion, not expand-stop-scroll (350 ms
                    // felt like two beats on device).
                    if hSizeClass != .regular {
                        Task {
                            try? await Task.sleep(for: .milliseconds(100))
                            withAnimation(reduceMotion ? nil : .smooth) {
                                proxy.scrollTo(
                                    anyExpanded ? ScrollTarget.dayTop : ScrollTarget.logHeader,
                                    anchor: .top
                                )
                            }
                        }
                    }
                } label: {
                    Text("Log")
                        .font(.sectionHeader)
                        // Nori: the structural accent (see Color.nori).
                        .foregroundStyle(Color.nori)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log. Collapses or expands every group")
                Spacer()
            }
            .padding(.horizontal)
            .id(ScrollTarget.logHeader)

            if model.foodLog.isEmpty {
                Text(model.isToday ? "Nothing logged yet." : "Nothing was logged this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            // Each meal group is its own Equatable view: toggling ONE
            // group — or a refresh that didn't touch this slot — leaves
            // the others' inputs unchanged, so SwiftUI skips their bodies
            // instead of rebuilding every row on screen (the scroll-perf
            // pass: a single chevron tap used to rebuild the whole log).
            ForEach(FoodCategory.allCases) { category in
                let entries = model.foodByCategory[category] ?? []
                if !entries.isEmpty {
                    MealSectionView(
                        category: category,
                        entries: entries,
                        isCollapsed: collapsedSections.contains(category),
                        entryMetric: entryMetric,
                        swipe: rowSwipe,
                        onToggle: {
                            withAnimation(reduceMotion ? nil : .snappy) {
                                if collapsedSections.contains(category) {
                                    collapsedSections.remove(category)
                                } else {
                                    collapsedSections.insert(category)
                                }
                            }
                        },
                        onEdit: { entry in activeSheet = .editEntry(entry) }
                    )
                    .equatable()
                }
            }

            if !model.waterLog.isEmpty {
                WaterSectionView(
                    entries: model.waterLog,
                    totalOz: model.summary.waterOz,
                    isCollapsed: waterCollapsed,
                    waterIcon: waterIcon,
                    swipe: rowSwipe,
                    onToggle: { withAnimation(reduceMotion ? nil : .snappy) { waterCollapsed.toggle() } },
                    onEdit: { entry in activeSheet = .editWater(entry) }
                )
                .equatable()
            }
        }
        // Full width regardless of content, so the header stays left-pinned
        // even when the day has no entries.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// Shared "is a row mid-swipe?" flag for the day-paging gesture. An
/// @Observable box, not a @State the body reads: rows WRITE it during a
/// drag, but the only READ is the day-paging gesture's onEnded (which runs
/// at gesture end, outside body evaluation), so writes never invalidate
/// TodayView. The old shared @State turned every swipe into a full-body
/// re-render.
@MainActor @Observable final class RowSwipeState {
    var active = false
}

/// One meal-slot group: a tappable header with the slot's total that
/// collapses its entries. Equatable on its data so a sibling group's
/// toggle (or an unrelated refresh) skips this whole subtree.
private struct MealSectionView: View, Equatable {
    let category: FoodCategory
    let entries: [FoodLogEntry]
    let isCollapsed: Bool
    let entryMetric: TrackedNutrient
    let swipe: RowSwipeState
    let onToggle: () -> Void
    let onEdit: (FoodLogEntry) -> Void

    /// Closures are excluded on purpose — they're recreated every parent
    /// render but capture only stable @State storage, so ignoring them is
    /// what lets an unchanged group skip its body.
    static func == (lhs: MealSectionView, rhs: MealSectionView) -> Bool {
        lhs.category == rhs.category
            && lhs.isCollapsed == rhs.isCollapsed
            && lhs.entryMetric == rhs.entryMetric
            && lhs.entries == rhs.entries
    }

    private var total: Double { entries.reduce(0) { $0 + $1.kcal } }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.nori)
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
                FoodLogRow(entry: entry, entryMetric: entryMetric, swipe: swipe, onEdit: onEdit)
                    .equatable()
            }
        }
    }
}

/// The day's water servings, folded into the log like a meal slot.
private struct WaterSectionView: View, Equatable {
    let entries: [WaterLogEntry]
    let totalOz: Double
    let isCollapsed: Bool
    let waterIcon: String
    let swipe: RowSwipeState
    let onToggle: () -> Void
    let onEdit: (WaterLogEntry) -> Void
    // Uncompared in == (the rewardIcon pattern): its own observation
    // re-renders the section when the unit changes.
    @AppStorage(SharedStore.waterUnitKey, store: SharedStore.defaults) private var waterUnitRaw = SharedStore.unitAutomatic
    private var waterUnit: WaterUnit { WaterUnit.resolve(waterUnitRaw) }

    static func == (lhs: WaterSectionView, rhs: WaterSectionView) -> Bool {
        lhs.isCollapsed == rhs.isCollapsed
            && lhs.totalOz == rhs.totalOz
            && lhs.waterIcon == rhs.waterIcon
            && lhs.entries == rhs.entries
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.nori)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text("Water")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(waterUnit.text(fromOz: totalOz))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityLabel("Water, \(waterUnit.value(fromOz: totalOz)) \(waterUnit.spoken(waterUnit.fromOz(totalOz))), \(isCollapsed ? "collapsed" : "expanded")")

        if !isCollapsed {
            ForEach(entries) { entry in
                WaterLogRow(entry: entry, waterIcon: waterIcon, swipe: swipe, onEdit: onEdit)
                    .equatable()
            }
        }
    }
}

/// One logged food: editable rows carry the swipe/tap affordances;
/// another app's entry is counted (reads span all sources by design) but
/// not ours to edit or delete. Its own Equatable view so a whole-screen
/// re-render doesn't rebuild it unless THIS entry (or the caption metric)
/// changed.
private struct FoodLogRow: View, Equatable {
    let entry: FoodLogEntry
    let entryMetric: TrackedNutrient
    let swipe: RowSwipeState
    let onEdit: (FoodLogEntry) -> Void
    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults) private var sodiumUnitRaw = SharedStore.unitAutomatic

    static func == (lhs: FoodLogRow, rhs: FoodLogRow) -> Bool {
        lhs.entry == rhs.entry && lhs.entryMetric == rhs.entryMetric
    }

    var body: some View {
        let label = HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.name)
                    if entry.aiGenerated {
                        Text(verbatim: "✨")
                            .font(.caption2)
                            .accessibilityLabel("AI estimated")
                    }
                }
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.kcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
                Text(entryMetric.captionText(
                    entryMetric.itemAmount(sodiumMg: entry.sodiumMg, nutrients: entry.nutrients) ?? 0,
                    sodium: SodiumUnit.resolve(sodiumUnitRaw)
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        if entry.editable {
            label
                .logRowSwipeActions(
                    swipe: swipe,
                    itemName: entry.name,
                    onTap: { onEdit(entry) },
                    onEdit: { onEdit(entry) }
                ) {
                    Task { await LogActions.deleteFoodEntry(entry) }
                }
                // One element with a role — name/time/kcal/sodium
                // fragments left VoiceOver with four stops and an
                // invisible tap-to-edit.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Edits this entry")
                .accessibilityAction(named: "Edit") { onEdit(entry) }
                .accessibilityAction(named: "Delete") {
                    Task { await LogActions.deleteFoodEntry(entry) }
                }
                .padding(.horizontal)
        } else {
            label
                .accessibilityElement(children: .combine)
                .accessibilityHint("Logged by another app")
                .padding(.horizontal)
        }
    }
}

/// One water serving: editable rows carry the swipe/tap affordances;
/// another app's sample counts toward the day (reads span all sources by
/// design) but HealthKit refuses our deletes — no affordances that can
/// only end in an error.
private struct WaterLogRow: View, Equatable {
    let entry: WaterLogEntry
    let waterIcon: String
    let swipe: RowSwipeState
    let onEdit: (WaterLogEntry) -> Void
    @AppStorage(SharedStore.waterUnitKey, store: SharedStore.defaults) private var waterUnitRaw = SharedStore.unitAutomatic
    private var waterUnit: WaterUnit { WaterUnit.resolve(waterUnitRaw) }

    static func == (lhs: WaterLogRow, rhs: WaterLogRow) -> Bool {
        lhs.entry == rhs.entry && lhs.waterIcon == rhs.waterIcon
    }

    var body: some View {
        let label = HStack(alignment: .firstTextBaseline) {
            WaterIconView(raw: waterIcon)
            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(waterUnit.text(fromOz: entry.oz))
                .monospacedDigit()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        if entry.editable {
            let amount = waterUnit.value(fromOz: entry.oz)
            label
                .logRowSwipeActions(
                    swipe: swipe,
                    itemName: "\(amount) \(waterUnit.spoken(waterUnit.fromOz(entry.oz))) entry",
                    onTap: { onEdit(entry) },
                    onEdit: { onEdit(entry) }
                ) {
                    Task { await LogActions.deleteWaterEntry(entry) }
                }
                // One element with a role — separate time/amount fragments
                // left VoiceOver with four stops and an invisible
                // tap-to-edit.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Edits this entry")
                .accessibilityAction(named: "Edit") { onEdit(entry) }
                .accessibilityAction(named: "Delete") {
                    Task { await LogActions.deleteWaterEntry(entry) }
                }
                .padding(.horizontal)
        } else {
            label
                .accessibilityElement(children: .combine)
                .accessibilityHint("Logged by another app")
                .padding(.horizontal)
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
        swipe: RowSwipeState,
        itemName: String,
        onTap: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(LogRowSwipeActions(
            swipe: swipe, itemName: itemName,
            onTap: onTap, onEdit: onEdit, onDelete: onDelete
        ))
    }
}

/// Swipe actions for log rows, matching the library lists: swipe right
/// (leading) to edit, swipe left (trailing) to delete, full swipes commit
/// the action outright. Today's log lives in a ScrollView (collapsible
/// custom sections), so there are no native swipeActions — this drags the
/// row over button reveals instead, and reports drag activity through the
/// swipe coordinator so the day-paging swipe stands down.
private struct LogRowSwipeActions: ViewModifier {
    /// Written (never read) here — see RowSwipeState: keeping the read out
    /// of any rendered body is what stops a swipe from re-rendering Today.
    let swipe: RowSwipeState
    let itemName: String
    /// Tap on a closed row (an open row's tap just settles it shut) —
    /// free discoverability for the edit hidden behind the swipe.
    var onTap: (() -> Void)?
    var onEdit: (() -> Void)?
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    /// Where the row currently rests: 0, or ±revealWidth when open.
    @State private var restOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Floating circular buttons, like the system's iOS 26 swipe pills.
    private static let buttonSize: CGFloat = 44
    private static let revealWidth: CGFloat = 60
    private static let fullSwipe: CGFloat = 220

    /// Static friction so the row doesn't slide on a light graze: it stays
    /// put until the finger passes the breakaway, then tracks from there.
    /// The row tracked 1:1 from the first pixel, so a slight sideways drag
    /// already peeled it open toward delete (the user). Applied to BOTH the
    /// visible offset and the reveal/commit decisions, so the extra travel
    /// is real resistance, not just cosmetic lag.
    private static let breakaway: CGFloat = 22
    private static func resist(_ translation: CGFloat) -> CGFloat {
        let mag = abs(translation)
        guard mag > breakaway else { return 0 }
        return (mag - breakaway) * (translation < 0 ? -1 : 1)
    }

    /// How far past the reveal the row keeps stretching, asymptotically —
    /// the visible offset approaches revealWidth + this and never hard-caps,
    /// so the row follows the finger the whole way to the commit instead of
    /// freezing partway (a hard cap read as "stiff/abrupt"; native
    /// .swipeActions keeps stretching).
    private static let stretchLimit: CGFloat = 90

    /// Rubber-band the row past the reveal so it doesn't slide 1:1 with the
    /// finger — native .swipeActions resists once the button is exposed.
    /// Elastic, asymptotic: the drag grows the further you pull, easing
    /// toward revealWidth + stretchLimit with no hard stop. The reveal/
    /// full-swipe DECISIONS stay on true finger travel (see onEnded); only
    /// the visible offset is damped.
    private static func rubberBand(_ raw: CGFloat) -> CGFloat {
        guard abs(raw) > revealWidth else { return raw }
        let sign: CGFloat = raw < 0 ? -1 : 1
        let extra = abs(raw) - revealWidth
        let damped = revealWidth + extra / (1 + extra / stretchLimit)
        return sign * damped
    }

    /// Native-style zoom: the pill scales up from small as it's revealed
    /// (and back down on close, since the settle animates `offset`), instead
    /// of just popping in via opacity (the user, 2026-07-15). `revealed` is
    /// the current reveal distance for this side (always ≥ 0).
    private static func revealScale(_ revealed: CGFloat) -> CGFloat {
        0.4 + 0.6 * min(1, max(0, revealed / revealWidth))
    }

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
                            .scaleEffect(Self.revealScale(offset))
                            .accessibilityLabel("Edit \(itemName)")
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 8)
                        .opacity(min(1, offset / 30))
                    }
                    if offset < 0 {
                        HStack {
                            Spacer(minLength: 0)
                            actionButton("trash.fill", tint: .red) {
                                settle(0)
                                onDelete()
                            }
                            .scaleEffect(Self.revealScale(-offset))
                            .accessibilityLabel("Delete \(itemName)")
                        }
                        .padding(.trailing, 8)
                        .opacity(min(1, -offset / 30))
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
            // The swipe is a UIKit pan recognizer bridged in
            // (HorizontalSwipeGesture), NOT a SwiftUI DragGesture, because it
            // MUST be able to hand a vertical drag back to the enclosing
            // ScrollView. A SwiftUI .gesture is mutually exclusive with the
            // scroll's pan; a .simultaneousGesture co-receives but still
            // can't yield — either way a DragGesture captures the touch at
            // its minimumDistance and holds it, so a vertical scroll that
            // STARTS on a row was intermittently dead (the row ate the pan;
            // biasing the axis only changed what we did after capture, not
            // whether we captured). The bridged recognizer instead FAILS
            // itself the instant a drag reads more vertical than horizontal,
            // so the scroll gets a clean pan; only a decisively horizontal
            // drag begins the swipe.
            .gesture(HorizontalSwipeGesture(
                onChanged: { translationX in
                    // UIKit translation is 0 at .began, so the row tracks
                    // straight from its rest offset (no catch-up pop) — minus
                    // the breakaway, which holds it still until the swipe is
                    // deliberate.
                    var raw = restOffset + Self.resist(translationX)
                    if onEdit == nil { raw = min(0, raw) }
                    offset = Self.rubberBand(raw)
                    if abs(offset) > 10 { swipe.active = true }
                },
                onEnded: { translationX in
                    // Decide on the SAME resisted travel the row showed, so
                    // reveal/commit line up with what the finger did: with the
                    // breakaway, reveal needs ~breakaway+36pt and a full-swipe
                    // delete needs a clearly deliberate long drag (rubber-
                    // banding still only damps the visible offset, not this).
                    var raw = restOffset + Self.resist(translationX)
                    if onEdit == nil { raw = min(0, raw) }
                    if raw < -Self.fullSwipe {
                        settle(0)
                        onDelete()
                    } else if raw > Self.fullSwipe, let onEdit {
                        settle(0)
                        onEdit()
                    } else if raw < -Self.revealWidth * 0.6 {
                        settle(-Self.revealWidth)
                    } else if raw > Self.revealWidth * 0.6, onEdit != nil {
                        settle(Self.revealWidth)
                    } else {
                        settle(0)
                    }
                    swipe.active = false
                }
            ))
    }

    private func actionButton(
        _ symbol: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .modifier(SwipePillChrome(tint: tint))
        }
        .buttonStyle(.plain)
    }

    /// Real Liquid Glass on iOS 26 — these buttons were IMITATING the
    /// system's swipe pills with a solid fill. Only one or two are ever
    /// visible mid-swipe, so the no-glass-in-list-rows perf rule
    /// (LogButton's lesson) doesn't apply. Solid fill below 26.
    private struct SwipePillChrome: ViewModifier {
        let tint: Color

        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(tint).interactive(), in: .circle)
            } else {
                content.background(tint, in: .circle)
            }
        }
    }

    private func settle(_ value: CGFloat) {
        // A gentle spring, not a fixed-duration ease: the row settles with
        // the same bit of life as the native .swipeActions release (barely
        // damped, no visible bounce). Only the swipe uses this — section-
        // collapse animations keep .snappy.
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { offset = value }
        restOffset = value
    }
}

/// A horizontal-only pan bridged from UIKit so it can YIELD a vertical drag
/// to the enclosing ScrollView — the one thing a SwiftUI DragGesture can't
/// do (it captures the touch at its minimumDistance and never hands it back,
/// which left vertical scrolls that began on a log row intermittently dead).
/// The recognizer fails itself the moment a drag reads more vertical than
/// horizontal (see HorizontalPanGestureRecognizer), so the scroll claims the
/// pan cleanly; a clearly horizontal drag begins the row swipe and, because
/// the delegate allows simultaneous recognition, is never pre-empted by the
/// scroll's own pan.
private struct HorizontalSwipeGesture: UIGestureRecognizerRepresentable {
    /// Horizontal translation (SwiftUI-space) as the drag moves.
    let onChanged: (CGFloat) -> Void
    /// Final horizontal translation when the drag ends, cancels, or fails.
    let onEnded: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> HorizontalPanGestureRecognizer {
        let recognizer = HorizontalPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: HorizontalPanGestureRecognizer, context: Context
    ) {
        // localTranslation is in the attached view's SwiftUI space, so it
        // stays stable as we move the row via .offset — reading
        // translation(in: view) here would feed the offset back into itself.
        let translationX = context.converter.localTranslation?.x ?? 0
        switch recognizer.state {
        case .began, .changed:
            onChanged(translationX)
        case .ended, .cancelled, .failed:
            onEnded(translationX)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // Recognize alongside the scroll's pan (and the row's tap): the
        // recognizer's own vertical-fail is what keeps vertical drags with
        // the scroll, so simultaneous recognition only ensures a horizontal
        // swipe isn't blocked by the scroll winning arbitration first.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// A pan that bows out of any drag it reads as vertical: past a small dead
/// zone, if the touch has travelled further vertically than horizontally it
/// fails, so the enclosing ScrollView claims the pan. A clearly horizontal
/// drag is left to begin as a normal pan (the row swipe). The dead zone
/// keeps first-pixel jitter from deciding the axis.
private final class HorizontalPanGestureRecognizer: UIPanGestureRecognizer {
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible else { return }
        let t = translation(in: view)
        let dx = abs(t.x), dy = abs(t.y)
        guard dx + dy > 8 else { return }
        // Claim the swipe only when the drag is DECISIVELY horizontal — dx
        // must lead dy by a clear margin. The first cut failed only when
        // dy > dx, so anything within 45° of horizontal tripped the swipe;
        // a scroll or slightly-slanted drag could trip swipe-to-delete
        // (accidental-delete risk). Requiring dx > dy·1.5 (≈ within 34° of
        // horizontal) hands ambiguous / near-diagonal drags to the
        // ScrollView instead. Tunable — raise the factor if still too eager.
        if dx < dy * 1.5 {
            state = .failed
        }
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
    @AppStorage(SharedStore.waterUnitKey, store: SharedStore.defaults) private var waterUnitRaw = SharedStore.unitAutomatic
    private var unit: WaterUnit { WaterUnit.resolve(waterUnitRaw) }

    init(entry: WaterLogEntry) {
        self.entry = entry
        _oz = State(initialValue: entry.oz)
        _date = State(initialValue: entry.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // State stays oz (1–128); mL mode steps ±50 on a
                    // snapped readout and the field edits whole mL.
                    Stepper {
                        LabeledContent("Amount (\(unit.symbol))") {
                            TextField("0", value: Binding(
                                get: {
                                    unit == .fluidOunces ? oz : unit.fromOz(oz).rounded()
                                },
                                set: { oz = min(max(unit.toOz($0), 1), 128) }
                            ), format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                                .focused($amountFocused)
                        }
                        .padding(.trailing, 8)
                    } onIncrement: {
                        if unit == .fluidOunces {
                            oz = min(128, oz + 4)
                        } else {
                            let ml = (unit.fromOz(oz) / 50).rounded() * 50
                            oz = min(128, unit.toOz(ml + 50))
                        }
                    } onDecrement: {
                        if unit == .fluidOunces {
                            oz = max(1, oz - 4)
                        } else {
                            let ml = (unit.fromOz(oz) / 50).rounded() * 50
                            oz = max(1, unit.toOz(ml - 50))
                        }
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

struct DailyGoalCard: View, Equatable {
    let bankedKcal: Double
    /// Signed day deficit (negative = surplus) — the band judgment
    /// needs the sign that the display-clamped `bankedKcal` drops.
    let deficitKcal: Double
    let intakeKcal: Double
    let plan: CalorieBudget.Plan
    /// The goal's ACTUAL mode — `isMaintenance` below is a zero-deficit
    /// presentation heuristic that a met lose goal also trips, and the
    /// two judge past days differently (band vs any-deficit).
    let isMaintenanceMode: Bool
    var showsRemaining = true
    /// Actual scale movement over the past week (negative = down);
    /// nil when Health has too few weigh-ins to say.
    var weeklyTrendLb: Double? = nil
    @AppStorage(SharedStore.rewardIconKey, store: SharedStore.defaults) private var rewardIcon = "onigiri"
    // Display-only (like the reward icon, uncompared in ==): its own
    // observation re-renders the scale line when the unit changes.
    @AppStorage(SharedStore.weightUnitKey, store: SharedStore.defaults) private var weightUnitRaw = SharedStore.unitAutomatic
    /// The gauge badge scales with its frame, so the frame must follow
    /// Dynamic Type or the badge stays frozen beside growing text.
    /// (Not compared in ==: ScaledMetric is a DynamicProperty — its
    /// changes re-render the card on their own.)
    @ScaledMetric(relativeTo: .headline) private var gaugeSize = 84.0

    /// Skip the whole card — including the OnigiriGauge's GeometryReader —
    /// when a re-render didn't touch its numbers (scroll-settle, an
    /// unrelated Settings change, the incidental evals around a log). The
    /// @AppStorage reward icon isn't compared: its own observation still
    /// updates the card independently of this equality.
    static func == (lhs: DailyGoalCard, rhs: DailyGoalCard) -> Bool {
        lhs.bankedKcal == rhs.bankedKcal
            && lhs.deficitKcal == rhs.deficitKcal
            && lhs.intakeKcal == rhs.intakeKcal
            && lhs.plan == rhs.plan
            && lhs.isMaintenanceMode == rhs.isMaintenanceMode
            && lhs.showsRemaining == rhs.showsRemaining
            && lhs.weeklyTrendLb == rhs.weeklyTrendLb
    }

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

    /// The past-day earned look, matching StreakCalendar's judgment:
    /// maintenance runs the band rule on the signed deficit; a met lose
    /// goal (deficit target 0, snapshot 0) stays any-deficit; a live
    /// lose goal wants the full target banked.
    private var dayEarnedLook: Bool {
        if isMaintenanceMode { return abs(deficitKcal) <= StreakCalendar.maintenanceBandKcal }
        if plan.requiredDailyDeficit <= 0 { return deficitKcal > 0 }
        return progress >= 1
    }

    var body: some View {
        HStack(spacing: 16) {
            OnigiriGauge(progress: progress, emoji: SharedStore.rewardEmoji(for: rewardIcon))
                .frame(width: min(gaugeSize, 120), height: min(gaugeSize, 120))

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
                } else if dayEarnedLook {
                    Text("\(SharedStore.rewardEmoji(for: rewardIcon)) earned")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    // An untracked day isn't a failed day.
                    Text(intakeKcal == 0
                         ? "nothing logged"
                         : (isMaintenanceMode ? "off budget" : "goal not met"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let trend = weeklyTrendLb {
                    let unit = WeightUnit.resolve(weightUnitRaw)
                    Label {
                        Text("Scale: \(trend < 0 ? "down" : "up") \(unit.fromLb(abs(trend)), format: .number.precision(.fractionLength(1))) \(unit.symbol) this week")
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        // One VoiceOver stop per card ("350, Intake"), not icon/number/
        // caption as three — the CalendarView.slotMetric grouping
        // discipline.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
