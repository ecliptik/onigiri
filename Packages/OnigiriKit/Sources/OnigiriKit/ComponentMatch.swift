import Foundation

/// Matching a food NAME against the library, for the two places a name is
/// all we have: an AI meal estimate's components (which must reuse a saved
/// food rather than mint a twin) and a logged meal's Contains rows (whose
/// snapshot carries a name and a kcal share, never a reference).
///
/// **Deliberately strict.** Matching is exact on the normalized form — no
/// substring matching, no word reordering. Reordering would equate "rice
/// pudding" with "pudding rice", and substrings would equate "chicken"
/// with "chicken skin". WHEN IN DOUBT, DON'T MATCH: an unmatched
/// component mints a food, which is visible and harmless, and an
/// unmatched Contains row simply isn't tappable. A WRONG match silently
/// attributes some other food's calories. Loosening any of this is a
/// tested change, never a guess.
///
/// `LibraryDuplicate.nameMatches` stays separate on purpose — it guards a
/// different decision (the food form's duplicate-food alert) and compares
/// raw trimmed text.
public enum ComponentMatch {
    /// Case, diacritics, punctuation, spacing, and simple plurals folded
    /// away — everything that is spelling rather than identity.
    public static func normalized(_ name: String) -> String {
        let folded = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: nil)
        // Punctuation becomes a separator, not nothing: "chicken,rice"
        // is two words, and gluing them would invent "chickenrice".
        let separated = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(separated)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(singularized)
            .joined(separator: " ")
    }

    /// The first name in `names` that means the same food, or nil.
    public static func index(of component: String, in names: [String]) -> Int? {
        let target = normalized(component)
        guard !target.isEmpty else { return nil }
        return names.firstIndex { normalized($0) == target }
    }

    /// `Meal.loggedItems` writes a multiplier into the name ("2× Egg",
    /// and with fractions "1.5× Egg" — locale-formatted, so the decimal
    /// separator varies). Strip up to the first "× " rather than parsing
    /// a number, and only when what precedes it really is one: a food
    /// honestly named "Salt × Pepper" must survive untouched.
    public static func strippingQuantityPrefix(_ name: String) -> String {
        guard let marker = name.range(of: "× ") else { return name }
        let prefix = name[name.startIndex..<marker.lowerBound]
        guard !prefix.isEmpty,
              prefix.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," || $0 == " " }),
              prefix.contains(where: \.isNumber)
        else { return name }
        return String(name[marker.upperBound...])
            .trimmingCharacters(in: .whitespaces)
    }

    /// Plural → singular for the shapes food names actually take. Left
    /// alone: short words, and the -ss/-us/-is endings where the "s" is
    /// part of the word ("hummus", "couscous", "swiss").
    private static func singularized(_ word: Substring) -> String {
        let text = String(word)
        guard text.count > 3, text.hasSuffix("s") else { return text }
        for keep in ["ss", "us", "is"] where text.hasSuffix(keep) { return text }
        return String(text.dropLast())
    }
}
