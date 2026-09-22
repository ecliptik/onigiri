import SwiftUI

/// The user's chosen food icon: the classic orange fork.knife SF symbol
/// (default) or one of the emoji options. Lives in the kit so the watch
/// renders the same personalization the phone does.
public struct FoodIconView: View {
    let raw: String
    /// Overrides the SF fork's orange — the watch's cream meal button
    /// needs dark content (orange-on-warm was unreadable). Emoji icons
    /// keep their own colors.
    let tint: Color?

    public init(raw: String, tint: Color? = nil) {
        self.raw = raw
        self.tint = tint
    }

    public var body: some View {
        if raw == "sfFork" || raw.isEmpty {
            Image(systemName: "fork.knife").foregroundStyle(tint ?? .orange)
        } else {
            Text(SharedStore.foodEmoji(for: raw))
        }
    }
}

/// The user's chosen water icon: the blue drop.fill SF symbol (default)
/// or one of the emoji options.
public struct WaterIconView: View {
    let raw: String
    /// Overrides the SF drop's blue — the watch's blue water button
    /// wants a solid white drop, matching the meal button's dark fork.
    /// Emoji icons keep their own colors.
    let tint: Color?

    public init(raw: String, tint: Color? = nil) {
        self.raw = raw
        self.tint = tint
    }

    public var body: some View {
        if raw == "sfDrop" || raw.isEmpty {
            Image(systemName: "drop.fill").foregroundStyle(tint ?? .blue)
        } else {
            Text(SharedStore.waterEmoji(for: raw))
        }
    }
}
