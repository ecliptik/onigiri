# Goal screen: reconciling the model with the scale, and reading the
# day's budget without arithmetic

2026-08-18. Two requests, very different in size. B is a half-day
change with one documented rule to renegotiate. A is a real feature that
touches the app's central philosophy and must not be built by reflex.

**Status: B and A1 shipped 2026-08-18** (the user chose that order).
A2 is deliberately deferred until A1 has shown, over a few weeks of real
data, whether the gap is large and steady enough to be worth acting on.
A3 stays rejected. CLAUDE.md's Budget paragraph was rewritten in the same
commit, and gained the two rules B and A1 create.

---

## A. "Last 30 days" disagrees with itself — should the budget adapt?

### What the row actually compares

`GoalTrendStats.derive` (kit):

- `predicted30Lb` = the sum of `deficitKcal` over TRACKED days in the
  trailing 30, divided by 3,500.
- `actual30Lb` = `WeightTrend.Change.actualLb`, the smoothed scale
  movement over the same window.

Both are already carefully built. `predicted` is filtered to tracked
days for exactly the reason this row exists — a day with burn and no
logged food reads as a ~2,500 kcal deficit, and unfiltered it inflated
the prediction by most of a pound of fiction, which then landed on
screen as "the scale is lagging" (2026-08-08).

So a residual gap is not a bug. It is the honest output of a model, and
the row's whole job is to show it.

### Why "just adjust the budget" is the trap

The gap has at least five causes and the two numbers cannot tell them
apart:

1. **Intake under-logging.** The best-documented effect in the
   literature, routinely 20–30%. Untracked snacks, oil, drinks.
2. **A wrong resting estimate.** `BasalEstimate` is a formula with a
   midpoint constant standing in for unspecified sex; it can sit a
   couple of hundred kcal/day off a real body.
3. **Health's active energy** over- or under-reporting for this person
   and these activities.
4. **Water, glycogen and sodium.** Thirty days smooths much of this and
   not all of it — a 2 lb swing inside the window is ordinary.
5. **The 3,500 kcal/lb constant**, which is an approximation of a
   composition-dependent quantity.

Causes 1–3 justify moving the budget. Cause 4 does not, and a
correction that fires on it will chase noise and then chase its own
tail. Cause 5 justifies nothing.

There is also a direct collision with `PLAN-earned-budget`:

> Active is EARNED: raw measured, never filled, never estimated. No
> watch, no active credit, smaller budget — that IS the incentive, and
> it's why the trailing-average substitution and the whole Fixed budget
> style were deleted rather than kept beside it.

An adaptive correction applied silently to `dayBurn` is the deleted
trailing-average model wearing a new coat. It substitutes a modelled
number for a measured one, which is the specific thing that was ripped
out. **Do not put it back by another name.** Whatever gets built has to
respect that ruling or explicitly overturn it, in writing, on purpose.

### The one number worth computing

Observed maintenance over a window, which needs nothing new from Health:

    observedBurn = meanDailyIntake + (weightChangeLb × 3500 / days)

Eating 2,000/day and losing 2 lb in 30 days implies ~2,233 kcal/day of
real expenditure, whatever the watch measured. Compare that against the
mean measured `dayBurn` for the same window and the difference is a
single, interpretable figure: **how far the model sits from the
evidence, in kcal/day.**

Note what it does NOT know: it cannot separate "you burn less than
measured" from "you eat more than you log". Both push it the same way,
and the correction happens to be right either way — it is only the
EXPLANATION that would be wrong. That is an argument for careful copy,
not for withholding the number.

### Three options

**A1 — Show it, change nothing.** Add a row to the collapsed "How the
budget is set": "Your results suggest ~2,233 kcal/day, about 210 below
measured." Pure information, zero risk, no philosophy renegotiated.
Small, and it makes the "Last 30 days" gap legible instead of puzzling.

**A2 — Offer it (recommended).** A1 plus a button that applies the
delta as an explicit, stored calibration on the plan, exactly the shape
the finish-line date button just took: the app proposes, the user
decides, the number is visible and reversible. This respects
"measured, never estimated" because no substitution ever happens behind
anyone's back — and a calibration the user accepted is not the app
quietly inventing burn.

