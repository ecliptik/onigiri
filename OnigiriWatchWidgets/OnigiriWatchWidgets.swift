import WidgetKit
import SwiftUI
import OnigiriKit

@main
struct OnigiriWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BalanceComplication()
        WaterComplication()
        StreakComplication()
        SummaryComplication()
    }
}

// MARK: - Shared provider

/// Smart Stack ranking (batch D): timeline widgets compete for
/// placement with signals we provide, and without any the stack
/// never surfaces Onigiri on its own. TimelineEntryRelevance is
/// watchOS 7 — no availability gate needed at the 10.0 floor.
enum ComplicationRelevance {
    /// The balance/summary complications matter most around meals.
    static func mealWindow(at date: Date) -> TimelineEntryRelevance {
        let hour = Calendar.current.component(.hour, from: date)
        let inWindow = (7...8).contains(hour)
            || (11...13).contains(hour)
            || (17...19).contains(hour)
        return TimelineEntryRelevance(score: inWindow ? 60 : 10)
    }

    /// The streak matters in the evening, while there's still time to
    /// save the day.
    static func evening(at date: Date) -> TimelineEntryRelevance {
        let hour = Calendar.current.component(.hour, from: date)
        return TimelineEntryRelevance(score: (19...22).contains(hour) ? 50 : 10)
    }
}

/// The watch's last-good plan state — the equivalent of the phone's
/// `widget.lastGoodSnapshot`, which the complications never had
/// (PLAN-widget-burn-freshness, Phase 4).
///
/// Without it, a reload against a SEALED Health store — watch off the
/// wrist, or simply locked — fell through `DailyPlanLoader`'s
/// `(try? await summaryRead) ?? .zero` and rendered a confident ZERO DAY:
/// no intake, no burn, a gauge reading whatever zero means in the current
/// mode. That is the precise failure the phone's cache was added to
/// prevent, and it gets likelier the moment Phase 2b raises how often the
/// watch reloads — which is why it ships in the same round.
///
/// Stale-but-true beats confidently wrong.
enum WatchStateCache {
    private static let key = "watchWidget.lastGoodState"

    static func store(_ state: DailyPlanLoader.State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        SharedStore.defaults.set(data, forKey: key)
    }

    static func load() -> DailyPlanLoader.State? {
        guard let data = SharedStore.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DailyPlanLoader.State.self, from: data)
    }

    /// The plan state for a complication render, and whether it came from
    /// the cache because the store was sealed.
    @MainActor
    static func resolve(goal: SyncedGoal?) async -> (state: DailyPlanLoader.State, cached: Bool) {
        if await HealthKitService().isStoreLocked(), let cached = load() {
            return (cached, true)
        }
        let state = await PlanCache.state(goal: goal)
        store(state)
        // The burn gate's baseline: what this render is about to show —
        // but never from a degenerate read. See SnapshotLoader for the
        // 2026-08-07 case where a sealed store slipped past
        // `isStoreLocked()` and wrote a baseline of zero.
        if state.dailyBudgetKcal != nil {
            WidgetBurnGate.recordRendered(activeKcal: state.summary.activeBurnKcal)
        }
        return (state, false)
    }
}

/// The poll every watch complication commits to — the phone's
/// `nextRefresh` twin, kept separate only because the two bundles don't
/// share a file. Recent activity is now a log OR burn (Phase 3): this
/// window used to open for `lastPhoneLogAt` alone, so a walk with no
/// logging left every complication on the flat hourly fallback.
func watchNextRefresh(after now: Date, wasCached: Bool) -> (date: Date, interval: TimeInterval) {
    let interval = wasCached
        ? WidgetRefreshPolicy.sealedStoreRetry
        : WidgetRefreshPolicy.nextPoll(now: now, lastActivityAt: WidgetBurnGate.lastActivityAt())
    return (now.addingTimeInterval(interval), interval)
}

