# PLAN — Log sheet: search on top, the doors floating at the bottom (2026-09-15)

> **DECIDED, not yet built** (2026-09-15, the user, via AskUserQuestion):
> floating glass door bar (Option A) · camera tinted, describe plain ·
> all five search fields move to the top drawer · the Add Food form keeps
> its in-form doors section, sharing controls with the bar rather than
> also floating. The alternatives considered are kept below each decision
> for the record, then struck from the build order.
> Deployment floor iOS 18.6; the phone runs iOS 27.0; sims 26.5 and 27.0.

## The ask

1. The Log sheet's Foods/Meals search should be a traditional field at the
   top of the sheet, like the Foods tab's — not the floating pill iOS 26 puts
   at the bottom of a sheet.
2. The camera and the "Describe food or meal" field move to the bottom as a
   floating control of their own, so they read as distinct from search.
3. Search should look the same on every screen that has one; the two entry
   doors should pop; and the Log sheet's order should be reviewed against
   the current HIG.

## What the HIG says (checked 2026-09-15)

Sources: HIG *Search fields*, *Toolbars*, *Sheets*, *Materials* (read via
the sosumi.ai mirror — developer.apple.com renders client-side and returned
only titles); Xcode 27's bundled `SwiftUI-New-Toolbar-Features.md`; Axiom
27.0.0-beta.22 (`axiom-swiftui/toolbars.md`, `26-ref.md`, `search-ref.md`).

- **Search placement, iPhone** (*Search fields*): "Place search at the
  bottom if there's room" because it "keeps the search experience easy to
  reach" — but "**Place search at the top when it's important to defer to
  content at the bottom of the screen, or there's no bottom toolbar.**" An
  inline field goes "above the list it searches, and consider pinning it to
  the top toolbar when scrolling."
  → The ask is HIG-conformant under the second clause: the bottom of the
  Log sheet is being given to the entry doors, so search goes to the top,
  pinned. That is exactly what `.navigationBarDrawer(displayMode: .always)`
  renders, and exactly what Foods already does.
- **Layers** (*Materials*): "Liquid Glass forms a distinct functional layer
  for controls and navigation elements … that floats above the content
  layer." "**Don't use Liquid Glass in the content layer.**" Custom glass
  controls: sparingly.
  → Today the doors are List rows — content layer — and are correctly NOT
  glass. Moving them into a floating bar puts them in the functional layer,
  which is what earns them glass. That is the whole design argument for
  "make them pop": position and material, not a bigger chip.
- **Tint** (*Toolbars*, Liquid Glass guidance): "Reduce the use of toolbar
  backgrounds and tinted controls"; tint one primary action, never
  everything. `.confirmationAction` already renders Done as prominent glass.
- **Sheets**: Cancel leading, Done trailing (already so). Nothing in the
  sheet guidance forbids a bottom bar inside a sheet; Mail's and Files'
  own sheets carry them.
- **iOS 27**: I found NO iOS 27 change to search-placement guidance. The 27
  additions that touch this screen are toolbar-overflow controls:
  `.visibilityPriority(_:)`, `.topBarPinnedTrailing`, `ToolbarOverflowMenu`
  (all iOS 27-gated), and a second semantic tab role, `Tab(role:
  .prominent)`, whose rendering Axiom itself says to confirm against the SDK
  before relying on. The iOS 26 rules stand on 27.

## Where things are today (facts, not opinions)

- `QuickLogSheet` is a full-height sheet from Today with its own
  `NavigationStack`. Its `.searchable` has NO placement argument, so iOS 26
  gives it the bottom-aligned pill. `FoodsView` passes
  `.navigationBarDrawer(displayMode: .always)` — the top drawer. **That one
  argument is the entire visible difference between the two fields.**
- Five search fields exist: Foods (top), Log sheet (bottom), the meal
  builder's food picker (`MealFormView`, default → bottom in its sheet),
  `MenuPicker` (default → bottom) and `NutrientPicker` (default).
- The "we've gone over this" history: 2026-07-13 tried moving FOODS' search
  to the bottom with `DefaultToolbarItem(kind: .search, placement:
  .bottomBar)` and it rendered behind the tab bar, because the search-tab
  slot belongs to the Add pill. That constraint is about the TAB screen and
  the bottom. Nothing constrains a SHEET's field going to the TOP — a sheet
  has no tab bar and owns its own stack. The 2026-07 "as close to Apple's as
  possible" decision was about using the system field, not about where it
  sits; both placements are the system field.
