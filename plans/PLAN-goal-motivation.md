# PLAN — motivation on the Goal tab (2026-07-31)

Five items, agreed with the user after they said the projected date "can
seem to change widely depending on the day" and asked for motivational
framing. Goal tab is the right home; nothing needs to move to Today.

## Done

- **Finish window** (`3531d61`). The projection is a 5-day range snapped
  to a fixed grid — "between Oct 6 and Oct 11" — so estimates wandering
  inside a bucket don't move the screen. Fitting the SMOOTHED series was
  the other half and is REJECTED: it pushed the fresh-diet fixture from
  37–44 days to 59–64, erasing signal with the noise. If the range still
  flaps, widen the bucket or require two consecutive estimates in a new
  bucket — do NOT reach for smoothing again.
- **Banked so far** + **best streak** (`14f6d81`).
  Net deficit over TRACKED days only, and the header shows the best run
  when the current streak is 0.
- **Milestones**, **progress bar**, **pace as a choice** — all three,
  on one start point (below). Kit: `GoalProgress` (start resolution,
  the of-total numbers, the marks) and `GoalTrendStats.fasterWindow`.
  Notes worth keeping:
  - Milestones are named by PROGRESS ("15 lb down"), not by weight.
    Anchored to the start, a 213.4 lb journey would otherwise post
    marks at 208.4 and 203.4. The chart draws every rung and labels
    only the next unreached one — four dashed lines with four labels
    was the confetti the plan warned about.
  - `fasterWindow` is nil when the boost doesn't cross a bucket
    boundary. Two identical date ranges offered as an incentive read
    as a broken promise.
  - The kilogram step is 2 kg, not 5 lb converted.

## The start point (built)

All three needed one, and it was the only real work here.

### The start-weight snapshot

`GoalSettings` gains two ADDITIVE OPTIONALS — `startWeightLb: Double?`
and `startedAt: Date?`. Optional additions stay inside `OnigiriSchemaV1`
(the model file's own note: only a NON-additive change needs a V2 plus a
MigrationStage), so no migration stage, but re-read that note before
assuming it.

Stamp them in `GoalUpsert` when a goal is created, and when the TARGET
changes (a new target is a new journey; a nudged date isn't).

**Existing goals have neither**, and can't. Do NOT stamp today's weight
as the start — that tells someone mid-journey they're at 0%. Derive the
fallback from the earliest weigh-in on record and label the progress
"since <that date>". Honest, immediately useful, and it stops being a
fallback the moment a goal is next edited.

Two carve-outs found while building it: maintenance never stamps (its
"target" is a hold-near anchor, so nudging it would mint a journey that
doesn't exist), and the stamp needs BOTH halves — a weight with no date
can't say what it measures from, so a half-stamp falls through to
derivation.

### 3. Milestones on the chart

Marks every 5 lb from start toward target, plus the target itself. Quiet
`RuleMark`/`PointMark` annotations, not confetti — the chart is already
dense, and the app's voice is calm.

### 4. Progress bar

start → now → target, with "8.4 of 25 lb". Reads at a glance in a way
the chart doesn't. Needs the same start point.

### 5. Pace as a choice

"At this pace: Oct 6–11. With 100 kcal/day more: Sep 22–27." Turns a
number you watch into one you can act on. Reuses
`GoalTrendStats.projectionWindow` with an adjusted slope — no new math,
and it must render as a window like everything else.

## Watch out

- `bestStreak` already existed in the kit, the model, AND the month
  details view; the fix was surfacing it, not writing it. Check for an
  existing helper before adding one here too.
- Banked excludes untracked days deliberately (a no-food day reads as a
  ~2,500 kcal deficit). Any new cumulative number needs the same guard.
- Weight display goes through `WeightUnit` at the UI boundary — kg users
  must not see pounds in the progress bar or milestones.
