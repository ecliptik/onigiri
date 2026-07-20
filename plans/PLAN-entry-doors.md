# PLAN — One set of entry doors (2026-07-19)

The three food-entry surfaces drifted: Foods = scan row + bottom search;
Log sheet = scan row + bottom search; Add Food = scan + describe +
bottom search, with its own hand-built scan label and a doubled
"review before saving" caption. Decided with the user 2026-07-19:

1. **Log-sheet describe → portion sheet → one-off log.** The estimate
   opens the portion sheet (name/kcal/sodium/serving prefilled);
   confirming logs WITHOUT adding to the Food Library — the same
   library-less entry Recents already resurfaces "as last logged".
2. **Captions name the provider.** "On-device estimate — review before
   saving." stays for Apple Intelligence; remote providers say
   "Anthropic estimate…", "OpenAI estimate…", "Local AI estimate…" —
   matching the privacy policy's per-provider disclosure.
3. **One shared doors component on all three surfaces.** Scan row +
   describe field, identical copy, icons, order, and caption behavior;
   search stays the standard bottom `.searchable` everywhere (the
   long-standing rule — no custom bars, no auto-focus).

## The component

`EntryDoorsSection` (new, app-side beside ScanRowLabel's home):

- **Scan door** — the existing shared `ScanRowLabel`; each surface
  keeps its own scanner presentation hookup. (Add Food's bespoke
  `Label` copy of it is deleted — that's the drift the shared row
  exists to prevent.)
- **Describe door** — sparkles icon + TextField, placeholder
  **"Describe food — half cup rice, fried egg"** (was "Describe it"),
  onSubmit → `FoodIntelligence.describeFood`, inline ProgressView
  while estimating. Rendered only when `FoodIntelligence.isAvailable`
  (unchanged rule — now provider-aware via BYO-AI).
- **One provenance caption**, always under the door that produced the
  result: describe results caption the describe door, scan/lookup
  results caption the scan door. The describe section's STATIC footer
  is deleted — that was the duplication in the screenshot (the orange
  scan-section `lookupMessage` + the static describe footer both
  showed after one describe).

Caption copy comes from one helper (e.g. `AIProvider.estimateCaption`)
kept beside the provider enum so Settings copy, privacy copy, and
captions can't drift. Sweep ALL existing "On-device estimate" strings
through it — including the scan/identify path's provenance and any
copy in ScanSheet.

## Per-surface wiring

- **Add Food form**: swap its scan section + describe section for the
  component. Behavior unchanged (scan prefills, describe prefills);
  caption placement fixed; copy updated.
- **Log sheet**: gains the describe door under its scan row. Estimate →
  `PortionSheet` with a `PortionTarget` built from the estimate
  (serving text carried; category defaults to the time-of-day slot) →
  `LogActions.logFood`. No library write. The sheet stays open after
  logging (the multi-item-lunch rule) and the field clears for the
  next item.
- **Foods**: gains the describe door under its scan row. Foods is the
  library screen, so describing there routes into the Add Food form
  prefilled — exactly like its scanner does. (The Q1 decision covers
  the LOG sheet; Foods adds to the library by design.)

## Verification + fallout

- UI tests: grep for the old "Describe it" placeholder in tests/evals
  (none referenced it); the log-flow, add-from-empty-search, and
  `SEARCH_PROBE` tests rerun (erased sim). The "describe-log doesn't
  grow the library" assertion was DELIBERATELY NOT added to the
  standard suite — it needs live model inference, which the suite
  keeps opt-in (the eval suite's rule); it belongs beside the evals
  if it's ever wanted.
- The FM eval suite is untouched (prompt text to the model unchanged).
- **Media goes stale AGAIN**: the Log sheet and Foods gain a visible
  row, so `add-food*.mp4` (shot 2026-07-19) and `foods.png` need a
  re-shoot after this lands — the capture rigs from this session make
  that cheap. Hold the recapture until the doors are user-approved.
- Ship as v2.6.1 after on-device confirmation.

## RESULT (2026-07-19, implemented + sim-verified, deployed for user pass)

All phases done as planned, plus two discoveries:
- **Floating-search-bar dead zone**: the doors' height pushed the Log
  sheet's Recents rows into the bottom bar's swallow zone — taps go
  dead there and XCUITest's `isHittable` STILL SAYS TRUE (manual
  coordinate tap reproduced it). The flow test now scrolls by FRAME
  (row clear of the bottom ~180 pt) before tapping. App behavior is
  correct — content scrolls clear like any bottom-bar list.
- **Prefill provenance had no home**: prefilled forms hide the doors
  (not blank), so the caption traveling with a Foods-describe prefill
  never rendered — it gets its own leading row now. Live-verified on
  sim: describe "bowl of oatmeal with honey" on Foods → New Food form
  "Oatmeal / 150 kcal / 1 bowl" with ONE "On-device estimate — review
  before saving." row.
- Tests: flow (142 s), SEARCH_PROBE (single-tap focus), and
  ADD_FROM_SEARCH (64 s) all green — the last is a THIRD silently
  opt-in test (`TEST_RUNNER_ADD_FROM_SEARCH=1`); a plain run skips it.

## Order

1. Caption helper + provider-named copy sweep (independent, small).
2. `EntryDoorsSection`; adopt in Add Food (fixes the dupe + copy).
3. Log sheet: describe → portion → one-off log.
4. Foods: describe → form prefill.
5. Build, test subset, sim pass, deploy, user pass, THEN media
   re-shoot + release.
