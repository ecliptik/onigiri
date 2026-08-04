# PLAN — Widget and complication burn freshness

**Symptom (the user, 2026-08-03):** the home-screen widget holds an older
number. Activity through the day raises the budget; the app shows the rise,
the widget does not — until the app is opened.

**Verdict:** not a bug in one place. There is *no push signal for burn at
all* on either device, and several separate mechanisms make the fallback
worse than its nominal one hour. Each is small; together they are the whole
symptom.

**Scope:** both bundles. The phone widgets and the watch complications
share the root cause and the shared refresh machinery, but their
amplifiers and their fixes differ enough that each phase below names both
devices explicitly. The watch is the more perverse case — see §3g.

---

## 1. Why the apps are always right

Both apps re-read HealthKit on every look, behind a short staleness gate:

- Phone: `TodayModel.foregrounded(healthWriteVersion:)`
  (`Onigiri/Models/TodayModel.swift:149`) — 30-second gate, and any Health
  write while backgrounded beats the gate outright.
- Watch: `WatchModel.refreshIfStale(maxAge: 30)`
  (`OnigiriWatch/WatchModel.swift:78`), driven from `WatchHomeView`'s
  `.task` and its wrist-raise handler (`WatchHomeView.swift:98`, `:101`).

Neither app caches a budget across a glance — each recomputes
`DayBudget.dayBurn` from live `activeEnergyBurned` / `basalEnergyBurned`.

So "the app is right" is not evidence the widget's data path is broken.
It is evidence the apps re-read and the widgets don't.

## 2. Root cause — nothing tells either widget bundle that burn moved

The budget is `DayBudget.dayBurn − requiredDeficit`, and within a single
day `dayBurn` moves on **one** input:

```swift
// Packages/OnigiriKit/Sources/OnigiriKit/DayBudget.swift:53
activeKcal + max(restingKcal, estimatedRestingKcal ?? 0)
```

Resting is credited up front, so it is flat from midnight (the `max`
holds it at the estimate until measured resting overtakes it, late in the
day). **Active energy is the only thing that moves the number during the
day** — which is exactly the input nothing observes.

The one push funnel into the widgets is `startObservingLogChanges`
(`HealthKitService.swift:91`) — a kit function, registered identically in
`OnigiriApp.init` (`OnigiriApp.swift:42`) and `OnigiriWatchApp.init`
(`OnigiriWatchApp.swift:24`). It observes exactly two types:

```swift
for identifier in [HKQuantityTypeIdentifier.dietaryEnergyConsumed, .dietaryWater]
```

