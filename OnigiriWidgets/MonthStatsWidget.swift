import WidgetKit
import SwiftUI
import OnigiriKit

/// This month's stats at a glance — goal-met days (the reward emoji) and
/// the current streak — the same judging as the Calendar tab. Replaced
/// the Weight Trend chart in 2.1 (the user). Rice-paper canvas to match
/// the Today card.
struct MonthStatsEntry: TimelineEntry {
    let date: Date
    let month: Date
    let earnedCount: Int
    let trackedCount: Int
    let streak: Int
    let needsSetup: Bool

    static let placeholder = MonthStatsEntry(
        date: .now, month: .now, earnedCount: 14, trackedCount: 19, streak: 5, needsSetup: false
    )
}

struct MonthStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthStatsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (MonthStatsEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in
            completion(await load(asOf: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthStatsEntry>) -> Void) {
        Task { @MainActor in
            // Pre-render the post-midnight numbers so a just-completed
            // day's mark and the rolled streak land even if WidgetKit
            // defers the reload.
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
    private func load(asOf anchor: Date) async -> MonthStatsEntry {
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
        let trackedCount = totals.filter {
            calendar.isDate($0.day, equalTo: month, toGranularity: .month)
                && StreakCalendar.isTracked($0, untrackedBelowKcal: SharedStore.untrackedBelowKcal)
        }.count
        return MonthStatsEntry(
            date: anchor,
            month: month,
            earnedCount: StreakCalendar.earnedCount(inMonthOf: month, earned: earned),
            trackedCount: trackedCount,
            streak: StreakCalendar.currentStreak(earned: earned, today: anchor),
            needsSetup: needsSetup
        )
    }
}

struct MonthStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.monthStats, provider: MonthStatsProvider()) { entry in
            MonthStatsWidgetView(entry: entry)
                .containerBackground(Color.riceCanvas, for: .widget)
                // Month stats live on the Calendar tab — route there,
                // not to whatever tab the app was left on.
                .widgetURL(URL(string: "onigiri://calendar"))
        }
        .configurationDisplayName("Month Stats")
        .description("This month's goal-met days and your current streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MonthStatsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MonthStatsEntry

    private var isSmall: Bool { family == .systemSmall }
    private var emoji: String { SharedStore.rewardEmoji }
    /// Fixed pixel sizes ignored Larger Text (Dynamic Type backfill);
    /// the scale rides one metric so the family ratios hold.
    @ScaledMetric(relativeTo: .largeTitle) private var textScale = 1.0
    private var monthName: String { entry.month.formatted(.dateTime.month(.wide)) }

    var body: some View {
        if entry.needsSetup {
            VStack(spacing: 6) {
                Text(emoji).font(.system(size: (isSmall ? 34 : 40) * textScale))
                Text("Open Onigiri to set up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isSmall {
            VStack(spacing: 4) {
                Text(monthName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.nori)
                Spacer(minLength: 0)
                Text("\(emoji) \(entry.earnedCount)")
                    .font(.system(size: 30 * textScale, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(entry.earnedCount == 1 ? "goal-met day" : "goal-met days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                streakLine
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(monthName)
                    .font(.headline)
                    .foregroundStyle(Color.nori)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    stat("\(emoji) \(entry.earnedCount)",
                         caption: entry.earnedCount == 1 ? "goal-met day" : "goal-met days")
                    Divider().frame(height: 40)
                    stat("\(entry.streak)",
                         caption: entry.streak == 1 ? "day streak" : "day streak",
                         color: entry.streak > 0 ? .green : .primary)
                    Divider().frame(height: 40)
                    stat("\(entry.trackedCount)", caption: "days tracked")
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var streakLine: some View {
        Text(entry.streak > 0
             ? "\(entry.streak)-day streak"
             : "no streak yet")
            .font(.caption2.weight(.medium))
            .foregroundStyle(entry.streak > 0 ? Color.green : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func stat(_ value: String, caption: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
