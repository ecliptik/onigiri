import SwiftUI
import OnigiriKit

/// The month calendar — weekday header + day cells with the earned
/// badges and the selection tint — shared by the Calendar tab and
/// Today's day-jump sheet so browsing days looks the same everywhere.
struct MonthGridView: View {
    /// Start of the displayed month.
    let month: Date
    let earned: Set<Date>
    /// Days that cleared the untracked threshold — a missed goal and a
    /// day with no data are different stories and wear different marks.
    var tracked: Set<Date> = []
    let selectedDay: Date
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 8) {
            weekdayHeader
            grid
        }
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

    private var grid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    let dayStart = calendar.startOfDay(for: day)
                    DayCell(
                        day: day,
                        earned: earned.contains(dayStart),
                        tracked: tracked.contains(dayStart),
                        isToday: calendar.isDateInToday(day),
                        isFuture: day > .now,
                        isSelected: dayStart == selectedDay
                    )
                    .onTapGesture {
                        if day <= .now {
                            onSelect(dayStart)
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
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayNumber in range {
            days.append(calendar.date(byAdding: .day, value: dayNumber - 1, to: month))
        }
        return days
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

private struct DayCell: View {
    let day: Date
    let earned: Bool
    let tracked: Bool
    let isToday: Bool
    let isFuture: Bool
    let isSelected: Bool

    // Scaled with the day number's font: at accessibility sizes a fixed
    // 44pt cell left the onigiri hanging outside the selection tint.
    @ScaledMetric(relativeTo: .caption2) private var cellHeight = 44.0
    @ScaledMetric(relativeTo: .caption2) private var markerHeight = 20.0
    @ScaledMetric(relativeTo: .caption2) private var emojiSize = 15.0
    @AppStorage(SharedStore.rewardIconKey, store: SharedStore.defaults) private var rewardIcon = "onigiri"

    var body: some View {
        VStack(spacing: 2) {
            Text(day, format: .dateTime.day())
                .font(.caption2)
                .foregroundStyle(isToday ? Color.accentColor : (isFuture ? Color.secondary.opacity(0.4) : Color.secondary))
                .fontWeight(isToday ? .bold : .regular)
            if earned {
                // Sized into the same box as the dot branch: emoji glyphs
                // draw past their line height, and at 18pt the rice ball
                // bled into the row below on iPad's wide grid.
                Text(SharedStore.rewardEmoji(for: rewardIcon))
                    .font(.system(size: emojiSize))
                    .frame(height: markerHeight)
            } else if tracked, !isToday {
                // Tracked but the goal was missed — a hollow dot. A day
                // with no data stays blank: one gray dot used to mean
                // missed, untracked, and pre-install alike.
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .opacity(isFuture ? 0 : 1)
                    .frame(height: markerHeight)
            } else {
                Color.clear
                    .frame(width: 6, height: 6)
                    .frame(height: markerHeight)
            }
        }
        .frame(height: cellHeight)
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
        // The cell is tap-driven (parent gesture) with purely visual state —
        // VoiceOver needs the story spelled out and a button to press.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isFuture ? "" : "Shows this day's summary")
    }

    private var accessibilitySummary: String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if isFuture { return "\(date), upcoming" }
        // Today is never "met" mid-day — the badge is awarded when the
        // day completes.
        if isToday { return "Today, \(date), \(earned ? "goal met" : "in progress")" }
        // "Goal not met" for a day with zero data was a lie.
        if earned { return "\(date), goal met" }
        return "\(date), \(tracked ? "goal not met" : "not tracked")"
    }
}
