# Handoff — the "+" tab flash, and the v2.5.12 batch (2026-07-18)

Two purposes:
1. **Deep-dive brief** for the tab-bar **"+" flash** bug (still unsolved).
2. **Release history** so nothing from this session is lost — what shipped
   (v2.5.7–v2.5.11) and what is **prepped, uncommitted** for **v2.5.12**.

Deployment floor: **iOS 18.0 / watchOS 10.0**. Devices in use are iOS/watchOS
26.5. The working tree **builds** as of this writing.

---

## PART 1 — THE "+" FLASH (needs a deep dive)

### Symptom
Tapping the bottom tab-bar **"+" (Add)** produces a brief **full-screen
flash** of the current screen. It's **most obvious on Foods** (the Add
chooser that follows is short and doesn't cover the flash) and **effectively
invisible on Today / Goal / Calendar** (the Log sheet that follows is large
and slides up over it). The user confirmed the flash fires on *every* "+"
tap; the big Log sheet just hides it elsewhere.

### What the "+" is
`ContentView.swift` → `mainTabs` → a `TabView`. The "+" is a **tab item**
used as an **action button**, not a destination:
`Tab("Add", systemImage: "plus", value: .log) { … }`. `AppTab.log` is never
meant to *stay* selected — tapping it should open an "add" flow.

Routing (must be preserved by any fix):
- **On Foods** → the **Add-to-Food-Library chooser** (Add Food / Add Meal).
- **Everywhere else** → **Today + the Log sheet** (`QuickActions.shared.quickLogRequest = .all`).
- **Long-press "+"** → log a water serving (`AddPillLongPress`, gated on
  `SharedStore.holdToLogWater`). Must keep working.

### Root-cause chain (what we established)
1. Originally the "+" was `role: .search` (the only public API that renders
   the Music-style *detached corner circle* in the iOS 26 tab bar), plus a
   **deferred bounce**: `.onChange(of: selectedTab)` set it to `.log`, then a
   `Task` reverted `selectedTab` to the origin tab.
2. Tapping it did two visible things:
   - the `.log` tab's placeholder content rendered for ~a frame (a bare
     `Color.clear` = **white flash**);
   - **`role: .search` activated a search experience on the CURRENT view** —
     morphing the tab bar and **sliding the current view's `.searchable`
     header down** (the user saw "the Foods heading slides in from the top").

