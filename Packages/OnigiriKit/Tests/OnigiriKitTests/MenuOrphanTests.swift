#if canImport(PDFKit)
import Foundation
import Testing
#if canImport(AppKit)
import AppKit
#endif
@testable import OnigiriKit

/// Rows whose figures were read and whose name was not
/// (`MenuTableParser.Orphan`), and the two ways a reader names them
/// after all (`MenuDocumentReader.resolvingOrphans`).
struct MenuOrphanTests {
    private func fixture(_ name: String) throws -> [LabelObservation] {
        struct Dump: Decodable { let observations: [LabelObservation] }
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url)).observations
    }

    /// An iPhone read every figure of three Jollibee rows and none of
    /// their names (2026-09-23). They are orphans, reported with their
    /// figures, and still not rows.
    @Test func aDeviceReadingReportsItsNamelessRows() throws {
        let plain = try fixture("menu-jollibee-device")
        let orphans = MenuTableParser.orphans(in: plain)
        #expect(orphans.map { $0.row.kcal } == [659, 638, 481])
        #expect(orphans.allSatisfy { $0.row.name.isEmpty })
        #expect(MenuTableParser.parse(plain).count == 24)
    }

    /// The other reading of the same picture has "Bacon Breakfast
    /// Sandwich Meal" with the same figures — borrowed, once. The two it
    /// did not read either stay unlisted rather than guessed at.
    @Test func aNameIsBorrowedFromTheOtherReadingOnMatchingFigures() async throws {
        let plain = try fixture("menu-jollibee-device")
        let paged = try fixture("menu-jollibee-device-tablemodel")
        let (runs, recovered) = await MenuDocumentReader.resolvingOrphans(plain, other: paged, image: nil)
        let rows = MenuTableParser.parse(runs)
        #expect(recovered == "1b/0c/3")
        #expect(rows.count == 25)
        let meal = try #require(rows.first { $0.name == "Bacon Breakfast Sandwich Meal" })
        #expect(meal.kcal == 481)
        #expect(meal.sodiumMg == 971)
        #expect(meal.section == "BREAKFAST")
        #expect(Set(rows.map(\.name)).count == rows.count, "no name used twice")
    }

    /// Nothing to borrow from: the name cell is read again, close up.
    /// The screenshot's own transcript with one name taken out, which is
    /// exactly what the phone produced for this row — and the crop reads
    /// it back whole.
    #if canImport(AppKit)
    @Test func aLostNameIsReadAgainFromItsCell() async throws {
        let url = try #require(Bundle.module.url(
            forResource: "menu-jollibee-screenshot", withExtension: "jpg", subdirectory: "Fixtures"))
        let image = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let blinded = try fixture("menu-jollibee-screenshot").filter { !$0.text.hasPrefix("Ultimate") }
        #expect(MenuTableParser.orphans(in: blinded).map(\.row.kcal) == [659])
        let (runs, recovered) = await MenuDocumentReader.resolvingOrphans(blinded, other: [], image: image)
        #expect(recovered == "0b/1c/1")
        let row = try #require(MenuTableParser.parse(runs).first { $0.kcal == 659 })
        #expect(row.name == "Ultimate Bacon Bacon Angus Cheeseburger")
    }
    #endif

    /// What the device's crop actually returned for that row.
    @Test func aCropDropsTheNextCellsEdge() {
        #expect(MenuDocumentReader.trimmedCropName("Ultimate Bacon Bacon Angus Cheeseburger (2")
            == "Ultimate Bacon Bacon Angus Cheeseburger")
        #expect(MenuDocumentReader.trimmedCropName("Spaghetti Family Pack (Serves 3-4)")
            == "Spaghetti Family Pack (Serves 3-4)")
    }

    @Test func figuresMustAgreeToBorrow() {
        func row(_ kcal: Double, sodium: Double, fat: Double, carbs: Double, protein: Double) -> MenuRow {
            MenuRow(id: 0, name: "x", kcal: kcal, sodiumMg: sodium,
                    nutrients: NutrientValues(fatG: fat, carbsG: carbs, proteinG: protein))
        }
        let a = row(481, sodium: 971, fat: 28, carbs: 37, protein: 20)
        #expect(MenuDocumentReader.sameFigures(a, row(481, sodium: 971, fat: 28, carbs: 37, protein: 20)))
        // One misread digit is tolerated…
        #expect(MenuDocumentReader.sameFigures(a, row(481, sodium: 971, fat: 28, carbs: 37, protein: 26)))
        // …two are a different row, and so is a different calorie count.
        #expect(!MenuDocumentReader.sameFigures(a, row(481, sodium: 971, fat: 29, carbs: 38, protein: 20)))
        #expect(!MenuDocumentReader.sameFigures(a, row(482, sodium: 971, fat: 28, carbs: 37, protein: 20)))
    }
}
#endif
