# Roadmap

Working queue for upcoming releases. Details get their own PLAN-x.y.md
when a release starts; this file is the durable to-do between sessions.

## 1.8.1 — Foods screen restructure (built — see PLAN-1.8.1.md)

- [x] Foods / Meals / Favorites scope menu (shared ScopeBar with Log).
- [x] "Scan Barcode" row under the scope menu (known barcode → portion
  sheet; new → prefilled form).
- [x] Sheet consolidation into one `.sheet(item:)` slot.
- [~] Bottom search: BLOCKED by platform — with the Add pill occupying
  the search-tab slot, `DefaultToolbarItem(kind: .search, .bottomBar)`
  renders the field behind the floating tab bar (verified on the 26.5
  sim, 2026-07-13). Kept the standard top drawer; details in
  PLAN-1.8.1.md and the FoodsView comment.
- [x] Log-vs-Foods recommendation written (PLAN-1.8.1.md): keep two
  screens, share components; three convergence follow-ups listed.

## 1.9 — Quality pass

- [x] Axiom skills enabled; six-lens review run (2026-07-13).
- [ ] Findings triaged in PLAN-1.9.md — batches pending review.

## 2.0 — Intelligence

- Vision-framework OCR of nutrition labels: point the camera at a
  label, prefill the food form (complements barcode scanning for foods
  without barcodes or not in any database).
- Survey Apple Intelligence features for genuinely useful additions.
- Both must respect the iOS 18 floor (see PLAN-1.8.md) — gate anything
  newer behind #available.
