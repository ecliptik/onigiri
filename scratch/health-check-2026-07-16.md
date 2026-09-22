# Onigiri Health Check — 2026-07-16

Scope: full project audit (no DIFF SCOPE block — whole repo scanned: Onigiri/, OnigiriWatch/, OnigiriWidgets/, OnigiriWatchWidgets/, Packages/OnigiriKit/, OnigiriUITests/).
Emphasis (from task framing): SwiftData safety, SwiftUI performance/layout, and accessibility — surfaced first below where severity allows.
Exclusions: none requested.

17 auditors run (6 always-run + 11 conditionally triggered by signal detection). 9 conditional auditors skipped — no signal (energy, camera, SpriteKit, networking, iCloud, database-schema, TextKit, Liquid Glass, screenshot-validator).

## Executive Summary (Top 5)

1. **CRITICAL** — Core Data / data-loss risk — `Packages/OnigiriKit/Sources/OnigiriKit/LibraryMaintenance.swift:41` — `existingObject(with:)` failures (transient I/O, locked store) are conflated with "row legitimately deleted" via `try?`, and the resulting delete is persisted — a real path to silently dropping a user's log entry during the app's own repair routine.
2. **CRITICAL** — App Store blocker — repo-wide — no `PrivacyInfo.xcprivacy` despite active use of two Required Reason API categories (UserDefaults, FileTimestamp); guaranteed App Store Connect rejection on next submission.
3. **HIGH** (accessibility, emphasized domain) — `Packages/OnigiriKit/Sources/OnigiriKit/BrandColors.swift:78` + 5 call sites — the "near budget" calorie warning color (`Color.remainingStatus`) has no VoiceOver/text twin anywhere, unlike the sodium-status convention it should mirror; and `CalendarView.swift:329`/`WatchMetricsView.swift:123` have a broken (ungrouped) `.accessibilityValue` that silently never reaches VoiceOver at all.
4. **HIGH** (SwiftUI architecture, emphasized domain) — `Onigiri/Views/TodayView.swift:450-465`, `GoalView.swift:61-75`, `OnboardingView.swift:292-305` — three views independently reimplement calorie-plan derivation instead of the shared, tested `DailyPlanLoader`; GoalView/Onboarding are missing the "never less than today's actual burn" floor that Today/widget/watch just got fixed for in 2.1.4 — the same bug class can silently resurface in Goal's preview.
5. **CRITICAL** — Test coverage gap on the exact code just fixed — `Packages/OnigiriKit/Sources/OnigiriKit/DailyPlanLoader.swift:46,53-54,65,84` and `HealthKitService.swift` (whole module) — the v2.1.4 burn-clamp fix and the entire HealthKit log-store layer have zero unit tests; a regression in either would only surface as a field bug.

## Scope Detection Detail
- Always-run: memory-auditor, security-privacy-scanner, accessibility-auditor, swift-performance-analyzer, modernization-helper, codable-auditor
- Conditional (triggered): swiftui-performance-analyzer, swiftui-architecture-auditor, swiftui-layout-auditor, swiftui-nav-auditor, swiftdata-auditor, core-data-auditor, concurrency-auditor, foundation-models-auditor, ux-flow-auditor, storage-auditor, testing-auditor
- Conditional (skipped, no signal): energy-auditor, camera-auditor, spritekit-auditor, networking-auditor, icloud-auditor, database-schema-auditor, textkit-auditor, liquid-glass-auditor, screenshot-validator

## Findings by Domain

