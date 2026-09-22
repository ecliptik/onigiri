import Foundation
import Testing
@testable import OnigiriKit

/// A photographed menu, where calorie labeling prints a figure beside
/// each dish. The fixture is real Vision OCR captured with
/// `scripts/dump-label-ocr.swift` from a rendered board — the same
/// pipeline a camera photo takes, so the OCR behaviour is genuine even
/// though the restaurant is not.
struct MenuBoardParserTests {
    private func fixture(_ name: String) throws -> [LabelObservation] {
        struct Dump: Decodable { let observations: [LabelObservation] }
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name)")
        return try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url)).observations
    }

    private func board() throws -> [MenuRow] {
        MenuBoardParser.parse(try fixture("menu-board-rendered"))
    }

    @Test func readsTheDishAndItsPrintedCalories() throws {
        let rows = try board()
        let burger = try #require(
            rows.first { $0.name == "Classic Cheeseburger" },
            "got \(rows.map(\.name))")
        #expect(burger.kcal == 780)
        #expect(burger.section == "BURGERS")
        // Printed, not estimated — so no provenance dot, unlike the sign
        // read this displaces.
        #expect(!burger.parsedLabel.aiGenerated)
    }

    @Test func aThousandsSeparatorIsNotTwoNumbers() throws {
        let rows = try board()
        let bacon = try #require(rows.first { $0.name == "Bacon Blue Burger" })
        #expect(bacon.kcal == 1020)
    }

    /// Both bounds are printed, so neither is invented. The upper one is
    /// taken deliberately: under-reporting intake is the direction that
    /// quietly breaks a deficit.
    @Test func aRangeTakesItsUpperBound() throws {
        let rows = try board()
        let caesar = try #require(rows.first { $0.name == "Caesar Salad" })
        #expect(caesar.kcal == 680)
    }

    /// The price sits between the dish and its calories on every line.
    @Test func pricesAreNeverPartOfTheName() throws {
        let rows = try board()
        #expect(!rows.isEmpty)
        for row in rows {
            #expect(!row.name.contains("$"), "price in \(row.name)")
        }
        #expect(rows.contains { $0.name == "Skillet Fries" })
    }

    /// An item's description is set smaller and sits within a row's
    /// pitch of it. Absorbed, it becomes part of the dish's name.
    @Test func descriptionsStayOutOfTheName() throws {
        let rows = try board()
        let burger = try #require(rows.first { $0.name == "Classic Cheeseburger" })
        #expect(!burger.name.contains("cheddar"))
        #expect(!rows.contains { $0.name.contains("add grilled chicken") })
    }

    /// The line every calorie-labeled menu is required to carry. Without
    /// a length bound on the calorie cell it parses as a 2,000-calorie
    /// item — the same sentence that already had to be defended against
    /// in `LabelParser`.
    @Test func theMandatoryFootnoteIsNotAFood() throws {
        let rows = try board()
        #expect(!rows.contains { $0.kcal == 2000 })
        #expect(!rows.contains { $0.name.localizedCaseInsensitiveContains("nutrition advice") })
        #expect(!rows.contains { $0.name.localizedCaseInsensitiveContains("upon request") })
    }

    @Test func headingsGroupTheBoardAndAreNotItems() throws {
        let rows = try board()
        #expect(!rows.contains { $0.name == "BURGERS" })
        #expect(!rows.contains { $0.name == "THE COPPER SKILLET" })
        #expect(rows.first { $0.name == "Harvest Grain Bowl" }?.section == "BOWLS & SALADS")
        #expect(rows.first { $0.name == "Soup of the Day" }?.section == "SIDES")
    }

    @Test func readsEveryItemOnTheBoard() throws {
        let rows = try board()
        #expect(rows.count == 7, "got \(rows.map { "\($0.name)=\($0.kcal ?? -1)" })")
        #expect(rows.allSatisfy { $0.kcal != nil })
        #expect(rows.allSatisfy { !$0.name.isEmpty })
    }

    /// A menu with no calorie labeling has nothing printed to read, and
    /// this parser must say so rather than invent — the AI sign read is
    /// what handles that picture, and it only gets its turn if this
    /// returns nothing.
    @Test func aBoardWithoutCaloriesYieldsNothing() {
        let rows = MenuBoardParser.parse([
            LabelObservation(text: "BURGERS", x: 0.05, y: 0.90, w: 0.14, h: 0.03),
            LabelObservation(text: "Classic Cheeseburger", x: 0.05, y: 0.85, w: 0.25, h: 0.03),
            LabelObservation(text: "$12.50", x: 0.74, y: 0.85, w: 0.08, h: 0.03),
            LabelObservation(text: "Bacon Blue Burger", x: 0.05, y: 0.80, w: 0.21, h: 0.03),
            LabelObservation(text: "$14.00", x: 0.74, y: 0.80, w: 0.08, h: 0.03),
        ])
        #expect(rows.isEmpty)
    }

    @Test func nothingIsReadOffAnEmptyPhoto() {
        #expect(MenuBoardParser.parse([]).isEmpty)
    }
}
