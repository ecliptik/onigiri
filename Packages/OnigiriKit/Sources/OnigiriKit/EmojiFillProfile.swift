#if canImport(CoreText)
import CoreText
import CoreGraphics
import Foundation

/// Where to put a waterline so that a given fraction of an emoji's
/// visible AREA ends up below it.
///
/// A rice ball is bottom-heavy — wide base, narrow apex — so filling to
/// 85% of its HEIGHT covers 98% of the rice, and the gauge read as full
/// while the label said 85% (the user, 2026-08-02). Height and area are
/// only interchangeable for a rectangle, and no food emoji is one.
///
/// Measured from the glyph's own alpha channel rather than assumed, so
/// it stays correct for whichever badge emoji is chosen in Settings —
/// including a custom one, whose shape can't be known in advance.
@MainActor
enum EmojiFillProfile {
    /// Row count of the sampled profile. 128 puts the quantisation well
    /// under a pixel at every size the gauge is drawn.
    private static let rows = 128
    /// Cumulative area from the BOTTOM, indexed by row, per emoji.
    private static var cache: [String: [Double]] = [:]

    /// The waterline height (0...1 of the glyph box) that leaves `area`
    /// of the visible glyph below it. Falls back to the identity — plain
    /// height fill — for anything that won't render.
    static func waterline(forArea area: Double, emoji: String) -> Double {
        let target = max(0, min(1, area))
        guard target > 0 else { return 0 }
        guard target < 1 else { return 1 }
        guard let cumulative = profile(for: emoji) else { return target }
        // First height whose area from the bottom reaches the target.
        guard let row = cumulative.firstIndex(where: { $0 >= target }) else { return 1 }
        return Double(row) / Double(cumulative.count - 1)
    }

    private static func profile(for emoji: String) -> [Double]? {
        if let cached = cache[emoji] { return cached }
        guard let measured = measure(emoji) else { return nil }
        cache[emoji] = measured
        return measured
    }

    private static func measure(_ emoji: String) -> [Double]? {
        let side = 128
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, CGFloat(side), nil)
        let text = emoji as NSString
        guard text.length > 0 else { return nil }
        var characters = [UniChar](repeating: 0, count: text.length)
        text.getCharacters(&characters)
        var glyphs = [CGGlyph](repeating: 0, count: text.length)
        // Every emoji outside the BMP is a surrogate PAIR, so the call
        // fills glyphs[0] with the composed glyph and leaves glyphs[1]
        // at 0. Requiring all of them to be non-zero rejected every
        // emoji there is, silently, and the gauge fell back to a linear
        // fill with the tests passing vacuously around it. Take the
        // first glyph and only the first.
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, text.length),
              let first = glyphs.first, first != 0
        else { return nil }
        var glyph = [first]
        let ink = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, nil, 1)
        let width = Int(ink.width.rounded(.up)), height = Int(ink.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        var origin = CGPoint(x: -ink.minX, y: -ink.minY)
        CTFontDrawGlyphs(font, &glyph, &origin, 1, context)
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Memory row 0 is the TOP of the image (verified against the
        // onigiri's own apex, which is empty). Walk UP from the last row
        // so the running total is area-from-the-bottom.
        var cumulative = [Double](repeating: 0, count: rows)
        var totals = [Double](repeating: 0, count: height)
        var total = 0.0
        for y in stride(from: height - 1, through: 0, by: -1) {
            var alpha = 0.0
            for x in 0..<width { alpha += Double(pixels[(y * width + x) * 4 + 3]) }
            total += alpha
            totals[height - 1 - y] = total
        }
        guard total > 0 else { return nil }
        for row in 0..<rows {
            let sample = min(height - 1, Int(Double(row) / Double(rows - 1) * Double(height - 1)))
            cumulative[row] = totals[sample] / total
        }
        return cumulative
    }
}
#endif