### SwiftData (emphasized)
- MEDIUM — No VersionedSchema/SchemaMigrationPlan — `LibraryModels.swift:515-522` — every schema change so far has been additive-optional; no fallback for a future rename/required-field/model-split change.
- MEDIUM — `SharedStore.modelContainer()`'s `Schema([...])` omits `MealItem.self` — `LibraryModels.swift:516` — works today via transitive discovery, undocumented reliance.
- MEDIUM — Several mutation paths rely on implicit autosave instead of explicit `save()` — `FoodFormView.swift:697-723`, `MealFormView.swift:324-348`, `FoodsView.swift:350-373` — inconsistent with `GoalUpsert`/`LibraryTransfer`/`DebugSeeder`, which do call `save()` explicitly; narrow data-loss window on crash/force-quit.
- LOW — N+1-shaped relationship traversal in `repairDanglingFoodReferences` — `LibraryMaintenance.swift:80-96` — negligible at current scale.
- LOW — `PhoneSyncService.pushNow` recomputes meal totals per item on every sync push — `PhoneSyncService.swift:90-113` — negligible given 30-meal watch payload cap.
- **Verified correct, no regression**: every SwiftData relationship (`Food.mealItems`↔`MealItem.food`, `Meal.items`↔`MealItem.meal`) re-checked line-by-line and confirmed to have a genuine, working inverse with correct delete rules — the CLAUDE.md-documented landmine fix holds.

### Core Data (repair path — related to SwiftData safety)
- **CRITICAL** — `existingObject(with:)` failure conflated with "row is gone" — `LibraryMaintenance.swift:41` — see Executive Summary #1.
- HIGH — Silent `try?` on store removal — `LibraryMaintenance.swift:32` — a failed unload could leave the file locked when SwiftData immediately reopens it, whose failure path is `fatalError`. The project's own test (`LibraryMaintenanceTests.swift:107-108`) uses the throwing form — production code's silencing is inconsistent with tested behavior.
- MEDIUM — Repair fetch/save silently no-op on failure, zero observability — `LibraryMaintenance.swift:36-37,48`.
- LOW — No thread-confinement guard (`context.performAndWait`) on the repair context — `LibraryMaintenance.swift:35-48` — safe today only because the sole call site is main-thread `OnigiriApp.init()`.

### SwiftUI Performance (emphasized)
- MEDIUM — `MealFormView.visibleFoods` recomputed twice per body evaluation — `MealFormView.swift:60-89,145,171` — the exact anti-pattern `FoodsView.swift:158-161` already fixed with a documented comment; MealFormView never received that fix.
- Today-log Equatable decomposition (v2.1.1 scroll-perf fix) verified intact, no regression — `TodayView.swift` rows/sections still Equatable, `.equatable()` applied at every call site.

### SwiftUI Layout (emphasized)
- HIGH — Hardcoded iPhone/iPad width breakpoint instead of trait-collection size class — `AddPillLongPress.swift:100` (`window.bounds.width < 500`) — in Split View/Stage Manager, width can cross 500pt independent of device idiom; silently breaks the long-press-to-log-water gesture hit-test.
- MEDIUM — Fixed circular gauge frames don't scale with Dynamic Type — `TodayView.swift:386,1336` — unlike `MonthGrid.swift:104-106`'s `@ScaledMetric` precedent. **Overlaps with accessibility's OnigiriGauge.swift:20 finding below — same root gap, viewed from call-site vs component side.**
- MEDIUM — Missing explicit iPhone orientation declaration — `Info.plist`/`project.yml:52-58` — iPad gets all 4 orientations declared; iPhone landscape neither declared nor tested (UI tests force `.portrait` at 13 sites).
- MEDIUM — `EmojiPrompt` UITextField fixed font, no Dynamic Type scaling — `EmojiPrompt.swift:29,87` — **duplicate of accessibility's identical finding below (same file:line); merged severity MEDIUM, domains: swiftui-layout + accessibility.**
- LOW — GeometryReader-in-`.background` fill bars could migrate to `containerRelativeFrame` — `TodayView.swift:947-953`, `OnigiriGauge.swift:18-33`, `TodayCardWidget.swift:310-315` — modernization note, not a defect (all usages already safely constrained).
- LOW — Root `ContentView` uses one TabView for iPhone and iPad alike, no split/multi-column adaptation — `ContentView.swift:127-193` — acceptable for a 4-tab app; noted given the project's iPad multitasking investment.

