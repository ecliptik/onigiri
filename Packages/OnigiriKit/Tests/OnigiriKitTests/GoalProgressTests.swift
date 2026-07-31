import Foundation
import Testing
@testable import OnigiriKit

/// Start → now → target. Most of the risk here is in the start point:
/// where it comes from, when it's derived, and what stops it moving.
struct GoalProgressTests {
    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 12))!

    private static func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: now)!
    }

    private static func resolve(
        startWeightLb: Double? = nil,
        startedAt: Date? = nil,
        history: [WeightTrend.Point] = [],
        currentWeightLb: Double? = 205,
        targetWeightLb: Double? = 190,
        isMaintenance: Bool = false,
        stepLb: Double = 5
    ) -> GoalProgress? {
        GoalProgress.resolve(
            startWeightLb: startWeightLb, startedAt: startedAt,
            weightHistory: history, currentWeightLb: currentWeightLb,
            targetWeightLb: targetWeightLb, isMaintenance: isMaintenance,
            milestoneStepLb: stepLb
        )
    }

    // MARK: The start point

    @Test func aStampedStartWins() throws {
        let stampedAt = Self.day(-40)
        let progress = try #require(Self.resolve(
            startWeightLb: 215, startedAt: stampedAt,
            // A weigh-in history that would derive a DIFFERENT start.
            history: [.init(date: Self.day(-60), weightLb: 208)]
        ))
        #expect(progress.startLb == 215)
        #expect(progress.startedAt == stampedAt)
        #expect(progress.isDerivedStart == false)
    }

    @Test func anUnstampedGoalDerivesFromTheEarliestWeighIn() throws {
        let progress = try #require(Self.resolve(history: [
            .init(date: Self.day(-60), weightLb: 215),
            .init(date: Self.day(-30), weightLb: 210),
            .init(date: Self.day(0), weightLb: 205),
        ]))
        #expect(progress.startLb == 215)
        #expect(progress.startedAt == Self.day(-60))
        // The UI leans on this to say "since Jun 1" instead of implying
        // the goal was set then.
        #expect(progress.isDerivedStart)
    }

    /// The trap the plan calls out: a mid-journey goal must NOT be
    /// backfilled with today's weight, which would read as 0% to someone
    /// ten pounds down.
    @Test func aDerivedStartIsNotTodaysWeight() throws {
        let progress = try #require(Self.resolve(history: [
            .init(date: Self.day(-60), weightLb: 215),
            .init(date: Self.day(0), weightLb: 205),
        ]))
        #expect(progress.startLb != progress.currentLb)
        #expect(progress.lostLb == 10)
    }

    @Test func halvesOfTheStampAreNotEnough() {
        // A weight with no date can't say what it measures from, and a
        // date with no weight measures nothing — both fall through to
        // derivation, and with no history at all there's no progress.
        #expect(Self.resolve(startWeightLb: 215) == nil)
        #expect(Self.resolve(startedAt: Self.day(-40)) == nil)
    }

    @Test func noStartAtAllMeansNoProgress() {
        #expect(Self.resolve(history: []) == nil)
    }

    // MARK: What there's nothing to show for

    @Test func maintenanceHasNoJourney() {
        #expect(Self.resolve(
            startWeightLb: 215, startedAt: Self.day(-40), isMaintenance: true) == nil)
    }

    @Test func aMissingTargetOrWeightMeansNoProgress() {
        #expect(Self.resolve(startWeightLb: 215, startedAt: Self.day(-40),
                             targetWeightLb: nil) == nil)
        // 0 is the "no anchor parked" placeholder, not a target.
        #expect(Self.resolve(startWeightLb: 215, startedAt: Self.day(-40),
                             targetWeightLb: 0) == nil)
        #expect(Self.resolve(startWeightLb: 215, startedAt: Self.day(-40),
                             currentWeightLb: nil) == nil)
    }

    @Test func aStartAtOrBelowTheTargetIsNoJourney() {
        #expect(Self.resolve(startWeightLb: 190, startedAt: Self.day(-40)) == nil)
        #expect(Self.resolve(startWeightLb: 185, startedAt: Self.day(-40)) == nil)
        // …and neither is a start a fraction of a pound above it.
        #expect(Self.resolve(startWeightLb: 190.5, startedAt: Self.day(-40)) == nil)
    }

    // MARK: The numbers on the bar

    @Test func theBarReadsLostOfTotal() throws {
        // 215 → 190 is 25 lb; at 206.6 that's 8.4 down.
        let progress = try #require(Self.resolve(
            startWeightLb: 215, startedAt: Self.day(-40), currentWeightLb: 206.6))
        #expect(abs(progress.lostLb - 8.4) < 0.001)
        #expect(progress.totalLb == 25)
        #expect(abs(progress.fraction - 0.336) < 0.001)
    }

    @Test func aGainReadsAsZeroProgressNotNegative() throws {
        let progress = try #require(Self.resolve(
            startWeightLb: 215, startedAt: Self.day(-40), currentWeightLb: 218))
        #expect(progress.lostLb == 0)
        #expect(progress.fraction == 0)
    }

    @Test func overshootingTheTargetFillsTheBarExactlyOnce() throws {
        let progress = try #require(Self.resolve(
            startWeightLb: 215, startedAt: Self.day(-40), currentWeightLb: 185))
        #expect(progress.fraction == 1)
    }

    // MARK: Milestones

    @Test func milestonesStepDownFromTheStartAndStopBeforeTheTarget() throws {
        // 215 → 190: marks at 5/10/15/20 lb down. The 25 lb mark IS the
        // target, which draws its own line.
        let progress = try #require(Self.resolve(
            startWeightLb: 215, startedAt: Self.day(-40), currentWeightLb: 206.6))
        #expect(progress.milestones.map(\.lostLb) == [5, 10, 15, 20])
        #expect(progress.milestones.map(\.weightLb) == [210, 205, 200, 195])
    }

    @Test func reachedMilestonesKnowIt() throws {
        let progress = try #require(Self.resolve(
            startWeightLb: 215, startedAt: Self.day(-40), currentWeightLb: 204))
        #expect(progress.milestones.map(\.isReached) == [true, true, false, false])
    }

    /// A weigh-in sitting exactly on a mark has reached it.
    @Test func aMilestoneLandedOnCounts() throws {
        let progress = try #require(Self.resolve(
            startWeightLb: 215, startedAt: Self.day(-40), currentWeightLb: 210))
        #expect(progress.milestones.first?.isReached == true)
    }

    @Test func aJourneyShorterThanOneStepHasNoMilestones() throws {
        let progress = try #require(Self.resolve(
            startWeightLb: 194, startedAt: Self.day(-40), currentWeightLb: 192))
        #expect(progress.milestones.isEmpty)
    }

    /// A step that divides the span exactly must not post a mark on top
    /// of the target line.
    @Test func anExactlyDivisibleSpanStopsShortOfTheTarget() {
        let marks = GoalProgress.milestones(
            startLb: 210, targetLb: 190, currentLb: 205, stepLb: 5)
        #expect(marks.map(\.lostLb) == [5, 10, 15])
    }

    /// Kilogram users get 2 kg steps, not 5 lb relabelled — the whole
    /// point of routing display through WeightUnit.
    @Test func theKilogramStepIsTwoKilograms() {
        let step = GoalProgress.milestoneStepLb(for: .kilograms)
        #expect(abs(WeightUnit.kilograms.fromLb(step) - 2) < 0.0001)
        #expect(GoalProgress.milestoneStepLb(for: .pounds) == 5)

        let marks = GoalProgress.milestones(
            startLb: 215, targetLb: 190, currentLb: 210, stepLb: step)
        // Every mark reads as a round number of kilograms down.
        for (index, mark) in marks.enumerated() {
            let kg = WeightUnit.kilograms.fromLb(mark.lostLb)
            #expect(abs(kg - Double(2 * (index + 1))) < 0.0001)
        }
    }

    @Test func aPathologicalStepCannotMintUnboundedMarks() {
        let marks = GoalProgress.milestones(
            startLb: 300, targetLb: 100, currentLb: 250, stepLb: 0.0001)
        #expect(marks.count == GoalProgress.maximumMilestones)
        // …and a zero/negative step yields nothing rather than looping.
        #expect(GoalProgress.milestones(
            startLb: 300, targetLb: 100, currentLb: 250, stepLb: 0).isEmpty)
    }
}
