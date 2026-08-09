import Testing
import Foundation
@testable import OnigiriKit

/// The two plan inputs the watch takes from the phone: the weight itself,
/// and the basis setting that says what that weight MEANS.
///
/// Both matter because `DailyPlanLoader.resolvedWeight` makes the phone's
/// synced weight WIN over the watch's own Health read, and the watch falls
/// back to computing its own basis once that value ages out. Sending the
/// raw last weigh-in while the phone planned from the 7-day mean of daily
/// lows therefore put a permanently different budget on the wrist than on
/// the screen — 316 kcal left vs 147, ~1.2 lb of basis at 3500/24 kcal per
/// pound (2026-08-08).
///
/// Serialized: these share defaults keys with each other and the cleanup
/// defers would race under parallel execution.
@Suite(.serialized)
struct PlanWeightSyncTests {
    private func clearBasis() {
        SharedStore.defaults.removeObject(forKey: SharedStore.weightBasisKey)
    }

    // MARK: - The cache the push reads

    @MainActor
    @Test func thePlanWeightCacheRoundTripsWithItsDay() {
        defer { SharedStore.defaults.removeObject(forKey: HealthKitService.planWeightCacheKey) }
        let now = Date.now
        HealthKitService.cachePlanWeight(212.4, now: now)
        let cached = HealthKitService.cachedPlanWeightLb()
        #expect(cached?.lb == 212.4)
        // Day-stamped, not time-stamped: an unchanged value must hash
        // identically or every push re-sends and the skip fingerprint dies.
        #expect(cached?.day == DeficitTargetHistory.dayKey(for: now))
    }

    @MainActor
    @Test func aWeightThatWentAwayClearsTheCache() {
        defer { SharedStore.defaults.removeObject(forKey: HealthKitService.planWeightCacheKey) }
        HealthKitService.cachePlanWeight(212.4, now: .now)
        // Every weigh-in deleted: a lingering cache would push a phantom
        // weight to the watch until the day window aged out.
        HealthKitService.cachePlanWeight(nil, now: .now)
        #expect(HealthKitService.cachedPlanWeightLb() == nil)
    }

    // MARK: - The basis setting

    @Test func theBasisAlwaysRidesWithItsResolvedValue() {
        defer { clearBasis() }
        clearBasis()
        // Absent resolves to the 7-day average — and the watch has to be
        // TOLD that, explicitly. A ride-only-when-set key would leave a
        // stale "last weigh-in" alive on the watch after a reset.
        #expect(WatchSync.planPreferencePairs.count == 1)
        #expect(WatchSync.planPreferencePairs.first?.0 == SharedStore.weightBasisKey)
        #expect(WatchSync.planPreferencePairs.first?.1 == WeightBasis.sevenDayAverage.rawValue)

        SharedStore.defaults.set(WeightBasis.lastWeighIn.rawValue, forKey: SharedStore.weightBasisKey)
        #expect(WatchSync.planPreferencePairs.first?.1 == WeightBasis.lastWeighIn.rawValue)
    }

    @Test func theBasisSurvivesTheWireIntoTheWatchsDefaults() {
        defer { clearBasis() }
        SharedStore.defaults.set(WeightBasis.lastWeighIn.rawValue, forKey: SharedStore.weightBasisKey)
        let context = WatchSync.makeContext(
            meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64,
            trackedMetricSettings: Dictionary(uniqueKeysWithValues: WatchSync.planPreferencePairs)
        )
        let payload = WatchSync.parse(context)
        #expect(payload.trackedMetricSettings?[SharedStore.weightBasisKey]
            == WeightBasis.lastWeighIn.rawValue)

        // The watch end. It is not a numeric slot key, so store() writes
        // it back as the string `SharedStore.weightBasis` reads — which is
        // what the watch's own `targetBasisWeightLb` consults when the
        // synced weight has aged out.
        clearBasis()
        #expect(SharedStore.weightBasis == .sevenDayAverage)
        WatchSync.store(SyncPayload(
            meals: nil, goal: .keep, waterServingOz: nil, waterGoalOz: nil,
            trackedMetricSettings: payload.trackedMetricSettings
        ))
        #expect(SharedStore.weightBasis == .lastWeighIn)
    }

    // MARK: - What the divergence cost

    /// The gap the fix closes, in the arithmetic that produced it: one
    /// basis, two weights, 3500/daysRemaining kcal per pound between them.
    @Test func twoWeightsForOneDayIsAWholeBudgetApart() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        let targetDate = calendar.date(byAdding: .day, value: 24, to: now)!

        func deficit(from weightLb: Double) -> Double {
            CalorieBudget.requiredDailyDeficit(
                currentWeightLb: weightLb, targetWeightLb: 210,
                targetDate: targetDate, calendar: calendar, now: now
            )!
        }
        // The phone's basis (mean of the week's daily lows) against the
        // raw morning weigh-in the watch was being sent.
        let apart = deficit(from: 213.4) - deficit(from: 212.2)
        #expect(abs(apart - 175) < 1)
    }
}
