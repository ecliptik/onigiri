# Onigiri — post-1.3 pool

Written at the v1.3.4 tag (2026-07-12). Read `CLAUDE.md` first (build/
deploy/test mechanics, landmines) and `docs/PLAN.md` for design history.
The rhythm: fix → test (package + affected UI tests on ERASED sims —
including the iPad's; seeds accumulate) → commit → push → deploy to
phone AND watch → say exactly what to verify on device. Weekly
re-deploy required (free team, 7-day provisioning).

## Where 1.3.x landed

- **iPad support** (1.3.0): readable-width column layouts, all
  orientations, Export/Import JSON as the library-transfer story
  (surfaced in both empty states), flow test green on both idioms.
- **Personalization** (1.3.1–1.3.2): customizable goal badge (presets +
  any emoji via the Custom Emoji prompt), and Today's two tracked-metric
  slots — any of 38 nutrients with limit/goal mode, target, and icon;
  "None" empties a slot; the calendar day card mirrors the slots.
- **Search** (1.3.3–1.3.4): paging past the first 10 on every search
  surface (Foods, Log sheet, AND the food form's own sheet — it has a
  separate list, mind), calorie-less results weeded with page backfill,
  Add Food from a dead-end search.
- **Rhythm & stats** (1.3.4): onigiri awarded only when the day
  completes; untracked-day threshold (default 1,000 kcal) keeps sparse
  days out of month stats while breaking streaks; Month Details grew
  days-tracked/foods-logged/calories/water totals; day Details carries
  the energy rows with Today's icons; day title → month-grid jump;
  compact Burned/Eaten energy mode; recency sort under favorites.

## The pool (unordered, unpromised)

1. **First-run onboarding.** There is none: a new user gets the Health
   sheet and empty states. A guided sequence — welcome → Health access
   with context → goal weight/target date → water goal / tracked
   metrics → done — would front-load what's currently discovered by
   wandering. (Micheal raised it 2026-07-12.)

2. **Paid developer account question.** iCloud/CloudKit sync and
   TestFlight distribution both hang on this; free-team provisioning
   forces the weekly re-deploy.

3. **Watch parity for tracked metrics.** The phone's two metric slots
   can track any of 38 nutrients; the watch doesn't know the slots
   exist — its home screen and complications show the original fixed
   pair (kcal gauge + a hardcoded "oz water" line), so a phone tracking
   Fiber + Iron still shows water on the wrist. Scoped out deliberately:
   the settings SYNC path is easy (slot keys ride the WatchConnectivity
   payload like the icons already do), but the NUMBERS need the watch
   to run its own HealthKit day-total queries per nutrient (the kit
   query code is shared, so this is wiring, not new math), plus a
   rework of the tiny complication layouts to render "10/28 g 🌾"-style
   lines. The real cost: watch UI has zero automated coverage — every
   layout change means Micheal eyeballing it on-wrist. Effort: a solid
   session.

4. **Portion sheet presentation.** `.presentationBackground(.thickMaterial)`
   fixed the worst of the dark-mode black-on-black blending when the
   sheet stacks over the food form or Log sheet, but the verdict was "a
   bit better, could use some work — fine for now." Ideas for the next
   pass, roughly in order of restraint: a visible border stroke or
   stronger shadow at the sheet edge; dimming the sheet BEHIND more
   aggressively; a tinted header strip so the Cancel/Log bar reads as a
   distinct surface; or the drastic option — an inset floating card
   (visible margins all around, dialog-like) instead of an edge-to-edge
   sheet, unmistakable layering at the price of departing from the
   standard sheet feel.

5. **Goal screen empty state.** Since the trend chart leads the screen
   (1.3.4), a brand-new user (fewer than two weigh-ins in Health) opens
   Goal to a single gray sentence — functional and honest, but a thin
   headline. Upgrade paths: the Foods-style empty-state block (icon +
   title + description), or conditionally reorder so the form leads
   until the chart has data. Micheal: "leave it as is" for now; it's
   here because onboarding work (#1) touches the same first-run
   experience and should sweep this up.

6. **README screenshots.** The public README's four shots (Today,
   Foods dark, Goal, Calendar dark) date from ~v1.2; the app has
   visibly moved since (tappable day title, "Details", tracked metrics,
   trend-first Goal, new day card). Drift is accepted — refresh is
   cheap (the QA walkthrough attachments ARE these screens) but each
   refresh needs a visual review pass, so do it at a meaty milestone
   (a 1.4 with onboarding), not per-release.
