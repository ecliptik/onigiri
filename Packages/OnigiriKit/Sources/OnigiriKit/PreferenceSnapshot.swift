import Foundation

/// The Settings sheet's Cancel/reset mechanics, extracted pure: capture
/// the swept keys on open, detect session edits, restore on discard,
/// clear on reset. Keychain-backed secrets stay outside — the sheet
/// hand-mirrors those (they never live in defaults).
public enum PreferenceSnapshot {
    /// Missing key = was unset; restore removes it again.
    public static func capture(keys: [String], from defaults: UserDefaults) -> [String: Any] {
        var snapshot: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                snapshot[key] = value
            }
        }
        return snapshot
    }

    public static func restore(_ snapshot: [String: Any], keys: [String], to defaults: UserDefaults) {
        for key in keys {
            if let value = snapshot[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Any swept key moved since capture? Drives the sheet's swipe gate
    /// and the Cancel confirmation. Property-list values compare via
    /// their NSObject bridges.
    public static func differs(from snapshot: [String: Any], keys: [String], in defaults: UserDefaults) -> Bool {
        keys.contains { key in
            let now = defaults.object(forKey: key) as? NSObject
            let then = snapshot[key] as? NSObject
            return now != then
        }
    }

    public static func clear(keys: [String], in defaults: UserDefaults) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}

public extension SharedStore {
    /// Keys no code path writes any more. They stay named here for one
    /// reason: a device that used the setting before it was removed is
    /// still carrying the value, and the sweep below is what clears it.
    /// The Fixed budget style went away when the budget became the day's
    /// own burn — a number that stays put no matter what you measure is
    /// the opposite of one you earn (2026-08-02).
    static let retiredBudgetStyleKey = "budgetStyle"
    static let retiredActivityCreditKey = "activityCredit"
    static let retiredCustomExpectedBurnKey = "customExpectedBurnKcal"
    static let retiredActivityLevelKey = "activityLevel"

    /// Every preference key the Settings sheet's Cancel rewinds and the
    /// settings reset returns to defaults. ANY new @AppStorage key a
    /// Settings subscreen writes MUST join this list, or its edits
    /// silently escape both Cancel and Reset Settings (the kit test
    /// pins the known families). hasOnboarded is deliberately absent (a
    /// settings reset shouldn't replay onboarding); Reset All wipes the
    /// whole domain instead.
    static let settingsSweepKeys: [String] = [
        appearanceKey,
        // Retired with the Fixed budget style (2026-08-02) — kept in the
        // sweep so Reset Settings still clears a value written before
        // the setting went away. Nothing reads them.
        retiredBudgetStyleKey, retiredActivityCreditKey,
        retiredCustomExpectedBurnKey, retiredActivityLevelKey,
        waterServingKey, waterGoalKey,
        waterIconKey, foodIconKey, rewardIconKey, mealIconKey,
        sodiumLimitKey, balanceStyleKey,
        progressGaugesKey, showSodiumKey, showWaterKey,
        remindMealsKey, remindWaterKey, remindStreakKey,
        remindMealsMinuteKey, remindStreakMinuteKey,
        remindWaterMinute1Key, remindWaterMinute2Key, remindWaterMinute3Key,
        trackedMetric1Key, trackedMetric1ModeKey,
        trackedMetric1TargetKey, trackedMetric1IconKey,
        trackedMetric2Key, trackedMetric2ModeKey,
        trackedMetric2TargetKey, trackedMetric2IconKey,
        untrackedBelowKey, energyStatsStyleKey,
        textSearchSourceKey, onlineLookupsKey,
        holdToLogWaterKey,
        // Three that were written by Settings but never swept (found
        // 2026-08-17 by diffing every @AppStorage key in SettingsView
        // against this list). Being absent meant Cancel didn't put them
        // back, Reset Settings didn't clear them, and changing ONLY one
        // of them left `hasSessionEdits` false — so the sheet let you
        // swipe away and Cancel dismissed without so much as a prompt.
        intakeWordKey, foodsDefaultScopeKey,
        AIProviderSettings.estimateNutritionKey,
        weightUnitKey, waterUnitKey, sodiumUnitKey, weightBasisKey,
        AIProviderSettings.enabledKey, AIProviderSettings.hintDismissedKey,
        AIProviderSettings.fallbackOnDeviceKey,
        AIProviderSettings.providerKey, AIProviderSettings.anthropicModelKey,
        AIProviderSettings.openAIModelKey, AIProviderSettings.localModelKey,
        AIProviderSettings.localBaseURLKey, AIProviderSettings.localVisionKey,
    ]
}
