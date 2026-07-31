# Swift Performance Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0
- HIGH: 0
- MEDIUM: 2
- LOW: 1
- Health: OVERHEAD (no bottlenecks; one worthwhile allocation-avoidance fix)

## Issues by Severity

### MEDIUM — Repeated array-of-KeyPath-tuples allocation in NutrientValues arithmetic
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/Nutrients.swift:393-405`
**Issue**: `NutrientValues.scalarFields` is a computed property (11-element array of (WritableKeyPath, CodingKeys) tuples) rebuilt from scratch on every call — invoked from `isEmpty`, `scaled(by:)`, `+`, `encode(to:)`, `init(from:)`. `Sequence<FoodLogEntry>.totalNutrients` (FoodLogEntry.swift:49) and `Meal.totalNutrients` (LibraryModels.swift:147-149) call `+` in a reduce, rebuilding the array N times per computation. `PhoneSyncService.pushNow` (PhoneSyncService.swift:90-113) calls this over the ENTIRE food+meal library on every debounced sync push.
**Impact**: Hundreds of avoidable small allocations per sync push for a library of a few hundred items; recurs on every day-detail view load and meal row render.
**Fix**: Cache `scalarFields` as `private nonisolated(unsafe) static let` (same precedent as `SharedStore.defaults` in LibraryModels.swift:495) instead of a computed property.

### MEDIUM — ProductCache uses Array.removeFirst() as a FIFO queue
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/OpenFoodFactsClient.swift:64-77`
**Issue**: `order.removeFirst()` is O(n) per eviction once the 200-item cache is full. Currently network-bound and low-impact (I/O dwarfs the shift cost), but wrong-collection-for-access-pattern.
**Fix**: Use `Deque<String>` from swift-collections, or track a start index instead of physically removing from the front.

### LOW — CalendarModel.trackedDays(inMonthOf:) recomputed independently by four callers
**File**: `Onigiri/Models/CalendarModel.swift:153-183`
**Issue**: `totalDeficit`, `daysTracked`, `totalCalories`, `totalBurned` (all `inMonthOf:`) each independently call the private `trackedDays(inMonthOf:)`, filtering/mapping `totalsByDay` up to 4x for one screen render.
**Impact**: Negligible in absolute terms (dozens to low-hundreds of dict entries) — Quick Win, not a real bottleneck.
**Fix**: Memoize per month or compute all four aggregates in one pass.

## Quick Wins
1. Make `NutrientValues.scalarFields` a `nonisolated(unsafe) static let` — one-line change, removes an 11-tuple allocation from every nutrient arithmetic call site app+watch+widgets-wide.
2. Collapse CalendarModel's four month-aggregate methods into one pass.
3. Swap ProductCache.order from `[String]` to `Deque<String>` for O(1) eviction.

## Recommendations
- No CRITICAL/HIGH findings; nothing amplified in a genuinely hot loop.
- Cache NutrientValues.scalarFields first — cheapest fix, broadest reach.
- If the food/meal library grows into the thousands, revisit PhoneSyncService.pushNow's full-library recomputation on every debounced push.
- Already well-optimized: WeightTrend.movingAverage (explicit O(n²)→prefix-sum rewrite, documented in comments), StreakCalendar, CalorieBudget, PlanCache/DailyPlanLoader (batches concurrent HealthKit reads).
