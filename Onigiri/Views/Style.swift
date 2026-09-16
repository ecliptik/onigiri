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

extension View {
    /// The app's ONE header shape: a NATIVE large title that shares its
    /// row with the trailing toolbar items (`.inlineLarge`, iOS 17+), so
    /// title and controls read as one header on every screen, and the
    /// search drawer — where there is one — sits directly beneath them.
    /// Today, Foods, Goal and Calendar — the four TAB ROOTS — go through
    /// this; nothing draws its own title (2026-09-16, the user, after
    /// the in-content detour below — `plans/PLAN-log-sheet-layout.md`).
    /// SHEETS do not: the Log sheet wore this header for one day and
    /// left it the same afternoon (the first rule below).
    ///
    /// Why this mode and not the two obvious alternatives, each measured
    /// on the 26.5, 27.0 and 18.6 simulators:
    /// - Plain `.large` floats the trailing items in their own glass
    ///   pill ABOVE the title (the user's original complaint), and iOS
    ///   27 no longer draws a large title above an always-visible search
    ///   drawer at all — it silently collapses to an inline one.
    /// - An IN-CONTENT title row (built 2026-09-16, reverted the same
    ///   day) fixed the pill and broke the rest: the drawer is nav-bar
    ///   chrome, so it rendered ABOVE the row on Foods and the Log
    ///   sheet; a Form's own top inset pushed Goal's row lower than
    ///   Today's; List/Form row insets shifted those titles 16pt right
    ///   of the ScrollView screens'. Four screens, four offset hacks,
    ///   still misaligned. `.inlineLarge` puts the title where the
    ///   system puts it and asks nothing of the container.
    /// - `ToolbarItemPlacement.largeTitle` (iOS 26) is not a third way:
    ///   it REPLACES the title with centered content, is suppressed
    ///   entirely whenever the search drawer is present, and in a sheet
    ///   it dropped Cancel and Done along with the title it replaced.
    ///
    /// Two rules come with the mode. A LEADING toolbar item is pushed
    /// onto a row above the title (or into an overflow menu, in a
    /// sheet) — the two-row header this exists to remove — which is why
    /// the mode is for tab roots ONLY. A sheet's Cancel belongs on the
    /// left, and moving it trailing to fit this mode showed on scroll:
    /// the compact title the scroll collapses to can't center behind
    /// three trailing controls and sat at the left edge, unlike every
    /// other sheet (the Log sheet, 2026-09-16, the user from device).
    /// A sheet keeps the standard inline title, Cancel in
    /// `.cancellationAction`, Done in `.confirmationAction`. And a
    /// List/Form host needs `flushTopContent()` below, or it picks up
    /// ~35pt of extra top inset under this mode that a ScrollView host
    /// does not.
    func inlineLargeTitle(_ title: String) -> some View {
        navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
    }

