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

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    weekdayHeader
                    monthGrid
                    daySummaryCard
                    summaryCard
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
            .navigationTitle("Calendar")
        }
        .task { await refresh() }
        .onAppear { Task { await refresh() } }
        .refreshable { await refresh() }
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
    }

    // MARK: - Pieces

    private var monthHeader: some View {
        HStack {
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month))
        }
        .padding(.top, 8)
    }

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

    private var daySummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(selectedDay, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.headline)
                Spacer()
                if model.earned.contains(selectedDay) {
                    Text("🍙 earned")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else if calendar.isDateInToday(selectedDay) {
                    Text("in progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let totals = model.totalsByDay[selectedDay] {
                HStack(spacing: 14) {
                    Label {
                        Text("\(totals.intakeKcal, format: .number.precision(.fractionLength(0))) in")
                    } icon: {
                        Image(systemName: "fork.knife").foregroundStyle(.orange)
                    }
                    Label {
                        Text("\(totals.burnKcal, format: .number.precision(.fractionLength(0))) out")
                    } icon: {
                        Image(systemName: "flame.fill").foregroundStyle(.red)
                    }
                    Spacer()
                    Text(deficitText(for: totals))
                        .fontWeight(.semibold)
                        .foregroundStyle(totals.deficitKcal > 0 ? Color.green : Color.orange)
                }
                .font(.subheadline)
                .monospacedDigit()
                if let target = model.targetDeficitKcal {
                    Text("Daily target: \(target, format: .number.precision(.fractionLength(0))) kcal deficit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No data recorded this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        .animation(.snappy, value: selectedDay)
    }

    private func deficitText(for totals: DayEnergyTotals) -> String {
        let deficit = Int(totals.deficitKcal.rounded())
        return deficit >= 0 ? "\(deficit) deficit" : "\(-deficit) surplus"
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("🍙 \(model.earnedCount(inMonthOf: displayedMonth))")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("this month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 2) {
                Text("\(model.streak) \(model.streak == 1 ? "day" : "days")")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(model.streak > 0 ? Color.green : Color.secondary)
                    .monospacedDigit()
                Text("current streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
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
