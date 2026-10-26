import XCTest

/// Destructive actions require the exact fresh dedicated seed. Separate Unit
/// VERIFY checks actual unlink/hash/writer evidence; UI alone cannot prove it.
final class CleanupFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testFixedMultipleCleanupCancellationResultsAndRelaunch() throws {
        let captures = try captures(flag: "FR_CLEANUP_UI")
        let app = XCUIApplication()
        app.launch()
        try loaded(app)
        try requireFresh(captures, app)
        for capture in captures.selected { try select(capture, app) }
        try openReview(captures, app)
        attach(app, "cleanup-exact-multiple-review-before-cancel")
        try cancelReview(app)
        try wait("The cancelled review must close", app) { !app.buttons["確認した原本を整理"].exists }
        try requireFresh(captures, app)
        try openReview(captures, app)
        attach(app, "cleanup-explicit-confirmation-before-effects")
        let confirm = app.buttons["確認した原本を整理"]
        guard confirm.isHittable else { throw CleanupUIFailure.unreachable }
        confirm.tap()
        try wait("The confirmed review must close", app) { !app.buttons["確認した原本を整理"].exists }
        let batch = try requireCompleted(captures, app)
        attach(app, "cleanup-two-success-one-ineligible-normal-list")
        app.terminate(); app.launch()
        try loaded(app)
        XCTAssertEqual(try requireCompleted(captures, app), batch, "Reopening must retain the same fixed batch")
        attach(app, "cleanup-relaunch-same-batch-and-normal-list")
    }

    /// Read-only follow-up for the same completed root. The caller may set the
    /// Simulator's maximum text size before this run; there is no new deletion.
    @MainActor func testStoredCleanupResultsAccessibilityOnDedicatedSeed() throws {
        let captures = try captures(flag: "FR_CLEANUP_UI_REVIEW")
        let app = XCUIApplication(); app.launch()
        try loaded(app)
        _ = try requireCompleted(captures, app)
        try top(app)
        try app.performAccessibilityAudit()
        attach(app, "cleanup-stored-results-accessibility")
    }

    @MainActor private func captures(flag: String) throws -> CleanupUICaptures {
        let environment = ProcessInfo.processInfo.environment
        guard environment[flag] == "1", let input = environment["FR_CLEANUP_SEED_TOKEN"] else {
            throw XCTSkip("Requires \(flag)=1 and a separately prepared FR_CLEANUP_SEED_TOKEN(UUID) dedicated seed")
        }
        let token = try XCTUnwrap(UUID(uuidString: input))
        return .init(prefix: "s34c-" + token.uuidString.lowercased())
    }

    @MainActor private func requireFresh(_ captures: CleanupUICaptures, _ app: XCUIApplication) throws {
        try scope(history: false, app)
        guard try scan(app) == captures.all else {
            attach(app, "cleanup-unsafe-root-abort")
            XCTFail("Refuse deletion unless the normal root contains exactly this token's four disposable files")
            throw CleanupUIFailure.unsafeRoot
        }
        try scope(history: true, app)
        guard try scan(app).isEmpty else { throw CleanupUIFailure.unsafeRoot }
        try scope(history: false, app)
        for capture in captures.all.sorted() {
            try top(app)
            try reveal(element("library.itemTitle." + capture, app), app)
            let row = element("library.item." + capture, app)
            guard row.label.contains("原本あり"), row.label.contains("削除記録なし"),
                  !withPrefix("library.result.\(capture).", app).exists else {
                attach(app, "cleanup-not-fresh-abort")
                XCTFail("Refuse deletion after any previous result or changed original state")
                throw CleanupUIFailure.unsafeRoot
            }
        }
    }

    @MainActor private func select(_ capture: String, _ app: XCUIApplication) throws {
        try top(app)
        let identifier = "library.select." + capture
        let row = element(identifier, app)
        try reveal(row, app)
        let control = row.descendants(matching: .switch).firstMatch
        guard control.exists, control.isHittable else { throw CleanupUIFailure.unreachable }
        control.tap()
        try wait("The exact row and switch must reflect selection", app) {
            let current = self.element(identifier, app)
            let child = current.descendants(matching: .switch).firstMatch
            return current.exists && child.exists && current.value as? String == "1" && child.value as? String == "1"
        }
    }

    @MainActor private func openReview(_ captures: CleanupUICaptures, _ app: XCUIApplication) throws {
        let action = app.buttons["library.action.cleanup"]
        try reveal(action, app)
        guard action.isEnabled else { throw CleanupUIFailure.unexpectedState }
        action.tap()
        let title = app.staticTexts["選択した原本を容量整理しますか？"]
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "最後に取得した保存検証と軽量版の有効な明示確認に基づき")).firstMatch
        guard title.waitForExistence(timeout: 5), message.waitForExistence(timeout: 5),
              captures.selected.allSatisfy({ message.label.contains("対象：動画 " + $0) }),
              !message.label.contains("対象：動画 " + captures.keep),
              message.label.contains("有効な保存検証と軽量版の明示確認がありません"),
              message.label.contains("オフラインではMac mini原本の現在の存在を確認していません"),
              message.label.contains("Mac miniと写真の動画は削除しません") else {
            attach(app, "cleanup-review-information-mismatch-abort")
            XCTFail("Refuse confirmation unless exact targets, missing evidence and external-copy limits are visible")
            throw CleanupUIFailure.unexpectedState
        }
    }

    @MainActor private func cancelReview(_ app: XCUIApplication) throws {
        let cancel = app.buttons["キャンセル"]
        if cancel.exists, cancel.isHittable { cancel.tap(); return }
        let region = app.otherElements["PopoverDismissRegion"]
        let popover = app.popovers.firstMatch
        guard region.exists, popover.exists else { throw CleanupUIFailure.unexpectedState }
        let bounds = region.frame
        let popup = popover.frame.intersection(bounds)
        let exposed = [
            CGRect(x: bounds.minX, y: bounds.minY, width: max(0, popup.minX - bounds.minX), height: bounds.height),
            CGRect(x: popup.maxX, y: bounds.minY, width: max(0, bounds.maxX - popup.maxX), height: bounds.height),
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, popup.minY - bounds.minY)),
            CGRect(x: bounds.minX, y: popup.maxY, width: bounds.width, height: max(0, bounds.maxY - popup.maxY))
        ].first { $0.width > 4 && $0.height > 4 }
        guard !popup.isEmpty, let exposed else { throw CleanupUIFailure.unreachable }
        let point = CGPoint(x: exposed.midX, y: exposed.midY)
        guard bounds.contains(point), !popover.frame.contains(point),
              !app.buttons["確認した原本を整理"].frame.contains(point) else { throw CleanupUIFailure.unsafeRoot }
        region.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - bounds.minX, dy: point.y - bounds.minY)).tap()
    }

    @MainActor private func requireCompleted(_ captures: CleanupUICaptures, _ app: XCUIApplication) throws -> String {
        try scope(history: false, app)
        XCTAssertEqual(try scan(app), captures.all, "Cleaned originals must retain the same normal rows")
        var batches: Set<String> = []
        for capture in captures.selected {
            try top(app)
            let prefix = "library.result.\(capture)."
            let result = withPrefix(prefix, app)
            try reveal(result, app)
            let outcome = capture == captures.missing ? "原本の容量整理：失敗：前回は削除を実行していません。" : "原本の容量整理：成功（記録確認済み）"
            try wait("The target must show its own durable result", app, timeout: 20) { result.exists && result.label == outcome }
            let batch = String(result.identifier.dropFirst(prefix.count))
            guard UUID(uuidString: batch) != nil else { throw CleanupUIFailure.unexpectedState }
            batches.insert(batch)
            let row = element("library.item." + capture, app)
            XCTAssertTrue(row.exists)
            XCTAssertTrue(row.label.contains(capture == captures.missing ? "原本あり" : "原本なし"))
            if capture != captures.missing { XCTAssertTrue(row.label.contains("容量整理済み（原本削除を照合済み）")) }
        }
        XCTAssertEqual(batches.count, 1, "All children must identify the same fixed accepted batch")
        try top(app)
        try reveal(element("library.itemTitle." + captures.keep, app), app)
        let keep = element("library.item." + captures.keep, app)
        XCTAssertTrue(keep.label.contains("原本あり") && keep.label.contains("削除記録なし"))
        XCTAssertFalse(withPrefix("library.result.\(captures.keep).", app).exists)
        try scope(history: true, app)
        XCTAssertTrue(try scan(app).isEmpty, "Cleanup must never enter discard history")
        try scope(history: false, app)
        return try XCTUnwrap(batches.first)
    }

    @MainActor private func scan(_ app: XCUIApplication) throws -> Set<String> {
        try top(app)
        var seen: Set<String> = []
        var previous = ""
        var stable = 0
        for _ in 0..<40 {
            let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.item.")).allElementsBoundByIndex
            let signature = rows.map { "\($0.identifier)=\($0.frame.integral)" }.sorted().joined(separator: "\n")
            for row in rows { seen.insert(String(row.identifier.dropFirst("library.item.".count))) }
            guard !seen.contains("s16v2-original"), !seen.contains(where: { !$0.hasPrefix("s34c-") }) else { throw CleanupUIFailure.unsafeRoot }
            stable = signature == previous ? stable + 1 : 0
            if stable >= 2 { return seen }
            previous = signature
            app.swipeUp()
        }
        throw CleanupUIFailure.unreachable
    }

    @MainActor private func loaded(_ app: XCUIApplication) throws {
        let refresh = app.buttons["library.refresh"]
        guard refresh.waitForExistence(timeout: 10) else { throw CleanupUIFailure.unexpectedState }
        try wait("Library must finish without a read failure", app) { refresh.isEnabled && !self.element("library.loadFailure", app).exists }
    }

    @MainActor private func scope(history: Bool, _ app: XCUIApplication) throws {
        try top(app)
        element("library.scope", app).tap()
        let choice = app.buttons[history ? "破棄の履歴" : "ライブラリ"]
        guard choice.waitForExistence(timeout: 5) else { throw CleanupUIFailure.unexpectedState }
        choice.tap()
    }

    @MainActor private func top(_ app: XCUIApplication) throws {
        try reveal(element("library.scope", app), app, preferUp: false)
    }

    @MainActor private func reveal(_ value: XCUIElement, _ app: XCUIApplication, preferUp: Bool = true) throws {
        for _ in 0..<40 {
            if value.exists {
                let top = app.navigationBars.firstMatch.frame.maxY
                let frame = value.frame
                if value.isHittable, frame.midY > top + 2, frame.midY < app.frame.maxY - 8 { return }
                if frame.midY <= top + 2 { app.swipeDown(); continue }
            }
            if preferUp { app.swipeUp() } else { app.swipeDown() }
        }
        attach(app, "cleanup-unreachable-" + value.identifier)
        throw CleanupUIFailure.unreachable
    }

    @MainActor private func wait(_ message: String, _ app: XCUIApplication, timeout: TimeInterval = 10,
        predicate: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            attach(app, "cleanup-wait-failure"); XCTFail(message); throw CleanupUIFailure.unexpectedState
        }
    }

    @MainActor private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    @MainActor private func withPrefix(_ prefix: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}

private struct CleanupUICaptures {
    let prefix: String
    var a: String { prefix + "-a" }
    var b: String { prefix + "-b" }
    var missing: String { prefix + "-missing" }
    var keep: String { prefix + "-keep" }
    var selected: [String] { [a, b, missing] }
    var all: Set<String> { [a, b, missing, keep] }
}

private enum CleanupUIFailure: Error { case unsafeRoot, unreachable, unexpectedState }
