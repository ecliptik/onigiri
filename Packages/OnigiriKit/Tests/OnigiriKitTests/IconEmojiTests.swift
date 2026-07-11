import Testing
@testable import OnigiriKit

struct IconEmojiTests {
    @Test func rewardPresetsMap() {
        #expect(SharedStore.rewardEmoji(for: "onigiri") == "🍙")
        #expect(SharedStore.rewardEmoji(for: "trophy") == "🏆")
        #expect(SharedStore.rewardEmoji(for: nil) == "🍙")
        #expect(SharedStore.rewardEmoji(for: "") == "🍙")
        #expect(SharedStore.rewardEmoji(for: "unknown-tag") == "🍙")
    }

    @Test func customEmojiPassesThroughEverySlot() {
        #expect(SharedStore.rewardEmoji(for: "🦄") == "🦄")
        #expect(SharedStore.foodEmoji(for: "🌮") == "🌮")
        #expect(SharedStore.waterEmoji(for: "🍺") == "🍺")
    }

    @Test func emojiValidatorAcceptsRealEmoji() {
        #expect(SharedStore.isCustomEmoji("🦄"))
        #expect(SharedStore.isCustomEmoji("🍙"))
        // Multi-scalar sequences are one visible character.
        #expect(SharedStore.isCustomEmoji("👨‍👩‍👧"))
        #expect(SharedStore.isCustomEmoji("🇯🇵"))
        #expect(SharedStore.isCustomEmoji("☺️"))
    }

    @Test func emojiValidatorRejectsTextAndMultiples() {
        #expect(!SharedStore.isCustomEmoji(""))
        #expect(!SharedStore.isCustomEmoji("a"))
        #expect(!SharedStore.isCustomEmoji("1"))
        #expect(!SharedStore.isCustomEmoji("#"))
        #expect(!SharedStore.isCustomEmoji("🙂🙂"))
        #expect(!SharedStore.isCustomEmoji("ab"))
        // Preset tags are not emoji; they route through the switch.
        #expect(!SharedStore.isCustomEmoji("trophy"))
    }
}
