import XCTest

/// Drives the seeded app end to end: grants Health access sheets, verifies
/// the seeded log renders on Today, and logs a food from the library.

/// Polls for an element to settle into a hittable state instead of a
/// fixed sleep, which either wastes time on a fast run or isn't long
/// enough on a slow one — the same idiom `switchTab` already uses below.
/// For a screenshot or an assertion that follows an animation (a
/// disclosure expanding, a scroll settling) with no existence change of
/// its own to wait on (health-check audit, 2026-09-14).
@MainActor
func settle(_ element: XCUIElement, timeout: TimeInterval = 2) {
    let deadline = Date().addingTimeInterval(timeout)
    while !element.isHittable, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
    }
}

/// Tab switching that survives both idioms: the iPhone's bottom TabBar
/// and the iPad's top bar, which exposes NO TabBar element at all.
@MainActor
func switchTab(in app: XCUIApplication, to name: String) {
    let phoneTab = app.tabBars.buttons[name]
    if phoneTab.waitForExistence(timeout: 2), phoneTab.isHittable {
        phoneTab.tap()
        return
    }
    let anyTab = app.buttons[name].firstMatch
    _ = anyTab.waitForExistence(timeout: 5)
    // EXISTENCE is not reachability, and this is the sharp version of
    // that rule: a sheet does NOT remove the screen beneath it from the
    // hierarchy, so a covered tab button still exists — and tapping it
    // lands on the sheet. Silently. No error, no failure, and every step
    // after it runs against the wrong screen.
    //
    // That is what cost the QA walkthrough its Goal, Foods-edit and
    // Meals-edit stops (found 2026-08-23): an Add Food form stayed up,
    // and `qa-goal` was a photograph of it while the run reported
    // success. Failing here is the only thing that makes such a capture
    // impossible; a tour that finishes with mislabelled screenshots is
    // worse than one that stops.
    let deadline = Date().addingTimeInterval(5)
    while !anyTab.isHittable, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.2)
    }
    guard anyTab.isHittable else {
        XCTFail(
            "The \(name) tab exists but is not tappable — something modal is "
            + "over it. Dismiss it before switching tabs (dismissModals)."
        )
        return
    }
    anyTab.tap()
}

/// Get back to a screen whose tab chrome can actually be tapped, and say
/// whether that worked.
///
/// The loop this replaces asked whether the Foods scope bar EXISTED, and
/// a sheet leaves the screen under it in the hierarchy — so the answer
/// was yes for the whole time it was covered. It exited on the first
/// check having dismissed nothing (2026-08-23). Hittability of the tab
/// bar is the honest test: only an unobstructed screen has one.
///
/// Nav-bar buttons only. A bare `app.buttons["Cancel"]` also matches the
/// `.searchable` bar's cancel and whatever a sheet's content puts on
/// screen, so it can "succeed" without closing anything and spin out the
/// retries.
@MainActor
@discardableResult
func dismissModals(in app: XCUIApplication, tries: Int = 5) -> Bool {
    func chromeReachable() -> Bool {
        app.tabBars.buttons.count > 0
            ? app.tabBars.buttons.firstMatch.isHittable
            : app.buttons["Today"].firstMatch.isHittable
    }
    for _ in 0..<tries where !chromeReachable() {
        let cancel = app.navigationBars.buttons["Cancel"].firstMatch
        if cancel.exists, cancel.isHittable { cancel.tap(); continue }
        let done = app.navigationBars.buttons["Done"].firstMatch
        if done.exists, done.isHittable { done.tap(); continue }
        app.swipeDown()
    }
    return chromeReachable()
}


/// The "Details ›" caption is one shared grammar across Today, the
/// Calendar day card, and the month card (2.1 restored Today's chevron
/// to match). The trailing chevron is accessibilityHidden, so all three
/// still read simply as "Details" — match by label, across StaticText
/// (Calendar) and Button (Today's NavigationLink).
@MainActor
func detailsLink(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(
        NSPredicate(format: "label == 'Details' AND elementType IN {9, 48}")
    ).firstMatch
}

/// The scan row's label is AI-gated ("Scan Barcode, Label, or Food"
/// when Apple Intelligence is available — which it IS on iOS 26 sims —
/// "Scan Barcode or Nutrition Label" otherwise). Match both.
@MainActor
func scanRow(in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH 'Scan Barcode'")
    ).firstMatch
}

/// The Log sheet's ONE text field — "Search, or Describe Food or Meal",
/// in the pinned door bar. It searches the library, so every test that
/// used to type into the sheet's `.searchable` drawer types here now
/// (the drawer left on 2026-09-17). By identifier, not label: the label
/// is the prompt, and the prompt is copy.
func logSheetField(in app: XCUIApplication) -> XCUIElement {
    app.textFields["entryDoorsDescribeField"].firstMatch
}

/// Tap a scope segment, scrolling it back into reach first. The Foods
/// tab renders its scope bar as a LIST ROW, so anything that scrolls the
/// list can leave the segment present-but-unhittable — a state
/// `waitForExistence` reports as ready.
@MainActor
func scopeTap(in app: XCUIApplication, _ label: String) {
    guard app.segmentedControls.count > 0 else { return }
    let segment = app.segmentedControls.firstMatch.buttons[label]
    for _ in 0..<3 where !segment.isHittable { app.swipeDown() }
    if segment.isHittable { segment.tap() }
}

/// Reveal `row` inside Goal's budget explainer, opening the group if it
/// is shut, and say whether it worked.
///
/// SCROLL FIRST, then toggle. A `DisclosureGroup` toggles, and a Form
/// does not render a row until it is scrolled near — so "the row is not
/// in the tree" is true both for a shut group AND for an open one whose
/// rows are below the fold. A tap decided on that reading CLOSES a group
/// that was already open, and the assertion after it then fails for the
/// opposite of its stated reason. That is what broke the lose-mode half
/// of `testMaintenanceMode` when the Budget section above shrank from
/// six rows to one and moved the header up (2026-08-23).
///
/// Deciding on a sentinel row instead does NOT work, and the attempt is
/// worth recording: the group has no row near its top common to both
/// modes — `To lose`, `Days left` and `Deficit needed` are all inside
/// `if !isMaintenance`, and `Based on` is a navigation-link `Picker`
/// that never appears as a plain static text at all, so probing for it
/// is false in every state and the toggle fires unconditionally.
@MainActor
@discardableResult
func revealInBudgetExplainer(
    in app: XCUIApplication, header: XCUIElement, row: XCUIElement
) -> Bool {
    // Two passes: the first rules out "merely below the fold", the
    // second runs after the group has actually been opened.
    for _ in 0..<2 {
        for _ in 0..<8 where !row.exists { app.swipeUp() }
        if row.exists { return true }
        for _ in 0..<8 where !header.isHittable { app.swipeDown() }
        guard header.isHittable else { return false }
        header.tap()
    }
    return row.exists
}

/// Leave Settings from wherever you are inside it.
///
/// The pushed subscreens (Metrics, Appearance, …) have only a Back button;
/// "Done" belongs to the Settings ROOT and is not in the tree at all from
/// inside one — so `app.buttons["Done"].tap()` from a subscreen fails
/// against a control that cannot be there. `testTrackedMetricSwap` did
/// exactly that, twice, and had been failing on it (2026-08-23, confirmed
/// against an untouched tree). The sheet cannot be swiped away either:
/// interactive dismissal is off by design, so every exit is an explicit
/// Done.
///
/// Both lookups are scoped to the NAVIGATION BAR, because the back button
/// is labelled with its parent's title — "Settings" — and so is Today's
/// gearshape, which makes the unscoped query ambiguous.
@MainActor
func closeSettings(in app: XCUIApplication) {
    let back = app.navigationBars.buttons["Settings"].firstMatch
    if back.waitForExistence(timeout: 3), back.isHittable { back.tap() }
    let done = app.navigationBars.buttons["Done"].firstMatch
    XCTAssertTrue(done.waitForExistence(timeout: 10), "The Settings root's Done")
    done.tap()
}

/// Today's day heading — a NATIVE `.inlineLarge` title since 2026-09-16
/// (`inlineLargeTitle`, Style.swift). It was a tappable in-content button
/// carrying "<day>. Jump to date" before; Jump to date is its own button
/// in the trailing pill now (`jumpToDate`). Scoped to the navigation bar
/// on purpose: Today's body has plain texts of its own, and the Log
/// sheet's title is another nav-bar text — call this with no sheet up.
///
/// READ ITS FRAME, NOT ITS LABEL, on the 26.5 sim: under `.inlineLarge`
/// that OS leaves the title's accessibility label on its FIRST value
/// after the day changes — "Today" while yesterday is on screen. A probe
/// app reproduced it in that mode alone (`.inline` and 27.0 both update),
/// so it is a platform bug, not ours. Which day is showing is read off
/// the Next-day chevron's enabled state instead (disabled only on today).
@MainActor
func dayHeading(in app: XCUIApplication) -> XCUIElement {
    app.navigationBars.staticTexts.firstMatch
}

/// The Calendar tab's MONTH summary card, which pushes the month detail.
/// Since 2.1 the day card ALSO shows "Details ›" (grammar unified), so a
/// bare detailsLink is ambiguous on this tab — target the month card by
/// the streak line only its combined label carries.
@MainActor
func calendarMonthCard(in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(
        NSPredicate(format: "label CONTAINS 'current streak'")
    ).firstMatch
}

final class OnigiriUITests: XCTestCase {

    /// One screenshot of Goal's `Budget` section, opt-in via
    /// `TEST_RUNNER_BUDGET_SHOT=1`. It exists because the QA walkthrough's
    /// `qa-goal` shot is NOT reliable evidence for this screen: on
    /// 2026-08-23 both of its Goal captures were a stuck food-form sheet
    /// (an optional Cancel that did not fire), and the test still passed —
    /// a green run that proved nothing until the images were opened.
    ///
    /// It asserts what it means to photograph, so a capture that lands on
    /// the wrong screen FAILS rather than filing a misleading picture —
    /// and it asserts the ABSENCES too, because "no day figures on Goal"
    /// is the property this section now has and nothing else pins it.
    @MainActor
    func testGoalBudgetShot() throws {
        guard ProcessInfo.processInfo.environment["BUDGET_SHOT"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_BUDGET_SHOT=1 to capture Goal's budget rows")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--seed-sample-data"]
        // TEST_RUNNER_SEED_AGGRESSIVE=1 captures the pace-warning state
        // instead of the ordinary one — the reason `--seed-aggressive`
        // exists, and the only thing that proves the flag still works
        // now that the default seed no longer trips the warning.
        let aggressive = ProcessInfo.processInfo.environment["SEED_AGGRESSIVE"] == "1"
        if aggressive { app.launchArguments.append("--seed-aggressive") }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        // A fresh install puts onboarding and the Health sheets in the
        // way, and this test used to skip both — it passed only because
        // it ran against an already-granted container. The uninstall
        // that a seeder change requires is exactly when that stops being
        // true, and `switchTab`'s new guard is what said so instead of
        // tapping through the permission sheet.
        skipOnboardingIfPresent(in: app)
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)
        switchTab(in: app, to: "Goal")
        // The chart, progress and weight rows come first, so the Budget
        // section starts below the fold — and a Form renders lazily, so
        // the row does not merely sit off-screen, it does not EXIST yet.
        // Waiting on it without scrolling is the "probe that guards
        // nothing" failure in its other direction: a 20-second wait that
        // could never have succeeded.
        _ = app.staticTexts["Current weight"].waitForExistence(timeout: 20)
        let budgetRow = app.staticTexts["Daily budget"]
        for _ in 0..<8 where !budgetRow.exists { app.swipeUp() }
        XCTAssertTrue(
            budgetRow.waitForExistence(timeout: 5),
            "Goal's Budget section never appeared — the shot would be of the wrong screen"
        )
        // The whole point of the section: nothing on it reports a DAY.
        for dayRow in ["Eaten today", "Left today", "Burned today", "Earned by moving"] {
            XCTAssertFalse(
                app.staticTexts[dayRow].exists,
                "\(dayRow) is a Today figure and does not belong on Goal"
            )
        }
        // The pace warning is its own section directly under the budget,
        // never inside the collapsed group — so its presence is exactly
        // what the seed flag is asserted by. Checked in BOTH directions:
        // the default seed tripping it is what made every Goal capture
        // unreviewable in the first place (2026-08-23).
        let pace = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'That pace is aggressive'")).firstMatch
        XCTAssertEqual(
            pace.exists, aggressive,
            aggressive
                ? "--seed-aggressive should trip the pace warning"
                : "the default seed should NOT trip the pace warning — if a "
                    + "state flag (e.g. --seed-aggressive) was used on this "
                    + "simulator, erase it: a plain seed only fills an EMPTY "
                    + "store, so the previous goal is still in there"
        )
        settle(budgetRow)
        let top = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        top.name = aggressive ? "goal-budget-aggressive" : "goal-budget"
        top.lifetime = .keepAlways
        add(top)
        // The disclosure open, so the two budgets and the reconciliation
        // sentence are in ONE frame — the whole point of the change.
        let disclosure = app.buttons["How your budget is calculated"]
        for _ in 0..<4 where !disclosure.exists { app.swipeUp() }
        if disclosure.waitForExistence(timeout: 5) {
            disclosure.tap()
            settle(disclosure)
            // `Average daily burn` is the LAST row of the recipe and
            // the only burn figure left on the screen: the observed
            // cross-check and both resting rows were cut on 2026-08-24,
            // so reaching this one means the whole derivation is in
            // frame. It also pins the cut — a second burn row would
            // push it further down, and a resting row would follow it.
            for _ in 0..<6 where !app.staticTexts["Average daily burn"].exists { app.swipeUp() }
            XCTAssertTrue(app.staticTexts["Average daily burn"].exists)
            for cut in ["Average burn, from data", "Resting burn, full day", "Resting budget"] {
                XCTAssertFalse(
                    app.staticTexts[cut].exists,
                    "\(cut) was cut from the explainer — the recipe is the only thing in it"
                )
            }
            let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            opened.name = "goal-budget-derivation"
            opened.lifetime = .keepAlways
            add(opened)
        }
    }

    @MainActor
    func testSeedGrantAndLogFlow() throws {
        let app = XCUIApplication()
        // Capture runs can leave the sim rotated; the flow's coordinate
        // taps assume portrait.
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()

        // Health access sheets appear up to twice: once for the app's own
        // types, once for the debug seeder's extra write types.
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        // Bounce tabs to trigger a Today refresh now that access is granted.
        switchTab(in: app, to: "Foods")
        switchTab(in: app, to: "Today")

        // Fail fast on stale sim state before the flow gets going: every
        // --seed-sample-data launch ADDS HealthKit samples, so the
        // hardcoded totals this test asserts (24→36 oz water, 154 g
        // protein, the 3-day streak) hold only on a freshly-erased
        // simulator pair. Without this guard a stale pair surfaces as a
        // cryptic timeout deep in the flow.
        assertFreshlySeededState(in: app)

        // Seeded food correlations should appear in the Today log. Meal
        // sections start collapsed, so expand them to see the entry rows.
        XCTAssertTrue(
            app.buttons.matching(collapsedSectionPredicate).firstMatch.waitForExistence(timeout: 20),
            "Seeded log should render meal-slot sections"
        )
        expandMealSections(in: app)
        XCTAssertTrue(
            app.staticTexts["Chicken burrito"].waitForExistence(timeout: 10),
            "Seeded lunch should render in the Logged today list"
        )
        XCTAssertTrue(app.staticTexts["Two eggs & toast"].exists)

        // Deliberate logging via the row's Log button (row taps open Edit).
        // Foods confirm through the portion sheet: pick a slot and Log.
        switchTab(in: app, to: "Foods")
        let logShake = app.buttons["Log Protein shake"]
        XCTAssertTrue(logShake.waitForExistence(timeout: 10), "Seeded library should list foods")
        logShake.tap()
        let confirmLog = app.buttons["Log"]
        XCTAssertTrue(confirmLog.waitForExistence(timeout: 5), "Portion sheet should open on +")
        app.buttons["Snack"].tap()
        confirmLog.tap()

        // A library MEAL logs one-tap and must carry its foods' combined
        // nutrients into HealthKit (the day detail reads them back).
        // Meals live behind their scope since 1.8.1 — switch first.
        let scopeBar = app.segmentedControls.firstMatch
        XCTAssertTrue(scopeBar.waitForExistence(timeout: 5), "Foods scope bar")
        scopeBar.buttons["Meals"].tap()
        let logMeal = app.buttons["Log Chicken & rice"]
        XCTAssertTrue(logMeal.waitForExistence(timeout: 10), "Seeded library should list meals")
        logMeal.tap()

        switchTab(in: app, to: "Today")
        XCTAssertTrue(app.staticTexts["Snack"].waitForExistence(timeout: 10),
                      "Entry should land in its meal-slot section")
        expandMealSections(in: app)
        XCTAssertTrue(
            app.staticTexts["Protein shake"].waitForExistence(timeout: 10),
            "Logged food should appear in the Today log"
        )

        // Water lives on Today now: seeded 24 oz + one 12 oz serving = 36,
        // shown in the hydration row.
        XCTAssertTrue(
            app.staticTexts["24 / 64 oz water"].waitForExistence(timeout: 10),
            "Seeded water total should show in the hydration row"
        )
        // Water logs from the Log sheet's pinned top row — restyled to
        // the row grammar: the + capsule ("Log Water") is the tap target.
        switchTab(in: app, to: "Add")
        let waterButton = app.buttons["Log Water"]
        XCTAssertTrue(waterButton.waitForExistence(timeout: 10),
                      "Log sheet should pin the water row on top")
        waterButton.tap()
        let waterDone = app.buttons["Done"]
        XCTAssertTrue(waterDone.waitForExistence(timeout: 5))
        waterDone.tap()
        XCTAssertTrue(
            app.staticTexts["36 / 64 oz water"].waitForExistence(timeout: 10),
            "Hydration total should update after the water log"
        )

        // The meter grid drills into the day's full nutrient breakdown,
        // summed from the seeded meals' extended nutrients.
        detailsLink(in: app).tap()
        XCTAssertTrue(
            app.navigationBars["Details"].waitForExistence(timeout: 10),
            "Meter grid should push the day nutrition detail"
        )
        // Groups are collapsed by default; expand to reach the rows.
        let macroGroup = app.staticTexts["Macronutrients"]
        XCTAssertTrue(macroGroup.waitForExistence(timeout: 5),
                      "Seeded meals should produce a macro group")
        macroGroup.tap()
        // The energy rows above (Active/Resting/Deficit) push the deep
        // macro rows below the iPhone's fold — scroll them into view.
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Protein"].waitForExistence(timeout: 5),
                      "Expanding macros should reveal the rows")
        // 154 g = seeded breakfast 24 + lunch 42 + shake 30 + the Chicken
        // & rice meal's 58 — only adds up if the one-tap meal wrote its
        // foods' combined nutrients to Health and they read back.
        let proteinTotal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '154 g'")).firstMatch
        XCTAssertTrue(proteinTotal.waitForExistence(timeout: 5),
                      "Protein total should include the logged meal's nutrients")
        app.swipeUp()
        let mineralsGroup = app.staticTexts["Minerals"]
        XCTAssertTrue(mineralsGroup.waitForExistence(timeout: 5),
                      "Seeded micronutrients should produce a Minerals group")
        mineralsGroup.tap()
        XCTAssertTrue(
            app.staticTexts["Calcium"].waitForExistence(timeout: 5),
            "Expanding Minerals should reveal its rows"
        )
        app.navigationBars["Details"].buttons.firstMatch.tap()
        // Scrolling the detail minimized the iOS 26 tab bar to just the
        // active tab; scrolling back up re-expands it.
        app.swipeDown()

