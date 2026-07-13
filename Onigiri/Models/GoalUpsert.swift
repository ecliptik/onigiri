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

    /// A goal needs a positive target below a known current weight —
    /// weight-gain/maintain goals aren't supported, and a goal saved
    /// without a current weight leaves the plan uncomputable everywhere.
    static func validate(targetLb: Double?, currentLb: Double?) -> Validation {
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
        goals: [GoalSettings],
        context: ModelContext
    ) {
        // The manual weight is only a fallback while Health has none.
        let fallback = healthWeightLb == nil ? manualWeightLb : nil
        if let goal = goals.first {
            goal.targetWeightLb = targetLb
            goal.targetDate = targetDate
            goal.fallbackCurrentWeightLb = fallback
        } else {
            context.insert(GoalSettings(
                targetWeightLb: targetLb,
                targetDate: targetDate,
                fallbackCurrentWeightLb: fallback
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
