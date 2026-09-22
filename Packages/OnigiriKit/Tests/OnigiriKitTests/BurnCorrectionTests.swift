import Foundation
import Testing
@testable import OnigiriKit

/// The burn correction (`plans/PLAN-burn-correction.md`): a flat,
/// person-accepted kcal/day offset on every day's burn. These pin the
/// rules the plan names — and, first, the one that protects every other
/// test in this package: a correction of 0 changes nothing, anywhere.
@MainActor
struct BurnCorrectionTests {
    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!

    private static func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    // MARK: - Zero is byte-identical

    /// Bitwise, not approximately: an `x + 0.0` or a clamp against a 0
    /// cap would still compare equal with `==` on most inputs, and the
    /// point is that the zero path does not run the arithmetic at all.
    @Test func zeroIsByteIdenticalOnEveryPath() {
        let cases: [(Double, Double, Double?)] = [
            (0, 0, nil), (50, 800, 1_800), (400, 2_000, 1_800),
            (300.123456789, 1_900.987654321, nil), (0, 2_000, 1_850),
        ]
        for (active, resting, estimate) in cases {
            let uncorrected = DayBudget.uncorrectedDayBurn(
                activeKcal: active, restingKcal: resting, estimatedRestingKcal: estimate)
            let corrected = DayBudget.dayBurn(
                activeKcal: active, restingKcal: resting,
                estimatedRestingKcal: estimate, burnCorrectionKcal: 0)
            #expect(corrected.bitPattern == uncorrected.bitPattern)
            // The pre-parameter formula, spelled out: what every existing
            // test was written against.
            #expect(corrected.bitPattern == (active + max(resting, estimate ?? 0)).bitPattern)
        }
    }

    /// The assembly every widget, the watch and the intents render.
    /// Everything but the new field must come out identical, and the new
    /// field must say "nothing" as an exact zero.
    @Test func zeroLeavesThePlanStateUntouched() {
        let summary = DailyEnergySummary(
            intakeKcal: 1_250.5, activeBurnKcal: 400.25, restingBurnKcal: 2_000.75,
            sodiumMg: 0, waterOz: 0)
        let goal = SyncedGoal(
            targetWeightLb: 170,
            targetDate: Self.cal.date(byAdding: .day, value: 40, to: Self.now)!,
            fallbackCurrentWeightLb: nil)
        for floor: Double? in [nil, 2_500.5] {
            let before = DailyPlanLoader.makeState(
                goal: goal, summary: summary, estimatedRestingKcal: 1_800,
                healthWeightLb: 183, todayBurnFloorKcal: floor,
                calendar: Self.cal, now: Self.now)
            let after = DailyPlanLoader.makeState(
                goal: goal, summary: summary, estimatedRestingKcal: 1_800,
                healthWeightLb: 183, todayBurnFloorKcal: floor,
                burnCorrectionKcal: 0,
                calendar: Self.cal, now: Self.now)
            #expect(after.dayBurnKcal?.bitPattern == before.dayBurnKcal?.bitPattern)
            #expect(after.dailyBudgetKcal?.bitPattern == before.dailyBudgetKcal?.bitPattern)
            #expect(after.gaugeProgress.bitPattern == before.gaugeProgress.bitPattern)
            #expect(after.creditedActiveKcal?.bitPattern == before.creditedActiveKcal?.bitPattern)
            #expect(after.creditedRestingKcal?.bitPattern == before.creditedRestingKcal?.bitPattern)
            #expect(after.creditedCorrectionKcal == 0)
        }
    }

    // MARK: - Applying it

    @Test func aCorrectionSubtractsFromTheDaysBurn() {
        // 400 active + 2,000 resting, less 300.
        let burn = DayBudget.dayBurn(
            activeKcal: 400, restingKcal: 2_000, estimatedRestingKcal: 1_800,
            burnCorrectionKcal: -300)
        #expect(burn == 2_100)
    }

    /// It is a term of its own, so no channel can go negative — the
    /// failure that ruled out folding it into active: 310 − 300 is 10,
    /// and a zero-active day would read below zero.
    @Test func noChannelIsTakenBelowZero() {
        let state = DailyPlanLoader.makeState(
            goal: SyncedGoal(targetWeightLb: 200, targetDate: Self.now,
                             fallbackCurrentWeightLb: nil, mode: GoalMode.maintain),
            summary: DailyEnergySummary(
                intakeKcal: 0, activeBurnKcal: 0, restingBurnKcal: 2_100,
                sodiumMg: 0, waterOz: 0),
            estimatedRestingKcal: 1_800, healthWeightLb: nil,
            burnCorrectionKcal: -300,
            calendar: Self.cal, now: Self.now)
        #expect(state.creditedActiveKcal == 0)
        #expect(state.creditedRestingKcal == 2_100)
        #expect(state.creditedCorrectionKcal == -300)
    }

