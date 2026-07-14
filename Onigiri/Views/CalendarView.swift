import SwiftUI
import SwiftData
import OnigiriKit

/// Gamification: a month grid where every day that met the deficit goal
/// earned an onigiri, with the current streak at the bottom.
struct CalendarView: View {
    @State private var model = CalendarModel()
    @State private var displayedMonth = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @Query private var goals: [GoalSettings]
    @Environment(\.scenePhase) private var scenePhase
    // AppStorage (not static SharedStore reads) so icon changes re-render
    // this screen immediately.
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.rewardIconKey, store: SharedStore.defaults) private var rewardIcon = "onigiri"
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric1IconKey, store: SharedStore.defaults) private var trackedMetric1Icon = ""
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"
    @AppStorage(SharedStore.trackedMetric2IconKey, store: SharedStore.defaults) private var trackedMetric2Icon = ""

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Layout.screenSpacing) {
                    // Stats first — they were below the fold at the bottom.
                    summaryCard
                    // Region-scoped swipes: the grid pages months, the day
                    // area pages days. Chevrons stay as the visible,
                    // accessible affordance for both.
                    MonthGridView(
                        month: displayedMonth,
                        earned: model.earned,
                        tracked: model.trackedDaySet,
                        selectedDay: selectedDay,
                        onSelect: { selectedDay = $0 }
                    )
                    .simultaneousGesture(horizontalSwipe { shiftMonth($0) })
                    // The legend the grid never had: three marks, three
                    // stories.
                    Text("\(SharedStore.rewardEmoji(for: rewardIcon)) goal met  ·  ○ tracked, goal missed  ·  blank: not tracked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    VStack(spacing: Layout.screenSpacing) {
                        dayHeader
                        daySummaryCard
                    }
                    .simultaneousGesture(horizontalSwipe { shiftDay($0) })
                    if model.targetDeficitKcal == nil {
                        Text("No goal set — any deficit earns a badge. Set a goal to raise the bar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.horizontal)
            }
            // Grouped surface idiom, app-wide (see TodayView).
            .readableContentWidth(groupedBackground: true)
            .expandsTabBarAtTop()
            // Month chevrons in the nav bar with the month as the title —
            // the same browsing pattern as Today.
            .navigationTitle(displayedMonth.formatted(.dateTime.month(.wide).year()))
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
            }
        }
        .task { await refresh() }
        .refreshable { await refresh(forceWeights: true) }
        // Months beyond the preloaded window load on demand — otherwise
        // they render every day as "goal not met" with a "—" day card.
        .task(id: displayedMonth) {
            await model.ensureTotals(forMonthOf: displayedMonth)
        }
        .onChange(of: selectedDay) { _, day in
            Task { await model.loadDaySummary(for: day) }
        }
        // Slot changes in Settings need fresh Health queries here too.
        .onChange(of: trackedMetric1) { _, _ in
            Task { await model.loadDaySummary(for: selectedDay) }
        }
        .onChange(of: trackedMetric2) { _, _ in
            Task { await model.loadDaySummary(for: selectedDay) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Once visited, this view stays alive in the TabView, so this
            // fires on every activation even with another tab frontmost —
            // only refresh when the model says the data went stale.
            if phase == .active,
               model.shouldForegroundRefresh(
                   healthWriteVersion: ToastCenter.shared.healthWriteVersion
               ) {
                Task { await refresh() }
            }
        }
    }

    private func refresh(forceWeights: Bool = false) async {
        let goal = goals.first.map {
            SyncedGoal(
                targetWeightLb: $0.targetWeightLb,
                targetDate: $0.targetDate,
                fallbackCurrentWeightLb: $0.fallbackCurrentWeightLb,
                mode: $0.mode
            )
        }
        await model.refresh(goal: goal, forceWeights: forceWeights)
        await model.loadDaySummary(for: selectedDay)
    }

    // MARK: - Pieces

    // Weekday header, grid, and DayCell live in MonthGridView (shared
    // with Today's day-jump sheet).

    /// Cycle the selected day like the month header cycles months; the
    /// grid follows across month boundaries.
    private var dayHeader: some View {
        HStack {
            Button {
                shiftDay(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
            Spacer()
            // "Today" over the date: while browsing an earlier month the
            // persistent day card read like that month's data at a glance.
            if calendar.isDateInToday(selectedDay) {
                Text("Today")
                    .font(.headline)
            } else {
                Text(selectedDay, format: .dateTime.weekday(.abbreviated).month(.wide).day())
                    .font(.headline)
            }
            Spacer()
            Button {
                shiftDay(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(calendar.isDateInToday(selectedDay))
            .accessibilityLabel("Next day")
        }
    }

    private func shiftDay(_ delta: Int) {
        guard let day = calendar.date(byAdding: .day, value: delta, to: selectedDay) else { return }
        selectedDay = min(calendar.startOfDay(for: day), calendar.startOfDay(for: .now))
        if !calendar.isDate(selectedDay, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = calendar.startOfMonth(for: selectedDay)
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let month = calendar.date(byAdding: .month, value: delta, to: displayedMonth),
              month <= calendar.startOfMonth(for: .now) else { return }
        displayedMonth = month
    }

    /// Left = forward, right = back — same thresholds as Today's day swipe.
    private func horizontalSwipe(_ shift: @escaping (Int) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            if value.translation.width < -60 {
                shift(1)
            } else if value.translation.width > 60 {
                shift(-1)
            }
        }
    }

    private var daySummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Goal status centered in the card; the chevron stays pinned
            // trailing as the tap affordance.
            ZStack {
                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if model.earned.contains(selectedDay) {
                    Text("Goal met \(SharedStore.rewardEmoji(for: rewardIcon))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else if calendar.isDateInToday(selectedDay) {
                    Text("In progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if model.trackedDaySet.contains(selectedDay) {
                    // A blank slot here read as a loading failure.
                    Text("Goal not met")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not tracked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            // Fixed three-column grid, always rendered ("—" when a day has
            // no data): every icon keeps its exact position across day
            // changes, so only the numbers repaint.
            let totals = model.totalsByDay[selectedDay]
            HStack(spacing: 0) {
                metric(icon: { FoodIconView(raw: foodIcon) },
                       text: totals.map { "\($0.intakeKcal.formatted(.number.precision(.fractionLength(0)))) in" } ?? "—")
                metric(icon: { Image(systemName: "flame.fill").foregroundStyle(.red) },
                       text: totals.map { "\($0.burnKcal.formatted(.number.precision(.fractionLength(0)))) out" } ?? "—")
                Text(totals.map(deficitText(for:)) ?? "—")
                    .fontWeight(.semibold)
                    .foregroundStyle((totals?.deficitKcal ?? 0) > 0 ? Color.green : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline)
            .monospacedDigit()

            // The two tracked-metric slots, mirroring Today's row (a None
            // slot drops out; both None drops the line).
            if slotNutrient(1) != nil || slotNutrient(2) != nil {
                HStack(spacing: 0) {
                    if let nutrient = slotNutrient(1) {
                        slotMetric(slot: 1, nutrient: nutrient)
                    }
                    if let nutrient = slotNutrient(2) {
                        slotMetric(slot: 2, nutrient: nutrient)
                    }
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
                .font(.subheadline)
                .monospacedDigit()
            }

            // The day's own snapshotted target when one was recorded
            // (history is judged by it); today's target otherwise. A 0
            // snapshot means the day ran goal-less — no line.
            if let target = model.targetDeficit(for: selectedDay), target > 0 {
                // Same vocabulary as Today's "Daily goal" card.
                Text("Daily goal: \(target, format: .number.precision(.fractionLength(0))) kcal deficit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // The tap is a cross-tab jump — the bare chevron never said
            // so, and the behavior was VoiceOver-hint-only discoverable.
            HStack {
                Spacer()
                Text("View & edit on Today")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .contentShape(.rect)
        // The whole card is the tap target: opens the day's full record
        // (sodium, water, entries, backfill) on Today.
        .onTapGesture {
            QuickActions.shared.dayRequest = selectedDay
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens this day on Today")
        .animation(.snappy, value: selectedDay)
    }

    /// A slot's nutrient from the reactive raw key; nil when set to None.
    private func slotNutrient(_ slot: Int) -> TrackedNutrient? {
        let raw = slot == 1 ? trackedMetric1 : trackedMetric2
        if raw == SharedStore.trackedMetricNone { return nil }
        return TrackedNutrient(key: raw) ?? (slot == 1 ? .sodium : .water)
    }

    /// The browsed day's total for a slot: sodium/water ride the day
    /// summary; anything else was fetched with it into the model.
    /// nil (untracked day, failed read) renders as "—" like the energy
    /// columns.
    private func slotValue(slot: Int, nutrient: TrackedNutrient) -> Double? {
        switch nutrient {
        case .sodium: model.selectedDaySummary?.sodiumMg
        case .water: model.selectedDaySummary?.waterOz
        default: model.selectedDaySlotTotals[slot - 1]
        }
    }

    /// One tracked metric column, same read as Today's row: limit mode
    /// shows the total colored toward the ceiling; goal mode "x / target",
    /// green when met.
    private func slotMetric(slot: Int, nutrient: TrackedNutrient) -> some View {
        let mode = SharedStore.trackedMode(slot: slot, nutrient: nutrient)
        let target = SharedStore.trackedTarget(slot: slot, nutrient: nutrient)
        let value = slotValue(slot: slot, nutrient: nutrient)
        let text: String = value.map { total in
            let totalText = total.formatted(.number.precision(.fractionLength(0)))
            // Color-only on screen by ruling; VoiceOver gets the limit
            // status via the value below.
            return mode == .limit
                ? "\(totalText) \(nutrient.unitSymbol)"
                : "\(totalText) / \(target.formatted(.number.precision(.fractionLength(0)))) \(nutrient.unitSymbol)"
        } ?? "—"
        let color: Color = value.map { total in
            mode == .limit
                ? Color.sodiumStatus(mg: total, limitMg: target)
                : (total >= target ? .green : .primary)
        } ?? .secondary
        let status = (mode == .limit ? value : nil)
            .flatMap { Color.sodiumStatusLabel(mg: $0, limitMg: target) }
        return metric(icon: { slotIcon(slot: slot, nutrient: nutrient) },
                      text: text, color: color)
            .accessibilityValue(status ?? "")
    }

    @ViewBuilder
    private func slotIcon(slot: Int, nutrient: TrackedNutrient) -> some View {
        if nutrient == .water {
            WaterIconView(raw: waterIcon)
        } else {
            let stored = slot == 1 ? trackedMetric1Icon : trackedMetric2Icon
            Text(SharedStore.isCustomEmoji(stored) ? stored : nutrient.defaultEmoji)
        }
    }

    /// One equal-width column with a fixed-width icon slot, so SF Symbol
    /// and emoji rows line up exactly and icons never move across days.
    private func metric(
        @ViewBuilder icon: () -> some View,
        text: String,
        color: Color = .primary
    ) -> some View {
        HStack(spacing: 6) {
            icon()
                .frame(width: 22, alignment: .center)
            Text(text).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deficitText(for totals: DayEnergyTotals) -> String {
        let deficit = totals.deficitKcal.rounded()
        let amount = abs(deficit).formatted(.number.precision(.fractionLength(0)))
        return deficit >= 0 ? "\(amount) deficit" : "\(amount) surplus"
    }

    /// Highlights only — the full month story (deficit, predicted vs
    /// scale, best streak) lives one tap deeper. The screen was getting
    /// crowded with all six stats on the card.
    private var summaryCard: some View {
        NavigationLink {
            MonthDetailView(model: model, month: displayedMonth)
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    // "this month" while browsing March claimed the
                    // wrong month — name it when it isn't the current.
                    stat(
                        "\(SharedStore.rewardEmoji(for: rewardIcon)) \(model.earnedCount(inMonthOf: displayedMonth))",
                        caption: calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month)
                            ? "this month"
                            : "in \(displayedMonth.formatted(.dateTime.month(.wide)))"
                    )
                    Divider().frame(height: 36)
                    stat(
                        "\(model.streak) \(model.streak == 1 ? "day" : "days")",
                        caption: "current streak",
                        color: model.streak > 0 ? .green : .secondary
                    )
                }
                HStack(spacing: 4) {
                    Text("Details")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the month's deficit, weight change, and records")
    }

    private func stat(_ value: String, caption: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

}

/// The browsed month's full story, pushed from Calendar's summary card
/// and Today's goal card: outcome totals, predicted vs scale weight
/// change, and all-time records.
struct MonthDetailView: View {
    let model: CalendarModel
    let month: Date
    @AppStorage(SharedStore.rewardIconKey, store: SharedStore.defaults) private var rewardIcon = "onigiri"

    var body: some View {
        List {
            Section("This month") {
                LabeledContent("Days goal met") {
                    Text("\(SharedStore.rewardEmoji(for: rewardIcon)) \(model.earnedCount(inMonthOf: month))")
                }
                LabeledContent("Days tracked") {
                    Text("\(model.daysTracked(inMonthOf: month))")
                        .monospacedDigit()
                }
                LabeledContent("Foods logged") {
                    Text(model.monthFoodEntries.map { "\($0)" } ?? "—")
                        .monospacedDigit()
                }
                // Values carry the app's semantic colors so the story
                // pops out of the grey (the user): water blue, burn red,
                // and the green/orange outcome pair everywhere a sign
                // means winning or losing ground.
                LabeledContent("Total water") {
                    Text(model.monthWaterOz.map {
                        "\($0.formatted(.number.precision(.fractionLength(0)))) oz"
                    } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(model.monthWaterOz != nil ? Color.blue : Color.secondary)
                }
                // The energy rows read as one sum (the user):
                // burned − calories = deficit.
                LabeledContent("Total calories") {
                    Text("\(model.totalCalories(inMonthOf: month), format: .number.precision(.fractionLength(0))) kcal")
                        .monospacedDigit()
                }
                LabeledContent("Total burned") {
                    Text("\(model.totalBurned(inMonthOf: month), format: .number.precision(.fractionLength(0))) kcal")
                        .monospacedDigit()
                        .foregroundStyle(.red)
                }
                // Signed like the weight rows (the user): under burn
                // reads negative — and green, the day cards' outcome
                // colors.
                LabeledContent("Total deficit") {
                    Text(model.totalDeficit(inMonthOf: month).map { signedKcal(-$0) } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(outcomeColor(model.totalDeficit(inMonthOf: month).map { -$0 }))
                }
                LabeledContent("Predicted") {
                    Text(model.predictedLb(inMonthOf: month).map { "≈ \(signedLb($0))" } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(outcomeColor(model.predictedLb(inMonthOf: month)))
                }
                LabeledContent("Scale change") {
                    Text(model.actualLb(inMonthOf: month).map(signedLb) ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(outcomeColor(model.actualLb(inMonthOf: month)))
                }
            }
            Section("Streaks") {
                LabeledContent("Current") {
                    Text("\(model.streak) \(model.streak == 1 ? "day" : "days")")
                        .foregroundStyle(model.streak > 0 ? .green : .secondary)
                }
                LabeledContent("Best ever") {
                    Text("\(model.bestStreak) \(model.bestStreak == 1 ? "day" : "days")")
                }
            }
        }
        .readableContentWidth(groupedBackground: true)
        .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
        .navigationBarTitleDisplayMode(.inline)
        // Water total and food count need their own Health queries; the
        // rest of the stats come from the already-loaded day totals.
        .task(id: month) { await model.loadMonthStats(for: month) }
    }

    private func signedLb(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))) lb"
    }

    private func signedKcal(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))) kcal"
    }

    /// The day cards' outcome pair: negative (losing ground on the
    /// scale, eating under burn) is green, positive is orange, absent
    /// or zero stays quiet.
    private func outcomeColor(_ value: Double?) -> Color {
        guard let value, value != 0 else { return .secondary }
        return value < 0 ? .green : .orange
    }
}

// Calendar.startOfMonth(for:) lives in MonthGrid.swift, shared with
// Today's day-jump sheet.

#Preview {
    CalendarView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
