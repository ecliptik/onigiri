# PLAN — A meal's full nutrition, not just one metric (2026-08-10)

The meal builder shows kcal and ONE tracked nutrient beside it (sodium
unless you changed it in Settings), and no way to see the rest. Every
number is already in the foods; nothing on the screen adds them up.

## Current state (verified in code)

Most of this is already built, which is why the feature is small:

- `NutrientValues` has both operations needed. `scaled(by:)` multiplies
  every scalar and micro by a factor — a member's quantity. `+` sums,
  and it is careful: a field nil on BOTH sides stays nil rather than
  becoming a spurious 0 (`Nutrients.swift:439`).
- The distinction the summing path must respect is already documented
  there: `fillingBlanks(from:)` exists precisely because summing two
  readings of the SAME food (a label parse and a model's read of the
  same panel) would double every field they agree on. Not a hazard here
  — different foods — but the rule is written down.
- `DayNutritionView` already renders the exact UI wanted: `macroRows`
  (fat → saturated/trans/poly/mono indented, cholesterol, carbs →
  fiber/sugar, protein, caffeine) and `microGroup` disclosures for
  vitamin/mineral families. Its `amountRow` renders NOTHING for a nil
  value — "nil ≠ zero — zero grams is a real recorded amount" — which is
  exactly right for a meal assembled from foods with patchy data.
- The coupling to be broken is ONE line:
  `private var totals: NutrientValues { model.foodLog.totalNutrients }`
  (`DayNutritionView.swift:34`). Everything below it reads `totals`.
- The meal builder already has each member's `NutrientValues` in hand —
  `MealFormView.totalMetricAmount` walks exactly this data today to
  produce its single figure.

## Part A — extract the rows

New `NutrientBreakdown` view taking a plain `NutrientValues`, holding
`macroRows`, `microGroup`, `amountRow`, and `hasMacros` verbatim.
`DayNutritionView` renders it with `model.foodLog.totalNutrients`.

Behaviour must not move: this is a cut-and-paste with the data source
parameterised, and the day view is the reference implementation. If the
day's breakdown renders differently after the extraction, the extraction
is wrong.

`amountRow`'s nil-skipping is the load-bearing part — do not "improve"
it into showing 0.

## Part B — sum the meal

In `MealFormView`, mirroring `totalMetricAmount`:

    members.reduce(NutrientValues()) { sum, member in
        sum + member.nutrients.scaled(by: member.quantity)
    }

Both kinds of member contribute — a library pick's `food.nutrients`, a
minted component's own estimate. Quantity scaling first, then the sum;
the reverse would scale someone else's numbers.

## Part C — where it appears

A `DisclosureGroup("Nutrition")` in the meal form, COLLAPSED, directly
below the Total row — the same idiom as Goal's "How the budget is set"
and the day view's own micro groups. Collapsed because the answer to
"how much magnesium is in this meal" is wanted rarely and would
otherwise push the member list off screen.

Hidden entirely when the sum is empty (`totals.isEmpty`, which the day
view already tests): a meal of foods with no macro data should not show
an empty disclosure.

## Decisions still open

1. **Do AI-estimated components count toward the sum?** They are in the
   meal, and ✨ already marks their provenance on the row — but the
   breakdown would then silently mix measured and estimated values with
   nothing on the totals saying so. Options: include silently, include
   with a footnote when any member is `aiGenerated`, or exclude (which
   makes the breakdown disagree with the Total above it — probably
   disqualifying).
2. **Does the portion sheet get the same breakdown?** It already has a
   "Contains" section for a logged meal, so the shape fits. But a logged
   meal's parts are name+kcal SNAPSHOTS (`LoggedMealItem`) — they do NOT
   carry `NutrientValues`, so this is a data change, not a UI one. Out
   of scope unless you want it.
3. **The food form too?** A single food's nutrients are already editable
   there; a read-only breakdown would duplicate the editor. Probably no.

## Tests

- Kit: `NutrientValues.scaled(by:)` and `+` are already covered by
  `NutrientValuesTests`; add the meal-sum case only if the summing helper
  lands in the kit rather than the view (it need not).
- The extraction is behaviour-preserving, so the guard is that the day
  view still renders identically — worth a screenshot comparison before
  and after rather than a new test.
- UI: extend the opt-in meal-builder test to assert the Nutrition
  disclosure appears with a member that has macros, and does not with a
  library of kcal-only foods.

## Why this is the least urgent of the deferred items

It is purely additive: nothing is wrong today, and the day view already
answers the question once the meal is logged. The argument for it is
that the builder currently surfaces one nutrient beside calories and
gives no way to see the others — a gap, not a defect.

## Files

- `Onigiri/Views/DayNutritionView.swift` — extract the rows.
- `Onigiri/Views/NutrientBreakdown.swift` (new) — the shared view.
- `Onigiri/Views/MealFormView.swift` — the sum and the disclosure.
- `OnigiriUITests/OnigiriUITests.swift` — the opt-in assertions.
