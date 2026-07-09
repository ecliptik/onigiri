import WidgetKit
import SwiftUI
import OnigiriKit

@main
struct OnigiriWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BalanceComplication()
        WaterComplication()
    }
}

// MARK: - Shared provider

struct WatchEntry: TimelineEntry {
    let date: Date
    let balanceKcal: Double
    let waterOz: Double
    let waterGoalOz: Double

    static let placeholder = WatchEntry(date: .now, balanceKcal: -225, waterOz: 36, waterGoalOz: 64)
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        Task { @MainActor in
            completion(await load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        Task { @MainActor in
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    @MainActor
    private func load() async -> WatchEntry {
        let summary = (try? await HealthKitService().todaySummary()) ?? .zero
        // Water goal syncs from the phone in a later phase; 64 oz until then.
        return WatchEntry(
            date: .now,
            balanceKcal: summary.balanceKcal,
            waterOz: summary.waterOz,
            waterGoalOz: 64
        )
    }
}

// MARK: - Balance complication

struct BalanceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriBalance", provider: WatchProvider()) { entry in
            BalanceComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Calorie Balance")
        .description("Today's calorie balance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BalanceComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("🍙 \(entry.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))) kcal")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("🍙 Onigiri")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(entry.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))) kcal")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(entry.balanceKcal <= 0 ? Color.green : Color.orange)
                Text("\(entry.waterOz, format: .number.precision(.fractionLength(0))) oz water")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        default:
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 4)
                VStack(spacing: 0) {
                    Text("🍙")
                        .font(.system(size: 13))
                    Text(entry.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.balanceKcal <= 0 ? Color.green : Color.orange)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(4)
            }
        }
    }
}

// MARK: - Water complication

struct WaterComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriWater", provider: WatchProvider()) { entry in
            WaterComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Water")
        .description("Today's water toward your goal.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct WaterComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("💧 \(entry.waterOz, format: .number.precision(.fractionLength(0))) of \(entry.waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
        default:
            Gauge(value: min(entry.waterOz, entry.waterGoalOz), in: 0...entry.waterGoalOz) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text(entry.waterOz, format: .number.precision(.fractionLength(0)))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.blue)
        }
    }
}
