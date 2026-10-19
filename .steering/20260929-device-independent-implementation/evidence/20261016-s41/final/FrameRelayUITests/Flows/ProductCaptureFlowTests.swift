import XCTest

final class ProductCaptureFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testOrdinaryCaptureWithoutTicketShowsSimulatorLimitationAndReturnsToLibrary() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulatorのカメラ利用不可表示を検証するケースです")
        #else
        let app = XCUIApplication()
        app.launch()
        let entry = app.buttons["product.capture"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let issue = app.staticTexts["capture.issue"]
        XCTAssertTrue(issue.waitForExistence(timeout: 10))
        XCTAssertTrue(issue.label.contains("Simulator"))
        XCTAssertFalse(app.buttons["capture.rec"].isEnabled)
        XCTAssertFalse(app.buttons["exploration.import"].exists)
        app.buttons["capture.closeToolbar"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.refresh"].exists)
        #endif
    }
}
