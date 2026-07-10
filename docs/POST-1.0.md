# Onigiri — post-1.0 roadmap

Handoff plan written at the v1.0 tag (2026-07-10). Read `CLAUDE.md` first
(build/deploy/test mechanics, SwiftData landmines) and `docs/PLAN.md` for
the app's design history. The working rhythm Micheal expects: fix → test
(package + affected UI test on ERASED paired sims) → commit → push →
deploy to phone AND watch (`scripts/deploy-phone.sh`) → tell him exactly
what to verify on device. Weekly re-deploy required (free team, 7-day
provisioning).

## Where 1.0 landed

Four tabs (Today · Foods · Goal · Calendar). Today is the single daily
record: calories, sodium, water (hydration bar + collapsible Water log
group; the Water tab was folded in), day browsing with swipe/chevrons/
title-menu date jump, backfill into past days. All logging goes through
`LogActions` (one toast + Undo + haptic everywhere); every new food goes
through `FoodFormView` (Log = save+portion for new, Save for edits);
known barcodes skip to the fast portion sheet. HealthKit holds the logs
(every dietary type Health supports, incl. 26 micronutrients; trans fat
is app-only — no HK type). System `.searchable` everywhere (bottom
placement is the iOS 26 standard). Liquid Glass on custom controls.
Daily JSON backups to Documents/Backups (visible in Files, ≤5 kept,
`BackupService`). Calendar is the gamification surface: month stats,
streaks, tappable day card → Today (`QuickActions.dayRequest`).

## 1.1 theme: "show me my data"

1. **Day nutrition detail.** The app writes ~30 nutrient types to Health
   but never displays them. Add a drill-in from Today (tap the meter
   grid or a new row): macros, fiber, sugar, sodium vs limit, caffeine,
   top micros for the browsed day. Data: extend
   `HealthKitService.daySummary` or add `dayNutrients(on:)` summing each
   type over `DayBounds.range`. Read-back mapping already exists
   (`HKCorrelation.nutrientValues` pattern in HealthKitService).
2. **Recents in the Log sheet.** A "Recent" section above Favorites:
   last ~10 unique food names from `foodEntries` history (new kit query
   over the trailing week). Tapping re-logs via the usual portion sheet
   (match to a library food by name when possible, else log the entry's
   own values).
3. **Weekly/monthly trend.** Calendar (or Goal) gains: total deficit ÷
   3,500 as "≈ lb burned off" next to actual scale-weight change over
   the same window — predicted vs real. `WeightTrend` and
   `CalendarModel.totalDeficit` already provide the halves.

## Later features

4. **Reminders** (needs notification permission + design): not-logged-
   by-2pm nudge, water pacing, streak about to lapse. Keep opt-in per
   reminder type in Settings.
5. **Duplicate-food guard**: scanning a product whose *name* (not
   barcode) matches a library food offers "edit existing instead" in the
   prefilled form. He hit this once (manual entry then scan) and chose
   to defer.
6. **Paid dev account** ($99): unlocks CloudKit (real library sync
   replacing WatchConnectivity + file backups) and TestFlight. Big
   migration; design before starting.
7. Watch parity niceties: sync the food/water icon personalization;
   water-goal progress on the watch home.
8. **Progress gauges toggle** (Micheal's idea, default OFF in Settings →
   Appearance): optional rings/bars on Today's metrics — e.g. a ring
   around the balance headline, water/sodium fill bars. Design as a
   set (all metrics or none); a lone water bar looked out of place and
   was removed pre-1.0.
9. **Showcase assets**: screenshots of every screen (light + dark) and a
   short sizzle reel — for README.md and for sending to reviewers.
   Simulator screenshots via `simctl io ... screenshot` are already part
   of the workflow; video via `simctl io ... recordVideo` while driving
   the seeded flow UI test makes a repeatable reel. Seed with
   `--seed-sample-data` so the data looks lived-in. Note item 4 covers
   notifications/reminders — Micheal has flagged it twice, so treat it
   as the top vote-getter for 1.1 alongside the "show me my data" theme.

## Engineering backlog (from the pre-1.0 three-agent audit; none urgent)

- Widget `SnapshotLoader` duplicates `DailyPlanLoader` and opens
  SwiftData in the memory-capped widget process — mirror the goal via
  shared defaults like the watch does (~25 lines deleted).
- `DailyPlanLoader.load` runs its two HealthKit reads sequentially and
  builds a fresh service per call — `async let` + reuse (complication
  refresh latency).
- QuickLog/Foods lists are filtered+sorted ~3× per keystroke — compute
  once per body evaluation.
- Select-all-on-focus (`FoodFormView.onReceive`) also fires for sheets
  presented above the form — scope it to the form's own fields.
- `OnlineFoodSearch.loadDetail` can double-fetch a barcode whose row
  scrolls off and back mid-flight — track in-flight codes.
- Stale online results after editing the query: the "Search online for…"
  button only renders when results are empty.
- Accessibility: calendar day cells need button traits/labels; month
  chevrons are unlabeled (day chevrons and trash buttons were fixed);
  long-press-only affordances (LogButton portions, +🍽️ favorites) need
  `accessibilityAction` equivalents.
- Dynamic Type: headline numbers now scale, but do a full pass at
  accessibility sizes (watch app especially).
- Error-style unification: load failures still use inline red footnotes
  in a few places; transient failures should all be toasts.

## Known quirks to preserve (don't "fix")

- Calendar shows deficit/surplus for past days regardless of the
  "Calorie display" setting — intentional: outcomes for finished days,
  "kcal left" only means something today.
- Gray system Form headers vs black content headers on scroll screens —
  intentional two-tier hierarchy.
- OFF supplement entries often carry label values in per-100g fields
  (÷100 error); Micheal hand-corrects micros once per food and the
  library's values deliberately win over OFF on rescan.
