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
