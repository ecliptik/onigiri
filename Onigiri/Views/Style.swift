import SwiftUI
import OnigiriKit

/// App-standard vertical rhythm — compact but still buffered.
enum Layout {
    /// Gap between top-level groups on ScrollView screens (Today, Water,
    /// Calendar).
    static let screenSpacing: CGFloat = 16
}

extension View {
    /// The standard compact gap between form/list sections, matching the
    /// food form. Apply to every Form and sectioned List.
    func compactSections() -> some View {
        listSectionSpacing(10)
    }
}

/// The user's chosen food icon: the classic orange fork.knife SF symbol
/// (default) or one of the emoji options.
struct FoodIconView: View {
    let raw: String

    var body: some View {
        if raw == "sfFork" || raw.isEmpty {
            Image(systemName: "fork.knife").foregroundStyle(.orange)
        } else {
            Text(SharedStore.foodEmoji(for: raw))
        }
    }
}

/// The user's chosen water icon: the blue drop.fill SF symbol (default,
/// matching the watch) or one of the emoji options.
struct WaterIconView: View {
    let raw: String

    var body: some View {
        if raw == "sfDrop" || raw.isEmpty {
            Image(systemName: "drop.fill").foregroundStyle(.blue)
        } else {
            Text(SharedStore.waterEmoji(for: raw))
        }
    }
}

extension Font {
    /// Section headers on scroll screens (Today's "Log", Water's day list) —
    /// proportional to the large controls that sit beside them. Cards keep
    /// .headline for their titles; Forms keep the system defaults.
    static let sectionHeader = Font.title3.weight(.semibold)
}
