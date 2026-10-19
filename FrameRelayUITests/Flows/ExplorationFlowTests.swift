import XCTest

final class ExplorationFlowTests: XCTestCase {
    @MainActor
    func testUnboundPreparationDoesNotClaimCameraCapabilityOrStartRecording() {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch()
        XCTAssertTrue(app.buttons["product.exploration"].waitForExistence(timeout: 5))
        app.buttons["product.exploration"].tap()
        XCTAssertTrue(app.staticTexts["exploration.purpose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["exploration.ticketStatus"].exists)
        reveal(app.staticTexts["exploration.capabilityStatus"], in: app, upwards: true)
        XCTAssertTrue(app.staticTexts["exploration.capabilityStatus"].exists)
        XCTAssertTrue(app.staticTexts["exploration.capabilityStatus"].label.contains("未照会"))
        reveal(app.buttons["exploration.rec"], in: app, upwards: true)
        XCTAssertTrue(app.buttons["exploration.rec"].exists)
        XCTAssertTrue(app.buttons["exploration.stop"].exists)
        XCTAssertFalse(app.buttons["exploration.rec"].isEnabled)
        XCTAssertFalse(app.buttons["exploration.stop"].isEnabled)
        reveal(app.buttons["exploration.prepare"], in: app, upwards: false)
        app.buttons["exploration.prepare"].tap()
        let ticketIssue = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "試験票が未束縛")).firstMatch
        reveal(ticketIssue, in: app, upwards: true)
        XCTAssertTrue(ticketIssue.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        reveal(app.staticTexts["exploration.capabilityStatus"], in: app, upwards: true)
        XCTAssertTrue(app.staticTexts["exploration.capabilityStatus"].label.contains("未照会"))
        #if targetEnvironment(simulator)
        reveal(app.staticTexts["exploration.simulator"], in: app, upwards: false)
        XCTAssertTrue(app.staticTexts["exploration.simulator"].exists)
        #endif
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
    }
}
