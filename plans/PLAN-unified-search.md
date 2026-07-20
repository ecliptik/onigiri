# PLAN — One search field, AI row on top (2026-07-19)

> **SHIPPED** as v2.7.0 (2026-07-20); v2.7.1 added the ✨ AI-provenance
> mark on saved foods/meals/logs. Post-ship copy deltas: the idle row
> is a single line — the quoted-query caption from amendment 1 was
> dropped as redundant (the query is visible in the search field), and
> the demo query is "pork and beans".

> **Amendments (2026-07-20, the user, after on-device use):**
> 1. The idle row reads "✨ **Estimate with <provider name>**" + the
>    quoted query as caption — a bare "Estimate" didn't read as AI,
>    and the provider name doubles as disclosure for remote engines.
> 2. Picking an estimate on the LOG SHEET opens the **full food form**
>    (every value editable), superseding the portion-sheet one-off:
>    the portion sheet allowed serving/meal only, and the form is the
>    same route unknown barcodes/labels already take from the sheet.

Supersedes the describe DOOR from PLAN-entry-doors on every surface:
"Describe food" and Search collapse into ONE field. Decided with the
user 2026-07-19:

1. **Tap-to-estimate row** — search results always lead with
   "✨ Estimate '<query>'"; tapping runs the AI once and the row becomes
   the result. No inference per keystroke (that would burn the user's
   own API tokens and add seconds of latency per letter); queries that
   are really library searches never touch AI.
2. **Order: AI row → library → online.** Saved staples stay one glance
   away; online remains the new-food fallback.
3. **Estimates gain MACROS, both engines** — fat, carbs, protein,
   fiber, sugar (exactly the label reader's five; micros stay out —
   that's where models produce confident garbage). The on-device eval
   suite gains macro plausibility gates, calibrated BEFORE thresholds
   are set (the Gate discipline).
4. **Everywhere**: Log sheet, Foods, and the Add Food form's inline
   search all read scan door + one search field. The Describe door is
   removed from all three.

## Architecture

- **Schema**: `DescribedFood` gains `nutrients: NutrientValues`. The FM
  `@Generable FoodEstimate` and the remote DTO both grow the five
  macro fields (single-source prompts stay in lockstep; the JSON-shape
  suffix and @Guide descriptions updated together). Estimates always
  give values (ranges guided) — unlike label refinement, which only
  reports what's printed.
- **Currency**: an estimate maps to `ScannedProduct` (name, kcal,
  sodium, serving, nutrients) — the exact currency online picks
  already use, so each surface routes it with ZERO new paths:
  Log sheet → portion sheet → one-off log (nutrients ride along);
  Foods → prefilled form; form → apply(). Provider-named provenance
  travels as today (prefill provenance / portion serving text
  unchanged; the row itself shows the caption as its subtitle).
- **`AIEstimateSection`** (new, shared like OnlineResultsSection): the
  tap-to-estimate row + its states (idle / estimating / result /
  failure with retry). Rendered by each surface ABOVE its library
  results whenever `FoodIntelligence.isAvailable` and the query is
  non-empty. onPick hands the ScannedProduct to the host.
- **EntryDoorsSection shrinks to the scan door** (keeps the shared
  caption slot); the describe field and its states are deleted. The
  Add Food form's prefill-provenance row stays.

## Verification + fallout

- Eval suite: golden foods gain macro plausibility ranges; run a
  BASELINE first, set Gates deliberately in their own commit
  (CLAUDE.md rule), then wire assertions. Remote spot-run optional.
- UI tests: the doors shrink by one row — the flow test's frame-based
  Recents scroll (added for the doors) absorbs the shift; rerun the
  same subset (flow, SEARCH_PROBE, ADD_FROM_SEARCH — env knobs!).
- **Media: hold everything.** The pending add-food/foods.png re-shoot
  would have gone stale AGAIN — do ONE media pass after this lands.
- Ship as v2.7.0 after the on-device pass; v2.6.1 releases FIRST as
  the known-good checkpoint (doors + toggle + providers all
  user-tested on the phone).

## Order

1. Release v2.6.1 (checkpoint).
2. Schema + both engines + eval calibration (baseline → Gates).
3. AIEstimateSection; wire Log sheet, Foods, form; delete the
   describe door.
4. Test subset + sim pass; deploy; user pass.
5. ONE media re-shoot (add-food clips, foods.png, anything else the
   new field changes); release v2.7.0.
