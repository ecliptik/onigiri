import Foundation
import WebKit
import OnigiriKit
import os

private nonisolated(unsafe) let linkLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "menu")

/// Turns a shared LINK into a PDF the menu parser can read
/// (`plans/PLAN-menu-import.md`).
///
/// Two cases, and the second is the interesting one:
///
/// - The link IS a PDF (the nutrition guide) — download it.
/// - The link is a PAGE (a restaurant's nutrition table in HTML) — load
///   it in a `WKWebView` and ask the web view to print itself with
///   `createPDF`. The page renders exactly as Safari draws it and we read
///   the resulting TEXT LAYER with the same `MenuTableParser`.
///
/// That second case is why this does not reopen the thing
/// `PLAN-screenshot-nutrition` vetoed. The veto was on "fetching
/// arbitrary URLs and parsing per-site HTML, which rots per restaurant" —
/// and there is no HTML parsing here at all. No selectors, no site
/// knowledge, nothing to rot: the browser does the layout and the
/// deterministic table parser does the rest, the same code path a
/// downloaded PDF takes. The fetch itself is the user's own explicit
/// share, not a background call.
@MainActor
enum MenuLinkLoader {
    enum Failure: Error {
        case unreachable
        case notAMenu
    }

    /// A page that never finishes loading must not hang the import sheet
    /// on a spinner forever.
    static let timeout: Duration = .seconds(25)

    /// Returns a local PDF file the caller owns and must delete.
    static func pdf(for url: URL) async throws -> URL {
        let data: Data
        if let downloaded = try? await downloadPDF(from: url) {
            linkLog.notice("Shared link was a PDF (\(downloaded.count) bytes)")
            data = downloaded
        } else {
            linkLog.notice("Shared link is a page — rendering it")
            let rendered = try await render(url)
            // A VIEWER page renders to a document with no table in it.
            // Shake Shack's guide is served through a JavaScript PDF
            // viewer, which paints each page into a canvas: the render
            // captures pictures with no text layer, and the share came
            // back "No nutrition table in that document" for a link that
            // really was a nutrition guide (the user, 2026-08-16).
            //
            // So when the render yields nothing readable, follow the PDF
            // the page itself names. That is a single general rule —
            // "this page points at a PDF, fetch it" — and not the
            // per-site HTML scraping PLAN-screenshot-nutrition vetoed:
            // no selectors, no structure, nothing per-site to rot. It
            // costs one extra request and only on a page that already
            // failed.
            if yieldsMenu(rendered) {
                data = rendered
            } else if let embedded = await embeddedPDF(pageAt: url) {
                linkLog.notice("Page had no table — followed the PDF it names (\(embedded.count) bytes)")
                data = embedded
            } else {
                data = rendered
            }
        }
        guard !data.isEmpty else { throw Failure.notAMenu }
        let file = FileManager.default.temporaryDirectory
            .appending(path: "shared-\(UUID().uuidString).pdf")
        try data.write(to: file, options: .atomic)
        return file
    }

    /// The page's TEXT, tags stripped.
    ///
    /// A rendered page only shows what CSS lets it show. Salt & Straw
    /// states its calories inside a COLLAPSED accordion, so the figure
    /// is in the document but not on the page, and rendering could never
    /// have found it (the user, 2026-08-16). The text is there either
    /// way.
    ///
    /// This is not the per-site scraping PLAN-screenshot-nutrition
    /// vetoed: there are no selectors and no knowledge of any site's
    /// markup — tags out, words left, and the same reader that handles a
    /// screenshot takes it from there.
    static func pageText(for url: URL) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        let mime = (response as? HTTPURLResponse)?.mimeType ?? response.mimeType ?? ""
        guard mime.localizedCaseInsensitiveContains("html") else { return nil }
        guard let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { return nil }
        return PageText.stripped(from: html)
    }

    /// Whether a rendered page actually produced a readable table. The
    /// parse is cheap (~0.1 s) beside the render that just ran.
    private static func yieldsMenu(_ data: Data) -> Bool {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "probe-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard (try? data.write(to: scratch, options: .atomic)) != nil,
              let document = try? MenuDocumentReader.read(scratch) else { return false }
        return !MenuTableParser.parse(pages: document.pages).isEmpty
    }

    /// The first URL the page names that really serves a PDF. Capped at
    /// a handful of candidates so a page full of links cannot turn one
    /// share into a crawl.
    private static func embeddedPDF(pageAt url: URL) async -> Data? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let pattern = /https?:\/\/[^\s"'<>()\\]{10,400}/
        var seen = Set<String>()
        var tried = 0
        for match in html.matches(of: pattern) {
            let text = String(match.output)
            let lower = text.lowercased()
            guard lower.contains(".pdf") || lower.contains("/pdf/") else { continue }
            guard seen.insert(text).inserted, let candidate = URL(string: text) else { continue }
            tried += 1
            if tried > 4 { break }
            if let pdf = try? await downloadPDF(from: candidate) { return pdf }
        }
        return nil
    }

    /// Only when the server actually says PDF — a 404 page is HTML and
    /// would otherwise be "downloaded" as a zero-item menu.
    private static func downloadPDF(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let mime = (response as? HTTPURLResponse)?.mimeType ?? response.mimeType ?? ""
        guard mime.localizedCaseInsensitiveContains("pdf") else { throw Failure.notAMenu }
        return data
    }

    private static func render(_ url: URL) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        // Ephemeral: a shared page must not deposit cookies or storage in
        // the app. Nothing here should outlive this render.
        configuration.websiteDataStore = .nonPersistent()
        // Tall on purpose. createPDF paginates what the web view has
        // LAID OUT, and a phone-sized frame makes a long nutrition table
        // reflow into a narrow single column — which parses as prose, not
        // as a table. A desktop-ish canvas keeps the columns columns.
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1280, height: 2400),
            configuration: configuration)
        let delegate = LoadWatcher()
        webView.navigationDelegate = delegate
        webView.load(URLRequest(url: url))

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await delegate.wait() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.unreachable
            }
            try await group.next()
            group.cancelAll()
        }
        // Layout settles after didFinish — a table sized by late CSS or
        // web fonts is still mid-reflow at that instant.
        try? await Task.sleep(for: .seconds(1))
        return try await webView.pdf()
    }
}

/// `WKNavigationDelegate` as an awaitable: resumes once, on whichever of
/// finish/fail arrives first.
@MainActor
private final class LoadWatcher: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var settled = false

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            if settled { continuation.resume(); return }
            self.continuation = continuation
        }
    }

    private func settle(_ result: Result<Void, Error>) {
        guard !settled else { return }
        settled = true
        switch result {
        case .success: continuation?.resume()
        case .failure(let error): continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settle(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        settle(.failure(error))
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        settle(.failure(error))
    }
}
