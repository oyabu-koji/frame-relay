import Foundation
import Testing
@testable import FrameRelay

struct MediaPersonControlTests {
    @Test func immutablePlanRoundTripsWithoutNormalizingOpaqueIdentities() throws {
        let request = try personDomainRequest("request-\u{00e9}")
        let source = MediaPersonControlTarget(request)
        let plan = try MediaPersonControlPlan(parent: .init(rawValue: "person-\u{00e9}"),
            storeIdentity: .init(rawValue: UUID()), scope: .single, action: .resumeIntent,
            children: [.init(command: .init(rawValue: "child-\u{00e9}"), target: source)])
        let bytes = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(MediaPersonControlPlan.self, from: bytes)
        #expect(MediaPersonControlValueValidation.exact(plan, decoded))
        #expect(source.matches(request) && source.attempt == nil)
        let alias = try personDomainRequest("request-e\u{0301}")
        #expect(request.operation == alias.operation) // Swift equality alone is insufficient.
        #expect(!source.matches(alias))
        #expect(source.accessibilityToken != MediaPersonControlTarget(alias).accessibilityToken)
    }

    @Test func aFixedAllPauseCannotBecomeResumeOrReuseCanonicalAliasChildIDs() throws {
        let first = MediaPersonControlTarget(try personDomainRequest("first"))
        let second = MediaPersonControlTarget(try personDomainRequest("second"))
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        #expect(throws: BackendContractError.invalidValue) {
            try MediaPersonControlPlan(parent: .init(rawValue: "parent"), storeIdentity: identity,
                scope: .allPause, action: .resumeIntent, children: [.init(command: .init(rawValue: "child"), target: first)])
        }
        #expect(throws: BackendContractError.duplicateTarget) {
            try MediaPersonControlPlan(parent: .init(rawValue: "parent"), storeIdentity: identity, scope: .allPause,
                action: .pause, children: [.init(command: .init(rawValue: "child-\u{00e9}"), target: first),
                    .init(command: .init(rawValue: "child-e\u{0301}"), target: second)])
        }
        #expect(throws: BackendContractError.duplicateTarget) {
            try MediaPersonControlPlan(parent: .init(rawValue: "parent"), storeIdentity: identity, scope: .allPause,
                action: .pause, children: [.init(command: second.operation, target: first),
                    .init(command: .init(rawValue: "other-child"), target: second)])
        }
        #expect(throws: BackendContractError.invalidValue) {
            try MediaPersonControlPlan(parent: .init(rawValue: "parent"), storeIdentity: identity,
                scope: .single, action: .cancel, children: [])
        }
    }

    @Test func aStoredIntentDecisionIsNotAnSDKTerminalOrABorrowedReceipt() throws {
        let child = MediaPersonControlChild(command: .init(rawValue: "child"), target: .init(try personDomainRequest("request")))
        let plan = try MediaPersonControlPlan(parent: .init(rawValue: "parent-\u{00e9}"), storeIdentity: .init(rawValue: UUID()),
            scope: .single, action: .pause, children: [child])
        let receipt = BackendCommitReceipt(key: .personControl(plan.parent), previousRevision: 8, committedRevision: 9)
        let record = StoredMediaPersonControlPlan(plan: plan, commit: receipt, children: [.init(child: child, decision: .recorded)])
        #expect(record.isCommitted && record.mutation.expectedRevision == 8)
        let alias = StoredMediaPersonControlPlan(plan: plan,
            commit: .init(key: .personControl(.init(rawValue: "parent-e\u{0301}")), previousRevision: 8, committedRevision: 9),
            children: record.children)
        #expect(!alias.isCommitted)
        let status = MediaPersonControlResult.recorded(record, stops: [.init(child: child.command, disposition: .unknown)])
        #expect(status != .unknown) // Durable intent and unconfirmed actual stop remain separate.
    }

    @Test func unicodeRegistrationAndAttemptAliasesCannotMatchAFixedSource() throws {
        let original = try publicationOriginal("opaque-source")
        let registration = RegistrationIdentity(destination: .init(rawValue: "destination-\u{00e9}"),
            id: .init(rawValue: "registration-\u{00e9}"), generation: .init(rawValue: 1))
        var request = MediaRequest(operation: .init(rawValue: "request"), target: .original(original), purpose: .upload,
            registration: registration, expectedStartRevision: 3)
        try request.acceptStartCommit(.init(key: .request(request.operation, request.target, registration), previousRevision: 3, committedRevision: 4))
        try request.reconcile(.init(context: .init(operation: request.operation, registration: registration,
            target: request.target, session: nil), observation: .init(rawValue: 1), result: .notExecuted))
        try request.beginAttempt(.init(rawValue: "attempt-\u{00e9}"))
        let source = MediaPersonControlTarget(request)
        let attemptAlias = MediaPersonControlTarget(operation: source.operation, target: source.target, purpose: source.purpose,
            registration: source.registration, expectedStartRevision: source.expectedStartRevision, attempt: .init(rawValue: "attempt-e\u{0301}"))
        #expect(!attemptAlias.matches(request))
        let registrationAlias = MediaPersonControlTarget(operation: source.operation, target: source.target, purpose: source.purpose,
            registration: .init(destination: .init(rawValue: "destination-e\u{0301}"), id: .init(rawValue: "registration-e\u{0301}"),
                generation: registration.generation), expectedStartRevision: source.expectedStartRevision, attempt: source.attempt)
        #expect(!registrationAlias.matches(request))
    }
}

nonisolated private func personDomainRequest(_ operation: String) throws -> MediaRequest {
    .init(operation: .init(rawValue: operation), target: .original(try publicationOriginal("person-control-domain")),
        purpose: .upload, registration: .init(destination: .init(rawValue: "destination"),
            id: .init(rawValue: "registration"), generation: .init(rawValue: 1)), expectedStartRevision: 3)
}
