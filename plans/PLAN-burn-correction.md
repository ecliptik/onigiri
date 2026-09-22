# Burn correction: making the budget answer to the scale

2026-09-22. Resumes **A2** of `PLAN-goal-budget-reconciliation.md`,
which was deferred on 2026-08-18 "until A1 has shown, over a few weeks
of real data, whether the gap is large and steady enough to be worth
acting on."

A1 shipped that day, spent six days in the wrong section, was cut, and
returned to Progress on 2026-09-22 as `Burn, from the scale`. The
evidence is now in. The gap is large, steady, and larger than the
deficit it is supposed to leave behind.

**Status: BUILT 2026-09-22, NOT ACCEPTED.** `BurnCorrection` (kit),
the Goal offer, Today's own row. Accept the offer only after a fortnight
of weighed logging.

Three implementation facts the design did not spell out:

- The correction applies AFTER `TodayBurnFloor`, which ratchets the
  uncorrected burn — otherwise a mid-day acceptance would sit under the
  morning's high mark until midnight.
- The resting floor holds part of it back on a morning (resting is
  credited from the estimate), so Today's row prints what LANDED with
  the accepted figure underneath; completed days take all of it.
- `minReasonableBudget` is reached through Goal's preview (the corrected
  average feeds `derivePlan`, which raises the pace warning), not the
  day path — `completedDayPlan` still carries no such floor, by design.

---

## What the evidence actually says

Three sources from the user's own device, 2026-09-21/22: Goal's live
Progress rows, `Documents/budget-diagnostics.log` pulled via
`devicectl`, and the arithmetic between them. The figures themselves
stay off this public page; their shape is the finding.

- Health's measured burn averaged a few hundred kcal/day ABOVE what
  `ObservedBurn` says the scale implies, over both the 30-day window
  and all tracked days.
- That gap is about the same size as the deficit the budget builds in.

**The gap is the same size as the deficit.** That is the whole finding.
`budget = burn - deficit` is correct arithmetic on an input that is
roughly one deficit too high, so eating to budget lands at roughly true
maintenance. The deficit is not missing; it is smaller than the error
in the number it is subtracted from.

Two things the diagnostics settled that speculation could not:

- **Sex is set in Health.** The logged resting estimate back-solves to
  a sexed Mifflin constant, so the unspecified midpoint is not in play
  and that whole line of suspicion is dead.
- **The resting floor is not the inflater.** On *completed* days
  Apple's measured basal sits ABOVE the estimate, so `max()` takes the
  measurement and the floor never fires. It fires only on partial days.
  What this does show is Apple's basal running above what Mifflin
  predicts for this body — suggestive, not conclusive, since Mifflin is
  itself a prediction with real individual spread. The scale remains
  the only ground truth.

Active energy is modest and cannot carry much of the error.

---

## Decisions

Asked and answered 2026-09-22.

### 1. It re-grades history

One burn figure across all of it. `Total deficit` becomes what the
scale actually did:

    banked − (correction × tracked days) = what the scale lost

Badges and the streak re-grade against the lower burn; days that
squeaked past their target un-earn. The user was asked directly and
accepts this: *"I am okay with breaking a streak, I want things as
accurate as possible."*

### 2. A flat kcal/day offset

A single signed number subtracted from every day's burn, not a
percentage. Both suspects — Apple's basal, and flat intake
under-logging — are flat-ish, and across the user's observed activity
range offset and multiplier differ by under 50 kcal/day. The pick is therefore on legibility, and one number a
person can sanity-check beats a factor they cannot.

### 3. Suggested from all tracked days

All tracked days, not the trailing 30. The 30-day window suggested a
noticeably larger correction, and the difference was mostly a few
pounds of water sitting above the trend line. Setting the correction
off the 30-day window would bake that water into the budget as if it
were metabolism.

---

## The superseded guardrail

`PLAN-goal-budget-reconciliation.md` listed, under A2:

> **Never retroactive.** A calibration must not re-grade history. Past
> days are judged by `DeficitTargetHistory` snapshots and that stays
> true.

Decision 1 overrules it. This must be argued, not ignored, because the
guardrail is right about the mechanism it names — and that mechanism
turns out not to cover this case.

`DeficitTargetHistory` snapshots exist so a day is judged by the RULE
in force that day: change your goal today and yesterday's badge must
not move. That protection is about the **target**. A burn correction
does not touch any target; it changes the **measurement** the target is
compared against. And measurements already re-grade — CLAUDE.md, on the
budget: *"Past days re-grade themselves from Health; that's accepted,
and it's less code than freezing them."*

So the rule that survives is sharper than the one it replaces:

> A day's TARGET is frozen by its `DeficitTargetHistory` snapshot. A
> day's MEASUREMENT is not, and never has been. A burn correction is a
> measurement, so it re-grades; anything that moves a target must not.

The remaining cost is honest and is not a mechanism problem: the
calendar visibly changes the day this is switched on. That makes it a
confirmed, explicit action with a named consequence, not a toggle.

---

## Design

### Storage

Two keys in `SharedStore`, app-group backed:

- `burnCorrectionKcal: Double`, default `0` — signed, negative reduces
  burn. `0` is off, which is the default and the disabled state; no
  separate Bool.
- `burnCorrectionSetAt: Date?` — what the offer was computed from, so
  the UI can say how old it is and prompt a re-check.

**Both MUST ride the watch settings sync** with an explicit value, the
rule the three unit keys already follow. A correction the phone has and
the watch does not is precisely the 2026-09-20 phone-vs-watch budget
disagreement, rebuilt deliberately.

### Where it applies

Inside `DayBudget.dayBurn`, as a new explicit parameter — not read from
`SharedStore` inside the kit. Every call site passes it, which is how
`estimatedRestingKcal` already works and what keeps it testable.

