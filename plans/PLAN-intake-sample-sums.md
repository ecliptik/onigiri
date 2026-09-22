# Why logged intake is summed from SAMPLES, not statistics (2026-08-05/06)

The rule and its consequences live in `CLAUDE.md` → *Logging: HealthKit is the
store*. This file is the investigation behind it: the measurements, the theories
that died, and the one design question still open. Read it before re-opening any
of that; don't re-derive it.

## The fault

`HKStatisticsQuery` drops a WATCH-written sample when an IPHONE-written sample
of the same type lands close to it in time. It is the cross-device
de-duplication that stops a phone and watch double-counting steps, misfiring on
food and water where every log is a distinct event.
`HKSampleQueryDescriptor` returns both.

    (the user's own log lines are not reproduced here; their shape:)
    food   watch log, then phone log 17 s later  → merged < samples,
                                                   the watch log dropped
    water  watch + phone logs 2 s apart          → one serving dropped
    food   isolated watch log, next phone 3.5 h → merged == samples
    lunch  three logs seconds apart, one device  → merged == samples

The merge WINDOW is still unmeasured: 2 s and 17 s both collide, 3.5 h does not,
and Apple does not document it.

## How the investigation went wrong

Six explanations were argued and five died to measurement. The one that survived
— cross-device merging — was the FIRST, and it was discarded early for two bad
reasons:

- `.separateBySource` reported a single source, which looked like proof that no
  cross-source anything was happening. It isn't: HealthKit credits the APP, not
  the device, so the phone app's bundle identifier is on watch-written samples
  too.
- Identical timestamps were tested for, instead of PROXIMITY. The colliding
  pairs are 2 s and 17 s apart, never equal.

`sourceRevision.productType` is the only field that names the writer —
`sample.device` is nil (we attach no `HKDevice`). Both wrong theories cost a
round of work before `productType` settled it.

`HealthKitService.diagnoseIntake` (DEBUG, keep it) reproduces all of the above
on demand.

## What it cost

A day read at well under half its logged intake on Today, and the same
undercount reached the calendar, badges and streak through
`dailyEnergyTotals` — low enough that the day fell under
`untrackedBelowKcal`, so a fully logged day would have read untracked.

v2.16.1 first fixed it by summing CORRELATIONS. That worked but silently dropped
other apps' food. Sample sums fix it without that trade, and measured faster
(3 ms vs 23 ms).

## Still open: making Apple Health agree

Health's own totals are statistics-based, so Health under-reports these days
too. Onigiri reading higher than Health is correct, not a bug — and only
Health's total can disagree, which is why a visual check inside Onigiri can
never test any of this.

Making them agree means separating the two devices' writes in time so the merge
cannot fire — a small change in `logFood`/`logWater`, NOT the WatchConnectivity
re-architecture floated earlier.

Two constraints on any such design:

1. It needs the merge window's width first, which is unmeasured. Measure it
   OPPORTUNISTICALLY rather than in a dedicated session: whenever a log happens
   from both devices, ask the spacing and read `water merged=… samples=…` out of
   `diagnoseIntake`.
2. It must work BLIND. At write time neither device reliably sees the other's
   recent sample (the watch writes to its own store and syncs later), so a
   pre-write "is anything near?" query cannot be trusted. That points at
   deterministic per-device lanes, not lookups.

**Re-state the trade before building anything.** It buys agreement with Apple
Health at the cost of slightly false log timestamps, and Onigiri is already the
one that is correct. This is a cosmetic fix to someone else's arithmetic.
