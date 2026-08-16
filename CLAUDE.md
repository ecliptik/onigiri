# Onigiri — agent notes

Personal iOS + watchOS calorie/sodium/water tracker.

**What belongs in this file:** rules the code cannot tell you, and landmines
that each cost a debugging session. **What does not:** anything derivable by
reading the code, per-release history (`CHANGELOG.md`, `git log`), or rationale
long enough to be its own document — those live in `plans/` and get linked from
here. Roadmap: `plans/PLAN.md`.

**Working on it:** [Repo/docs](#repo-docs-license) ·
[Build](#build-and-test) · [Deploy](#deploying-to-devices) ·
[Simulator](#simulator-automation) · [Widgets](#widget-timelines) ·
[SwiftData/SwiftUI](#swiftdata-and-swiftui-landmines) ·
[App launch](#app-launch-landmines)
**Rules of the app:** [Where code lives](#where-code-lives) ·
[Logging](#logging-healthkit-is-the-store) ·
[Budget](#the-budget-and-what-may-judge-a-day) ·
[Weight](#weight-which-reading-may-judge) · [Watch sync](#watch-sync) ·
[Units](#units) · [Food entry](#food-entry-search-scan-images) ·
[Library rows](#library-rows) · [Copy](#copy)

## Repo, docs, license

- ORIGIN is GitHub (github.com/ecliptik/onigiri); Forgejo rides as a second
  push URL on origin, so one `git push` updates both. Fetch comes from GitHub.
- `docs/` IS the GitHub Pages site (marketing index.html + privacy.md +
  showcase/media assets) — anything committed there is published on push.
  Internal design docs live in `plans/`. The user guide lives ONLY in the
  GitHub wiki (onigiri.wiki.git); the privacy policy lives in both (site
  canonical). The site's screenshots/clips exist in BOTH appearances
  (showcase/light + showcase/dark, media/*.mp4 + *-dark.mp4) and swap with
  the site theme — recapture both when screens change.
- Verify site media by PROBING it, not by looking: two container-metadata
  faults render wrong ONLY in a browser while sips/Finder/QuickTime show them
  fine — an empty edit list (`elst` `media time: -1`, left by `-ss` BEFORE
  `-i`) loops through black, and an EXIF orientation tag (which `sips -r`
  writes) stands a landscape PNG on its side. Both bit 2026-08-02.
- `plans/PLAN-site-and-media.md` has the rest: the site's theme contract, the
  wiki's push quirks, and the full capture recipe for the stills and clips —
  including the probes for the two faults above, which device the committed
  assets come from, and why the calendar shot must be taken mid-month.
- License: PolyForm Noncommercial 1.0.0 since the commit after the v2.2.0
  tag (≤ v2.2.0 remains MIT, irrevocably). Say "source-available, free for
  noncommercial use", never "open source". LICENSE is verbatim PolyForm text —
  never edit or paraphrase it, and the Required Notice line in the README's
  License section must survive edits. External PRs are declined by policy
  (CONTRIBUTING.md) so no CLA machinery is needed; if one is ever accepted,
  rights have to be resolved first. The branding clause reserves the Onigiri
  name and icon — forks must rename.

## Build and test

- `xcode-select` may point at CommandLineTools; prefix Xcode commands with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if so.
- `xcodebuild`/`simctl` fail under the Bash sandbox (temp caches, CoreSimulator
  XPC) — run them with the sandbox disabled.
- The `.xcodeproj` is generated and gitignored — after editing `project.yml`,
  run `xcodegen generate`. A NEW test file also needs it before it is in the
  target; without it `xcodebuild` reports `** TEST SUCCEEDED **` having
  executed zero tests. Always read the `Executed N tests` line, never the
  banner.

```sh
xcodegen generate
xcodebuild -project Onigiri.xcodeproj -scheme Onigiri \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
  # builds the watch app too (embedded). Do NOT pass CODE_SIGNING_ALLOWED=NO:
  # it strips the HealthKit entitlement; ad-hoc simulator signing needs no team.
cd Packages/OnigiriKit && swift test     # pure-logic tests; ALSO needs the
  # DEVELOPER_DIR prefix or @Model/#Preview macro plugins aren't found.
```

- `OnigiriTests` (app-hosted) is the Foundation Models eval suite for
  `FoodIntelligence` — golden sets with plausibility gates for describe-it,
  meal names, and label refinement. Opt-in (minutes of inference) and
  self-skipping: it needs `TEST_RUNNER_ONIGIRI_AI_EVALS=1` AND an available
  model (an iOS 26+ simulator works: verified 2026-07-16 on the 26.5 sim WITH
  the host Mac's Apple Intelligence off, even though macOS-side
  FoundationModels reported appleIntelligenceNotEnabled — trust the suite's
  own skip/run behavior, and never trust a green run without checking for
  skips). Re-run after ANY prompt change in FoodIntelligence.swift and after
  OS updates (the model moves under the app). Thresholds live in `Gate` — set
  before tuning; change them only deliberately, in a commit that says why.

```sh
TEST_RUNNER_ONIGIRI_AI_EVALS=1 xcodebuild -project Onigiri.xcodeproj \
  -scheme Onigiri -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath build test -only-testing:OnigiriTests
```

- Commits are GPG-signed: run `git commit` with the sandbox disabled (gpg needs
  `~/.gnupg`). If it fails with "Operation cancelled", the passphrase cache
  expired and pinentry can't prompt from the agent shell — ask the user to run
  `! gpg --clearsign -o /dev/null <<< test` to prime gpg-agent, then retry.
- Releases: `scripts/release.sh <version> -F notes.md` (the version bump is a
  separate commit first, and `-F` is required — `$EDITOR` can't open from an
  agent shell). It signs the tag, pushes both remotes, publishes the GitHub
  Release, and regenerates CHANGELOG.md from the tag message.

## Deploying to devices

- **Repeated watch install failures (CoreDeviceError 4000 / tunnel timeouts)
  with the watch demonstrably awake usually mean the MAC-side daemon is
  wedged, not the watch.** Diagnose with `xcrun devicectl list devices` —
  "Timed out waiting for CoreDeviceService to fully initialize" confirms it.
  Fix: `pkill -f CoreDeviceService` (no sudo needed), wait ~15 s for the
  watch to reach "connecting/connected", then install. Don't send the user
  chasing watch reboots until this is ruled out.
- **4000 / RemotePairingError-1001 / 3002 / `IXRemoteErrorDomain code 6`
  on the first attempts are normal — the install attempt itself is what
  wakes the channel.** deploy-phone.sh runs that retry loop, so don't
  build one by hand and never gate the watch on a one-shot
  `list devices` (a not-yet-enumerated watch reads as "unreachable" and
  gets silently skipped). Typical is success within 1–3 attempts;
  12 has happened.
- **`devicectl list devices` reading `unavailable` is NOT that failure
  family** — it means the watch is off-wrist, asleep, or out of range,
  and no amount of retrying fixes it. `available (paired)` is the state
  installs succeed from. Check this before starting a deploy: it costs
  one command and saves a 12-attempt loop that was never going to work
  (2026-08-10).
- **Watch discovery requires Mac BLUETOOTH ON.** Two days of debugging
  (reboots, re-pairing, trust resets, cache wipes, VPN toggles) and the watch
  never appeared in Xcode/devicectl until the Mac's Bluetooth was enabled —
  the Mac↔watch developer channel bootstraps over BT/AWDL. Check this FIRST.
- Address the watch by ID, not display name (the curly apostrophe matches
  neither tool): xcodebuild wants the hardware UDID, devicectl wants the
  CoreDevice identifier. Both live in scripts/local-devices.env (gitignored;
  copy the .example).
- `scripts/deploy-phone.sh` builds and installs on BOTH the configured iPhone
  and the watch (override with `DEVICE_NAME=…` / `WATCH_BUILD_ID=…` /
  `WATCH_INSTALL_ID=…`). Run weekly — free-team provisioning expires after 7
  days. Works over the network tunnel; phone and watch must be unlocked (watch
  on wrist, near the Mac).
- To verify a device install actually runs: `devicectl device process launch
  --console <bundle id>` prints crash reasons (e.g. SwiftData fatals) that never
  reach any log file. Requires the phone unlocked.

## Simulator automation

- XCUITest can drive springboard (`XCUIApplication(bundleIdentifier: "com.apple.springboard")`)
  for home-screen/widget-gallery flows; coordinate clicking via osascript/cliclick is
  unreliable for small controls. Health permission sheets have stable `UIA.Health.*`
  accessibility identifiers.
- Pass env vars to UI tests via `TEST_RUNNER_<NAME>=… xcodebuild test …`.
  `testAddWidgetToHomeScreen` (opt-in via `TEST_RUNNER_ADD_WIDGET=1`) installs
  the widget on the simulator home screen.
- **The iOS 26 tab bar is absent from the accessibility tree** that
  `axe describe-ui` dumps, so external drivers can't tap it. XCUITest's
  `app.tabBars.buttons[name]` resolves it fine — use a UI test for anything
  tab-bar-driven rather than coordinate taps (2026-08-14).
- The seeder DOES write body mass and active/basal energy. What made the
  earned-budget model invisible on a simulator was the resting ESTIMATE:
  `BasalEstimate` needs height and an AGE, and date of birth is a HealthKit
  CHARACTERISTIC no app can write. Fixed 2026-08-02 — the seeder writes a
  height sample and stamps `HealthKitService.debugSeededAgeKey`, which
  `bodyProfile()` reads in DEBUG only when Health has no birthday of its own.
  A correctly seeded sim shows "Resting burn ≈ 1,743 kcal/day" on Goal — a
  cheap check that the estimate is alive. Sex stays unspecified;
  BasalEstimate's midpoint constant covers it.
- **A green XCUITest proves nothing until you check WHAT it proved.**
  `waitForExistence` is not visibility or tappability (a present-but-unhittable
  list row still "exists"), and an "is it gone?" probe on an element that never
  appears passes forever while guarding nothing. Assert on something that can
  only be true when the behavior actually happened (2026-08-08).
- Three goal states a fresh sim can't otherwise reach without weeks of
  simulated weight change, each an extra launch argument beside
  `--seed-sample-data`: `--seed-goal-reached` (target above the seeded
  weigh-ins), `--seed-milestone` (a 210 lb start against a 190 target, so
  a 5 lb rung is passed and the target isn't), `--seed-regained`
  (maintenance held near 193, which the weigh-ins sit above).
- The iPhone and Watch sims are PAIRED and share Health data — erase BOTH before
  running the flow test, or seeded totals will be off (`simctl erase <both udids>`).
  Same for the iPad sim: every `--seed-sample-data` launch ADDS samples, so after
  a few QA runs the flow test's total assertions fail on stale data — erase first.
- **`simctl erase` FAILS on a BOOTED device** ("Unable to erase contents
  and settings in current state"). Shut down first, and never swallow its
  stderr: a silently-failed erase leaves the old container, and the next
  run tests stale state while looking like a code bug (cost a debugging
  detour 2026-08-10).
- UI-test capture runs leave the sim in their last orientation; tests that
  assume portrait must set `XCUIDevice.shared.orientation` themselves.
- Watch-window clicks need the window focused first (click its title bar); clicks
  silently stop landing after sheets open — relaunch the watch app to recover.
- The iOS 26.5 sim can't exercise Differentiate Without Color: the Settings
  toggle is inert to synthetic touch (as is the whole Settings switch layer)
  and writing the com.apple.Accessibility plist key changes nothing — verify
  DWC-gated UI on a device (done 2026-07-20). Synthesized taps also can't
  invoke a SwiftUI .accessibilityAction (only real VoiceOver's AXActivate
  can), so those need on-device VoiceOver too.
- Verifying scenePhase-transient UI (the PrivacyShield): single screenshots
  never catch it — record video through the background/foreground cycle and
  extract distinct frames (`ffmpeg -vsync vfr`). A constant-fps dump pads
  duplicates and LIES about what was on screen (looked like the sheet stayed
  visible; the VFR re-extraction showed the shield frame). 2026-07-20.
- Seeding app-group defaults from a test script takes TWO corrections, one
  each from 2026-07-21 and 2026-07-22. `simctl spawn <udid> defaults write
  group.com.ecliptik.Onigiri …` writes the sim's UNSANDBOXED root prefs, which
  the sandboxed app never sees — write the real container plist instead
  (`data/Containers/Shared/AppGroup/<UUID>/Library/Preferences/
  group.com.ecliptik.Onigiri.plist`, path minus `.plist`, app terminated
  first). AND run it via `simctl spawn`, not the host: a host-side write landed
  in the file but the app still read stale values, because the sim's own
  cfprefsd had the domain cached and served its copy.

## Widget timelines

- **Every provider's timeline carries the midnight entry, unconditionally.**
  A future-dated entry renders on schedule out of a timeline WidgetKit
  already holds — no reload, no budget. All seven providers used to
  append the pre-rendered new-day entry only `if midnight <= refresh`
  (i.e. only when the build landed in the last poll hour), which made
  correctness depend on the very reload the budget defers: a timeline
  built at 22:15 shipped ONE entry, the overnight reload never came, and
  the home-screen widget showed yesterday's kcal-left until the app was
  opened (2026-07-26). Keep the poll in `policy:`
  (`.after(min(refresh, midnight))`) and the rollover in the entries —
  they are not interchangeable.
- Pre-rendering needs a `newDay` transform that knows the gauge's
  direction: a deficit gauge starts empty, a maintenance gauge starts
  FULL (zero rendered an empty onigiri all morning). Anything derived
  from the plan rather than the day's samples survives the pre-render;
  anything read from Health does not.
- **Burn is the only input that moves the budget during a day, and for
  months nothing observed it** (2026-08-03,
  `plans/PLAN-widget-burn-freshness.md`). `DayBudget.dayBurn` is
  `active + max(resting, estimate)` and the resting term is flat, so
  ACTIVE energy alone moves the number — while every reload trigger in
  the app was a food/water/library/settings trigger. A walk changed the
  budget in the app (which re-queries on every foreground) and left the
  widget on its morning number until the app was opened.
  `startObservingBurnChanges` closes it. Three rules hold it shut:
  observe `activeEnergyBurned` ONLY — adding `HKWorkoutType` puts a new
  type in `readTypes`, flipping `statusForAuthorizationRequest` back to
  `.shouldRequest`, which `PlanCache.needsSetup` reads, so every widget
  paints "Open Onigiri to set up" over a working setup; every reload goes
  through `WidgetRefreshPolicy.shouldReloadForBurn` (≥40 kcal AND ≥10 min)
  because WidgetKit grants ~40–70 reloads/day and reloading per sample
  freezes the widget by mid-afternoon; and NEVER project future burn into
  pre-rendered entries — active is earned, which is the deleted
  trailing-average model.
- Opening the app used to reload widgets only as a SIDE EFFECT of the
  watch-sync push, which skips on an unchanged payload fingerprint —
  and those fingerprints are per-process, so a COLD launch reloaded and
  a warm foreground reloaded nothing. "Just open the app" worked or
  didn't depending on whether iOS had kept the process. Both apps now
  call `WidgetReloader.requestForegroundReload` explicitly.
- A sealed Health store (locked phone, watch off wrist) must never be
  rendered as data. The phone had `widget.lastGoodSnapshot`; the watch
  had NOTHING, so a reload against a sealed watch store fell through
  `DailyPlanLoader`'s `(try? …) ?? .zero` and rendered a confident ZERO
  DAY (`WatchStateCache` fixes it). And a provider that served a cached
  snapshot must come back in minutes, not commit the full cadence to a
  value it already knows is stale.

## SwiftData and SwiftUI landmines

Each cost a debugging session.

- Every relationship needs an explicit inverse. Without one, deleting the target
  leaves a dangling reference, and SwiftData KILLS THE PROCESS ("backing data
  could no longer be found") on the next property access — the app crash-looped
  at launch because the watch-sync push computes meal totals.
- A SwiftData-level repair can't fix that state (inspecting the reference traps
  too). `LibraryMaintenance.repairStore(at:)` opens the store with Core Data
  first — `objectIDs(forRelationshipNamed:)` reads references without firing
  faults — and must set `NSPersistentHistoryTrackingKey` or the store mounts
  read-only and the save silently fails.
- **Never resolve a `PersistentIdentifier` with `context.model(for:)` when the
  row may have been deleted** — it hands back a fault whose first property
  access is that same process kill. Look it up in the loaded `@Query` arrays
  instead; not found is then simply nothing (2026-08-14).
- With an inverse declared, both sides must be inserted into the context before
  linking (`MealItem(food:)` traps on never-inserted foods) — relevant in tests.
- In tests, keep the `ModelContainer` alive for the test body; returning just a
  context from a helper deallocates the container and every operation traps.
- Multiple chained `.sheet` modifiers on one view compete (consolidate
  into one `.sheet(item:)`); a Bool "request" flag that can be set while no
  onChange observer exists goes permanently dead (true→true never fires) — use
  a consumable Optional checked on change, appear, and foreground.
- Two dismissal races, each a silent field failure (both 2026-07-22):
  swapping a `.sheet(item:)` binding synchronously inside a closure the
  presented sheet follows with its own `dismiss()` tears the NEW sheet down
  with the old (defer the swap one turn — `Task { }` — as the label and
  known-barcode handoffs now do); and List sections under `.searchable` get a
  transient onDisappear/onAppear pair (@State intact) when the keyboard
  dismisses, so an onDisappear that cancels work needs an onAppear that
  resumes it, or the section wedges in its in-flight state forever.
- SwiftUI writes a `TabView` selection binding when you tap the tab you are
  ALREADY on. That is what makes "tapping Today goes to today's date" possible
  (a proxy `Binding` on the selection), and it is an assumption no build can
  check — so `testTodayTabReturnsToTodaysDate` asserts the RE-TAP specifically,
  after asserting the date moved away first, or it would pass vacuously.
  PROGRAMMATIC selections assign the state directly and skip the proxy on
  purpose: the Add pill's bounce must not reset the browsed day, because the
  Log sheet it opens backfills into that day.

## App-launch landmines

- **Never call `WKApplication.scheduleBackgroundRefresh` from `App.init`**
  — THE WATCH APP WILL NOT LAUNCH AT ALL. The crash names the reason
  exactly (2026-08-03, `WATCHKIT API Violation`):

      Condition failed:"NO". -[WKApplication scheduleBackgroundRefresh…]
      requires that your WKApplicationDelegate (null) implement
      handleBackgroundTasks:

  The delegate is `(null)` because SwiftUI installs the one backing
  `.backgroundTask(.appRefresh)` when the SCENE comes up, not before
  `init` runs. So arm anything WatchKit-facing from a `.task` on the
  scene — and NOT from `onChange(of: scenePhase)` alone, which never
  fires for the FIRST activation and would leave the chain unarmed
  until the app was opened and closed once. HealthKit observers in
  `init` ARE fine; the rule is specifically WatchKit. Symptom is
  indistinguishable from a provisioning problem: tapping a
  complication does nothing, the app never appears, and the widget
  extension keeps rendering fine — which is what proves the providers
  innocent.
- **A UIKit-facing delegate callback must never be `nonisolated`.**
  `UNUserNotificationCenterDelegate`'s methods are `async` bridged to
  ObjC completion handlers, and the completion runs wherever the async
  function FINISHES. Marked `nonisolated` on a `@MainActor` class they
  finish on the cooperative pool, so UIKit's post-response work
  (`_updateSnapshotAndStateRestorationWithAction:windowScene:`) ran off
  the main thread, hit an NSAssertionHandler and abort()ed ~235 ms into
  launch: EVERY reminder tap flashed the screen and never opened the
  app, while the icon opened it fine (2026-08-04, `EXC_CRASH/SIGABRT`
  on `com.apple.root.user-initiated-qos.cooperative`). An inner
  `await MainActor.run { }` does NOT save you — the hop ends before the
  method returns. Drop `nonisolated` and let the class's `@MainActor`
  carry the callback.
- **`UNUserNotificationCenter.current().delegate` must be assigned
  before launching finishes** — Apple's explicit contract. It rode
  `ReminderScheduler.activate()` out of ContentView's `.task` (i.e.
  once a view appeared) until 2026-08-03, so a reminder tapped from a
  cold launch had no delegate to deliver its response to and the tap
  did nothing. Everything a reminder tap is supposed to do lives in
  `didReceive` (water → log a serving, meal/streak → the Log sheet).
  It now registers from `AppDelegate.application(_:didFinishLaunching‑
  WithOptions:)`; `activate()` still calls it (idempotent) and keeps
  the replan.
- Free-team reminder: an app that refuses to launch AT ALL — from the
  icon, a notification, or a complication — is usually the lapsed
  7-day provisioning profile, not code. Redeploy before debugging.

## Where code lives

- Shared models/logic go in `Packages/OnigiriKit`, pure and unit-tested where
  possible.
- EXCEPTION — AppIntents: intent/entity/AppEnum types live in `SharedIntents/`,
  compiled INTO each target that exposes them (app, widget extension, watch app
  — see project.yml), NEVER in the kit. On-device linkd rejects SPM-delivered
  App Shortcuts metadata (`aggregateMetadataIsEmpty`, FB13281659) and the app
  silently never registers with Siri/Shortcuts; the 2.1 move into the kit broke
  registration invisibly for months (2026-07-16 evening). Pure logic the
  intents call (e.g. `StatusPhrasing`) stays in the kit with its tests. If
  intents ever fail with Shortcuts "internal error" while the app builds
  clean, check `log collect` for linkd `Failed to instantiate type … by name`
  (stale mangled name ⇒ delete app + reinstall re-registers; pull a backup
  out via devicectl FIRST — Documents/Backups dies with the container).
- Foundation Models code lives ONLY in `Onigiri/Models/FoodIntelligence.swift`
  (the kit never imports it); every AI affordance hides behind
  `FoodIntelligence.isAvailable` and every model failure falls back silently to
  the deterministic path.

## Logging: HealthKit is the store

- HealthKit holds the logs (food/sodium/water samples); SwiftData holds only the
  library (foods, meals, goals). Do not add a second source of truth for logs.
- Three correlation-metadata keys, and any new log/re-log path must carry them
  ALL through or edits regress and history silently loses detail:
  - `OnigiriMealCategory` — the meal slot. Absent ⇒ inferred from time of day
    (`FoodCategory.slot(for:)`).
  - `OnigiriQuantity` — the portion count (absent = 1). Log writes store
    multiplied totals PLUS this key; the edit sheet divides by it to recover
    the per-portion basis, so "3 hot dogs" edits as 3, not one triple serving.
  - `OnigiriMealItems` — a logged MEAL's composition (JSON `[LoggedMealItem]`,
    per-portion kcal, snapshotted at log time — never resolved from the
    library, which lies after meal edits). Absent = plain food or pre-feature
    log: no meal mark, no Contains section, by design.
- **Anything LOGGED is summed with a SAMPLE query, never a statistics
  query** (2026-08-05, cause CONFIRMED 2026-08-06 —
  `plans/PLAN-intake-sample-sums.md` has the measurements, the dead
  theories, and the one open design question; don't re-derive them).

  `HKStatisticsQuery` drops a WATCH-written sample when an IPHONE-written
  sample of the same type lands close to it in time — the cross-device
  de-duplication that stops steps double-counting, misfiring on food and
  water where every log is a distinct event. `HKSampleQueryDescriptor`
  returns both. `sourceRevision.productType` is the ONLY field that names
  the writer: `sample.device` is nil and the bundle identifier is the
  phone app's even for watch-written samples, because HealthKit credits
  the app, not the device. `HealthKitService.diagnoseIntake` (DEBUG, keep
  it) reproduces it on demand.

  BURN is the deliberate exception and keeps `sum`/statistics: burn is
  not logged, it is measured by both devices at once, so the cross-source
  merge is CORRECT there and a raw sample sum would DOUBLE-COUNT. Never
  "fix" burn for consistency.

  Apple Health's own totals are statistics-based, so **Health
  under-reports those days too — Onigiri reading higher than Health is
  correct, not a bug.** Only Health's total can disagree, which is why a
  visual check inside Onigiri can never test any of this.

## The budget, and what may judge a day

- The day's budget is `DayBudget.dayBurn − requiredDeficit`, ONE figure on every
  surface (2026-08-02, `plans/PLAN-earned-budget.md`). Resting is credited UP
  FRONT — the whole day from midnight, measured but floored by
  `BasalEstimate.restingKcal` — because it happens whether or not you move;
  dripping it hourly makes breakfast read as "over". Active is EARNED: raw
  measured, never filled, never estimated. No watch, no active credit, smaller
  budget — that IS the incentive, and it's why the trailing-average
  substitution and the whole Fixed budget style were deleted rather than kept
  beside it. `TodayBurnFloor` ratchets the day burn (Health revises today's
  burn DOWN mid-day).
- Verdict-shaped numbers — Net, banked, the gauge, the balance headline — go
  through `DayBudget.deficit`, NOT `DailyEnergySummary.balanceKcal`; the Burned
  flank and the Active/Resting rows stay on Health's raw totals, because those
  report a measurement rather than reach a judgment. Past days re-grade
  themselves from Health; that's accepted, and it's less code than freezing
  them.
- `CalorieBudget.projectedDailyBurn` survives for the Goal/onboarding PREVIEW
  only ("an average day"), never to judge a day. Goal shows BOTH budgets and
  they must stay TOLD APART — one label on two different numbers reads as a
  contradiction (726 kcal apart at lunchtime, 2026-08-02). Since 2026-08-11 the
  SECTION carries that distinction, not the row labels: `Budget` under `Today`
  (live `dayBurn − deficit`, as eaten/budget) and `Budget, average day` inside
  the collapsed "How budget is set". Don't put two rows called "Budget" side by
  side again, and don't re-add a today-floor to the projection to close the gap
  — that was tried, it made the average neither one thing nor the other, and it
  didn't close it.
- A day's VERDICT has two gates, and both live in `StreakCalendar`:
  `isTracked` (intake ≥ `untrackedBelowKcal`, default 500 — too little
  logged to trust the numbers; Settings → Metrics tunes it, 0 disables)
  AND the `DayBadgeRule`. Any surface that says "earned" must run BOTH.
  Today's goal card ran only the second and called a 934-kcal day with a
  1,702 deficit "earned" while the calendar left it blank (2026-08-02).
  Never reimplement either rule locally.

## Weight: which reading may judge

`plans/PLAN-goal-finish-line.md` (2026-08-14, v2.21.0).

- **Anything that reaches a VERDICT runs on the sustained basis; only the
  "Current weight" row stays raw.** The basis is the 7-day mean of DAILY LOWS
  (`WeightTrend.targetBasisLb`, `GoalCompletion`). Validation, the progress bar,
  the celebration, the finish line, the deficit and the chart's trend line are
  all verdicts. The raw last weigh-in reports a measurement and judges nothing
  — the same split the budget draws above.

  This was learned twice. 2026-08-02 unified the deficit chain but deliberately
  carved out validation and the progress bar, on the grounds that only the
  chain had to agree with itself. On 2026-08-14 that exception put four
  contradictory answers on one screen — a full bar reading "8.9 of 8.7 lb", an
  orange "Target must be below your current weight.", a projection five days
  out, and no celebration — each correct against a different weight, none of
  them saying which. Don't reintroduce the exception.
- `GoalFinishLine` has THREE states: `underWay` / `approaching` (within
  `bandLb`, 1 lb) / `reached`. Without the middle one an arrival renders as a
  form error, which is exactly what it did. Inside the band
  `requiredDailyDeficit` returns 0, and the band lives THERE rather than in the
  UI so Today, the widget, the watch and `DeficitTargetHistory` cannot disagree
  — the sensitivity is `3500 / daysRemaining` kcal per pound (194 kcal/day at
  18 days out), so the last pound otherwise swings on water weight.
- The chart's trend line has a checkable invariant: **its right-hand end EQUALS
  the "Weight" row under "How budget is set", to the digit**
  (`GoalFinishLineTests.theSmoothedLineEndsOnTheBudgetBasis`). It averages
  daily lows for that reason; on raw samples it ended ~2 lb high, and a day
  weighed twice outvoted a day weighed once — which measures weighing habits
  rather than body mass. The y-axis is scaled by the lows too, so one evening
  reading can't set how tall the chart is.
- A target moved DOWN by hand keeps the journey (`JourneyContinuity`,
  `StartChange.keep`); moved UP it re-stamps. Re-stamping on every target
  change re-zeroed a progress bar with nine pounds behind it.

## Watch sync

- Free personal team: no iCloud/CloudKit entitlements; watch↔phone library sync
  is WatchConnectivity, log sync is HealthKit's own.
- **A watch REINSTALL wipes the watch's library while the phone still believes
  it's in sync**: `pushNow` skips the send when the payload fingerprint is
  unchanged, and `lastSentFingerprint` is per-phone-process in-memory state, so
  the watch sits on its empty state ("add favorites or log food in the app")
  until the phone app is relaunched or the library happens to change.
  `sessionWatchStateDidChange` now clears that fingerprint and re-pushes — it's
  the only callback that fires when `isWatchAppInstalled` moves (2026-07-30).
  Any future send-side caching needs the same escape hatch.
- New payload fields are OPTIONAL for version skew in both directions, and
  nil must render as the pre-feature behavior rather than a guess. Where a
  field has a meaningful `false`, send it EXPLICITLY — `SyncedMeal.isMeal` on a
  food would otherwise be indistinguishable from an old phone's payload — and
  never infer one field from another's presence (`items` is nil for meals from
  old phones, and a memberless meal is legal).

## Units

- Settings → Units is display/entry-only. Storage is ALWAYS canonical — lb, US
  fl oz, sodium mg — in HealthKit, SwiftData, WatchSync, and backups;
  `WeightUnit`/`WaterUnit`/`SodiumUnit` (kit, UnitPreferences.swift) convert at
  the UI boundary and any new weight/water/sodium readout must go through them.
- Status/color/validation math stays canonical (the sodium near-limit band is
  an absolute 300 mg). "auto"/absent = follow region (sodium resolves via an
  EU/UK/EFTA region list, NOT measurementSystem — Australia is metric but
  labels sodium in mg). The three keys ALWAYS ride the watch sync with an
  explicit "auto" (an absent key would leave a stale explicit choice alive on
  the watch). Siri's LogWaterIntent parameter stays ounces by design; only its
  reply converts.

## Food entry: search, scan, images

- ALL online-search surfaces (Foods, Log sheet, and the food form's inline
  database search) render the shared `OnlineResultsSection` — a separate
  `FoodSearchSheet` with its own drifting list existed until 2026-07-13. Keep
  it that way: search behavior changes go in the shared section only. Search
  fields are the STANDARD system `.searchable` (bottom placement) everywhere —
  the user vetoed custom bars and auto-focus; the scanner is a labeled list row
  (`ScanRowLabel`), never a toolbar icon.
- OpenFoodFacts: the search index has NO nutrition fields — search rows lazily
  fetch the full product per barcode to show kcal/serving.
- Text search can route to USDA FoodData Central instead (Settings → Online
  Database; user-supplied api.data.gov key, device-local). FDC rows carry
  `fdc:{fdcId}` in the barcode slot and arrive with nutrients inline (no lazy
  fetch, no weeding). The FDC search endpoint must be POST — GET 400s on the
  `Survey (FNDDS)` dataType parens. Barcode scans are always OpenFoodFacts.
- Label scanning is the third door beside barcode and text search, and it
  shares ONE camera with barcodes: `ScanSheet` ("Scan Barcode or Nutrition
  Label" — the user's copy; one row on Foods, the Log sheet, and the blank food
  form) runs the live barcode scanner with a shutter button whose still goes to
  `LabelScan` (kit) — Vision OCR, `.accurate`, language correction OFF
  (correction mangles "0g" → "Og") — into the pure, fixture-tested
  `LabelParser`. Keep the request configuration in `LabelScan.swift` and
  `scripts/dump-label-ocr.swift` identical; capture new parser fixtures with
  that script, never by hand-transcribing. On iOS 26 the documents-request
  table branch runs first; real photos produce tables, rendered label graphics
  don't, so the geometry parser is a load-bearing fallback, not legacy.
- Screenshot import (`plans/PLAN-screenshot-nutrition.md`): the entry doors take
  a PASTED image as well as the camera, and every route — those two plus the
  scan sheet's own photo pick — runs ONE cascade, `FoodImageReader` (OCR →
  LabelParser → refine → identify). Never fork that path; a screenshot must
  read the way a photographed label does. A separate "Choose Photo" door was
  built and REMOVED the same day (the user, 2026-07-24): the scan sheet's
  photos button already covers saved images.
- The paste door is gated on `hasImages`, a detection property that raises no
  prompt, re-checked on appear AND foreground (the clipboard changes while
  backgrounded — copy in Safari, then switch — where `changedNotification` is
  unreliable). It is a plain `DoorRowLabel` reading
  `UIPasteboard.general.itemProviders`, NOT SwiftUI's `PasteButton`, so the
  system paste alert is VISIBLE; RESOLVED on device 2026-07-24 that iOS asks
  ONCE, not per paste. A declined paste and an empty clipboard are
  indistinguishable (iOS returns nothing for both), hence one shared message.
- `FoodImageSource.imported` additionally runs the screenshot read, which
  supplies the food NAME a photographed panel never carries; deterministic
  values always win over it, and a name equal to the serving is DROPPED (the
  model returned "1 burger (312g)" as a name, 2026-07-24 — blank beats wrong).
  When that read returns MORE THAN ONE food the deterministic parse is
  DISCARDED, not merged: it can only describe one row, so blank-filling stamped
  its numbers onto every candidate (four salads all reading 490 kcal, live
  2026-07-24). The host asks with a confirmationDialog — never a sheet swapped
  from inside a sheet.
- A photo with no nutrition panel is NOT a dead end (2026-08-02). The cascade
  after a failed parse is: `FoodIntelligence.readFoodSign` (the OCR TEXT — a
  bakery card, shelf sign, menu board, package front NAMES the food, which no
  classifier label can) → `identifyFood` (the picture itself) →
  `SignText.namedFood` (kit, pure: name + serving, transcription only, the
  AI-off floor so the form opens half-filled instead of blank). Sign reads are
  ESTIMATES and carry `aiGenerated` through `ParsedLabel`; >1 named item raises
  the existing "Which item?" dialog. Two guards are load-bearing:
  `plausibleSignFoods` rejects a name that appears nowhere in the OCR (it
  caught a confabulated food during the eval run), and the sign prompt DELIMITS
  the text as photographed data — without that framing an "Allergen Warning!
  Contains:…" line refuses every time with "May contain sensitive content".

## Library rows

- **Recency means LOGGED, never looked at** (2026-08-14). `lastUsedAt` may only
  be stamped where something is actually logged. It used to fire when the
  portion sheet OPENED, because `PortionTarget` carried no reference back to
  the library row — so tapping a food to look at it floated it to the top of
  Recent and cancelling left the list reordered underneath you. The target
  carries `source` (a `PersistentIdentifier`) and the sheet's CONFIRM handler
  stamps it, which a cancel never reaches.
- **A meal carries its mark in EVERY list.** `LibraryRow(isMeal:)` is
  unconditional. It used to be set only where a list mixed types, so Foods →
  Meals drew none while Favorites, search results and the Log sheet did — the
  same meal looking like two different things depending on where it was found.
  The watch draws it too (see Watch sync for the payload rule).

## Copy

- "Burn" and "energy" split by REGISTER (the user, 2026-08-02). **Burn** is the
  user-facing word — the glanceable numbers and their labels: the Today/widget
  flanks, the Active/Resting meters, Net, the calendar day card, Goal's own
  rows. **Energy** is for the FORMAL register: explanatory captions, settings
  footers, the privacy policy, the wiki. Goal's budget explainer reads "Resting
  energy is credited at midnight"; the meter beside it still says Resting burn.
  Keep the NOUN in both halves of that pair — shortening it to "…, active as
  you earn it" made "active" read as a state of resting energy rather than a
  second kind of it (2026-08-13).
- Never swap one wholesale for the other. A pass replacing "burn" with "Used"
  on the Today/widget flanks and "energy" in every noun slot ("Total energy",
  "Average energy", "Active energy") was built, shipped, and fully REVERTED:
  "Used" reads vague next to a hard number and doubles as budget-spend in a
  budget-framed app, and the neutral nouns lost more than the metaphor cost.
  Don't re-propose it.
- Today and the widget label the same `totalBurnKcal` — change them TOGETHER or
  the two surfaces disagree.
- What DID stick: "banked" is retired from user copy ("Total deficit", "the
  deficit counts"), and noun phrases read better rewritten into the verb — Goal
  says "eat close to what you burn in a day", the site says "You burn ~2,800
  kcal/day on average". Identifiers were never in scope and stay
  `burnKcal`/`bankedKcal`, mirroring HealthKit's own `activeEnergyBurned`.
  `docs/privacy.md`'s "daily energy use" clause has a wiki twin needing the
  same edit by hand.
