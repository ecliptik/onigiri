import SwiftUI
import OnigiriKit

/// The library-list sort, shared by the Foods screen and the meal
/// builder (both persist a pick via @AppStorage; defaults differ —
/// Foods leads with the favorites blend, the builder with Recent).
/// Raw values are stored preferences: never rename them.
enum LibrarySort: String, CaseIterable {
    case ranked, recent, name

    var label: String {
        switch self {
        case .ranked: "Favorites"
        case .recent: "Recent"
        case .name: "Name"
        }
    }
}

/// The shared "Details ›" tap-for-more caption — one grammar for the
/// three affordances that open more detail: the Calendar month card,
/// the Calendar day card, and Today's headline. (The 2026-07-13 chevron
/// removal on Today was reversed deliberately in 2.1 to unify them.)
/// The trailing chevron says "there's more behind this tap"; where the
/// tap ALSO crosses tabs or enables editing, that cue lives in the
/// host's accessibility hint, not extra visible words.
struct DetailsCaption: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Details")
            // Decorative "there's more" cue — hidden from VoiceOver so
            // the affordance reads simply as "Details" (and the flow
            // test can still match it by that label).
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

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
            // Lists/Forms must drop their own system gray or the warm
            // canvas never shows; a no-op for ScrollView screens.
            .scrollContentBackground(groupedBackground ? .hidden : .automatic)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .background {
                if groupedBackground {
                    // The brand canvas, not systemGroupedBackground —
                    // see Color.riceCanvas (identical in dark mode).
                    Color.riceCanvas.ignoresSafeArea()
                }
            }
    }
}

// FoodIconView / WaterIconView moved to OnigiriKit so the watch renders
// the same personalization.

/// The Foods / Meals / Favorites scope picker pinned above library lists —
/// ONE implementation for the Foods tab and the Log sheet (the
/// OnlineResultsSection lesson: shared surfaces drift apart when each
/// screen grows its own copy). Segmented normally; a menu at
/// accessibility sizes, because segmented controls ignore Dynamic Type.
struct ScopeBar<Tag: Hashable>: View {
    let options: [(label: String, tag: Tag)]
    @Binding var selection: Tag

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var picker: some View {
        Picker("Show", selection: $selection) {
            ForEach(options, id: \.tag) { option in
                Text(option.label).tag(option.tag)
            }
        }
    }
}

extension View {
    /// Pins a ScopeBar above a library list, styled like the Log
    /// sheet's: horizontal padding, bar material, stays put while the
    /// results scroll (Music-style). SHEETS ONLY — a top safeAreaInset
    /// suppresses large-title rendering, so the Foods TAB renders its
    /// ScopeBar as a list row instead.
    func scopeBar<Tag: Hashable>(
        options: [(label: String, tag: Tag)], selection: Binding<Tag>
    ) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            ScopeBar(options: options, selection: selection)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }
}

extension View {
    /// The warm paper canvas for grouped sheets and forms that don't
    /// go through readableContentWidth (Log sheet, Settings, the food
    /// and meal forms) — one surface color everywhere, with the
    /// onigiri warmth in light mode. See Color.riceCanvas.
    func riceCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.riceCanvas.ignoresSafeArea())
    }
}

extension View {
    /// iOS 26's hard scroll-edge under pinned chrome (the always-on
    /// search field, the Log sheet's scope bar) — content clips
    /// crisply instead of ghosting through. A no-op on iOS 18.
    @ViewBuilder
    func hardTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}

extension Font {
    /// Section headers on scroll screens (Today's "Log", Water's day list) —
    /// proportional to the large controls that sit beside them. Cards keep
    /// .headline for their titles; Forms keep the system defaults.
    static let sectionHeader = Font.title3.weight(.semibold)
}
