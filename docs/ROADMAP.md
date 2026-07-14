# Roadmap

Working queue for upcoming releases. Details get their own PLAN-x.y.md
when a release starts; this file is the durable to-do between sessions.

## 1.8.1 — Foods screen restructure

- Move the Foods search field to the bottom, like the Log sheet's.
- Add a Foods / Meals / Favorites scope menu at the top (like Log),
  replacing the one combined list.
- Replace the upper-right barcode toolbar button with a "Scan Barcode"
  row under the scope menu, like the new-food form's.
- Review Log vs Foods once the above lands — they'll be structurally
  similar: consolidate into one screen, or keep them distinct with
  shared elements? Write up the recommendation before building.

## 1.9 — Quality pass

- Enable Axiom skills and run a full review with them.

## 2.0 — Intelligence

- Vision-framework OCR of nutrition labels: point the camera at a
  label, prefill the food form (complements barcode scanning for foods
  without barcodes or not in any database).
- Survey Apple Intelligence features for genuinely useful additions.
- Both must respect the iOS 18 floor (see PLAN-1.8.md) — gate anything
  newer behind #available.
