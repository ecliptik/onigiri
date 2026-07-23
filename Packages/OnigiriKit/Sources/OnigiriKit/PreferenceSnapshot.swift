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
    /// Every preference key the Settings sheet's Cancel rewinds and the
    /// settings reset returns to defaults. ANY new @AppStorage key a
    /// Settings subscreen writes MUST join this list, or its edits
    /// silently escape both Cancel and Reset Settings (the kit test
    /// pins the known families). hasOnboarded is deliberately absent (a
    /// settings reset shouldn't replay onboarding); Reset All wipes the
    /// whole domain instead.
    static let settingsSweepKeys: [String] = [
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
        weightUnitKey, waterUnitKey, sodiumUnitKey,
        AIProviderSettings.enabledKey, AIProviderSettings.hintDismissedKey,
        AIProviderSettings.providerKey, AIProviderSettings.anthropicModelKey,
        AIProviderSettings.openAIModelKey, AIProviderSettings.localModelKey,
        AIProviderSettings.localBaseURLKey, AIProviderSettings.localVisionKey,
    ]
}
