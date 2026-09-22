# Swift Concurrency Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 0, MEDIUM: 0
- Readiness: READY
- No concurrency safety issues found.

## Isolation Architecture Map
- App target sets SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor (project.yml:24) — @Observable view models MainActor-isolated by default. Packages/OnigiriKit (SPM) has no default-isolation setting; every UI/state-touching type there explicitly marked @MainActor (HealthKitService, DailyPlanLoader, PlanCache, WidgetReloader, LibraryMaintenance, LogIntents).
- ProductCache (OpenFoodFactsClient.swift:61) is a genuine actor guarding the process-wide barcode/product cache.
- WatchConnectivity delegates (PhoneSyncService, WatchSyncReceiver) use nonisolated func session(...) delegate methods extracting plain Sendable values before hopping to Task { @MainActor in ... }.
- Structured concurrency (async let/withTaskGroup) used pervasively for independent HealthKit reads; unstructured Task{} reserved for fire-and-forget UI actions and stored-task idioms with explicit cancel-on-supersede.
- Every stored Task is cancelled and nilled before replacement; generation counters (refreshGeneration, searchGeneration, summaryGeneration) guard against stale results.

## Files verified clean
- HealthKitService.swift — @MainActor class; one nonisolated(unsafe) let done = completion (line 101) correctly commented as HealthKit-safe-off-queue.
- WatchSync.swift, PhoneSyncService.swift, WatchSyncReceiver.swift — safe delegate-value-capture pattern, not the anti-pattern.
- OpenFoodFactsClient.swift, FoodDataCentralClient.swift — Sendable structs; shared ProductCache is a real actor; OnlineFoodSearch (@MainActor) cancels superseded tasks with generation guard.
- FoodIntelligence.swift — Foundation Models calls isolated to one file, every respond() call wrapped in do/catch with silent deterministic fallback.
- GCD DispatchQueue.main.async usages (OnboardingView, TodayView, AddPillLongPress, FoodFormView, EmojiPrompt, MealFormView, FoodsView) are all UIKit-bridging inside @MainActor contexts — not mixed with actor-protected state.
- 3 nonisolated(unsafe) uses (LogIntents.swift:6, QuickActions.swift:6 — Logger instances; LibraryModels.swift:495 — UserDefaults) all justified, documented, permanent escape hatches for genuinely thread-safe system types.

## Concurrency Health Score

| Metric | Value |
|--------|-------|
| Isolation coverage | High — every UI-facing/state-holding type is actor, @MainActor, or covered by default-isolation setting |
| Structured concurrency | High |
| Escape hatches | 3 nonisolated(unsafe), all justified; 0 @unchecked Sendable, 0 @preconcurrency |
| Cancellation coverage | 100% of stored Task properties cancelled/superseded correctly |
| GCD legacy | 7 DispatchQueue.main.async sites, all UIKit-bridging, no incoherence |
| **Readiness** | **READY** |

## Recommendations
1. No immediate action needed.
2. No escape-hatch migration needed.
3. Long-term: document the generation-counter + cancel-before-replace idiom as a house convention so new call sites replicate it.