struct WatchEntry: TimelineEntry {
    let date: Date
    let state: DailyPlanLoader.State
    let waterGoalOz: Double
    var mode: HeadlineMode = .remaining
    /// Health access never granted — a confident green "0 kcal" before
    /// setup was indistinguishable from a genuinely balanced day.
    var needsSetup = false
    var relevance: TimelineEntryRelevance?

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
            mode: mode,
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
            completion(await load().entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let load = await load()
            var entry = load.entry
            entry.relevance = ComplicationRelevance.mealWindow(at: now)
            // Push-based reloads keep complications fresh; this poll is
            // the fallback — except right after recent activity, when a
            // stamp may have arrived ahead of the sample (WC beats
            // Health sync) and a short follow-up poll catches the totals
            // the reload missed.
            let refresh = watchNextRefresh(after: now, wasCached: load.cached)
            let midnight = Calendar.current.date(
                byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
            )
            // The midnight entry rides EVERY timeline: a future-dated
            // entry renders with no reload and no budget, while a
            // gated one leaves a stale single entry showing yesterday
            // whenever the overnight reload is deferred (phone widget,
            // 2026-07-26).
            var entries = [entry]
            if let midnight {
                var fresh = entry.newDay(at: midnight)
                fresh.relevance = ComplicationRelevance.mealWindow(at: midnight)
                entries.append(fresh)
            }
            WidgetLog.timelineBuilt(
                kind: WidgetKinds.balance,
                dayBurnKcal: entry.state.dayBurnKcal,
                nextPoll: refresh.interval,
                cached: load.cached
            )
            completion(Timeline(
                entries: entries,
                policy: .after(midnight.map { min($0, refresh.date) } ?? refresh.date)
            ))
        }
    }

    @MainActor
    private func load() async -> (entry: WatchEntry, cached: Bool) {
        let needsSetup = await PlanCache.needsSetup()
        // Goal and display settings sync from the phone into the shared defaults.
        let resolved = await WatchStateCache.resolve(goal: WatchSync.loadGoal())
        let entry = WatchEntry(
            date: .now,
            state: resolved.state,
            waterGoalOz: SharedStore.waterGoalOz,
            mode: SharedStore.headlineMode,
            needsSetup: needsSetup
        )
        return (entry, resolved.cached)
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
            mode: entry.mode,
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

// MARK: - Summary complication

/// One tracked-metric line as the phone's Today row shows it: limit mode
/// is the total colored toward the ceiling, goal mode "x / target".
struct SummarySlot: Sendable {
    let emoji: String
    /// Canonical units (mg/oz/…): the sodium status color's absolute
    /// near-limit band needs them — display conversion happens in
    /// slotText, not here.
    let total: Double
    let target: Double
    let nutrient: TrackedNutrient
    let isLimit: Bool

    var zeroed: SummarySlot {
        SummarySlot(emoji: emoji, total: 0, target: target, nutrient: nutrient, isLimit: isLimit)
    }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let state: DailyPlanLoader.State
    let slots: [SummarySlot]
    var mode: HeadlineMode = .remaining
    var needsSetup = false
    var relevance: TimelineEntryRelevance?

    static let placeholder = SummaryEntry(
        date: .now,
        state: DailyPlanLoader.State(
            summary: DailyEnergySummary(
                intakeKcal: 1280, activeBurnKcal: 385, restingBurnKcal: 1120,
                sodiumMg: 1780, waterOz: 36
            ),
            deficitTargetKcal: 583,
            gaugeProgress: 0.38
        ),
        slots: [
            SummarySlot(emoji: "🧂", total: 1780, target: 2300, nutrient: .sodium, isLimit: true),
            SummarySlot(emoji: "💧", total: 36, target: 64, nutrient: .water, isLimit: false),
        ]
    )

    func newDay(at date: Date) -> SummaryEntry {
        SummaryEntry(
            date: date,
            state: DailyPlanLoader.State(
                summary: .zero,
                deficitTargetKcal: state.deficitTargetKcal,
                gaugeProgress: 0,
                dailyBudgetKcal: state.dailyBudgetKcal
            ),
            slots: slots.map(\.zeroed),
            mode: mode,
            needsSetup: needsSetup
        )
    }
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in
            completion(await load().entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let load = await load()
            var entry = load.entry
            entry.relevance = ComplicationRelevance.mealWindow(at: now)
            // Push-based reloads keep complications fresh; this poll is
            // the fallback — except right after recent activity (a log,
            // or burn that moved enough to matter).
            let refresh = watchNextRefresh(after: now, wasCached: load.cached)
            let midnight = Calendar.current.date(
                byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
            )
            // The midnight entry rides EVERY timeline: a future-dated
            // entry renders with no reload and no budget, while a
            // gated one leaves a stale single entry showing yesterday
            // whenever the overnight reload is deferred (phone widget,
            // 2026-07-26).
            var entries = [entry]
            if let midnight {
                var fresh = entry.newDay(at: midnight)
                fresh.relevance = ComplicationRelevance.mealWindow(at: midnight)
                entries.append(fresh)
            }
            WidgetLog.timelineBuilt(
                kind: WidgetKinds.summary,
                dayBurnKcal: entry.state.dayBurnKcal,
                nextPoll: refresh.interval,
                cached: load.cached
            )
            completion(Timeline(
                entries: entries,
                policy: .after(midnight.map { min($0, refresh.date) } ?? refresh.date)
            ))
        }
    }

    @MainActor
    private func load() async -> (entry: SummaryEntry, cached: Bool) {
        let health = HealthKitService()
        let needsSetup = await PlanCache.needsSetup()
        let resolved = await WatchStateCache.resolve(goal: WatchSync.loadGoal())
        let state = resolved.state
        // The phone's two tracked-metric slots, exactly as Settings has
        // them (they sync into the shared defaults).
        var slots: [SummarySlot] = []
        for slot in 1...2 {
            guard let nutrient = SharedStore.trackedNutrient(slot: slot) else { continue }
            let total: Double
            switch nutrient {
            case .sodium: total = state.summary.sodiumMg
            case .water: total = state.summary.waterOz
            default: total = (try? await health.dayTotal(of: nutrient)) ?? 0
            }
            slots.append(SummarySlot(
                emoji: SharedStore.trackedEmoji(slot: slot, nutrient: nutrient),
                total: total,
                target: SharedStore.trackedTarget(slot: slot, nutrient: nutrient),
                nutrient: nutrient,
                isLimit: SharedStore.trackedMode(slot: slot, nutrient: nutrient) == .limit
            ))
        }
        let entry = SummaryEntry(
            date: .now,
            state: state,
            slots: slots,
            mode: SharedStore.headlineMode,
            needsSetup: needsSetup
        )
        return (entry, resolved.cached)
    }
}

