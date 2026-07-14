# Onigiri 🍙

A personal calorie, nutrition, and water tracker for iPhone + Apple Watch, built with SwiftUI and integrated with Apple Health.

Runs on iOS/iPadOS **18.0+** and watchOS **10.0+** — back to the iPhone XS, iPad (7th gen), and Apple Watch Series 4. On iOS 26+ the app wears Liquid Glass; older versions get the standard system look, same features.

**This project was 100% built agentically using [Claude Code](https://claude.com/claude-code).**

## Screenshots

| Today | Foods | Goal | Calendar |
|---|---|---|---|
| ![Today: balance headline, hydration, goal gauge, meters, log](docs/showcase/light/today.png) | ![Food library with meals and foods, dark mode](docs/showcase/dark/foods.png) | ![Goal: weight trend with projection and the daily plan](docs/showcase/light/goal.png) | ![Calendar: month grid of earned onigiri and streaks, dark mode](docs/showcase/dark/calendar.png) |

### iPad & Apple Watch

| iPad portrait | iPad landscape (dark) |
|---|---|
| ![Today on iPad, portrait](docs/showcase/light/ipad-portrait.png) | ![Today on iPad, landscape, dark mode](docs/showcase/dark/ipad-landscape.png) |

![Apple Watch: balance headline with one-tap meal and water logging](docs/showcase/watch/home.png)

## Features

- **Daily calorie meter** — front and center: `Intake − (Active + Resting energy)` from Apple Health, plus remaining budget for the day
- **Weight goal tracking** — set a target weight and date; the app computes the daily deficit budget and projects your finish date from your actual weight trend (smart scale → Apple Health)
- **Food library** — save foods with calories + sodium (manual entry or barcode scan via OpenFoodFacts)
- **Meals** — bundle saved foods into one-tap recurring meals
- **Water tracking** — configurable serving size (e.g., 12 oz) and daily goal
- **Apple Watch app** — glanceable meter, one-tap water and meal logging, watch-face complications (balance + water)
- **Home-screen widgets** — small onigiri gauge, and a medium meter with instant add-water and a configurable one-tap meal button (no app launch)

## Architecture at a glance

- **SwiftUI** apps for iOS and watchOS; shared `OnigiriKit` Swift package for models and logic
- **HealthKit is the log store**: every food/water log is written as Health samples (dietary energy, sodium, water). Weight and energy burn are read from Health. This gives free iPhone↔Watch log sync, visibility in the Health app, and zero lock-in.
- **SwiftData** stores only the library: foods, meals, goals, settings. Synced to the watch via WatchConnectivity.
- **XcodeGen** (`project.yml`) generates the Xcode project — no `.xcodeproj` merge conflicts.

See [docs/PLAN.md](docs/PLAN.md) for the full design and roadmap.

## Development setup

1. Xcode 26 (Mac App Store), then:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app
   sudo xcodebuild -license accept
   xcodebuild -downloadPlatform iOS -downloadPlatform watchOS
   ```
2. `brew install xcodegen`
3. `cp local.yml.example local.yml` (set your team ID there for device builds; the empty default builds for the simulator)
4. `xcodegen generate` in the repo root, open `Onigiri.xcodeproj`
5. Xcode → Settings → Accounts → add your Apple ID (free personal team is fine)
6. On iPhone and Watch: Settings → Privacy & Security → Developer Mode → on
7. For `scripts/deploy-phone.sh`: `cp scripts/local-devices.env.example scripts/local-devices.env` and fill in your device name and watch IDs

**Free personal team note:** apps expire after 7 days — re-deploy weekly (⌘R with your phone connected, or `scripts/deploy-phone.sh`).

## License

MIT — see [LICENSE](LICENSE).
