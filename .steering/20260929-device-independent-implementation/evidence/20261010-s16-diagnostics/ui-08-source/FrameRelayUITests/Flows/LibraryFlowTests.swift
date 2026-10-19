import XCTest

/// Requires the separately completed ProductLibrarySeedTests run. No launch
/// arguments, app fixture branch, or test-owned replacement UI are used.
final class LibraryFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testListDetailSelectionHistoryAndRetainedStateAfterRelaunch() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch()
        try waitForLibrary(app)
        attach(app, "operation-library-ready")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Library must not request camera or Photos permission")
        let original = element("library.item.s16v2-original", app)
        reveal(original, app)
        XCTAssertTrue(original.label.contains("不明"))
        selectVideo("s16v2-original", app)
        selectVideo("s16v2-unfinished", app)
        let selectedCount = app.staticTexts["選択した2本の操作"]
        reveal(selectedCount, app)
        XCTAssertTrue(selectedCount.exists)
        attach(app, "operation-library-two-selected")
        for action in ["transfer", "saveToPhotos", "cleanup"] {
            let button = app.buttons["library.action." + action]
            reveal(button, app)
            XCTAssertFalse(button.isEnabled)
            let reason = element("library.reason." + action, app)
            reveal(reason, app)
            XCTAssertTrue(reason.label.contains("まだ利用できません"))
        }
        top(app)
        reveal(original, app); original.tap()
        XCTAssertTrue(element("library.detailIdentity", app).waitForExistence(timeout: 5))
        attach(app, "operation-library-detail-identity")
        for axis in ["save", "original", "transfer", "verification", "publication", "retrieval", "confirmation", "invalidation", "photos", "removal"] {
            let status = element("library.status." + axis, app)
            reveal(status, app)
            XCTAssertTrue(status.exists)
        }
        let play = app.buttons["library.action.playOriginal"]
        reveal(play, app); XCTAssertTrue(play.isEnabled)
        for action in ["playRendition", "confirmRendition", "discard"] {
            let button = app.buttons["library.action." + action]
            reveal(button, app); XCTAssertFalse(button.isEnabled)
            XCTAssertTrue(element("library.reason." + action, app).exists)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        top(app)
        let cleanup = element("library.item.s16v2-cleanup", app)
        reveal(cleanup, app)
        XCTAssertTrue(cleanup.label.contains("整理"))
        XCTAssertFalse(element("library.item.s16v2-discard", app).exists)
        top(app); showHistory(app)
        let discarded = element("library.item.s16v2-discard", app)
        reveal(discarded, app)
        XCTAssertTrue(discarded.waitForExistence(timeout: 5))
        XCTAssertFalse(element("library.item.s16v2-cleanup", app).exists)
        attach(app, "operation-library-history")
        app.terminate(); app.launch()
        try waitForLibrary(app)
        reveal(element("library.item.s16v2-unfinished", app), app)
        XCTAssertTrue(element("library.item.s16v2-unfinished", app).label.contains("要照合"))
        attach(app, "library-relaunch-retained-seed")
    }

    /// Narrow comparison with the same pre-existing 30-second product original.
    /// Seed/repair and accessibility-audit changes are deliberately separate runs.
    @MainActor func testOriginalPlaybackDiagnosticStartStop() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        openOriginal(app)
        waitForProgress(app)
        attach(app, "diagnostic-original-progress")
        reveal(app.buttons["originalPlayback.stop"], app)
        app.buttons["originalPlayback.stop"].tap()
        waitForText(element("originalPlayback.status", app), "再生を停止しました")
        attach(app, "diagnostic-original-stopped")
        app.buttons["originalPlayback.close"].tap()
        XCTAssertFalse(element("originalPlayback.status", app).exists)
    }

    @MainActor func testOriginalPlaybackProgressStopBackgroundAndRestart() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        openOriginal(app)
        waitForProgress(app)
        attach(app, "operation-original-playback-progress")
        reveal(app.buttons["originalPlayback.stop"], app)
        attach(app, "operation-original-explanation-and-stop-reached")
        app.buttons["originalPlayback.stop"].tap()
        waitForText(element("originalPlayback.status", app), "再生を停止しました")
        app.buttons["originalPlayback.close"].tap()
        let replay = app.buttons["library.action.playOriginal"]
        reveal(replay, app)
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        XCTAssertTrue(replay.isEnabled)
        tapOriginalPlay(replay)
        waitForProgress(app)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        waitForText(element("originalPlayback.status", app), "再生を停止しました")
        let stopped = try XCTUnwrap(element("originalPlayback.elapsed", app).value as? String)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element("originalPlayback.status", app).label != "再生を停止しました"
                || element("originalPlayback.elapsed", app).value as? String != stopped
        }, object: nil)
        // A three-second test observation window, not a product timing promise.
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
        attach(app, "playback-stopped-after-background")
        app.buttons["originalPlayback.close"].tap()
        app.terminate(); app.launch(); try waitForLibrary(app)
        openOriginal(app); waitForProgress(app)
        app.buttons["originalPlayback.close"].tap()
        XCTAssertFalse(element("originalPlayback.status", app).exists)
    }

    @MainActor func testAccessibilityAcrossLibraryDetailHistoryAndPlayer() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        try audit(app, "library")
        let original = element("library.item.s16v2-original", app)
        reveal(original, app); original.tap()
        try audit(app, "detail-top")
        let play = app.buttons["library.action.playOriginal"]
        reveal(play, app)
        try audit(app, "detail-actions")
        tapOriginalPlay(play); waitForProgress(app)
        reveal(app.buttons["originalPlayback.stop"], app)
        app.buttons["originalPlayback.stop"].tap()
        waitForText(element("originalPlayback.status", app), "再生を停止しました")
        try audit(app, "player-stopped")
        app.buttons["originalPlayback.close"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        top(app); showHistory(app)
        try audit(app, "history")
    }

    @MainActor func testVoiceOverReadsLibraryStateAndActions() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        let service = XCUIDevice.shared.voiceOverService
        let wasEnabled = service.isEnabled
        addTeardownBlock { @MainActor in
            if service.isEnabled != wasEnabled {
                if wasEnabled { try service.enable() } else { try service.disable() }
            }
            XCTAssertEqual(service.isEnabled, wasEnabled, "Restore initial VoiceOver state")
        }
        try service.enable()
        var speech: [String] = []
        for _ in 0..<24 {
            let output = try service.moveForward()
            speech.append(output.utterance)
            if speech.contains(where: { $0.contains("不明") }), speech.contains(where: { $0.contains("選択") }) { break }
        }
        let joined = speech.joined(separator: "\n")
        let attachment = XCTAttachment(string: joined)
        attachment.name = "actual-VoiceOver-speech-text-not-listening-quality"
        attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(joined.contains("不明"))
        XCTAssertTrue(joined.contains("選択"))
    }

    @MainActor private func waitForLibrary(_ app: XCUIApplication) throws {
        let refresh = app.buttons["library.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            refresh.isEnabled && !element("library.loadFailure", app).exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                       "Expected enabled refresh and no load failure")
        // An older interrupted seed remains an ordinary row. At large Dynamic
        // Type the expected v2 row may not be materialized until it is scrolled in.
        let expected = element("library.item.s16v2-cleanup", app)
        reveal(expected, app)
        XCTAssertTrue(expected.exists, "Expected the separately seeded v2 record")
        XCTAssertTrue(refresh.isEnabled)
        XCTAssertFalse(element("library.loadFailure", app).exists)
        top(app)
    }

    @MainActor private func openOriginal(_ app: XCUIApplication) {
        let original = element("library.item.s16v2-original", app)
        reveal(original, app); original.tap()
        let play = app.buttons["library.action.playOriginal"]
        reveal(play, app); XCTAssertTrue(play.isEnabled); tapOriginalPlay(play)
    }

    @MainActor private func selectVideo(_ capture: String, _ app: XCUIApplication) {
        let row = element("library.select." + capture, app)
        reveal(row, app)
        // SwiftUI exposes the labelled row and the actual switch separately.
        // Tap the switch control rather than the centre of the surrounding row.
        let control = row.descendants(matching: .switch).firstMatch
        XCTAssertTrue(control.exists)
        XCTAssertTrue(control.isHittable)
        control.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        XCTAssertEqual(control.value as? String, "1")
    }

    @MainActor private func showHistory(_ app: XCUIApplication) {
        element("library.scope", app).tap()
        app.buttons["破棄の履歴"].tap()
    }

    @MainActor private func waitForProgress(_ app: XCUIApplication) {
        let elapsed = element("originalPlayback.elapsed", app)
        attachPlaybackTime("progress-wait-begin")
        let exists = elapsed.waitForExistence(timeout: 10)
        if !exists { attachPlaybackFailure(app, stage: "elapsed-missing") }
        XCTAssertTrue(exists)
        guard exists else { return }
        let progress = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = elapsed.value as? String ?? ""
            let numbers = value.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).filter { !$0.isEmpty }
            return numbers.contains { (Double($0) ?? 0) > 0.2 }
        }, object: nil)
        let result = XCTWaiter.wait(for: [progress], timeout: 15)
        attachPlaybackTime("progress-wait-ended-\(result.rawValue)")
        if result != .completed { attachPlaybackFailure(app, stage: "progress-timeout") }
        XCTAssertEqual(result, .completed)
        let playerExists = element("originalPlayback.player", app).exists
        if !playerExists { attachPlaybackFailure(app, stage: "player-missing-after-progress") }
        XCTAssertTrue(playerExists)
    }

    @MainActor private func tapOriginalPlay(_ button: XCUIElement) {
        attachPlaybackTime("play-tap-begin")
        button.tap()
        attachPlaybackTime("play-tap-returned")
    }

    @MainActor private func attachPlaybackTime(_ stage: String) {
        let value = XCTAttachment(string: "uptime=\(ProcessInfo.processInfo.systemUptime) stage=\(stage)")
        value.name = "playback-timing-" + stage; value.lifetime = .keepAlways
        add(value)
    }

    @MainActor private func attachPlaybackFailure(_ app: XCUIApplication, stage: String) {
        // Collect before an assertion with continueAfterFailure=false can abort.
        let phase = element("originalPlayback.status", app)
        let elapsed = element("originalPlayback.elapsed", app)
        let value = XCTAttachment(string: "uptime=\(ProcessInfo.processInfo.systemUptime) stage=\(stage)\n"
            + "phase=\(phase.exists ? phase.label : "missing")\n"
            + "elapsed=\(elapsed.exists ? String(describing: elapsed.value) : "missing")")
        value.name = "playback-failure-" + stage + "-phase"; value.lifetime = .keepAlways
        add(value)
        attach(app, "playback-failure-" + stage)
    }

    @MainActor private func waitForText(_ value: XCUIElement, _ text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    @MainActor private func audit(_ app: XCUIApplication, _ name: String) throws {
        attach(app, "accessibility-" + name)
        let previousFailurePolicy = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previousFailurePolicy }
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped, .sufficientElementDescription,
                                               .trait, .hitRegion, .elementDetection, .contrast]) { issue in
            let details = [issue.compactDescription, issue.detailedDescription,
                           "auditType=\(issue.auditType.rawValue)",
                           issue.element?.debugDescription ?? "SDK supplied no associated element"].joined(separator: "\n")
            let attachment = XCTAttachment(string: details)
            attachment.name = "accessibility-" + name + "-unhandled-issue"
            attachment.lifetime = .keepAlways; self.add(attachment)
            return false // Record every issue as a failure; this is not an exclusion filter.
        }
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}

@MainActor private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
}

@MainActor private func reveal(_ value: XCUIElement, _ app: XCUIApplication) {
    for _ in 0..<35 {
        if value.exists && value.isHittable { return }
        app.swipeUp()
    }
    XCTFail("Cannot reach \(value)")
}

@MainActor private func top(_ app: XCUIApplication) {
    for _ in 0..<35 {
        if element("library.scope", app).isHittable { return }
        app.swipeDown()
    }
    XCTFail("Cannot reach library scope")
}
