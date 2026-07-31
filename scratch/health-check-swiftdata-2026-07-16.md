# SwiftData Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 0, MEDIUM: 3, LOW: 2
- Health: FRAGILE (no CRITICAL/HIGH; migration-planning + explicit-save completeness gaps)

## Positive verification (explicitly re-checked)
Every relationship has a genuine, working inverse — re-verified line-by-line:
- `Food.mealItems: [MealItem]` (LibraryModels.swift:39) ↔ `MealItem.food: Food?` with `@Relationship(inverse: \Food.mealItems)` (LibraryModels.swift:104). Default `.nullify` delete rule — deleting a Food nullifies referencing MealItem.food, doesn't dangle.
- `Meal.items: [MealItem]` (LibraryModels.swift:127) `@Relationship(deleteRule: .cascade, inverse: \MealItem.meal)` ↔ `MealItem.meal: Meal?` (LibraryModels.swift:110). Cascade correctly removes orphaned MealItems.
- No manual double-write of both sides of a relationship found. No array relationship missing a default.
- LibraryTransfer.importData inserts new Foods before building MealItem(food:) for them — correct, matches the "both sides inserted before linking" landmine fix.

This is the correct, hardened shape of the CLAUDE.md-documented fix; no regression found.

## Issues by Severity

### MEDIUM — No VersionedSchema/SchemaMigrationPlan for a hand-maintained schema
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/LibraryModels.swift:515-522`
**Issue**: Every schema change to date (Food.micros, Food.lastUsedAt, GoalSettings.mode) has relied on additive-optional properties (lightweight migration), deliberate and documented. No fallback exists for a future rename, type change, required-field addition, or model split/merge.
**Impact**: A future non-additive schema change could crash on launch or silently drop data with no rollback path.
**Fix**: Introduce a VersionedSchema/SchemaMigrationPlan pair before the next non-additive schema change.

### MEDIUM — SharedStore.modelContainer()'s explicit Schema([...]) omits MealItem.self
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/LibraryModels.swift:516`
**Issue**: `Schema([Food.self, Meal.self, GoalSettings.self])` doesn't list MealItem.self, though it's a real @Model reachable only via relationship. SwiftData auto-discovers it transitively (tests corroborate this works), but relying on undocumented transitive discovery is fragile.
**Fix**: Add `MealItem.self` explicitly: `Schema([Food.self, MealItem.self, Meal.self, GoalSettings.self])`.

### MEDIUM — Several mutation paths rely on implicit autosave instead of explicit save()
**Files**: `Onigiri/Views/FoodFormView.swift:697-723` (persist(), no explicit save), `Onigiri/Views/MealFormView.swift:324-348` (save(), no explicit save), `Onigiri/Views/FoodsView.swift:350-373` (delete alerts, no explicit save)
**Issue**: Inconsistent — GoalUpsert.save(), LibraryTransfer.importData, DebugSeeder.seedLibraryIfEmpty all call `try? context.save()` explicitly; the Food/Meal create-edit-delete paths don't. isAutosaveEnabled is never explicitly set (default true).
**Impact**: Low but nonzero data-loss window: a crash/force-quit in the narrow window between a Food/Meal edit and SwiftData's next autosave checkpoint could lose that specific edit, while goal/import writes are already safe.
**Fix**: Add `try? context.save()` at the end of FoodFormView.persist(), MealFormView.save(), and after the two delete-alert actions in FoodsView.swift.

### LOW — Minor N+1-shaped relationship traversal in repairDanglingFoodReferences
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/LibraryMaintenance.swift:80-96`
**Issue**: `for meal in meals { meal.items.filter {...} }` accesses the items relationship once per Meal. Negligible at personal-library scale.

### LOW — PhoneSyncService.pushNow computes meal totals for every synced meal
**File**: `Onigiri/Models/PhoneSyncService.swift:90-113`
**Issue**: Meal.totalKcal/totalNutrients walk items and dereference item.food per item on every debounced sync push. Negligible given maxSyncedMeals=30 cap.

## Recommendations
1. No CRITICAL/HIGH issues — inverse-relationship fix intact and re-verified.
2. Short-term: add explicit save() calls to FoodFormView/MealFormView/FoodsView delete paths.
3. Long-term: add MealItem.self to the Schema array; introduce VersionedSchema/SchemaMigrationPlan before the next non-additive change.
