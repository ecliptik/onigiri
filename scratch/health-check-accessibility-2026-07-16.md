# Accessibility Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 4, MEDIUM: 4, LOW: 2
- Health: GAPS

## Accessibility Surface Map
- Interactive elements correctly labeled throughout; no generic "Button"/"Image" labels found.
- Day-paging DragGesture and row-swipe DragGesture both have accessible equivalents (Previous/Next buttons, accessibilityAction(named:)).
- App/watch targets use @ScaledMetric consistently for headline/hero sizes. Widget/complication targets do NOT — every .font(.system(size: N)) in OnigiriWidgets/, OnigiriWatchWidgets/, ComplicationViews.swift is fixed pixel size.
- Color.sodiumStatus has a documented non-color twin (sodiumStatusLabel), but the accompanying .accessibilityValue is applied to un-grouped containers in at least two places — never reaches VoiceOver. No non-color twin exists at all for Color.remainingStatus (kcal "near budget" warning).
- No accessibilityFocus/AccessibilityFocusState usage anywhere.

## Issues by Severity

### HIGH — sodium-status .accessibilityValue applied to un-grouped container, never reaches VoiceOver
**File**: `Onigiri/Views/CalendarView.swift:329` (metric(icon:text:color:) HStack, no accessibilityElement), `OnigiriWatch/WatchMetricsView.swift:123` (metricCard outer HStack, no accessibilityElement)
**Issue**: accessibilityValue/Label has no effect unless applied to a single element or an explicitly grouped container (.accessibilityElement(children: .combine/.ignore)). Both sites apply it to a plain HStack — compare working examples at TodayView.swift:387-388, TodayCardWidget.swift:183-184, GoalView.swift:370-372 which pair accessibilityElement(children:) with the value. In-code comments state the intended behavior but the value is orphaned without grouping.
**Impact**: Colorblind/VoiceOver users hear only the raw number, no indication sodium is near/over limit — the exact info the color coding exists to convey is silently dropped.
**Fix**: Add `.accessibilityElement(children: .combine)` before `.accessibilityValue`.

### HIGH — "near budget" kcal warning color has no VoiceOver/text twin anywhere
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/BrandColors.swift:78` (Color.remainingStatus), consumed at TodayView.swift:402, GaugeWidget.swift:103, TodayCardWidget.swift:202, WatchHomeView.swift:114, OnigiriWatchWidgets.swift:366
**Issue**: remainingStatus has 3 states (green/amber-near-budget/orange-over) but CalorieBudget.remainingHeadline only distinguishes 2 captions ("kcal left"/"kcal over") — no textual distinction for the amber warning at any of 5 call sites. Contrast with sodiumStatus's deliberate non-color twin discipline.
**Impact**: 5 surfaces (iPhone headline, home widget, watch face, watch complication) give a purely visual amber warning with no VoiceOver/colorblind signal.
**Fix**: Add a remainingStatusLabel(kcal:) twin analogous to sodiumStatusLabel; surface via grouped .accessibilityValue at each of the 5 call sites.

### HIGH — Widget and complication text uses fixed pixel sizes with no Dynamic Type support
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/ComplicationViews.swift:66,71,88,123,128,161,240,247,262,264`, `OnigiriWidgets/TodayCardWidget.swift:199,210`, `OnigiriWidgets/MonthStatsWidget.swift:105,119`, `OnigiriWidgets/AccessoryWidgets.swift:103,111`
**Issue**: Every .font(.system(size: N)) is hardcoded; zero @ScaledMetric usage in widget/kit files, unlike TodayView/WatchHomeView/WatchLogView/OnboardingView/MonthGrid which all use it.
**Impact**: Lock-screen widgets, home-screen widgets, watch complications never grow text under Larger Text/accessibility sizes — the most glanceable, legibility-critical surfaces stay tiny.
**Fix**: Replace fixed sizes with @ScaledMetric(relativeTo:) properties or semantic text styles with minimumScaleFactor for space-constrained families.

