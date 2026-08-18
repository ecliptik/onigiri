import Foundation

/// One item read off a restaurant's nutrition table
/// (`plans/PLAN-menu-import.md`). Printed values only — like
/// `LabelParser`, this never estimates and never invents a name, so a
/// row carries no AI-provenance mark.
public struct MenuRow: Sendable, Equatable, Identifiable {
    /// How many nutrient fields this row actually carries — the measure
    /// behind `minimumFieldFillRate`.
    var filledFieldCount: Int {
        var count = kcal == nil ? 0 : 1
        if sodiumMg != nil { count += 1 }
        for value in [nutrients.fatG, nutrients.saturatedFatG, nutrients.transFatG,
                      nutrients.cholesterolMg, nutrients.carbsG, nutrients.fiberG,
                      nutrients.sugarG, nutrients.proteinG] where value != nil {
            count += 1
        }
        return count
    }

    /// Stable within one parse: the source order, which is also the
    /// order the menu prints. Rows are not unique by name (a section can
    /// repeat "Small"), so the index is the identity.
    public let id: Int
    public let name: String
    /// The heading this row printed under ("CURATED BOWLS"), when the
    /// table had one. Display grouping only — never part of the name.
    public let section: String?
    /// What the table's own serving column said ("153g"), verbatim. Nil
    /// when the table has no such column, which is the common case — a
    /// print nutrition guide states the item as sold and names no
    /// serving. Never invented.
    public let serving: String?
    public let kcal: Double?
    public let sodiumMg: Double?
    public let nutrients: NutrientValues
    /// True when the numbers are a model's ESTIMATE rather than figures
    /// the menu printed — a menu without calorie labeling. Carries the
    /// provenance dot and the review contract through to the form.
    public let aiGenerated: Bool

    /// Public so the app can build rows from a source the kit cannot see
    /// — a menu whose dishes were LISTED rather than measured, where
    /// `kcal` is nil until the one being eaten is estimated.
    public init(
        id: Int, name: String, section: String? = nil, serving: String? = nil,
        kcal: Double? = nil, sodiumMg: Double? = nil,
        nutrients: NutrientValues = NutrientValues(), aiGenerated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.section = section
        self.serving = serving
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.nutrients = nutrients
        self.aiGenerated = aiGenerated
    }

    /// Folded into a `ParsedLabel` so a picked row enters exactly the
    /// plumbing a screenshot read already uses — the prefilled food
    /// form, unchanged.
    public var parsedLabel: ParsedLabel {
        var parsed = ParsedLabel()
        parsed.name = name.isEmpty ? nil : name
        parsed.kcal = kcal
        parsed.sodiumMg = sodiumMg
        parsed.nutrients = nutrients
        // Only when the table PRINTED one. A guide that states the item
        // as sold names no serving, and inventing "1 serving" would be
        // the parser guessing, which it never does.
        parsed.servingDescription = serving
        parsed.aiGenerated = aiGenerated
        // The gate runs HERE rather than at parse time: a mis-mapped
        // column is a per-field mistake, and this is the one place every
        // consumer of a row — the picker, the form, the share sheet's
        // confirm step — passes through (`NutritionPlausibility`).
        return NutritionPlausibility.checked(parsed)
    }
}

/// Deterministic parser for a published nutrition TABLE — the whole menu
/// at once, as opposed to `LabelParser`'s single FDA panel.
///
/// Input is the same `[LabelObservation]` currency `LabelParser` takes,
/// so a PDF page (`MenuDocument`) and an OCR transcript (`LabelScan`)
/// are interchangeable here.
///
/// The table's geometry does the work, and it has to: flattening a table
/// to text is what strands the column headers dozens of lines away from
/// their numbers, which is why the model path could never read one
/// (`plans/PLAN-menu-import.md`).
public enum MenuTableParser {

    // MARK: Columns

    enum Field: Hashable {
        case energy, fat, saturated, trans, cholesterol, sodium
        case carbs, fiber, sugars, protein
        /// Parsed so its column is consumed, then DISCARDED. It exists
        /// only to stop "Cal. from Fat" being read as the calorie
        /// column — see the match order below.
        case energyFromFat
        /// TEXT, not a number ("153g"). Recognized so it lands in the
        /// serving field instead of being swept into the NAME, which is
        /// what an unrecognized column left of the numbers does: every
        /// Chick-fil-A item read as "Spicy Chicken Biscuit 153g".
        case serving
    }

