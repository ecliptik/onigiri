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
                    VStack(spacing: Layout.screenSpacing) {
                        weekdayHeader
                        monthGrid
                    }
                    .simultaneousGesture(horizontalSwipe { shiftMonth($0) })
                    VStack(spacing: Layout.screenSpacing) {
                        dayHeader
                        daySummaryCard
                    }
                    .simultaneousGesture(horizontalSwipe { shiftDay($0) })
                    if model.targetDeficitKcal == nil {
                        Text("No goal set — days earn an onigiri for any calorie deficit. Set a goal to raise the bar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.horizontal)
            }
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
        .onAppear { Task { await refresh() } }
        .refreshable { await refresh() }
        .onChange(of: selectedDay) { _, day in
            Task { await model.loadDaySummary(for: day) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
    }

    private func refresh() async {
        let goal = goals.first.map {
            SyncedGoal(
                targetWeightLb: $0.targetWeightLb,
                targetDate: $0.targetDate,
                fallbackCurrentWeightLb: $0.fallbackCurrentWeightLb
            )
        }
        await model.refresh(goal: goal)
        await model.loadDaySummary(for: selectedDay)
    }

    // MARK: - Pieces

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        // Rotate so the row starts on the calendar's first weekday.
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return HStack {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    let dayStart = calendar.startOfDay(for: day)
                    DayCell(
                        day: day,
                        earned: model.earned.contains(dayStart),
                        isToday: calendar.isDateInToday(day),
                        isFuture: day > .now,
                        isSelected: dayStart == selectedDay
                    )
                    .onTapGesture {
                        if day <= .now {
                            selectedDay = dayStart
                        }
                    }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    /// The displayed month as day dates, padded with nil for grid alignment.
    private func monthDays() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayNumber in range {
            days.append(calendar.date(byAdding: .day, value: dayNumber - 1, to: displayedMonth))
        }
        return days
    }

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
            Text(selectedDay, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.headline)
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
            // Constant leading anchor; the goal status is a trailing badge
            // so nothing shifts or reflows as days change.
            HStack(spacing: 6) {
                Text("Day Summary")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.earned.contains(selectedDay) {
                    Text("Goal met 🍙")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else if calendar.isDateInToday(selectedDay) {
                    Text("In progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            // Fixed three-column grid, always rendered ("—" when a day has
            // no data): every icon keeps its exact position across day
            // changes, so only the numbers repaint.
            let totals = model.totalsByDay[selectedDay]
            HStack(spacing: 0) {
                metric(icon: { FoodIconView(raw: foodIcon) },
                       text: totals.map { "\(Int($0.intakeKcal.rounded())) in" } ?? "—")
                metric(icon: { Image(systemName: "flame.fill").foregroundStyle(.red) },
                       text: totals.map { "\(Int($0.burnKcal.rounded())) out" } ?? "—")
                Text(totals.map(deficitText(for:)) ?? "—")
                    .fontWeight(.semibold)
                    .foregroundStyle((totals?.deficitKcal ?? 0) > 0 ? Color.green : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline)
            .monospacedDigit()

            let summary = model.selectedDaySummary
            HStack(spacing: 0) {
                metric(icon: { Text("🧂") },
                       text: summary.map { "\(Int($0.sodiumMg.rounded())) mg" } ?? "—",
                       color: summary.map { Color.sodiumStatus(mg: $0.sodiumMg, limitMg: SharedStore.sodiumLimitMg) } ?? .secondary)
                metric(icon: { WaterIconView(raw: waterIcon) },
                       text: summary.map {
                           "\(Int($0.waterOz.rounded())) / \(Int(SharedStore.waterGoalOz)) oz"
                       } ?? "—",
                       color: (summary?.waterOz ?? 0) >= SharedStore.waterGoalOz ? .green : .primary)
                Spacer()
                    .frame(maxWidth: .infinity)
            }
            .font(.subheadline)
            .monospacedDigit()

            if let target = model.targetDeficitKcal {
                // Same vocabulary as Today's "Daily goal" card.
                Text("Daily goal: \(target, format: .number.precision(.fractionLength(0))) kcal deficit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
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
        let deficit = Int(totals.deficitKcal.rounded())
        return deficit >= 0 ? "\(deficit) deficit" : "\(-deficit) surplus"
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                stat("🍙 \(model.earnedCount(inMonthOf: displayedMonth))", caption: "this month")
                Divider().frame(height: 36)
                stat(
                    "\(model.streak) \(model.streak == 1 ? "day" : "days")",
                    caption: "current streak",
                    color: model.streak > 0 ? .green : .secondary
                )
            }
            HStack(spacing: 0) {
                stat(
                    model.totalDeficit(inMonthOf: displayedMonth).map {
                        "\(Int($0.rounded())) kcal"
                    } ?? "—",
                    caption: "total deficit, this month"
                )
                Divider().frame(height: 36)
                stat(
                    "\(model.bestStreak) \(model.bestStreak == 1 ? "day" : "days")",
                    caption: "best streak"
                )
            }
        }
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
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

private struct DayCell: View {
    let day: Date
    let earned: Bool
    let isToday: Bool
    let isFuture: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(day, format: .dateTime.day())
                .font(.caption2)
                .foregroundStyle(isToday ? Color.accentColor : (isFuture ? Color.secondary.opacity(0.4) : Color.secondary))
                .fontWeight(isToday ? .bold : .regular)
            if earned {
                Text("🍙")
                    .font(.system(size: 18))
            } else {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 5, height: 5)
                    .opacity(isFuture ? 0 : 1)
                    .frame(height: 20)
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.ricePaper.opacity(0.45) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(.rect)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
