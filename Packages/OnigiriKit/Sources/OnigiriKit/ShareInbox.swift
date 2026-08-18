import Foundation

/// The hand-off between the share extension and the app
/// (`plans/PLAN-menu-import.md` Part A2).
///
/// The extension writes; the app drains on foreground. It is a DROPBOX and
/// not a message, on purpose: a share extension cannot be relied on to
/// open its host app — `extensionContext.open` is unsupported for this
/// extension point and the responder-chain walk to reach `UIApplication`
/// is the trick that gets apps rejected. So the extension never assumes
/// the app will come up; the app finds what is waiting whenever it next
/// runs.
///
/// One-shot survives this: `take()` hands out a COPY and the original
/// stays in the dropbox until the import sheet closes
/// (`SharedImport.cleanUp`), so an app killed mid-import still finds the
/// document on its next foreground; the drain guard (`sharedImport ==
/// nil`) keeps one take from being offered twice while the sheet is up.
/// Moving-on-take was the old contract, and it silently lost the share
/// to any mid-import death (audit, 2026-08-17).
public enum ShareInbox {
    /// What was shared. Three kinds because the share sheet offers three
    /// useful things and they route to different readers: a menu
    /// document, a page that has to become one, and a photo, which goes
    /// to the image cascade the paste door already uses.
    public enum Item: Sendable, Equatable {
        /// A local PDF file, ready for `MenuTableParser`.
        case document(URL)
        /// A local image, for `FoodImageReader`.
        case image(URL)
        /// A remote http(s) page or PDF the app must resolve first.
        case link(URL)
    }

    public enum Kind: Sendable {
        case document
        case image

        var pathExtension: String {
            switch self {
            case .document: "pdf"
            case .image: "img"
            }
        }
    }

    /// A link is stored as a tiny marker file rather than in defaults, so
    /// it queues and orders exactly like a shared file does.
    static let linkExtension = "weburl"

    /// Inside the app group so both processes see it. A subdirectory
    /// rather than the group root: the group also holds the shared
    /// defaults, and a stray document beside them is how a "clear
    /// everything" sweep one day deletes the wrong thing.
    public static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appending(path: "ShareInbox", directoryHint: .isDirectory)
    }

    /// Called by the extension. Returns the deposited file's NAME — the
    /// session keeps it so its own cleanup can be scoped to what it
    /// wrote (`clear(files:)`) — or nil when the group container is
    /// unreachable, which the extension REPORTS rather than swallowing:
    /// a share that silently did nothing is worse than one that failed.
    @discardableResult
    public static func deposit(_ data: Data, name: String, kind: Kind) -> String? {
        write(data, name: name, pathExtension: kind.pathExtension)
    }

    /// Called by the extension when the share was a link rather than a
    /// file. The app decides what it is — a PDF to download or a page to
    /// render — because that needs the network and a web view, and an
    /// extension has neither the memory budget nor the lifetime.
    @discardableResult
    public static func deposit(link: URL) -> String? {
        guard let data = link.absoluteString.data(using: .utf8) else { return nil }
        return write(data, name: link.host() ?? "link", pathExtension: linkExtension)
    }

    private static func write(_ data: Data, name: String, pathExtension: String) -> String? {
        guard let directory else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            // Distinct per share: two menus shared before the app is
            // opened must both survive, and a name collision would eat
            // one silently.
            let file = directory
                .appending(path: "\(UUID().uuidString)-\(safe(name))")
                .appendingPathExtension(pathExtension)
            try data.write(to: file, options: .atomic)
            return file.lastPathComponent
        } catch {
            return nil
        }
    }

    /// What `take()` hands the app: the item to import, plus the inbox
    /// original backing it. The original stays in the dropbox until the
    /// import sheet's `cleanUp` deletes it, so a kill mid-import leaves
    /// the share recoverable on the next foreground.
    public struct Taken {
        public let item: Item
        public let inboxFile: URL
    }

    /// Called by the app on foreground. Returns the OLDEST waiting item;
    /// nil when nothing is waiting.
    ///
    /// A file is COPIED into the caller's temporary directory — not
    /// moved: the original is the crash net, and it lives until the
    /// caller's `cleanUp` (a re-offer after a mid-import death costs one
    /// duplicate prompt; the old move lost the document outright). A
    /// link marker likewise stays until `cleanUp`; only a malformed one
    /// is deleted here, or it would be retried on every foreground
    /// forever.
    public static func take() -> Taken? {
        guard let directory else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        let oldest = files
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return da < db
            }
            .first
        guard let oldest else { return nil }

        if oldest.pathExtension == linkExtension {
            guard let data = try? Data(contentsOf: oldest),
                  let text = String(data: data, encoding: .utf8),
                  let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme == "http" || url.scheme == "https"
            else {
                try? FileManager.default.removeItem(at: oldest)
                return nil
            }
            return Taken(item: .link(url), inboxFile: oldest)
        }

        let destination = FileManager.default.temporaryDirectory
            .appending(path: oldest.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: oldest, to: destination)
        } catch {
            // Drop it rather than leave it to be retried forever on every
            // foreground.
            try? FileManager.default.removeItem(at: oldest)
            return nil
        }
        return Taken(
            item: oldest.pathExtension == Kind.document.pathExtension
                ? .document(destination)
                : .image(destination),
            inboxFile: oldest
        )
    }

    // MARK: Who owns the work

    /// While the extension is on screen it OWNS what it deposited, and
    /// the app must not also pick it up.
    ///
    /// Without this the safety-net deposit becomes a duplicate: leave the
    /// share sheet open, switch to Onigiri, and the same import is
    /// showing in both places — then cancelling one leaves the other
    /// (the user, 2026-08-16).
    ///
    /// A timestamp rather than a lock, because the case this net exists
    /// for is a process that DIES: a killed extension can release
    /// nothing, so the claim has to expire on its own or the document is
    /// stranded forever.
    private static let claimKey = "shareInbox.claimedAt"
    static let claimSeconds: TimeInterval = 120

    public static func claim() {
        SharedStore.defaults.set(Date.now.timeIntervalSince1970, forKey: claimKey)
    }

    public static func releaseClaim() {
        SharedStore.defaults.removeObject(forKey: claimKey)
    }

    /// True while an extension is alive and working on what it left here.
    public static var isClaimed: Bool {
        let at = SharedStore.defaults.double(forKey: claimKey)
        guard at > 0 else { return false }
        return Date.now.timeIntervalSince1970 - at < claimSeconds
    }

    /// Called by the extension once its own share is finished — logged,
    /// cancelled, or a failure the user dismissed: nothing from THIS
    /// session should be left waiting for the app. Scoped to the files
    /// the session deposited, never a directory sweep: the dropbox can
    /// hold a DIFFERENT session's deposit (share menu A, swipe the sheet
    /// away — A's net is queued for the app — then share and finish B),
    /// and the sweep this replaced deleted A silently on B's finish
    /// (audit, 2026-08-17). "Two menus shared before the app is opened
    /// must both survive" is `write`'s own contract; this is the other
    /// half of keeping it.
    public static func clear(files: [String]) {
        guard let directory else { return }
        for name in files {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// A shared file name is untrusted input — it comes from whatever app
    /// did the sharing — so it never reaches the filesystem unfiltered.
    static func safe(_ name: String) -> String {
        let trimmed = name
            .replacing(/\.(pdf|jpe?g|png|heic|webp)$/.ignoresCase(), with: "")
            .prefix(48)
        let cleaned = trimmed.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let joined = String(cleaned).split(separator: "-").joined(separator: "-")
        return joined.isEmpty ? "shared" : joined
    }
}
