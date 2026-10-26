import UIKit
import XCTest

/// The runner alone receives the seed JSON. The product App is launched with
/// no arguments or environment injection and uses its native Wi-Fi observation.
/// Every consuming tap requires its exact unconsumed history prefix first.
final class OriginalUploadAcceptanceFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testSingleThenFixedMultipleAcceptanceAndReadOnlyRelaunch() throws {
        guard ProcessInfo.processInfo.environment["FR_ORIGINAL_UPLOAD_UI"] == "1" else {
            throw XCTSkip("The dedicated one-time original upload fixture is not enabled")
        }
        let context = try uploadContext(), app = XCUIApplication()
        try requireOrdinaryLaunch(app)
        let reference = XCTAttachment(string: context.encoded + "\nphase=" + context.phase
            + "\nstartPhase=" + (context.start ?? "<none>") + "\nreadonlyStage=" + (context.readonlyStage ?? "<none>")
            + "\nrunnerContentSizeCategory=" + UIApplication.shared.preferredContentSizeCategory.rawValue
            + "\nThe main runner owns Simulator font settings. Native product controls alone perform acceptance; no sender is started.")
        reference.name = "original-upload-independent-expectations"; reference.lifetime = .keepAlways; add(reference)
        app.launch(); try loaded(app)
        let phases: [String]
        if context.phase == "all" { phases = ["single", "multiple", "relaunch"] }
        else if context.phase == "tail" {
            let start = try XCTUnwrap(context.start)
            phases = start == "single" ? ["single", "multiple", "relaunch"] : start == "multiple" ? ["multiple", "relaunch"] : ["relaunch"]
        } else { phases = [context.phase] }
        let first = try XCTUnwrap(phases.first)
        let initialStage: Int
        switch first {
        case "single": initialStage = 0
        case "multiple": initialStage = 1
        case "readonly": initialStage = try stage(try XCTUnwrap(context.readonlyStage))
        default: initialStage = 2
        }
        var history = try scanRoot(app)
        try requireHistory(history, stage: initialStage, expected: context.value)
        try assertLibrary(context.value, stage: initialStage, app)
        for phase in phases {
            if phase == "readonly" {
                let before = history
                try inspectRecordedChildren(history, expected: context.value, app)
                try assertEmptyDiscardHistory(context.value, app)
                history = try scanRoot(app)
                try requireHistory(history, stage: initialStage, expected: context.value)
                XCTAssertEqual(history, before)
                try audit(app, context.value.variant + "-readonly-fixed-history")
                continue
            }
            if phase == "relaunch" {
                try requireHistory(history, stage: 2, expected: context.value)
                let before = history
                app.terminate(); try requireOrdinaryLaunch(app); app.launch(); try loaded(app)
                history = try scanRoot(app)
                try requireHistory(history, stage: 2, expected: context.value)
                XCTAssertEqual(history, before)
                try assertLibrary(context.value, stage: 2, app)
                try inspectRecordedChildren(history, expected: context.value, app)
                try assertEmptyDiscardHistory(context.value, app)
                try audit(app, context.value.variant + "-relaunch-same-parents-children-queued")
                let parent = try XCTUnwrap(history.headers.first { $0.value == "原本の転送要求・3本" }?.key)
                let parentID = String(parent.dropFirst("library.transfer.header.".count))
                try tapControl("library.transfer.record.lookup." + parentID, title: "この転送要求の保存記録を照合", app)
                try reveal("library.transfer.feedback", app)
                try wait("The record lookup must not become another acceptance", app) {
                    let feedback = self.element("library.transfer.feedback", app)
                    return feedback.exists && feedback.label == self.lookupFeedback
                }
                try fullText("library.transfer.feedback", lookupFeedback, app)
                history = try scanRoot(app)
                try requireHistory(history, stage: 2, expected: context.value)
                XCTAssertEqual(history, before)
                try audit(app, context.value.variant + "-relaunch-explicit-receipt-lookup-no-new-parent")
                continue
            }
            let next = try stage(phase)
            try requireHistory(history, stage: next - 1, expected: context.value)
            if phase == "single" {
                try openDetail(context.value.target("a"), app)
                try audit(app, context.value.variant + "-single-detail-before-native-acceptance")
                try awaitNativeWiFi(app, location: .detail)
                try tapControl("library.action.transfer", title: "Mac miniへ転送", app, location: .detail)
                try reveal("library.transfer.feedback", app, location: .detail)
                try wait("The single request must reach a durable queued acceptance", app) {
                    let feedback = self.element("library.transfer.feedback", app)
                    return feedback.exists && feedback.label == self.singleFeedback
                }
                try fullText("library.transfer.feedback", singleFeedback, app, location: .detail)
                try audit(app, context.value.variant + "-single-accepted-communication-not-started")
                try closeDetail(app)
            } else {
                for target in context.value.targets { try select(target, app) }
                try awaitNativeWiFi(app, location: .root)
                try revealControl("library.action.transfer", app)
                try assertControl("library.action.transfer", title: "Mac miniへ転送", enabled: true, app)
                try audit(app, context.value.variant + "-three-fixed-targets-before-one-native-tap")
                // One tap only. If the result is uncertain or the test is
                // interrupted, VERIFY/observe decides the consumed prefix.
                try tapControl("library.action.transfer", title: "Mac miniへ転送", app)
                try reveal("library.transfer.feedback", app)
                try wait("The whole three-child plan must record two independent nonprocessing reasons", app) {
                    let feedback = self.element("library.transfer.feedback", app)
                    return feedback.exists && feedback.label == self.multipleFeedback
                }
                try fullText("library.transfer.feedback", multipleFeedback, app)
                try audit(app, context.value.variant + "-multiple-one-queued-two-not-processed")
            }
            history = try scanRoot(app)
            try requireHistory(history, stage: next, expected: context.value)
            try inspectRecordedChildren(history, expected: context.value, app)
            try assertLibrary(context.value, stage: next, app)
            attach(app, context.value.variant + "-consumed-" + phase + "-no-resubmission")
        }
    }

    @MainActor private var singleFeedback: String {
        "転送要求を受け付けました。通信はまだ開始していません。固定した動画別の状態を確認してください。"
    }
    @MainActor private var multipleFeedback: String {
        "選択した3本の受付結果を保存しました。転送待ち1本と未処理の理由を動画別に確認してください。通信はまだ開始していません。"
    }
    @MainActor private var lookupFeedback: String {
        "転送要求の保存記録を照合しました。受付時の3本の結果と現在の通信状態を確認してください。この照合から通信は開始していません。"
    }
    @MainActor private var acceptedText: String { "受付時の記録：転送要求を受け付けました。受付時には通信を開始していません。" }
    @MainActor private var alreadyText: String { "未処理：同じ原本と転送先への転送要求が既にあります。" }
    @MainActor private var missingText: String { "未処理：iPhoneの原本が見つかりません。" }
    @MainActor private var runningText: String { "本人の意思：継続の記録あり（通信の開始・実際の再開とは別です）" }
    @MainActor private var waitsText: String { "待機条件：記録なし（通信の開始・再開を保証しません）" }
    @MainActor private var transportText: String { "通信状態の記録：開始待ち。通信処理の終了・媒体の使用解放は別に確認が必要です。" }

    @MainActor private func uploadContext() throws -> (value: UploadUIExpected, phase: String, start: String?, readonlyStage: String?, encoded: String) {
        let env = ProcessInfo.processInfo.environment, prefix = "FR_ORIGINAL_UPLOAD_"
        let encoded = try XCTUnwrap(env[prefix + "EXPECTED"])
        guard encoded.utf8.count <= 32_768 else { throw UploadUIFailure.environment }
        let value = try JSONDecoder().decode(UploadUIExpected.self, from: Data(encoded.utf8))
        let phase = try XCTUnwrap(env[prefix + "PHASE"]), nonce = try XCTUnwrap(env[prefix + "NONCE"])
        let variant = try XCTUnwrap(env[prefix + "VARIANT"]), start = env[prefix + "START_PHASE"], readonly = env[prefix + "EXPECTED_STAGE"]
        let requested = try XCTUnwrap(env[prefix + "SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let actual = try XCTUnwrap(env["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        guard env[prefix + "SEED"] != "1", env[prefix + "VERIFY"] != "1", actual == requested,
              UUID(uuidString: value.simulator) == actual, value.nonce == nonce, value.variant == variant,
              ((actual.uuidString == "0B25C6C1-874F-469C-9E64-5147ECD8B0E3" && variant == "normal" && nonce == "fbfcf429-af96-4e4d-a4a5-bc91d5c42f90")
                || (actual.uuidString == "D2A95760-9D74-41FF-AF73-4C7CF94E0385" && variant == "max" && nonce == "6ad6cdcb-598f-4e30-b41c-68e0fbcc37b5")),
              value.schema == "fr-original-upload-ui-v1", UUID(uuidString: value.storeUUID) != nil,
              value.manifest.bytes > 0, value.manifest.inode > 0, value.manifest.sha256.utf8.count == 64,
              ["single", "multiple", "all", "tail", "relaunch", "readonly"].contains(phase),
              value.targets.map(\.role) == ["a", "b", "missing"], Set(value.targets.map(\.capture)).count == 3,
              value.targets.allSatisfy({ $0.capture == "ou-" + String(nonce.prefix(8)) + "-" + $0.role && $0.present == ($0.role != "missing") }) else {
            throw UploadUIFailure.environment
        }
        if phase == "tail" {
            guard let start, ["single", "multiple", "relaunch"].contains(start), readonly == nil else { throw UploadUIFailure.environment }
        } else if phase == "readonly" {
            guard let readonly, ["seed", "single", "multiple"].contains(readonly), start == nil else { throw UploadUIFailure.environment }
        } else if start != nil || readonly != nil { throw UploadUIFailure.environment }
        return (value, phase, start, readonly, encoded)
    }
    @MainActor private func stage(_ phase: String) throws -> Int { try XCTUnwrap(["seed", "single", "multiple"].firstIndex(of: phase)) }
    @MainActor private func requireOrdinaryLaunch(_ app: XCUIApplication) throws {
        XCTAssertTrue(app.launchArguments.isEmpty && app.launchEnvironment.isEmpty)
        guard app.launchArguments.isEmpty && app.launchEnvironment.isEmpty else { throw UploadUIFailure.environment }
    }
    @MainActor private func loaded(_ app: XCUIApplication) throws {
        XCTAssertTrue(button("library.refresh", app).waitForExistence(timeout: 20))
        try wait("The normal library must load without a fixture repair", app) {
            let refresh = self.button("library.refresh", app)
            return refresh.exists && refresh.isEnabled && !self.element("library.loadFailure", app).exists
                && !self.element("library.empty", app).exists
        }
        XCTAssertFalse(element("library.empty", app).exists)
        XCTAssertFalse(element("originalPlayback.player", app).exists)
        XCTAssertFalse(element("renditionPlayback.player", app).exists)
    }
    @MainActor private func awaitNativeWiFi(_ app: XCUIApplication, location: UploadUILocation) throws {
        try revealControl("library.action.transfer", app, location: location)
        try wait("The product's native Wi-Fi observation must allow this first acceptance; no test override is installed", app) {
            let control = self.button("library.action.transfer", app)
            return control.exists && control.isEnabled
        }
        try assertControl("library.action.transfer", title: "Mac miniへ転送", enabled: true, app, location: location)
    }
    @MainActor private func openDetail(_ target: UploadUIExpected.Target, _ app: XCUIApplication) throws {
        try fullText("library.itemTitle." + target.capture, "動画 " + target.capture, app)
        try revealControl("library.itemTitle." + target.capture, app, buttonOnly: false)
        let title = element("library.itemTitle." + target.capture, app), item = element("library.item." + target.capture, app)
        guard item.exists else { throw UploadUIFailure.unreachable }
        XCTAssertGreaterThanOrEqual(item.frame.height, 44)
        guard title.exists && title.isEnabled && title.isHittable else { throw UploadUIFailure.unreachable }
        title.tap()
        XCTAssertTrue(element("library.detailIdentity", app).waitForExistence(timeout: 10))
        try fullText("library.detailIdentity", "動画 " + target.capture, app, location: .detail)
    }
    @MainActor private func closeDetail(_ app: XCUIApplication) throws {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        guard back.exists && back.isHittable else { throw UploadUIFailure.unreachable }
        back.tap(); try loaded(app)
    }
    @MainActor private func select(_ target: UploadUIExpected.Target, _ app: XCUIApplication) throws {
        let identifier = "library.select." + target.capture
        try reveal(identifier, app)
        let row = element(identifier, app), control = row.descendants(matching: .switch).firstMatch
        guard row.exists && control.exists else { throw UploadUIFailure.unexpected }
        XCTAssertEqual(row.label, "動画 " + target.capture + "を選択")
        XCTAssertEqual(row.value as? String, "0"); XCTAssertEqual(control.value as? String, "0")
        XCTAssertTrue(control.isEnabled && control.isHittable)
        guard row.value as? String == "0", control.value as? String == "0", control.isEnabled && control.isHittable else {
            throw UploadUIFailure.consumedPrefix
        }
        control.tap()
        try wait("The live row and native switch must both retain selection", app) {
            let current = self.element(identifier, app)
            guard current.exists else { return false }
            let native = current.descendants(matching: .switch).firstMatch
            return native.exists && current.value as? String == "1" && native.value as? String == "1"
        }
    }
    @MainActor private func assertLibrary(_ expected: UploadUIExpected, stage: Int, _ app: XCUIApplication) throws {
        for target in expected.targets {
            try fullText("library.itemTitle." + target.capture, "動画 " + target.capture, app)
            try fullText("library.itemCapturedAt." + target.capture, "撮影日時不明", app)
            try fullText("library.itemSave." + target.capture, "正常保存", app)
            try fullText("library.itemOriginal." + target.capture, target.present ? "原本あり" : "原本なし", app)
            if target.role == "missing" {
                try fullText("library.itemReconciliation." + target.capture, "要照合", app)
            }
        }
        let count = stage == 0 ? 0 : stage == 1 ? 1 : 2
        let summaries = try scanRoot(app).summaries
        XCTAssertEqual(summaries.count, count)
        for target in expected.targets where target.role == "a" && stage > 0 || target.role == "b" && stage == 2 {
            XCTAssertEqual(summaries["library.request.summary." + target.capture], "通信要求は1件です。対象別の記録と本人操作は動画の詳細で確認できます。")
        }
        try audit(app, expected.variant + "-library-3-saved-2-present-1-missing-stage-\(stage)")
    }
    @MainActor private func inspectRecordedChildren(_ history: UploadUIHistory, expected: UploadUIExpected, _ app: XCUIApplication) throws {
        for (identifier, title) in history.titles.sorted(by: { $0.key < $1.key }) {
            let child = String(identifier.dropFirst("library.transfer.child.title.".count))
            try fullText(identifier, title, app)
            try fullText("library.transfer.child.decision." + child, try XCTUnwrap(history.decisions["library.transfer.child.decision." + child]), app)
            if history.intents["library.transfer.child.intent." + child] != nil {
                try fullText("library.transfer.child.intent." + child, runningText, app)
                try fullText("library.transfer.child.waits." + child, waitsText, app)
                try fullText("library.transfer.child.transport." + child, transportText, app)
                let target = try XCTUnwrap(expected.targets.first { "動画 " + $0.capture == title })
                try openDetail(target, app)
                let token = Data(child.utf8).base64EncodedString()
                try fullText("library.request.identity." + token, "対象：動画 " + target.capture + "・原本", app, location: .detail)
                try fullText("library.request.intent." + token, runningText, app, location: .detail)
                try fullText("library.request.waits." + token, waitsText, app, location: .detail)
                try fullText("library.request.transport." + token, transportText, app, location: .detail)
                try assertControl("library.request.pause." + token, title: "この通信を停止", enabled: true, app, location: .detail)
                try assertControl("library.request.cancel." + token, title: "この通信を取り消す", enabled: true, app, location: .detail)
                try assertControl("library.request.resumeIntent." + token, title: "停止を解除して待機", enabled: false, app, location: .detail)
                try audit(app, expected.variant + "-queued-current-request-" + target.role)
                try closeDetail(app)
            }
        }
    }
    @MainActor private func assertEmptyDiscardHistory(_ expected: UploadUIExpected, _ app: XCUIApplication) throws {
        try revealControl("library.scope", app, buttonOnly: false)
        element("library.scope", app).tap()
        let history = app.buttons["破棄の履歴"]
        guard history.waitForExistence(timeout: 5) && history.isHittable else { throw UploadUIFailure.unreachable }
        history.tap()
        try fullText("library.historyExplanation", "原本の削除結果を照合できた破棄の記録です。原本を保管するゴミ箱ではありません。", app)
        try fullText("library.empty", "破棄の履歴はありません", app)
        try audit(app, expected.variant + "-discard-history-empty-originals-retained")
        try revealControl("library.scope", app, buttonOnly: false)
        element("library.scope", app).tap()
        let library = app.buttons["ライブラリ"]
        guard library.waitForExistence(timeout: 5) && library.isHittable else { throw UploadUIFailure.unreachable }
        library.tap(); try loaded(app)
    }

    /// Root-origin scans collect all dynamic IDs without deriving expectations
    /// from a missing element. A consumed phase must never be tapped again.
    @MainActor private func scanRoot(_ app: XCUIApplication) throws -> UploadUIHistory {
        try seekTop(app, location: .root)
        var result = UploadUIHistory(), collected = Set<String>(), previous = "", stable = 0
        for _ in 0..<240 {
            let values = app.descendants(matching: .any).matching(NSPredicate(format:
                "(identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@) AND NOT (identifier IN %@)",
                "library.transfer.", "library.request.summary.", "library.submission.", "library.result.", Array(collected) as NSArray)).allElementsBoundByIndex
            for value in values {
                guard value.exists else { continue }
                let identifier = value.identifier, label = value.label
                collected.insert(identifier)
                if identifier.hasPrefix("library.transfer.header.") { result.headers[identifier] = label }
                if identifier.hasPrefix("library.transfer.explanation.") { result.explanations[identifier] = label }
                if identifier.hasPrefix("library.transfer.child.title.") { result.titles[identifier] = label }
                if identifier.hasPrefix("library.transfer.child.decision.") { result.decisions[identifier] = label }
                if identifier.hasPrefix("library.transfer.child.intent.") { result.intents[identifier] = label }
                if identifier.hasPrefix("library.transfer.child.waits.") { result.waits[identifier] = label }
                if identifier.hasPrefix("library.transfer.child.transport.") { result.transports[identifier] = label }
                if identifier.hasPrefix("library.transfer.record.lookup.") { result.lookups[identifier] = label }
                if identifier.hasPrefix("library.request.summary.") { result.summaries[identifier] = label }
                if identifier.hasPrefix("library.transfer.pending") || identifier == "library.transfer.lookup"
                    || identifier.hasPrefix("library.transfer.child.currentUnavailable.") { result.pending.insert(identifier) }
                if identifier.hasPrefix("library.submission.") || identifier.hasPrefix("library.result.") { result.legacyResults.insert(identifier) }
            }
            let signature = app.scrollViews.firstMatch.debugDescription.replacingOccurrences(of: "0x[0-9a-fA-F]+",
                with: "0x<address>", options: .regularExpression)
            stable = signature == previous ? stable + 1 : 0
            if stable >= 3 {
                let evidence = XCTAttachment(string: result.description + "\n" + signature)
                evidence.name = "original-upload-complete-fixed-history"; evidence.lifetime = .keepAlways; add(evidence)
                return result
            }
            previous = signature; app.swipeUp()
        }
        attach(app, "original-upload-history-no-stable-bottom"); throw UploadUIFailure.unreachable
    }
    @MainActor private func requireHistory(_ history: UploadUIHistory, stage: Int, expected: UploadUIExpected) throws {
        let children = stage == 2 ? 4 : stage, accepted = stage == 2 ? 2 : stage
        XCTAssertTrue(history.pending.isEmpty && history.legacyResults.isEmpty)
        XCTAssertEqual(history.headers.count, stage); XCTAssertEqual(history.explanations.count, stage)
        XCTAssertEqual(history.lookups.count, stage); XCTAssertEqual(history.titles.count, children)
        XCTAssertEqual(history.decisions.count, children); XCTAssertEqual(history.intents.count, accepted)
        XCTAssertEqual(history.waits.count, accepted); XCTAssertEqual(history.transports.count, accepted)
        guard history.pending.isEmpty && history.legacyResults.isEmpty && history.headers.count == stage
            && history.explanations.count == stage && history.lookups.count == stage && history.titles.count == children
            && history.decisions.count == children && history.intents.count == accepted && history.waits.count == accepted
            && history.transports.count == accepted else { throw UploadUIFailure.consumedPrefix }
        var headerCounts: [String: Int] = [:]
        for (identifier, label) in history.headers {
            let parent = String(identifier.dropFirst("library.transfer.header.".count))
            XCTAssertTrue(canonicalID(parent)); headerCounts[label, default: 0] += 1
            let count = label == "原本の転送要求・1本" ? 1 : 3
            XCTAssertEqual(history.explanations["library.transfer.explanation." + parent],
                "受付時に固定した\(count)本すべての結果です。未処理の対象もこの要求に残します。受付はMacへの保存や通信の成功を示しません。")
            XCTAssertEqual(history.lookups["library.transfer.record.lookup." + parent], "この転送要求の保存記録を照合")
        }
        let expectedHeaders: [String: Int] = stage == 0 ? [:] : stage == 1 ? ["原本の転送要求・1本": 1]
            : ["原本の転送要求・1本": 1, "原本の転送要求・3本": 1]
        XCTAssertEqual(headerCounts, expectedHeaders)
        var roles: [String: Int] = [:], decisions: [String: Int] = [:], acceptedIDs = Set<String>(), childIDs = Set<String>()
        for (identifier, title) in history.titles {
            let child = String(identifier.dropFirst("library.transfer.child.title.".count))
            guard canonicalID(child), childIDs.insert(child).inserted,
                  let target = expected.targets.first(where: { "動画 " + $0.capture == title }),
                  let decision = history.decisions["library.transfer.child.decision." + child] else { throw UploadUIFailure.unexpected }
            roles[target.role, default: 0] += 1; decisions[decision, default: 0] += 1
            if decision == acceptedText { acceptedIDs.insert(child) }
            else if target.role == "a" { XCTAssertEqual(decision, alreadyText) }
            else if target.role == "missing" { XCTAssertEqual(decision, missingText) }
            else { throw UploadUIFailure.unexpected }
        }
        let expectedRoles: [String: Int] = stage == 0 ? [:] : stage == 1 ? ["a": 1] : ["a": 2, "b": 1, "missing": 1]
        let expectedDecisions: [String: Int] = stage == 0 ? [:] : stage == 1 ? [acceptedText: 1]
            : [acceptedText: 2, alreadyText: 1, missingText: 1]
        XCTAssertEqual(roles, expectedRoles); XCTAssertEqual(decisions, expectedDecisions)
        XCTAssertEqual(Set(history.intents.keys.map { String($0.dropFirst("library.transfer.child.intent.".count)) }), acceptedIDs)
        XCTAssertEqual(Set(history.waits.keys.map { String($0.dropFirst("library.transfer.child.waits.".count)) }), acceptedIDs)
        XCTAssertEqual(Set(history.transports.keys.map { String($0.dropFirst("library.transfer.child.transport.".count)) }), acceptedIDs)
        XCTAssertTrue(history.intents.values.allSatisfy { $0 == runningText })
        XCTAssertTrue(history.waits.values.allSatisfy { $0 == waitsText })
        XCTAssertTrue(history.transports.values.allSatisfy { $0 == transportText })
        guard headerCounts == expectedHeaders && roles == expectedRoles && decisions == expectedDecisions else { throw UploadUIFailure.consumedPrefix }
    }

    @MainActor private func seekTop(_ app: XCUIApplication, location: UploadUILocation) throws {
        let identifier = location == .root ? "product.capture" : "library.detailIdentity"
        for _ in 0..<180 {
            let anchor = element(identifier, app)
            if anchor.exists && anchor.isHittable && anchor.frame.minY >= app.navigationBars.firstMatch.frame.maxY - 2 { return }
            app.swipeDown()
        }
        attach(app, "original-upload-top-unreachable-" + identifier); throw UploadUIFailure.unreachable
    }
    @MainActor private func reveal(_ identifier: String, _ app: XCUIApplication, location: UploadUILocation = .root) throws {
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
        attach(app, "original-upload-unreachable-" + identifier); throw UploadUIFailure.unreachable
    }
    @MainActor private func revealControl(_ identifier: String, _ app: XCUIApplication, location: UploadUILocation = .root,
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
        attach(app, "original-upload-control-unreachable-" + identifier); throw UploadUIFailure.unreachable
    }
    @MainActor private func assertControl(_ identifier: String, title: String, enabled: Bool, _ app: XCUIApplication,
        location: UploadUILocation = .root) throws {
        try revealControl(identifier, app, location: location)
        let value = button(identifier, app)
        guard value.exists else { throw UploadUIFailure.unreachable }
        XCTAssertEqual(value.label, title); XCTAssertEqual(value.isEnabled, enabled)
        let frame = value.frame, bound = frame.minY.ulp + frame.maxY.ulp
        XCTAssertTrue(frame.height.isFinite && bound.isFinite); XCTAssertGreaterThanOrEqual(bound, 0); XCTAssertLessThan(bound, 1e-8)
        XCTAssertGreaterThanOrEqual(frame.width, 44); XCTAssertGreaterThanOrEqual(frame.height + bound, 44)
        XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX - 1); XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX + 1)
        if enabled { XCTAssertTrue(value.isHittable) }
        guard value.label == title && value.isEnabled == enabled && (!enabled || value.isHittable) else { throw UploadUIFailure.unexpected }
    }
    @MainActor private func tapControl(_ identifier: String, title: String, _ app: XCUIApplication,
        location: UploadUILocation = .root) throws {
        try assertControl(identifier, title: title, enabled: true, app, location: location)
        attach(app, "original-upload-armed-once-" + identifier)
        button(identifier, app).tap()
    }
    @MainActor private func fullText(_ identifier: String, _ expected: String, _ app: XCUIApplication,
        location: UploadUILocation = .root) throws {
        try reveal(identifier, app, location: location)
        let value = element(identifier, app)
        guard value.exists else { throw UploadUIFailure.unreachable }
        XCTAssertEqual(value.label, expected); XCTAssertGreaterThan(value.frame.height, 0)
        XCTAssertGreaterThanOrEqual(value.frame.minX, app.frame.minX - 1); XCTAssertLessThanOrEqual(value.frame.maxX, app.frame.maxX + 1)
        let evidence = XCTAttachment(string: metadata(value) + "\nexpectedCompleteSourceText=" + expected)
        evidence.name = "original-upload-native-full-text"; evidence.lifetime = .keepAlways; add(evidence)
    }
    @MainActor private func wait(_ message: String, _ app: XCUIApplication, predicate: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: 20) == .completed else {
            attach(app, "original-upload-wait-failure"); XCTFail(message); throw UploadUIFailure.unexpected
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
}

