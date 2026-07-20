# Onigiri 🍙

A personal calorie, nutrition, and water tracker for iPhone, iPad, and Apple Watch. Everything logged is saved to Apple Health, there's no account to sign up for and data always remains yours.

Runs on iPhone, iPad, and Apple Watch (iOS 18 / watchOS 10 or newer).

**[Website](https://ecliptik.github.io/onigiri/)** · **[User Guide](https://github.com/ecliptik/onigiri/wiki/User-Guide)** · **[Privacy Policy](https://ecliptik.github.io/onigiri/privacy/)**

**Built 100% agentically with [Claude Code](https://claude.com/claude-code).**

<p align="center">
  <img src="docs/showcase/light/today.png" width="300" alt="The Today screen: calorie balance headline, sodium and water, the daily goal gauge, energy meters, and the log">
</p>

## Features

- **Calorie & nutrition tracking** — your day at a glance: what you ate minus what you burned (Apple Health active + resting energy), with the calories you have left for the day.
- **Weight goal** — set a target weight and date. Onigiri works out the daily calorie budget to get there and projects your finish date from your real weight trend (smart scale → Apple Health).
- **Private by default** — no analytics, no ads, no servers, no tracking. Everything remains on your device: online lookups and AI are opt-in switches, offered once at onboarding and changeable anytime in Settings.
- **Barcode & label scanning** — snap a nutrition-facts label and the values are read on-device; with online lookups enabled, barcode scans and food search fill in from OpenFoodFacts and USDA FoodData Central.
- **AI features (optional — off by default)** — turn on one switch and Onigiri can estimate nutrition from a plain-language description ("pork and beans"), fill label values the scanner missed, identify a dish from a photo, and suggest meal names — every estimate reviewed before it's saved, and AI-created foods keep a small ✨ by their name. Runs on-device with Apple Intelligence, or bring your own AI: an Anthropic or OpenAI key, or any local OpenAI-compatible server (Ollama, LM Studio — Gemma, Qwen, and friends). Keys live in the Keychain; details in the [Privacy Policy](https://ecliptik.github.io/onigiri/privacy/#ai-features-optional).
- **Siri** — "Log water in Onigiri," "Log chicken and rice in Onigiri," "How many calories do I have left in Onigiri?": log water, saved meals, and favorite foods by voice, ask about your day, and (with AI on) describe a food and confirm the estimate hands-free. The same shortcuts work from Spotlight, the Action button, and the watch.
- **Fast logging** — log foods and water in a tap or two. Every entry is editable, with swipe to edit or delete and one-tap undo.
- **Custom meals** — bundle the foods you eat together into a meal, then log the whole thing in one tap.
- **Water tracking** — set your serving size and daily goal; log from the app, a widget, the watch, or a long-press on the add button.
- **Apple Watch app** — log on the go from a Favorites-then-Recent list, check your balance at a glance, and add balance and water complications to your watch face.
- **Widgets** — a Today widget (small, medium, large) with your calorie ring and a one-tap Log button, plus a month-stats card, water and streak widgets, and a Control Center water button.
- **Light & dark mode** — the app and its widgets follow your system appearance (screenshots below are light mode).

## Screenshots

| Foods | Goal | Calendar |
|---|---|---|
| <img src="docs/showcase/light/foods.png" width="260" alt="Food library with meals and foods"> | <img src="docs/showcase/light/goal.png" width="260" alt="Goal: weight trend with projection and the daily plan"> | <img src="docs/showcase/light/calendar.png" width="260" alt="Calendar: month grid of earned onigiri and streaks"> |

### iPad

<p align="center">
  <img src="docs/showcase/light/ipad-landscape.png" width="640" alt="Today on iPad: sidebar navigation with the day summary and the log side by side">
</p>

### Apple Watch

<p align="center">
  <img src="docs/showcase/watch/home.png" width="240" alt="Apple Watch: balance headline with a one-tap Log button and Log water">
</p>

### Home Screen widget

<p align="center">
  <img src="docs/showcase/widget/home-screen.png" width="300" alt="The medium Today widget on the Home Screen — calorie ring, burned and eaten, sodium and water, and a Log button — beside the stock iOS widgets">
</p>

## How the daily goal works

Onigiri reads your weight, what you eat, and what you burn from Apple Health, then turns them into a daily goal you can act on.

1. **Set a goal** — a target weight and date. Onigiri works out the **daily calorie deficit** you need to get there (burning more than you eat).
2. **Eat within your budget** — your budget is your average daily burn minus that deficit. As you log food, the Today ring shows **how much you can still eat today** and stay on pace.
3. **Lose weight** — finish each day at or under your budget and you hit the deficit; do it consistently and the scale follows.

**Example.** Your average burn is ~2,800 kcal/day and your goal needs a **350 kcal/day** deficit, leaving a **2,450 kcal budget**. You've eaten 2,300 so far, so the ring reads **150 kcal left** — room for 150 more and you'll still land on your target deficit by bedtime.

- **`kcal left` ≥ 0** → on track (still losing at your target pace).
- **Over budget** → you'll fall short of the pace for your target date (you may still lose, just slower).
- Eat nothing more and the deficit only grows — you'd *stop* losing only if you ate all the way up to your full burn (~2,800).

The **Daily goal** card shows the same thing from the deficit side: "245 of 350 kcal deficit" is what you've banked *so far* — the rest of the day's burn is still coming, which is why "245 banked" and "150 left to eat" both point at the same 350 target.

## Architecture at a glance

- **SwiftUI** apps for iOS and watchOS; shared `OnigiriKit` Swift package for models and logic
- **HealthKit is the log store**: every food/water log is written as Health samples (dietary energy, sodium, water). Weight and energy burn are read from Health. This gives free iPhone↔Watch log sync, visibility in the Health app, and zero lock-in.
- **SwiftData** stores only the library: foods, meals, goals, settings. Synced to the watch via WatchConnectivity.
- **XcodeGen** (`project.yml`) generates the Xcode project — no `.xcodeproj` merge conflicts.

See [plans/PLAN.md](plans/PLAN.md) for the full design and roadmap.

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

[PolyForm Noncommercial 1.0.0](LICENSE) — read it, build it, modify it,
and run it freely for any noncommercial purpose. Commercial use,
including selling this app or a derivative of it, is not permitted.
Releases through v2.2.0 were published under MIT and remain so.

Required Notice: Copyright (c) 2026 Micheal Waltz

The **Onigiri** name and icon identify this project and its official
builds; distribute forks under a different name and icon. This is a
personal project — issues are welcome, pull requests generally aren't
(see [CONTRIBUTING.md](CONTRIBUTING.md)).
