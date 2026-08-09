# Changelog

Every released version of Onigiri, newest first.

Generated from the annotated git tags by `scripts/generate-changelog.sh`.
**Do not edit by hand** — the tag message is the source of truth, and it is
also what each [GitHub Release](https://github.com/ecliptik/onigiri/releases) publishes. Versions before
v2.16.0 were not all tagged with notes; those show the version and its
comparison link alone.

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

