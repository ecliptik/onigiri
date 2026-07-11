# Onigiri 1.1.0 — "Show me my data" + reminders

Plan agreed 2026-07-10 (scope fine-tuned with Micheal). Read `CLAUDE.md` for
build/deploy mechanics and `docs/POST-1.0.md` for the source roadmap.

Status 2026-07-10 evening: M1–M6 implemented, kit-tested (79 pre-M4 → 83
tests), and sim-verified via the extended seeded flow test; committed
individually on main. Remaining: device deploy + Micheal's verification
pass (incl. reminders via the DEBUG preview row and a Dynamic Type look at
accessibility sizes), then M7 showcase assets + the 1.1.0 tag.

Scope decisions:

- All four features: day nutrition detail, Recents in the Log sheet,
  predicted-vs-actual weight trend, reminders (all three types).
- Trend lives on **both** Calendar (month view) and Goal (compact 30-day row).
- Day detail entry is **both**: tappable meters and a visible chevron.
- Reminders ship with fixed sensible defaults — Settings has only on/off
  toggles per type (times become configurable later if the defaults chafe).
- Engineering backlog quick wins **and** the accessibility pass ride along.
- Showcase assets are captured **after** the features land, as release wrap.
- `v1.1.0` tags at the end; milestone commits deploy as they land.

Each milestone is a deployable increment. Rhythm per milestone: implement →
kit tests + affected UI test on ERASED paired sims → commit → push → deploy
phone AND watch (`scripts/deploy-phone.sh`) → tell Micheal exactly what to
verify on device. (Weekly re-deploys, due ~07-17, fall out of this naturally.)

## M1 — Day nutrition detail

The app writes 39 dietary types to Health but never displays them.

