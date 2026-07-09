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
cd Packages/OnigiriKit && swift test     # pure-logic tests
```

## Deploying to devices

- **Watch discovery requires Mac BLUETOOTH ON.** Two days of debugging
  (reboots, re-pairing, trust resets, cache wipes, VPN toggles) and the watch
  never appeared in Xcode/devicectl until the Mac's Bluetooth was enabled —
  the Mac↔watch developer channel bootstraps over BT/AWDL. Check this FIRST.
- Watch: build OnigiriWatch scheme at the watch destination with
  -allowProvisioningUpdates, then `devicectl device install app` with the
  Debug-watchos product. Watch unlocked and on wrist.

- `scripts/deploy-phone.sh` builds and installs on "My iPhone" (override with
  `DEVICE_NAME=…`). Run weekly — free-team provisioning expires after 7 days.
  Works over the network tunnel; phone must be unlocked.

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

## Conventions

- Shared models/logic go in `Packages/OnigiriKit`, pure and unit-tested where possible.
- HealthKit is the log store (food/sodium/water samples); SwiftData holds only the
  library (foods, meals, goals). Do not add a second source of truth for logs.
- Free personal team: no iCloud/CloudKit entitlements; watch↔phone library sync is
  WatchConnectivity, log sync is HealthKit's own.
