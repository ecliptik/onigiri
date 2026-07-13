# 1.7 — USDA FoodData Central for text search

## Why

OpenFoodFacts is a barcode database: it ranks by scan-count popularity and
its raw-produce entries are sparse and usually missing nutrition facts.
Searching "grapes" returns Grape Jelly, Grape Soda, and Grape Seed Oil —
verified live 2026-07-13: the US top-50 for "grapes" contains zero
plain-grapes entries, so client-side ranking can only reorder the jelly.
USDA FoodData Central (FDC) is the canonical generic-foods database:
"Grapes, red or green, raw" with lab-quality nutrients and household
portions ("1 cup"). The two are complements, not competitors:

- **Barcode scans: always OpenFoodFacts.** FDC's branded set is US-only
  GS1 data and adds nothing over OFF for scanning.
- **Text search: user's choice of OFF (default) or FDC.**

## The API (verified live 2026-07-13)

- `GET https://api.nal.usda.gov/fdc/v1/foods/search?api_key=…&query=…`
  with `dataType` filter and `pageSize`/`pageNumber` paging.
- Free API key from https://api.data.gov (instant signup), 1,000
  requests/hour. Public-domain data (US government work), no attribution
  or usage restrictions.
- Search responses embed `foodNutrients` (name/number/unit/value per
  100 g) — **no per-row follow-up fetches**, unlike OFF's search index.
  Watch for the Energy duplicate: entries exist in both KCAL and kJ;
  filter on `unitName == "KCAL"` (or nutrient number 208).
- `GET /v1/food/{fdcId}` returns `foodPortions` (household measures with
  gram weights) — fetched once on pick to build the serving description
  and per-serving values.
- Datasets to query: `Foundation`, `SR Legacy` (the classic generic
  table), and `Survey (FNDDS)` ("foods as eaten," incl. restaurant-style
  generics). Exclude `Branded` (OFF's job).

## Settings (the user's design)

New Settings section **"Online Database"**:

- Footer notes that **barcode scans always use OpenFoodFacts**.
- Picker **"Text search"**: OpenFoodFacts (default) / USDA FoodData
  Central.
- When FDC is selected, an **API key field** appears below the picker,
  with a footer link: *"A free API key is required from
  https://api.data.gov"* (tappable Link).
- **No bundled key**: the key is user-supplied and device-local
  (SharedStore defaults; it never rides WatchConnectivity — the watch
  doesn't search — and never enters the repo). This keeps the public
  repo clean and every user on their own quota.
- FDC selected but key empty → text search stays on OFF, with an inline
  hint under the field saying so.

New SharedStore keys: `textSearchSource` ("off" default / "fdc"),
`fdcAPIKey` (string, empty default).

## Implementation

1. **`FoodDataCentralClient` in OnigiriKit** (pure parse/map logic,
   unit-tested from JSON fixtures — same shape as OpenFoodFactsClient):
   - `search(query:limit:page:)` → `[GenericFood]` (fdcId, description,
     dataType, per-100 g NutrientValues incl. kcal/sodium).
   - `food(id:)` → portions for the pick path.
   - Nutrient mapping: FDC nutrient numbers → NutrientValues fields
     (energy 208 KCAL-only, sodium 307, macros, micros where OFF mapping
     already established the fields); µg/mg/g unit conversions.
   - Errors: 403 → "check your API key" (distinct, actionable copy);
     429 → the shared busy/throttle handling. Route through the shared
     15 s-timeout session pattern and support cancellation like OFF.
2. **Routing in `OnlineFoodSearch`**: `search()` switches on the setting
   (+ non-empty key) between clients; results normalize into the
   existing row model — FDC rows carry `fdc:{fdcId}` in the barcode slot
   for identity/caching, dataType rides the brand slot for the row
   caption. FDC rows arrive with kcal inline, so the lazy-detail /
   weeding machinery short-circuits (no fetch, no weed). ONE results
   list, rendered by the shared `OnlineResultsSection` on every surface
   (the CLAUDE.md rule stands).
3. **Ranking**: reuse `OpenFoodFactsClient.rank` intent scoring
   (plural-insensitive words, exact-name bonus, extra-word penalty) on
   FDC descriptions — the live probe showed FDC has its own relevance
   quirks ("Grape leaves, canned" above raw grapes).
4. **Pick path**: on tap, fetch `food(id:)` portions; prefill the food
   form with the best household measure as `servingDescription` (e.g.
   "1 cup (151 g)") and nutrient values scaled to it; fall back to
   "100 g" when no portions exist. Cache picked products in the shared
   product cache keyed by the `fdc:` id.
5. **Copy/UX polish**: empty-state and error messages name the active
   source; the "Add Food" dead-end path is source-agnostic.

## Order of work

Client + fixtures/tests → SharedStore keys + Settings section → routing
in OnlineFoodSearch → pick-path portions → copy pass → on-device
verification ("grapes" returns raw grapes first).

## Non-goals

- No bundled/shared API key, no proxy service.
- No merging of OFF + FDC results in one list (pick a source, get its
  results — simpler to reason about, per the user's design).
- Watch unchanged (it never searches online).
- Barcode path unchanged.
