# Tab bar: the Liquid Glass indicator sticks on Foods landing on Today

2026-09-15. The user: switching tabs feels janky; specifically, on a
Calendar→Today jump the glass selection highlight "sort of pauses on
Foods," and after one fix attempt Today "flashes twice." Only jumps that
LAND on Today stick — Today→Goal/Calendar (same distance, same tabs
passed) never do. Reduce Motion is off. Phone: iPhone 16, iOS 27.0.

## What is measured, not guessed

Frame-accurate captures of the user's own screen recordings (native
~60 fps, tab-bar crop, per-frame pixel diff + orange-highlight centroid;
scripts in this session, method reusable):

- Landing on Today takes ~720 ms tap-to-settle vs ~500 ms landing on
  Foods, with a sustained low-amplitude flicker in the tail Foods lacks.
- On a Calendar→Today jump the highlight slides Calendar→Goal→Foods
  with each leg resolving in ONE frame, then sits fully formed and
  unchanging on Foods for ~12 frames (~200 ms), then completes the last
  hop. Reproduced in three separate recordings. Not a crossfade
  artifact of the centroid: verified by eye on the frames.
- Every transition, any tab, shows one ~30× single-frame diff spike —
  a compositor/recording hiccup common to all of them. Not the bug.
- The "flashes twice" regression (the deferred-stamp build) is a real
  double commit: the highlight reaches Today, jumps BACK to x≈325,
  returns, resettles ~150 ms later.
- The tracker (`analyze_probe.py`, session scratch; auto-calibrates the
  icon centres from still frames, then counts per-icon dwell frames on
  every transition that lands on Today) reproduces the stall on the
  2026-09-15 13:59 recording without any hand labelling: three
  Calendar→Today jumps, each ~300 ms of motion, dwell 3 / 9 / 11 frames
  in the Foods band against 2 / 2 / 2 in Goal's. The stall is a
  distribution, not a duration — the total barely moves, the middle of
  the slide does.

## App-side work eliminated so far (all kept — each was real)

1. `TodayModel.start()` repeat-visit branch called `refresh()` ungated
   (5 HealthKit reads + 6 `@Observable` writes per tab bounce). Gated on
   `refreshGate.isStale(maxAge: 30)`, the Goal/Calendar pattern.
2. `CalendarView`'s `.task` ungated the same way; routed through
   `shouldForegroundRefresh`. `GoalView` re-derived trend stats every
   visit; now only on first load or an actual refresh.
3. `TodayModel.select(day:)` — the destination of EVERY Today tap via
   `dayRequest` — refreshed and wrote `selectedDate`/`followsToday`
   unconditionally. `@Observable` does not skip an equal write. Both
   gated on the day actually changing.
4. `tabSelection` binding: `selectedTab` first, `dayRequest` stamp
   deferred a turn; the ContentView `onChange` re-write guarded.
5. `TodayView.consumeQuickLogRequest()` made a genuine no-op when
   already on today with no sheet request (no `navPath.removeAll()`, no
   `Task`, no model call).

Precedent: `16088cc` (2026-07-14) fixed the same class — "@Observable
fires on every set, equal value or not — and each fire re-evaluates the
TabView" — with an equality-guarded commit. Same lesson, same shape.

**After all five, the user reports the stick and the flash unchanged.**
That is the finding: the app-side reaction to landing on Today is no
longer the cause, or never was the whole cause.

Ruled out: legacy `LaunchImage` (Apple forums 809465's Liquid Glass
tab-bar hang root cause) — Onigiri uses `UILaunchScreen`.

## Simulator results (2026-09-15, same tracker)

| Build | OS | Calendar→Today total | frames | Foods-band | Goal-band |
|---|---|---|---|---|---|
| user's phone, real app | 27.0 (iPhone 16) | ~300–317 ms | 19–20 @17 ms | 9 / 11 (3 once) | 2 |
| real app, `testTabBarAnimationProbe` | 26.5 sim | ~148–150 ms | 14 @8–10 ms | 5–6 | 1 |
| **stock 5-tab `StockTabProbe`** (same shape: `.sidebarAdaptable`, `.tint`, search-role +) | **27.0 sim** | **~137 ms** | 10 @17 ms | **2** | 1 |

| **real app**, `--tab-probe-no-health` (skips the auth sheet; dayRequest disabled as on the phone) | **27.0 sim** | **~133–142 ms** | 10–12 @13–17 ms | **2** | — |

Neither the stock shape nor the real app sticks on the 27.0 simulator.
The stall reproduces only on the physical iPhone 16. Not the OS tab
bar, not the Today-tap logic (disabled in both). What a device has
that the sim doesn't is the GPU path Liquid Glass depends on: the bar
samples the content beneath it. The one thing added to Today's and
Foods' ROOT views the day before the report — and to neither Goal's nor
Calendar's, matching the reported asymmetry — is `.recedesBehindSheet`
(05d8f91/ce8ca2f, 2026-09-13/14), which keeps a `.blur(radius: 0)`
filter on the whole screen while no sheet is up. Phase 3 on the phone
starts there: one variable at a time, the user judging.

(The 27.0 Health sheet: its Allow is a StaticText at the bottom of the
topic list, not a Button; `grantHealthAccess` knows both shapes now but
XCUITest could not scroll it into view, so the probe skips Health via
`--tab-probe-no-health` instead.)

## Plan

