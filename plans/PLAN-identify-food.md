# Identify Food — photo → components → loggable food

Decided 2026-07-16: ship on iOS 26 now with an iOS-27-shaped seam; one
food with components as evidence; third door inside the existing
ScanSheet (camera only, no library import in v1).

## What it is

Point the one scan camera at actual food — a salad, a plate, a bowl —
tap the shutter, and get back a reviewable food: a name, estimated
kcal/sodium, and a serving description that names the components the
estimate was built from ("mixed greens, grilled chicken, vinaigrette").
Prefills the food form exactly like a nutrition-label scan; nothing is
logged or saved without review. Same trust contract as describe-it:
commonsense typical values the person corrects, never auto-committed.

## The platform constraint that shapes the design

iOS 26 Foundation Models is TEXT-ONLY. The on-device LLM cannot see the
photo until iOS 27's multimodal input (Attachment/ImageReference,
Xcode 27). So v1 is a relay:

    still photo ──Vision VNClassifyImageRequest──▶ food labels + confidences
                ──FoodIntelligence (text prompt)──▶ components + portions
                                                    + kcal/sodium estimate

Vision names the dish; the LLM decomposes it into *typical* components
and portions. It will NOT see that this particular salad has extra
avocado — the serving description makes the assumption visible and the
form makes it correctable. Portion size from pixels is out of scope on
26 (and honestly mostly out of reach on 27 too; treat 27 as "sees the
actual components" not "measures grams").

## UX: the cascade, not a mode

ScanSheet keeps its no-mode-to-pick design (CLAUDE.md pins the
one-camera rule). The shutter takes one still and the pipeline decides:

1. `LabelScan.scan` (existing). Parse non-empty → label path, unchanged.
2. Parse empty AND `FoodIntelligence.isAvailable` → identify path:
   classify → decompose → deliver. Today this case is a dead-end
   failure message; it becomes the feature.
3. Identify came up empty (no confident food in frame, model declined)
   → the existing "couldn't read a nutrition panel" message, extended
   to mention food photos.

No AI available → cascade never runs (every AI affordance hides behind
`FoodIntelligence.isAvailable`); the sheet behaves exactly as today.

Copy changes (the row label is the user's copy — confirm before
shipping): "Scan Barcode or Nutrition Label" → likely "Scan Barcode,
Label, or Food"; the in-camera hint line gains "…or photograph your
food". The identify result needs a "Estimated from a photo" cue in the
form, reusing the describe-it disclosure pattern.

## Architecture

- **Kit** (`Packages/OnigiriKit`): `FoodPhotoClassifier` — wraps
  `VNClassifyImageRequest`, filters to confident food-ish labels
  (`hasMinimumRecall(_:forPrecision:)`), returns `[FoodGuess]`
  (label + confidence). Pure enough to unit-test with fixture images;
  no FoundationModels import (kit never imports it).
- **App** (`Onigiri/Models/FoodIntelligence.swift` — the only FM
  bridge): `identifyFood(from guesses: [FoodGuess]) async ->
  IdentifiedFood?`. New `@Generable IdentifiedFood`: name (≤5 words),
  components: [Component] (name, portion text, kcal, sodiumMg — each
  `@Guide`-ranged), all summed IN CODE, not by the model. The prompt
  receives classifier labels as data ("a photo classifier saw: …"),
  never claims the model saw the image, and instructs: if the labels
  don't describe food, return nothing (that's the not-food gate).
- **ScanSheet**: orchestrates the cascade in `read(_:)`; new
  `onFood: (ScannedProduct) -> Void` callback delivering the existing
  prefill currency (barcode "", components folded into
  servingDescription). All three ScanSheet call sites (Foods row, Log
  sheet, food form) wire it to the same food-form prefill the label
  path uses.

### The iOS 27 seam

The public entry is shaped as photo-in/food-out:
`identifyFood(photo: CGImage) async -> IdentifiedFood?`. On 26 its body
is classify→relay; when Xcode 27/iOS 27 arrive, an `#available(iOS 27,
*)` branch replaces the body with the multimodal call (photo attached
to the session, same @Generable). UI, callbacks, and form flow don't
move. The Vision classifier stays useful as the pre-filter/fallback.

## Testing

- Kit: `FoodPhotoClassifier` unit test against 2-3 bundled fixture
  photos (salad, label, non-food) — classification is deterministic.
- Evals: extend `OnigiriTests/FoodIntelligenceEvals` with an
  identify golden set — the decomposition step is text-in/text-out, so
  it evals exactly like describeFood (fake classifier labels in,
  plausibility ranges out; produced-guardrail; not-food inputs must
  return nil — that's the adversarial row).
- UI test: `--food-id-sample` hook bundling a salad photo, mirroring
  `--label-scan-sample`, driving the cascade end to end (skips when the
  runner has no model).

## Risks / honest expectations

- Vision's taxonomy is broad but generic: mixed plates come back as
  "food", "salad", "vegetable" — the LLM gets little to work with and
  the estimate is correspondingly generic. Mitigation: show the name
  prominently in the form; a wrong guess is one edit away.
- A genuine label photo that OCRs to nothing now falls into identify
  instead of the retry message; the classifier seeing "text/menu" (not
  food) should route back to the retry message. Watch this seam in QA.
- Latency: classify is fast; the FM call is the same 1-3 s as
  describe-it. One progress state ("Identifying food…") in the existing
  isReading slot.

## Order of work

1. [x] Kit classifier + tests (2026-07-16; fixture photos deferred to
   the UI hook — the pure filter is tested, the Vision half rides the
   app-level sample-photo path like LabelScan).
2. [x] `FoodIntelligence.identifyFood` + evals (2026-07-16, three
   rounds). Eval-earned hardening, in order: components `.count(0...6)`
   not `1...6` (a mandatory component forced confabulation on not-food
   labels, then isFood flipped true); prompt rules — edible parts only,
   every food label counts, typical serving includes dressing; and the
   CONTAINMENT GUARD — the food's name/components must share a word
   with the classifier labels, because "document, text, paper" invented
   a salad through every prompt-side defense. Known gap row: multi-food
   labels (burger + fries) under-count — the model decomposes only the
   lead dish; kept failing-allowed under the 0.8 kcal gate.
3. [x] ScanSheet cascade + form prefill (2026-07-16): onFood delivers
   ScannedProduct to the same form route at all three call sites;
   "Identifying food…" progress leg; hint/a11y copy gated on
   FoodIntelligence.isAvailable. COPY AWAITING SIGN-OFF: the scan row
   label is untouched; hint, shutter a11y label, retry message, and the
   "Estimated from your photo" form note are proposals.
4. [ ] UI-test hook + QA pass on device (pantry + real meals). The
   --food-id-sample fixture wants a REAL food photo captured during QA,
   not a rendered stand-in — classifier behavior on synthetic images
   proves nothing.
5. [ ] Later, with Xcode 27: swap the seam body for multimodal, re-run
   the same evals (the model changed under the suite — re-baseline).
