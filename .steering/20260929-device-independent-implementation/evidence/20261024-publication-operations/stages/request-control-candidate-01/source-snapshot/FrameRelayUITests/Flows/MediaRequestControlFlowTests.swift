import UIKit
import XCTest

/// Expected values belong to the runner. The ordinary product App receives no
/// launch flags, environment, network mocks or fixture-setting UI. A phase is
/// armed only for its exact unconsumed prefix; no failed tap is retried here.
final class MediaRequestControlFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testExistingRequestsPersonIntentFixedAllPauseAndRelaunch() throws {
        guard ProcessInfo.processInfo.environment["FR_MEDIA_REQUEST_CONTROL_UI"] == "1" else {
            throw XCTSkip("Dedicated one-time media request control fixture is not enabled")
        }
        let context = try requestContext()
        let app = XCUIApplication()
        XCTAssertTrue(app.launchArguments.isEmpty && app.launchEnvironment.isEmpty)
        guard app.launchArguments.isEmpty && app.launchEnvironment.isEmpty else { throw RequestControlUIFailure.wrongEnvironment }
        let expected = XCTAttachment(string: context.encoded + "\nphase=" + context.phase
            + "\nstartPhase=" + (context.startPhase ?? "<none>")
            + "\nrunnerContentSizeCategory=" + UIApplication.shared.preferredContentSizeCategory.rawValue
            + "\nSimulator font setting is supplied and restored by the main runner. Only native product controls are used.")
        expected.name = "media-request-control-independent-expectations"; expected.lifetime = .keepAlways; add(expected)
        app.launch()
        try loaded(app)
        let firstPhase = context.startPhase ?? context.phase
        let phases: [String]
        if context.phase == "all" { phases = Array(requestControlUIPhases.dropFirst()) + ["relaunch"] }
        else if context.phase == "tail", firstPhase != "relaunch" {
            let start = try stage(firstPhase)
            phases = Array(requestControlUIPhases[start...]) + ["relaunch"]
        } else { phases = [firstPhase] }
        var history = try scanRootHistory(app)
        let firstStage = context.phase == "all" ? 0 : firstPhase == "relaunch" ? 6 : try stage(firstPhase) - 1
        try requireHistory(history, stage: firstStage, context: context.value, afterRelaunch: true)
        if context.phase == "tail", firstPhase == "localCancel" {
            try assertPausedRequestsAfterAllPause(context.value, app)
        }
        for phase in phases {
            if phase == "relaunch" {
                try requireHistory(history, stage: 6, context: context.value)
                let before = history
                app.terminate()
                app.launch()
                try loaded(app)
                history = try scanRootHistory(app)
                try requireHistory(history, stage: 6, context: context.value, afterRelaunch: true)
                XCTAssertEqual(history.plans, before.plans)
                XCTAssertEqual(history.headings, before.headings)
                XCTAssertEqual(history.identities, before.identities)
                XCTAssertEqual(history.decisions, before.decisions)
                try assertTerminalRows(context.value, app)
                try openLocal(context.value.target("local"), app)
                try assertRequest(context.value.target("local"), intent: "cancelled", app)
                try assertActions(context.value.target("local"), pause: false, cancel: false, resume: false,
                    reason: "この通信要求は本人取消済みです。", app)
                try audit(app, context.value.variant + "-relaunch-local-cancelled-no-auto-dispatch")
                try closeLocal(app)
                let allPause = button("library.request.allPause", app)
                try rootReveal(allPause, app)
                XCTAssertFalse(allPause.isEnabled)
                try fullText("library.request.allPause.reason", "停止を記録できる通信要求はありません。対象別の記録を確認してください。", app)
                try audit(app, context.value.variant + "-relaunch-same-fixed-history-no-redispatch")
                attach(app, context.value.variant + "-relaunch-identical-six-parents-ten-children")
                continue
            }
            let nextStage = try stage(phase)
            try requireHistory(history, stage: nextStage - 1, context: context.value)
            let local = phase.hasPrefix("local")
            let target = try context.value.target(local ? "local" : "waiting")
            if phase == "allPause" {
                let localTarget = try context.value.target("local")
                try openLocal(localTarget, app)
                try assertRequest(localTarget, intent: "running", app)
                try closeLocal(app)
                try rootReveal(element("library.request.identity." + target.requestToken, app), app)
                try assertRequest(target, intent: "running", app)
                try assertTerminalRows(context.value, app)
                let explanation = "保存済みの通信要求5件を、操作時に固定して全件停止の対象にします。開始待ち・条件待ちも含め、対象別に本人停止の記録と未処理理由を表示します。端末内の再生と写真への追加は独立した処理です。"
                let value = element("library.request.allPause.explanation", app)
                try rootReveal(value, app)
                try fullText("library.request.allPause.explanation", explanation, app)
                try audit(app, context.value.variant + "-fixed-five-before-all-pause")
                let control = button("library.request.allPause", app)
                try rootReveal(control, app)
                try assertControl(control, title: "開始指示済みの通信を全件停止", enabled: true, app)
                attach(app, context.value.variant + "-allPause-armed-prefix-four")
                control.tap()
                try wait("Fixed all-pause must commit its whole five-child plan", app) {
                    let feedback = self.element("library.request.feedback", app)
                    let allPause = self.button("library.request.allPause", app)
                    return feedback.exists && feedback.label == self.savedFeedback
                        && allPause.exists && !allPause.isEnabled
                }
                try fullText("library.request.feedback", savedFeedback, app)
                try audit(app, context.value.variant + "-allPause-result-two-recorded-three-unprocessed")
                try assertPausedRequestsAfterAllPause(context.value, app)
            } else {
                if local { try openLocal(target, app) }
                else { try rootReveal(element("library.request.identity." + target.requestToken, app), app) }
                let isResume = phase.hasSuffix("Resume")
                let isCancel = phase == "localCancel"
                try assertRequest(target, intent: isResume || isCancel ? "paused" : "running", app)
                try assertActions(target, pause: !isResume && !isCancel, cancel: true, resume: isResume || isCancel,
                    reason: nil, app)
                try audit(app, context.value.variant + "-" + phase + "-native-controls-before")
                let action = isResume ? "resumeIntent" : isCancel ? "cancel" : "pause"
                let control = button("library.request." + action + "." + target.requestToken, app)
                try reveal(control, app)
                try assertControl(control, title: actionTitle(action), enabled: true, app)
                attach(app, context.value.variant + "-" + phase + "-armed-prefix-\(nextStage - 1)")
                control.tap()
                let intent = isResume ? "running" : isCancel ? "cancelled" : "paused"
                try wait("The exact request must retain the new durable person intent", app) {
                    self.element("library.request.intent." + target.requestToken, app).label == self.intentText(intent)
                }
                try assertRequest(target, intent: intent, app)
                try assertActions(target, pause: isResume, cancel: !isCancel, resume: !isResume && !isCancel,
                    reason: isCancel ? "この通信要求は本人取消済みです。" : nil, app)
                try audit(app, context.value.variant + "-" + phase + "-intent-and-waits-after")
                if local { try closeLocal(app) }
                if isCancel {
                    try rootReveal(element("library.request.feedback", app), app)
                    try fullText("library.request.feedback", savedFeedback, app)
                    try audit(app, context.value.variant + "-localCancel-new-root-result-feedback")
                }
            }
            history = try scanRootHistory(app)
            try requireHistory(history, stage: nextStage, context: context.value)
            attach(app, context.value.variant + "-" + phase + "-consumed-prefix-\(nextStage)")
        }
    }

    @MainActor private var savedFeedback: String {
        "通信操作の対象別の受付結果を保存しました。本人意思・未処理理由と停止要求を確認してください。通信処理の終了は未確認です。"
    }
    @MainActor private func requestContext() throws -> (value: RequestControlUIExpected, phase: String, startPhase: String?, encoded: String) {
        let env = ProcessInfo.processInfo.environment, prefix = "FR_MEDIA_REQUEST_CONTROL_"
        let encoded = try XCTUnwrap(env[prefix + "EXPECTED"])
        guard encoded.utf8.count <= 32_768 else { throw RequestControlUIFailure.wrongEnvironment }
        let value = try JSONDecoder().decode(RequestControlUIExpected.self, from: Data(encoded.utf8))
        let phase = try XCTUnwrap(env[prefix + "PHASE"]), nonce = try XCTUnwrap(env[prefix + "NONCE"])
        let startPhase = env[prefix + "START_PHASE"]
        let variant = try XCTUnwrap(env[prefix + "VARIANT"])
        let requested = try XCTUnwrap(env[prefix + "SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let actual = try XCTUnwrap(env["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        guard env[prefix + "SEED"] != "1", env[prefix + "VERIFY"] != "1", actual == requested,
              UUID(uuidString: value.simulator) == actual, value.nonce == nonce, value.variant == variant,
              ((actual.uuidString == "DF5792DA-974B-484E-AABE-CEB35BE81671" && variant == "normal" && nonce == "2a348f92-1908-4f90-b8ee-022db9af9292")
                || (actual.uuidString == "DB784948-3DA5-454A-9526-29C37B22AB84" && variant == "max" && nonce == "6debb933-100f-4327-835f-5415010a47e7")),
              value.schema == "fr-s28-media-request-control-ui-v1", UUID(uuidString: value.storeUUID) != nil,
              value.manifest.bytes > 0, value.manifest.inode > 0, value.manifest.sha256.utf8.count == 64,
              requestControlUIPhases.dropFirst().contains(phase) || ["all", "relaunch", "tail"].contains(phase),
              value.targets.map(\.role) == ["local", "waiting", "cancelled", "completed", "ended"],
              Set(value.targets.map(\.operation)).count == 5,
              value.targets.allSatisfy({ target in
                  target.capture == "rc-" + String(nonce.prefix(8)) + "-" + target.role
                      && canonicalID(target.operation) && target.requestToken == Data(target.operation.utf8).base64EncodedString()
                      && (target.role == "local" ? target.rendition == nil && target.remoteToken == nil
                          : target.rendition.map(canonicalID) == true && target.remoteToken?.isEmpty == false)
              }) else { throw RequestControlUIFailure.wrongEnvironment }
        if phase == "tail" {
            guard let startPhase, requestControlUIPhases.dropFirst().contains(startPhase) || startPhase == "relaunch" else {
                throw RequestControlUIFailure.wrongEnvironment
            }
        } else if startPhase != nil { throw RequestControlUIFailure.wrongEnvironment }
        return (value, phase, startPhase, encoded)
    }
    @MainActor private func stage(_ phase: String) throws -> Int {
        try XCTUnwrap(requestControlUIPhases.firstIndex(of: phase))
    }
    @MainActor private func loaded(_ app: XCUIApplication) throws {
        let refresh = button("library.refresh", app)
        XCTAssertTrue(refresh.waitForExistence(timeout: 20))
        try wait("The ordinary library must finish loading without repair", app) {
            refresh.isEnabled && !self.element("library.loadFailure", app).exists
        }
        XCTAssertFalse(element("library.empty", app).exists)
        XCTAssertFalse(element("renditionPlayback.target", app).exists)
        XCTAssertFalse(element("renditionPlayback.player", app).exists)
    }
    @MainActor private func openLocal(_ target: RequestControlUIExpected.Target, _ app: XCUIApplication) throws {
        try top(app)
        let item = element("library.item." + target.capture, app)
        let title = element("library.itemTitle." + target.capture, app)
        try fullText("library.itemTitle." + target.capture, "動画 " + target.capture, app)
        try revealControl(title, app)
        XCTAssertGreaterThanOrEqual(item.frame.height, 44)
        guard title.isEnabled && title.isHittable else { throw RequestControlUIFailure.unreachable }
        title.tap()
        let identity = element("library.detailIdentity", app)
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertEqual(identity.label, "動画 " + target.capture)
    }
    @MainActor private func closeLocal(_ app: XCUIApplication) throws {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        guard back.exists && back.isHittable else { throw RequestControlUIFailure.unreachable }
        back.tap()
        try loaded(app)
    }
    @MainActor private func assertRequest(_ target: RequestControlUIExpected.Target, intent: String, _ app: XCUIApplication) throws {
        let media = target.rendition.map { "軽量版ID：" + $0 } ?? "原本"
        try fullText("library.request.identity." + target.requestToken, "対象：動画 " + target.capture + "・" + media, app)
        try fullText("library.request.intent." + target.requestToken, intentText(intent), app)
        try fullText("library.request.waits." + target.requestToken,
            target.role == "waiting" ? "待機条件：Wi-Fi条件、撮影中、認証" : "待機条件：記録なし（通信の開始・再開を保証しません）", app)
        try fullText("library.request.transport." + target.requestToken,
            "通信状態の記録：開始待ち。通信処理の終了・媒体の使用解放は別に確認が必要です。", app)
    }
    @MainActor private func assertActions(_ target: RequestControlUIExpected.Target, pause: Bool, cancel: Bool,
        resume: Bool, reason: String?, _ app: XCUIApplication) throws {
        for (action, enabled) in [("pause", pause), ("cancel", cancel), ("resumeIntent", resume)] {
            let control = button("library.request." + action + "." + target.requestToken, app)
            try reveal(control, app)
            try assertControl(control, title: actionTitle(action), enabled: enabled, app)
            if !enabled {
                let expected = reason ?? (action == "pause" ? "本人停止の記録があります。" : "停止した通信だけ停止を解除できます。")
                try fullText("library.request.reason." + action + "." + target.requestToken, expected, app)
            }
        }
    }
    @MainActor private func assertPausedRequestsAfterAllPause(_ expected: RequestControlUIExpected, _ app: XCUIApplication) throws {
        let target = try expected.target("waiting"), localTarget = try expected.target("local")
        try rootReveal(element("library.request.identity." + target.requestToken, app), app)
        try assertRequest(target, intent: "paused", app)
        try assertActions(target, pause: false, cancel: true, resume: true, reason: nil, app)
        try audit(app, expected.variant + "-allPause-paused-waiting-controls")
        try openLocal(localTarget, app)
        try assertRequest(localTarget, intent: "paused", app)
        try assertActions(localTarget, pause: false, cancel: true, resume: true, reason: nil, app)
        try audit(app, expected.variant + "-allPause-paused-local-controls")
        try closeLocal(app)
    }
    @MainActor private func assertTerminalRows(_ expected: RequestControlUIExpected, _ app: XCUIApplication) throws {
        for (role, reason) in [("cancelled", "この通信要求は本人取消済みです。"),
            ("completed", "この通信要求には完了の照合記録があります。"), ("ended", "この通信再生は終了済みです。")] {
            let target = try expected.target(role)
            try rootReveal(element("library.request.identity." + target.requestToken, app), app)
            try assertRequest(target, intent: role == "cancelled" ? "cancelled" : "running", app)
            try assertActions(target, pause: false, cancel: false, resume: false, reason: reason, app)
        }
    }
    @MainActor private func intentText(_ intent: String) -> String {
        switch intent {
        case "paused": "本人の意思：停止の記録あり"
        case "cancelled": "本人の意思：取消の記録あり"
        default: "本人の意思：継続の記録あり（通信の開始・実際の再開とは別です）"
        }
    }
    @MainActor private func actionTitle(_ action: String) -> String {
        switch action { case "pause": "この通信を停止"; case "cancel": "この通信を取り消す"; default: "停止を解除して待機" }
    }
    @MainActor private func assertControl(_ value: XCUIElement, title: String, enabled: Bool, _ app: XCUIApplication) throws {
        try revealControl(value, app)
        XCTAssertTrue(value.exists)
        XCTAssertEqual(value.label, title)
        XCTAssertEqual(value.isEnabled, enabled)
        let frame = value.frame, coordinateBound = value.frame.minY.ulp + value.frame.maxY.ulp
        XCTAssertTrue(frame.height.isFinite && coordinateBound.isFinite)
        XCTAssertGreaterThanOrEqual(coordinateBound, 0)
        XCTAssertLessThan(coordinateBound, 1e-8)
        XCTAssertGreaterThanOrEqual(frame.width, 44)
        XCTAssertGreaterThanOrEqual(frame.height + coordinateBound, 44)
        XCTAssertGreaterThanOrEqual(value.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(value.frame.maxX, app.frame.maxX + 1)
        if enabled { XCTAssertTrue(value.isHittable) }
        guard value.exists && value.isEnabled == enabled && (!enabled || value.isHittable) else { throw RequestControlUIFailure.unexpectedState }
    }
    @MainActor private func fullText(_ identifier: String, _ expected: String, _ app: XCUIApplication) throws {
        let value = element(identifier, app)
        try reveal(value, app)
        XCTAssertEqual(value.label, expected)
        XCTAssertGreaterThan(value.frame.height, 0)
        XCTAssertGreaterThanOrEqual(value.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(value.frame.maxX, app.frame.maxX + 1)
        let evidence = XCTAttachment(string: metadata(value) + "\nexpectedCompleteSourceText=" + expected)
        evidence.name = "media-request-control-native-full-text"; evidence.lifetime = .keepAlways; add(evidence)
    }

    /// Collect all native history IDs through ordinary scrolling. Every parent,
    /// fixed child and full decision must be present before a later tap is armed.
    @MainActor private func scanRootHistory(_ app: XCUIApplication) throws -> RequestControlHistory {
        try top(app)
        var history = RequestControlHistory(), previous = "", stable = 0
        var collected = Set<String>()
        for _ in 0..<220 {
            let values = app.descendants(matching: .any).matching(NSPredicate(format:
                "(identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier == %@) AND NOT (identifier IN %@)",
                "library.request.history", "library.request.pending", "library.request.lookup", Array(collected) as NSArray)).allElementsBoundByIndex
            for value in values {
                let identifier = value.identifier, label = value.label
                collected.insert(identifier)
                if identifier.hasPrefix("library.request.historyPlan.") { history.plans[identifier] = label }
                if identifier.hasPrefix("library.request.historyHeading.") { history.headings[identifier] = label }
                if identifier.hasPrefix("library.request.historyIdentity.") { history.identities[identifier] = label }
                if identifier.hasPrefix("library.request.historyDecision.") { history.decisions[identifier] = label }
                if identifier.hasPrefix("library.request.historyStop.") { history.stops[identifier] = label }
                if identifier.hasPrefix("library.request.pending") || identifier == "library.request.lookup" { history.pending.insert(identifier) }
            }
            // One native snapshot retains every label and frame. Only transient
            // 0x object addresses are normalized for the stable-bottom check.
            let signature = app.scrollViews.firstMatch.debugDescription.replacingOccurrences(
                of: "0x[0-9a-fA-F]+", with: "0x<address>", options: .regularExpression)
            stable = signature == previous ? stable + 1 : 0
            if stable >= 3 {
                let evidence = XCTAttachment(string: history.description)
                evidence.name = "media-request-control-complete-native-history"; evidence.lifetime = .keepAlways; add(evidence)
                let bottom = XCTAttachment(string: signature)
                bottom.name = "media-request-control-stable-bottom-native-tree"; bottom.lifetime = .keepAlways; add(bottom)
                return history
            }
            previous = signature
            app.swipeUp()
        }
        attach(app, "media-request-control-history-did-not-reach-stable-bottom")
        throw RequestControlUIFailure.unreachable
    }
    @MainActor private func requireHistory(_ history: RequestControlHistory, stage: Int,
        context: RequestControlUIExpected, afterRelaunch: Bool = false) throws {
        let childCount = stage <= 4 ? stage : stage + 4
        XCTAssertTrue(history.pending.isEmpty)
        XCTAssertEqual(history.plans.count, stage)
        XCTAssertEqual(history.headings.count, stage)
        XCTAssertEqual(history.identities.count, childCount)
        XCTAssertEqual(history.decisions.count, childCount)
        let unprocessed = stage >= 5 ? 3 : 0
        XCTAssertEqual(history.stops.count, childCount - unprocessed)
        guard history.pending.isEmpty && history.plans.count == stage && history.headings.count == stage
            && history.identities.count == childCount && history.decisions.count == childCount
            && history.stops.count == childCount - unprocessed else { throw RequestControlUIFailure.alreadyConsumedOrWrongPrefix }
        var planLabels = [String: Int]()
        for (identifier, label) in history.plans {
            let parent = String(identifier.dropFirst("library.request.historyPlan.".count))
            XCTAssertTrue(canonicalID(parent))
            XCTAssertEqual(history.headings["library.request.historyHeading." + parent],
                label == "停止の指示・固定対象5件" ? "全件停止の保存記録" : "単数の通信操作の保存記録")
            planLabels[label, default: 0] += 1
        }
        var expectedLabels = [String: Int]()
        if stage >= 1 { expectedLabels["停止の指示・固定対象1件"] = 1 }
        if stage >= 2 { expectedLabels["停止解除・待機の指示・固定対象1件"] = 1 }
        if stage >= 3 { expectedLabels["停止の指示・固定対象1件"] = 2 }
        if stage >= 4 { expectedLabels["停止解除・待機の指示・固定対象1件"] = 2 }
        if stage >= 5 { expectedLabels["停止の指示・固定対象5件"] = 1 }
        if stage >= 6 { expectedLabels["取消の指示・固定対象1件"] = 1 }
        XCTAssertEqual(planLabels, expectedLabels)
        var observedRoles = [String: Int](), childIDs = Set<String>()
        for (identifier, label) in history.identities {
            let suffix = String(identifier.dropFirst("library.request.historyIdentity.".count))
            guard suffix.utf8.count > 37 else { throw RequestControlUIFailure.unexpectedState }
            let child = String(suffix.prefix(36)), token = String(suffix.dropFirst(37))
            guard canonicalID(child), childIDs.insert(child).inserted,
                  let target = context.targets.first(where: { $0.requestToken == token }) else { throw RequestControlUIFailure.unexpectedState }
            let media = target.rendition.map { "軽量版ID：" + $0 } ?? "原本"
            XCTAssertEqual(label, "対象：動画 " + target.capture + "・" + media)
            XCTAssertNotNil(history.decisions["library.request.historyDecision." + child])
            observedRoles[target.role, default: 0] += 1
        }
        var expectedRoles = [String: Int]()
        if stage > 0 { expectedRoles["local"] = min(stage, 2) + (stage >= 5 ? 1 : 0) + (stage >= 6 ? 1 : 0) }
        if stage >= 3 { expectedRoles["waiting"] = min(stage - 2, 2) + (stage >= 5 ? 1 : 0) }
        if stage >= 5 { for role in ["cancelled", "completed", "ended"] { expectedRoles[role] = 1 } }
        XCTAssertEqual(observedRoles, expectedRoles)
        var expectedDecisions = [String: Int]()
        let pauses = (stage >= 1 ? 1 : 0) + (stage >= 3 ? 1 : 0) + (stage >= 5 ? 2 : 0)
        let resumes = (stage >= 2 ? 1 : 0) + (stage >= 4 ? 1 : 0)
        if pauses > 0 { expectedDecisions["停止指示を保存しました。通信処理の終了・媒体の使用解放は未確認です。"] = pauses }
        if resumes > 0 { expectedDecisions["停止解除の意思を保存しました。通信の開始・実際の再開は行っていません。"] = resumes }
        if stage >= 5 {
            expectedDecisions["未処理：通信要求は本人取消済みです。"] = 1
            expectedDecisions["未処理：通信要求は完了済みです。"] = 1
            expectedDecisions["未処理：通信再生は終了済みです。"] = 1
        }
        if stage >= 6 { expectedDecisions["取消指示を保存しました。Mac側の結果と通信処理の終了・媒体の使用解放は未確認です。"] = 1 }
        XCTAssertEqual(Dictionary(grouping: Array(history.decisions.values), by: { $0 }).mapValues(\.count), expectedDecisions)
        let resumeStop = "この指示は停止解除の意思の記録です。通信の開始・実際の再開は行っていません。"
        let noNewStop = "停止要求：保存した指示を表示しています。自動で要求を繰り返しません。通信処理の終了・媒体の使用解放は未確認です。"
        let noTask = "停止要求：今回の対象では不要でした。通信処理の終了・媒体の使用解放は別に確認が必要です。"
        XCTAssertEqual(history.stops.values.filter { $0 == resumeStop }.count, resumes)
        XCTAssertTrue(history.stops.values.allSatisfy { $0 == resumeStop || $0 == noNewStop || (!afterRelaunch && $0 == noTask) })
        guard planLabels == expectedLabels && observedRoles == expectedRoles else { throw RequestControlUIFailure.alreadyConsumedOrWrongPrefix }
    }

    @MainActor private func rootReveal(_ value: XCUIElement, _ app: XCUIApplication) throws {
        try top(app)
        try reveal(value, app)
    }
    @MainActor private func top(_ app: XCUIApplication) throws {
        let camera = button("product.capture", app)
        for _ in 0..<180 {
            if camera.exists && camera.isHittable && camera.frame.midY > app.navigationBars.firstMatch.frame.maxY + 2 { return }
            app.swipeDown()
        }
        throw RequestControlUIFailure.unreachable
    }
    @MainActor private func reveal(_ value: XCUIElement, _ app: XCUIApplication) throws {
        for _ in 0..<180 {
            if value.exists {
                let upper = app.navigationBars.firstMatch.frame.maxY + 2
                let viewport = CGRect(x: app.frame.minX, y: upper, width: app.frame.width, height: max(0, app.frame.maxY - upper - 8))
                let visible = value.frame.intersection(viewport)
                if !visible.isNull && visible.height >= min(44, value.frame.height) { return }
                if value.frame.maxY <= upper { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        attach(app, "media-request-control-unreachable-" + value.identifier)
        throw RequestControlUIFailure.unreachable
    }
    @MainActor private func revealControl(_ value: XCUIElement, _ app: XCUIApplication) throws {
        for _ in 0..<180 {
            let upper = app.navigationBars.firstMatch.frame.maxY + 2, lower = app.frame.maxY - 8
            if value.exists {
                let frame = value.frame
                if frame.minY >= upper - 2 && frame.maxY <= lower + 2 { return }
                let delta = frame.minY < upper ? frame.minY - upper - 4 : frame.maxY - lower + 4
                let height = max(1, lower - upper)
                let distance = min(max(abs(delta), 32), height * 0.4)
                let startY = upper + height * (delta > 0 ? 0.8 : 0.2)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let x = min(8, app.frame.width * 0.1)
                let start = origin.withOffset(CGVector(dx: x, dy: startY - app.frame.minY))
                let end = origin.withOffset(CGVector(dx: x, dy: startY - app.frame.minY + (delta > 0 ? -distance : distance)))
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            } else { app.swipeUp() }
        }
        attach(app, "media-request-control-unreachable-native-control")
        throw RequestControlUIFailure.unreachable
    }
    @MainActor private func wait(_ message: String, _ app: XCUIApplication, predicate: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: 20) == .completed else {
            attach(app, "media-request-control-wait-failure"); XCTFail(message); throw RequestControlUIFailure.unexpectedState
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
            let evidence = XCTAttachment(string: lines.joined(separator: "\n"))
            evidence.name = name + "-unhandled-accessibility-issue"; evidence.lifetime = .keepAlways; self.add(evidence)
            return false
        }
    }
    @MainActor private func metadata(_ value: XCUIElement) -> String {
        "identifier=\(value.identifier) type=\(value.elementType.rawValue) frame=\(value.frame) enabled=\(value.isEnabled) label=\(value.label)"
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = name; screen.lifetime = .keepAlways; add(screen)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    nonisolated private func canonicalID(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value && value.utf8.count == 36 }
}

private let requestControlUIPhases = ["seed", "localPause", "localResume", "remotePause", "remoteResume", "allPause", "localCancel"]
private enum RequestControlUIFailure: Error { case wrongEnvironment, unreachable, unexpectedState, alreadyConsumedOrWrongPrefix }
private struct RequestControlUIExpected: Decodable {
    struct Target: Decodable {
        let role: String
        let capture: String
        let operation: String
        let requestToken: String
        let rendition: String?
        let remoteToken: String?
        let startRevision: UInt64
    }
    struct Manifest: Decodable { let sha256: String; let bytes: UInt64; let device: Int64; let inode: UInt64 }
    let schema: String
    let nonce: String
    let simulator: String
    let variant: String
    let storeUUID: String
    let manifest: Manifest
    let targets: [Target]
    func target(_ role: String) throws -> Target { try XCTUnwrap(targets.first { $0.role == role }) }
}
private struct RequestControlHistory {
    var plans: [String: String] = [:]
    var headings: [String: String] = [:]
    var identities: [String: String] = [:]
    var decisions: [String: String] = [:]
    var stops: [String: String] = [:]
    var pending = Set<String>()
    var description: String {
        ["plans": plans, "headings": headings, "identities": identities, "decisions": decisions, "stops": stops]
            .sorted { $0.key < $1.key }.map { key, values in
                key + "\n" + values.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: "\n")
            }.joined(separator: "\n") + "\npending=" + pending.sorted().joined(separator: ",")
    }
}
