import Foundation
import Testing
@testable import OnigiriKit

/// The finish line: one weight behind every verdict about where a goal
/// stands. See `GoalFinishLine` for the screen that made this necessary.
struct GoalFinishLineTests {
    static let cal = Calendar(identifier: .gregorian)
    /// Local NOON, deliberately. `recentDailyLows` windows on
    /// `date <= now`, so a `now` that lands near local midnight puts
    /// this morning's 7am weigh-in in the FUTURE and silently drops a
    /// day — which reads as "not enough weigh-ins" and quietly turns
    /// every state assertion below into a pass for the wrong reason.
    static let now = cal
        .startOfDay(for: Date(timeIntervalSince1970: 1_786_000_000))
        .addingTimeInterval(12 * 3600)

    /// `daysAgo` back from `now`, at a fixed hour so daily-low bucketing
    /// is unambiguous.
    static func day(_ daysAgo: Int, hour: Int = 7) -> Date {
        let midnight = cal.startOfDay(for: now.addingTimeInterval(-Double(daysAgo) * 86400))
        return midnight.addingTimeInterval(Double(hour) * 3600)
    }

    static func history(_ readings: [(daysAgo: Int, lb: Double)]) -> [WeightTrend.Point] {
        readings
            .map { WeightTrend.Point(date: day($0.daysAgo), weightLb: $0.lb) }
            .sorted { $0.date < $1.date }
    }

    static func evaluate(_ history: [WeightTrend.Point], target: Double) -> GoalFinishLine {
        GoalFinishLine.evaluate(
            targetLb: target, history: history, now: now, calendar: cal)
    }

    // MARK: - The screen that caused this

