import Foundation
import PDFKit
import OnigiriKit
import os

// nonisolated(unsafe) matching quickActionLog: the reader runs off the
// main actor, and Logger is thread-safe.
private nonisolated(unsafe) let menuLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "menu")

/// A nutrition document taken apart into the currency `MenuTableParser`
/// reads (`plans/PLAN-menu-import.md`).
nonisolated struct MenuDocument: Sendable {
    /// One entry per page, each a page's positioned text runs.
    let pages: [[LabelObservation]]
    /// A restaurant name worth prefilling the import sheet's source
    /// field with, or nil when the document doesn't say — which is the
    /// COMMON case, not the exceptional one. See `source(in:fileName:)`.
    let suggestedSource: String?
}

/// The PDF half of the menu-import pipeline: one document in, the
/// parser's positioned runs out. Sits beside `MenuTableParser` the way
/// `LabelScan` sits beside `LabelParser`, and is mirrored by
/// `scripts/dump-pdf-text.swift`, which captures the test fixtures —
/// if the two drift, the tests stop testing this path.
/// `nonisolated` on purpose: the app target defaults to the main actor,
/// and this runs on a detached task — a six-page guide is ~1,100 text
/// runs and the caller is a view.
nonisolated enum MenuDocumentReader {
    /// Big enough for any nutrition guide, small enough that a
    /// mis-shared video or photo library export can't be read into
    /// memory. (It IS read into memory, deliberately: parsing from Data
    /// means no copy into our container, no inbox, and nothing to sweep
    /// up afterwards — which is what makes the import one-shot by
    /// construction rather than by cleanup.)
    static let sizeLimitBytes = 40 * 1024 * 1024

    enum Failure: Error {
        case unreadable
        case tooLarge
        case notADocument
    }

    /// Reads a file URL that arrived from elsewhere — a share sheet, the
    /// Files app. Off the main actor: a six-page guide is ~1,100 text
    /// runs, and the caller is a view.
    static func read(_ url: URL) throws -> MenuDocument {
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

    static func isPlausibleSource(_ candidate: String) -> Bool {
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
