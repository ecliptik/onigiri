import SwiftUI

/// The reward badge fills bottom-up as today's banked deficit approaches
/// the daily goal.
public struct OnigiriGauge: View {
    /// 0...1 fraction of the daily deficit goal achieved.
    public let progress: Double
    /// The badge emoji; defaults to the stored choice so widgets and
    /// complications follow the setting without threading it through.
    public let emoji: String

    public init(progress: Double, emoji: String = SharedStore.rewardEmoji) {
        self.progress = progress
        self.emoji = emoji
    }

    /// The emoji's size as a fraction of the frame's short side.
    private static let emojiScale = 0.85
    /// Apple Color Emoji, measured with CoreText (identical for every
    /// glyph — they all fill the em square): the LINE box is 1.3125× the
    /// font size, and the ink sits from 14.2857% to 90.4762% of that
    /// line, measured from its bottom. So the drawn onigiri is inset
    /// from the frame on both edges, and a mask measured against the
    /// FRAME misses at both ends of the scale: it covered nothing at all
    /// below ~12% progress, and at 85% left only a sliver of the narrow
    /// apex showing, which reads as a full rice ball (the user,
    /// 2026-08-02). The fill has to span the INK, not the frame.
    private static let lineHeightRatio = 1.3125
    private static let inkBottomInLine = 0.142857
    private static let inkHeightInLine = 0.761905

    /// Where the fill line goes so that `progress` of the rice ball is
    /// actually COVERED. Not `progress` itself: the shape is
    /// bottom-heavy, so a line at 85% of its height buries 98% of it,
    /// and the gauge read full while the label said 85% (the user,
    /// 2026-08-02). `EmojiFillProfile` measures the real shape, so this
    /// stays honest for whichever badge emoji is chosen.
    private var waterline: Double {
        #if canImport(CoreText)
        EmojiFillProfile.waterline(forArea: progress, emoji: emoji)
        #else
        max(0, min(1, progress))
        #endif
    }

    public var body: some View {
        GeometryReader { geo in
            let fontSize = min(geo.size.width, geo.size.height) * Self.emojiScale
            let emoji = Text(emoji).font(.system(size: fontSize))
            // Text lays out its line box centred in the frame; the ink
            // is a known band inside that.
            let lineHeight = fontSize * Self.lineHeightRatio
            let lineBottom = (geo.size.height - lineHeight) / 2
            let inkBottom = lineBottom + Self.inkBottomInLine * lineHeight
            let inkHeight = Self.inkHeightInLine * lineHeight
            ZStack {
                emoji
                    .grayscale(1)
                    .opacity(0.22)
                emoji
                    .mask(alignment: .bottom) {
                        Rectangle()
                            .frame(height: inkBottom + inkHeight * waterline)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityLabel("Daily goal progress")
        .accessibilityValue("\(Int((max(0, min(1, progress))) * 100)) percent")
    }
}

#Preview {
    VStack(spacing: 20) {
        OnigiriGauge(progress: 0.15).frame(width: 90, height: 90)
        OnigiriGauge(progress: 0.6).frame(width: 90, height: 90)
        OnigiriGauge(progress: 1.0).frame(width: 90, height: 90)
    }
}