private enum UploadUILocation: Equatable { case root, detail }
private enum UploadUIFailure: Error { case environment, unreachable, unexpected, consumedPrefix }
private struct UploadUIExpected: Decodable {
    struct Target: Decodable { let role: String; let capture: String; let present: Bool }
    struct Manifest: Decodable { let sha256: String; let bytes: UInt64; let device: Int64; let inode: UInt64 }
    let schema: String; let nonce: String; let simulator: String; let variant: String; let storeUUID: String
    let manifest: Manifest; let targets: [Target]
    func target(_ role: String) throws -> Target { try XCTUnwrap(targets.first { $0.role == role }) }
}
private struct UploadUIHistory: Equatable {
    var headers: [String: String] = [:], explanations: [String: String] = [:], titles: [String: String] = [:]
    var decisions: [String: String] = [:], intents: [String: String] = [:], waits: [String: String] = [:]
    var transports: [String: String] = [:], lookups: [String: String] = [:], summaries: [String: String] = [:]
    var pending = Set<String>(), legacyResults = Set<String>()
    var description: String {
        ["headers": headers, "explanations": explanations, "titles": titles, "decisions": decisions,
            "intents": intents, "waits": waits, "transports": transports, "lookups": lookups, "summaries": summaries]
            .sorted { $0.key < $1.key }.map { key, rows in
                key + "\n" + rows.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: "\n")
            }.joined(separator: "\n") + "\npending=" + pending.sorted().joined(separator: ",")
            + "\nlegacyResults=" + legacyResults.sorted().joined(separator: ",")
    }
}
