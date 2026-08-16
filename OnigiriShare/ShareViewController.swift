import UIKit
import UniformTypeIdentifiers
import OnigiriKit

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
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) {
            return await deposit(provider, type: .image, kind: .image,
                                 success: "Open Onigiri to log from this photo")
        }
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            return await depositLink(provider)
        }
        finish(message: "Nothing here Onigiri can read.", ok: false)
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
        guard ShareInbox.deposit(data, name: name, kind: kind) else {
            return finish(message: "Couldn't hand that to Onigiri.", ok: false)
        }
        finish(message: success, ok: true)
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
            return finish(message: Self.menuSaved, ok: true)
        }
        guard url.scheme == "http" || url.scheme == "https" else {
            return finish(message: "Onigiri can't open that kind of link.", ok: false)
        }
        guard ShareInbox.deposit(link: url) else {
            return finish(message: "Couldn't hand that to Onigiri.", ok: false)
        }
        finish(message: Self.menuSaved, ok: true)
    }

    private func loadFile(_ provider: NSItemProvider, type: UTType) async -> (Data, String)? {
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

    private func finish(message: String, ok: Bool) {
        spinner.stopAnimating()
        spinner.isHidden = true
        label.text = message
        // Long enough to read; a failure lingers because it is asking the
        // user to do something differently.
        let linger: Duration = ok ? .milliseconds(1100) : .seconds(2)
        Task {
            try? await Task.sleep(for: linger)
            extensionContext?.completeRequest(returningItems: [])
        }
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

        card.addSubview(spinner)
        card.addSubview(label)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
        ])
    }
}
