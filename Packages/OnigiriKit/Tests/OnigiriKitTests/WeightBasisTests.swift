import Testing
import Foundation
@testable import OnigiriKit

/// The weight the deficit target is derived from (PLAN-target-weight-basis).
/// The formula's sensitivity is `3500 / daysRemaining` kcal per pound —
/// ~146 at 24 days out — so which reading feeds it is worth this much
/// test.
struct WeightBasisTests {
    /// Fixed clock: these assert windowing, so a wall-clock `now` would
    /// make them flaky at midnight.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    /// `daysAgo` days back, at `hour` local time.
    private func at(daysAgo: Int, hour: Int, _ lb: Double) -> WeightTrend.Point {
        let day = calendar.startOfDay(for: now.addingTimeInterval(-Double(daysAgo) * 86400))
        let stamp = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return WeightTrend.Point(date: stamp, weightLb: lb)
    }

    // MARK: - Daily lows

    /// The point of the whole feature: evening runs 2–3 lb high, so the
    /// morning reading is the comparable one.
    @Test func aDayWithMorningAndEveningKeepsTheMorning() {
        let points = [at(daysAgo: 1, hour: 7, 212.2), at(daysAgo: 1, hour: 21, 214.8)]
        let lows = WeightTrend.dailyLows(points, calendar: calendar)
        #expect(lows.count == 1)
        #expect(lows[0].weightLb == 212.2)
    }

    @Test func theKeptPointCarriesItsOwnTimestamp() {
        // Not the day's start — windowing has to stay exact.
        let morning = at(daysAgo: 1, hour: 7, 212.2)
        let lows = WeightTrend.dailyLows([morning, at(daysAgo: 1, hour: 21, 214.8)], calendar: calendar)
        #expect(lows[0].date == morning.date)
    }

    @Test func anEveningOnlyDayStillContributes() {
        // Accepted trade: it reads high, and the mean damps it. Dropping
        // the day entirely would be worse.
        let lows = WeightTrend.dailyLows([at(daysAgo: 2, hour: 22, 215.1)], calendar: calendar)
        #expect(lows.count == 1)
        #expect(lows[0].weightLb == 215.1)
    }

    @Test func daysAreCollapsedInTheGivenCalendar() {
        // 23:00 Pacific one day and 07:00 the next are DIFFERENT days
        // locally, even though they are hours apart — and would be one
        // UTC day if this used the wrong calendar.
        let points = [at(daysAgo: 2, hour: 23, 215.0), at(daysAgo: 1, hour: 7, 212.0)]
        #expect(WeightTrend.dailyLows(points, calendar: calendar).count == 2)
    }

    @Test func lowsComeBackDateAscending() {
        let points = [at(daysAgo: 1, hour: 7, 212.0), at(daysAgo: 5, hour: 7, 215.0),
                      at(daysAgo: 3, hour: 7, 214.0)]
        let lows = WeightTrend.dailyLows(points, calendar: calendar)
        #expect(lows.map(\.weightLb) == [215.0, 214.0, 212.0])
    }

    @Test func noReadingsYieldsNoLows() {
        #expect(WeightTrend.dailyLows([], calendar: calendar).isEmpty)
    }

    // MARK: - The basis

    /// THE REGRESSION THIS EXISTS FOR: adding evening weigh-ins must not
    /// move the basis. A mean over raw samples fails this.
    @Test func eveningWeighInsDoNotMoveTheBasis() {
        let mornings = (1...5).map { at(daysAgo: $0, hour: 7, 212.0 + Double($0) * 0.1) }
        let withEvenings = mornings + [at(daysAgo: 2, hour: 21, 215.0),
                                       at(daysAgo: 4, hour: 22, 215.4)]
        let clean = WeightTrend.targetBasisLb(mornings, now: now, calendar: calendar)
        let noisy = WeightTrend.targetBasisLb(withEvenings, now: now, calendar: calendar)
        #expect(clean != nil)
        #expect(abs((clean ?? 0) - (noisy ?? 0)) < 0.0001)

        // And the naive version this replaces DOES move — proving the
        // test has teeth rather than passing vacuously.
        let naiveClean = mornings.reduce(0) { $0 + $1.weightLb } / Double(mornings.count)
        let naiveNoisy = withEvenings.reduce(0) { $0 + $1.weightLb } / Double(withEvenings.count)
        #expect(abs(naiveClean - naiveNoisy) > 0.5)
    }

    @Test func theBasisIsTheMeanOfDailyLows() {
        let points = [at(daysAgo: 1, hour: 7, 212.0), at(daysAgo: 2, hour: 7, 214.0),
                      at(daysAgo: 3, hour: 7, 216.0)]
        let basis = WeightTrend.targetBasisLb(points, now: now, calendar: calendar)
        #expect(basis == 214.0)
    }

