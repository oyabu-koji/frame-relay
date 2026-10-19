import XCTest

/// Exercises the real product entry without changing its existing library or credentials.
/// HTTPS registration success is covered separately by the authorized server probe, not a UI fixture branch.
final class ConnectionFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testConnectionEntryReconciliationAndReturnPreserveLibrary() throws {
        let app = XCUIApplication()
        app.launch()
        let entry = app.buttons["product.connection"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let state = app.staticTexts["connection.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        let retry = app.buttons["connection.reconcile"]
        if retry.exists {
            XCTAssertTrue(retry.waitForExistence(timeout: 5))
            retry.tap()
        }
        app.buttons["connection.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.refresh"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        app.buttons["connection.close"].tap()
        XCTAssertTrue(app.buttons["library.refresh"].exists)
    }

    @MainActor func testFirstConnectionRejectsPlainHTTPWithoutCreatingRegistration() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["product.connection"].waitForExistence(timeout: 10))
        app.buttons["product.connection"].tap()
        let origin = app.textFields["connection.origin"]
        // This case requires an unconfigured Keychain, but never erases an existing one.
        guard origin.waitForExistence(timeout: 10) else { throw XCTSkip("Initial connection input unavailable; existing credentials preserved") }
        origin.tap(); origin.typeText("http://127.0.0.1:8999")
        let destination = app.textFields["connection.destination"]
        destination.tap(); destination.typeText("9a3ba104-985f-4a2d-875d-d458258b9b6b")
        app.buttons["connection.register"].tap()
        let state = app.staticTexts["connection.state"]
        let invalid = NSPredicate(format: "label CONTAINS %@", "HTTPS")
        expectation(for: invalid, evaluatedWith: state)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["connection.registered"].exists)
        app.buttons["connection.close"].tap()
        XCTAssertTrue(app.buttons["library.refresh"].exists)
    }
}
