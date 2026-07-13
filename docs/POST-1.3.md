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

1. **First-run onboarding — SHIPPED 2026-07-12** (9af0b4f): five
   swipeable pages (welcome → Health with context → goal → water →
   done), every step skippable, existing installs auto-flagged past it.
   No in-app preview (Micheal: not needed) — the walkthrough test's
   screenshots are the review. The Goal empty-state item below is
   softened by this but not eliminated.

2. **Paid developer account question.** iCloud/CloudKit sync and
   TestFlight distribution both hang on this; free-team provisioning
   forces the weekly re-deploy.

3. **Watch parity for tracked metrics — SHIPPED 2026-07-12** (3dcc6ba):
   a horizontal page swipe from watch home reveals the Tracked screen
   mirroring the phone's slots; slot settings ride the sync payload,
   totals come from the watch's own Health store. Complications stay on
   the kcal headline + water line BY CHOICE (Micheal: "I like how it is
   now") — revisit only if he asks for slot-aware complications.

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
