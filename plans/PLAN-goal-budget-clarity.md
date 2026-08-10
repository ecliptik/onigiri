# PLAN — Goal's budgets, told apart by where they live (2026-08-10)

**Status: BUILT 2026-08-10**, shipped in v2.20.1. Verified on the 26.5
sim: `TODAY / Budget 1,532 kcal` over `AN AVERAGE DAY / Burn ≈ 2,300 ·
Budget ≈ 1,704` (the subtraction still reads off the screen), the
collapsed `How your budget is set` expanding IN PLACE to the five
derivation rows, and `PROGRESS` below it. `testGoalReachedCelebration‑
AndContinue` still passes against the restructured screen.

One deviation from the sketch, deliberate: the `isAggressive` warning
did NOT move into the collapsed group. A warning you have to open
something to see is not a warning, so it renders as its own section
between the average day and the disclosure.

Note on presentation: in a Form, `DisclosureGroup` draws a chevron that
reads like a navigation link until tapped — confirmed on device that it
rotates and expands in place rather than pushing. If that ever misleads,
the fix is a `Label` with an explicit chevron.png, not a NavigationLink.

The ask (the user, from the Goal tab): "help me understand all the
'budget' in the goal tabs mean. There's a lot here and I feel like it's
a bit too much — consolidate and make this clearer."

## Current state (verified in `GoalView.swift`)

ONE section, `Daily plan`, nine rows, and a second section below it
whose header is a third use of the word "budget":

    DAILY PLAN
      Based on              7-day average ›   ← control
      Weight used                  211.9 lb   ← its result
      To lose                        1.9 lb   ← weight − target
      Deficit needed          299 kcal/day    ← (1.9 × 3500) ÷ days left
      Average daily burn    ≈ 2,695 kcal/day  ← Health's recent average
      Budget, average day   ≈ 2,397 kcal/day  ← 2,695 − 299
      Budget, today             1,758 kcal    ← today's OWN burn − 299
      Total deficit    31,977 kcal ≈ 9.1 lb   ← retrospective
      Last 30 days   −7.8 predicted / −4.4    ← retrospective
      (footer) Daily budget grows as active energy increases.

    CALORIE BUDGET
      Resting burn, full day ≈ 1,820 kcal/day
      (caption) Your budget is the day's energy, minus the deficit…

Three diagnoses, in order of how much they cost the reader:

1. **One header, four jobs.** `Daily plan` covers the CONTROLS (Based
   on, Weight used), the DERIVATION (To lose → Deficit needed →
   Average burn → Budget), TODAY'S LIVE NUMBER, and RETROSPECTIVE
   EVIDENCE (Total deficit, Last 30 days). Nothing marks where one ends
   and the next begins, so all nine rows read as equally weighted — and
   the one row you actually act on (`Budget, today`) is seventh.
2. **"Budget" means three things**: the average-day projection, today's
   live figure, and the section header `Calorie budget` — which names no
   budget at all, but rather how one is composed.
3. **The two budgets are adjacent, similarly named, differently
   united** (`kcal/day` vs `kcal`) and 639 kcal apart. Adjacency invites
   reading them as competing answers when they are different TIME
   SCALES: a forecast and a live count that converge by bedtime.

## What must not change (each was a shipped bug once)

- **Both budgets stay, and stay distinguishable.** One label over two
  numbers is exactly the 2026-08-02 failure: Goal said 2,293 while
  Details said 1,567, 726 kcal apart at 1:43pm, both correct. This plan
  makes them MORE distinguishable, not less.
- **No today-floor on the projection** to close the gap. Tried, rejected:
  it made the average neither one thing nor the other and didn't close
  it.
- **`Resting burn, full day` keeps its qualifier** — the bare label
  collided with Details' measured-so-far figure and read as a
  contradiction (1,830 vs 1,272).
- **The weight-basis picker stays on this screen**, at the point where
  its effect is visible, and `Based on` / `Weight used` stay two rows —
  one row carrying both made the reader work out which half was the
  control (2026-08-08).
- Copy register: "burn" for the glanceable rows, "energy" for
  explanatory captions.

## The move

