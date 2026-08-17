// PDFKit is absent on watchOS; the kit builds there without the reader
// (the parsers themselves are pure and platform-free), exactly as
// LabelScan is gated on Vision.
#if canImport(PDFKit)
import Foundation
import PDFKit
import os

// nonisolated(unsafe) matching quickActionLog: the reader runs off the
// main actor, and Logger is thread-safe.
private nonisolated(unsafe) let menuLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "menu")

/// A nutrition document taken apart into the currency `MenuTableParser`
/// reads (`plans/PLAN-menu-import.md`).
public nonisolated struct MenuDocument: Sendable {
    /// One entry per page, each a page's positioned text runs.
    public let pages: [[LabelObservation]]
    /// A restaurant name worth prefilling the import sheet's source
    /// field with, or nil when the document doesn't say — which is the
    /// COMMON case, not the exceptional one. See `source(in:fileName:)`.
    public let suggestedSource: String?
}

/// The PDF half of the menu-import pipeline: one document in, the
/// parser's positioned runs out. Sits beside `MenuTableParser` the way
/// `LabelScan` sits beside `LabelParser`, and is mirrored by
/// `scripts/dump-pdf-text.swift`, which captures the test fixtures —
/// if the two drift, the tests stop testing this path.
/// `nonisolated` on purpose: the app target defaults to the main actor,
/// and this runs on a detached task — a six-page guide is ~1,100 text
/// runs and the caller is a view.
public nonisolated enum MenuDocumentReader {
    /// Big enough for any nutrition guide, small enough that a
    /// mis-shared video or photo library export can't be read into
    /// memory. (It IS read into memory, deliberately: parsing from Data
    /// means no copy into our container, no inbox, and nothing to sweep
    /// up afterwards — which is what makes the import one-shot by
    /// construction rather than by cleanup.)
    public static let sizeLimitBytes = 40 * 1024 * 1024

    public enum Failure: Error {
        case unreadable
        case tooLarge
        case notADocument
    }

    /// Reads a file URL that arrived from elsewhere — a share sheet, the
    /// Files app. Off the main actor: a six-page guide is ~1,100 text
    /// runs, and the caller is a view.
    /// How few runs on a page means "this page is a PICTURE of a table".
    /// Starbucks' guide is 3 pages carrying 22 text runs between them —
    /// the whole table is artwork, and PDFKit has nothing to hand the
    /// parser (2026-08-16). A real text page runs to hundreds.
    static let scannedPageRunLimit = 30

    static let ocrPageLimit = 12

    /// `read`, plus OCR for any page that turns out to be a picture.
    ///
    /// The parser takes OBSERVATIONS, not a PDF, and Vision produces the
    /// same normalized runs that PDFKit does — so a scanned guide can go
    /// down exactly the same path as a text one, with no second parser
    /// and no per-document special case. It costs a render and an OCR
    /// pass per page, which is why it only runs on pages that need it.
    public static func readOCR(_ url: URL) async throws -> MenuDocument {
        let document = try read(url)
        guard document.pages.contains(where: { $0.count < scannedPageRunLimit }) else {
            return document
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let pdf = PDFDocument(data: data) else { return document }

        // Bounded: OCR is ~1 s a page, and a share sheet that thinks for
        // half a minute reads as a hang. A scanned guide is usually a
        // few pages; a long one gives up its first dozen rather than
        // nothing.
        var budget = ocrPageLimit
        var pages = document.pages
        for index in pages.indices where pages[index].count < scannedPageRunLimit {
            guard budget > 0 else { break }
            budget -= 1
            guard let page = pdf.page(at: index), let image = render(page) else { continue }
            guard let scanned = try? await LabelScan.observations(from: image),
                  scanned.count > pages[index].count else { continue }
            pages[index] = scanned
        }
        return MenuDocument(pages: pages, suggestedSource: document.suggestedSource)
    }

    /// A page as pixels, big enough for Vision to read six-point table
    /// type: the long edge goes to `renderEdge`, which is where the
    /// figures on a scanned guide stop being legible below.
    static let renderEdge: CGFloat = 2_400

    static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = renderEdge / max(bounds.width, bounds.height)
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        // White, not transparent: an unpainted background composites to
        // black and Vision reads nothing off it.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    public static func read(_ url: URL) throws -> MenuDocument {
        // A URL handed over by another app is security-scoped; without
        // this the read fails with a permission error that looks exactly
        // like a corrupt file.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > sizeLimitBytes { throw Failure.tooLarge }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw Failure.unreadable
        }
        guard data.count <= sizeLimitBytes else { throw Failure.tooLarge }
        guard let document = PDFDocument(data: data) else { throw Failure.notADocument }

        var pages: [[LabelObservation]] = []
        for number in 0..<document.pageCount {
            guard let page = document.page(at: number) else { continue }
            pages.append(runs(on: page))
        }
        menuLog.notice("Read \(pages.count) page(s), \(pages.reduce(0) { $0 + $1.count }) runs")
        return MenuDocument(pages: pages, suggestedSource: source(in: document))
    }

    /// One page's positioned text runs, Vision-normalized (origin
    /// lower-left, unit square) so a PDF page and an OCR transcript are
    /// the same input to the parser.
    ///
    /// `selectionsByLine()` and NOT a `characterBounds(at:)` walk. On a
    /// real print-design PDF the per-glyph boxes are unusable: the "i"
    /// in "Spicy" reports 68 pt wide, and 185 of 2,133 glyphs on one
    /// page come back ZERO-HEIGHT (every "f" among them), so a run
    /// built from them both mis-measures and silently drops letters.
    /// Line selections return each positioned run with correct text and
    /// correct bounds — already one run per table cell.
    static func runs(on page: PDFPage) -> [LabelObservation] {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0,
              let whole = page.selection(for: bounds) else { return [] }
        return whole.selectionsByLine().compactMap { line in
            let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let rect = line.bounds(for: page)
            guard rect.width.isFinite, rect.height.isFinite, rect.height > 0 else { return nil }
            return LabelObservation(
                text: text,
                x: Double((rect.minX - bounds.minX) / bounds.width),
                y: Double((rect.minY - bounds.minY) / bounds.height),
                w: Double(rect.width / bounds.width),
                h: Double(rect.height / bounds.height))
        }
    }

    // MARK: Where the restaurant's name comes from

    /// Words that name the DOCUMENT rather than the restaurant. A source
    /// prefix of "Nutrition Guide — Greek Chicken" is worse than none.
    private static let generic: Set<String> = [
        "nutrition", "nutritional", "nutrition facts", "allergen", "allergens",
        "guide", "menu", "menus", "calories", "information", "food", "drinks",
        "nutrition and allergen guide", "nutrition guide", "untitled", "document",
    ]

    /// Best-effort, and it fails on the very first document this feature
    /// was built against: the Kwik Trip guide's PDF title is the InDesign
    /// filename `KT5_26_AN_STND_RECAN11148.indd`, its footer is the same
    /// job code, and its logo is artwork. So nil is an ordinary answer
    /// here and the import sheet ASKS — detection is the optimisation,
    /// the prompt is the contract.
    ///
    /// A web page saved through Safari's Share → Options → PDF titles
    /// itself after the page ("Nutrition & Allergens | Chick-fil-A"),
    /// which is why the title is split on separators and each part
    /// judged on its own.
    ///
    /// The TITLE only — never the filename. A filename is not the
    /// document saying who it belongs to, it is whatever the download
    /// was called, and "menu-kwiktrip — Greek Chicken" is the kind of
    /// wrong that a prompt would have avoided. Where a filename would
    /// have helped (Safari's export) the title already carries the same
    /// text.
    static func source(in document: PDFDocument) -> String? {
        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        for part in (title ?? "").split(whereSeparator: { "|—–:·".contains($0) }) {
            let candidate = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if isPlausibleSource(candidate) { return candidate }
        }
        return nil
    }

    /// The business a WEB ADDRESS names, when it names one.
    ///
    /// A shared link usually says whose menu it is before anything is
    /// read: `shakeshack.widen.net` is Shake Shack's, whatever the PDF's
    /// own metadata claims (the user, 2026-08-16). The label used is the
    /// first that is not infrastructure — a document host, a CDN, a site
    /// builder — because those name the SERVICE, not its customer.
    ///
    /// Squashed brand labels ("shakeshack", "kwiktrip") come back
    /// squashed; splitting them needs to know the words. This is the
    /// floor when nothing better is available, not the preferred answer.
    public static func source(fromHost host: String) -> String? {
        let infrastructure: Set<String> = [
            "www", "cdn", "assets", "static", "media", "files", "docs", "content",
            "widen", "widencdn", "cloudfront", "amazonaws", "s3", "squarespace",
            "wixstatic", "shopify", "wordpress", "sharepoint", "dropbox",
            "googleusercontent", "drive", "box", "azureedge", "akamaized",
            "net", "com", "org", "menu", "menus", "nutrition", "pdf",
        ]
        let labels = host.lowercased().split(separator: ".").map(String.init)
        guard let label = labels.first(where: { !infrastructure.contains($0) && $0.count >= 3 })
        else { return nil }
        let name = label.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        return isPlausibleSource(name) ? name : nil
    }

    public static func isPlausibleSource(_ candidate: String) -> Bool {
        guard candidate.count >= 2, candidate.count <= 40 else { return false }
        guard candidate.contains(where: \.isLetter) else { return false }
        // Job codes and export filenames: underscores, digit runs, a
        // leftover extension. None of these is a restaurant.
        if candidate.contains("_") { return false }
        if candidate.range(of: #"\d{3,}"#, options: .regularExpression) != nil { return false }
        let lowered = candidate.lowercased()
        for suffix in [".indd", ".pdf", ".docx", ".pages"] where lowered.hasSuffix(suffix) {
            return false
        }
        if generic.contains(lowered) { return false }
        // "Nutrition Guide 2026" and friends: every word is furniture.
        let words = lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard !words.isEmpty else { return false }
        return !words.allSatisfy { generic.contains($0) || $0.count <= 2 }
    }
}
#endif
