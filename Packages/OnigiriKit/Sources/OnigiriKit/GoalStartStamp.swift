import Foundation

/// What a goal save does to the journey's START point.
///
/// `nil` at the call site (the default) leaves the stored start alone —
/// most saves are about the target, and only the re-stamp rule in
/// `GoalStartStamp` may touch it.
public enum GoalStartChange: Equatable, Sendable {
    /// The user picked a start themselves. Sticky: no later target
    /// change re-stamps over it.
    case manual(at: Date, weightLb: Double)
    /// Back to inferring it from the earliest weigh-in on record.
    case automatic
    /// Continuing past a target that was REACHED: the same journey,
    /// extended. Leaves the stored start alone AND suppresses the
    /// target-changed re-stamp, so the progress bar keeps measuring the
    /// whole arc (22 of 27 lb) instead of re-zeroing at the moment it
    /// was earned. Only the goal-reached flow passes this — editing a
    /// target by hand is still a new journey.
    case keep
}

/// Where a goal's start point lands on save, as a pure decision.
///
/// Extracted from `GoalUpsert.save` (audit, 2026-08-17), which had this
/// tangled with the SwiftData write and therefore untestable — while its
/// own comments narrated several shipped regressions it exists to
/// prevent. Everything that varies is scalar, so the decision is a
/// function and the caller is left to apply it.
public enum GoalStartStamp {
    /// What to write to the stored start.
    public enum Outcome: Equatable, Sendable {
        /// Leave whatever is stored untouched.
        case keep
        /// Clear it — the goal goes back to inferring its own start.
        case clear
        /// Stamp these values.
        case set(lb: Double, at: Date, manual: Bool)
    }

    public struct Decision: Equatable, Sendable {
        public let outcome: Outcome
        /// A new journey re-derives its marks from a new start, so the
        /// deepest one already announced no longer describes anything.
        /// Left set, a 20 lb acknowledgement would silently settle every
        /// mark of the next journey.
        public let resetsMilestone: Bool

        public init(outcome: Outcome, resetsMilestone: Bool) {
            self.outcome = outcome
            self.resetsMilestone = resetsMilestone
        }
    }

    /// The decision for a goal that ALREADY exists.
    ///
    /// An explicit `change` and the automatic re-stamp are mutually
    /// exclusive by construction: the re-stamp requires `change == nil`.
    /// That `nil` check carries as much weight as the manual flag —
    /// someone who asked for automatic IN THIS SAVE must not be handed
    /// today's date straight back.
    public static func existing(
        change: GoalStartChange?,
        targetChanged: Bool,
        startIsManual: Bool?,
        mode: String?,
        currentLb: Double?,
        now: Date
    ) -> Decision {
        switch change {
        case .manual(let at, let weightLb):
            return Decision(outcome: .set(lb: weightLb, at: at, manual: true), resetsMilestone: false)
        case .automatic:
            return Decision(outcome: .clear, resetsMilestone: false)
        case .keep:
            return Decision(outcome: .keep, resetsMilestone: false)
        case nil:
            // A new TARGET is a new journey, so it re-stamps the start. A
            // nudged date, a switched mode or a corrected fallback weight
            // is the SAME journey and must leave the start alone —
            // re-stamping on every save would walk the start down behind
            // the scale and pin progress at ~0 forever.
            //
            // A start the user set, whether in this save or earlier and
            // never revoked, outranks the stamp.
            guard targetChanged, startIsManual != true,
                  mode != GoalMode.maintain, let currentLb
            else { return Decision(outcome: .keep, resetsMilestone: false) }
            return Decision(outcome: .set(lb: currentLb, at: now, manual: false), resetsMilestone: true)
        }
    }

    /// The decision for the FIRST goal.
    ///
    /// Maintenance has no journey to measure — its "target" is a
    /// hold-near anchor, and stamping one would mint a start the moment
    /// somebody nudged the anchor.
    public static func first(
        change: GoalStartChange?,
        mode: String?,
        currentLb: Double?,
        now: Date
    ) -> Decision {
        switch change {
        case .manual(let at, let weightLb):
            return Decision(outcome: .set(lb: weightLb, at: at, manual: true), resetsMilestone: false)
        case .automatic:
            return Decision(outcome: .clear, resetsMilestone: false)
        // `.keep` cannot reach here in practice — continuing implies a
        // goal that already existed — and a first goal has no journey to
        // preserve, so it stamps like any other.
        case .keep, nil:
            guard mode != GoalMode.maintain, let currentLb else {
                return Decision(outcome: .clear, resetsMilestone: false)
            }
            return Decision(outcome: .set(lb: currentLb, at: now, manual: false), resetsMilestone: false)
        }
    }
}
