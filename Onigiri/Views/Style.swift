import SwiftUI
import UIKit
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

/// A large title and its trailing controls sharing ONE row, in-content
/// rather than native nav-bar chrome (2026-09-16, the user, from-device
/// screenshots of Today/Foods/Goal/Calendar/the Log sheet: a native
/// large title's trailing toolbar buttons float as their own Liquid
/// Glass pill ABOVE the title with a visible gap — correct iOS 26
/// behavior, not a bug, but the user wants every screen's title and
/// controls to read as one header instead). A NATIVE large title also
/// grows taller on pull-down overscroll, independently of anything a
/// pinned `safeAreaInset` tracks — the Log sheet's scope-bar jank
/// (`plans/PLAN-log-sheet-layout.md`) was that growth outrunning a
/// fixed-position sibling; a title that is plain content instead never
/// grows, so nothing downstream of it can desync from it either.
/// `titleContent` sits leading (usually `Text(title).font(.largeTitle
/// .bold())`) at a 16pt horizontal / 4pt top inset — measured against
/// an unmodified native large title so switching tabs doesn't jump the
/// header — baked into this row rather than repeated per call site;
/// `controls` trails, wrapped by the caller in `headerControlChrome()`
/// so several icons read as one shared pill, matching what a real
/// `ToolbarItemGroup` gave them for free as nav-bar chrome.
///
/// `addsHorizontalPadding` defaults to `true` for hosts with no
/// competing inset of their own (Today/Foods/Goal/the Log sheet all
/// zero out any container padding around this row specifically so its
/// own 16pt is the only one). Pass `false` where the host ALREADY
/// wraps every sibling in the same padding (Calendar's outer VStack) —
/// stacking both would indent this row twice as far as everything
/// beside it.
struct LargeTitleHeaderRow<TitleContent: View, Controls: View>: View {
    // `addsHorizontalPadding` sits BEFORE the two @ViewBuilder closures
    // in the synthesized memberwise init on purpose — Swift's multiple
    // trailing-closure sugar (`LargeTitleHeaderRow { … } controls: { … }`)
    // requires the closures to be the LAST parameters; moving this one
    // after them would silently break every call site that uses it.
    var addsHorizontalPadding: Bool = true
    @ViewBuilder var titleContent: () -> TitleContent
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            titleContent()
            Spacer(minLength: 8)
            controls()
        }
        .padding(.horizontal, addsHorizontalPadding ? 16 : 0)
        .padding(.top, 4)
    }
}

extension View {
    /// The shared chrome for a `LargeTitleHeaderRow`'s trailing
    /// controls: Liquid Glass on iOS 26+ (one capsule for the whole
    /// group, interactive); a `.bar`-material capsule below the floor
    /// (the same fallback shape `ScopeBar`'s own pinned inset uses
    /// elsewhere). One shared definition so the four/five screens using
    /// this pattern can't visually drift from each other.
    @ViewBuilder
    func headerControlChrome() -> some View {
        if #available(iOS 26.0, *) {
            self
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar, in: .capsule)
        }
    }

    /// A single header control in its OWN circle, rather than fused
    /// into one shared pill with its neighbors — matching Apple Music's
    /// own Search tab, where the trailing control is one clean isolated
    /// circle rather than a merged group (the user, 2026-09-16, holding
    /// up Music's Search tab as the reference: "Food[s] header and
    /// search should look like how Music search does"). Foods' Filter
    /// and Sort are two logically separate actions, so each gets this
    /// individually instead of sharing `headerControlChrome()`'s one
    /// capsule; wrap the icon in a fixed-size frame BEFORE calling this
    /// so the circle doesn't hug the glyph unevenly.
    @ViewBuilder
    func headerCircleChrome() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self
                .padding(8)
                .background(.bar, in: .circle)
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
    /// The app's ONE search-field placement: the standard system field,
    /// pinned in the top drawer regardless of platform version — the
    /// Foods tab's placement (`plans/PLAN-log-sheet-layout.md`,
    /// 2026-09-15), now shared so a fifth field can't quietly drift onto
    /// the bottom-aligned default. `.always`, not the plain drawer: with
    /// a pinned top `safeAreaInset` below it (a scope bar), the
    /// hide-on-scroll drawer re-expands BLANK after a scroll — element
    /// present, field invisible (screenshot-verified 2026-07-13,
    /// FoodsView). Pinning skips that collapse/re-expand cycle.
    /// `isPresented` is optional — only a host that reads whether search
    /// is active (the Log sheet hides its own toolbar while searching)
    /// needs to pass one.
    @ViewBuilder
    func librarySearch(
        text: Binding<String>, prompt: LocalizedStringKey,
        isPresented: Binding<Bool>? = nil
    ) -> some View {
        if let isPresented {
            searchable(
                text: text, isPresented: isPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: prompt
            )
        } else {
            searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: prompt
            )
        }
    }

    // `entryDoorBar` (a `safeAreaBar`-pinned container for
    // `LogSheetDoorBar`) lived here from 2026-09-15 to -16. Retired: the
    // user found it left a large empty gap above the door bar whenever
    // the list was short (Favorites is often just two or three rows) —
    // a `safeAreaBar`/`safeAreaInset` pins to the SCREEN's edge
    // regardless of how much content precedes it. `LogSheetDoorBar` is
    // a plain trailing List row in QuickLogSheet now, so it sits right
    // after whatever content is actually there. Cost: on a long list it
    // no longer stays reachable without scrolling to the bottom, which
    // the user accepted explicitly in exchange for closing the gap.
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

    /// The counterpart to `sheetCardChrome()`: recedes the HOST's own
    /// content while a child sheet rides its single `activeSheet` slot,
    /// so the card in front reads as obviously the active surface. Needed
    /// specifically where the host is ITSELF a sheet on `riceCanvas` (the
    /// Log sheet, the food form) — there the system's default dimming
    /// barely registers against that near-black dark-mode surface, so a
    /// frosted card on top of it read as one continuous surface with only
    /// the grabber between them (the user, 2026-09-13 screenshot). Blurs
    /// content only, never the native nav bar/toolbar (SwiftUI's `.blur`
    /// can't reach that chrome) — `recedesWithSheet()` on each toolbar
    /// control is the other half, since Cancel/Done/the title otherwise
    /// stayed crisp and read as still usable (the user, same round).
    /// Respects Reduce Transparency by swapping blur for a stronger flat
    /// scrim rather than turning the effect off outright — the host is
    /// still visibly not the active surface either way.
    @ViewBuilder
    func recedesBehindSheet(_ isPresenting: Bool) -> some View {
        modifier(RecedesBehindSheet(isPresenting: isPresenting))
    }

    /// The nav-bar half of `recedesBehindSheet()`: a toolbar button or
    /// title lives in UIKit's own bar chrome, which `.blur` never
    /// reaches, so it read as crisp and tappable while a child sheet
    /// actually made it unreachable. Dims AND disables — the dimming
    /// alone would still be a live trap for a stray tap during the
    /// transition.
    func recedesWithSheet(_ isPresenting: Bool) -> some View {
        opacity(isPresenting ? 0.35 : 1)
            .disabled(isPresenting)
            .animation(.easeOut(duration: 0.2), value: isPresenting)
    }
}

