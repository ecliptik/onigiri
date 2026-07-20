import WidgetKit
import SwiftUI
import OnigiriKit

/// Small home-screen widget: the onigiri gauge with the balance number.
struct GaugeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriGauge", provider: GaugeProvider()) { entry in
            GaugeWidgetView(entry: entry)
                .containerBackground(Color.riceCanvas, for: .widget)
                // Land on Today like TodayCardWidget — without this the
                // tap dropped users on whatever tab was last active
                // (2026-07-20 audit; flagged 07-16, fixed for
                // MonthStats then, missed here).
                .widgetURL(URL(string: "onigiri://log"))
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
                mode: SharedStore.headlineMode,
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
        // Honor the same "Calorie display" setting (all four modes) as
        // the app and watch, through the one shared readout.
        let readout = CalorieBudget.headlineReadout(
            mode: SharedStore.headlineMode,
            summary: entry.snapshot.summary,
            dailyBudgetKcal: entry.snapshot.planState.dailyBudgetKcal
        )
        let valueFormat: FloatingPointFormatStyle<Double> = readout.signed
            ? .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))
            : .number.precision(.fractionLength(0))
        return VStack(spacing: 4) {
            OnigiriGauge(progress: entry.snapshot.gaugeProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(readout.value, format: valueFormat)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(readout.tint)
            Text(readout.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        // Carry the near/over budget (or deficit/surplus) status the tint
        // alone can't (empty while comfortably under).
        .accessibilityElement(children: .combine)
        .accessibilityValue(readout.statusLabel ?? "")
    }
}
