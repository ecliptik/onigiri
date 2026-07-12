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
        let waterButton = app.buttons["Log 12 ounces of water"]
        XCTAssertTrue(waterButton.waitForExistence(timeout: 10), "Today should show the +water button")
        waterButton.tap()
        XCTAssertTrue(
            app.staticTexts["36 / 64 oz water"].waitForExistence(timeout: 10),
            "Hydration total should update after the one-tap log"
        )

        // The meter grid drills into the day's full nutrient breakdown,
        // summed from the seeded meals' extended nutrients.
        app.staticTexts["Details"].tap()
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
        app.buttons["Log food or meal"].tap()
        XCTAssertTrue(
            app.staticTexts["Recent"].waitForExistence(timeout: 10),
            "Log sheet should lead with a Recent section"
        )
        let recentBurrito = app.buttons["Log Chicken burrito"]
        XCTAssertTrue(recentBurrito.waitForExistence(timeout: 5),
                      "History-only food should surface in Recents")
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
        let waterRow = app.staticTexts["12 oz"].firstMatch
        XCTAssertTrue(waterRow.waitForExistence(timeout: 10),
                      "Water rows should be visible once expanded")
        // The water group sits at the bottom of the expanded log.
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
        // Deletes confirm now (library-consistent): a centered alert.
        let confirmDelete = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5),
                      "Full swipe should ask for confirmation")
        confirmDelete.tap()
        XCTAssertTrue(app.staticTexts["24 / 64 oz water"].waitForExistence(timeout: 10),
                      "Confirming should delete the water row")
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
        app.buttons["Log"].tap()
        XCTAssertTrue(app.staticTexts["360 kcal"].waitForExistence(timeout: 10),
                      "Editing to 2 servings should double the logged entry")
        // Scroll back up so the minimized tab bar re-expands.
        app.swipeDown()
        switchTab(in: app, to: "Calendar")

        // Predicted vs actual moved off the card into the pushed month
        // detail. Seeded data has a month of weigh-ins and deficit days,
        // so both rows should carry real values (assert on lb, not —).
        app.staticTexts["Details"].tap()
        let predictedRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Predicted, by deficit' AND label CONTAINS 'lb'"))
            .firstMatch
        XCTAssertTrue(predictedRow.waitForExistence(timeout: 10),
                      "Month detail should show a predicted change in lb")
        let scaleRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Scale change' AND label CONTAINS 'lb'"))
            .firstMatch
        XCTAssertTrue(scaleRow.exists, "Month detail should show the scale change in lb")
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

        app.staticTexts["Details"].tap()
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

        app.buttons["Log food or meal"].tap()
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
        _ = app.staticTexts["Details"].waitForExistence(timeout: 10)
        scene("calendar")
        app.staticTexts["Details"].tap()
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
        app.staticTexts["Details"].tap()
        shot("nutrition-past-day")
        app.navigationBars["Details"].buttons.firstMatch.tap()
        for _ in 0..<2 { app.buttons["Previous day"].tap() }
        shot("past-day-empty")
        app.staticTexts["Details"].tap()
        shot("nutrition-empty-day")
        app.navigationBars["Details"].buttons.firstMatch.tap()

        // Back to today via chevrons (the title menu isn't reliably
        // hittable from tests; the jump sheet is a stock DatePicker).
        for _ in 0..<5 { app.buttons["Next day"].tap() }

        // Log sheet: kinds, no-match search, portion sheet.
        app.buttons["Log food or meal"].tap()
        _ = app.staticTexts["Recent"].waitForExistence(timeout: 10)
        shot("logsheet-all")
        // At accessibility sizes the kind picker is a menu, not segments;
        // segment shots only make sense in the normal pass.
        if app.segmentedControls.count > 0 {
            let kindPicker = app.segmentedControls.firstMatch
            kindPicker.buttons["Meals"].tap()
            shot("logsheet-meals")
            kindPicker.buttons["Foods"].tap()
            shot("logsheet-foods")
        }
        let logShakeRow = app.buttons["Log Protein shake"].firstMatch
        for _ in 0..<3 where !logShakeRow.isHittable {
            app.swipeUp()
        }
        if tapIfExists(logShakeRow) {
            shot("portion-sheet")
            // The half-height portion sheet leaves the Log sheet's Cancel
            // hittable behind it — the topmost (last) Cancel is the portion's.
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

        // Foods: filter menu, add menu, forms.
        tab("Foods")
        shot("foods")
        if tapIfExists(app.buttons["Filter by category"]) {
            shot("foods-filter-menu")
            if tapIfExists(app.buttons["Breakfast"].firstMatch) {
                shot("foods-filtered-breakfast")
                tapIfExists(app.buttons["Filter by category"])
                tapIfExists(app.buttons["All"].firstMatch)
            }
        }
        if tapIfExists(app.buttons["Add food or meal"], timeout: 5) {
            shot("foods-add-menu")
            if tapIfExists(app.buttons["Add Food"]) {
                shot("food-form-new", settle: 1.2)
                tapIfExists(app.buttons["Cancel"].firstMatch)
            }
        }
        if tapIfExists(app.staticTexts["Protein shake"].firstMatch) {
            shot("food-form-edit", settle: 1.2)
            tapIfExists(app.buttons["Cancel"].firstMatch)
        }
        if tapIfExists(app.staticTexts["Chicken & rice"].firstMatch) {
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
        if tapIfExists(app.staticTexts["Details"]) {
            shot("month-detail-sparse", settle: 1.0)
            tapIfExists(app.navigationBars.buttons.firstMatch)
        }
        tapIfExists(app.buttons["Next month"])

        // Settings: pushed icon picker + data section.
        tab("Today")
        if tapIfExists(app.buttons["Settings"]) {
            _ = app.staticTexts["Reminders"].waitForExistence(timeout: 5)
            shot("settings-top")
            // Leave gauges ON so today-final captures the ring + fills.
            // Coordinate tap at the row's trailing edge: the switch query
            // alone failed to register taps on this SwiftUI toggle.
            var gauges = app.switches["Progress gauges"].firstMatch
            if !gauges.waitForExistence(timeout: 2) {
                gauges = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == 'Progress gauges'")).firstMatch
                _ = gauges.waitForExistence(timeout: 2)
            }
            if gauges.exists {
                gauges.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            // Hide the water metric via the second slot's None option:
            // today-final shows sodium only.
            let metricRows = app.staticTexts.matching(identifier: "Metric")
            if metricRows.count >= 2 {
                metricRows.element(boundBy: 1).tap()
                if tapIfExists(app.staticTexts["None"]) {
                    shot("settings-metric-none", settle: 0.5)
                }
            }
            shot("settings-gauges-on", settle: 0.5)
            if tapIfExists(app.staticTexts["Food icon"]) {
                shot("settings-food-icon-picker")
                tapIfExists(app.navigationBars.buttons.firstMatch)
            }
            app.swipeUp()
            shot("settings-bottom")
            tapIfExists(app.buttons["Done"])
        }
        shot("today-final")
    }

    /// Today's meal-slot sections start collapsed; their header buttons say
    /// so in the accessibility label ("Lunch, 680 kcal, collapsed").
    private var collapsedSectionPredicate: NSPredicate {
        NSPredicate(format: "label CONTAINS 'collapsed'")
    }

    /// Expand every collapsed meal section so entry rows are hittable.
    @MainActor
    private func expandMealSections(in app: XCUIApplication) {
        let collapsed = app.buttons.matching(collapsedSectionPredicate)
        for _ in 0..<4 {
            guard collapsed.count > 0 else { return }
            collapsed.firstMatch.tap()
        }
    }

    /// The decimal pad has no return key; the Goal tab shows a nav-bar Done
    /// while a weight field is focused, and tapping it dismisses the keyboard.
    @MainActor
    func testGoalKeyboardDoneDismisses() throws {
        let app = XCUIApplication()
        app.launch()
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Goal")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Weight field should exist")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard should appear")

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Done should appear while editing")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Keyboard should dismiss")
    }

    /// Barcode → OpenFoodFacts lookup prefills the food form. Uses the
    /// manual-entry fallback (no camera in the simulator) and live network.
    @MainActor
    func testBarcodeLookupPrefillsForm() throws {
        let app = XCUIApplication()
        app.launch()
        grantHealthAccess(in: app, timeout: 10)

        switchTab(in: app, to: "Foods")
        let addMenu = app.buttons["Add food or meal"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 10), "Add menu")
        addMenu.tap()
        let addFood = app.buttons["Add Food"]
        XCTAssertTrue(addFood.waitForExistence(timeout: 5), "Add Food menu item")
        addFood.tap()

        let scan = app.buttons["Scan barcode"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5), "Scan button in food form")
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

    /// Adds the MEDIUM widget, opens Edit Widget, and verifies the meal
    /// picker lists a synced meal. Opt in via EDIT_WIDGET=1.
    @MainActor
    func testEditWidgetMealPicker() throws {
        guard ProcessInfo.processInfo.environment["EDIT_WIDGET"] == "1" else {
            throw XCTSkip("Set EDIT_WIDGET=1 to run the widget config test")
        }
        // Launch the app once so the meal mirror is written to the App Group.
        let app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 3)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)

        // Add the widget from the gallery, paging to the medium family.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 2)
        let edit = springboard.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Jiggle-mode Edit")
        edit.tap()
        let addWidget = springboard.buttons["Add Widget"]
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5), "Add Widget menu item")
        addWidget.tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8), "Gallery search")
        search.tap()
        search.typeText("Onigiri")
        let result = springboard.staticTexts["Onigiri"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8), "Gallery result")
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let add = springboard.buttons[" Add Widget"].exists
            ? springboard.buttons[" Add Widget"]
            : springboard.buttons["Add Widget"]
        XCTAssertTrue(add.waitForExistence(timeout: 8), "Add Widget confirm")
        var hops = 0
        while !springboard.staticTexts["Calorie Meter"].exists && hops < 3 {
            if springboard.pageIndicators.firstMatch.exists {
                springboard.pageIndicators.firstMatch
                    .coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
            } else {
                springboard.swipeLeft()
            }
            hops += 1
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(springboard.staticTexts["Calorie Meter"].exists, "Should reach the medium widget page")
        add.tap()
        let done = springboard.buttons["Done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }
        Thread.sleep(forTimeInterval: 3)

        // Long-press the widget (an icon whose label mentions Onigiri content)
        // until we find the one with an Edit Widget menu item.
        let editWidgetItem = springboard.buttons["Edit Widget"]
        let candidates = springboard.icons.matching(
            NSPredicate(format: "(label CONTAINS[c] 'Onigiri' OR label CONTAINS[c] 'kcal' OR label CONTAINS[c] 'Calorie') AND NOT label CONTAINS[c] 'Runner'")
        )
        var opened = false
        for index in 0..<min(candidates.count, 6) {
            let candidate = candidates.element(boundBy: index)
            guard candidate.exists, candidate.isHittable else { continue }
            candidate.press(forDuration: 2)
            if editWidgetItem.waitForExistence(timeout: 3) {
                opened = true
                break
            }
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(opened, "Edit Widget menu should appear")
        editWidgetItem.tap()

        // Tap the Meal parameter and expect the synced meal as an option.
        let mealParam = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Meal'")).firstMatch
        XCTAssertTrue(mealParam.waitForExistence(timeout: 8), "Meal parameter row")
        mealParam.tap()
        let option = springboard.staticTexts["Chicken & rice"]
        XCTAssertTrue(option.waitForExistence(timeout: 10), "Synced meal should be listed")
        option.tap()
        XCUIDevice.shared.press(.home)
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
        Thread.sleep(forTimeInterval: 2)

        // The picker dismisses back into the Form; the message lives in the
        // Data section which may need re-scrolling into view.
        let confirmation = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Imported'")
        ).firstMatch
        var confirmScrolls = 0
        while !confirmation.exists && confirmScrolls < 6 {
            app.swipeUp()
            confirmScrolls += 1
        }
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
        XCTAssertTrue(
            app.staticTexts["Protein shake"].waitForExistence(timeout: 10),
            "Imported food appears in Foods"
        )
        attachShot(named: "imported")
    }

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
        let addMenu = app.buttons["Add food or meal"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 10), "Add menu")
        addMenu.tap()
        app.buttons["Add Food"].tap()
        let dbSearch = app.buttons["Search database"]
        XCTAssertTrue(dbSearch.waitForExistence(timeout: 10), "Form search row")
        dbSearch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Search sheet field")
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
        grantHealthAccess(in: app, timeout: 30)
        Thread.sleep(forTimeInterval: 3)
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
}