**Phase 1 — bisect app vs OS (deployed, awaiting the user).** A
diagnostic build with the `dayRequest` stamp disabled outright
(`if false, tapped == .today` in `tabSelection`; "tap Today to return
to today" intentionally broken). Still sticks ⇒ no app reaction to the
tap is involved; go to Phase 2. Smooth ⇒ the cascade is the cause and
the no-op guard in (5) is not reaching the real work; instrument it.
**Revert this build either way.**

**Phase 2 — reproduce on the iOS 27.0 simulator.** `testTabBarAnimationProbe`
(`TEST_RUNNER_TAB_PROBE=1`) drives Calendar→Today ×3 with dwells plus
Today→Calendar and Foods→Today controls, under `simctl io recordVideo`.
Same frame analysis. If it reproduces, every later step iterates here
in ~2 min instead of a phone round-trip. Run the SAME build on the
26.5 sim as the OS baseline.

**Phase 3 — structural bisection of the TabView (simulator).** One
modifier per build, same probe, same metric: `.tabViewStyle
(.sidebarAdaptable)` → `.automatic`; drop `.tint`; drop the VoiceOver
`.overlay`; drop `.background(AddPillGestures)`; drop
`TabBarMinimizePin`; drop `Tab(role: .search)`; swap Today to a
different tab position. The asymmetry (index 0 only) suggests the
leading-edge tab or the search-role slot's presence.

**Phase 4 — OS baseline.** A stock 5-tab `TabView` sample with the same
shape on the 27.0 sim. If the stock sample sticks too, this is Apple's
rendering (like the Add pill's 26→27 change) and gets documented, not
chased; file feedback with the frame data.

**Phase 5 — land it.** Apply the isolated fix or the documentation;
revert Phase 1; `testTodayTabReturnsToTodaysDate` green; deploy; a
CLAUDE.md landmine entry — this class has now cost sessions on
2026-07-14 and 2026-09-15.

## Open

- Whether the ~200 ms Foods dwell is a second animation being queued
  (Foods→Today) after a first (Calendar→Foods) rather than one slide —
  the per-leg timing (1 frame, 1 frame, then a hold) reads that way.
- Why index 0 only. `@SceneStorage` default, `NavigationStack(path:)`
  root, `.recedesBehindSheet` on the stack — each is Today-specific and
  each is a Phase 3 candidate.

## Resolution (2026-09-15)

Phase 3, first variable, on the phone: `RecedesBehindSheet` rewritten to
branch (`if isPresenting { content.blur(radius: 12) } else { content }`)
instead of `.blur(radius: isPresenting ? 12 : 0)`, everything else
held (Today-tap stamp still disabled) — the user: "Much better now."
That is the cause: a zero-radius blur keeps a filter on the whole
rendered output the Liquid Glass bar samples, and only Today and Foods
carried it. Shipped as the fix; the Today-tap stamp restored to its
original synchronous form (the deferral was the double-flash); the five
gates kept as the real waste they were; probe test, stock-TabView
harness, `--tab-probe-no-health` and `scripts/analyze-tab-probe.py` kept
for next time. CLAUDE.md carries the landmine.

Not answered, and not needed to ship: why the simulator's compositor
hides it, and whether the phone's ProMotion-less 60 Hz panel matters.
If it returns, the probe + analyzer give a number in one run.

## Second cause (2026-09-16): the Today-tap stamp

It came back. The user, the evening after the blur fix shipped: "the
stuttering of the liquid glass selector when moving to Today is back."

Measured, not guessed, with the probe and analyzer this plan left
behind, on the 27.0 simulator (iPhone 18 Pro), `--tab-probe-no-health`,
Calendar→Today ×3 (the analyzer labels the origin by the first settled
icon it sees, hence "Goal→Today" in its own output):

| Build | tap-to-settle | frames | Foods-band dwell |
|---|---|---|---|
| HEAD of `log-sheet-layout` (native headers) | ~283 ms | 20 | 10 |
| same, `.inlineLarge` off everywhere | 267–287 ms | 17–25 | 7 / 8 / 10 |
| **branch point `f06e555`** (the blur fix, as shipped) | 263–303 ms | 20–23 | 6 / 7 / 2 |
| HEAD, Today-tap stamp disabled (this plan's Phase 1) | 135–152 ms | 10–11 | 2 / 3 / 3 |
| HEAD, the fix below (`todayTabTapped`) | 133–148 ms | 11–12 | 3 / 3 / 4 |

So the header rework was innocent, and so was the simulator's
reputation: the sim never showed the FIRST cause (a GPU filter), but it
shows this one plainly. Which also explains the table above: this plan's
clean "real app on the 27.0 sim" row was measured on the Phase 1
diagnostic build — stamp disabled — and the blur fix was then verified
on the phone in that same state ("Much better now") and shipped with the
stamp restored. Two causes, one symptom; removing either one alone
helps, removing both is smooth.

The mechanism: `ContentView.tabSelection`'s setter wrote the OBSERVED
`quickActions.dayRequest` on every user tap of Today, switches included,
synchronously before `selectedTab`. ContentView's body observes that
property (its `onChange` for Calendar's "View day"), so the write re-ran
the body — the whole `TabView` — as the slide began; `TodayView`'s
consumer then wrote it back to `nil`, re-running it again. Two TabView
re-evaluations inside a ~140 ms animation. The five gates of 2026-09-15
made Today's REACTION a no-op and left the writes in place, which is
why they changed nothing.

Fix: a SWITCH to Today sets `QuickActions.todayTabTapped`, an
`@ObservationIgnored` Bool no view observes; `TodayView` consumes it on
appear (a tab switch always fires it) and browses home — a no-op when
already on today with nothing pushed. A RE-TAP, with no slide to
disturb, still raises `dayRequest` and shares the "View day" consumer.
Deferring the observed write a runloop turn (tried 2026-09-15) is not an
alternative: the double commit it caused is the "flashes twice" above.

Two rules come out of it. Nothing ContentView's body observes may be
written from the TabView selection setter. And verify a fix on a build
with every diagnostic toggle at its SHIPPING value — a diagnostic left
flipped through verification can be the fix without anyone noticing.