private struct RecedesBehindSheet: ViewModifier {
    let isPresenting: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        // NO blur filter while idle — the branch, not `.blur(radius:
        // isPresenting ? 12 : 0)`. A zero-radius blur still hangs a
        // filter on the host's whole rendered output, and the Liquid
        // Glass tab bar samples that output every frame of a selection
        // slide. On a DEVICE (never on a simulator) that made a
        // Calendar→Today jump park the glass highlight on Foods for
        // ~200 ms — Today and Foods being the two tab roots that carry
        // this modifier, Goal and Calendar neither carrying it nor
        // sticking. Bisected on the phone one variable at a time after
        // five app-side gating fixes changed nothing (2026-09-15,
        // plans/PLAN-tab-bar-jank.md, the user: "much better now").
        // Cost: the blur-in no longer animates from 0 — it appears as
        // the sheet starts rising, which reads fine; the dim still
        // fades. Don't put the radius-0 form back for the animation.
        Group {
            if isPresenting && !reduceTransparency {
                content.blur(radius: 12)
            } else {
                content
            }
        }
        .overlay {
            if isPresenting {
                Color.black.opacity(reduceTransparency ? 0.55 : 0.32)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresenting)
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

/// Disables the NavigationStack's system edge-swipe-to-pop gesture on the
/// screen it's attached to.
///
/// Applied to TodayView as an attempted fix for a whole-screen horizontal
/// shift while swiping a log row (the user, 2026-08-30) — the theory being
/// that the row's own gesture delegate saying yes to simultaneous
/// recognition with the enclosing ScrollView's pan (needed so a vertical
/// scroll starting on a row still works) was ALSO letting the system's
/// edge-pop recognizer, always present on a NavigationStack, ride along.
/// **Confirmed NOT the cause** (2026-08-31): on-device diagnostic logging
/// showed this recognizer genuinely disabled (`isEnabled=false`) while the
/// bug still reproduced, and separately the user confirmed the swipe that
/// triggers it starts anywhere on a row — including the trailing edge and
/// middle — never the screen's leading edge this recognizer is scoped to.
/// The real cause turned out to be nothing in this file, or in any of the
/// gesture code this investigation spent most of its time on: it was a
/// silently corrupted SwiftData `Food` LIBRARY record, fixed by editing
/// and re-saving that one food (see `refreshAfterSwipeSettles` in
/// TodayView.swift for the full trail). Kept anyway because it's an
/// independently safe, justified change on its own terms — a prior
/// session already found this exact edge zone stealing taps from a
/// button that used to sit there (see the toolbar comment above the day
/// chevrons in TodayView.swift). Today is a TAB ROOT with nothing
/// meaningful to pop back to by edge-swipe (its one push destination, Day
/// Nutrition detail, still pops via its own back button).
struct DisablesInteractivePop: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        DispatchQueue.main.async {
            controller.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

extension View {
    /// See `DisablesInteractivePop`.
    func disablesInteractivePop() -> some View {
        background(DisablesInteractivePop())
    }
}
