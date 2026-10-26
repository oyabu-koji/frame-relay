import XCTest

final class PhotoPermissionsFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// Run on the ordinary product entry, including when Photos read/add access
    /// was denied externally. No launch-time fixture or permission auto-dismissal.
    @MainActor func testOrdinaryLibraryRefreshAndCaptureDoNotRequestPhotosPermission() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()
        let capture = app.buttons["product.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
        let refresh = app.buttons["library.refresh"]
        XCTAssertTrue(refresh.exists)
        refresh.tap()
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
        capture.tap()
        let close = app.buttons["capture.closeToolbar"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["capture.rec"].exists)
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Ordinary capture without a Photos request"
        attachment.lifetime = .keepAlways
        add(attachment)
        close.tap()
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.refresh"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
    }
}