struct SummaryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriSummary", provider: SummaryProvider()) { entry in
            SummaryComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Metrics")
        .description("Calorie headline plus your two tracked metrics.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct SummaryComplicationView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            headline
                .font(.headline.weight(.semibold))
            ForEach(Array(entry.slots.enumerated()), id: \.offset) { _, slot in
                HStack(spacing: 4) {
                    Text(slot.emoji)
                        .font(.caption)
                    Text(slotText(slot))
                        .font(.caption)
                        .foregroundStyle(slotColor(slot))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var headline: some View {
        if entry.needsSetup {
            Text("Open Onigiri to set up")
        } else {
            let readout = CalorieBudget.headlineReadout(
                mode: entry.mode, summary: entry.state.summary,
                dailyBudgetKcal: entry.state.dailyBudgetKcal,
                dayBurnKcal: entry.state.dayBurnKcal
            )
            let valueFormat: FloatingPointFormatStyle<Double> = readout.signed
                ? .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))
                : .number.precision(.fractionLength(0))
            Text("\(readout.value, format: valueFormat) \(readout.caption)")
                .foregroundStyle(readout.tint)
                // The amber near-budget (or deficit/surplus) status needs
                // a non-color twin.
                .accessibilityValue(readout.statusLabel ?? "")
        }
    }

    private func slotText(_ slot: SummarySlot) -> String {
        let water = SharedStore.waterUnit
        let sodium = SharedStore.sodiumUnit
        let digits = slot.nutrient.displayFractionDigits(sodium: sodium)
        let total = slot.nutrient.displayValue(slot.total, water: water, sodium: sodium)
            .formatted(.number.precision(.fractionLength(digits)))
        let symbol = slot.nutrient.displayUnitSymbol(water: water, sodium: sodium)
        if slot.isLimit {
            return "\(total) \(symbol)"
        }
        let target = slot.nutrient.displayValue(slot.target, water: water, sodium: sodium)
            .formatted(.number.precision(.fractionLength(digits)))
        return "\(total) / \(target) \(symbol)"
    }

    private func slotColor(_ slot: SummarySlot) -> Color {
        if slot.isLimit {
            return Color.sodiumStatus(mg: slot.total, limitMg: slot.target)
        }
        return slot.total >= slot.target ? .green : .primary
    }
}

// MARK: - Streak complication

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let needsSetup: Bool
    var relevance: TimelineEntryRelevance?

    static let placeholder = StreakEntry(date: .now, streak: 3, needsSetup: false)
}

struct StreakComplicationProvider: TimelineProvider {
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
            // the post-midnight number (today judged complete) so
            // yesterday's count never shows into the new day.
            let now = Date()
            // The streak judges COMPLETED days, so today's burn can't
            // move it — plain cadence, no recent-activity window (the
            // phone's streak widget matches).
            let refresh = now.addingTimeInterval(WidgetRefreshPolicy.pollInterval(now: now))
            let midnight = Calendar.current.date(
                byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
            )
            let (streak, atMidnight, needsSetup) = await StreakLoader.loadWithMidnight(midnight ?? now)
            var entry = StreakEntry(date: now, streak: streak, needsSetup: needsSetup)
            entry.relevance = ComplicationRelevance.evening(at: now)
            var entries = [entry]
            if let midnight {
                var fresh = StreakEntry(date: midnight, streak: atMidnight, needsSetup: needsSetup)
                fresh.relevance = ComplicationRelevance.evening(at: midnight)
                entries.append(fresh)
            }
            WidgetLog.timelineBuilt(
                kind: WidgetKinds.streak, dayBurnKcal: nil,
                nextPoll: refresh.timeIntervalSince(now), cached: false
            )
            completion(Timeline(
                entries: entries,
                policy: .after(midnight.map { min($0, refresh) } ?? refresh)
            ))
        }
    }

    @MainActor
    private func load() async -> StreakEntry {
        // The shared kit loader — the iPhone streak widget runs the
        // exact same judging.
        let (streak, needsSetup) = await StreakLoader.load()
        return StreakEntry(date: .now, streak: streak, needsSetup: needsSetup)
    }
}

struct StreakComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriStreak", provider: StreakComplicationProvider()) { entry in
            StreakAccessoryView(streak: entry.streak, needsSetup: entry.needsSetup)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Your current run of goal-met days.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner, .accessoryRectangular])
    }
}
