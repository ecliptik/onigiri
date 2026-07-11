import SwiftUI

/// The user's chosen food icon: the classic orange fork.knife SF symbol
/// (default) or one of the emoji options. Lives in the kit so the watch
/// renders the same personalization the phone does.
public struct FoodIconView: View {
    let raw: String

    public init(raw: String) {
        self.raw = raw
    }

    public var body: some View {
        if raw == "sfFork" || raw.isEmpty {
            Image(systemName: "fork.knife").foregroundStyle(.orange)
        } else {
            Text(SharedStore.foodEmoji(for: raw))
        }
    }
}

/// The user's chosen water icon: the blue drop.fill SF symbol (default)
/// or one of the emoji options.
public struct WaterIconView: View {
    let raw: String

    public init(raw: String) {
        self.raw = raw
    }

    public var body: some View {
        if raw == "sfDrop" || raw.isEmpty {
            Image(systemName: "drop.fill").foregroundStyle(.blue)
        } else {
            Text(SharedStore.waterEmoji(for: raw))
        }
    }
}
