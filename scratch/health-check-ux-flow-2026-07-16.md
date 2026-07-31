# UX Flow Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 1, MEDIUM: 2, LOW: 0
- Health: ROUGH EDGES

## Journey Architecture Map
- Single WindowGroup, deep link (onigiri://log?day=) handled in ContentView.onOpenURL. App-icon quick actions via QuickActions.swift. One root TabView (Today/Foods/Goal/Calendar), each with own NavigationStack, sheets consistently `.sheet(item:)` single-slot enum. watchOS mirrors with 3-page TabView.
- Overall unusually disciplined UX hygiene (documented lessons in comments for past defects). No new instance of the already-tracked first-swipe/scroll conflict found.

## Issues by Severity

### HIGH — Dismiss trap + missing error state: WatchEntryEditSheet has no escape route and swallows failures
**File**: `OnigiriWatch/WatchLogView.swift:79-173`
**Issue**: Unlike every other sheet in the app (FoodFormView, MealFormView, WaterEditSheet, SettingsView, even the watch's own MealPickerView), `WatchEntryEditSheet` (`.sheet(item: $editing)` at WatchLogView.swift:50) is a bare ScrollView with no NavigationStack, no title, no Cancel action. Only ways out: Save (disabled until changed, stays open on HealthKit write failure per WatchModel.editEntry, WatchModel.swift:111-143), Remove (destructive, no confirmation), or an ambiguous system gesture. Additionally, `WatchEntryEditSheet.body` never reads `model.flash`/`model.flashIsError` — a failed save leaves the sheet open with no visible error (flash only renders in WatchHomeView/WatchLogView, behind the sheet, and auto-clears via flashGeneration).
**Impact**: A user who opened the wrong entry has no discoverable way to back out; a failed HealthKit edit shows no explanation.
**Fix**: Wrap the sheet body in a NavigationStack with .navigationTitle and a Cancel toolbar button matching every other form. Surface model.flash/flashIsError inside the sheet itself.

### MEDIUM — Platform parity gap: no iPad-adaptive layout despite explicit iPad support
**File**: `project.yml:38-52` (TARGETED_DEVICE_FAMILY "1,2", full iPad multitasking), all `Onigiri/Views/*.swift`
**Issue**: Zero matches for horizontalSizeClass, NavigationSplitView, regularWidth, UIDevice.current.userInterfaceIdiom anywhere in Onigiri/. Every screen is single-column NavigationStack in a TabView — no size-class-aware layout. iPad in landscape/Split View gets letterboxed/stretched iPhone-width columns.
**Fix**: At minimum wrap FoodsView/CalendarView's list+detail pairs in NavigationSplitView gated by .horizontalSizeClass == .regular, or explicitly document iPad as "runs fine, no bespoke layout" if that's the intent.

### MEDIUM — Reminder notifications don't deep-link into the action they're for
**File**: `Onigiri/Models/ReminderScheduler.swift:153-161`
**Issue**: ReminderScheduler implements `willPresent` (foreground banner) but not `didReceive response:withCompletionHandler:`. Tapping a "log lunch"/"log water"/"keep your streak" notification opens the app to whatever tab was last active — doesn't route to the Log sheet like app-icon quick actions already do for the same intents.
**Fix**: Implement didReceive response: and set QuickActions.shared.quickLogRequest based on the notification's category/identifier, reusing the existing consumable-Optional pattern.

## Recommendations
1. Immediate: fix WatchEntryEditSheet Cancel + in-sheet error surfacing.
2. Short-term: decide/implement an iPad story.
3. Longer-term: wire notification taps to the existing quick-log routing.
