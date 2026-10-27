import XCTest

/// The Phase 1 prototype flow on the simulator: start screen, camera, a fixture product, the
/// product sheet, check another, close, start screen again.
final class PrototypeFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testScanFixtureShowsProductSheetAndReturnsHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-demoHousehold"]
        app.launch()

        // 1. Start screen with the demo household.
        let check = app.buttons["start.checkProduct"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["start.household"].label, "I check the ingredients for you and Mia.")
        check.tap()

        // 2. Camera: pick a fixture product (the simulator stands in for the scanner).
        let picker = app.buttons["scan.fixturePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let peanutButter = app.buttons["Creamy Peanut Butter"]
        XCTAssertTrue(peanutButter.waitForExistence(timeout: 5))
        peanutButter.tap()

        // 3. Product sheet: the engine's verdict and the disclaimer.
        let disclaimer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
                                                                "Check the package. Not medical advice.")).firstMatch
        XCTAssertTrue(disclaimer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Not for Mia")).firstMatch.exists)

        // 4. Check another: back to the frame.
        app.buttons["Check another"].firstMatch.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertFalse(disclaimer.exists)

        // 5. Close the camera: the start screen again.
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(check.waitForExistence(timeout: 5))
    }
}
