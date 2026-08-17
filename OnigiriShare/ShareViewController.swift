import UIKit
import SwiftUI
import UniformTypeIdentifiers
import OnigiriKit

/// What this share turned out to be, once the attachment was read.
enum SharePayload {
    case document(URL)
    case image(URL)
    case link(URL)
}

/// The share-sheet door (`plans/PLAN-menu-import.md`).
///
/// Deliberately the thinnest thing that works: take what was shared, put
/// it in the app group, say so, exit. No parsing, no network, no web view
/// — a share extension runs under a much tighter memory ceiling than the
/// app, and resolving a link needs both a network call and a `WKWebView`
/// render, which is the app's job.
///
/// It does NOT try to launch Onigiri. `extensionContext.open` is not
/// supported from this extension point, and walking the responder chain
/// to find `UIApplication` is the trick that gets apps rejected. The app
/// drains `ShareInbox` on its next foreground, so nothing is lost — it
/// just waits.
final class ShareViewController: UIViewController {
    private let card = UIView()
    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let close = UIButton(type: .system)

    /// The user's copy (2026-08-16). One line for every menu route —
    /// a PDF, a file, or a page — because the next step is the same
    /// whichever door it came through, and the extension cannot take it
    /// for them.
    static let menuSaved = "Open Onigiri to log items from menu"

    /// Big enough for any nutrition guide or photo, small enough that a
    /// mis-shared video can't be read into an extension's memory.
    private static let sizeLimitBytes = 40 * 1024 * 1024

    override func viewDidLoad() {
        super.viewDidLoad()
        buildCard()
        // Claimed for as long as this sheet is up, so the app leaves the
        // deposit alone rather than opening a second copy of the same
        // import beside it.
        ShareInbox.claim()
        Task { await handleShare() }
    }

