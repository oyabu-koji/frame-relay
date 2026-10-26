import XCTest

/// The ordinary product composition reads the separate opt-in Unit seed.
/// No App launch flag, injected transport, original removal or media request.
final class RemoteInventoryFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testRemoteCatalogConflictFailedMetadataRefreshAndRelaunch() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["FR_S28_INVENTORY_UI"] == "1" else { throw XCTSkip("Dedicated remote-inventory normal root is not enabled") }
        let nonce = try XCTUnwrap(env["FR_S28_INVENTORY_NONCE"])
        let requested = try XCTUnwrap(env["FR_S28_INVENTORY_SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let actual = try XCTUnwrap(env["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let dedicated = UUID(uuidString: "FCEE8D70-F5E1-4566-91CE-2BFE917582DE")!
        XCTAssertEqual(UUID(uuidString: nonce)?.uuidString.lowercased(), nonce)
        guard requested == dedicated, actual == dedicated else { throw InventoryUIFailure.wrongEnvironment }
        let context = XCTAttachment(string: "nonce=\(nonce) simulator=\(dedicated.uuidString)\nDedicated synthetic metadata only. Unit VERIFY checks actual local/external hashes and immutable journal/Keychain. Positive HTTPS, Log/Rec709 and device acceptance are not asserted.")
        context.name = "remote-inventory-bound-context"; context.lifetime = .keepAlways; add(context)
        let prefix = "s28i-" + nonce
        let app = XCUIApplication(); app.launch()
        try assertCatalog(app, prefix: prefix)
        let entry = app.buttons["product.connection"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        let registered = app.staticTexts["connection.registered"]
        try reveal(registered, app)
        XCTAssertTrue(registered.waitForExistence(timeout: 10))
        XCTAssertEqual(registered.label, "登録世代 1")
        let discover = app.buttons["connection.inventory"]
        try reveal(discover, app)
        XCTAssertTrue(discover.isEnabled)
        XCTAssertEqual(discover.label, "Macの保存記録を照合")
        let close = app.buttons["connection.close"]
        XCTAssertTrue(close.isHittable)
        let closeFrame = close.frame
        let synchronize = app.buttons["connection.synchronize"]
        try reveal(synchronize, app)
        XCTAssertTrue(synchronize.isEnabled)
        XCTAssertEqual(synchronize.label, "状態だけを同期")
        let synchronizationExplanation = element("connection.synchronization.explanation", app)
        try reveal(synchronizationExplanation, app)
        XCTAssertEqual(synchronizationExplanation.label, "公開版と保存済みの確認・失効記録を照合します。動画は送受信しません。")
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(close.frame, closeFrame)
        XCTAssertLessThanOrEqual(app.scrollViews["connection.content"].frame.maxY, close.frame.minY)
        try app.performAccessibilityAudit()
        try reveal(discover, app)
        try app.performAccessibilityAudit()
        discover.tap()
        let result = app.staticTexts["connection.inventory.state"]
        try wait("Refused local HTTPS must settle without claiming a completed discovery", timeout: 35) {
            result.exists && result.label.contains("保持") && discover.isEnabled
        }
        try reveal(result, app)
        XCTAssertTrue(result.label.contains("照合できません"))
        try app.performAccessibilityAudit()
        attach(app, "remote-inventory-refused-metadata-retains-records")
        app.buttons["connection.close"].tap()
        try assertCatalog(app, prefix: prefix)
        app.terminate(); app.launch()
        try assertCatalog(app, prefix: prefix)
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        let restored = app.staticTexts["connection.registered"]
        try reveal(restored, app)
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.label, "登録世代 1")
        XCTAssertFalse(app.staticTexts["connection.inventory.state"].exists)
        app.buttons["connection.close"].tap()
        try requireLibrary(app)
    }

    @MainActor private func assertCatalog(_ app: XCUIApplication, prefix: String) throws {
        try requireLibrary(app)
        try top(app)
        let local = app.descendants(matching: .any).matching(identifier: "library.item." + prefix + "-local").firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["library.empty"].exists)
        for (capture, conflict) in [(prefix + "-local", true), (prefix + "-remote-a", false), (prefix + "-remote-b", false)] {
            try top(app)
            let title = app.descendants(matching: .any).matching(NSPredicate(format:
                "identifier BEGINSWITH %@ AND label == %@", "library.remote.title.", "動画 " + capture)).firstMatch
            try reveal(title, app)
            let identifier = title.identifier
            XCTAssertTrue(identifier.hasPrefix("library.remote.title."))
            let token = String(identifier.dropFirst("library.remote.title.".count))
            let date = element("library.remote.date." + token, app)
            try reveal(date, app)
            XCTAssertEqual(date.label, "撮影日時不明")
            let storage = element("library.remote.storage." + token, app)
            try reveal(storage, app)
            XCTAssertTrue(storage.label.contains("Macの原本保存記録あり"))
            XCTAssertTrue(storage.label.contains("現在存在は未照合"))
            let original = element("library.remote.local." + token, app)
            try reveal(original, app)
            if conflict {
                XCTAssertTrue(original.label.contains("異なる内容") && original.label.contains("要照合"))
            } else { XCTAssertTrue(original.label.contains("原本保存記録との対応はありません")) }
            let media = element("library.remote.media." + token, app)
            try reveal(media, app)
            XCTAssertTrue(media.label.contains("取得・再生はまだ利用できません"))
            XCTAssertTrue(media.label.contains("確認済みになりません"))
            try app.performAccessibilityAudit()
            attach(app, "remote-inventory-" + capture)
        }
    }

    @MainActor private func requireLibrary(_ app: XCUIApplication) throws {
        let refresh = app.buttons["library.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 15))
        try wait("The preserved normal library must finish loading", timeout: 15) { refresh.isEnabled }
        XCTAssertFalse(element("library.loadFailure", app).exists)
    }
    @MainActor private func top(_ app: XCUIApplication) throws {
        let camera = app.buttons["product.capture"]
        for _ in 0..<32 {
            if camera.exists, camera.isHittable, camera.frame.midY > app.navigationBars.firstMatch.frame.maxY + 2 { return }
            app.swipeDown()
        }
        throw InventoryUIFailure.unreachable
    }
    @MainActor private func reveal(_ value: XCUIElement, _ app: XCUIApplication) throws {
        for _ in 0..<36 {
            if value.exists {
                let top = app.navigationBars.firstMatch.frame.maxY
                if value.isHittable, value.frame.midY > top + 2, value.frame.midY < app.frame.maxY - 8 { return }
                if value.frame.midY <= top + 2 { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        throw InventoryUIFailure.unreachable
    }
    @MainActor private func wait(_ message: String, timeout: TimeInterval, predicate: @escaping () -> Bool) throws {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expected], timeout: timeout) == .completed else {
            XCTFail(message); throw InventoryUIFailure.unexpectedState
        }
    }
    @MainActor private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private enum InventoryUIFailure: Error { case wrongEnvironment, unexpectedState, unreachable }
