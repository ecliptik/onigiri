import Testing
import Foundation
@testable import OnigiriKit

/// `deepestMilestone(reachedAtOrBelow:)` — the rung the Daily goal card
/// announces. It lived inline in `TodayView` until 2026-08-17, which
/// left it the only untested member of the "which weight judges a
/// verdict" family that CLAUDE.md records shipping bugs twice.
struct GoalProgressMilestoneTests {
    private let started = Date(timeIntervalSince1970: 1_740_000_000)

    /// 210 → 190 with 5 lb rungs: marks at 205, 200 and 195. The target
    /// itself is deliberately not among them.
    private func journey(currentLb: Double = 200) throws -> GoalProgress {
        try #require(GoalProgress.resolve(
            startWeightLb: 210,
            startedAt: started,
            weightHistory: [],
            currentWeightLb: currentLb,
            targetWeightLb: 190,
            isMaintenance: false,
            milestoneStepLb: 5
        ))
    }

    @Test func aBasisAboveEveryRungReachesNothing() throws {
        let progress = try journey()
        #expect(progress.deepestMilestone(reachedAtOrBelow: 206) == nil)
    }

    @Test func aBasisOnARungReachesIt() throws {
        let progress = try journey()
        let reached = try #require(progress.deepestMilestone(reachedAtOrBelow: 205))
        #expect(reached.lostLb == 5)
    }

    /// The property the inline version existed to get right: crossing
    /// two rungs between one check and the next announces the DEEPER
    /// one, not both and not the first.
    @Test func crossingTwoRungsAtOnceReportsTheDeeper() throws {
        let progress = try journey()
        let reached = try #require(progress.deepestMilestone(reachedAtOrBelow: 199))
        #expect(reached.lostLb == 10)
        #expect(reached.weightLb == 200)
    }

    @Test func aBasisPastEveryRungReportsTheDeepest() throws {
        let progress = try journey()
        let reached = try #require(progress.deepestMilestone(reachedAtOrBelow: 191))
        #expect(reached.lostLb == 15)
    }

    /// The whole reason this takes a basis instead of reading
    /// `currentLb`: `Milestone.isReached` is computed against the raw
    /// weigh-in, so one light morning marks a rung the sustained basis
    /// has not reached. The two must be free to disagree.
    @Test func theBasisAndTheRawReadingCanDisagree() throws {
        // A single light morning at 199 …
        let progress = try journey(currentLb: 199)
        #expect(progress.milestones.contains { $0.lostLb == 10 && $0.isReached })
        // … while the sustained basis is still above that rung.
        #expect(progress.deepestMilestone(reachedAtOrBelow: 203)?.lostLb == 5)
    }
}
