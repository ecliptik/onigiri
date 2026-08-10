import Foundation
import Testing
@testable import OnigiriKit

/// Reaching the target is a sustained result, not a lucky morning — and
/// it must stay reachable for someone who doesn't weigh every day. These
/// are the cases that define both halves.
struct GoalCompletionTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    /// `daysAgo` readings, newest last.
    private func history(_ entries: [(daysAgo: Double, lb: Double)]) -> [WeightTrend.Point] {
        entries
            .map { WeightTrend.Point(date: now.addingTimeInterval(-$0.daysAgo * 86400), weightLb: $0.lb) }
            .sorted { $0.date < $1.date }
    }

    // MARK: The preferred window

    @Test func threeWeighInDaysBelowTargetMeetsTheGoal() {
        let result = GoalCompletion.evaluate(
            targetLb: 175,
            history: history([(5, 174.8), (3, 174.2), (1, 174.6)]),
            now: now)
        #expect(result.isMet)
        #expect(result.weighInDays == 3)
        #expect(result.usedWiderWindow == false)
    }

    @Test func twoWeighInDaysIsNotEnoughOnItsOwn() {
        // Only two days inside 7 AND fewer than three within 30, so the
        // widened rule can't rescue it either.
        let result = GoalCompletion.evaluate(
            targetLb: 175,
            history: history([(3, 174.2), (1, 174.6)]),
            now: now)
        #expect(!result.isMet)
        #expect(result.basisLb == nil)
    }

    /// The case the whole thing exists for: one low morning in a week
    /// that is otherwise well above target.
    @Test func oneLowMorningDoesNotMeetTheGoal() {
        let result = GoalCompletion.evaluate(
            targetLb: 175,
            history: history([(6, 178.1), (4, 177.6), (2, 178.0), (1, 174.4)]),
            now: now)
        #expect(!result.isMet)
        #expect(result.usedWiderWindow == false)
    }

    @Test func exactlyAtTargetCounts() {
        let result = GoalCompletion.evaluate(
            targetLb: 175,
            history: history([(5, 175), (3, 175), (1, 175)]),
            now: now)
        #expect(result.isMet)
    }

    /// Two readings on one day are ONE day, and the LOW one decides it —
    /// an evening weigh-in runs 2–3 lb high. Anchored to explicit
    /// calendar days: fractional day offsets straddle midnight and would
    /// be testing the fixture rather than the rule.
    @Test func sameDayReadingsCollapseToTheirLow() {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        func point(daysAgo: Int, hour: Int, _ lb: Double) -> WeightTrend.Point {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: midnight)!
            return WeightTrend.Point(
                date: calendar.date(byAdding: .hour, value: hour, to: day)!, weightLb: lb)
        }
        let sparse = GoalCompletion.evaluate(
            targetLb: 175,
            history: [
                point(daysAgo: 5, hour: 7, 174.4),
                point(daysAgo: 3, hour: 7, 174.5),
                point(daysAgo: 1, hour: 7, 174.0),    // morning
                point(daysAgo: 1, hour: 20, 176.4),   // same day, evening
            ],
            now: now)
        // Four readings, three DAYS — and that day contributes its low.
        #expect(sparse.weighInDays == 3)
        #expect(sparse.isMet)
        let mean = (174.0 + 174.5 + 174.4) / 3
        #expect(abs((sparse.basisLb ?? 0) - mean) < 0.0001)
    }

    /// Pins the boundary, which Part A moved into shared code.
    @Test func aReadingExactlyAWindowOldIsOutside() {
        let result = GoalCompletion.evaluate(
            targetLb: 175,
            history: history([(7, 100), (3, 174.2), (1, 174.6)]),
            now: now)
        // The 7-day-old reading is excluded from the preferred window;
        // with only two days left there, the widened rule takes over and
        // then finds all three within 30 days.
        #expect(result.usedWiderWindow)
        #expect(result.weighInDays == 3)
    }

    // MARK: Widening — the sparse weigher

    @Test func aWeeklyWeigherCanStillReachTheGoal() {
        let result = GoalCompletion.evaluate(
            targetLb: 175,
            history: history([(21, 174.9), (14, 174.3), (7.5, 174.2)]),
            now: now)
        #expect(result.isMet)
        #expect(result.usedWiderWindow)
        #expect(result.weighInDays == 3)
    }

    /// Widening takes the most recent three, NOT everything inside the
    /// cap: the day-26 reading would pull the mean above target if it
    /// were wrongly included.
    @Test func wideningTakesTheNewestThreeOnly() {
        let result = GoalCompletion.evaluate(
            targetLb: 175,
            history: history([(26, 190), (20, 174.5), (13, 174.0), (8, 174.4)]),
            now: now)
        #expect(result.isMet)
        #expect(result.weighInDays == 3)
        let mean = (174.5 + 174.0 + 174.4) / 3
        #expect(abs((result.basisLb ?? 0) - mean) < 0.0001)
    }

    @Test func nothingRecentEnoughIsNotAResult() {
        let result = GoalCompletion.evaluate(
            targetLb: 175,
            history: history([(45, 174.0), (38, 173.5), (31, 173.8)]),
            now: now)
        #expect(!result.isMet)
        #expect(result.basisLb == nil)
    }

    /// The widening path must not move the common case.
    @Test func aDailyWeigherIsUnaffectedByTheFallback() {
        let daily = history((1...7).map { (daysAgo: Double($0), lb: 174.0 + Double($0) * 0.1) })
        let result = GoalCompletion.evaluate(targetLb: 175, history: daily, now: now)
        #expect(result.usedWiderWindow == false)
        #expect(result.weighInDays == 6)   // the 7-day-old reading is outside
        let basis = WeightTrend.targetBasisLb(daily, windowDays: 7, now: now)
        #expect(abs((result.basisLb ?? 0) - (basis ?? -1)) < 0.0001)
    }

    @Test func emptyHistoryIsNotMet() {
        let result = GoalCompletion.evaluate(targetLb: 175, history: [], now: now)
        #expect(!result.isMet)
        #expect(result.basisLb == nil)
        #expect(result.weighInDays == 0)
    }

    @Test func aboveTargetIsNotMetHoweverManyWeighIns() {
        let result = GoalCompletion.evaluate(
            targetLb: 175,
            history: history([(5, 176.1), (3, 175.8), (1, 175.2)]),
            now: now)
        #expect(!result.isMet)
        #expect(result.weighInDays == 3)
    }
}

