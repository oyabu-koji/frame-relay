import XCTest

extension XCTestCase {
    /// Register before launch so an assertion/audit failure still closes a live
    /// product player through its UI. Never erase or repair the reader ledger.
    @MainActor func registerPlaybackCleanup(for app: XCUIApplication) {
        addTeardownBlock { @MainActor in
            guard app.state != .notRunning else { return }
            if app.state != .runningForeground { app.activate() }
            let close = app.buttons["originalPlayback.close"]
            guard close.waitForExistence(timeout: 2) else { return }
            let status = app.descendants(matching: .any).matching(identifier: "originalPlayback.status").firstMatch
            let stop = app.buttons["originalPlayback.stop"]
            if stop.exists && stop.isEnabled { stop.tap() }
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                ["再生を停止しました", "再生が終了しました", "原本を再生できませんでした", "読み取り終了の照合が必要です"].contains(status.label)
            }, object: nil)
            let result = XCTWaiter.wait(for: [settled], timeout: 15)
            if result != .completed || status.label == "読み取り終了の照合が必要です" {
                let evidence = XCTAttachment(string: app.debugDescription)
                evidence.name = "playback-cleanup-unresolved"; evidence.lifetime = .keepAlways
                self.add(evidence)
                XCTFail("Playback cleanup remains unconfirmed; preserve its reader ledger")
            }
            close.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !close.exists && !status.exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 15), .completed,
                           "Wait for the product close operation to finish")
        }
    }
}