    /// Match order is specificity order, exactly as `LabelParser`'s table
    /// is, and here it is load-bearing twice over on one real document:
    ///
    /// - `Cal.` appears TWICE in the CAVA header — once as the
    ///   calorie column and once as the first half of `Cal. from Fat`.
    ///   `energyFromFat` must be tested first or the calories column is
    ///   read off the wrong number.
    /// - THREE columns contain the word "fat" (`Total Fat`, `Sat. Fat`,
    ///   `Trans. fat`), so plain `fat` must be tested last.
    static let headerTable: [(Field, [String])] = [
        (.serving, ["serving size", "serving", "portion size", "amount per"]),
        (.energyFromFat, ["cal from fat", "calories from fat", "cal fr fat"]),
        (.trans, ["trans"]),
        (.saturated, ["sat fat", "saturated"]),
        (.cholesterol, ["chol"]),
        (.sodium, ["sodium", "natrium", "salt"]),
        (.fiber, ["fiber", "fibre", "dietary fiber"]),
        (.sugars, ["sugars", "sugar"]),
        (.carbs, ["carb", "carbohydrate", "total carb"]),
        (.protein, ["protein"]),
        (.fat, ["total fat", "fat"]),
        (.energy, ["calories", "cal", "energy", "kcal"]),
    ]

    struct Column {
        var minX: Double
        var maxX: Double
        var text: String
        var field: Field?
        var unit: Unit?
        var center: Double { (minX + maxX) / 2 }
    }

    enum Unit { case g, mg }

    // MARK: Bands

    struct Band {
        var runs: [LabelObservation]
        var midY: Double
        var height: Double
        /// Computed ONCE, at cluster time, and summed on merge. The
        /// verdict is asked for on every band by the join pass, the
        /// header search and the name-column scan, and recomputing it
        /// means re-parsing every run's numbers each time.
        var numberCount = 0
        var hasTextRun = false

        var isData: Bool { numberCount >= 3 && hasTextRun }
    }

    /// Cluster runs into visual rows. Same rule `LabelParser.clusterRows`
    /// uses — tolerance from the SHORTER box, so a tall display number
    /// never swallows the small-print line above it.
    static func bands(_ observations: [LabelObservation]) -> [Band] {
        joinSubPitch(cluster(observations), anchor: isDataBand)
    }

    static func cluster(_ observations: [LabelObservation]) -> [Band] {
        var bands: [Band] = []
        for run in observations.sorted(by: { $0.midY > $1.midY }) {
            // Mutated through the subscript, in place: the pulled-out
            // copy (`var last`) held a second reference to the runs
            // buffer, so every append paid a full copy-on-write clone of
            // the accumulated band (audit, 2026-08-17 — same shape as
            // LabelParser.clusterRows and joinSubPitch below).
            if let lastIndex = bands.indices.last,
               abs(run.midY - bands[lastIndex].midY) < 0.5 * min(run.h, bands[lastIndex].height) {
                bands[lastIndex].runs.append(run)
                bands[lastIndex].midY = (bands[lastIndex].midY
                    * Double(bands[lastIndex].runs.count - 1) + run.midY)
                    / Double(bands[lastIndex].runs.count)
                bands[lastIndex].height = min(bands[lastIndex].height, run.h)
            } else {
                bands.append(Band(runs: [run], midY: run.midY, height: run.h))
            }
        }
        for i in bands.indices {
            bands[i].runs.sort { $0.x < $1.x }
            for run in bands[i].runs {
                let found = numbers(in: run.text).count
                bands[i].numberCount += found
                // A run with LETTERS in it is text, even when it also
                // carries a number. This used to require a run with no
                // numbers at all, and Shake Shack's guide sets each
                // item's name, allergens and calories as ONE run ("Big
                // Shack Contains: Milk, Egg, Wheat, Soy, Sesame 900"),
                // so every burger row looked like numbers with no name
                // and `isData` rejected the lot — fourteen rows parsed
                // as one (2026-08-16). A band of bare units ("12g")
                // that this now admits still has no name, and a
                // nameless row is dropped later.
                if looksLikeProse(run.text) || (found == 0 && !run.text.isEmpty) {
                    bands[i].hasTextRun = true
                }
            }
        }
        return bands
    }