**Let the section header carry the distinction, so the row labels don't
have to.** A row called `Budget` under `TODAY` and another under
`AN AVERAGE DAY` cannot be confused; two rows called `Budget, …` a
thumb apart always can be. Nothing is deleted — the same nine numbers,
grouped by the question they answer, and ordered so the one you act on
comes first.

    TARGET                              (unchanged, above)

    TODAY
      Budget                      1,758 kcal
      (footer) Grows as you move: resting energy is credited from
      midnight, active energy as you earn it.

    AN AVERAGE DAY
      Burn                    ≈ 2,695 kcal/day
      Budget                  ≈ 2,397 kcal/day
      (footer) A forecast from your recent burn — today's own number is
      above.

    THE MATH                            (collapsed by default)
      Based on                7-day average ›
      Weight used                    211.9 lb
      To lose                          1.9 lb
      Deficit needed            299 kcal/day
      Resting burn, full day  ≈ 1,820 kcal/day
      (footer) Your budget is the day's energy, minus the deficit.

    PROGRESS
      Total deficit      31,977 kcal ≈ 9.1 lb
                          across 33 tracked days
      Last 30 days           −7.8 lb predicted
                              −4.4 lb on scale

Four headers, each a plain-language question: what can I eat today,
what does a typical day look like, where do these numbers come from,
and is it working. The `Calorie budget` section disappears as a header —
its resting row is an INPUT to the math, and its caption is the math's
explanation, so both belong under `THE MATH`.

### Why `THE MATH` collapses

It is the only group that is pure derivation: read once to understand
the model, then rarely again. Collapsing it takes the screen from nine
rows to five without hiding anything — and it is where the weight-basis
picker lives, so the control stays exactly one tap from the number it
governs. `DisclosureGroup`, the idiom `DayNutritionView` already uses
for its micronutrient groups.

Open-by-default is the safer variant if a collapsed control feels
buried; that is a taste knob, not a design fork.

### Naming

- `Budget, today` → **`Budget`** under `TODAY`.
- `Budget, average day` → **`Budget`** under `AN AVERAGE DAY`.
- `Average daily burn` → **`Burn`** under `AN AVERAGE DAY` (the header
  already says "average", so the label stops repeating it).
- `Calorie budget` header → **`The math`**; nothing is called "budget"
  except the two figures that ARE budgets.
- Everything else keeps its current label.

## Risks / what to check on device

- **The two budgets are now further apart on screen**, which is the
  point, but it must not make them feel unrelated: `AN AVERAGE DAY`'s
  footer explicitly points at the row above it. Read both footers on
  device — if they stutter, the average-day one goes first.
- Maintenance mode has no `To lose` / `Deficit needed`, and the current
  code already conditions those rows; `THE MATH` must not render as an
  empty disclosure there.
- The no-history captions ("No burn history in Health yet…", "Add your
  height and date of birth…") currently live in `Calorie budget` and
  need a home in `THE MATH`.
- `plan.isAggressive` warning belongs with the math that produced it,
  not with today's number.
- iPad two-pane and accessibility sizes: four short sections stack
  better than one nine-row block, but confirm the disclosure's chevron
  target at accessibility sizes.

## Tests

- No kit change: this is presentation only. Every figure keeps its
  existing derivation, so the existing `CalorieBudget` / `DayBudget`
  tests continue to cover the math.
- UI (extend an existing opt-in Goal shot rather than adding a suite):
  assert `Budget` resolves to TWO elements in different sections, that
  today's figure matches Today's own headline arithmetic, and that
  expanding `THE MATH` reveals the weight-basis picker.

## Decisions (settled 2026-08-10, the user)

1. **Four named sections**, as sketched: `TODAY`, `AN AVERAGE DAY`,
   `HOW YOUR BUDGET IS SET`, `PROGRESS`. The header carries the
   distinction; neither budget row needs a qualifier.
2. **The derivation section is COLLAPSED by default** — nine rows to
   five, with nothing removed.
3. **It is called `How your budget is set`** — explicit about why you'd
   open it, and in the formal register the app already uses for
   explanatory captions and settings footers. `The math` was rejected as
   flip for what is actually the plan itself. **`Details` is
   unavailable** at any point in this screen: `DetailsCaption` reserves
   "Details ›" app-wide for "tap to open another screen", and reusing it
   as a header would muddy an established affordance.
   Its header is longer than its three neighbours — check the balance at
   accessibility sizes; if it wraps badly, `The plan` is the fallback.
4. **`TODAY` does NOT move above the chart.** The mode picker and trend
   chart keep the top of the tab; this is a restructure of the rows
   below them, not a reordering of the whole screen.
