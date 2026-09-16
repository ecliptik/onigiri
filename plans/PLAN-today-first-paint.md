# Today: no zeros on a cold launch

2026-09-16. The user, after the sheet-dismissal fix: "if the app is
closed and I open it new, it takes a slight second for the kcal and log
to appear, quickly going from 0 to the kcal logged number on Today. I'm
assuming it's because it's reading from Health? Is there a way to cache
this or make it appear less jarring?" Chosen: placeholders, a faster
first load, AND a last-good prime.

## What the cold launch did (26.5 sim, `simctl recordVideo`, frame-counted)

After the launch screen, Today painted at t=3.775 with "0 kcal balance",
"0 mg sodium", "0 / 64 oz water", the add-a-weigh-in hint, three zero
meters and "Nothing logged yet." — real-looking values. At t=3.815 the
Resting meter alone became 1,743 (the estimate from `loadStatic`). At
t=3.877 everything else landed: 320 kcal left, the Daily goal card,
1,510 / 385, the Breakfast / Snack / Water groups. ~100 ms of zeros on
an M-series simulator; the model's own comment puts HealthKit's first
read of a launch at ~450 ms on the phone, and the static reads ran
BEFORE the day's (`await loadStatic(); await refresh()`), so the kcal
and log queued behind weight history they never needed.

Two staged jumps, then: zeros → resting → everything.

## Fix

1. **Prime.** `TodayPrime` (OnigiriKit, Codable, tested) holds the
   summary, day burn, resting estimate, weight basis, average burn,
   trend, weight history, tracked totals and both logs, stamped with
   its day and a schema. `TodayPrimeStore` (app) keeps it as one JSON
   file in Caches. `TodayModel.init` reads it synchronously before the
   first frame; `refresh()` writes it after each trustworthy read of
   today once the static reads are in. `FoodLogEntry`, `WaterLogEntry`
   and `WeightTrend.Point` became Codable for it.
2. **Placeholders.** `TodayView.awaitingFirstLoad` is true only with
   NEITHER a prime nor a Health answer (first launch, a new day, an
   evicted cache): the summary stack renders `.redacted(.placeholder)`,
   and "Nothing logged yet." and the weigh-in hint wait. The no-goal
   text does not — it is a SwiftData fact.
3. **Side by side.** `start()` runs `loadStatic()` and `refresh()`
   concurrently (MainActor default isolation — they interleave at
   awaits), then re-derives the day burn once the estimate is in and
   stores the prime. `rederiveDayBurn()` is the one place the ratchet
   is applied.

## The rule (CLAUDE.md, Logging)

The prime is a picture of the last refresh, never a store: written only
from a Health answer for today, never by a log; read only by `init`;
refused for another day, another schema, or the all-zero day a sealed
store returns. HealthKit stays the only source of truth for logs.

## Results (2026-09-16, 26.5 sim, frame-counted)

- Primed cold launch: the FIRST content frame (t=3.058) already holds
  the whole day — headline, sodium/water, Daily goal card, the three
  meters, the Breakfast/Dinner/Snack/Water groups. No later content
  event; the only motion after it is the launch zoom and the toolbar
  pill fading in.
- No-cache cold launch (prime file removed): the first content frame
  (t=3.453) is the skeleton — redacted headline, sodium/water and
  meters, a bare "Log" header, no weigh-in hint, no "Nothing logged
  yet." — and the real day lands in ONE step at t=3.707. Before, the
  same window showed real-looking zeros, then the resting meter alone,
  then the rest.
- Kit: `TodayPrimeTests` (round trip through JSON with meal items and
  nutrients, validity by day and schema, the sealed zero-day refusal)
  — 18 tests across the four touched suites pass. UI:
  `testSeedGrantAndLogFlow` passes on the new build.
- `simctl recordVideo` notes for next time: a deep-link nudge to flush
  the encoder leaves "Open in Onigiri?" on screen for the NEXT launch
  (two recordings were of that dialog); `simctl ui appearance` is a
  cleaner flush. And `axe tap` by coordinate missed the dialog's
  Cancel on the 26.5 sim; tapping the frame `axe describe-ui` reports
  did not.
