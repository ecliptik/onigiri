import Testing
import Foundation
@testable import OnigiriKit

/// The replacement for `isStoreLocked()`, which could not work: a sealed
/// HealthKit store is allowed to answer EMPTY rather than throw, and an
/// empty result is indistinguishable from "no samples" through that API.
/// So the question changed from "did a probe throw" to "does this result
/// contradict something we know was there a moment ago".
@Suite(.serialized)
struct HealthReadTrustTests {
    private let calendar = Calendar.current
    private let now = Date.now

    private func day(_ offset: Int) -> String {
        DeficitTargetHistory.dayKey(
            for: calendar.date(byAdding: .day, value: offset, to: now)!, calendar: calendar)
    }

    @Test func aWeightInHandIsProofTheStoreAnswered() {
        #expect(!HealthReadTrust.looksSealed(
            weightLb: 212.4, cachedDay: day(0), calendar: calendar, now: now))
        // Even with nothing cached — the read itself is the evidence.
        #expect(!HealthReadTrust.looksSealed(
            weightLb: 212.4, cachedDay: nil, calendar: calendar, now: now))
    }

    /// The case the old probe called "open": every channel empty while a
    /// weight was read minutes earlier. Observed three times on 08-08.
    @Test func nilBesideARecentWeightIsASealedRead() {
        #expect(HealthReadTrust.looksSealed(
            weightLb: nil, cachedDay: day(0), calendar: calendar, now: now))
        #expect(HealthReadTrust.looksSealed(
            weightLb: nil, cachedDay: day(-1), calendar: calendar, now: now))
    }

    /// A user with no weigh-ins at all must be BELIEVED, or every surface
    /// freezes on a stale snapshot and never recovers.
    @Test func nilWithNothingCachedIsAnHonestAbsence() {
        #expect(!HealthReadTrust.looksSealed(
            weightLb: nil, cachedDay: nil, calendar: calendar, now: now))
    }

    /// And deleting every weigh-in must stop reading as "sealed" once the
    /// cache ages past the window — otherwise the freeze is permanent.
    @Test func aStaleCacheStopsVouchingForTheAbsence() {
        #expect(!HealthReadTrust.looksSealed(
            weightLb: nil, cachedDay: day(-2), calendar: calendar, now: now))
        #expect(!HealthReadTrust.looksSealed(
            weightLb: nil, cachedDay: day(-30), calendar: calendar, now: now))
    }

    // MARK: - The cache that supplies the evidence

    /// A sealed read must not clear a recent cache. Clearing it would
    /// throw away good data, stop the watch push carrying any weight, and
    /// destroy the evidence the NEXT nil is judged against — the check
    /// would quietly disarm itself after one bad read.
    @MainActor
    @Test func aSealedReadKeepsTheRecentCache() {
        defer { SharedStore.defaults.removeObject(forKey: HealthKitService.planWeightCacheKey) }
        HealthKitService.cachePlanWeight(212.4, now: now)
        HealthKitService.cachePlanWeight(nil, now: now)
        #expect(HealthKitService.cachedPlanWeightLb()?.lb == 212.4)
    }

    /// But a nil against an already-stale cache clears it: by then the
    /// absence is real, and a lingering value would push a phantom weight
    /// to the watch long after the scale stopped saying it.
    @MainActor
    @Test func aNilAgainstAStaleCacheClearsIt() {
        defer { SharedStore.defaults.removeObject(forKey: HealthKitService.planWeightCacheKey) }
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!
        HealthKitService.cachePlanWeight(212.4, now: threeDaysAgo)
        HealthKitService.cachePlanWeight(nil, now: now)
        #expect(HealthKitService.cachedPlanWeightLb() == nil)
    }
}
