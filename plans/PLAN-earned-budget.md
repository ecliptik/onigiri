# PLAN — one burn basis: resting up front, active earned (2026-08-02)

## Why

Today's Details screen showed "695 kcal left" and "197 kcal surplus" at
the same time, and July 30 read differently on Calendar vs Details. Not
two bugs — one root cause, in two halves:

1. **Two burn bases.** `DailyEnergySummary.balanceKcal` derives from the
   RAW `activeBurnKcal + restingBurnKcal`, while the budget row, the
   calendar, badges and streaks all use `DayBudget.effectiveBurn` =
   `max(measured, expected)`. The Net row is the only verdict-shaped
   number in the app not on the shared figure.
2. **The budget is a full-day allowance from the trailing AVERAGE.** A
   budget of 3,050 assumed ~3,198 kcal of burn; Health had recorded
   2,158. So "695 left" is an allowance against a day you aren't having,
   and it keeps promising it right up to bedtime.

## The model (the user, 2026-08-02)

```
dayBurn = restingCredit + activeMeasured
budget  = dayBurn − requiredDailyDeficit
left    = budget − intake
```

- **Resting is credited UP FRONT** — the whole day's worth from midnight.
  It's the predictable part, it's going to happen whether or not you
  move, and dripping it out hourly would make breakfast read as "over"
  every morning while adding no watch incentive.
  `restingCredit = max(measuredResting, BasalEstimate.restingKcal(…))`.
  That one expression covers all three cases: today early (estimate
  wins), a complete day (they agree), an unworn day (estimate floors it).
- **Active is EARNED** — raw measured, never filled, never estimated. No
  watch, no active credit, smaller budget. That IS the incentive, and
  it's the whole reason `effectiveBurn`'s expected-burn substitution goes
  away.
- This is also how MyFitnessPal and Lifesum behave: baseline up front
  from body metrics, tracker activity credited as an adjustment on top.
  HealthKit's two channels map onto it exactly — `basalEnergyBurned` is
  the baseline, `activeEnergyBurned` is defined as energy ABOVE resting.

**History re-grades itself and that's accepted** (the user: "don't worry
about previous earned days… do whatever is cleanest"). Verdicts are
recomputed from Health on every read rather than stored, so NOT freezing
old days is strictly less code. Days with no watch will lose active
credit retroactively and some badges with them.

## What changes

- `DayBudget.effectiveBurn(measuredKcal:expectedKcal:)` → replaced by a
  day-burn function taking active and resting separately. The
  `expectedKcal`/`PlanBurnHistory` substitution is deleted: it exists
  only to protect unworn days, which is exactly what we now refuse to do.
  Its two call sites are `HealthKitService.dailyEnergyTotals` (feeds the
  calendar, badges, streaks) and `TodayView.plan(for:)`'s past-day branch.
- `HealthKitService.dailyEnergyTotals` needs the body profile to compute
  the resting estimate — it already reads Health, so this is a `bodyProfile()`
  call, not new plumbing. Missing height/DOB ⇒ no estimate ⇒ measured
  resting only (documented fallback, not a crash).
- `TodayView.plan(for:)` — today stops driving the budget from
  `averageDailyBurnKcal`. Both branches converge on the same dayBurn.
- `CalorieBudget.derivePlan`'s `averageDailyBurnKcal` /
  `todayActualBurnKcal` pair: check whether the average is still needed
  anywhere (Goal's projection may want it) before ripping it out.
- `TodayBurnFloor.ratcheted` — still meaningful? It guards against
  Health revising burn DOWN mid-day. Under measured-only that guard
  matters MORE, not less. Keep it, but it now ratchets the day burn
  rather than an average-derived figure.
- Goal tab's "Average burn"/"Burn per day" rows describe the OLD budget
  inputs. Re-read them against the new model before shipping — the Fixed
  budget style (`BudgetStyle.fixed`, `customExpectedBurn`) may no longer
  have a coherent meaning if the budget is always measured.

## Watch out

- The morning ring is the acceptance test: at 8am it must read roughly
  `restingFullDay + smallActive − deficit − breakfast`, NOT a number near
  zero. If breakfast reads as "over", resting is being accrued instead of
  credited up front.
- `DayBudget` and `DailyPlanLoader` are read by the widgets and the watch
  too — a change here moves all four surfaces. That's the point (they
  must agree), but it means the widget snapshot and watch payload need
  re-checking, not just the phone.
- Kit tests to update: `DayBudgetTests` asserts "staying in budget is
  exactly banking the deficit" — that identity should SURVIVE this
  change and is the best regression canary.

