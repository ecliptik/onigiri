// PDFKit is absent on watchOS; the kit builds there without the reader
// (the parsers themselves are pure and platform-free), exactly as
// LabelScan is gated on Vision.
#if canImport(PDFKit)
import Foundation
import PDFKit
import os

// `nonisolated`, not `nonisolated(unsafe)`: the opt-out from the app
// target's main-actor default is the load-bearing half (the reader runs
// detached); Logger is Sendable, so the unsafe half is now a warning.
private nonisolated let menuLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "menu")

/// A nutrition document taken apart into the currency `MenuTableParser`
/// reads (`plans/PLAN-menu-import.md`).
public nonisolated struct MenuDocument: Sendable {
    /// One entry per page, each a page's positioned text runs.
    public let pages: [[LabelObservation]]
    /// A restaurant name worth prefilling the import sheet's source
    /// field with, or nil when the document doesn't say — which is the
    /// COMMON case, not the exceptional one. See `source(in:fileName:)`.
    public let suggestedSource: String?
    /// What each stage of the OCR escalation actually produced, in
    /// DEBUG. Nil in release and nil when no OCR ran.
    ///
    /// Kept, in the spirit of `HealthKitService.diagnoseIntake`: this
    /// path escalates through three readings behind a memory cap and a
    /// pass budget, and when it comes back empty NOTHING on screen says
    /// which stage gave up. The simulator read somisomi's page and the
    /// phone did not, and the only way to tell those apart was to put
    /// the counts in the failure message (2026-08-23).
    public let scanNote: String?
    /// What OCR produced, in DEBUG, EVEN WHERE IT WAS REJECTED — the
    /// transcript `pages` did not keep. A rejected reading is the one
    /// worth looking at.
    public let debugScanned: [[LabelObservation]]?

    public init(
        pages: [[LabelObservation]], suggestedSource: String?,
        scanNote: String? = nil, debugScanned: [[LabelObservation]]? = nil
    ) {
        self.pages = pages
        self.suggestedSource = suggestedSource
        self.scanNote = scanNote
        self.debugScanned = debugScanned
    }
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

    /// Every Vision pass this document may spend, across strips and both
    /// orientations. The page cap above still says which PAGES are
    /// eligible; this one keeps a tall page cut into eight strips and
    /// read twice from turning a share sheet into a half-minute hang.
    static let ocrImageLimit = 24

    /// `read`, plus OCR for any page that turns out to be a picture.
    ///
    /// The parser takes OBSERVATIONS, not a PDF, and Vision produces the
    /// same normalized runs that PDFKit does — so a scanned guide can go
    /// down exactly the same path as a text one, with no second parser
    /// and no per-document special case. It costs a render and an OCR
    /// pass per page, which is why it only runs on pages that need it.
    ///
    /// TWO triggers, and the second is what a WEB PAGE needs. "Too few
    /// runs to be text" identifies a scanned guide, and it can never
    /// fire on a rendered page: nav, footer and cookie banner put
    /// somisomi's nutrition page at 41 runs — above the limit — while
    /// its two tables are `<img>` PNGs with no text layer at all, so the
    /// share came back "no nutrition table" for a page that is nothing
    /// but nutrition tables (the user, 2026-08-23). The honest test
    /// there is the parse that just came back EMPTY, which is also what
    /// `MenuLinkLoader` uses to decide a render failed. Asked of the
    /// whole document, so a guide whose table pages already parse never
    /// pays for its allergen pages.
    public static func readOCR(_ url: URL) async throws -> MenuDocument {
        let document = try read(url)
        let looksScanned = { (page: [LabelObservation]) in page.count < scannedPageRunLimit }
        let readsAsNothing = MenuTableParser.parse(pages: document.pages).isEmpty
        guard readsAsNothing || document.pages.contains(where: looksScanned) else {
            return document
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let pdf = PDFDocument(data: data) else { return document }

        // Bounded: OCR is ~1 s a pass, and a share sheet that thinks for
        // half a minute reads as a hang. A scanned guide is usually a
        // few pages; a long one gives up its first dozen rather than
        // nothing.
        var pages = document.pages
        var budget = ocrImageLimit
        var pagesLeft = ocrPageLimit
        var note: [String] = []
        var scannedPages: [[LabelObservation]] = []
        for index in pages.indices where readsAsNothing || looksScanned(pages[index]) {
            guard pagesLeft > 0, budget > 0 else { break }
            pagesLeft -= 1
            guard let page = pdf.page(at: index) else { continue }
            var stages: [String] = []
            let scanned = await observations(
                on: page, existing: pages[index], budget: &budget, stages: &stages)
            #if DEBUG
            scannedPages.append(scanned)
            #endif
            #if DEBUG
            note.append("p\(index):" + stages.joined(separator: ","))
            #endif
            let reads = !MenuTableParser.parse(scanned).isEmpty
            if looksScanned(pages[index]) {
                // A picture of a page: anything Vision finds beats the
                // handful of runs PDFKit had.
                guard reads || scanned.count > pages[index].count else { continue }
            } else {
                // A page that HAS a text layer keeps it unless the OCR
                // produced the table that layer could not. A shared
                // article is read as PROSE further down the pipeline
                // (`SharedPageReader`), off these same runs, and swapping
                // them for a transcript that also holds no table changes
                // that reading for nothing.
                guard reads else { continue }
            }
            pages[index] = scanned
        }
        #if DEBUG
        note.append("left=\(budget)")
        #endif
        return MenuDocument(
            pages: pages, suggestedSource: document.suggestedSource,
            scanNote: note.isEmpty ? nil : note.joined(separator: " "),
            debugScanned: scannedPages.isEmpty ? nil : scannedPages)
    }

    /// One page read by Vision, in page-normalized coordinates.
    ///
    /// Two things a single `LabelScan.observations` call cannot do:
    ///
    /// - **Vision downsamples what it is given**, so raising
    ///   `renderEdge` on a tall page buys nothing — the extra pixels are
    ///   thrown away before recognition. A rendered web page is often
    ///   2–3 screens tall, and somisomi's eleven column names came back
    ///   as one run of `!!!!!!!!!!` whether the page was rendered at
    ///   2,400 or at 10,000. It is cut into strips instead, each
    ///   `readableWidth` across, which is what puts real pixels on
    ///   six-point table type.
    /// - **A turned column name reads correctly in exactly ONE of two
    ///   orientations.** somisomi sets its eleven headers on a diagonal
    ///   and Vision reads most of them upside down — `SATURATED FAT`
    ///   comes back as `AVS G3AYUNEVS`. Every one of them is clean in
    ///   the 180° pass, which costs a second read of the same pixels and
    ///   nothing else.
    ///
    /// The flipped pass mostly REPLACES a run it overlaps: on an
    /// ordinary upright page it reads noise, and noise that loses every
    /// comparison changes nothing. It may ADD a run only where it names
    /// a column and the upright pass found nothing at all — see
    /// `readingBetterOf`, and the device that returns silence where the
    /// simulator returns wreckage.
    ///
    /// It ESCALATES rather than always paying for this: a page whose
    /// whole-page reading already yields a table returns there in one
    /// pass, exactly as a scanned guide did before, and the strips are
    /// turned over only where `hidesText` says there is pictured text to
    /// turn.
    ///
    /// What is NOT a gate is "did this parse". A table parses from the
    /// upright strips alone — with four of its eleven headings garbled
    /// into nothing, so sodium held the carbohydrate figures and the
    /// reading was plausible and wrong. Stopping at the first transcript
    /// that yields rows is stopping at the first that yields WRONG rows,
    /// which is the failure this whole path exists to avoid. Reading the
    /// second orientation can only help, because the merge replaces a
    /// run solely with a MORE legible reading of the same box.
    static func observations(
        on page: PDFPage, existing: [LabelObservation], budget: inout Int,
        stages: inout [String]
    ) async -> [LabelObservation] {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0, budget > 0 else {
            stages.append("skip")
            return []
        }
        budget -= 1
        var whole: [LabelObservation] = []
        if let image = render(page),
           let runs = try? await LabelScan.observations(from: image) {
            whole = runs
            if !MenuTableParser.parse(runs).isEmpty {
                stages.append("whole=\(runs.count)!")
                return runs
            }
        }
        stages.append("whole=\(whole.count)")
        // Strip-normalized, kept so the flipped pass below has something
        // to be compared against. The IMAGES are not kept: eight strips
        // of five megapixels is most of a phone's memory for a share
        // sheet, and re-rendering one costs a fraction of reading it.
        let strips = strips(of: bounds)
        var perStrip: [[LabelObservation]] = []
        var renderFailures = 0
        for strip in strips {
            guard budget > 0 else { break }
            guard let image = render(page, strip: strip) else { renderFailures += 1; break }
            budget -= 1
            perStrip.append((try? await LabelScan.observations(from: image)) ?? [])
        }
        stages.append("strips=\(strips.count)/\(perStrip.count)"
                      + (renderFailures > 0 ? "/rf\(renderFailures)" : ""))
        // The SECOND orientation is spent only on a page that is HIDING
        // text — one the strips found substantially more on than PDFKit
        // could see, which means ink the text layer does not account
        // for. somisomi's render carries 41 runs of navigation over 458
        // read off its two table PNGs; a shared ARTICLE reads about the
        // same either way, and turning it over would buy nothing.
        //
        // The question cannot be asked any earlier. At the whole-page
        // size Vision hands back 46 runs for the very page whose strips
        // hold 458 — a pictured table is invisible until there are
        // enough pixels on it, so a cheap probe cannot tell these two
        // pages apart.
        let upright = merge(perStrip, of: strips, in: bounds)
        stages.append("up=\(upright.count)")
        guard hidesText(upright, beyond: existing) else {
            stages.append("nothidden")
            return upright.count > whole.count ? upright : whole
        }
        var added = 0
        for (index, strip) in strips.enumerated() where index < perStrip.count {
            guard budget > 0, let image = render(page, strip: strip),
                  let flipped = turned(image) else { break }
            budget -= 1
            guard let second = try? await LabelScan.observations(from: flipped) else { continue }
            let before = perStrip[index].count
            perStrip[index] = readingBetterOf(perStrip[index], flipped: second)
            added += perStrip[index].count - before
        }
        let stripped = merge(perStrip, of: strips, in: bounds)
        let rows = MenuTableParser.parse(stripped).count
        stages.append("turned=\(stripped.count)/add\(added)/rows\(rows)")
        if rows > 0 { return stripped }

        let withHeader = await readingHeader(
            of: page, in: bounds, over: stripped, budget: &budget)
        let headerRows = MenuTableParser.parse(withHeader).count
        stages.append("hdr=\(withHeader.count)/rows\(headerRows)")
        if headerRows > 0 { return withHeader }
        return withHeader.count > whole.count ? withHeader : whole
    }

    /// Whether Vision found materially more on the page than its own
    /// text layer holds.
    static func hidesText(
        _ scanned: [LabelObservation], beyond existing: [LabelObservation]
    ) -> Bool {
        scanned.count > max(existing.count * 2, existing.count + 20)
    }

    /// Every strip's runs in the page's own coordinates, with the seam
    /// duplicates dropped: the strips overlap, so a row that straddles
    /// one is read twice, and left in, its numbers are counted twice and
    /// the row stops matching its columns.
    static func merge(
        _ perStrip: [[LabelObservation]], of strips: [CGRect], in bounds: CGRect
    ) -> [LabelObservation] {
        var merged: [LabelObservation] = []
        for (runs, strip) in zip(perStrip, strips) {
            for run in runs.map({ placed($0, of: strip, in: bounds) })
            where !merged.contains(where: { $0.text == run.text && covers($0, run) }) {
                merged.append(run)
            }
        }
        return merged
    }

    /// How wide a page has to be rendered before Vision can read
    /// six-point table type off it, and how many pixels it may hand
    /// Vision at once.
    ///
    /// The second number is the surprising one. **Vision downsamples
    /// what it is given**, so rendering a tall page bigger does not make
    /// its small type readable — measured on the somisomi sheet, a
    /// 4,000 × 3,201 render lost the column headers entirely while
    /// 3,000 × 818 of the same header read every one of them. The way
    /// through is fewer pixels per pass, not more: cut the page into
    /// strips wide enough to resolve the type and short enough to stay
    /// under the budget.
    static let readableWidth: CGFloat = 3_900
    static let pixelBudget: CGFloat = 6_000_000

    static let stripOverlap: CGFloat = 0.06

    static func strips(of bounds: CGRect) -> [CGRect] {
        let tallest = pixelBudget / (readableWidth * readableWidth)
        let aspect = bounds.height / bounds.width
        // The overlap below makes each strip taller than its share, and
        // the budget is about what Vision is HANDED, not what the page
        // was divided into.
        let count = max(1, Int(((aspect * (1 + 2 * stripOverlap)) / tallest).rounded(.up)))
        // Overlapped, because a strip edge otherwise falls through a row
        // of the table and cuts its numbers in half. A run split across
        // two strips is read whole by the other one, and the duplicate
        // reading loses to it or matches it.
        let height = bounds.height / CGFloat(count)
        let overlap = count > 1 ? height * stripOverlap : 0
        return (0..<count).map { index in
            let minY = max(bounds.minY, bounds.minY + height * CGFloat(index) - overlap)
            let maxY = min(bounds.maxY, bounds.minY + height * CGFloat(index + 1) + overlap)
            return CGRect(x: bounds.minX, y: minY, width: bounds.width, height: maxY - minY)
        }
    }

    /// A strip's run put back into the page's own coordinates.
    static func placed(
        _ run: LabelObservation, of strip: CGRect, in bounds: CGRect
    ) -> LabelObservation {
        LabelObservation(
            text: run.text,
            x: (Double(strip.minX - bounds.minX) + run.x * Double(strip.width))
                / Double(bounds.width),
            y: (Double(strip.minY - bounds.minY) + run.y * Double(strip.height))
                / Double(bounds.height),
            w: run.w * Double(strip.width) / Double(bounds.width),
            h: run.h * Double(strip.height) / Double(bounds.height))
    }

    /// The upright reading of each run, unless the 180° pass read the
    /// same box more legibly.
    static func readingBetterOf(
        _ upright: [LabelObservation], flipped: [LabelObservation]
    ) -> [LabelObservation] {
        merging(flipped.map {
            LabelObservation(text: $0.text, x: 1 - $0.x - $0.w, y: 1 - $0.y - $0.h, w: $0.w, h: $0.h)
        }, into: upright)
    }

    /// A second reading of the same page laid over the first: it wins a
    /// box it covers only by being more legible, and stands on its own
    /// only where it NAMES A COLUMN.
    static func merging(
        _ extra: [LabelObservation], into base: [LabelObservation]
    ) -> [LabelObservation] {
        var runs = base
        for candidate in extra {
            guard let index = runs.firstIndex(where: { covers($0, candidate) }) else {
                // NOTHING TO REPLACE. Vision on the phone hands back no
                // run at all where the Mac's hands back wreckage, so
                // somisomi's turned headings arrived as `AVS G3AYUNEVS`
                // in the simulator and as SILENCE on the device — and a
                // replace-only merge threw away the one correct reading
                // of them for having nothing to overwrite. Every row
                // then had a calorie column and no other, and the sheet
                // said "no nutrition found" (the user, 2026-08-23).
                //
                // So a flipped-only run may be ADDED, but only when it
                // NAMES A COLUMN — which is the entire reason this pass
                // exists, and is a bar that OCR noise does not clear.
                if MenuTableParser.namesAColumn(candidate.text) { runs.append(candidate) }
                continue
            }
            guard legibility(candidate.text) > legibility(runs[index].text) else { continue }
            runs[index] = candidate
        }
        return runs
    }

    /// How the COLUMN HEADINGS are read when the strips have delivered a
    /// table without any.
    ///
    /// Vision downsamples what it is handed, and the phone's threshold
    /// sits far below the Mac's. Measured on the device, on the very
    /// same band of the very same page:
    ///
    ///     3,900 x 1,365  (5.3 MP)   1 of 10 column names
    ///     3,900 x   914  (3.3 MP)   2 of 10
    ///     2,600 x   609  (1.6 MP)  10 of 10
    ///
    /// The strips are sized for the DATA rows, which read perfectly well
    /// at 5.3 MP; the headings are smaller type set on a diagonal and do
    /// not. So the headings get one close look of their own, at about
    /// two megapixels, over the band directly above the first data row —
    /// two passes, not a resizing of all sixteen.
    ///
    /// This is why the phone said "no nutrition found" while the
    /// simulator read the page: the transcript reaching the parser had
    /// every figure in it and one column name, and a table with no
    /// columns is correctly refused (the user, 2026-08-23).
    static let headerBandWidth: CGFloat = 3_250
    static let headerBandHeight = 0.075

    static func readingHeader(
        of page: PDFPage, in bounds: CGRect, over transcript: [LabelObservation],
        budget: inout Int
    ) async -> [LabelObservation] {
        let bands = MenuTableParser.bands(transcript)
        guard let data = bands.first(where: { MenuTableParser.isDataBand($0) }),
              let floor = data.runs.map({ $0.y + $0.h }).max() else { return transcript }
        let ceiling = min(1, floor + headerBandHeight)
        guard ceiling > floor, budget > 0 else { return transcript }
        let rect = CGRect(
            x: bounds.minX, y: bounds.minY + bounds.height * floor,
            width: bounds.width, height: bounds.height * (ceiling - floor))
        guard rect.width > 0, rect.height > 0,
              let image = raster(page, in: rect, scale: headerBandWidth / rect.width)
        else { return transcript }
        budget -= 1
        var runs = (try? await LabelScan.observations(from: image)) ?? []
        if budget > 0, let flipped = turned(image),
           let second = try? await LabelScan.observations(from: flipped) {
            budget -= 1
            runs = readingBetterOf(runs, flipped: second)
        }
        return merging(runs.map { placed($0, of: rect, in: bounds) }, into: transcript)
    }

    /// The same piece of the page, read twice — most of the smaller box
    /// lies inside the larger.
    static func covers(_ a: LabelObservation, _ b: LabelObservation) -> Bool {
        let width = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
        let height = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
        guard width > 0, height > 0 else { return false }
        return width * height > 0.5 * min(a.w * a.h, b.w * b.h)
    }

    /// How much of a run reads as text rather than as OCR wreckage.
    /// `SATURATED FAT` scores 1; the upside-down reading of it,
    /// `AVS G3AYUNEVS`, scores the same — so the tie is broken by what
    /// the header table can NAME, which is the only judge that matters
    /// here and the reason a garbled twin never wins.
    static func legibility(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let named = MenuTableParser.field(forHeader: text) != nil ? 1.0 : 0
        let readable = text.unicodeScalars.filter { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespaces.contains(scalar)
                || ".,()%/-'".unicodeScalars.contains(scalar))
        }.count
        return named + Double(readable) / Double(text.unicodeScalars.count)
    }

    /// A page as pixels, big enough for Vision to read six-point table
    /// type: the long edge goes to `renderEdge`, which is where the
    /// figures on a scanned guide stop being legible below.
    static let renderEdge: CGFloat = 2_400

    static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return raster(page, in: bounds, scale: renderEdge / max(bounds.width, bounds.height))
    }

    /// A strip at `readableWidth` across, whatever its height — the
    /// whole point of cutting the page up is the pixels ACROSS it, and
    /// scaling by the long edge would give a short strip fewer of them
    /// than the page it came from.
    static func render(_ page: PDFPage, strip: CGRect) -> CGImage? {
        guard strip.width > 0, strip.height > 0 else { return nil }
        return raster(page, in: strip, scale: readableWidth / strip.width)
    }

    private static func raster(_ page: PDFPage, in bounds: CGRect, scale: CGFloat) -> CGImage? {
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

    /// The same pixels upside down. Not `CGImagePropertyOrientation`:
    /// that rides on the request and rotates the RESULT's coordinates
    /// back, which is exactly what must not happen — the second reading
    /// has to be compared against the first in the same frame.
    static func turned(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.translateBy(x: CGFloat(image.width) / 2, y: CGFloat(image.height) / 2)
        context.rotate(by: .pi)
        context.draw(image, in: CGRect(
            x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
            width: CGFloat(image.width), height: CGFloat(image.height)))
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
    /// was built against: the CAVA guide's PDF title is the InDesign
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
    /// was called, and "menu-cava — Greek Chicken" is the kind of
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
    /// Squashed brand labels ("shakeshack", "cava") come back
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
