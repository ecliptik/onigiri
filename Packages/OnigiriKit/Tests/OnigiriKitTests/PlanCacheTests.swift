import Testing
import Foundation
@testable import OnigiriKit

#if canImport(HealthKit)
/// Counts invocations so a test can assert how many times the expensive
/// read actually ran — the thing `PlanCache` exists to bound. `delay`
/// lets a test force a real suspension, which is what makes the
/// coalescing test deterministic instead of racing the scheduler.
///
/// Reports a SEALED-AND-RECENT read (nil weight, a fresh cached day) on
/// purpose: `DailyPlanLoader.load` stamps `DeficitTargetHistory` — a
/// process-global default other suites (`DeficitTargetHistoryTests`)
/// read and write concurrently — for any read `HealthReadTrust
/// .mayStampPlan` doesn't recognize as sealed, and this suite has
/// nothing to do with that history. Only a real, non-maintenance goal
/// with no fallback weight actually reaches the sealed check at all
/// (a nil goal or a maintenance one short-circuits `mayStampPlan` to
/// "always stamp" before the weight signal is even considered) — see
/// `sealedGoal` below.
@MainActor
private final class CountingHealth: HealthPlanReading {
    private(set) var callCount = 0
    var delay: Duration = .zero

    func todaySummary() async throws -> DailyEnergySummary {
        callCount += 1
        if delay > .zero { try? await Task.sleep(for: delay) }
        return .zero
    }
    func latestBodyMassLb() async throws -> Double? { nil }
    func bodyProfile() async -> (heightCm: Double?, ageYears: Int?, sex: BasalEstimate.Sex) {
        (nil, nil, .unspecified)
    }
    func lastGoodWeightDay() -> String? {
        DeficitTargetHistory.dayKey(for: .now, calendar: .current)
    }
}

/// A weight-loss goal with no fallback weight, paired with
/// `CountingHealth`'s nil `latestBodyMassLb()`, so `currentWeightLb`
/// resolves to nil — `deficitTargetKcal` comes back nil, `hasWeightGoal`
/// is true, and together they route `mayStampPlan` into the sealed
/// check (which the stub's fresh `lastGoodWeightDay()` satisfies)
/// instead of its "always stamp" shortcut.
@MainActor
private func sealedGoal(targetWeightLb: Double = 150) -> SyncedGoal {
    SyncedGoal(
        targetWeightLb: targetWeightLb,
        targetDate: Date.now.addingTimeInterval(86400 * 30),
        fallbackCurrentWeightLb: nil)
}

/// The health-check audit's coverage gap: this cache's TTL, cross-
/// process-version, and task-coalescing behavior had zero tests, in the
/// exact subsystem CLAUDE.md documents as the most historically
/// bug-prone (the sealed-store-renders-as-zero class). `state(goal:)`
/// is where that risk actually lives — `energyTotals`/`needsSetup`
/// construct `HealthKitService()` with no injection seam of their own
/// and are out of scope here.
///
/// Serialized: `PlanCache`'s entries are process-global static state.
@MainActor
@Suite(.serialized)
struct PlanCacheTests {
    init() { PlanCache.invalidate() }

    @Test func aSecondCallWithinTTLReusesTheCachedValueInsteadOfRereading() async {
        let health = CountingHealth()
        let goal = sealedGoal()
        _ = await PlanCache.state(goal: goal, health: health)
        _ = await PlanCache.state(goal: goal, health: health)
        #expect(health.callCount == 1, "the second call landed inside the TTL — it must reuse, not re-read")
    }

    @Test func invalidateForcesTheNextCallToRereadEvenWithinTTL() async {
        let health = CountingHealth()
        let goal = sealedGoal()
        _ = await PlanCache.state(goal: goal, health: health)
        PlanCache.invalidate()
        _ = await PlanCache.state(goal: goal, health: health)
        #expect(health.callCount == 2, "invalidate() must defeat the TTL — a mutation happened, not just time passing")
    }

    @Test func differentGoalsDoNotShareAnEntry() async {
        let health = CountingHealth()
        _ = await PlanCache.state(goal: sealedGoal(targetWeightLb: 150), health: health)
        _ = await PlanCache.state(goal: sealedGoal(targetWeightLb: 140), health: health)
        #expect(health.callCount == 2, "a cached entry for one goal must not answer for a different one")
    }

    @Test func concurrentCallsForTheSameGoalCoalesceIntoOneRead() async {
        let health = CountingHealth()
        let goal = sealedGoal()
        // Long enough that the second call below is guaranteed to start
        // while the first is still in flight and observe it, rather than
        // racing whether the scheduler interleaves a trivially-fast async
        // call.
        health.delay = .milliseconds(50)
        async let first = PlanCache.state(goal: goal, health: health)
        async let second = PlanCache.state(goal: goal, health: health)
        _ = await (first, second)
        #expect(health.callCount == 1, "two in-flight calls for the same goal must share one read, not run it twice")
    }
}
#endif
