# PLAN — What's IN the meal, made distinct (2026-08-09)

**Status: BUILT 2026-08-09.** Parts A–C all shipped as specified.
Verified on the 26.5 sim: the member section holds while a search
filters the library to "No foods match …" (the regression the rework
exists for), and a picked food appears in exactly one of the two
sections. 436 kit tests pass; `testMealBuilderQuantityAndSort` extended
and green.

**Device feedback, same day (the user), both applied:**
- **The `×` badge is REJECTED.** `×2` invented a notation for something
  the app calls a SERVING everywhere else (the portion sheet's
  `LabeledContent("Serving")`), so one screen spoke its own dialect. The
  quantity is now a plain trailing-aligned field like every other number
  in the app; the tinted capsule went with it. Membership is carried by
  the section, the name weight, and the contribution caption — it never
  needed a glyph. Don't re-propose the badge.
- **The Total keeps `kcal • <tracked metric>`.** It was removed as a
  stray sodium reading, then RESTORED once it was clear the figure is
  ALREADY customizable: `TrackedNutrient.firstFoodMetric(slot1:slot2:)`
  walks the two Settings → Metrics slots, skips water (not a property of
  a food), and falls back to sodium only if neither resolves — so slot 1
  = Protein makes the line read "12 g protein". Every Foods/Log library
  row and the portion sheet's "Will log" show the same pair, so
  kcal-only would have made THIS screen the odd one out. A comment at
  `libraryMetric` carries the ruling.
- Still open, offered and not built: a real **all-nutrient breakdown**
  for the meal — a "Nutrition" disclosure summing the members'
  `NutrientValues`, reusing `DayNutritionView`'s macro rows and micro
  `DisclosureGroup`s. Needs those rows extracted into a shared view
  first so the two can't drift.

Two things moved during the build, both recorded below in place:
- the `×` slot is reserved for MEMBER rows only — reserving it on
  library rows stranded their "—" half a row from the stepper (caught in
  the first sim shot, not in review);
- a member row's accessibility label carries ", in this meal", so UI
  tests must match its name by PREFIX. Both of the first run's failures
  were that, and the app was right each time.

The ask (the user): "when making a new meal, and adding food, it brings
it all up to the top, but doesn't distinctively show what is 'in' the
meal except that the portion isn't 0."

So: the builder has no place that answers *what is in this meal*. It has
a re-ordering trick that hints at it.

## Current state (verified in `Onigiri/Views/MealFormView.swift`)

One `Form`: name (+ ✨ suggest) · Category · Favorite · **Total** ·
[estimate row while searching] · ["From your description" pending
section] · **"Foods"** — and that last section is the whole library,
every row a `Stepper` with a typed quantity field.

Membership is expressed in exactly two ways, both weak:

- `visibleFoods` (line 128–130) partitions the *already sorted, already
  filtered* pool into `inMeal + rest` and concatenates them. Same
  section, same header, same row style, no separator — the member group
  is invisible unless you happen to notice the list re-ordered.
- The trailing `TextField` shows a number instead of its `—`
  placeholder (line 265). That is the "portion isn't 0" the user names.

Three further consequences of that single-section design, all live today:

1. **Members disappear while you search.** The filter runs *before* the
   partition (line 110–116), so typing "chick" hides the four things
   already in the meal. The code even documents the resulting
   contradiction — "totals still count every selected food, filtered out
   of view or not" (line 98). You lose sight of the meal exactly while
   assembling it.
2. **A member row shows the wrong number.** The caption is
   `food.kcal` — the *per-serving* figure — so "2 × Egg" reads "78 kcal"
   while contributing 156. Nothing on the row says what it puts into the
   Total.
3. **There is no remove.** Pending rows have `.onDelete` (line 434);
   library picks have no gesture at all — you clear the field or step
   down to zero.

And "what's in the meal" is split across **two** sections whenever a
described meal is in flight: some members in "From your description",
others down in "Foods".

## The shape of the fix

One section, above the library, that *is* the meal. Everything else is
the pantry you draw from.

    Meal name                    [✨]
    Category                  Breakfast
    Favorite                       ( )
    Total          620 kcal • 480 mg

    IN THIS MEAL                 3 items      ← new section
      Steamed rice          ×2      [− +]
        380 kcal · 190 each
      Grilled chicken       ×1      [− +]
        220 kcal
      Miso soup ✨          ×0.5    [− +]
        20 kcal · 40 each
      Estimated by Apple Intelligence. Saving
      adds 1 food to your library.

    ADD FROM YOUR LIBRARY        Recent ⇅     ← was "Foods"
      Soylent                 —      [− +]
        400 kcal
      …

