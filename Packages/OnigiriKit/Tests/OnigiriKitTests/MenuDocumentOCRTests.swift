#if canImport(PDFKit)
import Foundation
import CoreGraphics
import Testing
@testable import OnigiriKit

/// The pure halves of `MenuDocumentReader.readOCR` — how a page is cut
/// up for Vision, and how two readings of the same pixels are reconciled
/// (`plans/PLAN-menu-import.md`). The OCR itself is exercised on device
/// by `MenuDocumentTests`; everything here is arithmetic and can be
/// asserted exactly.
struct MenuDocumentOCRTests {
    private let page = CGRect(x: 0, y: 0, width: 1280, height: 3201)

    // MARK: Strips

    /// Vision downsamples what it is handed, so a tall page is cut up
    /// rather than rendered larger — measured on the somisomi render,
    /// where 4,000 × 3,201 lost the column headers entirely and
    /// 3,000 × 818 of the same header read every one of them.
    @Test func aTallPageIsCutIntoStripsVisionCanResolve() {
        let strips = MenuDocumentReader.strips(of: page)
        #expect(strips.count > 1, "a page two and a half screens tall is not read whole")
        for strip in strips {
            let pixels = MenuDocumentReader.readableWidth
                * (MenuDocumentReader.readableWidth * strip.height / strip.width)
            #expect(pixels <= MenuDocumentReader.pixelBudget,
                    "a strip of \(Int(pixels)) pixels is past what Vision reads at full size")
        }
    }

    /// Nothing may fall between two strips: a seam through a table row
    /// cuts its numbers in half, so the strips overlap and cover the page
    /// end to end.
    @Test func theStripsCoverThePageWithoutAGap() {
        let strips = MenuDocumentReader.strips(of: page)
        #expect(strips.first?.minY == page.minY)
        #expect(strips.last?.maxY == page.maxY)
        for (lower, upper) in zip(strips, strips.dropFirst()) {
            #expect(upper.minY < lower.maxY, "the strips must overlap, not merely meet")
        }
    }

    /// A run read inside a strip has to come back in the page's own
    /// coordinates or every column lands somewhere else.
    @Test func aStripsRunComesBackInPageCoordinates() {
        let strip = CGRect(x: 0, y: 1600, width: 1280, height: 800)
        let run = LabelObservation(text: "115", x: 0.5, y: 0.25, w: 0.01, h: 0.02)
        let placed = MenuDocumentReader.placed(run, of: strip, in: page)
        #expect(abs(placed.x - 0.5) < 0.0001, "x is unchanged — the strips are full width")
        #expect(abs(placed.y - (1600 + 0.25 * 800) / 3201) < 0.0001)
        #expect(abs(placed.h - 0.02 * 800 / 3201) < 0.0001)
    }

    // MARK: Reading the same pixels twice

    /// A name set at 60° reads correctly in exactly ONE of two
    /// orientations, and on this sheet it is the upside-down one:
    /// `SATURATED FAT` comes back from the upright pass as
    /// `AVS G3AYUNEVS`.
    @Test func theTurnedReadingWinsWhenTheUprightOneIsWreckage() {
        let upright = [LabelObservation(text: "AVS G3AYUNEVS", x: 0.40, y: 0.82, w: 0.065, h: 0.067)]
        // The same box as the flipped pass reports it, before mapping.
        let flipped = [LabelObservation(text: "SATURATED FAT", x: 0.535, y: 0.113, w: 0.065, h: 0.067)]
        let merged = MenuDocumentReader.readingBetterOf(upright, flipped: flipped)
        #expect(merged.count == 1, "the same box read twice is one run")
        #expect(merged.first?.text == "SATURATED FAT")
        #expect(abs((merged.first?.x ?? 0) - 0.40) < 0.001, "and it keeps the upright frame")
    }

    /// Noise the flipped pass reads over an ordinary upright page must
    /// not be appended beside the real runs — that would be a new way to
    /// break a table that already worked.
    @Test func theTurnedPassAddsNoNoiseOfItsOwn() {
        let upright = [LabelObservation(text: "SODIUM", x: 0.57, y: 0.82, w: 0.043, h: 0.042)]
        let flipped = [
            LabelObservation(text: "WNIQOS", x: 0.387, y: 0.138, w: 0.043, h: 0.042),
            LabelObservation(text: "!!!!!", x: 0.10, y: 0.40, w: 0.20, h: 0.01),
            LabelObservation(text: "0LZ", x: 0.30, y: 0.55, w: 0.02, h: 0.004),
        ]
        let merged = MenuDocumentReader.readingBetterOf(upright, flipped: flipped)
        #expect(merged.map(\.text) == ["SODIUM"], "the upright reading held and nothing was appended")
    }

    /// But a COLUMN NAME it finds in empty space is added, and has to
    /// be. Vision on the phone returns no run at all where the Mac's
    /// returns wreckage, so somisomi's turned headings arrived as
    /// `AVS G3AYUNEVS` in the simulator and as silence on the device —
    /// and a replace-only merge threw away the only correct reading of
    /// them for having nothing to overwrite. Every row then had a
    /// calorie column and no other, and the sheet said "no nutrition
    /// found" (2026-08-23).
    @Test func aColumnNameTheUprightPassMissedEntirelyIsKept() {
        let upright = [LabelObservation(text: "CALORIES", x: 0.347, y: 0.813, w: 0.032, h: 0.017)]
        let flipped = [
            LabelObservation(text: "SODIUM", x: 0.410, y: 0.163, w: 0.030, h: 0.014),
            LabelObservation(text: "CHOLESTEROL", x: 0.443, y: 0.154, w: 0.041, h: 0.022),
        ]
        let merged = MenuDocumentReader.readingBetterOf(upright, flipped: flipped)
        #expect(merged.count == 3, "the two headings the upright pass never saw")
        #expect(merged.contains { $0.text == "SODIUM" })
        #expect(merged.contains { $0.text == "CHOLESTEROL" })
        let sodium = try? #require(merged.first { $0.text == "SODIUM" })
        #expect(abs((sodium?.x ?? 0) - 0.560) < 0.001, "mapped back into the upright frame")
    }

    /// The second orientation is worth reading only where there is
    /// something the page's own text layer never had. A shared ARTICLE
    /// reads about the same either way; somisomi's render carries 41
    /// runs of navigation over 458 read off two table PNGs.
    @Test func onlyAPageHidingTextIsReadTwice() {
        func runs(_ count: Int) -> [LabelObservation] {
            (0..<count).map {
                LabelObservation(text: "\($0)", x: 0.1, y: Double($0) / 1000, w: 0.01, h: 0.001)
            }
        }
        #expect(MenuDocumentReader.hidesText(runs(458), beyond: runs(41)))
        #expect(!MenuDocumentReader.hidesText(runs(70), beyond: runs(67)),
                "a page whose words are all really there")
        #expect(MenuDocumentReader.hidesText(runs(120), beyond: runs(0)),
                "a scanned guide's page has no text layer at all, and its headings turn too")
        #expect(!MenuDocumentReader.hidesText(runs(12), beyond: runs(0)),
                "a nearly blank reading is noise, not a hidden table")
    }

    /// What breaks the tie is what the header table can NAME. Both
    /// readings of a turned heading are the same length and the same
    /// characters, so a plain legibility count calls them equal.
    @Test func aNameableHeadingBeatsItsGarbledTwin() {
        #expect(MenuDocumentReader.legibility("SATURATED FAT")
                > MenuDocumentReader.legibility("AVS G3AYUNEVS"))
        #expect(MenuDocumentReader.legibility("SODIUM") > MenuDocumentReader.legibility("WNIQOS"))
        #expect(MenuDocumentReader.legibility("115") > MenuDocumentReader.legibility("\u{4e00}\u{4e8c}\u{4e09}"))
    }
}
#endif
