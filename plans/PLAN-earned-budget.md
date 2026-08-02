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

NOT DONE — the reason this isn't deployed:
- **`DailyPlanLoader` still derives from `averageDailyBurnKcal`** (lines
  ~62/81). It feeds the WIDGETS and the WATCH, so those two surfaces
  would keep quoting the old average-based budget while the phone quotes
  the earned one — the exact disagreement this plan exists to kill.
  Migrate it to `DayBudget.dayBurn` before shipping. It needs the same
  resting estimate, so it needs the body profile too.
- `PlanBurnHistory.recordToday` (DailyPlanLoader:157) still writes
  snapshots nothing reads for burn any more. Harmless, but dead —
  remove once the loader is migrated and nothing else wants it.
- Goal's "Average burn"/"Burn per day" rows and the whole `BudgetStyle`
  Fixed option still describe the OLD inputs. Fixed may no longer have a
  coherent meaning now that the budget is always the day's own burn.
- The morning acceptance test is unrun: at 8am the ring must read
  ~`restingFullDay + smallActive − deficit − breakfast`, NOT near zero.