    /// 2026-08-14, screenshotted. A 209.8 lb morning against a 210 lb
    /// target, with the week's daily lows still averaging above it.
    ///
    /// The old screen answered this three ways at once: an orange
    /// "Target must be below your current weight." (raw weigh-in), a
    /// full progress bar reading 8.9 of 8.7 lb (raw weigh-in), and no
    /// celebration (basis). One state now, and it is neither of the two
    /// the app used to have.
    @Test func theAugustFourteenthScreen() throws {
        let readings = Self.history([
            (6, 212.0), (5, 211.4), (4, 211.0), (3, 210.7),
            (2, 210.4), (1, 210.1), (0, 209.8),
        ])
        // The morning reading is BELOW the target — which is what fired
        // the orange warning — while the week it belongs to is not.
        #expect(readings.last?.weightLb == 209.8)
        let basis = try #require(
            WeightTrend.targetBasisLb(readings, now: Self.now, calendar: Self.cal))
        // Above the target, so NOT reached...
        #expect(basis > 210)
        guard case .approaching(let reported, let remaining) = Self.evaluate(readings, target: 210)
        else {
            Issue.record("expected .approaching, got \(Self.evaluate(readings, target: 210))")
            return
        }
        // ...and the state reports the same basis the budget plans from,
        // not the 209.8 the scale said this morning.
        #expect(abs(reported - basis) < 0.001)
        #expect(reported != 209.8)
        #expect(abs(remaining - (basis - 210)) < 0.001)
        #expect(remaining > 0 && remaining < GoalFinishLine.bandLb)
    }

    // MARK: - The three states

    @Test func wellAboveTargetIsStillUnderWay() {
        let readings = Self.history([(2, 216), (1, 215.5), (0, 215)])
        #expect(Self.evaluate(readings, target: 210) == .underWay)
    }

    @Test func theBandIsExclusiveAtItsEdge() {
        // A basis exactly one pound out is still under way — the band is
        // "inside the last pound", and `requiredDailyDeficit` keeps
        // charging a deficit at exactly that gap for the same reason.
        let atBand = Self.history([(2, 211), (1, 211), (0, 211)])
        #expect(Self.evaluate(atBand, target: 210) == .underWay)
        let insideBand = Self.history([(2, 210.9), (1, 210.9), (0, 210.9)])
        #expect(Self.evaluate(insideBand, target: 210).isAtOrNearTarget)
        #expect(!Self.evaluate(insideBand, target: 210).isReached)
    }

    @Test func theSustainedBasisAtOrBelowTargetIsReached() {
        let readings = Self.history([(2, 209.6), (1, 209.9), (0, 209.5)])
        let state = Self.evaluate(readings, target: 210)
        #expect(state.isReached)
        #expect(state.isAtOrNearTarget)
        guard case .reached(let completion) = state else {
            Issue.record("expected .reached")
            return
        }
        #expect(completion.isMet)
        #expect(!completion.usedWiderWindow)
    }

    /// One lucky morning is not an arrival — the rule `GoalCompletion`
    /// already enforces, restated here so the finish line can never
    /// acquire a second opinion about it.
    @Test func oneLowMorningUnderAWeekOfHigherOnesIsNotReached() {
        let readings = Self.history([
            (6, 213), (5, 213), (4, 212.8), (3, 212.5),
            (2, 212.4), (1, 212.2), (0, 208.0),
        ])
        #expect(Self.evaluate(readings, target: 210) == .underWay)
    }

    /// Too few weigh-in days to average: no verdict, not a guess.
    @Test func tooFewWeighInDaysStaysUnderWay() {
        let readings = Self.history([(1, 205), (0, 204)])
        #expect(Self.evaluate(readings, target: 210) == .underWay)
        #expect(Self.evaluate([], target: 210) == .underWay)
    }

    /// A weekly weigher reaches the finish line through the widened
    /// window, exactly as the celebration does.
    @Test func aWeeklyWeigherStillReachesIt() {
        let readings = Self.history([(21, 209), (14, 208.5), (7, 208)])
        let state = Self.evaluate(readings, target: 210)
        #expect(state.isReached)
        guard case .reached(let completion) = state else { return }
        #expect(completion.usedWiderWindow)
    }

    @Test func anUnsetTargetHasNoFinishLine() {
        let readings = Self.history([(2, 209), (1, 209), (0, 209)])
        #expect(Self.evaluate(readings, target: 0) == .underWay)
    }

    // MARK: - The chart line and the budget basis are the same number

    /// The property the drawn line had never had. Its right-hand end
    /// must equal the "Weight" figure under "How the budget is set", or the
    /// eye reads one number while the plan uses another — 212 drawn
    /// against a ~210.8 basis (the user, 2026-08-14).
    ///
    /// Evening readings in the fixture on purpose: they are exactly what
    /// pulled the raw-sample average up and what the daily-low average
    /// ignores.
    @Test func theSmoothedLineEndsOnTheBudgetBasis() throws {
        let readings = [
            (6, 7, 212.4), (6, 20, 214.9),
            (5, 7, 211.8),
            (4, 7, 211.2), (4, 21, 213.6),
            (3, 7, 210.9),
            (2, 7, 210.6), (2, 19, 213.0),
            (1, 7, 210.4),
            (0, 7, 209.8),
        ].map { (daysAgo, hour, lb) in
            WeightTrend.Point(date: Self.day(daysAgo, hour: hour), weightLb: lb)
        }.sorted { $0.date < $1.date }

        let lows = WeightTrend.dailyLows(readings, calendar: Self.cal)
        let line = WeightTrend.movingAverage(lows, windowDays: 7)
        let lineEnd = try #require(line.last?.weightLb)
        // The budget's own basis, read at the last weigh-in's moment so
        // both windows cover the same days.
        let lastLowAt = try #require(lows.last?.date)
        let basis = try #require(WeightTrend.targetBasisLb(
            readings, now: lastLowAt, calendar: Self.cal))
        #expect(abs(lineEnd - basis) < 0.001)

        // And the raw-sample average this replaced does NOT — the whole
        // defect, pinned so it cannot come back.
        let rawLine = WeightTrend.movingAverage(readings, windowDays: 7)
        let rawEnd = try #require(rawLine.last?.weightLb)
        #expect(rawEnd > lineEnd + 0.5)
    }

    // MARK: - Journey continuity

    @Test func loweringATargetKeepsTheJourney() {
        #expect(JourneyContinuity.continuesJourney(
            oldTargetLb: 210, newTargetLb: 200, progressLb: 8.9))
    }

    @Test func raisingATargetStartsANewJourney() {
        #expect(!JourneyContinuity.continuesJourney(
            oldTargetLb: 210, newTargetLb: 220, progressLb: 8.9))
    }

    @Test func aJourneyWithNothingBehindItIsNotWorthPreserving() {
        #expect(!JourneyContinuity.continuesJourney(
            oldTargetLb: 210, newTargetLb: 200, progressLb: 0))
        // Below `minimumJourneyLb` a derived start can sit a hair above
        // the target by coincidence — nothing to carry forward.
        #expect(!JourneyContinuity.continuesJourney(
            oldTargetLb: 210, newTargetLb: 200, progressLb: 0.4))
        // And a goal that never had a target can't continue one.
        #expect(!JourneyContinuity.continuesJourney(
            oldTargetLb: 0, newTargetLb: 200, progressLb: 8.9))
    }

    // MARK: - The band, in the budget

    /// Inside the band the deficit is 0 rather than a jittery few
    /// hundred kcal that falls off a cliff a morning later.
    @Test func theBandZeroesTheDeficitInsideTheLastPound() {
        // 0.8 lb out, 18 days left: 156 kcal/day before the band.
        #expect(CalorieBudget.requiredDailyDeficit(
            currentWeightLb: 210.8, targetWeightLb: 210, daysRemaining: 18) == 0)
        // A full pound out still plans, so the documented
        // 3500/daysRemaining sensitivity is unchanged above the band.
        #expect(abs(CalorieBudget.requiredDailyDeficit(
            currentWeightLb: 211, targetWeightLb: 210, daysRemaining: 18) - 194.4) < 0.5)
    }

    /// And the band cannot make the two screens disagree: it lives in
    /// the one function Today, the widget, the watch and the snapshots
    /// all call.
    @Test func aGoalAtTargetPlansAZeroDeficitRatherThanNoPlan() throws {
        let targetDate = Self.cal.date(byAdding: .day, value: 18, to: Self.now)!
        let plan = try #require(CalorieBudget.derivePlan(
            isMaintenance: false,
            currentWeightLb: 210.8, targetWeightLb: 210, targetDate: targetDate,
            averageDailyBurnKcal: 2_600,
            calendar: Self.cal, now: Self.now
        ))
        #expect(plan.requiredDailyDeficit == 0)
        #expect(plan.dailyBudget == 2_600)
        #expect(!plan.isAggressive)
    }
}
