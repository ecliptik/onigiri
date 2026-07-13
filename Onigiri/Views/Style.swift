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
    /// iPhone layouts are untouched (widths never hit the cap), iPad
    /// stops stretching rows edge to edge across 1024pt. A plain frame
    /// cap on purpose: the old GeometryReader desynced the nav-bar
    /// search drawer, and explicit contentMargins squared every
    /// List/Form by overriding the system's inset-grouped defaults.
    /// Pass `groupedBackground: true` for Lists/Forms so iPad's side
    /// gutters match the grouped background instead of flashing white.
    func readableContentWidth(
        max maxWidth: CGFloat = 700, groupedBackground: Bool = false
    ) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth, groupedBackground: groupedBackground))
    }
}

private struct ReadableContentWidth: ViewModifier {
    let maxWidth: CGFloat
    let groupedBackground: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .background {
                if groupedBackground {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                }
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