### Accessibility (emphasized)
- HIGH — sodium-status `.accessibilityValue` applied to an un-grouped container, never reaches VoiceOver — `CalendarView.swift:329`, `WatchMetricsView.swift:123` — missing `.accessibilityElement(children: .combine)`; one-line fix, restores intended behavior.
- HIGH — "near budget" kcal warning color has no non-color/VoiceOver twin — `BrandColors.swift:78` + `TodayView.swift:402`, `GaugeWidget.swift:103`, `TodayCardWidget.swift:202`, `WatchHomeView.swift:114`, `OnigiriWatchWidgets.swift:366` — 5 surfaces give a purely visual amber warning.
- HIGH — Widget/complication text uses fixed pixel sizes, no Dynamic Type — `ComplicationViews.swift` (10 sites), `TodayCardWidget.swift:199,210`, `MonthStatsWidget.swift:105,119`, `AccessoryWidgets.swift:103,111` — zero `@ScaledMetric` usage, unlike every comparable app/watch screen.
- HIGH — `DayNutritionView`'s sodium/water rows convey status by color with zero VoiceOver equivalent — `DayNutritionView.swift:86-95` — the one surface that doesn't even attempt the pattern other screens (imperfectly) try.
- MEDIUM — Long-press Add pill (log water shortcut) has no `accessibilityAction` equivalent — `AddPillLongPress.swift:1-121` — convenience feature only, primary flow (Log sheet) remains reachable.
- MEDIUM — `EmojiPrompt` UITextField fixed font, no Dynamic Type — `EmojiPrompt.swift:29,87` — see swiftui-layout above (duplicate, merged).
- MEDIUM — `OnigiriGauge`'s emoji glyph scales with frame geometry, not Dynamic Type — `OnigiriGauge.swift:20` — every caller passes a fixed `.frame`, so the badge never grows even as `@ScaledMetric` text beside it does. See swiftui-layout's `TodayView.swift:386,1336` above (same root cause).
- LOW — No `accessibilityFocus`/`AccessibilityFocusState` anywhere — completeness note, spot-check sheets with VoiceOver.
- LOW — Custom tracked-metric emoji rely on automatic VoiceOver pronunciation rather than explicit labels — `WatchMetricsView.swift:142-144`, `ComplicationViews.swift:70-76,121-123`.

### SwiftUI Navigation
- HIGH — `FoodFormView` still uses two chained `.sheet` modifiers — `FoodFormView.swift:387,394` — the exact landmine CLAUDE.md documents as fixed elsewhere (`FoodsView`, `QuickLogSheet`); not actively broken today but one behavior change away from silently swallowing a presentation.
- HIGH — Deep-link/quick-action sheet presents on top of a stale pushed `DayNutritionView` instead of the Today root — `TodayView.swift:80,469,185,299-316`, `ContentView.swift:109-118` — `TodayView`'s `NavigationStack` has no `NavigationPath` to pop before presenting.
- MEDIUM — `MonthStatsWidget`/`GaugeWidget` have no `widgetURL` — `MonthStatsWidget.swift:82-92`, `GaugeWidget.swift:6-18` — tapping doesn't route to Calendar/day context, unlike `TodayCardWidget`.
- MEDIUM — Missing `NavigationPath` / no state restoration for pushed detail views — `TodayView.swift:80`, `CalendarView.swift:26,367`, `SettingsView.swift:727` — low-cost given one-tap-deep screens; worth fixing alongside the HIGH finding above.
- LOW — No `@SceneStorage` for tab selection — `ContentView.swift:16` — matches "home is Today/today by design."

### SwiftUI Architecture
- HIGH — `GoalView` owns HealthKit reads and derived trend math directly in the view — `GoalView.swift:12-33,237-268,279-312` — unlike Today/Calendar/Watch, which delegate to `@Observable` models; no unit-test safety net for the projection math (unlike `WeightTrendTests`).
- HIGH — Cross-view duplication of calorie-plan derivation — `TodayView.swift:450-465`, `GoalView.swift:61-75`, `OnboardingView.swift:292-305` — see Executive Summary #4.
- MEDIUM — Nontrivial search/paging/ranking logic lives in Views/, untested — `OnlineResults.swift:1-407` (`OnlineFoodSearch`) — comparable complexity to kit clients that are tested; this has zero coverage.
- LOW — Root views construct their own `@Observable` models rather than receiving them — `TodayView.swift:8,10`, `CalendarView.swift:8` — `TodayView` owns a second, independent `CalendarModel` instance duplicating `CalendarView`'s.