### Everything tried, in order, and the result
| # | Change | Result |
|---|--------|--------|
| a | Deferred the chooser 250 ms so the tab-bounce didn't dismiss it | Fixed the *"chooser immediately disappears"* bug, but **exposed** the flash (previously the flash + the disappear were tangled). |
| b | `.log` tab content `Color.clear` → `Color.riceCanvas` (match page bg) | **No fix** (search morph + card-blink remained). |
| c | Moved the chooser out of FoodsView (`.alert` on a `Color.clear` bg) into **ContentView**, presented synchronously so it survives the bounce; made it a **bottom sheet** (`AddToLibrarySheet`) | Fixed the disappear robustly; sheet UX is what the user wants. **Flash persists** (a medium sheet doesn't cover the top of the screen, and the flash precedes the sheet). |
| d | **Custom `TabView` selection binding** that intercepts `.log` and never commits it (so `selectedTab` never becomes `.log`) | **Flash persists.** Strong signal that SwiftUI **transiently renders the tapped tab** even when the binding rejects the selection. |
| e | **Removed `role: .search`** (the "+" becomes a plain tab item) | Fixed the **header slide** (that was the search role). **Flash STILL persists.** |
| f | `.log` content back to `Color.riceCanvas` (with role gone) | **Built, NOT deployed/tested.** The last thing the user tested was (e) with `Color.clear`. |
| g | **REVERTED (e)+(f)** — the user found the plain-tab "+" made "the menu bar look off" (lost the detached corner circle). Restored `role: .search` + the deferred bounce. | Menu bar correct again; **flash accepted as a known-unsolved issue** for the deep dive. |

### Current working-tree state of the "+" (after the revert, step g)
- **`role: .search` RESTORED** — the "+" is the Music-style detached corner
  circle again. This is the appearance the user wants; **do not remove it**
  without replacing it with an equivalent non-tab "+".
- **Deferred `.onChange(of: selectedTab)` bounce RESTORED** (the `Task {}` that
  bounces `.log` back to the origin tab).
- **Add-chooser routing kept on the new bottom sheet**: the bounce's Foods
  branch sets `showAddChooser = true` (ContentView's `AddToLibrarySheet`),
  *not* the old `addFoodRequest`. Everywhere-else branch → Today + Log sheet.
- `.log` tab content = `Color.clear`.
- **The flash is PRESENT again** — this is the accepted trade for the correct
  menu bar. Eliminating it is the deep-dive's job (non-tab "+").
- The custom selection binding and `riceCanvas` placeholder from (d)–(f) are
  **gone**.

### Leading hypothesis
The flash is **intrinsic to the "+" being a `Tab`**: SwiftUI momentarily
renders the tapped tab's content on tap, *even when a custom selection
binding rejects the selection*. Neither matching the background color nor
rejecting the selection removes that transient render. **The only reliable
fix is to make the "+" NOT a tab.**

### Recommended directions for the deep dive
1. **iOS 26 `.tabViewBottomAccessory`** — a floating "+" accessory above the
   tab bar (not a tab → no selection → no transient render → no flash). Needs
   an **iOS 18 fallback** (target is 18.0). This may also *restore* the
   original "detached corner Add pill" look (see `plans/` history / memory).
2. **Custom floating action button** overlaid in a corner — version-agnostic,
   but repositions the "+".
3. **Confirm the transient-render hypothesis empirically**: drive a tap on the
   "+" tab via XCUITest, record with `simctl io <udid> recordVideo`, and
   inspect frames (ffmpeg) to see *exactly* what flashes (tab content vs a
   tab-bar highlight vs the sheet). We never got a frame capture of it.
4. Explore disabling the transition (`Transaction.disablesAnimations`) or an
   entirely custom tab bar.

### Landmines the deep dive must respect
- The bounce was originally **deferred** because a **synchronous** bounce with
  `role: .search` **wedged the Foods search drawer** (dead taps on Foods
  search after using the pill) — pinned by **`testFoodsSearchAfterSave`**.
  (May not apply now that `role: .search` is gone — verify against that test.)
- **`AddPillLongPress`** (long-press "+" → log water) must keep working.
- Preserve the routing above (Foods → chooser; else → Today + Log sheet).
- The Add chooser is now a **bottom sheet on ContentView** (`AddToLibrarySheet`)
  driven by `QuickActions.addFoodKind` (`.food` / `.meal`), consumed by
  FoodsView. Keep that; the flash work is orthogonal to it.

### Screenshot dependency (important)
Any "+" fix that changes the tab-bar appearance (removing `role: .search`
already does — the "+" is a plain tab now instead of the detached circle)
**changes the tab bar in EVERY screenshot** (Today, iPad, Foods, Calendar).
**Do not finalize/recapture screenshots until the "+" design is settled.**

---

## PART 2 — SHIPPED THIS SESSION (committed + pushed to BOTH remotes)

All on `main`, GPG-signed, tagged, pushed to GitHub + Forgejo.

| Ver | Commit | What |
|-----|--------|------|
| v2.5.7 | `c17aa1a` | **Today log rows scroll reliably.** Replaced the SwiftUI `DragGesture` on log rows with a **UIKit pan recognizer** (`HorizontalSwipeGesture` / `HorizontalPanGestureRecognizer` in `TodayView.swift`) that **fails itself on vertical drags** so the `ScrollView` pans. First UIKit bridge in the app. |
| v2.5.8 | `992d15d` | **Watch home title dropped** (inline `"🍙 Onigiri"` → empty title, headline no longer clipped) **+ live log refresh** (the watch's HealthKit log observer now also calls `model.refreshIfStale(maxAge:0)` when foreground). |
| v2.5.9 | `146dea8` | **Firmer Today swipe.** Recognizer requires **decisively horizontal** (`dx > dy*1.5`); **breakaway static friction** (~22 pt) in `LogRowSwipeActions` so a light graze doesn't peel a row toward delete. |
| — | `dae6b88` | **Recaptured Today screenshots** (phone + iPad, light+dark) for the new chevron layout; **hardened `testHeaderShots`** iPad capture (grab `tab-today` directly, before the flaky sidebar `switchTab`). |
| v2.5.10 | `2942584` | **Today day chevrons off the back-swipe edge** — moved `.topBarLeading` prev-chevron into a `.topBarTrailing` group (prev, next, then Settings). The left ~20 pt is iOS's back-swipe zone and was intermittently stealing the prev-day tap. |
| v2.5.11 | `009029f` | **Calendar + Foods controls off the edge** — Calendar month chevrons → both trailing; Foods category-filter + sort menus → trailing. |

### Watch/phone total discrepancy (investigated, NOT a bug — do not re-chase)
Watch and phone day totals can differ transiently. **Reboot-confirmed** it's
**HealthKit device-sync divergence**, not our code: phone (`TodayModel.summary`)
and watch (`DailyPlanLoader`→`todaySummary`) run the **identical**
`HealthKitService.daySummary` = sum(`.dietaryEnergyConsumed`) read. Free team =
no CloudKit, so log data rides HealthKit's own peer-to-peer sync
(eventually-consistent; the phone never pushes the day total). The v2.5.8
observer→refresh fix only closes the "data arrived, screen stale" window; it
can't beat HealthKit's sync timing. The paid→CloudKit path is the only real
remedy.

---

## PART 3 — SHIPPED AS v2.5.12

Committed + tagged + pushed as **v2.5.12** on 2026-07-18 (the known-working
checkpoint this session ended on). All items were deployed to the phone and
user-confirmed. The **"+" flash is NOT fixed** — it ships as-is (the experiment
was reverted; see Part 1). `MARKETING_VERSION` is now `2.5.12`.

- **Log Food sheet sort → trailing** — `QuickLogSheet.swift`, the sort Menu
  moved `.topBarLeading` → `.topBarTrailing`. ✅ confirmed.
- **"Food Library" copy sweep** — the tab stays **"Foods"**; user-facing copy
  standardized on **"Food Library"**; the two broken **"the Library tab"**
  strings fixed. Files: `MealFormView`, `QuickLogSheet`, `FoodsView`,
  `FoodFormView` (dup warning), `SettingsView` (Reset / Export / Import Food
  Library + toasts). Code comments → "Foods tab/screen" (`QuickActions`,
  `FoodFormView`). ✅ confirmed.
- **Add-to-Food-Library chooser → bottom sheet** — moved from a FoodsView
  `.alert` to **ContentView** as `AddToLibrarySheet` (a bottom sheet, `.height`
  detent, drag indicator). Add Food + Add Meal both `.borderedProminent`
  `riceToast`, Cancel `.bordered`. `QuickActions.addFoodRequest: Bool?` →
  `addFoodKind: AddFoodKind?` (`enum { food, meal }`); FoodsView consumes it.
  ✅ sheet + button colors confirmed. (Presentation is entangled with the
  flash work — see Part 1.)
- **The "+" flash** — the flash-fix experiment (remove `role: .search` + custom
  binding) was **reverted** (step g) because the plain-tab "+" made the menu bar
  look wrong. `role: .search` + the deferred bounce are restored; the bounce now
  feeds the new bottom-sheet chooser. ⚠️ **Flash still unsolved** — see Part 1;
  the real fix is a non-tab "+" (deep-dive item), which will change the tab-bar
  appearance again, so pair it with the screenshot recapture.
- **Sort order** — `LibrarySort` (`Style.swift`) reordered to
  `case recent, ranked, name` → menu shows **Recent, Favorites, Name**;
  Foods default → **`.recent`** (`FoodsView` `@AppStorage` default + fallback
  + the sort-icon "default" indicator). QuickLogSheet already defaulted
  `.recent` (separate `"logSheetSort"` key). ✅ confirmed.
- **App-icon Scan shortcut wording** — `project.yml` (generates Info.plist)
  `"Scan Barcode or Label"` → **`"Scan Barcode, Label, or Food"`** to match the
  in-app scan row. ✅ (regenerate Info.plist via `xcodegen`/deploy). NOTE:
  Info.plist is generated from `project.yml` — edit **project.yml**, not the
  plist.
- **Watch DEBUG seed path** — `WatchModel.start()` gained a `#if DEBUG`
  `--seed-sample-data` branch that logs a realistic day via `logFood`/
  `logWater` (NOT `seedSampleData()`, whose `requestDebugSeedAuthorization`
  pops an un-tappable watch Health sheet). This is the **watch-screenshot
  capture aid** (see Part 5). Release-safe (DEBUG-only).

---

## PART 4 — SCREENSHOTS (task in flight, paused on the "+" decision)

Marketing shots live in `docs/showcase/{light,dark,watch,widget}/` and
`docs/media/` (both light + dark; the site swaps with theme). `docs/` IS the
GitHub Pages site — committing publishes.

**Done + live** (in `dae6b88`): `showcase/{light,dark}/today.png`,
`showcase/{light,dark}/ipad-landscape.png` — new chevron layout, light+dark.

**Captured + staged** (in scratchpad `newshots/`, NOT yet in `docs/`):
- `watch-home.png` — **title-less watch home, −270 kcal balance**, 416×496.
  Ready to drop into `docs/showcase/watch/home.png`.
- `calendar-light.png`, `foods-light.png` — from `testHeaderShots`.

**Still to do:**
- `calendar.png` **dark** (only light captured).
- `foods.png` — **must be recaptured** because the **sort default changed to
  Recent** (the staged `foods-light.png` used the old `ranked`/favorites
  default, so the list order differs). Also foods.png is **light only** in the
  repo (no dark variant).
- **`docs/media/day-swipe*.mp4`** (+ posters, light+dark) — currently show the
  **removed** swipe-to-change-days gesture (captioned *"Swiping through three
  days"*). **Decision: re-shoot as chevron day-nav.** Not started.
- **Blocked on the "+" decision** (Part 1): finalizing the "+" changes the tab
  bar in every shot. Re-capture ALL device shots after the "+" is settled.

Capture recipe (memory `onigiri-readme-screenshots.md`): erase sim →
`simctl ui … appearance` → `simctl status_bar … override --time 9:41` →
`TEST_RUNNER_HEADER_SHOTS=1 … -only-testing:…/testHeaderShots` →
`xcrun xcresulttool export attachments`. iPhone 17 `B9DD19BB`. iPad Pro 13"
26.5 needs `sips -r 270` (portrait buffer), Full-Screen-Apps mode, and the
`•••`/home-indicator painted out (iPadOS 26 bakes them into captures). Helper
scripts live in this session's scratchpad (`capture-shot.sh`, `extract.py`).

---

## PART 5 — WATCH SIM FOOD-SEEDING (hard-won; also in memory)

To screenshot the watch home with realistic totals on the sim:
1. Erase **both paired sims** (iPhone 17 Pro `65FE85CE…` + Watch Series 11
   46mm `B5010BD4…`; `simctl list pairs`).
2. **Seed + grant on the PHONE** via `testHeaderShots` — CRITICAL: this
   *determines the shared HealthKit auth* so the watch's `requestAuthorization`
   is a no-op. Without it the watch pops a "Health Access / Review" sheet that
   **cannot be tapped** on the watch sim (no `simctl` tap, no watch UI-test).
3. Build `OnigiriWatch` for the watch sim, install, then
   `simctl launch <watch> com.ecliptik.Onigiri.watchkitapp --seed-sample-data`
   → the DEBUG seed's `logFood` writes into the now-authorized store (no
   sheet). Burn (~1505) comes from the phone's shared seed → balance ≈
   food − burn (logging ~1235 → −270 green).
4. `simctl io <watch> screenshot`. `status_bar override` is **unsupported** on
   watchOS (shows real sim time). Do NOT use `seedSampleData()` on the watch —
   its `requestDebugSeedAuthorization` pops the un-tappable sheet.

---

## PART 6 — MEMORY IS BEHIND

`onigiri-project-status.md` was updated through **v2.5.8** this session; it does
**not** yet reflect v2.5.9 / v2.5.10 / v2.5.11 or the prepped v2.5.12 batch.
`onigiri-readme-screenshots.md` has the watch-seeding recipe (Part 5). Update
the status hub when v2.5.12 lands.
