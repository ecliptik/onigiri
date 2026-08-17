# Beyond the scale — what the budget and goal model can't currently say

Review opened 2026-08-16 against v2.22.0, prompted by the JACC
central-adiposity paper and its Hacker News thread. This is a **review and
proposal document**, not a commitment: everything below is a finding plus a
recommendation, and the sequencing section at the end says which parts are
worth doing and which are deliberately parked.

## Sources, and what they actually say

**The paper.** Dardari et al., *Risk Reclassification Beyond BMI by Waist
Circumference and Waist-to-Hip Ratio Across Nine Cardiovascular Outcomes:
Results from the Cross-Cohort Collaboration*, JACC, published 2026-08-11
([PMC13470613](https://pmc.ncbi.nlm.nih.gov/articles/PMC13470613/)).
260,959 participants across 15 cohorts, median 20.0 years of follow-up
(IQR 12.7–23.5), nine cardiovascular outcomes.

- Cutoffs: WC ≥88 cm (female) / >102 cm (male); WHR ≥0.85 / >0.90.
- Among **normal-weight** people, 5% had high WC and 18% had high WHR.
  Among **overweight**, 39% / 40%. Among people **with obesity**, 9% had
  low WC and **45% had low WHR**.
- Normal-weight people with high central adiposity carried HRs of roughly
  **1.15–1.50** across most outcomes.
- Conclusion, verbatim: "WC and WHR identifies misclassification of
  conventional BMI categories and reclassifies CVD risk across normal
  weight, overweight, and obesity, adding diagnostic and prognostic value."

**The thread.** [HN 49314403](https://news.ycombinator.com/item?id=49314403),
321 points, 268 comments. Worth being honest about what it is: the thread is
overwhelmingly about **BMI versus body composition**, not about calorie
math. Nothing in it says anything about the app's budget arithmetic. The
parts that bear on Onigiri:

- The near-consensus that BMI is a population screener that fails
  individuals in a specific direction — it cannot tell fat from muscle and
  says nothing about *where* the fat sits. One commenter cites the 2025
  Lancet Commission on clinical obesity recommending BMI be used only as a
  population-level surrogate, with individual assessment confirmed by waist
  measurement or direct body-fat measurement. (That is a commenter's
  citation, not this paper's finding — treat accordingly.)
- **Waist-to-height** was repeatedly favoured over waist-to-hip on
  practical grounds: one measurement instead of two, and the rule of thumb
  ("keep your waist under half your height") needs no table.
- **Measurement protocol is the actual obstacle**, stated plainly by GuB-42:
  "I don't even know how to make a waist measurement. Where exactly? How
  relaxed should the subject be? How long after eating?" And sn9's answer:
  "You want to make sure you measure under similar conditions, like in the
  morning after relieving yourself."
- A calorie sub-thread, which is where the app's own subject matter shows
  up. Two claims worth taking seriously and one worth resisting:
  - *"the reason people fail with it is not because calorie counting doesn't
    work, but because people's maintenance calorie estimates are often
    poor… your maintenance calories often shift downward as you progress"*
    (faangguyindia).
  - *"calorie restriction can cause a reduction in resting metabolic rate
    through metabolic adaptation… by shedding metabolically active tissue"*
    (someothherguyy, citing PMC9036397).
  - *"The average person eats 19 calories a day more than they need to"*
    (rootusrootus) — repeated twice as the thread's rebuttal to
    willpower framing. Whether or not the figure survives scrutiny, the
    *shape* of it matters: the quantity that decides a year is far below
    the resolution of anything the app measures.
  - The one to resist: sn9's *"losing ~0.5–1 lbs per week while strength
    and endurance training"* is offered as advice. Onigiri does not give
    advice. It can, however, tell you what pace your own settings have
    actually asked for, which it currently does not.

## What Onigiri does today

Established by reading, not memory:

- **Day budget** = `DayBudget.dayBurn − requiredDeficit`, where `dayBurn`
  is `active + max(measuredResting, BasalEstimate.restingKcal)`
  (`DayBudget.swift:48`). Resting is credited up front from midnight;
  active is earned.
- **The resting floor** is Mifflin–St Jeor over total body weight, height,
  age and sex, with no activity multiplier (`BasalEstimate.swift:38`).
- **The deficit target** is `(current − target) × 3500 / daysRemaining`,
  zeroed inside a 1 lb band (`CalorieBudget.swift:139`). 3500 kcal/lb is
  also the conversion behind `predicted30Lb`, `bankedLb`, and the
  `paceBoostKcalPerDay` line on Goal (`WeightTrend.Change`,
  `GoalTrendStats.swift:160`).
- **Guardrails** are two absolute constants: deficit > 1000 kcal/day or
  budget < 1500 kcal flips `isAggressive` (`CalorieBudget.swift:9,12,163`).
- **The verdict weight** is the 7-day mean of daily lows
  (`WeightTrend.targetBasisLb`), per the rule in CLAUDE.md that anything
  reaching a verdict runs on the sustained basis.
- **Body composition is entirely absent.** `readTypes` covers energy,
  body mass, height, date of birth and sex (`HealthKitService.swift:47`).
  No waist, no body fat, no lean mass. Weight is the only thing the goal
  model can see, and therefore the only thing it can judge.

## Findings

### F1 — Two call sites floor resting off the RAW weigh-in (defect)

CLAUDE.md's weight rule says every verdict-shaped number runs on the
sustained basis. Two of the four `BasalEstimate` call sites don't:

| Call site | Weight fed to `BasalEstimate` |
|---|---|
| `TodayModel.loadStatic` (`TodayModel.swift:203`) | `targetBasisWeightLb()` ✅ |
| `DailyPlanLoader` (both paths, `:240`, `:293`) | `targetBasisWeightLb()` ✅ |
| `GoalModel.loadIfStale` (`GoalModel.swift:100`) | `latestBodyMassLb()` ❌ |
| `HealthKitService.dailyEnergyTotals` (`:865`) | `latestBodyMassLb()` ❌ |

The resting estimate is a whole-day figure and measured basal accrues
through the day, so the estimate wins the `max` for most of the day — which
means this is live most of the time, not an edge case. Mifflin–St Jeor's
weight term is 10 kcal/kg, so a 3 lb evening weigh-in moves the floor by
~14 kcal/day.

Small, but the sign is wrong in exactly the way the basis rule exists to
prevent: an evening weigh-in *raises* the budget. And `dailyEnergyTotals`
is the figure the calendar, badges, streaks and `bankedKcal` all read, so
Today and the calendar can disagree about a day's burn — the precise
failure `alignedDaySummary` was built to end. **Two-line fix, and the
existing `PlanWeightSyncTests`/`WeightBasisTests` are the right home for
the regression.** Do this one regardless of what else on this page happens.

### F2 — `readTypes` growth is currently a widget regression (blocker)

`PlanCache.needsSetup()` is `shouldRequestAuthorization()`, which is
`statusForAuthorizationRequest(toShare:read:) == .shouldRequest` over the
*whole* `readTypes` set (`PlanCache.swift:101`, `HealthKitService.swift:68`).
CLAUDE.md already records what that costs: adding a type flips it true for
every existing install until the user is re-prompted, so **every widget and
complication paints "Open Onigiri to set up" over a working setup.** That
was the recorded reason `HKWorkoutType` was rejected for the burn observer.

Every data-side idea below needs a new read type, so this is the
prerequisite for all of them, and it is worth fixing on its own merits —
the current shape means the app can never add a Health type again without
a visible regression.

**Proposed shape:** split *what we request* from *what proves setup*.
`needsSetup` should ask `statusForAuthorizationRequest` about a small,
frozen CORE set (the dietary share types plus `activeEnergyBurned` read) —
the types without which a widget genuinely cannot render — while
`requestAuthorization` keeps asking for everything. Optional reads then
cost nothing when absent and are never load-bearing. This wants a comment
naming the regression it prevents, and a test that pins the core set
against accidental growth.

### F3 — The guardrails are absolute where the risk is proportional

`maxSafeDailyDeficit = 1000` and `minReasonableBudget = 1500` are the same
numbers for everyone. 1000 kcal/day is ~2 lb/week: about 0.67%/week for a
300 lb body and over 1.5%/week for a 130 lb one. The conventional
sustainable band is expressed as a *fraction* of body mass for exactly this
reason, and the fraction is what predicts lean-mass loss.

More directly: **the app never compares the budget to the resting estimate
it already computes.** It knows `BasalEstimate.restingKcal` and it knows
`dayBurn − deficit`, and a budget below resting is the actual red line —
far more meaningful than a flat 1500. That comparison costs nothing; both
numbers are already on the Goal screen, two rows apart.

Recommendation: keep the absolute constants as a floor, add a
proportional check (`deficit × 7 / 3500` as a percentage of the basis) and
a below-resting check, and route all three through the existing
`isAggressive` flag so no surface has to learn a new state. What the app
must NOT do is start prescribing a pace — `isAggressive`'s existing copy
already says the fix is a later target date, which is the right register.

### F4 — 3500 kcal/lb is used for two different jobs, and only one is fine

The constant appears as `CalorieBudget.kcalPerPound` and again as
`WeightTrend.Change.kcalPerLb`. Two jobs:

1. **Setting the deficit target.** Fine. It is a planning convention;
   whether the number is exactly right barely matters, because the target
   is re-derived every day from a fresh basis weight. Errors don't
   accumulate — the feedback loop closes.
2. **Predicting the scale.** Not fine, and the app already surfaces the
   symptom. `GoalTrendStats.predicted30Lb` converts 30 days of banked
   deficit into pounds and sits next to `actual30Lb` for comparison. A
   linear 3500 systematically over-predicts loss over a month, because the
   burn side falls as mass falls and the tissue lost is not pure fat. Which
   means **the row is built to read as "the scale is lagging" when the
   arithmetic was optimistic from the start.**

The row today is `Last 30 days` over two lines — "−3.2 lb predicted" /
"−2.1 lb on scale" (`GoalView.swift:362`), and its own comment records that
Calendar's month detail carries the identical pair. So this is a
two-surface change under the same rule as the Today/widget burn labels:
change them together or they disagree.

The honest fix is not a better constant — it's to say what the row is. Two
options, and the second is better:

- Swap in a decaying model (Hall's dynamic model, or the crude
  "~10 kcal/day of maintenance per pound lost" adjustment). Rejected: it
  imports a whole physiological model, its parameters can't be validated
  from anything the app measures, and the plan doc it would need is longer
  than the feature.
- **Keep the arithmetic, fix the framing.** `predicted30Lb` is "what the
  textbook conversion says your logged deficits are worth", `actual30Lb` is
  "what the scale did". The gap is *information* — it is, in effect, a
  measurement of the individual's own adaptation — and the app currently
  presents it as a discrepancy to be troubled by. This is a copy and
  labelling change, not a math change, and it is the single highest
  value-per-line item on this page.

### F5 — Nothing observes maintenance; everything predicts it

This is the thread's strongest point applied to the app. `BasalEstimate` is
a *predictive equation* — the population's answer for a body of this size —
and `dayBurn` adds measured active energy to it. Nowhere does the app ask
the question it has the data to answer: **given the intake actually logged
and the weight actually recorded, what maintenance level is this body
demonstrating?**

Over a 30-day window the app holds mean daily intake and a fitted
lb/day slope (`WeightTrend.recencyWeightedFit`, already computed for the
projection). Observed maintenance is then
`meanIntake + slopeLbPerDay × 3500`, and comparing it to `dayBurn` gives an
adaptation figure the user's own data earned.

Attractive, and I am **not** recommending it be wired into the budget.
Three reasons:

- It multiplies the scale's noise by 3500. A 0.05 lb/day fit error is
  175 kcal/day. The projection can absorb that because it is quantized to a
  5-day grid and clearly framed as a forecast; a *budget* cannot.
- It depends on complete logging. `StreakCalendar.isTracked` exists because
  under-logged days are common, and this estimator inherits every one of
  them as a maintenance figure that is too low — which would then *raise*
  the budget. Wrong direction, silently.
- It re-opens something already settled. Substituting a derived burn figure
  for the measured one is exactly what the trailing-average model did, and
  `PLAN-earned-budget.md` records why it was deleted. Feeding an *observed*
  average back into the budget is the same shape wearing different clothes.

What it is genuinely good for is **a read-out, on Goal, beside the
predicted-vs-actual row**, gated behind a real tracked-day count (30+
tracked days in the window, say — reuse `StreakCalendar.isTracked` and
`bankedDays`, which already exists for exactly this kind of honesty). It
answers "is my body burning what the equation thinks it does" without
letting the answer touch a verdict. Same discipline as the basis rule:
measurements report, verdicts judge, and these are not the same job.

### F6 — DECLINED 2026-08-16: waist as a tracked measure

**The user does not take waist measurements and would not take them
regularly. That settles it — the rest of this section is kept as the
reasoning, not as a queue item.** A chart series and a Goal row fed by
nothing are worse than their absence: the row reads "—" forever, the chart
gains an axis it never uses, and the measurement-protocol copy below would
be advice nobody acts on. Don't re-propose without new data actually
arriving in Health first.

The paper's finding still stands and is worth knowing — it is simply a
finding about a metric this app has no way to observe. What survives from
it is F6c's rule, which is now hypothetical, and the general principle it
expresses (sparse hand-entered series report; dense automatic ones may
judge) which is already carried by the weight-basis rule in CLAUDE.md.

<details>
<summary>Original analysis, kept for the record</summary>

#### The goal model can only see one number, and it's the wrong one for the question the paper asks

This is where the paper lands. Onigiri's entire goal apparatus —
`GoalProgress`, `GoalCompletion`, `GoalFinishLine`, the chart, the
celebration, the milestones — is a function of scale weight. The paper's
finding is that scale weight (via BMI) misclassifies a large minority in
both directions: 18% of normal-weight people had high WHR; **45% of people
with obesity had low WHR.**

Three consequences, in ascending order of how much they'd change:

**F6a — A waist reading has nowhere to live.** HealthKit has (identifier
never verified against the SDK — the feature was declined first)
`waistCircumference` (Body Measurements in the Health app; verify the
identifier against the current SDK before building). The app could read it
and never write it, exactly as it already treats `height` — one sentence in
the read-types comment covers the precedent. The minimum useful version is
a row on Goal: latest waist, and waist-to-height as a ratio. WHtR over WHR
deliberately: one measurement instead of two, height is already read for
`BasalEstimate`, and it was the thread's own practical preference.

The measurement-protocol problem is real and is a *copy* problem, which is
this project's strong suit. One line under the row, in the formal register
per the Copy rules: same spot each time, before eating, at the end of a
normal breath. It is the same discipline `dailyLows` already encodes for
weight — pick the comparable reading, don't average incomparable ones.

**F6b — A waist trend is a better progress signal than the app currently
has, during exactly the periods when weight lies.** The recorded failure
modes of a weight-only chart — a plateau that isn't one, water weight
swinging the last pound hard enough to need `GoalFinishLine.bandLb` — are
periods when a tape measure keeps moving. Charting waist alongside weight
costs one series.

**F6c — Should waist reach a verdict?** No, and this needs stating before
someone tries it. `GoalCompletion`, `GoalFinishLine`, the deficit target
and the celebration must stay on weight alone. Weigh-ins arrive daily and
automatically from a scale; waist readings arrive when someone remembers a
tape measure. A verdict on a sparse, hand-entered, high-variance series
would be the raw-weigh-in mistake of 2026-08-14 with worse data. Waist
reports; weight judges. Write that rule down in CLAUDE.md at the same time
the feature lands, or it will be re-litigated.

</details>

### F7 — Body fat / lean mass would improve the resting floor, for the people who have it

Mifflin–St Jeor over total mass is the best of the equations that only know
height and weight, and it errs in a known direction: it under-predicts for
lean bodies and over-predicts for fat ones — the same failure mode as BMI,
for the same reason. Katch–McArdle (`370 + 21.6 × leanBodyMassKg`) does
better *when lean mass is known*, and smart scales routinely write
`bodyFatPercentage` to Health.

Worth doing only under conditions:

- Strictly opportunistic. `BasalEstimate.restingKcal` keeps its current
  signature and behaviour; a *separate* entry point takes lean mass and is
  used only when Health has a recent reading. Nothing regresses for anyone
  without a smart scale, which is the common case.
- Bioimpedance body fat is not accurate in absolute terms. It is, however,
  reasonably *consistent* for one person on one scale, which is what a
  resting estimate needs — and the estimate is only a floor under a
  measured value in the first place, so its blast radius is already small.
- The budget would move for these users when it lands. That is a real,
  visible change to a number people watch daily, and it needs to be the
  kind of change the Goal screen can explain in a row — which the "How
  budget is set" section is already built to do.

Lowest priority on this page. It is the most physiologically interesting
item and the least likely to change anyone's day.

## What this review does NOT propose

Recorded so it doesn't come back:

- **No BMI anywhere.** The paper's whole argument is that BMI adds nothing
  once you have weight and a waist measurement, and the app already has the
  first and would have the second. Displaying it would be adding the metric
  the source says to stop relying on.
- **No health advice.** Not target waists, not "you should lose 0.5–1 lb a
  week", not risk categories. The paper's cutoffs are population screening
  thresholds against cardiovascular endpoints; rendering "you are at
  elevated risk" from a tape measure is a different product and a
  regulatory question. Show the number and the trend; the user brings the
  interpretation. `isAggressive`'s existing register — "the fix is a later
  target date" — is the ceiling for how prescriptive anything here gets.
- **No return of a derived or averaged burn in the budget** (F5). Settled
  in `PLAN-earned-budget.md`; observed maintenance is a read-out only.
- **No dynamic weight-loss model** (F4). Rejected above with reasons.
- **No re-opening** of the today-floor on the projection, the Fixed budget
  style, or the raw-weight exception for verdicts. All three are recorded
  losses in CLAUDE.md.

## What any of this does to the numbers

Asked 2026-08-16 and worked here so it doesn't get re-derived. Worked
against the seeder's reference body — 178 cm, 40 years, ~200 lb, sex
unspecified (`HealthKitService.swift:1307`) — because it is the one body in
the repo with published figures to check against (CLAUDE.md's "Resting burn
≈ 1,743 kcal/day"; the equation gives 1,741.7).

**The structural point first.** `BasalEstimate` enters as a FLOOR:
`dayBurn = active + max(measuredResting, estimate)`. So every body-metric
change below bites only while the estimate is winning that `max`. That is
not a narrow window — a real full-day measured basal for this body lands
near 1,742, so the estimate governs most of the day and on a light day all
of it. But it does mean a completed, watch-worn day is usually immune,
which is why calendar-wide totals move far less than a per-day delta
suggests.

| | Budget | Deficit target | Banked / predicted | What changes |
|---|---|---|---|---|
| **F1** (done) | ±2–14 kcal | — | ≤0.04 lb | Resting floor rides the basis |
| **F2** (done) | — | — | — | Nothing; authorization scoping only |
| **F3** | — | — | — | `isAggressive` fires in more cases |
| **F4** | — | — | — | Label on an existing number |
| **F5** | — | — | — | Adds a read-out |
| **F7** | **±100–200 kcal** | — | — | Resting floor swaps equations |

**F1.** Mifflin–St Jeor's weight term is 10 kcal/kg = **4.54 kcal/lb**. An
evening weigh-in 3 lb above the basis was inflating the floor by 13.6
kcal/day; the common case (a morning low ~0.5 lb under the 7-day mean on a
downward trend) is +2.3 kcal/day the other way. Calendar-wide it is smaller
still, since a worn day's measured basal usually exceeds the estimate and
the floor never applies — banked moves well under the 0.1 lb the readout
can display. The point was agreement between Today and the calendar, not
magnitude.

Note the side effect: `dailyEnergyTotals` now calls `targetBasisWeightLb()`,
which writes `cachePlanWeight`. It writes the same value the other three
sites write, so no number changes — but the plan-weight cache (which the
watch push reads) now refreshes from calendar and widget paths too. The
weight read runs concurrently with `bodyProfile()`, which was previously
serial, so round-trips are roughly a wash.

**F2 moves nothing.** No figure in the app is derived from the
authorization sets. The only behavioural change is that `needsSetup` can
now answer false where it would have answered true after a future type
addition — which is the entire feature.

**F3 widens a warning band and computes nothing.** `isAggressive` is a Bool
consumed at exactly three view sites (`TodayView.swift:2067`,
`OnboardingView.swift:242`, `GoalView.swift:322`), all warning banners.
Adding the below-resting check moves this body's threshold from
"budget < 1,500" to "budget < 1,742", so a 1,600 kcal budget starts warning
where it passes silently today.

Worth knowing before building the proportional half: at 200 lb the existing
flat 1,000 kcal cap ALREADY equals 1.0%/week. The proportional check only
binds at lighter bodies (1.54%/week at 130 lb) and only relaxes at heavier
ones (0.67%/week at 300 lb). **For this user it changes essentially
nothing** — the below-resting check is where the value is, and it may be
worth shipping that alone.

**F4 moves nothing.** 3500 stays exactly where it is; only the words around
`predicted30Lb`/`actual30Lb` change.

**F5 adds a number and changes none.** `maintenance = meanIntake − slope ×
3500`. On the seeder's −0.067 lb/day trend that is intake + 233 kcal. Its
noise is the whole argument for keeping it off the budget: a 0.01 lb/day
slope error is 35 kcal/day, and 0.05 lb/day is 175 kcal/day.

**F7 is the only real mover.** Katch–McArdle is `370 + 21.6 × LBM(kg)`:

| Body fat | Katch–McArdle | Δ vs Mifflin's 1,742 |
|---|---|---|
| 20% | 1,938 | **+196** |
| 25% | 1,840 | +98 |
| 30% | 1,742 | ≈ 0 |
| 35% | 1,644 | −98 |
| 40% | 1,546 | **−196** |

The equations cross at ~30% body fat for this body and diverge **98 kcal
per 5 percentage points**. Below 30% the budget gets BIGGER — right
physiologically, but it will read as the app becoming generous, and it
moves daily as the body-fat reading does. That is what makes F7 the item
needing a row in "How budget is set" to explain itself, and the one to hold
longest.

## Status

- **F1 — DONE 2026-08-16.** Both raw-weight call sites now floor the
  resting estimate from the basis: `HealthKitService.dailyEnergyTotals`
  reads `targetBasisWeightLb()` (concurrently with `bodyProfile()`, which
  it previously awaited in series), and `GoalModel.loadIfStale` uses the
  `basisWeightLb` it already computes. The Weight field and validation
  still show the raw weigh-in — those report a measurement.
- **F2 — DONE 2026-08-16.** `shouldRequestAuthorization` now asks about a
  frozen `setupCoreShareTypes`/`setupCoreReadTypes` (dietary energy;
  active and basal burn) instead of the full sets.
  `requestAuthorization` is unchanged and still asks for everything.
  `HealthAuthorizationScopeTests` pins the three invariants: the core is a
  subset of what we actually request, the core is frozen, and the full
  read set stays wider. **A new optional Health read type is now a safe
  change** — that was the whole point.
- **F3 — DONE 2026-08-16, below-resting half only.** `plan`/`derivePlan`
  take an optional `restingFloorKcal`, and `isAggressive` now tests
  `budget < max(minReasonableBudget, restingFloorKcal ?? 0)`. Both floors
  are kept: the estimate is nil whenever Health can't describe the body,
  and a guardrail that vanishes with its input is not a guardrail. nil
  reproduces the old behaviour exactly, which is its own test. Goal passes
  `model.estimatedRestingKcal`; onboarding passes nothing, because it never
  reads `bodyProfile` at all — it keeps the flat floor, which is honest for
  a screen that runs before any body read.

  **The proportional half was NOT built and should not be**, per the
  numbers above: at ~200 lb the existing flat 1,000 kcal cap already sits
  at 1.0%/week, so it would change nothing for this user while adding a
  threshold the app effectively asserts.

- **DEFECT found while wiring F3 and fixed the same day: Today's pace
  warning could never render.** `DailyGoalCard` read `plan.isAggressive`,
  but its plan comes from `plan(for:)` → `completedDayPlan`, which
  hardcodes `isAggressive: false` ("a past day can't be talked out of what
  it already was" — correct, and it also silenced today). So the warning
  on the DEFAULT TAB had never once appeared, while the same sentence on
  Goal worked fine, which is why it went unnoticed. The card now takes
  `showsPaceWarning`, computed for today only via the same `derivePlan`
  call Goal makes — so the two screens cannot reach different verdicts
  about one goal. `aCompletedDayIsNeverTalkedOutOfWhatItWas` pins the
  `completedDayPlan` half so the fix can't be "simplified" back.

  Worth noting what this means for F3: without it, the widened guardrail
  would have shipped into a warning that still couldn't render where
  people would meet it.

- **F6 — DECLINED 2026-08-16**, see above.
- **F4, F5, F7 — proposed, and per the 2026-08-16 verdict below, probably
  not worth building.**

## Verdict on the remainder (2026-08-16)

Asked directly whether any of this makes the app more accurate or reliable,
or is just arguing details. Honest answer: **mostly details**, and the
reasoning belongs here so it isn't re-litigated.

- **The budget math is not the error term.** Mifflin–St Jeor predicts
  resting energy within 10% for most people — ±175 kcal on 1,742. A single
  restaurant meal logged by eyeball is comparable; an under-logged day is
  worse (which is why `untrackedBelowKcal` exists). Everything on this page
  except F7 moves less than the noise it sits in.
- **F4 and F5 are the same information twice.** `predicted30Lb` vs
  `actual30Lb` ALREADY is the adaptation signal, on screen today. F5
  restates it in kcal/day with ±175 kcal of slope noise; F4 relabels it.
  Neither adds a fact.
- **F7 is probably not an accuracy gain.** Katch–McArdle is better given
  TRUE lean mass. Fed by a bathroom scale's bioimpedance — commonly ±5
  percentage points or worse — the input error alone is ±98 kcal by the
  table above, before the equation's own error. That is trading a known
  bias for an unknown one, under a floor that a worn watch overrides
  anyway.

Where the accuracy actually is: **what gets logged, and how well.** The
largest correctness win in this codebase's history was the intake
sample-sum fix (`PLAN-intake-sample-sums.md`) — watch-written samples
silently dropped by a statistics query, worth hundreds of kcal on real
days. That is the scale of thing worth hunting. Nothing remaining on this
page is.

Verified: 527 kit tests pass, iOS app target builds. Neither change has
been seen on a device yet; F1 moves a real number (~14 kcal on a day with
an evening weigh-in) and F2 is invisible when correct and loud when wrong,
so the device check for F2 is simply that no widget says "Open Onigiri to
set up" after the next install.

## Sequencing for the rest

Ordered by value per line, not by interest:

1. **F4** — reframe predicted-vs-actual. Copy only, two surfaces (Goal and
   Calendar's month detail), and it turns a row that currently reads as a
   failure into the app's one honest window on adaptation.
2. **F3** — proportional and below-resting guardrails through the existing
   `isAggressive` flag.
3. **F5** — observed maintenance as a gated read-out beside F4's row.
4. **F7** — opportunistic Katch–McArdle. Last, and only if a smart scale
   writing `bodyFatPercentage` is actually in the loop; unverified whether
   one is.

F3 and F4 need no new Health permissions and no new UI surfaces. F5 and F7
are features and should get their own plan doc when one is started.

## Open questions

- F5's tracked-day gate: is `bankedDays` the right counter to reuse, or
  does the 30-day window need its own? They are the same idea and should
  not become two.
- F3's proportional guardrail needs a threshold, and picking one is
  choosing a number the app will effectively assert. `deficit × 7 / 3500`
  as a percentage of the basis is the arithmetic; what fraction flips
  `isAggressive` is a decision, not a derivation.
- F4 changes two surfaces that currently share wording by hand. Worth
  checking whether the pair should be extracted the way the Today/widget
  burn labels are, so the next edit can't move one and not the other.
