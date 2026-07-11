import XCTest

/// Drives the seeded app end to end: grants Health access sheets, verifies
/// the seeded log renders on Today, and logs a food from the library.
final class OnigiriUITests: XCTestCase {

    @MainActor
    func testSeedGrantAndLogFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-sample-data"]
        app.launch()

        // Health access sheets appear up to twice: once for the app's own
        // types, once for the debug seeder's extra write types.
        grantHealthAccess(in: app, timeout: 30)
        grantHealthAccess(in: app, timeout: 10)

        // Bounce tabs to trigger a Today refresh now that access is granted.
        app.tabBars.buttons["Foods"].tap()
        app.tabBars.buttons["Today"].tap()

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
        app.tabBars.buttons["Foods"].tap()
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

        app.tabBars.buttons["Today"].tap()
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
        app.staticTexts["Nutrition details"].tap()
        XCTAssertTrue(
            app.navigationBars["Nutrition"].waitForExistence(timeout: 10),
            "Meter grid should push the day nutrition detail"
        )
        // Groups are collapsed by default; expand to reach the rows.
        let macroGroup = app.staticTexts["Macronutrients"]
        XCTAssertTrue(macroGroup.waitForExistence(timeout: 5),
                      "Seeded meals should produce a macro group")
        macroGroup.tap()
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
        app.navigationBars["Nutrition"].buttons.firstMatch.tap()
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
        let calendarTab = app.tabBars.buttons["Calendar"]
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 5),
                      "Tab bar should be back after the sheet dismisses")
        calendarTab.tap()
        XCTAssertTrue(
            app.staticTexts["3 days"].waitForExistence(timeout: 10),
            "Seeded history should produce a 3-day streak"
        )

        // Log rows delete by swipe now (library-consistent, trash icons
        // gone). Water was 36 oz across three 12 oz rows; deleting one
        // brings the hydration row back to 24 — and the day-paging swipe
        // must stand down, so the title stays "Today".
        app.tabBars.buttons["Today"].tap()
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
        XCTAssertTrue(app.navigationBars["Today"].exists,
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
        let calendarTabAgain = app.tabBars.buttons["Calendar"]
        XCTAssertTrue(calendarTabAgain.waitForExistence(timeout: 5))
        calendarTabAgain.tap()

        // Predicted vs actual moved off the card into the pushed month
        // detail. Seeded data has a month of weigh-ins and deficit days,
        // so both rows should carry real values (assert on lb, not —).
        app.staticTexts["Month details"].tap()
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
        app.tabBars.buttons["Foods"].tap()
        app.tabBars.buttons["Today"].tap()
        _ = app.buttons.matching(collapsedSectionPredicate).firstMatch.waitForExistence(timeout: 20)
        expandMealSections(in: app)
        scene("today")

        app.staticTexts["Nutrition details"].tap()
        let macros = app.staticTexts["Macronutrients"]
        if macros.waitForExistence(timeout: 5) {
            macros.tap()
            Thread.sleep(forTimeInterval: 0.6)
            let minerals = app.staticTexts["Minerals"]
            if minerals.isHittable { minerals.tap() }
        }
        scene("nutrition")
        app.navigationBars["Nutrition"].buttons.firstMatch.tap()
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
        let foodsTab = app.tabBars.buttons["Foods"]
        _ = foodsTab.waitForExistence(timeout: 5)
        foodsTab.tap()
        scene("foods")

        app.tabBars.buttons["Calendar"].tap()
        _ = app.staticTexts["Month details"].waitForExistence(timeout: 10)
        scene("calendar")
        app.staticTexts["Month details"].tap()
        scene("month", hold: 3.5)
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Goal"].tap()
        scene("goal")
        app.swipeUp()
        scene("goal-trend", hold: 3)
        app.swipeDown()

        app.tabBars.buttons["Today"].tap()
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

        func shot(_ name: String, settle: TimeInterval = 0.8) {
            Thread.sleep(forTimeInterval: settle)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "qa-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func tab(_ name: String) {
            app.swipeDown()
            let button = app.tabBars.buttons[name]
            _ = button.waitForExistence(timeout: 5)
            button.tap()
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
        app.tabBars.buttons["Foods"].tap()
        app.tabBars.buttons["Today"].tap()
        _ = app.buttons.matching(collapsedSectionPredicate).firstMatch.waitForExistence(timeout: 20)
        shot("today-collapsed")
        expandMealSections(in: app)
        shot("today-expanded")

        // Past days: seeded day-3 has entries; day-5 is empty.
        for _ in 0..<3 { app.buttons["Previous day"].tap() }
        shot("past-day-with-data")
        app.staticTexts["Nutrition details"].tap()
        shot("nutrition-past-day")
        app.navigationBars["Nutrition"].buttons.firstMatch.tap()
        for _ in 0..<2 { app.buttons["Previous day"].tap() }
        shot("past-day-empty")
        app.staticTexts["Nutrition details"].tap()
        shot("nutrition-empty-day")
        app.navigationBars["Nutrition"].buttons.firstMatch.tap()

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
        if tapIfExists(app.staticTexts["Month details"]) {
            shot("month-detail-sparse", settle: 1.0)
            tapIfExists(app.navigationBars.buttons.firstMatch)
        }
        tapIfExists(app.buttons["Next month"])

        // Settings: pushed icon picker + data section.
        tab("Today")
        if tapIfExists(app.buttons["Settings"]) {
            _ = app.staticTexts["Reminders"].waitForExistence(timeout: 5)
            shot("settings-top")
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

        app.tabBars.buttons["Goal"].tap()
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

        app.tabBars.buttons["Foods"].tap()
        let addMenu = app.buttons["Add"]
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
        app.tabBars.buttons["Today"].tap()
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
        app.tabBars.buttons["Today"].tap()
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
            let onMyIphone = app.staticTexts["On My iPhone"]
            if onMyIphone.waitForExistence(timeout: 4) {
                onMyIphone.tap()
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
        let sheet = app.navigationBars["Health Access"]
        guard sheet.waitForExistence(timeout: timeout) else { return }

        let turnOnAll = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        if turnOnAll.waitForExistence(timeout: 5) {
            turnOnAll.tap()
        }

        let allow = app.buttons["Allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5), "Allow should enable after Turn On All")
        allow.tap()
        _ = sheet.waitForNonExistence(timeout: 10)
    }
}
