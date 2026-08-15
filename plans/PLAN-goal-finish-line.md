# PLAN — the finish line (2026-08-14)

## Why

Aug 14, the morning weigh-in came in at 209.8 against a 210 target. One
screen said four different things at once:

- **Progress: 8.9 of 8.7 lb**, bar full — done, and then some.
- **"On this trend, you'll hit your target between Aug 19 and Aug 24"** —
  five to ten days out.
- **"Target must be below your current weight."** in orange — a form
  error, i.e. the goal is malformed.
- **No "You hit your target" card on Today** — not there yet.

None of them is a bug on its own. Each reads a DIFFERENT weight, and the
screen never says which:

| Surface | Weight it reads | Where |
| --- | --- | --- |
| "Current weight — From Apple Health" | raw last weigh-in | `GoalModel.healthWeightLb` |
| "Target must be below…" | raw last weigh-in | `GoalUpsert.validate`, via `currentWeightLb` |
| Progress bar / "8.9 of 8.7 lb" | raw last weigh-in | `GoalProgress.resolve(currentWeightLb:)` |
| The celebration (Goal + Today) | mean of last 7 days' daily LOWS, ≥3 weigh-in days | `GoalCompletion.evaluate` |
| The daily budget (Today, widget, watch) | mean of last 7 days' daily lows | `HealthKitService.targetBasisWeightLb` |
| The chart's blue line | trailing 7-day mean over RAW samples | `WeightTrend.movingAverage(weightHistory)` |
| The projection window | recency-weighted fit over RAW samples, 21 d | `GoalTrendStats.derive` |

That's three notions of "now" — raw, daily-low average, fitted — and the
one the user is judged by (daily-low average) is the one shown only
inside a COLLAPSED disclosure ("How budget is set" → Weight).

`GoalView.swift:70` already ruled that the deficit chain must not mix the
raw reading with the average, "the same 'one label, two numbers' failure
that hit this screen twice on 2026-08-02" — and deliberately left
validation on the raw reading. That exception is what produced this. The
ruling was right; its scope was too narrow. **Anything that reaches a
VERDICT about where you are runs on the sustained basis. Only the
"Current weight" row, which reports a measurement, stays raw.** Same
split the app already draws between `DayBudget.deficit` and
`DailyEnergySummary.balanceKcal`.

## What is actually wrong

### 1. The finish line is rendered as a form error

`validate` has one failure mode for two completely different situations:
someone typing a target 20 lb ABOVE their weight (a mistake), and someone
whose scale has just crossed their target (an arrival). Both get
"Target must be below your current weight." in orange.

### 2. There is no way to continue the journey before the celebration fires

`continueGoal` is the only save path that passes `GoalUpsert.StartChange.keep`,
which preserves the journey start. It is rendered only inside
`if goalReached` (`GoalView.swift:675`). So at 209.8 against a 210 target
the "Keep going · 5 lb more / 10 lb more" chips do not exist, and the only
route to a 200 target is hand-editing the field — which takes the
`targetChanged` branch in `GoalUpsert.save:97`, re-stamps the start to
today at the RAW last weigh-in, and re-zeros a bar that read 8.9 of 8.7.

### 3. The Goal screen's budget rows vanish exactly at the finish line

`plan` is nil when `target >= planWeightLb` (`GoalView.swift:238`). When
the basis crosses 210 that takes out the whole "Today — Budget / Burn"
section AND, through `hasProgressTotals`, "Total deficit" and
"Last 30 days". Meanwhile Today keeps rendering a budget, because
`requiredDailyDeficit` clamps at `max(0, …)` and returns 0, so
`DailyPlanLoader` produces `budget = full dayBurn`. Two screens, one
goal, one shows a budget and the other shows nothing.

### 4. The badge rule loosens silently

Deficit target 0 → `DayBadgeRule.current` returns `.anyDeficit`
(`StreakCalendar.swift:30`), which grades MORE permissively than either
real mode. `GoalReachedCard`'s two-week re-arm exists precisely because
"that drift is otherwise invisible forever" — but nothing on screen ever
says it happened.

### 5. The chart's line is the only weight series computed from raw samples

Everything that judges uses daily lows; the drawn line does not. Two
consequences:

- The right-hand end of the blue line does not equal any number on the
  screen — not the 209.8 above it, not the basis under "How budget is
  set". It sits between them.
