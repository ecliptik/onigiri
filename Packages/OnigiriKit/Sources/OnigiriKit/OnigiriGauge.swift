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

    public var body: some View {
        GeometryReader { geo in
            let emoji = Text(emoji)
                .font(.system(size: min(geo.size.width, geo.size.height) * 0.85))
            ZStack {
                emoji
                    .grayscale(1)
                    .opacity(0.22)
                emoji
                    .mask(alignment: .bottom) {
                        Rectangle()
                            .frame(height: geo.size.height * max(0, min(1, progress)))
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
