import Foundation
import Testing
@testable import OnigiriKit

/// The gauge's area-vs-height mapping, measured off the real glyph.
@MainActor
struct EmojiFillProfileTests {
    /// The whole point: a rice ball is bottom-heavy, so covering 85% of
    /// it needs a line well below 85% of its height. Getting this
    /// backwards is what made a 85%-full gauge look finished.
    @Test func aBottomHeavyShapeNeedsALowerWaterline() {
        let waterline = EmojiFillProfile.waterline(forArea: 0.85, emoji: "🍙")
        #expect(waterline < 0.85)
        #expect(waterline > 0.4)  // not so low it reads as half-done
    }

    /// Monotonic, and pinned at both ends — an empty gauge must be
    /// empty and a met goal must be a whole rice ball.
    @Test func theMappingRunsFromEmptyToFull() {
        #expect(EmojiFillProfile.waterline(forArea: 0, emoji: "🍙") == 0)
        #expect(EmojiFillProfile.waterline(forArea: 1, emoji: "🍙") == 1)
        var previous = 0.0
        for step in 1...20 {
            let line = EmojiFillProfile.waterline(forArea: Double(step) / 20, emoji: "🍙")
            #expect(line >= previous)
            previous = line
        }
    }

    /// Out-of-range progress can't push the mask past the glyph.
    @Test func progressIsClamped() {
        #expect(EmojiFillProfile.waterline(forArea: -3, emoji: "🍙") == 0)
        #expect(EmojiFillProfile.waterline(forArea: 42, emoji: "🍙") == 1)
    }

    /// Every badge option in Settings measures, rather than falling back
    /// to a linear fill — a custom emoji is the case that can't be
    /// hardcoded, so the measurement has to be what runs.
    @Test func theBadgeChoicesAllMeasure() {
        // Asserting < 0.9, not merely "in range": every one of these
        // tapers toward the top, so a measured profile MUST put the
        // 90%-area line below 90% height. A plain range check passes on
        // the linear fallback, which is exactly how a broken glyph
        // lookup hid here once.
        for emoji in ["🍙", "🍱", "🍚", "⭐️", "🔥"] {
            let line = EmojiFillProfile.waterline(forArea: 0.9, emoji: emoji)
            #expect(line < 0.9, "\(emoji) fell back to a linear fill")
            #expect(line > 0.2, "\(emoji) waterline implausibly low")
        }
    }

    /// Nonsense in, linear out — never a crash, never a stuck gauge.
    @Test func unrenderableInputFallsBackToPlainHeight() {
        #expect(EmojiFillProfile.waterline(forArea: 0.4, emoji: "") == 0.4)
    }
}