    /// Resting has a floor so a day never credits less than the body
    /// at rest; a correction does not get to breach it. On a partial
    /// morning — resting credited from the estimate, little active —
    /// the floor holds and only part of the correction lands.
    @Test func neverBelowTheRestingEstimate() {
        let burn = DayBudget.dayBurn(
            activeKcal: 50, restingKcal: 800, estimatedRestingKcal: 1_800,
            burnCorrectionKcal: -300)
        #expect(burn == 1_800)
        // Without an estimate there is nothing to floor at but zero.
        #expect(DayBudget.dayBurn(
            activeKcal: 0, restingKcal: 100, estimatedRestingKcal: nil,
            burnCorrectionKcal: -300) == 80)  // capped at 20% of 100
    }

    @Test func clampedToTwentyPercentOfTheBurn() {
        let burn = DayBudget.dayBurn(
            activeKcal: 500, restingKcal: 2_000, estimatedRestingKcal: nil,
            burnCorrectionKcal: -1_000)
        #expect(burn == 2_000)  // 2,500 − 20% × 2,500
        let up = DayBudget.dayBurn(
            activeKcal: 500, restingKcal: 2_000, estimatedRestingKcal: nil,
            burnCorrectionKcal: 1_000)
        #expect(up == 3_000)
    }

    /// The card has to ADD UP: Active + Resting + Correction is the burn
    /// the budget was cut from, to the kcal, ratcheted or not.
    @Test func theSplitAddsUpWithACorrectionLive() throws {
        let goal = SyncedGoal(
            targetWeightLb: 170,
            targetDate: Self.cal.date(byAdding: .day, value: 40, to: Self.now)!,
            fallbackCurrentWeightLb: nil)
        let summary = DailyEnergySummary(
            intakeKcal: 1_200, activeBurnKcal: 400, restingBurnKcal: 2_000,
            sodiumMg: 0, waterOz: 0)
        for floor: Double? in [nil, 2_600] {
            let state = DailyPlanLoader.makeState(
                goal: goal, summary: summary, estimatedRestingKcal: 1_800,
                healthWeightLb: 183, todayBurnFloorKcal: floor,
                burnCorrectionKcal: -300,
                calendar: Self.cal, now: Self.now)
            let active = try #require(state.creditedActiveKcal)
            let resting = try #require(state.creditedRestingKcal)
            let correction = try #require(state.creditedCorrectionKcal)
            #expect(active + resting + correction == state.dayBurnKcal)
            #expect(correction == -300)
        }
    }

    /// The ratchet guards the MEASUREMENT; the correction applies after
    /// it. Otherwise a correction accepted at noon would sit under the
    /// morning's uncorrected high mark until midnight.
    @Test func appliesOnTopOfTheRatchet() {
        let state = DailyPlanLoader.makeState(
            goal: SyncedGoal(targetWeightLb: 200, targetDate: Self.now,
                             fallbackCurrentWeightLb: nil, mode: GoalMode.maintain),
            summary: DailyEnergySummary(
                intakeKcal: 0, activeBurnKcal: 300, restingBurnKcal: 1_900,
                sodiumMg: 0, waterOz: 0),
            estimatedRestingKcal: 1_800, healthWeightLb: nil,
            todayBurnFloorKcal: 2_400,  // an earlier, higher read
            burnCorrectionKcal: -300,
            calendar: Self.cal, now: Self.now)
        #expect(state.dayBurnKcal == 2_100)
    }

    // MARK: - History

    /// Decision 1: it re-grades history. A −300 correction across 60
    /// tracked days takes 18,000 kcal off "Total deficit", landing it on
    /// what the scale actually lost.
    @Test func totalDeficitLandsOnTheMeasuredLoss() {
        // 60 days, burn 2,600, eating 1,600 ⇒ 1,000/day banked on
        // Health's burn: 60,000 kcal ≈ 17.1 lb.
        let correction = -300.0
        let totals = (1...60).map { offset -> DayEnergyTotals in
            let measured = 2_600.0
            let burn = BurnCorrection.apply(
                toBurnKcal: measured, estimatedRestingKcal: 1_800, correctionKcal: correction)
            return DayEnergyTotals(
                day: Self.day(-offset), intakeKcal: 1_600, burnKcal: burn,
                correctionKcal: burn - measured)
        }
        let stats = GoalTrendStats.derive(
            weightHistory: [], dailyTotals: totals,
            targetWeightLb: nil, isMaintenance: false, untrackedBelowKcal: 500,
            calendar: Self.cal, now: Self.now)
        #expect(stats.bankedKcal == 60_000 + correction * 60)
        // (1,000 − 300) × 60 / 3,500 = 12.0 lb — the measured loss.
        #expect(abs(stats.bankedLb - 12.0) < 0.01)
    }

    // MARK: - The suggestion

    /// Suggested from ALL completed tracked days, off UNCORRECTED burn.
    @Test func suggestionReadsEveryTrackedDayAgainstTheScale() throws {
        // 60 completed days eating 2,000 against a measured 2,600, while
        // the scale drops 1/14 lb/day (≈ 250 kcal/day of real deficit).
        let totals = (1...60).map {
            DayEnergyTotals(day: Self.day(-$0), intakeKcal: 2_000, burnKcal: 2_600)
        }
        let history = (0...60).map {
            WeightTrend.Point(date: Self.day(-60 + $0), weightLb: 180 - Double($0) / 14)
        }
        let s = try #require(BurnCorrection.suggest(
            dailyTotals: totals, weightHistory: history, untrackedBelowKcal: 500,
            calendar: Self.cal, now: Self.now))
        // Scale burn 2,250; measured 2,600 ⇒ −350.
        #expect(s.kcalPerDay == -350)
        #expect(s.trackedDays == 60)
        #expect(s.since == Self.day(-60))
        #expect(abs(s.scaleBurnKcal - 2_250) < 1)
        #expect(s.measuredBurnKcal == 2_600)
    }

    /// Once a correction is live the totals carry it; the suggestion must
    /// still answer "how much", not "how much more", or it drifts to zero
    /// the moment it is accepted.
    @Test func suggestionIgnoresALiveCorrection() throws {
        let history = (0...60).map {
            WeightTrend.Point(date: Self.day(-60 + $0), weightLb: 180 - Double($0) / 14)
        }
        let corrected = (1...60).map {
            DayEnergyTotals(day: Self.day(-$0), intakeKcal: 2_000, burnKcal: 2_300,
                            correctionKcal: -300)
        }
        let s = try #require(BurnCorrection.suggest(
            dailyTotals: corrected, weightHistory: history, untrackedBelowKcal: 500,
            calendar: Self.cal, now: Self.now))
        #expect(s.kcalPerDay == -350)
    }

    @Test func suggestionIsSilentUnderTheMinimumOrNearZero() {
        let history = (0...60).map {
            WeightTrend.Point(date: Self.day(-60 + $0), weightLb: 180 - Double($0) / 14)
        }
        let thin = (1..<ObservedBurn.minimumTrackedDays).map {
            DayEnergyTotals(day: Self.day(-$0), intakeKcal: 2_000, burnKcal: 2_600)
        }
        #expect(BurnCorrection.suggest(
            dailyTotals: thin, weightHistory: history, untrackedBelowKcal: 500,
            calendar: Self.cal, now: Self.now) == nil)
        // Health agreeing with the scale to within 50 kcal: no offer.
        let agreeing = (1...60).map {
            DayEnergyTotals(day: Self.day(-$0), intakeKcal: 2_000, burnKcal: 2_270)
        }
        #expect(BurnCorrection.suggest(
            dailyTotals: agreeing, weightHistory: history, untrackedBelowKcal: 500,
            calendar: Self.cal, now: Self.now) == nil)
    }

    /// Today is half a day — resting credited up front, intake half
    /// logged — and stays out of the calibration.
    @Test func suggestionLeavesTodayOut() throws {
        let history = (0...60).map {
            WeightTrend.Point(date: Self.day(-60 + $0), weightLb: 180 - Double($0) / 14)
        }
        let past = (1...60).map {
            DayEnergyTotals(day: Self.day(-$0), intakeKcal: 2_000, burnKcal: 2_600)
        }
        let today = DayEnergyTotals(day: Self.day(0), intakeKcal: 600, burnKcal: 1_900)
        let s = try #require(BurnCorrection.suggest(
            dailyTotals: past + [today], weightHistory: history, untrackedBelowKcal: 500,
            calendar: Self.cal, now: Self.now))
        #expect(s.trackedDays == 60)
        #expect(s.kcalPerDay == -350)
    }
}

