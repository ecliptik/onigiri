import Foundation
import Testing
@testable import OnigiriKit

/// Fixtures are real PDF text layers captured with
/// `scripts/dump-pdf-text.swift` from the Kwik Trip nutrition guide the
/// feature was designed against (`plans/PLAN-menu-import.md`) — the exact
/// runs `MenuDocument` hands the parser on device, never hand-written.
struct MenuTableParserTests {
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

    // MARK: The document it was designed against

    @Test func readsEveryColumnOfARow() throws {
        let rows = MenuTableParser.parse(try fixture("menu-kwiktrip-p1"))
        let bowl = try #require(
            rows.first { $0.name == "Spicy Lamb + Avocado Bowl" },
            "the guide's first item; got \(rows.prefix(3).map(\.name))")
        expectEqual(bowl.kcal, 800, "the Cal. column, NOT Cal. from Fat (460)")
        expectEqual(bowl.sodiumMg, 1670)
        expectEqual(bowl.nutrients.fatG, 52)
        expectEqual(bowl.nutrients.saturatedFatG, 14)
        expectEqual(bowl.nutrients.transFatG, 0)
        expectEqual(bowl.nutrients.cholesterolMg, 105)
        expectEqual(bowl.nutrients.carbsG, 49)
        expectEqual(bowl.nutrients.fiberG, 17)
        expectEqual(bowl.nutrients.sugarG, 11)
        expectEqual(bowl.nutrients.proteinG, 43)
    }

    /// `Cal.` appears TWICE in this header — the calorie column and the
    /// first half of `Cal. from Fat`. Matching on a substring reads the
    /// wrong one, and every item in the document would be wrong by the
    /// same mechanism.
    @Test func caloriesFromFatNeverBecomesCalories() throws {
        let rows = MenuTableParser.parse(try fixture("menu-kwiktrip-p1"))
        let steak = try #require(rows.first { $0.name == "Steak + Harissa Bowl" })
        expectEqual(steak.kcal, 620)
        #expect(steak.kcal != 310, "310 is this row's Cal. from Fat")
    }

    /// THREE columns on this page contain the word "fat".
    @Test func theThreeFatColumnsStaySeparate() throws {
        let rows = MenuTableParser.parse(try fixture("menu-kwiktrip-p1"))
        let falafel = try #require(rows.first { $0.name == "Falafel Crunch Bowl" })
        expectEqual(falafel.nutrients.fatG, 56)
        expectEqual(falafel.nutrients.saturatedFatG, 9)
        expectEqual(falafel.nutrients.transFatG, 0)
    }

    /// A run can cover two columns: "0 105" and "7 7" come back as ONE
    /// selection because the cells sit close together. Splitting them by
    /// which column centres the run spans is what keeps trans fat and
    /// cholesterol apart.
    @Test func aRunCoveringTwoColumnsSplitsBetweenThem() throws {
        let rows = MenuTableParser.parse(try fixture("menu-kwiktrip-p1"))
        let steak = try #require(rows.first { $0.name == "Steak + Harissa Bowl" })
        expectEqual(steak.nutrients.transFatG, 0, "the first half of the merged \"0 105\" run")
        expectEqual(steak.nutrients.cholesterolMg, 105, "the second half")
        expectEqual(steak.nutrients.fiberG, 7, "the merged \"7 7\" run")
        expectEqual(steak.nutrients.sugarG, 7)
    }

    @Test func headingsGroupRowsAndAreNotThemselvesItems() throws {
        let rows = MenuTableParser.parse(try fixture("menu-kwiktrip-p1"))
        #expect(!rows.contains { $0.name == "CURATED BOWLS" }, "a heading is not a food")
        let bowl = try #require(rows.first { $0.name == "Spicy Lamb + Avocado Bowl" })
        #expect(bowl.section == "CURATED BOWLS")
        let rice = try #require(rows.first { $0.name == "Brown Rice" })
        #expect(rice.section == "BASES", "the heading changes partway down the page")
    }

    /// The whole point of the feature: one document, many items.
    @Test func readsTheWholePage() throws {
        let rows = MenuTableParser.parse(try fixture("menu-kwiktrip-p1"))
        #expect(rows.count > 30, "page 1 lists dozens of items, got \(rows.count)")
        #expect(rows.allSatisfy { $0.kcal != nil }, "a row without calories is not a food")
        #expect(rows.allSatisfy { !$0.name.isEmpty })
    }

    /// The guide reprints its header on every page at DIFFERENT x
    /// positions. Columns detected once and reused would misread
    /// everything after page 1.
    @Test func columnsAreDetectedPerPage() throws {
        let page2 = MenuTableParser.parse(try fixture("menu-kwiktrip-p2"))
        #expect(page2.count > 20, "page 2 parsed \(page2.count) rows")
        #expect(page2.allSatisfy { $0.kcal != nil })
    }

    /// The allergen pages carry a header with no calorie column, so they
    /// exclude themselves. Without this the parser would emit a row per
    /// allergen mark.
    @Test func aPageWithNoNutritionTableYieldsNothing() throws {
        #expect(MenuTableParser.parse(try fixture("menu-kwiktrip-allergens")).isEmpty)
    }

    /// The invariant `PLAN-menu-import` asks for, and the shape of the
    /// bug that shipped on the AI path once (four salads all reading 490
    /// kcal): a row's numbers must come from that row's own band.
    @Test func everyRowsNumbersComeFromItsOwnBand() throws {
        let rows = MenuTableParser.parse(try fixture("menu-kwiktrip-p1"))
        let bowls = rows.filter { $0.section == "CURATED BOWLS" }
        #expect(bowls.count >= 8)
        let calories = Set(bowls.compactMap(\.kcal))
        #expect(calories.count >= bowls.count - 1,
                "near-unique per row; identical values across a section means one band won")
    }

    @Test func rowsFoldIntoTheLabelTheFoodFormAlreadyConsumes() throws {
        let rows = MenuTableParser.parse(try fixture("menu-kwiktrip-p1"))
        let bowl = try #require(rows.first { $0.name == "Spicy Lamb + Avocado Bowl" })
        let label = bowl.parsedLabel
        #expect(label.name == "Spicy Lamb + Avocado Bowl")
        expectEqual(label.kcal, 800)
        #expect(!label.aiGenerated, "printed values are not an estimate")
        #expect(label.servingDescription == nil, "the guide names no serving; never invent one")
    }

    /// The document API. Ids must stay unique across pages — they are
    /// the picker's row identity, and a repeat would make two different
    /// items select as one.
    @Test func pagesParseIntoOneDocument() throws {
        let one = MenuTableParser.parse(try fixture("menu-kwiktrip-p1"))
        let two = MenuTableParser.parse(try fixture("menu-kwiktrip-p2"))
        let both = MenuTableParser.parse(pages: [
            try fixture("menu-kwiktrip-p1"), try fixture("menu-kwiktrip-p2"),
        ])
        #expect(both.count == one.count + two.count)
        #expect(Set(both.map(\.id)).count == both.count, "ids are unique across pages")
        #expect(both.first?.name == one.first?.name)
    }

    /// A heading is printed once and the table runs on past the page
    /// break, so the section has to survive it — otherwise every item
    /// above the next heading loses its grouping.
    @Test func aSectionCarriesAcrossAPageBreak() throws {
        let both = MenuTableParser.parse(pages: [
            try fixture("menu-kwiktrip-p1"), try fixture("menu-kwiktrip-p2"),
        ])
        let firstOnPageTwo = try #require(
            both.dropFirst(MenuTableParser.parse(try fixture("menu-kwiktrip-p1")).count).first)
        #expect(firstOnPageTwo.section != nil, "inherited from page 1's last heading")
    }

    // MARK: Units and shape

    @Test func aHeaderNamingGramsForSodiumConvertsToMilligrams() {
        // Synthetic: no fixture prints sodium in grams, but a European
        // table would, and storage is always canonical mg.
        let observations = [
            LabelObservation(text: "Item", x: 0.05, y: 0.90, w: 0.10, h: 0.02),
            LabelObservation(text: "Calories", x: 0.30, y: 0.90, w: 0.10, h: 0.02),
            LabelObservation(text: "Sodium (g)", x: 0.50, y: 0.90, w: 0.12, h: 0.02),
            LabelObservation(text: "Protein (g)", x: 0.70, y: 0.90, w: 0.12, h: 0.02),
            LabelObservation(text: "Soup", x: 0.05, y: 0.85, w: 0.10, h: 0.02),
            LabelObservation(text: "120", x: 0.32, y: 0.85, w: 0.06, h: 0.02),
            LabelObservation(text: "1.5", x: 0.53, y: 0.85, w: 0.06, h: 0.02),
            LabelObservation(text: "9", x: 0.74, y: 0.85, w: 0.04, h: 0.02),
        ]
        let rows = MenuTableParser.parse(observations)
        #expect(rows.count == 1)
        expectEqual(rows.first?.sodiumMg, 1500, "1.5 g of sodium is 1,500 mg")
        expectEqual(rows.first?.nutrients.proteinG, 9)
    }

    @Test func nothingIsReadOffAnEmptyPage() {
        #expect(MenuTableParser.parse([]).isEmpty)
    }
}