    /// The List/Form half of `inlineLargeTitle`: zero the scroll
    /// content's top margin, which is where the extra inset that mode
    /// adds to those two containers lives (measured: Foods' scope row
    /// sat ~57pt under the search field with it, ~22pt without — the
    /// same gap a plain `.large` title leaves). Not for ScrollView hosts
    /// (Today, Calendar); they never had the gap. Not exclusive to
    /// `.inlineLarge` either: the Log sheet's List — a plain `.inline`
    /// title in a sheet, search drawer beneath — showed the same inset
    /// with this removed (scope row ~63pt under the field against
    /// Foods' ~27pt, 26.5 sim, 2026-09-16), so it keeps the modifier.
    /// iOS 26+ only, which is where it was measured — the 18.6 sim
    /// showed no gap to remove.
    /// The QA walkthrough's Goal stop used to scroll back to the top by
    /// a fixed swipe COUNT, which this margin change threw off; it
    /// scrolls until the field is hittable now, so don't read an old
    /// note about "contentMargins broke the walkthrough" as a reason to
    /// drop this.
    @ViewBuilder
    func flushTopContent() -> some View {
        if #available(iOS 26.0, *) {
            self.contentMargins(.top, 0, for: .scrollContent)
        } else {
            self
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

    /// The Log sheet's PINNED door bar (`LogSheetDoorBar`): below the
    /// list, above the home indicator, riding up with the keyboard.
    /// `safeAreaBar` on iOS 26+ (the system's scroll-edge treatment,
    /// and it insets the list so the last rows scroll clear); a
    /// `.bar`-material `safeAreaInset` below the floor. `isHidden`
    /// EMPTIES the bar rather than dropping the modifier — an `if`
    /// around the whole call changes the List's modifier chain and
    /// re-creates it mid-search.
    ///
    /// Pinned, not a trailing List row, and this was decided TWICE
    /// (2026-09-16, the user). Pinned first; then, because a short
    /// Favorites list left empty canvas between its last row and the
    /// bar, moved into the list as its last row — where on a real
    /// library it was never on screen at all until the list had been
    /// scrolled to its end ("hiding it completely"). With both versions
    /// in hand the user chose pinned: the canvas under a short list is
    /// what every iOS bottom bar looks like over a short screen. Don't
    /// move it back into the list.
    @ViewBuilder
    func entryDoorBar<Bar: View>(
        isHidden: Bool, @ViewBuilder bar: @escaping () -> Bar
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .bottom) {
                if !isHidden { bar() }
            }
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                if !isHidden {
                    bar()
                        .padding(.top, 6)
                        .background(.bar)
                }
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

    /// The counterpart to `sheetCardChrome()`: recedes the HOST's own
    /// content while a child sheet rides its single `activeSheet` slot,
    /// so the card in front reads as obviously the active surface. Needed
    /// specifically where the host is ITSELF a sheet on `riceCanvas` (the
    /// Log sheet, the food form) — there the system's default dimming
    /// barely registers against that near-black dark-mode surface, so a
    /// frosted card on top of it read as one continuous surface with only
    /// the grabber between them (the user, 2026-09-13 screenshot). A plain
    /// dim — the system's own idiom (the 2026-09-16 A/B against three
    /// materials, below) — drawn as an overlay, so on a NavigationStack
    /// host it covers the bar too; `recedesWithSheet()` on each toolbar
    /// control is still the other half, since a dimmed Cancel/Done is
    /// otherwise a live trap for a stray tap. Reduce Transparency gets a
    /// stronger dim rather than nothing — the host is still visibly not
    /// the active surface either way.
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
        // An OVERLAY — never a modifier on `content`, and never an `if`
        // AROUND `content`. Two lessons, a day apart:
        // - 2026-09-15: `.blur(radius: isPresenting ? 12 : 0)` keeps a
        //   filter on the host's whole rendered output at radius 0,
        //   which the Liquid Glass tab bar samples every frame of a
        //   selection slide; on a DEVICE (never a simulator) a
        //   Calendar→Today jump parked the highlight on Foods ~200 ms
        //   (plans/PLAN-tab-bar-jank.md). So nothing may touch the
        //   content while idle.
        // - 2026-09-16: the fix for that — `Group { if isPresenting {
        //   content.blur(radius: 12) } else { content } }` — swapped
        //   between two view TYPES, which changes the content's
        //   structural identity. Every present and every dismiss tore
        //   the whole host subtree down and rebuilt it on the main
        //   thread in the dismissal's own transaction: Today's entire
        //   NavigationStack under a closing Log sheet (its `.sheet`
        //   slot, `.task`, scroll offset and all), the Foods List under
        //   a closing food form. Cancel/Done "didn't register, then
        //   did" on the phone, and the un-blur was a hard cut ~360 ms
        //   after an interactively dismissed child had already left
        //   (plans/PLAN-sheet-dismiss-latency.md;
        //   testSheetRoundTripKeepsFoodsScroll bites on the branch).
        // The `if` lives INSIDE the overlay, where insertion and
        // removal cost one rectangle. A plain dim, not a material: the
        // same day's on-device A/B put regular, thin and ultra-thin
        // materials beside this scrim and the user could not tell the
        // three apart — "go with whatever is most like other Apple
        // apps", which dim the view behind a sheet and never frost it.
        content
            .overlay {
                if isPresenting {
                    Color.black.opacity(reduceTransparency ? 0.55 : 0.32)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
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
