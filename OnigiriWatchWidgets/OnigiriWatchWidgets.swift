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
    /// Health access never granted — a confident green "0 kcal" before
    /// setup was indistinguishable from a genuinely balanced day.
    var needsSetup = false

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

    /// The just-after-midnight render: nothing eaten or burned yet, the
    /// same plan. Pre-rendered so yesterday's numbers never show into
    /// the new day while WidgetKit waits out its refresh budget.
    func newDay(at date: Date) -> WatchEntry {
        WatchEntry(
            date: date,
            state: DailyPlanLoader.State(
                summary: .zero,
                deficitTargetKcal: state.deficitTargetKcal,
                gaugeProgress: 0,
                dailyBudgetKcal: state.dailyBudgetKcal
            ),
            waterGoalOz: waterGoalOz,
            showsRemaining: showsRemaining,
            needsSetup: needsSetup
        )
    }
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        // The complication picker gets the flattering placeholder, not
        // a fresh install's zeros (or a watchdog fallback).
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in
            completion(await load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let entry = await load()
            let refresh = now.addingTimeInterval(30 * 60)
            let midnight = Calendar.current.date(
                byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
            )
            if let midnight, midnight <= refresh {
                completion(Timeline(
                    entries: [entry, entry.newDay(at: midnight)],
                    policy: .after(midnight)
                ))
            } else {
                completion(Timeline(entries: [entry], policy: .after(refresh)))
            }
        }
    }

    @MainActor
    private func load() async -> WatchEntry {
        let health = HealthKitService()
        let needsSetup = (try? await health.shouldRequestAuthorization()) == true
        // Goal and display settings sync from the phone into the shared defaults.
        let state = await DailyPlanLoader.load(goal: WatchSync.loadGoal())
        return WatchEntry(
            date: .now,
            state: state,
            waterGoalOz: SharedStore.waterGoalOz,
            showsRemaining: SharedStore.showsRemainingKcal,
            needsSetup: needsSetup
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
        // Corner slots are the most numerous on the popular analog
        // faces — Onigiri simply didn't appear as an option there.
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
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
        if entry.needsSetup {
            setupHint
        } else {
            complication
        }
    }

    /// Pre-authorization: say what to do instead of a confident zero.
    @ViewBuilder
    private var setupHint: some View {
        switch family {
        case .accessoryInline:
            Text("\(SharedStore.rewardEmoji) Open Onigiri to set up")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Text(SharedStore.rewardEmoji)
                Text("Open Onigiri\nto set up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        case .accessoryCorner:
            Text(SharedStore.rewardEmoji)
                .font(.system(size: 20))
                .widgetLabel { Text("Set up Onigiri") }
        default:
            Gauge(value: 0) {
                Text(SharedStore.rewardEmoji).font(.system(size: 12))
            } currentValueLabel: {
                Text("—")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }

    @ViewBuilder
    private var complication: some View {
        switch family {
        case .accessoryInline:
            Text("\(SharedStore.rewardEmoji) ").font(.body) + headlineText
        case .accessoryCorner:
            // The badge in the corner, the headline on the curve.
            Text(SharedStore.rewardEmoji)
                .font(.system(size: 20))
                .widgetLabel {
                    headlineText
                        .foregroundStyle(headlineColor)
                }
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
            // The ring mimics Today's headline ring: how much of the
            // day's calorie budget is eaten, orange when over (it showed
            // deficit-goal progress before — Micheal wanted one meaning).
            // Without a plan it falls back to goal progress.
            let eaten = entry.state.dailyBudgetKcal.map { budget in
                budget > 0 ? min(1, entry.state.summary.intakeKcal / budget) : 0
            }
            let over = entry.state.dailyBudgetKcal.map { entry.state.summary.intakeKcal > $0 } ?? false
            Gauge(value: eaten ?? entry.state.gaugeProgress) {
                Text(SharedStore.rewardEmoji)
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
            .tint(over ? .orange : .green)
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
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct WaterComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    private var waterOz: Double { entry.state.summary.waterOz }

    var body: some View {
        switch family {
        case .accessoryInline:
            if entry.needsSetup {
                Text("💧 Open Onigiri to set up")
            } else {
                Text("💧 \(waterOz, format: .number.precision(.fractionLength(0))) of \(entry.waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
            }
        case .accessoryCorner:
            Image(systemName: "drop.fill")
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .widgetLabel {
                    entry.needsSetup
                        ? Text("Set up Onigiri")
                        : Text("\(waterOz, format: .number.precision(.fractionLength(0)))/\(entry.waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
                }
        default:
            Gauge(value: entry.needsSetup ? 0 : min(waterOz, entry.waterGoalOz), in: 0...max(1, entry.waterGoalOz)) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                entry.needsSetup
                    ? Text("—")
                    : Text(waterOz, format: .number.precision(.fractionLength(0)))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.blue)
        }
    }
}