- **Data — no new HealthKit read permissions.** Sum the browsed day's
  nutrients from the app's own food correlations: `foodEntries(on:)` already
  returns `FoodLogEntry.nutrients` via `HKCorrelation.nutrientValues`
  (`HealthKitService.swift:352,539`). Add a pure `NutrientValues` day-sum
  helper in OnigiriKit (unit-tested). Tradeoff (accepted): micros logged by
  *other* apps won't appear in the breakdown — the headline kcal/sodium/water
  stay all-sources via `daySummary`. Trans fat shows from the library-side
  entry values only where present (no HK type; it can't round-trip).
- **UI.** New `DayNutritionView` pushed in Today's existing `NavigationStack`
  (`TodayView.swift:53`). Entry: the meter grid (`TodayView.swift:314`)
  becomes a NavigationLink with a trailing chevron so it's discoverable.
  Follows the browsed day (`TodayModel.selectedDate`). Content order: macros
  (fat + breakdown, carbs, fiber, sugar, protein), sodium vs limit
  (`Color.sodiumStatus`), caffeine, then non-zero micronutrients sorted by
  % of typical intake where we have a reference, else grouped
  vitamins/minerals. Empty day → friendly empty state.
- **Tests.** Kit: day-sum over multiple entries, empty day, nil-vs-zero
  fields. UI: extend the seeded flow test — open the detail from the meter
  grid, assert seeded totals render.
- **Verify on device:** tap the meters for today and for a backfilled past
  day; confirm sodium coloring matches the Today row.

## M2 — Recents in the Log sheet

- **Kit.** `HealthKitService.recentFoods(days: 7, limit: 10)` — correlation
  query over the trailing week, newest first, unique by name
  (case-insensitive). Uniquing/ordering logic is pure and unit-tested.
- **UI.** New `Section("Recent")` in `QuickLogSheet` above Favorites
  (`QuickLogSheet.swift:128`), shown only while the search query is empty.
  Tap → match a library food by name → the usual portion sheet
  (`makePortionTarget`, `QuickLogSheet.swift:281`); no library match → build
  the portion target from the entry's own logged values. All logging still
  routes through `LogActions` (one toast + Undo + haptic).
- **Tests.** UI: log a food from the seeded library, reopen the Log sheet,
  assert it leads the Recent section and re-logs via the portion sheet.
- **Verify on device:** yesterday's real foods appear; tapping one prefills
  the same portion as last time.

## M3 — Reminders (top vote-getter)

Greenfield: the repo has **no** notification code, no background modes, and a
free team (no push). Everything is local notifications, pre-scheduled from
last-known state — there is no background execution to check state at fire
time, so the scheduler re-plans on every app foreground and after every log,
and copy is phrased to survive slight staleness.

- **Kit.** `ReminderPlanner` — pure: (day state, enabled types, now) → the
  notifications that should exist for the next ~3 days (id, fire date,
  title/body). Heavily unit-tested; this is where all the logic lives.
  - *Not-logged-by-2pm*: fires 2pm on days with no food logged when planned.
    Copy: "Nothing logged yet today — log breakfast or lunch?"
  - *Water pacing*: check-ins at 11am / 3pm / 7pm, planned only when water is
    behind pace at planning time; all cancelled once the goal is met.
  - *Streak lapse*: 8pm when a streak ≥ 2 is alive and today's goal isn't met
    yet. Copy: "Your N-day streak ends at midnight."
- **App.** `ReminderScheduler` — thin `UNUserNotificationCenter` wrapper:
  remove all pending Onigiri requests, schedule the planner's output. Hooked
  into app foreground (`ContentView` scenePhase, next to `backupIfDue`) and
  `LogActions` after any log/delete.
- **Settings.** New `Section("Reminders")` after Appearance
  (`SettingsView.swift:126`): three toggles, all default OFF. First
  toggle-on requests notification permission; if denied, the section shows
  an explainer row linking to system Settings.
- **Watch:** none needed — iOS mirrors local notifications to a paired watch
  automatically when the phone is locked.
- **Debug hook.** `#if DEBUG` "Preview reminders" row in Settings fires each
  enabled type after ~5 s — the only practical way to verify on device
  without waiting for 2pm.
- **Tests.** Planner: each type × (already satisfied / behind / disabled),
  midnight boundaries, the 3-day horizon. Manual device pass via the debug
  hook plus one real 2pm nudge.
- **Verify on device:** enable all three, use the preview row, then leave
  lunch unlogged one day and confirm the 2pm nudge (and that logging food
  in the morning suppresses it).

## M4 — Weekly/monthly trend: predicted vs actual

Total deficit ÷ 3,500 as "≈ lb burned off" next to actual scale change.

- **Kit.** `WeightChange` helper: actual = 7-day-MA endpoint difference
  within a window (reusing `WeightTrend.movingAverage`); predicted =
  deficit ÷ 3,500. Nil-safe when the window has < 2 weigh-ins. Unit-tested.
- **Calendar.** `summaryCard` (`CalendarView.swift:294`) gains the pair for
  the displayed month — predicted from the existing
  `CalendarModel.totalDeficit`, actual from a new `bodyMassHistory` fetch in
  `CalendarModel.refresh`. Sparse weigh-ins → "not enough weight data".
- **Goal.** Compact row in the Daily plan section (`GoalView.swift:80`):
  trailing-30-day predicted vs actual, reusing the already-loaded
  `weightHistory` plus a 30-day deficit sum from `dailyEnergyTotals`.
- **Verify on device:** June's number should roughly match what the scale
  actually did; Goal row and Calendar (current month) should agree in spirit.

## M5 — Engineering quick wins (small commits, one deploy)

From the pre-1.0 audit; file refs current as of a5ce213.

1. Widget `SnapshotLoader` (`OnigiriWidgets/SnapshotLoader.swift:28`): stop
   opening SwiftData in the widget process — phone mirrors `GoalSettings`
   into app-group defaults on edit (the `WatchSync.store` pattern) and the
   widget uses `DailyPlanLoader` with that `SyncedGoal`, deleting the
   duplicate loader body.
2. `DailyPlanLoader.load` (`Packages/.../DailyPlanLoader.swift:36`): the
   three sequential awaits become `async let` (complication/widget latency).
3. QuickLog `allItems`/`filtered` (`QuickLogSheet.swift:44,74`) and
   `FoodsView.filteredMeals/filteredFoods` (`FoodsView.swift:45`): compute
   once per body evaluation instead of ~3× per keystroke.
4. `FoodFormView` select-all-on-focus (`FoodFormView.swift:201`): scope the
   `textDidBeginEditing` observer to the form's own fields so sheets above
   the form stop inheriting it.
5. `OnlineFoodSearch` double-fetch (`Onigiri/Views/OnlineResults.swift:54`):
   track in-flight barcodes so a row scrolling off and back doesn't refetch.
6. Stale "Search online for…" (`OnlineResults.swift:152`): show the button
   whenever the query has changed since the last online search, not only
   when results are empty.

## M6 — Accessibility pass

- Calendar `DayCell` (`CalendarView.swift:338`): button trait + label
  ("Tuesday July 8, goal met" / "no data") + hint; it's currently a bare
  tap gesture. (Month/day chevrons are already labeled.)
- `LogButton` (`FoodsView.swift:373`): `accessibilityAction` for the
  long-press custom-portion path; same treatment for any long-press-only
  affordance on Today's +food/+water menus.
- Full Dynamic Type pass at accessibility sizes, phone AND watch — fix
  truncation/clipping; headline numbers already scale.
- New 1.1 views (M1–M4) get labels/traits as they're built, not here.
- **Verify on device:** VoiceOver across Calendar and the Foods list; largest
  text size on the watch home.

## M7 — Showcase assets + release wrap

- Screenshots of every screen, light + dark, on seeded data
  (`--seed-sample-data`) via `simctl io … screenshot` → `docs/showcase/`;
  embed the best in `README.md`.
- Sizzle reel: `simctl io … recordVideo` while the seeded flow UI test
  drives (erase BOTH paired sims first).
- Release: bump `MARKETING_VERSION` to 1.1.0 in `project.yml` ONLY (the
  plist is generated), `xcodegen generate`, full build + test, tag `v1.1.0`,
  deploy both devices.

## Out of scope for 1.1.0 (unchanged from POST-1.0)

Duplicate-food guard, paid dev account / CloudKit migration, watch parity
niceties (icon personalization, water-goal progress), progress-gauges
toggle, user-configurable reminder times, error-style unification.
