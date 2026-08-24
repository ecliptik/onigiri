# PLAN — one budget, two burns: reconciling the Goal screen (2026-08-23)

## The report

> "I still don't understand the budget. I don't like 'budget right now', we
> should have a set daily budget based on our goal and then track it against
> logging and burn. 1,596 here as a budget is different than the budget,
> average day of 2,369." — the user, 2026-08-23, plus: add the kcal-left
> number to Goal's Budget section.

This is the THIRD round on this screen (2026-08-11 section header,
2026-08-18 row labels, 2026-08-23 footer). Each round renamed something.
The confusion survived all three, which is the evidence that naming is not
where the problem is.

## What the screen actually showed

    Budget, right now      1,596 kcal
    Eaten today            1,018 kcal
    Burned today           2,066 kcal
    ...
    Deficit needed           470 kcal/day
    Budget, average day  ≈ 2,369 kcal/day

Both figures are the SAME formula, `burn − deficit`, on two different burns:

| row                   | burn                                  | − deficit | = budget |
|-----------------------|---------------------------------------|-----------|----------|
| `Budget, right now`   | today's `DayBudget.dayBurn` = 2,066   | 470       | 1,596    |
| `Budget, average day` | `averageDailyBurnKcal` = 2,839        | 470       | 2,369    |

Nothing on the screen states that relationship. The two live in different
containers — one in the Budget card, one inside the collapsed "How the budget
is set" — so they cannot be compared even by a reader who suspects they are
related.

Three facts that change how the fix should be framed:

1. **The 773 kcal gap is entirely ACTIVE energy.** Resting is credited whole
   at midnight, so `Budget, right now` is not a partial-day measurement the
   way "right now" implies; only the active half is partial. The gap is
   `average day's active − today's active so far`.
2. **A set daily budget already exists — it is 2,369.**
   `HealthKitService.averageDailyBurnKcal` excludes today and caches on a
   day-key, so `Budget, average day` is CONSTANT from midnight to midnight.
   It is presented as a rough aside (`≈`, collapsed, "/day") rather than as
   the day's plan, which is why it does not read as one.
3. **Whichever budget "kcal left" rides is the one the day is graded on.**
   If Today's ring says 1,351 left (against 2,369) while `DayBadgeRule` /
   the calendar / the streak grade against 1,596, the app invites the reader
   over the line it then marks them down for. That is strictly worse than the
   present confusion, and it is exactly why PLAN-earned-budget collapsed the
   forecast and the verdict onto one figure on 2026-08-02.

Fact 3 makes this a binary product decision, not a layout fix.

## Fork A — keep the earned model, fix what the screen says (RECOMMENDED)

The budget stays `dayBurn − deficit` and keeps climbing. Nothing about
grading, the widgets, the watch, the calendar or the streak moves. The screen
changes so the two numbers read as one quantity with a named difference.

1. **`Budget, right now` → `Budget, today's burn`.** Keeps the comma form
   that pairs it with `Budget, average day`, and names the INPUT that differs
   — which is the whole reconciliation. It is also checkable on the spot:
   `Burned today` (2,066) sits two rows below and `Deficit needed` (470) is
   one disclosure away, so `2,066 − 470 = 1,596` can be verified without
   leaving the screen. "Right now" said only WHEN, which is the half the
   reader already knew.
2. **Add `Left today`** — `todayBudget − todayIntakeKcal`, through
   `CalorieBudget.remainingHeadline` so "over" renders the way it does on
   every other surface. Placed directly under `Eaten today` so the column
   reads as the subtraction it is (1,596 − 1,018 = 578). This is the user's
   direct ask and needs no new plumbing: `GoalView` already holds both terms.
3. **The footer carries the reconciliation, in live numbers.** The pattern
   the user liked on 2026-08-18 ("9.3 lb over 69 days needs 470 kcal/day")
   applied here: after the existing direction clause, one sentence naming the
   forecast and the gap — e.g. "On an average day it finishes near 2,369 kcal;
   today's active energy is 773 behind an average day so far."
   This DEPARTS from the 2026-08-23 one-clause footer rule, deliberately:
   that rule exists to stop the footer restating rows, and this sentence
   states a relationship no row on this screen can hold.
4. **Leave `Budget, average day` where it is.** Promoting it into the Budget
   card would put two budget rows side by side, which 2026-08-11 forbade, and
   would make three descending figures read as a derivation (the 2026-08-18
   `ObservedBurn` lesson). The footer reference is what connects them.

