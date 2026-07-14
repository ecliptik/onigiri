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
- [x] Batches A (correctness), B (polish/a11y), C (performance)
  applied — see PLAN-1.9.md status notes. Watch fixes deployed
  2026-07-13; verify complication freshness over the week.
- [x] On-device feedback arc (2026-07-13/14): pinned Foods search
  drawer, first-scroll smoothing, one-surface grouped idiom, the
  rice-paper canvas, the nori structural accent, month grid on a
  card, Favorites-first scopes, scan rows with LogButton-sized
  icons, Goal mode picker on top.
- [x] RELEASED as v1.9.0 (2026-07-14).
- [x] Batch D shipped as v1.9.1 (2026-07-14, all items except
  Always-On privacy — declined): watch to 3 pages (favorites fold
  into the meal picker), locked-phone widgets keep the last-good
  snapshot, midnight-spanning burn apportions, streak/month widgets
  pre-render midnight, streak warning says N+1, chart/grid/watch
  accessibility, complication Smart Stack relevance, widget-intent
  echo guard, and the gated iOS 26 garnish (hard scroll edges, glass
  swipe pills, symbol effects).

## 2.0 — Intelligence (planned — see PLAN-2.0.md)

- Scan Nutrition Label: Vision OCR (RecognizeTextRequest, iOS 18
  floor-clean) → LabelParser in the kit → the existing prefill path;
  iOS 26 adds the documents-request table branch, gated.
- Apple Intelligence (Foundation Models, iOS 26, fully gated):
  label-parse refinement, a "describe it" quick add, meal-name
  suggestions — and an explicit decline list (no chat, no coaching,
  no meal plans, no cloud model).
- Milestones M1–M5 in PLAN-2.0.md; deterministic paths always
  precede and outrank the model.
