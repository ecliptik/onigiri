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
>
> **Follow-ups after use on device:**
>
> **v2.19.1** — (a) `Weight used` split into TWO rows, `Based on`
> (the period, and the picker) over `Weight used` (the weight it
> yields); the caption under it is gone, since split the pair explains
> itself and "Based on" covers the last-weigh-in option that
> "7-day average of daily lows" never did. (b) `predicted30Lb` now
> applies the SAME tracked-day filter `bankedKcal` always had — one
> untracked day was adding ~0.7 lb of phantom loss to a row whose whole
> job is to be compared against the scale, so the fiction read as "the
> scale is lagging". Both new tests were CONFIRMED to fail without the
> fix (−1.71 and −1.66 against −1.0), not assumed to.
>
> **v2.19.2** — the new-food form drops its visible title: `Cancel ·
> New Food · Log · Log & Save` read as crowded. Measured first, it
> never truncates (iPhone SE at XXL text lays both out with real
> frames), so this is density, not breakage. The title yields ONLY
> where the confirm pair needs the room — editing keeps "Edit Food"
> and `MealFormView` keeps "New Meal", both single-button bars. A
> nav-bar title is what VoiceOver announces on presenting a sheet, so
> the form keeps a zero-opacity header-trait `Text`; NOT `.hidden()`,
> which removes it from the accessibility tree and defeats the point.
> The rest of the app was audited for the same hole and had none
> (TodayView draws its own headline, PortionSheet announces the food
> name as a section header).
>
> **A test that would have rotted:** it used
> `navigationBars["New Food"]` as its "form is gone" probe. With an
> empty title that predicate goes true INSTANTLY — passing forever
> while guarding nothing, which is precisely the dismissal race its own
> comment describes. It waits on the Name field now.
>
> **Not fixed, and known:** `requiredDeficit`'s sensitivity is still
> `3500/daysRemaining` per pound — 146 kcal/lb at 24 days out, 700 at
> five. Smoothing damps the INPUT; the amplifier is untouched. If a
> near-deadline plan still swings, the next lever is the deficit's rate
> of change, which is a separate decision.

## The observation

A controlled morning experiment (the user, 2026-08-08, screenshots):

(Figures below are illustrative, rebuilt with the same arithmetic on a
synthetic 190 lb target; the user's own readings stay off this page.)

| | 7:40 before weigh-in | 7:41 after | Δ |
| --- | --- | --- | --- |
| Burn (`dayBurn`) | 1,900 | 1,901 | +1 |
| Required deficit | **497** | **323** | **−174** |
| kcal left | 1,403 | 1,578 | +175 |

`1900 − 497 = 1403`, `1901 − 323 = 1578`. Burn did not move. The
entire jump is the deficit target, and the only input that changed was
the weight: 193.4 → 192.2 lb.

## Why — the formula, and its sensitivity

`CalorieBudget.requiredDailyDeficit` (`CalorieBudget.swift:132`):

    requiredDeficit = max(0, current − target) × 3500 / max(1, daysRemaining)

Solving the two data points gives **target ≈ 190 lb, ≈24 days
remaining** — and both readings check out: `(193.4−190)×3500/24 = 496`
and `(192.2−190)×3500/24 = 321`.

So the derivative is:

    d(deficit)/d(weight) = 3500 / daysRemaining

≈ **146 kcal per pound today**, and it GROWS as the target date nears —
292 kcal/lb at 12 days, 700 kcal/lb at 5 days. The nearer the deadline
and the smaller the remaining gap, the more violently each reading
swings the day's allowance.

**This also explains the 2026-08-07 "morning budget jump"**
(OPEN #1 in the handoff notes), which was never a partial Health read.
That note assumed a fixed deficit and concluded the budget had a floor
it could not go below. The deficit is not fixed: the post-weigh-in
budget matched the arithmetic, and the much lower morning figure implies
a stale weight a few pounds higher, which is exactly where the 08-03
peak sits. Same mechanism, no second bug. **Close OPEN #1.**

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
   behind Today's "down N lb this week" line, so the number on screen
   and the number in the math come from one idea.
3. **Setting lives in the Goal tab**, under the Daily plan, where the
   plan already explains itself.
4. **Default: the smoothed basis.** `WeightTrend`'s own doc comment
   already says "the moving average is what goal progress and
   projections should use" — the deficit simply never used it. Past days
   are unaffected: `DeficitTargetHistory` snapshots each day's target, so
   history keeps the bar it was held to.
5. **Display never changes.** Goal keeps showing the real last weigh-in
   (192.2 lb). The app must not report a weight that never appeared on
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
  ○  Last weigh-in      192.2 lb
  ◉  7-day average      192.8 lb
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
| **Average day** | **a BUDGET**: `Average burn − Deficit needed` (2,500 − 323 = 2,177) |
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
(Goal and Details hundreds of kcal apart; "Calorie budget" meaning two
things one screen apart).

Daily plan becomes, in order:

    Weight used          194.1 lb  ›
      └ 7-day average of daily lows (last weigh-in 192.2 lb)
    To lose                4.1 lb
    Deficit needed       598 kcal/day
    Average daily burn ≈ 2,500 kcal/day
    Budget, average day ≈ 1,902 kcal/day
    Budget, today        1,302 kcal

Every row is now derivable from the two above it:
`4.1 × 3500 ÷ 24 = 598` and `2,500 − 598 = 1,902`. **"To lose" derives
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

    Total deficit    N kcal ≈ N lb
                     across N tracked days

The day count comes from the same tracked-day set `bankedKcal` already
walks, so this is a plumb-through, not a new calculation.

### 2d. Last 30 days copy

- `-N lb on the scale` → **`on scale`** (the user).
- Drop the `≈` from `≈ -N lb predicted`: the word "predicted" already
  says it is an estimate, and the squiggle on one line but not the other
  implied a precision difference that isn't the real distinction.

### What the user should expect the day this ships

On the illustrative figures above (a week of readings whose last two
dropped a few pounds off a peak, basis ≈ 194.1):

    raw      → to lose 2.2 lb → deficit 323 → today 1,577
    smoothed → to lose 4.1 lb → deficit 598 → today 1,302

**Smoothing COSTS a few hundred kcal on the day it lands**, because the
last two readings dropped off the peak and the average has not caught
up. That is the honest number — a multi-pound drop in two days is water — but
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
- **The arithmetic above is a test.** `(193.4−190)×3500/24 = 496` and
  `(192.2−190)×3500/24 = 321` pin the formula against observed-shape
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