- The doors (`EntryDoorsSection`) are the first List section on the Log
  sheet, hidden while searching; the same section leads a blank
  `FoodFormView`. The describe field's results (`AIEstimateSection`,
  `OnlineResultsSection`) render directly under the doors, then Water, then
  Recent / Everything else. The scope bar is a top `safeAreaInset`.
- The Log sheet's `.sheet(item: $activeSheet)` is attached on the List
  chain INSIDE the stack. Foods moved its to the `NavigationStack` for a
  reason that only bites with the top drawer: presenting a sheet over the
  drawer's view leaves the drawer's search controller unable to take focus
  after dismissal — taps land, the keyboard never rises (pinned by
  `testFoodsSearchAfterSave`). Part 1 inherits that landmine.

---

## Part 1 — Search at the top, everywhere (the Foods twin)

One shared modifier in `Style.swift`, so the five fields cannot drift:

```swift
/// The app's ONE search-field placement: the standard system field,
/// pinned in the top drawer on every platform version. Sheets get it
/// under their Cancel/Done bar; the Foods tab under its large title.
func librarySearch(text: Binding<String>, prompt: LocalizedStringKey,
                   isPresented: Binding<Bool>? = nil) -> some View
```

wrapping `.searchable(text:isPresented:placement:
.navigationBarDrawer(displayMode: .always), prompt:)`.

- **Decided: all five.** Adopt on the Log sheet (the ask), Foods (no visible
  change), the meal builder's food picker, `MenuPicker`, and `NutrientPicker`
  — one shared modifier, no field left to drift onto the default placement
  later.
- **`.always`, not the default drawer**: with a pinned top `safeAreaInset`
  (the scope bar) below the drawer, the hide-on-scroll drawer re-expands
  BLANK after a scroll — element present, field invisible (screenshot-
  verified 2026-07-13, recorded in FoodsView). Pinning skips the collapse
  cycle. The Log sheet has that same inset.
- **Move `.sheet(item:)` and `.fileImporter` to the Log sheet's
  `NavigationStack`**, matching Foods, for the drawer-focus bug above.
  `.recedesBehindSheet` stays on the List (it blurs content, never chrome).
- `searchPresented` keeps its job: an active drawer search hides the nav
  bar (Cancel/Done) exactly as the bottom pill did, so the "deactivate on
  sub-sheet" rule stands. If Cancel/Done should stay visible mid-search,
  `.searchPresentationToolbarBehavior(.avoidHidingContent)` (iOS 17.1+) does
  that — the user's call; Foods doesn't use it.
- iOS 18: the drawer already IS the placement there. No floor risk.
- iOS 27 nicety, gated: `.visibilityPriority(.low)` on the Sort menu so a
  narrow bar (large Dynamic Type) overflows Sort before anything else. Done
  needs nothing — `.confirmationAction` already resists overflow.

Resulting sheet header, top to bottom: nav bar (Cancel · Log · Sort · Done)
→ pinned search drawer → scope bar → list. Foods reads: large title →
drawer → scope row → list. Same field, same place relative to the list.

---

## Part 2 — The doors float at the bottom

**Decided: the floating door bar** (`safeAreaBar`, glass on 26+). The two
alternatives considered — a bottom toolbar pair that expands into a sheet,
and shipping Part 1 alone without moving the doors — are kept below for the
record, then dropped from the build order.

### Chosen — Floating door bar (`safeAreaBar`, glass on 26+)

```
┌──────────────────────────────────────┐
│ Cancel           Log          ⇅ Done │  nav bar (unchanged)
│ ┌──────────────────────────────────┐ │
│ │ 🔍 Foods and Meals               │ │  pinned system drawer (Part 1)
│ └──────────────────────────────────┘ │
│ ┌ Favorites ┬  Foods  ┬  Meals ┐     │  scope bar (unchanged)
│                                      │
│  💧 Water               12 oz   (+)  │  the list, as today minus the doors
│  Recent                              │
│  Burrito bowl          650 kcal (+)  │
│  Greek yogurt          120 kcal (+)  │
│  …                                   │
│                                      │
│   ╭────╮ ╭──────────────────────╮    │
│   │ 📷 │ │ ✨ Describe food or… │    │  floating door bar — glass, above
│   ╰────╯ ╰──────────────────────╯    │  the home indicator, list scrolls under
└──────────────────────────────────────┘
```

