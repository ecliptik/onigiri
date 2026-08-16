import Foundation

/// One item read off a restaurant's nutrition table
/// (`plans/PLAN-menu-import.md`). Printed values only — like
/// `LabelParser`, this never estimates and never invents a name, so a
/// row carries no AI-provenance mark.
public struct MenuRow: Sendable, Equatable, Identifiable {
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
        return parsed
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
    /// - `Cal.` appears TWICE in the Kwik Trip header — once as the
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
    }

    /// Cluster runs into visual rows. Same rule `LabelParser.clusterRows`
    /// uses — tolerance from the SHORTER box, so a tall display number
    /// never swallows the small-print line above it.
    static func bands(_ observations: [LabelObservation]) -> [Band] {
        var bands: [Band] = []
        for run in observations.sorted(by: { $0.midY > $1.midY }) {
            if var last = bands.last,
               abs(run.midY - last.midY) < 0.5 * min(run.h, last.height) {
                last.runs.append(run)
                last.midY = (last.midY * Double(last.runs.count - 1) + run.midY)
                    / Double(last.runs.count)
                last.height = min(last.height, run.h)
                bands[bands.count - 1] = last
            } else {
                bands.append(Band(runs: [run], midY: run.midY, height: run.h))
            }
        }
        for i in bands.indices { bands[i].runs.sort { $0.x < $1.x } }
        return joinSubPitch(bands)
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
    static func joinSubPitch(_ bands: [Band]) -> [Band] {
        let dataMidYs = bands.filter(isDataBand).map(\.midY)
        guard dataMidYs.count >= 3 else { return bands }
        let gaps = zip(dataMidYs, dataMidYs.dropFirst()).map { abs($0 - $1) }.sorted()
        let pitch = gaps[gaps.count / 2]
        guard pitch > 0 else { return bands }
        let threshold = 0.35 * pitch

        var joined: [Band] = []
        for band in bands {
            guard var last = joined.last,
                  abs(last.midY - band.midY) < threshold,
                  !(isDataBand(last) && isDataBand(band))
            else {
                joined.append(band)
                continue
            }
            last.runs.append(contentsOf: band.runs)
            last.runs.sort { $0.x < $1.x }
            // Keep the ANCHOR's geometry: a name that trails its numbers
            // must not drag the band's midY away from the row.
            last.height = min(last.height, band.height)
            joined[joined.count - 1] = last
        }
        return joined
    }

    // MARK: Numbers

    /// Numbers in a run, left to right. Reuses `LabelParser`'s numeric
    /// fixups so OCR damage ("Og", "1,5") reads the same on both paths;
    /// a percentage is skipped, since a %DV column is not a value.
    static func numbers(in text: String) -> [Double] {
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

    static func field(forHeader text: String) -> Field? {
        let folded = fold(text)
        guard !folded.isEmpty else { return nil }
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
        // no header at all. (The Kwik Trip guide reprints its header on
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
            let nameRuns = band.runs.filter { $0.maxX <= firstValueX && $0.x >= nameStart }
            let valueRuns = band.runs.filter { $0.maxX > firstValueX }
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
                if isHeading(name) {
                    section = name
                } else if let last = rows.last {
                    rows[rows.count - 1] = MenuRow(
                        id: last.id, name: "\(last.name) \(name)", section: last.section,
                        serving: last.serving, kcal: last.kcal,
                        sodiumMg: last.sodiumMg, nutrients: last.nutrients)
                }
                continue
            }
            guard !name.isEmpty else { continue }
            guard let row = row(
                name: name, section: section, valueRuns: valueRuns,
                columns: columns, id: offset + rows.count)
            else { continue }
            rows.append(row)
        }
        return rows
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
    static func isDataBand(_ band: Band) -> Bool {
        let counted = band.runs.reduce(0) { $0 + numbers(in: $1.text).count }
        guard counted >= 3 else { return false }
        return band.runs.contains { numbers(in: $0.text).isEmpty && !$0.text.isEmpty }
    }

    private static func isHeading(_ name: String) -> Bool {
        let letters = name.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        return !letters.contains(where: \.isLowercase)
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
        let runs = block.flatMap(\.runs)
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
        return Header(columns: columns, bodyStart: bottom + 1)
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
        let ordered = numberRuns.sorted { $0.x < $1.x }.flatMap { numbers(in: $0.text) }
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
            // Kwik Trip page). Columns whose centre falls inside the
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
