# SwiftUI Architecture Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 2, MEDIUM: 1, LOW: 1
- Health: TANGLED

## Architecture Boundary Map
- 33 View structs across 17 files vs 7 @Observable classes (~4.7:1). Most business logic correctly lives in OnigiriKit. Exceptions: GoalView (trend-projection math + HealthKit reads in the view itself) and duplicated calorie-plan derivation across three views.

## Issues by Severity

### HIGH — GoalView owns HealthKit reads and derived business math directly in the view
**File**: `Onigiri/Views/GoalView.swift:12-33` (state), `:237-268` (.task with concurrent HealthKit reads + staleness gating), `:279-312` (deriveTrendStats() — least-squares slope projection, target-date projection, chart domain calc)
**Issue**: Unlike TodayView/CalendarView/WatchHomeView (all delegate to @Observable models), GoalView keeps ~15 @State properties and performs async HealthKit fan-out + trend projection math as private methods on the View struct itself. No unit-test safety net (unlike WeightTrendTests/CalorieBudgetTests in the kit) for the projection math.
**Fix**: Introduce a GoalModel (@Observable, in Onigiri/Models/) mirroring TodayModel/CalendarModel; move .task HealthKit reads, staleness gate, and deriveTrendStats() (pushing pure slope/projection arithmetic into OnigiriKit next to WeightTrend) into the model.

### HIGH — Cross-view duplication of calorie-budget plan derivation (validation-adjacent divergence risk)
**File**: `Onigiri/Views/TodayView.swift:450-465` (plan(for:)), `Onigiri/Views/GoalView.swift:61-75` (plan), `Onigiri/Views/OnboardingView.swift:292-305` (previewPlan)
**Issue**: Three views independently reimplement the same derivation instead of using the already-shared, tested `DailyPlanLoader.load(goal:)` (Packages/OnigiriKit/Sources/OnigiriKit/DailyPlanLoader.swift:36-105) that CalendarModel/WatchModel call. Critically, TodayView uses `model.expectedDailyBurnKcal` (max of average/actual-burn/2000, matching DailyPlanLoader's rule) while GoalView and OnboardingView use a bare `averageBurnKcal ?? 2000` — missing the "never less than today's actual burn" floor. In-code comments even acknowledge the duplication.
**Impact**: GoalView's/Onboarding's previewed plan can silently disagree with what Today/widget/watch actually show once burn-past-average kicks in — the exact bug class the 2.1.4 changelog says was just fixed for Today/widget/watch, but not propagated to Goal/Onboarding's preview.
**Fix**: Route GoalView.plan and OnboardingView.previewPlan through DailyPlanLoader, or extract the shared logic into one OnigiriKit helper so all four call sites can't drift again.

### MEDIUM — Nontrivial search/paging/ranking logic lives in Views/ instead of OnigiriKit, untested
**File**: `Onigiri/Views/OnlineResults.swift:1-407` (OnlineFoodSearch class)
**Issue**: @MainActor @Observable class with substantial business logic (dual-source concurrent paging, stable-append rank-merging, missing-calorie weeding with capped backfill, generation-based cancellation) comparable in complexity to FoodDataCentralClient/OpenFoodFactsClient (both in OnigiriKit, both tested) — but OnlineFoodSearch has zero test coverage.
**Fix**: Extract the paging/ranking/weeding state machine into a plain Sendable OnigiriKit-resident type; add unit tests for the Both-mode stable-append merge and auto-backfill cap.

### LOW — Root views construct their own @Observable models rather than receiving them
**File**: `Onigiri/Views/TodayView.swift:8,10` (model + monthModel = CalendarModel()), `Onigiri/Views/CalendarView.swift:8` (model = CalendarModel())
**Issue**: TodayView owns a second, independent CalendarModel instance duplicating the one CalendarView owns — two instances loading/caching the same HealthKit data separately. Acceptable for tab-root screens but worth noting.
**Fix**: Not urgent; promote to a shared @Environment instance only if the two are observed to diverge.

## Recommendations
1. No CRITICAL issues.
2. Short-term (HIGH): extract GoalView's logic into GoalModel; collapse the three plan derivations onto DailyPlanLoader/CalorieBudget.
3. Longer-term (MEDIUM): move OnlineFoodSearch's state machine into OnigiriKit with tests.
