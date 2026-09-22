# SwiftUI Navigation Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 2, MEDIUM: 2, LOW: 1
- Health: FRAGILE

## Navigation Architecture Map
- 14 NavigationStacks (iOS) + 4 (watchOS), no NavigationPath anywhere, zero `.navigationDestination(for:)` calls. 3 static NavigationLink pushes (DayNutritionView, MonthDetailView, NutrientPickerView). One deep link (`onigiri://log`) from TodayCardWidget only — MonthStatsWidget/GaugeWidget have no widgetURL.
- Routing via shared @Observable QuickActions singleton with consumable Optional requests — correctly implements the documented "Bool flag goes dead" fix, applied consistently everywhere EXCEPT FoodFormView (see HIGH finding).
- FoodsView/QuickLogSheet were explicitly refactored to single `.sheet(item:)` enums; FoodFormView was NOT migrated.

## Issues by Severity

### HIGH — FoodFormView still uses two chained .sheet modifiers (the exact landmine CLAUDE.md says was fixed)
**File**: `Onigiri/Views/FoodFormView.swift:387` (`.sheet(isPresented: $showScanner)`) and `:394` (`.sheet(item: $portionTarget, onDismiss:)`)
**Issue**: Two separate .sheet modifiers on the same view — the exact pattern FoodsView.swift:24-28 and QuickLogSheet.swift:44 document having been refactored away from. FoodFormView was never migrated to the single ActiveSheet enum pattern.
**Impact**: Not actively broken today (triggers don't fire in the same run-loop turn currently), but one behavior change away from silently swallowing a presentation (e.g., an "auto-continue to portion after scan" feature, or a fast double-tap during dismiss animation).
**Fix**: Consolidate into `enum ActiveFormSheet: Identifiable { case scanner, portion(PortionTarget) }` + single `@State private var activeSheet`, matching FoodsView/QuickLogSheet.

### HIGH — Deep-link/quick-action sheet presents on top of a stale pushed DayNutritionView instead of returning to Today root
**File**: `Onigiri/Views/TodayView.swift:80` (bare NavigationStack, no path), `:469` (NavigationLink push to DayNutritionView), `:185` (.sheet(item:) on same stack), `:299-316` (consumeQuickLogRequest()), `Onigiri/ContentView.swift:109-118` (.onOpenURL deep link)
**Issue**: TodayView's NavigationStack has no path binding so nothing can force-pop it to root. DayNutritionView holds a live reference to the same TodayModel (not a snapshot). If the user is pushed into Day Nutrition and the onigiri://log widget deep link or app-icon quick action fires, consumeQuickLogRequest() calls model.select(day:) (re-rendering the still-visible DayNutritionView) then presents the Log sheet OVER Day Nutrition instead of over Today root.
**Impact**: User deep-links from widget/quick-action while navigated into day-detail sees the Log sheet stacked on an unexpected background screen; dismissing leaves them stranded on Day Nutrition instead of Today.
**Fix**: Give TodayView's NavigationStack a bound NavigationPath; in consumeQuickLogRequest(), pop it (`path = NavigationPath()`) before presenting activeSheet.

### MEDIUM — MonthStatsWidget and GaugeWidget have no widgetURL, tapping doesn't route anywhere specific
**File**: `OnigiriWidgets/MonthStatsWidget.swift:82-92`, `OnigiriWidgets/GaugeWidget.swift:6-18`
**Issue**: Unlike TodayCardWidget (widgetURL to onigiri://log), these widgets have no deep-link URL — tapping just launches to the default tab (Today), never Calendar (for MonthStats) or with day context (for Gauge).
**Fix**: Add a distinct deep link (e.g. onigiri://calendar) handled alongside onigiri://log in ContentView's .onOpenURL, wire via widgetURL/Link.

### MEDIUM — Missing NavigationPath / no state restoration for pushed detail views
**File**: `Onigiri/Views/TodayView.swift:80`, `Onigiri/Views/CalendarView.swift:26,367`, `Onigiri/Views/SettingsView.swift:727`
**Issue**: None of the app's 3 NavigationLink push destinations are addressable via NavigationPath; app termination while pushed drops the user back to tab root with no memory.
**Impact**: Minor — one-level-deep detail screens, low-cost state loss. Worth fixing only alongside the HIGH NavigationPath finding above.

### LOW — No @SceneStorage/state restoration for tab selection or scroll position
**File**: `Onigiri/ContentView.swift:16`
**Issue**: selectedTab and TodayModel.selectedDate reset to defaults on fresh launch. Very low impact — matches expected "home is Today/today" design.

## Recommendations
1. Immediate: add NavigationPath binding to TodayView's NavigationStack, pop it in consumeQuickLogRequest() before presenting sheets.
2. Short-term: consolidate FoodFormView's two chained .sheet modifiers into the ActiveSheet enum pattern.
3. Long-term: give MonthStatsWidget/GaugeWidget their own deep-link URLs.
