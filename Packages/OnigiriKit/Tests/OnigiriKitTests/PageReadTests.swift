import Foundation
import Testing
@testable import OnigiriKit

/// Reading a shared WEB PAGE — `PageText` + `LabelParser` in prose mode,
/// the pair behind `SharedPageReader` (`plans/PLAN-nutrition-plausibility.md`).
///
/// Fixtures are the real stripped text of real pages, produced by
/// `PageText.stripped(from:)` off the live HTML, so these runs are the
/// ones the app parses — not a hand-written approximation of them.
struct PageReadTests {
    private func page(_ name: String) throws -> [LabelObservation] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"),
            "missing fixture \(name)")
        return PageText.observations(from: try String(contentsOf: url, encoding: .utf8))
    }

    // MARK: The incident

    /// 2026-08-16: this page logged a 300 kcal dessert with **810,400 mg
    /// of sodium**. Its last line is `Salt & Straw © 2026 All Rights
    /// Reserved` — the copyright YEAR, taken as grams of salt and
    /// converted at 0.4 × 1000. The calories are real and must survive;
    /// nothing else on the page is nutrition.
    @Test func aCopyrightYearIsNotSalt() throws {
        let label = LabelParser.parse(try page("page-saltandstraw-galette"), prose: true)
        #expect(label.kcal == 300, "stated in a sentence inside the collapsed accordion")
        #expect(label.sodiumMg == nil, "2026 × 0.4 × 1000 = 810,400 — the bug this test exists for")
        #expect(label.nutrients.sugarG == nil, "the ingredients line names Sugar and no amount")
        #expect(label.nutrients.fatG == nil)
    }

    /// The sibling failure on the sibling page: `Made with Bitterman
    /// Salt` carries no amount, and the next line is the PRICE — `$15`,
    /// which became 15 g of salt and 6,000 mg of sodium. Wrong, and
    /// small enough to be believed, which is the worse half.
    @Test func aPriceIsNotSalt() throws {
        let label = LabelParser.parse(try page("page-saltandstraw-seasalt"), prose: true)
        #expect(label.kcal == 340)
        #expect(label.sodiumMg == nil, "$15 × 0.4 × 1000 = 6,000")
    }

    /// A recipe page is 16 KB of prose with ingredient weights all over
    /// it. It states no nutrition per serving, so it must yield none —
    /// the menu parser's rule (`PLAN-menu-import` Round 6) applied to
    /// pages: a read that goes wrong returns NOTHING.
    @Test func aRecipeIsNotAFood() throws {
        let label = LabelParser.parse(try page("page-recipe-kingarthur"), prose: true)
        #expect(label.kcal == nil)
        #expect(label.isEmpty)
    }

    /// The same page RENDERED — real PDF geometry, not fabricated
    /// coordinates — which is the path tried first for a shared link.
    /// The calories live in a collapsed accordion and never reach the
    /// rendering, but `Salt & Straw © 2026 All Rights Reserved` does,
    /// laid out as a genuine text run. So the footer is a live route to
    /// the same 810,400 on a page that only has to supply a calorie
    /// figure from somewhere else — and the accordion's HEADING, the
    /// bare word "Nutrition", is rendered, which is enough to send the
    /// text to a model that might supply one.
    ///
    /// A rendered page reaching this reader has already failed the table
    /// parse, so it has no columns to protect: prose.
    @Test func aRenderedPageReadsAsProse() throws {
        let url = try #require(Bundle.module.url(
            forResource: "page-rendered-saltandstraw", withExtension: "json",
            subdirectory: "Fixtures"))
        struct Dump: Decodable { let observations: [LabelObservation] }
        let runs = try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url)).observations
        #expect(runs.count == 67)
        #expect(LabelParser.parse(runs, prose: true).sodiumMg == nil)
        #expect(LabelParser.parse(runs, prose: true).kcal == nil, "the figure is inside the accordion")
    }

    // MARK: A restaurant's product page, rendered

    private func rendered(_ name: String) throws -> [LabelObservation] {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        struct Dump: Decodable { let observations: [LabelObservation] }
        return try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url)).observations
    }

    /// 2026-09-24: shared from Safari, this page logged a side of fries
    /// at **2 kcal**. The page sets its panel BESIDE the ingredients, and
    /// "Calories 420" shares a line with "…sodium acid pyrophosphate…" —
    /// so the row read as sodium, and the only calorie row left was the
    /// FDA footnote, "2,000 calories a day", its comma taken as a decimal
    /// point. Captured with the extension's own render (a 1280-wide
    /// WKWebView's `createPDF`) through `scripts/dump-pdf-text.swift`.
    ///
    /// Read both ways because `SharedPageReader` reads a render as a
    /// panel first and page TEXT as prose second; neither may say 2.
    @Test(arguments: [false, true])
    func caloriesBesideTheIngredientsStillRead(prose: Bool) throws {
        let label = LabelParser.parse(try rendered("page-rendered-chickfila-fries"), prose: prose)
        #expect(label.kcal == 420, "not the footnote's 2,000 read as 2")
        #expect(label.sodiumMg == 240)
        #expect(label.nutrients.fatG == 24)
        #expect(label.nutrients.saturatedFatG == 4)
        #expect(label.nutrients.transFatG == 0)
        #expect(label.nutrients.cholesterolMg == 0)
        #expect(label.nutrients.carbsG == 45)
        #expect(label.nutrients.fiberG == 5)
        #expect(label.nutrients.sugarG == 1)
        #expect(label.nutrients.proteinG == 5)
    }

    /// The sibling page read its calories — this layout's line fell the
    /// other way — but lost its carbs, as every US restaurant page did:
    /// "Total Carbohydrates" is PLURAL, and whole-word matching knew only
    /// "carbohydrate" and "carb".
    @Test func pluralCarbohydratesRead() throws {
        let label = LabelParser.parse(try rendered("page-rendered-chickfila-sandwich"))
        #expect(label.kcal == 420)
        #expect(label.nutrients.carbsG == 41)
        #expect(label.sodiumMg == 1460)
        #expect(label.nutrients.cholesterolMg == 70)
        #expect(label.nutrients.proteinG == 29)
    }

    /// The footnote on its own, with no panel to lose to: it states a
    /// diet, never a food, and must yield no calories at all.
    @Test func theDailyValueFootnoteIsNotAFood() {
        let runs = PageText.observations(from: """
            2,000 calories a day is used for general nutrition advice, but calorie needs vary.
            """)
        #expect(LabelParser.parse(runs).kcal == nil)
        #expect(LabelParser.parse(runs, prose: true).kcal == nil)
    }

    // MARK: Prose that really is a panel

    /// Prose mode must not go blind: a page that prints its panel as
    /// lines of text still reads, because every amount states its own
    /// unit. This is the case the shared-page reader exists to serve.
    @Test func aPanelWrittenOutInLinesStillReads() {
        let runs = PageText.observations(from: """
            Peanut Butter Cups
            Serving Size 2 pieces (42g)
            Calories 220
            Total Fat 13g
            Saturated Fat 5g
            Sodium 105mg
            Total Carbohydrate 24g
            Dietary Fiber 2g
            Total Sugars 21g
            Protein 5g
            """)
        let label = LabelParser.parse(runs, prose: true)
        #expect(label.kcal == 220)
        #expect(label.sodiumMg == 105)
        #expect(label.nutrients.fatG == 13)
        #expect(label.nutrients.saturatedFatG == 5)
        #expect(label.nutrients.carbsG == 24)
        #expect(label.nutrients.fiberG == 2)
        #expect(label.nutrients.sugarG == 21)
        #expect(label.nutrients.proteinG == 5)
    }

    /// Salt is not banned in prose — a STATED MASS still converts. The
    /// rule is "say the unit", which every real panel does and no
    /// footer, price or copyright line ever will.
    @Test func saltWithAStatedMassStillConverts() {
        let runs = PageText.observations(from: """
            Sea Salt Crackers
            Energy 120 kcal
            Salt 1.2g
            """)
        let label = LabelParser.parse(runs, prose: true)
        #expect(label.kcal == 120)
        #expect(label.sodiumMg == 480, "1.2 g salt × 0.4 → 480 mg sodium")
    }
}
