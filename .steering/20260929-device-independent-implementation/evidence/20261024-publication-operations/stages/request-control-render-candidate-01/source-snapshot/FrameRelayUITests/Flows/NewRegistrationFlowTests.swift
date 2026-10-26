import XCTest

/// Uses the ordinary product composition. The separate Unit SEED/VERIFY bind
/// this repeated negative UI flow to one dedicated empty root and its preserved
/// foreign credentials. No launch arguments or product fixture flags are used.
final class NewRegistrationFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testExplicitInputCancellationHTTPRejectionDepartureAndRelaunch() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["FR_NEW_REGISTRATION_UI"] == "1" else { throw XCTSkip("Requires the separately prepared dedicated new-registration seed") }
        let token = try XCTUnwrap(env["FR_NEW_REGISTRATION_SEED_TOKEN"].flatMap(UUID.init(uuidString:)))
        let nonce = try XCTUnwrap(env["FR_NEW_REGISTRATION_SEED_NONCE"].flatMap(UUID.init(uuidString:)))
        let requested = try XCTUnwrap(env["FR_NEW_REGISTRATION_SIMULATOR_ID"].flatMap(UUID.init(uuidString:)))
        let actual = try XCTUnwrap(env["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        guard requested == UUID(uuidString: "5B5BD239-98C0-44E9-9EF3-29EB1B9A4EE5"), actual == requested, token != nonce else {
            XCTFail("Refuse this fixture-specific flow on another Simulator or without the bound seed context")
            return
        }
        let context = XCTAttachment(string: "token=\(token.uuidString.lowercased()) nonce=\(nonce.uuidString.lowercased()) simulator=\(requested.uuidString)\nReal HTTPS success/registration/quality is not asserted. Unit VERIFY checks exact preserved Keychain hashes and the empty writer.")
        context.name = "new-registration-bound-context"; context.lifetime = .keepAlways; add(context)
        let app = XCUIApplication()
        app.launch()
        try openConnection(app)
        try assertForeignEntry(app)
        attach(app, "new-registration-explanation")
        try openInput(app)
        try assertEmptyInput(app)
        try fill(app, origin: "https://previous-registration.invalid", nonce: nonce)
        let cancel = app.buttons["connection.new.cancel"]
        try reveal(cancel, app); cancel.tap()
        try assertForeignEntry(app)
        XCTAssertFalse(app.secureTextFields["connection.new.bearer"].exists)

        try openInput(app)
        try assertEmptyInput(app)
        try fill(app, origin: "http://registration.invalid", nonce: nonce)
        let register = app.buttons["connection.new.register"]
        try reveal(register, app)
        XCTAssertTrue(register.isEnabled)
        register.tap()
        let state = app.staticTexts["connection.state"]
        try reveal(state, app, preferUp: false)
        try wait("Plain HTTP must be refused locally and the operation must settle", app) {
            state.exists && state.label.contains("HTTPS")
        }
        try reveal(register, app)
        try wait("The refused operation must release its input controls", app) { register.isEnabled }
        XCTAssertFalse(app.staticTexts["connection.registered"].exists)
        try assertEmptyBearer(app)
        attach(app, "new-registration-http-refused-bearer-cleared")
        app.buttons["connection.close"].tap()
        try requireEmptyLibrary(app)

        try openConnection(app)
        try assertForeignEntry(app)
        try openInput(app)
        try assertEmptyInput(app)
        let bearer = app.secureTextFields["connection.new.bearer"]
        try reveal(bearer, app); bearer.tap(); bearer.typeText("synthetic-bootstrap-" + nonce.uuidString.lowercased())
        app.buttons["connection.close"].tap()
        try requireEmptyLibrary(app)
        try openConnection(app)
        try assertForeignEntry(app)
        try openInput(app)
        try assertEmptyInput(app)
        app.buttons["connection.close"].tap()
        app.terminate(); app.launch()
        try openConnection(app)
        try assertForeignEntry(app)
        try openInput(app)
        try assertEmptyInput(app)
        attach(app, "new-registration-relaunch-retains-old-binding-and-empty-input")
        app.buttons["connection.close"].tap()
        try requireEmptyLibrary(app)
    }

    @MainActor private func openConnection(_ app: XCUIApplication) throws {
        try requireEmptyLibrary(app)
        let open = app.buttons["product.connection"]
        guard open.waitForExistence(timeout: 10) else { throw NewRegistrationUIFailure.unexpectedState }
        open.tap()
        guard app.staticTexts["connection.state"].waitForExistence(timeout: 10) else { throw NewRegistrationUIFailure.unexpectedState }
    }

    @MainActor private func requireEmptyLibrary(_ app: XCUIApplication) throws {
        let refresh = app.buttons["library.refresh"]
        guard refresh.waitForExistence(timeout: 10) else { throw NewRegistrationUIFailure.unexpectedState }
        try wait("Dedicated root must remain an empty readable library", app) {
            refresh.isEnabled && app.staticTexts["library.empty"].exists
                && !app.descendants(matching: .any).matching(identifier: "library.loadFailure").firstMatch.exists
        }
    }

    @MainActor private func assertForeignEntry(_ app: XCUIApplication) throws {
        try connectionTop(app)
        let explanation = element("connection.new.explanation", app)
        try reveal(explanation, app)
        XCTAssertTrue(explanation.label.contains("以前の登録情報を保持したまま"))
        XCTAssertTrue(explanation.label.contains("以前の軽量版の確認・失効への応答は引き継ぎません"))
        let open = app.buttons["connection.new.open"]
        try reveal(open, app)
        guard open.isEnabled else { throw NewRegistrationUIFailure.unexpectedState }
        XCTAssertFalse(app.textFields["connection.origin"].exists)
        XCTAssertFalse(app.buttons["connection.continue"].exists)
        XCTAssertFalse(app.staticTexts["connection.registered"].exists)
    }

    @MainActor private func openInput(_ app: XCUIApplication) throws {
        let open = app.buttons["connection.new.open"]
        try reveal(open, app); open.tap()
        guard app.textFields["connection.new.origin"].waitForExistence(timeout: 5) else { throw NewRegistrationUIFailure.unexpectedState }
    }

    @MainActor private func assertEmptyInput(_ app: XCUIApplication) throws {
        try connectionTop(app)
        for (identifier, placeholder) in [("connection.new.origin", "HTTPSの接続先URL（パスなし）"), ("connection.new.destination", "接続先ID")] {
            let field = app.textFields[identifier]
            try reveal(field, app)
            XCTAssertTrue(field.exists)
            let value = field.value as? String ?? ""
            XCTAssertTrue(value.isEmpty || value == placeholder, "No previous connection input may survive cancel/departure")
        }
        try assertEmptyBearer(app)
    }

    @MainActor private func assertEmptyBearer(_ app: XCUIApplication) throws {
        let field = app.secureTextFields["connection.new.bearer"]
        try reveal(field, app)
        XCTAssertTrue(field.exists)
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == "認証トークン", "The bearer must be cleared before any later action")
    }

    @MainActor private func fill(_ app: XCUIApplication, origin: String, nonce: UUID) throws {
        try connectionTop(app)
        let originField = app.textFields["connection.new.origin"]
        try reveal(originField, app); originField.tap(); originField.typeText(origin)
        let destination = app.textFields["connection.new.destination"]
        try reveal(destination, app); destination.tap(); destination.typeText("9a3ba104-985f-4a2d-875d-d458258b9b6b")
        let bearer = app.secureTextFields["connection.new.bearer"]
        try reveal(bearer, app); bearer.tap(); bearer.typeText("synthetic-bootstrap-" + nonce.uuidString.lowercased())
    }

    @MainActor private func connectionTop(_ app: XCUIApplication) throws {
        try reveal(app.staticTexts["connection.state"], app, preferUp: false)
    }

    @MainActor private func reveal(_ value: XCUIElement, _ app: XCUIApplication, preferUp: Bool = true) throws {
        let content = app.scrollViews["connection.content"]
        guard content.waitForExistence(timeout: 5) else { throw NewRegistrationUIFailure.unexpectedState }
        for _ in 0..<36 {
            if value.exists {
                let top = max(app.navigationBars.firstMatch.frame.maxY, content.frame.minY)
                let bottom = content.frame.maxY
                if value.isHittable, value.frame.midY > top + 2, value.frame.midY < bottom - 2 { return }
                if value.frame.midY <= top + 2 { content.swipeDown(); continue }
            }
            if value.exists || preferUp { content.swipeUp() } else { content.swipeDown() }
        }
        attach(app, "new-registration-unreachable")
        let targetGeometry = value.exists ? "\(value.identifier) frame=\(value.frame) hittable=\(value.isHittable)" : "target absent"
        let keyboard = app.keyboards.firstMatch
        let keyboardGeometry = keyboard.exists ? "\(keyboard.frame)" : "absent"
        let diagnostic = XCTAttachment(string: "\(targetGeometry) content=\(content.frame) keyboard=\(keyboardGeometry)\n\(app.debugDescription)")
        diagnostic.name = "new-registration-unreachable-geometry"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        throw NewRegistrationUIFailure.unreachable
    }

    @MainActor private func wait(_ message: String, _ app: XCUIApplication, predicate: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: 10) == .completed else {
            XCTFail(message); throw NewRegistrationUIFailure.unexpectedState
        }
    }

    @MainActor private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

private enum NewRegistrationUIFailure: Error { case unexpectedState, unreachable }
