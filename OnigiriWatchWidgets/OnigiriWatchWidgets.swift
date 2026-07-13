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
    let entry: WatchEntry

    var body: some View {
        // The shared kit view — the iPhone lock screen renders the
        // exact same thing.
        BalanceAccessoryView(
            state: entry.state,
            showsRemaining: entry.showsRemaining,
            needsSetup: entry.needsSetup
        )
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
    let entry: WatchEntry

    var body: some View {
        // The shared kit view — the iPhone lock screen renders the
        // exact same thing.
        WaterAccessoryView(
            waterOz: entry.state.summary.waterOz,
            goalOz: entry.waterGoalOz,
            needsSetup: entry.needsSetup
        )
    }
}
