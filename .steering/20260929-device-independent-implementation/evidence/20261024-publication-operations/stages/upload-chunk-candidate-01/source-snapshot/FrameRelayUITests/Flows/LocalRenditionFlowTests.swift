import UIKit
import XCTest

/// The App receives no fixture flags. The test runner alone receives bounded
/// expected identities extracted from the immutable, one-time Unit seed.
final class LocalRenditionFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testDiagnosticConsumedLocalAvailabilityWithoutStartingPlayer() throws {
        guard ProcessInfo.processInfo.environment["FR_S28_LOCAL_RENDITION_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Consumed local-copy availability diagnostic is not enabled")
        }
        let context = try localContext()
        let target = try XCTUnwrap(context.value.targets.first { $0.kind == "local" })
        let app = XCUIApplication(); app.launch()
        try requireLibrary(app)
        try top(app)
        try itemTarget(target.capture, app).tap()
        let detail = element("library.detailIdentity", app)
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertEqual(detail.label, "動画 " + target.capture)
        let play = button("library.action.playRendition", app)
        try revealVisible(play, app)
        let reason = element("library.reason.playRendition", app)
        if reason.exists { try revealVisible(reason, app) }
        let expected = "この登録・公開版に対応する完全取得済みの軽量版と配布記録を確認できません。必要な媒体の取得は、まだ利用できません。"
        let observed = XCTAttachment(string: context.encoded + "\n" + metadata(play)
            + "\nreasonExists=\(reason.exists)\nrawReason=" + (reason.exists ? reason.label : "<absent>")
            + "\nexpectedCompleteReason=" + expected)
        observed.name = "consumed-local-copy-availability-diagnostic"; observed.lifetime = .keepAlways; add(observed)
        attach(app, "consumed-local-copy-availability-without-sdk-start")
        let oldPolicy = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = oldPolicy }
        XCTAssertFalse(play.isEnabled, "A reclaimed copy must not remain enabled at the native product control")
        XCTAssertTrue(reason.exists)
        if reason.exists { XCTAssertEqual(reason.label, expected) }
        XCTAssertFalse(element("renditionPlayback.target", app).exists)
        XCTAssertFalse(element("renditionPlayback.player", app).exists)
        app.terminate()
    }

    @MainActor func testConsumedRemoteRemainsUnavailableAndNeverRestoresPlaybackAfterRelaunch() throws {
        guard ProcessInfo.processInfo.environment["FR_S28_LOCAL_RENDITION_TAIL_VERIFY"] == "1" else {
            throw XCTSkip("Read-only consumed remote-copy tail verification is not enabled")
        }
        let context = try localContext()
        guard context.value.phase == "normal" else { throw LocalRenditionUIFailure.wrongEnvironment }
        let remote = try XCTUnwrap(context.value.targets.first { $0.kind == "remote" })
        let expectedReason = "この登録・公開版に対応する完全取得済みの軽量版と配布記録を確認できません。必要な媒体の取得は、まだ利用できません。"
        let evidence = XCTAttachment(string: context.encoded
            + "\nRead-only tail verification of the already consumed normal pair. No playback, confirmation, Photos addition or fixture repair is requested.")
        evidence.name = "local-rendition-tail-independent-expected-identities"; evidence.lifetime = .keepAlways; add(evidence)
        let app = XCUIApplication(); app.launch()
        try requireLibrary(app)
        try top(app)
        let token = try remoteToken(capture: remote.capture, app)
        let consumed = button("library.remote.play." + token, app)
        try revealVisible(consumed, app)
        XCTAssertFalse(consumed.isEnabled)
        XCTAssertTrue(consumed.isHittable)
        let reason = element("library.remote.playReason." + token, app)
        try revealVisible(reason, app)
        XCTAssertEqual(reason.label, expectedReason)
        attach(app, "local-rendition-tail-consumed-before-relaunch")
        app.terminate(); app.launch()
        try requireLibrary(app)
        XCTAssertFalse(element("renditionPlayback.target", app).exists)
        XCTAssertFalse(element("renditionPlayback.player", app).exists)
        XCTAssertFalse(element("renditionPlayback.version", app).exists)
        XCTAssertFalse(element("renditionPlayback.confirmation", app).exists)
        XCTAssertFalse(button("renditionPlayback.confirm", app).exists)
        try assertUnacquired(context.value.negativeCapture, app)
        let restoredToken = try remoteToken(capture: remote.capture, app)
        let noRestart = button("library.remote.play." + restoredToken, app)
        try revealVisible(noRestart, app)
        XCTAssertFalse(noRestart.isEnabled)
        XCTAssertTrue(noRestart.isHittable)
        let restoredReason = element("library.remote.playReason." + restoredToken, app)
        try revealVisible(restoredReason, app)
        XCTAssertEqual(restoredReason.label, expectedReason)
        try audit(app, "tail-consumed-remote-after-relaunch")
        attach(app, "local-rendition-tail-no-token-or-auto-playback-after-relaunch")
    }

    @MainActor func testLocalAndRemoteCompleteCopiesPlayConfirmStopAndNeverAutoRestore() throws {
        guard ProcessInfo.processInfo.environment["FR_S28_LOCAL_RENDITION_UI"] == "1" else {
            throw XCTSkip("Dedicated local-rendition normal root is not enabled")
        }
        let context = try localContext()
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in
            let close = self.button("renditionPlayback.close", app)
            if close.exists && close.isHittable && close.isEnabled {
                close.tap()
                let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !close.exists }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 20), .completed,
                    "Even a UI assertion failure must ask the live player to close")
            }
        }
        let evidence = XCTAttachment(string: context.encoded + "\nrunnerContentSizeCategory="
            + UIApplication.shared.preferredContentSizeCategory.rawValue
            + "\nRunner UIKit metrics are references; product frames, complete AX labels and screenshots are actual layout evidence.")
        evidence.name = "local-rendition-independent-expected-identities"; evidence.lifetime = .keepAlways; add(evidence)
        let local = try XCTUnwrap(context.value.targets.first { $0.kind == "local" })
        let remote = try XCTUnwrap(context.value.targets.first { $0.kind == "remote" })
        app.launch()
        try requireLibrary(app)
        try assertUnacquired(context.value.negativeCapture, app)
        try top(app)
        try itemTarget(local.capture, app).tap()
        let detail = element("library.detailIdentity", app)
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertEqual(detail.label, "動画 " + local.capture)
        let publication = element("library.status.publication", app)
        try revealVisible(publication, app)
        XCTAssertTrue(publication.label.contains("公開版ID：" + local.rendition))
        XCTAssertTrue(publication.label.contains("公開世代：\(local.publicationGeneration)"))
        let before = element("library.status.confirmation", app)
        try revealVisible(before, app)
        XCTAssertTrue(before.label.contains("現在の記録版の明示確認なし"))
        let open = button("library.action.playRendition", app)
        try revealVisible(open, app)
        XCTAssertTrue(open.isEnabled && open.isHittable)
        try audit(app, context.value.phase + "-local-detail-before-play")
        open.tap()
        try requirePlaying(local, app)
        try observeStableStopDuringActualElapsedUpdates(local, app)
        try audit(app, context.value.phase + "-local-playing-stable-footer")
        try revealFullPlaybackExplanationWhileStopRemainsFixed(app)
        let stop = button("renditionPlayback.stop", app)
        XCTAssertTrue(stop.isEnabled && stop.isHittable)
        stop.tap()
        try requireStopped(local, app)
        XCTAssertFalse(element("renditionPlayback.confirmation", app).exists)
        let confirm = button("renditionPlayback.confirm", app)
        XCTAssertTrue(confirm.isEnabled && confirm.isHittable,
            "An actual playback token remains confirmable in this same stopped presentation")
        confirm.tap()
        try requireConfirmed(local, app)
        try audit(app, context.value.phase + "-local-stopped-explicit-confirmation")
        try closePlayer(app)
        try revealVisible(before, app)
        XCTAssertTrue(before.label.contains("有効な明示確認の保存記録あり"))
        let acquiredAgain = button("library.action.playRendition", app)
        try revealVisible(acquiredAgain, app)
        XCTAssertFalse(acquiredAgain.isEnabled, "The consumed copy is not restored to make another playback succeed")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        try requireLibrary(app)

        let remoteRowToken = try remoteToken(capture: remote.capture, app)
        let remotePublication = element("library.remote.publication." + remoteRowToken, app)
        try revealVisible(remotePublication, app)
        XCTAssertTrue(remotePublication.label.contains("公開版ID：" + remote.rendition))
        XCTAssertTrue(remotePublication.label.contains("公開世代：\(remote.publicationGeneration)"))
        let remoteOpen = button("library.remote.play." + remoteRowToken, app)
        try revealVisible(remoteOpen, app)
        XCTAssertTrue(remoteOpen.isEnabled && remoteOpen.isHittable)
        remoteOpen.tap()
        try requirePlaying(remote, app)
        try audit(app, context.value.phase + "-remote-playing")
        let remoteConfirm = button("renditionPlayback.confirm", app)
        XCTAssertTrue(remoteConfirm.isEnabled && remoteConfirm.isHittable)
        remoteConfirm.tap()
        try requireConfirmed(remote, app, revealFeedback: false)
        XCUIDevice.shared.press(.home)
        try wait("The ordinary App must enter the background", timeout: 10) {
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }
        app.activate()
        try requireStopped(remote, app)
        try requireConfirmed(remote, app)
        try audit(app, context.value.phase + "-remote-background-terminal")
        try closePlayer(app)
        try requireLibrary(app)
        try top(app)
        let consumedRemote = button("library.remote.play." + remoteRowToken, app)
        try revealVisible(consumedRemote, app)
        XCTAssertFalse(consumedRemote.isEnabled)
        app.terminate(); app.launch()
        try requireLibrary(app)
        XCTAssertFalse(element("renditionPlayback.target", app).exists)
        XCTAssertFalse(element("renditionPlayback.player", app).exists)
        XCTAssertFalse(element("renditionPlayback.version", app).exists)
        XCTAssertFalse(element("renditionPlayback.confirmation", app).exists)
        try assertUnacquired(context.value.negativeCapture, app)
        let afterRelaunch = try remoteToken(capture: remote.capture, app)
        let noRestart = button("library.remote.play." + afterRelaunch, app)
        try revealVisible(noRestart, app)
        XCTAssertFalse(noRestart.isEnabled)
        attach(app, context.value.phase + "-relaunch-no-token-or-auto-playback")
    }

    @MainActor private func localContext() throws -> (value: LocalRenditionExpected, encoded: String) {
        let environment = ProcessInfo.processInfo.environment
        let encoded = try XCTUnwrap(environment["FR_S28_LOCAL_EXPECTED"])
        guard encoded.utf8.count <= 8192 else { throw LocalRenditionUIFailure.wrongEnvironment }
        let value = try JSONDecoder().decode(LocalRenditionExpected.self, from: Data(encoded.utf8))
        let nonce = try XCTUnwrap(environment["FR_S28_LOCAL_RENDITION_NONCE"])
        let phase = try XCTUnwrap(environment["FR_S28_LOCAL_RENDITION_PHASE"])
        let requested = try XCTUnwrap(environment["FR_S28_LOCAL_RENDITION_SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let actual = try XCTUnwrap(environment["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let dedicated: Set<UUID> = [UUID(uuidString: "32123811-3702-4F30-A198-CEC7F743D711")!,
            UUID(uuidString: "D4AFACDE-F4C0-4527-8A0A-1E64A8BB4F03")!,
            UUID(uuidString: "FFAC5EB6-0006-4186-ABD8-503013CA4ECC")!,
            UUID(uuidString: "19086AB5-0EC7-4CE2-ADDE-A7C2939E1675")!,
            UUID(uuidString: "842A7F12-8232-4248-A78A-87757694B6D9")!,
            UUID(uuidString: "76647BEF-D2F9-4883-B6BC-F34AA9F4DA4E")!]
        guard value.schema == "fr-s28-local-ui-v1", dedicated.contains(requested), actual == requested,
              UUID(uuidString: value.simulator) == actual, UUID(uuidString: nonce)?.uuidString.lowercased() == nonce,
              value.nonce == nonce, ["normal", "max"].contains(phase), value.phase == phase,
              value.targets.count == 2, Set(value.targets.map(\.kind)) == ["local", "remote"],
              value.negativeCapture == "s28lr-" + nonce + "-unacquired",
              value.targets.allSatisfy({ target in
                  target.capture == "s28lr-" + nonce + "-" + phase + "-" + target.kind
                      && UUID(uuidString: target.rendition)?.uuidString.lowercased() == target.rendition
                      && target.publicationGeneration == 1
              }) else { throw LocalRenditionUIFailure.wrongEnvironment }
        return (value, encoded)
    }

    @MainActor private func requirePlaying(_ target: LocalRenditionExpected.Target, _ app: XCUIApplication) throws {
        try wait("The exact local movie must actually advance before confirmation", timeout: 20) {
            self.element("renditionPlayback.status", app).label == "端末内の軽量版を再生中"
                && self.element("renditionPlayback.player", app).exists
                && self.elapsedSeconds(app) > 0.2
                && self.element("renditionPlayback.version", app).exists
        }
        XCTAssertEqual(element("renditionPlayback.target", app).label, "動画 " + target.capture)
        XCTAssertEqual(element("renditionPlayback.version", app).label, "再生版ID：" + target.rendition)
        XCTAssertFalse(element("renditionPlayback.issue", app).exists)
        XCTAssertFalse(element("renditionPlayback.confirmation", app).exists,
            "Actual playback alone never creates an explicit confirmation")
        XCTAssertTrue(button("renditionPlayback.confirm", app).isEnabled)
    }

    @MainActor private func requireStopped(_ target: LocalRenditionExpected.Target, _ app: XCUIApplication) throws {
        try wait("Stop must finish SDK/reader teardown rather than only accept cancellation", timeout: 20) {
            self.element("renditionPlayback.status", app).label == "軽量版の再生を停止しました"
                && !self.element("renditionPlayback.player", app).exists
                && !self.button("renditionPlayback.stop", app).exists
        }
        XCTAssertEqual(element("renditionPlayback.target", app).label, "動画 " + target.capture)
        XCTAssertEqual(element("renditionPlayback.version", app).label, "再生版ID：" + target.rendition)
        XCTAssertFalse(element("renditionPlayback.issue", app).exists)
        let close = button("renditionPlayback.close", app)
        XCTAssertTrue(close.isEnabled && close.isHittable)
    }

    @MainActor private func requireConfirmed(_ target: LocalRenditionExpected.Target, _ app: XCUIApplication,
        revealFeedback: Bool = true) throws {
        let feedback = element("renditionPlayback.confirmation", app)
        try wait("The singular user action must obtain its exact durable confirmation", timeout: 15) {
            feedback.exists && feedback.label == "この再生版の明示確認を保存しました。Mac miniへの送達は別に照合します。"
                && !self.button("renditionPlayback.confirm", app).isEnabled
        }
        XCTAssertEqual(element("renditionPlayback.version", app).label, "再生版ID：" + target.rendition)
        XCTAssertFalse(element("renditionPlayback.issue", app).exists)
        if revealFeedback { try revealVisible(feedback, app, scroll: app.scrollViews["renditionPlayback.content"]) }
    }

    @MainActor private func closePlayer(_ app: XCUIApplication) throws {
        let close = button("renditionPlayback.close", app)
        XCTAssertTrue(close.isEnabled && close.isHittable)
        close.tap()
        try wait("Close must dismiss only after the live reader owner ends", timeout: 20) {
            !self.element("renditionPlayback.target", app).exists && !close.exists
        }
    }

    @MainActor private func observeStableStopDuringActualElapsedUpdates(_ target: LocalRenditionExpected.Target,
        _ app: XCUIApplication) throws {
        var seconds = Set<Double>(), frames: [CGRect] = [], observations: [String] = []
        var reachable = true
        let progress = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = self.elapsedSeconds(app)
            seconds.insert(value)
            let stop = self.button("renditionPlayback.stop", app)
            let exists = stop.exists
            reachable = reachable && exists && stop.isEnabled && stop.isHittable
            if exists { frames.append(stop.frame) }
            observations.append("uptime=\(ProcessInfo.processInfo.systemUptime) seconds=\(value) stopExists=\(exists) "
                + "stopFrame=\(exists ? stop.frame : .zero) version=\(self.element("renditionPlayback.version", app).label)")
            return value >= 10.2
        }, object: nil)
        let result = XCTWaiter.wait(for: [progress], timeout: 17)
        let movement = max((frames.map(\.minY).max() ?? 0) - (frames.map(\.minY).min() ?? 0),
            (frames.map(\.maxY).max() ?? 0) - (frames.map(\.maxY).min() ?? 0))
        observations.append("waitResult=\(result.rawValue) distinctSeconds=\(seconds.sorted()) verticalMovement=\(movement)")
        let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
        attachment.name = "local-rendition-stop-position-during-real-progress"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(seconds.contains { $0 < 10 } && seconds.contains { $0 >= 10 })
        XCTAssertGreaterThanOrEqual(seconds.count, 3)
        XCTAssertGreaterThanOrEqual(frames.count, 3)
        XCTAssertTrue(reachable)
        XCTAssertLessThanOrEqual(movement, 1)
        XCTAssertGreaterThanOrEqual(frames.map(\.height).min() ?? 0, 44)
        XCTAssertEqual(element("renditionPlayback.version", app).label, "再生版ID：" + target.rendition)
    }

    @MainActor private func revealFullPlaybackExplanationWhileStopRemainsFixed(_ app: XCUIApplication) throws {
        let scroll = app.scrollViews["renditionPlayback.content"]
        let explanation = element("renditionPlayback.explanation", app)
        let navigation = app.navigationBars.matching(NSPredicate(format:
            "identifier == %@", "軽量版の再生と確認")).firstMatch
        let expected = "完全取得済みの軽量版を端末内から再生します。Wi-FiやMac miniへの接続は不要です。実際に再生した同じ版を、本人の操作で1本ずつ確認できます。再生だけでは確認済みになりません。停止や終了後も、この画面の同じ再生版を確認できます。画面を閉じると、この再生に対する確認操作は終了します。使用を終えた一時媒体は既存の回収条件に従って解放され、次回は取得が必要になる場合があります。iPhone原本とMac mini、写真の動画は削除しません。"
        var observations: [String] = []
        let ready = scroll.waitForExistence(timeout: 5) && explanation.waitForExistence(timeout: 5)
            && navigation.waitForExistence(timeout: 5)
        let initial = explanationGeometry(scroll: scroll, explanation: explanation, navigation: navigation, app: app)
        recordExplanationGeometry(initial, stage: "initial ready=\(ready)", expected: expected, observations: &observations)
        XCTAssertTrue(ready)
        XCTAssertTrue(initial.stopExists && initial.stopEnabled && initial.stopHittable)
        XCTAssertGreaterThanOrEqual(initial.stop.height, 44)
        let originalStop = initial.stop
        var reachedFirst = false, reachedLast = false
        for attempt in 0..<28 {
            let geometry = explanationGeometry(scroll: scroll, explanation: explanation, navigation: navigation, app: app)
            let viewport = geometry.viewport, frame = geometry.explanation
            if frame.minY >= viewport.minY - 2 && frame.minY < viewport.maxY { reachedFirst = true }
            if frame.maxY <= viewport.maxY + 2 && frame.maxY > viewport.minY { reachedLast = true }
            recordExplanationGeometry(geometry, stage: "attempt=\(attempt) first=\(reachedFirst) last=\(reachedLast)",
                expected: expected, observations: &observations)
            XCTAssertTrue(geometry.stopExists && geometry.stopEnabled && geometry.stopHittable)
            XCTAssertEqual(geometry.stop, originalStop, "Scrolling the explanation must leave the footer in place")
            XCTAssertGreaterThanOrEqual(geometry.stop.height, 44)
            XCTAssertLessThanOrEqual(geometry.scroll.intersection(geometry.app).maxY, geometry.stop.minY)
            XCTAssertGreaterThan(viewport.height, 0)
            if reachedFirst && reachedLast { break }
            // Position an actual endpoint instead of flicking past its narrow
            // visibility window and reversing all the way to the previous page.
            let delta = !reachedFirst ? frame.minY - viewport.minY - 4 : frame.maxY - viewport.maxY + 4
            dragExplanationGutter(viewport: viewport, delta: delta, app: app)
        }
        let final = explanationGeometry(scroll: scroll, explanation: explanation, navigation: navigation, app: app)
        if final.explanation.minY >= final.viewport.minY - 2 && final.explanation.minY < final.viewport.maxY { reachedFirst = true }
        if final.explanation.maxY <= final.viewport.maxY + 2 && final.explanation.maxY > final.viewport.minY { reachedLast = true }
        recordExplanationGeometry(final, stage: "final first=\(reachedFirst) last=\(reachedLast)",
            expected: expected, observations: &observations)
        XCTAssertTrue(final.stopExists && final.stopEnabled && final.stopHittable)
        XCTAssertEqual(final.stop, originalStop, "Scrolling the explanation must leave the footer in place")
        XCTAssertGreaterThanOrEqual(final.stop.height, 44)
        XCTAssertLessThanOrEqual(final.scroll.intersection(final.app).maxY, final.stop.minY)
        XCTAssertEqual(explanation.label, expected.replacingOccurrences(of: "\n", with: " "))
        XCTAssertTrue(reachedFirst && reachedLast, "Reach both ends of the complete explanation through its ordinary scroll view")
        attach(app, "local-rendition-explanation-reached-footer-remains-visible")
    }

    private struct ExplanationGeometry {
        let scroll: CGRect
        let navigation: CGRect
        let app: CGRect
        let explanation: CGRect
        let stop: CGRect
        let stopExists: Bool
        let stopEnabled: Bool
        let stopHittable: Bool
        let label: String
        var viewport: CGRect {
            let area = scroll.intersection(app)
            guard !area.isNull else { return .zero }
            let upper = max(area.minY, navigation.maxY)
            let lower = min(area.maxY, stop.minY)
            return CGRect(x: area.minX, y: upper, width: area.width, height: max(0, lower - upper))
        }
    }

    @MainActor private func explanationGeometry(scroll: XCUIElement, explanation: XCUIElement,
        navigation: XCUIElement, app: XCUIApplication) -> ExplanationGeometry {
        let stop = button("renditionPlayback.stop", app)
        let exists = stop.exists
        return .init(scroll: scroll.exists ? scroll.frame : .zero,
            navigation: navigation.exists ? navigation.frame : .zero, app: app.frame,
            explanation: explanation.exists ? explanation.frame : .zero,
            stop: exists ? stop.frame : .zero, stopExists: exists,
            stopEnabled: exists && stop.isEnabled, stopHittable: exists && stop.isHittable,
            label: explanation.exists ? explanation.label : "<absent>")
    }

    @MainActor private func recordExplanationGeometry(_ geometry: ExplanationGeometry, stage: String,
        expected: String, observations: inout [String]) {
        observations.append("uptime=\(ProcessInfo.processInfo.systemUptime) stage=\(stage) scroll=\(geometry.scroll) "
            + "playerNavigation=\(geometry.navigation) app=\(geometry.app) viewport=\(geometry.viewport) "
            + "explanation=\(geometry.explanation) stopExists=\(geometry.stopExists) stop=\(geometry.stop) "
            + "stopEnabled=\(geometry.stopEnabled) stopHittable=\(geometry.stopHittable) fullLabel=\(geometry.label)")
        // Add before any potentially aborting XCTest assertion. A Swift defer
        // is not sufficient when continueAfterFailure=false aborts a test case.
        let evidence = XCTAttachment(string: observations.joined(separator: "\n") + "\nexpectedCompleteSourceText=" + expected)
        evidence.name = "local-rendition-explanation-ordinary-scroll-and-fixed-footer"
        evidence.lifetime = .keepAlways; add(evidence)
    }

    @MainActor private func dragExplanationGutter(viewport: CGRect, delta: CGFloat, app: XCUIApplication) {
        // MAX52 moved about 144.3pt for a 154.4pt drag, then a final 10pt
        // gesture moved nothing. Cross the pan recognition threshold with a
        // finite gesture; endpoint assertions still use the actual viewport.
        let distance = min(max(abs(delta), 32), viewport.height * 0.4)
        let x = viewport.minX + min(8, viewport.width * 0.1)
        let startY = viewport.minY + viewport.height * (delta > 0 ? 0.8 : 0.2)
        let endY = startY + (delta > 0 ? -distance : distance)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let appFrame = app.frame
        let start = origin.withOffset(CGVector(dx: x - appFrame.minX, dy: startY - appFrame.minY))
        let end = origin.withOffset(CGVector(dx: x - appFrame.minX, dy: endY - appFrame.minY))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    @MainActor private func elapsedSeconds(_ app: XCUIApplication) -> Double {
        let value = element("renditionPlayback.elapsed", app).value as? String ?? ""
        return value.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap(Double.init).first ?? 0
    }

    @MainActor private func assertUnacquired(_ capture: String, _ app: XCUIApplication) throws {
        let token = try remoteToken(capture: capture, app)
        let play = button("library.remote.play." + token, app)
        try revealVisible(play, app)
        XCTAssertFalse(play.isEnabled)
        let reason = element("library.remote.playReason." + token, app)
        try revealVisible(reason, app)
        XCTAssertEqual(reason.label, "この登録・公開版に対応する完全取得済みの軽量版と配布記録を確認できません。必要な媒体の取得は、まだ利用できません。")
    }

    @MainActor private func remoteToken(capture: String, _ app: XCUIApplication) throws -> String {
        try top(app)
        let title = app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label == %@", "library.remote.title.", "動画 " + capture)).firstMatch
        try revealVisible(title, app)
        XCTAssertTrue(title.identifier.hasPrefix("library.remote.title."))
        return String(title.identifier.dropFirst("library.remote.title.".count))
    }

    @MainActor private func requireLibrary(_ app: XCUIApplication) throws {
        let refresh = button("library.refresh", app)
        XCTAssertTrue(refresh.waitForExistence(timeout: 15))
        try wait("The shared-writer library must finish loading", timeout: 15) {
            refresh.isEnabled && !self.element("library.loadFailure", app).exists
        }
        XCTAssertFalse(element("library.empty", app).exists)
    }

    @MainActor private func itemTarget(_ capture: String, _ app: XCUIApplication) throws -> XCUIElement {
        for _ in 0..<56 {
            let item = element("library.item." + capture, app)
            if item.exists && item.isHittable { return item }
            let title = item.descendants(matching: .staticText).matching(NSPredicate(format:
                "identifier == %@", "library.itemTitle." + capture)).firstMatch
            if item.exists && title.exists && title.isHittable { return title }
            app.swipeUp()
        }
        throw LocalRenditionUIFailure.unreachable
    }

    @MainActor private func top(_ app: XCUIApplication) throws {
        let camera = button("product.capture", app)
        for _ in 0..<64 {
            if camera.exists && camera.isHittable && camera.frame.midY > app.navigationBars.firstMatch.frame.maxY + 2 { return }
            app.swipeDown()
        }
        throw LocalRenditionUIFailure.unreachable
    }

    @MainActor private func revealVisible(_ value: XCUIElement, _ app: XCUIApplication,
        scroll: XCUIElement? = nil) throws {
        for _ in 0..<64 {
            if value.exists {
                let upper = app.navigationBars.firstMatch.frame.maxY + 2
                let viewport = (scroll?.frame ?? app.frame).intersection(
                    CGRect(x: app.frame.minX, y: upper, width: app.frame.width, height: max(0, app.frame.maxY - upper - 8)))
                let visible = value.frame.intersection(viewport)
                if !visible.isNull && visible.height >= min(44, value.frame.height) { return }
                if value.frame.maxY <= upper { (scroll ?? app).swipeDown(); continue }
            }
            (scroll ?? app).swipeUp()
        }
        attach(app, "local-rendition-unreachable-element")
        throw LocalRenditionUIFailure.unreachable
    }

    @MainActor private func wait(_ message: String, timeout: TimeInterval, predicate: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            XCTFail(message); throw LocalRenditionUIFailure.unexpectedState
        }
    }

    @MainActor private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }
    @MainActor private func button(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    @MainActor private func audit(_ app: XCUIApplication, _ name: String) throws {
        let types: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .sufficientElementDescription,
                                                .trait, .hitRegion, .elementDetection, .contrast]
        attach(app, name + "-accessibility-before")
        let oldPolicy = continueAfterFailure
        continueAfterFailure = true
        defer { attach(app, name + "-accessibility-after"); continueAfterFailure = oldPolicy }
        try app.performAccessibilityAudit(for: types) { issue in
            var lines = [issue.compactDescription, issue.detailedDescription, "auditType=\(issue.auditType.rawValue)",
                         "uptime=\(ProcessInfo.processInfo.systemUptime)"]
            if let associated = issue.element { lines += [self.metadata(associated), associated.debugDescription] }
            let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
            attachment.name = name + "-unhandled-accessibility-issue"; attachment.lifetime = .keepAlways; self.add(attachment)
            return false
        }
    }

    @MainActor private func metadata(_ value: XCUIElement) -> String {
        "identifier=\(value.identifier) type=\(value.elementType.rawValue) frame=\(value.frame) enabled=\(value.isEnabled) label=\(value.label)"
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = name
        screen.lifetime = .keepAlways; add(screen)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"
        tree.lifetime = .keepAlways; add(tree)
    }
}

private struct LocalRenditionExpected: Decodable {
    let schema: String
    let nonce: String
    let simulator: String
    let phase: String
    let targets: [Target]
    let negativeCapture: String
    struct Target: Decodable {
        let kind: String
        let capture: String
        let rendition: String
        let publicationGeneration: UInt64
    }
}
private enum LocalRenditionUIFailure: Error { case wrongEnvironment, unexpectedState, unreachable }
