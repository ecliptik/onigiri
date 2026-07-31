# Test Quality Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 2, HIGH: 3, MEDIUM: 4, LOW: 2
- Health: GAPS

## Coverage Shape Map
- 22 kit test files (100% Swift Testing, zero XCTestCase); 1 XCUITest file (25 test functions, 6 run by default, 19 opt-in via TEST_RUNNER_* env vars).
- Untested kit modules: HealthKitService.swift (entire HealthKit read/write/auth layer), DailyPlanLoader.swift (v2.1.4 budget-follows-burn orchestration), FoodLogEntry.swift, WaterLogEntry.swift, LabelScan.swift (live Vision/camera driver — LabelParser itself is fixture-tested), LogIntents.swift, PlanCache.swift, OnigiriGauge.swift, ComplicationViews.swift, BrandColors.swift.

## Issues by Severity

### CRITICAL — HealthKitService has zero tests
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/HealthKitService.swift`
**Issue**: This is the log store of record for the entire app. Contains 7+ distinct HKError catch branches and all read/write paths for food/water/weight — none unit tested, only indirectly exercised via the UI test's grant-and-log flow.
**Fix**: Extract a thin protocol (HealthDataStore) HealthKitService conforms to, inject a fake in tests for the pure orchestration logic (auth gating, error-to-fallback mapping).

### CRITICAL — Untested HealthKitService() instantiated directly inside the v2.1.4 budget-follows-burn logic
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/DailyPlanLoader.swift:46,53-54,65,84`
**Issue**: computePlan(goal:) hard-instantiates HealthKitService(), making it impossible to unit test in isolation. The exact 2.1.4-fix logic — `max(((try? await burnRead) ?? nil) ?? 0, summary.totalBurnKcal, 2000)` (lines 65, 84) — guarding against the ring/widget/complication reading 0 once actual burn tops the 14-day average — has zero test coverage. CalorieBudgetTests tests CalorieBudget.plan given already-computed inputs, never the max() selection logic that produces averageBurn itself — precisely where the bug lived.
**Fix**: Extract averageBurn selection as a pure injectable function (e.g. DailyPlanLoader.effectiveAverageBurn(historicalAverage:todayActual:floor:)) and unit test directly.

### HIGH — OpenFoodFactsClient network/error paths untested
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/OpenFoodFactsClient.swift:89-148,248-340`
**Issue**: Only static parse/parseSearch/parseLegacySearch tested with hand-built JSON. Actual product(barcode:)/search/ALicious→legacy fallback/HTTP-status mapping (404→notFound, 429→throttled, 503→serverBusy) never exercised — no URLProtocol stub harness.
**Fix**: Add a URLProtocol-based stub session; cover each HTTP status→error mapping and the ALicious-fails→legacy-search-succeeds fallback.

### HIGH — 39 Thread.sleep() calls, mostly in opt-in tests but one always-run test has a bare sleep with no assertion after it
**File**: `OnigiriUITests/OnigiriUITests.swift` — 34/39 sleeps confined to env-gated capture tests (legitimate per CLAUDE.md); `testGrantPendingAccess` (line 1876, NOT env-gated) uses Thread.sleep(3) at line 1881 with no condition-based wait or assertion after.
**Fix**: Replace the trailing sleep in testGrantPendingAccess with waitForExistence on the post-grant element.

### HIGH — Recently-touched HealthKit auth path (2.1.3 fix) has no unit coverage
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/HealthKitService.swift:58` (shouldRequestAuthorization)
**Issue**: The 2.1.3 fix ("logFood writes only authorized nutrient types") touched exactly this surface; only indirect UI coverage via grantHealthAccess helper (tests the permission sheet UI, not the authorization-branching logic).
**Fix**: Extract per-type authorization-filtering logic into a pure testable function; unit test with fully- and partially-authorized sets.

### MEDIUM — testGrantPendingAccess has no meaningful assertions of its own
**File**: `OnigiriUITests/OnigiriUITests.swift:1876-1882`
**Issue**: Only assertion is buried in the shared grantHealthAccess helper; test itself asserts nothing about post-grant app state.
**Fix**: Add an assertion confirming the app landed on Today/tab bar, or fold into testSeedGrantAndLogFlow.

### MEDIUM — testHeaderShots has zero assertions (capture-only, flagging for visibility)
**File**: `OnigiriUITests/OnigiriUITests.swift:1571-1616`
**Issue**: Pure screenshot-capture tooling, not a regression check — low priority, noted so it isn't miscounted as coverage.

### MEDIUM — FDC API key Keychain storage untested
**File**: no test file for Keychain read/write; `FoodDataCentralTests.swift:271-276` only tests isPlausibleFDCKey string-shape validation.
**Issue**: The 4c6e426/63abc8d Keychain migration has no test of the actual save/load/delete round-trip.
**Fix**: Add a test exercising the Keychain-backed store's save→load→delete cycle.

### MEDIUM — Cumulative HealthKit seed data not defensively handled by streak/total assertions
**File**: `OnigiriUITests/OnigiriUITests.swift:219,110,124,150` (hardcoded "3 days"/"24 / 64 oz"/"154 g" totals)
**Issue**: CLAUDE.md documents that HealthKit seeding is cumulative across runs unless simulators are erased first, but the test has no defensive guard (pre-flight zero-sample check) beyond the orientation reset.
**Fix**: Compute expected totals from what the test itself seeds, or add a fail-fast pre-check for stale sim state.

### LOW — No Swift 6/@MainActor isolation issues found in the UI test target (clean result)
### LOW — No shared mutable state/order-dependence found (clean result)

## Quick Wins
1. Fix testGrantPendingAccess's missing assertion (10 min).
2. Extract DailyPlanLoader's averageBurn selection into a pure function with 3-4 test cases — directly covers the 2.1.4 bug class.
3. Add a URLProtocol stub harness for OpenFoodFactsClient's 4 HTTP-status mappings.

## Recommendations
1. Immediate: unit-test HealthKitService's auth-filtering logic (2.1.3 bug class) and DailyPlanLoader's burn-clamping logic (2.1.4 bug class) — both recently-fixed production incidents with zero regression coverage.
2. Short-term: URLProtocol-stubbed OpenFoodFactsClient tests, Keychain round-trip test, fix testGrantPendingAccess.
3. Long-term: make testSeedGrantAndLogFlow's total assertions self-computing or fail-fast on stale-sim state.