/// The stored value, which is shared defaults state — serialized for the
/// same reason `PlanWeightSyncTests` is.
@Suite(.serialized)
@MainActor
struct BurnCorrectionStorageTests {
    private func restore(_ kcal: Double, _ at: Double) {
        SharedStore.defaults.set(kcal, forKey: SharedStore.burnCorrectionKcalKey)
        SharedStore.defaults.set(at, forKey: SharedStore.burnCorrectionSetAtKey)
    }

    /// It never recomputes itself. A derive that moves the SUGGESTION —
    /// here a new month of logging that changes what the scale implies —
    /// must leave the stored correction exactly where a person put it.
    @Test func theStoredCorrectionSurvivesARefreshThatMovesTheSuggestion() throws {
        let savedKcal = SharedStore.defaults.double(forKey: SharedStore.burnCorrectionKcalKey)
        let savedAt = SharedStore.defaults.double(forKey: SharedStore.burnCorrectionSetAtKey)
        defer { restore(savedKcal, savedAt) }
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        SharedStore.setBurnCorrection(kcal: -300, now: stamp)

        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!
        let start = cal.startOfDay(for: now)
        func day(_ o: Int) -> Date { cal.date(byAdding: .day, value: o, to: start)! }
        let history = (0...60).map {
            WeightTrend.Point(date: day(-60 + $0), weightLb: 180 - Double($0) / 14)
        }
        for burn in [2_600.0, 2_400.0] {
            let totals = (1...60).map {
                DayEnergyTotals(day: day(-$0), intakeKcal: 2_000, burnKcal: burn)
            }
            let stats = GoalTrendStats.derive(
                weightHistory: history, dailyTotals: totals,
                targetWeightLb: 170, isMaintenance: false, untrackedBelowKcal: 500,
                calendar: cal, now: now)
            #expect(stats.burnCorrectionSuggestion != nil)
            _ = DailyPlanLoader.makeState(
                goal: nil, summary: .zero, estimatedRestingKcal: nil, healthWeightLb: nil,
                burnCorrectionKcal: SharedStore.burnCorrectionKcal)
            #expect(SharedStore.burnCorrectionKcal == -300)
            #expect(SharedStore.burnCorrectionSetAt == stamp)
        }
    }