### Testing Quality
- **CRITICAL** — `HealthKitService.swift` (whole module) has zero unit tests — the app's entire log-store layer, including 7+ `HKError` branches, is untested.
- **CRITICAL** — `DailyPlanLoader.swift:46,53-54,65,84` — the v2.1.4 burn-clamp fix (`max(historicalAverage, todayActual, 2000)`) is untestable in isolation (hard-instantiates `HealthKitService()`) and has zero coverage.
- HIGH — `OpenFoodFactsClient.swift:89-148,248-340` — network/HTTP-error-mapping paths untested (only pure JSON parsing is covered); no `URLProtocol` stub harness exists.
- HIGH — `OnigiriUITests.swift:1876-1882` (`testGrantPendingAccess`) — an always-run (non-gated) test with a bare 3-second `Thread.sleep()` and no assertion of its own about post-grant app state.
- HIGH — HealthKit authorization-filtering logic (the 2.1.3 "write only authorized types" fix) — `HealthKitService.swift:58` — untested at the unit level, only indirect UI coverage.
- MEDIUM — `testHeaderShots` has zero assertions — `OnigiriUITests.swift:1571-1616` — capture-only tooling, flagged for visibility not urgency.
- MEDIUM — FDC API key Keychain round-trip untested — no dedicated test beyond string-shape validation.
- MEDIUM — Cumulative HealthKit seed data not defensively handled by streak/total assertions — `OnigiriUITests.swift:219,110,124,150` — hardcoded totals only correct on a freshly-erased simulator pair, matching a quirk CLAUDE.md already documents operationally but the test itself doesn't guard against.
- LOW — No Swift 6/`@MainActor` isolation issues found (clean result).
- LOW — No shared mutable state/order-dependence found (clean result).

### UX Flow
- HIGH — `WatchEntryEditSheet` has no Cancel and swallows failures — `OnigiriWatch/WatchLogView.swift:79-173` — bare `ScrollView`, no `NavigationStack`/title/Cancel, and `model.flash`/`flashIsError` is never read inside the sheet itself, so a failed save leaves it looking unresponsive.
- MEDIUM — No iPad-adaptive layout despite explicit iPad support — `project.yml:38-52` — related to the swiftui-layout iPad findings above (different specific gaps, same underlying "iPad is declared but under-served" theme).
- MEDIUM — Reminder notifications don't deep-link into the logging action — `ReminderScheduler.swift:153-161` — `didReceive response:` isn't implemented; tapping a reminder doesn't route like app-icon quick actions do for the same intent.

### Codable
- MEDIUM — Discarded `DecodingError` context in FDC parsing — `FoodDataCentralClient.swift:256-262,282-288` — no logging before rethrowing as generic `.badResponse`.
- MEDIUM — Silent field drop: `lastUsedAt` not preserved by `LibraryExport` — `LibraryExport.swift:8-37,49-68`, `LibraryTransfer.swift:14-35` — every backup/restore silently resets Favorites/recency ordering.
- MEDIUM — `WatchSync` date strategy consistency is implicit, not enforced — `WatchSync.swift:182-183,195,233,290` — 4 independent call sites agree only by coincidence.
- LOW — `LibraryTransfer.importData` catch discards structured decode detail — `LibraryTransfer.swift:131-133`.
- LOW — FDC numeric fallback silently zeros malformed values — `WatchSync.swift:259-267` — informational, currently safe by sentinel convention.

### Foundation Models
- MEDIUM — No evaluation suite for the three shipping AI affordances — `FoodIntelligence.swift` — on-device model drift has nothing to catch a regression.
- MEDIUM — Untrusted text (user input, OCR transcript) interpolated directly into prompt body — `FoodIntelligence.swift:103,137,194` — low practical risk given `@Generable`/`@Guide` containment and human-review-before-save design.
- LOW — No explicit cancellation surface for in-flight generations — `FoodFormView.swift:584-600`, `MealFormView.swift:284-290`, `ScanSheet.swift:201-229`.
- LOW — Fresh `LanguageModelSession` per call, no reuse — `FoodIntelligence.swift:96,131,185` — actually the correct pattern given stateless calls; noted only for awareness.
- LOW — Generic-only error handling — informational, matches CLAUDE.md's documented silent-fallback contract, not a defect.
- **Kit isolation boundary verified**: zero Foundation Models symbols anywhere in `Packages/OnigiriKit` — the app-only convention holds.

