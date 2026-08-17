import Testing
import Foundation
@testable import OnigiriKit

#if canImport(HealthKit)
import HealthKit

/// What "is Onigiri set up?" is allowed to ask about.
///
/// `PlanCache.needsSetup` is `shouldRequestAuthorization`, which is
/// `statusForAuthorizationRequest` — and that answers `.shouldRequest` when
/// ANY type in the sets it is handed has never been requested. Handed the
/// FULL share/read sets (as it was until 2026-08-16), adding a single type
/// flipped every existing install to "not set up" until the user was
/// re-prompted, so every widget and complication painted "Open Onigiri to
/// set up" over a working setup. That is the recorded reason
/// `HKWorkoutType` was rejected for the burn observer — the permission set
/// had become one that could never grow again.
///
/// These pin the split. Nothing here checks a live store; they check the
/// two properties that make the split safe, both of which are silent to
/// break.
struct HealthAuthorizationScopeTests {
    /// The invariant that actually matters. A core type NOT in the set
    /// `requestAuthorization` asks for could never be satisfied by
    /// granting permission, so `needsSetup` would answer true forever and
    /// every widget would sit on "Open Onigiri to set up" permanently —
    /// with the permission sheet, when it appeared, never mentioning the
    /// type that was blocking it.
    @MainActor
    @Test func theSetupCoreIsAlwaysAmongTheTypesWeActuallyRequest() {
        #expect(HealthKitService.setupCoreShareTypes.isSubset(of: HealthKitService.shareTypes))
        #expect(HealthKitService.setupCoreReadTypes.isSubset(of: HealthKitService.readTypes))
    }

    /// The core is FROZEN, and this test is the freeze.
    ///
    /// Every identifier below shipped in v1.0, which is the whole
    /// argument: no existing install can be missing one, so asking about
    /// them can never turn a working setup into an unconfigured one.
    /// Adding a type here re-arms the regression for everyone who
    /// installed before it — so this failing is not a formality to update,
    /// it is the decision being surfaced. Optional reads belong in
    /// `readTypes` alone, where absent means absent.
    @MainActor
    @Test func theSetupCoreIsFrozen() {
        #expect(HealthKitService.setupCoreShareTypes == [
            HKQuantityType(.dietaryEnergyConsumed),
        ])
        #expect(HealthKitService.setupCoreReadTypes == [
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
        ])
    }

    /// The core is a SUBSET, not the whole thing — the split is only worth
    /// having while `readTypes` carries types the core doesn't. If these
    /// ever converge, the decoupling has been quietly undone and
    /// `needsSetup` is back to tracking every type in the app.
    @MainActor
    @Test func theFullReadSetStaysWiderThanTheCore() {
        #expect(HealthKitService.readTypes.count > HealthKitService.setupCoreReadTypes.count)
        // The body metrics the resting estimate rides are the standing
        // example: read, never written, and never a reason to call the app
        // unconfigured.
        #expect(HealthKitService.readTypes.contains(HKQuantityType(.height)))
        #expect(!HealthKitService.setupCoreReadTypes.contains(HKQuantityType(.height)))
    }
}
#endif
