# 1.9 — Quality pass (Axiom review findings)

Six parallel reviews against the Axiom skill rubrics (2026-07-13):
HIG/Liquid Glass/SF Symbols/toolbars, SwiftUI + launch performance,
watchOS + WatchConnectivity + complications, HealthKit, accessibility,
widgets/App Intents. Spot-verified in source where marked ✓.

**Status: batches A–C APPLIED 2026-07-13** (build + 129 kit tests +
flow test green). Deviations from the writeup:

- A3: affordances are suppressed only for entries from OUTSIDE the
  app family (phone/watch twin bundle ids treated as one). Whether
  the phone can delete the watch twin's entries is unverified — so
  twin rows keep their affordances and the error message is now
  honest either way ("Another app logged this entry — remove it in
  the Health app.").
- A5 also landed the enableBackgroundDelivery error logging (old #7).
- A1/A5 watch-side changes compile but need a WATCH DEPLOY to verify
  live (background context delivery, complication refresh) — check at
  the next weekly deploy window.
- B7 amended BY RULING (2026-07-13, on-device): NO visible status
  words on tracked metrics — "the color speaks". The "near limit"/
  "over limit" text now lives only in accessibilityValue (VoiceOver),
  on Today, the Calendar day card, and the watch metrics card.
- C16 splits the mirror fingerprint in two (goal+settings vs library
  lists): settings changes still reload every widget (the trend
  widget reads the goal target), library-only changes reload the
  log-affected kinds. The widget-intent echo suppression (cross-
  process stamp) was NOT done — deferred with batch D.

Batch D remains open for discussion.

The reviews also confirmed a lot of existing discipline: no unguarded
iOS 26 API anywhere (the 1.8 floor holds), textbook WatchConnectivity
payload semantics, correct statistics-query dedupe of phone+watch
burn, the debounced kind-scoped widget reloader, correlation deletion
that can't desync day totals, and Dynamic Type handling better than
most shipping apps. The items below are the gaps.

## A. Correctness (do first)

1. **Watch never receives background library/goal pushes** ✓ — no
   `.backgroundTask(.watchConnectivity)` handler and WCSession
   activation lives in WatchHomeView's `.task`, so a phone-side goal
   or settings change waits until the watch app is manually opened;
   complications render the old plan indefinitely.
   *Fix:* activate the session in `OnigiriWatchApp` init (idempotent)
   and add `.backgroundTask(.watchConnectivity)` to the scene. Both
   APIs are within the watchOS 10 floor. (watchOS #1–2)
2. **Watch edit can double-log** ✓ — `WatchModel.editEntry` writes the
   replacement correlation, then deletes the original; if the delete
   throws, the new entry stays (day counts the meal twice). The phone
   (`Feedback.swift`) already rolls back in this exact case. Likely
   trigger: editing a phone-logged entry — HealthKit only lets each
   app delete its OWN objects, so cross-device edits throw. (HK #1)
3. **Delete/edit offered on entries the app can't delete** — Today and
   the watch list read food correlations from ALL sources but attach
   swipe-delete/edit to every row; foreign rows (other app/device)
   fail with a misleading "check Health access". *Fix:* carry the
   source bundle id into `FoodLogEntry`, disable or relabel foreign
   rows, and special-case the authorization-denied delete error.
   (HK #2)
4. **Maintenance-mode midnight widget shows an empty gauge** — the
   pre-rendered `newDay` entry hardcodes `gaugeProgress: 0`; in
   maintenance mode midnight progress is 1.0 (full budget left).
   (widgets #2)
5. **Observer wake can be lost** — the HKObserverQuery handler calls
   `completion()` before the scheduled Task runs, so a background
   wake can suspend the process with the widget reload undone; and
   the observers are registered in view `.task`, which a background
   relaunch may never run. *Fix:* complete after the work; register
   in the app structs' init. (HK #3–4)

## B. Cheap high-value polish

6. **Contrast: white-on-riceToast prominent buttons** ✓ — ~1.9:1 in
   dark mode. Five sites (Onboarding ×3, both Import Library
   buttons); the app's own fix (`.tint(.ricePaper)` +
   `.foregroundStyle(Color.onRicePaper)`, ≈14:1) is already used by
   the keyboard-Done buttons. (UI #1)
7. **Sodium/limit status is color-only** — near/over-limit conveyed
   purely by the green→toast→red ramp, in colors that fail AA at
   small sizes, across Today, Calendar, watch metrics, and the
   progress widget. *Fix:* append "· near limit"/"· over" (or a
   warning symbol) in the warning bands + `accessibilityValue`;
   darken the light-mode warning tone one step. Brand accent itself
   untouched. (UI #2, a11y #4–5)
8. **VoiceOver on log rows** — Today's food/water rows read as 3–4
   unrelated text stops with an invisible tap-to-edit; Foods rows
   (new 1.8.1 builders) miss the `.isButton`/combine treatment their
   Log-sheet twin already has. *Fix:* `.accessibilityElement(children:
   .combine)` + `.isButton` + hint on both. (a11y #2, #6)
9. **Undo is unreachable under VoiceOver** — the toast announces the
   message but not that Undo exists, and auto-dismisses in 5 s.
   *Fix:* append ", Undo available" to the announcement and extend
   the linger when VoiceOver is running. Deletes have no confirm, so
   Undo is the only recovery path. (a11y #1)
10. **GoalView segmented picker ignores Dynamic Type** — the app's own
    segmented→menu-at-accessibility-sizes rule (ScopeBar, PortionSheet)
    was missed here. (a11y #3)
11. **Log sheet "Done" sits in the cancel slot** — placement (not the
    name, which is a settled ruling) belongs in `.confirmationAction`;
    move the scanner icon to leading. (UI #4)
12. **`LogMealIntent` lacks a `parameterSummary`** — hidden from
    quick-run surfaces; one line (`Summary("Log \(\.$meal)")`), plus
    optionally an AppShortcut phrase. (widgets #4)
13. **Manual samples miss `HKMetadataKeyWasUserEntered`** — one line
    in `logWater`/`logFood`; feeds Journal suggestions and source
    distinction. (HK #9)

## C. Performance (user-visible first)

14. **QuickLogSheet rebuilds the whole library item list per search
    keystroke** — `allItems` walks every meal's relationships and
    copies nutrient dictionaries on each body evaluation; the
    historyRows half of this was already cached for exactly this
    reason. *Fix:* cache library items the same way; body only
    filters. The app's most-typed surface. (perf #1)
15. **GoalView: four serial HealthKit reads on every tab visit** —
    `async let` them (TodayModel already does) + a staleness stamp so
    tab bounces don't replay 92-day scans; also lift the smoothing/
    least-squares/domain math out of per-keystroke computed props.
    (perf #2–3)
16. **Every log escalates to `reloadAllTimelines`** ✓ — the recency
    bump fingerprints the mirror as changed, and `pushNow` reloads
    ALL widget kinds including the trend chart that's deliberately
    excluded from log-driven reloads. One-line scope fix. Related:
    widget-intent taps double-reload via the observer echo
    (cross-process debounce gap) — stamp-and-skip. (perf #4,
    widgets #1)
17. **`HealthKitService()` constructed per operation** — a dozen sites
    in Feedback.swift plus loaders; defeats the deletion caches
    (forcing UUID re-fetch on undo) and re-creates HKHealthStore.
    *Fix:* one shared instance. (perf #6, HK #11)

## D. Worth discussing (product calls / lower urgency)

- **Watch tab count**: six horizontally-paged tabs vs the 2–5
  guideline; Favorites/Meals/Foods pages duplicate the meal-picker
  sheet one tap from Home. Dropping them is guideline-clean but it's
  a product feel decision. (watchOS #3)
- **Always-On privacy**: calorie balance/sodium/log legible with
  wrist down; `.privacySensitive()` on the values is one modifier
  each if wanted. (watchOS #4)
- **Locked-phone widget zeros**: background reload while locked reads
  an inaccessible Health store and renders "0 kcal" until unlock —
  distinguish `errorDatabaseInaccessible`, keep last-good snapshot.
  (HK #5)
- **Midnight edges**: `.strictStartDate` drops the post-midnight
  slice of spanning basal-burn samples (small systematic undercount);
  Streak/Month widgets lack a pre-rendered midnight entry (stale
  "today" highlight); tomorrow's streak warning understates by one.
  (HK #8, widgets #3, #7)
- **Charts/complication a11y**: weight charts need a one-line
  accessible summary; the month accessory grid should collapse to a
  single labeled element; watch headline/kcal editor use fixed font
  sizes and the ±25 cluster isn't an adjustable element; watch flash
  confirmations aren't announced. (a11y #7–11)
- **iOS 26 garnish** (all guarded): `.scrollEdgeEffectStyle(.hard)`
  under the pinned scope bars; real glass on the log-row swipe pills;
  `.contentTransition(.symbolEffect(.replace))` on the filter icon;
  optional `.searchToolbarBehavior(.minimize)` on Foods. Plus
  `TimelineEntryRelevance` (watchOS 7+) so complications rank in the
  Smart Stack during meal windows. (UI opportunities, watchOS #5)
- **Misc**: touch targets on Calendar chevrons + Today "Details"
  link; Calendar legend caption2→caption; observer doesn't watch
  bodyMass (weigh-ins wait for the hourly poll); ReminderScheduler
  replans unserialized; conditional keyboard-Done ToolbarItems
  rebuild the bar while a field is focused.

## Suggested batching

- **Batch 1 (correctness):** A1–A5 — small diffs, test on sim + one
  watch deploy.
- **Batch 2 (a11y/contrast/polish):** B6–B13.
- **Batch 3 (performance):** C14–C17.
- **Batch 4:** whatever survives discussion from D.