Cost: the headline figure still climbs, so someone who checks only at
breakfast still sees a low number. The footer sentence is the mitigation, and
it is the same mitigation shipped on 2026-08-23 — this round only adds the
forecast it lands on.

## Fork B — switch to a planned (fixed) budget, verdict included

Budget = `projectedDailyBurn − requiredDailyDeficit`, fixed all day, on every
surface, AND the badge / streak / calendar grade against it. Active burn
becomes context, not substrate.

What this buys: exactly what was asked for — one number, available at
breakfast, never moving, trackable against logging.

What it costs, stated honestly:

- It restores the trailing-average substitution PLAN-earned-budget deleted,
  with its documented failure: "67 kcal left" on a day that ended 29 kcal over
  break-even (2026-07-30). A sedentary day passes on a promise it did not earn.
- The incentive goes. "No watch, no active credit, smaller budget" was the
  stated point of the earned model (the user, 2026-08-02).
- Every past day re-grades, because verdicts are recomputed from Health on
  read rather than stored.

One argument the original plan did not credit, and which is worth weighing:
the 14-day average is not a fixed promise, it is an estimate that UPDATES. A
consistently sedentary fortnight drops the average and the budget with it. The
feedback loop is slow (a fortnight) but real, and `Last 30 days` plus
`ObservedBurn` already exist to surface systematic error.

Scope if chosen: `DailyPlanLoader`, `TodayView.plan(for:)`,
`CalorieBudget.completedDayPlan` call sites, `HeadlineMode`, the widgets, the
watch payload, `DayBudgetTests`, and a rewrite of PLAN-earned-budget's status
section recording the reversal.

## Fork C — B plus a pace warning

Fork B, with a line when today's burn is materially under the average
("you are 773 kcal below an average day"). Honest, but it is B with a nag
attached: the budget still does not move, so the warning has nothing the
reader can act on except eat less than the number the app just gave them.
Not recommended — it re-creates the two-answers-one-screen problem in prose.

## Regardless of the fork

- `Left today` gets added to Goal's Budget section either way; only which
  budget it subtracts from changes.
- Whatever "kcal left" rides must be the figure `DayBadgeRule` grades. No
  design may separate them again.
- Any label change must survive the standing bans: not "so far" (claims a
  partial measurement the midnight resting credit makes false), not "earned"
  (the verdict word), and never two rows reading plainly "Budget".

## How Lifesum and MyFitnessPal do it (the user asked, 2026-08-23)

Both are **fixed baseline + earned bonus**, not Fork B:

1. A declared ACTIVITY LEVEL (sedentary / normal / active / very active)
   multiplies an estimated BMR into a TDEE.
2. Goal and pace subtract a fixed deficit, giving a calorie goal known at
   midnight that never moves on its own.
3. Exercise — logged or pulled from Health — is ADDED BACK on top, visibly,
   raising that day's number.

So Onigiri is already the same shape. Two differences, one in Onigiri's
favour and one not:

- Onigiri's baseline is MEASURED (Health's resting, floored by
  `BasalEstimate`) rather than declared, so it cannot double-count the way
  a declared level plus a tracker feed does.
- **Lifesum shows the two parts separately; Onigiri shows only the sum.**
  That is the whole of the difference, and it is exactly the complaint.

Which suggests a Fork A follow-on, not yet built — decompose the row:

    Resting budget      1,430 kcal   ← yours at midnight, does not move
    + Earned by moving    166 kcal   ← active so far today
    = Budget              1,596 kcal

The fixed daily budget then EXISTS and is guaranteed rather than forecast,
and both budgets finally share a visible common term (`Budget, average day`
is the same first row plus an average day's active). Caveats to settle
first: the resting credit is `max(measured, estimate)`, so it can rise a
little during the day rather than being strictly fixed; `TodayBurnFloor`
ratchets the TOTAL, so the parts must be derived as
`resting = credit, active = todayDayBurnKcal − credit` or the column will
not add up; and it takes the section to six rows, which is the direction
2026-08-10 pulled back from ("there's a lot here").

## Status — Fork A shipped (2026-08-23)

The user chose Fork A. Built, 654 kit tests green, app + watch build clean:

- `Budget, right now` → **`Budget, today's burn`**.
- **`Left today`** added, directly under the intake row, through
  `remainingHeadline` (`+246 kcal over` past the budget, never a negative
  allowance). `GoalView.todayLeftText`.
- Footer gained the reconciliation clause,
  `GoalView.averageDayReconciliation(_:)` — suppressed when
  `averageBurnKcal` is nil or the projected budget is non-positive.
- CLAUDE.md's three budget bullets updated to match.

The Lifesum decomposition above is the open question.
