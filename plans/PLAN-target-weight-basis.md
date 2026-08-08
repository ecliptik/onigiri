# PLAN — Which weight the deficit target is derived from (2026-08-08)

> **SHIPPED** as v2.19.0 (2026-08-08). 416 kit tests (17 new) and the QA
> walkthrough green; the Goal chain verified on a seeded simulator —
> `200.2 − 190 = 10.2`, `10.2 × 3500 ÷ 60 = 595 ≈ 596`,
> `2,300 − 596 = 1,704`. Every row derives from the two above it, on
> screen.
>
> Deltas from the plan as written:
>
> 1. `WeightBasis` + `dailyLows`/`targetBasisLb`/`basisLb` live IN
>    `WeightTrend.swift` rather than a new file — they are the same
>    subject, and the type's own doc already said the moving average is
>    what goal math should use.
> 2. `targetBasisWeightLb()` is a protocol requirement with a DEFAULT
>    (raw latest) rather than a bare requirement, so the existing
>    `HealthPlanReading` test doubles keep compiling and degrade
>    honestly. `HealthKitService` overrides it.
> 3. `GoalModel` computes `basisWeightLb` from the `bodyMassHistory()`
>    it ALREADY loads — no extra query on that screen.
> 4. `GoalView` keeps `currentWeightLb` (raw) for the Weight field,
>    validation and "use current as target", and adds `planWeightLb`
>    (basis) for the deficit chain. Keeping them separate is the point;
>    mixing them is the contradiction this plan exists to avoid.
> 5. `GoalTrendStats.bankedDays` added for the "across N tracked days"
>    line.
> 6. UNRELATED, surfaced by verification: `testQAWalkthrough` failed on
>    a Foods scope tap — existence is not hittability, the scope bar is
>    a LIST ROW, and the tour's own `swipeDown()` can leave it under the
>    nav bar. Pre-existing (the bar has been a list row throughout);
>    fixed with a `scopeTap` helper that scrolls it into reach.

## The observation

A controlled morning experiment (the user, 2026-08-08, screenshots):

| | 7:40 before weigh-in | 7:41 after | Δ |
| --- | --- | --- | --- |
| Burn (`dayBurn`) | 1,848 | 1,849 | +1 |
| Required deficit | **497** | **323** | **−174** |
| kcal left | 1,351 | 1,526 | +175 |
| Scale line | down 1.1 lb | down 1.8 lb | — |

`1848 − 497 = 1351`, `1849 − 323 = 1526`. Burn did not move (active
17→18, resting 1,829→1,824). The entire jump is the deficit target, and
the only input that changed was the weight: 213.4 → 212.2 lb.

## Why — the formula, and its sensitivity

`CalorieBudget.requiredDailyDeficit` (`CalorieBudget.swift:132`):

    requiredDeficit = max(0, current − target) × 3500 / max(1, daysRemaining)

Solving the two data points gives **target ≈ 210 lb, ≈24 days
remaining** — and both readings check out: `(213.4−210)×3500/24 = 496`
and `(212.2−210)×3500/24 = 321`.

So the derivative is:

    d(deficit)/d(weight) = 3500 / daysRemaining

≈ **146 kcal per pound today**, and it GROWS as the target date nears —
292 kcal/lb at 12 days, 700 kcal/lb at 5 days. The nearer the deadline
and the smaller the remaining gap, the more violently each reading
swings the day's allowance.

