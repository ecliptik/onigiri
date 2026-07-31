# SwiftUI Performance Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 0, MEDIUM: 1, LOW: 0
- Health: SMOOTH
- Zero regressions found in the v2.1.1 Today-log Equatable decomposition — confirmed intact and exemplary.

## Today log decomposition (regression check) — PASS
`Onigiri/Views/TodayView.swift`: MealSectionView (713), WaterSectionView (765), FoodLogRow (816), WaterLogRow (881) all still View+Equatable with explicit == excluding closures (725-730, 774-779, 822-823, 887-888); `.equatable()` applied at every call site (676, 690, 758, 805). RowSwipeState (706) correctly written-but-never-read in body. TodayModel.foodByCategory precomputed once per refresh (TodayModel.swift:196), not re-filtered per render. DailyGoalCard (1296) also Equatable, skips OnigiriGauge GeometryReader subtree when unchanged.

## Issues by Severity

### MEDIUM — visibleFoods recomputed twice per body evaluation in MealFormView
**File**: `Onigiri/Views/MealFormView.swift:60-89` (definition), used at lines 145 and 171
**Issue**: `visibleFoods` is a computed property that filters+sorts the entire foods array on every access; accessed twice per body invocation (ForEach at 145, empty-state check at 171) — runs on every keystroke in the filter field and every quantity edit (`.animation(.default, value: quantities)` at line 245 re-renders the whole form).
**Impact**: Small/imperceptible today at personal-library scale, but it's the exact anti-pattern `Onigiri/Views/FoodsView.swift:158-161` already fixed with a documented comment ("Bound once per evaluation..."). MealFormView never received that fix — latent regression risk if the library grows.
**Fix**: Bind once at the top of body: `let visible = visibleFoods` then use `visible` in both the ForEach and the empty-state check, matching FoodsView's pattern.

## Phase 2 anti-pattern sweep — all clear
- No file I/O, formatters, or image processing in any view body.
- All long lists use List/LazyVStack/LazyVGrid (MonthGridView uses LazyVGrid at MonthGrid.swift:51; TodayView log uses LazyVStack at line 612 despite already being Equatable-decomposed).
- All ForEach loops (23 call sites) use Identifiable models or explicit id:.
- No NavigationPath usage (NavigationStack + local @State selection/sheet enums) — no navigation-rebuild risk.
- Zero ObservableObject/@Published anywhere — fully migrated to @Observable.
- GeometryReader confined to single-instance non-scrolling views (OnigiriGauge, TodayView gaugeFill modifier, widget trackedMetricPill) — never inside a scrolling cell.
- No AsyncImage/uncached image loading in scrolling contexts (app has no remote images in lists).

## Performance Health Score

| Metric | Value |
|--------|-------|
| View body purity | ~30 files scanned, 0 with expensive ops in body (0%) |
| Scrolling cell safety | 6/6 clean cells (100%) |
| Lazy container usage | 7/7 contexts using List/LazyVStack/LazyVGrid (100%) |
| Collection efficiency | 9/10 bound-once or small-collection; 1 (MealFormView) double-evaluated (90%) |
| Observable efficiency | 100% migrated to @Observable |
| **Health** | **SMOOTH** |

## Recommendation
Apply the one-line "bind once" fix to MealFormView.swift matching FoodsView.swift:158-161 — trivial, consistent with established house pattern.
