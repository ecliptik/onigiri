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
  - Moving it to the field's TRAILING edge was asked for twice
    (2026-09-16, 2026-09-17) and reverted twice: it silently breaks
    barcode scanning, the camera tap simply not opening the scanner,
    caught only by `testBarcodeLookupPrefillsForm`. `EntryDoorBar`'s
    own comment has the detail. **This is the one part of the composer
    that could fix it properly**: a camera in the ACTION ROW is no
    longer a fixed-size circle trailing a flexible-width field inside a
    `GlassEffectContainer`, which is the standing suspicion. If the
    user wants the camera off the leading edge, building the action row
    first and putting it there is the route that doesn't fight the bug.
  - Re-run `testBarcodeLookupPrefillsForm` after ANY change to this
    row's composition, including building the composer on top of it.
- ~~**The action row is always present, dimmed until there is text.**~~
  **REVERSED the same evening, on the device** (the user: "The +,
  Estimate with AI and Search Online should only show up when the
  keyboard/field is active"). The row belongs to the field and arrives
  with its keyboard. What "discoverable at rest" actually bought was
  three dead controls under a sheet you were reading — and not even
  legibly, since "Estimate with AI" truncated to "Estimate wit…" to fit
  beside the others. Estimate and Search Online are still disabled
  until something is typed, which now means "focused but empty".
  - The fear that justified always-on — a bar that changes height on
    the first keystroke shoving the list — doesn't apply: the row
    arrives with the keyboard, at the one moment the bar was going to
    move anyway.
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
(The provider-name question is settled — see below.)

## Decided since

- **The Estimate label is generic: "Estimate with AI"**, with the
  provider named in the RESULT instead (the user, 2026-09-17). Applied
  to today's row immediately, so the composer inherits it.
  `PLAN-unified-search`'s amendment 1 had put the provider in the idle
  row for two reasons: a bare "Estimate" didn't read as AI, and for a
  REMOTE engine it disclosed where the typed text was about to go
  before you tapped. "with AI" keeps the first. The second now arrives
  with the answer — `resultRow`'s caption is the engine that actually
  replied, which is the more honest figure anyway (an unreachable
  remote provider hands off to Apple Intelligence, and the caption is
  the only thing that says so). Accepted on the grounds that the
  provider is the user's own setting on a single-person app.
  `MealEstimateSection` followed on 2026-09-18 ("Match AI copy to be
  consistent") and now reads **"Estimate this meal with AI"** — the
  provider leaves the label, the OBJECT stays, because the meal builder
  also carries a ✨ name button a row up and "Estimate with AI" alone
  would not say which of the two this is.
- **A dead end names the ways OUT** (the user, 2026-09-18: change
  "Try different words, or tap Search Online" to "Add Food, Estimate
  with AI or Search Online"). `deadEndHint` BUILDS that sentence from
  the controls actually on screen — Add Food yields to the online
  section's own button, the estimate needs `isAvailable`, the search
  needs `onlineLookups` — because a hardcoded list would promise
  buttons that aren't there whenever a feature is off. Order follows
  the eye: this card's own button, then the bar's two actions, left to
  right. The Foods tab's "Try different words, or add it as a new
  food." is UNCHANGED: that screen has no AI and no online search, so
  its one route is already the one it names.
- **The action row fills its width, and the `+` sits in the camera's
  column** (the user, 2026-09-17: "have the +, Estimate with AI and
  Search Online fill the entire row, with + left aligned and then
  increase the width of the other two buttons. Change copy to AI
  Estimate if it will help make it fit better"). The `+` is a fixed
  `controlHeight` square so it lands on the camera's midX — the row
  reads as a column under the camera rather than three unrelated
  pills — and the two `ComposerAction` capsules split what's left
  with `maxWidth: .infinity`. "AI Estimate" is what makes that fit;
  "Estimate with AI" truncated at the widths this leaves. The test
  measures the `+` against the camera's midX (±1.5pt), so a future
  layout that drifts them apart fails rather than looking slightly off.
- **`+` opens a chooser, not a `Menu`** (the user, same message: "make
  it bring up a dialog similar to Claude", with a screenshot).
  `AddContextSheet` — Camera / Photos / Files tiles, "Add Food From",
  a close button — presented from the host's ONE sheet slot like
  everything else here, each tile handing back a `ScanSheet.Door` and
  dismissing, with the host's swap deferred a turn (the 2026-07-22
  race). A `Menu` was the first build and reads as a system control,
  not as part of the composer.
- **The actions FILL the row, and "Estimate with AI" came back with the
  width** (the user, 2026-09-18: "have the AI Estimate and Search Online
  buttons be wider to fill in the space in the second row, go back to
  'Estimate with AI' copy to match the active voice style and fit with
  the larger width"). `.frame(maxWidth: .infinity)` had been hung on the
  BUTTON, outside its label — which expands the slot and leaves the
  capsule at its natural width, so the row read as three pills adrift in
  their own gaps. Inside the label, before `DoorBarChrome`, the chip
  itself fills. The shorter "AI Estimate" only ever existed to fit the
  unfilled version; the active voice is the house style and is what the
  rest of the app's buttons are written in. Two consequences worth
  knowing: `testLogSheetOneFieldAndWater` now measures the CHIPS (equal
  halves, reaching the field's trailing edge) because an expanded slot
  around a small chip is invisible to an existence check; and the
  showcase tour's `label BEGINSWITH 'Estimate with'` query — which the
  rename had quietly broken — works again.
- **The "+" is LEFT-ALIGNED, reversing "centred under the camera"** (the
  user, 2026-09-18: "left aligned the +, right align Search Online and
  widen the Estimate with AI and Search Online pills so they evenly fill
  in the row with standard gaps between pills"). The + had been wrapped
  in a `controlHeight`-wide frame so its 36pt circle sat on the 50pt
  camera's axis — which put it 7pt in from the leading edge the camera
  and field share, and made the gap beside the first pill 17pt against
  the 10pt between the pills. Uneven gaps read as a mistake more loudly
  than an off-axis circle does, and the earlier complaint the centring
  answered ("the + button also looks disproportionate") was about its
  SIZE, which is unchanged. At its natural width all three controls in
  the row share one spacing and the 14pt freed goes to the pills (150 →
  157 each). The test now asserts leading EDGES against the camera, and
  that the two gaps are equal — which is the assertion the user's eye
  actually made.
- **The camera must not come up behind a door that isn't the camera**
  (the user, same message: "even after viewing/dismissing the photo or
  file picker the Camera Scan always comes up too. Camera Scan should
  only come up with the camera button"). `ScanSheet` took a door and
  presented the picker OVER its live viewfinder, so dismissing the
  picker revealed a running scanner nobody asked for — and my own code
  comment had called that a feature. `ScanSheet.openDoor` now selects
  a THIRD layout beside camera and fallback: `doorLayout`, the rice
  canvas plus progress/failure, with no `DataScannerViewController` at
  all. Cancelling the picker dismisses the whole sheet
  (`onChange(of: showingPhotos)` for Photos, the `fileImporter`'s
  failure path for Files), so a cancelled door costs nothing and
  leaves nothing running. `doorDelivered` keeps a SUCCESSFUL pick from
  tripping that same dismissal while the read is in flight.
  - **That was still wrong, and the second cut moved the PICKERS
    instead** (the user, the same day: "Scan still comes up with +, but
    disappears itself, still looks janky"). Taking the viewfinder out
    left the sheet still PRESENTING before it had anything to show — an
    empty canvas that threw a picker over itself and closed again on
    cancel. A sheet may not appear before it has something to show, so
    `AddContextSheet` owns `.photosPicker`/`.fileImporter` now and
    `ScanSheet.opening` carries the PICK (`.photo(PhotosPickerItem)` /
    `.menuFile(URL)`) rather than a request for one. The reader opens
    already reading — its door layout's DEFAULT state is the spinner,
    not the `isReading` one, so even the frames before the task starts
    aren't blank — and a cancelled picker presents nothing at all,
    leaving the chooser up where the choice was made. This deleted the
    whole `showingPhotos`/`doorDelivered`/self-dismiss apparatus above.
    A `fileImporter` URL survives the hand-off because
    `MenuDocumentReader` claims the security scope itself at read time.