**A3 — Apply it automatically.** Continuous adaptive TDEE. Rejected for
now: it overturns the earned-budget ruling silently, it cannot tell
water weight from a real model error, and a budget that moves on its own
is the thing "a budget that stays put no matter what you measure is the
opposite of one you earn" was written against — from the other
direction.

### Guardrails any of these needs

- **A minimum window.** Nothing below ~21 tracked days in the window;
  below that, water weight dominates and the figure is noise. Reuse the
  `isTracked` gate `predicted30Lb` already applies — the fiction it
  filters would poison this far worse.
- **A cap.** Clamp the correction to something like ±20% of measured
  burn. An uncapped correction fed a bad month produces a budget nobody
  should eat to, and `minReasonableBudget`/`restingFloorKcal` are the
  floors that would have to catch it — the same pair that turned out to
  be missing from `completedDayPlan` on 2026-08-18.
- **Hysteresis.** Recompute weekly at most. A figure that moves daily
  invites the same "that date seems to change widely depending on the
  day" complaint the projection window was quantized to fix.
- **Never retroactive.** A calibration must not re-grade history. Past
  days are judged by `DeficitTargetHistory` snapshots and that stays
  true.
- **Off by default**, and reversible in one tap.

### Open questions for the user

1. Is the goal to make the app's PREDICTION honest, or to make the
   BUDGET land you on the target date? A1 answers the first; A2 answers
   the second. They are different products.
2. If the gap is under-logging, do you want the app to say so? It cannot
   know, but it could name both possibilities — at the cost of a longer,
   more hedged sentence on a screen already carrying a lot.

---

## B. "Today" section becomes "Budget", with three plain rows

### Now

    Today
      Budget    612 / 1595 kcal
      Burn            2207 kcal

The compound `612 / 1595` asks the reader to do the subtraction, and
which side is which is not self-evident.

### Proposed

    Budget
      Today's Budget   1,595 kcal
      Eaten Today        612 kcal
      Burned Today     2,207 kcal

Each row is one fact. Nothing is hidden and nothing new is computed —
this is purely how three existing numbers are laid out.

### The rule this renegotiates, and it must be renegotiated openly

CLAUDE.md is explicit:

> Since 2026-08-11 the SECTION carries that distinction, not the row
> labels: `Budget` under `Today` (live `dayBurn − deficit`) and
> `Budget, average day` inside the collapsed "How the budget is set".
> Don't put two rows called "Budget" side by side again.

The proposal moves the distinction from the SECTION back to the ROW
label. The hazard that rule was written against — two rows both reading
plainly "Budget" — is still avoided, because the labels become "Today's
Budget" and "Budget, average day", which differ on their face. But the
mechanism is inverted, and the section header becomes the ambiguous
part rather than the disambiguating part.

**If this ships, CLAUDE.md's Budget paragraph must be edited in the same
commit** to say the ROW label now carries it. Leaving the file asserting
the opposite is how the entry-doors line rotted for a fortnight.

### Two details not to lose

- **The footer is now more load-bearing, not less.** "Burned Today"
  reads like a measurement taken so far, and `dayBurn` is not that: it
  is active earned to now PLUS the whole day's resting, credited from
  midnight. That exact misreading already collided with Details once
  and read as the app contradicting itself (2026-08-02). The footer
  that currently carries the distinction has to survive, and probably
  has to get plainer.
- **"Burned" is the right register.** Copy rules put *burn* in the
  glanceable slot and *energy* in the formal one, and the accessibility
  strings already say "1,505, Burned".

### Optional fourth row

A "Left Today" row would complete the arithmetic, but the Today tab's
headline already is that number, in the largest type in the app. Adding
it here risks the two disagreeing at a glance for the ordinary reason
they are sampled at different moments. Recommend leaving it out.

### Effort

Half a day including the CLAUDE.md edit and a UI-test touch-up if any
test asserts on the current labels — `testGoalCancelDismissesKeyboard`
does not, but the label strings should be grepped before starting.

---

## Suggested order

B first: it is small, self-contained, and improves a screen read every
day. Then A1 as its own change, since it is nearly free and makes the
"Last 30 days" row explicable. Then decide A2 on the evidence of what
A1 actually shows over a few weeks — if the gap turns out to be small
and unstable, A2 is not worth building.
