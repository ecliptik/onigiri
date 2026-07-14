# 1.8.1 — Foods screen restructure

Make the Foods tab structurally match the Log sheet: scope menu on
top, bottom search, a labeled scan entry — then judge whether two
near-identical screens should become one (written up separately once
this lands).

## Changes

1. **Scope menu (Foods / Meals / Favorites)** pinned above the list,
   replacing the combined Meals+Foods sections — the Log sheet's
   picker, extracted into a shared `ScopeBar` component both screens
   render (the OnlineResultsSection lesson: shared surface, one
   implementation). Segmented normally, a menu at accessibility sizes.
   - Foods/Meals scopes keep the library ranking (favorites first,
     then recency, then name). Favorites is a flat mixed list ranked
     by recency, meals badged like the Log sheet's.
2. **Search moves to the bottom (iOS 26)** via
   `DefaultToolbarItem(kind: .search, placement: .bottomBar)` — the
   corner Add pill occupies the search-*tab* slot, but the toolbar
   item places the actual field in the bottom bar, which the old
   "top drawer by ruling" predates. iOS 18 keeps the standard
   nav-bar drawer (no bottom search exists there; the Log sheet
   falls back the same way).
3. **"Scan Barcode" row** under the scope menu (hidden while
   searching), styled like the new-food form's row. Routing matches
   the screen's own online-search pick path: a barcode already in
   the library opens the portion sheet (fast log); a new one fetches
   the product and opens the prefilled food form.
4. **Sheet consolidation**: FoodsView's six chained `.sheet`
   modifiers become one `.sheet(item:)` enum (the QuickLogSheet
   pattern) — required anyway for the scanner→portion handoff, which
   is exactly the silent-failure case that forced QuickLogSheet's
   consolidation.

## Test updates

- Flow test: logging the seeded meal now needs the Meals scope
  selected first (the default scope is Foods).
- QA walkthrough: scope shots on the Foods tab, mirroring the Log
  sheet's.

## Log vs Foods: recommendation

The restructure makes the two screens structurally similar on purpose
— same scope bar, same rows, same online section, same bottom search.
The roadmap asks: consolidate into one screen, or keep them distinct
with shared elements?

**Recommendation: keep them distinct; keep sharing at the component
level.** The screens now differ only where their jobs differ, and
every difference left is a deliberate product decision, not drift:

| | Log (sheet) | Foods (tab) |
|---|---|---|
| Job | record eating, into the browsed day | manage the library |
| Row tap | portion sheet ("in a sheet named Log, tap = log") | edit form |
| Extras | water row, HealthKit history ("as last logged"), Recent split, backfill date | category filter, delete, add flows, import empty state |
| Scanner | top-right toolbar icon | Scan Barcode row |

A consolidated screen would need a mode flag to flip tap semantics —
reintroducing "the one surprising row" that tap-to-edit-in-a-logging-
flow used to be — and would drag library management (delete, filter,
import) into a sheet whose whole point is fast logging. Two thin
screens over shared components is the cheaper honest shape.

What SHOULD still converge (follow-ups, not blockers):

1. **Barcode routing** — "known barcode → portion sheet, new →
   prefilled form" now lives in three places (Foods scan row, Foods
   online pick, Log's lookup). Extract one shared decision helper;
   each screen keeps its own sheet plumbing.
2. **Scanner placement** — Log keeps the toolbar icon for now (its
   list leads with Water + Recent; a scan row would push those down).
   If the icon proves undiscoverable in use, adopt the Foods row
   there too. One to judge on-device.
3. **Ranking** — Foods ranks favorites-first, Log ranks recency-only
   (both user rulings, at different times, for different jobs). Fine
   as-is, but worth a conscious re-confirm now that the screens look
   alike: same-looking lists that order differently can read as a bug.

## Non-goals

- Consolidating Log and Foods into one screen (see above).
- Touching the Log sheet's top-right barcode button (follow-up 2).
