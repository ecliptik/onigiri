# PLAN — Meal marks + logged-meal composition (2026-07-23)

Three user asks, one arc:
1. A meal emoji mark beside meal names everywhere meals appear (Foods,
   Log sheet, Today's log, …), the ✨ grammar.
2. Both marks LARGER — ✨ renders at `.caption2` and reads tiny beside
   the row's body-size name (the user, from the food log).
3. Viewing a logged meal shows the foods that make it up with their
   kcal, so the meal total is explained.

## Current state (verified in code)

- ✨ mark: `Text(verbatim: "✨").font(.caption2)` in `LibraryRow.nameLine`
  (FoodsView) and the Today log row (TodayView ~1004), a11y "AI
  estimated". Driven by `aiGenerated` on models/entries.
- Meals in mixed lists carry a "Meal" TEXT CAPSULE (`LibraryRow.isMeal`),
  used on the Favorites scope. The Log sheet's mixed list and Today's
  log have NO meal indicator at all.
- A logged meal is ONE HealthKit correlation with summed totals. The
  component foods are NOT recorded anywhere — `FoodLogEntry` has no meal
  awareness, so the log literally cannot tell a meal from a food today.
- ONE write choke point: `HealthKitService.logFood(...)` builds the
  correlation + metadata (`OnigiriMealCategory` / `OnigiriAIGenerated` /
  `OnigiriQuantity`). The WATCH also logs through it (`WatchModel.log`
  → `logFood`), so a metadata addition covers every platform's writes.
- The log's "view a meal" surface is the shared `PortionSheet` (Today
  `.editEntry` case opens it on the entry's per-portion basis).

## Part A — the meal mark

- Emoji: **🍱** (proposed; 🍽️ and 🥡 are the runners-up — user veto
  welcome. NOT 🍙: that's the logo and the default reward badge).
- Replaces the "Meal" capsule in `LibraryRow` — one mark grammar beside
  the name: `star · name · ✨ · 🍱`. a11y label "Meal" (the emoji is
  decoration to VoiceOver otherwise).
- Where it shows: every list that MIXES meals with foods — Favorites,
  the Log sheet's item list, Today's log rows (via Part C's entry
  awareness), and the watch quick-log list if cheap. NOT the Foods
  → Meals scope (the whole list is meals; a per-row mark is noise).
- Pre-feature logged meals have no metadata → no mark in the log.
  Accepted, mirrors how pre-quantity entries open at 1.

## Part B — mark size

- ✨ and 🍱 move `.caption2` → **`.callout`** in both row types (still a
  step under the body-size name, clearly legible; scales with Dynamic
  Type). Device-verify the balance — this is a taste knob; `.footnote`
  is the fallback if `.callout` shouts.
- The favorite star stays `.caption2` (a tinted glyph, not part of the
  complaint) unless it reads unbalanced next to the bigger marks
  on-device.

## Part C — logged-meal composition

Data (the `OnigiriQuantity` pattern, immutable history over live
lookup — resolving the meal by name at view time would lie after the
meal is edited or deleted):

- New kit type `LoggedMealItem: Codable, Sendable, Equatable`
  { `name: String`, `kcal: Double` } — kcal on the ONE-MEAL-PORTION
  basis, exactly like the quantity contract (totals stored multiplied;
  the sheet divides back).
- New correlation metadata key `mealItemsMetadataKey =
  "OnigiriMealItems"`: JSON-encoded `[LoggedMealItem]` as a String
  (metadata is plist-typed; ~50 B/item, meals are small — no cap
  needed, but encode-failure degrades to absent, never blocks a log).
- `logFood(...)` gains `mealItems: [LoggedMealItem]? = nil`.
- `FoodLogEntry` gains `mealItems: [LoggedMealItem]` (empty = food or
  pre-feature log); parsed in the read-back beside quantity.

Write paths that must carry it (the quantity lesson, now a CLAUDE.md
rule for BOTH keys — any new log/re-log path carries quantity AND
mealItems or history silently degrades):

1. FoodsView meal one-tap log + meal portion-sheet log (items from
   `meal.items` at log time).
2. QuickLogSheet meal item log (same source).
3. QuickLogSheet HISTORY re-log rows (from `entry.mealItems`).
4. Today undo re-log (`entry.mealItems`).
5. `LogActions.editFoodEntry` re-save — PRESERVE the stored items
   verbatim (an edit changes totals, not composition).
6. Watch: `SyncedMeal` gains optional `items` (absent-tolerant both
   directions — the WatchSync version-skew rule), passed by
   `WatchModel.log`. Old-watch pairing just logs without breakdown.

UI:

- `PortionSheet` gains an optional "Contains" section (shown when the
  target carries components): one row per item — name, trailing
  `item.kcal × quantity` kcal — LIVE against the quantity stepper, so
  the section itself demonstrates how the total builds. Footer when
  `|Σ − total|` exceeds rounding: "Values were edited after logging."
- Today `.editEntry` passes `entry.mealItems`; the Log sheet's LIBRARY
  meal portion sheet passes `meal.items` (same section for free — the
  ask was the log, this rides along).
- Today log rows mark 🍱 when `!entry.mealItems.isEmpty`.

Tests (kit): LoggedMealItem JSON round-trip through the metadata
string; FoodLogEntry read-back parse (absent → empty); per-portion ×
quantity math at the sheet boundary; WatchSync payload round-trip with
and without items.

## Not touched / no-risk notes

- NO SwiftData schema change (Meal/MealItem unchanged — items snapshot
  into the log at write time). No migration, no backup format change
  (backups are library-only).
- Sodium/nutrient breakdown per component: deliberately NOT stored —
  kcal answers "how does the total build"; full per-component nutrient
  history doubles the payload for a question nobody asked.
- Evals, label parsing, AI paths: untouched.

## Sequencing

1. Commit 1 (Parts A+B): pure UI — LibraryRow capsule→🍱, size bump,
   Log sheet + Favorites coverage. Sim-verify, device-glance.
2. Commit 2 (Part C): kit type + metadata + logFood + read-back +
   write-path sweep + PortionSheet section + Today mark + kit tests.
3. CLAUDE.md conventions paragraph gains the both-keys re-log rule;
   watch payload note in WatchSync docs.
4. Device verify: log a meal, view it, edit quantity, undo/re-log,
   watch-log a meal (breakdown present), pre-existing meal log (no
   mark, no section, no crash).
