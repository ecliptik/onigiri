import Foundation
import Testing
@testable import OnigiriKit

/// A nutrition sheet that TURNS its column names, and the reading
/// machinery a turned name needs (`plans/PLAN-menu-import.md`).
///
/// The document is somisomi's nutrition page, which the share sheet
/// could not read at all (the user, 2026-08-23): a React shell whose two
/// tables are `<img>` PNGs, so the rendered page's text layer holds only
/// navigation and a cookie banner. The fixture is what
/// `MenuDocumentReader.readOCR` gets off that render — strips, read
/// twice — and it is captured through the shipping path rather than by
/// hand, exactly as the PDF fixtures beside it are.
///
/// Eleven column names have to fit above eleven narrow number columns,
/// so the sheet sets them at about 60°. That breaks two assumptions at
/// once and each has its own test below: OCR reads a turned name into a
/// box that overlaps its neighbours, and it reads most of them UPSIDE
/// DOWN.
struct MenuTableParserDiagonalTests {
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

    // MARK: The document

    @Test func theTurnedHeaderSheetParses() throws {
        let rows = MenuTableParser.parse(try fixture("menu-somisomi-rendered"))
        #expect(rows.count >= 25, "the first table lists 27 items, got \(rows.count)")
    }

    /// Every figure in the row, in the field the sheet printed it under.
    /// Before the turned header was understood this same row came back
    /// with its carbohydrates filed as sodium — a plausible number in the
    /// wrong place, which is the failure the parser's gates exist to stop
    /// and the one a row count alone would never catch.
    @Test func aRowLandsUnderTheColumnsTheSheetPrinted() throws {
        let rows = MenuTableParser.parse(try fixture("menu-somisomi-rendered"))
        let sesame = try #require(
            rows.first { $0.name == "BLACK SESAME" },
            "the first item; got \(rows.prefix(3).map(\.name))")
        expectEqual(sesame.kcal, 280)
        expectEqual(sesame.sodiumMg, 115, "and NOT 37, which is the carbohydrates")
        expectEqual(sesame.nutrients.carbsG, 37)
        expectEqual(sesame.nutrients.cholesterolMg, 40)
    }

    /// The two columns most easily swapped on this sheet: cholesterol and
    /// sodium print side by side, both in mg, both three digits.
    @Test func neighbouringColumnsInTheSameUnitStayApart() throws {
        let rows = MenuTableParser.parse(try fixture("menu-somisomi-rendered"))
        let cheddar = try #require(rows.first { $0.name == "CHEDDAR TAIYAKI" })
        expectEqual(cheddar.kcal, 160)
        expectEqual(cheddar.nutrients.cholesterolMg, 175)
        expectEqual(cheddar.sodiumMg, 205)
        expectEqual(cheddar.nutrients.fatG, 10.5)
        expectEqual(cheddar.nutrients.saturatedFatG, 4.5)
    }

    /// A DROPPED figure is the acceptable outcome; a MOVED one is not.
    /// OCR loses cells on this sheet — a printed `0` most often — and the
    /// two readings this replaced both filled the gap rather than admit
    /// it, one by counting and one by nearest column. Nothing here may
    /// carry a figure that belongs to another column.
    @Test func aFigureIsPlacedInsideAColumnOrNotAtAll() throws {
        let rows = MenuTableParser.parse(try fixture("menu-somisomi-rendered"))
        // Sodium on this sheet is 50–205 mg and carbohydrates 12–49 g.
        // A carbohydrate figure read as sodium is the exact shift that
        // shipped, and it shows up as sodium below 50.
        for row in rows {
            if let sodium = row.sodiumMg {
                #expect(sodium >= 50, "\(row.name) has \(sodium) mg — a carbohydrate figure")
            }
        }
    }

    /// `TOTAL ADDED SUGAR` contains the keyword for a column Onigiri does
    /// keep. Where a sheet prints both, the plain `SUGAR` heading beside
    /// it already won on being leftmost — but OCR lost that heading here
    /// and the added-sugars column inherited the field, so every soft
    /// serve reported 20 g of sugar against a printed 31.
    @Test func addedSugarsNeverBecomeSugars() throws {
        let rows = MenuTableParser.parse(try fixture("menu-somisomi-rendered"))
        let chocolate = try #require(rows.first { $0.name == "CHOCOLATE" })
        #expect(chocolate.nutrients.sugarG == nil, "the sheet's 31 g was not read; 20 g is its added sugars")
    }

    /// THE SAME PAGE, READ ON THE PHONE, before its headings were read.
    ///
    /// Vision downsamples what it is handed and the phone's threshold
    /// sits far below the Mac's, so the strips — sized for the data rows
    /// — delivered every figure on this sheet and exactly ONE column
    /// name. The parser is right to refuse that, and this pins it: a
    /// table with no columns must return nothing rather than map its
    /// figures onto the one column it can see.
    ///
    /// `MenuDocumentReader.readingHeader` is what stops the reader
    /// arriving here — one close look at about two megapixels over the
    /// band above the first data row, which reads all ten names.
    @Test func aTableWhoseColumnsWentUnreadIsRefused() throws {
        let runs = try fixture("menu-somisomi-device-headerless")
        #expect(runs.count > 400, "every figure on the sheet is present")
        #expect(runs.contains { $0.text == "BLACK SESAME" })
        #expect(runs.contains { $0.text == "CALORIES" })
        // Not `field(forHeader:)`: `SALTED CARAMEL` answers to the
        // sodium keyword `salt`, which is harmless in a NAME column and
        // would make this assertion lie.
        #expect(!runs.contains { $0.text == "SODIUM" },
                "and not one of the other ten column names")
        #expect(MenuTableParser.parse(runs).isEmpty,
                "a sheet with one column name yields no rows, not 27 wrong ones")
    }

    // MARK: The header

    /// A turned name's box is as tall as the word is long. That is a
    /// property of the ink, so it reads the same on every platform —
    /// unlike counting which boxes touch, which macOS Vision and iOS
    /// Vision disagreed about on this very sheet.
    @Test func turnedNamesAreOneColumnEach() {
        let runs = [
            LabelObservation(text: "SATURATED FAT", x: 0.430, y: 0.82, w: 0.045, h: 0.024),
            LabelObservation(text: "TRANS FAT", x: 0.472, y: 0.82, w: 0.036, h: 0.018),
            LabelObservation(text: "CHOLESTEROL", x: 0.516, y: 0.82, w: 0.041, h: 0.022),
            LabelObservation(text: "SODIUM", x: 0.560, y: 0.82, w: 0.030, h: 0.014),
        ]
        let columns = MenuTableParser.turnedColumns(runs, rowAspect: 1.49)
        #expect(columns?.count == 4, "four names, four columns — not one merged block")
        #expect(columns?.map(\.field) == [.saturated, .trans, .cholesterol, .sodium])
        #expect(columns?.allSatisfy(\.anchored) == true)
    }

    /// ONE overlapping pair is enough, and it has to be: iOS Vision
    /// left only one of somisomi's headings in contact where macOS
    /// Vision left three, so a rule wanting two read the same sheet as
    /// turned on the Mac and as upright on the phone — where
    /// `SATURATED FAT` and `TRANS FAT` became a single column and every
    /// row shifted, reporting 31 g of sugar as 31 mg of sodium.
    @Test func oneOverlappingPairIsEnough() {
        let runs = [
            LabelObservation(text: "TOTAL FAT", x: 0.388, y: 0.82, w: 0.035, h: 0.018),
            LabelObservation(text: "SATURATED FAT", x: 0.430, y: 0.82, w: 0.045, h: 0.024),
            LabelObservation(text: "TRANS FAT", x: 0.472, y: 0.82, w: 0.036, h: 0.018),
            LabelObservation(text: "CHOLESTEROL", x: 0.516, y: 0.82, w: 0.041, h: 0.022),
        ]
        let columns = MenuTableParser.turnedColumns(runs, rowAspect: 1.49)
        #expect(columns?.count == 4, "only saturated and trans touch, and that is the whole signal")
    }

    /// A name set at a FULL 90° is narrower than its column and leans on
    /// nothing, so the ordinary merge handles it — McDonald's, Shake
    /// Shack and Chipotle have all read correctly that way since the day
    /// they were fixtured. Rotation alone must never route a header
    /// here.
    @Test func aVerticalHeaderThatLeansOnNothingIsLeftAlone() {
        let runs = [
            LabelObservation(text: "Calories", x: 0.463, y: 0.82, w: 0.010, h: 0.0455),
            LabelObservation(text: "Total Fat (g)", x: 0.517, y: 0.82, w: 0.010, h: 0.0678),
            LabelObservation(text: "Sat Fat (g)", x: 0.568, y: 0.82, w: 0.010, h: 0.0572),
            LabelObservation(text: "Sodium (mg)", x: 0.619, y: 0.82, w: 0.010, h: 0.0700),
        ]
        #expect(MenuTableParser.turnedColumns(runs, rowAspect: 0.48) == nil,
                "vertical, but nothing overlaps")
    }

    /// An upright header is set at about the size of the rows under it.
    @Test func anUprightHeaderIsNotReadAsTurned() {
        let runs = [
            LabelObservation(text: "Total Fat", x: 0.40, y: 0.8, w: 0.05, h: 0.011),
            LabelObservation(text: "Sodium", x: 0.50, y: 0.8, w: 0.05, h: 0.010),
            LabelObservation(text: "Total Carb.", x: 0.60, y: 0.8, w: 0.05, h: 0.012),
            LabelObservation(text: "Protein", x: 0.70, y: 0.8, w: 0.05, h: 0.010),
        ]
        #expect(MenuTableParser.turnedColumns(runs, rowAspect: 1.49) == nil)
    }

    /// Only the TURNED runs become columns. A unit line and a section
    /// label share the header block and are set at row size; given a
    /// column of their own they would swallow the figures beside them.
    @Test func onlyTheTurnedRunsBecomeColumns() {
        let runs = [
            LabelObservation(text: "CALORIES", x: 0.344, y: 0.812, w: 0.033, h: 0.017),
            LabelObservation(text: "CHOLESTEROL", x: 0.516, y: 0.824, w: 0.041, h: 0.022),
            LabelObservation(text: "mg", x: 0.516, y: 0.817, w: 0.016, h: 0.0035),
            LabelObservation(text: "SODIUM", x: 0.550, y: 0.824, w: 0.030, h: 0.014),
            LabelObservation(text: "SOFT SERVE ONLY (6 wt. oz)", x: 0.190, y: 0.815, w: 0.144, h: 0.005),
        ]
        let columns = MenuTableParser.turnedColumns(runs, rowAspect: 1.49)
        #expect(columns?.map(\.field) == [.energy, .cholesterol, .sodium])
        #expect(columns?.first(where: { $0.field == .cholesterol })?.unit == .mg,
                "the unit line still attaches to the name above it")
    }

    /// Detection is about the header's LAYOUT, not about which columns
    /// Onigiri keeps: the moment `TOTAL ADDED SUGAR` joined the ignored
    /// list it stopped counting toward the tally, one real sheet fell
    /// back to being read as upright, and its rows shifted a column.
    @Test func anIgnoredHeadingStillCountsAsAHeading() {
        #expect(MenuTableParser.namesAColumn("TOTAL ADDED SUGAR"))
        #expect(MenuTableParser.namesAColumn("CALCIUM"))
        #expect(MenuTableParser.field(forHeader: "TOTAL ADDED SUGAR") == nil)
        #expect(!MenuTableParser.namesAColumn("mg"))
        #expect(!MenuTableParser.namesAColumn("BLACK SESAME"))
    }
}
