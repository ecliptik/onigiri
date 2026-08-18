import XCTest

/// Drives the seeded app end to end: grants Health access sheets, verifies
/// the seeded log renders on Today, and logs a food from the library.

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
    anyTab.tap()
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
        // The in-content title still reads "Today" (a page would say
        // "Yesterday"); the nav bar no longer carries the day title.
        XCTAssertTrue(app.buttons["dayTitleButton"].label.hasPrefix("Today"),
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
        app.buttons["Log Two eggs & toast"].tap()
        _ = app.buttons["Log"].waitForExistence(timeout: 5)
        scene("portion", hold: 3)
        app.buttons["Log"].tap()

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

        func shot(_ name: String, settle: TimeInterval = 0.8) {
            Thread.sleep(forTimeInterval: settle)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "qa-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func tab(_ name: String) {
            app.swipeDown()
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
            // The Log sheet's own dismiss is "Done" now, so the only
            // Cancel on screen is the portion sheet's.
            app.buttons.matching(identifier: "Cancel").allElementsBoundByIndex.last?.tap()
        }
        // Search state last: focusing the field replaces toolbar buttons,
        // so the sheet gets torn down by relaunching instead.
        let searchField = app.searchFields.firstMatch
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
        shot("foods")
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
                // The inline database search (the shared section under
                // the bottom system field).
                let dbField = app.searchFields["Search OpenFoodFacts"]
                if tapIfExists(dbField) {
                    dbField.typeText("granola")
                    shot("food-form-db-search", settle: 1.2)
                    tapIfExists(app.buttons["Cancel"].firstMatch)
                }
                tapIfExists(app.buttons["Cancel"].firstMatch)
            }
        }
        // The edit shots need the Foods LIST back (the add-food flow
        // above leaves its sheet up) and the right scope per item: a
        // food shows in Foods, a meal ONLY in Meals/Favorites. Dismiss
        // any lingering sheet until the scope bar reappears, then pick
        // the scope. The meal shot silently skipped once Favorites (not
        // "All") became the default and the tour ran its scope walk from
        // Foods — hence the explicit Meals switch.
        var dismissTries = 0
        while !app.segmentedControls.firstMatch.waitForExistence(timeout: 2), dismissTries < 4 {
            if !tapIfExists(app.buttons["Cancel"].firstMatch, timeout: 1) {
                app.swipeDown()
            }
            dismissTries += 1
        }
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
            shot("food-form-edit", settle: 1.2)
            tapIfExists(app.buttons["Cancel"].firstMatch)
        }
        scopeTap(in: app, "Meals")
        if tapIfExists(app.buttons["Chicken & rice"].firstMatch, timeout: 5) {
            shot("meal-form-edit", settle: 1.2)
            tapIfExists(app.buttons["Cancel"].firstMatch)
        }

        // Goal, including the focused-keyboard state.
        tab("Goal")
        shot("goal")
        if tapIfExists(app.textFields.firstMatch) {
            shot("goal-keyboard")
            tapIfExists(app.buttons["Done"].firstMatch, timeout: 2)
        }

        // Calendar: previous month (little data), day picking, month detail.
        tab("Calendar")
        shot("calendar")
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
            .matching(NSPredicate(format: "label == 'How the budget is set'")).firstMatch
        // Below the fold, and a Form's rows don't exist in the tree until
        // scrolled near — waiting on one that isn't there just times out.
        XCTAssertTrue(scroll(app, until: howSet), "The budget explainer is reachable")
        // Open it and PROVE it opened before asserting a row is absent:
        // a shut group makes every absence trivially true.
        let restingRow = app.staticTexts["Resting burn, full day"]
        if !restingRow.exists { howSet.tap() }
        XCTAssertTrue(restingRow.waitForExistence(timeout: 5), "The group opens")
        XCTAssertFalse(app.staticTexts["Deficit needed"].exists, "No deficit row in maintenance")
        let save = app.buttons["Save"]
        XCTAssertTrue(save.isEnabled, "Mode change should enable Save")
        save.tap()

        switchTab(in: app, to: "Today")
        let budgetTitle = app.staticTexts["Daily budget"]
        XCTAssertTrue(budgetTitle.waitForExistence(timeout: 10), "Today card should read Daily budget")
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
        if !deficitRow.exists {
            XCTAssertTrue(scroll(app, until: howSet), "The explainer is reachable in lose mode")
            if !deficitRow.exists { howSet.tap() }
        }
        XCTAssertTrue(deficitRow.waitForExistence(timeout: 5), "Deficit row returns in lose mode")
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
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field at rest")
        attachShot(named: "foods-scroll-rest")

        // The drawer is pinned (.always): scrolling must not hide it —
        // the collapsing drawer re-expanded BLANK over the scope bar's
        // safeAreaInset (element present, field invisible).
        app.swipeUp()
        app.swipeUp()
        attachShot(named: "foods-scrolled-down")
        XCTAssertTrue(search.exists, "Pinned search field visible mid-scroll")
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
        // `EntryDoorsSection` now renders in exactly two places — the
        // Log sheet and a blank food form — and the Add tab IS the Log
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

        // Leg 2 — the Foods screen's own Scan Label row: same pipeline,
        // but the handoff re-presents the single sheet slot as the
        // prefilled form (the unknown-barcode route). Values scanned IN
        // a blank form make it dirty, so this Cancel confirms first —
        // and the form must be GONE before tapping, or the form's own
        // Scan Label row shadows the Foods row.
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
        let foodsScanLabel = scanRow(in: app)
        XCTAssertTrue(foodsScanLabel.waitForExistence(timeout: 5), "Scan Label row on Foods")
        attachShot(named: "label-scan-foods-rows")
        foodsScanLabel.tap()
        XCTAssertTrue(sample.waitForExistence(timeout: 5), "Sample row from the Foods surface")
        sample.tap()
        XCTAssertTrue(
            fieldWithValue("280").waitForExistence(timeout: 20),
            "Foods scan handed off to the prefilled form")
        attachShot(named: "label-scan-foods-handoff")

        // Leg 3 — the Log sheet's row (opened via the corner pill from
        // Today); its form carries the log date back. This form arrived
        // prefilled (untouched), so its Cancel dismisses without the
        // confirm — closeFoodForm handles either way.
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
        let search = app.searchFields["Foods, Meals, and More"].firstMatch
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
        XCTAssertTrue(app.buttons["Switch to Maintain"].firstMatch.exists,
                      "Maintain is offered")
        let keepGoing = app.buttons["5 lb more"].firstMatch
        XCTAssertTrue(keepGoing.waitForExistence(timeout: 5), "Quick amounts are offered")
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
        for tab in ["Foods", "Goal", "Calendar"] {
            switchTab(in: app, to: tab)
            attachShot(named: "tab-\(tab.lowercased())", settle: 2)
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
        }
        switchTab(in: app, to: "Today")
        // Tolerant: the corner slot's element shape differs on iPad and
        // the tab shots above are this test's real product.
        let addTab = app.buttons["Add"].firstMatch
        if addTab.waitForExistence(timeout: 5), addTab.isHittable {
            addTab.tap()
            attachShot(named: "log-sheet", settle: 2)
        }
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
        attachShot(named: "metric-slot-settings")
        app.buttons["Done"].tap()

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
        app.buttons["Settings"].tap()
        XCTAssertTrue(metricsRow.waitForExistence(timeout: 10))
        metricsRow.tap()
        XCTAssertTrue(metricRow.waitForExistence(timeout: 10))
        metricRow.tap()
        // Single-text rows flatten to a Button with no StaticText child.
        let none = app.buttons["None"].firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 5), "None in the picker")
        none.tap()
        app.buttons["Done"].tap()
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
        let nameField = app.textFields["zzqxvbnfood"]
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

        let searchField = app.searchFields.firstMatch
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
        let logTitle = app.navigationBars["Log"]
        if !logTitle.waitForExistence(timeout: 10) {
            switchTab(in: app, to: "Add")
        }
        XCTAssertTrue(logTitle.waitForExistence(timeout: 10), "Log sheet should be up")

        let searchField = app.searchFields.firstMatch
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
        app.buttons["Done"].firstMatch.tap()
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
        // The form's own bottom system search field; results render
        // inline via the shared section. By placeholder: the Foods
        // screen's search bar sits behind the sheet.
        let field = app.searchFields["Search OpenFoodFacts"]
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
        var swipes = 0
        while swipes < 12 {
            app.swipeUp(velocity: .fast)
            swipes += 1
            if throttled.exists { break }
            if rowCount(app) > before { break }
        }
        Thread.sleep(forTimeInterval: 3)
        let after = rowCount(app)
        attachShot(named: "form-paging-bottom")
        XCTAssertTrue(
            after > before || throttled.exists,
            "Form search paged (\(before)→\(after)) or throttled gracefully"
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
        XCTAssertTrue(app.buttons["dayTitleButton"].waitForExistence(timeout: 10),
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
            dismissHealthSyncPrompt(in: app)
            return
        }

        let turnOnAll = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        if turnOnAll.waitForExistence(timeout: 5) {
            turnOnAll.tap()
        }

        let allow = app.buttons["Allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5), "Allow should enable after Turn On All")
        allow.tap()
        _ = sheet.waitForNonExistence(timeout: 10)
        dismissHealthSyncPrompt(in: app)
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

        // The in-content large title doubles as the date control, and its
        // label carries the browsed day ("Today. Jump to date").
        let dayTitle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Jump to date'")
        ).firstMatch
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 30), "Today's date control should render")
        XCTAssertTrue(
            dayTitle.label.contains("Today"),
            "should open on today, got '\(dayTitle.label)'"
        )

        // Page back. Asserting the move is load-bearing: without it a
        // tab tap that does nothing would still end on "Today" and this
        // test would pass while proving nothing.
        let previousDay = app.buttons["Previous day"]
        XCTAssertTrue(previousDay.waitForExistence(timeout: 10), "day pager should exist")
        previousDay.tap()
        previousDay.tap()
        let movedAway = expectation(
            for: NSPredicate(format: "NOT (label CONTAINS 'Today')"),
            evaluatedWith: dayTitle
        )
        wait(for: [movedAway], timeout: 10)

        // The re-tap: already on Today, two days back.
        switchTab(in: app, to: "Today")
        let cameHome = expectation(
            for: NSPredicate(format: "label CONTAINS 'Today'"),
            evaluatedWith: dayTitle
        )
        wait(for: [cameHome], timeout: 10)

        // And from another tab, since "always" covers that too.
        previousDay.tap()
        wait(for: [expectation(
            for: NSPredicate(format: "NOT (label CONTAINS 'Today')"),
            evaluatedWith: dayTitle
        )], timeout: 10)
        switchTab(in: app, to: "Foods")
        switchTab(in: app, to: "Today")
        wait(for: [expectation(
            for: NSPredicate(format: "label CONTAINS 'Today'"),
            evaluatedWith: dayTitle
        )], timeout: 10)
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
}
