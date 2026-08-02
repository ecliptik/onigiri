import Foundation

/// The food a photo's TEXT names, when there is no nutrition panel to
/// parse — a bakery-case card, a shelf sign, a menu board, the front of
/// a package.
///
/// `LabelParser` correctly returns nothing for these: they carry no
/// panel, and inventing one is exactly what it must never do. But the
/// picture still SAYS what the food is, and throwing that away is what
/// left a pasted bakery sign opening a blank food form (the user,
/// 2026-08-02: "GREEN ONION", its ingredients and its net weight all
/// read cleanly, and none of it reached the form).
///
/// This is the no-model floor: pure text selection, no estimate, no
/// nutrition. `FoodIntelligence.readFoodSign` does the richer job when
/// AI is switched on; this runs when it isn't, so the answer degrades
/// to a half-filled form instead of a dead end.
public enum SignText {
    /// The name the sign gives the food, plus a serving when the text
    /// states one unambiguously. nil when nothing on it reads like a
    /// food name.
    public static func namedFood(in transcript: [LabelObservation]) -> ParsedLabel? {
        guard let name = name(in: transcript) else { return nil }
        var label = ParsedLabel()
        label.name = name
        label.servingDescription = netWeight(in: transcript)
        return label
    }

    /// A sign is typeset so the product name is the biggest thing on it,
    /// so the rule is "largest text that isn't furniture" — measured by
    /// AREA, not height.
    ///
    /// Height alone loses, and the two fixtures show exactly why. On the
    /// bakery-case card the tallest box by a mile is the vertical
    /// Japanese label running down the left edge (h 0.128 against "HAM &
    /// CHEESE" at 0.033) — tall because it is a COLUMN of characters,
    /// not because it is prominent. Area puts the two within 6% of each
    /// other, which is still too thin to trust, so vertical boxes are
    /// dropped outright: a horizontal line of text is always wider than
    /// it is tall, and every name we want is horizontal.
    static func name(in transcript: [LabelObservation]) -> String? {
        // A brand is printed on every bag in the case ("SUNMERRY", four
        // times in one frame) while the product name appears once. Any
        // line that repeats is packaging, not the thing being named.
        var occurrences: [String: Int] = [:]
        for observation in transcript {
            let key = observation.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            occurrences[key, default: 0] += 1
        }
        let candidates = transcript.filter { observation in
            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleName(text) else { return false }
            // Vertical text: a column of CJK characters, never the
            // Latin product line.
            guard observation.w > observation.h else { return false }
            return occurrences[text.lowercased(), default: 0] == 1
        }
        guard let winner = candidates.max(by: { $0.w * $0.h < $1.w * $1.h }) else { return nil }
        let full = [winner.text] + continuation(of: winner, among: candidates)
        return titleCased(
            full.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " "))
    }

    /// Sign names wrap: "HAM & CHEESE" over "FILLING BAGEL". The second
    /// line sits directly under the first, indented within it, and set
    /// slightly smaller — take it, or the form reads "Ham & Cheese" and
    /// loses what the thing actually is.
    ///
    /// Bounded on all three axes so an ingredient run underneath can't
    /// be swept in: on the green-onion card the line below the name is
    /// "Flour/Sugar/Salt/Egg/Milk", which fails the size test at 30% of
    /// the name's height before its slashes are even considered.
    static func continuation(
        of winner: LabelObservation, among candidates: [LabelObservation]
    ) -> [String] {
        let next = candidates.filter { other in
            guard other != winner else { return false }
            // Below the winner, within one line's height. Vision's boxes
            // overlap slightly on tightly-set lines, so the window opens
            // a little ABOVE the winner's baseline too.
            let gap = winner.y - (other.y + other.h)
            guard gap > -winner.h, gap < winner.h else { return false }
            // Same size family — a caption or a price is not a name.
            guard other.h >= winner.h * 0.6 else { return false }
            // Horizontally inside the first line's span.
            return other.x >= winner.x - winner.w * 0.15
                && other.x + other.w <= winner.x + winner.w * 1.15
        }
        // One continuation line only: two is a paragraph, not a name.
        return next.max { $0.w * $0.h < $1.w * $1.h }.map { [$0.text] } ?? []
    }

    static func isPlausibleName(_ text: String) -> Bool {
        // Two characters admits CJK names ("麵包"); the ceiling rejects
        // the sentence-length lines — ingredient runs and warnings —
        // that a name never is.
        guard text.count >= 2, text.count <= 40 else { return false }
        let folded = text.lowercased()
        // Page furniture, by the words that only ever appear on it.
        let furniture = [
            "allergen", "warning", "contains", "ingredient", "net wt", "net weight",
            "nutrition", "calories", "serving", "keep refrigerated", "best by",
            "sell by", "made in", "distributed by", "product of",
        ]
        if furniture.contains(where: { folded.contains($0) }) { return false }
        // A price, a weight, a code — anything a currency mark claims,
        // and anything with no letters in it at all.
        if text.contains(where: { "$€£¥₩".contains($0) }) { return false }
        guard text.contains(where: { $0.isLetter }) else { return false }
        // An ingredient list, which on these cards is slash- or
        // comma-separated: "Flour/Sugar/Salt/Egg/Milk".
        let separators = text.filter { $0 == "/" || $0 == "," }.count
        if separators >= 2 { return false }
        // Mostly digits means a weight or a code that kept a stray
        // letter ("250z" — OCR of "2.5oz", language correction being
        // off on purpose).
        return text.filter(\.isLetter).count > text.filter(\.isNumber).count
    }

    /// Signs shout. "GREEN ONION" reads better in the form as "Green
    /// Onion", and the user edits it either way — but only an all-caps
    /// line is touched, so brand casing like "iPhone" survives.
    static func titleCased(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty, letters.allSatisfy({ $0.isUppercase }) else { return text }
        return text.split(separator: " ", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : $0.prefix(1) + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// A net weight, only when it parses cleanly with a real unit token.
    ///
    /// Deliberately strict. The green-onion card's "Net WT. 2.5oz" came
    /// back from Vision as "Net WT 250z" — the period gone and the "o"
    /// read as a zero, which is the same OCR confusion that makes label
    /// scanning run with language correction OFF. A repair rule that
    /// turned that into "25 oz" would be ten times wrong; nil is right.
    /// Blank beats wrong, the app's standing rule.
    static func netWeight(in transcript: [LabelObservation]) -> String? {
        for observation in transcript {
            guard observation.text.lowercased().contains("net w") else { continue }
            guard let match = observation.text.firstMatch(
                of: /(?<amount>\d+(?:\.\d+)?)\s*(?<unit>oz|g|kg|lb|ml|l)\b/.ignoresCase()
            ) else { continue }
            return "\(match.amount) \(match.unit.lowercased())"
        }
        return nil
    }
}