        // Recents: the Log sheet leads with last week's distinct logged
        // foods. "Chicken burrito" lives only in seeded HealthKit history
        // (not the library), so its Log button can only come from the
        // Recent query — and its portion sheet must carry the entry's own
        // values ("as last logged"), the no-library-match path.
        switchTab(in: app, to: "Add")  // the corner + pill opens the Log sheet
        // Favorites is the default scope (flat ranked list, no Recent
        // split) — the Recent assertions live on the Foods scope.
        let logScopeBar = app.segmentedControls.firstMatch
        XCTAssertTrue(logScopeBar.waitForExistence(timeout: 10), "Log sheet scope bar")
        logScopeBar.buttons["Foods"].tap()
        // Form rows are lazy: on smaller screens (5.8" XS class) the
        // Recent section starts below the fold — swipe it into existence.
        // Case-insensitive: iOS 18 renders section headers UPPERCASED
        // ('RECENT'); iOS 26's design stopped uppercasing.
        let recentHeader = app.staticTexts.matching(
            NSPredicate(format: "label ==[c] 'Recent'")
        ).firstMatch
        for _ in 0..<4 where !recentHeader.exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            recentHeader.waitForExistence(timeout: 10),
            "Log sheet should lead with a Recent section"
        )
        let recentBurrito = app.buttons["Log Chicken burrito"]
        for _ in 0..<3 where !recentBurrito.exists {
            app.swipeUp()
        }
        XCTAssertTrue(recentBurrito.waitForExistence(timeout: 5),
                      "History-only food should surface in Recents")
        // Exists ≠ tappable: the entry doors (scan + describe) sit above
        // the list now, so this row can land in the floating bottom
        // search bar's dead zone where taps are swallowed — and
        // isHittable still reports true there (caught + sim-reproduced
        // 2026-07-19, manual coordinate tap also dead). Scroll by FRAME
        // until the row sits clear of the bar's zone (~bottom 180 pt).
        for _ in 0..<3 where recentBurrito.frame.midY > app.frame.height - 180 {
            app.swipeUp()
        }
        recentBurrito.tap()
        // LabeledContent folds label and value into one element, so match
        // the combined label rather than a bare static text.
        let lastLogged = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'as last logged'")).firstMatch
        XCTAssertTrue(lastLogged.waitForExistence(timeout: 5),
                      "Recent without a library match should re-log its own values")
        let logRecent = app.buttons["Log"]
        XCTAssertTrue(logRecent.waitForExistence(timeout: 5),
                      "Recent row should open the portion sheet")
        logRecent.tap()
        // The Log sheet stays open after a log now (multi-item lunches);
        // Done leaves it.
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5),
                      "Log sheet should stay open after logging, with Done to leave")
        doneButton.tap()

        // Streak calendar: the three seeded history days each earned an
        // onigiri (750 kcal deficit vs ~618 target), so the streak is 3.
        switchTab(in: app, to: "Calendar")
        XCTAssertTrue(
            app.staticTexts["3 days"].waitForExistence(timeout: 10),
            "Seeded history should produce a 3-day streak"
        )

        // Log rows delete by swipe now (library-consistent, trash icons
        // gone). Water was 36 oz across three 12 oz rows; deleting one
        // brings the hydration row back to 24 — and the day-paging swipe
        // must stand down, so the title stays "Today".
        switchTab(in: app, to: "Today")
        expandMealSections(in: app)
        // The water group sits at the bottom of the expanded log, and the
        // log's rows are LAZY — a row below the fold doesn't exist in the
        // tree until scrolled near. Scroll toward it BEFORE asserting
        // existence (asserting first failed deterministically on an erased
        // sim, reproduced on stock v2.5.12 — 2026-07-19).
        let waterRow = app.staticTexts["12 oz"].firstMatch
        for _ in 0..<4 where !waterRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(waterRow.waitForExistence(timeout: 10),
                      "Water rows should be visible once expanded")
        for _ in 0..<3 where !waterRow.isHittable {
            app.swipeUp()
        }
        // A slow press-drag, not swipeLeft(): the flick is too fast for a
        // DragGesture inside a ScrollView to accumulate samples. 300pt
        // left is past the full-swipe threshold, so it deletes outright.
        let waterStart = waterRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        waterStart.press(
            forDuration: 0.1,
            thenDragTo: waterStart.withOffset(CGVector(dx: -300, dy: 0))
        )
        // Deletes commit outright now — the Undo toast replaced the
        // confirm alert (one gesture instead of four).
        XCTAssertTrue(app.staticTexts["24 / 64 oz water"].waitForExistence(timeout: 10),
                      "Full swipe should delete the water row outright")
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5),
                      "Delete should offer Undo in the toast")
        // Still on today: the Next-day chevron is disabled only there
        // (the title's label is unreliable on 26.5 — see `dayHeading`).
        XCTAssertFalse(app.buttons["Next day"].isEnabled,
                       "A row swipe must not page to another day")

        // Swipe RIGHT on a food row reveals Edit (library-consistent);
        // 150pt opens the reveal without committing. Editing to 2
        // servings doubles the entry in place.
        let shakeRow = app.staticTexts["Protein shake"].firstMatch
        XCTAssertTrue(shakeRow.waitForExistence(timeout: 5))
        for _ in 0..<2 where !shakeRow.isHittable {
            app.swipeUp()
        }
        let shakeStart = shakeRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        shakeStart.press(
            forDuration: 0.1,
            thenDragTo: shakeStart.withOffset(CGVector(dx: 150, dy: 0))
        )
        let editShake = app.buttons["Edit Protein shake"]
        XCTAssertTrue(editShake.waitForExistence(timeout: 5),
                      "Right-swiping a log row should reveal Edit")
        editShake.tap()
        // The stepper replaced the fraction chips: 4 quarter-steps = 2×.
        let increment = app.buttons["Increment"].firstMatch
        XCTAssertTrue(increment.waitForExistence(timeout: 5),
                      "Edit should open the portion sheet with the stepper")
        for _ in 0..<4 { increment.tap() }
        // Edit mode's confirm reads "Save" (and offers the entry's time).
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["360 kcal"].waitForExistence(timeout: 10),
                      "Editing to 2 servings should double the logged entry")
        // Scroll back up so the minimized tab bar re-expands.
        app.swipeDown()
        switchTab(in: app, to: "Calendar")

        // Predicted vs actual moved off the card into the pushed month
        // detail. Seeded data has a month of weigh-ins and deficit days,
        // so both rows should carry real values (assert on lb, not —).
        // Target the MONTH card specifically: since 2.1 the day card
        // also shows "Details ›" (grammar unified), so a bare
        // detailsLink is ambiguous on this tab.
        let monthCard = calendarMonthCard(in: app)
        XCTAssertTrue(monthCard.waitForExistence(timeout: 5),
                      "Calendar month summary card")
        // Existence is not hittability — this file's own rule. The card
        // happens to sit above the fold on this device, but a larger
        // Dynamic Type size pushes it down, and an unhittable card taps
        // into nothing while still "existing". Defensive, not the fix
        // for anything observed.
        for _ in 0..<5 where !monthCard.isHittable { app.swipeUp() }
        XCTAssertTrue(monthCard.isHittable, "Month card should be reachable")
        monthCard.tap()
        // Confirm the push landed before hunting rows on it, or a failed
        // navigation reads as a missing row.
        func row(titled title: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", title))
                .firstMatch
        }
        XCTAssertTrue(row(titled: "Days goal met").waitForExistence(timeout: 10),
                      "Month detail should have pushed")

        // The rows sit nine deep in "This month", below the fold, and a
        // List keeps off-screen rows out of the accessibility tree — so
        // scroll before reading. `waitForExistence` on an element that
        // never enters the tree just burns its timeout.
        //
        // Match the COMBINED element: each `LabeledContent` yields two
        // static texts, the bare title ("Predicted") and the whole row
        // ("Predicted, -0.9 lb"). A plain `CONTAINS title` firstMatch
        // returns the title, whose own `value` is empty — which reads as
        // a blank figure and sent an earlier fix down the wrong path.
        func figure(inRowTitled title: String) -> String {
            let target = app.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", title + ","))
                .firstMatch
            for _ in 0..<6 where !target.exists { app.swipeUp() }
            XCTAssertTrue(target.waitForExistence(timeout: 5),
                          "Month detail should show a '\(title)' row")
            return target.label
        }
        let predicted = figure(inRowTitled: "Predicted")
        XCTAssertTrue(predicted.contains("lb"),
                      "Predicted should carry an lb figure, row read: \(predicted)")
        let scale = figure(inRowTitled: "Scale change")
        XCTAssertTrue(scale.contains("lb"),
                      "Scale change should carry an lb figure, row read: \(scale)")
    }

    /// The site's three clips (opt-in: TEST_RUNNER_SITE_CLIP=day-swipe |
    /// add-food | ai-estimate). This test only DRIVES — an external
    /// `simctl io recordVideo` films it, and `CLIPMARK <name> <epoch>`
    /// lines in the log say roughly where each beat fell. "Roughly": a
    /// tap lands up to a second after it is asked for and the recorder
    /// starts 0.2–2 s late, so the cut is always measured from FRAMES
    /// (`plans/PLAN-site-and-media.md`). XCUITest rather than `axe`
    /// because the iOS 26 tab bar is absent from the tree `axe` reads,
    /// and the + that opens two of these clips lives in it.
    ///
    /// day-swipe opens and closes on Today at rest, so the loop has no
    /// seam. The other two end somewhere new and cut back, as they
    /// always have. Every take logs or types something — one take per
    /// launch; the seed resets Health on a simulator.
    @MainActor
    func testSiteClip() throws {
        guard let clip = ProcessInfo.processInfo.environment["SITE_CLIP"] else {
            throw XCTSkip("Set TEST_RUNNER_SITE_CLIP=day-swipe|add-food|ai-estimate")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"] + (clip == "ai-estimate" ? ["--seed-ai-on"] : [])
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        func mark(_ name: String) {
            print("CLIPMARK \(name) \(Date().timeIntervalSince1970)")
        }
        func beat(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
        /// The ENABLED match: while a child sheet is up the host's own
        /// Cancel/Log/Done stay in the tree, disabled (`recedesWithSheet`).
        func enabledButton(_ label: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label == %@ AND enabled == true", label)).firstMatch
        }

        XCTAssertTrue(app.buttons["Previous day"].waitForExistence(timeout: 15), "Today should be up")
        beat(4) // the first load, the ring's fill, the prime's write

        switch clip {
        case "day-swipe":
            let previous = app.buttons["Previous day"]
            let next = app.buttons["Next day"]
            mark("start")
            beat(1.6)
            for (name, button) in [("back1", previous), ("back2", previous), ("fwd1", next), ("fwd2", next)] {
                mark(name)
                button.tap()
                beat(1.1)
            }
            mark("end")
            beat(3)

        case "add-food":
            mark("start")
            beat(1.4)
            app.buttons["Add"].firstMatch.tap()
            mark("sheet")
            XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 5), "Log sheet should be up")
            beat(1.8)
            // The meal's ROW opens the portion sheet (with Contains); its
            // + would log it outright.
            let mealRow = app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH 'Chicken & rice'")).firstMatch
            XCTAssertTrue(mealRow.waitForExistence(timeout: 5), "The seeded favorite meal should be listed")
            mealRow.tap()
            mark("portion")
            beat(2.6)
            enabledButton("Log").tap()
            mark("logged")
            beat(4)

        case "ai-estimate":
            app.buttons["Add"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 5), "Log sheet should be up")
            beat(2)
            mark("start")
            beat(1.4)
            let describe = app.textFields["entryDoorsDescribeField"].firstMatch
            XCTAssertTrue(describe.waitForExistence(timeout: 5), "The describe field needs AI on")
            describe.tap()
            beat(0.6)
            mark("typing")
            for character in "Pork and beans" {
                describe.typeText(String(character))
            }
            beat(1.4)
            let estimate = app.descendants(matching: .any).matching(NSPredicate(
                format: "label BEGINSWITH 'Estimate with'")).firstMatch
            XCTAssertTrue(estimate.waitForExistence(timeout: 5), "The tap-to-estimate row should be offered")
            estimate.tap()
            mark("estimating")
            // Only true once the model has ANSWERED — the query text is in
            // the tree from the first keystroke and proves nothing.
            let result = app.descendants(matching: .any).matching(NSPredicate(
                format: "label CONTAINS 'AI estimate'")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 90), "The estimate should land")
            mark("answered")
            beat(2.2)
            result.tap()
            mark("form")
            XCTAssertTrue(app.navigationBars["New Food"].waitForExistence(timeout: 8), "The food form should open")
            beat(4)

        default:
            XCTFail("Unknown SITE_CLIP '\(clip)'")
        }
    }

    /// Showcase tour (opt-in via TEST_RUNNER_SHOWCASE=1): walks every
    /// feature at reading pace on seeded data, attaching a named
    /// screenshot per scene plus a JSON of wall-clock scene timings — an
    /// external `simctl io recordVideo` can be captioned against those
    /// epochs. Erase the paired sims first.
    @MainActor
    func testShowcaseTour() throws {
        guard ProcessInfo.processInfo.environment["SHOWCASE"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_SHOWCASE=1 to run the showcase tour")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--seed-sample-data"]
        var timings: [[String: Any]] = []

        func scene(_ name: String, settle: TimeInterval = 1.0, hold: TimeInterval = 4.5) {
            Thread.sleep(forTimeInterval: settle)
            timings.append(["name": name, "epoch": Date().timeIntervalSince1970])
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "shot-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
            Thread.sleep(forTimeInterval: hold)
        }

        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)
        switchTab(in: app, to: "Foods")
        switchTab(in: app, to: "Today")
        _ = app.buttons.matching(collapsedSectionPredicate).firstMatch.waitForExistence(timeout: 20)
        expandMealSections(in: app)
        scene("today")

        detailsLink(in: app).tap()
        let macros = app.staticTexts["Macronutrients"]
        if macros.waitForExistence(timeout: 5) {
            macros.tap()
            Thread.sleep(forTimeInterval: 0.6)
            let minerals = app.staticTexts["Minerals"]
            if minerals.isHittable { minerals.tap() }
        }
        scene("nutrition")
        app.navigationBars["Details"].buttons.firstMatch.tap()
        app.swipeDown()

        switchTab(in: app, to: "Add")  // the corner + pill opens the Log sheet
        // Favorites opens by default; the seeded tour foods live on Foods.
        if app.segmentedControls.firstMatch.waitForExistence(timeout: 10) {
            app.segmentedControls.firstMatch.buttons["Foods"].tap()
        }
        _ = app.staticTexts["Recent"].waitForExistence(timeout: 10)
        scene("logsheet")
        // The row's Log button is unique to the sheet — the row text also
        // matches Today's log behind the sheet and isn't hittable there.
        // EXISTENCE is not hittability: the row sits well down a scrolling
        // list, and a tap on an off-screen element lands wherever its
        // frame happens to be — so the portion sheet never opened and the
        // "Log" the next line wants could not exist. The tour had been
        // failing here on an untouched tree (found 2026-08-23); the QA
        // walkthrough already scrolls its equivalent row into reach.
        // "Two eggs", the seeded library FOOD — not "Two eggs & toast",
        // which is not in the library at all: it is the name of a logged
        // HealthKit sample, so that row is HISTORY and has no portion
        // sheet behind it. Tapping it did nothing a screenshot could
        // show, and the tour had been failing here on an untouched tree
        // (found 2026-08-23). A food's + is the tap that opens the
        // portion sheet; a meal's is its long press, and history's is
        // neither.
        let eggsRow = app.buttons["Log Two eggs"].firstMatch
        for _ in 0..<6 where !eggsRow.isHittable { app.swipeUp() }
        XCTAssertTrue(eggsRow.isHittable, "The row to log has to be reachable")
        eggsRow.tap()
        let confirm = app.buttons["Log"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "The portion sheet opens")
        scene("portion", hold: 3)
        confirm.tap()
        // Logging closes the PORTION sheet; the Log sheet behind it stays
        // up, and its own dismiss is "Done". The tour carried on into
        // Today's stops regardless, running them against whatever was on
        // top — invisible until `switchTab` stopped tapping through
        // modals (2026-08-23).
        XCTAssertTrue(dismissModals(in: app), "The Log sheet closes after logging")

        Thread.sleep(forTimeInterval: 1.5)
        expandMealSections(in: app)
        let burrito = app.staticTexts["Chicken burrito"].firstMatch
        for _ in 0..<2 where !burrito.isHittable {
            app.swipeUp()
        }
        if burrito.isHittable {
            let start = burrito.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 120, dy: 0)))
            scene("swipe-edit", settle: 0.3, hold: 2.5)
            burrito.tap()
            Thread.sleep(forTimeInterval: 0.5)
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -120, dy: 0)))
            scene("swipe-delete", settle: 0.3, hold: 2)
            burrito.tap()
        }

        // The row drags can minimize the iOS 26 tab bar; scroll up first.
        app.swipeDown()
        switchTab(in: app, to: "Foods")
        scene("foods")

        switchTab(in: app, to: "Calendar")
        _ = calendarMonthCard(in: app).waitForExistence(timeout: 10)
        scene("calendar")
        calendarMonthCard(in: app).tap()
        scene("month", hold: 3.5)
        app.navigationBars.buttons.firstMatch.tap()

        switchTab(in: app, to: "Goal")
        scene("goal")
        app.swipeUp()
        scene("goal-trend", hold: 3)
        app.swipeDown()

        switchTab(in: app, to: "Today")
        app.buttons["Settings"].tap()
        _ = app.staticTexts["Reminders"].waitForExistence(timeout: 5)
        scene("settings", hold: 3.5)
        app.buttons["Done"].tap()
        scene("finale", hold: 3)

        let data = try JSONSerialization.data(withJSONObject: timings)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "scene-timings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// QA walkthrough (opt-in via TEST_RUNNER_QA=1): visits the states the
    /// showcase tour skips — empty days, no-match search, the forms and
    /// pickers, month edges — attaching a named screenshot per stop for
    /// visual review. Assertions are deliberately loose; the screenshots
    /// are the product. Erase the paired sims first.
    @MainActor
    func testQAWalkthrough() throws {
        guard ProcessInfo.processInfo.environment["QA"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_QA=1 to run the QA walkthrough")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--seed-sample-data"]
        if let sizeCategory = ProcessInfo.processInfo.environment["QA_TEXT_SIZE"] {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", sizeCategory,
            ]
        }
        // iPad pass: QA_ORIENTATION=landscape rotates before launch so
        // every stop is captured wide. Orientation persists on the sim
        // between runs, so default back to portrait explicitly.
        XCUIDevice.shared.orientation =
            ProcessInfo.processInfo.environment["QA_ORIENTATION"] == "landscape"
                ? .landscapeLeft : .portrait

        /// `expect` names something only the intended screen has. A
        /// screenshot filed under the wrong name is worse than a missing
        /// one — it is reviewed as evidence — and that is exactly what
        /// this tour produced on 2026-08-23: a stuck Add Food form was
        /// captured as `qa-goal`, `qa-food-form-edit` and
        /// `qa-meal-form-edit`, and the run passed. The failure is
        /// RECORDED rather than fatal (`continueAfterFailure` is true
        /// here), so the tour still finishes and files every other stop
        /// — but the run goes red and names the stop that lied.
        func shot(_ name: String, settle: TimeInterval = 0.8, expect: String? = nil) {
            Thread.sleep(forTimeInterval: settle)
            var name = name
            if let expect, !app.descendants(matching: .any)[expect].exists {
                XCTFail("qa-\(name) captured the wrong screen — no \"\(expect)\" on it.")
                name += "-WRONG"
            }
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "qa-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func tab(_ name: String) {
            // Dismiss FIRST, and verify it worked. The bare swipeDown
            // this replaces did not close a sheet with a focused search
            // field, and `switchTab` then tapped a tab button that
            // exists but is covered — landing on the sheet.
            dismissModals(in: app)
            switchTab(in: app, to: name)
        }
        // The walkthrough must always finish — a missed optional control
        // skips its shots rather than failing the whole capture.
        @discardableResult
        func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
            guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
            element.tap()
            return true
        }

        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)
        switchTab(in: app, to: "Foods")
        switchTab(in: app, to: "Today")
        _ = app.buttons.matching(collapsedSectionPredicate).firstMatch.waitForExistence(timeout: 20)
        shot("today-collapsed")
        expandMealSections(in: app)
        shot("today-expanded")

        // Past days: seeded day-3 has entries; day-5 is empty.
        for _ in 0..<3 { app.buttons["Previous day"].tap() }
        shot("past-day-with-data")
        detailsLink(in: app).tap()
        shot("nutrition-past-day")
        app.navigationBars["Details"].buttons.firstMatch.tap()
        for _ in 0..<2 { app.buttons["Previous day"].tap() }
        shot("past-day-empty")
        detailsLink(in: app).tap()
        shot("nutrition-empty-day")
        app.navigationBars["Details"].buttons.firstMatch.tap()

        // Back to today via chevrons (the title menu isn't reliably
        // hittable from tests; the jump sheet is a stock DatePicker).
        for _ in 0..<5 { app.buttons["Next day"].tap() }

        // Log sheet: kinds, no-match search, portion sheet.
        switchTab(in: app, to: "Add")  // the corner + pill opens the Log sheet
        // Favorites opens by default; start the scope tour from Foods.
        if app.segmentedControls.firstMatch.waitForExistence(timeout: 10) {
            app.segmentedControls.firstMatch.buttons["Foods"].tap()
        }
        _ = app.staticTexts["Recent"].waitForExistence(timeout: 10)
        shot("logsheet-all")
        // At accessibility sizes the kind picker is a menu, not segments;
        // segment shots only make sense in the normal pass.
        if app.segmentedControls.count > 0 {
            let kindPicker = app.segmentedControls.firstMatch
            kindPicker.buttons["Meals"].tap()
            shot("logsheet-meals")
            kindPicker.buttons["Favorites"].tap()
            shot("logsheet-favorites")
            kindPicker.buttons["Foods"].tap()
            shot("logsheet-foods")
        }
        let logShakeRow = app.buttons["Log Protein shake"].firstMatch
        for _ in 0..<3 where !logShakeRow.isHittable {
            app.swipeUp()
        }
        if tapIfExists(logShakeRow) {
            shot("portion-sheet")
            // Two "Cancel" buttons exist while the portion sheet is up:
            // the portion sheet's own (enabled) and the Log sheet's
            // (disabled underneath it, via `recedesWithSheet`). Filter
            // for the ENABLED one instead of guessing at tree order — a
            // `.last` pick broke the day the Log sheet's Cancel moved
            // between chrome and content (2026-09-16).
            app.buttons.matching(identifier: "Cancel").allElementsBoundByIndex
                .first(where: \.isEnabled)?.tap()
        }
        // Search state last; the sheet gets torn down by relaunching.
        let searchField = logSheetField(in: app)
        if searchField.waitForExistence(timeout: 5) {
            searchField.tap()
            searchField.typeText("zzzz")
            shot("logsheet-no-matches", settle: 1.2)
        }
        // Keep the text-size override; drop only the seed flag so the
        // relaunch doesn't double the sample data.
        app.launchArguments.removeAll { $0 == "--seed-sample-data" }
        app.launch()

        // Foods: scopes, filter menu, add menu, forms.
        tab("Foods")
        shot("foods", expect: "Filter by category")
        // Scope shots mirror the Log sheet's; segments only exist in
        // the normal-size pass (a menu at accessibility sizes).
        if app.segmentedControls.count > 0 {
            let scopeBar = app.segmentedControls.firstMatch
            scopeBar.buttons["Meals"].tap()
            shot("foods-meals")
            scopeBar.buttons["Favorites"].tap()
            shot("foods-favorites")
            scopeBar.buttons["Foods"].tap()
        }
        if tapIfExists(app.buttons["Filter by category"]) {
            shot("foods-filter-menu")
            if tapIfExists(app.buttons["Breakfast"].firstMatch) {
                shot("foods-filtered-breakfast")
                tapIfExists(app.buttons["Filter by category"])
                tapIfExists(app.buttons["All"].firstMatch)
            }
        }
        switchTab(in: app, to: "Add")
        if app.buttons["Add Food"].waitForExistence(timeout: 5) {
            shot("foods-add-menu")
            if tapIfExists(app.buttons["Add Food"]) {
                shot("food-form-new", settle: 1.2)
                // The describe field now carries the inline database
                // search too (2026-08-29) — the dedicated bottom
                // "Search OpenFoodFacts" field it used to live under is
                // retired, so this walks the SAME shot through the new
                // door.
                let dbField = app.textFields["Describe food or meal"]
                if tapIfExists(dbField) {
                    dbField.typeText("granola")
                    shot("food-form-db-search", settle: 1.2)
                }
                // Relaunching is the one dismissal that cannot miss —
                // the tour already uses it a few stops up for the Log
                // sheet's focused search, and keeping it here too costs
                // nothing even now that the field is a plain TextField
                // rather than the `.searchable` bar whose X-glyph
                // dismissal used to make a Cancel tap miss (2026-08-23).
                // The seed flag is already gone from launchArguments by
                // here, so this does not re-seed.
                app.launch()
            }
        }
        // The edit shots need the Foods LIST back (the add-food flow
        // above leaves its sheet up) and the right scope per item: a
        // food shows in Foods, a meal ONLY in Meals/Favorites. Dismiss
        // any lingering sheet until the scope bar reappears, then pick
        // the scope. The meal shot silently skipped once Favorites (not
        // "All") became the default and the tour ran its scope walk from
        // Foods — hence the explicit Meals switch.
        // The relaunch above lands wherever the app restores to, so come
        // back to Foods explicitly. This used to be a loop asking whether
        // the scope bar EXISTED — which a sheet leaves true the whole
        // time it covers it, so the loop exited having dismissed
        // nothing and both edit shots below silently skipped for an
        // unknown stretch (found 2026-08-23). `tab` verifies now.
        tab("Foods")
        // A library row is a Button labeled by its name
        // (accessibilityAddTraits(.isButton)) — NOT a staticText, which
        // is why the old app.staticTexts[name] never matched and both
        // edit shots silently skipped. ("Log <name>" is the separate +
        // button, unaffected by the exact-label match.)
        // EXISTENCE is not hittability: the Foods scope bar is a list
        // ROW, and the dismissal loop above swipes down, which can leave
        // it scrolled under the translucent nav bar — present in the
        // hierarchy, untappable. Scroll it back into reach first.
        scopeTap(in: app, "Foods")
        if tapIfExists(app.buttons["Protein shake"].firstMatch, timeout: 5) {
            shot("food-form-edit", settle: 1.2, expect: "Edit Food")
            tapIfExists(app.buttons["Cancel"].firstMatch)
        }
        scopeTap(in: app, "Meals")
        if tapIfExists(app.buttons["Chicken & rice"].firstMatch, timeout: 5) {
            shot("meal-form-edit", settle: 1.2, expect: "Edit Meal")
            tapIfExists(app.buttons["Cancel"].firstMatch)
        }

        // Goal: the top, the budget rows, and the focused-keyboard state.
        tab("Goal")
        // NOT "Daily budget" — the budget is below the fold and a Form
        // does not render a row until it is scrolled near, so naming one
        // here fails on the RIGHT screen. An expectation has to be
        // something the capture can actually contain.
        shot("goal", expect: "Current weight")
        for _ in 0..<8 where !app.staticTexts["Daily budget"].exists { app.swipeUp() }
        shot("goal-budget", expect: "Daily budget")
        if tapIfExists(app.buttons["How your budget is calculated"]) {
            // The group unrolls BELOW the fold, so its rows are not
            // rendered — and therefore do not exist — until scrolled to.
            // Same lazy-Form trap as the stop above, one level in.
            for _ in 0..<6 where !app.staticTexts["Deficit needed"].exists { app.swipeUp() }
            shot("goal-budget-calculated", settle: 1.0, expect: "Deficit needed")
        }
        // Back to the top for the weight field, and out via Cancel —
        // Goal's toolbar is Cancel ↔ Save, so the "Done" this used to
        // tap has not existed since 2026-08-18 and the keyboard stayed
        // up into the next stop. Scroll UNTIL the field is hittable,
        // not a fixed swipe count: the count silently depended on the
        // Form's exact scroll geometry and broke the moment
        // `flushTopContent()` changed it (2026-09-16).
        for _ in 0..<10 where !app.textFields.firstMatch.isHittable { app.swipeDown() }
        if tapIfExists(app.textFields.firstMatch) {
            shot("goal-keyboard")
            tapIfExists(app.buttons["Cancel"].firstMatch, timeout: 2)
        }

        // Calendar: previous month (little data), day picking, month detail.
        tab("Calendar")
        shot("calendar", expect: "Previous month")
        if tapIfExists(app.buttons["Previous month"]) {
            shot("calendar-previous-month")
        }
        if tapIfExists(calendarMonthCard(in: app)) {
            shot("month-detail-sparse", settle: 1.0)
            tapIfExists(app.navigationBars.buttons.firstMatch)
        }
        tapIfExists(app.buttons["Next month"])

        // Settings: pushed icon picker + data section.
        tab("Today")
        if tapIfExists(app.buttons["Settings"]) {
            _ = app.staticTexts["Reminders"].waitForExistence(timeout: 5)
            shot("settings-top")
            // Appearance lives behind its own row now (the declutter):
            // gauges toggle + food icon picker moved into the subscreen.
            if tapIfExists(app.staticTexts["Appearance"]) {
                // Leave gauges ON so today-final captures the ring + fills.
                // Coordinate tap at the row's trailing edge: the switch
                // query alone failed to register taps on this toggle.
                var gauges = app.switches["Progress gauges"].firstMatch
                if !gauges.waitForExistence(timeout: 2) {
                    gauges = app.descendants(matching: .any)
                        .matching(NSPredicate(format: "label == 'Progress gauges'")).firstMatch
                    _ = gauges.waitForExistence(timeout: 2)
                }
                if gauges.exists {
                    gauges.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
                }
                shot("settings-appearance", settle: 0.5)
                if tapIfExists(app.staticTexts["Food icon"]) {
                    shot("settings-food-icon-picker")
                    tapIfExists(app.navigationBars.buttons.firstMatch)
                }
                tapIfExists(app.navigationBars.buttons.firstMatch)
            }
            // Hide the water metric via the second slot's None option
            // (the slots live behind the Metrics row now): today-final
            // shows sodium only.
            if tapIfExists(app.staticTexts["Metrics"]) {
                let metricRows = app.staticTexts.matching(identifier: "Metric")
                if metricRows.count >= 2 {
                    metricRows.element(boundBy: 1).tap()
                    if tapIfExists(app.staticTexts["None"]) {
                        shot("settings-metric-none", settle: 0.5)
                    }
                }
                tapIfExists(app.navigationBars.buttons.firstMatch)
            }
            shot("settings-gauges-on", settle: 0.5)
            app.swipeUp()
            shot("settings-bottom")
            tapIfExists(app.buttons["Done"])
        }
        shot("today-final")
    }

    /// Stale-sim tripwire for the seeded flow: the hydration row is the
    /// cleanest canary because every --seed-sample-data launch adds
    /// exactly 24 oz of water, so anything but "24 / …" up front means
    /// the paired sims carry samples from an earlier run and every
    /// hardcoded total downstream is off. Fails with the fix (erase both
    /// sims — they share Health data) instead of a cryptic timeout later.
    @MainActor
    private func assertFreshlySeededState(in app: XCUIApplication) {
        let hydration = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'oz water'")
        ).firstMatch
        // No hydration row at all is a different failure — leave it to
        // the flow's own assertions, which describe what's missing.
        guard hydration.waitForExistence(timeout: 20) else { return }
        if !hydration.label.hasPrefix("24 /") {
            // Abort outright — every assertion past this point would just
            // time out against the stale totals.
            continueAfterFailure = false
            XCTFail(
                """
                Stale simulator Health data: the hydration row reads \
                "\(hydration.label)" but a fresh seed yields "24 / 64 oz water". \
                --seed-sample-data ADDS samples on every launch — erase BOTH \
                paired simulators (xcrun simctl erase <phone-udid> <watch-udid>; \
                they share Health data) and rerun. See CLAUDE.md.
                """
            )
        }
    }

    /// Today's meal-slot sections start collapsed; their header buttons say
    /// so in the accessibility label ("Lunch, 680 kcal, collapsed").
    private var collapsedSectionPredicate: NSPredicate {
        NSPredicate(format: "label CONTAINS 'collapsed'")
    }

    /// Expand every collapsed meal section so entry rows are hittable.
    /// Headers at the screen's bottom edge sit under the corner Add pill
    /// (and the tab bar) — scroll them clear before tapping.
    @MainActor
    private func expandMealSections(in app: XCUIApplication) {
        let collapsed = app.buttons.matching(collapsedSectionPredicate)
        for _ in 0..<6 {
            guard collapsed.count > 0 else { return }
            let target = collapsed.firstMatch
            if !target.isHittable {
                app.swipeUp()
                guard target.isHittable else { continue }
            }
            target.tap()
        }
    }

    /// A cold open paints the LAST load, not a blank that fills in a beat
    /// later (`GoalPrime`, `CalendarPrime` — `TodayPrime`'s siblings; the
    /// user, 2026-09-17: Goal "populating is abrupt"). Two launches,
    /// because a prime is only ever written from a Health answer: the
    /// first visits both tabs and lets them load, the second holds both
    /// loads open 4 s and looks at what is drawn INSIDE that window.
    /// Without a prime, Goal is a placeholder row there (no "From Apple
    /// Health") and every past day on the Calendar reads "not tracked" —
    /// so both checks fail on a build that primes nothing.
    @MainActor
    func testColdOpenPaintsTheLastLoad() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)
        let judgedDay = app.descendants(matching: .any).matching(NSPredicate(
            format: "label ENDSWITH 'goal met' OR label ENDSWITH 'goal not met'"
        )).firstMatch

        switchTab(in: app, to: "Goal")
        XCTAssertTrue(app.staticTexts["From Apple Health"].waitForExistence(timeout: 15),
                      "First launch: Goal loads the seeded weigh-in")
        switchTab(in: app, to: "Calendar")
        XCTAssertTrue(judgedDay.waitForExistence(timeout: 15),
                      "First launch: the Calendar judges at least one seeded day")
        // The day card's sodium slot — a combined element reading
        // "1,550 mg", or "—" while it has nothing.
        let sodiumSlot = app.descendants(matching: .any).matching(NSPredicate(
            format: "label ENDSWITH ' mg'"
        )).firstMatch
        XCTAssertTrue(sodiumSlot.waitForExistence(timeout: 15),
                      "First launch: the day card reads the seeded sodium")
        // The primes are written off the main actor after each load.
        Thread.sleep(forTimeInterval: 1.5)
        app.terminate()

        app.launchArguments = ["--seed-sample-data", "--slow-goal-load", "--slow-calendar-load"]
        app.launch()
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Goal")
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3), "Goal's toolbar should be up")
        XCTAssertTrue(app.staticTexts["From Apple Health"].exists,
                      "Goal draws the last load's weight while this launch's load is still held open")
        XCTAssertFalse(app.buttons["Save"].isEnabled,
                       "Nothing saves against a prime — Save waits for Health")
        attachShot(named: "goal-cold-open-primed", settle: 0)

        switchTab(in: app, to: "Calendar")
        XCTAssertTrue(app.buttons["Previous month"].waitForExistence(timeout: 3), "Calendar should be up")
        XCTAssertTrue(judgedDay.exists,
                      "The Calendar re-judges the last refresh's days while this launch's refresh is held open")
        XCTAssertTrue(sodiumSlot.exists,
                      "Today's day card shows its tracked slots too, not a dash, while its read is held open")
        attachShot(named: "calendar-cold-open-primed", settle: 0)
    }

    /// The first visit to Goal in a process must not flash a Cancel
    /// button. The stored goal used to reach the form only AFTER the
    /// awaited Health load, so until it landed the form held its
    /// built-in defaults beside a stored goal it didn't match — it read
    /// as edited, and a Cancel pill appeared left of Save and vanished
    /// (the user, 2026-09-17; ~6 frames on the sim, frame-counted).
    /// `--slow-goal-load` holds that load open for 4 s, so the window is
    /// wide enough to query inside: against the old ordering Cancel is
    /// up for all of it and the field is still empty, and both checks
    /// below fail. Asserts the FIELD too — "no Cancel" alone would pass
    /// on a build that merely hid the button.
    @MainActor
    func testGoalFirstVisitShowsNoCancel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-sample-data", "--slow-goal-load"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Goal")
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3), "Goal's toolbar should be up")
        // Inside the held-open load: the form already IS the stored goal.
        XCTAssertFalse(app.buttons["Cancel"].exists,
                       "No Cancel on an untouched Goal, even before Health answers")
        // A field that HOLDS something — an empty one reports its "0"
        // placeholder as its value. Not `textFields.firstMatch`: that was
        // the manual current-weight field the first time this ran, shown
        // because Health hadn't answered — a second first-visit flash,
        // asserted gone below.
        let filled = app.textFields.matching(
            NSPredicate(format: "value != '0' AND value != ''")
        ).firstMatch
        XCTAssertTrue(filled.exists,
                      "The stored target fills its field before the load lands")
        XCTAssertFalse(save.isEnabled, "Nothing to save on an untouched Goal")
        XCTAssertFalse(
            app.staticTexts["No weight in Apple Health yet — enter it here."].exists,
            "Not asked yet is not \"no weight\" — no manual field before Health answers"
        )
        attachShot(named: "goal-first-visit-loading", settle: 0)
        // And once the held load lands, still no Cancel: nothing about
        // Health answering is an edit.
        XCTAssertTrue(app.staticTexts["From Apple Health"].waitForExistence(timeout: 10),
                      "The seeded weigh-in arrives once the load lands")
        XCTAssertFalse(app.buttons["Cancel"].exists, "No Cancel after the load lands either")
        attachShot(named: "goal-first-visit-loaded", settle: 0.5)
    }

    /// The decimal pad has no return key, so the weight fields need a way
    /// out that isn't the return key. Goal's toolbar is Cancel ↔ Save —
    /// the styled principal "Done" was removed because it read as
    /// belonging to nothing — and Cancel is what appears on FOCUS ALONE
    /// (`hasEdits || focusedField != nil`), then discards and drops the
    /// keyboard. This test asserted the deleted Done until 2026-08-18;
    /// it had been failing on that button ever since, which is why the
    /// suite's "Connect Hardware Keyboard" suspect was a red herring —
    /// the keyboard assertion above it always passed.
    @MainActor
    func testGoalCancelDismissesKeyboard() throws {
        let app = XCUIApplication()
        app.launch()
        skipOnboardingIfPresent(in: app)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Goal")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Weight field should exist")

        // Focus is what summons Cancel, so it must be absent first — an
        // "is it there?" probe on a button that was always there would
        // pass while guarding nothing.
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 3),
                      "Cancel should be absent on an unedited, unfocused Goal")

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard should appear")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Focus alone should summon Cancel")
        cancel.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Keyboard should dismiss")
    }

    /// Maintenance mode end to end on screen: flip the Goal picker to
    /// Maintain, save, and confirm Today's card reads budget (not
    /// deficit). Opt-in capture via TEST_RUNNER_MAINTENANCE=1 — it
    /// mutates the goal, so keep it out of the default suite.
    @MainActor
    func testMaintenanceMode() throws {
        guard ProcessInfo.processInfo.environment["MAINTENANCE"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_MAINTENANCE=1 to run the maintenance-mode capture")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--seed-sample-data"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        func shot(_ name: String) {
            Thread.sleep(forTimeInterval: 0.8)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "maintenance-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        switchTab(in: app, to: "Goal")
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Goal mode picker should exist")
        picker.buttons["Maintain"].tap()
        shot("goal-maintain")
        // Target section hides; the budget stands without a deficit.
        // The old "Calorie budget" section became this disclosure on
        // 2026-08-10 — and the deficit row moved INSIDE it, so absence
        // has to be checked with the group OPEN or it passes merely
        // because the group is shut.
        let howSet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'How your budget is calculated'")).firstMatch
        // Below the fold, and a Form's rows don't exist in the tree until
        // scrolled near — waiting on one that isn't there just times out.
        XCTAssertTrue(scroll(app, until: howSet), "The budget explainer is reachable")
        // Open it and PROVE it opened before asserting a row is absent:
        // a shut group makes every absence trivially true.
        //
        // Decide open-vs-shut on `Based on`, the group's FIRST row, and
        // only then scroll for the rest. A row further down is not
        // rendered until it is scrolled near, so "it isn't there" looks
        // identical whether the group is closed or merely below the
        // fold — and tapping on that reading CLOSES a group that was
        // already open. The Budget section going from six rows to one
        // (2026-08-23) moved everything up far enough to make that
        // coin-flip land the wrong way.
        // The mechanism caption is the target because it is inside the
        // group in BOTH modes, and it sits BELOW where `Deficit needed`
        // would be — so reaching it means the absence checked next was
        // scrolled past, not merely unrendered. It took over from
        // `Resting burn, full day` when the explainer was cut back to
        // the recipe (2026-08-24): in maintenance the group now holds
        // one row and its captions, and that row sits ABOVE the deficit
        // row's place, which would have made the absence below it
        // trivially true again.
        // Passed as an ARGUMENT, never inlined into the format string:
        // captions change, and a quoted literal terminates on the first
        // apostrophe one of them contains — throwing at runtime rather
        // than failing to compile.
        let mechanismCaption = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Resting plus active energy")
        ).firstMatch
        XCTAssertTrue(
            revealInBudgetExplainer(in: app, header: howSet, row: mechanismCaption),
            "The group opens")
        XCTAssertFalse(app.staticTexts["Deficit needed"].exists, "No deficit row in maintenance")
        let save = app.buttons["Save"]
        XCTAssertTrue(save.isEnabled, "Mode change should enable Save")
        save.tap()

        switchTab(in: app, to: "Today")
        // "Today's budget" — Goal's row owns "Daily budget" and holds the
        // average-day figure, so this card cannot share the phrase.
        let budgetTitle = app.staticTexts["Today's budget"]
        XCTAssertTrue(budgetTitle.waitForExistence(timeout: 10),
                      "Today card should read Today's budget in maintenance")
        XCTAssertFalse(app.staticTexts["Daily budget"].exists,
                       "\"Daily budget\" belongs to Goal, not Today")
        shot("today-maintain")

        // Back to lose so the sim isn't left in maintenance.
        switchTab(in: app, to: "Goal")
        // The budget check above scrolled this screen down and a tab
        // switch preserves that, so the mode picker is off the top.
        for _ in 0..<6 where !picker.exists { app.swipeDown() }
        picker.buttons["Lose Weight"].tap()
        // "Deficit needed" moved INSIDE the disclosure on 2026-08-10, so
        // scrolling alone can never reveal it — the group has to be open.
        let deficitRow = app.staticTexts["Deficit needed"]
        XCTAssertTrue(
            revealInBudgetExplainer(in: app, header: howSet, row: deficitRow),
            "Deficit row returns in lose mode")
        app.buttons["Save"].tap()
    }

    /// Holding the corner + logs one water serving directly; the tap's
    /// add flow must NOT also fire (the recognizer cancels the pill's
    /// touch, or a hold would log water AND open the sheet).
    @MainActor
    func testAddPillLongPressLogsWater() throws {
        let app = XCUIApplication()
        app.launch()
        // A fresh install shows onboarding INSTEAD of the tabs — no
        // pill exists until it's skipped.
        skipOnboardingIfPresent(in: app)
        grantHealthAccess(in: app, timeout: 30)

        let phonePill = app.tabBars.buttons["Add"]
        let pill = phonePill.waitForExistence(timeout: 5) && phonePill.isHittable
            ? phonePill : app.buttons["Add"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "Corner Add pill")
        pill.press(forDuration: 1.0)

        let toast = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Logged' AND label CONTAINS 'water'")
        ).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 8), "Water toast after long press")
        XCTAssertFalse(app.buttons["Done"].exists, "Log sheet stayed closed")
    }

    /// Reset All → restore round trip (opt-in via TEST_RUNNER_RESET_ROUNDTRIP=1;
    /// destroys the sim install's data): seed, flip the goal to Maintain,
    /// grow the water serving, Back Up Now, Reset All, verify stock, then
    /// relaunch with --import-latest-backup and verify the library, the
    /// maintain mode (the round-trip's newest passenger), and water came
    /// back — and that the settings outside the export stayed at stock.
    @MainActor
    func testResetAllRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["RESET_ROUNDTRIP"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_RESET_ROUNDTRIP=1 to run the reset round trip")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--seed-sample-data"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        // A goal state the old export format couldn't carry.
        switchTab(in: app, to: "Goal")
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Goal mode picker")
        picker.buttons["Maintain"].tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5) && save.isEnabled, "Save after mode change")
        save.tap()

        // A water setting the export DOES carry: serving 12 → 14 oz.
        switchTab(in: app, to: "Today")
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "Settings gear")
        gear.tap()
        // The serving stepper lives behind the Water row now.
        let waterRow = app.staticTexts["Water"].firstMatch
        XCTAssertTrue(waterRow.waitForExistence(timeout: 5), "Water row")
        waterRow.tap()
        let servingStepper = app.steppers.matching(
            NSPredicate(format: "label CONTAINS[c] 'Serving size'")
        ).firstMatch
        XCTAssertTrue(servingStepper.waitForExistence(timeout: 5), "Water serving stepper")
        servingStepper.buttons["Increment"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        // Snapshot everything into Documents/Backups.
        let backUp = app.buttons["Back Up Now"]
        for _ in 0..<6 where !backUp.exists {
            app.swipeUp()
        }
        XCTAssertTrue(backUp.waitForExistence(timeout: 5), "Back Up Now")
        backUp.tap()
        XCTAssertTrue(
            app.staticTexts["Backed up ✓"].waitForExistence(timeout: 10),
            "Backup confirmation toast"
        )

        // Reset All, behind its centered confirm.
        let resetAll = app.buttons["Reset All"]
        for _ in 0..<6 where !resetAll.exists {
            app.swipeUp()
        }
        XCTAssertTrue(resetAll.waitForExistence(timeout: 5), "Reset All row")
        resetAll.tap()
        let alert = app.alerts["Reset All?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Reset confirm alert")
        alert.buttons["Reset"].tap()
        XCTAssertTrue(
            app.staticTexts["Onigiri reset to stock"].waitForExistence(timeout: 10),
            "Reset toast"
        )
        app.buttons["Done"].tap()

        // Stock: the seeded library is gone.
        switchTab(in: app, to: "Foods")
        // Any-element label match, NOT `app.staticTexts`: a library row
        // carries `.isButton`, so its text is never exposed as a
        // StaticText and that query can't match whatever the app does.
        // Which made the assertion below pass vacuously — "library empty
        // after reset" was true of an app that had reset nothing — while
        // its twin after the restore could only ever fail. Both went
        // unnoticed because this test is opt-in (audit, 2026-08-17).
        // `testFoodsSearchSurvivesScroll` had the right shape all along.
        let seededFood = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Chicken breast'")
        ).firstMatch
        XCTAssertFalse(seededFood.waitForExistence(timeout: 3), "Library empty after reset")

        // Relaunch restoring the backup (no seeder — what returns is
        // what the file carried).
        app.terminate()
        app.launchArguments = ["--import-latest-backup"]
        app.launch()
        skipOnboardingIfPresent(in: app)

        switchTab(in: app, to: "Foods")
        XCTAssertTrue(seededFood.waitForExistence(timeout: 10), "Library restored from backup")

        switchTab(in: app, to: "Goal")
        let restoredPicker = app.segmentedControls.firstMatch
        XCTAssertTrue(restoredPicker.waitForExistence(timeout: 10), "Goal picker after restore")
        XCTAssertTrue(
            restoredPicker.buttons["Maintain"].isSelected,
            "Maintain mode survives the round trip"
        )

        switchTab(in: app, to: "Today")
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        let restoredWaterRow = app.staticTexts["Water"].firstMatch
        XCTAssertTrue(restoredWaterRow.waitForExistence(timeout: 5), "Water row after restore")
        restoredWaterRow.tap()
        let restoredServing = app.steppers.matching(
            NSPredicate(format: "label CONTAINS[c] 'Serving size' AND label CONTAINS '14'")
        ).firstMatch
        XCTAssertTrue(restoredServing.waitForExistence(timeout: 5), "Water serving restored to 14 oz")
        app.navigationBars.buttons.firstMatch.tap()
        // Settings OUTSIDE the export stay stock: the text-search source
        // reads its default again — the Online Database row summarizes it
        // from the main screen.
        let onlineRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Online Database' AND label CONTAINS[c] 'OpenFoodFacts'")
        ).firstMatch
        XCTAssertTrue(onlineRow.waitForExistence(timeout: 5), "Search source back at default")
        app.buttons["Done"].tap()
    }

    /// Regression: the Foods search field must survive a scroll. After
    /// the 1.8.1 scope-bar inset it collapsed on scroll-down and never
    /// came back (the same desync class as the old GeometryReader bug).
    @MainActor
    func testFoodsSearchSurvivesScroll() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        // Big library: the drawer only collapses when the list truly
        // scrolls; the four-item seed can't reproduce the bug.
        app.launchArguments = ["--seed-sample-data", "--seed-big-library"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Foods")
        // The precondition, asserted: without the fillers the list never
        // scrolls, the drawer never has a reason to collapse, and every
        // check below passes while guarding nothing — which is what this
        // test did on any previously-seeded sim until 2026-09-17, when
        // `--seed-big-library` only filled an EMPTY store.
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(
                format: "label CONTAINS 'Filler food'"
            )).firstMatch.waitForExistence(timeout: 10),
            "Big library seeded"
        )
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field at rest")
        attachShot(named: "foods-scroll-rest")

        // The drawer is pinned (.always): scrolling must not hide it —
        // the collapsing drawer re-expanded BLANK over the scope bar's
        // safeAreaInset (element present, field invisible).
        app.swipeUp()
        app.swipeUp()
        attachShot(named: "foods-scrolled-down")
        // .exists alone can't catch the bug this guards: the buggy state
        // re-expands the drawer BLANK — the field is still present in
        // the tree, just not rendering, so .exists stayed true through
        // it (health-check audit, 2026-09-14). isHittable is what an
        // invisible-but-present field fails.
        XCTAssertTrue(search.isHittable, "Pinned search field visible mid-scroll")
        app.swipeDown()
        app.swipeDown()
        attachShot(named: "foods-scrolled-back")
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Search field back after scroll")
        XCTAssertTrue(search.isHittable, "Search field hittable after scroll")

        // And it still works: activating and typing filters the list.
        search.tap()
        search.typeText("egg")
        attachShot(named: "foods-search-egg", settle: 1.0)
        // Any-element label match: the rows carry an .isButton trait, so
        // their texts aren't exposed as StaticTexts.
        let match = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Two eggs'")
        ).firstMatch
        XCTAssertTrue(
            match.waitForExistence(timeout: 5),
            "Search filters after the scroll round-trip"
        )
    }

    /// A sheet round trip must leave its host's subtree alone
    /// (`RecedesBehindSheet`, Style.swift). Scroll the Foods list well
    /// past its top, open a row's edit form, Cancel — and the row is
    /// still where it was. The 2026-09-15 blur BRANCH (`if isPresenting
    /// { content.blur } else { content }`) rebuilt the whole host on
    /// every present AND dismiss: this list snapped back to its top,
    /// Today's NavigationStack was re-created under the closing Log
    /// sheet, and Cancel/Done in both dialogs read as sluggish on the
    /// phone (the user, 2026-09-16; `plans/PLAN-sheet-dismiss-latency.md`).
    /// Fails against that branch; passes on the overlay form. Asserts
    /// hittability and the row's frame, never existence — a reset list
    /// still "has" the row.
    @MainActor
    func testSheetRoundTripKeepsFoodsScroll() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        // Big library: the four-item seed never scrolls.
        app.launchArguments = ["--seed-sample-data", "--seed-big-library"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Foods")
        // Rows, not their "Log …" + buttons, which carry the same name.
        let rows = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS 'Filler food' AND NOT (label BEGINSWITH 'Log ')"
        ))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "Big library seeded")
        // The list's top is whichever filler leads at rest (the Recent
        // sort puts the fillers, created last, ahead of the four named
        // seeds — which sit 30 rows down, virtualized out of the tree).
        let topLabel = rows.firstMatch.label
        let topRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", topLabel)
        ).firstMatch
        XCTAssertTrue(topRow.isHittable, "Top row on screen at rest")

        // Scroll until the list's top is off screen, then anchor on a
        // row sitting mid-screen, clear of the drawer and the tab bar.
        var anchor: XCUIElement?
        for _ in 0..<6 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.6)
            guard !topRow.isHittable else { continue }
            let screenMidY = app.frame.midY
            anchor = rows.allElementsBoundByIndex.first {
                $0.isHittable && abs($0.frame.midY - screenMidY) < 150
            }
            if anchor != nil { break }
        }
        let row = try XCTUnwrap(anchor, "A filler row mid-screen with the list's top scrolled away")
        let label = row.label
        let yBefore = row.frame.minY
        attachShot(named: "foods-scrolled-before-sheet")

        // The row itself (not its +) opens the edit form.
        row.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Edit form opened")
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5), "Edit form shows the Name field")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 10), "Edit form dismissed")
        attachShot(named: "foods-scrolled-after-sheet", settle: 1.0)

        let after = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 5), "Row still in the tree after the round trip")
        XCTAssertTrue(after.isHittable, "Row still on screen after the sheet round trip")
        XCTAssertEqual(after.frame.minY, yBefore, accuracy: 4,
                       "List kept its scroll offset across the sheet round trip")
        XCTAssertFalse(topRow.isHittable, "List did not snap back to its top")
    }

    /// Barcode → OpenFoodFacts lookup prefills the food form. Uses the
    /// manual-entry fallback (no camera in the simulator) and live network.
    @MainActor
    func testBarcodeLookupPrefillsForm() throws {
        let app = XCUIApplication()
        // SEEDED, and not for the library: `DebugSeeder` is what flips
        // `onlineLookups` on ("the off-by-default privacy stance would
        // skip all of it, so seeded runs opt in" — barcode routes are
        // named in that comment). Unseeded, "Set Up Later" leaves
        // lookups off and Look Up can never reach OpenFoodFacts, so the
        // form never opens. The test passed for as long as it ran on a
        // sim some earlier seeded run had already opted in; erasing the
        // sim took that away (2026-08-18).
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        // Fresh sims land on onboarding (no tab bar) — this test used
        // to depend on an already-onboarded device state.
        skipOnboardingIfPresent(in: app)
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        // The LOG SHEET's scan row. This test used to tap a scan row on
        // the Foods tab; the entry doors left that screen on 2026-08-02
        // (FoodsView: "this is the LIBRARY screen, and the + already
        // opens an Add Food form that carries the very same two doors"),
        // so the row it looked for had not existed for a fortnight.
        // The door bar (`EntryDoorBar`) renders in exactly two places —
        // the Log sheet and a blank food form — and the Add tab IS the Log
        // sheet (`Tab("Add" …, value: .log)`), which keeps the intent
        // the original comment named: an unknown barcode goes straight
        // to the prefilled form, no trip through a chooser.
        switchTab(in: app, to: "Add")
        let scan = scanRow(in: app)
        XCTAssertTrue(scan.waitForExistence(timeout: 5), "Scan row in the Log sheet")
        scan.tap()

        let field = app.textFields["Barcode"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Manual barcode fallback field")
        field.tap()
        field.typeText("3017620422003")
        app.buttons["Look Up"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        let filled = expectation(
            for: NSPredicate(format: "value CONTAINS[c] 'nutella'"),
            evaluatedWith: nameField
        )
        wait(for: [filled], timeout: 25)
    }

    /// Label scan: the bundled FDA sample photo through the real Vision
    /// request and LabelParser into the form (opt-in via LABEL_SCAN=1).
    /// Photo pickers can't be driven headlessly, so --label-scan-sample
    /// surfaces a sample-photo row in the Scan Label sheet; everything
    /// after the pick — OCR, parse, prefill funnel — runs live.
    @MainActor
    func testLabelScanPrefillsForm() throws {
        guard ProcessInfo.processInfo.environment["LABEL_SCAN"] == "1" else {
            throw XCTSkip("Set LABEL_SCAN=1 to run the label-scan test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--label-scan-sample"]
        app.launch()
        skipOnboardingIfPresent(in: app)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Foods")
        // The corner + pill opens the Food-or-Meal chooser from Foods.
        switchTab(in: app, to: "Add")
        let addFood = app.buttons["Add Food"]
        XCTAssertTrue(addFood.waitForExistence(timeout: 5), "Add Food chooser option")
        addFood.tap()

        let scanLabel = scanRow(in: app)
        XCTAssertTrue(scanLabel.waitForExistence(timeout: 5), "Scan Label row in the food form")
        attachShot(named: "label-scan-form-row")
        scanLabel.tap()

        let sample = app.buttons["labelScanSample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5), "Sample photo row (needs --label-scan-sample)")
        attachShot(named: "label-scan-sheet")
        sample.tap()

        // The bundled FDA sample panel: 280 kcal, 1 cup (227g), 850 mg
        // sodium. The subscript matches identifier/label only, so filled
        // fields are found by VALUE predicate.
        func fieldWithValue(_ value: String) -> XCUIElement {
            app.textFields.matching(NSPredicate(format: "value == %@", value)).firstMatch
        }
        XCTAssertTrue(
            fieldWithValue("280").waitForExistence(timeout: 20),
            "Calories prefilled from the label")
        XCTAssertTrue(fieldWithValue("1 cup (227g)").exists, "Serving prefilled from the label")

        // The nutrient groups stay collapsed; their filled counts prove
        // the rest landed — 8 macros (sodium 850 among them: fat, sat,
        // cholesterol, sodium, carbs, fiber, sugar, protein) and
        // 3 minerals (calcium, iron, potassium). Expanding a
        // DisclosureGroup under XCUITest is unreliable; the counts
        // assert the same outcome.
        let macroCount = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '8 filled'")
        ).firstMatch
        XCTAssertTrue(macroCount.waitForExistence(timeout: 5), "8 macronutrients prefilled")
        let mineralCount = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '3 filled'")
        ).firstMatch
        XCTAssertTrue(mineralCount.exists, "3 minerals prefilled")
        attachShot(named: "label-scan-prefilled-form")

        // Leg 2 — the Log sheet's door (opened via the corner pill from
        // Today): same pipeline, but the handoff re-presents the single
        // sheet slot as the prefilled form (the unknown-barcode route),
        // and that form carries the log date back. Values scanned IN a
        // blank form make it dirty, so this Cancel confirms first — and
        // the form must be GONE before the next tap, or the form's own
        // door shadows the sheet's. (A Foods-tab leg sat between the two
        // until 2026-09-16, hunting the scan row Foods lost on 2026-08-02
        // — CLAUDE.md: "don't re-add a Foods-tab scan row". The doors
        // render in exactly two places and both legs are here.)
        func closeFoodForm() {
            app.buttons["Cancel"].firstMatch.tap()
            let discard = app.buttons["Discard"]
            if discard.waitForExistence(timeout: 3) { discard.tap() }
            // The form's NAME FIELD, not its title: the new-food form
            // has no title any more (it competed with the two confirm
            // buttons for the bar), and a navigationBars["New Food"]
            // probe would report "gone" instantly — passing while
            // guarding nothing.
            let formGone = expectation(
                for: NSPredicate(format: "exists == false"),
                evaluatedWith: app.textFields["Name"]
            )
            wait(for: [formGone], timeout: 5)
        }
        closeFoodForm()
        switchTab(in: app, to: "Today")
        switchTab(in: app, to: "Add")
        let logScanLabel = scanRow(in: app)
        XCTAssertTrue(logScanLabel.waitForExistence(timeout: 5), "Scan Label row on the Log sheet")
        attachShot(named: "label-scan-log-rows")
        logScanLabel.tap()
        XCTAssertTrue(sample.waitForExistence(timeout: 5), "Sample row from the Log sheet")
        sample.tap()
        XCTAssertTrue(
            fieldWithValue("280").waitForExistence(timeout: 20),
            "Log-sheet scan handed off to the prefilled form")
    }

    /// Foods-search-after-save probe (opt-in via SEARCH_PROBE=1, seeded):
    /// the user hit dead search taps after saving a food or meal — the
    /// iOS 26 drawer desync class. Saves a food through the form, then
    /// activates the Foods search and REQUIRES keyboard focus.
    @MainActor
    func testFoodsSearchAfterSave() throws {
        guard ProcessInfo.processInfo.environment["SEARCH_PROBE"] == "1" else {
            throw XCTSkip("Set SEARCH_PROBE=1 to run the search-after-save probe")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Foods")
        // The Add-pill path — the one that wedged the drawer: the pill
        // rides the search-role tab slot, and the selection bounce used
        // to abort its activation mid-transition. (The edit-path save
        // never broke it; verified while isolating.)
        switchTab(in: app, to: "Add")
        let addFood = app.buttons["Add Food"]
        XCTAssertTrue(addFood.waitForExistence(timeout: 5), "Add Food chooser option")
        addFood.tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Probe food")
        let kcalField = app.textFields["Calories (kcal)"].firstMatch
        // LabeledContent stretches the row; the editable part sits trailing.
        kcalField.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        kcalField.typeText("100")
        app.buttons["Save"].firstMatch.tap()

        // The form dismissed back to Foods — now the search must still
        // take a tap. Diagnostic matrix: single tap, settle+retap, so
        // the failure mode (dead vs transient) is visible in the log.
        let search = app.searchFields["Foods and Meals"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Foods search field after save")
        Thread.sleep(forTimeInterval: 1.0)
        search.tap()
        let focusedAfterOneTap = (search.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
        print("PROBE: focus after single tap = \(focusedAfterOneTap)")
        if !focusedAfterOneTap {
            Thread.sleep(forTimeInterval: 1.5)
            search.tap()
            let focusedAfterRetap = (search.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
            print("PROBE: focus after second tap = \(focusedAfterRetap)")
        }
        search.typeText("probe")
        XCTAssertTrue(
            (search.value as? String)?.localizedCaseInsensitiveContains("probe") == true,
            "Search field must take focus and text after a save (drawer desync)")
    }

    /// Meal-builder shots (opt-in via MEAL_FORM=1, seeded): the typed
    /// quantity field takes a fraction, and the sort menu leads Recent.
    @MainActor
    func testMealBuilderQuantityAndSort() throws {
        guard ProcessInfo.processInfo.environment["MEAL_FORM"] == "1" else {
            throw XCTSkip("Set MEAL_FORM=1 to run the meal-builder shots")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Foods")
        switchTab(in: app, to: "Add")
        let addMeal = app.buttons["Add Meal"]
        XCTAssertTrue(addMeal.waitForExistence(timeout: 5), "Add Meal chooser option")
        addMeal.tap()

        // Type a fractional quantity into the first food's field.
        let quantityField = app.textFields.matching(
            NSPredicate(format: "label BEGINSWITH 'Servings of'")
        ).firstMatch
        XCTAssertTrue(quantityField.waitForExistence(timeout: 5), "Typed quantity field")
        // The row's own name, so the member assertions below don't depend
        // on which food the seed happens to sort first.
        let memberName = quantityField.label.replacingOccurrences(of: "Servings of ", with: "")
        quantityField.tap()
        quantityField.typeText("0.5")
        attachShot(named: "meal-builder-typed-quantity")

        // TextField(value:format:) commits on focus RESIGNATION, so the
        // food doesn't join the meal until the decimal pad is dismissed.
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 3) { done.tap() }

        // What's in the meal has its own section (2026-08-09) — the
        // grouped list owns the header's case, hence BEGINSWITH[c].
        let membersHeader = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'In this meal'")
        ).firstMatch
        XCTAssertTrue(membersHeader.waitForExistence(timeout: 5),
                      "A picked food gets an 'In this meal' section")
        // ...and it appears ONCE in the whole form: the list below is
        // strictly what is NOT in the meal yet, so a member must not be
        // in both. Matched by PREFIX because a member row's label
        // carries ", in this meal" — membership must not depend on
        // VoiceOver having announced the section header — which the next
        // assertion pins.
        let mentions = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", memberName))
        XCTAssertEqual(mentions.count, 1,
                       "A member is listed in the meal, not also in the library below")
        XCTAssertEqual(mentions.firstMatch.label, "\(memberName), in this meal",
                       "A member row says so to VoiceOver on its own")
        attachShot(named: "meal-builder-members")

        // The meal's full nutrition, summed from its members and shown
        // through the same rows as the day's breakdown.
        let nutrition = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Nutrition'")).firstMatch
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5),
                      "A meal whose foods carry nutrient data offers a breakdown")
        nutrition.tap()
        let macros = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Macronutrients'")).firstMatch
        XCTAssertTrue(macros.waitForExistence(timeout: 5), "...which opens onto the macros")
        macros.tap()
        // SCALED, not raw: the row above is half a 30 g-protein shake,
        // so this must read 15 g. The Total only proves kcal scaling —
        // nutrients go through NutrientValues.scaled(by:), a different
        // path, and forgetting to scale it would look plausible.
        let protein = app.staticTexts["Protein"]
        XCTAssertTrue(protein.waitForExistence(timeout: 5), "Protein is listed")
        let shown = ((protein.value as? String) ?? "")
            + app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '15'"))
                .firstMatch.label
        XCTAssertTrue(shown.contains("15"),
                      "Half a serving contributes half its protein, not all of it: \(shown)")
        attachShot(named: "meal-builder-nutrition")

        // The sort menu: Recent leads, Name is one tap away.
        let sortMenu = app.buttons["Sort foods"].firstMatch
        XCTAssertTrue(sortMenu.waitForExistence(timeout: 5), "Sort menu in the Foods header")
        sortMenu.tap()
        XCTAssertTrue(app.buttons["Name"].waitForExistence(timeout: 3), "Name sort option")
        attachShot(named: "meal-builder-sort-menu")
        app.buttons["Name"].tap()

        // The one field does both jobs (2026-07-29): its prompt must say
        // so, or describing a meal stays invisible — the exact mistake
        // the Add Food form made for a release.
        let search = app.searchFields["Search foods or describe a meal"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Meal-builder search prompt names both jobs")
        // The decimal pad covers the bottom-placed search field, so taps
        // land on the keyboard; the form's own principal Done button is
        // the way out (decimal pads have no return key). Already tapped
        // after the quantity above — re-check in case focus came back.
        if done.exists {
            done.tap()
        }
        // Settle, then tap-and-retap: the iOS 26 search drawer regularly
        // ignores the first tap right after another control dismissed
        // (the same quirk testFoodsSearchAfterSave probes for).
        Thread.sleep(forTimeInterval: 1.0)
        search.tap()
        if (search.value(forKey: "hasKeyboardFocus") as? Bool) != true {
            Thread.sleep(forTimeInterval: 1.5)
            search.tap()
        }
        search.typeText("burrito bowl with rice and beans")
        // AI ships OFF, and this launch never turns it on: with the
        // master switch off there must be NO estimate row, only the
        // dismissable pointer at Settings. Off-by-default is the app's
        // spine — this asserts the switch actually gates the new door.
        XCTAssertFalse(
            app.buttons.containing(
                NSPredicate(format: "label BEGINSWITH 'Estimate this meal'")
            ).firstMatch.exists,
            "The meal estimate row must not appear while AI is switched off")
        // The regression this rework exists to prevent: a search filters
        // the LIBRARY, never the meal. Before 2026-08-09 the member
        // vanished from view while its calories still counted toward the
        // Total — you lost sight of the meal exactly while building it.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", memberName))
                .firstMatch.waitForExistence(timeout: 3),
            "Members stay visible while the search filters the library")
        attachShot(named: "meal-builder-describe-prompt")
    }

    /// Reaching the target: the announcement, that it can be dismissed for
    /// good, and — the part that matters — that continuing past a reached
    /// target KEEPS the journey instead of re-zeroing the bar at the moment
    /// it was earned.
    ///
    /// Opt-in via GOAL_REACHED=1, and seeded with `--seed-goal-reached`:
    /// the criterion is a sustained one (7-day basis, 3+ weigh-in days), so
    /// there is no way to reach this state on a fresh simulator without a
    /// month of simulated weight loss.
    @MainActor
    func testGoalReachedCelebrationAndContinue() throws {
        guard ProcessInfo.processInfo.environment["GOAL_REACHED"] == "1" else {
            throw XCTSkip("Set GOAL_REACHED=1 to run the goal-reached flow")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data", "--seed-goal-reached"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        // The milestone lands on the screen you actually open, and it
        // reports the ARC rather than only the finish line.
        let announcement = NSPredicate(format: "label BEGINSWITH 'You hit your target'")
        let card = app.descendants(matching: .any).matching(announcement).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Today announces a reached target")
        XCTAssertTrue(card.label.contains("down"),
                      "The card says how far you've come, not just that you arrived: \(card.label)")
        attachShot(named: "goal-reached-card")

        // Dismissing is permanent for this target — the acknowledgement
        // lives in defaults, so it has to survive the process.
        let dismiss = app.buttons["Dismiss"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "The card can be dismissed")
        dismiss.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "Dismissing hides the card")
        app.terminate()
        // No seed arguments: the library and the Health samples are already
        // in place, and every seeded launch ADDS samples.
        app.launchArguments = []
        app.launch()
        grantHealthAccess(in: app, timeout: 10)
        XCTAssertFalse(
            app.descendants(matching: .any).matching(announcement).firstMatch
                .waitForExistence(timeout: 8),
            "A dismissed card stays dismissed across launches")

        // ...but dismissing the ANNOUNCEMENT must never hide the DECISION.
        switchTab(in: app, to: "Goal")
        let celebration = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH \"You've reached your target\"")).firstMatch
        XCTAssertTrue(celebration.waitForExistence(timeout: 15),
                      "Goal keeps the celebration after the card is dismissed")
        // The celebration renders at the very bottom edge of the screen,
        // so its CHOICES are below the fold and a Form has not built
        // them yet — `.exists` on them is false while the card they
        // belong to is plainly there. Scroll to each rather than assert
        // where they happen to land (2026-08-23).
        let maintain = app.buttons["Switch to Maintain"].firstMatch
        XCTAssertTrue(scroll(app, until: maintain), "Maintain is offered")
        let keepGoing = app.buttons["5 lb more"].firstMatch
        XCTAssertTrue(scroll(app, until: keepGoing), "Quick amounts are offered")
        attachShot(named: "goal-reached-choices")

        // The journey's start weight, before and after. The seeded start is
        // 210 lb against weigh-ins that never exceed 202, and continuing
        // drops the target to 200 — so nothing else on this screen can put
        // a "210" on it, and its survival is the assertion.
        //
        // The Progress section sits below the fold, and a Form's rows don't exist
        // in the accessibility tree until they're scrolled near.
        // A LabeledContent row is ONE element carrying the value, but the
        // shape isn't guaranteed — accept a sibling static text too.
        let weightThen = app.staticTexts["Starting weight"]
        func startWeightShown() -> Bool {
            ((weightThen.value as? String) ?? "").contains("210")
                || app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS '210'")).firstMatch.exists
        }
        XCTAssertTrue(scroll(app, until: weightThen),
                      "Progress reports the journey's start")
        XCTAssertTrue(startWeightShown(), "...and that start is the seeded 210 lb")

        keepGoing.tap()

        // Measured from the target that was HIT (205), not from today's
        // weight — so it lands on a round 200 rather than 195.2.
        XCTAssertTrue(
            app.textFields.matching(NSPredicate(format: "value == '200'")).firstMatch
                .waitForExistence(timeout: 10),
            "\"5 lb more\" sets a round new target below the one just reached")
        // Saving re-lays the screen out (the celebration is gone), so find
        // the section again rather than trusting the old scroll position.
        XCTAssertTrue(scroll(app, until: weightThen),
                      "Progress survives the new target")
        XCTAssertTrue(startWeightShown(),
                      "Continuing KEEPS the original start — the bar still measures the whole arc")
        attachShot(named: "goal-reached-continued")
    }

    /// Adds the Onigiri medium widget to the simulator home screen by driving
    /// springboard. Mutates home-screen state — opt in via ADD_WIDGET=1.
    @MainActor
    func testAddWidgetToHomeScreen() throws {
        guard ProcessInfo.processInfo.environment["ADD_WIDGET"] == "1" else {
            throw XCTSkip("Set ADD_WIDGET=1 to run the widget installer")
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()

        // Reset to a clean home screen regardless of leftover state.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)

        // Long-press an empty spot to enter jiggle mode.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 2)

        let edit = springboard.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Jiggle-mode Edit button")
        edit.tap()

        let addWidget = springboard.buttons["Add Widget"]
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5), "Add Widget menu item")
        addWidget.tap()

        // Widget gallery: search for the app.
        let searchField = springboard.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8), "Gallery search field")
        searchField.tap()
        searchField.typeText("Onigiri")

        let result = springboard.staticTexts["Onigiri"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8), "Onigiri in gallery results")
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Wait for the widget detail pager, then swipe to the medium widget.
        let add = springboard.buttons[" Add Widget"].exists
            ? springboard.buttons[" Add Widget"]
            : springboard.buttons["Add Widget"]
        XCTAssertTrue(add.waitForExistence(timeout: 8), "Add Widget confirm button")
        // Swipe the family pager (not the whole screen) to reach the medium widget.
        let pager = springboard.scrollViews.firstMatch
        if pager.exists {
            pager.swipeLeft()
        } else {
            springboard.swipeLeft()
        }
        Thread.sleep(forTimeInterval: 1)
        add.tap()

        // Exit jiggle mode and give the timeline a moment to render.
        let done = springboard.buttons["Done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }
        Thread.sleep(forTimeInterval: 5)
    }

    /// Adds the LARGE Today-card widget to the simulator home screen and
    /// attaches a screenshot of the result. Seeds the app first so the
    /// card has real numbers. Mutates home-screen state — opt in via
    /// ADD_TODAY_WIDGET=1.
    @MainActor
    func testAddTodayCardWidget() throws {
        guard ProcessInfo.processInfo.environment["ADD_TODAY_WIDGET"] == "1" else {
            throw XCTSkip("Set ADD_TODAY_WIDGET=1 to run the Today-card widget installer")
        }
        // Seed Health + goal so the widget renders real numbers (the
        // goal mirror reaches the App Group via the launch sync push).
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)
        Thread.sleep(forTimeInterval: 3)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)

        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 2)
        let edit = springboard.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Jiggle-mode Edit button")
        edit.tap()
        let addWidget = springboard.buttons["Add Widget"]
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5), "Add Widget menu item")
        addWidget.tap()

        // NOT firstMatch: the App Library's offscreen search field can
        // match first when the home screen rests on its last page.
        let searchField = springboard.searchFields["Search Widgets"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8), "Gallery search field")
        searchField.tap()
        searchField.typeText("Onigiri")
        let result = springboard.staticTexts["Onigiri"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8), "Onigiri in gallery results")
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let add = springboard.buttons[" Add Widget"].exists
            ? springboard.buttons[" Add Widget"]
            : springboard.buttons["Add Widget"]
        XCTAssertTrue(add.waitForExistence(timeout: 8), "Add Widget confirm button")
        // Page the family pager to the Today card (matched by its
        // description, robust to bundle order).
        let pager = springboard.scrollViews.firstMatch
        let todayPage = springboard.staticTexts[
            "Today's balance, burned and eaten, and your tracked metrics."
        ]
        var swipes = 0
        while !todayPage.exists && swipes < 10 {
            if pager.exists { pager.swipeLeft() } else { springboard.swipeLeft() }
            Thread.sleep(forTimeInterval: 0.5)
            swipes += 1
        }
        XCTAssertTrue(todayPage.exists, "Today card page in the family pager")
        attachShot(named: "widget-gallery-today-card", settle: 1)
        add.tap()

        let done = springboard.buttons["Done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }
        // Give the timeline a moment to load Health data and render.
        Thread.sleep(forTimeInterval: 8)
        attachShot(named: "home-screen-today-card", settle: 1)
    }

    /// Clean systemMedium render of the Today card (no intent taps, so
    /// no shimmer). Opt in via ADD_TODAY_MEDIUM=1.
    @MainActor
    func testAddTodayCardMedium() throws {
        guard ProcessInfo.processInfo.environment["ADD_TODAY_MEDIUM"] == "1" else {
            throw XCTSkip("Set ADD_TODAY_MEDIUM=1 to run the medium capture")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)
        Thread.sleep(forTimeInterval: 3)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 2)
        springboard.buttons["Edit"].tap()
        springboard.buttons["Add Widget"].tap()
        let searchField = springboard.searchFields["Search Widgets"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8), "Gallery search field")
        searchField.tap()
        searchField.typeText("Onigiri")
        let result = springboard.staticTexts["Onigiri"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8), "Gallery result")
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let add = springboard.buttons[" Add Widget"].exists
            ? springboard.buttons[" Add Widget"]
            : springboard.buttons["Add Widget"]
        XCTAssertTrue(add.waitForExistence(timeout: 8), "Add Widget confirm")
        // The family pager holds small/medium/large, and the description
        // text exists for ALL of them at once — so waiting on it never
        // swipes and adds the small default. Swipe the preview once
        // (small → medium) by coordinate, the reliable lever.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.4))
            .press(forDuration: 0.05,
                   thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4)))
        Thread.sleep(forTimeInterval: 1)
        add.tap()
        if springboard.buttons["Done"].waitForExistence(timeout: 5) {
            springboard.buttons["Done"].tap()
        }
        Thread.sleep(forTimeInterval: 8)
        attachShot(named: "home-today-medium", settle: 1)
    }

    /// Long-press the app icon → Log Water quick action → app opens on the
    /// Water tab. Opt in via QUICK_ACTION=1 (drives springboard).
    @MainActor
    func testQuickActionLogWater() throws {
        guard ProcessInfo.processInfo.environment["QUICK_ACTION"] == "1" else {
            throw XCTSkip("Set QUICK_ACTION=1 to run the quick-action test")
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)

        // Find the app icon (not a widget): long-press until the menu shows
        // our quick actions. Menu items may surface as buttons, cells, or
        // static texts depending on the springboard version.
        // Widgets are also icons labeled "Onigiri", and the app icon may sit
        // on a later page — hunt across pages for the icon whose long-press
        // menu contains our quick action.
        let logWater = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Log Water'")).firstMatch
        let candidates = springboard.icons.matching(
            NSPredicate(format: "label == 'Onigiri'")
        )
        var opened = false
        pageLoop: for _ in 0..<3 {
            for index in 0..<min(candidates.count, 4) {
                let candidate = candidates.element(boundBy: index)
                guard candidate.exists, candidate.isHittable else { continue }
                candidate.press(forDuration: 1.6)
                if logWater.waitForExistence(timeout: 4) {
                    opened = true
                    break pageLoop
                }
                XCUIDevice.shared.press(.home)
                Thread.sleep(forTimeInterval: 1)
            }
            springboard.swipeLeft()
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(opened, "Quick-action menu with Log Water should appear")
        logWater.tap()

        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should open")
        XCTAssertTrue(
            app.buttons["Add 12 oz"].waitForExistence(timeout: 10),
            "Quick action should land on the Water tab"
        )

        // Warm path: with the app still running, the shortcut goes through
        // the scene delegate instead of launch options.
        switchTab(in: app, to: "Today")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        var warmOpened = false
        for index in 0..<min(candidates.count, 4) {
            let candidate = candidates.element(boundBy: index)
            guard candidate.exists, candidate.isHittable else { continue }
            candidate.press(forDuration: 1.6)
            if logWater.waitForExistence(timeout: 4) {
                warmOpened = true
                break
            }
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(warmOpened, "Quick-action menu (warm)")
        logWater.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should resume")
        XCTAssertTrue(
            app.buttons["Add 12 oz"].waitForExistence(timeout: 10),
            "Warm quick action should land on the Water tab too"
        )
    }

    /// Export the library to Files, then import it back; both paths surface
    /// a confirmation message. Opt in via EXPORT_IMPORT=1.
    @MainActor
    func testExportImportRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["EXPORT_IMPORT"] == "1" else {
            throw XCTSkip("Set EXPORT_IMPORT=1 to run the export/import test")
        }
        let app = XCUIApplication()
        app.launch()
        grantHealthAccess(in: app, timeout: 10)

        // Data tools live in Settings (gear on the Today tab).
        switchTab(in: app, to: "Today")
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "Settings gear")
        gear.tap()
        let export = app.buttons["Export library…"]
        XCTAssertTrue(export.waitForExistence(timeout: 10), "Export button")
        export.tap()

        // System document "save" browser: confirm with Move/Save.
        let saveButton = app.buttons["Move"].exists ? app.buttons["Move"] : app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10), "Document save confirm")
        saveButton.tap()
        // Overwrite if a previous export exists.
        let replace = app.buttons["Replace"]
        if replace.waitForExistence(timeout: 3) {
            replace.tap()
        }
        XCTAssertTrue(
            app.staticTexts["Library exported ✓"].waitForExistence(timeout: 10),
            "Export confirmation"
        )

        app.buttons["Import library…"].tap()
        // Document picker (open mode): pick the file we just saved. Files
        // render as collection cells; tap the cell, not its text label.
        let fileCell = app.cells.matching(
            NSPredicate(format: "label CONTAINS[c] 'onigiri-library'")
        ).firstMatch
        let fileText = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'onigiri-library'")
        ).firstMatch
        if !fileCell.waitForExistence(timeout: 6) {
            // Fresh device: Recents is empty — navigate Browse → On My iPhone.
            let browse = app.buttons["Browse"]
            if browse.exists {
                browse.tap()
                Thread.sleep(forTimeInterval: 1)
                browse.tap()
            }
            let onMyDevice = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'On My'")
            ).firstMatch
            if onMyDevice.waitForExistence(timeout: 4) {
                onMyDevice.tap()
            }
        }
        if fileCell.waitForExistence(timeout: 6) {
            fileCell.tap()
        } else {
            XCTAssertTrue(fileText.waitForExistence(timeout: 5), "Exported file in picker")
            fileText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        // The outcome is a TOAST now (one feedback channel app-wide) —
        // catch it right away, it only lingers a couple of seconds.
        let confirmation = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Imported'")
        ).firstMatch
        _ = confirmation.waitForExistence(timeout: 6)
        if !confirmation.exists {
            // Surface whatever message actually rendered (e.g. an error).
            let anyMessage = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'import' OR label CONTAINS[c] 'export'")
            ).firstMatch
            if anyMessage.exists {
                XCTFail("Rendered message was: \(anyMessage.label)")
            }
        }
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), "Import summary message")
    }

    /// Empty-library onboarding (opt-in via EMPTY_IMPORT=1): on a FRESH
    /// install (run after `simctl uninstall` — an exported onigiri-library
    /// file must already sit in Files from a prior EXPORT_IMPORT run), the
    /// Foods empty state offers Import inline; picking the file fills the
    /// library without a trip through Settings.
    @MainActor
    func testEmptyStateImport() throws {
        guard ProcessInfo.processInfo.environment["EMPTY_IMPORT"] == "1" else {
            throw XCTSkip("Set EMPTY_IMPORT=1 to run the empty-state import test")
        }
        let app = XCUIApplication()
        app.launch()
        skipOnboardingIfPresent(in: app)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Foods")
        let importButton = app.buttons["Import library…"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10), "Empty-state import button")
        attachShot(named: "empty-state")
        importButton.tap()

        // Same picker dance as the Settings round trip.
        let fileCell = app.cells.matching(
            NSPredicate(format: "label CONTAINS[c] 'onigiri-library'")
        ).firstMatch
        if !fileCell.waitForExistence(timeout: 6) {
            let browse = app.buttons["Browse"]
            if browse.exists {
                browse.tap()
                Thread.sleep(forTimeInterval: 1)
                browse.tap()
            }
            let onMyDevice = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'On My'")
            ).firstMatch
            if onMyDevice.waitForExistence(timeout: 4) {
                onMyDevice.tap()
            }
        }
        XCTAssertTrue(fileCell.waitForExistence(timeout: 6), "Exported file in picker")
        fileCell.tap()

        // Proof over toast: the imported library renders in the list.
        // Any-element match for the same reason as the reset round-trip
        // above — a row is a Button, so `staticTexts` never matches it.
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Protein shake'")
            ).firstMatch.waitForExistence(timeout: 10),
            "Imported food appears in Foods"
        )
        attachShot(named: "imported")
    }

    /// Opt-in (HEADER_SHOTS=1): one resting screenshot per tab plus the
    /// Log sheet — for visual alignment/styling checks between screens.
    @MainActor
    func testHeaderShots() throws {
        guard ProcessInfo.processInfo.environment["HEADER_SHOTS"] == "1" else {
            throw XCTSkip("Set HEADER_SHOTS=1 to run the header-shots capture")
        }
        let app = XCUIApplication()
        // HEADER_ORIENTATION=landscape for the iPad README shot;
        // portrait otherwise (and always on iPhone).
        XCUIDevice.shared.orientation =
            ProcessInfo.processInfo.environment["HEADER_ORIENTATION"] == "landscape"
                ? .landscapeLeft : .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)
        // The iPad sim adds a Health sync prompt after the grants.
        dismissHealthSyncPrompt(in: app)
        // The app launches on Today — capture it directly, before the tab
        // loop. Tapping the sidebar "Today" via switchTab is flaky on the
        // iPad capture, and Today is the shot this recapture needs; grabbing
        // it up front makes the capture independent of that tap.
        attachShot(named: "tab-today", settle: 3)
        var titleFrames = ["Today": dayHeading(in: app).frame]
        for tab in ["Foods", "Goal", "Calendar"] {
            switchTab(in: app, to: tab)
            attachShot(named: "tab-\(tab.lowercased())", settle: 2)
            titleFrames[tab] = app.navigationBars.staticTexts.firstMatch.frame
        }
        // The headers ALIGN: every tab draws one native `.inlineLarge`
        // title (`inlineLargeTitle`, Style.swift), so all four title
        // frames share a top-left corner. This is the assertion the
        // 2026-09-16 in-content detour never had — Foods' title sat
        // ~150pt lower than Today's and 16pt further right, Goal's
        // ~22pt lower, and nothing red said so.
        let reference = titleFrames["Today"]!
        // A title that was never found has a zero frame, and four zero
        // frames "align" perfectly — guard the reference first.
        XCTAssertGreaterThan(reference.width, 0, "Today's title should be in the nav bar")
        for (tab, frame) in titleFrames.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(frame.minX, reference.minX, accuracy: 1,
                           "\(tab)'s title left edge should match Today's")
            XCTAssertEqual(frame.minY, reference.minY, accuracy: 1,
                           "\(tab)'s title top edge should match Today's")
        }
        // The Foods library segment — Favorites is the default and shows
        // only the starred item; the README's Foods shot wants the list.
        switchTab(in: app, to: "Foods")
        let librarySegments = app.segmentedControls.firstMatch
        if librarySegments.waitForExistence(timeout: 5) {
            librarySegments.buttons["Foods"].tap()
            attachShot(named: "tab-foods-library", settle: 2)
        }
        // The Foods search drawer, activated — catches the
        // field-disappears-on-tap class of bug.
        let foodsSearch = app.searchFields.firstMatch
        if foodsSearch.waitForExistence(timeout: 5) {
            foodsSearch.tap()
            attachShot(named: "foods-search-active", settle: 2)
            app.typeText("egg")
            attachShot(named: "foods-search-typed", settle: 2)
            // Leave search before switching tabs: with the drawer
            // focused the tab bar is present but NOT hittable, and
            // switchTab fails loudly on exactly that (2026-09-16). The
            // drawer's close control is the X button labelled "Close"
            // — NOT "Cancel", which is what a bottom-placed search bar
            // shows (measured in the accessibility tree, iOS 26.5).
            let closeSearch = app.buttons["Close"].firstMatch
            if closeSearch.waitForExistence(timeout: 3) { closeSearch.tap() }
        }
        switchTab(in: app, to: "Today")
        // Tolerant: the corner slot's element shape differs on iPad and
        // the tab shots above are this test's real product.
        let addTab = app.buttons["Add"].firstMatch
        if addTab.waitForExistence(timeout: 5), addTab.isHittable {
            addTab.tap()
            attachShot(named: "log-sheet", settle: 2)
            // The Log sheet is a SHEET, not a fifth tab: "Log" inline
            // and centered with Cancel at its LEFT, like Settings and
            // Add Food — at rest AND scrolled. It wore the tabs'
            // `.inlineLarge` header for one day (2026-09-16) with Cancel
            // moved trailing, and scrolled, the compact title sat at
            // the left edge behind three trailing controls (the user,
            // from device). Asserted both ways so it can't drift back —
            // though an inline title has no collapsed state, so the
            // at-rest check is the load-bearing one; the seeded
            // Favorites list is three rows and the swipe below scrolls
            // nothing on a phone (the two shots were byte-identical,
            // 2026-09-16). It bites only on a library long enough to
            // scroll.
            let logBar = app.navigationBars["Log"]
            XCTAssertTrue(logBar.waitForExistence(timeout: 5), "Log sheet should be up")
            assertSheetHeader(logBar, title: "Log")
            app.swipeUp()
            attachShot(named: "log-sheet-scrolled", settle: 2)
            assertSheetHeader(logBar, title: "Log")
        }
    }

    /// The standard sheet header shape: Cancel entirely LEFT of the
    /// title, and the title centered in its bar (±4pt). A title that
    /// could not center reads as the tab-root header instead.
    private func assertSheetHeader(_ bar: XCUIElement, title: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let titleText = bar.staticTexts[title].firstMatch
        let cancel = bar.buttons["Cancel"].firstMatch
        XCTAssertTrue(titleText.waitForExistence(timeout: 3),
                      "\(title) title in the bar", file: file, line: line)
        XCTAssertTrue(cancel.exists, "Cancel in the bar", file: file, line: line)
        XCTAssertLessThan(cancel.frame.maxX, titleText.frame.minX,
                          "Cancel should sit left of the title", file: file, line: line)
        XCTAssertEqual(titleText.frame.midX, bar.frame.midX, accuracy: 4,
                       "\(title) should be centered in the bar", file: file, line: line)
    }

    /// Scrolls until `element` materializes, or gives up. Form rows below
    /// the fold don't exist in the accessibility tree at all, so a plain
    /// `waitForExistence` on one waits out its timeout and fails.
    @MainActor
    @discardableResult
    private func scroll(_ app: XCUIApplication, until element: XCUIElement, swipes: Int = 8) -> Bool {
        for _ in 0..<swipes {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.exists
    }

    @MainActor
    private func attachShot(named name: String, settle: TimeInterval = 0.8) {
        Thread.sleep(forTimeInterval: settle)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Reward badge + search paging (opt-in via BADGE_PAGING=1, seeded
    /// sims): swaps the goal badge to the trophy preset, then to a custom
    /// emoji, checking the calendar's "Goal met" line follows; then pages
    /// the online search past the first 10 results (or hits the graceful
    /// throttle footnote — either proves the mechanism).
    @MainActor
    func testRewardBadgeAndSearchPaging() throws {
        guard ProcessInfo.processInfo.environment["BADGE_PAGING"] == "1" else {
            throw XCTSkip("Set BADGE_PAGING=1 to run the badge/paging test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        // Preset swap: Settings → Goal badge → Trophy.
        switchTab(in: app, to: "Today")
        app.buttons["Settings"].tap()
        let badgeRow = app.staticTexts["Goal badge"]
        XCTAssertTrue(badgeRow.waitForExistence(timeout: 10), "Goal badge picker row")
        badgeRow.tap()
        app.staticTexts["Trophy"].tap()
        // The push-picker pops on selection; close Settings.
        app.buttons["Done"].tap()

        // A seeded past day earned its badge — the day card proves the swap.
        switchTab(in: app, to: "Calendar")
        let dayEight = app.staticTexts["8"].firstMatch
        XCTAssertTrue(dayEight.waitForExistence(timeout: 10), "Calendar day 8")
        dayEight.tap()
        // The day card flattens its children — match any element's label.
        let trophyMet = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Goal met 🏆'")
        ).firstMatch
        XCTAssertTrue(trophyMet.waitForExistence(timeout: 5), "Day card shows the trophy badge")
        attachShot(named: "badge-trophy")

        // Custom emoji through the "Choose your own…" prompt.
        switchTab(in: app, to: "Today")
        app.buttons["Settings"].tap()
        XCTAssertTrue(badgeRow.waitForExistence(timeout: 10))
        badgeRow.tap()
        app.staticTexts["Choose custom…"].tap()
        // The prompt sheet's field focuses itself with the current emoji
        // selected — typing replaces it, no tap (a tap would deselect).
        // Target by identifier: the emoji keyboard's own "Search Emoji"
        // bar is a TextField too.
        let field = app.textFields["emojiPromptField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Emoji prompt field")
        Thread.sleep(forTimeInterval: 1.5)
        field.typeText("🦄")
        attachShot(named: "badge-custom-prompt")
        app.buttons["Save"].tap()
        app.buttons["Done"].tap()
        switchTab(in: app, to: "Calendar")
        dayEight.tap()
        let customMet = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Goal met 🦄'")
        ).firstMatch
        XCTAssertTrue(customMet.waitForExistence(timeout: 5), "Day card shows the custom badge")
        attachShot(named: "badge-custom")

        // Paging: search online, walk to the bottom, expect either a second
        // page of rows or the throttle footnote.
        switchTab(in: app, to: "Foods")
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field")
        searchField.tap()
        searchField.typeText("chicken\n")
        let firstRowCount = { (app: XCUIApplication) -> Int in
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'kcal' OR label CONTAINS[c] 'no data'")
            ).count
        }
        // Let the first page land, then scroll the list to its end.
        Thread.sleep(forTimeInterval: 5)
        let before = firstRowCount(app)
        let throttled = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'busy' OR label CONTAINS[c] 'more results'")
        ).firstMatch
        var swipes = 0
        while swipes < 12 {
            app.swipeUp(velocity: .fast)
            swipes += 1
            if throttled.exists { break }
            if firstRowCount(app) > before { break }
        }
        Thread.sleep(forTimeInterval: 3)
        let after = firstRowCount(app)
        attachShot(named: "paging-bottom")
        // No fixed floor: weeding drops calorie-less rows, so page sizes
        // vary — growth or the graceful throttle both prove the paging.
        XCTAssertTrue(
            after > before || throttled.exists,
            "Second page loaded (\(before)→\(after)) or throttle footnote shown"
        )
    }

    /// Tracked-metric swap (opt-in via TRACKED_METRIC=1, seeded sims):
    /// points the first slot at Fiber and checks Today's metric row
    /// follows with the goal format and FDA-default target.
    @MainActor
    func testTrackedMetricSwap() throws {
        guard ProcessInfo.processInfo.environment["TRACKED_METRIC"] == "1" else {
            throw XCTSkip("Set TRACKED_METRIC=1 to run the tracked-metric test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Today")
        app.buttons["Settings"].tap()
        // The slots live behind the Metrics row now.
        let metricsRow = app.staticTexts["Metrics"].firstMatch
        XCTAssertTrue(metricsRow.waitForExistence(timeout: 10), "Metrics row")
        metricsRow.tap()
        // Both slots render a "Metric" row; the first belongs to slot 1.
        let metricRow = app.staticTexts["Metric"].firstMatch
        XCTAssertTrue(metricRow.waitForExistence(timeout: 10), "Slot 1 metric row")
        metricRow.tap()
        let fiber = app.staticTexts["Fiber"]
        XCTAssertTrue(fiber.waitForExistence(timeout: 5), "Fiber in the picker")
        fiber.tap()
        // Prove the pick took. Tapping the option pops the picker, and a
        // tap that lands on a neighbour leaves the slot reading something
        // else entirely ("Metric, None" was observed) — which the Today
        // assertion far below would then blame on the wrong thing.
        XCTAssertTrue(app.buttons["Metric, Fiber"].firstMatch.waitForExistence(timeout: 5),
                      "Slot 1 now reads Fiber")
        attachShot(named: "metric-slot-settings")
        // The Metric picker pops back to the PUSHED Metrics screen, whose
        // exit is a Back button — "Done" belongs to the Settings ROOT and
        // does not exist here at all. The test was updated for the move
        // behind the Metrics row but not for the way out, so it had been
        // failing on a control that cannot be on screen (found 2026-08-23,
        // and confirmed against an untouched tree).
        // Walk out of the pushed screens until the Settings root's Done is
        // TAPPABLE, and judge it by that alone. Existence proves nothing
        // in either direction here: the root stays in the hierarchy under
        // every pushed screen, so waiting for "Reminders" passed from
        // inside Metrics, while "Done" is not in the tree at all until
        // the pop finishes. Both readings sent this somewhere wrong.
        // Out of Settings in two steps, both scoped to the NAVIGATION BAR.
        // The pushed Metrics screen has only a Back button; "Done" belongs
        // to the Settings ROOT and is not in the tree at all from in here,
        // which is the control the original single tap reached for. And
        // the sheet cannot be swiped away — interactive dismissal is off
        // by design, so every exit is an explicit Done.
        //
        // Scoped, because a bare `app.buttons["Settings"]` is AMBIGUOUS
        // here: the back button carries the label "Settings" and so does
        // Today's gearshape.
        closeSettings(in: app)

        // Seeded foods carry fiber; the row reads "🌾 x / 28 g Fiber".
        let fiberMetric = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '28 g Fiber'")
        ).firstMatch
        XCTAssertTrue(fiberMetric.waitForExistence(timeout: 10), "Today shows the fiber metric")
        attachShot(named: "metric-today-fiber")

        // The calendar day card mirrors the slots.
        switchTab(in: app, to: "Calendar")
        let calendarFiber = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '28 g'")
        ).firstMatch
        XCTAssertTrue(calendarFiber.waitForExistence(timeout: 10), "Calendar day card shows the fiber metric")
        attachShot(named: "metric-calendar-fiber")

        // None empties the slot everywhere.
        switchTab(in: app, to: "Today")
        // By IDENTIFIER: a bare `app.buttons["Settings"]` is ambiguous
        // whenever a pushed screen's back button carries the same label.
        app.buttons["gearshape"].firstMatch.tap()
        XCTAssertTrue(metricsRow.waitForExistence(timeout: 10))
        metricsRow.tap()
        XCTAssertTrue(metricRow.waitForExistence(timeout: 10))
        metricRow.tap()
        // Single-text rows flatten to a Button with no StaticText child.
        let none = app.buttons["None"].firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 5), "None in the picker")
        none.tap()
        // The SAME exit, and the same bug: this second pass carried its
        // own `app.buttons["Done"].tap()` against the pushed screen.
        closeSettings(in: app)
        let fiberGone = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'g Fiber'")
        ).firstMatch
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(fiberGone.exists, "None removes the metric from Today")
        attachShot(named: "metric-today-none")
    }

    /// Dead-end search → Add Food (opt-in via ADD_FROM_SEARCH=1, seeded
    /// sims): a gibberish query returns nothing (or errors — either way),
    /// the Add Food button appears, and the new-food form opens with the
    /// query as the name.
    @MainActor
    func testAddFoodFromEmptySearch() throws {
        guard ProcessInfo.processInfo.environment["ADD_FROM_SEARCH"] == "1" else {
            throw XCTSkip("Set ADD_FROM_SEARCH=1 to run the add-from-search test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Foods")
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field")
        searchField.tap()
        searchField.typeText("zzqxvbnfood\n")

        let addFood = app.buttons["Add Food"].firstMatch
        XCTAssertTrue(addFood.waitForExistence(timeout: 20), "Add Food after dead-end search")
        attachShot(named: "search-add-food")
        addFood.tap()

        // The new-food form opens with the query prefilled as the name.
        // By VALUE, not identifier: the Name field carries an explicit
        // .accessibilityLabel("Name"), so a by-label/identifier lookup
        // for the typed text itself always misses it (found 2026-08-30,
        // pre-existing — the correct pattern already lives two tests
        // down, in testLogWithoutSaving's own note on this exact trap).
        let nameField = app.textFields.matching(
            NSPredicate(format: "value == %@", "zzqxvbnfood")
        ).firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Form prefilled with the query")
        attachShot(named: "search-add-food-form")
    }

    /// Cross-scope search (opt-in via CROSS_SCOPE_SEARCH=1, seeded sims):
    /// a query searches the WHOLE library, not the selected scope. The
    /// regression it guards: searching a FOOD while the Meals scope was
    /// up returned nothing, because the scope filter ran before the
    /// query (the user, 2026-08-07 — "nectarine").
    @MainActor
    func testSearchCrossesTheScopes() throws {
        guard ProcessInfo.processInfo.environment["CROSS_SCOPE_SEARCH"] == "1" else {
            throw XCTSkip("Set CROSS_SCOPE_SEARCH=1 to run the cross-scope search test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Add")  // the corner + pill opens the Log sheet
        let scopeBar = app.segmentedControls.firstMatch
        XCTAssertTrue(scopeBar.waitForExistence(timeout: 10), "Log sheet scope bar")
        // Stand squarely in the wrong scope: "Rice bowl" is a FOOD, and
        // the seeded meal ("Chicken & rice") does not contain the query.
        scopeBar.buttons["Meals"].tap()

        let searchField = logSheetField(in: app)
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Log sheet search field")
        searchField.tap()
        searchField.typeText("Rice bowl")

        // The food surfaces despite the Meals scope, under a named
        // group. Case-insensitive: iOS 18 uppercases section headers,
        // iOS 26 does not.
        let foodsHeader = app.staticTexts.matching(
            NSPredicate(format: "label ==[c] 'Foods'")
        ).firstMatch
        XCTAssertTrue(foodsHeader.waitForExistence(timeout: 10),
                      "Cross-scope search should group matches under Foods")
        XCTAssertTrue(app.buttons["Log Rice bowl"].waitForExistence(timeout: 5),
                      "A food should match while the Meals scope is selected")
        // The bar steps aside — no segment can be the true one when the
        // results cross every scope.
        XCTAssertFalse(app.segmentedControls.firstMatch.exists,
                       "Scope bar should hide while searching")
        attachShot(named: "logsheet-cross-scope-search")
    }

    /// The Log sheet's ONE field (opt-in via LOG_FIELD=1, seeded sims):
    /// it carries the merged prompt, there is no `.searchable` drawer
    /// above the list any more, the first row while searching is not
    /// FLUSH against the nav bar, and the Water row — not a library row
    /// — leaves while a query is typed unless the query names water (the
    /// user, 2026-09-17). Each assertion is something only the new
    /// behavior makes true: the prompt string, the drawer's ABSENCE, a
    /// measured gap that was exactly 0.0 before the fix, and Water gone
    /// for "rice" but back for "wat".
    ///
    /// `--seed-ai-on` so the estimate row is the first thing under the
    /// bar: that row is what measured `gapAboveRow=0.0`, and a FRAME
    /// comparison is the only thing that catches this class of bug —
    /// eyeballing a screenshot passed it twice (the chip's own internal
    /// padding reads as a gap that isn't there).
    @MainActor
    func testLogSheetOneFieldAndWater() throws {
        guard ProcessInfo.processInfo.environment["LOG_FIELD"] == "1" else {
            throw XCTSkip("Set LOG_FIELD=1 to run the Log-sheet field test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data", "--seed-ai-on"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Add")
        XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 10), "Log sheet should be up")
        let field = logSheetField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The door bar's field")
        // The seeder leaves online lookups ON, so the field has something
        // to describe to and wears the full prompt.
        XCTAssertEqual(field.placeholderValue, "Search or Describe Food",
                       "The one field says it searches AND describes")
        XCTAssertFalse(app.searchFields.firstMatch.exists,
                       "No .searchable drawer on the Log sheet")
        // THE COMPOSER'S ACTIONS ARE NOT THERE AT REST. They were, and
        // dimmed, for about an hour — discoverable, in theory; three
        // dead controls under a sheet you are reading, in practice,
        // with the estimate's own label truncated to fit (the user,
        // 2026-09-17, from device). They belong to the field, so they
        // arrive with its keyboard.
        let estimateAction = app.buttons["Estimate with AI"]
        let onlineAction = app.buttons["Search Online"]
        let addAction = app.buttons["Add a Photo or File"]
        XCTAssertFalse(estimateAction.exists, "No estimate action until the field is active")
        XCTAssertFalse(onlineAction.exists, "…nor Search Online")
        XCTAssertFalse(addAction.exists, "…nor the +")

        let water = app.buttons["Log Water"].firstMatch
        XCTAssertTrue(water.waitForExistence(timeout: 5), "Water leads the sheet at rest")
        // Where the list's first row sits while BROWSING — the mark the
        // searching state has to hit, taken before the scope bar leaves.
        let scopeBar = app.segmentedControls.firstMatch
        XCTAssertTrue(scopeBar.waitForExistence(timeout: 5), "Scope bar leads the sheet at rest")
        let browsingTop = scopeBar.frame.minY

        // THE WATER CARD SITS IN AN EVEN RHYTHM. Its neighbours are a
        // transparent row above (the scope bar) and a card below, and
        // for a while the row above spent ~10.5pt of list row inset as
        // blank canvas nobody could see the reason for: 20.33pt above
        // the card against 10pt below it (the user, 2026-09-17:
        // "Above/below should match"). Cells, not labels — the gap is
        // between the CARDS, and only their frames know where those
        // are.
        let rows = app.cells.allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(rows.count, 3, "Scope, Water and at least one library card")
        let aboveWater = rows[1].frame.minY - scopeBar.frame.maxY
        let belowWater = rows[2].frame.minY - rows[1].frame.maxY
        XCTAssertEqual(aboveWater, belowWater, accuracy: 1.5,
                       "The Water card's gaps must match (above \(aboveWater)pt, below \(belowWater)pt)")
        attachShot(named: "logsheet-field-rest")

        field.tap()
        // …and they arrive with the keyboard, the "+" among them,
        // still disabled until there is something to act on.
        XCTAssertTrue(estimateAction.waitForExistence(timeout: 5), "Estimate with AI arrives with the field")
        XCTAssertTrue(onlineAction.exists, "…with Search Online")
        XCTAssertTrue(addAction.exists, "…and the +")
        XCTAssertFalse(estimateAction.isEnabled, "…and it is dead until something is typed")
        XCTAssertFalse(onlineAction.isEnabled, "…as is Search Online")
        // The "+" shares the camera's vertical: same column, both
        // centred in it (the user: the + "looks disproportionate").
        let camera = scanRow(in: app)
        XCTAssertEqual(addAction.frame.midX, camera.frame.midX, accuracy: 1.5,
                       "The + is centred under the camera "
                       + "(+ \(addAction.frame.midX), camera \(camera.frame.midX))")
        // The two actions SPLIT what the + leaves, equally, and reach
        // the field's own trailing edge. The fill lived on the Button
        // rather than inside its label for a day, so the capsules drew
        // at their natural width and the row read as three pills adrift
        // (the user, 2026-09-18) — a slot that expands while the chip
        // in it doesn't is invisible to an existence check and obvious
        // on a phone, so this measures the CHIPS.
        XCTAssertEqual(estimateAction.frame.width, onlineAction.frame.width, accuracy: 1.5,
                       "The two actions are equal halves "
                       + "(estimate \(estimateAction.frame.width), online \(onlineAction.frame.width))")
        // The bar's own trailing margin, NOT `field.frame.maxX`: the
        // field element is the TextField inside the capsule and stops
        // short of the in-capsule chevron, so it is 52pt narrower than
        // the row and measuring against it fails on a correct layout.
        let barTrailing = app.windows.firstMatch.frame.maxX - 16
        XCTAssertEqual(onlineAction.frame.maxX, barTrailing, accuracy: 2,
                       "…and the row reaches the bar's trailing margin "
                       + "(online \(onlineAction.frame.maxX), margin \(barTrailing))")
        // One 10pt gap after the camera's COLUMN — which is where the
        // field starts too, so the two rows line up. Measured from the
        // camera rather than from the + glyph: the glyph is 36pt centred
        // in that 50pt column, so its own edge sits 7pt inside it.
        XCTAssertEqual(estimateAction.frame.minX, camera.frame.maxX + 10, accuracy: 2,
                       "…and the actions start where the field does "
                       + "(estimate \(estimateAction.frame.minX), camera ends \(camera.frame.maxX))")

        // The "+" opens a CHOOSER, and what it offers matters: the
        // camera is one of three doors you pick, never one that arrives
        // on its own. Photos and Files used to open the scan sheet with
        // the live viewfinder running behind the picker, so dismissing
        // the picker dropped you on a camera you never asked for (the
        // user, 2026-09-18). Whether the camera stays away is checked
        // below; that it is OFFERED here is checked now.
        addAction.tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5), "The chooser offers Photos")
        XCTAssertTrue(app.buttons["Files"].exists, "…and Files")
        XCTAssertTrue(app.buttons["Camera"].exists, "…and the Camera, as a choice")
        attachShot(named: "logsheet-add-context")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Photos"].waitForNonExistence(timeout: 5), "Close leaves the chooser")
        XCTAssertTrue(app.navigationBars["Log"].exists, "…and the sheet is still the Log sheet")
        // Nothing opened a scanner on the way through.
        XCTAssertFalse(app.navigationBars["Scan"].exists,
                       "Opening and closing the chooser must not raise the camera")

        field.typeText("rice")
        XCTAssertTrue(app.buttons["Log Rice bowl"].waitForExistence(timeout: 10),
                      "The library match for the query")
        XCTAssertTrue(water.waitForNonExistence(timeout: 5),
                      "Water leaves for a query that doesn't name it")
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "Scope bar hides while searching")

        // The jump this used to guard is GONE BY CONSTRUCTION, not
        // relaxed: it compared the scope bar (browsing) against the
        // estimate row (searching) because those were the two things
        // that led the list, and a flush estimate row was the bug
        // (0.0pt, then an overshoot to 148.0 against the bar's 142.67).
        // The estimate row left the list entirely for the composer on
        // 2026-09-17, so there is no second first-row to disagree with
        // the scope bar. What still has to hold is the margin that fix
        // installed — the list's content starts one section gap under
        // the nav bar — and `browsingTop` is where it is measured.
        XCTAssertEqual(browsingTop - app.navigationBars["Log"].frame.maxY, 10, accuracy: 1.5,
                       "The list keeps its section-gap margin under the nav bar "
                       + "(measured \(browsingTop - app.navigationBars["Log"].frame.maxY)pt)")

        // With a query the actions come alive, and the LIST stays
        // results only. The two trigger rows that used to sit among the
        // matches are gone: the sole "Estimate with…" element anywhere
        // is the composer's own, below every result, and the online
        // section's "Search OpenFoodFacts…" row is nowhere.
        XCTAssertTrue(estimateAction.isEnabled, "Estimate with AI wakes with a query")
        XCTAssertTrue(onlineAction.isEnabled, "…and so does Search Online")
        // The composer's button and the in-list idle row read the SAME
        // words now ("Estimate with AI" everywhere, 2026-09-18), so the
        // count and the geometry are what tell them apart — one such
        // button in the whole tree, and it below the last result rather
        // than among the rows.
        let estimateLabelled = app.buttons.matching(
            NSPredicate(format: "label == 'Estimate with AI'")).allElementsBoundByIndex
        XCTAssertEqual(estimateLabelled.count, 1, "One estimate trigger, not two")
        let resultCells = app.cells.allElementsBoundByIndex
        XCTAssertFalse(resultCells.isEmpty, "The query matched something to show")
        let lastCellBottom = resultCells.map(\.frame.maxY).max() ?? 0
        XCTAssertGreaterThan(estimateLabelled[0].frame.minY, lastCellBottom,
                             "…and it is the composer's, below the results rather than among them")
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Search OpenFoodFacts'")).firstMatch.exists,
                       "The online search row left the list with it")
        attachShot(named: "logsheet-field-rice")

        // The button really starts a run. Asserted on EITHER outcome,
        // never on the happy one alone: on-device inference fails in
        // seconds on some Macs (the ModelManagerError 1001 this machine
        // returns), and a test that waited for a RESULT would go red
        // over the host's model rather than over this wiring. A trigger
        // that did nothing produces neither.
        estimateAction.tap()
        let estimating = app.staticTexts["Estimating…"]
        let estimateFailed = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'Couldn'")).firstMatch
        let estimateResult = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'AI estimate'")).firstMatch
        var ran = false
        for _ in 0..<40 where !ran {
            ran = estimating.exists || estimateFailed.exists || estimateResult.exists
            if !ran { Thread.sleep(forTimeInterval: 0.25) }
        }
        XCTAssertTrue(ran, "Tapping Estimate starts a run — spinner, result or failure")

        // THE KEYBOARD HAS A WAY OUT THAT ISN'T THE SHEET'S. Before the
        // door bar's accessory the only exits were Cancel and Done,
        // which take the whole sheet with them, so a long description
        // typed by mistake cost the sheet (the user, 2026-09-17: "how
        // can I minimize it without closing out the whole dialog?").
        // Both halves matter: the keyboard gone AND the sheet still up,
        // with what was typed still in the field.
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5),
                      "The keyboard is up while the field has focus")
        // Cancel does not move, change or disappear while typing — the
        // keyboard's exit is its own control, in the field's capsule.
        XCTAssertTrue(app.buttons["Cancel"].exists, "Cancel stays Cancel while typing")
        let hideKeyboard = app.buttons["entryDoorsHideKeyboard"]
        XCTAssertTrue(hideKeyboard.waitForExistence(timeout: 5),
                      "The capsule offers a way out of the keyboard")
        // It is laid out BESIDE the text, never across it — the whole
        // complaint about the `.keyboard` toolbar accessory it replaced
        // (the user, from device: "overlaps the search field"). Not
        // containment: `field.frame` is the text input alone, and this
        // button is its sibling inside the capsule, so the honest test
        // is that the two rectangles don't meet.
        XCTAssertFalse(field.frame.intersects(hideKeyboard.frame),
                       "The dismiss must not overlap the text "
                       + "(field \(field.frame), button \(hideKeyboard.frame))")
        XCTAssertGreaterThanOrEqual(hideKeyboard.frame.minX, field.frame.maxX,
                                    "…and sits after it, on the trailing edge")
        hideKeyboard.tap()
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 5),
                      "…and it puts the keyboard away")
        XCTAssertTrue(app.navigationBars["Log"].exists,
                      "…leaving the sheet open — this is not Cancel wearing another name")
        XCTAssertEqual(field.value as? String, "rice", "…with the query still in the field")
        XCTAssertFalse(hideKeyboard.exists, "…and it goes when the keyboard does")
        attachShot(named: "logsheet-keyboard-dismissed")

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        field.typeText("wat")
        XCTAssertTrue(water.waitForExistence(timeout: 5), "Water is back for a query on the way to it")
        XCTAssertFalse(app.buttons["Log Rice bowl"].exists, "…and the library rows are still filtered")
        attachShot(named: "logsheet-field-wat")
    }

    /// Log without saving (opt-in via LOG_WITHOUT_SAVING=1, seeded sims):
    /// reached from the LOG sheet the food form offers Log / Log & Save,
    /// and plain Log writes the entry without minting a library food.
    /// The library assertion at the end is the whole point of the
    /// feature — a one-off should not permanently enlarge the library.
    @MainActor
    func testLogWithoutSaving() throws {
        guard ProcessInfo.processInfo.environment["LOG_WITHOUT_SAVING"] == "1" else {
            throw XCTSkip("Set LOG_WITHOUT_SAVING=1 to run the log-without-saving test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        // Unique per run: this test LOGS the name, and HealthKit keeps
        // it for a week — a fixed name would match its own previous
        // run's Recently Logged row on the second run, so the dead-end
        // search would no longer be a dead end.
        let oneOff = "Zzdiner plate \(Int(Date().timeIntervalSince1970) % 100_000)"

        // Turn online lookups OFF first. The seeder switches them ON,
        // and the online section's own "Add Food" only appears after a
        // search actually RETURNS — which on a sim with no route to
        // OpenFoodFacts means retry backoff, not a result. Off, the
        // dead-end search offers Add Food from local state alone, so
        // this test never depends on the network.
        switchTab(in: app, to: "Today")
        app.buttons["Settings"].firstMatch.tap()
        // The row is a LabeledContent inside a NavigationLink, so its
        // label carries the summary too ("Online Database, On") — match
        // the prefix, not the whole string.
        let onlineDatabase = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Online Database'")
        ).firstMatch
        XCTAssertTrue(onlineDatabase.waitForExistence(timeout: 10), "Settings → Online Database")
        onlineDatabase.tap()
        let lookups = app.switches.matching(
            NSPredicate(format: "label BEGINSWITH 'Online lookups'")
        ).firstMatch
        XCTAssertTrue(lookups.waitForExistence(timeout: 10), "Online lookups toggle")
        // Unconditional (the seeder leaves this ON), and on the TRAILING
        // edge: the switch element spans the whole Form row, so a plain
        // .tap() lands on the label — which does not toggle a SwiftUI
        // Toggle. Same reason the kcal field below is tapped at 0.9.
        lookups.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let back = app.navigationBars["Online Database"].buttons.firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }   // back to Settings
        // Confirm it took: the row summarises itself as "Off".
        let lookupsOff = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Online Database' AND label CONTAINS 'Off'")
        ).firstMatch
        XCTAssertTrue(lookupsOff.waitForExistence(timeout: 10),
                      "Online lookups should read Off after the toggle")
        let settingsDone = app.buttons["Done"].firstMatch
        if settingsDone.waitForExistence(timeout: 3) { settingsDone.tap() }

        switchTab(in: app, to: "Add")  // the corner + pill opens the Log sheet
        // Confirm the SHEET is actually up before typing: the Settings
        // detour above leaves the tab selection mid-bounce, and a
        // search field on some other screen would silently absorb the
        // query.
        // The nav bar named by the sheet's NATIVE title. (A bare
        // `staticTexts["Log"]` would be ambiguous: Today's own "Log"
        // section header is plain `Text("Log")` and stays in the tree
        // underneath this sheet.)
        let logTitle = app.navigationBars["Log"]
        if !logTitle.waitForExistence(timeout: 10) {
            switchTab(in: app, to: "Add")
        }
        XCTAssertTrue(logTitle.waitForExistence(timeout: 10), "Log sheet should be up")

        let searchField = logSheetField(in: app)
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Log sheet search field")
        searchField.tap()
        searchField.typeText(oneOff)

        let addFood = app.buttons["Add Food"].firstMatch
        XCTAssertTrue(addFood.waitForExistence(timeout: 20), "Add Food after dead-end search")
        addFood.tap()

        // By LABEL, not by value: the name field carries an explicit
        // .accessibilityLabel("Name") (its placeholder rides as the
        // value and vanishes once filled), so a by-value subscript
        // misses it.
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Form name field")
        XCTAssertEqual(nameField.value as? String, oneOff, "Form prefilled with the query")
        // The logging route's pair — and NOT the library route's.
        XCTAssertTrue(app.buttons["Log & Save"].waitForExistence(timeout: 5),
                      "Log sheet route should offer Log & Save")
        XCTAssertTrue(app.buttons["Log"].exists, "Log sheet route should offer a plain Log")
        XCTAssertFalse(app.buttons["Save"].exists,
                       "Log sheet route should not offer a library-only Save")
        // The VISIBLE title is gone (it crowded the confirm pair), but
        // the screen must still announce what it is — the nav-bar title
        // is what VoiceOver reads when a sheet presents, so dropping it
        // silently took that with it.
        XCTAssertTrue(app.staticTexts["New Food"].exists,
                      "the form keeps a heading for VoiceOver even with no visible title")
        XCTAssertFalse(app.navigationBars["New Food"].exists,
                       "…and that heading is NOT the visible bar title")
        attachShot(named: "form-log-pair")

        let kcalField = app.textFields["Calories (kcal)"].firstMatch
        // LabeledContent stretches the row; the editable part sits trailing.
        kcalField.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        kcalField.typeText("410")
        app.buttons["Log"].firstMatch.tap()

        // The portion sheet — "Will log" is its own, always present.
        // Its confirm ALSO reads "Log" and the form's toolbar is still
        // behind it, so take the last match (the same idiom the flow
        // test uses for stacked Cancels).
        XCTAssertTrue(app.staticTexts["Will log"].waitForExistence(timeout: 10),
                      "Portion sheet should follow Log")
        app.buttons.matching(identifier: "Log").allElementsBoundByIndex.last?.tap()

        // It logged: the entry is on Today. The log's meal groups render
        // COLLAPSED on a seeded day, so expand them before looking, and
        // scroll — the slot may sit below the fold.
        //
        // The form and the portion sheet leave in ONE cascade after Log
        // (2026-09-16), and the Log sheet comes back with the dead-end
        // query still in its field — a plain TextField in the door bar
        // since 2026-09-17, so Cancel/Sort/Done are all still there.
        // (Until then the query lived in a top `.searchable` drawer,
        // whose search controller swapped the toolbar for its own
        // "Close" for the rest of the sheet's life, and this step had
        // to tap that first — the iOS 26 landmine measured 2026-09-15.)
        // Wait for the sheet to be back, then Done: tapping it straight
        // after Log found no Done at all (2026-09-16).
        let done = app.buttons["Done"].firstMatch
        for _ in 0..<40 where !(done.exists && done.isHittable) {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(done.isHittable, "Log sheet's Done back after the form left")
        done.tap()
        switchTab(in: app, to: "Today")
        let entry = app.staticTexts[oneOff]
        let expandAll = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Log. Collapses'")
        ).firstMatch
        if expandAll.waitForExistence(timeout: 10), !entry.exists {
            expandAll.tap()
        }
        for _ in 0..<4 where !entry.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(entry.exists, "The one-off should appear in the Today log")

        // …and it did NOT enter the library: searching Foods for it
        // finds nothing. (Online lookups are off, so "No matches" is
        // the whole result.)
        switchTab(in: app, to: "Foods")
        let foodsSearch = app.searchFields.firstMatch
        XCTAssertTrue(foodsSearch.waitForExistence(timeout: 10), "Foods search field")
        foodsSearch.tap()
        foodsSearch.typeText(oneOff)
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 10),
                      "A logged-only food must not be saved to the library")
        XCTAssertFalse(app.buttons["Log \(oneOff)"].exists,
                       "A logged-only food must not appear as a library row")
        attachShot(named: "library-without-the-one-off")
    }

    /// Form search paging (opt-in via FORM_PAGING=1, seeded sims): the
    /// food form's Search Database sheet pages past 10 like the other
    /// search surfaces.
    @MainActor
    func testFormSearchPaging() throws {
        guard ProcessInfo.processInfo.environment["FORM_PAGING"] == "1" else {
            throw XCTSkip("Set FORM_PAGING=1 to run the form-paging test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Foods")
        // The corner + pill opens the Food-or-Meal chooser now.
        switchTab(in: app, to: "Add")
        let addFood = app.buttons["Add Food"]
        XCTAssertTrue(addFood.waitForExistence(timeout: 5), "Add Food chooser option")
        addFood.tap()
        // The describe field now carries the database search too
        // (2026-08-29); the dedicated bottom search field it used to
        // live under is retired. Submitting still runs the online leg,
        // same as the old field's `.onSubmit(of: .search)` did.
        let field = app.textFields["Describe food or meal"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Form database search field")
        field.tap()
        field.typeText("chicken\n")

        let rowCount = { (app: XCUIApplication) -> Int in
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'kcal' OR label CONTAINS[c] 'no data'")
            ).count
        }
        Thread.sleep(forTimeInterval: 5)
        let before = rowCount(app)
        let throttled = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'busy' OR label CONTAINS[c] 'more results'")
        ).firstMatch
        // The online section now sits inline in the whole FORM's own
        // scroll view, not a focused `.searchable` results list of its
        // own (2026-08-29) — a fast swipe travels through everything
        // below it too (Name, Calories, Macronutrients…), so unpaced
        // swipes blew straight past the still-loading rows into the
        // form's own fields, which then virtualized the online rows
        // OUT of the tree and read as a row-count DROP (11→4) rather
        // than growth. A settle between swipes gives `loadMore` (fired
        // by the last row's `.onAppear`) a chance to land before the
        // next swipe, and stopping at the Name field means "ran out of
        // online content to page through" is treated as overshoot, not
        // silently swiped past.
        let overshot = app.textFields["Name"]
        var swipes = 0
        while swipes < 12 {
            app.swipeUp(velocity: .fast)
            swipes += 1
            Thread.sleep(forTimeInterval: 0.5)
            if throttled.exists { break }
            if rowCount(app) > before { break }
            if overshot.exists { break }
        }
        Thread.sleep(forTimeInterval: 3)
        let after = rowCount(app)
        attachShot(named: "form-paging-bottom")
        XCTAssertTrue(
            after > before || throttled.exists || overshot.exists,
            "Form search paged (\(before)→\(after)), throttled gracefully, or ran out of online rows to page"
        )
    }

    /// One-off: grants whatever Health sheet is pending, without seeding.
    @MainActor
    func testGrantPendingAccess() throws {
        let app = XCUIApplication()
        app.launch()
        skipOnboardingIfPresent(in: app)
        grantHealthAccess(in: app, timeout: 30)
        // Deterministic settle with an actual assertion — the bare 3 s
        // sleep proved nothing and slowed every full-suite run.
        XCTAssertTrue(
            app.buttons["Today"].waitForExistence(timeout: 10),
            "App reaches its tab bar after the Health grant"
        )
    }

    /// Fresh installs without a seeded goal land on onboarding — tests
    /// that aren't about it skip straight through.
    @MainActor
    private func skipOnboardingIfPresent(in app: XCUIApplication) {
        let skip = app.buttons["Set Up Later"]
        if skip.waitForExistence(timeout: 4) {
            skip.tap()
        }
    }

    /// Onboarding walkthrough (opt-in via ONBOARDING=1, fresh erased
    /// sims, NO seeding): welcome → Health access → goal (190 lb) →
    /// water → done, then the goal exists in the app.
    @MainActor
    func testOnboarding() throws {
        guard ProcessInfo.processInfo.environment["ONBOARDING"] == "1" else {
            throw XCTSkip("Set ONBOARDING=1 to run the onboarding test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to Onigiri"].waitForExistence(timeout: 10),
                      "Fresh install lands on onboarding")
        attachShot(named: "onboarding-welcome")
        app.buttons["Continue"].firstMatch.tap()

        let allow = app.buttons["Allow Health Access"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5), "Health page")
        attachShot(named: "onboarding-health")
        allow.tap()
        grantHealthAccess(in: app, timeout: 30)

        let targetField = app.textFields.firstMatch
        XCTAssertTrue(targetField.waitForExistence(timeout: 10), "Goal page fields")
        attachShot(named: "onboarding-goal")
        // Fields: current weight (manual, no Health data on a fresh sim)
        // then target — fill both so the goal validates. LabeledContent
        // stretches the field's frame across the row; the editable part
        // sits at the trailing edge, so tap there.
        let fields = app.textFields
        fields.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.5)
        fields.element(boundBy: 0).typeText("210")
        fields.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.5)
        fields.element(boundBy: 1).typeText("190")
        app.buttons["Save Goal"].tap()

        XCTAssertTrue(app.staticTexts["Daily water goal"].waitForExistence(timeout: 5), "Water page")
        attachShot(named: "onboarding-water")
        app.buttons["Continue"].firstMatch.tap()

        // The privacy-choices page (2026-07-20): both switches ship
        // OFF and the walkthrough leaves them that way — the default
        // story is the tested story.
        XCTAssertTrue(app.staticTexts["Private by default"].waitForExistence(timeout: 5),
                      "Privacy page")
        attachShot(named: "onboarding-privacy")
        app.buttons["Continue"].firstMatch.tap()

        let start = app.buttons["Start Logging"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Done page")
        attachShot(named: "onboarding-done")
        start.tap()

        // Landed in the app with the goal saved.
        XCTAssertTrue(app.buttons["jumpToDate"].waitForExistence(timeout: 10),
                      "Onboarding hands off to Today")
        switchTab(in: app, to: "Goal")
        // "190" lives in the target field's VALUE (editable), and the
        // derived plan proves the save — match either.
        let target = app.descendants(matching: .any).matching(
            NSPredicate(format: "value CONTAINS '190' OR label CONTAINS 'To lose'")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Goal saved from onboarding")
        attachShot(named: "onboarding-goal-saved")
    }

    /// Handles the Health permission sheet: Turn On All, then Allow.
    /// The sheet renders inside the host app's accessibility hierarchy with
    /// stable UIA.Health.* identifiers.
    @MainActor
    private func grantHealthAccess(in app: XCUIApplication, timeout: TimeInterval) {
        // iPads without Health iCloud sync interpose an "iCloud Health
        // Data Sync is Off" sheet around the grant flow — clear it
        // wherever it lands.
        dismissHealthSyncPrompt(in: app)

        let sheet = app.navigationBars["Health Access"]
        guard sheet.waitForExistence(timeout: timeout) else {
            // The scope page can be up on its own — this helper is
            // called twice and the first call may have left it there.
            grantHealthTimeScope(in: app)
            dismissHealthSyncPrompt(in: app)
            return
        }

        let turnOnAll = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        if turnOnAll.waitForExistence(timeout: 5) {
            turnOnAll.tap()
        }

        // Nothing about the confirm control is stable across builds, and
        // it isn't even ONE control — this sheet can present it two
        // different ways depending on path taken through "Turn On All":
        // a compact secondary confirmation with real Buttons carrying the
        // identifier `UIA.Health.Allow.Button` ("Allow" on 26.5, seen
        // relabeled "Continue" on a 27.0 build 24A434, both WITH that
        // identifier); or — reached by scrolling the full 88-topic list
        // to its end (9 pages on that same 24A434 build) instead of
        // going through the compact path — a plain StaticText labeled
        // "Allow" with NO identifier at all, inside one Cell with
        // "Don’t Allow" (found 2026-09-17 re-filming the AI clip: the
        // failure named its own query, `'"Allow" IN identifiers'`, and
        // that subscript never matched this text although the tree
        // dump showed it). So match on identifier OR label with an
        // explicit predicate, across any element type, and be ready to
        // scroll a long way.
        let confirm = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'UIA.Health.Allow.Button' OR label == 'Allow' OR label == 'Continue'"
        )).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "The Health sheet's confirm control should exist after Turn On All")
        var swipes = 0
        while !confirm.isHittable, swipes < 60 {
            app.swipeUp(velocity: .fast)
            swipes += 1
        }
        XCTAssertTrue(confirm.isHittable, "The Health sheet's confirm control should scroll into view")
        confirm.tap()
        _ = sheet.waitForNonExistence(timeout: 10)
        grantHealthTimeScope(in: app)
        dismissHealthSyncPrompt(in: app)
    }

    /// The SECOND page of the grant (2026-09-18): "How much data would
    /// you like to share with …?", a scope choice whose Allow is
    /// DISABLED until one of the two rows is picked.
    ///
    /// It cost an afternoon because nothing about it looks like a Health
    /// sheet from the outside. Its nav bar identifies as
    /// `HealthUI.HKAuthorizationTimeBoundedView`, so the caller's
    /// `navigationBars["Health Access"]` misses it (the only thing here
    /// with that label is the BACK button) and the caller returned
    /// having granted nothing — leaving this sheet standing over the
    /// app, out of process, so the app's own tree read perfectly healthy
    /// while every tap failed as "exists but is not tappable".
    ///
    /// ALL recorded data, not "Past 30 Days": the seeder writes months
    /// of weigh-ins and logs, and a 30-day window hides the history Goal
    /// and the Calendar are tested against.
    @MainActor
    private func grantHealthTimeScope(in app: XCUIApplication) {
        let scopeLabel = "All Recorded Data and Future Data"
        let scope = app.staticTexts[scopeLabel]
        guard scope.waitForExistence(timeout: 10) else { return }
        scope.tap()
        let allow = app.buttons["Allow"]
        guard allow.waitForExistence(timeout: 5) else {
            XCTFail("The scope page should offer Allow")
            return
        }
        // The row may swallow the tap without selecting; the cell around
        // it is the control. Poll rather than asserting immediately —
        // enabling follows the selection by a frame or two.
        let cell = app.cells.containing(
            NSPredicate(format: "label CONTAINS %@", scopeLabel)
        ).firstMatch
        let deadline = Date().addingTimeInterval(5)
        while !allow.isEnabled, Date() < deadline {
            if cell.exists, cell.isHittable { cell.tap() }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(allow.isEnabled, "Choosing a data scope should enable Allow")
        allow.tap()
        _ = allow.waitForNonExistence(timeout: 10)
    }

    @MainActor
    private func dismissHealthSyncPrompt(in app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2), notNow.isHittable {
            notNow.tap()
        }
    }

    /// The tab called Today goes to today — including a RE-TAP while the
    /// tab is already selected, which is the whole point (the user,
    /// 2026-08-14: paging back through the week left the nav bar as the
    /// only way home).
    ///
    /// This exists because the implementation rests on an assumption a
    /// build cannot check: that SwiftUI writes the TabView's selection
    /// binding when you tap the tab you are already on. If that ever
    /// stops holding, the feature silently does nothing — so the re-tap,
    /// not the tab switch, is what this asserts.
    @MainActor
    func testTodayTabReturnsToTodaysDate() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        // Which day is showing is read off the NEXT-day chevron: it is
        // disabled on today and enabled on any other day. Not the title
        // text — on the iOS 26.5 sim the native `.inlineLarge` title's
        // accessibility label sticks on "Today" after the day changes
        // (a platform bug, fixed in 27.0; `dayHeading(in:)` explains),
        // so a title read here would pass or fail by OS version, not by
        // behaviour.
        XCTAssertTrue(app.buttons["jumpToDate"].waitForExistence(timeout: 30),
                      "Today's header should render")
        let nextDay = app.buttons["Next day"]
        XCTAssertTrue(nextDay.waitForExistence(timeout: 10), "day pager should exist")
        XCTAssertFalse(nextDay.isEnabled, "should open on today (Next day disabled)")

        // Page back. Asserting the move is load-bearing: without it a
        // tab tap that does nothing would still end on today and this
        // test would pass while proving nothing.
        let previousDay = app.buttons["Previous day"]
        previousDay.tap()
        previousDay.tap()
        let onAnotherDay = NSPredicate(format: "isEnabled == true")
        let onToday = NSPredicate(format: "isEnabled == false")
        wait(for: [expectation(for: onAnotherDay, evaluatedWith: nextDay)], timeout: 10)

        // The re-tap: already on Today, two days back.
        switchTab(in: app, to: "Today")
        wait(for: [expectation(for: onToday, evaluatedWith: nextDay)], timeout: 10)

        // And from another tab, since "always" covers that too.
        previousDay.tap()
        wait(for: [expectation(for: onAnotherDay, evaluatedWith: nextDay)], timeout: 10)
        switchTab(in: app, to: "Foods")
        switchTab(in: app, to: "Today")
        wait(for: [expectation(for: onToday, evaluatedWith: nextDay)], timeout: 10)
    }

    /// Moving a log entry in time must be finishable and abandonable.
    ///
    /// The compact `DatePicker` this replaced opened a floating calendar
    /// with no controls of its own — dismissed only by tapping OUTSIDE,
    /// which on a `.medium` sheet is the backdrop that closes the whole
    /// edit. So a date could be chosen and never committed (the user,
    /// 2026-08-17).
    ///
    /// The assertions are on what could not be true before: a confirm
    /// control EXISTS, using it collapses the picker while the edit
    /// sheet stays up, and Cancel leaves the entry's own date alone.
    @MainActor
    func testLogTimePickerConfirmsAndCancels() throws {
        guard ProcessInfo.processInfo.environment["LOG_TIME_ROW"] == "1" else {
            throw XCTSkip("Set LOG_TIME_ROW=1 to run the log time-picker test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data"]
        app.launch()
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)
        switchTab(in: app, to: "Today")

        // Down to the Log, which arrives COLLAPSED — the groups have to
        // be opened before any entry is on screen to tap.
        let group = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'collapsed' AND NOT (label BEGINSWITH 'Water')")
        ).firstMatch
        for _ in 0..<6 where !group.exists {
            app.swipeUp()
        }
        XCTAssertTrue(group.waitForExistence(timeout: 10), "a collapsed meal group")
        group.tap()

        // An ENTRY row, told from its group by the time it carries.
        let entry = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'kcal' AND (label CONTAINS 'AM' OR label CONTAINS 'PM')")
        ).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "a logged entry")
        entry.tap()

        // LabeledContent folds the row's own label into its controls, so
        // the chip reads "Time, Date, Aug 17, 2026".
        let dateChip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Date, '")
        ).firstMatch
        XCTAssertTrue(dateChip.waitForExistence(timeout: 10), "the entry's date chip")
        let before = dateChip.label

        // Days are addressed the way the calendar names them to
        // VoiceOver ("Sunday, August 16"). Across a month boundary the
        // picker opens on a month that has neither, so the day-moving
        // half is skipped rather than faked.
        let dayFormat = DateFormatter()
        dayFormat.dateFormat = "EEEE, MMMM d"
        func day(_ offset: Int) -> XCUIElement? {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: .now),
                  Calendar.current.isDate(date, equalTo: .now, toGranularity: .month)
            else { return nil }
            return app.buttons[dayFormat.string(from: date)]
        }
        let bar = app.navigationBars["Date"]
        func openCalendar() {
            // The previous sheet's dismissal is ANIMATED, and a chip
            // tapped mid-transition lands on a backdrop that is still
            // there — which closes the edit itself. Wait for the picker
            // to be really gone before asking for it again.
            if bar.exists {
                wait(for: [expectation(for: NSPredicate(format: "exists == false"),
                                       evaluatedWith: bar)], timeout: 10)
            }
            dateChip.tap()
            XCTAssertTrue(bar.waitForExistence(timeout: 10), "the calendar opens on its own sheet")
        }

        // CONFIRM: the controls that did not exist at all, and a day
        // that actually moves — the whole point of the row.
        openCalendar()
        XCTAssertTrue(app.buttons["logTime.done"].exists, "a way to confirm")
        XCTAssertTrue(app.buttons["logTime.cancel"].exists, "a way out")
        let yesterday = day(-1)
        if let yesterday, yesterday.waitForExistence(timeout: 3) { yesterday.tap() }
        app.buttons["logTime.done"].tap()
        XCTAssertTrue(dateChip.waitForExistence(timeout: 10),
                      "confirming leaves the edit sheet up")
        let afterDone = dateChip.label
        if yesterday != nil {
            XCTAssertNotEqual(afterDone, before, "Done commits the day that was chosen")
        }

        // CANCEL: a real change, discarded. Weaker phrasings pass
        // vacuously — cancelling a calendar nobody touched changes
        // nothing either way.
        openCalendar()
        if let earlier = day(-2), earlier.waitForExistence(timeout: 3) { earlier.tap() }
        app.buttons["logTime.cancel"].tap()
        XCTAssertTrue(dateChip.waitForExistence(timeout: 10),
                      "cancelling leaves the edit sheet up")
        XCTAssertEqual(dateChip.label, afterDone, "…and the entry keeps the date it had")
    }

    /// The check-the-estimate step
    /// (`plans/PLAN-refine-with-context.md`). Opt-in via REFINE_STEP=1;
    /// the estimate itself comes from --refine-sample, because no
    /// headless runner can point a camera at a plate.
    ///
    /// It asserts the rules that survive EITHER outcome of the refine,
    /// and that is deliberate: whether a model answers here is not
    /// something a UI test may assume. AI ships off, but the master
    /// switch lives in app-group defaults that outlive the install — an
    /// eval run on the same simulator leaves it ON, which is exactly how
    /// the first version of this test failed (2026-08-24). So:
    ///
    /// - a refine that DECLINES keeps the estimate and says so;
    /// - a refine that LANDS leaves the first estimate one tap away;
    /// - and Use hands over whatever is on screen, to the same form the
    ///   read used to open directly.
    @MainActor
    func testRefineStepChecksAnEstimateBeforeItFillsAnything() throws {
        guard ProcessInfo.processInfo.environment["REFINE_STEP"] == "1" else {
            throw XCTSkip("Set REFINE_STEP=1 to run the refine-step test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--seed-sample-data", "--refine-sample"]
        app.launch()
        skipOnboardingIfPresent(in: app)
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Add")
        let logTitle = app.navigationBars["Log"]
        if !logTitle.waitForExistence(timeout: 10) { switchTab(in: app, to: "Add") }
        XCTAssertTrue(logTitle.waitForExistence(timeout: 10), "Log sheet should be up")

        let scan = scanRow(in: app)
        XCTAssertTrue(scan.waitForExistence(timeout: 5), "Scan row in the Log sheet")
        scan.tap()
        let sample = app.buttons["refineScanSample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10),
                      "Sample estimate row (needs --refine-sample)")
        sample.tap()

        XCTAssertTrue(app.navigationBars["Check the Estimate"].waitForExistence(timeout: 10),
                      "The step should stand between the read and the form")
        XCTAssertTrue(app.staticTexts["Sample Chicken Salad"].waitForExistence(timeout: 5),
                      "the estimate, named")
        // 520 kcal is SUMMED from the three components, never taken from
        // the value passed beside them.
        let firstTotal = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "520")).firstMatch
        XCTAssertTrue(firstTotal.waitForExistence(timeout: 5),
                      "520 kcal — summed from the components")
        attachShot(named: "refine-step")

        // Refine is a BUTTON and it needs a note: nothing to say, nothing
        // to spend.
        let run = app.buttons["refineRun"]
        XCTAssertTrue(run.waitForExistence(timeout: 5), "Refine button")
        XCTAssertFalse(run.isEnabled, "Refine with an empty note must not run")

        let note = app.textFields["refineNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "The note field")
        note.tap()
        note.typeText("no dressing")
        XCTAssertTrue(run.isEnabled, "…and it arms once there is something to say")
        run.tap()

        // Whichever way it goes, the step has to RESOLVE — a spinner
        // that never returns is the failure neither branch may become.
        let revert = app.buttons["refineRevert"]
        let unchanged = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "the estimate is unchanged")).firstMatch
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, !revert.exists, !unchanged.exists {
            _ = revert.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(revert.exists || unchanged.exists,
                      "a refine must either land or say it didn't")
        attachShot(named: "refine-answered")

        if revert.exists {
            // It landed — so the first estimate must still be one tap
            // away. A refine that comes back worse must not cost the
            // photograph.
            revert.tap()
            XCTAssertTrue(firstTotal.waitForExistence(timeout: 10),
                          "Use the first estimate restores what the read produced")
        } else {
            // It declined — the estimate that was there is still the best
            // one there is, so it must still BE there.
            XCTAssertTrue(firstTotal.exists,
                          "a declined refine must not cost the numbers")
        }
        XCTAssertTrue(app.staticTexts["Sample Chicken Salad"].exists,
                      "…nor the food")

        // Use hands over exactly as the read used to, into the same form.
        // Asserted on the NAME field, not on a navigation title: the form
        // wears the Log sheet's chrome here (Cancel / Log / Log & Save),
        // not "Add Food".
        app.buttons["refineUse"].tap()
        XCTAssertTrue(
            app.textFields.matching(
                NSPredicate(format: "value CONTAINS %@", "Chicken Salad")
            ).firstMatch.waitForExistence(timeout: 15),
            "Use should prefill the food form with the estimate on screen")
        attachShot(named: "refine-used")
    }

    /// The loop this feature exists for (`plans/PLAN-multi-item-import.md`):
    /// one read, several items. Opt-in via MENU_LOOP=1; the list itself
    /// comes from --menu-scan-sample, because no headless runner can
    /// point a camera at a menu board.
    ///
    /// The assertion that matters is the SECOND log. A picker that
    /// appears, and a first item that logs, is exactly what shipped
    /// before — the fault was that the list then disappeared, so
    /// anything provable with one pick proves nothing here. "Logged 2
    /// items" can only be rendered by a list that survived the first
    /// one, and both entries in the day's log can only be written by a
    /// flow that was never torn down.
    @MainActor
    func testMenuPickerLogsSeveralItems() throws {
        guard ProcessInfo.processInfo.environment["MENU_LOOP"] == "1" else {
            throw XCTSkip("Set MENU_LOOP=1 to run the multi-item menu test")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        // The seed RESETS the store on a simulator, so the day's log
        // holds this run's entries and no earlier run's.
        app.launchArguments = ["--seed-sample-data", "--menu-scan-sample"]
        app.launch()
        skipOnboardingIfPresent(in: app)
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Add")   // the corner + pill opens the Log sheet
        let logTitle = app.navigationBars["Log"]
        if !logTitle.waitForExistence(timeout: 10) { switchTab(in: app, to: "Add") }
        XCTAssertTrue(logTitle.waitForExistence(timeout: 10), "Log sheet should be up")

        let scan = scanRow(in: app)
        XCTAssertTrue(scan.waitForExistence(timeout: 5), "Scan row in the Log sheet")
        scan.tap()
        let sampleMenu = app.buttons["menuScanSample"]
        XCTAssertTrue(sampleMenu.waitForExistence(timeout: 10),
                      "Sample menu row (needs --menu-scan-sample)")
        sampleMenu.tap()

        // The source dialog does not appear — the sample names its cafe,
        // which is the same path a document that named itself takes.
        let picker = app.navigationBars["Choose an Item"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "The menu picker should be up")
        attachShot(named: "menu-picker-first")

        /// Pick a row, confirm it, and come back. Waits for the picker's
        /// own title to return, which is the loop closing.
        func logItem(_ name: String, expectFinalNote note: String) {
            let row = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", name)
            ).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) row in the picker")
            row.tap()
            let confirm = app.navigationBars["Log Food"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 15), "Confirm step for \(name)")
            attachShot(named: "menu-confirm-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))")
            app.buttons["Log"].firstMatch.tap()
            // Back on the list, with the receipt of what just happened.
            let noteText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", note)
            ).firstMatch
            XCTAssertTrue(noteText.waitForExistence(timeout: 15),
                          "The list should return, reading “\(note)”")
        }

        logItem("Sample Bowl", expectFinalNote: "Logged Sample Bowl")
        // THE assertion: a second pick off a list that was supposed to be
        // gone.
        logItem("Sample Fries", expectFinalNote: "Logged 2 items")
        attachShot(named: "menu-picker-after-two")

        app.buttons["Done"].firstMatch.tap()
        // Done closes the picker AND the scan sheet, landing back in the
        // Log sheet the pill opened.
        XCTAssertTrue(logTitle.waitForExistence(timeout: 10),
                      "Done should return to the Log sheet")
        app.buttons["Done"].firstMatch.tap()

        // Both logs actually landed in the day — the picker's own note
        // is the flow's word for it, this is Health's. Meal sections
        // start collapsed, so the rows have to be opened before they can
        // be asserted on.
        switchTab(in: app, to: "Today")
        XCTAssertTrue(
            app.buttons.matching(collapsedSectionPredicate).firstMatch.waitForExistence(timeout: 20),
            "Today's log should render meal-slot sections")
        expandMealSections(in: app)
        // The source is appended at pick time, so the entries read
        // "Sample Bowl (Sample Cafe)" — matched by prefix.
        for name in ["Sample Bowl", "Sample Fries"] {
            let entry = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", name)
            ).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 15),
                          "\(name) should be in today's log")
        }
        attachShot(named: "menu-loop-today")

        // Leg 2 — the other half of the purpose split. The SAME list
        // reached from a blank Add Food form fills the form and stops:
        // a door inside a form that started writing to Health would be
        // a different feature. So here a pick must produce a form, and
        // must NOT produce a confirm step.
        switchTab(in: app, to: "Foods")
        switchTab(in: app, to: "Add")
        let addFood = app.buttons["Add Food"]
        XCTAssertTrue(addFood.waitForExistence(timeout: 5), "Add Food chooser option")
        addFood.tap()
        let formScan = scanRow(in: app)
        XCTAssertTrue(formScan.waitForExistence(timeout: 5), "Scan row in the food form")
        formScan.tap()
        let formSample = app.buttons["menuScanSample"]
        XCTAssertTrue(formSample.waitForExistence(timeout: 10), "Sample menu row")
        formSample.tap()
        let formPicker = app.navigationBars["Choose an Item"]
        XCTAssertTrue(formPicker.waitForExistence(timeout: 10), "The picker should be up")
        let shake = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Sample Shake'")
        ).firstMatch
        XCTAssertTrue(shake.waitForExistence(timeout: 10), "Sample Shake row")
        shake.tap()

        // The form, filled — and no Log Food step on the way, which is
        // what tells the two purposes apart.
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 15),
                      "A pick in the form's door should fill the form")
        XCTAssertFalse(app.navigationBars["Log Food"].exists,
                       "Filling a form must not raise the confirm step")
        let named = expectation(
            for: NSPredicate(format: "value CONTAINS[c] 'sample shake'"),
            evaluatedWith: nameField)
        wait(for: [named], timeout: 15)
        attachShot(named: "menu-fills-form")
    }

    /// Tab-bar animation probe (`TEST_RUNNER_TAB_PROBE=1`): drives the
    /// exact tap sequence behind the Calendar→Today Liquid Glass stall so
    /// it can be screen-recorded on a simulator (`simctl io recordVideo`)
    /// and frame-analysed, instead of round-tripping a phone recording
    /// per build (2026-09-15, plans/PLAN-tab-bar-jank.md). The dwells are
    /// the point: each transition must settle before the next tap, or
    /// the capture measures interruption rather than the animation.
    /// Asserts nothing about smoothness — it can't; the recording is the
    /// assertion. Today→Calendar is the control that reportedly never
    /// sticks; the single-hop pair at the end separates "landing on
    /// Today" from "jumping three tabs."
    @MainActor
    func testTabBarAnimationProbe() throws {
        guard ProcessInfo.processInfo.environment["TAB_PROBE"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_TAB_PROBE=1 to run the tab-bar animation probe.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--seed-sample-data"]
        // Variant selection without a rebuild: TEST_RUNNER_TAB_PROBE_ARGS
        // ="--tab-probe-stock --tab-probe-no-search" etc. (ContentView's
        // StockTabProbe documents the set).
        if let extra = ProcessInfo.processInfo.environment["TAB_PROBE_ARGS"] {
            app.launchArguments += extra.split(separator: " ").map(String.init)
        }
        app.launch()
        // Health sheet only on a fresh container; the shared helper
        // tolerates its absence and knows both the 26.5 (Button) and
        // 27.0 (StaticText) shapes of its Allow row.
        grantHealthAccess(in: app, timeout: 10)
        dismissModals(in: app)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        for _ in 0..<3 {
            switchTab(in: app, to: "Calendar")
            Thread.sleep(forTimeInterval: 1.5)
            switchTab(in: app, to: "Today")
            Thread.sleep(forTimeInterval: 1.5)
        }
        switchTab(in: app, to: "Foods")
        Thread.sleep(forTimeInterval: 1.5)
        switchTab(in: app, to: "Today")
        Thread.sleep(forTimeInterval: 1.5)
    }
}
