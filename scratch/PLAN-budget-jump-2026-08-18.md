# The badge copy change and the +498 morning — resolved

2026-08-18. Reported: (a) the Daily goal card changed vocabulary between
Aug 14 and Aug 15, (b) Today read **+498 kcal over** at 09:04 with
nothing logged. Both **diagnosed and closed** below. Neither is a
regression from the Aug 14–18 work. Three real defects were found on the
way, one of them previously unknown.

## Verdict

| report | cause | regression? |
|---|---|---|
| Aug 15/17 copy change | the 1 lb finish-line band zeroing the deficit target | no — designed |
| Today +498 over | target changed 210 → 200 with the date left ~14 days out | no — designed |

Evidence: the device's own plan journal, captured 09:20 via
`devicectl device process launch --console` (raw in
`scratchpad/console.txt`).

## What the journal proved

```
plan 08-17 22:32 act=699 restM=2108 restE=1814 wt=210
plan 08-18 07:05 act=0   restM=458  restE=1812 wt=209
plan 08-18 09:20 act=148 restM=841  restE=1812 wt=209
budget active=148 restingMeasured=841 restingEstimate=1812
       weightHealth=209 weightFallback=nil deficit=2453 intake=0
```

**The weight input never moved.** `wt=` is 210 → 209 across the whole
window, and `weightFallback=nil`. That **refutes H1 and H2** from the
first draft — there was no substitution of a stale stored weight, and
no 12 lb jump. The jump was in `target`, not in `weight`.

### (a) Aug 15/17 — the band rule, and it predates the target change

Target was 210 lb. The basis reached ~210.7 on Aug 15 and 210.0 on
Aug 17 — inside `GoalFinishLine.bandLb` (1 lb), so
`CalorieBudget.requiredDailyDeficit` returned **0** by design, and
`DeficitTargetHistory` stamped 0 for those days. Aug 14's basis was
~211.2, one notch outside the band, giving `1.17 × 3500 / 18 = 227`.

`GoalCard.isMaintenance` is `plan.requiredDailyDeficit <= 0`
(TodayView.swift:1980) — not the goal's mode. So a zero target flips
the whole card into the maintenance framing. That is the entire
mechanism, and it is working as specified.

### (b) Today — the target moved, the date did not

Target changed 210 → 200 shortly before 09:04. Basis 209.8, so
`9.81 × 3500 / 14 days = 2,453` — matching `deficit=2453` exactly, and
placing the saved target date at ~Sep 1. Budget is then
`1,956 − 2,453 = −497` → "+498 over". Every figure reconciles.

The Goal screen simultaneously projects arrival **between Sep 27 and
Oct 2**. The app knows the date is four weeks too early and saved it
anyway.

This also explains the "You hit your target" banner vanishing: at 07:05
the basis (209.7) was below the 210 target and the goal was genuinely
met; by 09:04 the target was 200 and it was not. Not a dismissal.

## The three real defects

**D1 — a sealed Health read silently rewrites a past day's badge rule.
NEW, and the most serious.**

The journal carries interleaved sealed reads throughout both days:

```
plan 08-17 20:33 act=0 restM=0 restE=NIL wt=NIL
plan 08-17 21:24 act=0 restM=0 restE=NIL wt=NIL
plan 08-18 03:40 act=0 restM=0 restE=NIL wt=NIL
plan 08-18 07:07 act=0 restM=0 restE=NIL wt=NIL
plan 08-18 09:06 act=0 restM=0 restE=NIL wt=NIL
```

`wt=NIL` is the sealed-store signature `HealthReadTrust` was written to
recognise — its own doc comment shows this exact pattern from
2026-08-08. The guard is live on the three RENDER paths
(`OnigiriWidgets/SnapshotLoader.swift:172`,
`OnigiriWatchWidgets.swift:69`, `WidgetBurnGate.swift:175`), so a
sealed read is never drawn as data.

**It is not on the PERSISTENCE path.** `DailyPlanLoader.load`
(line 214) stamps `DeficitTargetHistory.recordToday(targetKcal:)` after
every `computeState`, sealed or not. On a sealed read with
`fallbackCurrentWeightLb == nil` — true on this device —
`requiredDailyDeficit` returns nil, `deficitTargetKcal` is nil, and
`recordToday` writes **0**, i.e. "no goal, any deficit earns the
badge". "The last value recorded on a day stands", so a sealed read at
23:50 permanently re-grades that day.

This did not cause the Aug 15/17 report (the band rule accounts for
those on its own, and both produce the same 0). It is an independent
latent corruption of badge history, found only because the journal was
read. Fix: consult `healthReadLooksSealed` before stamping, or make
`recordToday` refuse a nil target when the goal is a live lose goal.

**D2 — a day's budget has no floor.** `completedDayPlan` returns
`dayBurn − deficit` with no guardrail and hardcodes
`isAggressive: false`. The floors that exist — `minReasonableBudget`
and `restingFloorKcal` — are only in `plan()`, the Goal-tab PREVIEW
path, never the one a day is judged by. So the budget went to −497 and
Today rendered "+498 over" at 09:04 with nothing eaten. Subtracting a
whole-day deficit from a 9am partial-day burn is the "over budget at
breakfast" failure the resting-up-front credit was meant to retire —
that reasoning holds only while the deficit is small next to the burn.

**D3 — the gauge changes what it measures without saying so.** Aug 14's
100% is `banked / required`. Aug 15's 35% is `1 − eaten / budget`. Same
ring, same "%", two incompatible scales — which is why "35%" beside
"🍙 earned" reads as a contradiction. And reaching the target is
narrated by silently borrowing maintenance vocabulary; the card never
says "you reached your target". `isMaintenance` (no target today) and
`isMaintenanceMode` (the goal's mode) are different booleans in the
same view and the card mixes them — title from the first,
`dayEarnedLook` from the second.

**D4 (product, not a bug) — editing the target weight should revisit
the target date.** `JourneyContinuity` correctly preserved the journey
(Progress reads 8.9 of 18.7 lb since Jul 7). Nothing revisits the date,
so a 10 lb extension inherited a two-week deadline and produced an
impossible 2,453 kcal/day. The projection needed to offer the date is
already on the same screen.

## Order of work

1. **D1** — highest value, silent, corrupts history. Guard the stamp.
2. **D2** — floor the day's budget; make the aggressive state
   stand the budget-shaped UI down rather than print a negative.
3. **D4** — on a target-weight change, offer the projected date.
4. **D3** — name the reached-target state; stop reusing the
   maintenance framing and the borrowed gauge scale.

Verify on device with a console launch, not a green test.

## Explicitly NOT to do

- Don't revert Aug 15's framing to Aug 14's. The framing is downstream
  of the target going to 0; when the goal really is met, deficit
  framing would be worse.
- Don't widen `GoalFinishLine.bandLb`. The band is what took the cliff
  out of the last pound.
- Don't restore a trailing-average burn floor to make mornings read
  better (PLAN-earned-budget: deleted on purpose).
