import XCTest

/// Ordinary App composition over a separately seeded normal root. No App
/// launch flags, injected transport, media download or confirmation action.
final class PublicationFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testPublicationVersionsAvailabilityAndHistoricalIsolationSurviveRelaunch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["FR_S28_PUBLICATION_UI"] == "1" else {
            throw XCTSkip("Dedicated publication normal root is not enabled")
        }
        let nonce = try XCTUnwrap(environment["FR_S28_PUBLICATION_NONCE"])
        let requested = try XCTUnwrap(environment["FR_S28_PUBLICATION_SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let actual = try XCTUnwrap(environment["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let dedicated = UUID(uuidString: "8D2B4837-8EC9-4A8B-9511-6914BFD0EE85")!
        XCTAssertEqual(UUID(uuidString: nonce)?.uuidString.lowercased(), nonce)
        guard requested == dedicated, actual == dedicated else { throw PublicationUIFailure.wrongEnvironment }
        let context = XCTAttachment(string: "nonce=\(nonce) simulator=\(dedicated.uuidString)\nSynthetic metadata only. Native App reads the common writer. Unit VERIFY checks immutable metadata, real original/sentinel bytes, independent reopen and zero readers. No formal Rec709 producer, positive media dispatch, Photos or device acceptance is asserted.")
        context.name = "publication-bound-context"; context.lifetime = .keepAlways; add(context)
        let prefix = "s28p-" + nonce
        let app = XCUIApplication(); app.launch()
        try assertLocalAndRemotePublications(app, prefix: prefix)
        app.terminate(); app.launch()
        try assertLocalAndRemotePublications(app, prefix: prefix)
        try requireLibrary(app)
    }

    @MainActor private func assertLocalAndRemotePublications(_ app: XCUIApplication, prefix: String) throws {
        try requireLibrary(app)
        try top(app)
        let local = prefix + "-local"
        try read("library.itemPublication." + local,
            expected: publicationText(id: "00000000-0000-4000-8000-000000001011", version: 1, pending: false), app)
        try read("library.itemRetrieval." + local,
            expected: "端末内の軽量版の取得記録なし・オフライン再生不可", app)
        try audit(app, "local-publication-and-unavailable-offline")
        try top(app)
        try itemTarget(local, app).tap()
        let identity = element("library.detailIdentity", app)
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertEqual(identity.label, "動画 " + local)
        let publication = element("library.status.publication", app)
        try revealText(publication, app)
        for fragment in ["公開版ID：00000000-0000-4000-8000-000000001011", "公開世代：1", "観測版：1",
                         "失効世代：0", "媒体形式：video/quicktime", "最後の照合時に置換待ちなし"] {
            XCTAssertTrue(publication.label.contains(fragment), "Preserve complete publication detail: " + fragment)
        }
        try audit(app, "local-detail-publication")
        let retrieval = element("library.status.retrieval", app)
        try revealText(retrieval, app)
        XCTAssertTrue(retrieval.label.contains("端末内の軽量版の取得記録なし・オフライン再生不可"))
        let confirmation = element("library.status.confirmation", app)
        try revealText(confirmation, app)
        XCTAssertTrue(confirmation.label.contains("現在の記録版の明示確認なし"))
        XCTAssertFalse(confirmation.label.contains("有効な明示確認の保存記録あり"))
        try audit(app, "local-detail-no-generated-confirmation")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        try requireLibrary(app)

        try assertRemote(app, capture: prefix + "-remote-pending",
            publication: publicationText(id: "00000000-0000-4000-8000-000000002022", version: 2, pending: true),
            retrieval: "端末内の軽量版の取得記録なし・オフライン再生不可", name: "remote-current-v2-pending")
        try assertRemote(app, capture: prefix + "-remote-unpublished",
            publication: "最後の照合では公開版なし（観測版：0・失効世代：0）",
            retrieval: "最後の照合では公開版なし・取得や再生の利用可否は要照合です", name: "remote-unpublished")
        try assertRemote(app, capture: prefix + "-remote-history",
            publication: "公開版の保存記録なし（未照合を含む）",
            retrieval: "端末内の軽量版の取得記録なし・オフライン再生不可", name: "remote-historical-registration-isolated")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label CONTAINS %@", "library.remote.publication.",
            "00000000-0000-4000-8000-000000009099")).firstMatch.exists)
    }

    @MainActor private func assertRemote(_ app: XCUIApplication, capture: String,
        publication: String, retrieval: String, name: String) throws {
        try top(app)
        let title = app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label == %@", "library.remote.title.", "動画 " + capture)).firstMatch
        try revealText(title, app)
        let identifier = title.identifier
        XCTAssertTrue(identifier.hasPrefix("library.remote.title."))
        let token = String(identifier.dropFirst("library.remote.title.".count))
        try read("library.remote.date." + token, expected: "撮影日時不明", app)
        try read("library.remote.publication." + token, expected: publication, app)
        try audit(app, name + "-publication")
        try read("library.remote.retrieval." + token, expected: retrieval, app)
        try read("library.remote.media." + token,
            expected: "軽量版の取得・再生はまだ利用できません。保存記録の取得だけでは確認済みになりません。", app)
        try audit(app, name + "-retrieval-and-no-confirmation")
    }

    private func publicationText(id: String, version: UInt64, pending: Bool) -> String {
        "公開版の保存記録あり（最後に照合した版）\n公開版ID：\(id)"
            + "\n公開世代：\(version)・観測版：\(version)・失効世代：0\n媒体形式：video/quicktime"
            + (pending ? "\n置換待ち（現在の取得・再生可否とは別）" : "\n最後の照合時に置換待ちなし")
    }

    @MainActor private func requireLibrary(_ app: XCUIApplication) throws {
        let refresh = app.buttons["library.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            refresh.isEnabled && !self.element("library.loadFailure", app).exists
        }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 15) == .completed else {
            XCTFail("Normal library must finish loading without a read failure")
            throw PublicationUIFailure.unexpectedState
        }
        XCTAssertFalse(app.staticTexts["library.empty"].exists)
    }

    @MainActor private func read(_ identifier: String, expected: String, _ app: XCUIApplication) throws {
        let value = element(identifier, app)
        try revealText(value, app)
        // UILabel exposes each source newline as a single AX space. Keep every
        // other byte, word and punctuation exact, including the raw observed label.
        let expectedAccessibilityLabel = expected.replacingOccurrences(of: "\n", with: " ")
        let observation = XCTAttachment(string: metadata(value) + "\nexpectedCompleteSourceText=" + expected
            + "\nexpectedAccessibilityLabel=" + expectedAccessibilityLabel + "\nrawAccessibilityLabel=" + value.label)
        observation.name = "publication-complete-text"; observation.lifetime = .keepAlways; add(observation)
        XCTAssertEqual(value.label, expectedAccessibilityLabel, "Keep the complete AX text at the current system content size")
        XCTAssertGreaterThan(value.frame.width, 0)
        XCTAssertGreaterThan(value.frame.height, 0)
    }

    /// Reading a long noninteractive label needs a visible portion, even when
    /// Dynamic Type makes its intrinsic frame taller than the whole viewport.
    /// Controls use their own fresh isHittable target and an ordinary tap.
    @MainActor private func revealText(_ value: XCUIElement, _ app: XCUIApplication) throws {
        for _ in 0..<48 {
            if value.exists {
                let navigation = app.navigationBars.firstMatch
                let upper = navigation.exists ? navigation.frame.maxY + 2 : app.frame.minY + 2
                let viewport = CGRect(x: app.frame.minX, y: upper, width: app.frame.width,
                    height: max(0, app.frame.maxY - upper - 8))
                let visible = value.frame.intersection(viewport)
                if !visible.isNull && visible.height >= min(44, value.frame.height) { return }
                if value.frame.maxY <= upper { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        attach(app, "publication-unreachable-text")
        XCTFail("Cannot read " + value.identifier)
        throw PublicationUIFailure.unreachable
    }

    @MainActor private func top(_ app: XCUIApplication) throws {
        let camera = app.buttons["product.capture"]
        for _ in 0..<48 {
            if camera.exists, camera.isHittable, camera.frame.midY > app.navigationBars.firstMatch.frame.maxY + 2 { return }
            app.swipeDown()
        }
        throw PublicationUIFailure.unreachable
    }

    @MainActor private func itemTarget(_ capture: String, _ app: XCUIApplication) throws -> XCUIElement {
        for _ in 0..<48 {
            let item = element("library.item." + capture, app)
            if item.exists && item.isHittable { return item }
            let title = item.descendants(matching: .staticText)
                .matching(identifier: "library.itemTitle." + capture).firstMatch
            if item.exists && title.exists && title.isHittable { return title }
            app.swipeUp()
        }
        throw PublicationUIFailure.unreachable
    }

    @MainActor private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    @MainActor private func audit(_ app: XCUIApplication, _ name: String) throws {
        let types: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .sufficientElementDescription,
                                                .trait, .hitRegion, .elementDetection, .contrast]
        attach(app, "publication-accessibility-" + name + "-before")
        let oldPolicy = continueAfterFailure
        continueAfterFailure = true
        defer {
            attach(app, "publication-accessibility-" + name + "-after")
            continueAfterFailure = oldPolicy
        }
        try app.performAccessibilityAudit(for: types) { issue in
            var lines = [issue.compactDescription, issue.detailedDescription,
                         "auditType=\(issue.auditType.rawValue)", "uptime=\(ProcessInfo.processInfo.systemUptime)"]
            if let associated = issue.element { lines += [self.metadata(associated), associated.debugDescription] }
            else { lines.append("SDK supplied no associated element") }
            let value = XCTAttachment(string: lines.joined(separator: "\n"))
            value.name = "publication-accessibility-" + name + "-unhandled-issue"
            value.lifetime = .keepAlways; self.add(value)
            return false
        }
    }

    @MainActor private func metadata(_ value: XCUIElement) -> String {
        "identifier=\(value.identifier) type=\(value.elementType.rawValue) frame=\(value.frame) enabled=\(value.isEnabled) label=\(value.label)"
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = name; screen.lifetime = .keepAlways; add(screen)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}

private enum PublicationUIFailure: Error { case wrongEnvironment, unexpectedState, unreachable }
