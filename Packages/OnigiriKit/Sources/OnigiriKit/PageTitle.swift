import Foundation

// Beside `MenuDocumentReader`, whose plausibility rule it borrows and
// which exists only where PDFKit does (not watchOS).
#if canImport(PDFKit)

/// What a shared page's TITLE says about the food on it.
///
/// A restaurant's product page names its dish and itself in the title —
/// `Chick-fil-A® Chicken Sandwich | Chick-fil-A`, `Waffle Potato Fries
/// Nutrition and Ingredients | Chick-fil-A` — and nowhere else as
/// plainly. The nutrition panel under it carries no name at all, so
/// before this the only name a shared page ever got was whatever the
/// model read off it, which it sometimes did and sometimes didn't: the
/// same page logged as "Chick-fil-A Chicken Sandwich" once and as "Menu
/// item" twice (the user, 2026-09-24). The title is deterministic, so it
/// wins; the model is the fallback.
///
/// Not per-site scraping (`PLAN-screenshot-nutrition`'s veto): no
/// selectors, no markup, one string every page has.
public enum PageTitle {
    public struct Reading: Equatable, Sendable {
        /// The dish, with the page's own furniture ("Nutrition and
        /// Ingredients", "Menu") taken off. Nil when nothing is left.
        public let item: String?
        /// The segment naming the business, when the title has one.
        public let site: String?
    }

    public static func read(_ title: String, host: String? = nil) -> Reading {
        let cleaned = title
            .replacingOccurrences(of: #"[®™©℠]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            // A SPACED hyphen or double colon separates like a bar; an
            // unspaced one is part of a name ("Chick-fil-A").
            .replacingOccurrences(of: #" (?:-|::) "#, with: " | ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = cleaned
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return Reading(item: nil, site: nil) }

        // Which segment is the business: the one the web address spells,
        // else — with more than one segment — the last, which is where
        // titles put the site name by convention.
        var siteIndex: Int?
        if let host {
            let spelled = Set(host.lowercased().split(separator: ".").map { letters(String($0)) })
            siteIndex = segments.firstIndex { spelled.contains(letters($0)) }
        }
        if siteIndex == nil, segments.count > 1 { siteIndex = segments.count - 1 }
        let site = siteIndex.map { segments[$0] }
            .flatMap { MenuDocumentReader.isPlausibleSource($0) ? $0 : nil }

        let item = segments.indices
            .filter { $0 != siteIndex }
            .lazy
            .compactMap { dish(from: segments[$0]) }
            .first
        return Reading(item: item, site: site)
    }

    /// Bars, dashes and dots. A plain hyphen is not here — it is
    /// rewritten to a bar above only when spaced.
    private static let separators: CharacterSet = CharacterSet(charactersIn: "|–—·•")

    /// A segment as a dish: page furniture trimmed from its end, and
    /// refused when what is left names nothing.
    private static func dish(from segment: String) -> String? {
        var text = segment
        var changed = true
        while changed {
            changed = false
            for suffix in furniture {
                if let range = text.range(of: #"\s*\b"# + suffix + #"$"#,
                                          options: [.regularExpression, .caseInsensitive]) {
                    text = String(text[..<range.lowerBound])
                    changed = true
                }
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // A three-letter word, the menu parser's own test for a name.
        guard text.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil else { return nil }
        guard !generic.contains(text.lowercased()) else { return nil }
        return text
    }

    /// Words a title appends to the dish rather than part of it,
    /// longest first so "Nutrition and Ingredients" goes whole.
    private static let furniture = [
        "nutrition (?:and|&) ingredients", "nutrition (?:and|&) allergens",
        "ingredients (?:and|&) nutrition", "nutrition facts", "nutrition information",
        "nutrition info", "nutrition", "ingredients", "allergens", "calories", "menu",
    ]

    /// A whole segment that names a page, not a dish.
    private static let generic: Set<String> = [
        "home", "menu", "our menu", "food", "order online", "order now", "products", "shop",
    ]

    private static func letters(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
#endif