    private func handleShare() async {
        let providers = attachments()
        // Order matters: a Safari share of a PDF page can carry BOTH the
        // file and its URL, and the file is always the better answer —
        // it needs no network and can't 404. Likewise an image share can
        // carry a URL alongside the picture.
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }) {
            return await deposit(provider, type: .pdf, kind: .document,
                                 success: Self.menuSaved)
        }
        // The CONCRETE type the provider actually vends, not the
        // abstract `public.image`: `loadFileRepresentation` for an
        // abstract identifier hands back nil, which took the failure
        // branch and dismissed the sheet after two seconds — indis-
        // tinguishable from a crash, and reported as one (2026-08-16).
        if let (provider, concrete) = imageAttachment(in: providers) {
            return await deposit(provider, type: concrete, kind: .image,
                                 success: "Open Onigiri to log from this photo")
        }
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            return await depositLink(provider)
        }
        finish(message: "Nothing here Onigiri can read.", ok: false)
    }

    /// A Photos share vends `public.heic` or `public.jpeg`; a screenshot
    /// vends `public.png`. Any of them CONFORMS to `public.image`, but
    /// only the concrete one can be loaded.
    private func imageAttachment(in providers: [NSItemProvider]) -> (NSItemProvider, UTType)? {
        for provider in providers {
            for identifier in provider.registeredTypeIdentifiers {
                guard let type = UTType(identifier), type.conforms(to: .image),
                      type != .image else { continue }
                return (provider, type)
            }
        }
        return nil
    }

    private func attachments() -> [NSItemProvider] {
        ((extensionContext?.inputItems as? [NSExtensionItem]) ?? [])
            .flatMap { $0.attachments ?? [] }
    }

    private func deposit(
        _ provider: NSItemProvider, type: UTType, kind: ShareInbox.Kind, success: String
    ) async {
        guard let (data, name) = await loadFile(provider, type: type) else {
            return finish(message: "Couldn't read what was shared.", ok: false)
        }
        guard data.count <= Self.sizeLimitBytes else {
            return finish(message: "That file is too big for Onigiri to read.", ok: false)
        }
        // Deposited BEFORE the work starts, so an extension killed for
        // memory leaves the document for the app to find. Cleared only
        // once something is actually logged.
        guard ShareInbox.deposit(data, name: name, kind: kind) else {
            return finish(message: "Couldn't hand that to Onigiri.", ok: false)
        }
        // Photos are read HERE again. They were handed to the app for a
        // while on a diagnosis that turned out to be wrong: after
        // jetsam killed this extension during a full-size image decode
        // (real, and fixed by decoding at size), the next run produced a
        // bare title with no calories and that was read as "no room for
        // a model in 220 MB". It was not. The cause was
        // FoodIntelligence.isAvailable returning false for a remote
        // provider whose key had gone missing, with the fallback never
        // consulted — the same bug that had every AI feature dark in the
        // APP too (2026-08-16). The model was never the thing failing.
        //
        // The deposit above is still the net: an extension killed for
        // memory leaves the photo for the app to find on next
        // foreground, which is exactly the old behaviour reappearing on
        // its own.
        present(kind == .document ? .document(local(data, name: name, ext: "pdf"))
                                  : .image(local(data, name: name, ext: "img")))
    }

    /// The flow reads from a file, and the inbox copy is the app's, not
    /// ours to consume.
    private func local(_ data: Data, name: String, ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "share-\(UUID().uuidString).\(ext)")
        try? data.write(to: url, options: .atomic)
        return url
    }

    private func present(_ payload: SharePayload) {
        let flow = ShareFlow(payload: payload) { [weak self] logged in
            guard let self else { return }
            // Logged OR cancelled, the deposit goes: the net exists for a
            // process that died, and this one didn't. Cancelling here has
            // to cancel it everywhere, which was the whole complaint.
            ShareInbox.clear()
            ShareInbox.releaseClaim()
            self.extensionContext?.completeRequest(returningItems: [])
        }
        let host = UIHostingController(rootView: flow)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        card.isHidden = true
        view.backgroundColor = .systemBackground
    }

    private func depositLink(_ provider: NSItemProvider) async {
        guard let url = await loadURL(provider) else {
            return finish(message: "Couldn't read that link.", ok: false)
        }
        // A FILE url reached us as a url rather than as a file — read it
        // here, since the app can't reach another app's sandbox later.
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url), data.count <= Self.sizeLimitBytes else {
                return finish(message: "Couldn't read that file.", ok: false)
            }
            let kind: ShareInbox.Kind = url.pathExtension.lowercased() == "pdf" ? .document : .image
            guard ShareInbox.deposit(data, name: url.lastPathComponent, kind: kind) else {
                return finish(message: "Couldn't hand that to Onigiri.", ok: false)
            }
            return present(.document(local(data, name: url.lastPathComponent, ext: "pdf")))
        }
        guard url.scheme == "http" || url.scheme == "https" else {
            return finish(message: "Onigiri can't open that kind of link.", ok: false)
        }
        guard ShareInbox.deposit(link: url) else {
            return finish(message: "Couldn't hand that to Onigiri.", ok: false)
        }
        present(.link(url))
    }

    private func loadFile(_ provider: NSItemProvider, type: UTType) async -> (Data, String)? {
        if let file = await fileRepresentation(provider, type: type) { return file }
        // Belt and braces: some providers refuse a file representation
        // but hand over the object. This is the API the paste door uses,
        // and it is known to work on a Photos share.
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        let image: UIImage? = await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
        // pngData() re-encodes a full-size bitmap; the caller only needs
        // bytes it can hand to ImageIO, and JPEG at high quality is a
        // fraction of the peak memory.
        guard let data = image?.jpegData(compressionQuality: 0.9) else { return nil }
        return (data, "shared")
    }

    private func fileRepresentation(_ provider: NSItemProvider, type: UTType) async -> (Data, String)? {
        await withCheckedContinuation { continuation in
            // loadFileRepresentation, not loadDataRepresentation: the
            // sharing app owns the file and deletes it the moment the
            // completion returns, so the copy happens INSIDE the closure.
            _ = provider.loadFileRepresentation(
                forTypeIdentifier: type.identifier
            ) { url, _ in
                guard let url, let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (data, url.lastPathComponent))
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    /// A failure STAYS UP until dismissed. It used to linger two seconds
    /// and then complete the request on its own, which is how a plain
    /// "couldn't read that" became a bug report about the sheet silently
    /// crashing — a message nobody has time to read is worse than none
    /// (2026-08-16).
    private func finish(message: String, ok: Bool) {
        spinner.stopAnimating()
        spinner.isHidden = true
        label.text = message
        guard !ok else {
            // RELEASE, but do NOT clear: this is the hand-off path, and
            // what was deposited is exactly what the app must pick up.
            // Without this the claim taken at launch stays live for two
            // minutes and the app skips the inbox it is being handed —
            // "open Onigiri" led to nothing at all (2026-08-16). The
            // claim exists to stop the app racing a LIVE extension; this
            // one is finished.
            ShareInbox.releaseClaim()
            Task {
                try? await Task.sleep(for: .milliseconds(1100))
                extensionContext?.completeRequest(returningItems: [])
            }
            return
        }
        close.isHidden = false
    }

    private func buildCard() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 20
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        label.text = "Sending to Onigiri…"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        close.setTitle("Close", for: .normal)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.isHidden = true
        close.addAction(UIAction { [weak self] _ in
            // A failure the user dismissed is not a crash to recover
            // from, so nothing is left waiting for the app.
            ShareInbox.clear()
            ShareInbox.releaseClaim()
            self?.extensionContext?.completeRequest(returningItems: [])
        }, for: .touchUpInside)

        card.addSubview(spinner)
        card.addSubview(label)
        card.addSubview(close)

        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
            close.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            close.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -24),
        ])
    }
}