### HIGH (compound) — DayNutritionView's sodium/water rows convey status by color with zero VoiceOver equivalent
**File**: `Onigiri/Views/DayNutritionView.swift:86-95`
**Issue**: Sodium row (.foregroundStyle(Color.sodiumStatus(...))) and water row (green/secondary) have no accessibilityValue/label at all — unlike TodayView (attempts it) and CalendarView/WatchMetricsView (attempt it, but broken per above). This is the one surface that doesn't even try.
**Fix**: Add .accessibilityValue(Color.sodiumStatusLabel(...)) to the sodium Text; analogous "goal met" value to the water row.

### MEDIUM — Long-press the Add pill to log water has no accessibilityAction equivalent
**File**: `Onigiri/Views/AddPillLongPress.swift:1-121` (installed via ContentView.swift:188-191)
**Issue**: Window-level UIGestureRecognizer bolted onto the tab bar's Add pill; no accessibility action or Switch Control equivalent.
**Impact**: VoiceOver/Switch Control users lose this one-tap shortcut, must fall back to the full Log sheet flow (not a dead end, just a gap in a convenience feature).
**Fix**: Document/expose the existing Home Screen quick-action shortcut (QuickActions/AppShortcuts.swift) as the accessible substitute.

### MEDIUM — EmojiUITextField uses hardcoded UIFont with no UIFontMetrics scaling
**File**: `Onigiri/Views/EmojiPrompt.swift:29,87`
**Issue**: Fixed 24pt font in a fixed 96×40 frame, no Dynamic Type scaling.
**Impact**: Low (one-glyph emoji picker), but inconsistent with the large emoji preview above it at large accessibility sizes.
**Fix**: Wrap in UIFontMetrics(forTextStyle:).scaledFont(for:), or note as a deliberate exception in-code.

### MEDIUM — OnigiriGauge's emoji glyph scales with frame, not Dynamic Type
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/OnigiriGauge.swift:20`
**Issue**: Every caller passes a fixed .frame(width:height:), so the badge never grows even when surrounding @ScaledMetric text does — increasingly mismatched layout at large text sizes.
**Fix**: Drive the gauge's .frame from @ScaledMetric at call sites, matching MonthGrid's DayCell pattern.

### LOW — No accessibilityFocus/AccessibilityFocusState usage anywhere (completeness note)
**Issue**: None of ~15 sheet/fullScreenCover presentations explicitly move VoiceOver focus onto presented content. Likely fine given system defaults, but worth a spot-check on denser sheets (MealFormView, FoodFormView, QuickLogSheet).

### LOW — Custom emoji icons rely on automatic VoiceOver pronunciation rather than explicit labels
**File**: `OnigiriWatch/WatchMetricsView.swift:142-144`, `Packages/OnigiriKit/Sources/OnigiriKit/ComplicationViews.swift:70-76,121-123`
**Issue**: User-chosen tracked-metric emoji rely on iOS's automatic emoji-to-word pronunciation, which can be unclear for custom/food emoji.
**Fix**: Optional explicit accessibilityLabel naming the metric.

## Recommendations
1. Immediate: fix the two broken .accessibilityValue groupings (CalendarView.swift:329, WatchMetricsView.swift:123) — one-line fixes.
2. Short-term: add remainingStatusLabel non-color twin (5 call sites); backfill DayNutritionView's sodium/water rows with the existing sodiumStatusLabel pattern.
3. Short-term: introduce @ScaledMetric-driven sizing in the widget/complication layer.
4. Long-term: spot-check sheet presentations with VoiceOver for focus landing; consider an accessible substitute for the Add-pill long-press shortcut.

## Testing Checklist
- [ ] VoiceOver test: Calendar day card and Watch Metrics page (sodium-status announcement bug)
- [ ] Dynamic Type at AX5: lock-screen widgets and watch complications
- [ ] Reduce Motion: no violations found (all animations respect system settings)
- [ ] External keyboard on iPad: not audited in depth, no .keyboardShortcut usage found