    @Test func clearingDropsTheStamp() {
        let savedKcal = SharedStore.defaults.double(forKey: SharedStore.burnCorrectionKcalKey)
        let savedAt = SharedStore.defaults.double(forKey: SharedStore.burnCorrectionSetAtKey)
        defer { restore(savedKcal, savedAt) }
        SharedStore.setBurnCorrection(kcal: -300)
        #expect(SharedStore.burnCorrectionSetAt != nil)
        SharedStore.setBurnCorrection(kcal: 0)
        #expect(SharedStore.burnCorrectionKcal == 0)
        #expect(SharedStore.burnCorrectionSetAt == nil)
    }

    /// Both keys ride the watch sync with an explicit value, 0 included,
    /// and land back as the Doubles `SharedStore` reads. A correction
    /// only one device applies is two budgets for one day.
    @Test func bothKeysRideTheWatchSyncExplicitly() {
        let savedKcal = SharedStore.defaults.double(forKey: SharedStore.burnCorrectionKcalKey)
        let savedAt = SharedStore.defaults.double(forKey: SharedStore.burnCorrectionSetAtKey)
        defer { restore(savedKcal, savedAt) }

        // Off: still sent, as an explicit zero, so a watch holding an
        // old correction is told to drop it.
        SharedStore.setBurnCorrection(kcal: 0)
        let offPairs = Dictionary(uniqueKeysWithValues: WatchSync.planPreferencePairs)
        #expect(offPairs[SharedStore.burnCorrectionKcalKey] == "0.0")
        #expect(offPairs[SharedStore.burnCorrectionSetAtKey] == "0.0")

        let stamp = Date(timeIntervalSince1970: 1_790_000_123.456)
        SharedStore.setBurnCorrection(kcal: -300, now: stamp)
        let context = WatchSync.makeContext(
            meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64,
            trackedMetricSettings: Dictionary(uniqueKeysWithValues: WatchSync.planPreferencePairs))
        let payload = WatchSync.parse(context)

        // The watch end: wipe, then store what arrived.
        SharedStore.setBurnCorrection(kcal: 0)
        WatchSync.store(SyncPayload(
            meals: nil, goal: .keep, waterServingOz: nil, waterGoalOz: nil,
            trackedMetricSettings: payload.trackedMetricSettings))
        #expect(SharedStore.burnCorrectionKcal == -300)
        #expect(SharedStore.burnCorrectionSetAt == stamp)
    }
}