While describing (field focused, text present):

```
│  ✨ Estimate "pork and beans"      ›  │  AIEstimateSection (tap-to-run)
│  Search OpenFoodFacts & USDA       ›  │  OnlineResultsSection
│  💧 Water …                           │  the pool continues below
│   ╭────╮ ╭──────────────────────╮     │
│   │ 📷 │ │ ✨ pork and beans  ⓧ │     │  bar rides up on the keyboard
│   ╰────╯ ╰──────────────────────╯     │
│ ┌──────────── keyboard ────────────┐  │
```

- **Container**: `safeAreaBar(edge: .bottom)` on iOS 26+ (a sticky bar with
  the system's scroll-edge blur, and it insets the list so the last rows
  scroll clear — which retires the "bottom swallow zone" the flow test
  scrolls around). iOS 18 fallback: `safeAreaInset(edge: .bottom)` with a
  `.bar` background, the scope bar's own pattern. One `ViewModifier`, the
  `ToastChrome`/`SwipePillChrome` shape.
- **Contents**: the two controls `EntryDoorsSection` already draws, in a
  `GlassEffectContainer` (glass can't sample glass; the container is what
  lets the circle and the capsule sit 14 pt apart without fighting).
  Camera: 44 pt circle. Describe: a capsule with the sparkle leading the
  `TextField`. On 26+ both are `.glassEffect` (`.regular.interactive()`);
  below 26 they keep today's `.tertiarySystemGroupedBackground` chips.
  Row height stays the `LogButton` 44 pt pairing, since the bar no longer
  sits beside Water's row and parity there stops mattering — but 44 is
  still Apple's minimum target.
- **Tint — decided: camera only.** The camera is the app's primary capture
  action, so it gets the tinted glass (`.regular.tint(.riceToast)`, the
  treatment the swipe pills already use); the describe capsule stays
  regular glass with the riceToast sparkle. Tinting both would be the
  "when everything is tinted, nothing stands out" mistake the HIG calls
  out — the user picked one, per that rule.
- **Shape story, for free**: iOS 26's own bottom idiom is a glass search
  capsule plus a round action button (Safari, Mail). The bar is that shape
  with the jobs swapped — capsule = describe, circle = camera — so it reads
  native at a glance while being obviously not the search field, which now
  lives at the top in a different material (the drawer is part of the nav
  bar, not floating glass).
- **Keyboard**: a bottom safe-area bar rides above the keyboard (SwiftUI's
  keyboard avoidance shrinks the safe area; that is how compose bars work).
  Verify in the SHEET on the device — a landmine class this file has
  history with.
- **Where the results go**: `describeQuery` non-empty → the AI-estimate and
  online sections LEAD the list, pool below, scope bar untouched. That is
  today's order with the doors subtracted, and it puts the results in the
  strip that stays visible above the keyboard — the implementation default;
  revisit only if a device pass shows the scope bar reading as a
  contradiction the way an active search's does.
