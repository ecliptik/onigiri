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

## Conventions

- Shared models/logic go in `Packages/OnigiriKit`, pure and unit-tested where possible.
- HealthKit is the log store (food/sodium/water samples); SwiftData holds only the
  library (foods, meals, goals). Do not add a second source of truth for logs.
- Free personal team: no iCloud/CloudKit entitlements; watch↔phone library sync is
  WatchConnectivity, log sync is HealthKit's own.
