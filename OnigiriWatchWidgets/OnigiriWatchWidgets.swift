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
    let state: DailyPlanLoader.State
    let waterGoalOz: Double
    var showsRemaining = false

    /// The headline number in the user's chosen style: (value, positive-is-good).
    var headline: (kcal: Double, goodAboveZero: Bool) {
        if showsRemaining, let remaining = state.remainingKcal {
            return (remaining, true)
        }
        return (state.summary.balanceKcal, false)
    }

    static let placeholder = WatchEntry(
        date: .now,
        state: DailyPlanLoader.State(
            summary: DailyEnergySummary(
                intakeKcal: 1280, activeBurnKcal: 385, restingBurnKcal: 1120,
                sodiumMg: 1780, waterOz: 36
            ),
            deficitTargetKcal: 583,
            gaugeProgress: 0.38
        ),
        waterGoalOz: 64
    )
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
        // Goal and display settings sync from the phone into the shared defaults.
        let state = await DailyPlanLoader.load(goal: WatchSync.loadGoal())
        return WatchEntry(
            date: .now,
            state: state,
            waterGoalOz: SharedStore.waterGoalOz,
            showsRemaining: SharedStore.showsRemainingKcal
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
        .description("Today's calorie balance and goal progress.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BalanceComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    private var headlineText: Text {
        let (kcal, goodAboveZero) = entry.headline
        return goodAboveZero
            ? Text("\(kcal, format: .number.precision(.fractionLength(0))) kcal left")
            : Text("\(kcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))) kcal")
    }

    private var headlineColor: Color {
        let (kcal, goodAboveZero) = entry.headline
        return (goodAboveZero ? kcal >= 0 : kcal <= 0) ? .green : .orange
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("🍙 ").font(.body) + headlineText
        case .accessoryRectangular:
            HStack(spacing: 8) {
                OnigiriGauge(progress: entry.state.gaugeProgress)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    headlineText
                        .font(.headline.weight(.bold))
                        .foregroundStyle(headlineColor)
                    if let target = entry.state.deficitTargetKcal, target > 0 {
                        Text("\(Int(entry.state.gaugeProgress * 100))% of daily goal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(entry.state.summary.waterOz, format: .number.precision(.fractionLength(0))) oz water")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            Gauge(value: entry.state.gaugeProgress) {
                Text("🍙")
                    .font(.system(size: 12))
            } currentValueLabel: {
                Text(entry.headline.kcal, format: entry.headline.goodAboveZero
                    ? .number.precision(.fractionLength(0))
                    : .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(headlineColor)
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.green)
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

    private var waterOz: Double { entry.state.summary.waterOz }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("💧 \(waterOz, format: .number.precision(.fractionLength(0))) of \(entry.waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
        default:
            Gauge(value: min(waterOz, entry.waterGoalOz), in: 0...max(1, entry.waterGoalOz)) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text(waterOz, format: .number.precision(.fractionLength(0)))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.blue)
        }
    }
}
