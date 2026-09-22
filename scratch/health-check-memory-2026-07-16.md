# Memory Leak Audit — Onigiri (2026-07-16)

## Resource Ownership Map
- No `Timer`, `Timer.publish`, `DispatchSourceTimer`, Combine `.sink`/`.assign`, or `PHImageManager` usage anywhere in the codebase — entire classes of leak pattern don't apply.
- `NotificationCenter` appears only via SwiftUI `.onReceive(NotificationCenter.default.publisher(...))` in views (OnboardingView.swift:74, FoodFormView.swift:350, MealFormView.swift:250, FoodsView.swift:885) — self-managing Combine subscription tied to view lifecycle, not addObserver/removeObserver. No leak.
- Long-lived resource owners are all `static let shared` singletons or app/scene-rooted objects matching their resource lifetime by design: PhoneSyncService.shared, ReminderScheduler.shared, QuickActions.shared, ToastCenter.shared, ProductCache.shared, PlanCache (enum/static state), WidgetReloader (enum/static state).
- HKObserverQuery registrations (HealthKitService.swift:95) are deliberately app-lifetime, held via @State on OnigiriApp/OnigiriWatchApp, idempotent-guarded (isObservingLogChanges) — correct, documented-intentional pattern.
- Stored Task properties (OnlineFoodSearch.searchTask/pageTask/detailTasks in OnlineResults.swift:22,64-65; WatchModel.refreshTask; PhoneSyncService.pushTask; PlanCache/WidgetReloader static tasks) all follow a consistent self-nilling/generation-guard idiom, explicitly cancelled on supersession.
- WCSessionDelegate (PhoneSyncService, WatchSyncReceiver) and UNUserNotificationCenterDelegate (ReminderScheduler) assign self to system singletons, but delegate holders are app-lifetime objects — not a cycle.
- ProductCache is an explicitly bounded FIFO (limit=200, OpenFoodFactsClient.swift:65-78) — no unbounded growth.
- No class implements deinit — none needs one.

## Summary
- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0

**No memory leak issues were found.**

## Memory Health Score

| Metric | Value |
|--------|-------|
| Resource ownership coverage | 0 classes require explicit cleanup; 5 stored-Task owners all self-cancel/self-nil (100%) |
| Timer lifecycle | 0 repeating timers found (N/A) |
| Observer lifecycle | 0 addObserver/KVO registrations found (N/A); HealthKit observer queries intentionally app-lifetime, idempotent-guarded |
| Task lifecycle | 5 classes with stored Task properties, all 5 cancel/nil on supersession or completion (100%) |
| Combine subscriptions | 0 .sink/.assign/AnyCancellable usages found |
| Unbounded collections | 0 — ProductCache is bounded FIFO; CalendarModel.totalsByDay grows proportionally to real usage |
| **Health** | **CLEAN** |

## Recommendations
1. No immediate action required.
2. Preserve existing conventions (generation-counter guards, self-nilling Tasks, bounded FIFO caches, singleton-scoped delegate ownership) as the pattern to follow for future features.
3. A confirmatory Instruments Leaks/Allocations pass during normal QA would be a good sanity check but isn't expected to surface anything given this static analysis.