    /// Second pass: pull a band into its neighbour when the two are far
    /// closer together than the table's own row spacing.
    ///
    /// A visual row is not always one baseline. The Chick-fil-A table
    /// puts an item's NAME on a baseline a hair below its numbers, and
    /// wraps a long name onto a line below that — three bands, one row.
    /// Left split, the name band reads as a numberless row and gets
    /// glued to the row ABOVE it, which is how "Hash Brown Scramble
    /// Bowl" came out as "…Bowl 233g Dipping Sauces Dressings".
    ///
    /// The measure is the table's own DATA pitch, not glyph height:
    /// heights vary within a row, pitch does not. Two data bands are
    /// never merged — that would fuse two real items.
    /// `anchor` names the bands that ARE rows, whose spacing defines the
    /// pitch. `requireSimilarHeight` additionally refuses to absorb text
    /// set much smaller than the row it would join — a menu board's
    /// item description sits within a pitch of its item and must not
    /// become part of the dish's name.
    static func joinSubPitch(
        _ bands: [Band],
        anchor: (Band) -> Bool,
        requireSimilarHeight: Bool = false
    ) -> [Band] {
        let dataMidYs = bands.filter(anchor).map(\.midY)
        guard dataMidYs.count >= 3 else { return bands }
        let gaps = zip(dataMidYs, dataMidYs.dropFirst()).map { abs($0 - $1) }.sorted()
        let pitch = gaps[gaps.count / 2]
        guard pitch > 0 else { return bands }
        let threshold = 0.35 * pitch

        var joined: [Band] = []
        for band in bands {
            // Subscript mutation — the same COW rationale as `cluster`.
            guard let lastIndex = joined.indices.last,
                  abs(joined[lastIndex].midY - band.midY) < threshold,
                  !(anchor(joined[lastIndex]) && anchor(band)),
                  !requireSimilarHeight || similarHeight(joined[lastIndex], band)
            else {
                joined.append(band)
                continue
            }
            joined[lastIndex].runs.append(contentsOf: band.runs)
            joined[lastIndex].runs.sort { $0.x < $1.x }
            joined[lastIndex].numberCount += band.numberCount
            joined[lastIndex].hasTextRun = joined[lastIndex].hasTextRun || band.hasTextRun
            // Keep the ANCHOR's geometry: a name that trails its numbers
            // must not drag the band's midY away from the row.
            joined[lastIndex].height = min(joined[lastIndex].height, band.height)
        }
        return joined
    }

    /// Compared on the TALLEST run in each band, not the band height,
    /// which `cluster` has already shrunk to its smallest member.
    static func similarHeight(_ a: Band, _ b: Band) -> Bool {
        let ha = a.runs.map(\.h).max() ?? 0
        let hb = b.runs.map(\.h).max() ?? 0
        guard ha > 0, hb > 0 else { return false }
        return min(ha, hb) / max(ha, hb) >= 0.75
    }

    // MARK: Numbers

    /// Numbers in a run, left to right. Reuses `LabelParser`'s numeric
    /// fixups so OCR damage ("Og", "1,5") reads the same on both paths;
    /// a percentage is skipped, since a %DV column is not a value.
    static func numbers(in text: String) -> [Double] {
        // A page is mostly WORDS — dish names, descriptions, navigation.
        // Without this the five regex passes in normalizedNumericText run
        // on every one of them, and `isDataBand` asks for this repeatedly
        // (banding, header search, name-column detection). It was 2.5 s
        // on a 1,673-run page, on a Mac.
        guard text.contains(where: \.isNumber) else { return [] }
        let normalized = LabelParser.normalizedNumericText(text)
        var found: [Double] = []
        for match in normalized.matches(of: /\d+(?:\.\d+)?/) {
            var after = match.range.upperBound
            while after < normalized.endIndex, normalized[after] == " " {
                after = normalized.index(after: after)
            }
            if after < normalized.endIndex, normalized[after] == "%" { continue }
            if let value = Double(normalized[match.range]) { found.append(value) }
        }
        return found
    }

