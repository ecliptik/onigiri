import Foundation

/// One OCR observation: a text fragment and its Vision-normalized bounding
/// box (origin lower-left, unit square). Codable so fixture transcripts
/// captured by `scripts/dump-label-ocr.swift` decode directly.
public struct LabelObservation: Sendable, Equatable, Codable {
    public let text: String
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public init(text: String, x: Double, y: Double, w: Double, h: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    var midY: Double { y + h / 2 }
    var maxX: Double { x + w }
}

/// What a nutrition label yielded. Every field is parsed-or-nil — the form
/// shows what was read and leaves the rest blank; nothing is guessed.
/// Values are per serving when a serving weight was found (per-100g panels
/// are converted); otherwise `isPer100g` stays true and the serving
/// description says so, mirroring the OpenFoodFacts fallback.
public struct ParsedLabel: Sendable, Equatable {
    public var servingDescription: String?
    public var servingGrams: Double?
    public var kcal: Double?
    public var sodiumMg: Double?
    public var nutrients = NutrientValues()
    public var isPer100g = false
    /// A name for the food, when the image carried one. A photographed
    /// panel doesn't — a SCREENSHOT of a restaurant's nutrition page
    /// nearly always does, and retyping it was the whole complaint
    /// (PLAN-screenshot-nutrition). Always nil from the deterministic
    /// parse, which never invents one; only a model read fills it.
    public var name: String?
    /// Set when a per-100g panel was converted to per-serving — anything
    /// later read off the raw transcript (the Foundation Models
    /// refinement pass) must apply the same factor to stay on basis.
    public var per100gScaleFactor: Double?
    /// These numbers are a model's ESTIMATE, not values printed anywhere
    /// — a sign or menu that named the food without listing nutrition.
    /// Rides the label so the candidates dialog and the food form keep
    /// the provenance mark; a deterministic parse never sets it.
    public var aiGenerated = false

    public init() {}

    public var isEmpty: Bool {
        kcal == nil && sodiumMg == nil && nutrients.isEmpty
    }

    /// The prefill currency the food form consumes. A label carries no
    /// barcode — callers pass through anything the user already typed
    /// so a scan can't erase it. What the user typed ALWAYS wins; the
    /// label's own `name` (a screenshot or sign read) fills only a blank.
    public func scannedProduct(name: String = "", fallbackServing: String = "") -> ScannedProduct {
        ScannedProduct(
            barcode: "",
            name: name.isEmpty ? (self.name ?? "") : name,
            kcal: kcal,
            sodiumMg: sodiumMg,
            servingDescription: servingDescription ?? fallbackServing,
            nutrients: nutrients,
            aiGenerated: aiGenerated)
    }
}

/// Deterministic nutrition-panel parser: `[(text, box)] → ParsedLabel`.
/// Geometry does the table work — y-bands associate a nutrient name with
/// its amount, x-position picks the value column (leftmost amount column;
/// the %DV column is excluded by its position and the % suffix).
public enum LabelParser {
    // MARK: Nutrient keyword table

    private enum Field: Hashable {
        case energy, fat, saturated, trans, poly, mono
        case cholesterol, sodium, salt, carbs, fiber, sugars, protein, caffeine
        case micro(Micronutrient)
    }

