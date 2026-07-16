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
            .containerBackground(Color.riceCanvas, for: .widget)
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
                .containerBackground(Color.riceCanvas, for: .widget)
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
    /// Fixed pixel sizes ignored Larger Text (Dynamic Type backfill).
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize = 40.0
    @ScaledMetric(relativeTo: .largeTitle) private var countSize = 32.0

    var body: some View {
        switch family {
        case .accessoryInline, .accessoryCircular:
            // The shared kit view — the watch complication renders the
            // exact same thing.
            StreakAccessoryView(streak: entry.streak, needsSetup: entry.needsSetup)
        default:
            VStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: badgeSize))
                    .minimumScaleFactor(0.6)
                if entry.needsSetup {
                    Text("Open Onigiri to set up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("\(entry.streak)")
                        .font(.system(size: countSize, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
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
