import UIKit
import XCTest

/// Only the runner receives expectations. The ordinary App receives no launch
/// arguments/environment/mocks and reads its own current-UUID Keychain bundle.
/// One running/unknown-session tap is allowed, only at the untouched prefix.
final class UploadMetadataFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testClosedHTTPSUnknownExactLookupPersonPauseCancelAndRelaunch() throws {
        guard ProcessInfo.processInfo.environment["FR_UPLOAD_METADATA_UI"] == "1" else {
            throw XCTSkip("The new one-time upload metadata fixture is not enabled")
        }
        let context = try metadataContext(), expected = context.value, app = XCUIApplication()
        try ordinaryLaunch(app)
        let reference = XCTAttachment(string: context.encoded + "\nphase=" + context.phase
            + "\nstartPhase=" + (context.start ?? "<none>") + "\nexpectedStage=" + (context.expectedStage ?? "<none>")
            + "\nrunnerContentSizeCategory=" + UIApplication.shared.preferredContentSizeCategory.rawValue
            + "\nSynthetic current registration; native closed HTTPS refusal only. The main runner holds the bound, non-listening port and owns font settings. Native SDK global counts are not measured here.")
        reference.name = "upload-metadata-independent-expectations"; reference.lifetime = .keepAlways; add(reference)
        app.launch(); try loaded(app)
        let phases: [String]
        if context.phase == "all" { phases = ["requestUnknown", "paused", "cancelled", "relaunch"] }
        else if context.phase == "tail" {
            let sequence = ["requestUnknown", "paused", "cancelled", "relaunch"]
            let first = try XCTUnwrap(sequence.firstIndex(of: try XCTUnwrap(context.start)))
            phases = Array(sequence[first...])
        } else { phases = [context.phase] }
        let first = try XCTUnwrap(phases.first)
        var currentStage = first == "readonly" || first == "relaunch"
            ? try stage(context.expectedStage ?? "cancelled") : try stage(first) - 1
        var history = try scanRoot(app)
        try requireHistory(history, stage: currentStage, expected: expected)
        try assertLibrary(expected, app)
        try inspectHistory(history, expected, app)
        for phase in phases {
            if phase == "readonly" || phase == "relaunch" {
                let before = history.durable
                if phase == "relaunch" {
                    app.terminate(); try ordinaryLaunch(app); app.launch(); try loaded(app)
                }
                try openDetail(expected, app)
                try assertRequest(expected, stage: currentStage, app)
                if currentStage > 0 { try lookupSameQuery(expected, app) }
                try audit(app, expected.variant + "-" + phase + "-same-pending-query-person-intent")
                try closeDetail(app)
                history = try scanRoot(app)
                try requireHistory(history, stage: currentStage, expected: expected)
                XCTAssertEqual(history.durable, before)
                try inspectHistory(history, expected, app)
                try audit(app, expected.variant + "-" + phase + "-immutable-acceptance-and-person-history")
                continue
            }
            let next = try stage(phase)
            guard currentStage == next - 1 else { throw MetadataUIFailure.consumedPrefix }
            try requireHistory(history, stage: currentStage, expected: expected)
            try openDetail(expected, app)
            try assertRequest(expected, stage: currentStage, app)
            try audit(app, expected.variant + "-" + phase + "-before-single-native-tap")
            if phase == "requestUnknown" {
                // This is the sole eligible running/unknown-session refresh.
                // If interrupted, main uses VERIFY/observe, never a second tap.
                try tapControl(metadataID("action", expected), title: metadataTitle, app, location: .detail)
                try reacquireRequest(expected, app)
                try awaitFeedback(unknownFeedback, expected, app)
                try fullText(metadataID("status", expected), pendingStatus, app, location: .detail)
                try audit(app, expected.variant + "-closed-https-result-unknown-no-saved-proof")
                try lookupSameQuery(expected, app)
            } else {
                let action = phase == "paused" ? "pause" : "cancel"
                let title = phase == "paused" ? "この通信を停止" : "この通信を取り消す"
                try tapControl("library.request." + action + "." + expected.requestToken, title: title, app, location: .detail)
                // A LazyVStack may cull the tapped row. Requery by the fixed
                // request identity before reading the new intent or feedback.
                try reacquireRequest(expected, app)
                try wait("The exact existing request must retain its new person intent", app) {
                    let value = self.element("library.request.intent." + expected.requestToken, app)
                    return value.exists && value.label == self.intentText(next)
                }
                try assertRequest(expected, stage: next, app)
                try audit(app, expected.variant + "-" + phase + "-durable-person-intent")
                // The current UI keeps this control available for old query
                // recovery. With no session, paused/cancelled creates must
                // refuse; this safe rejection must not create query number 2.
                try tapControl(metadataID("action", expected), title: metadataTitle, app, location: .detail)
                try reacquireRequest(expected, app)
                try awaitFeedback(refusedFeedback, expected, app)
                try fullText(metadataID("status", expected), pendingStatus, app, location: .detail)
                try audit(app, expected.variant + "-" + phase + "-new-preparation-refused")
                try lookupSameQuery(expected, app)
            }
            try closeDetail(app)
            currentStage = next; history = try scanRoot(app)
            try requireHistory(history, stage: currentStage, expected: expected)
            try assertLibrary(expected, app)
            try inspectHistory(history, expected, app)
            try audit(app, expected.variant + "-consumed-" + phase + "-fixed-history")
        }
    }

    @MainActor private var metadataTitle: String { "Macの転送準備・状態照合" }
    @MainActor private var explanation: String {
        "この操作はMacの転送準備と状態の照会だけを行います。原本は送信しません。本人停止・取消中に新しい準備は作らず、既知の受付だけを照会します。結果不明の記録は先に照合します。"
    }
    @MainActor private var pendingStatus: String { "Macへの照会を予約しました。応答の記録は未確定です。この照会では原本を送信しません。" }
    @MainActor private var seedStatus: String { "Macへの転送準備・状態照合は未実行です。転送要求の受付だけではMacへの保存は確認できません。" }
    @MainActor private var unknownFeedback: String {
        "Macへの照会または結果の保存は未確定です。同じ記録を照合してください。再びアプリを開いても新しい転送準備を自動で作りません。"
    }
    @MainActor private var refusedFeedback: String { "現在の本人意思やMacの受付記録では、新しい転送準備を実行できません。原本は保持しています。" }
    @MainActor private var waitsText: String { "待機条件：記録なし（通信の開始・再開を保証しません）" }
    @MainActor private var transportText: String { "通信状態の記録：開始待ち。通信処理の終了・媒体の使用解放は別に確認が必要です。" }
    @MainActor private func intentText(_ stage: Int) -> String {
        stage < 2 ? "本人の意思：継続の記録あり（通信の開始・実際の再開とは別です）"
            : stage == 2 ? "本人の意思：停止の記録あり" : "本人の意思：取消の記録あり"
    }
    @MainActor private func metadataID(_ component: String, _ expected: MetadataUIExpected) -> String {
        "library.uploadMetadata." + component + "." + expected.requestToken
    }
    @MainActor private func metadataContext() throws -> MetadataUIContext {
        let prefix = "FR_UPLOAD_METADATA_", env = ProcessInfo.processInfo.environment
        let encoded = try XCTUnwrap(env[prefix + "EXPECTED"])
        guard encoded.utf8.count <= 16_384 else { throw MetadataUIFailure.environment }
        let value = try JSONDecoder().decode(MetadataUIExpected.self, from: Data(encoded.utf8))
        let phase = try XCTUnwrap(env[prefix + "PHASE"]), nonce = try XCTUnwrap(env[prefix + "NONCE"])
        let variant = try XCTUnwrap(env[prefix + "VARIANT"]), requested = try XCTUnwrap(env[prefix + "SIMULATOR_UDID"])
        let actual = try XCTUnwrap(env["SIMULATOR_UDID"]), start = env[prefix + "START_PHASE"], expectedStage = env[prefix + "EXPECTED_STAGE"]
        guard env[prefix + "SEED"] != "1", env[prefix + "VERIFY"] != "1", actual == requested, value.simulator == actual,
              value.nonce == nonce, value.variant == variant,
              ((actual == "7AD9895F-23EB-4FB2-B2A0-A92F4D7E431F" && variant == "normal" && nonce == "6c947a54-5a1a-438b-8080-96db9ef62f80")
                || (actual == "52CDA9DC-D57C-4DA7-89BB-33F15C5B9169" && variant == "max" && nonce == "76416ee5-f016-4720-9f78-46f697a2719c")),
              value.schema == "fr-upload-metadata-ui-v1", UUID(uuidString: value.storeUUID) != nil,
              value.capture == "um-" + String(nonce.prefix(8)) + "-saved", canonicalID(value.operation), canonicalID(value.acceptanceParent),
              value.operation != value.acceptanceParent, value.requestToken == Data(value.operation.utf8).base64EncodedString(),
              value.manifest.bytes > 0, value.manifest.inode > 0, digest(value.manifest.sha256), digest(value.credentialBundleSHA256),
              value.origin == "https://127.0.0.1:51875", value.portKeeperID == "12667470-2db3-4f9d-bc26-b3b919e691ae",
              value.portKeeperPID == 37193, ["all", "tail", "readonly", "relaunch", "requestUnknown", "paused", "cancelled"].contains(phase) else {
            throw MetadataUIFailure.environment
        }
        if phase == "tail" {
            guard let start, ["requestUnknown", "paused", "cancelled", "relaunch"].contains(start), expectedStage == nil else { throw MetadataUIFailure.environment }
        } else if phase == "readonly" {
            guard let expectedStage, ["seed", "requestUnknown", "paused", "cancelled"].contains(expectedStage), start == nil else { throw MetadataUIFailure.environment }
        } else if phase == "relaunch" {
            guard start == nil, expectedStage == nil || ["seed", "requestUnknown", "paused", "cancelled"].contains(expectedStage!) else { throw MetadataUIFailure.environment }
        } else if start != nil || expectedStage != nil { throw MetadataUIFailure.environment }
        return .init(value: value, phase: phase, start: start, expectedStage: expectedStage, encoded: encoded)
    }
    @MainActor private func ordinaryLaunch(_ app: XCUIApplication) throws {
        XCTAssertTrue(app.launchArguments.isEmpty && app.launchEnvironment.isEmpty)
        guard app.launchArguments.isEmpty && app.launchEnvironment.isEmpty else { throw MetadataUIFailure.environment }
    }
    @MainActor private func stage(_ phase: String) throws -> Int { try XCTUnwrap(["seed", "requestUnknown", "paused", "cancelled"].firstIndex(of: phase)) }
    @MainActor private func loaded(_ app: XCUIApplication) throws {
        XCTAssertTrue(button("library.refresh", app).waitForExistence(timeout: 20))
        try wait("The ordinary library must load its preserved fixture", app) {
            let refresh = self.button("library.refresh", app)
            return refresh.exists && refresh.isEnabled && !self.element("library.loadFailure", app).exists && !self.element("library.empty", app).exists
        }
        XCTAssertFalse(element("originalPlayback.player", app).exists); XCTAssertFalse(element("renditionPlayback.player", app).exists)
    }
    @MainActor private func assertLibrary(_ expected: MetadataUIExpected, _ app: XCUIApplication) throws {
        try fullText("library.itemTitle." + expected.capture, "動画 " + expected.capture, app)
        try fullText("library.itemSave." + expected.capture, "正常保存", app)
        try fullText("library.itemCapturedAt." + expected.capture, "撮影日時不明", app)
        try fullText("library.itemOriginal." + expected.capture, "原本あり", app)
        try fullText("library.request.summary." + expected.capture, "通信要求は1件です。対象別の記録と本人操作は動画の詳細で確認できます。", app)
    }
    @MainActor private func openDetail(_ expected: MetadataUIExpected, _ app: XCUIApplication) throws {
        let identifier = "library.itemTitle." + expected.capture
        try fullText(identifier, "動画 " + expected.capture, app)
        try revealControl(identifier, app, buttonOnly: false)
        let title = element(identifier, app), row = element("library.item." + expected.capture, app)
        guard title.exists && row.exists && title.isEnabled && title.isHittable else { throw MetadataUIFailure.unreachable }
        XCTAssertGreaterThanOrEqual(row.frame.height, 44); title.tap()
        XCTAssertTrue(element("library.detailIdentity", app).waitForExistence(timeout: 10))
        try fullText("library.detailIdentity", "動画 " + expected.capture, app, location: .detail)
    }
    @MainActor private func closeDetail(_ app: XCUIApplication) throws {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        guard back.exists && back.isHittable else { throw MetadataUIFailure.unreachable }
        back.tap(); try loaded(app)
    }
    @MainActor private func reacquireRequest(_ expected: MetadataUIExpected, _ app: XCUIApplication) throws {
        try reveal("library.request.identity." + expected.requestToken, app, location: .detail)
        let identity = element("library.request.identity." + expected.requestToken, app)
        guard identity.exists else { throw MetadataUIFailure.unreachable }
        XCTAssertEqual(identity.label, "対象：動画 " + expected.capture + "・原本")
    }
    @MainActor private func assertRequest(_ expected: MetadataUIExpected, stage: Int, _ app: XCUIApplication) throws {
        try reacquireRequest(expected, app)
        try fullText("library.request.intent." + expected.requestToken, intentText(stage), app, location: .detail)
        try fullText("library.request.waits." + expected.requestToken, waitsText, app, location: .detail)
        try fullText("library.request.transport." + expected.requestToken, transportText, app, location: .detail)
        try fullText(metadataID("status", expected), stage == 0 ? seedStatus : pendingStatus, app, location: .detail)
        try fullText(metadataID("explanation", expected), explanation, app, location: .detail)
        try assertControl(metadataID("action", expected), title: metadataTitle, enabled: true, app, location: .detail)
        if stage > 0 {
            try assertControl(metadataID("lookup", expected), title: "同じ照会の保存記録を照合", enabled: true, app, location: .detail)
        }
        try assertControl("library.request.pause." + expected.requestToken, title: "この通信を停止", enabled: stage < 2, app, location: .detail)
        try assertControl("library.request.cancel." + expected.requestToken, title: "この通信を取り消す", enabled: stage < 3, app, location: .detail)
    }
    @MainActor private func awaitFeedback(_ expectedText: String, _ expected: MetadataUIExpected, _ app: XCUIApplication) throws {
        let identifier = metadataID("feedback", expected)
        try reveal(identifier, app, location: .detail)
        try wait("The metadata operation must retain its exact bounded result", app) {
            let value = self.element(identifier, app)
            return value.exists && value.label == expectedText
        }
        try fullText(identifier, expectedText, app, location: .detail)
    }
    @MainActor private func lookupSameQuery(_ expected: MetadataUIExpected, _ app: XCUIApplication) throws {
        try tapControl(metadataID("lookup", expected), title: "同じ照会の保存記録を照合", app, location: .detail)
        try reacquireRequest(expected, app)
        try awaitFeedback(unknownFeedback, expected, app)
        try fullText(metadataID("status", expected), pendingStatus, app, location: .detail)
        try audit(app, expected.variant + "-explicit-local-query-lookup-no-new-preparation")
    }
    @MainActor private func scanRoot(_ app: XCUIApplication) throws -> MetadataUIHistory {
        try seekTop(app, location: .root)
        var history = MetadataUIHistory(), seen = Set<String>(), previous = "", stable = 0
        for _ in 0..<220 {
            let query = NSPredicate(format: "(identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier == %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@) AND NOT (identifier IN %@)",
                "library.transfer.", "library.request.history", "library.request.pending", "library.request.lookup",
                "library.submission.", "library.result.", Array(seen) as NSArray)
            for value in app.descendants(matching: .any).matching(query).allElementsBoundByIndex {
                guard value.exists else { continue }
                let identifier = value.identifier, label = value.label
                seen.insert(identifier)
                if identifier.hasPrefix("library.request.historyStop.") { history.stops[identifier] = label }
                else if identifier.hasPrefix("library.request.history") || identifier.hasPrefix("library.transfer.header.")
                    || identifier.hasPrefix("library.transfer.explanation.") || identifier.hasPrefix("library.transfer.child.")
                    || identifier.hasPrefix("library.transfer.record.lookup.") { history.durable[identifier] = label }
                if identifier.hasPrefix("library.request.pending") || identifier == "library.request.lookup"
                    || identifier.hasPrefix("library.transfer.pending") || identifier == "library.transfer.lookup"
                    || identifier.hasPrefix("library.submission.") || identifier.hasPrefix("library.result.") { history.unresolved.insert(identifier) }
            }
            let signature = app.scrollViews.firstMatch.debugDescription.replacingOccurrences(of: "0x[0-9a-fA-F]+", with: "0x<address>", options: .regularExpression)
            stable = signature == previous ? stable + 1 : 0
            if stable >= 3 {
                let evidence = XCTAttachment(string: history.description + "\n" + signature)
                evidence.name = "upload-metadata-complete-fixed-history"; evidence.lifetime = .keepAlways; add(evidence)
                return history
            }
            previous = signature; app.swipeUp()
        }
        attach(app, "upload-metadata-history-no-stable-bottom"); throw MetadataUIFailure.unreachable
    }
    @MainActor private func requireHistory(_ history: MetadataUIHistory, stage: Int, expected: MetadataUIExpected) throws {
        let persons = max(0, stage - 1), parent = expected.acceptanceParent, child = expected.operation
        var fixed: [String: String] = [
            "library.transfer.header." + parent: "原本の転送要求・1本",
            "library.transfer.explanation." + parent: "受付時に固定した1本すべての結果です。未処理の対象もこの要求に残します。受付はMacへの保存や通信の成功を示しません。",
            "library.transfer.record.lookup." + parent: "この転送要求の保存記録を照合",
            "library.transfer.child.title." + child: "動画 " + expected.capture,
            "library.transfer.child.decision." + child: "受付時の記録：転送要求を受け付けました。受付時には通信を開始していません。",
            "library.transfer.child.intent." + child: intentText(stage),
            "library.transfer.child.waits." + child: waitsText,
            "library.transfer.child.transport." + child: transportText]
        let plans = history.durable.filter { $0.key.hasPrefix("library.request.historyPlan.") }
        let identities = history.durable.filter { $0.key.hasPrefix("library.request.historyIdentity.") }
        let decisions = history.durable.filter { $0.key.hasPrefix("library.request.historyDecision.") }
        XCTAssertEqual(plans.count, persons); XCTAssertEqual(identities.count, persons); XCTAssertEqual(decisions.count, persons)
        guard history.unresolved.isEmpty && plans.count == persons && identities.count == persons
            && decisions.count == persons && history.stops.count == persons else { throw MetadataUIFailure.consumedPrefix }
        var planLabels: [String: Int] = [:], decisionLabels: [String: Int] = [:], commands = Set<String>()
        for (identifier, label) in plans {
            let id = String(identifier.dropFirst("library.request.historyPlan.".count))
            guard canonicalID(id), id != parent && id != child else { throw MetadataUIFailure.unexpected }
            fixed[identifier] = label; fixed["library.request.historyHeading." + id] = "単数の通信操作の保存記録"
            planLabels[label, default: 0] += 1
        }
        for (identifier, _) in identities {
            let suffix = String(identifier.dropFirst("library.request.historyIdentity.".count))
            guard suffix.count > 37 else { throw MetadataUIFailure.unexpected }
            let command = String(suffix.prefix(36)), token = String(suffix.dropFirst(37))
            guard canonicalID(command), commands.insert(command).inserted, token == expected.requestToken,
                  command != parent && command != child else { throw MetadataUIFailure.unexpected }
            fixed[identifier] = "対象：動画 " + expected.capture + "・原本"
            let decisionID = "library.request.historyDecision." + command
            let decision = try XCTUnwrap(decisions[decisionID]); fixed[decisionID] = decision; decisionLabels[decision, default: 0] += 1
            let stop = try XCTUnwrap(history.stops["library.request.historyStop." + command])
            XCTAssertTrue(["停止要求：今回の対象では不要でした。通信処理の終了・媒体の使用解放は別に確認が必要です。",
                "停止要求：保存した指示を表示しています。自動で要求を繰り返しません。通信処理の終了・媒体の使用解放は未確認です。"].contains(stop))
        }
        var expectedPlans: [String: Int] = [:], expectedDecisions: [String: Int] = [:]
        if persons > 0 {
            expectedPlans["停止の指示・固定対象1件"] = 1
            expectedDecisions["停止指示を保存しました。通信処理の終了・媒体の使用解放は未確認です。"] = 1
        }
        if persons > 1 {
            expectedPlans["取消の指示・固定対象1件"] = 1
            expectedDecisions["取消指示を保存しました。Mac側の結果と通信処理の終了・媒体の使用解放は未確認です。"] = 1
        }
        XCTAssertEqual(planLabels, expectedPlans); XCTAssertEqual(decisionLabels, expectedDecisions); XCTAssertEqual(history.durable, fixed)
        guard planLabels == expectedPlans && decisionLabels == expectedDecisions && history.durable == fixed else { throw MetadataUIFailure.consumedPrefix }
    }

    @MainActor private func inspectHistory(_ history: MetadataUIHistory, _ expected: MetadataUIExpected, _ app: XCUIApplication) throws {
        for (identifier, label) in history.durable.sorted(by: { $0.key < $1.key }) {
            if identifier.hasPrefix("library.transfer.record.lookup.") {
                try assertControl(identifier, title: label, enabled: true, app)
            } else { try fullText(identifier, label, app) }
            if identifier.hasPrefix("library.request.historyDecision.") || identifier.hasPrefix("library.transfer.child.decision.") {
                try audit(app, expected.variant + "-persisted-full-decision-" + identifier)
            }
        }
        for (identifier, label) in history.stops.sorted(by: { $0.key < $1.key }) { try fullText(identifier, label, app) }
    }

    // Native geometry, root-origin bidirectional reveal and seven unhandled
    // accessibility audit types retain the existing strict helper contract.
    @MainActor private func seekTop(_ app: XCUIApplication, location: MetadataUILocation) throws {
        let identifier = location == .root ? "product.capture" : "library.detailIdentity"
        for _ in 0..<180 {
            let anchor = element(identifier, app)
            if anchor.exists && anchor.isHittable && anchor.frame.minY >= app.navigationBars.firstMatch.frame.maxY - 2 { return }
            app.swipeDown(velocity: .fast)
        }
        attach(app, "upload-metadata-top-unreachable-" + identifier); throw MetadataUIFailure.unreachable
    }
    @MainActor private func reveal(_ identifier: String, _ app: XCUIApplication, location: MetadataUILocation = .root) throws {
        let current = element(identifier, app)
        if current.exists {
            let upper = app.navigationBars.firstMatch.frame.maxY + 2
            let viewport = CGRect(x: app.frame.minX, y: upper, width: app.frame.width,
                height: max(0, app.frame.maxY - upper - 8))
            let visible = current.frame.intersection(viewport)
            if !visible.isNull && visible.height >= min(44, current.frame.height) { return }
        }
        try seekTop(app, location: location)
        // Both directions start from a known root/detail anchor. A failed query
        // never reads XCUIElement.identifier to derive another query or error.
        for upward in [true, false] {
            for _ in 0..<200 {
                let value = element(identifier, app)
                if value.exists {
                    let upper = app.navigationBars.firstMatch.frame.maxY + 2
                    let viewport = CGRect(x: app.frame.minX, y: upper, width: app.frame.width,
                        height: max(0, app.frame.maxY - upper - 8))
                    let visible = value.frame.intersection(viewport)
                    if !visible.isNull && visible.height >= min(44, value.frame.height) { return }
                }
                if upward { app.swipeUp() } else { app.swipeDown() }
            }
        }
        attach(app, "upload-metadata-unreachable-" + identifier); throw MetadataUIFailure.unreachable
    }
    @MainActor private func revealControl(_ identifier: String, _ app: XCUIApplication, location: MetadataUILocation = .root,
        buttonOnly: Bool = true) throws {
        try reveal(identifier, app, location: location)
        for _ in 0..<160 {
            let value = buttonOnly ? button(identifier, app) : element(identifier, app)
            guard value.exists else { try reveal(identifier, app, location: location); continue }
            let upper = app.navigationBars.firstMatch.frame.maxY + 2, lower = app.frame.maxY - 8, frame = value.frame
            if frame.minY >= upper - 2 && frame.maxY <= lower + 2 { return }
            let delta = frame.minY < upper ? frame.minY - upper - 4 : frame.maxY - lower + 4
            let height = max(1, lower - upper), distance = min(max(abs(delta), 32), height * 0.4)
            let y = upper + height * (delta > 0 ? 0.8 : 0.2), origin = app.coordinate(withNormalizedOffset: .zero)
            let x = min(8, app.frame.width * 0.1)
            origin.withOffset(CGVector(dx: x, dy: y - app.frame.minY)).press(forDuration: 0.1,
                thenDragTo: origin.withOffset(CGVector(dx: x, dy: y - app.frame.minY + (delta > 0 ? -distance : distance))),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        attach(app, "upload-metadata-control-unreachable-" + identifier); throw MetadataUIFailure.unreachable
    }
    @MainActor private func assertControl(_ identifier: String, title: String, enabled: Bool, _ app: XCUIApplication,
        location: MetadataUILocation = .root) throws {
        try revealControl(identifier, app, location: location)
        let value = button(identifier, app)
        guard value.exists else { throw MetadataUIFailure.unreachable }
        XCTAssertEqual(value.label, title); XCTAssertEqual(value.isEnabled, enabled)
        let frame = value.frame, bound = frame.minY.ulp + frame.maxY.ulp
        XCTAssertTrue(frame.height.isFinite && bound.isFinite); XCTAssertGreaterThanOrEqual(bound, 0); XCTAssertLessThan(bound, 1e-8)
        XCTAssertGreaterThanOrEqual(frame.width, 44); XCTAssertGreaterThanOrEqual(frame.height + bound, 44)
        XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX - 1); XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX + 1)
        if enabled { XCTAssertTrue(value.isHittable) }
        guard value.label == title && value.isEnabled == enabled && (!enabled || value.isHittable) else { throw MetadataUIFailure.unexpected }
    }
    @MainActor private func tapControl(_ identifier: String, title: String, _ app: XCUIApplication,
        location: MetadataUILocation = .root) throws {
        try assertControl(identifier, title: title, enabled: true, app, location: location)
        attach(app, "upload-metadata-armed-once-" + identifier)
        let armed = button(identifier, app)
        guard armed.exists && armed.isEnabled && armed.isHittable else { throw MetadataUIFailure.unreachable }
        armed.tap()
    }
    @MainActor private func fullText(_ identifier: String, _ expected: String, _ app: XCUIApplication,
        location: MetadataUILocation = .root) throws {
        try reveal(identifier, app, location: location)
        let value = element(identifier, app)
        guard value.exists else { throw MetadataUIFailure.unreachable }
        XCTAssertEqual(value.label, expected); XCTAssertGreaterThan(value.frame.height, 0)
        XCTAssertGreaterThanOrEqual(value.frame.minX, app.frame.minX - 1); XCTAssertLessThanOrEqual(value.frame.maxX, app.frame.maxX + 1)
        let evidence = XCTAttachment(string: metadata(value) + "\nexpectedCompleteSourceText=" + expected)
        evidence.name = "upload-metadata-native-full-text"; evidence.lifetime = .keepAlways; add(evidence)
    }
    @MainActor private func wait(_ message: String, _ app: XCUIApplication, predicate: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: 20) == .completed else {
            attach(app, "upload-metadata-wait-failure"); XCTFail(message); throw MetadataUIFailure.unexpected
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
        let previous = continueAfterFailure; continueAfterFailure = true
        defer { attach(app, name + "-accessibility-after"); continueAfterFailure = previous }
        try app.performAccessibilityAudit(for: types) { issue in
            var lines = [issue.compactDescription, issue.detailedDescription, "auditType=\(issue.auditType.rawValue)",
                "uptime=\(ProcessInfo.processInfo.systemUptime)"]
            if let value = issue.element { lines += [self.metadata(value), value.debugDescription] }
            let evidence = XCTAttachment(string: lines.joined(separator: "\n"))
            evidence.name = name + "-unhandled-accessibility-issue"; evidence.lifetime = .keepAlways; self.add(evidence)
            return false
        }
    }
    @MainActor private func metadata(_ value: XCUIElement) -> String {
        guard value.exists else { return "element no longer exists at metadata observation" }
        return "identifier=\(value.identifier) type=\(value.elementType.rawValue) frame=\(value.frame) enabled=\(value.isEnabled) label=\(value.label)"
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = name; screen.lifetime = .keepAlways; add(screen)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    nonisolated private func canonicalID(_ text: String) -> Bool { text.utf8.count == 36 && UUID(uuidString: text)?.uuidString.lowercased() == text }
    nonisolated private func digest(_ text: String) -> Bool { text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
}

private enum MetadataUILocation: Equatable { case root, detail }
private enum MetadataUIFailure: Error { case environment, unreachable, unexpected, consumedPrefix }
private struct MetadataUIExpected: Decodable {
    struct Signature: Decodable { let sha256: String; let bytes: UInt64; let device: Int64; let inode: UInt64 }
    let schema: String; let nonce: String; let simulator: String; let variant: String; let storeUUID: String
    let capture: String; let operation: String; let requestToken: String; let acceptanceParent: String
    let manifest: Signature; let credentialBundleSHA256: String; let origin: String; let portKeeperID: String; let portKeeperPID: Int
}
private struct MetadataUIContext {
    let value: MetadataUIExpected; let phase: String; let start: String?; let expectedStage: String?; let encoded: String
}
private struct MetadataUIHistory {
    var durable: [String: String] = [:], stops: [String: String] = [:]
    var unresolved = Set<String>()
    var description: String {
        durable.merging(stops, uniquingKeysWith: { _, right in right }).sorted { $0.key < $1.key }
            .map { $0.key + "=" + $0.value }.joined(separator: "\n") + "\nunresolved=" + unresolved.sorted().joined(separator: ",")
    }
}
