import Testing
@testable import OnigiriKit

/// Emoji out of the fields that hold a measure. The suggestion bar
/// offers 💯 for "100", and one tap replaced a serving's number with it
/// (the user, 2026-09-25).
struct EmojiTextTests {
    @Test func theSuggestionThatStartedIt() {
        #expect(EmojiText.stripped("💯") == "")
        #expect(EmojiText.stripped("💯 g") == " g")
    }

    /// Digits, # and * carry Unicode's `isEmoji` (they can begin a
    /// keycap), and a serving is mostly digits — none of them may go.
    @Test func digitsAndMeasuresStay() {
        for text in ["1 hot dog (57 g)", "2 tbsp", "8 fl oz", "½ cup", "100 g", "#2 combo", "3*", "2°C"] {
            #expect(EmojiText.stripped(text) == text, "\(text)")
        }
    }

    /// Every shape an emoji takes: plain, variation-selected, keycap,
    /// flag, skin tone, ZWJ family.
    @Test func everyKindOfEmojiGoes() {
        #expect(EmojiText.stripped("1 hot dog 🌭") == "1 hot dog ")
        #expect(EmojiText.stripped("❤️ 1 cup") == " 1 cup")
        #expect(EmojiText.stripped("1️⃣ slice") == " slice")
        #expect(EmojiText.stripped("1 🇺🇸 cup") == "1 cup", "the doubled space it leaves collapses")
        #expect(EmojiText.stripped("2 👍🏽 bars") == "2 bars")
        #expect(EmojiText.stripped("👨‍👩‍👧 1 bowl") == " 1 bowl")
    }

    /// Nothing to strip, nothing touched — including spaces typed on
    /// purpose, which a field being edited must keep.
    @Test func textWithoutEmojiIsUntouched() {
        #expect(EmojiText.stripped("1  cup ") == "1  cup ")
    }

    /// The icon slots share the rule: one emoji is an icon, a digit is not.
    @Test func iconSlotsUseTheSameRule() {
        #expect(SharedStore.isCustomEmoji("🍙"))
        #expect(SharedStore.isCustomEmoji("❤️"))
        #expect(!SharedStore.isCustomEmoji("1"))
        #expect(!SharedStore.isCustomEmoji("#"))
    }

    /// A database or a model can hand one over too; the product every
    /// door builds cleans it on the way in.
    @Test func aProductsServingArrivesClean() {
        let product = ScannedProduct(
            barcode: "x", name: "Hot dog", kcal: 300, sodiumMg: nil,
            servingDescription: "1 🌭 (57 g)", nutrients: NutrientValues())
        #expect(product.servingDescription == "1 (57 g)")
    }
}