    /// A window of DAYS, not of readings — skipping days must not reach
    /// further back and silently widen it.
    @Test func theWindowIsDaysNotReadings() {
        let inside = [at(daysAgo: 1, hour: 7, 212.0), at(daysAgo: 2, hour: 7, 212.0)]
        let old = [at(daysAgo: 20, hour: 7, 230.0), at(daysAgo: 30, hour: 7, 240.0)]
        let basis = WeightTrend.targetBasisLb(inside + old, now: now, calendar: calendar)
        #expect(basis == 212.0)
    }

    @Test func aGapLongerThanTheWindowYieldsNil() {
        // Caller falls back to the raw latest.
        let stale = [at(daysAgo: 30, hour: 7, 230.0)]
        #expect(WeightTrend.targetBasisLb(stale, now: now, calendar: calendar) == nil)
        #expect(WeightTrend.targetBasisLb([], now: now, calendar: calendar) == nil)
    }

    @Test func aSingleRecentReadingIsItsOwnBasis() {
        let one = [at(daysAgo: 1, hour: 7, 212.2)]
        #expect(WeightTrend.targetBasisLb(one, now: now, calendar: calendar) == 212.2)
    }

    @Test func futureDatedReadingsAreIgnored() {
        // A watch/phone clock skew must not let tomorrow into the window.
        let points = [at(daysAgo: 1, hour: 7, 212.0), at(daysAgo: -2, hour: 7, 190.0)]
        #expect(WeightTrend.targetBasisLb(points, now: now, calendar: calendar) == 212.0)
    }

    // MARK: - Setting resolution

    @Test func absentSettingReadsAsSmoothed() {
        #expect(WeightBasis.resolve(nil) == .sevenDayAverage)
        #expect(WeightBasis.resolve("nonsense") == .sevenDayAverage)
        #expect(WeightBasis.resolve("lastWeighIn") == .lastWeighIn)
    }

    @Test func lastWeighInBasisIgnoresHistory() {
        let history = [at(daysAgo: 1, hour: 7, 212.0), at(daysAgo: 2, hour: 7, 216.0)]
        let resolved = WeightTrend.basisLb(
            .lastWeighIn, history: history, latestLb: 212.2, now: now, calendar: calendar)
        #expect(resolved == 212.2)
    }

    @Test func smoothedBasisFallsBackToLatestWhenUncomputable() {
        let resolved = WeightTrend.basisLb(
            .sevenDayAverage, history: [], latestLb: 212.2, now: now, calendar: calendar)
        #expect(resolved == 212.2)
        // Nothing at all to go on.
        #expect(WeightTrend.basisLb(
            .sevenDayAverage, history: [], latestLb: nil, now: now, calendar: calendar) == nil)
    }

    // MARK: - The protocol seam

    /// A conformer that implements nothing extra — every existing test
    /// double is one of these.
    private struct BareHealth: HealthPlanReading {
        let latest: Double?
        func todaySummary() async throws -> DailyEnergySummary { .zero }
        func latestBodyMassLb() async throws -> Double? { latest }
        func bodyProfile() async -> (heightCm: Double?, ageYears: Int?, sex: BasalEstimate.Sex) {
            (nil, nil, .unspecified)
        }
    }

    /// The default must degrade to the raw latest, not to nil — a
    /// surface that silently lost its weight would drop the deficit to
    /// zero and quote the full day's burn as the budget.
    @Test func theProtocolDefaultFallsBackToTheRawLatest() async {
        #expect(await BareHealth(latest: 212.2).targetBasisWeightLb() == 212.2)
        #expect(await BareHealth(latest: nil).targetBasisWeightLb() == nil)
    }

    // MARK: - The observed case, as a fixture

    /// 2026-08-08, screenshotted: 213.4 → 212.2 moved the deficit
    /// 497 → 323 and the budget 1,351 → 1,526. Pins the formula against
    /// numbers that were actually on screen.
    @Test func theObservedMorningJump() {
        let before = CalorieBudget.requiredDailyDeficit(
            currentWeightLb: 213.4, targetWeightLb: 210, daysRemaining: 24)
        let after = CalorieBudget.requiredDailyDeficit(
            currentWeightLb: 212.2, targetWeightLb: 210, daysRemaining: 24)
        #expect(abs(before - 496) < 2)
        #expect(abs(after - 321) < 2)
        // The budget moved by exactly the deficit's change: burn was flat.
        #expect(abs((before - after) - 175) < 3)
    }

    /// The sensitivity that makes the basis matter, stated as a test:
    /// 3500 / daysRemaining kcal per pound, growing as the date nears.
    @Test func sensitivityGrowsAsTheTargetDateApproaches() {
        func perPound(days: Int) -> Double {
            CalorieBudget.requiredDailyDeficit(currentWeightLb: 211, targetWeightLb: 210, daysRemaining: days)
        }
        #expect(abs(perPound(days: 24) - 145.8) < 0.5)
        #expect(abs(perPound(days: 12) - 291.7) < 0.5)
        #expect(abs(perPound(days: 5) - 700) < 0.5)
    }
}
