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

    /// The rule itself lives in the kit as `GoalStartChange` /
    /// `GoalStartStamp`, where it is unit-tested — it had shipped several
    /// regressions from being tangled with the write below and therefore
    /// untestable (audit, 2026-08-17). Kept as an alias so every call
    /// site still reads `GoalUpsert.StartChange`.
    typealias StartChange = GoalStartChange

    /// Write a start decision onto the stored goal. The rule that
    /// produced it is `GoalStartStamp`; this only applies it.
    private static func apply(_ decision: GoalStartStamp.Decision, to goal: GoalSettings) {
        switch decision.outcome {
        case .keep:
            break
        case .clear:
            goal.startWeightLb = nil
            goal.startedAt = nil
            goal.startIsManual = nil
        case .set(let lb, let at, let manual):
            goal.startWeightLb = lb
            goal.startedAt = at
            goal.startIsManual = manual ? true : nil
        }
        // Deliberately NOT reset when continuing past a reached target
        // (`.keep`): that journey's marks carry on from the same start,
        // and re-announcing "20 lb down" would be a lie about news.
        if decision.resetsMilestone {
            SharedStore.recordMilestoneSeen(lostLb: 0)
        }
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
            apply(
                GoalStartStamp.existing(
                    change: startChange,
                    targetChanged: targetChanged,
                    startIsManual: goal.startIsManual,
                    mode: mode,
                    currentLb: currentLb,
                    now: .now
                ),
                to: goal
            )
        } else {
            let start: (lb: Double, at: Date, manual: Bool)?
            switch GoalStartStamp.first(
                change: startChange, mode: mode, currentLb: currentLb, now: .now
            ).outcome {
            case .set(let lb, let at, let manual): start = (lb, at, manual)
            // A goal being inserted has nothing stored to keep, so both
            // of these mean the same thing here.
            case .clear, .keep: start = nil
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
        context.saveOrReport("Couldn't save your goal")
        PhoneSyncService.shared.push(from: context)
        // A new target changes tonight's streak-warning math.
        ReminderScheduler.shared.replan()
        // Same success haptic as every log (the toast is the caller's —
        // onboarding stays quiet, GoalView announces).
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
