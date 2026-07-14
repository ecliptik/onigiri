# 2.0 — Intelligence: label scanning + Apple Intelligence

> **Status (2026-07-14):** M1–M4 implemented and sim-verified. M1
> fixtures are real Vision dumps (`scripts/dump-label-ocr.swift`); the
> M3 table branch was validated against real
> `RecognizeDocumentsRequest` output (real photos yield tables,
> rendered graphics don't — the M2 parser stays the fallback, and its
> LABEL_SCAN test doubles as the fallback regression on iOS 18 sims).
> Foundation Models paths compile and gate correctly (no AI affordance
> renders on non-AI devices — verified by screenshot); their behavior
> needs the iPhone 16, since no Mac-hosted simulator here carries the
> model. Remaining: on-device pantry tour + both-paths A/B on the 16,
> describe-it/meal-name feel, then M5 docs/screenshots/release.

Two features, one bar: they must make *entering a food faster or
better* — the app's philosophy stays "targeted, alongside Apple
Health, no bloat." Everything here respects the iOS 18 floor
(PLAN-1.8.md): the baseline works on the XS; iOS 26 devices get
gated upgrades.

## Feature 1 — Scan Nutrition Label (OCR → prefilled food form)

The gap it closes: barcode scanning covers packaged food that
OpenFoodFacts knows; the label scan covers everything else — store
brands, imports, meal kits, foods with no barcode at all. Point the
camera at the Nutrition Facts panel, get the food form prefilled,
review, save. Scanning stays a one-time event per food; daily
logging stays offline (the barcode-scan rule).

### Pipeline

1. **Capture** — a "Scan Label" entry beside Scan Barcode in the
   new-food form (and the same row grammar if it earns a spot on
   Foods/Log later). Two sources: live camera and photo-library
   pick (labels photographed earlier — cans in a dark pantry).
   Camera path reuses the existing capture plumbing;
   `VNDocumentCameraViewController`-style cropping is NOT needed —
   Vision handles skew.
2. **OCR** — Vision's modern Swift API, `RecognizeTextRequest`
   (iOS 18+, so floor-clean) at `.accurate`, `usesLanguageCorrection`
   OFF for the numbers pass (correction mangles "0g" → "Og").
   Output: text lines WITH bounding boxes — the geometry matters,
   because a label is a two-column table (nutrient | amount) and
   x-position is what associates "Sodium" with "160mg" when OCR
   returns them as separate observations.
