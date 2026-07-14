# 2.1 — Glance: the Today-mirror widget + logging polish

The bar, as ever: faster or better logging, alongside Apple Health,
no bloat. 2.1's headline is the user's widget: Today's top card on
the home screen, with logging one tap away. Around it, three small
things the 2.0 testing surfaced. iOS 18 floor holds; nothing here
needs a 26-era API beyond what already ships.

## Feature 1 — Today-mirror widget

A home-screen widget that looks exactly like the top of Today (the
user supplied a reference screenshot): the kcal-left ring with
Burned/Eaten flanking, the sodium/water metric pills, the rice-paper
canvas. Families: **systemLarge** (the full card) and **systemMedium**
(compressed: ring + pills; the flanks only where they fit).

Interactions (widgets can't scroll — everything is a Button):

- **‹ ›Day paging** via AppIntents: the intent writes the browsed day
  to shared defaults and reloads the timeline. **Snap-back at day
  roll** (the user): a browsed day that is no longer "today ± its
  offset" renders as the new today — nobody wakes up to Tuesday's
  numbers. Paging is bounded by the data the kit already holds
  (the 92-day totals window).
- **+ button** deep-links into the app's Log sheet for the SHOWN day
  (widgetURL routing, like the existing quick actions — backfill
  included).
- **Water button** (the app's water icon) logs the default serving
  IN PLACE — reuses the Control Center "Log Water" AppIntent; no app
  launch.

Existing pieces: DailyProgressWidget (gauge family precedent),
BalanceAccessoryView (shared ring), the Log Water control intent,
PlanCache/DaySnapshot (locked-phone last-good snapshot INCLUDED —
the widget must degrade exactly like the others).

## Feature 2 — Watch home "Log"

Rename "Log a meal" → "Log"; its sheet becomes the phone's default
Log view in miniature: **Favorites first (meals + foods mixed), then
Recent** — one unified list, one tap to log. NO Meal-or-Food chooser
(ruled out 2026-07-14: an extra tap per log on the tappiest device);
the Meals/Foods pages stay the scope switch, one swipe away.

## Feature 3 — "Details ›" everywhere

One grammar for the three tap-for-more affordances: the Calendar day
card's "View & edit on Today" and Today's headline "Details" both
become the month card's "Details ›" (caption, secondary, trailing
chevron.right). Deliberately reverses the 2026-07-13 chevron removal
on Today. The day card's edit/cross-tab cue moves into the
accessibility hint.

## Feature 4 — housekeeping that rides along

- Shared barcode-routing helper: one implementation of the
  known-barcode → portion sheet / unknown → prefilled form route,
  replacing the FoodsView and QuickLogSheet copies (1.8.1 follow-up).
- QA-walkthrough tour taps updated for the Favorites-first defaults
  (its meal-form-edit shot silently skips today).
- Pantry-tour findings land here as they surface: LabelParser fixture
  additions, Foundation Models prompt tweaks — the 2.0 QA is the
  intake funnel.

## Architecture

- Widget: `TodayCardWidget` in OnigiriWidgets; browsed-day state in
  the App Group defaults keyed per widget kind; day totals via the
  kit's existing HealthKit day queries under PlanCache; snapshot
  fallback via DaySnapshot.
- Watch: rename + list reshaping inside MealPickerView; payload
  unchanged (favorites/recents already sync).
- Details›: three call sites, one small shared caption view if it
  earns it.

## Milestones

- **M1** — Widget data + static render, systemLarge: ring, flanks,
  pills, canvas; snapshot fallback verified (locked-phone parity).
- **M2** — Interactivity: ‹ › paging with day-roll snap-back, water
  intent, + deep link; systemMedium variant; gallery/QA shots.
- **M3** — Watch "Log" rename + unified sheet; on-wrist verify.
- **M4** — Details› sweep + barcode-routing helper + QA-tour test
  fixes.
- **M5** — Docs, screenshots if the README surfaces changed, release
  as 2.1.

## Non-goals

- Widget scrolling or configuration UI (paging covers day browsing;
  AppIntentConfiguration can come later if slot choice is wanted).
- The paid-account question (CloudKit sync, TestFlight) — explicitly
  deferred again 2026-07-14; Export/Import remains the transfer
  story.
- Any new Apple Intelligence surface — 2.0's set holds until the
  on-device QA says otherwise.
