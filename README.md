# Onigiri 🍙

A personal calorie, sodium, and water tracker for iPhone + Apple Watch, built with SwiftUI and deeply integrated with Apple Health.

**Goal:** support losing 20 lb by making daily energy balance (calories in − calories out) effortless to see and log.

## Tour

<p align="center">
  <img src="docs/showcase/reel.gif" width="320" alt="Autoplaying 100-second tour of Onigiri: the daily balance, nutrition detail, fast logging, swipe editing, the streak calendar, predicted-vs-scale weight change, goal planning, and reminders.">
</p>

<p align="center"><em>Full quality: <a href="docs/showcase/reel.mp4">reel.mp4</a></em></p>

## Screenshots

<p>
  <img src="docs/showcase/light/today.png" width="24%" alt="Today: balance headline, hydration, goal gauge, meters, log">
  <img src="docs/showcase/light/nutrition.png" width="24%" alt="Day nutrition detail with macro and micronutrient groups">
  <img src="docs/showcase/light/logsheet.png" width="24%" alt="Log sheet: Recents, Favorites, meals tagged">
  <img src="docs/showcase/light/portion.png" width="24%" alt="Portion sheet confirming servings and meal slot">
</p>
<p>
  <img src="docs/showcase/light/calendar.png" width="24%" alt="Calendar: month grid of earned onigiri and streaks">
  <img src="docs/showcase/light/month.png" width="24%" alt="Month detail: total deficit, predicted vs scale change">
  <img src="docs/showcase/light/goal.png" width="24%" alt="Goal: daily plan with predicted vs actual">
  <img src="docs/showcase/light/foods.png" width="24%" alt="Food library with meals and foods">
</p>
<p>
  <img src="docs/showcase/dark/today.png" width="24%" alt="Today in dark mode">
  <img src="docs/showcase/dark/nutrition.png" width="24%" alt="Nutrition detail in dark mode">
  <img src="docs/showcase/dark/calendar.png" width="24%" alt="Calendar in dark mode">
  <img src="docs/showcase/dark/settings.png" width="24%" alt="Settings with reminder toggles in dark mode">
</p>

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
3. `xcodegen generate` in the repo root, open `Onigiri.xcodeproj`
4. Xcode → Settings → Accounts → add your Apple ID (free personal team is fine)
5. On iPhone and Watch: Settings → Privacy & Security → Developer Mode → on

**Free personal team note:** apps expire after 7 days — re-deploy weekly (⌘R with your phone connected).
