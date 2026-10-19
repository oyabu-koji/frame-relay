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
        let stabilization = app.staticTexts["capture.stabilization"]
        if !stabilization.isHittable { app.swipeUp() }
        XCTAssertTrue(stabilization.exists)
        XCTAssertTrue(stabilization.label.contains("未確認"))
        XCTAssertTrue(app.staticTexts["capture.framing"].label.contains("一致は確認できていません"))
        let whiteBalance = app.staticTexts["capture.whiteBalance"]
        if !whiteBalance.isHittable { app.swipeUp() }
        XCTAssertTrue(whiteBalance.exists)
        XCTAssertTrue(whiteBalance.label.contains("未確認"))
        XCTAssertFalse(app.buttons["capture.refreshWhiteBalance"].isEnabled)
        let subjects = app.staticTexts["capture.subject.state"]
        for _ in 0..<4 where !subjects.isHittable { app.swipeUp() }
        XCTAssertTrue(subjects.exists)
        XCTAssertTrue(subjects.label.contains("未確認"))
        XCTAssertTrue(subjects.label.contains("REC"))
        let ndAdvice = app.staticTexts["capture.ndAdvice"]
        for _ in 0..<3 where !ndAdvice.isHittable { app.swipeUp() }
        XCTAssertTrue(ndAdvice.exists)
        XCTAssertTrue(ndAdvice.label.contains("保留"))
        let ndReason = app.staticTexts["capture.ndReason"]
        XCTAssertTrue(ndReason.label.contains("入力"))
        XCTAssertFalse(ndReason.label.contains("評価基準はまだ設定"))
        let audio = app.staticTexts["capture.audio.input"]
        if !audio.isHittable { app.swipeUp() }
        XCTAssertTrue(audio.exists)
        XCTAssertFalse(app.buttons["capture.audio.retry"].isEnabled)
        XCTAssertFalse(app.staticTexts["capture.audio.failure"].exists)
        XCTAssertFalse(app.buttons["exploration.import"].exists)
        app.buttons["capture.closeToolbar"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.refresh"].exists)
        #endif
    }

    @MainActor func testStabilizationSettingsKeepCandidateUnconfirmedWithoutCameraAndDoNotInventFPS() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulatorで能力未確認の通常設定表示を検証します")
        #else
        let app = XCUIApplication()
        app.launch()
        let entry = app.buttons["product.capture"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let settings = app.buttons["capture.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["capture.desired"].label.hasPrefix("未選択。"))
        settings.tap()
        let fps = app.buttons["capture.settings.fps"]
        XCTAssertTrue(fps.waitForExistence(timeout: 5))
        let fpsText = pickerDisplayedText(fps, attachmentName: "Initial frame-rate picker")
        XCTAssertTrue(fpsText.contains("選択してください"), fpsText)
        XCTAssertFalse(fpsText.contains("24 fps") || fpsText.contains("30 fps"), fpsText)
        let picker = app.buttons["capture.settings.stabilization"]
        for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.exists)
        let status = app.staticTexts["capture.settings.stabilizationStatus"]
        XCTAssertTrue(status.exists)
        XCTAssertTrue(status.label.contains("カメラ") || status.label.contains("未確認"))
        let stabilizationText = pickerDisplayedText(picker, attachmentName: "Initial stabilization picker")
        XCTAssertTrue(stabilizationText.contains("標準（未確認）"), stabilizationText)
        app.buttons["capture.settings.close"].tap()
        app.buttons["capture.closeToolbar"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        #endif
    }

    /// The run owner preserves/restores the Simulator's preference file while the
    /// app is stopped. Initial nil intent is covered with an isolated product store.
    @MainActor func testShootingIntentCanBeChosenWithoutCameraAndRestoresAfterRelaunch() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulatorで通常画面の撮影意図保存・復元を検証します")
        #else
        let app = XCUIApplication()
        app.launch()
        openCaptureAndRevealIntent(in: app)
        let picker = app.buttons["capture.subject.intent"]
        XCTAssertTrue(picker.isEnabled)
        let originalText = pickerDisplayedText(picker, attachmentName: "Original shooting intent")
        let original = ["人物のみ", "人物＋背景", "景色優先"].first { originalText.contains($0) }
        let chosen = original == "人物＋背景" ? "景色優先" : "人物＋背景"
        chooseShootingIntent(chosen, in: app)
        XCTAssertFalse(app.buttons["capture.rec"].isEnabled)
        XCTAssertTrue(app.staticTexts["capture.subject.state"].label.contains("未確認"))

        app.terminate()
        app.launch()
        openCaptureAndRevealIntent(in: app)
        let restored = pickerDisplayedText(app.buttons["capture.subject.intent"], attachmentName: "Restored shooting intent")
        XCTAssertTrue(restored.contains(chosen), restored)
        XCTAssertFalse(app.buttons["capture.rec"].isEnabled)
        XCTAssertTrue(app.staticTexts["capture.subject.state"].label.contains("未確認"))
        if let original { chooseShootingIntent(original, in: app) }
        app.buttons["capture.closeToolbar"].tap()
        XCTAssertTrue(app.buttons["product.capture"].waitForExistence(timeout: 5))
        #endif
    }

    @MainActor private func openCaptureAndRevealIntent(in app: XCUIApplication) {
        let entry = app.buttons["product.capture"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let issue = app.staticTexts["capture.issue"]
        XCTAssertTrue(issue.waitForExistence(timeout: 10))
        XCTAssertTrue(issue.label.contains("Simulator"))
        let picker = app.buttons["capture.subject.intent"]
        for _ in 0..<6 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable)
    }

    @MainActor private func chooseShootingIntent(_ title: String, in app: XCUIApplication) {
        let picker = app.buttons["capture.subject.intent"]
        picker.tap()
        let option = app.buttons[title].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let labels = [picker.label] + picker.staticTexts.allElementsBoundByIndex.map(\.label)
            return (labels + [picker.value.map { String(describing: $0) } ?? ""]).joined(separator: "\n").contains(title)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    /// SwiftUI menu pickers can expose the displayed selection in the label or a
    /// child static text while their value is a non-nil unrelated control value.
    /// Scope all text to this picker, so another row's placeholder cannot satisfy it.
    @MainActor private func pickerDisplayedText(_ picker: XCUIElement, attachmentName: String) -> String {
        let labels = [picker.label] + picker.staticTexts.allElementsBoundByIndex.map(\.label)
        let value = picker.value.map { String(describing: $0) } ?? "<nil>"
        let text = (labels + [value]).joined(separator: "\n")
        let attachment = XCTAttachment(string: "value=\(value)\n\(picker.debugDescription)")
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
        return text
    }

}
