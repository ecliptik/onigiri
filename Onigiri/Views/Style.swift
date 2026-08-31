import SwiftUI
import OnigiriKit

/// The library-list sort, shared by the Foods screen, the Log sheet,
/// and the meal builder (each persists a pick via @AppStorage).
/// Raw values are stored preferences: never rename them.
/// The "Favorites" sort (rawValue "ranked") was REMOVED 2026-07-19 —
/// the Favorites SCOPE owns the starred shortlist, and two adjacent
/// "Favorites" concepts read as one (the user). A stored "ranked"
/// falls back to .recent through the usual `?? .recent` at read sites.
enum LibrarySort: String, CaseIterable {
    // Declaration order IS the menu order: Recent, Name.
    case recent, name

    var label: String {
        switch self {
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
    /// `isHidden` empties the inset — a search crosses every scope, so
    /// a highlighted segment would contradict the list below it.
    func scopeBar<Tag: Hashable>(
        options: [(label: String, tag: Tag)], selection: Binding<Tag>,
        isHidden: Bool = false
    ) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            // Hidden = an EMPTY inset, NOT a dropped modifier: wrapping
            // the whole `.scopeBar(…)` call in an `if` changes the
            // modifier chain's identity, which re-creates the List
            // underneath it and loses its state mid-search.
            if !isHidden {
                ScopeBar(options: options, selection: selection)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
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

    /// The frosted card chrome for half-height sheets presented OVER
    /// other sheets (Edit Water, the meal "Contains" card): material +
    /// hairline rim so the card reads as physically separate in both
    /// modes. ONE implementation — Today and Foods each carried a
    /// byte-identical copy of this ZStack (audit, 2026-08-17).
    ///
    /// Deliberately material on iOS 26 too, not `glassEffect`: glass is
    /// for chrome floating over content, and a sheet's background IS a
    /// content surface — the system's own sheets stay material. The
    /// 2026-08-17 audit proposed the port; declined on that ground.
    func sheetCardChrome() -> some View {
        presentationCornerRadius(28)
            .presentationBackground {
                ZStack {
                    Rectangle().fill(.thickMaterial)
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                }
            }
    }
}

extension View {
    /// The fix: `sheetCardChrome()`'s custom `.presentationBackground`
    /// removes the sheet's own navigation-bar material, and THAT — not the
    /// button code — is what silently opts a sheet out of the automatic
    /// Liquid Glass capsule every plain toolbar `Button` gets elsewhere
    /// (verified 2026-08-30: forcing `.buttonStyle(.glass)` on Cancel
    /// instead squashed it into a clipped 44pt circle — `.glass`'s own
    /// compact-icon fallback for a leading slot with no bar to measure
    /// against, a DIFFERENT broken look, not a fix). Restoring the bar's
    /// own visible material is what lets plain buttons resolve their
    /// automatic styling again, same as every sheet that never opted out.
    @ViewBuilder
    func restoreToolbarGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

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
