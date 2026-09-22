import Foundation
import Testing
@testable import OnigiriKit

/// The other document shape: a restaurant's nutrition PAGE, rendered to
/// PDF by `MenuLinkLoader`'s web view and captured with
/// `scripts/dump-pdf-text.swift`.
///
/// The headline finding is that there IS no other shape. The plan
/// expected "labelled runs" needing a second parser; a rendered page is a
/// POSITIONAL TABLE like any print PDF, so the same parser reads both.
/// What it does have is page furniture a print guide never carries, and
/// each test below is one piece of that furniture getting into the data.
struct MenuTableParserWebTests {
    private func fixture(_ name: String) throws -> [LabelObservation] {
        struct Dump: Decodable { let observations: [LabelObservation] }
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name)")
        return try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url)).observations
    }

    private func expectEqual(_ actual: Double?, _ expected: Double, accuracy: Double = 0.01,
                             _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let actual else {
            Issue.record(comment ?? "value is nil, expected \(expected)", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(actual - expected) <= accuracy, comment, sourceLocation: sourceLocation)
    }

    @Test func readsARowOffTheRenderedPage() throws {
        let rows = MenuTableParser.parse(try fixture("menu-chickfila-p1"))
        let biscuit = try #require(
            rows.first { $0.name == "Spicy Chicken Biscuit" },
            "got \(rows.prefix(4).map(\.name))")
        expectEqual(biscuit.kcal, 450)
        expectEqual(biscuit.nutrients.fatG, 22)
        expectEqual(biscuit.nutrients.saturatedFatG, 8)
        expectEqual(biscuit.nutrients.transFatG, 0)
        expectEqual(biscuit.nutrients.cholesterolMg, 40)
        expectEqual(biscuit.sodiumMg, 1570)
        expectEqual(biscuit.nutrients.carbsG, 44)
        expectEqual(biscuit.nutrients.fiberG, 3)
        expectEqual(biscuit.nutrients.sugarG, 5)
        expectEqual(biscuit.nutrients.proteinG, 19)
    }

    /// This table HAS a serving column, unlike the print guide. Left
    /// unrecognized it sat left of the numbers and was swept into the
    /// name — every item read as "Spicy Chicken Biscuit 153g".
    @Test func theServingColumnBecomesTheServing() throws {
        let rows = MenuTableParser.parse(try fixture("menu-chickfila-p1"))
        let biscuit = try #require(rows.first { $0.name == "Spicy Chicken Biscuit" })
        #expect(biscuit.serving == "153g")
        #expect(!biscuit.name.contains("153"), "the weight is not part of the dish's name")
        #expect(biscuit.parsedLabel.servingDescription == "153g")
    }

    /// The page carries a category SIDEBAR at the far left whose entries
    /// share bands with table rows. "Kid's Meals (nutrition per entrée
    /// only) Egg White Grill" was a real parsed name.
    @Test func theCategorySidebarStaysOutOfTheNames() throws {
        let rows = MenuTableParser.parse(try fixture("menu-chickfila-p1"))
        #expect(!rows.isEmpty)
        for row in rows {
            #expect(!row.name.contains("Kid's Meals"), "sidebar text in \(row.name)")
            #expect(!row.name.contains("nutrition per"), "sidebar text in \(row.name)")
        }
        #expect(rows.contains { $0.name == "Egg White Grill" })
    }

    /// On this page an item's NAME sits on a baseline a hair below its
    /// numbers, so the name arrives as its own band. Read as a wrapped
    /// name it was appended to the row ABOVE, which produced
    /// "…Bowl 233g Dipping Sauces Dressings".
    @Test func aNameOnItsOwnBaselineStaysWithItsOwnNumbers() throws {
        let rows = try wholeDocument()
        let juice = try #require(
            rows.first { $0.name.contains("Simply Orange") },
            "got \(rows.suffix(4).map(\.name))")
        expectEqual(juice.kcal, 160)
        #expect(juice.name == "Simply Orange®", "exactly its own name: \(juice.name)")
    }

    /// The second page reprints NO header — it continues page one's
    /// table. Read alone it can only come back empty, which is why the
    /// document API carries the columns forward and the page API cannot.
    @Test func aContinuationPageIsOnlyReadableInDocumentContext() throws {
        #expect(MenuTableParser.parse(try fixture("menu-chickfila-p2")).isEmpty)
        let both = try wholeDocument()
        let onlyFirst = MenuTableParser.parse(try fixture("menu-chickfila-p1"))
        #expect(both.count > onlyFirst.count, "page 2's items would otherwise be dropped")
    }

    private func wholeDocument() throws -> [MenuRow] {
        MenuTableParser.parse(pages: [
            try fixture("menu-chickfila-p1"), try fixture("menu-chickfila-p2"),
        ])
    }

    /// A long name wraps onto the line below and both halves belong to
    /// the row — in reading order, not x order.
    @Test func aWrappedNameIsPutBackTogether() throws {
        let rows = try wholeDocument()
        let gallon = try #require(
            rows.first { $0.name.hasPrefix("Gallon Chick-fil-A® Lemonade (") },
            "got \(rows.suffix(6).map(\.name))")
        #expect(gallon.name.contains("Diet Lemonade)"), "second half missing: \(gallon.name)")
        expectEqual(gallon.kcal, 120)
    }

    @Test func theWholePageParsesAndNothingIsBlank() throws {
        let rows = MenuTableParser.parse(try fixture("menu-chickfila-p1"))
        #expect(rows.count > 40, "the page lists dozens of items, got \(rows.count)")
        #expect(rows.allSatisfy { $0.kcal != nil })
        #expect(rows.allSatisfy { !$0.name.isEmpty })
        // A column header must never become an item or a section.
        #expect(!rows.contains { $0.name.localizedCaseInsensitiveContains("serving size") })
        #expect(!rows.contains { $0.section?.localizedCaseInsensitiveContains("serving size") == true })
    }
}
