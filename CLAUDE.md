# Onigiri — agent notes

Personal iOS + watchOS calorie/sodium/water tracker. Design + roadmap: `docs/PLAN.md`.

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

- Commits are GPG-signed: run `git commit` with the sandbox disabled (gpg needs
  `~/.gnupg`). If it fails with "Operation cancelled", the passphrase cache
  expired and pinentry can't prompt from the agent shell — ask Micheal to run
  `! gpg --clearsign -o /dev/null <<< test` to prime gpg-agent, then retry.

## Deploying to devices

- **Repeated watch install failures (CoreDeviceError 4000 / tunnel timeouts)
  with the watch demonstrably awake usually mean the MAC-side daemon is
  wedged, not the watch.** Diagnose with `xcrun devicectl list devices` —
  "Timed out waiting for CoreDeviceService to fully initialize" confirms it.
  Fix: `pkill -f CoreDeviceService` (no sudo needed), wait ~15 s for the
  watch to reach "connecting/connected", then install. Don't send the user
  chasing watch reboots until this is ruled out.
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
- The iPhone and Watch sims are PAIRED and share Health data — erase BOTH before
  running the flow test, or seeded totals will be off (`simctl erase <both udids>`).
- Watch-window clicks need the window focused first (click its title bar); clicks
  silently stop landing after sheets open — relaunch the watch app to recover.

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

## Conventions

- Shared models/logic go in `Packages/OnigiriKit`, pure and unit-tested where possible.
- HealthKit is the log store (food/sodium/water samples); SwiftData holds only the
  library (foods, meals, goals). Do not add a second source of truth for logs.
  The meal slot (Breakfast/…) rides in correlation metadata `OnigiriMealCategory`;
  entries without it infer the slot from time of day (`FoodCategory.slot(for:)`).
- Free personal team: no iCloud/CloudKit entitlements; watch↔phone library sync is
  WatchConnectivity, log sync is HealthKit's own.
- OpenFoodFacts: the search index has NO nutrition fields — search rows lazily
  fetch the full product per barcode to show kcal/serving.