### Swift Performance
- MEDIUM — `NutrientValues.scalarFields` rebuilt from scratch on every call — `Nutrients.swift:393-405` — hit on every `+`/`scaled(by:)`/`isEmpty`/encode/decode; amplified by `PhoneSyncService.pushNow` running it over the entire library on every sync push.
- MEDIUM — `ProductCache` uses `Array.removeFirst()` as a FIFO queue — `OpenFoodFactsClient.swift:64-77` — O(n) eviction, currently network-bound so low real-world impact.
- LOW — `CalendarModel.trackedDays(inMonthOf:)` recomputed independently by 4 callers — `CalendarModel.swift:153-183`.

### Security & Privacy
- **CRITICAL** — Missing Privacy Manifest with Required Reason APIs in active use — see Executive Summary #2.
- HIGH — Export compliance declaration (`ITSAppUsesNonExemptEncryption`) absent from all 4 Info.plists — causes a manual prompt on every upload.
- MEDIUM — FDC API key transmitted as URL query parameter — `FoodDataCentralClient.swift:145,225` — dictated by USDA's API contract, not a code choice; low risk over HTTPS.
- LOW — No snapshot/background obscuring for sensitive screens — `ContentView.swift:15,77`, `OnigiriWatchApp.swift:14,58` — health/diet data visible in App Switcher snapshot.
- **Verified clean**: FDC key Keychain migration confirmed intact and correct (no regression), no hardcoded credentials, HTTPS-only, no sensitive data in logs, no ATT usage, no unused entitlements, no third-party SPM dependencies.

### Storage
- LOW — Missing explicit `FileProtectionType` on the library backup write — `BackupService.swift:44` — optional hardening; not a secret, default protection already applies.
- Otherwise clean: correct Keychain usage, correct App Group usage, bounded backup retention (5 backups kept), no iCloud dependency, versioned export format.

### Modernization
- LOW (×8) — `DispatchQueue.main.async` in UIViewRepresentable text-field coordinators, stylistic only — `OnboardingView.swift:78`, `FoodFormView.swift:360`, `FoodsView.swift:889,901`, `MealFormView.swift:255`, `EmojiPrompt.swift:34`, `AddPillLongPress.swift:23-28`, `TodayView.swift:1107,1146,1202`.
- Otherwise: fully migrated to `@Observable`/`@State`, no `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject` anywhere. Grade: excellent.

### Concurrency
- **Clean.** No CRITICAL/HIGH/MEDIUM issues. All 3 `nonisolated(unsafe)` uses justified (Logger, UserDefaults — documented thread-safe system types). 100% of stored `Task` properties cancel/supersede correctly. Structured concurrency (`async let`/`TaskGroup`) used consistently for independent HealthKit fan-outs.

### Memory
- **Clean.** Zero timer leaks, zero observer leaks, zero missing `[weak self]`, zero delegate cycles, zero PhotoKit/asset accumulation. All stored `Task`s self-cancel/nil; `ProductCache` is an explicitly bounded FIFO.

## Passed Audits (zero issues)
- **Memory** — clean, no findings of any severity.
- **Concurrency** — clean, no findings of any severity.

## Summary Table

