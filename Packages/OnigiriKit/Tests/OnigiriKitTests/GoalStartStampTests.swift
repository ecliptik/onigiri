import Testing
import Foundation
@testable import OnigiriKit

/// The start-point rule `GoalUpsert.save` used to carry inline, where it
/// could not be tested — while its own comments narrated the regressions
/// it exists to prevent. One test per named incident.
struct GoalStartStampTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let earlier = Date(timeIntervalSince1970: 1_740_000_000)

    // MARK: - An existing goal

    /// The headline regression: "re-stamping on every save would walk the
    /// start down behind the scale and pin progress at ~0 forever." A
    /// nudged date, a switched mode, a corrected fallback weight — same
    /// journey, same target — must not touch the start.
    @Test func sameTargetLeavesTheStartAlone() {
        let decision = GoalStartStamp.existing(
            change: nil, targetChanged: false, startIsManual: nil,
            mode: nil, currentLb: 205, now: now
        )
        #expect(decision.outcome == .keep)
        #expect(decision.resetsMilestone == false)
    }

    @Test func aNewTargetStampsTodayAndResetsTheMilestone() {
        let decision = GoalStartStamp.existing(
            change: nil, targetChanged: true, startIsManual: nil,
            mode: nil, currentLb: 205, now: now
        )
        #expect(decision.outcome == .set(lb: 205, at: now, manual: false))
        // "a 20 lb ack would silently settle every mark of the next
        // journey" — the new journey re-derives its marks, so the
        // deepest one already announced has to go.
        #expect(decision.resetsMilestone == true)
    }

    /// A start the user set is sticky: no later target change re-stamps
    /// over it.
    @Test func aManualStartSurvivesANewTarget() {
        let decision = GoalStartStamp.existing(
            change: nil, targetChanged: true, startIsManual: true,
            mode: nil, currentLb: 205, now: now
        )
        #expect(decision.outcome == .keep)
        #expect(decision.resetsMilestone == false)
    }

    /// `.keep` is what continuing past a REACHED target passes. The
    /// journey is extended, not restarted — the bar keeps reading 22 of
    /// 27 lb rather than re-zeroing at the moment it was earned — and
    /// the milestone must NOT reset, or the same "20 lb down" is
    /// re-announced as news.
    @Test func continuingPastAReachedTargetKeepsTheJourney() {
        let decision = GoalStartStamp.existing(
            change: .keep, targetChanged: true, startIsManual: nil,
            mode: nil, currentLb: 190, now: now
        )
        #expect(decision.outcome == .keep)
        #expect(decision.resetsMilestone == false)
    }

    /// Asking for automatic IN THIS SAVE must not hand today's date
    /// straight back — the `change == nil` half of the guard carries as
    /// much weight as the manual flag.
    @Test func askingForAutomaticClearsRatherThanRestamping() {
        let decision = GoalStartStamp.existing(
            change: .automatic, targetChanged: true, startIsManual: nil,
            mode: nil, currentLb: 205, now: now
        )
        #expect(decision.outcome == .clear)
        #expect(decision.resetsMilestone == false)
    }

    @Test func aManuallyPickedStartIsStampedAsManual() {
        let decision = GoalStartStamp.existing(
            change: .manual(at: earlier, weightLb: 212), targetChanged: false,
            startIsManual: nil, mode: nil, currentLb: 205, now: now
        )
        #expect(decision.outcome == .set(lb: 212, at: earlier, manual: true))
        #expect(decision.resetsMilestone == false)
    }

    /// Maintenance has no journey to measure, so nothing stamps a start
    /// the moment somebody nudges the hold-near anchor.
    @Test func maintenanceNeverStamps() {
        let decision = GoalStartStamp.existing(
            change: nil, targetChanged: true, startIsManual: nil,
            mode: GoalMode.maintain, currentLb: 205, now: now
        )
        #expect(decision.outcome == .keep)
        #expect(decision.resetsMilestone == false)
    }

    /// No weight on record anywhere means nothing to stamp WITH.
    @Test func noCurrentWeightCannotStamp() {
        let decision = GoalStartStamp.existing(
            change: nil, targetChanged: true, startIsManual: nil,
            mode: nil, currentLb: nil, now: now
        )
        #expect(decision.outcome == .keep)
        #expect(decision.resetsMilestone == false)
    }

    // MARK: - The first goal

    @Test func aFirstGoalStampsTodayWithoutResettingAnything() {
        let decision = GoalStartStamp.first(
            change: nil, mode: nil, currentLb: 205, now: now
        )
        #expect(decision.outcome == .set(lb: 205, at: now, manual: false))
        // There is no earlier journey whose marks could be stale.
        #expect(decision.resetsMilestone == false)
    }

    @Test func aFirstMaintenanceGoalStampsNothing() {
        let decision = GoalStartStamp.first(
            change: nil, mode: GoalMode.maintain, currentLb: 205, now: now
        )
        #expect(decision.outcome == .clear)
    }

    @Test func aFirstGoalHonoursAManuallyPickedStart() {
        let decision = GoalStartStamp.first(
            change: .manual(at: earlier, weightLb: 212), mode: nil,
            currentLb: 205, now: now
        )
        #expect(decision.outcome == .set(lb: 212, at: earlier, manual: true))
    }

    /// `.keep` cannot reach the insert path in practice — continuing
    /// implies a goal that already existed — and a first goal has no
    /// journey to preserve, so it stamps like any other.
    @Test func aFirstGoalTreatsKeepAsAnOrdinaryStamp() {
        let decision = GoalStartStamp.first(
            change: .keep, mode: nil, currentLb: 205, now: now
        )
        #expect(decision.outcome == .set(lb: 205, at: now, manual: false))
    }
}
