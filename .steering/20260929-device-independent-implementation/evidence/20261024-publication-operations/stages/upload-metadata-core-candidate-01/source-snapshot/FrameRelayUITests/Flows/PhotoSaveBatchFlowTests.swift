import UIKit
import XCTest

/// Expected identities come only from the immutable Unit seed manifest. The
/// ordinary App is launched without test arguments or environment overrides.
final class PhotoSaveBatchFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testNormalNativeGateSingleAndMixedNewPhotoSaveRequests() throws {
        guard ProcessInfo.processInfo.environment["FR_S31_PHOTO_BATCH_TAIL_FROM_SINGLE"] != "1" else {
            throw XCTSkip("The verified single-success root requires the dedicated tail entry")
        }
        let context = try photoContext(entry: "manual")
        try exercise(context)
    }

    @MainActor func testMaximumTextExplicitlyContinuesAcceptedSingleAndMixedPhotoSaveRequests() throws {
        let context = try photoContext(entry: "accepted")
        try exercise(context)
    }

    /// Requires the independent partial Unit VERIFY before this invocation.
    /// The old single SDK action is observed by exact child ID and never tapped.
    @MainActor func testNormalContinuesMixedRequestAfterVerifiedSingleSuccess() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["FR_S31_PHOTO_BATCH_TAIL_FROM_SINGLE"] == "1" else {
            throw XCTSkip("The verified single-success tail is not enabled")
        }
        let context = try photoContext(entry: "manual")
        guard context.phase == "normal" else { throw PhotoUIFailure.invalidContext }
        let prior = try XCTUnwrap(environment["FR_S31_PHOTO_BATCH_PRIOR_SINGLE_CHILD_ID"])
        guard prior.utf8.count == 36, UUID(uuidString: prior) != nil else { throw PhotoUIFailure.invalidContext }
        try exercise(context, priorSingleChild: prior)
    }

    /// The independent queued/success VERIFY must precede this focused tail.
    /// It never opens or starts the already successful single target again.
    @MainActor func testMaximumTextContinuesOnlyMixedQueueAfterVerifiedSingleSuccess() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["FR_S31_PHOTO_BATCH_TAIL_FROM_SINGLE"] == "1" else {
            throw XCTSkip("The verified maximum-text mixed tail is not enabled")
        }
        let context = try photoContext(entry: "accepted")
        let single = try XCTUnwrap(context.targets.first { $0.role == "single" })
        let local = try XCTUnwrap(context.targets.first { $0.role == "mixedLocal" })
        let remote = try XCTUnwrap(context.targets.first { $0.role == "mixedRemote" })
        let prior = try XCTUnwrap(environment["FR_S31_PHOTO_BATCH_PRIOR_SINGLE_CHILD_ID"])
        guard context.phase == "max", prior.utf8.count == 36, UUID(uuidString: prior) != nil,
              Data(prior.utf8) == Data((single.child ?? "").utf8) else { throw PhotoUIFailure.invalidContext }
        let batch = try XCTUnwrap(local.batch)
        XCTAssertEqual(remote.batch, batch)
        XCTAssertNotEqual(single.batch, batch)
        let expected = XCTAttachment(string: try String(decoding: JSONEncoder().encode(context), as: UTF8.self)
            + "\nverifiedPriorSingleChild=" + prior + "\nSingle success is inherited only from the independent partial VERIFY; this tail never resumes or saves that target.")
        expected.name = "photo-batch-maximum-focused-tail-independent-identities"; expected.lifetime = .keepAlways; add(expected)
        let app = XCUIApplication(); app.launch()
        try requireLibrary(app)
        try top(app)
        for target in [local, remote] {
            let child = try locateChild(target, app)
            XCTAssertEqual(try childID(child), target.child)
            try readFullText(child, expected: progress(target, succeeded: false), app: app)
        }
        try readFullText(element("library.photoBatch.explanation." + batch, app), expected: resumeExplanation, app: app)
        let resume = button("library.photoBatch.resume." + batch, app)
        try revealControl(resume, app)
        XCTAssertTrue(resume.isEnabled && resume.isHittable)
        try audit(app, "max-focused-mixed-queued-before-explicit-continue")
        try tapButtonAfterAudit("library.photoBatch.resume." + batch, app)
        for target in [local, remote] {
            let child = try requireSuccess(target, app)
            XCTAssertEqual(try childID(child), target.child)
            try readFullText(child, expected: progress(target, succeeded: true), app: app)
        }
        let remoteRegistration = element("library.remote.photo.registration." + (try XCTUnwrap(remote.child)), app)
        try readFullText(remoteRegistration, expected: "過去の登録：過去の登録成功", app: app)
        try requireDuplicateSuppressed(app, identifier: "library.remote.photo.save." + (try XCTUnwrap(remote.remoteToken)))
        try audit(app, "max-focused-mixed-native-results-and-no-duplicate")
        app.terminate(); app.launch()
        try requireLibrary(app)
        for target in context.targets {
            let child = try requireSuccess(target, app)
            XCTAssertEqual(try childID(child), target.child)
            if target.role == "single" { XCTAssertEqual(try childID(child), prior) }
            try readFullText(child, expected: progress(target, succeeded: true), app: app)
        }
        XCTAssertFalse(button("library.photoBatch.lookup", app).exists)
        for target in context.targets {
            XCTAssertFalse(button("library.photoBatch.resume." + (try XCTUnwrap(target.batch)), app).exists)
        }
        try requireDuplicateSuppressed(app, identifier: "library.remote.photo.save." + (try XCTUnwrap(remote.remoteToken)))
        try audit(app, "max-focused-relaunch-retains-three-exact-results-without-auto-add")
        attach(app, "max-focused-tail-final-results")
        app.terminate()
    }

    /// Observes the independently verified three successful native additions.
    /// There are no save/resume/retry taps in either process lifetime.
    @MainActor func testMaximumTextObservesThreeVerifiedPhotoResultsOnlyAcrossRelaunch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["FR_S31_PHOTO_BATCH_RESULTS_ONLY"] == "1" else {
            throw XCTSkip("The verified maximum-text results-only observation is not enabled")
        }
        let context = try photoContext(entry: "accepted")
        guard context.phase == "max" else { throw PhotoUIFailure.invalidContext }
        let remote = try XCTUnwrap(context.targets.first { $0.role == "mixedRemote" })
        let expected = XCTAttachment(string: try String(decoding: JSONEncoder().encode(context), as: UTF8.self)
            + "\nRead-only results observation after independent full VERIFY. No save, resume, retry or fixture mutation is requested.")
        expected.name = "photo-batch-maximum-results-only-independent-identities"; expected.lifetime = .keepAlways; add(expected)
        let app = XCUIApplication(); app.launch()
        var firstObserved: [String: String] = [:]
        for observation in 0..<2 {
            try requireLibrary(app)
            for target in context.targets {
                let child = try requireSuccess(target, app)
                let id = try childID(child)
                XCTAssertEqual(id, target.child)
                if observation == 0 { firstObserved[target.role] = id }
                else { XCTAssertEqual(id, firstObserved[target.role]) }
                try readFullText(child, expected: progress(target, succeeded: true), app: app)
            }
            XCTAssertEqual(Set(firstObserved.values).count, 3)
            let registration = element("library.remote.photo.registration." + (try XCTUnwrap(remote.child)), app)
            try readFullText(registration, expected: "過去の登録：過去の登録成功", app: app)
            try requireDuplicateSuppressed(app, identifier: "library.remote.photo.save." + (try XCTUnwrap(remote.remoteToken)))
            XCTAssertFalse(button("library.photoBatch.lookup", app).exists)
            for target in context.targets {
                XCTAssertFalse(button("library.photoBatch.resume." + (try XCTUnwrap(target.batch)), app).exists)
            }
            try audit(app, observation == 0 ? "max-results-only-three-successes" : "max-results-only-relaunch-same-three-successes")
            if observation == 0 { app.terminate(); app.launch() }
        }
        attach(app, "max-results-only-final-three-exact-children")
        app.terminate()
    }

    @MainActor private func exercise(_ context: PhotoUIExpected, priorSingleChild: String? = nil) throws {
        let single = try XCTUnwrap(context.targets.first { $0.role == "single" })
        let local = try XCTUnwrap(context.targets.first { $0.role == "mixedLocal" })
        let remote = try XCTUnwrap(context.targets.first { $0.role == "mixedRemote" })
        let app = XCUIApplication()
        let identity = XCTAttachment(string: try String(decoding: JSONEncoder().encode(context), as: UTF8.self)
            + "\nrunnerContentSizeCategory=" + UIApplication.shared.preferredContentSizeCategory.rawValue
            + "\nProduct labels, actual viewport frames and screenshots establish UI layout; runner font metrics are references only."
            + "\nmanual requires the ordinary native initial Wi-Fi gate; accepted begins from injected test-only queued acceptance."
            + "\nverifiedPriorSingleChild=" + (priorSingleChild ?? "none"))
        identity.name = "photo-batch-independent-manifest-identities"; identity.lifetime = .keepAlways; add(identity)
        app.launch()
        try requireLibrary(app)
        try top(app)
        try openLocal(single.capture, app)
        XCTAssertEqual(element("library.detailIdentity", app).label, "動画 " + single.capture)
        var children: [String: String] = [:]
        if let priorSingleChild {
            guard context.entry == "manual" && context.phase == "normal" else { throw PhotoUIFailure.invalidContext }
            let prior = try requireSuccess(single, app)
            XCTAssertEqual(try childID(prior), priorSingleChild)
        } else if context.entry == "manual" {
            XCTAssertFalse(childQuery(single, app).firstMatch.exists)
            let explanationID = "library.action.saveToPhotos.explanation"
            try readFullText(element(explanationID, app), expected: saveExplanation(local: 1, remote: 0), app: app)
            let save = button("library.action.saveToPhotos", app)
            try requireNewSaveAvailable(save, app)
            try audit(app, context.phase + "-single-new-request-before-native-gate")
            try tapButtonAfterAudit("library.action.saveToPhotos", app, newSave: true)
        } else {
            let batch = try XCTUnwrap(single.batch)
            let child = try locateChild(single, app)
            XCTAssertEqual(child.identifier, "library.photoBatch.child." + (try XCTUnwrap(single.child)))
            try readFullText(child, expected: progress(single, succeeded: false), app: app)
            try readFullText(element("library.photoBatch.explanation." + batch, app), expected: resumeExplanation, app: app)
            let resume = button("library.photoBatch.resume." + batch, app)
            try revealControl(resume, app)
            XCTAssertTrue(resume.isEnabled)
            try audit(app, context.phase + "-single-accepted-queued-before-explicit-continue")
            try tapButtonAfterAudit("library.photoBatch.resume." + batch, app)
        }
        let singleChild = try requireSuccess(single, app)
        children[single.role] = try childID(singleChild)
        if let priorSingleChild { XCTAssertEqual(children[single.role], priorSingleChild) }
        try readFullText(singleChild, expected: progress(single, succeeded: true), app: app)
        let singleRegistration = element("library.photo.registration." + (try XCTUnwrap(children[single.role])), app)
        try readFullText(singleRegistration, expected: "過去の登録：過去の登録成功", app: app)
        try requireDuplicateSuppressed(app, identifier: "library.action.saveToPhotos")
        try audit(app, context.phase + "-single-native-result-and-no-duplicate")
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "identifier == %@", "BackButton")).firstMatch
        try wait("The actual back control must remain available after the audit", timeout: 10) { back.exists && back.isEnabled && back.isHittable }
        requireMinimumButtonHeight(back)
        back.tap()
        try requireLibrary(app)
        try top(app)

        if context.entry == "manual" {
            let localToggle = app.switches.matching(NSPredicate(format: "identifier == %@", "library.select." + local.capture)).firstMatch
            try selectSwitchOnce(localToggle, app)
            let remoteToggle = app.switches.matching(NSPredicate(format: "identifier == %@",
                "library.remote.photo.select." + (try XCTUnwrap(remote.remoteToken)))).firstMatch
            try selectSwitchOnce(remoteToggle, app)
            try readFullText(element("library.action.saveToPhotos.explanation", app),
                expected: saveExplanation(local: 1, remote: 1), app: app)
            let save = button("library.action.saveToPhotos", app)
            try requireNewSaveAvailable(save, app)
            XCTAssertEqual(save.label, "選択した2本の取得済み軽量版を写真に保存")
            try audit(app, context.phase + "-fixed-mixed-local-and-remote-before-native-gate")
            try tapButtonAfterAudit("library.action.saveToPhotos", app, newSave: true)
        } else {
            let batch = try XCTUnwrap(local.batch)
            XCTAssertEqual(remote.batch, batch)
            for target in [local, remote] {
                let queued = try locateChild(target, app)
                XCTAssertEqual(queued.identifier, "library.photoBatch.child." + (try XCTUnwrap(target.child)))
                try readFullText(queued, expected: progress(target, succeeded: false), app: app)
            }
            try readFullText(element("library.photoBatch.explanation." + batch, app), expected: resumeExplanation, app: app)
            let resume = button("library.photoBatch.resume." + batch, app)
            try revealControl(resume, app)
            XCTAssertTrue(resume.isEnabled)
            try audit(app, context.phase + "-fixed-mixed-accepted-before-explicit-continue")
            try tapButtonAfterAudit("library.photoBatch.resume." + batch, app)
        }
        for target in [local, remote] {
            let child = try requireSuccess(target, app)
            children[target.role] = try childID(child)
            try readFullText(child, expected: progress(target, succeeded: true), app: app)
        }
        XCTAssertEqual(Set(children.values).count, 3)
        let remoteRegistration = element("library.remote.photo.registration." + (try XCTUnwrap(children[remote.role])), app)
        try readFullText(remoteRegistration, expected: "過去の登録：過去の登録成功", app: app)
        try requireDuplicateSuppressed(app, identifier: "library.remote.photo.save." + (try XCTUnwrap(remote.remoteToken)))
        try audit(app, context.phase + "-mixed-native-results-and-no-duplicate")

        // An ordinary process replacement must display these exact three old
        // results. It cannot fabricate a new child/SDK request from a journal.
        app.terminate(); app.launch()
        try requireLibrary(app)
        for target in context.targets {
            let child = try requireSuccess(target, app)
            XCTAssertEqual(try childID(child), children[target.role])
            try readFullText(child, expected: progress(target, succeeded: true), app: app)
        }
        XCTAssertFalse(button("library.photoBatch.lookup", app).exists)
        for target in context.targets where target.batch != nil {
            XCTAssertFalse(button("library.photoBatch.resume." + (try XCTUnwrap(target.batch)), app).exists)
        }
        try audit(app, context.phase + "-relaunch-retains-exact-results-without-auto-add")
        attach(app, context.phase + "-photo-batch-final-results")
        app.terminate()
    }

    @MainActor private func photoContext(entry: String) throws -> PhotoUIExpected {
        let environment = ProcessInfo.processInfo.environment
        guard environment["FR_S31_PHOTO_BATCH_UI"] == "1" else { throw XCTSkip("Dedicated Photos product UI is not enabled") }
        let encoded = try XCTUnwrap(environment["FR_S31_PHOTO_BATCH_EXPECTED_JSON"])
        guard encoded.utf8.count <= 16_384 else { throw PhotoUIFailure.invalidContext }
        let value = try JSONDecoder().decode(PhotoUIExpected.self, from: Data(encoded.utf8))
        if value.entry != entry { throw XCTSkip("The other explicitly allocated entry is selected") }
        let actual = try XCTUnwrap(environment["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let requested = try XCTUnwrap(environment["FR_S31_PHOTO_BATCH_SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let nonce = try XCTUnwrap(environment["FR_S31_PHOTO_BATCH_NONCE"])
        let phase = try XCTUnwrap(environment["FR_S31_PHOTO_BATCH_PHASE"])
        let normal = UUID(uuidString: "E436C891-9574-42CE-9F29-6C6C1759438B")!
        let finalNormal = UUID(uuidString: "82CD3937-D91E-41D6-8907-3EA37EB7747B")!
        let maximum = UUID(uuidString: "EDAC8594-9259-4266-87DB-90000B5E558C")!
        guard actual == requested, UUID(uuidString: value.simulator) == actual,
              value.schema == "fr-s31-photo-batch-ui-v1", value.nonce == nonce, value.phase == phase,
              UUID(uuidString: value.storeUUID) != nil, isSHA256(value.manifestSHA256), value.targets.count == 3,
              Set(value.targets.map(\.role)) == ["single", "mixedLocal", "mixedRemote"],
              Set(value.targets.map(\.rendition)).count == 3, Set(value.targets.map(\.media)).count == 3,
              (actual == normal && phase == "normal" && entry == "manual" && nonce == "4de832b4-34b0-4a7a-a94a-1d6eb54f4868")
                || (actual == finalNormal && phase == "normal" && entry == "manual" && nonce == "5a0dfd38-7db4-4369-85cc-8104603487f5")
                || (actual == maximum && phase == "max" && entry == "accepted" && nonce == "4e72ae94-8b6b-4daa-9e06-03cbe1de7e8e")
        else { throw PhotoUIFailure.invalidContext }
        for target in value.targets {
            let suffix = target.role == "single" ? "s" : target.role == "mixedLocal" ? "l" : "r"
            guard target.capture == "ps-" + String(nonce.prefix(8)) + "-" + suffix,
                  UUID(uuidString: target.rendition) != nil, UUID(uuidString: target.media) != nil,
                  isSHA256(target.sha256), (target.remoteToken != nil) == (target.role == "mixedRemote"),
                  (target.batch != nil) == (entry == "accepted"), (target.child != nil) == (entry == "accepted")
            else { throw PhotoUIFailure.invalidContext }
        }
        if entry == "accepted" {
            guard Set(value.targets.compactMap(\.batch)).count == 2,
                  Set(value.targets.compactMap(\.child)).count == 3,
                  value.targets.allSatisfy({ UUID(uuidString: $0.batch ?? "") != nil && UUID(uuidString: $0.child ?? "") != nil })
            else { throw PhotoUIFailure.invalidContext }
        }
        return value
    }

    private let resumeExplanation = "続行は未着手の対象だけを開始します。開始予約や写真の登録意図が残る対象は、自動でも再起動後でも再追加しません。取消も既に開始した写真への追加を取り消しません。"
    private func saveExplanation(local: Int, remote: Int) -> String {
        "ローカル\(local)本とMacの記録\(remote)本、合計\(local + remote)本を対象にします。Macの記録の選択は写真への保存専用です。完全取得済みの軽量版だけを固定して写真への追加を要求します。最初の受付時にWi-Fi経路を確認します。受付後の端末内処理はオフラインでも続きます。撮影・保存・復旧中は未着手の処理を保持して待機します。要求の受付は写真への登録成功ではありません。"
    }
    private func progress(_ target: PhotoUIExpected.Target, succeeded: Bool) -> String {
        let photos = succeeded ? "過去の登録成功" : "未着手・待機中。再起動後は明示的な続行が必要です"
        let management = succeeded ? "開始予約の保存記録あり。追加結果が未確定なら自動で再追加しません"
            : "要求受付済み・未着手。撮影待機では媒体を保持し、再起動後は明示的な続行が必要です"
        return "対象：動画 \(target.capture)\n軽量版ID：\(target.rendition)\n取得：受付時の完全取得済み軽量版（現在の実媒体は開始時に再照合）\n写真：\(photos)\n管理：\(management)\n要求の受付・取得・写真の登録結果は別々の記録です。"
    }

    @MainActor private func requireLibrary(_ app: XCUIApplication) throws {
        let refresh = button("library.refresh", app)
        XCTAssertTrue(refresh.waitForExistence(timeout: 20))
        try wait("Ordinary shared product library must load", timeout: 20) {
            refresh.isEnabled && !self.element("library.loading", app).exists && !self.element("library.loadFailure", app).exists
        }
    }
    @MainActor private func openLocal(_ capture: String, _ app: XCUIApplication) throws {
        let item = element("library.item." + capture, app)
        let title = element("library.itemTitle." + capture, app)
        let expectedTitle = "動画 " + capture
        // At AX5 the card is taller than the viewport. Its native title is the
        // ordinary visible activation point of the same NavigationLink.
        try readFullText(title, expected: expectedTitle, app: app)
        try revealControl(title, app)
        attachGeometry(title, app, name: "photo-batch-exact-local-title-before-one-tap")
        XCTAssertEqual(title.label, expectedTitle)
        XCTAssertTrue(title.isEnabled && title.isHittable)
        XCTAssertGreaterThanOrEqual(item.frame.height, 44)
        title.tap()
        let identity = element("library.detailIdentity", app)
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertEqual(identity.label, expectedTitle)
    }
    @MainActor private func requireNewSaveAvailable(_ value: XCUIElement, _ app: XCUIApplication) throws {
        try revealControl(value, app)
        let evidence = XCTAttachment(string: metadata(value) + "\n"
            + (element("library.reason.saveToPhotos", app).exists ? element("library.reason.saveToPhotos", app).label : "noUnavailableReason"))
        evidence.name = "native-first-acceptance-path-availability"; evidence.lifetime = .keepAlways; add(evidence)
        try wait("The ordinary native Wi-Fi gate must allow the explicit new action; no injected fallback is permitted", timeout: 30) {
            value.exists && value.isEnabled
        }
        XCTAssertTrue(value.isHittable)
        requireMinimumButtonHeight(value)
    }
    @MainActor private func tapButtonAfterAudit(_ identifier: String, _ app: XCUIApplication, newSave: Bool = false) throws {
        // Audits may scroll/reflow the lazy library. Resolve the exact control
        // again through ordinary scrolling before its one explicit user tap.
        let value = button(identifier, app)
        if newSave { try requireNewSaveAvailable(value, app) }
        else {
            try revealControl(value, app)
            try wait("The exact audited action must still be enabled and hittable", timeout: 10) {
                value.exists && value.isEnabled && value.isHittable
            }
            requireMinimumButtonHeight(value)
        }
        attachGeometry(value, app, name: "photo-batch-post-audit-exact-control-before-one-tap")
        value.tap()
    }
    @MainActor private func requireMinimumButtonHeight(_ value: XCUIElement) {
        let frame = value.frame
        let rawHeight = frame.height
        let coordinateBound = frame.minY.ulp + frame.maxY.ulp
        let geometry = XCTAttachment(string: "frame=\(frame) rawHeight=\(rawHeight) minY=\(frame.minY) maxY=\(frame.maxY) minYULP=\(frame.minY.ulp) maxYULP=\(frame.maxY.ulp) coordinateBound=\(coordinateBound) adjustedHeight=\(rawHeight + coordinateBound) requiredHeight=44 coordinateBoundLimit=1e-8")
        geometry.name = "photo-batch-control-height-coordinate-representation"; geometry.lifetime = .keepAlways; add(geometry)
        XCTAssertTrue(rawHeight.isFinite && frame.minY.isFinite && frame.maxY.isFinite && coordinateBound.isFinite)
        XCTAssertGreaterThanOrEqual(coordinateBound, 0)
        XCTAssertLessThan(coordinateBound, 1e-8)
        XCTAssertGreaterThanOrEqual(rawHeight + coordinateBound, 44)
    }
    @MainActor private func requireDuplicateSuppressed(_ app: XCUIApplication, identifier: String) throws {
        let save = button(identifier, app)
        try revealControl(save, app)
        try wait("A successful or reclaimed copy must not remain eligible for another new addition", timeout: 20) { !save.isEnabled }
        XCTAssertTrue(save.isHittable)
    }
    @MainActor private func selectSwitchOnce(_ value: XCUIElement, _ app: XCUIApplication) throws {
        try revealControl(value, app)
        attachGeometry(value, app, name: "photo-batch-switch-before-one-control-tap")
        XCTAssertEqual(value.elementType, .switch)
        XCTAssertTrue(value.isEnabled && value.isHittable)
        XCTAssertEqual(value.value as? String, "0")
        // Tail73's actual 338pt AX row includes its label. The recording shows
        // the native switch at the trailing edge; the row's center hits text.
        // Use one ordinary tap inside that native track, not an AX-state write.
        let frame = value.frame
        let point = CGPoint(x: frame.maxX - 14, y: frame.midY)
        let evidence = XCTAttachment(string: "identifier=\(value.identifier) row=\(frame) viewport=\(viewport(app)) oneTapPoint=\(point) beforeValue=\(String(describing: value.value))")
        evidence.name = "photo-batch-native-switch-single-tap-coordinate"; evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertTrue(frame.contains(point) && viewport(app).contains(point))
        attach(app, "photo-batch-switch-before-single-trailing-control-tap")
        value.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -14, dy: 0)).tap()
        try wait("The single tap must actually select this exact native switch", timeout: 5) {
            value.exists && value.value as? String == "1"
        }
        attachGeometry(value, app, name: "photo-batch-switch-after-one-control-tap")
        XCTAssertEqual(value.value as? String, "1")
    }
    @MainActor private func childQuery(_ target: PhotoUIExpected.Target, _ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "library.photoBatch.child.", "対象：動画 " + target.capture, "軽量版ID：" + target.rendition))
    }
    @MainActor private func locateChild(_ target: PhotoUIExpected.Target, _ app: XCUIApplication) throws -> XCUIElement {
        let query = childQuery(target, app)
        let value = query.firstMatch
        try revealReadable(value, app)
        attachGeometry(value, app, name: "photo-batch-located-child")
        XCTAssertEqual(query.count, 1, "Full independent capture and rendition must identify one exact child")
        let id = try childID(value)
        if let expected = target.child { XCTAssertEqual(id, expected) }
        return value
    }
    @MainActor private func childID(_ child: XCUIElement) throws -> String {
        let prefix = "library.photoBatch.child."
        guard child.identifier.hasPrefix(prefix) else { throw PhotoUIFailure.unexpectedState }
        let raw = String(child.identifier.dropFirst(prefix.count))
        guard UUID(uuidString: raw) != nil else { throw PhotoUIFailure.unexpectedState }
        return raw
    }
    @MainActor private func requireSuccess(_ target: PhotoUIExpected.Target, _ app: XCUIApplication) throws -> XCUIElement {
        let child = try locateChild(target, app)
        try wait("Only an actual Photos success for this exact child satisfies the product flow", timeout: 45) {
            child.exists && self.normalized(child.label) == self.normalized(self.progress(target, succeeded: true))
        }
        return child
    }
    private func normalized(_ value: String) -> String { value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ") }
    private func isSHA256(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }

    @MainActor private func top(_ app: XCUIApplication) throws {
        guard isRootLibrary(app) else { throw PhotoUIFailure.unexpectedState }
        let camera = button("product.capture", app)
        for _ in 0..<96 {
            let area = viewport(app)
            if camera.exists && camera.isEnabled && camera.isHittable,
               camera.frame.minY >= area.minY - 2 && camera.frame.maxY <= area.maxY + 2 {
                attachGeometry(camera, app, name: "photo-batch-root-top-capture-marker")
                return
            }
            // Only positioning the root top uses a fast ordinary gutter flick.
            // Reading body endpoints keeps the finite, slow drag below.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = area.minX + min(8, area.width * 0.1)
            let start = origin.withOffset(CGVector(dx: x - app.frame.minX,
                dy: area.minY + area.height * 0.2 - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: x - app.frame.minX,
                dy: area.minY + area.height * 0.8 - app.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.1)
        }
        attachGeometry(camera, app, name: "photo-batch-root-top-marker-unreachable")
        attach(app, "photo-batch-root-top-marker-unreachable")
        throw PhotoUIFailure.unreachable
    }
    @MainActor private func isRootLibrary(_ app: XCUIApplication) -> Bool {
        let root = app.navigationBars.matching(NSPredicate(format: "identifier == %@", "ライブラリ")).firstMatch
        let detail = app.navigationBars.matching(NSPredicate(format: "identifier == %@", "動画の詳細")).firstMatch
        return root.exists && !detail.exists
    }
    @MainActor private func prepareRootSearchIfNeeded(_ value: XCUIElement, _ app: XCUIApplication) throws {
        guard isRootLibrary(app) else { return }
        if value.exists {
            let visible = value.frame.intersection(viewport(app))
            if !visible.isNull && visible.height > 0 && visible.width > 0 { return }
        }
        // A culled lazy row may be above the current viewport. Start from the
        // observed root marker rather than searching only toward the bottom.
        try top(app)
    }
    @MainActor private func viewport(_ app: XCUIApplication) -> CGRect {
        let scroll = app.scrollViews.firstMatch
        let area = (scroll.exists ? scroll.frame : app.frame).intersection(app.frame)
        let navigation = app.navigationBars.firstMatch
        let upper = max(area.minY, navigation.exists ? navigation.frame.maxY : area.minY)
        return CGRect(x: area.minX, y: upper, width: area.width, height: max(0, area.maxY - upper))
    }
    @MainActor private func revealControl(_ value: XCUIElement, _ app: XCUIApplication, minimumHeight: CGFloat = 44) throws {
        try prepareRootSearchIfNeeded(value, app)
        for _ in 0..<112 {
            let area = viewport(app)
            if value.exists {
                let frame = value.frame
                let visible = frame.intersection(area)
                if !visible.isNull && visible.height >= min(minimumHeight, frame.height) && value.isHittable {
                    attachGeometry(value, app, name: "photo-batch-control-ready-for-action-assertion")
                    return
                }
                // A partially visible target is moved farther into its visible
                // edge, never back past the opposite edge of the viewport.
                let delta: CGFloat
                if frame.minY < area.minY { delta = frame.minY - area.minY - 4 }
                else if frame.maxY > area.maxY { delta = frame.maxY - area.maxY + 4 }
                else { delta = frame.midY - area.midY }
                if abs(delta) < 2 {
                    attachGeometry(value, app, name: "photo-batch-control-not-hittable-inside-viewport")
                    throw PhotoUIFailure.unreachable
                }
                drag(app, delta: delta)
            } else { drag(app, delta: area.height * 0.6) }
        }
        attachGeometry(value, app, name: "photo-batch-unreachable-control-geometry")
        attach(app, "photo-batch-unreachable-element")
        throw PhotoUIFailure.unreachable
    }
    @MainActor private func revealReadable(_ value: XCUIElement, _ app: XCUIApplication) throws {
        try prepareRootSearchIfNeeded(value, app)
        for _ in 0..<112 {
            let area = viewport(app)
            if value.exists {
                let frame = value.frame
                let visible = frame.intersection(area)
                if !visible.isNull && visible.height >= min(1, frame.height) { return }
                let delta = frame.maxY <= area.minY ? frame.minY - area.minY - 4 : frame.maxY - area.maxY + 4
                drag(app, delta: delta)
            } else { drag(app, delta: area.height * 0.6) }
        }
        attachGeometry(value, app, name: "photo-batch-unreachable-text-geometry")
        attach(app, "photo-batch-unreachable-text")
        throw PhotoUIFailure.unreachable
    }
    @MainActor private func readFullText(_ value: XCUIElement, expected: String, app: XCUIApplication) throws {
        try revealReadable(value, app)
        attachGeometry(value, app, name: "photo-batch-fulltext-before-source-assertion")
        XCTAssertEqual(normalized(value.label), normalized(expected), "The complete visible source text must remain accessible")
        var first = false, last = false
        var observations: [String] = []
        for attempt in 0..<112 {
            let area = viewport(app), frame = value.frame
            first = first || (frame.minY >= area.minY - 2 && frame.minY < area.maxY)
            last = last || (frame.maxY <= area.maxY + 2 && frame.maxY > area.minY)
            observations.append("attempt=\(attempt) viewport=\(area) labelFrame=\(frame) first=\(first) last=\(last) label=\(value.label)")
            if first && last { break }
            let delta = !first ? frame.minY - area.minY - 4 : frame.maxY - area.maxY + 4
            drag(app, delta: delta)
        }
        let geometry = XCTAttachment(string: observations.joined(separator: "\n") + "\nexpectedCompleteSource=" + expected)
        geometry.name = "photo-batch-fulltext-ordinary-scroll-" + value.identifier
        geometry.lifetime = .keepAlways; add(geometry)
        XCTAssertEqual(normalized(value.label), normalized(expected))
        XCTAssertTrue(first && last, "Both ends of the whole label must enter the actual ordinary scroll viewport")
    }
    @MainActor private func drag(_ app: XCUIApplication, delta: CGFloat) {
        let area = viewport(app)
        guard area.height > 0 else { return }
        let distance = min(max(abs(delta), 32), area.height * 0.6)
        let x = area.minX + min(8, area.width * 0.1)
        let startY = area.minY + area.height * (delta > 0 ? 0.8 : 0.2)
        let endY = startY + (delta > 0 ? -distance : distance)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: endY - app.frame.minY))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }
    @MainActor private func wait(_ message: String, timeout: TimeInterval, predicate: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            XCTFail(message); throw PhotoUIFailure.unexpectedState
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
        attach(app, name + "-strict-audit-before")
        let previous = continueAfterFailure; continueAfterFailure = true
        defer { attach(app, name + "-strict-audit-after"); continueAfterFailure = previous }
        try app.performAccessibilityAudit(for: types) { issue in
            var lines = [issue.compactDescription, issue.detailedDescription, "auditType=\(issue.auditType.rawValue)"]
            if let associated = issue.element { lines += [self.metadata(associated), associated.debugDescription] }
            let evidence = XCTAttachment(string: lines.joined(separator: "\n"))
            evidence.name = name + "-unhandled-issue"; evidence.lifetime = .keepAlways; self.add(evidence)
            return false
        }
    }
    @MainActor private func metadata(_ value: XCUIElement) -> String {
        "identifier=\(value.identifier) frame=\(value.frame) enabled=\(value.isEnabled) hittable=\(value.isHittable) label=\(value.label)"
    }
    @MainActor private func attachGeometry(_ value: XCUIElement, _ app: XCUIApplication, name: String) {
        let navigation = app.navigationBars.firstMatch
        let scroll = app.scrollViews.firstMatch
        let description = "viewport=\(viewport(app)) app=\(app.frame) navigation=\(navigation.exists ? navigation.frame : .zero) scroll=\(scroll.exists ? scroll.frame : .zero)\n"
            + (value.exists ? metadata(value) : "elementAbsent")
        let evidence = XCTAttachment(string: description)
        evidence.name = name; evidence.lifetime = .keepAlways; add(evidence)
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}

private struct PhotoUIExpected: Codable {
    struct Target: Codable {
        let role: String
        let capture: String
        let rendition: String
        let media: String
        let sha256: String
        let remoteToken: String?
        let batch: String?
        let child: String?
    }
    let schema: String
    let nonce: String
    let simulator: String
    let phase: String
    let entry: String
    let storeUUID: String
    let manifestSHA256: String
    let targets: [Target]
}
private enum PhotoUIFailure: Error { case invalidContext, unreachable, unexpectedState }
