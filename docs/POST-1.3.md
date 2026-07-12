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
3. **Watch parity for tracked metrics.** The watch still shows
   sodium/water regardless of the phone's slot configuration (scoped
   out deliberately in the metrics work).
4. **Portion sheet presentation.** The frosted material was "a bit
   better, could use some work but fine for now" — revisit if stacked
   sheets keep reading flat.
5. **Goal screen empty state.** Leads with one gray sentence before any
   weigh-ins exist ("leave as is" for now — noted as modest).
6. **README screenshots** drift as the UI changes; Micheal accepts
   staleness, refresh opportunistically at milestones.
