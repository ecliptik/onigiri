import Foundation

/// Reads a photographed MENU — a board above the counter, a card on the
/// table — where calorie labeling puts a figure beside each dish
/// (`plans/PLAN-menu-import.md`).
///
/// The sibling of `MenuTableParser` and its opposite in shape. A
/// nutrition guide is a grid with a header naming every column; a menu is
/// a list, has no header at all, and prints exactly one number that
/// matters next to prices, descriptions and dot leaders that look like
/// data and are not. So the CALORIE CELL is the anchor here: find it
/// first, and the dish is whatever names it on the same line.
///
/// Deterministic, like every printed-values path in this app. It runs
/// with AI off and reads the number the menu prints rather than
/// estimating one — which is the whole reason it exists, since the sign
/// read it displaces is prompted to *estimate* and marks its answers
/// with the AI provenance dot.
public enum MenuBoardParser {

    /// `780 Cal`, `1,020 Calories`, `430-680 Cal`. The unit word is
    /// required: a menu is covered in bare numbers (prices, table
    /// numbers, "$4 add chicken") and only this one is nutrition.
    /// Computed, not stored: `Regex` is not Sendable, so a static
    /// constant is a concurrency error under Swift 6.
    static var calorieCell: Regex<(Substring, Substring, Substring?)> {
        /(\d[\d,]*)(?:\s*[-–—]\s*(\d[\d,]*))?\s*(?:k?cal|calories|calorie)\b/.ignoresCase()
    }

    /// The calorie figure on a menu is its own small cell. This bound is
    /// what keeps the mandatory FDA footnote out — "2,000 calories a day
    /// is used for general nutrition advice…" is one long run, and
    /// without a length test it becomes a 2,000-calorie item called
    /// "Additional nutrition information available upon request".
    /// (`LabelParser` learned the same lesson from the same sentence.)
    static let longestCalorieCell = 24

    public static func parse(_ observations: [LabelObservation]) -> [MenuRow] {
        // Anchored on calorie cells, not on "≥3 numbers": a menu row has
        // a price and a calorie count and nothing else, so the table
        // parser's notion of a data row never fires here.
        //
        // requireSimilarHeight because an item's DESCRIPTION sits within
        // a row's pitch of it and is set much smaller — merged in, it
        // becomes part of the dish's name ("Classic Cheeseburger aged
        // cheddar, house pickles, brioche").
        let bands = MenuTableParser.joinSubPitch(
            MenuTableParser.cluster(observations),
            anchor: hasCalorieCell,
            requireSimilarHeight: true)

        var rows: [MenuRow] = []
        var section: String?
        for band in bands {
            guard let cell = band.runs.first(where: { calorieRun($0) != nil }),
                  let kcal = calorieRun(cell) else {
                // No calories on this line. An all-caps line is the
                // board's own heading; anything else is a description,
                // a footnote, or the restaurant's name — none of which
                // is a food, and none of which may join the row above
                // (a menu does not wrap its dish names into the line
                // below the way a table wraps a cell).
                if let heading = heading(in: band) { section = heading }
                continue
            }
            let name = name(in: band, before: cell)
            guard !name.isEmpty else { continue }
            rows.append(MenuRow(
                id: rows.count, name: name, section: section, serving: nil,
                kcal: kcal, sodiumMg: nil, nutrients: NutrientValues()))
        }
        return rows
    }

    static func hasCalorieCell(_ band: MenuTableParser.Band) -> Bool {
        band.runs.contains { calorieRun($0) != nil }
    }

    /// The calories a run states, or nil when it states none.
    ///
    /// A RANGE takes its upper bound. Both numbers are printed, so
    /// neither is invented, and the choice is deliberate: this app exists
    /// to hold a deficit, and under-reporting intake is the direction
    /// that quietly breaks that. The form opens for review either way.
    static func calorieRun(_ run: LabelObservation) -> Double? {
        let text = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= longestCalorieCell else { return nil }
        guard let match = text.firstMatch(of: calorieCell) else { return nil }
        let low = number(String(match.output.1))
        let high = match.output.2.flatMap { number(String($0)) }
        guard let value = high ?? low, value > 0, value <= 10_000 else { return nil }
        return value
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacing(",", with: ""))
    }

    /// The dish: everything on the line left of the calorie cell that is
    /// not a price. Dot leaders and currency are the two things a menu
    /// puts between a name and its numbers.
    static func name(in band: MenuTableParser.Band, before cell: LabelObservation) -> String {
        band.runs
            .filter { $0.x < cell.x && !isPrice($0.text) }
            .sorted { $0.x < $1.x }
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
            .replacing(/[.\u{2026}]{2,}/, with: " ")
            .replacing(/\s{2,}/, with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-–—"))
    }

    static func isPrice(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("$") { return true }
        // A bare "12.50" or "12" alone in its own cell is a price too;
        // a number that is part of a NAME ("7 Layer Dip") is not alone.
        return trimmed.wholeMatch(of: /\d[\d.,]*/) != nil
    }

    /// A board's section headings are set in capitals — the same rule
    /// the table parser uses, and for the same reason: nothing else
    /// distinguishes a heading from a stray line.
    static func heading(in band: MenuTableParser.Band) -> String? {
        let text = band.runs
            .sorted { $0.x < $1.x }
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = text.filter(\.isLetter)
        guard letters.count >= 3, !letters.contains(where: \.isLowercase) else { return nil }
        return text
    }
}
