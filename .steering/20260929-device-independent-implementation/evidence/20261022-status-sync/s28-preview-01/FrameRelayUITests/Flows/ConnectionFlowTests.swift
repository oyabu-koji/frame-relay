import XCTest

/// Exercises the real product entry without changing its existing library or credentials.
/// The separate authorized HTTP loopback probe covers the registration chain, not product HTTPS UI success.
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

    /// Requires the separately seeded, dedicated synthetic Simulator. It uses
    /// the unchanged normal App composition and a refused local HTTPS endpoint.
    @MainActor func testRegisteredMetadataSynchronizationPreservesSavedPublication() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["FR_S28_STATUS_UI"] == "1" else { throw XCTSkip("Explicit S28 dedicated metadata UI fixture is not enabled") }
        let nonce = try XCTUnwrap(env["FR_S28_STATUS_NONCE"])
        XCTAssertEqual(UUID(uuidString: nonce)?.uuidString.lowercased(), nonce)
        let expected = try XCTUnwrap(env["FR_S28_STATUS_SIMULATOR_UDID"])
        XCTAssertNotNil(UUID(uuidString: expected))
        XCTAssertEqual(env["SIMULATOR_UDID"], expected)
        let app = XCUIApplication(); app.launch()
        let entry = app.buttons["product.connection"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertTrue(app.staticTexts["connection.registered"].waitForExistence(timeout: 10))
        let synchronize = app.buttons["connection.synchronize"]
        XCTAssertTrue(synchronize.waitForExistence(timeout: 5)); XCTAssertTrue(synchronize.isEnabled)
        synchronize.tap()
        let result = app.staticTexts["connection.synchronization.state"]
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        XCTAssertTrue(result.label.contains("一部"))
        XCTAssertTrue(synchronize.isEnabled)
        app.buttons["connection.close"].tap()
        XCTAssertTrue(app.buttons["library.refresh"].waitForExistence(timeout: 5))
        let video = app.buttons.containing(.staticText, identifier: "動画 s28-" + nonce).firstMatch
        // The library row includes the synthetic recording title and saved
        // publication. It is neither a completed media acquisition nor proof.
        let saved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "公開版の保存記録あり")).firstMatch
        if !saved.exists && video.exists { video.tap() }
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertTrue(app.staticTexts["connection.registered"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["connection.synchronization.state"].exists)
        app.buttons["connection.close"].tap()
    }
}