3. **Parse** — `LabelParser` in OnigiriKit, PURE and fixture-tested:
   `[(text, box)] → ParsedLabel`. Deterministic heuristics:
   - Anchor on "Nutrition Facts"/"Valeurs nutritives"/"Nutrition
     Information" to crop the region; tolerate its absence.
   - Serving size line → servingDescription + gram weight
     ("2/3 cup (55g)"); "Servings per container" ignored (we log
     per serving).
   - Row extraction by y-band + x-column: nutrient keyword table
     (calories, total fat, saturated, trans, cholesterol, sodium,
     carbohydrate, fiber, sugars, added sugars, protein, the
     vitamin/mineral tail) → value + unit. %DV column EXCLUDED by
     position and the % suffix — the classic parsing trap.
   - Salt→sodium ×0.4 when the label is EU-style (salt, per-100g);
     per-100g labels convert to per-serving when a serving weight
     was found, else import as per-100g with the serving field
     saying so (the OFF fallback behavior).
   - Unit normalization (g/mg/mcg/µg → the app's label units),
     comma decimals, "<1g" → 0.5g convention, "0g"/"Og" OCR fixups.
   - Confidence: each field carries parsed-or-not; the form shows
     what it got and leaves the rest blank — NEVER guess silently.
4. **Prefill** — the existing `ScannedProduct`/prefill path the
   barcode flow uses; Save / Save & Log unchanged. No new form.

### iOS 26 upgrades (gated, optional)

- `RecognizeDocumentsRequest` returns the label as a semantic
  TABLE (`DocumentObservation.Container.tables`) — when available,
  prefer its rows over the geometry heuristics and keep the iOS 18
  parser as the fallback. Same `ParsedLabel` out.
- Foundation Models cleanup pass (see Feature 2): when the
  deterministic parse leaves holes on a gnarly label, feed the raw
  transcript to the on-device model with a `@Generable ParsedLabel`
  and MERGE: deterministic values always win; the model only fills
  blanks. Never required, never networked.

### Testing

- `LabelParserTests`: fixture transcripts (text + boxes captured
  once from real labels via a debug dump) — US FDA panel, EU
  per-100g, bilingual CA, a vertical/compact panel, a curved-jar
  photo with OCR noise. Pure functions, fast, no Vision needed.
- Opt-in UI test (LABEL_SCAN=1): bundled label photo through the
  photo-pick path on the sim — exercises the real Vision request
  end to end and asserts the form fields.
- On-device QA: the pantry tour — five real products, compare
  against the printed label.

## Feature 2 — Apple Intelligence survey: what earns its keep

Framework reality: **Foundation Models** (iOS 26+) is the useful
surface — an on-device ~3B LLM, private, free, offline, with
`@Generable` guided generation (structured output without JSON
parsing) and a small context (~4k tokens; read
`SystemLanguageModel().contextSize`). Availability is explicit and
must gate EVERYTHING: `SystemLanguageModel.default.availability`
distinguishes device-not-eligible (the XS, and any non-AI iPhone) /
Apple-Intelligence-off / assets-still-downloading. The app never
mentions AI on devices that can't run it.

### Adopt (in order of value)

1. **Label-parse refinement** (above) — the highest-value, lowest-
   risk use: invisible, bounded input, structured output, and the
   deterministic parser both precedes and outranks it.
2. **"Describe it" quick add** — a text field on the food form (and
   maybe the dead-end-search Add Food path): type or dictate
   "half cup cooked white rice and a fried egg" → `@Generable`
   guesses [name, kcal, sodium, serving] for REVIEW in the form,
   clearly marked as estimates. This is the model doing what it's
   genuinely good at (commonsense portion/nutrition estimates) with
   the user as the final check. On non-AI devices the field simply
   doesn't exist — the form is unchanged.
3. **Meal-name suggestion** (tiny): naming a Meal from its member
   foods ("Chicken & rice bowl") — one prompt, one suggestion,
   dismissible. Cheap delight, zero risk.

### Decline (the bloat line)

- Chat/coaching/insights ("you eat late on Tuesdays") — not the
  app's job; Health app territory.
- Generated meal plans or recipes — different product.
- Visual Intelligence integration (iOS 26 camera search surfacing
  app content) — Onigiri's content is personal, not searchable
  catalog material.
- Private Cloud Compute model — entitlement-gated, quota-limited,
  networked; the on-device model covers our use cases and keeps
  the "nothing leaves the device" story clean.

### Guardrails (from the platform's own failure modes)

- Wrap every session in the full error surface: context exceeded,
  guardrail violation, model refusal, unsupported language, assets
  unavailable, concurrent requests — each falls back to "the
  deterministic path, silently" (refinement) or a plain empty state
  (describe-it). No AI error ever blocks saving a food by hand.
- Prompts stay small and single-purpose; transcripts are never
  accumulated (no chat, no multi-turn).

## Architecture

- `OnigiriKit/LabelParser.swift` — pure parse, fixture-tested.
- `OnigiriKit/LabelScan.swift` — Vision request wrapper returning
  `[(text, box)]`; iOS 26 documents-request branch lives here.
- `FoodIntelligence.swift` (app target, iOS 26-gated file) — the
  Foundation Models sessions for refinement/describe-it/meal names,
  behind a protocol so the kit parser never imports it.
- Form changes ride the existing prefill path; no new screens.

## Milestones

- **M1** — LabelParser + fixtures green (no UI).
- **M2** — Scan Label in the food form: camera + photo pick →
  prefill, iOS 18 path only. On-device pantry QA.
- **M3** — iOS 26 documents-request branch + FM refinement, gated;
  A/B the same labels both paths on the 16.
- **M4** — Describe-it quick add (gated) + meal-name suggestion.
- **M5** — Docs, screenshots if UI changed, release as 2.0.

## Non-goals

- Photo-of-the-plate calorie estimation (the model can't weigh
  food; confidently wrong numbers poison the log).
- Replacing OpenFoodFacts/FDC — the label scan is the third door
  beside barcode and text search, not a successor.
- Any cloud inference, any new entitlements, any account.