**This also explains the 2026-08-07 "morning budget jump"**
(OPEN #1 in the handoff notes), which was never a partial Health read.
That note assumed a fixed 193 kcal deficit and concluded the budget
"cannot go below ~1,627". The deficit is not fixed. Post-weigh-in that
day, `1820 − 196 = 1624` — the "~1,600" that was actually seen. The
"~1,000" implies a stale weight near 215–216, which is exactly where the
08-03 peak sits. Same mechanism, no second bug. **Close OPEN #1.**

## The real cause is DIURNAL, not noise

The user, on being shown the above: weight at night runs **2–3 lb
higher** than the next morning — the day's food and water. So
"last weigh-in" encodes *when you last weighed* as much as what you
weigh. At 24 days out that is a **290–440 kcal** difference in the day's
allowance from clock time alone.

This is what kills the naive fix. A plain 7-day mean over raw samples is
skewed by how many EVENING readings happen to fall in the window: two
late weigh-ins in a week pull the average up ~0.6 lb and quietly tighten
the budget ~90 kcal, with nothing on screen to explain it. **The average
has to compare like with like first.**

## The rule

**Daily minimum, then a 7-day mean, as the basis for the deficit target
only.** Decided with the user 2026-08-08:

1. **Collapse each calendar day to its LOWEST reading.** The morning
   weight IS the day's low, so the minimum selects it without a clock
   rule to tune, ignores a stray evening weigh-in instead of averaging
   it in, and never drops a day for lacking a morning reading. (A day
   with only an evening reading still reads high — damped by the mean,
   accepted.)
2. **Mean of those dailies over 7 days**, matching the window already
   behind Today's "down 1.8 lb this week" line, so the number on screen
   and the number in the math come from one idea.
3. **Setting lives in the Goal tab**, under the Daily plan, where the
   plan already explains itself.
4. **Default: the smoothed basis.** `WeightTrend`'s own doc comment
   already says "the moving average is what goal progress and
   projections should use" — the deficit simply never used it. Past days
   are unaffected: `DeficitTargetHistory` snapshots each day's target, so
   history keeps the bar it was held to.
5. **Display never changes.** Goal keeps showing the real last weigh-in
   (212.2 lb). The app must not report a weight that never appeared on
   the scale; only the target math uses the average.

## Architecture

### Kit — one resolver, three callers

`WeightTrend` gains the pure, tested piece:

```swift
public extension WeightTrend {
    /// One comparable reading per calendar day: the day's LOWEST.
    /// Evening weight runs 2–3 lb above the next morning, so a mean over
    /// raw samples measures weighing habits as much as body mass.
    static func dailyLows(_ points: [Point], calendar: Calendar = .current) -> [Point]

    /// The weight the deficit target is derived from: the mean of the
    /// last `windowDays` daily lows, or nil when there is nothing to
    /// average (caller falls back to the raw latest).
    static func targetBasisLb(
        _ points: [Point], windowDays: Int = 7, now: Date = .now
    ) -> Double?
}
```

New enum beside the other unit/preference types:

```swift
public enum WeightBasis: String, CaseIterable, Sendable {
    case lastWeighIn      // today's behavior
    case sevenDayAverage  // default
}
```

`AIProviderSettings`-style key in `SharedStore`:
`weightBasisKey = "weightBasis"`, absent = `.sevenDayAverage`. Add it to
`PreferenceSnapshot.settingsSweepKeys` — and note the exact-count
tripwire in `PreferenceSnapshotTests` will fire (49 → 50), by design.

### The three call sites must agree

The deficit is computed in THREE places, and a basis that resolves
differently in any of them puts a different number on Today than on the
widget — the failure this repo has already paid for twice:

- `TodayView.swift:652` (`currentRequiredDeficit`)
- `DailyPlanLoader.swift:118`
- `DailyPlanLoader.swift:235`

Each currently feeds `latestBodyMassLb()`. Introduce ONE resolver they
all call:

```swift
// HealthKitService
/// The weight the deficit target should use, per the user's setting.
/// Falls back to the raw latest whenever the basis can't be computed
/// (no history, Health sealed) — a target is better than no target.
public func targetBasisWeightLb() async -> Double?
```

`DailyPlanLoader` already reads `bodyMassHistory` elsewhere, so the
extra query is not new work on that path; Today already loads
`bodyMassHistory(days: 7)` for the trend line and can reuse it.

**One resolved "current weight" per surface.** `TodayModel` also feeds
`currentWeightLb` to `BasalEstimate` for the resting floor. Both go
through the same resolved value, so a screen never mixes two different
current weights. This slightly steadies the resting estimate too —
harmless, since measured resting normally wins over the floor.

### Goal tab UI

Under the Daily plan section:

```
Weight used for the target
  ○  Last weigh-in      212.2 lb
  ◉  7-day average      212.8 lb
     └ Steadier target — a single weigh-in moves it less.
```

Both live values shown so the choice is concrete rather than abstract.
Footer, formal register: "Evening weigh-ins read 2–3 lb above the next
morning. The average uses each day's lowest reading, so the target
follows real change instead of the time you stepped on the scale."

## Part 2 — The Goal tab reads as a chain (2026-08-08)

The basis change forces a UI reckoning, and reviewing the screen with the
user surfaced four separate confusions. Their questions, and what the
code actually does:

| Row | What it is |
| --- | --- |
| To lose | last weigh-in − target |
| Deficit needed | `to lose × 3500 ÷ daysRemaining` |
| **Average day** | **a BUDGET**: `Average burn − Deficit needed` (2,692 − 323 = 2,369) |
| Today | today's `dayBurn − deficit`; matches Details' Calorie budget ✓ |
| **Total deficit** | net across **all tracked days on record** — NOT since the goal was set |
| Last 30 days | predicted = deficit ÷ 3500; actual = smoothed linear fit |
| Resting burn, full day | estimated full-day resting ✓ |
| **Average burn** | trailing average of daily TOTAL burn — the INPUT to "Average day" |

Nothing here is miscomputed. Every complaint is that the screen doesn't
show its own arithmetic: "Average day" and "Average burn" sound
parallel, sit in different sections, and one is derived from the other.

### 2a. The chain must add up

**This is the load-bearing one.** With the deficit on the smoothed basis
and "To lose" on the last weigh-in, the two rows contradict: To lose 2.2
lb above a deficit that implies 4.1 lb. That is exactly the "one label,
two different numbers" failure this codebase has already paid for twice
(Goal 2,293 vs Details 1,567; "Calorie budget" meaning two things one
screen apart).

Daily plan becomes, in order:

    Weight used          214.1 lb  ›
      └ 7-day average of daily lows (last weigh-in 212.2 lb)
    To lose                4.1 lb
    Deficit needed       598 kcal/day
    Average daily burn ≈ 2,692 kcal/day
    Budget, average day ≈ 2,094 kcal/day
    Budget, today        1,259 kcal

Every row is now derivable from the two above it:
`4.1 × 3500 ÷ 24 = 598` and `2,692 − 598 = 2,094`. **"To lose" derives
from the basis, not the raw weigh-in** — and the raw number stays
visible both in the Weight field at the top of Goal and in the basis
row's caption, so nothing is hidden.

The "Weight used" row is the basis PICKER from Part 1 (tapping it offers
Last weigh-in / 7-day average), which puts the control at the exact
point where its effect is visible.

### 2b. Rename and colocate

- `Average day` → **`Budget, average day`** — unmistakably a budget.
- `Today` → **`Budget, today`** — parallel with the above.
- `Average burn` → **`Average daily burn`**, MOVED from the Calorie
  budget section up into Daily plan, directly above the budget it feeds.
- The Calorie budget section keeps `Resting burn, full day` and its
  existing explainer.

Register check (CLAUDE.md): "burn" is the user-facing word for
glanceable numbers, which these are — no "energy" substitution. The
2026-08-02 reverted pass is not being re-proposed; these are noun
clarifications, not a burn→energy swap.

### 2c. Total deficit says what it covers

Behaviour UNCHANGED — it stays the number a bad weigh-in can't take away
(untracked days excluded, surplus days subtract). Only the row gains its
scope:

    Total deficit    29,423 kcal ≈ 8.4 lb
                     across 47 tracked days

The day count comes from the same tracked-day set `bankedKcal` already
walks, so this is a plumb-through, not a new calculation.

### 2d. Last 30 days copy

- `-4.3 lb on the scale` → **`on scale`** (the user).
- Drop the `≈` from `≈ -8.2 lb predicted`: the word "predicted" already
  says it is an estimate, and the squiggle on one line but not the other
  implied a precision difference that isn't the real distinction.

### What the user should expect the day this ships

Their own numbers, read off the 08/02–08/08 chart (≈215.4, 216.0, 214.6,
214.3, 215.1, 211.4, 212.2 → basis ≈ 214.1):

    raw      → to lose 2.2 lb → deficit 323 → today 1,535
    smoothed → to lose 4.1 lb → deficit 598 → today ~1,259

**Smoothing COSTS ~276 kcal on the day it lands**, because the last two
readings dropped ~4 lb off the 08/06 peak and the average has not caught
up. That is the honest number — a 4 lb drop in two days is water — but
it is a large, visible change and the user was told before agreeing.
Flagged here so nobody later reads it as a regression.

## Verification

- **Kit tests** (`WeightTrendTests`): a day with morning+evening readings
  yields the morning one; an evening-only day yields that evening
  reading; days are collapsed in the caller's calendar (not UTC);
  windowing takes the last 7 DAYS, not the last 7 readings; empty and
  single-reading inputs return nil / that reading; **the regression this
  is for** — a fixture with two evening weigh-ins in a week produces the
  same basis as one without them, within a stated tolerance, where a
  naive mean over raw samples does not.
- **The arithmetic above is a test.** `(213.4−210)×3500/24 = 496` and
  `(212.2−210)×3500/24 = 321` pin the formula against real observed
  numbers; add them to `CalorieBudgetTests` as a documented case.
- **Cross-surface**: with the setting flipped, Today's deficit and
  `DailyPlanLoader`'s must be equal for the same day — assert directly,
  since this is the drift that matters.
- On device: flip the basis in Goal and confirm Today, the widget, and
  the watch all move together.

## Fallout / open

- **`isAggressive` is evaluated against the deficit**, so a steadier
  basis also steadies the "aggressive plan" warning — an improvement,
  but worth a look that it doesn't flap at the boundary.
- **The sensitivity itself is untouched by this plan.** Smoothing damps
  the INPUT; `3500/daysRemaining` still amplifies whatever comes out,
  and it goes hyperbolic as the target date approaches (700 kcal/lb at 5
  days). If a near-deadline plan still swings unpleasantly, the next
  lever is the deficit's rate of change — a separate decision, not this
  one.
- Onboarding (`OnboardingView.swift:197`) and the Goal PREVIEW read the
  raw latest deliberately: at first run there is no history to average,
  and the preview answers "an average day". Leave both.
- Wiki/site: the user guide describes the daily target; a line about
  which weight it follows belongs there once this ships.

## Order of work

1. Kit: `dailyLows` + `targetBasisLb` + `WeightBasis` + tests.
2. `SharedStore` key, sweep-list registration, tripwire update.
3. `HealthKitService.targetBasisWeightLb()`; route all THREE deficit
   sites and `TodayModel`'s basal weight through it.
4. Goal tab, Part 2 — in this order, because each step makes the next
   one legible:
   a. `Weight used` row + basis picker; `To lose` derives from it.
   b. Move `Average daily burn` up; rename the two budget rows.
   c. `Total deficit` day count; `Last 30 days` copy.
5. Tests, sim pass, device pass across Today/widget/watch.
6. Version bump, release; close OPEN #1 in the handoff notes.

## A note for whoever picks this up

The arithmetic in Part 2 is not decoration. Three of the four
confusions the user raised were "these two numbers look like they should
relate and I can't see how" — and the codebase's two worst copy bugs
(2026-08-02, twice in one screen) were the same failure. When adding a
row here, the test is whether a reader can derive it from the rows above
it. If they cannot, it needs a caption or a different neighbour, not a
better label.
