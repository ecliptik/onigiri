# Roadmap

Working queue for upcoming releases. Details get their own PLAN-x.y.md
when a release starts; this file is the durable to-do between sessions.

## 1.8.1 — Foods screen restructure (built — see archive/PLAN-1.8.1.md)

- [x] Foods / Meals / Favorites scope menu (shared ScopeBar with Log).
- [x] "Scan Barcode" row under the scope menu (known barcode → portion
  sheet; new → prefilled form).
- [x] Sheet consolidation into one `.sheet(item:)` slot.
- [~] Bottom search: BLOCKED by platform — with the Add pill occupying
  the search-tab slot, `DefaultToolbarItem(kind: .search, .bottomBar)`
  renders the field behind the floating tab bar (verified on the 26.5
  sim, 2026-07-13). Kept the standard top drawer; details in
  archive/PLAN-1.8.1.md and the FoodsView comment.
- [x] Log-vs-Foods recommendation written (archive/PLAN-1.8.1.md): keep two
  screens, share components; three convergence follow-ups listed.

## 1.9 — Quality pass

- [x] Axiom skills enabled; six-lens review run (2026-07-13).
- [x] Batches A (correctness), B (polish/a11y), C (performance)
  applied — see archive/PLAN-1.9.md status notes. Watch fixes deployed
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

## 2.0 — Intelligence (RELEASED 2026-07-14 — see archive/PLAN-2.0.md)

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

## 2.1 — Glance (BUILT 2026-07-14 — see PLAN-2.1.md; awaiting on-device verdict)

Planned 2026-07-14 (PLAN-2.1.md): widget in LARGE + MEDIUM, day
paging snaps back at day roll, barcode-routing cleanup AND the OFF
nutrition-facts filter (verify-live-first) ride along, paid-account
question deferred again.

- [x] Built + on-device tested 2026-07-14. TodayCardWidget in
  small/medium/large: the kcal ring with burned/eaten, the tracked
  pills, and a prominent Log button (a Link deep into the Log sheet).
  Watch home "Log" rename + unified Favorites→Recent sheet. Details›
  grammar unified across the three sites. Shared BarcodeRouter
  replaces the FoodsView/QuickLogSheet copies. QA-tour edit shots
  fixed.
- Interactive widget AppIntent buttons DROPPED after the on-device
  pass: the planned ‹ › day paging and in-place water wouldn't
  dispatch as WidgetKit buttons on the device (they no-op'd / flashed)
  and couldn't on the simulator either (linkd doesn't index
  widget-intent metadata; the shipped Control Center water button
  failed identically). The card keeps the glance + the reliable Log
  deep link (Link/openURL). LogWaterIntent stays for Control Center /
  Siri.
- Widget lineup trimmed (the user): removed Calorie Meter, Daily
  Progress, Month, and the Weight Trend chart; added a Month Stats
  card (goal-met days + streak). The onigiri gauge lost its water
  button. All home-screen widgets wear the Today card's rice-paper
  canvas. Bumped to MARKETING_VERSION 2.1.0 (build 2).
- OFF search-a-licious nutrition-facts-completed filter SLIPPED back
  to the backlog: probed 2026-07-14, search-a-licious returned 502 and
  legacy 503 (service mid-outage), so the exact filter syntax couldn't
  be verified — and its failure mode is a silent 200-with-zero-hits.
- Release (tag + push) pending the final on-device verdict.

- Today-mirror widget (the user, 2026-07-14, with reference
  screenshot): a medium/large home-screen widget that looks exactly
  like the top of Today — the kcal-left ring with Burned/Eaten
  flanking, the sodium/water metric pills, the rice-paper canvas.
  Interactive: widgets can't scroll, so day paging = ‹ › AppIntent
  buttons swapping the rendered day; a + button deep-links into the
  Log sheet for the shown day (widgetURL routing like the existing
  quick actions), and a water button (the water icon/emoji) that logs
  the default serving IN PLACE — the Control Center "Log Water"
  AppIntent already does exactly this, so the widget reuses it; one
  glance at the day, food and water one tap away (the user).
  Existing pieces to build on: DailyProgressWidget,
  BalanceAccessoryView, the Log Water control intent, the kit's
  PlanCache/DaySnapshot plumbing.

- Watch home "Log" button (the user, 2026-07-14): rename "Log a
  meal" → "Log" and shape its sheet exactly like the phone's default
  Log view — Favorites first (meals + foods mixed), then Recent, one
  unified list. NO Meal-or-Food chooser (an extra tap per log on the
  tappiest device; ruled out after discussion — the Meals/Foods pages
  remain the scope switch, one swipe away).

- "Details ›" everywhere (the user, 2026-07-14): ONE grammar for the
  three tap-for-more affordances — the Calendar day card's "View &
  edit on Today" and Today's headline "Details" both become the month
  card's "Details ›" (text + chevron.right, caption, secondary).
  Reverses the 2026-07-13 chevron removal on Today, deliberately —
  the chevron is the "this navigates" signal and text+chevron is the
  strongest form (audited: no other candidates; Settings' "See Water
  settings" is a pointer caption, not a tap target). Keep the day
  card's edit/cross-tab cue in the accessibility hint.

## 2.4 — Identify Food (planned 2026-07-16 — see PLAN-identify-food.md)

- [ ] Photo of actual food (salad, plate, bowl) → reviewable food with
  components as evidence, prefilled like a label scan. iOS 26 relay
  (kit `FoodPhotoClassifier` Vision classify → `FoodIntelligence`
  text decomposition), shaped so iOS 27 multimodal drops into the
  same `identifyFood` seam. Third door via the existing ScanSheet
  cascade — shutter still, label parse empty → identify (no mode to
  pick, camera only in v1). Evals extend OnigiriTests; scan-row copy
  change needs sign-off.

## 2.5 — Siri (planned 2026-07-16 — see PLAN-siri.md)

- [x] Foundation shipped same day (c678c3a): water/meal/food App
  Shortcuts with parameterized phrases, EntityStringQuery spoken-name
  matching, vocabulary refresh on mirror rewrites.
- [ ] Ask-back queries ("calories left / water / sodium today") —
  one intent, metric AppEnum, live HealthKit reads, snippet card.
- [ ] Watch-side registration (phone-free raise-to-speak logging).
- [ ] Water ounces parameter (Shortcuts automation; ServingSize enum
  only if one-shot spoken sizes prove wanted).
- [ ] Describe-to-log via the on-device model, ALWAYS confirmed before
  the HealthKit write; spoken-grammar rows join the eval suite.
- [ ] negativePhrases pass ("delete/undo my log" must not log).

## Backlog (unscheduled)

- OFF search-a-licious `nutrition-facts-completed` filter (slipped
  from 2.1, 2026-07-14): the legacy leg already filters unfilled
  entries; the primary leg still weeds client-side. Add the equivalent
  via search-a-licious's query DSL (likely appending
  `states_tags:en:nutrition-facts-completed` to `q`) — but ONLY after
  a live probe of the exact syntax during a STABLE window, since a
  wrong filter fails as a silent 200-with-zero-hits that never trips
  the legacy fallback. Breadcrumb in `OpenFoodFactsClient.searchALicious`.
- Watch complication-freshness verification over a normal week
  (1.9 batch A).
- The paid-developer-account question: CloudKit library sync,
  TestFlight.