That single composition point is the reason this is tractable:
`dailyEnergyTotals` (calendar, badges, streak, `bankedKcal`,
`GoalTrendStats`), `DailyPlanLoader` (Today), the widgets and the watch
all read through it, so one change gives one figure on every surface.

### It gets its own row, and this matters

Today's Details card must ADD UP — `creditedActive + creditedResting ==
dayBurnKcal` exactly, a rule that has failed twice with raw figures.
The correction therefore renders as its **own line**, not folded into
either channel:

    Active        400
    Resting     1,800
    Correction   -300
                -----
    Burn        1,900

Folding it into resting would push resting under its own floor, which
is the floor's whole purpose. Folding it into active sends active
negative on a quiet day (250 active less a 300 correction is already
below zero). And an invisible correction is exactly the "silently"
failure every rule in this area is written against.

### The offer

Beside `Burn, from the scale` on Goal, where the number it is derived
from already lives. Same shape as the finish-line date button: the app
proposes, the user decides, the value is visible and reversible.

- Appears only when `ObservedBurn` has an answer, i.e. at or past
  `ObservedBurn.minimumTrackedDays` (21) tracked days.
- States the consequence before it is taken, including the re-grade.
- One tap to clear, returning to `0`.
- **Never recomputes itself.** A stored correction changes only when a
  person taps something. Re-suggesting is a manual button.

### Guardrails carried forward

From the A2 list, all still required:

- **Minimum window** — the 21-day `ObservedBurn` gate.
- **A cap** — clamp to ±20% of measured burn. An uncapped correction
  fed a bad month produces a budget nobody should eat to.
- **A floor** — the corrected burn may never fall below
  `BasalEstimate.restingKcal`, and the resulting budget must still
  clear `minReasonableBudget`. Confirm during implementation that both
  floors are actually reached on this path; the 2026-08-18 work found
  them missing from `completedDayPlan`.
- **Off by default**, reversible in one tap.

Hysteresis is moot under "never recomputes itself" and is dropped.

---

## What this must never become

A3 from the predecessor plan — continuous adaptive TDEE — stays
rejected, and this design is one refactor away from it, so the line
needs restating:

> Feeding `ObservedBurn` back into `dayBurn` automatically would
> re-create the trailing-average substitution `PLAN-earned-budget`
> DELETED, and do it silently, which is worse than the version that was
> removed.

A stored number a person accepted is not the app inventing burn. A
number that updates itself is. The distinguishing property is not where
the value comes from but whether a human agreed to it, so any future
"just refresh it weekly" is this rule being broken.

---

## Hazards

**The correction absorbs under-logging, and that is not stable.** The
gap is some mix of Apple's burn and the user's logging. A correction
derived from `ObservedBurn` swallows both. If logging then improves,
the correction is suddenly wrong in the punishing direction — the user
would be under-eating by whatever share was really intake error.

**This is a sequencing question, and it is the one open item.** The
fortnight of weighed logging proposed on 2026-09-22 separates the
causes with a sharp prediction: weighed logs landing about one gap
ABOVE the usual logged intake while eating normally means it was
under-logging; landing near the usual figure again means Apple's basal
is most of it. Setting the correction *before* that
fortnight calibrates against a moving target.

**DECIDED 2026-09-22: build now, set later.** The mechanism ships; the
offer appears on Goal and is NOT accepted until a fortnight of weighed
logging has separated the causes. The build is not the risky part —
taking the offer is.

The rejected alternative was fortnight-first-then-build, which is
cleaner but costs two weeks for little: the budget staying a gap too
generous matters less than it sounds, since the user already eats well
under it and is ahead of the target date.

This decision puts one requirement ON the implementation, because the
app cannot enforce a wait: **the offer must state what it is calibrated
against and how old that basis is** (`burnCorrectionSetAt` exists for
this). A bare "Use −300?" button invites the tap this sequencing exists
to delay. It should say what it was computed from and over how many
days, so taking it early is at least an informed choice.

**The re-grade is one-way in practice.** Clearing the correction
restores the old verdicts, so it is reversible in the code. It is not
reversible in the user's head: having seen the streak re-cut, seeing it
restored is not neutral. Say what will happen before it happens.

---

## Test plan

Kit, pure, where the rules live:

- `dayBurn` with a correction: subtracts, never sends a channel
  negative, never falls below `BasalEstimate`, clamps at ±20%.
- `GoalTrendStats` with a correction: `bankedKcal` drops by
  `correction x trackedDays`, and on this user's shape `bankedLb`
  lands on the measured loss.
- A correction of `0` is byte-identical to today, on every path. This
  is the one that protects every existing test.
- The suggestion is derived from all tracked days and is NOT recomputed
  by any code path — assert the stored value survives a load/refresh
  cycle that changes `ObservedBurn`.

UI:

- The offer appears only past the 21-day gate, and states the re-grade.
- Today's Details still adds up with a correction live — the existing
  "card that has to ADD UP" assertion, re-run with a non-zero value.
- Accepting, then clearing, returns every figure to its prior value.

Device, because the simulator cannot show it: phone and watch must read
the SAME corrected burn. Diff `budget-diagnostics.log` from both, the
2026-09-20 recipe. If they disagree, the settings sync is the suspect.

---

## Out of scope

- Any automatic or scheduled recomputation. See above.
- A correction on INTAKE rather than burn. It would be the more honest
  model if under-logging is the whole cause, but the app cannot know
  that, and two correction knobs is worse than one.
- Per-channel corrections (separate active and resting factors).
  Nothing in the evidence supports resolving the error into channels,
  and `ObservedBurn` returns one number by construction.
- Anything that changes the target or the target date. The deficit
  comes from pounds ÷ days and is independent of burn; it should stay
  that way.
