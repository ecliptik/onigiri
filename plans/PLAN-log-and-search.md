# PLAN — Log without saving, and search that crosses the scopes (2026-08-07)

> **SHIPPED** as v2.17.0 (2026-08-07). Deltas from the plan as written:
>
> 1. `LibrarySearch.groups` takes `sortByRecency: Bool`, not
>    `sort: LibrarySort` — `LibrarySort` lives in the view layer
>    (`Style.swift`) and moving a UI enum into the kit bought nothing.
> 2. `FoodsView.favoriteEntries` did NOT collapse away: the Favorites
>    SCOPE wants one flat starred list, which is not what a grouped
>    query returns. It survives as a two-line call THROUGH
>    `LibrarySearch.groups` (take the `.favorites` group), so the
>    precedence and ranking still have one definition.
> 3. Matching moved to `localizedStandardContains`, which adds
>    DIACRITIC insensitivity — "creme brulee" found nothing while
>    "Crème Brûlée" sat in the library. Caught by the planned test.
>    It can only add matches, never remove one.
> 4. Both UI tests exist and pass. `testLogWithoutSaving` has to turn
>    online lookups OFF through Settings first (the seeder switches
>    them ON, and the online section's own "Add Food" only appears
>    after a search RETURNS — retry backoff on a sim with no route to
>    OpenFoodFacts), and it names its one-off uniquely per run,
>    because the entry it logs lives in HealthKit for a week and would
>    otherwise match its own previous run.

Two independent changes to the logging surfaces, decided with the user
2026-08-07. They can ship in either order or together; part 2 is the
larger one and carries the only new kit code.

---

## Part 1 — "Log" and "Log & Save" on the logging route

### The complaint

Scanning a barcode, label, or food from **Today → Log** ends at the food
form, whose only two confirm buttons are **Save** and **Save & Log**.
Both write a `Food` row. There is no way to log a one-off — a restaurant
plate, a friend's cooking, something bought once — without permanently
enlarging the library.

### The rule

**The form's confirm buttons follow the route that opened it.** Same
form, same fields; only the pair of actions differs.

| Opened from | Left button | Right button (primary) |
| --- | --- | --- |
| Log sheet (Today → Log, its scan door, its search, its estimate row) | **Log** — portion sheet, then log. Nothing is saved. | **Log & Save** — persist, then portion sheet |
| Foods tab (+ → Add Food, its search, its estimate row) | **Save** — library only | **Save & Log** — persist, then portion sheet |

The Foods-tab pair is unchanged from today. Editing an existing food
(`food != nil`) keeps its single **Save**, unchanged.

This is the same reasoning `QuickLogSheet`'s `.task` already records for
its opening scope: the Log sheet and the Foods tab answer different
questions, and shouldn't be wired together. You reached the form to log,
so both buttons log; whether the library grows is the choice.

### Changes

**`Onigiri/Views/FoodFormView.swift`**

1. New parameter beside `logDate` / `onLogged`:

   ```swift
   /// Which route opened the form — it decides the confirm pair, and
   /// nothing else. `.logging` is the Log sheet; `.library` is Foods.
   enum Purpose { case library, logging }
   var purpose: Purpose = .library
   ```

   Defaulted, so every existing call site keeps today's behavior.

2. Toolbar (`FoodFormView.swift:344`, the `food == nil` branch) picks the
   pair on `purpose`. Positions and keyboard shortcuts hold — ⌘S on the
   left button, ⇧⌘S on the right, `.fontWeight(.semibold)` on the right.

3. New `logOnly()`, the whole of it:

   ```swift
   /// Logging-route "Log": no library row at all. The entry lands in
   /// HealthKit; the Log sheet's Recently Logged rows re-log it.
   private func logOnly() { presentPortionSheet() }
   ```

   `saveAndLog()` is unchanged (persist first, so the food survives every
   later choice, then the portion sheet).

4. **Portion-sheet cancel diverges, and this is the load-bearing part.**
   `sheetDidDismiss()` (`:720`) currently toasts "Saved … — not logged"
   and dismisses, which is right *because the food is already safe in the
   library*. On the log-only path nothing has been persisted, so
   dismissing would silently destroy every typed field. Track which
   action opened the portion sheet (a `savedBeforePortion` flag set in
   `saveAndLog`, cleared in `logOnly`) and:

   - saved path → today's toast, then `dismiss()` — unchanged
   - log-only path → **no toast, no dismiss**: stay on the form with the
     values intact. Cancelling a portion is "not that portion", not
     "throw my work away."