- **Precedence between the two fields**: `searchPresented` hides the bar
  (today's "doors hide while searching"), so the two can never be active
  at once. Cancelling search reveals the bar with whatever `describeQuery`
  still holds; the sheet's existing "clear the query on a successful pick"
  rule stands.
- **Busy state**: `scanBusy` (barcode lookup) swaps the camera glyph for a
  `ProgressView` and disables the button — the "Looking up product…" row
  has no list row to live in any more. The Log sheet never passed
  `scanCaption`; only the form does, and the form keeps its section.
- **Neither AI nor online on**: the field is a dead end, so the bar shows
  ONE labeled glass capsule, "Scan Barcode, Label, or Menu" (`ScanRowLabel`'s
  copy), full width. Same gating `EntryDoorsSection.describeFieldAvailable`
  already computes.
- **Accessibility**: the camera keeps `.accessibilityLabel("Scan Barcode,
  Label, Menu, or Food")` — `scanRow(in:)` and VoiceOver find it by
  `label BEGINSWITH 'Scan Barcode'` — and the field keeps "Describe food or
  meal" plus `describeFieldAccessibilityID`. The bar is a sibling of the
  List in the accessibility tree, so VoiceOver reaches it without scrolling.
- **The blank Add Food form — decided: keeps its in-form doors SECTION**
  (a form is filled top-down; its doors prefill the fields below them, and
  a bar under a Form you're typing into would compete with the keyboard).
  To keep "one set of doors" true, the two controls extract into an
  `EntryDoorControls` view that both the form's section and the Log
  sheet's bar render — one glyph, one label, one a11y contract, two
  chromes. CLAUDE.md's "exactly TWO places" rule stays true; the chrome
  rule gets a sentence.

### Considered, not chosen — Bottom toolbar buttons that expand (the "minimize" idiom)

```
│   ╭────╮ ╭──────────────────╮        │
│   │ 📷 │ │ ✨ Describe      │        │  ToolbarItemGroup(.bottomBar):
│   ╰────╯ ╰──────────────────╯        │  two system glass buttons
     tap Describe → a short sheet (.height detent) with the field
     focused and the AI/online results under it
```

- System-managed glass, morphs with the nav bar, zero custom chrome. This
  is the iOS 26 `.searchToolbarBehavior(.minimize)` shape — a compact
  button that opens into a field — which the HIG's *Toolbars* page is
  written for.
- Cost: describing is one tap longer, and the field has to live somewhere
  when it opens. A `TextField` inside a toolbar item is the anti-pattern
  Axiom's toolbar skill names outright ("search is not toolbar content"),
  so the expanded state is a small sheet — a sheet over a sheet for one
  text field, routed through the single `activeSheet` slot. Heavier than
  A for the most-typed control on the screen.
- Fallback only: reach for this if the floating bar's keyboard behaviour
  inside the sheet proves unfixable on the device.

### Considered, not chosen — Part 1 only

Search goes to the top; the doors stay as the leading List section, chips
as today. Zero new chrome, one line of risk, but it does not deliver the
bottom-doors ask — listed only as the last-resort fallback.

---

## The Log sheet's order, after

1. Nav bar — Cancel · Log · Sort · Done (unchanged)
2. Search — pinned top drawer (Part 1)
3. Scope bar — Favorites / Foods / Meals (unchanged; hidden while searching)
4. List — [describe results, only while describing] → Water → Recent →
   Everything else (unchanged minus the doors)
5. Door bar — camera + describe, floating (hidden while searching)

Water considered for the bar as a third control and **rejected**: a
drop button beside the camera crowds the bar ("Liquid Glass elements need
breathing room"), shrinks the field, and loses the row's serving text and
its hold-for-amounts menu. Water stays the first row.

Not in this plan, worth its own probe: the Add "+" rides the tab bar's
`.search` role slot, and the whole `AddPillGestures` interception exists
because selecting that role cross-fades the screen. iOS 27's
`Tab(role: .prominent)` may be the honest role for a "+" — unverified
rendering, Axiom says confirm against the SDK first.

---

## Order of work

1. `Style.swift`: `librarySearch(...)` + the door-bar chrome modifier (26+
   glass / 18 material).
2. Part 1 on the Log sheet: placement, `.sheet`/`.fileImporter` to the
   stack, `.visibilityPriority` on Sort under `#available(iOS 27)`.
   Build; sim pass on 26.5 AND 27.0; run `testFoodsSearchAfterSave` and the
   flow test — the drawer-focus landmine is the thing to catch here.
3. Extract `EntryDoorControls`; wire the floating door bar on the Log
   sheet; the form keeps its section through the shared controls.
4. Sweep the other three fields through `librarySearch`.
5. UI tests: flow test (its ~180 pt bottom-zone scroll survives, re-measure
   the margin), `testLogWithoutSaving`, `testBarcodeLookupPrefillsForm`,
   `CROSS_SCOPE_SEARCH`, `testFoodsSearchAfterSave`, the QA tour's
   `logsheet-*` shots (they assert what they photographed — the new bar is
   something a capture can CONTAIN, so add it to the expectation).
6. Deploy phone + watch; the user's eye on the device is the assertion for
   glass, keyboard ride-up, and the tint — a simulator can rule the OS out
   but not a fix in (the tab-bar lesson).
7. Media: the Log sheet is in `docs/media/add-food*.mp4` and the site
   stills, both appearances. Recapture after the user signs off, not before.