- Days with two weigh-ins pull the line up, days with one don't. The
  line partly measures WHEN you weighed. This is the exact hazard
  `WeightTrend.dailyLows` was written for ("a mean over RAW samples
  measures weighing habits as much as body mass") — the budget got the
  fix, the chart never did.

### 6. The axis is set by the noisiest readings

`chartYDomain` is `min(raw) − 2 … max(raw) + 2` over 90 days plus the
target. Evening weigh-ins (2–3 lb high, per `dailyLows`' own doc) stretch
it at the top; a lower target stretches it at the bottom. Moving the
target 210 → 200 grows the axis from ~13 lb tall to ~23 lb and visually
flattens the whole trend, with no change to the data.

### 7. The deficit is hypersensitive this close to the date

`requiredDailyDeficit = max(0, basis − target) × 3500 / daysRemaining`.
At 18 days out that is **194 kcal/day per pound** of basis. So the budget
swings by most of a snack on scale noise alone, then falls off a cliff to
0 the moment the basis touches 210. `WeightTrend.swift:148` already
documents this sensitivity; nothing acts on it.

## The model

Three states, not two, and one weight behind all of them — the sustained
basis (`GoalCompletion`'s daily-low mean, the same one the budget rides):

```
basis > target + band     →  under way   (today's screen, unchanged)
basis within band         →  APPROACHING (new)
basis <= target, ≥3 days  →  reached     (celebration, unchanged)
target > basis + band     →  error       (a real mistake, unchanged)
```

`band` is the scale's own noise floor for a week-scale readout — reuse
`GoalTrendStats.steadyDriftThresholdLbPerWeek`'s spirit, but as a weight:
**1 lb**, one place in the kit, named.

The APPROACHING state is the whole point. It is what today's screen has
no vocabulary for, and it is where a user actually spends the last week
of a goal.

## The work

### A. `GoalFinishLine` (kit, new, pure, tested)

One type that answers "where is this goal", replacing the boolean pair
`validation == .targetNotBelowCurrent` / `goalReached`:

```swift
public enum GoalFinishLine: Equatable, Sendable {
    case underWay
    case approaching(basisLb: Double, remainingLb: Double)
    case reached(GoalCompletion)
}
```

Derived from `(targetLb, history, now)`. It runs `GoalCompletion.evaluate`
once and reads its `basisLb`, so it cannot disagree with the celebration
— same rule, same window, same widening.

**Built with three cases, not the four this plan first drafted.** The
fourth, `targetAboveCurrent`, would have had no producer: a target typed
above where you are is a statement about the FORM, not about the goal's
progress, and `GoalUpsert.validate` already owns it. Moving it here would
have split one question across two types. `validate` instead moves onto
the basis (§B), which is what actually made it agree with its neighbours.

**And no `weighInDaysNeeded`.** The draft assumed you could be at target
by weight but short on weigh-in days, and report the shortfall. You
can't: `GoalCompletion.basisLb` is non-nil *only* when the day count is
already satisfied, so that number is always 0. The honest actionable
figure is `remainingLb` — how far the average still has to come down —
plus naming the rule in the copy. `basisLb` rides along because the state
has to be able to SAY which weight it means; that is the entire defect.

### B. Goal screen: the error becomes a state

`targetSection` switches on `GoalFinishLine` instead of chaining
`goalReached` / `validation`:

- `.reached` — today's celebration, unchanged.
- `.approaching` — a green (not orange) line: *"Your 7-day average is
  210.8 lb — 0.8 lb from your target. Three weigh-in days in a week
  averaging 210 lb or less finishes it."* Plus the **"Keep going" chips,
  shown here too** (fix for §2). No orange, no "must".
- `.underWay` — the existing orange warning when `validate` refuses,
  now only for actual mistakes; the "enter a target" hint otherwise.

Save stays gated on `validate`, but `validate` moves onto the basis so it
agrees with the line above it. Note the deliberate reversal of
`GoalView.swift:70`'s carve-out — write the reason into that comment, do
not silently drop it.

### C. Continuing a journey stops being celebration-only

Two halves:

1. The chips render in `.approaching` as well as `.reached` (above).
2. A hand-edited target that moves DOWN keeps the journey. New kit
   function beside `GoalProgress`, tested:
   `JourneyContinuity.startChange(oldTargetLb:newTargetLb:progressLb:)` —
   `.keep` when the target moves down and the current journey has
   ≥ `GoalProgress.minimumJourneyLb` behind it, `nil` (re-stamp) when it
   moves up or there is no journey to preserve. `GoalUpsert.save` keeps
   its existing re-stamp rule for every other case; only GoalView's
   `startChange` computation changes.

   Rationale: a target moved down is the same journey with a further
   destination, which is what the `.keep` path was built for. A target
   moved UP is a reset, and re-stamping is right.

   Ordering matters, and the draft had it wrong: an explicit start edit
   (`startEdited`) is tested BEFORE the lowered-target rule, or a start
   the user steered themselves gets silently overruled by an inference.

### D. The plan survives the finish line

`CalorieBudget.derivePlan` already returned a zero-deficit plan when
`target >= current` — `requiredDailyDeficit` clamps at `max(0, …)`. The
`nil` came from GoalView's own `target < current` guard, so THAT is what
goes, and it is the whole change. Then:

- Goal's "Today — Budget / Burn" rows stay put and agree with Today.
- `hasProgressTotals` gates on a non-nil plan, which is now satisfied at
  the finish line, so "Total deficit" / "Last 30 days" stay readable at
  the moment someone comes looking for them. No edit needed there.

Check `DailyPlanLoader` and `PlanCache` need no change — they already
clamp at `max(0, …)` and produce `budget = dayBurn`. This is Goal
catching up to them, not a model change.

### E. Say the badge rule loosened

At `.reached` (and at deficit 0 generally), the Goal screen states it in
the Today section's footer: *"You're at your target, so today's budget is
your full burn — any deficit earns the day."* One sentence, where the
budget it describes already is. This is the `GoalReachedCard` re-arm's
reason, made visible instead of inferred.

### F. The chart draws what the app judges

- **Blue line:** `WeightTrend.movingAverage(WeightTrend.dailyLows(history), 7)`.
  Acceptance criterion, and it is a sharp one: **the right-hand end of
  the blue line must equal the "Weight" figure under "How budget is
  set"**, to the digit. Today it does not, and no test would have caught
  that.
- **Scatter:** stays raw — showing what the scale actually said is
  correct and it is the honest backdrop for a smoothed line. But mark
  the daily low distinguishably (full opacity vs 0.2 for the rest), so
  the cloud reads as spread around the line rather than as the data.
- **Y domain:** the daily lows plus the target set the scale, padded by
  `domainPadLb` (2). The raw cloud is then let back IN — points that
  clip read as missing data — but no further than
  `WeightTrend.sameDayRiseLb` (3) past the lows. So a normal evening
  weigh-in stays in frame and a fat-fingered one can't flatten a month
  of trend. Shipped this way rather than letting the cloud clip
  outright, which the draft proposed.
- **Target change:** NOT capped. The draft wanted to stop a distant
  target stretching the axis, but every way of doing it either clips the
  target line out of the chart or hides how far there is to go — and
  "here's the distance" is what that line is for. A 200 lb target on a
  210–219 history draws a ~23 lb axis, and that is the honest picture.

### G. Blunt the near-date cliff

Inside the band, the deficit is 0 — no jitter, no cliff, no 194 kcal/day
swings on water weight. `requiredDailyDeficit` takes a `bandLb` and
returns 0 when `basis − target < bandLb`. Everything at or above the band
is unchanged, which is why `WeightBasisTests`' documented
3500/daysRemaining sensitivity (measured at exactly 1 lb) still holds.

The band lives in `requiredDailyDeficit` and NOT in the UI, deliberately:
Today, the widget, the watch and the snapshots `DeficitTargetHistory`
stamps for past days all come through that one function, and a band
applied anywhere else would be a fourth weight rule — the exact class of
bug this plan exists to remove.

## Tests

Kit, pure, beside the existing `GoalCompletionTests` /
`GoalProgressTests` / `GoalTrendStatsTests`:

- `GoalFinishLine` — each of the four states, at the boundaries, and the
  widened-window case (a weekly weigher approaching a target).
- The Aug 14 fixture verbatim: start 218.7, target 210, raw latest 209.8,
  daily lows averaging just above 210 → `.approaching`, NOT
  `.targetAboveCurrent`, NOT `.reached`. This screen is the regression.
- `JourneyContinuity.startChange` — down/up/no-journey.
- `derivePlan` at and below target → zero-deficit plan, not nil.
- The chart-line/basis identity: `movingAverage(dailyLows(h), 7).last ==
  targetBasisLb(h)` for a history with mixed morning/evening readings.
  This is the one that would have caught §5.

## What is NOT in scope

- Re-opening the raw-vs-average choice for the "Current weight" row. It
  reports what the scale said and stays raw. The fix is that nothing
  ELSE reads it.
- Changing the projection's fit input. `GoalTrendStats.swift:133`
  records that fitting the smoothed series was tried and rejected on
  2026-07-31 for erasing real trend changes — that ruling stands and is
  about the FIT, not about the drawn line.
- A new "you're nearly there" notification or card on Today. The
  approaching state belongs on Goal, where the decision it invites
  (keep going / maintain) lives. Today already has one celebration card
  and `GoalReachedCard`'s doc is explicit that more cards make the
  target stop feeling like an arrival.