## Status (2026-08-02)

DONE and green (app + watch build, 354 kit tests pass):
- `DayBudget.dayBurn(activeKcal:restingKcal:estimatedRestingKcal:)`
  replaces `effectiveBurn`; `budget(dayBurnKcal:…)` renamed to match.
- `HealthKitService.dailyEnergyTotals` — the calendar/badge/streak
  figure — now resting-up-front + active-earned, with one profile read
  for the estimate.
- `TodayModel.estimatedRestingKcal` added from `bodyProfile()`.
- `TodayView.plan(for:)` — the today/past fork COLLAPSED. Both go
  through `completedDayPlan(dayBurnKcal:)`; today keeps the
  `TodayBurnFloor` ratchet, which matters MORE under measured-only.
- Tests rewritten to assert the reversed rule
  (`unwornHoursCostActivityButNeverTheBaseline`).

Also done (2026-08-02, second pass — 358 kit tests, app + watch build):
- **`DailyPlanLoader` migrated.** `makeState` takes
  `estimatedRestingKcal` instead of `averageBurnKcal` and rides
  `DayBudget.dayBurn` + `completedDayPlan`, so the widgets and the watch
  quote the same budget the phone does. The fetch layer reads
  `bodyProfile()` (new `HealthPlanReading` requirement) and reads weight
  even in maintenance — not a plan input there, but the resting estimate
  is built from it. `TodayBurnFloor` now ratchets the DAY burn.
- `CalorieBudget.requiredDailyDeficit` extracted: the deficit is pure
  weight-and-calendar arithmetic with no burn in it, which is what lets
  the budget ride the day's own burn while the target stays put. Both
  the loader and `TodayView.currentRequiredDeficit` call it, instead of
  reaching through `derivePlan` for one field and discarding a
  trailing-average budget alongside it.
- `PlanBurnHistory` DELETED (nothing read its snapshots).
  `DeficitTargetHistory` stays — still live, still the thing that keeps
  a past day judged by the goal it was actually held to.
- `resolvedBurn`/`HealthPlanReading.averageDailyBurnKcal` removed with
  it. `WatchSync`'s plan-burn key still rides the sync (the phone sends
  it, the receiver hashes it); harmless, and untangling it is a separate
  change.

Third pass (2026-08-02, both decided with the user):
- **`BudgetStyle` REMOVED**, with `customExpectedBurn` and
  `ActivityLevel`. Fixed had gone inert everywhere that matters — Today,
  the calendar, the badges, the widgets and the watch all derive from
  measured burn — so the pinned "Burn per day" was only moving the Goal
  tab's own preview. And a budget that stays put no matter what you
  measure is the opposite of one you earn: keeping it would have meant
  maintaining a second burn basis alongside the first, which is the
  shape of the bug this plan exists to fix. The keys stay named in
  `PreferenceSnapshot` as `retired*` so Reset Settings still clears a
  value written before the setting went away.
  - Goal's budget section is now informational: "Resting burn" (the
    estimate, newly surfaced — it is half of what the budget is made
    of) over "Average burn" (the projection basis), and a sentence
    saying resting counts from midnight while active is earned.
  - `expectedDailyBurn` → `projectedDailyBurn`, with the SharedStore
    reads gone. It survives for one job: the Goal/onboarding PREVIEW,
    where the question is "a typical day". No specific day is ever
    judged by it.
- **Net moved onto `dayBurn`.** `DayBudget.deficit(intakeKcal:
  dayBurnKcal:)` is the one entry point; `TodayModel.dayBurnKcal` (one
  ratcheted computation per refresh, not per view body) and
  `DailyPlanLoader.State.dayBurnKcal` carry it to the phone and the
  watch/widgets respectively. Moved: Details' Net row and its tint,
  the goal card's banked figure, the watch's goal line, the shared
  `headlineReadout` balance mode, and the loader's gauge progress.
  NOT moved, deliberately: the Burned flank and the Active/Resting
  rows. Those report a measurement; these reach a verdict.
  - The widget snapshot reconstructs `dayBurnKcal` as
    `budget + deficitTarget` rather than growing a stored field, so a
    pre-existing last-good blob still decodes.

Fourth pass (2026-08-02): the two rows both called "Calorie budget".
Goal showed ≈2,293 kcal/day next to Details' 1,567 — both right, 726
kcal apart, indistinguishable. Goal is the average-day projection;
Details is `dayBurn − deficit` on a day that at 1:43pm had earned only
150 active kcal and would climb all afternoon.
- Goal's "Daily plan" now names BOTH: **"Average day"** (≈2,293
  kcal/day) over **"Today"** (1,567 kcal), with a footer saying
  today's starts at resting burn and grows as active is earned.
  Seeing them together is the fix; either alone invites the question.
