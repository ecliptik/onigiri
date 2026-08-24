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

Which suggested a Fork A follow-on, and the user took it (see Status) —
decompose the row:

    Resting budget      1,430 kcal   ← yours at midnight, does not move
    + Earned by moving    166 kcal   ← active so far today
    = Budget              1,596 kcal

The fixed daily budget then EXISTS and is guaranteed rather than forecast,
and both budgets finally share a visible common term (`Budget, average day`
is the same first row plus an average day's active). Settled in the build:
the resting credit is `max(measured, estimate)`, so it can rise a little
during the day rather than being strictly fixed — accepted, it can only
rise; `TodayBurnFloor` ratchets the TOTAL, so `earned` is DERIVED
(`dayBurn − credit`) and the residual lands in active, which is the term
the ratchet exists to protect; and the pair is suppressed when the deficit
exceeds the credit, where no honest "already yours" figure exists. It does
take the section to six rows, which is the direction 2026-08-10 pulled back
from ("there's a lot here") — the mitigation is that all six now form one
checkable column rather than six unrelated facts.

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
- `OnigiriUITests.testGoalBudgetShot` (opt-in, `TEST_RUNNER_BUDGET_SHOT=1`)
  captures the section and asserts the rows it photographs. It exists
  because the QA walkthrough's `qa-goal` shots are NOT evidence for this
  screen — both of 2026-08-23's were a stuck food-form sheet and the run
  passed anyway. It scrolls before waiting: a Form renders lazily, so a
  below-fold row does not exist to wait for, and the first version of this
  test spent 20 seconds waiting for something that could never appear.

Then the Lifesum decomposition, on the user's go (2026-08-23):

- `Resting budget` + `Earned by moving` above `Budget, today's burn`, the
  two halves summing to it exactly. `GoalModel.todayRestingCreditKcal`
  added; `earned` derived, never read from Health, so the ratchet cannot
  break the column. Verified on the seeded sim: 1,093 + 385 = 1,478, and
  1,478 − 1,100 = 378.


## Round 3 — one budget, and Goal stops reporting a day (2026-08-23)

> "I think we're overcomplicating by mixing in daily information into goal.
> Goal should include just the daily budget and how it is calculated. We
> don't need to include today's active energy, food eaten or left, just have
> Daily Budget. Put the resting budget into the How the budget is set, also
> rename this to 'How your budget is calculated'." — the user

This REVERSES Round 2's direction, and the reversal is the lesson. Rounds 1
and 2 both tried to make two budgets legible side by side — better names,
then a reconciling footer, then a resting/earned split. Each addition was
correct on its own and none of them fixed the complaint, because the
complaint was never about naming. Two numbers that answer "what can I eat
per day" cannot be made to read as one, however well labelled.

What fixed it was deleting one. Goal keeps the AVERAGE-DAY budget — the
stable one, the one a plan is made of, constant midnight to midnight — and
the live figure stays on Today, where the logging it is tracked against
already lives. Nothing on Goal moves during a day, so there is no second
number left to contradict the first.

Shipped:

- The `Budget` section is ONE row, `Daily budget` = `plan.dailyBudget`,
  rendered `≈ N kcal/day` because it is a rate, not a day.
- Gone from Goal: `Budget, today's burn`, `Earned by moving`, `<intake>
  today`, `Left today`, `Burned today` — and with them `GoalModel`'s
  `todayDayBurnKcal` / `todayIntakeKcal` / `todayRestingCreditKcal`, its
  `todaySummary()` read, and its `TodayBurnFloor` ratchet (TodayView and
  `DailyPlanLoader` still drive that; Goal was only ever a reader).
- `Resting budget` moved INTO the explainer, rebuilt from `BasalEstimate`
  rather than today's credit so nothing in the group moves either. It sits
  directly under `Resting burn, full day`, the row it is cut from.
- `How the budget is set` → `How your budget is calculated`. "Set" reads as
  a setting; every figure inside is derived.
- `Budget, average day` deleted from the explainer — the visible row IS that
  number now, and repeating it under a second name is the same fault as two
  numbers under one name.
- The footer is the one thing holding the two screens together: "This is
  what an average day allows. Today's own budget follows the energy you
  actually burn, so Today can read higher or lower."

Open, flagged not fixed: Today's card title is ALSO "Daily budget" in
maintenance mode (`TodayView`; "Daily goal" in lose mode). In maintenance
the same words name Goal's average and Today's live figure — the collision
this plan exists to remove, in the one mode nobody was looking at.

## The QA walkthrough was filing false evidence (2026-08-23)

Found while verifying Round 2: `qa-goal` was a photograph of a stuck Add
Food form, and the run passed. Three faults, each invisible on its own.

1. **The form never closed.** The bottom `.searchable` bar dismisses with an
   X GLYPH, not a button labelled "Cancel", so the two `tapIfExists(Cancel)`
   calls after `food-form-db-search` matched nothing. Fixed by relaunching,
   which the tour already does for the Log sheet's focused search.
2. **The recovery loop guarded nothing.** It asked whether the Foods scope
   bar EXISTED — and a sheet does not remove the screen beneath it from the
   hierarchy, so the answer was yes the whole time it was covered. It exited
   on the first check having dismissed nothing. Replaced by `dismissModals`,
   which tests HITTABILITY of the tab chrome.
3. **`switchTab` tapped through the sheet.** A covered tab button still
   exists, and tapping it lands on whatever is over it — silently. It now
   waits for hittability and `XCTFail`s with a named reason.

Plus `shot(expect:)`: every stop that can land on the wrong screen names
something only the right screen has, files the image as `…-WRONG`, and
records a failure without aborting the tour. Two traps met while adding it,
both worth remembering:

- **An expectation must be something the capture can CONTAIN.** `qa-goal`
  is the top of Goal and the budget is below the fold, so expecting
  "Daily budget" failed on the right screen. It expects "Current weight",
  and a new `qa-goal-budget` stop scrolls down for the rows themselves.
- **An expectation must not also be true of the screen behind.** The first
  version expected "Protein shake" on the food-form stop — which the Foods
  LIST row carries too, so it would have passed on the exact failure it was
  written for. It expects "Edit Food".

## The seeded simulator (2026-08-23)

- **Default target +60 days → +120.** At 60, the seeded 12.2 lb asks 650
  kcal/day, leaving a ~1,650 average-day budget against a ~1,743 resting
  estimate — under the body's own baseline, so `isAggressive` fired and every
  Goal capture carried an orange pace warning. A correct warning about a bad
  seed, and no way to review the ordinary screen. 120 days asks ~298 for a
  ~2,002 budget. `--seed-aggressive` keeps 60 so the warning stays reachable.
- **A state flag now REPLACES the saved goal.** `goalCount == 0` made every
  one of them a no-op on the second run — the SwiftData store outlives the
  install — so `--seed-goal-reached` inserted nothing and
  `testGoalReachedCelebrationAndContinue` failed on a real assertion about a
  state the argument had declined to set up.
- **A state flag clears `goalReachedAck*`.** Defaults outlive the store too,
  so the celebration stayed permanently dismissed and the test worked exactly
  once per simulator.

Two more latent test bugs surfaced once the seed was honest, both the same
lazy-Form trap in different clothes: `testMaintenanceMode` decided a
`DisclosureGroup` was shut because a row below the fold was not in the tree,
and CLOSED the group it needed open (`revealInBudgetExplainer` scrolls
first, then toggles); and `testGoalReachedCelebrationAndContinue` asserted
`.exists` on choices that render below the celebration card's own bottom
edge.
