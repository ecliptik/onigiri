# PLAN — The door bar becomes a composer (2026-09-17)

> Status: PROPOSED. Decisions below are the user's, taken 2026-09-17
> against the Claude iOS app's composer as the reference shape.

## The ask

> "See how there's typing area with actions underneath? Create a plan to
> have something similar, and in the actions below have the Estimate
> with AI, Search Online, and a photo/camera icon. This way we can have
> all actions in one place and keep the results above consistent."

Today the Log sheet's actions are split across two places. The camera
sits in the door bar; the AI estimate and the online search are ROWS IN
THE RESULTS LIST, interleaved with the library matches they compete
with. So the list means two different things at once — here is what you
have, and here are two things you could do — and what a query shows
depends on which of AI and online lookups happen to be on.

The composer puts every action in one container with the text it acts
on, and leaves the list to mean one thing: results.

## Shape

```
┌───────────────────────────────────────────┐
│  📷   Search or Describe Food             │   ← text row (camera leading)
│                                           │
│  ✨ Estimate        🔍 Search Online      │   ← action row
└───────────────────────────────────────────┘
```

One container, pinned where `entryDoorBar` pins it now. Decisions:

- **Both hosts.** The Log sheet and the blank Add Food form share
  `EntryDoorBar`, and they stay one component with one look.
- **The camera stays LEADING**, in its tinted circle, where a thumb
  already knows it. The action row below holds Estimate and Search
  Online. (The alternative — camera as a third action, field full width
  — was offered and declined.)
- **The action row is always present, dimmed until there is text.**
  Discoverable at rest, and the bar never changes height as you type.
  Estimate and Search Online are disabled on an empty query.
- **The list's trigger rows go away.** Both of them:
  `AIEstimateSection`'s tap-to-run row and `OnlineResultsSection`'s
  "Search OpenFoodFacts & USDA for …" row. The buttons are the only
  triggers; the list holds only results.

## What that costs, and what has to move with it

1. **`AIEstimateSection` is a row AND a state machine.** `TapToEstimateRow`
   owns four phases (idle / estimating / result / failure-with-retry)
   plus the refine note, and the IDLE phase is the trigger that now
   moves to the composer. The other three still have to render — in the
   list, where results live. So the section doesn't disappear; it loses
   its idle phase and gains an externally-driven start.
   `MealEstimateSection` shares `TapToEstimateRow` and is NOT in scope
   (the meal builder keeps its inline row), so the phase machine has to
   keep working both ways.
2. **`OnlineResultsSection` loses its search button, not its section.**
   Its row is also the RE-search affordance when the query changes after
   a search ("the rows below are for the old words"). With the trigger
   in the composer, that state needs an answer: the button re-enables
   when the query no longer matches `search.lastQuery`, so the composer
   carries the staleness that the row used to.
3. **The dead-end copy is wrong the moment this lands.** "Try different
   words, or search online below" — online is no longer below. And
   `OnlineResultsSection`'s own "Add Food" appears only after a search
   returns empty, which is still right, but the local "No matches in
   your library" state now has to point at a BUTTON rather than a
   section.
4. **The bar gets taller, and it is pinned above the keyboard.** Two
   rows instead of one, eating list height exactly when the keyboard is
   already eating it. Measure the remaining list height on the 26.5 sim
   before and after; if a typed query shows fewer than ~2 result rows
   above the keyboard, the action row should collapse while typing after
   all (reversing the "always visible" decision, with the measurement as
   the reason).
5. **Neither AI nor online on.** Today the bar collapses to one
   full-width labeled camera door ("Scan Barcode, Label, or Menu") —
   `describeFieldAvailable` in `EntryDoorBar`. With both actions gone
   the action row would be empty, so that collapse stays exactly as it
   is: no composer, no action row, just the door.
6. **The keyboard dismiss** currently added inside the field's capsule
   (a trailing chevron, 2026-09-17) needs a decision: keep it in the
   text row, or drop it now that the composer gives the thumb somewhere
   else to land. Cheap either way; decide when the shape is on a device.

## Rules this must not break

- **AI is tap-to-run, never per-keystroke** (`PLAN-unified-search`,
  2026-07-19). A button makes that more obvious, not less — but the
  button must not re-fire on every text change.
- **One inference at a time.** `TapToEstimateRow.isEstimating` exists so
  a host can quiet its other AI affordances; the composer's Estimate
  button is now one of them and must disable while a run is in flight.
- **The order the results keep.** `PLAN-unified-search` fixed AI →
  library → online and the user has not reopened it. With the triggers
  gone, the RESULTS keep that order: an AI result above the library
  matches, online results below them.
- **The camera's accessibility label** stays "Scan Barcode, Label,
  Menu, or Food" (CLAUDE.md, "Food entry") — `OnigiriUITests.scanRow`
  and VoiceOver both find it by that prefix.
- **`EntryDoorDescribeField.accessibilityID`** must not be renamed;
  `FoodFormView`'s select-all-on-focus handler matches on it, and every
  UI test types through `logSheetField(in:)`.

## Order of work

1. `EntryDoorBar` grows the action row — disabled state, both hosts,
   no behaviour change yet (the list still triggers). Screenshot both
   hosts, both appearances, and MEASURE the list height left above the
   keyboard (point 4).
2. Move the AI trigger: composer button starts the run,
   `AIEstimateSection` renders phases only. Meal builder untouched —
   re-run its test.
3. Move the online trigger the same way, including the stale-query
   re-enable (point 2).
4. Copy pass: the local dead-end state, and anything saying "below".
5. `testLogSheetOneFieldAndWater` gains: the buttons exist and are
   disabled on an empty query; tapping Estimate produces a result row in
   the list; tapping Search Online produces online rows; and the list no
   longer carries either trigger row. `testFormSearchPaging` submits
   with "\n" for the online leg — check it still has a trigger it can
   reach, or move it to the button.
6. Re-run the opt-in suites that drive this sheet end to end:
   `LOG_FIELD`, `LOG_WITHOUT_SAVING`, `CROSS_SCOPE_SEARCH`, `LABEL_SCAN`,
   and the form's `ADD_FROM_SEARCH` / `FORM_SEARCH_PAGING`.

## Open, deliberately

- Whether the action row is a `GlassEffectContainer` row of pills
  matching the camera's chrome, or plain tinted labels. Decide on a
  device: the bar's existing glass rules are in `DoorBarChrome`, and
  the 2026-08-30 lesson (a hierarchical material washing out on the
  phone in dark mode) applies to anything new put in this bar.
- Whether Estimate's label carries the provider name, as the row does
  today ("Estimate with Apple Intelligence" / "with Anthropic"). The
  row had the width for it; a button in a three-up row may not, and the
  provider name is disclosure for remote engines, not decoration.
