# Onigiri — post-1.3.5 polish plan (RELEASED as v1.4.0, 2026-07-13)

Written at the v1.3.5 tag (2026-07-12), from a full seven-angle review:
onboarding, the logging loop, goals/settings, history/calendar, watch +
widgets, a style-consistency audit, and a dedicated bug sweep. Read
`CLAUDE.md` first (build/deploy/test mechanics, landmines) and
`docs/PLAN.md` for design history. The rhythm: fix → test (package +
affected UI tests on ERASED sims) → commit → push → deploy to phone AND
watch → say exactly what to verify on device.

What the review did NOT find: crashes in normal use, softlocked
onboarding, day-bounds/DST bugs, silent HealthKit failures on the phone
(everything funnels through `LogActions` with toast+haptic+undo), or
divergent goal math between surfaces. The core loop is sound — water is
one tap, backfill is first-class, undo works. The items below are the
gap between "works" and "polished".

## Tier 1 — bugs & softlocks — ALL SHIPPED 2026-07-12 (same session as this doc)

All eight landed together: write-then-delete edits (undo restores before
deleting, with a rollback if the original's delete fails), the search
generation counter (also fixes a resubmit-same-query race the string
compare couldn't see), the `followsToday` intent flag, the portion
clamp + every HealthKit-fed `Int(Double)` cast swapped to `formatted()`
(which also fixed Tier 6 #35's "12000 vs 12,000" for free), the
`MealItem.meal` inverse with package tests covering the trap scenario,
QuickLogSheet's single enum sheet slot, GoalView's confirmed Remove
Goal row (plus `ReminderScheduler.replan()` on save — Tier 2 #9's
scheduling half), and the meal-intent name fallback + thrown error.
Bonus: `PhoneSyncService.push` now reloads widget timelines, closing
Tier 2 #14's main gap at the choke point.

1. **Edit-entry can lose the entry** — `Feedback.swift:130-152`.
   `editFoodEntry` deletes the original HealthKit correlation, THEN
   writes the replacement; a write failure after the delete loses the
   entry with only a "Couldn't update" toast. The undo closure has the
   same delete-first shape with a `try?` re-log. Fix: write-then-delete
   in both directions, and toast if restoration fails.

2. **Online-search paging softlock** — `OnlineResults.swift:71-94`.
   `loadMore()`'s superseded-query guard returns before resetting
   `isLoadingMore`; a new search submitted while page 2 is in flight
   leaves a permanent "Searching…" row and paging dead until the field
   passes through empty (the Foods tab's search object is long-lived).
   Fix: reset `isLoadingMore` unconditionally; same hygiene for
   `isSearching`.

3. **Today never rolls past midnight** — `TodayModel.swift:106-110`.
   The roll-forward branch is gated on `isToday`, which is already
   false once the date changes — dead code. App open (or resumed)
   across midnight stays on yesterday, and a quick log then gets the
   backfill noon-of-yesterday timestamp: food eaten after midnight
   lands on the wrong day at a fabricated time. Fix: track "following
   today" intent (cleared only by explicit day navigation) instead of
   comparing dates.

4. **Unbounded portion quantity can trap** — `FoodsView` PortionSheet
   quantity `TextField` bypasses the stepper's 0.01…100 clamp; an
   absurd typed value (e.g. `1e18`) logs an entry whose kcal overflow
   `Int(Double)` casts in row/accessibility labels and crash-loops the
   Today tab until the entry is deleted in Health. Fix: clamp on
   commit; audit `Int(…)` casts on HealthKit-sourced doubles.

5. **`Meal.items` violates the inverse rule** — `LibraryModels.swift:121`,
   `MealFormView.swift:127-128`. No inverse on the cascade
   relationship, and MealFormView deletes old items before unlinking —
   the exact preconditions of the documented "backing data could no
   longer be found" process-kill; currently safe only because every
   call site happens to detach first. Fix: add the `MealItem.meal`
   inverse; unlink before delete.

6. **QuickLogSheet stacks five chained `.sheet`s** —
   `QuickLogSheet.swift:246-271`. The documented landmine class TodayView
   was refactored away from. Concrete casualty: scanning a barcode
   already in the library sets `portionTarget` while the scanner sheet
   is still dismissing, so the portion sheet can silently fail to
   appear — the scan is eaten. Fix: consolidate into one enum-driven
   `.sheet(item:)`.

7. **A goal can never be removed** — `GoalView.swift:272-288`. No
   delete path exists anywhere (`GoalUpdate.clear` in the sync layer is
   unreachable). Hitting the target or quitting the diet leaves the
   deficit budget, gauge, and streak judging active forever. Fix:
   destructive "Remove Goal" row (confirmed) that deletes
   `GoalSettings`, pushes sync, replans reminders, reloads widgets.

8. **Widget meal button can silently no-op** — `LogIntents.swift:32-44`.
   A configured meal deleted/re-created on the phone leaves the widget
   button live but doing nothing (`return .result()` on lookup miss),
   and neither intent checks Health write authorization — a widget
   added before first launch "logs" nothing, no feedback. Fix: throw a
   user-visible error on lookup miss and on auth failure.

## Tier 2 — correctness — ALL SHIPPED 2026-07-12 (same session)

All seven landed: reminders judge today live (and the plan-load stamp
runs on every replan even with reminders off); slot totals ride the
day-summary generation guard; months past the 92-day window load on
demand (`dailyEnergyTotals(from:to:)` + `ensureTotals(forMonthOf:)`);
per-day deficit-target snapshots (`DeficitTargetHistory` — recorded by
every `DailyPlanLoader.load`, judged by `StreakCalendar` per day, shown
on the day card; 0 = the no-goal rule; unsnapshotted days fall back to
the current target as before); import names its goal/water overwrite
and skip counts, export failures surface; all three widget providers
cut timelines at midnight with a pre-rendered zeroed entry and return
the placeholder in gallery previews, and the appex/watch version
strings now track MARKETING_VERSION; one shared `GoalUpsert`
validation+save behind GoalView AND onboarding with inline
"target must be below current weight" copy.

9. **Streak reminders judge today wrong** — `ReminderScheduler.swift:77-87`.
   `todayGoalMet` is computed from `earnedDays`, which excludes today
   by design, so it is constitutionally false: the 8 PM "streak on the
   line" warning fires even when today is already banked, and the
   tomorrow-pre-plan branch in `ReminderPlanner` is dead code. Also
   passes no `untrackedBelowKcal`, so the reminder's streak length can
   disagree with the Calendar tab's. Fix: judge today live from the
   plan summary; pass the shared threshold.

10. **Calendar slot totals race + error-as-zero** —
    `CalendarView.swift:306-314`. `loadSlotTotals` lacks the generation
    guard its sibling has (fast day-swiping can display a previous
    day's protein next to the current day's calories) and renders a
    failed read as "0 mg" instead of "—". Fix: fold into
    `loadDaySummary` under `summaryGeneration`; keep nil on error.

11. **The 92-day data cliff** — `CalendarModel.swift:26`,
    `HealthKitService.swift:215`. Months older than ~3 months render
    half-empty: every day "goal not met" (VoiceOver says so too), day
    cards show "—", Month Detail says "Days tracked: 0" beside real
    foods-logged/water numbers queried directly. Fix: fetch totals for
    the displayed month on demand, or stop paging at the horizon with
    "History starts <date>".

12. **Past days are judged against today's goal** —
    `CalendarModel.swift:24-37`, `DayNutritionView.swift:11-12`. The
    deficit target recomputes from current weight/date/burn and applies
    retroactively — losing weight or editing the goal silently rewrites
    which past days earned an onigiri; streaks shrink overnight with no
    entry changing. Real fix: snapshot the day's target when the day
    closes. Stopgap: label history cards "vs current goal".

13. **Import silently overwrites goal + water settings** —
    `LibraryTransfer.swift:81-95`. Foods/meals import additively, but a
    restore quietly regresses the goal to a stale target date (which
    can then demand a huge daily deficit). Fix: confirm or opt-in the
    goal/water portion; name it in the result message. Also: export
    failures are completely silent (`try?` at `SettingsView.swift:103-106`)
    and the import summary hides name-matched skips ("Imported 0 foods ✓"
    after restoring a full backup reads as failure).

14. **Settings changes leave widgets stale — FULLY SHIPPED 2026-07-12**:
    choke-point reload in `PhoneSyncService.push`, midnight timeline cut
    with a pre-rendered zeroed entry in all three providers, gallery
    previews render the placeholder, and the appex/watch
    CFBundleShortVersionString now tracks MARKETING_VERSION.

15. **GoalView saves goals onboarding would reject** —
    `GoalView.swift:28-34` vs `OnboardingView.swift:217-221`. Target ≥
    current weight saves silently; the plan section just vanishes and
    `DailyPlanLoader` renders a full gauge. Onboarding has the inverse
    bugs: re-saving after a back-swipe no-ops under a button that says
    "Save Goal" (`saveGoalIfValid` guards on `goals.isEmpty`), an
    invalid target shows "No goal set" copy, and a goal can save with
    NO current weight at all — a half-state GoalView then can't edit
    (Save stays disabled). Fix: one shared upsert + validation for both
    surfaces, with inline "target must be below current weight" copy.

## Tier 3 — daily-loop friction — ALL SHIPPED 2026-07-12 (same session)

All ten landed: log-row deletes commit outright with an Undo toast
(alert gone; water rows too); Today's scan (menu AND app-icon quick
action) routes to the Log sheet's scanner via a new `.scan` kind —
library fast path + browsed-day logDate — and the Foods-tab
scanRequest plumbing is gone; the edit PortionSheet moves entries in
date/time and water rows gained an edit sheet (`editWaterEntry`, same
write-then-delete + undo shape); the portion field commits before Log
reads it (focus resign + one-runloop defer) with a Done affordance;
Save / Save & Log toolbar replaced the post-save alert; both forms
confirm discard when dirty (`interactiveDismissDisabled` + snapshot
compare); the Log sheet stays open after logging (toolbar reads Done)
with row-tap = portion sheet and edit demoted to a leading swipe (+
accessibility action); Today log rows tap-to-edit; `FoodSearchSheet`
now renders the shared `OnlineResultsSection` (stale-query button,
clear-on-empty, failure state, Add Food fallback all came free — the
CLAUDE.md two-list rule is retired); the duplicate guard matches
barcode before name. Flow-test expectations updated to the new UX.

16. **Delete should be one swipe + undo, not four gestures + alert.**
    `TodayView.swift:243-262`. The safety models are inverted: a cheap
    accidental log gets an Undo toast; delete gets a modal claiming
    "This can't be undone" — false, re-logging the captured values is
    exactly what edit-undo already does. Drop the alert, delete
    immediately, show the 5-second Undo toast.

17. **Today's "Scan barcode" routes to the wrong scanner** —
    `TodayView.swift:673-675` → Foods tab's new-food form. It skips the
    library-barcode fast path (known product = 1-tap portion sheet in
    QuickLogSheet's scanner), loses the browsed-day `logDate` (a scan
    while viewing Tuesday logs to NOW), and strands the user on the
    Foods tab. Route to the Log sheet with an auto-open-scanner flag.

18. **An entry's time/date can't be changed, ever** — edit is
    rescale+slot only (`Feedback.swift:130`); water entries have no
    edit at all. "Logged dinner at 11 pm that belonged to yesterday" =
    delete + re-log. `editFoodEntry` is already delete-and-recreate, so
    threading a new date through is nearly free; give water rows the
    same swipe with an amount field.

19. **PortionSheet typed-quantity commit race** — `FoodsView.swift:465-471`.
    `TextField(value:format:)` commits on focus resignation, the
    decimal pad has no return key, and PortionSheet has no
    `@FocusState`/Done (FoodFormView solved this exact problem). Typing
    0.5 then tapping Log plausibly logs 1.0. Resign focus inside the
    Log action; add the Done affordance. (Same mechanics make
    FoodFormView's Save look dead while kcal is uncommitted.)

20. **"Save & Log" instead of the post-save alert** —
    `FoodFormView.swift:442-445`. Every online pick funnels through
    save → "Log?" alert → portion sheet; the alert is a whole modal for
    a yes/no, and "log a one-off without saving" (which a comment
    claims exists) doesn't. Toolbar Save / Save & Log; consider a true
    one-off path. The stale "(Save / Save & Log)" comment at
    `FoodsView.swift:209` gets fixed for free.

21. **Cancel/swipe-down silently discards a fully-typed food form** —
    `FoodFormView.swift`, `MealFormView.swift`. No dirty-check, no
    `interactiveDismissDisabled`. Twelve typed nutrient fields vanish
    on a stray drag. Confirm discard when dirty (PortionSheet/scanner
    are cheap to lose — leave them).

22. **One log per Log-sheet visit** — `QuickLogSheet.swift:424-437`
    dismisses on success; an ad-hoc 3-item lunch is three full
    round-trips. Stay open after a log (toast already confirms) with
    Done to leave.

23. **The two online-search lists have drifted** (the CLAUDE.md rule).
    `FoodSearchSheet` lacks: the stale-query "Search online for …"
    button, clear-on-empty, any failure state (blank list after the
    toast fades), and the dead-end "Add Food" fallback. Move all four
    into the shared component.

24. **Mixed row-tap semantics in the Log sheet** — library rows open
    the EDITOR on tap while Recent rows open the portion sheet
    (`QuickLogSheet.swift:352-386`), visually identical. In a sheet
    named "Log", tap = log everywhere; demote edit to swipe. Related
    discoverability: Today's log rows do nothing on tap (edit hides
    behind swipe-right).

25. **Duplicate guard is name-only** — `FoodFormView.swift:289-294`.
    Scanning a barcode already saved under a different name mints a
    twin; match barcode first like QuickLogSheet's scanner does.

## Tier 4 — onboarding & goal polish — ALL SHIPPED 2026-07-12 (same session)

All four landed: `sharingDenied()` drives recovery hints on Today and
a Settings "Apple Health" section (instructional copy — iOS can't
deep-link the sharing pane); the onboarding goal page gained the
corner Done for the decimal keyboard, a swipe-past-safe Health request
(one guarded path for button and swipe), an inline plan preview with
the aggressive-pace warning, ScaledMetric icons, and the unambiguous
Goal-tab caption; GoalView labels the assumed 2000 kcal burn and says
why Save is disabled; the nutrient picker disables the other slot's
pick, the sodium limit stays editable while untracked, zeroed targets
sync to the watch, and the tracked/reminder footers explain themselves.

## The user's UI direction (landed with Tier 4, same session)

1. **Corner + pill**: food logging/adding moved to the Music-style
   detached tab-bar circle ("Add", the search-role slot — the only
   public API that renders there; it acts as a button via a selection
   bounce). On Today/Goal/Calendar it opens the Log sheet; on the
   Library it opens the new-food form (Add Meal stays in the toolbar
   menu). The header food menu is gone; favorites/scanner live in the
   Log sheet. Water keeps its 1-tap capsule in the Log header.
2. **Music-style search**: the Log sheet is search-first — kind pills
   pinned on top, keyboard auto-raised on open, placeholder "Meals,
   Foods, Favorites, and More" (Foods search matches). Watch for the
   search-slot morph quirk on device; fallback is a floating button.

26. **No recovery path from denied Health permission, anywhere.** The
    request is one-shot; denial leaves all-zero meters, raw "Couldn't
    log" toasts, and no Health row in Settings (notifications-denied
    got one). Write-auth IS detectable. Add a Settings "Apple Health"
    row + Today banner when sharing is denied, with go-to-Health-app
    instructions.

27. **Onboarding goal page**: no keyboard dismissal (regressed
    GoalView's Done fix), swiping past the Health page skips the
    permission request so it fires contextlessly on Today later, no
    guardrail/plan preview (GoalView would warn "that pace is
    aggressive"; onboarding commits blind), fixed 48–72 pt icons ignore
    Dynamic Type, and the Health button lacks an in-flight guard
    (double-tap = two auth flows; completion yanks `selection` back).

28. **Goal screen thin states**: average-burn fallback (2000 kcal)
    presented indistinguishably from measured data; disabled Save gives
    no reason; the empty state is still the single gray sentence
    (carried from POST-1.3 #5).

29. **Tracked-metric settings edge cases**: both slots can select the
    same nutrient (two Settings sections then edit the same target);
    untracking sodium orphans the sodium limit (still drives calendar/
    detail/reminder colors with no UI to edit it); sections never say
    where the metrics appear; a target reset to 0 on the phone never
    reaches the watch (`PhoneSyncService.swift:48-56` drops ≤0 keys —
    send "0" explicitly). Water reminders keep firing for untracked
    water (goal can't go below 16 oz); `GoalView.save()` never replans
    reminders.

## Tier 5 — history & watch polish — ALL SHIPPED 2026-07-12 (same session)

Month grid: hollow dot = tracked-but-missed, blank = untracked, honest
VoiceOver, a one-line legend, and the day card's missing status
branches ("Goal not met"/"Not tracked") plus a "View & edit on Today"
caption on the cross-tab card. Day details: the "Deficit" row is "Net"
(reading "x kcal deficit/surplus"), the all-sources-vs-Onigiri-only
split is disclosed in the empty state and a section footer, and the
month summary names past months. Watch: success flash ("+12 oz ✓" /
"✓ Meal") and a visible failure hint (meal picker stays open on
failure), water button shows the serving, an auth-denied footnote,
riceToast tint (was orange/blue — the only off-brand surface), and the
balance style repaints via @AppStorage. Widgets: accessoryCorner for
both complications, and every widget/complication renders "Open
Onigiri to set up" before Health access instead of a confident zero.

## Tier 6 — consistency & copy — SWEPT 2026-07-12 (same session)

Edit-saves toast + haptic (foods, meals, goal), favorites tick, toasts
post VoiceOver announcements, Settings transfer/backup outcomes moved
to the app-wide toast channel, Title Case across buttons ("Import
Library…", "Back Up Now", …), "Nothing logged yet.", "No saved foods
yet" unified, keyboard-Done standardized to .principal, duplicate
alert got its cancel role, EmojiPrompt shows the slot's name, the meal
builder takes quarter servings, `Color.onRicePaper` replaces raw
.black, and replan only clears onigiri.* notifications. Deliberately
left: "Removed" toasts (reads better next to Undo than "Deleted").

30. **Month grid legend + third state.** The gray dot conflates
    missed / untracked / pre-install / outside-window; VoiceOver says
    "goal not met" for a day with zero data; past missed days show NO
    status line on the day card (reads as loading failure). Add a
    hollow-dot "tracked, missed" vs no-dot "untracked" distinction, a
    one-line legend, and the two missing status branches.

31. **Calendar→Today jump is an unlabeled one-way teleport** —
    `CalendarView.swift:248-250`. The tab switch is discoverable only
    via VoiceOver hint. Minimum: caption the card "View & edit on
    Today ›".

32. **Deficit/surplus vocabulary**: Today shows "+320 balance"
    (orange), Calendar "320 deficit" (green), Details a row labeled
    "Deficit" that can read "surplus". Pick deficit/surplus everywhere
    history is shown. Also: DayNutritionView never discloses that the
    headline is all-sources HealthKit while the breakdown is
    Onigiri-only ("Nothing logged this day." under 1,800 kcal);
    summary caption says "this month" while browsing March; double
    refresh on Calendar appear; streaks break on untracked days while
    the goal card insists "an untracked day isn't a failed day" —
    align the copy or surface the break honestly.

33. **Watch feedback is haptic-only, and failure looks like success.**
    Meal-log failure still dismisses the picker; water logging changes
    nothing visible on the kcal-only home; denied Health on the watch
    = zeros forever with no hint. Success flash ("+12 oz ✓"), keep the
    sheet open on failure with a message, label the water button with
    the serving ("Log water (12 oz)" — synced value is already there),
    and a footnote when auth is undetermined/denied. Also: watch
    buttons are `.orange`/`.blue` — the only surfaces skipping the
    riceToast brand; `showsRemainingKcal` is a plain read in `body`
    (not `@AppStorage` like the icons) so a synced style flip doesn't
    repaint a foregrounded watch home.

34. **Widget/complication gaps**: no `accessoryCorner` family (the
    most numerous slots on popular faces); pre-setup surfaces show a
    confident green "0 kcal" instead of "Open Onigiri to set up"
    (check `statusForAuthorizationRequest` in the snapshot loaders).

## Tier 6 — consistency & copy sweep (one mechanical pass)

35. **Numbers**: replace `"\(Int(x.rounded()))"` interpolations with
    `Text(value, format:)` (CalendarView:208-210, 283-284, 331-333,
    411-417; WatchMetricsView:99-100 — also an unrounded `Int(target)`
    truncation). "12000" vs "12,000" on the screens a tracker user
    checks daily.

36. **Feedback parity**: editing a saved food/meal succeeds silently
    (every log toasts); favorite toggles silent; goal save toasts but
    skips the haptic; Settings import/export uses inline text where
    Foods/QuickLog toast the same operation; toasts are invisible to
    VoiceOver (post `.announcement` — the Undo affordance is currently
    sighted-only).

37. **Copy case**: settle Title Case for buttons ("Import library…",
    "Back up now", "Scan barcode", "Search database" vs "Add Food",
    "Look Up", "Scan Barcode"); "Nothing Logged"/"Nothing was logged
    this day." mismatch inside one ternary (TodayView:704); "No foods
    yet" vs "No saved foods yet"; Delete alerts → "Removed" toasts.

38. **One-offs**: keyboard-Done lands in `.principal` in FoodFormView
    but `.topBarTrailing` in GoalView; QuickLogSheet's dismiss button
    says "Cancel" (nothing is cancelled — logging already committed);
    duplicate-food alert has no cancel-role button; ⭐ emoji in Today's
    long-press menu vs `star.fill` everywhere else; MealFormView's
    empty-filter state is plain Text (third style for that state) and
    shows `No foods match “”.` when the library is empty; EmojiPrompt
    ignores its `title` parameter (all five icon slots present as
    "Custom Emoji"); meal builder is integer-only (`step: 1`) while
    PortionSheet celebrates 0.85 servings; hard-coded
    `.foregroundStyle(.black)` on ricePaper Done buttons deserves a
    semantic `onRicePaper` color; `removeAllPendingNotificationRequests`
    wipes ALL notifications, not just reminder-prefixed IDs.

## Feedback round 1 (2026-07-12, on-device) — SHIPPED same session

The user's first pass on the new UI: keep the corner pills, drop the
auto-focused search ("too jarring" — list + bottom bar, no keyboard);
placeholder shortened to "Foods, Meals, and More" (Foods tab matches).
Log sheet scopes became Foods / Meals / Favorites (Favorites replaced
"All"; mixed view only earned its keep as a favorites shelf) with a
"Recent" top-10 (PURELY most recent, no favorite boost — the user's call) and
"Everything else" per scope; history-only entries fold into the Foods
pool as rows. Water found its home: the hydration metric IS the button
(tap = serving, long-press = amounts, Undo covers slips, a11y value
carries the total) and the header capsule is gone — chosen from a
brainstorm (over log-sheet row / keep-capsule options). The Foods
toolbar "+ Add" menu consolidated into the corner pill (Food-or-Meal
chooser dialog). The food form's search entry moved from a top row to
a bottom search-bar launcher ("Search OpenFoodFacts", Log-sheet look,
barcode button sized to the bar).

## Paid developer account — decision brief (2026-07-13)

$99/year buys, in order of value to THIS app:

1. **No weekly re-deploys** — provisioning lasts a year instead of 7
   days; the recurring deploy chore (and the watch wrestling it brings)
   disappears. This alone is most of the value.
2. **TestFlight** — family devices (the other iPhones/iPads on this
   Mac) get the app over the air, auto-updating, no cables.
3. **iCloud/CloudKit** — SwiftData+CloudKit sync for the library
   (foods/meals/goal) across devices, replacing Export/Import JSON.
   Migration note: CloudKit-backed SwiftData requires optional
   relationships and no unique constraints — the current models are
   close but need an audit pass; logs stay in HealthKit regardless.
4. Push notifications and App Store distribution — not needed today.

Costs beyond the $99: none structural — same bundle IDs, HealthKit,
widgets, and watch app; per PLAN.md it's "only a signing-team switch".
**Recommendation:** buy when either (a) the weekly re-deploy chore
grates, or (b) family wants the app — TestFlight is the clean way to
give it to them. If neither, the free team keeps working.

## Widget expansion plan — W1+W2+W3 BUILT 2026-07-13, RELEASED as v1.5.0

On-watch feedback settled the button scheme: meal = rice-paper cream
with dark content, water = blue with a SOLID WHITE drop (both icons
monochrome, matching) and no serving suffix in the label — the flash
confirms the amount.

Everything below shipped except item 10 (parked by ruling). The
intents moved into OnigiriKit (`OnigiriKitIntents`, registered via
`AppIntentsPackage` in the app and widget extension) so one definition
serves widget buttons, Control Center, and Siri. New surfaces: gauge
widget gained the Lock Screen families + a corner water-log button; a
Water accessory widget; Streak (small + lock), Month (large/XL grid),
Weight Trend (Charts, medium/large), Daily Progress combo (medium);
a Control Center "Log Water" control; App Shortcuts for Siri. The
accessory renderings live in the kit (`BalanceAccessoryView` /
`WaterAccessoryView`) — watch complications and iPhone Lock Screen are
one implementation. To use: long-press Lock Screen → add widgets;
Control Center → add control; check the widget gallery for the four
new home-screen widgets.

Current inventory: iPhone home screen small (gauge) and medium (meter
with interactive water/meal buttons, configurable meal); watch
complications (balance: circular/rectangular/inline/corner; water:
circular/inline/corner). All recently hardened (midnight cut, gallery
previews, needs-setup states, choke-point reloads).

### W1 — cheap wins (reuse existing views/intents)

1. **iPhone Lock Screen widgets**: add the accessory families
   (circular/rectangular/inline) to the iOS bundle — the watch
   complication layouts port nearly verbatim. Balance ring + water
   ring on the lock screen is the single biggest glanceability win.
2. **Control Center "Log Water" control** (ControlWidget): one-press
   water from Control Center or the Action button, wrapping the
   existing LogWaterIntent.
3. **App Shortcuts**: expose Log Water / Log Meal to Siri and
   Spotlight (AppShortcutsProvider over the existing intents).
4. **StandBy audit**: systemSmall already appears in StandBy — verify
   the gauge reads well in night mode, tweak if not.

### W2 — new widgets

5. **Streak** (systemSmall + accessoryCircular): current streak count
   with the reward badge — StreakCalendar over the day totals, using
   the same per-day snapshot targets as the app.
6. **Month calendar** (systemLarge, iPad shines): the month grid with
   earned/tracked marks — phone mirrors the earned/tracked sets into
   the App Group on sync push; the widget renders statically.
7. **Weight trend** (systemMedium/Large): the Goal chart (weigh-ins +
   7-day average + target line) via Swift Charts, which works in
   widgets; reads Health directly like the others.

### W3 — later

8. **Daily progress combo** (systemMedium alt): gauge + sodium + water
   + streak in one card, as a configurable alternative to the meter.
9. **Interactive gauge**: a water quick-log button on the small
   widget (one intent button fits).
10. Slot-aware watch complications — parked BY RULING ("I like how it
    is now"); revisit only on request.

Constraints that shape all of it: the widget process is memory-capped
(no SwiftData — the App Group mirror pattern is established), and the
free team means no push (irrelevant: WidgetKit timelines are local).

## Feature-complete batch — the last five (BUILT 2026-07-13, after v1.5.0)

From the "are we feature complete?" review: five philosophy-fit items,
then the app is feature-complete on its own terms.

1. **Maintenance mode** — Goal tab grew a segmented Lose Weight/Maintain
   picker. Maintain needs no target/date: the daily budget IS the
   average burn (`CalorieBudget.maintenancePlan`), the goal card reads
   "Daily budget … X of Y kcal eaten", the gauge tracks budget left,
   and any deficit earns the day's badge (deficit target syncs as nil —
   the calendar/streak 0-target rule already handled it). Mode rides
   `GoalSettings.mode` / `SyncedGoal.mode` (nil = lose, so old payloads
   and onboarding are untouched).
2. **Today scale trend line** — goal card caption "Scale: down 0.4 lb
   this week" from the 7-day-smoothed weigh-in change (21 days of
   history for runway). The plan-math card now shows what the scale
   actually did, both modes.
3. **Recent foods on the watch** — the phone pushes its top-6
   most-recent foods (SyncedMeal-shaped) in the application context;
   the watch's Log sheet gains a "Recent foods" section, same one-tap
   path as meals. Version-skew-safe (missing key = keep).
4. **HealthKit background delivery** — `background-delivery`
   entitlement on both apps + `HKObserverQuery` on dietary energy and
   water. A log from the watch refreshes iPhone widgets (and vice
   versa for complications) without waiting out WidgetKit's timeline.
5. **Watch streak complication** — StreakLoader + StreakAccessoryView
   moved into the kit (shared judging with the iPhone streak widget,
   which was refactored onto them); the watch bundle grew
   StreakComplication (circular/inline/corner/rectangular).

## v1.6.0 — the feature-complete release (TAGGED 2026-07-13)

The batch above plus the feedback rounds on it, all user-verified
on device:

- **Watch page layout (the user's design)**: home (Log a meal / Log water,
  immediate on open) → Metrics (renamed from Tracked, the user's pick) →
  Log → Favorites → Meals → Foods. The browse pages are the ten most
  recent per scope, one tap to log, flash confirms in place; the
  "Log a meal" sheet stays the quick page (meals + six recent foods).
  All pages share the left-aligned inline title style.
- **Watch Log page**: today's food entries, tap to adjust calories
  (crown or ±25 — sodium/nutrients rescale proportionally, the
  phone's write-before-delete edit) or Remove; left-swipe removes.
- **"Metrics" complication** (accessoryRectangular): kcal headline in
  the user's style over the two tracked-metric lines with their
  emojis — the phone's Settings slots exactly.
- **Sync payload**: favorites (meals + foods interleaved by recency,
  ten) and recentFoods (ten) ride the application context; meals now
  sync recency-ordered.
- **Copy round (the user's picks)**: water reminder drops "— time for
  water"; meal nudge "…keep today's balance up to date"; streak title
  "Keep your streak going"; Maintain footer "To hold steady, eat
  within your average daily burn."; Remove Goal footer "If no goal is
  set, any deficit earns a daily badge."

## Deliberately not doing

- **Metric units** (kg/ml): personal US app; revisit only if it grows
  an audience. Storage stays lb/oz either way.
- **Circular vs rectangular complication semantics** (budget-eaten ring
  vs banked-deficit onigiri): deliberate per the code comment; the
  visuals are distinct. Document, don't converge.
- **Watch one-tap logging without confirmation**: consistent with the
  phone's meal fast path; mis-taps are fixable on the phone.
