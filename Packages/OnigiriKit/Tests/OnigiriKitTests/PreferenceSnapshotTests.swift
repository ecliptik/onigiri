import Foundation
import Testing
@testable import OnigiriKit

/// The Settings sheet's Cancel/reset mechanics — capture, dirtiness,
/// restore (including remove-what-was-unset), clear.
struct PreferenceSnapshotTests {
    /// A throwaway suite per test; parallel tests must not share one.
    private func makeDefaults() -> UserDefaults {
        let name = "PreferenceSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let keys = ["alpha", "beta", "gamma"]

    @Test func restoreRoundTripsValuesAndRemovesWhatWasUnset() {
        let defaults = makeDefaults()
        defaults.set("one", forKey: "alpha")
        defaults.set(2.5, forKey: "beta")
        // gamma deliberately unset at capture time.

        let snapshot = PreferenceSnapshot.capture(keys: keys, from: defaults)
        defaults.set("changed", forKey: "alpha")
        defaults.removeObject(forKey: "beta")
        defaults.set(true, forKey: "gamma")

        PreferenceSnapshot.restore(snapshot, keys: keys, to: defaults)
        #expect(defaults.string(forKey: "alpha") == "one")
        #expect(defaults.double(forKey: "beta") == 2.5)
        // Unset-at-capture must come back UNSET, not survive as true —
        // a restore that only writes values leaves new keys behind.
        #expect(defaults.object(forKey: "gamma") == nil)
    }

    @Test func differsDetectsEachKindOfEdit() {
        let defaults = makeDefaults()
        defaults.set("one", forKey: "alpha")
        let snapshot = PreferenceSnapshot.capture(keys: keys, from: defaults)

        #expect(!PreferenceSnapshot.differs(from: snapshot, keys: keys, in: defaults))
        defaults.set("two", forKey: "alpha")
        #expect(PreferenceSnapshot.differs(from: snapshot, keys: keys, in: defaults))
        defaults.set("one", forKey: "alpha")
        defaults.set(1, forKey: "gamma")
        #expect(PreferenceSnapshot.differs(from: snapshot, keys: keys, in: defaults))
        defaults.removeObject(forKey: "gamma")
        #expect(!PreferenceSnapshot.differs(from: snapshot, keys: keys, in: defaults))
        // A key OUTSIDE the swept list must not read as dirty.
        defaults.set("stray", forKey: "delta")
        #expect(!PreferenceSnapshot.differs(from: snapshot, keys: keys, in: defaults))
    }

    @Test func clearRemovesEverySweptKeyOnly() {
        let defaults = makeDefaults()
        for key in keys { defaults.set("x", forKey: key) }
        defaults.set("keep", forKey: "delta")
        PreferenceSnapshot.clear(keys: keys, in: defaults)
        for key in keys {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(defaults.string(forKey: "delta") == "keep")
    }

    /// The sweep list is a manually-maintained invariant (a subscreen
    /// key missing from it silently escapes Cancel AND Reset Settings).
    /// Pin the known families so at least their removal fails loudly.
    @Test func sweepListCoversTheKnownSettingFamilies() {
        let keys = Set(SharedStore.settingsSweepKeys)
        // Units (they escaped the sweep once — 2026-07-22).
        #expect(keys.contains(SharedStore.weightUnitKey))
        #expect(keys.contains(SharedStore.waterUnitKey))
        #expect(keys.contains(SharedStore.sodiumUnitKey))
        // Which weight the deficit target follows (2026-08-08). Defaults
        // ON to the average, so a reset that left it behind would strand
        // an explicit "last weigh-in" the user can no longer see.
        #expect(keys.contains(SharedStore.weightBasisKey))
        // Reminders: toggles and all five minute keys.
        for key in [SharedStore.remindMealsKey, SharedStore.remindWaterKey,
                    SharedStore.remindStreakKey, SharedStore.remindMealsMinuteKey,
                    SharedStore.remindStreakMinuteKey, SharedStore.remindWaterMinute1Key,
                    SharedStore.remindWaterMinute2Key, SharedStore.remindWaterMinute3Key] {
            #expect(keys.contains(key))
        }
        // Tracked metrics, water, online, AI families (spot pins).
        #expect(keys.contains(SharedStore.trackedMetric1Key))
        #expect(keys.contains(SharedStore.trackedMetric2IconKey))
        #expect(keys.contains(SharedStore.waterGoalKey))
        #expect(keys.contains(SharedStore.untrackedBelowKey))
        #expect(keys.contains(SharedStore.onlineLookupsKey))
        #expect(keys.contains(AIProviderSettings.enabledKey))
        #expect(keys.contains(AIProviderSettings.localVisionKey))
        // The unreachable-provider fallback (2026-08-07). It defaults
        // ON, so a reset that left it behind would strand an explicit
        // OFF that the user could no longer see in a fresh Settings.
        #expect(keys.contains(AIProviderSettings.fallbackOnDeviceKey))
        // Icons, including the meal mark (2026-07-23).
        #expect(keys.contains(SharedStore.mealIconKey))
        // Theme (2026-07-29) — an Appearance subscreen key like the icons.
        #expect(keys.contains(SharedStore.appearanceKey))
        // Budget style (2026-07-30) — set in the Goal tab, but the same
        // rule applies: outside this list they'd escape Cancel and Reset.
        #expect(keys.contains(SharedStore.retiredBudgetStyleKey))
        #expect(keys.contains(SharedStore.retiredCustomExpectedBurnKey))
        // The retired key stays swept: it still feeds BudgetStyle.resolve,
        // so a reset that left it behind would resurrect an old choice.
        #expect(keys.contains(SharedStore.retiredActivityCreditKey))
        // Onboarding deliberately stays OUT (reset must not replay it).
        #expect(!keys.contains(SharedStore.hasOnboardedKey))
        // The three that were missing until 2026-08-17. Each is written
        // by a Settings subscreen — Appearance's two pickers and the AI
        // screen's Estimate toggle — and being absent from this list
        // meant Cancel didn't restore them, Reset Settings didn't clear
        // them, and editing only one of them left the sheet thinking
        // nothing had changed.
        #expect(keys.contains(SharedStore.intakeWordKey))
        #expect(keys.contains(SharedStore.foodsDefaultScopeKey))
        #expect(keys.contains(AIProviderSettings.estimateNutritionKey))
        // A tripwire for edits to THIS list, and deliberately not more
        // than that: it cannot see a setting that never joined the list
        // in the first place, which is exactly how the three above hid.
        // That check is a diff of every `@AppStorage` key in
        // SettingsView against this array, and it lives in no test —
        // run it by hand when adding a setting.
        #expect(keys.count == 53)
    }
}