| Auditor | Trigger Reason | Findings | Severity Breakdown | Report File |
|---------|----------------|----------|---------------------|--------------|
| testing-auditor | signal: XCTestCase/@Test/@Suite | 11 | 2 CRITICAL, 3 HIGH, 4 MEDIUM, 2 LOW | scratch/health-check-testing-2026-07-16.md |
| accessibility-auditor | always-run | 9 | 0 CRITICAL, 4 HIGH, 4 MEDIUM, 2 LOW (2 dup w/ swiftui-layout) | scratch/health-check-accessibility-2026-07-16.md |
| security-privacy-scanner | always-run | 4 | 1 CRITICAL, 1 HIGH, 1 MEDIUM, 1 LOW | scratch/health-check-security-2026-07-16.md |
| swiftui-layout-auditor | signal: NavigationStack/sheet/TabView | 6 | 0 CRITICAL, 1 HIGH, 3 MEDIUM, 2 LOW (1 dup w/ accessibility) | scratch/health-check-swiftui-layout-2026-07-16.md |
| swiftui-nav-auditor | signal: NavigationStack/sheet/TabView | 5 | 0 CRITICAL, 2 HIGH, 2 MEDIUM, 1 LOW | scratch/health-check-swiftui-nav-2026-07-16.md |
| swiftui-architecture-auditor | signal: SwiftUI import | 4 | 0 CRITICAL, 2 HIGH, 1 MEDIUM, 1 LOW | scratch/health-check-swiftui-architecture-2026-07-16.md |
| core-data-auditor | signal: import CoreData | 4 | 1 CRITICAL, 1 HIGH, 1 MEDIUM, 1 LOW | scratch/health-check-coredata-2026-07-16.md |
| swiftdata-auditor | signal: @Model | 5 | 0 CRITICAL, 0 HIGH, 3 MEDIUM, 2 LOW | scratch/health-check-swiftdata-2026-07-16.md |
| codable-auditor | always-run | 5 | 0 CRITICAL, 0 HIGH, 3 MEDIUM, 2 LOW | scratch/health-check-codable-2026-07-16.md |
| foundation-models-auditor | signal: LanguageModelSession/@Generable | 5 | 0 CRITICAL, 0 HIGH, 2 MEDIUM, 3 LOW | scratch/health-check-foundation-models-2026-07-16.md |
| ux-flow-auditor | signal: NavigationStack/sheet/TabView | 3 | 0 CRITICAL, 1 HIGH, 2 MEDIUM, 0 LOW | scratch/health-check-ux-flow-2026-07-16.md |
| swift-performance-analyzer | always-run | 3 | 0 CRITICAL, 0 HIGH, 2 MEDIUM, 1 LOW | scratch/health-check-swift-performance-2026-07-16.md |
| swiftui-performance-analyzer | signal: SwiftUI import | 1 | 0 CRITICAL, 0 HIGH, 1 MEDIUM, 0 LOW | scratch/health-check-swiftui-performance-2026-07-16.md |
| modernization-helper | always-run | 8 | 0 CRITICAL, 0 HIGH, 0 MEDIUM, 8 LOW | scratch/health-check-modernization-2026-07-16.md |
| storage-auditor | signal: FileManager/UserDefaults | 1 | 0 CRITICAL, 0 HIGH, 0 MEDIUM, 1 LOW | scratch/health-check-storage-2026-07-16.md |
| memory-auditor | always-run | 0 | clean | scratch/health-check-memory-2026-07-16.md |
| concurrency-auditor | signal: async/await/actor | 0 | clean | scratch/health-check-concurrency-2026-07-16.md |

Skipped (no signal): energy-auditor, camera-auditor, spritekit-auditor, networking-auditor, icloud-auditor, database-schema-auditor, textkit-auditor, liquid-glass-auditor, screenshot-validator.

## Cross-Domain Duplicates Identified During Dedup
1. `EmojiPrompt.swift:29,87` — flagged identically by accessibility-auditor and swiftui-layout-auditor (fixed UIFont, no Dynamic Type scaling). Counted once above, tagged both domains.
2. `OnigiriGauge.swift:20` (accessibility) + `TodayView.swift:386,1336` (swiftui-layout) — same root cause (gauge badge doesn't scale with Dynamic Type despite surrounding `@ScaledMetric` text) viewed from component vs. call-site side. Cross-referenced, not merged into one line item since the fixes differ slightly (component vs. call sites) but should be fixed together.
3. `project.yml` iPad support (ux-flow-auditor: "no adaptive layout") + `Info.plist`/orientation (swiftui-layout-auditor) + `AddPillLongPress.swift:100` breakpoint (swiftui-layout-auditor) — three auditors independently converged on "iPad is declared and provisioned but under-served by the UI," from different angles. Worth a single iPad-story decision rather than three piecemeal fixes.
