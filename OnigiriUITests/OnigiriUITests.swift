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

        // Seeded food correlations should appear in the Today log.
        XCTAssertTrue(
            app.staticTexts["Chicken burrito"].waitForExistence(timeout: 20),
            "Seeded lunch should render in the Logged today list"
        )
        XCTAssertTrue(app.staticTexts["Two eggs & toast"].exists)

        // One-tap logging from the Foods library.
        app.tabBars.buttons["Foods"].tap()
        let shake = app.staticTexts["Protein shake"]
        XCTAssertTrue(shake.waitForExistence(timeout: 10), "Seeded library should list foods")
        shake.tap()

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(
            app.staticTexts["Protein shake"].waitForExistence(timeout: 10),
            "Tapped food should appear in the Logged today list"
        )

        // Water quick-add: seeded 24 oz + one 12 oz serving = 36.
        app.tabBars.buttons["Water"].tap()
        let addWater = app.buttons["Add 12 oz"]
        XCTAssertTrue(addWater.waitForExistence(timeout: 10), "Water quick-add should render")
        XCTAssertTrue(app.staticTexts["24"].waitForExistence(timeout: 10), "Seeded water total should show")
        addWater.tap()
        XCTAssertTrue(
            app.staticTexts["36"].waitForExistence(timeout: 10),
            "Ring total should update after quick-add"
        )
    }

    /// Barcode → OpenFoodFacts lookup prefills the food form. Uses the
    /// manual-entry fallback (no camera in the simulator) and live network.
    @MainActor
    func testBarcodeLookupPrefillsForm() throws {
        let app = XCUIApplication()
        app.launch()
        grantHealthAccess(in: app, timeout: 10)

        app.tabBars.buttons["Foods"].tap()
        app.navigationBars["Foods"].buttons.element(boundBy: 0).tap()
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
