import Foundation

/// Emoji, told apart from the digits and symbols that share their
/// Unicode property.
///
/// The keyboard's predictions offer 💯 for "100", and one tap on the
/// suggestion bar put it into a food's Serving field in place of the
/// number (the user, 2026-09-25). A serving is free text — "1 hot dog
/// (57 g)", "2 tbsp" — so it cannot use a number pad; it strips emoji
/// instead, typed or arriving from a database, a model or a read.
///
/// Names keep theirs on purpose: an emoji in a food's name is a choice,
/// one in its serving is an accident.
public enum EmojiText {
    /// The icon slots' rule: presented as emoji. `isEmoji` alone is
    /// true of "0"–"9", "#" and "*" (they can start a keycap sequence),
    /// so a single scalar counts only with emoji presentation; a
    /// variation selector or a multi-scalar sequence (flags, keycaps,
    /// ZWJ families, skin tones) counts whatever its first scalar is.
    public static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation
            || scalars.contains { $0.properties.isVariationSelector }
            || scalars.count > 1
    }

    /// `text` with every emoji removed. Spaces the removal left doubled
    /// collapse to one, and only then — a field being typed into keeps
    /// the spaces its user put there.
    public static func stripped(_ text: String) -> String {
        guard text.contains(where: isEmoji) else { return text }
        let kept = String(text.filter { !isEmoji($0) })
        return kept.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    }
}
