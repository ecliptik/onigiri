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

    /// Caps scrollable content at a readable width and centers it —
    /// iPhone layouts are untouched (margin math yields 0), iPad stops
    /// stretching rows edge to edge across 1024pt. Apply to ScrollViews
    /// and Lists/Forms alike (contentMargins reaches both).
    func readableContentWidth(max maxWidth: CGFloat = 700) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth))
    }
}

private struct ReadableContentWidth: ViewModifier {
    let maxWidth: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        // iPhone bypasses ENTIRELY: no width can need the margin, and
        // both the GeometryReader wrapper (which desynced the nav-bar
        // search drawer and large-title collapse) and an explicit 0pt
        // margin (which squared every List/Form by overriding the
        // system's inset-grouped defaults) caused real bugs here.
        if UIDevice.current.userInterfaceIdiom == .pad {
            GeometryReader { geo in
                content
                    .contentMargins(
                        .horizontal,
                        max(0, (geo.size.width - maxWidth) / 2),
                        for: .scrollContent
                    )
            }
        } else {
            content
        }
    }
}

// FoodIconView / WaterIconView moved to OnigiriKit so the watch renders
// the same personalization.

extension Font {
    /// Section headers on scroll screens (Today's "Log", Water's day list) —
    /// proportional to the large controls that sit beside them. Cards keep
    /// .headline for their titles; Forms keep the system defaults.
    static let sectionHeader = Font.title3.weight(.semibold)
}
