import Foundation

/// Tracks what was last mirrored locally / actually sent to the watch, so
/// repeat pushes with nothing changed skip the mirror write, widget
/// reload, and radio (`PhoneSyncService.pushNow`). Extracted out of that
/// class as a pure, `Sendable` value type (health-check audit,
/// 2026-08-31) so the invalidation rule below — the fix for a real,
/// previously-shipped production bug — has a regression test that
/// doesn't need a live `WCSession`.
///
/// Three fingerprints, tracked SEPARATELY on purpose:
/// - `mirrored`: the phone's own last-written-to-App-Group-defaults state
///   (widgets/Shortcuts read this; a library-only change like a recency
///   bump still needs to land here).
/// - `settings`: the goal+settings SLICE of the mirror (excludes the
///   library lists) — moving this triggers a full widget reload; moving
///   only the lists triggers a scoped one.
/// - `sent`: what a SPECIFIC watch installation last actually received
///   over WatchConnectivity.
///
/// `mirrored`/`settings` describe the PHONE's own state and stay valid
/// across a watch pairing change. `sent` describes the WATCH's state,
/// which a reinstall invalidates independently: a watch reinstall wipes
/// its library, but `sent` still held what the OLD installation was sent,
/// so the next push computed an identical fingerprint and SKIPPED the
/// send — the watch sat on "add favorites or log food in the app"
/// forever while the phone's library was full, and only a phone relaunch
/// (which cleared this in-memory state) or an unrelated library edit
/// broke the deadlock (field report 2026-07-30). `invalidateSent()` is
/// that fix, called from `sessionWatchStateDidChange` — this type makes
/// it impossible to invalidate the wrong slice by accident.
public struct WatchSyncFingerprintCache: Sendable, Equatable {
    public private(set) var mirrored: Int?
    public private(set) var settings: Int?
    public private(set) var sent: Int?

    public init() {}

    public func mirrorUnchanged(from fingerprint: Int) -> Bool { fingerprint == mirrored }
    public mutating func recordMirrored(_ fingerprint: Int) { mirrored = fingerprint }

    public func settingsUnchanged(from fingerprint: Int) -> Bool { fingerprint == settings }
    public mutating func recordSettings(_ fingerprint: Int) { settings = fingerprint }

    public func sentUnchanged(from fingerprint: Int) -> Bool { fingerprint == sent }
    public mutating func recordSent(_ fingerprint: Int) { sent = fingerprint }

    /// The watch-reinstall fix. Invalidates ONLY the sent-half — mirrored/
    /// settings stay put, since the phone's own state hasn't changed and
    /// re-mirroring would cost an unnecessary widget reload.
    public mutating func invalidateSent() { sent = nil }
}
