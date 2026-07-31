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

    /// Update the existing goal or insert one, then push sync (which
    /// reloads widgets) and replan reminders. Call after `.valid`.
    static func save(
        targetLb: Double,
        targetDate: Date,
        healthWeightLb: Double?,
        manualWeightLb: Double?,
        mode: String? = nil,
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
            if targetChanged, mode != GoalMode.maintain, let currentLb {
                goal.startWeightLb = currentLb
                goal.startedAt = .now
            }
        } else {
            context.insert(GoalSettings(
                targetWeightLb: targetLb,
                targetDate: targetDate,
                fallbackCurrentWeightLb: fallback,
                mode: mode,
                // Maintenance has no journey to measure; its "target" is
                // a hold-near anchor, and stamping one would mint a
                // start the moment someone nudged the anchor.
                startWeightLb: mode == GoalMode.maintain ? nil : currentLb,
                startedAt: mode == GoalMode.maintain || currentLb == nil ? nil : .now
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
