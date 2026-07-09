# Onigiri — Design & Roadmap

Personal-use calorie/sodium/water tracker for iPhone + Apple Watch. Goal: lose 20 lb, driven by a visible daily energy balance.

## Product decisions (settled)

| Decision | Choice |
|---|---|
| Dev account | Free personal team now; paid account later once the app proves itself |
| Food entry | Manual entry + barcode scan (OpenFoodFacts) |
| Goal model | Deficit budget derived from target weight + date, plus trend-based projection |
| Watch scope | Glanceable meter + one-tap water and saved-meal logging; food creation stays on iPhone |
| Nutrients | Calories and sodium only |

## Architecture

### Targets (XcodeGen `project.yml`)

1. **Onigiri** — iOS app, SwiftUI
2. **OnigiriWatch** — watchOS app, SwiftUI
3. **OnigiriKit** — local Swift package shared by both: models, HealthKit service, budget math, OpenFoodFacts client
4. **Widgets** (later phase) — WidgetKit extensions: iPhone home-screen widget + watch complication

### Data: HealthKit is the log store, SwiftData is the library

**Logs → HealthKit** (source of truth for anything time-series):

- Food/meal logging writes `HKCorrelation(.food)` wrapping `dietaryEnergyConsumed` (kcal) + `dietarySodium` (mg) samples, with metadata carrying the food/meal name so today's log can be listed and entries deleted.
- Water logging writes `dietaryWater` samples.
- Reads: `activeEnergyBurned`, `basalEnergyBurned`, `bodyMass` (smart scale), plus `dietaryEnergyConsumed`/`dietaryWater` from all sources (so anything logged elsewhere still counts).

Why: HealthKit syncs iPhone↔Watch automatically (no iCloud needed — critical on a free team), data shows up in the Health app, and there is zero lock-in if you ever switch trackers.

**Library → SwiftData** (local, iPhone-owned):

- `Food` — name, calories (kcal), sodium (mg), serving description, optional barcode
- `Meal` — name + list of (food, quantity) portions
- `GoalSettings` — target weight, target date, start weight/date, water serving size (oz), daily water goal, units

Library and settings are pushed to the watch via WatchConnectivity `applicationContext` (small payload, latest-wins — right fit for a reference list).

### Calorie meter & budget math

- **Meter:** `Intake − (Active + Resting)` for today. Resting energy accrues during the day, so the balance is honest at any hour.
- **Budget:** 20 lb ≈ 70,000 kcal (3,500 kcal/lb). Required daily deficit = remaining kcal ÷ days to target date. Daily budget = expected TDEE (14-day average total burn from HealthKit) − required deficit.
- **Guardrails:** warn when the required deficit exceeds ~1,000 kcal/day or the budget drops below ~1,500 kcal — nudge to move the target date instead.
- **Progress:** 7-day moving average of weight (raw scale readings are noisy) charted against the goal line, with a projected finish date at the current trend.

### Barcode scanning

VisionKit `DataScannerViewController` → OpenFoodFacts REST lookup → prefill the new-food form (name, kcal, sodium; convert salt→sodium ×0.4 when OFF only has salt). Foods are always saved to the local library, so scanning is a one-time event per product and daily logging stays offline.

## Free personal team caveats

- App expires on device after **7 days** — re-deploy weekly (⌘R with iPhone connected, or a scripted `xcodebuild` install).
- Max ~3 free-team apps per device; 10 app IDs per week (we use 2–3 — fine).
- No CloudKit/iCloud, no push — the HealthKit + WatchConnectivity design avoids needing them.
- Upgrading to a paid account later is only a signing-team switch; no redesign.

## Roadmap

- [x] **Phase 0 — Environment**: Xcode 26.6 + iOS/watchOS 26.5 simulators installed. *Remaining when we first deploy to hardware: Apple ID added as personal team in Xcode, Developer Mode on iPhone + Watch.*
- [x] **Phase 1 — Scaffold**: XcodeGen project; iOS + watch apps boot in simulators
- [x] **Phase 2 — Meter**: HealthKit authorization + read pipeline; home-screen calorie meter (intake, burn, balance)
- [x] **Phase 3 — Food**: food library CRUD, logging with sodium, one-tap meals. *Pulled forward from Phase 5: goal settings (target weight/date), deficit budget, and the onigiri daily-goal gauge on Today. Also: app icon (🍙), XCUITest end-to-end flow.*
- [ ] **Phase 4 — Water**: quick-add serving, daily goal ring
- [ ] **Phase 5 — Goal**: weight trend chart (Swift Charts) + projected finish date
- [ ] **Phase 6 — Watch**: meter view, one-tap water + meals, complication, library sync
- [ ] **Phase 7 — Barcode**: VisionKit scanner + OpenFoodFacts
- [ ] **Phase 8 — Polish**: iPhone home-screen widget, on-device deployment, weekly re-deploy script
