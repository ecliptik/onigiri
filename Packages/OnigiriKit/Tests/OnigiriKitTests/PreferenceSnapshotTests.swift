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
        // Onboarding deliberately stays OUT (reset must not replay it).
        #expect(!keys.contains(SharedStore.hasOnboardedKey))
        #expect(keys.count == 42)
    }
}
