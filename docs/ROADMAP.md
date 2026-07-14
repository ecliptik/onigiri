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

## 2.0 — Intelligence (RELEASED 2026-07-14 — see PLAN-2.0.md)

- [x] Scan Nutrition Label: Vision OCR → kit LabelParser (five real
  fixture transcripts) → the existing prefill path; iOS 26
  documents-request table branch, gated; ONE scan row + ONE camera
  ("Scan Barcode or Nutrition Label", shutter on the live scanner).
- [x] Apple Intelligence (Foundation Models, iOS 26, fully gated):
  label-parse refinement (fills blanks only), "describe it" quick
  add, meal-name suggestions; deterministic paths precede and
  outrank the model everywhere; decline list held.
- [x] Same-day UX round from on-device feedback: Goal ScopeBar,
  Favorites-first scopes, meal-builder overhaul (typed fractional
  portions, live Total, members-first, sort), sort menus on all
  library surfaces, first-tracked-slot metric captions (phone +
  watch), Month Details arithmetic + semantic colors, the Add-pill
  search wedge and the TabBarPin gesture-storm fixes.
- On-device QA still open: pantry tour, both-paths A/B on the 16,
  Foundation Models feel.

## 2.1 — candidates

- Today-mirror widget (the user, 2026-07-14, with reference
  screenshot): a medium/large home-screen widget that looks exactly
  like the top of Today — the kcal-left ring with Burned/Eaten
  flanking, the sodium/water metric pills, the rice-paper canvas.
  Interactive: widgets can't scroll, so day paging = ‹ › AppIntent
  buttons swapping the rendered day; a + button deep-links into the
  Log sheet for the shown day (widgetURL routing like the existing
  quick actions). Existing pieces to build on: DailyProgressWidget,
  BalanceAccessoryView, the kit's PlanCache/DaySnapshot plumbing.

## Backlog (unscheduled)

- Shared barcode-routing helper (lookUpBarcode exists in FoodsView
  and QuickLogSheet — 1.8.1 follow-up).
- Watch complication-freshness verification over a normal week
  (1.9 batch A).
- OFF search-a-licious nutrition-facts-completed filter, when the
  service is stable enough to verify against (1.6.1).
- The paid-developer-account question: CloudKit library sync,
  TestFlight.
