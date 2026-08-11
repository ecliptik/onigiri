import Foundation
import SwiftData
import UIKit
import OnigiriKit

/// The one validation + save path for weight goals. GoalView and
/// onboarding had drifted: onboarding saved current-weight-less goals
/// GoalView couldn't edit, GoalView saved target ≥ current goals
/// onboarding rejected, and onboarding's re-save silently no-opped.
@MainActor
enum GoalUpsert {
    enum Validation: Equatable {
        case valid
        case missingTarget
        case missingCurrentWeight
        case targetNotBelowCurrent
    }

    /// A lose goal needs a positive target below a known current weight —
    /// weight-gain goals aren't supported, and a goal saved without a
    /// current weight leaves the plan uncomputable everywhere. Maintenance
    /// needs neither: the budget is the burn.
    static func validate(targetLb: Double?, currentLb: Double?, mode: String? = nil) -> Validation {
        if mode == GoalMode.maintain { return .valid }
        guard let target = targetLb, target > 0 else { return .missingTarget }
        guard let current = currentLb else { return .missingCurrentWeight }
        return target < current ? .valid : .targetNotBelowCurrent
    }

    /// What this save does to the journey's start point. `nil` (the
    /// default) leaves the stored start alone — most saves are about the
    /// target, and only the stamp rule below may touch it.
    enum StartChange {
        /// The user picked a start themselves. Sticky: no later target
        /// change re-stamps over it.
        case manual(at: Date, weightLb: Double)
        /// Back to inferring it from the earliest weigh-in on record.
        case automatic
        /// Continuing past a target that was REACHED: the same journey,
        /// extended. Leaves the stored start alone AND suppresses the
        /// target-changed re-stamp below, so the progress bar keeps
        /// measuring the whole arc (22 of 27 lb) instead of re-zeroing
        /// at the moment it was earned. Only the goal-reached flow
        /// passes this — editing a target by hand is still a new
        /// journey.
        case keep
    }

    /// Update the existing goal or insert one, then push sync (which
    /// reloads widgets) and replan reminders. Call after `.valid`.
    static func save(
        targetLb: Double,
        targetDate: Date,
        healthWeightLb: Double?,
        manualWeightLb: Double?,
        mode: String? = nil,
        startChange: StartChange? = nil,
        goals: [GoalSettings],
        context: ModelContext
    ) {
        // The manual weight is only a fallback while Health has none.
        let fallback = healthWeightLb == nil ? manualWeightLb : nil
        // Where today's weight sits, for the start-point stamp below.
        let currentLb = healthWeightLb ?? manualWeightLb
        if let goal = goals.first {
            // Read before the write: a new TARGET is a new journey, so
            // it re-stamps the start. A nudged date, a switched mode, or
            // a corrected fallback weight is the same journey and must
            // leave the start alone — re-stamping on every save would
            // walk the start down behind the scale and pin progress at
            // ~0 forever.
            let targetChanged = goal.targetWeightLb != targetLb
            goal.targetWeightLb = targetLb
            goal.targetDate = targetDate
            goal.fallbackCurrentWeightLb = fallback
            goal.mode = mode
            switch startChange {
            case .manual(let at, let weightLb):
                goal.startWeightLb = weightLb
                goal.startedAt = at
                goal.startIsManual = true
            case .automatic:
                goal.startWeightLb = nil
                goal.startedAt = nil
                goal.startIsManual = nil
            case .keep, nil:
                // `.keep` differs from nil only below: it is NOT `nil`,
                // so the re-stamp guard skips it and the journey
                // survives the new target.
                break
            }
            // The stamp is for goals whose start nobody is steering: a
            // start the user just set, or set earlier and never
            // revoked, outranks it. `startChange == nil` matters as much
            // as the flag — someone who asked for automatic IN THIS SAVE
            // shouldn't be handed today's date back.
            if targetChanged, startChange == nil, goal.startIsManual != true,
               mode != GoalMode.maintain, let currentLb {
                goal.startWeightLb = currentLb
                goal.startedAt = .now
                // A new journey re-derives its marks from a new start, so
                // the deepest one already announced no longer describes
                // anything. Left alone, a 20 lb ack would silently settle
                // every mark of the next journey. Deliberately NOT reset
                // for `.keep` (continuing past a reached target): that
                // journey's marks carry on from the same start, and
                // re-announcing "20 lb down" would be a lie about news.
                SharedStore.acknowledgeMilestone(lostLb: 0)
            }
        } else {
            // Maintenance has no journey to measure; its "target" is a
            // hold-near anchor, and stamping one would mint a start the
            // moment someone nudged the anchor.
            let stamped: (lb: Double, at: Date)? = mode == GoalMode.maintain
                ? nil
                : currentLb.map { ($0, .now) }
            let start: (lb: Double, at: Date, manual: Bool)? = switch startChange {
            case .manual(let at, let weightLb): (weightLb, at, true)
            case .automatic: nil
            // `.keep` can't reach here in practice (continuing implies a
            // goal that was already reached), and a first goal has no
            // journey to preserve — so it stamps like any other.
            case .keep, nil: stamped.map { ($0.lb, $0.at, false) }
            }
            context.insert(GoalSettings(
                targetWeightLb: targetLb,
                targetDate: targetDate,
                fallbackCurrentWeightLb: fallback,
                mode: mode,
                startWeightLb: start?.lb,
                startedAt: start?.at,
                startIsManual: start?.manual == true ? true : nil
            ))
        }
        try? context.save()
        PhoneSyncService.shared.push(from: context)
        // A new target changes tonight's streak-warning math.
        ReminderScheduler.shared.replan()
        // Same success haptic as every log (the toast is the caller's —
        // onboarding stays quiet, GoalView announces).
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
