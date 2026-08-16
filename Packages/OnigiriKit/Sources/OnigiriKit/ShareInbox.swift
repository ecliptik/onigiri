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
/// One-shot survives this: `take()` MOVES the item out and the caller
/// deletes it after reading, so a document cannot be imported twice and
/// an abandoned share cannot pile up.
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

    /// Called by the extension. Returns false when the group container is
    /// unreachable, which the extension REPORTS rather than swallowing —
    /// a share that silently did nothing is worse than one that failed.
    @discardableResult
    public static func deposit(_ data: Data, name: String, kind: Kind) -> Bool {
        write(data, name: name, pathExtension: kind.pathExtension)
    }

    /// Called by the extension when the share was a link rather than a
    /// file. The app decides what it is — a PDF to download or a page to
    /// render — because that needs the network and a web view, and an
    /// extension has neither the memory budget nor the lifetime.
    @discardableResult
    public static func deposit(link: URL) -> Bool {
        guard let data = link.absoluteString.data(using: .utf8) else { return false }
        return write(data, name: link.host() ?? "link", pathExtension: linkExtension)
    }

    private static func write(_ data: Data, name: String, pathExtension: String) -> Bool {
        guard let directory else { return false }
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
            return true
        } catch {
            return false
        }
    }

    /// Called by the app on foreground. Takes the OLDEST waiting item;
    /// nil when nothing is waiting.
    ///
    /// A file is MOVED into the caller's temporary directory and the
    /// caller owns it from then on. A link marker is read and deleted
    /// here — there is nothing for the caller to clean up.
    public static func take() -> Item? {
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
            defer { try? FileManager.default.removeItem(at: oldest) }
            guard let data = try? Data(contentsOf: oldest),
                  let text = String(data: data, encoding: .utf8),
                  let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme == "http" || url.scheme == "https"
            else { return nil }
            return .link(url)
        }

        let destination = FileManager.default.temporaryDirectory
            .appending(path: oldest.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: oldest, to: destination)
        } catch {
            // Drop it rather than leave it to be retried forever on every
            // foreground.
            try? FileManager.default.removeItem(at: oldest)
            return nil
        }
        return oldest.pathExtension == Kind.document.pathExtension
            ? .document(destination)
            : .image(destination)
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
