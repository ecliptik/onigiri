import WidgetKit
import SwiftUI
import OnigiriKit

/// Lock-screen water ring/line — the same shared views as the watch's
/// water complication. Reuses the gauge's provider (same snapshot).
struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriWaterAccessory", provider: GaugeProvider()) { entry in
            WaterAccessoryView(
                waterOz: entry.snapshot.summary.waterOz,
                goalOz: entry.snapshot.waterGoalOz,
                needsSetup: entry.snapshot.needsSetup
            )
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Water")
        .description("Today's water toward your goal.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Streak

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let needsSetup: Bool

    static let placeholder = StreakEntry(date: .now, streak: 3, needsSetup: false)
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in
            completion(await load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        Task { @MainActor in
            // The streak only moves when a day completes — pre-render
            // the post-midnight number (today judged as a completed
            // day) so yesterday's count never shows into the new day
            // while WidgetKit waits out its budget.
            let refresh = Date().addingTimeInterval(WidgetRefreshPolicy.pollFallback)
            let midnight = nextMidnight(after: .now)
            let (streak, atMidnight, needsSetup) = await StreakLoader.loadWithMidnight(midnight ?? .now)
            var entries = [StreakEntry(date: .now, streak: streak, needsSetup: needsSetup)]
            if let midnight, midnight <= refresh {
                entries.append(StreakEntry(date: midnight, streak: atMidnight, needsSetup: needsSetup))
            }
            completion(Timeline(
                entries: entries,
                policy: .after(midnight.map { min($0, refresh) } ?? refresh)
            ))
        }
    }

    @MainActor
    private func load() async -> StreakEntry {
        // The shared kit loader — the watch streak complication runs the
        // exact same judging (per-day snapshot targets, untracked
        // threshold, badges only on completed days).
        let (streak, needsSetup) = await StreakLoader.load()
        return StreakEntry(date: .now, streak: streak, needsSetup: needsSetup)
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriStreak", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Your current run of goal-met days.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    private var emoji: String { SharedStore.rewardEmoji }

    var body: some View {
        switch family {
        case .accessoryInline, .accessoryCircular:
            // The shared kit view — the watch complication renders the
            // exact same thing.
            StreakAccessoryView(streak: entry.streak, needsSetup: entry.needsSetup)
        default:
            VStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 40))
                if entry.needsSetup {
                    Text("Open Onigiri to set up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("\(entry.streak)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.streak > 0 ? Color.green : Color.secondary)
                        .contentTransition(.numericText())
                    Text(entry.streak == 1 ? "day streak" : "day streak")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Month calendar

struct MonthEntry: TimelineEntry {
    let date: Date
    let month: Date
    let earned: Set<Date>
    let tracked: Set<Date>
    let streak: Int
    let needsSetup: Bool
    /// Which day the grid bolds as "today" — entries are ARCHIVED
    /// snapshots, so a midnight pre-render must carry its own anchor
    /// (isDateInToday at render time baked yesterday's highlight in).
    var todayAnchor: Date = .now

    static var placeholder: MonthEntry {
        let calendar = Calendar.current
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        // A believable half-month of history for the gallery.
        var earned: Set<Date> = []
        var tracked: Set<Date> = []
        let today = calendar.startOfDay(for: .now)
        for offset in 1...12 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  calendar.isDate(day, equalTo: month, toGranularity: .month) else { continue }
            tracked.insert(day)
            if offset % 3 != 0 { earned.insert(day) }
        }
        return MonthEntry(date: .now, month: month, earned: earned, tracked: tracked, streak: 2, needsSetup: false)
    }
}

struct MonthProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (MonthEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in
            completion(await load(asOf: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthEntry>) -> Void) {
        Task { @MainActor in
            // Pre-render the post-midnight grid: today's highlight
            // moves and a just-completed day gets its final mark, even
            // if WidgetKit defers the .after(midnight) reload.
            let refresh = Date().addingTimeInterval(WidgetRefreshPolicy.pollFallback)
            let midnight = nextMidnight(after: .now)
            var entries = [await load(asOf: .now)]
            if let midnight, midnight <= refresh {
                entries.append(await load(asOf: midnight))
            }
            completion(Timeline(
                entries: entries,
                policy: .after(midnight.map { min($0, refresh) } ?? refresh)
            ))
        }
    }

    @MainActor
    private func load(asOf anchor: Date) async -> MonthEntry {
        let calendar = Calendar.current
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
        let needsSetup = await PlanCache.needsSetup()
        let state = await PlanCache.state(goal: WatchSync.loadGoal())
        let totals = await PlanCache.energyTotals()
        let earned = StreakCalendar.earnedDays(
            totals: totals,
            targetDeficitKcal: state.deficitTargetKcal,
            targetsByDay: DeficitTargetHistory.targetsByDay(),
            untrackedBelowKcal: SharedStore.untrackedBelowKcal,
            today: anchor
        )
        let tracked = Set(totals
            .filter { StreakCalendar.isTracked($0, untrackedBelowKcal: SharedStore.untrackedBelowKcal) }
            .map { calendar.startOfDay(for: $0.day) })
        return MonthEntry(
            date: anchor,
            month: month,
            earned: earned,
            tracked: tracked,
            streak: StreakCalendar.currentStreak(earned: earned, today: anchor),
            needsSetup: needsSetup,
            todayAnchor: anchor
        )
    }
}

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriMonth", provider: MonthProvider()) { entry in
            MonthWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Month")
        .description("This month's goal-met days and streak.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

/// A compact clone of the app's month grid — same three marks, three
/// stories (badge = met, hollow dot = tracked-but-missed, blank = not
/// tracked).
struct MonthWidgetView: View {
    let entry: MonthEntry

    private let calendar = Calendar.current

    var body: some View {
        if entry.needsSetup {
            VStack(spacing: 6) {
                Text(SharedStore.rewardEmoji).font(.system(size: 40))
                Text("Open Onigiri to set up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 8) {
                HStack {
                    Text(entry.month, format: .dateTime.month(.wide))
                        .font(.headline)
                    Spacer()
                    if entry.streak > 0 {
                        Text("\(entry.streak)-day streak")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                weekdayHeader
                grid
                Spacer(minLength: 0)
            }
        }
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
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

    /// The whole grid speaks as ONE element — bare day numbers and
    /// repeated "rice ball" stops carried none of the three-mark story.
    private var gridSummary: String {
        let earnedCount = StreakCalendar.earnedCount(inMonthOf: entry.month, earned: entry.earned)
        let month = entry.month.formatted(.dateTime.month(.wide))
        return "\(month): goal met \(earnedCount) days, \(entry.streak)-day streak"
    }

    private var grid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    let dayStart = calendar.startOfDay(for: day)
                    VStack(spacing: 1) {
                        let isAnchorDay = calendar.isDate(day, inSameDayAs: entry.todayAnchor)
                        Text(day, format: .dateTime.day())
                            .font(.caption2)
                            .foregroundStyle(isAnchorDay
                                ? Color.riceToast
                                : (day > entry.todayAnchor ? Color.secondary.opacity(0.4) : Color.secondary))
                            .fontWeight(isAnchorDay ? .bold : .regular)
                        if entry.earned.contains(dayStart) {
                            Text(SharedStore.rewardEmoji)
                                .font(.system(size: 10))
                                .frame(height: 12)
                        } else if entry.tracked.contains(dayStart), !calendar.isDate(day, inSameDayAs: entry.todayAnchor) {
                            Circle()
                                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                                .frame(width: 5, height: 5)
                                .frame(height: 12)
                        } else {
                            Color.clear.frame(width: 5, height: 12)
                        }
                    }
                } else {
                    Color.clear.frame(height: 20)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gridSummary)
    }

    private func monthDays() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: entry.month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: entry.month)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayNumber in range {
            days.append(calendar.date(byAdding: .day, value: dayNumber - 1, to: entry.month))
        }
        return days
    }
}