5. No `persist()` on the log-only path means no `PhoneSyncService.push`
   — correct, the library didn't change.

### Consequences, stated plainly

- **A log-only food never reaches the watch's Recent foods.** That list
  rides the library push (`QuickLogSheet.log()`'s comment at `:778`).
  The HealthKit *sample* still syncs, so every total, streak, and badge
  agrees across devices — only the one-tap re-log shortcut is
  phone-side.
- **Re-logging one comes from history, which is a 7-day / top-10
  window** (`HealthKitService.recentFoodEntries`, `:1088`). A one-off
  logged nine days ago is no longer one tap away. That is the deal the
  feature makes, and it is the right one — but it is a deal.
- **After adopting a duplicate** ("Edit Existing" sets `createdFood`),
  the buttons still read Log / Log & Save. **Log** then logs the values
  on screen without writing any edit back to the matched food. Consistent
  — Log never touches the library — and worth a comment at the branch.

### Verification

- Build; sim pass through Today → Log → scan door → form.
- New opt-in UI test, `LOG_WITHOUT_SAVING=1`, seeded sim: Log sheet →
  dead-end search → Add Food → assert the buttons read **Log** and
  **Log & Save** → tap Log → portion sheet → Log → the entry is on Today
  **and** the name is absent from the Foods tab. That last assertion is
  the entire point of the feature.
- `SEARCH_PROBE`'s `app.buttons["Save"]` tap (`OnigiriUITests:1188`)
  comes through the Foods-tab Add pill and is unaffected.
- Check `docs/media/add-food*.mp4` before release: if the clip records
  the *Foods* add path its labels are unchanged; if it records the Log
  sheet's, it needs a re-shoot in **both** appearances.

---

## Part 2 — Search crosses the scopes and groups the results

### The complaint

Searching "nectarine" with the **Meals** scope selected returns nothing,
because the scope filter runs *before* the query. The nectarine is right
there in the library.

### The rule

**A query searches the whole library. The scope bar is a browsing
control, not a search filter.** With search text present:

- the scope bar is **hidden** (it would highlight a segment that
  contradicts the list; the Log sheet already hides its entry doors and
  Water row on search — same habit)
- results render as **Favorites → Foods → Meals → Recently Logged**,
  empty groups dropped
- **one home per row**: a starred food appears under Favorites only, not
  again under Foods. List length equals match count.
- **Recently Logged** (Log sheet only) is last week's logged entries with
  no library twin — the rows with no ★ and no Edit. Naming them explains
  why, and Part 1 makes them the primary re-log path.
- the AI estimate row stays above everything, the Online section stays
  below — both unchanged.

Clearing the field restores the scope bar on the scope you left it.

### The shared piece — new kit code

Both surfaces implement this today and they will drift if each grows its
own copy (the `OnlineResultsSection` lesson). One pure, tested type:

**`Packages/OnigiriKit/Sources/OnigiriKit/LibrarySearch.swift`**

```swift
/// The buckets a cross-scope search sorts into, in display order.
public enum LibrarySearchGroup: String, CaseIterable, Sendable {
    case favorites = "Favorites"
    case foods = "Foods"
    case meals = "Meals"
    case recentlyLogged = "Recently Logged"
}

/// What a row exposes to be searched and grouped.
public protocol LibrarySearchable {
    var searchName: String { get }
    var searchCategory: String? { get }
    var isStarred: Bool { get }
    var isMealRow: Bool { get }
    var isHistoryRow: Bool { get }
    var searchRecency: Date { get }
}

public enum LibrarySearch {
    /// Name OR category text — so "snack" still pulls up every snack.
    /// The rule both surfaces already carry, now in one place.
    public static func matches(_ item: some LibrarySearchable, query: String) -> Bool

    /// Query → groups, empties dropped, ranked by `sort` (recency then
    /// name, or name alone). A starred row lands ONLY in .favorites.
    public static func groups<T: LibrarySearchable>(
        _ items: [T], query: String, sort: LibrarySort
    ) -> [(group: LibrarySearchGroup, items: [T])]
}
```

Bucket precedence, one home per row: starred → `.favorites`, else
history → `.recentlyLogged`, else meal → `.meals`, else `.foods`.
(History rows are constructed `isFavorite: false`, so starred-and-history
cannot occur.)

Conformances: `Food` and `Meal` in `LibraryModels.swift` (both already
have `recencyDate`); `QuickLogSheet.Item` app-side.

**Tests — `Packages/OnigiriKit/Tests/OnigiriKitTests/LibrarySearchTests.swift`**,
against a plain fixture struct:

- **the nectarine case**: a matching food is returned even when the
  caller's browsing scope is Meals (i.e. grouping never consults a scope)
- a starred item appears exactly once, under Favorites
- category-text match still works ("snack")
- empty groups are dropped; group order is fixed
- `.recent` vs `.name` ordering inside a group
- history rows land in Recently Logged
- case- and diacritic-insensitive matching

### Wiring — `Onigiri/Views/QuickLogSheet.swift`

- `pool(_:)` (`:184`) splits: **no search** keeps today's `kind` filter
  and the Recent / Everything-else split (`:315–341`) untouched;
  **search** calls `LibrarySearch.groups` and ignores `kind`.
- Render `ForEach(groups)` → `Section(group.rawValue)`.
- The scope bar is a `safeAreaInset` (`:365`). **Do not wrap `.scopeBar`
  in an `if`** — that changes the modifier chain's identity and
  re-creates the List underneath it (state loss, plus the searchable
  section onDisappear/onAppear churn CLAUDE.md records). Instead give
  `Style.swift:133`'s helper an `isHidden: Bool = false` whose hidden
  branch renders nothing at all — no padding, no `.bar` background — so
  the inset collapses to zero height with the chain intact.
- `historyItems()`'s twin-exclusion (`:157`) stays exactly as is: entries
  matching a library name already appear as library rows.
- `emptyState(pool:items:)` takes the flattened count.
- Final order: AI estimate → Favorites → Foods → Meals → Recently Logged
  → Online.

### Wiring — `Onigiri/Views/FoodsView.swift`

- `filteredFoods` / `filteredMeals` (`:134–152`) are already scope-free —
  the scope switch lives in `body` (`:211`). With search text present,
  skip that switch and render the groups; skip the scope-bar list row
  (`:179`) too.
- Generalize the existing `FavoriteEntry` enum (`:53`) into
  `LibraryEntry { case meal(Meal), food(Food) }` conforming to
  `LibrarySearchable`, and use it for both the Favorites scope and the
  search groups. `favoriteEntries(meals:foods:)` (`:157`) collapses into
  `LibrarySearch.groups` — its hand-rolled ranking is the same rule.
- The category filter keeps applying during search (it rides `matches`),
  and its toolbar chip stays visible.
- `emptyState(visibleCount:)` takes the total across groups.
- No Recently Logged group here — the Foods tab shows the library, and
  HealthKit history isn't part of it.

### Fallout

- The QA tour's `logsheet-no-matches` shot (`OnigiriUITests:553`) now
  renders without the scope bar. Expected; it is a QA attachment, not a
  site asset.
- Every scope-bar tap in the flow and QA tests (`:188`, `:519–534`,
  `:566–571`, `:604`) happens with an empty search field — unaffected.
  The `:604` loop uses the scope bar's *existence* as its
  "sheet dismissed" probe, which stays valid for the same reason.
- New opt-in UI test, `CROSS_SCOPE_SEARCH=1`, seeded sim: open the Log
  sheet, switch to **Meals**, search a seeded **food** name, assert the
  row appears under a "Foods" header and the scope bar is gone.

---

## Order of work

1. Kit: `LibrarySearch` + its tests. `swift test` green before any view
   is touched.
2. Wire `QuickLogSheet`, then `FoodsView`; delete `favoriteEntries` and
   the `kind` branch of `pool`.
3. `FoodFormView.Purpose` + the Log / Log & Save pair + the divergent
   portion-cancel.
4. Build; both new opt-in UI tests; sim pass on iPhone and iPad.
5. `scripts/deploy-phone.sh` (phone + watch); user pass on device.
6. Check the add-food clip; version bump and release.