    static func fold(_ text: String) -> String {
        let lowered = text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: nil)
        let stripped = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(stripped).split(separator: " ").joined(separator: " ")
    }

    /// Columns recognised in order to be IGNORED. A nutrition table's
    /// right-hand end is micronutrients and % Daily Value, none of which
    /// Onigiri stores — and "Calcium" CONTAINS "cal", so it matched the
    /// calorie column and, sitting to the right, overwrote it: every
    /// McDonald's row read 25 kcal instead of 740 (2026-08-16). Naming
    /// them here is safer than tightening every keyword, because the
    /// next table will invent another one.
    static let ignoredHeaderWords = [
        "calcium", "vitamin", "iron", "potassium", "daily value", "dv",
    ]

    /// A nutrition table states each value once. When two columns
    /// resolve to the same field the later one is an artifact — a
    /// repeated header half, a footnote, a second table's edge — and
    /// letting it through means the right-hand one silently wins.
    static func deduplicated(_ columns: [Column]) -> [Column] {
        var seen = Set<Field>()
        return columns.map { column in
            guard let field = column.field else { return column }
            guard seen.insert(field).inserted else {
                var copy = column
                copy.field = nil
                return copy
            }
            return column
        }
    }

    static func field(forHeader text: String) -> Field? {
        let folded = fold(text)
        guard !folded.isEmpty else { return nil }
        if ignoredHeaderWords.contains(where: { folded.contains($0) }) { return nil }
        for (field, keywords) in headerTable {
            for keyword in keywords where folded.contains(keyword) { return field }
        }
        return nil
    }

    /// A header cell names its own unit — `Sodium (mg)`, `Carb. (g)`.
    /// Read it so a table printing sodium in grams still lands in mg.
    static func unit(forHeader text: String) -> Unit? {
        let folded = fold(text)
        if folded.contains("mg") { return .mg }
        if folded.contains(" g") || folded.hasSuffix("g") { return .g }
        return nil
    }

    // MARK: Parse

    /// One page. Returns nothing when the page carries no nutrition
    /// table — which is how the guide's ALLERGEN pages exclude
    /// themselves: their header has no calorie column, so no table is
    /// recognized and no page whitelist is needed.
    public static func parse(_ observations: [LabelObservation]) -> [MenuRow] {
        parse(pages: [observations])
    }

    /// A whole document. Each page re-detects its own header — the guide
    /// repeats it per page at DIFFERENT x positions, so columns found
    /// once and reused would misread every page after the first.
    public static func parse(pages: [[LabelObservation]]) -> [MenuRow] {
        var rows: [MenuRow] = []
        // Both carry across a page break, because the table does: a
        // heading is printed once, and a CONTINUATION page may reprint
        // no header at all. (The CAVA guide reprints its header on
        // every page — at different x positions — so a page's own header
        // always wins; this only fills in when there is none.)
        var section: String?
        var inherited: [Column]?
        for page in pages {
            rows.append(contentsOf: parsePage(
                page, section: &section, columns: &inherited, startingAt: rows.count))
        }
        return rows
    }

    private static func parsePage(
        _ observations: [LabelObservation],
        section: inout String?,
        columns inherited: inout [Column]?,
        startingAt offset: Int
    ) -> [MenuRow] {
        let bands = bands(observations)
        guard let dataStart = bands.firstIndex(where: { isDataBand($0) }) else { return [] }
        let header = header(above: dataStart, in: bands)
        // A page that reprints no header continues the previous page's
        // table. Without this the tail of a long menu is silently
        // dropped — the Chick-fil-A render puts its drinks on a second,
        // header-less page.
        guard let columns = header?.columns ?? inherited, !columns.isEmpty else { return [] }
        inherited = columns
        guard let firstValueX = columns.first(where: { $0.field != nil })?.minX else { return [] }
        // A table with no calorie column is not a nutrition table. The
        // allergen pages reach here and stop.
        guard columns.contains(where: { $0.field == .energy }) else { return [] }

        let body = Array(bands[(header?.bodyStart ?? 0)...])
        let nameStart = nameColumnStart(in: body, before: firstValueX)
        // The table's own type size, for telling a section heading from
        // a wrapped name below.
        let dataHeights = body.filter(\.isData).compactMap { $0.runs.map(\.h).max() }.sorted()
        let dataHeight = dataHeights.isEmpty ? 0 : dataHeights[dataHeights.count / 2]

        var rows: [MenuRow] = []
        // From just below the header, NOT from the first data row: the
        // first section heading ("CURATED BOWLS") sits between the two,
        // and starting at the data would drop it and leave every row in
        // the opening section unlabelled.
        for band in body {
            // `nameStart` and not simply "everything to the left": the
            // Chick-fil-A page carries a category SIDEBAR at the far
            // left, and its entries share bands with table rows —
            // "Kid's Meals (nutrition per entrée only) Egg White Grill"
            // was a real parsed name.
            // Normally a name run is one that ENDS before the values.
            // Shake Shack breaks that: it sets the item, its allergens
            // and its calories as a single run reaching well past the
            // calorie column, so on those bands nothing ends in the name
            // column, the name came out empty and the row was dropped —
            // fourteen burgers parsed as one (2026-08-16).
            //
            // So the wider rule applies ONLY to a band with no ordinary
            // name run at all. Chick-fil-A has ordinary names AND runs
            // that straddle the boundary, and taking the wide reading
            // there swept a "Serving Size" header into a section and
            // broke a wrapped name — measured, not supposed.
            // …and only on a DATA band. A header band has no ordinary
            // name run either, and read widely its "SERVING SIZE" cell
            // becomes part of a name, which then reads as a section
            // heading. The fallback exists to rescue rows whose name
            // merged with a VALUE, so rows are all it may touch.
            let hasNarrowName = band.runs.contains { $0.maxX <= firstValueX && $0.x >= nameStart }
            let wide = !hasNarrowName && band.isData
            func isNameRun(_ run: LabelObservation) -> Bool {
                guard run.x >= nameStart else { return false }
                return wide ? run.x < firstValueX : run.maxX <= firstValueX
            }
            let nameRuns = band.runs.filter(isNameRun)
            let valueRuns = band.runs.filter { !isNameRun($0) && $0.maxX > firstValueX }
            // Reading order, not x order: a wrapped name continues on
            // the line BELOW, and both halves sit at the same x.
            let name = nameRuns
                .sorted { $0.midY == $1.midY ? $0.x < $1.x : $0.midY > $1.midY }
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !valueRuns.isEmpty, valueRuns.contains(where: { !numbers(in: $0.text).isEmpty })
            else {
                guard !name.isEmpty else { continue }
                // A band with a name and no numbers is either a section
                // heading or the second line of a wrapped name, and
                // nothing else distinguishes them. All-caps means
                // heading; anything else continues the row above.
                if isHeading(name, height: band.runs.map(\.h).max() ?? 0, dataHeight: dataHeight) {
                    section = name
                } else if let last = rows.last {
                    rows[rows.count - 1] = MenuRow(
                        id: last.id, name: "\(last.name) \(name)", section: last.section,
                        serving: last.serving, kcal: last.kcal,
                        sodiumMg: last.sodiumMg, nutrients: last.nutrients)
                }
                continue
            }
            // A NAME IS MADE OF WORDS. The Cheesecake Factory's booklet
            // sets its product names as individual letters, which
            // cluster into bands across neighbouring columns and came
            // out as "T R I P O L A C I G G N R E E L O O C R" beside a
            // 0 kcal — 171 rows of confident nonsense (2026-08-16).
            // A parse that has gone wrong should return nothing, not
            // something: nothing prompts a screenshot, and something
            // gets logged.
            guard !name.isEmpty, looksLikeProse(name) else { continue }
            guard let row = row(
                name: name, section: section, valueRuns: valueRuns,
                columns: columns, id: offset + rows.count)
            else { continue }
            rows.append(row)
        }
        // DID THE ROWS KEEP THE HEADER'S PROMISE?
        //
        // A header that declares protein and sodium columns sits above
        // rows that fill them. When almost none do, the column mapping
        // is wrong rather than the table sparse — and a wrong mapping
        // does not fail loudly, it returns confident nonsense: the
        // Cheesecake Factory booklet produced "HUMMUS, 10 kcal" and 170
        // more like it (2026-08-16). Better to return nothing and let
        // the sheet say so; a screenshot of one item still works.
        let declared = columns.filter { $0.field != nil && $0.field != .serving }.count
        guard !rows.isEmpty else { return rows }
        // THREE columns, not one. `header` needs three nutrient WORDS to
        // accept a block, but after merging and splitting they can
        // collapse to a single usable column — and a page offering only
        // "calories" will map any stray number to it. The Cheesecake
        // booklet's decorative pages did exactly that.
        guard declared >= 3 else { return [] }
        let filled = rows.reduce(0) { $0 + $1.filledFieldCount }
        let rate = Double(filled) / Double(rows.count * declared)
        guard rate >= minimumFieldFillRate else { return [] }
        return rows
    }

    /// How much of a declared header a real table actually fills. Set
    /// well below a sparse-but-honest table (Wendy's fills 4 of 4,
    /// McDonald's nearly all) and well above a broken mapping (the
    /// Cheesecake booklet managed 0.13).
    static let minimumFieldFillRate = 0.35

    /// A WORD, not a unit. Deciding "this run is text" on any letter at
    /// all counts `662g` and `79g` as names, so a row's value-only band
    /// stopped being merged into the name band beside it and a wrapped
    /// Chick-fil-A name came apart (2026-08-16). Three letters in a row
    /// is the line: `g`, `mg`, `oz` fall below it, `Nuggets` and
    /// `Sesame` do not.
    static func looksLikeProse(_ text: String) -> Bool {
        var streak = 0
        for character in text {
            guard character.isLetter else { streak = 0; continue }
            streak += 1
            if streak >= 3 { return true }
        }
        return false
    }

    /// "Big Shack Contains: Milk, Egg, Wheat, Soy, Sesame" is one cell
    /// holding a name and an allergen notice. The notice is FDA
    /// boilerplate, worded the same way everywhere, and it is not part
    /// of what anyone would call the food — nor of what they would
    /// search for later.
    static func strippingAllergens(from name: String) -> String {
        var name = name
        // The FDA calorie footnote runs along the foot of many menus and
        // lands in whichever row sits on its baseline: "ORIGINAL
        // CHEESECAKE * Adults need an average of 2000 calories…". No
        // dish is named with an asterisk.
        if let star = name.range(of: " *") {
            let head = String(name[name.startIndex..<star.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if head.contains(where: \.isLetter) { name = head }
        }
        guard let range = name.range(of: "contains:", options: .caseInsensitive) else { return name }
        let head = String(name[name.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return head.contains(where: \.isLetter) ? head : name
    }

    /// The trailing number in a name cell that merged with the value
    /// beside it, and the name without it. Nil unless what remains is
    /// still a name — a bare number is a stray run, not an item.
    static func splitTrailingNumber(from name: String) -> (name: String, value: Double)? {
        guard let match = name.firstMatch(of: /\s(\d{1,5}(?:[.,]\d{1,3})?)\s*$/) else { return nil }
        let head = String(name[name.startIndex..<match.range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard head.contains(where: \.isLetter),
              let value = numbers(in: String(match.1)).first else { return nil }
        return (head, value)
    }

    /// Where the NAME column starts, taken from the table rather than
    /// assumed: the most common left edge among the text sitting left of
    /// the values. A page's own furniture — a category sidebar, a
    /// footnote — lands at some other x and appears in far fewer rows,
    /// so the mode is the names and the outliers drop out.
    static func nameColumnStart(in body: [Band], before firstValueX: Double) -> Double {
        var histogram: [Int: Int] = [:]
        for band in body where isDataBand(band) {
            for run in band.runs where run.maxX <= firstValueX {
                histogram[Int((run.x * 200).rounded()), default: 0] += 1
            }
        }
        guard let mode = histogram.max(by: {
            $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value
        })?.key else { return 0 }
        // A shade of slack: a wrapped line or an italic variant can start
        // a hair left of the column.
        return Double(mode) / 200 - 0.01
    }

    /// ≥3 numbers on one line, with something non-numeric to its left.
    /// Prose survives this: a paragraph mentioning "100%" carries one
    /// number, not three.
    static func isDataBand(_ band: Band) -> Bool { band.isData }

    /// A numberless band is either a SECTION HEADING or the second line
    /// of a wrapped name, and the text alone often cannot say which:
    /// Shake Shack sets its sections in Title Case ("Burgers",
    /// "Chicken"), so an all-caps test called them continuations and
    /// glued them onto the row above — no document in the sweep
    /// produced a single section (2026-08-16).
    ///
    /// Type SIZE separates them, and measurably: on that page a heading
    /// runs 1.5x the height of a data row while the paragraph of
    /// marketing prose beside it runs 0.81x. A wrapped name is set in
    /// the row's own size, so it stays a continuation.
    static func isHeading(_ name: String, height: Double, dataHeight: Double) -> Bool {
        let letters = name.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        if !letters.contains(where: \.isLowercase) { return true }
        guard dataHeight > 0 else { return false }
        return height >= 1.25 * dataHeight
    }

    /// Build the columns from the header block — the bands immediately
    /// above the first data row that carry nutrient words.
    ///
    /// The header is not one line: `Sodium` sits above `(mg)`, and
    /// `Cal.` sits above `from Fat`. So cells are assembled by X-RANGE
    /// across every header band, never per line — which is also what
    /// keeps the bare `Cal.` column apart from `Cal. from Fat`.
    struct Header {
        var columns: [Column]
        /// First band BELOW the header — where the table body starts.
        var bodyStart: Int
    }

    /// One header run holding SEVERAL column names, split back apart.
    ///
    /// The Cheesecake Factory's booklet extracts its header as
    /// "Cholesterol Carbohydrates Total Sugars Added" — one run across
    /// four columns — so the column that swallowed them all took every
    /// value with it and the page parsed into letter-soup names with
    /// zero calories (2026-08-16).
    ///
    /// Split only where the run names TWO OR MORE different nutrients,
    /// which no single column heading does; the sub-ranges are
    /// apportioned by character offset, which is exact enough for
    /// monospaced-ish header type and only has to be good enough to
    /// separate neighbours.
    static func splitMergedHeaderRun(_ run: LabelObservation) -> [LabelObservation] {
        let words = run.text.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count >= 2 else { return [run] }
        // Where each matched nutrient word STARTS, in characters.
        var starts: [(offset: Int, field: Field)] = []
        var cursor = 0
        for word in words {
            if let field = field(forHeader: String(word)), !starts.contains(where: { $0.field == field }) {
                starts.append((cursor, field))
            }
            cursor += word.count + 1
        }
        guard starts.count >= 2 else { return [run] }

        let total = Double(max(run.text.count, 1))
        var pieces: [LabelObservation] = []
        for (index, match) in starts.enumerated() {
            // A segment runs from the previous match's word to this
            // one's, so unmatched words ("Total" in "Total Fats") stay
            // with the name they qualify.
            let from = index == 0 ? 0 : match.offset
            let to = index + 1 < starts.count ? starts[index + 1].offset : run.text.count
            guard to > from else { continue }
            let lower = run.x + run.w * (Double(from) / total)
            let width = run.w * (Double(to - from) / total)
            let start = run.text.index(run.text.startIndex, offsetBy: from)
            let end = run.text.index(run.text.startIndex, offsetBy: min(to, run.text.count))
            pieces.append(LabelObservation(
                text: String(run.text[start..<end]).trimmingCharacters(in: .whitespaces),
                x: lower, y: run.y, w: width, h: run.h))
        }
        return pieces.isEmpty ? [run] : pieces
    }

    static func header(above dataStart: Int, in bands: [Band]) -> Header? {
        var block: [Band] = []
        var bottom = dataStart
        var index = dataStart - 1
        while index >= 0, block.count < 3 {
            let band = bands[index]
            let hasHeaderWord = band.runs.contains { field(forHeader: $0.text) != nil }
            if !hasHeaderWord, !block.isEmpty { break }
            if !hasHeaderWord, block.isEmpty { index -= 1; continue }
            block.insert(band, at: 0)
            bottom = index
            index -= 1
        }
        guard !block.isEmpty else { return nil }
        let runs = block.flatMap(\.runs).flatMap(splitMergedHeaderRun)
        let matches = runs.reduce(0) { $0 + (field(forHeader: $1.text) != nil ? 1 : 0) }
        guard matches >= 3 else { return nil }

        var columns: [Column] = []
        for run in runs.sorted(by: { $0.x < $1.x }) {
            if var last = columns.last, run.x <= last.maxX {
                last.minX = min(last.minX, run.x)
                last.maxX = max(last.maxX, run.maxX)
                columns[columns.count - 1] = last
            } else {
                columns.append(Column(minX: run.x, maxX: run.maxX, text: "", field: nil, unit: nil))
            }
        }
        // Cell text reads top line first, then left to right, so
        // "Sodium" + "(mg)" assembles as "Sodium (mg)" and not the
        // reverse.
        for i in columns.indices {
            let members = runs
                .filter { $0.x < columns[i].maxX && $0.maxX > columns[i].minX }
                .sorted { $0.midY == $1.midY ? $0.x < $1.x : $0.midY > $1.midY }
            columns[i].text = members.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            columns[i].field = field(forHeader: columns[i].text)
            columns[i].unit = unit(forHeader: columns[i].text)
        }
        return Header(columns: deduplicated(columns), bodyStart: bottom + 1)
    }

    private static func row(
        name: String, section: String?, valueRuns: [LabelObservation],
        columns: [Column], id: Int
    ) -> MenuRow? {
        var values: [Field: Double] = [:]
        var serving: String?
        // The serving cell is TEXT ("153g", "1 sandwich") and is taken
        // whole rather than parsed — its number is a weight, not a
        // nutrient, and running it through the numeric path would file
        // 153 under whatever column it happened to land near.
        if let column = columns.first(where: { $0.field == .serving }) {
            let cell = valueRuns
                .filter { $0.x < column.maxX && $0.maxX > column.minX }
                .sorted { $0.x < $1.x }
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            serving = cell.isEmpty ? nil : cell
        }
        let servingColumn = columns.first { $0.field == .serving }
        let numberRuns = valueRuns.filter { run in
            guard let servingColumn else { return true }
            return !(run.x < servingColumn.maxX && run.maxX > servingColumn.minX)
        }
        let valueColumns = columns.filter { $0.field != nil && $0.field != .serving }

        // PRIMARY: count match. A table row prints one number per value
        // column, in column order, so when the counts agree the mapping
        // is positional and needs no geometry at all.
        //
        // This is not an optimisation — geometry alone gets it WRONG
        // here. On the Chick-fil-A page the header words and the numbers
        // under them have different extents ("FIBER (G)" spans
        // 0.841–0.859 while its data starts at 0.860), so a run holding
        // two values landed both on the same column: fibre came out nil
        // and sugar took the fibre figure.
        var ordered = numberRuns.sorted { $0.x < $1.x }.flatMap { numbers(in: $0.text) }
        var name = name

        // A NAME CELL THAT SWALLOWED THE FIRST VALUE. Shake Shack's
        // guide sets the item, its allergen list and its calories as one
        // text run — "Big Shack Contains: Milk, Egg, Wheat, Soy, Sesame
        // 900" — so the calorie column holds nothing at all and the row
        // came up exactly one number short of its columns. Fourteen
        // burgers parsed as one (2026-08-16).
        //
        // Gated on being EXACTLY one short, which is what makes it safe:
        // a name that merely ends in a digit ("Coke 12") sits in a row
        // whose numbers already match its columns, so nothing is taken
        // from it.
        if ordered.count + 1 == valueColumns.count,
           let split = splitTrailingNumber(from: name) {
            name = split.name
            ordered.insert(split.value, at: 0)
        }
        // AFTER the split, never before: the merged cell reads
        // "… Contains: Milk, Egg, Wheat, Soy, Sesame 900", so trimming
        // the allergen clause first takes the calories with it.
        name = strippingAllergens(from: name)
        if ordered.count == valueColumns.count {
            for (column, value) in zip(valueColumns, ordered) {
                guard let field = column.field else { continue }
                values[field] = converted(value, for: field, unit: column.unit)
            }
            return assemble(
                id: id, name: name, section: section, serving: serving, values: values)
        }

        // FALLBACK: a ragged row — a blank cell, a footnote mark, a value
        // the parser couldn't read. Place what there is by geometry.
        for run in numberRuns {
            let found = numbers(in: run.text)
            guard !found.isEmpty else { continue }
            // A run can span TWO columns: adjacent cells whose gap is
            // narrow come back as one selection ("0 105", "7 7" on the
            // CAVA page). Columns whose centre falls inside the
            // run's span, in order, are the cells it covers.
            let spanned = columns.filter { $0.center >= run.x && $0.center <= run.maxX }
            let targets: [Column]
            if spanned.count == found.count {
                targets = spanned
            } else if let nearest = columns.min(by: {
                abs($0.center - run.midX) < abs($1.center - run.midX)
            }), found.count == 1 {
                targets = [nearest]
            } else {
                // Ragged: place each number under the nearest centre.
                targets = found.indices.map { i in
                    let at = run.x + (run.w * (Double(i) + 0.5) / Double(found.count))
                    return columns.min { abs($0.center - at) < abs($1.center - at) }!
                }
            }
            for (column, value) in zip(targets, found) {
                guard let field = column.field, field != .serving else { continue }
                values[field] = converted(value, for: field, unit: column.unit)
            }
        }
        return assemble(id: id, name: name, section: section, serving: serving, values: values)
    }

    private static func assemble(
        id: Int, name: String, section: String?, serving: String?, values: [Field: Double]
    ) -> MenuRow? {
        // No calories, no food. A heading row, a spacer, or a line the
        // parser only half-read never becomes an item.
        guard let kcal = values[.energy] else { return nil }
        var nutrients = NutrientValues()
        nutrients.fatG = values[.fat]
        nutrients.saturatedFatG = values[.saturated]
        nutrients.transFatG = values[.trans]
        nutrients.cholesterolMg = values[.cholesterol]
        nutrients.carbsG = values[.carbs]
        nutrients.fiberG = values[.fiber]
        nutrients.sugarG = values[.sugars]
        nutrients.proteinG = values[.protein]
        return MenuRow(
            id: id, name: name, section: section, serving: serving,
            kcal: kcal, sodiumMg: values[.sodium], nutrients: nutrients)
    }

    /// Storage stays canonical (CLAUDE.md *Units*): grams for macros,
    /// milligrams for sodium and cholesterol, whatever the table printed.
    private static func converted(_ value: Double, for field: Field, unit: Unit?) -> Double {
        let wantsMg = field == .sodium || field == .cholesterol
        switch (wantsMg, unit) {
        case (true, .g): return value * 1000
        case (false, .mg): return value / 1000
        default: return value
        }
    }
}

private extension LabelObservation {
    var midX: Double { x + w / 2 }
}
