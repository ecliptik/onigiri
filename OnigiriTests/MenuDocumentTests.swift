import XCTest
import OnigiriKit
@testable import Onigiri

/// The half of menu import that the kit's pure suite cannot reach:
/// PDFKit. `MenuTableParserTests` proves the parser against fixtures
/// captured by `scripts/dump-pdf-text.swift`; this proves the app reads
/// the same runs OUT OF THE SAME PDF, so a fixture stays evidence about
/// the shipping path rather than about a script that has drifted from it.
///
/// Deliberately NOT opt-in like the eval suite beside it — no model, no
/// network, ~50 ms.
///
/// No class-level @MainActor (the target's nonisolated-default rule,
/// project.yml) — MenuDocumentReader's read functions are nonisolated.
final class MenuDocumentTests: XCTestCase {
    private func menuURL() throws -> URL {
        try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "menu-cava", withExtension: "pdf"),
            "missing PDF fixture")
    }

    /// The twin check. If `MenuDocumentReader.runs` and the capture
    /// script diverge — different API, different normalization — this
    /// fails while every parser test keeps passing, which is exactly the
    /// failure mode the comment in both files warns about.
    func testTheReaderProducesTheRunsTheFixtureWasCapturedFrom() throws {
        let document = try MenuDocumentReader.read(try menuURL())
        XCTAssertEqual(document.pages.count, 6)

        let captured = try fixtureObservations("menu-cava-p1")
        let read = try XCTUnwrap(document.pages.first)
        XCTAssertEqual(read.count, captured.count, "run count drifted from the captured fixture")
        for (a, b) in zip(read, captured) {
            XCTAssertEqual(a.text, b.text)
            XCTAssertEqual(a.x, b.x, accuracy: 0.0001)
            XCTAssertEqual(a.y, b.y, accuracy: 0.0001)
        }
    }

    /// End to end on device APIs: a real PDF in, menu rows out.
    func testTheWholeGuideParses() throws {
        let document = try MenuDocumentReader.read(try menuURL())
        let rows = MenuTableParser.parse(pages: document.pages)
        XCTAssertGreaterThan(rows.count, 90, "the guide lists ~113 items, got \(rows.count)")
        XCTAssertTrue(rows.allSatisfy { $0.kcal != nil })

        let bowl = try XCTUnwrap(rows.first { $0.name == "Spicy Lamb + Avocado Bowl" })
        XCTAssertEqual(try XCTUnwrap(bowl.kcal), 800, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(bowl.sodiumMg), 1670, accuracy: 0.01)
    }

    /// The document this feature was built against names its restaurant
    /// NOWHERE — its PDF title is the InDesign job code
    /// `KT5_26_AN_STND_RECAN11148.indd`, its footer is the same code,
    /// its logo is artwork. Detection MUST come back empty here so the
    /// import sheet asks, which is the whole contract. (A filename
    /// fallback made this pass for the wrong reason and would have
    /// prefixed items with whatever the download was called.)
    func testAJobCodeIsNotMistakenForARestaurantName() throws {
        let document = try MenuDocumentReader.read(try menuURL())
        XCTAssertNil(document.suggestedSource)
    }

    func testWhatCountsAsARestaurantName() {
        XCTAssertTrue(MenuDocumentReader.isPlausibleSource("Chick-fil-A"))
        XCTAssertTrue(MenuDocumentReader.isPlausibleSource("CAVA"))
        // Job codes, export filenames, and words that name the document
        // rather than the place.
        XCTAssertFalse(MenuDocumentReader.isPlausibleSource("KT5_26_AN_STND_RECAN11148"))
        XCTAssertFalse(MenuDocumentReader.isPlausibleSource("KT5_26_AN_STND_RECAN11148.indd"))
        XCTAssertFalse(MenuDocumentReader.isPlausibleSource("Nutrition Guide"))
        XCTAssertFalse(MenuDocumentReader.isPlausibleSource("nutrition and allergen guide"))
        XCTAssertFalse(MenuDocumentReader.isPlausibleSource("Menu"))
        XCTAssertFalse(MenuDocumentReader.isPlausibleSource(""))
        XCTAssertFalse(MenuDocumentReader.isPlausibleSource("2026"))
    }

    func testANonPDFIsRejectedRatherThanParsedAsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-menu.pdf")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try MenuDocumentReader.read(url))
    }

    // MARK: -

    private func fixtureObservations(_ name: String) throws -> [LabelObservation] {
        struct Dump: Decodable { let observations: [LabelObservation] }
        // The fixtures live in the KIT's test bundle; this target reaches
        // them through the repo, which is fine for a check whose whole
        // job is comparing the two capture paths.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OnigiriTests
            .deletingLastPathComponent()   // repo root
        let url = root.appending(path:
            "Packages/OnigiriKit/Tests/OnigiriKitTests/Fixtures/\(name).json")
        return try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url)).observations
    }
}
