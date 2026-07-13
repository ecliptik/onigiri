#if canImport(HealthKit)
import Foundation

/// One widget reload used to fan out to every provider, each re-running the
/// full HealthKit pipeline (todaySummary + weight + 14-day burn ≈ 9 queries,
/// plus 92-day energy scans for the streak surfaces) independently. This
/// cache computes each expensive read once per reload burst and shares it
/// across the providers in the same process.
///
/// An entry is valid for a short TTL, within the same calendar day, and only
/// while the cross-process data version is unchanged. WidgetReloader bumps
/// the version before every intentional reload — i.e. exactly when log data
/// or settings changed — so providers never render a pre-mutation cache.
@MainActor
public enum PlanCache {
    static let versionKey = "planCacheVersion"

    /// Long enough to cover one reload burst across providers; short enough
    /// that a poll-driven reload minutes later recomputes from Health.
    public static let ttl: TimeInterval = 60

    private struct Entry<Value> {
        let value: Value
        let stamp: Date
        let version: Int
    }

    private static var stateEntry: (entry: Entry<DailyPlanLoader.State>, goal: SyncedGoal?)?
    private static var stateTask: (task: Task<DailyPlanLoader.State, Never>, goal: SyncedGoal?, version: Int)?
    private static var totalsEntry: Entry<[DayEnergyTotals]>?
    private static var totalsTask: (task: Task<[DayEnergyTotals], Never>, version: Int)?
    private static var setupEntry: Entry<Bool>?
    private static var setupTask: (task: Task<Bool, Never>, version: Int)?

    /// Log data or settings changed: bump the cross-process version (other
    /// processes' entries die with it) and drop this process's entries.
    public static func invalidate() {
        SharedStore.defaults.set(currentVersion() + 1, forKey: versionKey)
        stateEntry = nil
        stateTask = nil
        totalsEntry = nil
        totalsTask = nil
        setupEntry = nil
        setupTask = nil
    }

    static func currentVersion() -> Int {
        SharedStore.defaults.integer(forKey: versionKey)
    }

    private static func isValid<Value>(_ entry: Entry<Value>?, version: Int) -> Bool {
        guard let entry else { return false }
        return entry.version == version
            && Date.now.timeIntervalSince(entry.stamp) < ttl
            && Calendar.current.isDate(entry.stamp, inSameDayAs: .now)
    }

    /// The daily plan, computed at most once per burst per goal.
    public static func state(goal: SyncedGoal?) async -> DailyPlanLoader.State {
        let version = currentVersion()
        if let cached = stateEntry, cached.goal == goal, isValid(cached.entry, version: version) {
            return cached.entry.value
        }
        if let running = stateTask, running.goal == goal, running.version == version {
            return await running.task.value
        }
        let task = Task { await DailyPlanLoader.load(goal: goal) }
        stateTask = (task, goal, version)
        let value = await task.value
        if stateTask?.task == task {
            stateTask = nil
            stateEntry = (Entry(value: value, stamp: .now, version: version), goal)
        }
        return value
    }

    /// The trailing-window per-day energy totals (the heaviest scan the
    /// streak/month surfaces share), computed at most once per burst.
    public static func energyTotals() async -> [DayEnergyTotals] {
        let version = currentVersion()
        if isValid(totalsEntry, version: version) {
            return totalsEntry!.value
        }
        if let running = totalsTask, running.version == version {
            return await running.task.value
        }
        let task = Task { (try? await HealthKitService().dailyEnergyTotals()) ?? [] }
        totalsTask = (task, version)
        let value = await task.value
        if totalsTask?.task == task {
            totalsTask = nil
            totalsEntry = Entry(value: value, stamp: .now, version: version)
        }
        return value
    }

    /// Whether the Health permission sheet has never been shown — an XPC
    /// round trip every provider was repeating per reload.
    public static func needsSetup() async -> Bool {
        let version = currentVersion()
        if isValid(setupEntry, version: version) {
            return setupEntry!.value
        }
        if let running = setupTask, running.version == version {
            return await running.task.value
        }
        let task = Task { (try? await HealthKitService().shouldRequestAuthorization()) == true }
        setupTask = (task, version)
        let value = await task.value
        if setupTask?.task == task {
            setupTask = nil
            setupEntry = Entry(value: value, stamp: .now, version: version)
        }
        return value
    }
}
#endif