    /// Match order is specificity order: sub-nutrients before their parents
    /// (saturated before fat), so a row claims exactly one field. Keywords
    /// match with word boundaries against case/diacritic-folded text; EN/FR
    /// per the label formats the app targets, plus the DE/NL/ES synonyms
    /// multilingual EU panels carry.
    private static let keywordTable: [(Field, [String])] = [
        (.trans, ["trans"]),
        (.saturated, ["saturated", "satures", "gesattigte", "verzadigde", "saturadas"]),
        (.poly, ["polyunsaturated", "polyinsatures"]),
        (.mono, ["monounsaturated", "monoinsatures"]),
        (.sugars, ["sugars", "sugar", "sucres", "zucker", "suikers", "azucares"]),
        (.fiber, ["fiber", "fibre", "fibres", "ballaststoffe", "vezels"]),
        (.carbs, ["carbohydrate", "carb", "glucides", "kohlenhydrate", "koolhydraten", "hidratos"]),
        (.cholesterol, ["cholesterol"]),
        (.sodium, ["sodium", "natrium"]),
        (.salt, ["salt", "sel", "salz", "zout", "sal"]),
        (.protein, ["protein", "proteins", "proteines", "eiweiss", "eiwitten", "proteinas"]),
        (.caffeine, ["caffeine", "cafeine"]),
        (.energy, ["calories", "energy", "energie", "energia"]),
        (.fat, ["fat", "lipides", "grasses", "fett", "vetten", "grasas"]),
        (.micro(.vitaminA), ["vitamin a", "vitamine a"]),
        (.micro(.vitaminC), ["vitamin c", "vitamine c"]),
        (.micro(.vitaminD), ["vitamin d", "vitamine d"]),
        (.micro(.vitaminE), ["vitamin e", "vitamine e"]),
        (.micro(.vitaminK), ["vitamin k", "vitamine k"]),
        (.micro(.vitaminB6), ["vitamin b6", "vitamine b6"]),
        (.micro(.vitaminB12), ["vitamin b12", "vitamine b12"]),
        (.micro(.thiamin), ["thiamin", "thiamine"]),
        (.micro(.riboflavin), ["riboflavin", "riboflavine"]),
        (.micro(.niacin), ["niacin", "niacine"]),
        (.micro(.folate), ["folate", "folic acid", "folacine"]),
        (.micro(.biotin), ["biotin", "biotine"]),
        (.micro(.pantothenicAcid), ["pantothen"]),
        (.micro(.calcium), ["calcium"]),
        (.micro(.iron), ["iron", "fer", "eisen"]),
        (.micro(.potassium), ["potassium", "kalium"]),
        (.micro(.magnesium), ["magnesium"]),
        (.micro(.zinc), ["zinc"]),
        (.micro(.phosphorus), ["phosphorus", "phosphore"]),
        (.micro(.iodine), ["iodine", "iode"]),
        (.micro(.selenium), ["selenium"]),
        (.micro(.copper), ["copper", "cuivre"]),
        (.micro(.manganese), ["manganese"]),
        (.micro(.chloride), ["chloride", "chlorure"]),
        (.micro(.chromium), ["chromium", "chrome"]),
        (.micro(.molybdenum), ["molybdenum", "molybdene"]),
    ]

    private static let anchors = [
        "nutrition facts", "valeur nutritive", "valeurs nutritive",
        "valeurs nutrition", "nutrition information", "nahrwert",
        "voedingswaarde", "informacion nutricional",
    ]

    // MARK: Amounts

    private enum AmountUnit { case g, mg, mcg, kcal, kj, ml }

    private struct Amount {
        let value: Double
        let unit: AmountUnit?
    }

    /// OCR fixups that only apply inside numeric contexts: letter O misread
    /// for zero ("Og", "16Omg", "O.5g"), comma decimals ("30,9").
    static func normalizedNumericText(_ text: String) -> String {
        // Every rule below rewrites an O/o or a comma. A cell that has
        // neither — "450", "1570", most of a nutrition table — cannot be
        // changed by any of them, and five regex passes over it is pure
        // cost. Exactly equivalent, just not paid for.
        guard text.contains(where: { $0 == "O" || $0 == "o" || $0 == "," }) else { return text }
        var s = text
        s = s.replacing(/(\d)[Oo](?=\d)/) { "\($0.output.1)0" }
        s = s.replacing(/(\d)[Oo](?=(?:g|mg|mcg|ug|µg|kg|ml)\b)/.ignoresCase()) { "\($0.output.1)0" }
        s = s.replacing(/\b[Oo](?=\d)/) { _ in "0" }
        s = s.replacing(/\b[Oo](?=\s?(?:g|mg|mcg|ug|µg|kg|ml)\b)/) { _ in "0" }
        s = s.replacing(/(\d),(?=\d)/) { "\($0.output.1)." }
        return s
    }