/// "Announce it, allow a dismissal, say it once more in two weeks if
/// nothing was decided, then never again for that target."
struct GoalReachedCardTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)
    private func daysBefore(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86400)
    }

    @Test func neverAcknowledgedShows() {
        #expect(GoalReachedCard.shouldShow(
            isMet: true, isMaintenance: false, targetLb: 175,
            ackTarget: 0, ackCount: 0, ackAt: nil, now: now))
    }

    @Test func notMetNeverShows() {
        #expect(!GoalReachedCard.shouldShow(
            isMet: false, isMaintenance: false, targetLb: 175,
            ackTarget: 0, ackCount: 0, ackAt: nil, now: now))
    }

    @Test func maintenanceHasNoTargetToReach() {
        #expect(!GoalReachedCard.shouldShow(
            isMet: true, isMaintenance: true, targetLb: 175,
            ackTarget: 0, ackCount: 0, ackAt: nil, now: now))
    }

    @Test func dismissedTodayStaysHiddenUntilTheReArm() {
        for days in [0.0, 6.0, 13.0] {
            #expect(!GoalReachedCard.shouldShow(
                isMet: true, isMaintenance: false, targetLb: 175,
                ackTarget: 175, ackCount: 1, ackAt: daysBefore(days), now: now),
                "hidden \(days) days after a dismissal")
        }
    }

    @Test func theReArmFiresAtFourteenDays() {
        #expect(GoalReachedCard.shouldShow(
            isMet: true, isMaintenance: false, targetLb: 175,
            ackTarget: 175, ackCount: 1, ackAt: daysBefore(14), now: now))
    }

    /// Twice, never three times — however long it has been.
    @Test func aSecondDismissalEndsIt() {
        for days in [14.0, 60.0, 400.0] {
            #expect(!GoalReachedCard.shouldShow(
                isMet: true, isMaintenance: false, targetLb: 175,
                ackTarget: 175, ackCount: 2, ackAt: daysBefore(days), now: now),
                "still silent \(days) days on")
        }
    }

    /// A decision writes the terminal count, so it can't leave a re-arm
    /// loaded behind it.
    @Test func aDecisionSilencesItImmediately() {
        #expect(!GoalReachedCard.shouldShow(
            isMet: true, isMaintenance: false, targetLb: 175,
            ackTarget: 175, ackCount: GoalReachedCard.maximumShows,
            ackAt: daysBefore(30), now: now))
    }

    /// An acknowledgement belongs to the target it was made for.
    @Test func aNewTargetReArmsTheCard() {
        #expect(GoalReachedCard.shouldShow(
            isMet: true, isMaintenance: false, targetLb: 170,
            ackTarget: 175, ackCount: 2, ackAt: daysBefore(1), now: now))
    }

    @Test func noTargetNeverShows() {
        #expect(!GoalReachedCard.shouldShow(
            isMet: true, isMaintenance: false, targetLb: nil,
            ackTarget: 0, ackCount: 0, ackAt: nil, now: now))
    }
}