- The today-floor came OUT of `projectedDailyBurn`. It existed so the
  Goal preview couldn't read lower than Today, which made the figure
  neither an average nor today — and it did NOT prevent the disagreement
  it was there for. With Today shown as its own row the average is free
  to be a true average, and `derivePlan` loses its `todayDayBurnKcal`
  parameter along with onboarding's whole today-burn read.
- VERIFIED on the simulator, after fixing why it couldn't be. The
  standing note that "the seeder writes no body-mass or burn samples"
  was WRONG — it writes all three, and always did. What was missing is
  the resting ESTIMATE: `BasalEstimate` needs height and an age, the
  seeder never wrote a height sample, and date of birth is a HealthKit
  CHARACTERISTIC no app can write at all. So every simulator ran the
  model with `estimatedRestingKcal == nil`, i.e. measured-only, which
  is precisely the behavior the change replaced.
  Fixed: the seeder writes height (178 cm, chosen so the estimate
  lands ~1,743 against a seeded 1,120 of basal and therefore visibly
  FLOORS a partial day) and stamps `debugSeededAgeKey`, which
  `bodyProfile()` consults in DEBUG only when Health has no birthday.
  Goal now renders "Resting burn ≈ 1,743 kcal/day", "Average day"
  and "Today" on a seeded sim — captured via `testHeaderShots` plus a
  throwaway scroll test, since the Health sheet needs XCUITest and
  can't be driven from osascript.
  Watch the double-seed artifact when reading those numbers: every
  `--seed-sample-data` launch ADDS samples, so a second run doubles
  today's burn (385/1,120 became 770/2,240, and "Today" read 2,412
  against an "Average day" of 1,702). Erase the sim first.
- The morning acceptance test is unrun: at 8am the ring must read
  ~`restingFullDay + smallActive − deficit − breakfast`, NOT near zero.
  (Partly evidenced already: at 1:43pm the budget was 1,567 against
  1,302 kcal of measured burn, so the estimate IS flooring resting.)
- The Goal tab's motivation UI is now PARTLY verified: the
  `testHeaderShots` capture shows the progress bar ("1.9 of 12.2 lb"),
  the "Since Jul 3, your earliest weigh-in" line and the projected
  RANGE rendering cleanly, with no crowding of the target label. Still
  unverified: whether a custom start date survives a target change
  (`GoalSettings.startIsManual`).

## Fifth pass (2026-08-02/03) — the field-report round

Ten reports from a live device, and the same shape underneath nearly all
of them: ONE number rendered on two surfaces under different rules or
different labels. When a figure looks wrong, ask FIRST what other screen
shows the same quantity.

- **Badge verdict needs BOTH gates.** `StreakCalendar.isTracked` AND the
  `DayBadgeRule`. Today's goal card ran only the second, so a 934-kcal
  day with a 1,702 deficit read "earned" while the calendar left it
  blank. The card now runs the shared rule and names the threshold.
- **Untracked default 1000 → 500** (the user). The rule is for days you
  FORGOT to log; 1,000 was disqualifying honest low-intake days.
- **Calendar day card** shows the ring's own figure through
  `remainingHeadline` ("+246 over"), not a bare banked deficit; green is
  reserved for a day that MET its target; the redundant "Details ›"
  footer is gone (the corner chevron is the affordance).
- **Headline caption** is "kcal over" with an explicit "+" — the caption
  is the first thing a complication drops, and a bare "36" reads as
  calories still available. The sign travels WITH the value out of
  `remainingHeadline` so no surface can show one without the other.
- **"surplus" → "excess."** "remains"/"remainder" were considered and
  rejected: they describe something LEFT OVER, and this number is what
  was eaten BEYOND the burn.
- **The gauge fills by AREA**, measured from the emoji's alpha channel
  (`EmojiFillProfile`). A rice ball is bottom-heavy, so a waterline at
  85% of its height covered 98% of it.
- **Fresh-install bug**: `DailyPlanLoader` stamps today's target on every
  load and on a fresh install runs before the goal mirrors to the App
  Group, stamping 0 — Today read that and showed MAINTENANCE framing to
  someone with a weight goal. Today now derives from the live goal; the
  snapshot serves only days that are over.

Copy: "burn" and "energy" now split by REGISTER (glanceable numbers vs
explanatory captions) — see CLAUDE.md. Site media recaptured except
`calendar.png` (needs a mid-month capture) and `watch/home.png`.
