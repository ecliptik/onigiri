import Foundation

/// Start → now → target: the one resolved start point behind the Goal
/// tab's progress bar and the chart's milestone marks.
///
/// The chart answers "what is the scale doing"; this answers "how far
/// have I come", which is the question a bad weigh-in can't spoil. Both
/// need a start, and a start is the only thing the app didn't already
/// know — hence `GoalSettings.startWeightLb` / `startedAt` and the
/// derivation below for the goals that predate them.
public struct GoalProgress: Equatable, Sendable {
    /// Weight when this journey began, in canonical pounds.
    public let startLb: Double
    /// When it began — shown as "since <date>" for a derived start.
    public let startedAt: Date
    public let currentLb: Double
    public let targetLb: Double
    /// The start was recovered from the earliest weigh-in on record
    /// rather than stamped when the goal was set. Existing goals have no
    /// stamp and can't be given one honestly: writing today's weight in
    /// would tell someone forty pounds down that they're at 0%. Deriving
    /// it understates a long journey (Health history is read 90 days
    /// back) but never overstates it, and the UI says which date it's
    /// counting from. It stops being a fallback the next time the goal
    /// is edited.
    public let isDerivedStart: Bool
    /// Marks between start and target, nearest first. The target itself
    /// is NOT among them — the chart already draws that line, and a
    /// milestone on top of it would only thicken it.
    public let milestones: [Milestone]

    /// One mark on the way down.
    public struct Milestone: Equatable, Sendable {
        /// Where the mark sits on the weight axis (canonical lb).
        public let weightLb: Double
        /// How far below the start it is — what the mark is NAMED after
        /// ("5 lb down"). Naming marks by progress rather than by weight
        /// keeps them round when the start weight isn't: a journey from
        /// 213.4 lb would otherwise post milestones at 208.4 and 203.4.
        public let lostLb: Double
        /// The scale has reached it.
        public let isReached: Bool
    }

    /// Pounds off the start so far, floored at zero: a gain reads as no
    /// progress, never as negative progress.
    public var lostLb: Double { max(0, startLb - currentLb) }

    /// The whole journey, start to target.
    public var totalLb: Double { max(0, startLb - targetLb) }

    /// 0...1 for a progress bar. Clamped at both ends — overshooting the
    /// target is a full bar, not a 110% one.
    public var fraction: Double {
        guard totalLb > 0 else { return 0 }
        return min(1, max(0, lostLb / totalLb))
    }

    /// A journey shorter than this has nothing worth drawing a bar for
    /// (and a derived start can land a hair above the target by
    /// coincidence).
    public static let minimumJourneyLb = 1.0

    /// Runaway guard only: a pathological step can't mint a million
    /// marks. Real journeys produce a handful, and the chart's y-domain
    /// clips all but the nearby ones anyway.
    static let maximumMilestones = 60

    /// 5 lb is the milestone people count in; the kilogram equivalent is
    /// 2 kg, not 2.27. Marks are anchored to the START, so the step is
    /// all the display unit gets to decide.
    public static func milestoneStepLb(for unit: WeightUnit) -> Double {
        unit == .pounds ? 5 : unit.toLb(2)
    }

    /// Resolve the journey, or nil when there isn't one to show.
    ///
    /// nil in maintenance (no journey — the anchor isn't a destination),
    /// without a target or a current weight, and when no start can be
    /// found or the start isn't meaningfully above the target.
    public static func resolve(
        startWeightLb: Double?,
        startedAt: Date?,
        weightHistory: [WeightTrend.Point],
        currentWeightLb: Double?,
        targetWeightLb: Double?,
        isMaintenance: Bool,
        milestoneStepLb: Double = 5
    ) -> GoalProgress? {
        guard !isMaintenance,
              let current = currentWeightLb,
              let target = targetWeightLb, target > 0
        else { return nil }

        // The stamp wins; the earliest weigh-in on record is the
        // fallback. Both halves are required — a start weight without a
        // date can't say what it's measuring from.
        let start: (lb: Double, at: Date, derived: Bool)
        if let startWeightLb, let startedAt {
            start = (startWeightLb, startedAt, false)
        } else if let earliest = weightHistory.first {
            start = (earliest.weightLb, earliest.date, true)
        } else {
            return nil
        }
        guard start.lb - target >= minimumJourneyLb else { return nil }

        return GoalProgress(
            startLb: start.lb,
            startedAt: start.at,
            currentLb: current,
            targetLb: target,
            isDerivedStart: start.derived,
            milestones: milestones(
                startLb: start.lb, targetLb: target,
                currentLb: current, stepLb: milestoneStepLb
            )
        )
    }

    /// Marks every `stepLb` down from the start, stopping short of the
    /// target's own line.
    static func milestones(
        startLb: Double, targetLb: Double, currentLb: Double, stepLb: Double
    ) -> [Milestone] {
        let span = startLb - targetLb
        guard stepLb > 0, span > 0 else { return [] }
        // Strictly inside the span: a step that lands exactly on the
        // target (a 25 lb journey in 5 lb steps) yields four marks, not
        // five. The epsilon keeps floating-point 24.999999 out too.
        let count = min(Int(((span - 0.01) / stepLb).rounded(.down)), maximumMilestones)
        guard count > 0 else { return [] }
        return (1...count).map { index in
            let lost = stepLb * Double(index)
            let weight = startLb - lost
            return Milestone(
                weightLb: weight,
                lostLb: lost,
                // A hair of slack so a weigh-in sitting exactly on the
                // mark counts as having reached it.
                isReached: currentLb <= weight + 0.001
            )
        }
    }
}