    // Locale is Sendable (unlike Regex below) so it can be a stored
    // static — building one per fold() call was pure waste.
    private static let foldingLocale = Locale(identifier: "en_US")

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: foldingLocale)
            .lowercased()
    }

    // Computed: Regex isn't Sendable, so a stored static trips strict
    // concurrency.
    private static var amountRegex: Regex<(Substring, lt: Substring?, num: Substring, unit: Substring?)> {
        /(?<lt><\s*)?(?<num>\d+(?:\.\d+)?)\s?(?<unit>g|mg|mcg|µg|ug|kcal|kj|cal|ml)?\b/
            .ignoresCase()
    }

    /// All amounts in a fragment, in reading order. Amounts carrying a %
    /// (the %DV column) yield nothing; "<1g" applies the label convention
    /// of half the bound; a digit glued to a preceding letter ("b3" OCR
    /// noise) is not a number.
    private static func amounts(in text: String) -> [Amount] {
        let normalized = normalizedNumericText(text)
        var result: [Amount] = []
        for match in normalized.matches(of: amountRegex) {
            if match.range.lowerBound > normalized.startIndex {
                let before = normalized[normalized.index(before: match.range.lowerBound)]
                if before.isLetter || before.isNumber || before == "." { continue }
            }
            var after = match.range.upperBound
            while after < normalized.endIndex, normalized[after] == " " {
                after = normalized.index(after: after)
            }
            if after < normalized.endIndex, normalized[after] == "%" { continue }
            guard var value = Double(match.num) else { continue }
            if match.lt != nil { value /= 2 }
            let unit: AmountUnit? = switch match.unit?.lowercased() {
            case "g": .g
            case "mg": .mg
            case "mcg", "µg", "ug": .mcg
            case "kcal", "cal": .kcal
            case "kj": .kj
            case "ml": .ml
            default: nil
            }
            result.append(Amount(value: value, unit: unit))
        }
        return result
    }

    // MARK: Rows

    private struct Row {
        var cells: [LabelObservation]
        var midY: Double
        var height: Double
        /// Stored, finalized once at the end of clusterRows (cells stop
        /// changing there): the parse passes re-read these 3+ times per
        /// row, and the computed versions re-joined and re-folded on
        /// every access.
        var text = ""
        var folded = ""
    }

    private static func clusterRows(_ observations: [LabelObservation]) -> [Row] {
        var rows: [Row] = []
        for obs in observations.sorted(by: { $0.midY > $1.midY }) {
            // Tolerance from the smaller box: a tall value ("Calories 280"
            // display print) must not get absorbed into the small-print
            // caption line above it.
            if var last = rows.last,
               abs(obs.midY - last.midY) < 0.6 * min(obs.h, last.height) {
                last.cells.append(obs)
                rows[rows.count - 1] = last
            } else {
                rows.append(Row(cells: [obs], midY: obs.midY, height: obs.h))
            }
        }
        for i in rows.indices {
            rows[i].cells.sort { $0.x < $1.x }
            rows[i].text = rows[i].cells.map(\.text).joined(separator: " ")
            rows[i].folded = fold(rows[i].text)
        }
        return rows
    }

    private static func keywordMatch(in folded: String) -> Field? {
        for (field, keywords) in keywordTable {
            for keyword in keywords where matches(folded, keyword: keyword) {
                return field
            }
        }
        return nil
    }

    private static func matches(_ folded: String, keyword: String) -> Bool {
        guard folded.contains(keyword) else { return false }
        if keyword.contains(" ") { return true }
        return folded.range(
            of: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b",
            options: .regularExpression
        ) != nil
    }

    /// Range of the earliest keyword occurrence in a cell's text, located on
    /// the folded string and mapped back by character offset (folding here
    /// is per-character, so offsets line up).
    private static func keywordRange(in text: String) -> Range<String.Index>? {
        let folded = fold(text)
        var best: Range<String.Index>?
        for (_, keywords) in keywordTable {
            for keyword in keywords {
                let pattern = keyword.contains(" ")
                    ? NSRegularExpression.escapedPattern(for: keyword)
                    : "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
                guard let range = folded.range(of: pattern, options: .regularExpression) else { continue }
                if best == nil || range.lowerBound < best!.lowerBound { best = range }
            }
        }
        guard let best else { return nil }
        let lower = folded.distance(from: folded.startIndex, to: best.lowerBound)
        let upper = folded.distance(from: folded.startIndex, to: best.upperBound)
        guard let start = text.index(text.startIndex, offsetBy: lower, limitedBy: text.endIndex),
              let end = text.index(start, offsetBy: upper - lower, limitedBy: text.endIndex) else { return nil }
        return start..<end
    }

    // MARK: Table transcripts (iOS 26 documents request)

    /// Lays a semantic table (rows of cell transcripts, as
    /// RecognizeDocumentsRequest returns them) onto a synthetic grid so
    /// the same geometry parser handles both pipelines. Cell transcripts
    /// keep their line breaks: each wrapped line becomes its own band,
    /// which is what lets a merged "Saturated … ⏎ + Trans …" cell claim
    /// two nutrients and a stacked "2252/ ⏎ 539" cell read as kJ/kcal.
    public static func observations(fromTableRows tableRows: [[String]]) -> [LabelObservation] {
        let maxColumns = tableRows.map(\.count).max() ?? 0
        guard maxColumns > 0 else { return [] }
        let lineRows = tableRows.map { row in
            row.map { cell in
                cell.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }
        let bandsPerRow = lineRows.map { row in max(row.map(\.count).max() ?? 1, 1) }
        let step = 1.0 / Double(bandsPerRow.reduce(0, +) + 2)
        var result: [LabelObservation] = []
        var band = 0
        for (rowIndex, row) in lineRows.enumerated() {
            for (columnIndex, lines) in row.enumerated() {
                for (lineIndex, line) in lines.enumerated() {
                    result.append(LabelObservation(
                        text: line,
                        x: 0.02 + 0.9 * Double(columnIndex) / Double(maxColumns),
                        y: 1.0 - Double(band + lineIndex + 1) * step,
                        w: 0.85 / Double(maxColumns),
                        h: step * 0.7))
                }
            }
            band += bandsPerRow[rowIndex]
        }
        return result
    }

    // MARK: Parse

    /// `prose` reads a web page's WORDS, where this parser's geometry
    /// does not exist (`SharedPageReader` fabricates a coordinate per
    /// line, so every safeguard below is inert and every number on the
    /// page is a candidate for every keyword above it).
    ///
    /// Three rules change, and each one has a corpse behind it
    /// (2026-08-16, `plans/PLAN-nutrition-plausibility.md`):
    ///
    /// - An amount must carry its own unit. A panel states the unit once
    ///   in the column header; prose has no header, so a bare number
    ///   near a keyword is just a number — a price, a year, a quantity.
    /// - No `pending` carry-forward. Wrapped nutrient names are a panel
    ///   phenomenon; in prose it means "Made with Bitterman Salt"
    ///   adopts the `$15` on the next line.
    /// - Salt → sodium needs that unit specifically, because it is the
    ///   one conversion with a ×400 amplifier and the one keyword that
    ///   is also a brand name, an ingredient-list entry and an ordinary
    ///   English word. `Salt & Straw © 2026 All Rights Reserved` logged
    ///   810,400 mg of sodium: 2026 × 0.4 × 1000.
    ///
    /// **Do not make these unconditional.** EU panels print the unit in
    /// the column header and the value cell bare (`Sel/Zout/Salz` │
    /// `(g)` │ `0,107`) — `euPer100gPanel` and `euTableRows` fail
    /// immediately, which is the check that this belongs to prose alone.
    /// Calories are untouched either way: energy has its own column
    /// logic, and a bare number after the word is the convention there
    /// (`Calories per serving: 300` is the whole reason a page is read).
    public static func parse(_ observations: [LabelObservation], prose: Bool = false) -> ParsedLabel {
        var label = ParsedLabel()
        let trimmed = observations.compactMap { obs -> LabelObservation? in
            let text = obs.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return LabelObservation(text: text, x: obs.x, y: obs.y, w: obs.w, h: obs.h)
        }
        guard !trimmed.isEmpty else { return label }

        // Anchor crop: drop anything above the panel title when present.
        var kept = trimmed
        if let anchor = trimmed
            .filter({ obs in anchors.contains { fold(obs.text).contains($0) } })
            .max(by: { $0.midY < $1.midY }) {
            kept = trimmed.filter { $0.midY <= anchor.y + anchor.h + 0.01 }
        }

        var rows = clusterRows(kept)

        // Footnotes ("* The % Daily Value (DV) tells you…") carry keyword
        // lookalikes; drop rows led by footnote markers.
        rows.removeAll { row in
            guard let first = row.cells.first else { return true }
            return first.text.hasPrefix("*") || first.text.hasPrefix("•") || first.text.hasPrefix("†")
        }

        // %DV column boundary: the leftmost header that *starts* with %.
        // Amount candidates at or right of it, on rows below it, are %DV
        // noise regardless of whether OCR kept their % sign. Must sit
        // right of the name column — bilingual headers wrap "% Daily
        // Value" onto a left-edge line that is not a column boundary.
        let dvHeader = kept
            .filter { $0.text.hasPrefix("%") && $0.x > 0.3 }
            .min(by: { $0.x < $1.x })

        // The topmost nutrient row separates the header region (title,
        // serving line, column captions) from the table body.
        var firstNutrientRowY = -Double.infinity
        for row in rows where keywordMatch(in: row.folded) != nil {
            firstNutrientRowY = max(firstNutrientRowY, row.midY)
        }

        // Serving line and label basis.
        var isPer100g = false
        var servingDescription: String?
        var servingGrams: Double?

        for row in rows {
            let folded = row.folded
            if folded.contains("servings per") || folded.contains("portions par") { continue }
            if folded.contains("serving size") || folded.contains("portion size") {
                let remainder = row.text
                    .replacing(/(?i).*serving size:?\s*/, with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty { servingDescription = remainder }
            } else if servingDescription == nil,
                      row.text.contains("("),
                      let match = row.text.firstMatch(
                        of: /^(?:Per|Pour)\s+(?<desc>.+?)\s*(?:\*|\/\s*(?:Per|Pour)\b|$)/.ignoresCase()
                      ) {
                servingDescription = String(match.desc).trimmingCharacters(in: .whitespaces)
            }
            if folded.contains("100 g") || folded.contains("100g") || folded.contains("100 ml"),
               row.midY >= firstNutrientRowY {
                // Header region only — a footnote mentioning 100 g must not
                // flip the basis after nutrients were read per serving.
                isPer100g = true
            }
        }

        if let desc = servingDescription,
           let match = desc.firstMatch(of: /\(\s*(?<num>\d+(?:[.,]\d+)?)\s*(?:g|ml)\s*\)/.ignoresCase()),
           let grams = Double(match.num.replacing(",", with: ".")) {
            servingGrams = grams
        }

        // EU panels have no serving line; the portion column header carries
        // a bare weight ("15g") above the first nutrient row — sometimes
        // embedded in a longer multilingual header fragment.
        if isPer100g, servingGrams == nil {
            let headerCells = rows
                .filter { $0.midY > firstNutrientRowY }
                .flatMap(\.cells)
                .sorted { $0.x < $1.x }
            outer: for cell in headerCells {
                for match in fold(cell.text).matches(of: /\b(?<num>\d{1,3}(?:[.,]\d+)?)\s?g\b/) {
                    guard let grams = Double(match.num.replacing(",", with: ".")),
                          grams != 100, grams <= 500 else { continue }
                    servingGrams = grams
                    break outer
                }
            }
        }

        // Nutrient rows, top to bottom. First match claims a field; a
        // keyword row with no amount stays pending across wrapped
        // continuation lines (multilingual names wrap onto the row that
        // holds the value).
        var values: [Field: Amount] = [:]
        var pending: (field: Field, rowsLeft: Int)?

        func rowAmount(_ row: Row, after keywordCell: LabelObservation?) -> Amount? {
            let excludeFrom: Double? = {
                guard let dvHeader, row.midY < dvHeader.midY else { return nil }
                return dvHeader.x - 0.01
            }()
            for cell in row.cells {
                if let keywordCell, cell.x < keywordCell.x { continue }
                if let excludeFrom, cell.x >= excludeFrom { continue }
                let candidates: [Amount]
                if let keywordCell, cell == keywordCell {
                    // Inline value: only text after the keyword counts, so
                    // a number inside the name ("Vitamin B12") can't be
                    // taken by itself — but "Fat / Lipides 0 g" is.
                    guard let range = keywordRange(in: cell.text) else { continue }
                    candidates = amounts(in: String(cell.text[range.upperBound...]))
                } else {
                    candidates = amounts(in: cell.text)
                }
                // In prose the unit is the only thing separating an
                // amount from a price, a year, or a street number.
                if let amount = candidates.first(where: { !prose || $0.unit != nil }) { return amount }
            }
            return nil
        }

        for row in rows where row.midY <= firstNutrientRowY {
            let folded = row.folded
            if folded.contains("added") || folded.contains("includes") { continue }
            if folded.contains("serving size") || folded.contains("servings per") { continue }

            guard let field = keywordMatch(in: folded), values[field] == nil else {
                // No new keyword: a pending wrapped name may own this row's
                // value.
                if let p = pending {
                    if let amount = rowAmount(row, after: nil) {
                        values[p.field] = amount
                        pending = nil
                    } else if p.rowsLeft > 1 {
                        pending = (p.field, p.rowsLeft - 1)
                    } else {
                        pending = nil
                    }
                }
                continue
            }

            if case .energy = field {
                pending = nil
                continue // energy has its own kJ/kcal column logic below
            }

            let keywordCell = row.cells.first { keywordMatch(in: fold($0.text)) == field }
            if let amount = rowAmount(row, after: keywordCell) {
                values[field] = amount
                pending = nil
            } else {
                // A keyword with no amount is a wrapped label name on a
                // panel and an ordinary sentence in prose, where holding
                // the field open just means the next number wins.
                pending = prose ? nil : (field, 2)
            }
        }

        // Energy: kJ/kcal pairs stack vertically per column on EU panels
        // and sit side by side on US ones. Group numeric fragments from the
        // energy row band (plus one continuation row) into x-columns; a
        // column whose two values ratio ≈4.184 is kJ over kcal, else the
        // leftmost single value wins (bare = kcal, the US convention).
        if let energyRowIndex = rows.firstIndex(where: { row in
            if case .energy = keywordMatch(in: row.folded) { return true }
            return false
        }) {
            let row = rows[energyRowIndex]
            var kcal: Double?
            if let keywordCell = row.cells.first(where: {
                let folded = fold($0.text)
                return folded.contains("calorie") || folded.contains("energ")
            }), let range = keywordRange(in: keywordCell.text) {
                let inline = amounts(in: String(keywordCell.text[range.upperBound...]))
                if let marked = inline.first(where: { $0.unit == .kcal }) {
                    kcal = marked.value
                } else if inline.count == 1, let only = inline.first {
                    kcal = only.unit == .kj ? only.value / 4.184 : (only.unit == nil ? only.value : nil)
                }
            }
            if kcal == nil {
                var cells = row.cells
                if energyRowIndex + 1 < rows.count,
                   keywordMatch(in: rows[energyRowIndex + 1].folded) == nil {
                    cells += rows[energyRowIndex + 1].cells
                }
                var columns: [(x: Double, amounts: [Amount], foldedText: String)] = []
                for cell in cells.sorted(by: { $0.x < $1.x }) {
                    let cellAmounts = amounts(in: cell.text)
                    let foldedCell = fold(cell.text)
                    guard !cellAmounts.isEmpty || foldedCell.contains("kcal") || foldedCell.contains("kj")
                    else { continue }
                    if let index = columns.firstIndex(where: { abs($0.x - cell.x) < 0.06 }) {
                        columns[index].amounts += cellAmounts
                        columns[index].foldedText += " " + foldedCell
                    } else {
                        columns.append((cell.x, cellAmounts, foldedCell))
                    }
                }
                for column in columns {
                    let numbers = column.amounts.map(\.value).filter { $0 > 0 }
                    guard numbers.count == 2, numbers[1] > 0 else { continue }
                    let ratio = numbers[0] / numbers[1]
                    if (3.6...4.8).contains(ratio) { kcal = numbers[1]; break }
                    if ratio > 0, (3.6...4.8).contains(1 / ratio) { kcal = numbers[0]; break }
                }
                if kcal == nil {
                    for column in columns {
                        guard column.amounts.count == 1, let amount = column.amounts.first else { continue }
                        if amount.unit == .kcal || column.foldedText.contains("kcal") {
                            kcal = amount.value
                        } else if amount.unit == .kj || column.foldedText.contains("kj") {
                            kcal = amount.value / 4.184
                        } else if amount.unit == nil {
                            kcal = amount.value
                        }
                        if kcal != nil { break }
                    }
                }
            }
            if let kcal, kcal >= 0, kcal < 10_000 {
                values[.energy] = Amount(value: kcal, unit: .kcal)
            }
        }

        // Assemble, converting each amount into the app's field unit. A
        // bare number defaults to the field's label-convention unit (grams
        // for macros, milligrams for sodium/cholesterol).
        func grams(_ field: Field) -> Double? {
            guard let amount = values[field] else { return nil }
            return switch amount.unit {
            case .g, nil: amount.value
            case .mg: amount.value / 1_000
            case .mcg: amount.value / 1_000_000
            default: nil
            }
        }
        func milligrams(_ field: Field) -> Double? {
            guard let amount = values[field] else { return nil }
            return switch amount.unit {
            case .mg, nil: amount.value
            case .g: amount.value * 1_000
            case .mcg: amount.value / 1_000
            default: nil
            }
        }

        label.kcal = values[.energy]?.value
        label.sodiumMg = milligrams(.sodium)
        // ×400 from grams of salt to milligrams of sodium: the largest
        // amplifier in the parser, on its most ambiguous keyword. In
        // prose it fires only on a stated mass.
        if label.sodiumMg == nil, !prose || values[.salt]?.unit != nil,
           let saltG = grams(.salt) {
            label.sodiumMg = saltG * 0.4 * 1_000
        }
        label.nutrients.fatG = grams(.fat)
        label.nutrients.saturatedFatG = grams(.saturated)
        label.nutrients.transFatG = grams(.trans)
        label.nutrients.polyunsaturatedFatG = grams(.poly)
        label.nutrients.monounsaturatedFatG = grams(.mono)
        label.nutrients.cholesterolMg = milligrams(.cholesterol)
        label.nutrients.carbsG = grams(.carbs)
        label.nutrients.fiberG = grams(.fiber)
        label.nutrients.sugarG = grams(.sugars)
        label.nutrients.proteinG = grams(.protein)
        label.nutrients.caffeineMg = milligrams(.caffeine)

        for (field, amount) in values {
            guard case .micro(let micro) = field else { continue }
            // Micronutrient amounts need an explicit unit — a bare number
            // in the vitamin tail is usually a stray %DV.
            let canonical: Double? = switch (amount.unit, micro.unit) {
            case (.mg, .milligrams), (.mcg, .micrograms): amount.value
            case (.mg, .micrograms): amount.value * 1_000
            case (.mcg, .milligrams): amount.value / 1_000
            case (.g, _): amount.value * micro.unit.perGram
            default: nil
            }
            if let canonical { label.nutrients[micro] = canonical }
        }

        // Basis: convert per-100g panels to per serving when a weight is
        // known; otherwise say so, matching the OpenFoodFacts fallback.
        if isPer100g {
            if let grams = servingGrams {
                let factor = grams / 100
                label.kcal = label.kcal.map { $0 * factor }
                label.sodiumMg = label.sodiumMg.map { $0 * factor }
                label.nutrients = label.nutrients.scaled(by: factor)
                label.per100gScaleFactor = factor
                label.servingGrams = grams
                label.servingDescription = servingDescription
                    ?? "1 portion (\(grams.formatted(.number.precision(.fractionLength(0...1)))) g)"
            } else if !label.isEmpty {
                label.isPer100g = true
                label.servingDescription = "per 100 g"
            }
        } else {
            label.servingGrams = servingGrams
            label.servingDescription = servingDescription ?? (label.isEmpty ? nil : "1 serving")
        }

        return label
    }
}
