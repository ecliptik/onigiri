import WidgetKit
import SwiftUI
import OnigiriKit

/// Small home-screen widget: the onigiri gauge with the balance number.
struct GaugeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriGauge", provider: GaugeProvider()) { entry in
            GaugeWidgetView(entry: entry)
                .containerBackground(Color.riceCanvas, for: .widget)
        }
        .configurationDisplayName("Onigiri Gauge")
        .description("Daily goal progress at a glance.")
        // Accessory families put the balance on the iPhone Lock Screen
        // — the same shared views the watch complications render.
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct GaugeEntry: TimelineEntry {
    let date: Date
    let snapshot: DaySnapshot
}

struct GaugeProvider: TimelineProvider {
    func placeholder(in context: Context) -> GaugeEntry {
        GaugeEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (GaugeEntry) -> Void) {
        // The gallery gets the flattering placeholder, not a fresh
        // install's zeros (or a watchdog fallback from a slow query).
        if context.isPreview {
            completion(GaugeEntry(date: .now, snapshot: .placeholder))
            return
        }
        Task { @MainActor in
            completion(GaugeEntry(date: .now, snapshot: await SnapshotLoader.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GaugeEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let snapshot = await SnapshotLoader.load()
            // Push-based reloads keep widgets fresh; this poll is only a fallback.
            let refresh = now.addingTimeInterval(WidgetRefreshPolicy.pollFallback)
            if let midnight = nextMidnight(after: now), midnight <= refresh {
                completion(Timeline(
                    entries: [
                        GaugeEntry(date: now, snapshot: snapshot),
                        GaugeEntry(date: midnight, snapshot: snapshot.newDay),
                    ],
                    policy: .after(midnight)
                ))
            } else {
                completion(Timeline(
                    entries: [GaugeEntry(date: now, snapshot: snapshot)],
                    policy: .after(refresh)
                ))
            }
        }
    }
}

struct GaugeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GaugeEntry

    var body: some View {
        if family != .systemSmall {
            // Lock Screen families render the shared complication view.
            BalanceAccessoryView(
                state: entry.snapshot.planState,
                showsRemaining: SharedStore.showsRemainingKcal,
                needsSetup: entry.snapshot.needsSetup
            )
        } else if entry.snapshot.needsSetup {
            VStack(spacing: 6) {
                OnigiriGauge(progress: 0)
                    .frame(width: 52, height: 52)
                Text("Open Onigiri to set up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            // Pure gauge now — the water button was removed 2.1 (the
            // user); water lives on the Today card and Control Center.
            gauge
        }
    }

    private var gauge: some View {
        VStack(spacing: 4) {
            OnigiriGauge(progress: entry.snapshot.gaugeProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Honor the same "Calorie display" setting as the app/watch.
            if SharedStore.showsRemainingKcal, let remaining = entry.snapshot.remainingKcal {
                let headline = CalorieBudget.remainingHeadline(remaining)
                Text(headline.value, format: .number.precision(.fractionLength(0)))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.remainingStatus(kcal: remaining))
                Text(headline.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.snapshot.summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(entry.snapshot.summary.balanceKcal <= 0 ? Color.green : Color.orange)
                Text("kcal balance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        // Carry the near/over budget status the amber tint alone can't
        // (remainingStatusLabel discipline; empty while comfortably under).
        .accessibilityElement(children: .combine)
        .accessibilityValue(remainingStatusValue ?? "")
    }

    /// VoiceOver twin of the headline's amber "near budget" tint.
    private var remainingStatusValue: String? {
        guard SharedStore.showsRemainingKcal, let remaining = entry.snapshot.remainingKcal else { return nil }
        return Color.remainingStatusLabel(kcal: remaining)
    }
}