## Part A — the "In this meal" section (the core)

- New section between the estimate row and the library, holding **every
  component**: library picks *and* pending components from a described
  meal. One list, one row grammar, one answer to the question.
- **Never filtered by the search field, never re-ordered by the sort
  menu.** The meal is not a search result. This is what fixes
  consequence 1 above, and it retires the "totals count what you can't
  see" comment.
- Header `In this meal`, trailing `3 items` (`.textCase(nil)`, matching
  the sort menu's header treatment). Count only — the Total row above
  already carries kcal and the tracked metric; two kcal figures a
  thumb apart would read as a disagreement.
- Footer: the pending section's existing text, verbatim, shown only
  while `pending` is non-empty (`pendingEngine.estimateCaption` +
  "Saving adds N foods to your library.").
- Empty state: one quiet row, `Add foods below to build this meal.`,
  shown only when the search field is empty. The section is then the
  anchor from the first moment instead of appearing from nowhere on the
  first tap. (Taste knob — review on device; hiding it when empty is the
  fallback.)
- `visibleFoods` loses the `inMeal + rest` concatenation entirely and
  instead *excludes* members. The library section becomes strictly
  "things not yet in the meal", which is why its header is renamed
  **"Add from your library"** — "Foods" beside a section that is also
  foods says nothing.

### Row grammar — what makes a member row look like a member

Structure carries the distinction; everything below reinforces it.
(Deliberate: the app's colour-only ruling means the primary cue must
survive Differentiate Without Color and VoiceOver, and section
membership does.)

1. **Quantity as `×2`, not a bare number.** The typed field keeps its
   job; a `×` glyph sits immediately before it. `×` reads as
   multiplication of a thing you have, `—` reads as absence. On a member
   row the pair gets a `.riceToast.opacity(0.15)` rounded-rect
   background, text staying `.primary` for contrast; library rows keep
   the plain `—` field, no background.
2. **The row's contribution, not its unit price.** Caption becomes the
   quantity's actual kcal, with the per-serving figure trailing only
   when it differs:
   - `1` → `220 kcal`
   - `2` → `380 kcal · 190 each`
   - `0.5` → `20 kcal · 40 each`

   Fixes consequence 2, and makes the Total legible as a sum of visible
   parts.
3. **Name at `.body.weight(.medium)`** in the member section; library
   rows keep the default weight.
4. Marks unchanged: `✨` on a component whose food will be minted on
   save (the existing provenance grammar; `.callout`, per the
   2026-07-23 mark-size ruling).
5. **Swipe to remove**, one `.onDelete` over the unified member list — a
   library pick's quantity goes to 0, a pending component is dropped.
   This *preserves* the pending section's current delete rather than
   losing it in the merge, and gives library picks the gesture they
   never had (consequence 3).

Implementation: the two `ForEach` bodies today are already near-identical
(Stepper wrapping name/caption + a trailing quantity field). Collapse
them into one `MealComponentRow` taking `name`, `caption`, `marks`, a
`Binding<Double>`, and an `isMember` flavour that selects badge-vs-plain.
Two call sites, one visual truth — the `OnlineResultsSection` discipline.

The member list is a computed `[MealMember]` (id, name, caption, kind)
so a single `ForEach` + `.onDelete` can span both kinds; the binding
resolves per kind (library → the existing `binding(for: food)`, pending →
by `UUID` into `pending`).

### Accessibility

- The quantity field keeps its `"Servings of \(name)"` label —
  unchanged, and `testMealBuilderQuantityAndSort` matches on it.
- A member row's *name* takes
  `.accessibilityLabel("\(name), in this meal")` so membership doesn't
  depend on VoiceOver having announced the section header.
- The `×` glyph is decoration: `.accessibilityHidden(true)`.
- Dynamic Type: the member caption gains a second clause; check the
  accessibility sizes stack rather than truncate (the `LibraryRow`
  precedent already switches to a `VStack` at
  `dynamicTypeSize.isAccessibilitySize` — do the same here if it
  squeezes).

## Part B — fold matched components into `quantities` (recommended)

`apply(_:)` currently keeps a matched component in `pending` with a
`matchID`, then reads its values *through* the library food
(`matchedFood`/`kcal(of:)`/`sodiumMg(of:)`/`nutrients(of:)`), and
`visibleFoods` hides the claimed food so it can't be added twice.

Once both live in one section that machinery buys nothing. Have
`apply(_:)` write matches straight into `quantities` and keep only
**unmatched** components in `pending`. Then:

- the `claimed` filter in `visibleFoods` disappears;
- the four value-indirection accessors collapse to the estimate values;
- the "• in your library" caption goes away — a matched component now
  renders exactly like a hand-picked one, which is correct, because on
  save they *are* the same thing;
- `mealItemsFromPending()` keeps its re-match against the live library
  (a food can be added on another screen while the sheet is open) and
  keeps both SwiftData disciplines in its doc comment.

Behaviour change, accepted: a library food deleted while the sheet is
open currently falls back to the estimate's numbers; after this it
simply leaves the meal. That is the more honest of the two.

Separable from Part A — but Part A is smaller and cleaner with it.

## Part C — stable insertion order (optional)

Members currently order by `librarySort` within their group, so a food
lands wherever the alphabet or recency puts it. Keep an
`@State addOrder: [PersistentIdentifier]`, appended on 0→>0 and pruned
on →0, so a just-added food arrives at the end of the member list where
the eye already is; seed it from `meal.items` when editing so a saved
meal reopens in the order it was built. Pending components follow the
library picks in their own order.

Cheap (~10 lines) and it removes the last of the jumpiness the user's
"brings it all up to the top" describes. Skip if device review says the
sort-order grouping already reads fine.

## What does not change

The Total row and its position (deliberate — the old bottom Total sat off
screen); the ✨ name button and its serialization against
`isEstimatingMeal`; the estimate row and its search-field prompt (both
jobs, one field); the sort menu; save semantics, `aiGenerated` /
`aiComposed` rules, and the `MealItem` writes; the discard-confirm
snapshot (extend `FieldsSnapshot` only if Part C adds state — `addOrder`
is derived, so it must **not** enter the snapshot or a pure re-order
would read as dirty).

## Risks / verify on device

- **Focus survival when a row changes section.** `TextField(value:format:)`
  commits on focus resignation, not per keystroke, so the section move
  should land after the field is done — but the stepper's `+` moves the
  row *instantly*. Verify: type `0.5`, tap Done, keystrokes intact; then
  `+` a second food while the first field is focused.
- **Cross-section move animation.** `.animation(.default, value: quantities)`
  must also key off `pending` (it is `Equatable`). A cross-section move
  may cross-fade rather than slide; acceptable, but look at it.
- Search + members: with the members section pinned, a long meal pushes
  search results down. If that bites on iPhone, the fallback is a
  compact member section while a query is active (names + `×n`, no
  steppers) — not built up front.
- iPad: sheet layout only, nothing structural.
- Watch: **no meal builder exists on watchOS** — out of scope entirely.

## Tests

- Kit (pure, `Packages/OnigiriKit`): the member caption is a pure
  function of quantity and per-serving kcal — put it in the kit with
  cases for 1 / 2 / 0.5 / 0.25 and a nutrient-unit case, so the
  "contribution vs each" rule can't drift between rows.
- UI (`testMealBuilderQuantityAndSort`, already opt-in via `MEAL_FORM=1`):
  after setting a quantity, assert (a) the "In this meal" section exists,
  (b) the food is **not** also listed under "Add from your library", and
  (c) — the regression that matters — it is **still visible after typing
  a search string that does not match its name**. Add a shot
  `meal-builder-members`.
- Manual: build a meal by hand; describe one; describe one whose parts
  are already in the library (Part B's path); edit a saved meal and
  confirm it opens with its components in the member section.

## Files

- `Onigiri/Views/MealFormView.swift` — all of Parts A–C.
- `Packages/OnigiriKit/Sources/OnigiriKit/` + `Tests/` — the caption
  helper.
- `OnigiriUITests/OnigiriUITests.swift` — the assertions above.
- No site media: `docs/showcase` and `docs/media` carry Today, Foods,
  Calendar, Goal, iPad, add-food, ai-estimate and day-swipe — the meal
  builder appears in none of them, so nothing to recapture in both
  appearances.

## Decisions (settled 2026-08-09, the user)

1. **One merged section.** Library picks and described components share
   "In this meal"; per-row ✨ and the section footer carry the
   mint-on-save distinction. A meal split across two sections is the
   same diffuseness the ask is about. Part B therefore ships with
   Part A.
2. **Header reads `In this meal`.** `Contains` stays the portion
   sheet's word for the read-only breakdown of a logged meal — this
   surface is an editing one and says so.
3. **Empty state shows the placeholder row** (`Add foods below to build
   this meal.`), hidden while a search is active. Revisit only if it
   reads as clutter on device.
4. **Part C ships** — insertion order, seeded from `meal.items` when
   editing. `addOrder` is derived state and must stay OUT of
   `FieldsSnapshot`, or a pure re-order reads as dirty.
