# Onigiri — agent notes

Personal iOS + watchOS calorie/sodium/water tracker. Design + roadmap: `plans/PLAN.md`.

## Repo, docs, license

- ORIGIN is GitHub (github.com/ecliptik/onigiri); Forgejo rides as a second
  push URL on origin, so one `git push` updates both. Fetch comes from GitHub.
- `docs/` IS the GitHub Pages site (marketing index.html + privacy.md +
  showcase/media assets) — anything committed there is published on push.
  Internal design docs live in `plans/`. The user guide lives ONLY in the
  GitHub wiki (onigiri.wiki.git); the privacy policy lives in both (site
  canonical). The site's app screenshots/clips exist in BOTH appearances
  (showcase/light + showcase/dark, media/*.mp4 + *-dark.mp4) and swap with
  the site theme — recapture both when screens change. Verify site media
  by PROBING it, not by looking: two container-metadata faults render
  wrong ONLY in a browser while sips/Finder/QuickTime show them fine —
  an empty edit list (`elst` `media time: -1`, left by `-ss` BEFORE
  `-i`) loops through black, and an EXIF orientation tag (which
  `sips -r` writes) stands a landscape PNG on its side. Both bit
  2026-08-02; probes and fixes are in the screenshot-recipe notes.
- License: PolyForm Noncommercial 1.0.0 since the commit after the v2.2.0
  tag (≤ v2.2.0 remains MIT). Say "source-available", not "open source".
  LICENSE is verbatim PolyForm text — never edit it. External PRs are
  declined by policy (CONTRIBUTING.md) to keep commercial rights clean.

## Build

- `xcode-select` may point at CommandLineTools; prefix Xcode commands with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if so.
- `xcodebuild`/`simctl` fail under the Bash sandbox (temp caches, CoreSimulator XPC) —
  run them with the sandbox disabled.
- The `.xcodeproj` is generated and gitignored — after editing `project.yml`, run `xcodegen generate`.

```sh
xcodegen generate
xcodebuild -project Onigiri.xcodeproj -scheme Onigiri \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
  # builds the watch app too (embedded). Do NOT pass CODE_SIGNING_ALLOWED=NO:
  # it strips the HealthKit entitlement; ad-hoc simulator signing needs no team.
cd Packages/OnigiriKit && swift test     # pure-logic tests; ALSO needs the
  # DEVELOPER_DIR prefix or @Model/#Preview macro plugins aren't found.
```

- `OnigiriTests` (app-hosted unit tests) is the Foundation Models eval
  suite for `FoodIntelligence` — golden sets with plausibility gates for
  describe-it, meal names, and label refinement. Opt-in (minutes of
  inference) and self-skipping: it needs `TEST_RUNNER_ONIGIRI_AI_EVALS=1`
  AND an available model (an iOS 26+ simulator works: verified 2026-07-16
  on the 26.5 sim WITH the host Mac's Apple Intelligence off, even though
  macOS-side FoundationModels reported appleIntelligenceNotEnabled — trust
  the suite's own skip/run behavior, and never trust a green run without
  checking for skips). Re-run after ANY prompt
  change in FoodIntelligence.swift and after OS updates (the model moves
  under the app). Thresholds live in `Gate` — set before tuning; change
  them only deliberately, in a commit that says why.

```sh
TEST_RUNNER_ONIGIRI_AI_EVALS=1 xcodebuild -project Onigiri.xcodeproj \
  -scheme Onigiri -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath build test -only-testing:OnigiriTests
```

- Commits are GPG-signed: run `git commit` with the sandbox disabled (gpg needs
  `~/.gnupg`). If it fails with "Operation cancelled", the passphrase cache
  expired and pinentry can't prompt from the agent shell — ask the user to run
  `! gpg --clearsign -o /dev/null <<< test` to prime gpg-agent, then retry.

## Deploying to devices

- **Repeated watch install failures (CoreDeviceError 4000 / tunnel timeouts)
  with the watch demonstrably awake usually mean the MAC-side daemon is
  wedged, not the watch.** Diagnose with `xcrun devicectl list devices` —
  "Timed out waiting for CoreDeviceService to fully initialize" confirms it.
  Fix: `pkill -f CoreDeviceService` (no sudo needed), wait ~15 s for the
  watch to reach "connecting/connected", then install. Don't send the user
  chasing watch reboots until this is ruled out.
- **If 4000/RemotePairingError-1001 persists past the daemon reset (watch
  "available (paired)", BT on, VPN exonerated): keep making contact and
  POLL.** The watch's "preparation errors" state clears with repeated
  attempts; once the error shifts to "Device is busy (Connecting…)", loop
  `devicectl list devices` every ~10 s until the state reads "connected"
  (it bounces available↔connecting↔connected) and build+install in that
  window. A patience loop succeeds where one-shot attempts time out
  (2026-07-11: ~an hour of identical failures, then connected on poll 7).
  ATTEMPT THE INSTALL every round, don't just watch the state: a loop
  that only polled `list devices` sat at "available (paired)" for 20
  rounds, while a loop that ran `devicectl device install app` each
  round succeeded on attempt 2 after one 3002 (2026-07-20) — the
  install attempt itself is the contact that wakes the channel.
  `IXRemoteErrorDomain code 6` belongs to the same retry-through family
  (2026-07-21: five of those + one network timeout, then success on
  attempt 7). deploy-phone.sh runs this loop itself now — and never
  gates the watch on a one-shot `list devices` (a not-yet-enumerated
  watch read as "unreachable" and got silently skipped).
- **Watch discovery requires Mac BLUETOOTH ON.** Two days of debugging
  (reboots, re-pairing, trust resets, cache wipes, VPN toggles) and the watch
  never appeared in Xcode/devicectl until the Mac's Bluetooth was enabled —
  the Mac↔watch developer channel bootstraps over BT/AWDL. Check this FIRST.
- Address the watch by ID, not display name (the curly apostrophe matches
  neither tool): xcodebuild wants the hardware UDID, devicectl wants the
  CoreDevice identifier. Both live in scripts/local-devices.env (gitignored;
  copy the .example).

- `scripts/deploy-phone.sh` builds and installs on BOTH the configured iPhone and the
  watch (override with `DEVICE_NAME=…` / `WATCH_BUILD_ID=…` / `WATCH_INSTALL_ID=…`).
  Run weekly — free-team provisioning expires after 7 days. Works over the
  network tunnel; phone and watch must be unlocked (watch on wrist, near the Mac).
- To verify a device install actually runs: `devicectl device process launch
  --console <bundle id>` prints crash reasons (e.g. SwiftData fatals) that never
  reach any log file. Requires the phone unlocked.

## Simulator automation notes

- XCUITest can drive springboard (`XCUIApplication(bundleIdentifier: "com.apple.springboard")`)
  for home-screen/widget-gallery flows; coordinate clicking via osascript/cliclick is
  unreliable for small controls. Health permission sheets have stable `UIA.Health.*`
  accessibility identifiers.
- Pass env vars to UI tests via `TEST_RUNNER_<NAME>=… xcodebuild test …`.
- `testAddWidgetToHomeScreen` (opt-in via `TEST_RUNNER_ADD_WIDGET=1`) installs the
  widget on the simulator home screen.
- The seeder DOES write body mass and active/basal energy (it always
  has). What made the earned-budget model invisible on a simulator was
  the resting ESTIMATE: `BasalEstimate` needs height and an AGE, and
  date of birth is a HealthKit CHARACTERISTIC no app can write. Fixed
  2026-08-02 — the seeder writes a height sample and stamps
  `HealthKitService.debugSeededAgeKey`, which `bodyProfile()` reads in
  DEBUG only when Health itself has no birthday. Goal now shows
  "Resting burn ≈ 1,743 kcal/day" on a seeded sim. Sex stays
  unspecified; BasalEstimate's midpoint constant covers it.
- The iPhone and Watch sims are PAIRED and share Health data — erase BOTH before
  running the flow test, or seeded totals will be off (`simctl erase <both udids>`).
  Same for the iPad sim: every `--seed-sample-data` launch ADDS samples, so after
  a few QA runs the flow test's total assertions fail on stale data — erase first.
- UI-test capture runs leave the sim in their last orientation; tests that
  assume portrait must set `XCUIDevice.shared.orientation` themselves (the flow
  and QA tests now do).
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
- Seeding app-group defaults from a test script: `simctl spawn <udid>
  defaults write group.com.ecliptik.Onigiri …` writes the sim's UNSANDBOXED
  root prefs — the sandboxed app never sees it. Write the real container
  plist instead: `data/Containers/Shared/AppGroup/<UUID>/Library/Preferences/
  group.com.ecliptik.Onigiri.plist` (pass the path minus `.plist` to
  `defaults write`, app terminated first). Cost a smoke-test cycle 2026-07-21.
  AND run that `defaults write` via `simctl spawn <udid>`, not the host: a
  host-side write to the same path landed in the file but the app still read
  stale values — the sim's own cfprefsd had the domain cached and served its
  copy. Spawning defaults inside the sim goes through that daemon (2026-07-22).

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
  observe `activeEnergyBurned` ONLY — adding `HKWorkoutType` would put a
  new type in `readTypes`, flipping `statusForAuthorizationRequest` back
  to `.shouldRequest`, which is what `PlanCache.needsSetup` reads, so
  every widget would paint "Open Onigiri to set up" over a working setup;
  every reload goes through `WidgetRefreshPolicy.shouldReloadForBurn`
  (≥40 kcal AND ≥10 min) because WidgetKit grants ~40–70 reloads/day and
  reloading per sample freezes the widget by mid-afternoon; and NEVER
  project future burn into pre-rendered entries — active is earned, "raw
  measured, never filled, never estimated", which is the deleted
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

## SwiftData landmines (each cost a debugging session)

- Every relationship needs an explicit inverse. Without one, deleting the target
  leaves a dangling reference, and SwiftData KILLS THE PROCESS ("backing data
  could no longer be found") on the next property access — the app crash-looped
  at launch because the watch-sync push computes meal totals.
- A SwiftData-level repair can't fix that state (inspecting the reference traps
  too). `LibraryMaintenance.repairStore(at:)` opens the store with Core Data
  first — `objectIDs(forRelationshipNamed:)` reads references without firing
  faults — and must set `NSPersistentHistoryTrackingKey` or the store mounts
  read-only and the save silently fails.
- With an inverse declared, both sides must be inserted into the context before
  linking (`MealItem(food:)` traps on never-inserted foods) — relevant in tests.
- In tests, keep the `ModelContainer` alive for the test body; returning just a
  context from a helper deallocates the container and every operation traps.
- SwiftUI: multiple chained `.sheet` modifiers on one view compete (consolidate
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

## App-launch landmines (what belongs in `init`, and what does not)

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

## Conventions

- Shared models/logic go in `Packages/OnigiriKit`, pure and unit-tested where possible.
  EXCEPTION — AppIntents: intent/entity/AppEnum types live in `SharedIntents/`,
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
- HealthKit is the log store (food/sodium/water samples); SwiftData holds only the
  library (foods, meals, goals). Do not add a second source of truth for logs.
  The meal slot (Breakfast/…) rides in correlation metadata `OnigiriMealCategory`;
  entries without it infer the slot from time of day (`FoodCategory.slot(for:)`).
  The portion count rides in `OnigiriQuantity` (absent = 1) — log writes store
  multiplied totals PLUS this key, and the edit sheet divides totals by it to
  recover the per-portion basis, so "3 hot dogs" edits as 3, not one triple
  serving. A logged MEAL's composition rides in `OnigiriMealItems`
  (JSON [LoggedMealItem], per-portion kcal, snapshotted at log time —
  never resolved from the library, which lies after meal edits); absent =
  plain food or pre-feature log (no meal mark, no Contains section — by
  design). Any new log/re-log path must carry BOTH keys through or edits
  regress to 1 and history silently loses its breakdown.
- Free personal team: no iCloud/CloudKit entitlements; watch↔phone library sync is
  WatchConnectivity, log sync is HealthKit's own. **A watch REINSTALL wipes the
  watch's library while the phone still believes it's in sync**: `pushNow`
  skips the send when the payload fingerprint is unchanged, and
  `lastSentFingerprint` is per-phone-process in-memory state, so the watch
  sits on its empty state ("add favorites or log food in the app") until the
  phone app is relaunched or the library happens to change.
  `sessionWatchStateDidChange` now clears that fingerprint and re-pushes —
  it's the only callback that fires when `isWatchAppInstalled` moves
  (2026-07-30). Any future send-side caching needs the same escape hatch.
- The day's budget is `DayBudget.dayBurn − requiredDeficit`, ONE figure
  on every surface (2026-08-02, `plans/PLAN-earned-budget.md`). Resting
  is credited UP FRONT — the whole day from midnight, measured but
  floored by `BasalEstimate.restingKcal` — because it happens whether or
  not you move; dripping it hourly makes breakfast read as "over". Active
  is EARNED: raw measured, never filled, never estimated. No watch, no
  active credit, smaller budget — that IS the incentive, and it's why the
  trailing-average substitution and the whole Fixed budget style were
  deleted rather than kept beside it. `TodayBurnFloor` ratchets the day
  burn (Health revises today's burn DOWN mid-day). Verdict-shaped numbers
  — Net, banked, the gauge, the balance headline — go through
  `DayBudget.deficit`, NOT `DailyEnergySummary.balanceKcal`; the Burned
  flank and the Active/Resting rows stay on Health's raw totals, because
  those report a measurement rather than reach a judgment. Past days
  re-grade themselves from Health; that's accepted, and it's less code
  than freezing them. `CalorieBudget.projectedDailyBurn` survives for the
  Goal/onboarding PREVIEW only ("an average day"), never to judge a day.
  Goal's Daily plan shows BOTH budgets, named — "Average day" (the
  projection) over "Today" (the live `dayBurn − deficit`) — because one
  label on two different numbers reads as a contradiction (726 kcal
  apart at lunchtime, 2026-08-02). Don't re-add a today-floor to the
  projection to close the gap: that was tried, it made the average
  neither one thing nor the other, and it didn't close it.
- **Food totals are summed from the day's own CORRELATIONS, never from a
  statistics query** (2026-08-04). A statistics query on the phone could
  not see a sample logged on the WATCH: measured, `merged=295
  bySource=295 corr=681 rows=3` with `.separateBySource` reporting a
  SINGLE source — the watch app's bundle never appeared, so the sample
  isn't merged away, it is invisible to that query kind. Apple Health
  showed 295 too. A 681 kcal day therefore read as 295 with all three
  rows listed beneath it. Worse, `dailyEnergyTotals` fed the calendar,
  badges and streak the same undercount, and at 295 the day fell under
  `untrackedBelowKcal` — a fully logged day would have been marked
  untracked. Water sums its own samples for the same reason (bare
  samples, logged on both devices). BURN keeps the statistics collection:
  there a cross-source merge is correct, because the two devices really
  are measuring one body. `HealthKitService.diagnoseIntake` (DEBUG)
  re-runs the measurement; the underlying HealthKit cause is still
  unknown, and a correlation sum is immune to it either way. The trade
  taken knowingly: food logged into Health by another app no longer
  counts toward intake — it never appeared in the day's list either.
- A day's VERDICT has two gates, and both live in `StreakCalendar`:
  `isTracked` (intake ≥ `untrackedBelowKcal`, default 500 — too little
  logged to trust the numbers; Settings → Metrics tunes it, 0 disables)
  AND the `DayBadgeRule`. Any surface that
  says "earned" must run BOTH. Today's goal card ran only the second and
  called a 934-kcal day with a 1,702 deficit "earned" while the calendar
  left it blank (2026-08-02). Never reimplement either rule locally.
- Unit preferences (Settings → Units): display/entry-only. Storage is ALWAYS
  canonical — lb, US fl oz, sodium mg — in HealthKit, SwiftData, WatchSync,
  and backups; `WeightUnit`/`WaterUnit`/`SodiumUnit` (kit, UnitPreferences.swift)
  convert at the UI boundary and any new weight/water/sodium readout must go
  through them. Status/color/validation math stays canonical (the sodium
  near-limit band is an absolute 300 mg). "auto"/absent = follow region
  (sodium resolves via an EU/UK/EFTA region list, NOT measurementSystem —
  Australia is metric but labels sodium in mg). The three keys ALWAYS ride
  the watch sync with an explicit "auto" (an absent key would leave a stale
  explicit choice alive on the watch). Siri's LogWaterIntent parameter stays
  ounces by design; only its reply converts.
- OpenFoodFacts: the search index has NO nutrition fields — search rows lazily
  fetch the full product per barcode to show kcal/serving.
- Label scanning is the third door beside barcode and text search, and
  it shares ONE camera with barcodes: `ScanSheet` ("Scan Barcode or
  Nutrition Label" — the user's copy, one row on Foods, the Log sheet,
  and the blank food form) runs the live barcode scanner with a shutter
  button whose still goes to `LabelScan` (kit) — Vision OCR, `.accurate`,
  language correction OFF (correction mangles "0g" → "Og") — into the
  pure, fixture-tested `LabelParser`. Keep the request configuration in
  `LabelScan.swift` and `scripts/dump-label-ocr.swift` identical; capture
  new parser fixtures with that script, never by hand-transcribing. On
  iOS 26 the documents-request table branch runs first; real photos
  produce tables, rendered label graphics don't, so the geometry parser
  is a load-bearing fallback, not legacy. Foundation Models code lives
  ONLY in `Onigiri/Models/FoodIntelligence.swift` (the kit never imports
  it); every AI affordance hides behind `FoodIntelligence.isAvailable`
  and every model failure falls back silently to the deterministic path.
- Text search can route to USDA FoodData Central instead (Settings →
  Online Database; user-supplied api.data.gov key, device-local). FDC rows
  carry `fdc:{fdcId}` in the barcode slot and arrive with nutrients inline
  (no lazy fetch, no weeding). The FDC search endpoint must be POST — GET
  400s on the `Survey (FNDDS)` dataType parens. Barcode scans are always
  OpenFoodFacts.
- Screenshot import (PLAN-screenshot-nutrition): the entry doors take a
  PASTED image as well as the camera, and every route — those two plus
  the scan sheet's own photo pick — runs ONE cascade, `FoodImageReader`
  (OCR → LabelParser → refine → identify). Never fork that path; a
  screenshot must read the way a photographed label does. A separate
  "Choose Photo" door on the entry row was built and REMOVED the same
  day (the user, 2026-07-24): the scan sheet's photos button already
  covers saved images. Gate the paste door's visibility on `hasImages`,
  a detection property that raises no prompt, re-checked on appear AND
  foreground (the clipboard changes while the app is backgrounded —
  copy in Safari, then switch — where `changedNotification` is
  unreliable). The paste control is a plain `DoorRowLabel` row reading
  `UIPasteboard.general.itemProviders`, NOT SwiftUI's `PasteButton` —
  chosen so the system "would like to paste" alert is VISIBLE, and
  RESOLVED on device 2026-07-24: iOS asked ONCE, not per paste, so the
  earlier fear that a programmatic read nags every time was wrong.
  Privacy is identical either way — the app can never read the
  clipboard un-prompted. A declined paste and an empty clipboard are
  indistinguishable (iOS returns nothing for both), hence one shared
  message. `FoodImageSource.imported`
  additionally runs the screenshot read, which supplies the food NAME a
  photographed panel never carries; deterministic values always win over
  it, and a name equal to the serving is DROPPED (the on-device model
  returned "1 burger (312g)" as a name, 2026-07-24 — blank beats wrong).
  When that read returns MORE THAN ONE food the deterministic parse is
  discarded, not merged: it can only describe one row, so blank-filling
  stamped its numbers onto every candidate (four salads all reading 490
  kcal, live 2026-07-24). The host asks with a confirmationDialog —
  never a sheet swapped from inside a sheet.
- A photo with no nutrition panel is NOT a dead end (2026-08-02). The
  cascade after a failed parse is: `FoodIntelligence.readFoodSign`
  (the OCR TEXT — a bakery card, shelf sign, menu board, package front
  NAMES the food, which no classifier label can) → `identifyFood`
  (the picture itself) → `SignText.namedFood` (kit, pure: name +
  serving, transcription only, the AI-off floor so the form opens
  half-filled instead of blank). Sign reads are ESTIMATES and carry
  `aiGenerated` through `ParsedLabel`; >1 named item raises the
  existing "Which item?" dialog. Two guards are load-bearing:
  `plausibleSignFoods` rejects a name that appears nowhere in the OCR
  (it caught a confabulated food during the eval run), and the sign
  prompt DELIMITS the text as photographed data — without that framing
  an "Allergen Warning! Contains:…" line refuses every time with "May
  contain sensitive content".
- ALL online-search surfaces (Foods, Log sheet, and the food form's
  inline database search) render the shared `OnlineResultsSection` —
  a separate `FoodSearchSheet` with its own drifting list existed until
  2026-07-13. Keep it that way: search behavior changes go in the
  shared section only. Search fields are the STANDARD system
  `.searchable` (bottom placement) everywhere — the user vetoed custom
  bars and auto-focus; the scanner is a labeled list row (ScanRowLabel),
  never a toolbar icon.
- Copy: "burn" and "energy" split by REGISTER (the user, 2026-08-02).
  "Burn" is the user-facing word — the glanceable numbers and their
  labels: the Today/widget flanks, the Active/Resting meters, Net, the
  calendar day card, Goal's own rows. "Energy" is for the FORMAL
  register: explanatory captions, settings footers, the privacy policy,
  the wiki. Goal's budget explainer reads "Resting energy starts at
  midnight"; the meter beside it still says Resting burn. Never swap one
  wholesale for the other: a pass replacing "burn" with "Used" on the
  Today/widget flanks and "energy" in every noun slot ("Total energy",
  "Average energy", "Active energy") was built, shipped, and fully
  REVERTED. "Used" reads vague
  next to a hard number and doubles as budget-spend in a budget-framed
  app, and the neutral nouns lost more than the metaphor cost. Don't
  re-propose it. Today and the widget label the same `totalBurnKcal` —
  change them TOGETHER or the two surfaces disagree.

  What DID stick: "banked" is retired from user copy ("Total deficit",
  "the deficit counts"), and noun phrases read better rewritten into the
  verb — Goal says "eat close to what you burn in a day", the site says
  "You burn ~2,800 kcal/day on average". Identifiers were never in scope
  and stay `burnKcal`/`bankedKcal`, mirroring HealthKit's own
  `activeEnergyBurned`. `docs/privacy.md`'s "daily energy use" clause has
  a wiki twin needing the same edit by hand.
