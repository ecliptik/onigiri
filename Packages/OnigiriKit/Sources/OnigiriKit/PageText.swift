import Foundation

/// A web page reduced to its words.
///
/// A RENDERED page only shows what CSS allows: Salt & Straw states its
/// calories inside a collapsed accordion, so the figure is in the
/// document and never on the page, and no amount of rendering could
/// reach it (the user, 2026-08-16). The text is there either way.
///
/// Not the per-site scraping PLAN-screenshot-nutrition vetoed — there
/// are no selectors and no knowledge of any site's markup. Tags out,
/// words left; the reader that handles a screenshot takes it from there.
public enum PageText {
    public static func stripped(from html: String) -> String {
        var text = html
        // Script and style hold code, not words, and both are full of
        // numbers that would read as nutrition.
        for pattern in [/(?s)<script\b[^>]*>.*?<\/script>/, /(?s)<style\b[^>]*>.*?<\/style>/] {
            text = text.replacing(pattern, with: " ")
        }
        text = text.replacing(/(?s)<[^>]+>/, with: "\n")
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The page's lines as observations stacked top to bottom, for the
    /// label parser — which wants geometry and here has none to want.
    /// Prose has no columns, so the coordinates are FABRICATED and only
    /// their order carries meaning; that is exactly why the parse runs
    /// in `prose` mode (`LabelParser.parse(_:prose:)`).
    ///
    /// Lives in the kit rather than beside its one caller so the
    /// regression fixtures parse the same runs the app does — the
    /// `LabelScan`/`dump-label-ocr` rule, one implementation.
    public static func observations(from text: String, limit: Int = 400) -> [LabelObservation] {
        let lines = text.split(separator: "\n").prefix(limit)
        guard !lines.isEmpty else { return [] }
        return lines.enumerated().map { index, line in
            LabelObservation(
                text: String(line), x: 0.05,
                y: 0.98 - (Double(index) / Double(lines.count)) * 0.96,
                w: 0.9, h: 0.9 / Double(lines.count))
        }
    }
}