`activeEnergyBurned` and `basalEnergyBurned` are in `readTypes`
(`HealthKitService.swift:48-49`) — authorized on both devices, read by
both, observed by neither. `startObservingWeightChanges` deliberately
excludes burn too, and says why in its own doc comment ("those move
continuously while you walk around"). That reasoning was right for the
Goal tab's 90-day average. It was never re-examined for a *today* figure.

Result: every widget-reload trigger in the codebase — on both devices — is
a **food/water/library/settings** trigger. A walk changes the number and
fires nothing, anywhere.

## 3. The amplifiers

Each of these independently stretches "up to an hour stale" into "stale
all afternoon". They compound.

### 3a. Both — the 1-hour poll is the entire fallback

`WidgetRefreshPolicy.pollFallback = 60 * 60` (`WidgetReloader.swift:7`).
All four phone providers use it verbatim (`GaugeWidget.swift:52`,
`TodayCardWidget.swift:54`, `AccessoryWidgets.swift:54`,
`MonthStatsWidget.swift:40`); all three watch providers reach it through
`nextPoll` (`OnigiriWatchWidgets.swift:106`, `:284`, `:448`). The comment
says "push-based reloads keep widgets fresh; this poll is only a
fallback" — true for food, false for burn, where the poll is the *only*
mechanism. Best case that is an hour of drift; WidgetKit's own deferral
makes it worse.

### 3b. Phone — "open the app" only works on a cold launch

The foreground reload the user relies on is not guaranteed. Foregrounding
runs `PhoneSyncService.push` (`ContentView.swift:110`), which reloads
widgets **only when the payload fingerprint moved**
(`PhoneSyncService.swift:201`, `:212`). Those fingerprints are in-memory
instance state (`PhoneSyncService.swift:30-35`), so the first push of a
*process* always goes through — and a warm foreground with no library or
settings change goes through **nothing**. Nothing else in the foreground
path calls `WidgetReloader`.

Cold launch → `requestReloadAll` → widget correct. Switching back to a
resident process → no reload at all. The user's own workaround is a coin
flip on whether iOS kept the process.

### 3c. Phone — a locked-phone poll burns the hour and re-commits the stale value

`SnapshotLoader.load()` (`SnapshotLoader.swift:120`) returns the cached
last-good snapshot when the Health store is sealed — correct, and the
comment explains why (stale-but-true beats confident zeros). But the
provider then wraps that known-stale snapshot in a full timeline with
`policy: .after(now + 1h)`.

The phone is locked in a pocket for most of the walk. The poll that
should have caught the new burn lands while sealed, serves the old value,
and re-commits it for another hour. Nothing re-reloads on unlock.

### 3d. Watch — the short-poll window opens on a *food* stamp

The watch is the only place with a sub-hour cadence, and it is aimed at
the wrong event:

```swift
// WidgetReloader.swift:18 — nextPoll
guard let lastLogAt, abs(now.timeIntervalSince(lastLogAt)) < postLogWindow
else { return pollFallback }
return postLogPoll                      // 8 min, inside a 20-min window
```

`lastLogAt` is `WatchSync.lastPhoneLogAt()` — the stamp the phone writes
when *food or water* is logged (`OnigiriApp.swift:56`). Burn never opens
the window. A walk with no logging leaves the complication on the flat
hourly fallback, exactly like the phone.

### 3e. Watch — the app never schedules a background refresh

`OnigiriWatchApp` declares one background hook,
`.backgroundTask(.watchConnectivity)` (`OnigiriWatchApp.swift:89`). There
is no app-refresh scheduling anywhere in the watch target — no
`BGAppRefreshTaskRequest`, no `scheduleBackgroundRefresh`. watchOS gives a
complication-bearing app a materially better app-refresh allowance than
iOS gives a plain app, and it is the standard way a complication stays
current between timeline turns. Onigiri leaves it entirely unused.

### 3f. Watch — no last-good snapshot, so a sealed store renders zeros

The phone's locked-store guard has no watch equivalent. The watch
providers call `PlanCache.state` directly (`OnigiriWatchWidgets.swift:131-
133`) with no lock check and no cache, and `DailyPlanLoader.computeState`
swallows a failed read as `.zero`:

```swift
// DailyPlanLoader.swift:213
let summary = (try? await summaryRead) ?? .zero
```

A reload against a sealed watch store therefore renders a *confident
zero day* — the exact failure `SnapshotLoader`'s `lastGoodKey` exists to
prevent on the phone. This is a latent correctness bug, not just a
freshness one, and it gets more likely the moment we increase the watch's
reload rate. Fix it in the same round.

### 3g. Watch — the hourly cap, and the irony

watchOS silently caps most types' background delivery at hourly
regardless of the requested `.immediate` — the codebase already knows
this and says so at `HealthKitService.swift:98`. So the phone's observer
fix (§5, Phase 2) does not transfer verbatim; the watch needs Phase 2b.

Which is backwards, because **the watch is where active energy
originates**. Its own HealthKit store holds the samples first; the phone
receives them later over HealthKit's device sync. The device with the
freshest possible burn data has the stalest surface and the tightest
delivery cap. That asymmetry is the reason the watch gets its own tactic
rather than a copy of the phone's.

### 3h. Not a cause — `PlanCache`

`PlanCache.ttl = 60` seconds, cross-process versioned
(`PlanCache.swift:20`), shared by both bundles. A reload always
recomputes from Health. The cache is doing its job; it is not part of
this.

---

## 4. Rejected before anyone tries them

- **Project future active burn into pre-rendered entries.** The obvious
  "fix it without more reloads" move, and forbidden by the model: active
  is *earned*, "raw measured, never filled, never estimated"
  (`DayBudget.swift:39-43`, CLAUDE.md). A projected budget is the
  trailing-average model that was deliberately deleted. The midnight entry
  works precisely because it derives from the *plan*, not from Health; a
  burn projection does not.
- **Just shorten `pollFallback` to 15 minutes.** 96 reloads/day against
  WidgetKit's ~40–70/day budget. The widget updates well for an hour and
  then freezes for the rest of the day — strictly worse than today, and
  the exact documented trap. Doubly bad on the watch, whose budget is
  tighter and whose poll already burns extra turns inside the post-log
  window.
- **`.immediate` background delivery on burn with no gate.** The watch
  syncs active energy in small batches continuously; this wakes the app
  dozens of times an hour and spends the reload budget on 3-kcal deltas.
  The gate in Phase 2 is what makes `.immediate` affordable.
- **APNs widget push (watchOS 26+).** The textbook answer for
  unpredictable complication data, and unavailable here: it needs a paid
  developer account and a server to push from. Onigiri is a free personal
  team, device-local by design (CLAUDE.md). Not an option, now or after a
  paid account — there is no backend to originate the push.
- **`transferCurrentComplicationUserInfo` from the phone on every burn
  change.** A 50/day Watch Connectivity budget, silently throttled past
  it, and it would make the watch's freshness depend on the phone
  observing data the watch already has locally. Wrong direction (§3g).

---

## 5. The plan

Ordered by ratio of symptom removed to risk taken. Phases 1 and 2 are the
fix; 3 and 4 are the polish. Every phase names both devices.

### Phase 1 — make the known workaround reliable

Small, no new signals, no entitlements.

- **Phone:** add an explicit widget reload to the `.active` scenePhase
  branch in `ContentView.swift:109`, independent of the sync fingerprint.
- **Watch:** the same gap exists — `OnigiriWatchApp.swift:67` only handles
  `phase != .active` (the flush). Add the `.active` reload request there.
  `WatchModel` already refreshes the *app's* numbers on foreground; the
  complications are not reloaded by anything.

Throttle both in `WidgetReloader` to at most once per few minutes so
tab-flipping and wrist-raises can't spend the budget.

Why first: a handful of reloads/day, no new machinery, and it converts
"opening the app usually fixes it" into "opening the app always fixes
it" on both devices. It does not fix the glance-only case, which is
Phase 2.

### Phase 2 — a burn signal, gated so it fits the budget

**The gate is shared** (new, in `WidgetRefreshPolicy` — pure logic, unit
tested in the kit, used by both devices). Reload only when *both* hold:

- the ratcheted day burn has risen by **≥ ~40 kcal** since the value the
  widget last rendered, **and**
- **≥ ~10 minutes** have passed since the last burn-driven reload.

The "current" side comes from `TodayBurnFloor` (`TodayBurnFloor.swift:21`),
already the app-group high-water mark each device derives its budget from —
so the gate cannot disagree with what the widget will render. The "last
rendered" side needs a new app-group key written where the snapshot is
built (phone: beside `widget.lastGoodSnapshot`,
`SnapshotLoader.swift:159`; watch: in the providers' `load()`). Note both
devices keep *their own* mark over their own store, per CLAUDE.md — the
gate must stay per-device, not synced.

Worst case spend: a 600-kcal active day with a 40-kcal gate is ~15
reloads. Inside budget, and every one changes pixels.

**Phone — two new observers:**

1. `HKWorkoutType`, background delivery `.immediate`. A finished workout
   is discrete, few-per-day, and the single largest jump the budget ever
   takes. This is "as I do activity my budget increases" in its most
   literal form, and it is nearly free.
2. `activeEnergyBurned`, background delivery `.immediate`, behind the
   gate — the ambient drift a workout never captures.

**Watch — the same two observers, plus Phase 2b.** Register them
identically (the kit function should take the types, so both apps call
one implementation). But assume `.immediate` is capped to hourly here
(§3g) until measured — `activeEnergyBurned` may or may not be one of the
"handful of fitness types" watchOS honors, and that is an empirical
question this plan does not get to answer from documentation. Measure it
in Phase 0; if it is capped, 2b carries the watch.

Both observers, both devices, must call their completion handler on every
path — HealthKit disables background delivery after three misses. Follow
the `defer { done() }` shape the existing observer uses.

### Phase 2b — watch only: schedule the refresh watchOS is willing to give

Close §3e. Chain an app-refresh task: each wake runs the shared gate,
reloads the complications if it passes, and re-arms the next request.

Use `BGAppRefreshTaskRequest` + `.backgroundTask(.appRefresh("<id>"))`
with the identifier in the watch Info.plist's
`BGTaskSchedulerPermittedIdentifiers` — the legacy
`WKApplication.scheduleBackgroundRefresh(withPreferredDate:userInfo:)`
path is deprecated on the 27 SDK. Check the watch target's deployment
target before choosing; if it predates the BackgroundTasks-on-watchOS
availability, use the legacy call and note the migration.

This is the watch's answer to the hourly delivery cap: the wake cadence
comes from watchOS's app-refresh allowance (better for an app with a
complication on the active face) rather than from HealthKit's delivery
frequency. Re-arm on *every* wake, including gate-blocked ones, or the
chain dies silently after the first quiet hour.

### Phase 3 — spend the poll where the day is

- **Phone:** replace the flat `pollFallback` with a waking-hours cadence —
  ~45 min between 07:00 and 23:00, ~3 h overnight. ~29 daytime + ~2
  overnight ≈ 31/day versus 24 today: more freshness when it matters,
  *less* budget overnight, and room left for Phase 2's event reloads.
- **Watch:** fix §3d by widening what opens the short window. `nextPoll`'s
  `lastLogAt` parameter should become a general "something moved recently"
  stamp that a burn event also writes — rename the concept off "post-log"
  while touching it, since it will no longer mean that. Keep the existing
  8-minute/20-minute shape; it is already the right idea aimed at the
  wrong event.

Keep the midnight entry riding every timeline on both devices exactly as
it does now. That rule is load-bearing and independent of everything here
(`SnapshotLoader.swift:93-107`, `OnigiriWatchWidgets.swift:111-115`); do
not touch it.

### Phase 4 — sealed stores

- **Phone:** when `SnapshotLoader` served the cached snapshot because the
  store was sealed, return `policy: .after(now + ~10 min)` instead of the
  full fallback. The snapshot is *known* stale — retry soon, not in an
  hour. Needs `load()` to report the locked path (a flag alongside the
  snapshot, or a non-persisted `wasCached` on `DaySnapshot`). While in
  there, stamp the cached snapshot with its capture time; nothing
  currently records how old a last-good blob is.
- **Watch:** give the watch providers the last-good cache it never had
  (§3f) — the same `isStoreLocked()` check and the same persisted-snapshot
  fallback, so a sealed read renders yesterday's truth instead of a
  confident zero day. Then apply the same short retry policy. This is the
  one item here that is a correctness fix, not a freshness one, and it
  becomes more likely the moment Phase 2b raises the watch's reload rate —
  so it ships in the same round as 2b, not after it.

---

## 6. Verification

Simulator cannot test this. HealthKit background delivery does not run on
the Simulator, and the earned-budget path needs seeded body metrics
(CLAUDE.md's seeder note). Device job — `scripts/deploy-phone.sh` already
installs both the phone and the watch.

**Phase 0, before changing anything:** add an `os_log` line at the top of
every provider's `getTimeline` in both bundles (kind + timestamp + the
dayBurn it rendered) and run a normal day with the watch worn. Capture
with `log collect` / `xclog`. This gives:

- the actual reload cadence per kind per device, and whether WidgetKit is
  already deferring the hourly poll;
- any existing "budget exhausted" message;
- **the answer to §3g** — register a throwaway `activeEnergyBurned`
  observer on the watch with `.immediate` and log every fire. If the
  fires are hourly, the cap applies and Phase 2b carries the watch; if
  they are minutes apart, the watch gets the phone's tactic too and 2b
  becomes optional.

Every threshold in Phases 2 and 3 is a guess until this run exists.

**Acceptance test**, on device, watch worn, both apps force-quit:

1. Note the figure on the home-screen widget *and* on a watch face
   complication.
2. Walk 20–30 minutes without touching either device.
3. Raise the wrist and unlock the phone — look at both surfaces *without
   opening Onigiri on either*.
4. Both show the higher budget within a few minutes of the walk.
5. Open each app — the numbers must already match, not jump.

Then leave the build on both devices for a full day and re-check the log
for budget exhaustion. A widget that updates beautifully until 3pm and
then freezes is the failure mode this plan is most likely to produce.

**Regression guards:**

- Logging food still reloads within the existing 2-second debounce, on
  both devices.
- The midnight rollover still renders from the pre-built entry with no
  reload — leave both devices idle overnight and check the morning
  figures (the 2026-07-26 lesson).
- A phone log still opens the watch's short-poll window after the Phase 3
  rename (§3d) — that path is load-bearing and easy to break while
  generalizing the stamp.
- Watch off-wrist overnight, then wrist-raise: the complication shows
  stale-but-true numbers, never zeros (§3f).

---

## 7. Files

| File | Change |
|---|---|
| `Onigiri/ContentView.swift` | Phase 1 — phone foreground reload |
| `OnigiriWatch/OnigiriWatchApp.swift` | Phase 1 — watch foreground reload; Phase 2 observers; Phase 2b app-refresh hook |
| `OnigiriWatch/Info.plist` (via `project.yml`) | Phase 2b — `BGTaskSchedulerPermittedIdentifiers` |
| `Packages/OnigiriKit/Sources/OnigiriKit/WidgetReloader.swift` | Phase 1 throttle; Phase 2 gate; Phase 3 cadence + `nextPoll` generalization |
| `Packages/OnigiriKit/Sources/OnigiriKit/HealthKitService.swift` | Phase 2 — `startObservingBurnChanges` + workout observer, shared by both apps |
| `Onigiri/OnigiriApp.swift` | Phase 2 — register them in `init` (not a view) |
| `OnigiriWidgets/SnapshotLoader.swift` | Phase 2 last-rendered-burn key; Phase 4 locked flag + capture stamp |
| `OnigiriWidgets/{Gauge,TodayCard,Accessory,MonthStats}*.swift` | Phase 3/4 policy — all four move together |
| `OnigiriWatchWidgets/OnigiriWatchWidgets.swift` | Phase 2 last-rendered-burn key; Phase 4 last-good cache + lock check; Phase 3 policy — all three providers move together |
| `Packages/OnigiriKit/Tests/` | Pure tests for the gate, the cadence, and the generalized `nextPoll` |

---

## 8. Sequencing

1. **Phase 0** on both devices — a day of logging. Nothing else starts
   until the numbers exist.
2. **Phase 1**, both devices. Ship it alone; it is independently useful
   and it makes the rest measurable against a known-good workaround.
3. **Phase 2 + 2b + Phase 4's watch half**, together. The watch's cache
   fix must not lag the watch's reload-rate increase.
4. **Phase 3**, last, tuned to what Phase 0 and the Phase 2 logs show
   about remaining budget.
