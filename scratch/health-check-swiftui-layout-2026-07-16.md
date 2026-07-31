# SwiftUI Layout Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 1, MEDIUM: 3, LOW: 2
- Health: RIGID

## Layout Strategy Map
- 5 GeometryReader call sites, all safely constrained (root-with-external-frame or inside .background{}) — no anti-pattern instances.
- No horizontalSizeClass/verticalSizeClass usage anywhere — iPad adaptation uses a deliberate readableContentWidth() modifier (Style.swift:57-91) capping content at 700pt, applied to Today/Goal/Calendar/Foods/DayNutritionView/NutrientPicker.
- AnyLayout used correctly once (TodayCardWidget.swift:260-262) to switch HStackLayout/VStackLayout without losing child identity.
- Zero deprecated UIScreen.main/UIDevice.current.orientation in production code.

## Issues by Severity

### HIGH — Hardcoded iPhone/iPad breakpoint instead of trait-collection size class, in Split View/Stage Manager-reachable code
**File**: `Onigiri/Views/AddPillLongPress.swift:100`
**Issue**: The long-press-to-log-water gesture's hit-test (`window.bounds.width < 500`) assumes iPhone-vs-iPad by raw window width. project.yml explicitly enables full iPad multitasking (Split View/Slide Over/Stage Manager, all orientations) — an iPad in Split View or resizable Stage Manager window can land on either side of 500pt independent of device idiom.
**Impact**: In Split View widths straddling 500pt, the fallback hit-test can silently stop working for the corner "+" pill's long-press gesture — silent feature loss, not a crash.
**Fix**: Replace with `view.traitCollection.horizontalSizeClass == .compact`.

### MEDIUM — Fixed circular gauge frames don't scale with Dynamic Type, unlike a sibling component that does
**File**: `Onigiri/Views/TodayView.swift:386` (190×190 ring), `:1336` (84×84 OnigiriGauge)
**Issue**: Fixed pixel sizes; headline text relies on minimumScaleFactor(0.5) instead of the ring growing. MonthGrid.swift:104-106 already uses @ScaledMetric(relativeTo: .caption2) for exactly this reason (documented in its own comment).
**Fix**: Add `@ScaledMetric(relativeTo: .largeTitle) private var ringSize = 190.0` matching the MonthGrid precedent.

### MEDIUM — Missing explicit iPhone orientation support / unverified landscape layout
**File**: `Onigiri/Info.plist` (from project.yml:52-58)
**Issue**: project.yml sets UISupportedInterfaceOrientations~ipad (all 4) but never sets the plain UISupportedInterfaceOrientations key for iPhone. UI tests force .portrait at 13 call sites, only flip to landscape for iPad-specific QA runs — iPhone landscape neither declared nor tested.
**Fix**: Decide intent explicitly — declare portrait-only for iPhone, or add a landscape iPhone UI-test pass.

### MEDIUM — Fixed-size emoji UITextField bridge doesn't scale with Dynamic Type
**File**: `Onigiri/Views/EmojiPrompt.swift:29` (systemFont size 24, no UIFontMetrics), `:87` (.frame(width: 96, height: 40))
**Issue**: UIViewRepresentable-wrapped UITextField with hardcoded font size; every other text display in the app auto-scales or uses @ScaledMetric.
**Fix**: Scale via UIFontMetrics(forTextStyle: .title2).scaledFont(for:), size frame from @ScaledMetric.

### LOW — GeometryReader-in-.background fill bars could migrate to containerRelativeFrame
**File**: `Onigiri/Views/TodayView.swift:947-953`, `Packages/OnigiriKit/Sources/OnigiriKit/OnigiriGauge.swift:18-33`, `OnigiriWidgets/TodayCardWidget.swift:310-315`
**Issue**: Safe today (each usage already constrained), but textbook case for iOS 17+ containerRelativeFrame. Modernization note only, not a defect.

### LOW — Root ContentView uses one TabView for iPhone and iPad alike with no split/multi-column adaptation
**File**: `Onigiri/ContentView.swift:127-193`
**Issue**: Functionally fine for a 4-tab personal tracker; only the readableContentWidth() cap accommodates iPad. No action needed unless there's product intent to use iPad's larger canvas more deliberately.

## Recommendations
1. No CRITICAL layout defects.
2. Short-term: fix AddPillLongPress.swift:100 breakpoint; add @ScaledMetric to the two fixed gauge rings; decide/declare iPhone orientation support.
3. Long-term: consider Dynamic Type support for the emoji-prompt UITextField bridge; consider iPad-specific layout if iPad becomes a more deliberate target.
4. Test on: iPhone SE at largest accessibility text size; iPad Split View at ~480-520pt; iPhone landscape (currently untested).
