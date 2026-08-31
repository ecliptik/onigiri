import Testing
@testable import OnigiriKit

/// Regression coverage for the watch-reinstall sync deadlock (field
/// report 2026-07-30, health-check audit 2026-08-31): a reinstalled
/// watch wipes its own library, but the phone's `sent` fingerprint still
/// held what the OLD installation received, so the next push computed an
/// identical fingerprint and skipped the send — the watch sat on "add
/// favorites or log food in the app" forever. `PhoneSyncService` itself
/// needs a live `WCSession` and can't be unit tested directly; this cache
/// holds the exact decision that bug lived in, extracted so it can be.
struct WatchSyncFingerprintCacheTests {
    @Test func freshCacheTreatsEveryFingerprintAsChanged() {
        let cache = WatchSyncFingerprintCache()
        #expect(!cache.mirrorUnchanged(from: 42))
        #expect(!cache.settingsUnchanged(from: 42))
        #expect(!cache.sentUnchanged(from: 42))
    }

    @Test func recordingAFingerprintMakesTheSameValueReadAsUnchanged() {
        var cache = WatchSyncFingerprintCache()
        cache.recordSent(42)
        #expect(cache.sentUnchanged(from: 42))
        #expect(!cache.sentUnchanged(from: 43))
    }

    /// The exact bug: a normal push records `sent`. Without an
    /// intervening invalidation, an IDENTICAL payload on the next push
    /// (nothing changed on the phone) correctly reads as unchanged —
    /// this is the skip-repeat-sends optimization working as designed.
    @Test func unrelatedPushesWithNoChangeStaySkippedByDesign() {
        var cache = WatchSyncFingerprintCache()
        cache.recordSent(42)
        #expect(cache.sentUnchanged(from: 42), "repeat pushes with nothing changed must still skip")
    }

    /// The fix: after a watch reinstall (or any pair/install state
    /// change), the SAME fingerprint that used to read as "unchanged"
    /// must now read as "changed" — the whole point being that
    /// `sessionWatchStateDidChange` invalidates `sent` even though
    /// nothing on the PHONE'S side changed at all.
    @Test func invalidateSentMakesAnIdenticalFingerprintReadAsChangedAgain() {
        var cache = WatchSyncFingerprintCache()
        cache.recordSent(42)
        #expect(cache.sentUnchanged(from: 42))

        cache.invalidateSent()

        #expect(!cache.sentUnchanged(from: 42), "a watch reinstall must force a re-send of the SAME payload")
    }

    /// `invalidateSent` must touch ONLY the sent half — the phone's own
    /// mirrored/settings state hasn't changed just because the WATCH was
    /// reinstalled, and re-mirroring would cost an unnecessary widget
    /// reload for no reason.
    @Test func invalidateSentLeavesMirroredAndSettingsAlone() {
        var cache = WatchSyncFingerprintCache()
        cache.recordMirrored(1)
        cache.recordSettings(2)
        cache.recordSent(3)

        cache.invalidateSent()

        #expect(cache.mirrorUnchanged(from: 1), "mirrored state describes the PHONE and must survive")
        #expect(cache.settingsUnchanged(from: 2), "settings state describes the PHONE and must survive")
        #expect(!cache.sentUnchanged(from: 3), "only the watch-facing sent fingerprint must be cleared")
    }

    /// The three fingerprints must be independently addressable — a
    /// mirror-only push (library recency bump) must not be confused with
    /// a settings change or a send, which is what lets the "scoped vs
    /// full" widget reload decision in PhoneSyncService.pushNow work.
    @Test func theThreeFingerprintsAreIndependent() {
        var cache = WatchSyncFingerprintCache()
        cache.recordMirrored(1)
        #expect(cache.mirrorUnchanged(from: 1))
        #expect(!cache.settingsUnchanged(from: 1))
        #expect(!cache.sentUnchanged(from: 1))
    }
}
