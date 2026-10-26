import XCTest

/// Destructive UI coverage for a separately seeded, dedicated Simulator only.
/// The app receives no fixture environment or launch arguments. Raw unlink,
/// byte identity, external files and the store are verified by the separate
/// ProductRemovalSeedTests VERIFY run, not inferred from these UI assertions.
final class RemovalFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testDiscardCancellationAndDurableHistoryOnDedicatedSeed() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["FR_REMOVAL_UI"] == "1" else {
            throw XCTSkip("Requires FR_REMOVAL_UI=1 and the separately prepared dedicated removal seed")
        }
        guard let rawToken = environment["FR_REMOVAL_SEED_TOKEN"], !rawToken.isEmpty else {
            throw XCTSkip("Requires FR_REMOVAL_SEED_TOKEN(UUID) for the dedicated removal seed")
        }
        let token = try XCTUnwrap(UUID(uuidString: rawToken), "Removal seed token must be a UUID")
        let captures = RemovalUICaptures(token: token)
        let identity = XCTAttachment(string: "seedToken=\(token.uuidString.lowercased())\n"
            + "expectedRecordings=\(captures.all.sorted())\n"
            + "UI results are paired with a separate Unit VERIFY; they alone do not prove raw deletion.")
        identity.name = "removal-dedicated-seed-identity"; identity.lifetime = .keepAlways
        add(identity)

        let app = XCUIApplication()
        addTeardownBlock { @MainActor in
            if app.state == .runningForeground { self.attach(app, "removal-final-observed-screen") }
        }
        app.launch()
        try waitForLibrary(app)
        try assertFreshDedicatedSeed(captures, app: app)
        try assertOtherRecordings(captures, app: app)

        try openDetail(captures.discard, app: app)
        let information = try removalInformation(for: captures.discard, app: app)
        let saveBefore = try status("save", containing: "保存結果不明", app: app)
        _ = try status("original", containing: "原本あり", app: app)
        _ = try status("removal", containing: "削除記録なし", app: app)
        try openDiscardReview(for: captures.discard, app: app)
        attach(app, "removal-first-confirmation-before-cancel")
        try cancelDiscardReview(app)
        try waitUntil("Discard confirmation must close after cancellation", app: app) {
            !app.buttons["対象の原本を破棄"].exists
        }
        XCTAssertEqual(try removalInformation(for: captures.discard, app: app), information)
        XCTAssertEqual(try status("save", containing: "保存結果不明", app: app), saveBefore)
        _ = try status("original", containing: "原本あり", app: app)
        _ = try status("removal", containing: "削除記録なし", app: app)
        XCTAssertFalse(withPrefix("library.result.\(captures.discard).", app).exists)
        XCTAssertFalse(withPrefix("library.submission.target.\(captures.discard).", app).exists)
        attach(app, "removal-cancel-retains-original-and-no-operation-result")
        try returnToLibrary(app)
        try assertFreshDedicatedSeed(captures, app: app)
        try assertOtherRecordings(captures, app: app)

        // Every destructive control below is reached only after the exact fresh
        // token/root checks above. Never substitute an existing CF capture ID.
        try openDetail(captures.discard, app: app)
        XCTAssertEqual(try removalInformation(for: captures.discard, app: app), information)
        try openDiscardReview(for: captures.discard, app: app)
        attach(app, "removal-second-confirmation-before-explicit-discard")
        app.buttons["対象の原本を破棄"].tap()
        let resultPrefix = "library.result.\(captures.discard)."
        let result = withPrefix(resultPrefix, app)
        try waitUntil("Expected the target's durable success projection", app: app, timeout: 20) {
            result.exists && result.label.contains("成功（記録確認済み）")
        }
        try reveal(result, app: app)
        XCTAssertEqual(result.label, "不要な原本を破棄：成功（記録確認済み）")
        let resultIdentifier = result.identifier
        let batchID = String(resultIdentifier.dropFirst(resultPrefix.count))
        XCTAssertNotNil(UUID(uuidString: batchID), "Durable result must identify its removal batch")
        _ = try status("original", containing: "原本なし", app: app)
        _ = try status("removal", containing: "破棄済み（原本削除を照合済み）", app: app)
        attach(app, "removal-detail-durable-success-and-original-absence")
        try returnToLibrary(app)
        try showScope(history: false, app: app)
        XCTAssertEqual(try scanRecordingIDs(app), captures.all.subtracting([captures.discard]))
        try assertOtherRecordings(captures, app: app)
        try showScope(history: true, app: app)
        XCTAssertEqual(try scanRecordingIDs(app), [captures.discard])
        try assertHistoryTarget(captures.discard, app: app)
        attach(app, "removal-only-explicit-target-enters-history")

        app.terminate(); app.launch()
        try waitForLibrary(app)
        try showScope(history: false, app: app)
        XCTAssertEqual(try scanRecordingIDs(app), captures.all.subtracting([captures.discard]))
        try assertOtherRecordings(captures, app: app)
        try showScope(history: true, app: app)
        XCTAssertEqual(try scanRecordingIDs(app), [captures.discard])
        try assertHistoryTarget(captures.discard, app: app)
        try openDetail(captures.discard, app: app)
        let persistedResult = element(resultIdentifier, app)
        try reveal(persistedResult, app: app)
        XCTAssertEqual(persistedResult.label, "不要な原本を破棄：成功（記録確認済み）")
        _ = try status("original", containing: "原本なし", app: app)
        _ = try status("removal", containing: "破棄済み（原本削除を照合済み）", app: app)
        XCTAssertFalse(app.buttons["library.action.discard"].exists)
        attach(app, "removal-relaunch-retains-same-durable-result-and-history")
    }

    @MainActor private func assertFreshDedicatedSeed(_ captures: RemovalUICaptures, app: XCUIApplication) throws {
        try showScope(history: false, app: app)
        let recordings = try scanRecordingIDs(app)
        guard recordings == captures.all, !recordings.contains("s16v2-original") else {
            attach(app, "removal-unsafe-root-before-any-destructive-operation")
            XCTFail("Dedicated root must contain exactly the four fresh token IDs; shared CF seed must remain untouched")
            throw RemovalUIFailure.unsafeRoot
        }
        try showScope(history: true, app: app)
        guard try scanRecordingIDs(app).isEmpty else {
            XCTFail("Fresh dedicated removal seed must have an empty history")
            throw RemovalUIFailure.unsafeRoot
        }
        try showScope(history: false, app: app)
        let discard = element("library.item.\(captures.discard)", app)
        try reveal(discard, app: app)
        XCTAssertTrue(discard.label.contains("原本あり"))
        XCTAssertTrue(discard.label.contains("削除記録なし"))
        attach(app, "removal-fresh-token-preflight-recordings-and-empty-history")
    }

    @MainActor private func assertOtherRecordings(_ captures: RemovalUICaptures, app: XCUIApplication) throws {
        try showScope(history: false, app: app)
        for (capture, original, removal) in [
            (captures.cleanup, "原本なし", "容量整理済み（原本削除を照合済み）"),
            (captures.pending, "原本あり", "削除結果を確定できません・要照合"),
            (captures.keep, "原本あり", "削除記録なし")
        ] {
            let row = element("library.item.\(capture)", app)
            try reveal(row, app: app)
            XCTAssertTrue(row.label.contains(original), capture + " original state")
            XCTAssertTrue(row.label.contains(removal), capture + " removal state")
            if capture == captures.pending { XCTAssertTrue(row.label.contains("要照合")) }
        }
        attach(app, "removal-cleanup-remains-normal-pending-unresolved-keep-preserved")
    }

    @MainActor private func assertHistoryTarget(_ capture: String, app: XCUIApplication) throws {
        let row = element("library.item.\(capture)", app)
        try reveal(row, app: app)
        XCTAssertTrue(row.label.contains("原本なし"))
        XCTAssertTrue(row.label.contains("破棄済み（原本削除を照合済み）"))
    }

    @MainActor private func removalInformation(for capture: String, app: XCUIApplication) throws -> String {
        let information = element("library.removalReviewInformation", app)
        try reveal(information, app: app)
        let label = information.label
        XCTAssertTrue(label.contains("対象：動画 \(capture)"))
        XCTAssertTrue(label.contains("撮影日時"))
        XCTAssertTrue(label.contains("原本のサイズ："))
        XCTAssertTrue(label.contains("保存検証："))
        return label
    }

    @MainActor private func openDiscardReview(for capture: String, app: XCUIApplication) throws {
        let identity = element("library.detailIdentity", app)
        guard identity.exists, identity.label == "動画 \(capture)", capture.hasPrefix("s34r-") else {
            XCTFail("Refuse to open a destructive review for an unexpected capture")
            throw RemovalUIFailure.unsafeRoot
        }
        let button = app.buttons["library.action.discard"]
        try reveal(button, app: app)
        XCTAssertTrue(button.isEnabled)
        button.tap()
        let commit = app.buttons["対象の原本を破棄"]
        guard commit.waitForExistence(timeout: 5) else { throw RemovalUIFailure.unexpectedState }
        let title = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "この原本を破棄しますか？")).firstMatch
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "iPhone内の原本を削除します。")).firstMatch
        guard title.waitForExistence(timeout: 5), message.waitForExistence(timeout: 5) else {
            XCTFail("Destructive confirmation must present the target and loss risk")
            throw RemovalUIFailure.unexpectedState
        }
        guard message.label.contains("対象：動画 \(capture)"),
              message.label.contains("Mac miniや写真にコピーがなければ、この動画を失います。"),
              message.label.contains("Mac miniと写真の動画は削除しません。"),
              app.buttons["キャンセル"].exists
                || (app.otherElements["PopoverDismissRegion"].exists && app.popovers.firstMatch.exists) else {
            attach(app, "removal-confirmation-information-mismatch-abort")
            XCTFail("Refuse destructive confirmation without the exact target, loss risk and external-copy explanation")
            throw RemovalUIFailure.unexpectedState
        }
    }

    @MainActor private func cancelDiscardReview(_ app: XCUIApplication) throws {
        let cancel = app.buttons["キャンセル"]
        if cancel.exists, cancel.isHittable {
            cancel.tap()
            return
        }
        // A native popover omits the cancel-role button. Operate its actual
        // dismiss region at a point outside the popover, never at its centre,
        // which can overlap the destructive action or confirmation message.
        let region = app.otherElements["PopoverDismissRegion"]
        let popover = app.popovers.firstMatch
        guard region.exists, popover.exists else {
            XCTFail("Expected a visible cancellation control or native popover dismiss region")
            throw RemovalUIFailure.unexpectedState
        }
        let bounds = region.frame
        let popup = popover.frame.intersection(bounds)
        let exposedRegions = [
            CGRect(x: bounds.minX, y: bounds.minY, width: max(0, popup.minX - bounds.minX), height: bounds.height),
            CGRect(x: popup.maxX, y: bounds.minY, width: max(0, bounds.maxX - popup.maxX), height: bounds.height),
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, popup.minY - bounds.minY)),
            CGRect(x: bounds.minX, y: popup.maxY, width: bounds.width, height: max(0, bounds.maxY - popup.maxY))
        ]
        guard !popup.isEmpty, let exposed = exposedRegions.first(where: { $0.width > 4 && $0.height > 4 }) else {
            XCTFail("Native popover has no reachable exposed cancellation region")
            throw RemovalUIFailure.unexpectedState
        }
        let point = CGPoint(x: exposed.midX, y: exposed.midY)
        guard bounds.contains(point), !popover.frame.contains(point),
              !app.buttons["対象の原本を破棄"].frame.contains(point) else {
            XCTFail("Cancellation must occur outside the destructive popover")
            throw RemovalUIFailure.unexpectedState
        }
        let evidence = XCTAttachment(string: "cancellationRoute=PopoverDismissRegion\n"
            + "region=\(bounds) popover=\(popover.frame) tap=\(point)")
        evidence.name = "removal-native-popover-cancellation"; evidence.lifetime = .keepAlways; add(evidence)
        region.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - bounds.minX, dy: point.y - bounds.minY)).tap()
    }

    @MainActor private func status(_ axis: String, containing expected: String, app: XCUIApplication) throws -> String {
        let value = element("library.status." + axis, app)
        try reveal(value, app: app)
        XCTAssertTrue(value.label.contains(expected), axis + " must retain " + expected)
        return value.label
    }

    @MainActor private func openDetail(_ capture: String, app: XCUIApplication) throws {
        let row = element("library.item.\(capture)", app)
        try reveal(row, app: app)
        row.tap()
        let identity = element("library.detailIdentity", app)
        guard identity.waitForExistence(timeout: 5), identity.label == "動画 \(capture)" else {
            XCTFail("Expected the exact requested detail before continuing")
            throw RemovalUIFailure.unexpectedState
        }
    }

    @MainActor private func returnToLibrary(_ app: XCUIApplication) throws {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        try waitForLibrary(app)
    }

    @MainActor private func showScope(history: Bool, app: XCUIApplication) throws {
        let scope = element("library.scope", app)
        try reveal(scope, app: app, preferUp: false)
        scope.tap()
        let choice = app.buttons[history ? "破棄の履歴" : "ライブラリ"]
        guard choice.waitForExistence(timeout: 5) else { throw RemovalUIFailure.unexpectedState }
        choice.tap()
    }

    /// Scan to the stable end, including lazily materialized rows, before using
    /// absence or an exact set as evidence. This also guards a mixed CF root.
    @MainActor private func scanRecordingIDs(_ app: XCUIApplication) throws -> Set<String> {
        try reveal(element("library.scope", app), app: app, preferUp: false)
        var seen: Set<String> = []
        var previous: String?
        var stableEndCount = 0
        for _ in 0..<36 {
            let rows = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.item.")).allElementsBoundByIndex
            let values = rows.map { ($0.identifier, $0.frame.integral) }
            for (identifier, _) in values { seen.insert(String(identifier.dropFirst("library.item.".count))) }
            guard !seen.contains("s16v2-original") else {
                attach(app, "removal-shared-CF-seed-detected-abort")
                XCTFail("Refuse destructive UI operations on the shared CF root")
                throw RemovalUIFailure.unsafeRoot
            }
            let signature = values.map { "\($0.0)=\($0.1)" }.sorted().joined(separator: "\n")
            stableEndCount = signature == previous ? stableEndCount + 1 : 0
            if stableEndCount >= 2 {
                let evidence = XCTAttachment(string: "recordingIDs=\(seen.sorted())\nstableEnd=true\n" + signature)
                evidence.name = "removal-recording-scan"; evidence.lifetime = .keepAlways; add(evidence)
                return seen
            }
            previous = signature
            app.swipeUp()
        }
        attach(app, "removal-recording-scan-did-not-reach-stable-end")
        XCTFail("Cannot confirm all recording IDs within the bounded scan")
        throw RemovalUIFailure.unreachable
    }

    @MainActor private func waitForLibrary(_ app: XCUIApplication) throws {
        let refresh = app.buttons["library.refresh"]
        guard refresh.waitForExistence(timeout: 10) else { throw RemovalUIFailure.unexpectedState }
        try waitUntil("Library must finish loading without a load failure", app: app) {
            refresh.isEnabled && !self.element("library.loadFailure", app).exists
        }
    }

    @MainActor private func waitUntil(_ message: String, app: XCUIApplication, timeout: TimeInterval = 10,
        predicate: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            attach(app, "removal-wait-failure")
            XCTFail(message)
            throw RemovalUIFailure.unexpectedState
        }
    }

    @MainActor private func reveal(_ value: XCUIElement, app: XCUIApplication, preferUp: Bool = true) throws {
        for _ in 0..<36 {
            if value.exists {
                let navigation = app.navigationBars.firstMatch
                let top = navigation.exists ? navigation.frame.maxY : app.frame.minY
                let frame = value.frame
                if value.isHittable, frame.midY > top + 2, frame.midY < app.frame.maxY - 8 { return }
                if frame.midY <= top + 2 { app.swipeDown(); continue }
            }
            if preferUp { app.swipeUp() } else { app.swipeDown() }
        }
        attach(app, "removal-unreachable-element")
        XCTFail("Cannot reach " + value.identifier)
        throw RemovalUIFailure.unreachable
    }

    @MainActor private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor private func withPrefix(_ prefix: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = name; screen.lifetime = .keepAlways; add(screen)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}

private struct RemovalUICaptures {
    let prefix: String
    init(token: UUID) { prefix = "s34r-" + token.uuidString.lowercased() }
    var discard: String { prefix + "-discard" }
    var cleanup: String { prefix + "-cleanup" }
    var pending: String { prefix + "-pending" }
    var keep: String { prefix + "-keep" }
    var all: Set<String> { [discard, cleanup, pending, keep] }
}

private enum RemovalUIFailure: Error { case unsafeRoot, unexpectedState, unreachable }
