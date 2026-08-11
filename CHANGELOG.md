# Changelog

Every released version of Onigiri, newest first.

Generated from the annotated git tags by `scripts/generate-changelog.sh`.
**Do not edit by hand** — the tag message is the source of truth, and it is
also what each [GitHub Release](https://github.com/ecliptik/onigiri/releases) publishes. Versions before
v2.16.0 were not all tagged with notes; those show the version and its
comparison link alone.

## v2.20.6 — a milestone is a line, not a card

_2026-08-11_ · [changes since v2.20.5](https://github.com/ecliptik/onigiri/compare/v2.20.5...v2.20.6)

v2.20.5 gave every 5 lb rung a card of its own on Today. That made a rung look
like an arrival, stacked a ✕ directly above a chevron so two controls read as
one crowded control, and promised seven cards over a long journey.

A rung is a line in the **Daily goal** card now, under the scale movement that
earned it: *5 lb down · 10 lb to your target*. Only hitting the target still
gets a card — and that card loses its chevron, since its own text already says
where the tap goes and nothing should sit under the ✕.

The line lasts the day and then goes quietly. That deletes the whole dismissal
apparatus with it: no ✕, no count, no re-arm, nothing to keep in step. What is
recorded is the deepest rung and the day it was first SEEN rather than first
crossed — a rung passed while the app was closed is still news the next time it
opens.

## v2.20.5 — View Food

_2026-08-11_ · [changes since v2.20.4](https://github.com/ecliptik/onigiri/compare/v2.20.4...v2.20.5)

The door a logged food gained in v2.20.4 is called **View Food** now. "Edit
food" promised more than the row does: it opens the food, and what happens
there is your business — most of the time a look rather than a change.

The caption underneath follows. It described editing, which contradicted a row
that no longer says edit; it now describes changes, which is true whichever you
came to do: changes to the food apply to future logs, not to the entry you're
looking at.

Nothing else in the app moved. The rest of this tag is housekeeping in the
project's own notes — a watch-install chronology that the deploy script and a
watchOS update between them made unnecessary, and a description of the Goal
screen that stopped matching the Goal screen two releases ago.

## v2.20.4 — a logged food can open the food it came from

_2026-08-11_ · [changes since v2.20.3](https://github.com/ecliptik/onigiri/compare/v2.20.3...v2.20.4)

Tap a logged meal in the log and you get its components, each one a door into
that food's editor. Tap a logged food and you got nothing: the portion sheet's
only route to a food was through a meal's Contains rows, and a plain food has no
Contains section.

It now offers **Edit food**, with the same treatment a Contains row gets — a real
button with a chevron, and only when the food is still findable. A food logged
from an online search and never saved, or one since renamed, simply has no row;
nothing to tap beats a tap that opens nothing.

Meals are deliberately left out of that match. A meal's name belongs to a meal,
and a food that happened to share it would open the wrong thing. The match
itself is exact on the normalized name rather than a substring, so "Chicken
burrito" cannot reach "Chicken breast".

While you're editing an entry that already exists, the section now says what the
door does and doesn't do: the food changes for future logs, and this entry keeps
the numbers it was logged with. A logged meal's breakdown already carried that
caveat; the single-food case needed it too — otherwise the obvious move is to
"fix" an entry's calories there and watch nothing happen.

## v2.20.3 — the way down marked, the way back up noticed

_2026-08-11_ · [changes since v2.20.2](https://github.com/ecliptik/onigiri/compare/v2.20.2...v2.20.3)

The chart has drawn 5 lb rungs since the progress bar landed, and passing one
never got a word. Today's card now marks it — quieter than the target's: shown
once, dismissible, no re-arm. A 40 lb journey posts seven of these, and if each
nagged like the target's card the target would stop feeling like an arrival.

They are judged on the same sustained basis as the target rather than on the
latest weigh-in, so a rung reached by one light morning isn't reached. The
acknowledgement is a single number — the deepest mark announced — so dismissing
"15 lb down" settles everything at or below it while a later 20 lb mark still
shows. Starting a new goal clears it, because a new journey re-derives its
rungs; continuing past a target you reached does not, because those rungs are
the same ones.

**Maintenance has always had an anchor and never looked at it.** If your 7-day
weight settles 5 lb above the weight you're holding near, the Goal screen now
says so once, in plain text, with "Set a new goal" attached. No card on the
screen you open every morning, no badge, no colour, nothing to dismiss. It is
the only notice in this app carrying bad news, and it is built as an offer.

**A meal shows everything it contains.** The builder had kcal and whichever
single nutrient your first tracked slot names; the rest were sitting in the
foods, unsummed. A collapsed Nutrition breakdown now adds them up through the
same rows the day's detail screen uses — scaled by each member's quantity, and
silent about nutrients none of the foods recorded. Estimated components count,
and it says so, because leaving them out would have made the breakdown disagree
with the total right above it.

Smaller, on Goal: Progress leads with Starting weight, then Starting date. And
the unit moved out of the label on every field that takes one — "Weight (lb)"
sat directly under "From Apple Health  200.2 lb", the same fact in two places
depending on whether you could type in it. Three fields did that, all editable;
they now read like the rows around them.

## v2.20.2 — one budget on the Goal screen

_2026-08-10_ · [changes since v2.20.1](https://github.com/ecliptik/onigiri/compare/v2.20.1...v2.20.2)

v2.20.1 sorted Goal's numbers into sections, and left two of them a screen apart
both labelled "Budget" — "which makes me think they should be the same". They
never could be. One is a forecast from your recent burn; the other is a live
count of what today has earned. Same arithmetic, different spans.

Only one of them is on the visible screen now. **Today** reads
`Budget 1,100 / 1,532 kcal` — eaten of what today allows — over the burn that
produces it. The average-day pair moved into **How the budget is set**, where a
projection belongs beside the rest of the derivation and its label has the
context to mean something.

The fraction is deliberately not today's budget over the average day's. Those
are different quantities, and on an active day the first exceeds the second, so
that fraction would render past 100% and break its own metaphor. Eaten over
today's budget cannot.

**Progress since** and **Progress** were one question split across a screen —
since when, and how far. They are one section now: the start date and weight,
then the banked total and the 30-day comparison. Its explainer moved from the
section footer to a caption under the rows it explains, since a footer there
would now trail the totals and read as describing those instead.

Smaller: "Weight then" and "Weight used" are both just **Weight** — the sections
they sit in already say which weight — and the disclosure is **How the budget is
set**.

One thing that did NOT change, on purpose: the burn row does not say "so far".
The day's burn is active energy earned to now PLUS the whole day's resting,
credited from midnight. Calling it "so far" would contradict the Details screen,
which shows what Health has actually recorded — a collision this app has already
made once. The caption carries the distinction instead.

## v2.20.1 — Goal's numbers, sorted by the question they answer

_2026-08-10_ · [changes since v2.20.0](https://github.com/ecliptik/onigiri/compare/v2.20.0...v2.20.1)

Nine rows sat under one "Daily plan" header answering four unrelated
questions — the controls, the derivation, today's live figure, and what the
scale has done — with nothing marking where one ended and the next began. The
word "budget" meant three things on that screen at once: the average-day
forecast, today's number, and a section header that named no budget at all.

Worst of it, the two budgets sat adjacent, similarly labelled, differently
united and 639 kcal apart. They were never in conflict — one is a forecast from
your recent burn, the other a live count of what today has earned, and they
converge by bedtime — but nothing on screen said so.

Four sections now, each a plain question. **Today** leads, because it is the
only number here you act on and it used to be seventh. **An average day**
follows, with the burn directly above the budget it feeds so the subtraction
still reads off the screen. **How your budget is set** collapses the
derivation — the weight it comes from, the deficit that implies, the resting
estimate the day is floored by — taking the screen from nine rows to five
without hiding a single figure, and the weight-basis picker stays one tap from
the numbers it governs. **Progress** goes last, being the question you ask after
the fact rather than one you act on now.

The headers now carry the distinction the row labels used to spell out, so
neither budget needs a qualifier. A Budget under Today and a Budget under An
average day cannot be read as competing answers, where two "Budget, …" rows a
thumb apart always could.

No arithmetic moved, and nothing was removed. The old "Calorie budget" section
is gone as a header — its resting row is an input to the math and its caption is
that math's explanation, so both moved into the collapsed group, which still
appears when no plan can be computed. The aggressive-pace warning stays outside
it: a warning you have to open something to see is not a warning.

## v2.20.0 — what's in the meal, and what comes after the goal

_2026-08-10_ · [changes since v2.19.4](https://github.com/ecliptik/onigiri/compare/v2.19.4...v2.20.0)

Building a meal showed you the library and moved your picks to the top of it.
That was the only sign a food was in the meal — that, and its portion no longer
reading as a dash. Search for the next food and the ones already chosen were
filtered out of sight, while the running Total still counted them.

There is now one section that IS the meal, above the library it draws from. It
never filters and never re-sorts: a search filters the LIBRARY, so the meal
stays on screen while you hunt. Each row reports what it CONTRIBUTES rather
than what one serving costs — 380 kcal · 190 each — so the Total reads as a sum
of the rows above it, and swiping removes any of them. Components an estimate
minted sit in that same list, because "what is in this meal" should have one
answer in one place.

Hitting your goal was a single line on a screen you had to go looking for, and
it fired off the wrong number: it compared the raw last weigh-in while the
budget beside it planned from the smoothed 7-day basis, so one light morning
could congratulate you on a week nowhere near target.

Reaching it is now a sustained result — the 7-day basis at or below target
across at least three weigh-in days, the same window the budget plans from. Three
days inside seven is impossible for anyone who weighs weekly, so the window
widens until it finds three, capped at thirty days; past that there is nothing
recent enough to call current.

Today carries the moment: a card wearing your reward badge, reporting the arc
rather than the finish line — "10 lb down" — and opening Goal for the decision.
It appears once per target, dismisses, and returns once after two weeks if
nothing was chosen. That last part is not politeness. Sitting at target
undecided grades days more permissively than either real mode, and nothing else
on screen says so.

Goal offers the two moves that actually exist. "5 lb more" measures from the
target you just hit, so it lands on a round number, with a date that can be met
— a fresh target against a stale date divides by the days remaining and asks for
17,500 kcal a day. And continuing keeps the journey: the bar still measures the
whole arc instead of re-zeroing at the moment you earned it.

Smaller: the meal builder's serving field is a plain number again, since that is
what a serving looks like everywhere else in the app, and Settings now says once
that your first tracked metric is the one riding alongside calories on food,
meal, and log rows.

## v2.19.4 — a read you can trust, instead of a lock you can't detect

_2026-08-09_ · [changes since v2.19.3](https://github.com/ecliptik/onigiri/compare/v2.19.3...v2.19.4)

The widgets kept a guard against rendering a sealed Health store as a confident
zero day. The guard asked the wrong question: it probed one sample type and
called the store locked only if the query THREW. Apple does not promise a
throw — a locked device is allowed to answer empty, and an empty answer is
indistinguishable from "no samples" through that API. The probe came back
empty too, and said "open".

The phone's own journal caught three of them in one day, one in the same minute
as a healthy read either side:

    plan 08-08 08:39 act=51 restM=677 restE=1824 wt=212   <- good
    plan 08-08 08:39 act=0  restM=0   restE=NIL  wt=NIL   <- sealed

So the question changed. Rather than interrogate the store, validate the result
against something a good read must produce: a nil weight standing beside a
weight cached today or yesterday is a bad read, while the same nil with nothing
cached recently is a user who has no weigh-ins and must be believed. One sample
query, the same cost as the probe it replaces.

Three quieter faults went with it: the weight cache cleared itself on a nil, so
the first bad read destroyed the evidence the next one is judged against; both
widget paths wrote their computed state as "last good" unconditionally, so a
device locking mid-read cached a zero day and served it back as stale-but-true;
and the burn observer wrote that same zero as its rendered baseline, making the
next fire measure a jump that never happened.

## v2.19.3 — one weight, both wrists

_2026-08-08_ · [changes since v2.19.2](https://github.com/ecliptik/onigiri/compare/v2.19.2...v2.19.3)

The wrist read 316 kcal left while the phone read 147; later the same evening,
613 of 201 against 613 of 370. The banked figure always matched, because both
devices read the same Health samples. Only the deficit TARGET diverged — the
one number derived from a weight.

The phone pushed its RAW last weigh-in to the watch, and the watch prefers
whatever arrives over its own Health read. So from the day v2.19.0 moved the
target onto the 7-day mean of daily lows, the two devices planned from two
different weights: 212.5 lb against 211.4 lb, 1.16 lb apart, which at
3500/daysRemaining kcal per pound is the 169 kcal seen twice in one night.
Neither device was wrong about its own arithmetic.

The write-through cache now holds the basis rather than the raw reading, and
the basis SETTING rides the context too — the watch computes its own whenever
the synced weight ages out, and cannot match a phone whose basis it does not
know.

No watch build is needed to collect this: v2.16.4 already prefers the synced
plan weight, so the phone alone closes the gap.

## v2.19.2 — room for the confirm buttons, without losing VoiceOver

_2026-08-08_ · [changes since v2.19.1](https://github.com/ecliptik/onigiri/compare/v2.19.1...v2.19.2)

The new-food form's bar held Cancel, a title, and two confirm buttons, and read
as crowded. The title yields — only there, and only because the pair needs the
room; editing and the meal form keep theirs.

A nav-bar title is also what VoiceOver announces when a sheet appears, so the
form keeps a heading with no visual weight. Dropping the title without it would
have opened the form onto a text field with no statement of where you are.

## v2.19.1 — clearer weight rows, honest 30-day prediction

_2026-08-08_ · [changes since v2.19.0](https://github.com/ecliptik/onigiri/compare/v2.19.0...v2.19.1)

The Daily plan's weight row was doing two jobs at once — showing the period and
the weight it produced. It is two rows now, "Based on" and "Weight used", and
the caption that existed to explain the crowding is gone.

"Last 30 days · predicted" now excludes untracked days, the same way Total
deficit always has. A day with burn and nothing logged reads as a ~2,500 kcal
deficit that was never earned, and on a row whose whole job is to be compared
against the scale, that phantom loss read as the scale lagging.

## v2.19.0 — a deficit target that doesn't follow the clock

_2026-08-08_ · [changes since v2.18.0](https://github.com/ecliptik/onigiri/compare/v2.18.0...v2.19.0)

The daily target is derived from your weight, and the raw last weigh-in made
that a coin flip: evening weight runs 2–3 lb above the next morning, and near a
target date each pound is worth 150–700 kcal of allowance. Stepping on the
scale could move the day's budget by more than a meal.

Each day now collapses to its lowest reading — the morning one — and those are
averaged over seven days. Goal → Weight used switches back to the last weigh-in
if you prefer it.

The Goal tab also shows its own arithmetic now: Weight used → To lose → Deficit
needed → Average daily burn → Budget, average day → Budget, today, each row
derived from the two above it.

## v2.18.0 — answer on device when the provider can't be reached

_2026-08-08_ · [changes since v2.17.0](https://github.com/ecliptik/onigiri/compare/v2.17.0...v2.18.0)

Estimating and identifying food with a bring-your-own AI provider failed
outright in an area with no cell coverage, while the phone's own model sat
idle. When the chosen provider cannot be reached — no signal, a DNS failure, a
rate limit, an outage — Apple Intelligence answers instead, across every AI
feature: estimates, label refinement, screenshot and sign reading, and photo
identification.

A provider that ANSWERS is never second-guessed, so a rejected API key still
surfaces as a failure rather than being masked forever. Settings → AI → Fall
back to Apple Intelligence, on by default. Nothing leaves the device when it
fires; the caption names the engine that actually answered.

## v2.17.0 — log without saving, search that crosses the scopes

_2026-08-08_ · [changes since v2.16.4](https://github.com/ecliptik/onigiri/compare/v2.16.4...v2.17.0)

Logging a one-off no longer means enlarging your food library: reached from
Today's Log button, the food form offers Log and Log & Save, and plain Log
writes the entry with no library row at all.

Search now looks at the whole library instead of the selected scope. Searching
a food while the Meals tab was up used to find nothing, with the food sitting
right there; results come back grouped as Favorites, Foods, Meals, and
Recently Logged.

## v2.16.4 — durable plan trail, guarded burn baseline

_2026-08-07_ · [changes since v2.16.3](https://github.com/ecliptik/onigiri/compare/v2.16.3...v2.16.4)

Every plan computation records the budget's inputs to a bounded App Group
trail, so a budget that moves without visible cause can be explained
after the fact instead of requiring someone to be watching.

Fixes a real defect it found on its first day: isStoreLocked() probes a
single HealthKit type and can report 'open' while weight, height and the
day summary all read empty. Such a read wrote a burn-gate baseline of
zero. Baselines now come only from a read that produced a real plan.

Also: v2.16.0's burn-driven widget refresh is verified on real workouts.

## v2.16.3 — the cause, named

_2026-08-06_ · [changes since v2.16.2](https://github.com/ecliptik/onigiri/compare/v2.16.2...v2.16.3)

HKStatisticsQuery drops a watch-written sample when an iPhone-written
sample of the same type lands close to it in time: the cross-device
de-duplication that stops the two double-counting steps, misfiring on
food and water where every log is a distinct event. Confirmed on device
for both food (17 s apart) and water (2 s apart); isolated watch logs
and same-device clusters are unaffected.

No behaviour change — the sample-sum fix in v2.16.2 already reads the
truth. This release carries the diagnosis, a diagnostic that prints
sourceRevision.productType (the only field that names the writing
device), and a durable burn journal for verifying widget refresh after
the fact.

## v2.16.2 — logged totals read the samples

_2026-08-05_ · [changes since v2.16.1](https://github.com/ecliptik/onigiri/compare/v2.16.1...v2.16.2)

Intake, sodium, water, the tracked slots and the per-day intake behind
the calendar and streak are summed from plain sample queries. A
statistics query sometimes omits food samples that a sample query
returns from the same store, predicate and window; measured, not
theorised — five explanations for it have been refuted and the cause is
still open, which is precisely why the totals no longer depend on one.

Supersedes v2.16.1's correlation sums: same fix, but other apps' food
counts again and it measured faster. Burn deliberately keeps the
statistics collection — it is measured by both devices at once, so the
cross-source merge is correct there.

## v2.16.1 — food totals agree with the log

_2026-08-04_ · [changes since v2.16.0](https://github.com/ecliptik/onigiri/compare/v2.16.0...v2.16.1)

Intake, sodium and water are summed from the same correlations and
samples the day's list renders, not from a merged statistics query.
HealthKit merges cumulative types across sources by priority rather than
adding them, so food logged on the watch could be dropped against food
logged on the phone in the same window: a 681 kcal day read as 295.

The calendar, badges and streak were judged on the same undercount, which
could mark a fully logged day untracked. Burn keeps the statistics
collection — there the cross-source merge is correct.

## v2.16.0 — widgets follow burn

_2026-08-04_ · [changes since v2.15.0](https://github.com/ecliptik/onigiri/compare/v2.15.0...v2.16.0)

The home-screen widget and watch complications now update as activity
raises the day's budget, instead of holding their morning number until
the app was opened. Adds a gated active-energy observer on both
devices, an explicit foreground reload, a waking-hours poll cadence,
a scheduled wake chain on the watch, and a last-good snapshot so a
sealed Health store can never render as a zero day.

Also fixes three launch crashes found on device: reminder taps
abort()ing the app from a nonisolated delegate callback, the
notification delegate registering after launch, and the watch app
failing to launch from a WatchKit call in App.init.

## v2.15.0 — one budget figure a day: resting up front, active earned

_2026-08-03_ · [changes since v2.13.1](https://github.com/ecliptik/onigiri/compare/v2.13.1...v2.15.0)

## v2.13.1 — widget midnight rollover, scanner freeze

_2026-07-26_ · [changes since v2.13.0](https://github.com/ecliptik/onigiri/compare/v2.13.0...v2.13.1)

## v2.13.0 — nutrition from a screenshot

_2026-07-24_ · [changes since v2.12.0](https://github.com/ecliptik/onigiri/compare/v2.12.0...v2.13.0)

## v2.12.0

_2026-07-23_ · [changes since v2.11.1](https://github.com/ecliptik/onigiri/compare/v2.11.1...v2.12.0)

## v2.11.1

_2026-07-22_ · [changes since v2.11.0](https://github.com/ecliptik/onigiri/compare/v2.11.0...v2.11.1)

The streak warning fires only when nothing is logged (it gated on a
burn-so-far goal check and fired every evening on logged days).

## v2.11.0

_2026-07-22_ · [changes since v2.10.1](https://github.com/ecliptik/onigiri/compare/v2.10.1...v2.11.0)

Unit preferences (kg / mL / salt-gram display, Automatic by region)
and the Settings restructure (rows-based main screen, seven subscreens,
discard gating, truthful summaries, the four-lens audit round).

## v2.10.1

_2026-07-20_ · [changes since v2.10.0](https://github.com/ecliptik/onigiri/compare/v2.10.0...v2.10.1)

Bug fix (93b176b): editing a logged entry kept normalizing the portion
to 1 serving — the count now rides the log as OnigiriQuantity metadata,
so 3 logged hot dogs edit as Serving 3 and reducing to 2 means two hot
dogs, not 0.66 of a triple. Edits and undo re-logs also stop dropping
the ✨ AI-provenance mark.

## v2.10.0

_2026-07-20_ · [changes since v2.9.0](https://github.com/ecliptik/onigiri/compare/v2.9.0...v2.10.0)

The notifications round (a22f684): every reminder time is now a
Settings picker (defaults unchanged), water pacing re-paces over the
chosen check-ins, and Preview Reminders works — the replan sweep was
cancelling its own preview samples.

## v2.9.0

_2026-07-20_ · [changes since v2.8.2](https://github.com/ecliptik/onigiri/compare/v2.8.2...v2.9.0)

The maintenance round (44f17c8): Maintain gains a hold-near anchor,
a drift readout, and a ±100 kcal band badge; window-change reads
drop the moving-average lag; reaching a lose target celebrates and
offers the switch; the Goal form joins the Cancel ↔ Save pattern
with select-on-focus weight fields.

## v2.8.2

_2026-07-20_ · [changes since v2.8.1](https://github.com/ecliptik/onigiri/compare/v2.8.1...v2.8.2)

The goal-projection fix (808c4a9): the Goal tab's finish date now
comes from a recency-weighted fit of raw weigh-ins, so a fresh diet
projects at its real rate instead of weeks conservative.

## v2.8.1

_2026-07-20_ · [changes since v2.8.0](https://github.com/ecliptik/onigiri/compare/v2.8.0...v2.8.1)

The watch parity round (7bf4f8b): the phone's plan inputs sync to the
watch so both devices derive the same calorie budget, and a phone log's
context push now wakes the watch complications instead of leaving them
to the hourly poll.

## v2.8.0

_2026-07-20_ · [changes since v2.7.1](https://github.com/ecliptik/onigiri/compare/v2.7.1...v2.8.0)

The 2026-07-20 quality day: accessibility round (a409c5a),
performance round (aa7dd5e), security round (2ab202e), and the
six-lens pre-submission round (717042d). The 2026-07-16 health check
is fully closed and the store schema is versioned ahead of App Store
distribution.

## v2.7.1

_2026-07-20_ · [changes since v2.7.0](https://github.com/ecliptik/onigiri/compare/v2.7.0...v2.7.1)

## v2.7.0

_2026-07-20_ · [changes since v2.6.1](https://github.com/ecliptik/onigiri/compare/v2.6.1...v2.7.0)

## v2.6.1

_2026-07-19_ · [changes since v2.6.0](https://github.com/ecliptik/onigiri/compare/v2.6.0...v2.6.1)

## v2.6.0

_2026-07-19_ · [changes since v2.5.15](https://github.com/ecliptik/onigiri/compare/v2.5.15...v2.6.0)

## v2.5.15

_2026-07-19_ · [changes since v2.5.14](https://github.com/ecliptik/onigiri/compare/v2.5.14...v2.5.15)

## v2.5.14

_2026-07-19_ · [changes since v2.5.13](https://github.com/ecliptik/onigiri/compare/v2.5.13...v2.5.14)

## v2.5.13

_2026-07-19_ · [changes since v2.5.12](https://github.com/ecliptik/onigiri/compare/v2.5.12...v2.5.13)

## v2.5.12

_2026-07-18_ · [changes since v2.5.11](https://github.com/ecliptik/onigiri/compare/v2.5.11...v2.5.12)

## v2.5.11

_2026-07-18_ · [changes since v2.5.10](https://github.com/ecliptik/onigiri/compare/v2.5.10...v2.5.11)

## v2.5.10

_2026-07-18_ · [changes since v2.5.9](https://github.com/ecliptik/onigiri/compare/v2.5.9...v2.5.10)

## v2.5.9

_2026-07-18_ · [changes since v2.5.8](https://github.com/ecliptik/onigiri/compare/v2.5.8...v2.5.9)

## v2.5.8

_2026-07-18_ · [changes since v2.5.7](https://github.com/ecliptik/onigiri/compare/v2.5.7...v2.5.8)

## v2.5.7

_2026-07-17_ · [changes since v2.5.6](https://github.com/ecliptik/onigiri/compare/v2.5.6...v2.5.7)

## v2.5.6

_2026-07-17_ · [changes since v2.5.5](https://github.com/ecliptik/onigiri/compare/v2.5.5...v2.5.6)

## v2.5.5

_2026-07-17_ · [changes since v2.5.2](https://github.com/ecliptik/onigiri/compare/v2.5.2...v2.5.5)

## v2.5.2

_2026-07-16_ · [changes since v2.5.1](https://github.com/ecliptik/onigiri/compare/v2.5.1...v2.5.2)

Backup files now use .complete file protection: encrypted and
unreadable while the device is locked, past the iOS default that
already encrypts them at rest. Backup I/O is foreground-only, so the
lock restriction never bites. The library store and widget mirror stay
at the default (they need background access); the FDC key stays in the
Keychain; HealthKit protects the logs itself.

## v2.5.1

_2026-07-16_ · [changes since v2.5.0](https://github.com/ecliptik/onigiri/compare/v2.5.0...v2.5.1)

Ask Siri about any macro ("How much protein have I had in Onigiri?") —
tracked nutrients answer against their Today target. The calorie
headline now shows "kcal left" by default (positive, no minus; the
signed balance is one tap away in Settings). Backups can never
overwrite each other and never snapshot an empty library. And the
Today tab bar no longer gets stuck minimized — the day-paging swipe
that caused it is gone (nav-bar chevrons page days).

## v2.5.0

_2026-07-16_ · [changes since v2.4.0](https://github.com/ecliptik/onigiri/compare/v2.4.0...v2.5.0)

Say "Log water in Onigiri," "Log chicken and rice in Onigiri," or ask
"How many calories do I have left in Onigiri?" — Siri logs and answers
on the phone and the watch, no setup. With Apple Intelligence,
"Describe a food in Onigiri" estimates whatever you ate and logs it
after you confirm. Under the hood: the App Shortcuts registration fix
(intents now compile into each target — on-device indexing rejects
SPM-package metadata, broken invisibly since 2.1), Siri pronunciation
hints, ounces parameter for water automations, and backup files that
can never overwrite each other.

## v2.4.0

_2026-07-16_ · [changes since v2.3.0](https://github.com/ecliptik/onigiri/compare/v2.3.0...v2.4.0)

Point the scan camera at the food itself on Apple Intelligence
devices: Onigiri names the dish, lists its typical components, and
estimates calories and sodium for review — on-device, review-first,
and the same camera still does barcodes and labels. Say "Log water in
Onigiri" or "Log chicken and rice in Onigiri" and Siri logs it; the
same shortcuts ride Spotlight and the Action button. Under the hood: a
golden-set eval suite for every Foundation Models affordance, audit
round 2 (WatchSync wire format pinned, scene-restored tabs, stale-sim
test guards), and reminders that replan when logs arrive from the
watch, widgets, Control Center, or Siri.

## v2.3.0

_2026-07-16_ · [changes since v2.2.0](https://github.com/ecliptik/onigiri/compare/v2.2.0...v2.3.0)

No code changes since 2.2.0 beyond the relicense: everything through
v2.2.0 remains MIT; v2.3.0 and later are PolyForm Noncommercial 1.0.0.

## v2.2.0

_2026-07-16_

