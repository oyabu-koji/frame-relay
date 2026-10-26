import XCTest
import UIKit

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
        _ = libraryItemTarget("s16v2-original", app)
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
            if action == "cleanup" {
                XCTAssertEqual(reason.label, "原本があり、内容と保存記録の対応が確定した動画を選んでください。")
            } else {
                XCTAssertTrue(reason.label.contains("まだ利用できません"))
            }
        }
        top(app)
        openOriginalDetail(app)
        attach(app, "operation-library-detail-identity")
        for axis in ["save", "original", "transfer", "verification", "publication", "retrieval", "confirmation", "invalidation", "photos", "removal"] {
            let status = element("library.status." + axis, app)
            reveal(status, app)
            XCTAssertTrue(status.exists)
        }
        let play = app.buttons["library.action.playOriginal"]
        reveal(play, app); XCTAssertTrue(play.isEnabled)
        for action in ["playRendition", "confirmRendition"] {
            let button = app.buttons["library.action." + action]
            reveal(button, app); XCTAssertFalse(button.isEnabled)
            XCTAssertTrue(element("library.reason." + action, app).exists)
        }
        // Inspect availability only. Never invoke deletion on this shared CF seed.
        let discard = app.buttons["library.action.discard"]
        reveal(discard, app)
        XCTAssertTrue(discard.isEnabled)
        XCTAssertFalse(element("library.reason.discard", app).exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        top(app)
        let cleanup = element("library.item.s16v2-cleanup", app)
        _ = libraryItemTarget("s16v2-cleanup", app)
        XCTAssertTrue(cleanup.label.contains("整理"))
        XCTAssertFalse(element("library.item.s16v2-discard", app).exists)
        top(app); showHistory(app)
        let discarded = element("library.item.s16v2-discard", app)
        _ = libraryItemTarget("s16v2-discard", app)
        XCTAssertTrue(discarded.waitForExistence(timeout: 5))
        XCTAssertFalse(element("library.item.s16v2-cleanup", app).exists)
        attach(app, "operation-library-history")
        app.terminate(); app.launch()
        try waitForLibrary(app)
        _ = libraryItemTarget("s16v2-unfinished", app)
        XCTAssertTrue(element("library.item.s16v2-unfinished", app).label.contains("要照合"))
        attach(app, "library-relaunch-retained-seed")
    }

    /// Narrow comparison with the same pre-existing 30-second product original.
    /// Seed/repair and accessibility-audit changes are deliberately separate runs.
    @MainActor func testOriginalPlaybackDiagnosticStartStop() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app, diagnostics: true)
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
        observeStableOriginalPlaybackStop(app)
        reachOriginalPlaybackExplanation(app, name: "playing", requiresStop: true)
        tapOriginalPlaybackStopAndWait(app)
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

    @MainActor func testAccessibilityLibraryAndDetail() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        try audit(app, "library")
        openOriginalDetail(app)
        try audit(app, "detail-top")
        reveal(app.buttons["library.action.playOriginal"], app)
        try audit(app, "detail-actions")
    }

    @MainActor func testAccessibilityFreshHistory() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        showHistory(app)
        reveal(element("library.historyExplanation", app), app)
        XCTAssertFalse(elementWithPrefix("library.submission.header.", app).exists)
        try audit(app, "history-fresh-explanation")
        reveal(element("library.item.s16v2-discard", app), app)
        try audit(app, "history-fresh-record")
    }

    @MainActor func testAccessibilityHistoryAfterPlaybackHandoff() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        openOriginal(app)
        let status = element("originalPlayback.status", app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let close = app.buttons["originalPlayback.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !close.exists && !status.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 15), .completed)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        top(app); showHistory(app)
        reveal(element("library.historyExplanation", app), app)
        try audit(app, "history-after-handoff-explanation")
        reveal(element("library.item.s16v2-discard", app), app)
        try audit(app, "history-after-handoff-record")
        revealPlaybackSubmission(app)
        try audit(app, "history-after-handoff-submission")
    }

    @MainActor func testAccessibilityStoppedPlayer() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        openOriginal(app)
        waitForProgress(app)
        let stop = app.buttons["originalPlayback.stop"]
        XCTAssertTrue(stop.isHittable)
        XCTAssertTrue(stop.isEnabled)
        try audit(app, "player-playing-with-stop")
        tapOriginalPlaybackStopAndWait(app)
        reachOriginalPlaybackExplanation(app, name: "stopped", requiresStop: false)
        try audit(app, "player-stopped")
    }

    @MainActor func testAccessibilityDetailActionsContrastOnly() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        openOriginalDetail(app)
        reveal(app.buttons["library.action.playOriginal"], app)
        try audit(app, "detail-actions-contrast-only", types: [.contrast])
        let discard = app.buttons["library.action.discard"]
        reveal(discard, app)
        XCTAssertTrue(discard.isEnabled)
        try audit(app, "detail-actions-bottom-contrast-only", types: [.contrast])
    }

    @MainActor func testAccessibilityReconciliationDescriptionDynamicTypeOnly() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        openOriginalDetail(app)
        let explanation = element("library.detailReconciliationExplanation", app)
        reveal(explanation, app)
        XCTAssertTrue(explanation.exists)
        // The SDK audits the visible screen; neighboring elements remain unfiltered.
        try audit(app, "detail-reconciliation-dynamic-type-only", types: [.dynamicType])
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

    /// Run unchanged at each system content size. The runner's UIKit metrics
    /// are references; the product's frames, complete labels and screenshots
    /// remain the evidence of its actual layout.
    @MainActor func testHistoryAndSubmissionTextLayoutAtCurrentContentSize() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        attachSemanticTextEnvironment()
        showHistory(app)
        measureText(element("library.historyExplanation", app),
            expected: "原本の削除結果を照合できた破棄の記録です。原本を保管するゴミ箱ではありません。",
            style: .body, app: app, name: "history-explanation")
        measureText(element("library.itemTitle.s16v2-discard", app),
            expected: "動画 s16v2-discard", style: .headline, app: app, name: "history-title")
        measureText(element("library.itemRemoval.s16v2-discard", app),
            expected: "破棄済み（原本削除を照合済み）", style: .body, app: app, name: "history-removal")

        top(app)
        element("library.scope", app).tap()
        app.buttons["ライブラリ"].tap()
        prepareHistoryAfterPlaybackHandoff(app)
        measureText(elementWithPrefix("library.submission.header.", app),
            expected: "開始した操作の照合", style: .headline, app: app, name: "submission-header")
        measureText(elementWithPrefix("library.submission.title.s16v2-original.", app),
            expected: "動画 s16v2-original", style: .headline, app: app, name: "submission-title")
        measureText(elementWithPrefix("library.submission.action.s16v2-original.", app),
            expected: "iPhone原本を再生", style: .body, app: app, name: "submission-action")
        measureText(elementWithPrefix("library.submission.phase.s16v2-original.", app),
            expected: "再生機能に引き渡しました。再生状態はプレーヤーで確認してください。",
            style: .body, app: app, name: "submission-phase")
    }

    @MainActor func testVoiceOverReadsHistoryAndPlaybackSubmission() throws {
        let app = XCUIApplication()
        registerPlaybackCleanup(for: app)
        app.launch(); try waitForLibrary(app)
        attachSemanticTextEnvironment()
        prepareHistoryAfterPlaybackHandoff(app)
        let originalState = element("library.itemOriginal.s16v2-discard", app)
        top(app); reveal(originalState, app)
        XCTAssertEqual(originalState.label, "原本なし")
        let removal = element("library.itemRemoval.s16v2-discard", app)
        reveal(removal, app)
        XCTAssertEqual(removal.label, "破棄済み（原本削除を照合済み）")
        top(app)
        reveal(element("library.historyExplanation", app), app)

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
        defer {
            let checks = historySpeechChecks(speech).map { "\($0.name)=\($0.present)" }.joined(separator: "\n")
            let attachment = XCTAttachment(string: checks + "\n" + speech.joined(separator: "\n"))
            attachment.name = "history-submission-actual-VoiceOver-speech-text-not-listening-quality"
            attachment.lifetime = .keepAlways; add(attachment)
            attach(app, "history-submission-voiceover-after")
        }
        speech.append(try service.currentSpeech().utterance)
        for _ in 0..<64 {
            speech.append(try service.moveForward().utterance)
            if historySpeechChecks(speech).allSatisfy({ $0.present }) { break }
        }
        for check in historySpeechChecks(speech) {
            XCTAssertTrue(check.present, "VoiceOver must retain " + check.name)
        }
    }

    @MainActor private func prepareHistoryAfterPlaybackHandoff(_ app: XCUIApplication) {
        openOriginal(app)
        let status = element("originalPlayback.status", app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let close = app.buttons["originalPlayback.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !close.exists && !status.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 15), .completed)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        top(app); showHistory(app)
        revealPlaybackSubmission(app)
    }

    @MainActor private func attachSemanticTextEnvironment() {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let headline = UIFont.preferredFont(forTextStyle: .headline)
        let value = XCTAttachment(string:
            "runnerContentSizeCategory=\(UIApplication.shared.preferredContentSizeCategory.rawValue)\n"
            + "body font=\(body.fontName) pointSize=\(body.pointSize) lineHeight=\(body.lineHeight)\n"
            + "headline font=\(headline.fontName) pointSize=\(headline.pointSize) lineHeight=\(headline.lineHeight)\n"
            + "UIKit runner metrics are references. Compare product Text frames and screenshots across system sizes.\n"
            + "SwiftUI/UIKit Japanese fallback and line wrapping may differ; boundingRect alone does not determine clipping.")
        value.name = "history-submission-semantic-text-environment"; value.lifetime = .keepAlways
        add(value)
    }

    @MainActor private func measureText(_ value: XCUIElement, expected: String,
        style: UIFont.TextStyle, app: XCUIApplication, name: String) {
        let viewport = positionTextForMeasurement(value, app: app)
        let label = value.label
        let frame = value.frame
        let font = UIFont.preferredFont(forTextStyle: style)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        // Round at most one point to avoid making an intrinsic-width text wrap
        // solely because AX reports a fractional pixel below its glyph width.
        let referenceWidth = ceil(frame.width)
        let referenceBounds = NSAttributedString(string: expected,
            attributes: [.font: font, .paragraphStyle: paragraph]).boundingRect(
                with: CGSize(width: referenceWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let referenceHeight = ceil(referenceBounds.height)
        let metrics = XCTAttachment(string:
            "\(auditMetadata(value))\nexpectedCompleteLabel=\(expected)\n"
            + "runnerContentSizeCategory=\(UIApplication.shared.preferredContentSizeCategory.rawValue)\n"
            + "semanticStyle=\(style.rawValue) referenceFont=\(font.fontName) pointSize=\(font.pointSize) lineHeight=\(font.lineHeight)\n"
            + "visibleViewport=\(viewport) fullyWithinViewport=\(viewport.contains(frame)) tallerThanViewport=\(frame.height > viewport.height)\n"
            + "frameHeightMinusReferenceLine=\(frame.height - font.lineHeight)\n"
            + "boundingRectReferenceWidth=\(referenceWidth) requiredHeight=\(referenceHeight) frameHeightMinusRequired=\(frame.height - referenceHeight)\n"
            + "BoundingRect is a reference comparison; SwiftUI/UIKit Japanese fallback and wrapping can differ.")
        metrics.name = "text-layout-" + name + "-measurements"; metrics.lifetime = .keepAlways
        add(metrics)
        if frame.height <= viewport.height {
            let screenshot = XCTAttachment(screenshot: value.screenshot())
            screenshot.name = "text-layout-" + name + "-element"; screenshot.lifetime = .keepAlways
            add(screenshot)
            attach(app, "text-layout-" + name + "-screen")
        } else {
            // A taller text cannot fit in one screen. Preserve both ends, with
            // the complete intrinsic AX frame recorded above.
            _ = positionTextForMeasurement(value, app: app, edge: .top)
            attach(app, "text-layout-" + name + "-first-screen")
            _ = positionTextForMeasurement(value, app: app, edge: .bottom)
            attach(app, "text-layout-" + name + "-last-screen")
        }
        let previousFailurePolicy = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previousFailurePolicy }
        XCTAssertEqual(label, expected, "Preserve the complete product label")
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertGreaterThanOrEqual(frame.height + 2, font.lineHeight,
                                   "Text must have at least one current semantic line, within two points")
    }

    /// Measurement-only positioning. Audit tests keep using their original
    /// reveal/top helpers and continue to report every SDK issue.
    @MainActor private func positionTextForMeasurement(_ value: XCUIElement,
        app: XCUIApplication, edge: UIRectEdge = []) -> CGRect {
        reveal(value, app)
        for _ in 0..<8 {
            let viewport = textMeasurementViewport(app)
            let frame = value.frame
            let delta: CGFloat
            if edge == .top {
                delta = frame.minY - viewport.minY - 2
            } else if edge == .bottom {
                delta = frame.maxY - viewport.maxY + 2
            } else if frame.height > viewport.height - 4 {
                delta = frame.minY - viewport.minY - 2
            } else {
                if viewport.insetBy(dx: 0, dy: 2).contains(frame) { return viewport }
                delta = frame.midY - viewport.midY
            }
            guard viewport.height > 0, abs(delta) > 2 else { return viewport }
            // Keep both ends of the gesture away from navigation/system bars.
            let distance = min(abs(delta), viewport.height * 0.45)
            let startY = viewport.minY + viewport.height * (delta > 0 ? 0.75 : 0.25)
            let endY = startY + (delta > 0 ? -distance : distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let appFrame = app.frame
            let start = origin.withOffset(CGVector(dx: viewport.midX - appFrame.minX, dy: startY - appFrame.minY))
            let end = origin.withOffset(CGVector(dx: viewport.midX - appFrame.minX, dy: endY - appFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return textMeasurementViewport(app)
    }

    @MainActor private func textMeasurementViewport(_ app: XCUIApplication) -> CGRect {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        let window = app.windows.firstMatch
        let frame = scroll.frame.intersection(window.exists ? window.frame : app.frame)
        let navigationBar = app.navigationBars.firstMatch
        let top = navigationBar.exists ? max(frame.minY, navigationBar.frame.maxY) : frame.minY
        return CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, frame.maxY - top))
    }

    @MainActor private func historySpeechChecks(_ speech: [String]) -> [(name: String, present: Bool)] {
        let normalized = speech.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                       locale: Locale(identifier: "ja_JP")).filter { $0.isLetter || $0.isNumber }
        }
        return [
            ("history removal", normalized.contains { $0.contains("破棄済み") }),
            ("history original absence", normalized.contains { $0.contains("原本なし") }),
            ("submission title", normalized.contains {
                $0.contains("動画") && ($0.contains("original") || $0.contains("オリジナル"))
            }),
            ("submission action", normalized.contains { $0.contains("原本") && $0.contains("再生") }),
            ("submission phase", normalized.contains { $0.contains("引き渡") && $0.contains("プレーヤー") })
        ]
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
        _ = libraryItemTarget("s16v2-cleanup", app)
        XCTAssertTrue(element("library.item.s16v2-cleanup", app).exists,
                      "Expected the separately seeded v2 record")
        XCTAssertTrue(refresh.isEnabled)
        XCTAssertFalse(element("library.loadFailure", app).exists)
        top(app)
    }

    /// A Dynamic Type card may be taller than the screen. Its visible title is
    /// part of the same NavigationLink and accepts the same ordinary tap.
    @MainActor private func libraryItemTarget(_ capture: String, _ app: XCUIApplication) -> XCUIElement {
        let identifier = "library.item." + capture
        var observations: [String] = []
        func attachObservations() {
            let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
            attachment.name = "library-item-target-" + capture
            attachment.lifetime = .keepAlways; add(attachment)
        }
        for attempt in 0..<35 {
            let item = element(identifier, app)
            let itemExists = item.exists
            let itemHit = itemExists && item.isHittable
            var line = "attempt=\(attempt) parentExists=\(itemExists) parentHit=\(itemHit)"
            if itemExists { line += " parentFrame=\(item.frame)" }
            if itemHit {
                observations.append(line + " target=parent")
                attachObservations()
                return item
            }
            let title = item.descendants(matching: .staticText)
                .matching(identifier: "library.itemTitle." + capture).firstMatch
            let titleExists = itemExists && title.exists
            let titleHit = titleExists && title.isHittable
            line += " titleExists=\(titleExists) titleHit=\(titleHit)"
            if titleExists { line += " titleFrame=\(title.frame)" }
            if titleHit {
                observations.append(line + " target=title")
                attachObservations()
                return title
            }
            observations.append(line)
            app.swipeUp()
        }
        attachObservations()
        XCTFail("Cannot reach \(identifier) or its title")
        return element(identifier, app)
    }

    @MainActor private func openOriginalDetail(_ app: XCUIApplication) {
        libraryItemTarget("s16v2-original", app).tap()
        let identity = element("library.detailIdentity", app)
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        XCTAssertEqual(identity.label, "動画 s16v2-original")
    }

    @MainActor private func openOriginal(_ app: XCUIApplication) {
        openOriginalDetail(app)
        let play = app.buttons["library.action.playOriginal"]
        reveal(play, app); XCTAssertTrue(play.isEnabled); tapOriginalPlay(play)
    }

    @MainActor private func selectVideo(_ capture: String, _ app: XCUIApplication) {
        let identifier = "library.select." + capture
        let row = element(identifier, app)
        reveal(row, app)
        // SwiftUI exposes the labelled row and the actual switch separately.
        // Tap the switch control rather than the centre of the surrounding row.
        let control = row.descendants(matching: .switch).firstMatch
        XCTAssertTrue(control.exists)
        XCTAssertTrue(control.isHittable)
        control.tap()
        var observations: [String] = []
        let describe: (Any?) -> String = { value in
            guard let value else { return "nil" }
            return "\(String(reflecting: type(of: value)))=\(String(describing: value))"
        }
        // Resolve both current elements after SwiftUI updates the row, rather
        // than retaining the pre-tap element as the predicate's fixed object.
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let currentRow = element(identifier, app)
            guard currentRow.exists else {
                if observations.count < 32 { observations.append("row missing") }
                return false
            }
            let currentControl = currentRow.descendants(matching: .switch).firstMatch
            guard currentControl.exists else {
                if observations.count < 32 { observations.append("child switch missing") }
                return false
            }
            let rowValue = currentRow.value
            let controlValue = currentControl.value
            if observations.count < 32 {
                observations.append("uptime=\(ProcessInfo.processInfo.systemUptime) "
                    + "rowValue=\(describe(rowValue)) childValue=\(describe(controlValue)) "
                    + "rowFrame=\(currentRow.frame) childFrame=\(currentControl.frame)")
            }
            return rowValue as? String == "1" && controlValue as? String == "1"
        }, object: nil)
        let result = XCTWaiter.wait(for: [selected], timeout: 5)
        let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
        attachment.name = "library-selection-live-" + capture
        attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(result, .completed)
        let currentControl = element(identifier, app).descendants(matching: .switch).firstMatch
        XCTAssertEqual(currentControl.value as? String, "1")
    }

    @MainActor private func showHistory(_ app: XCUIApplication) {
        element("library.scope", app).tap()
        app.buttons["破棄の履歴"].tap()
    }

    @MainActor private func revealPlaybackSubmission(_ app: XCUIApplication) {
        let header = elementWithPrefix("library.submission.header.", app)
        reveal(header, app)
        XCTAssertEqual(header.label, "開始した操作の照合")
        let group = elementWithPrefix("library.submission.target.s16v2-original.", app)
        reveal(group, app)
        let parts = [
            ("title", "動画 s16v2-original"),
            ("action", "iPhone原本を再生"),
            ("phase", "再生機能に引き渡しました。再生状態はプレーヤーで確認してください。")
        ]
        for (part, expected) in parts {
            let child = elementWithPrefix("library.submission." + part + ".s16v2-original.", app)
            if child.exists {
                reveal(child, app)
                XCTAssertTrue(child.label.contains(expected))
            } else {
                // Preserve the existing SwiftUI combine semantics: the three
                // texts may be exposed through their aggregate AX element.
                reveal(group, app)
                XCTAssertTrue(group.label.contains(expected), "Combined submission must expose " + part)
            }
        }
        attach(app, "history-after-handoff-four-submission-texts")
    }

    /// Observe actual changing playback values without scrolling the stop
    /// control back into place. This also covers the single/double digit edge.
    @MainActor private func observeStableOriginalPlaybackStop(_ app: XCUIApplication) {
        var observations: [String] = []
        var secondsObserved = Set<Double>()
        var stopFrames: [CGRect] = []
        var alwaysHittable = true
        var alwaysEnabled = true
        let progress = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let elapsed = element("originalPlayback.elapsed", app)
            let value = elapsed.value as? String ?? "missing"
            let seconds = value.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
                .compactMap(Double.init).first
            if let seconds { secondsObserved.insert(seconds) }
            let stop = app.buttons["originalPlayback.stop"]
            let exists = stop.exists
            let frame = exists ? stop.frame : .zero
            let hittable = exists && stop.isHittable
            let enabled = exists && stop.isEnabled
            alwaysHittable = alwaysHittable && hittable
            alwaysEnabled = alwaysEnabled && enabled
            if exists { stopFrames.append(frame) }
            observations.append("uptime=\(ProcessInfo.processInfo.systemUptime) elapsed=\(value) "
                + "elapsedFrame=\(elapsed.frame) stopExists=\(exists) stopFrame=\(frame) "
                + "stopHittable=\(hittable) stopEnabled=\(enabled)")
            return (seconds ?? 0) >= 10.2
        }, object: nil)
        // The product fixture is 30 seconds. Bound this observation so the
        // explicit stop still precedes natural playback completion.
        let result = XCTWaiter.wait(for: [progress], timeout: 16)
        let lowerEdges = stopFrames.map(\.minY)
        let upperEdges = stopFrames.map(\.maxY)
        let verticalMovement = max((lowerEdges.max() ?? 0) - (lowerEdges.min() ?? 0),
                                   (upperEdges.max() ?? 0) - (upperEdges.min() ?? 0))
        observations.append("result=\(result.rawValue) distinctElapsed=\(secondsObserved.sorted()) "
            + "verticalMovement=\(verticalMovement)")
        let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
        attachment.name = "playback-stop-position-during-elapsed-updates"
        attachment.lifetime = .keepAlways; add(attachment)
        if result != .completed { attachPlaybackFailure(app, stage: "stop-position-progress-timeout") }
        XCTAssertEqual(result, .completed)
        XCTAssertGreaterThanOrEqual(secondsObserved.filter { $0 >= 5 && $0 < 10 }.count, 3,
                                    "Observe multiple real values in the previous wrapping range")
        XCTAssertTrue(secondsObserved.contains { $0 < 10 })
        XCTAssertTrue(secondsObserved.contains { $0 >= 10 }, "Cover the move to two elapsed digits")
        XCTAssertGreaterThanOrEqual(stopFrames.count, 3)
        XCTAssertTrue(alwaysHittable, "Stop must remain reachable without scrolling")
        XCTAssertTrue(alwaysEnabled)
        XCTAssertLessThanOrEqual(verticalMovement, 1, "Elapsed updates must not move the stop control")
        XCTAssertGreaterThanOrEqual(stopFrames.map(\.height).min() ?? 0, 44)
        attach(app, "operation-original-stop-stable-and-reached")
    }

    /// Scroll only the presented player's content, then verify its complete
    /// explanation fits above the separate operation area.
    @MainActor private func reachOriginalPlaybackExplanation(_ app: XCUIApplication,
        name: String, requiresStop: Bool) {
        let scroll = app.scrollViews.matching(identifier: "originalPlayback.content").firstMatch
        let explanation = scroll.staticTexts.matching(identifier: "originalPlayback.explanation").firstMatch
        let ready = scroll.waitForExistence(timeout: 5) && explanation.waitForExistence(timeout: 5)
        if !ready { attach(app, "playback-explanation-" + name + "-missing") }
        XCTAssertTrue(ready, "Reach the explanation in the presented player's own scroll view")
        guard ready else { return }
        let expected = "原本の再生では軽量版の明示確認や写真への保存は行いません。"
        let navigationBar = app.navigationBars["原本の再生"].firstMatch
        let window = app.windows.firstMatch.frame
        var observations: [String] = []
        var stopFrames: [CGRect] = []
        var stopStayedReachable = true
        func observe(_ stage: String) -> (viewport: CGRect, frame: CGRect, label: String, hittable: Bool) {
            let scrollFrame = scroll.frame
            let visible = scrollFrame.intersection(window)
            let navigationFrame = navigationBar.exists ? navigationBar.frame : .zero
            let top = max(visible.minY, navigationFrame.maxY)
            let viewport = CGRect(x: visible.minX, y: top, width: visible.width,
                                  height: max(0, visible.maxY - top))
            let frame = explanation.frame
            let label = explanation.label
            let hittable = explanation.isHittable
            let stop = app.buttons["originalPlayback.stop"]
            let stopExists = stop.exists
            let stopFrame = stopExists ? stop.frame : .zero
            let stopHittable = stopExists && stop.isHittable
            if requiresStop {
                stopStayedReachable = stopStayedReachable && stopHittable
                if stopExists { stopFrames.append(stopFrame) }
            }
            observations.append("uptime=\(ProcessInfo.processInfo.systemUptime) stage=\(stage) "
                + "scrollFrame=\(scrollFrame) navigationFrame=\(navigationFrame) viewport=\(viewport) "
                + "explanationFrame=\(frame) fullyWithinViewport=\(viewport.contains(frame)) "
                + "explanationHittable=\(hittable) label=\(label) "
                + "stopExists=\(stopExists) stopFrame=\(stopFrame) stopHittable=\(stopHittable)")
            return (viewport, frame, label, hittable)
        }
        var current = observe("before-scroll")
        for attempt in 0..<6 {
            if current.viewport.contains(current.frame) { break }
            if current.frame.height > current.viewport.height { break }
            if current.frame.maxY > current.viewport.maxY {
                scroll.swipeUp()
            } else {
                scroll.swipeDown()
            }
            current = observe("after-scroll-\(attempt + 1)")
        }
        let lowerEdges = stopFrames.map(\.minY)
        let upperEdges = stopFrames.map(\.maxY)
        let verticalMovement = max((lowerEdges.max() ?? 0) - (lowerEdges.min() ?? 0),
                                   (upperEdges.max() ?? 0) - (upperEdges.min() ?? 0))
        observations.append("requiresStop=\(requiresStop) stopVerticalMovement=\(verticalMovement)")
        let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
        attachment.name = "playback-explanation-" + name + "-viewport-and-stop-frames"
        attachment.lifetime = .keepAlways; add(attachment)
        attach(app, "playback-explanation-" + name + "-reached")
        XCTAssertTrue(navigationBar.exists)
        XCTAssertEqual(current.label, expected, "Preserve the complete explanation")
        XCTAssertGreaterThan(current.viewport.height, 0)
        XCTAssertTrue(current.viewport.contains(current.frame), "The complete text frame must fit above the operation area")
        XCTAssertTrue(current.hittable)
        if requiresStop {
            XCTAssertFalse(stopFrames.isEmpty)
            XCTAssertTrue(stopStayedReachable, "Scrolling the explanation must preserve stop access")
            XCTAssertLessThanOrEqual(verticalMovement, 1, "Scrolling must not move the stop control")
        }
    }

    @MainActor private func tapOriginalPlaybackStopAndWait(_ app: XCUIApplication) {
        let stopping = "再生を停止し、原本の読み取り終了を確認しています"
        let stopped = "再生を停止しました"
        var observations: [String] = []
        var stoppingWasDisabled = true
        func observe(_ stage: String) -> (phase: String, stopExists: Bool, stopEnabled: Bool,
                                         stopHittable: Bool, playerExists: Bool) {
            let status = element("originalPlayback.status", app)
            let phase = status.exists ? status.label : "missing"
            let stop = app.buttons["originalPlayback.stop"]
            let exists = stop.exists
            let enabled = exists && stop.isEnabled
            let hittable = exists && stop.isHittable
            let playerExists = element("originalPlayback.player", app).exists
            if phase == stopping { stoppingWasDisabled = stoppingWasDisabled && !enabled }
            observations.append("uptime=\(ProcessInfo.processInfo.systemUptime) stage=\(stage) phase=\(phase) "
                + "stopExists=\(exists) stopFrame=\(exists ? stop.frame : .zero) "
                + "stopEnabled=\(enabled) stopHittable=\(hittable) playerExists=\(playerExists)")
            return (phase, exists, enabled, hittable, playerExists)
        }
        func attachObservations(_ stage: String) {
            let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
            attachment.name = "playback-stop-transition-" + stage
            attachment.lifetime = .keepAlways; add(attachment)
        }
        let before = observe("before-single-tap")
        attachObservations("before-single-tap")
        XCTAssertTrue(before.stopExists)
        XCTAssertTrue(before.stopEnabled)
        XCTAssertTrue(before.stopHittable, "The ordinary tap must reach the stop control")
        app.buttons["originalPlayback.stop"].tap()
        let transition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = observe("after-single-tap")
            // Releasing the real reader can complete before the first snapshot.
            return current.phase == stopping || current.phase == stopped
        }, object: nil)
        let transitionResult = XCTWaiter.wait(for: [transition], timeout: 10)
        attachObservations("accepted")
        if transitionResult != .completed { attachPlaybackFailure(app, stage: "stop-tap-transition-timeout") }
        XCTAssertEqual(transitionResult, .completed, "One tap must begin or complete stopping")
        let releaseCompleted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = observe("awaiting-final-stop")
            return current.phase == stopped && !current.stopExists && !current.playerExists
        }, object: nil)
        let releaseResult = XCTWaiter.wait(for: [releaseCompleted], timeout: 10)
        attachObservations("completed")
        if releaseResult != .completed { attachPlaybackFailure(app, stage: "stop-completion-timeout") }
        XCTAssertEqual(releaseResult, .completed)
        XCTAssertTrue(stoppingWasDisabled, "Disable repeat stop while real reader release is pending")
        attach(app, "operation-original-stopped-after-single-tap")
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

    @MainActor private func audit(_ app: XCUIApplication, _ name: String,
        types: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .sufficientElementDescription,
                                            .trait, .hitRegion, .elementDetection, .contrast]) throws {
        attach(app, "accessibility-" + name + "-before")
        attachAuditCandidates(app, "accessibility-" + name + "-before")
        let previousFailurePolicy = continueAfterFailure
        continueAfterFailure = true
        defer {
            attach(app, "accessibility-" + name + "-after")
            attachAuditCandidates(app, "accessibility-" + name + "-after")
            continueAfterFailure = previousFailurePolicy
        }
        try app.performAccessibilityAudit(for: types) { issue in
            var details = [issue.compactDescription, issue.detailedDescription,
                           "auditType=\(issue.auditType.rawValue)",
                           "uptime=\(ProcessInfo.processInfo.systemUptime)",
                           "associatedElement=\(issue.element != nil)"]
            if let associated = issue.element {
                details.append(self.auditMetadata(associated))
                details.append(associated.debugDescription)
            } else { details.append("SDK supplied no associated element") }
            let attachment = XCTAttachment(string: details.joined(separator: "\n"))
            attachment.name = "accessibility-" + name + "-unhandled-issue"
            attachment.lifetime = .keepAlways; self.add(attachment)
            return false // Every SDK issue remains unhandled and is recorded as a failure.
        }
    }

    @MainActor private func attachAuditCandidates(_ app: XCUIApplication, _ name: String) {
        let prefixes = ["library.action.", "library.reason.", "library.status.", "library.detailReconciliation",
                        "library.historyExplanation", "library.item.s16v2-discard", "library.submission.",
                        "originalPlayback.", "product.capture"]
        let predicate = NSPredicate(format: prefixes.map { _ in "identifier BEGINSWITH %@" }.joined(separator: " OR "),
                                    argumentArray: prefixes)
        let candidates = app.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
        var lines = ["uptime=\(ProcessInfo.processInfo.systemUptime) candidates=\(candidates.count)"]
        for candidate in candidates.prefix(64) { lines.append(auditMetadata(candidate)) }
        for bar in app.navigationBars.allElementsBoundByIndex { lines.append(auditMetadata(bar)) }
        for list in app.collectionViews.allElementsBoundByIndex { lines.append(auditMetadata(list)) }
        for scroll in app.scrollViews.allElementsBoundByIndex { lines.append(auditMetadata(scroll)) }
        let value = XCTAttachment(string: lines.joined(separator: "\n"))
        value.name = name + "-candidate-frames"; value.lifetime = .keepAlways
        add(value)
    }

    @MainActor private func auditMetadata(_ value: XCUIElement) -> String {
        "identifier=\(value.identifier) type=\(value.elementType.rawValue) frame=\(value.frame) "
            + "enabled=\(value.isEnabled) label=\(value.label)"
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

@MainActor private func elementWithPrefix(_ prefix: String, _ app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
}
