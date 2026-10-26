import Foundation
import Testing
@testable import FrameRelay

struct OriginalUploadAcceptanceTests {
    @Test func fixedRequestAndAlignedStatRoundTripWithoutTrimmingOrInventoryLimits() throws {
        let capture = "  opaque-\u{00e9}-" + String(repeating: "x", count: 2_100) + "  "
        let binding = try uploadAcceptanceDomainBinding(capture)
        let request = try uploadAcceptanceDomainRequest([.init(operation: .init(rawValue: "child-\u{00e9}"), binding: binding)])
        let plan = try OriginalUploadAcceptancePlan(request: request, presences: [.present(byteCount: binding.original.content.byteCount)])
        let encoded = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(OriginalUploadAcceptancePlan.self, from: encoded)
        #expect(OriginalUploadAcceptanceValueValidation.exact(plan, decoded))
        #expect(decoded.request.targets[0].binding.original.capture.rawValue.utf8.elementsEqual(capture.utf8))
        #expect(decoded.request.targets[0].binding.reference == binding.reference)
        #expect(decoded.request.registration == request.registration)
        #expect(decoded.request.targets[0].binding.saveCommit.previousRevision == 1)
        #expect(decoded.request.targets[0].binding.saveCommit.committedRevision == 2)
    }

    @Test func aliasesDuplicateMembershipAndUnalignedPlansAreParentErrors() throws {
        let a = try uploadAcceptanceDomainBinding("first"), b = try uploadAcceptanceDomainBinding("second")
        let first = OriginalUploadAcceptanceTarget(operation: .init(rawValue: "child-\u{00e9}"), binding: a)
        let second = OriginalUploadAcceptanceTarget(operation: .init(rawValue: "child-e\u{0301}"), binding: b)
        #expect(throws: BackendContractError.duplicateTarget) { try uploadAcceptanceDomainRequest([first, second], scope: .multiple) }
        #expect(throws: BackendContractError.duplicateTarget) {
            try uploadAcceptanceDomainRequest([.init(operation: .init(rawValue: "parent"), binding: a)])
        }
        let sameCapture = try uploadAcceptanceDomainBinding("first")
        #expect(throws: BackendContractError.duplicateTarget) {
            try uploadAcceptanceDomainRequest([first, .init(operation: .init(rawValue: "other"), binding: sameCapture)], scope: .multiple)
        }
        let referenceAlias = OriginalBinding(original: b.original, reference: a.reference, saveRecord: b.saveRecord, saveCommit: b.saveCommit)
        #expect(throws: BackendContractError.duplicateTarget) {
            try uploadAcceptanceDomainRequest([first, .init(operation: .init(rawValue: "other"), binding: referenceAlias)], scope: .multiple)
        }
        let composed = try uploadAcceptanceDomainBinding("capture-\u{00e9}")
        let decomposed = try uploadAcceptanceDomainBinding("capture-e\u{0301}")
        #expect(throws: BackendContractError.duplicateTarget) {
            try uploadAcceptanceDomainRequest([.init(operation: .init(rawValue: "a"), binding: composed),
                .init(operation: .init(rawValue: "b"), binding: decomposed)], scope: .multiple)
        }
        let request = try uploadAcceptanceDomainRequest([first])
        let intent = RegistrationIntent(operation: .init(rawValue: "register"), destination: .init(rawValue: "destination-\u{00e9}"))
        let server = RegistrationServerReceipt(intent: intent, registration: .init(destination: .init(rawValue: "destination-e\u{0301}"),
            id: .init(rawValue: "registration"), generation: .init(rawValue: 1)))
        let aliasRegistration = DeviceRegistration(server: server,
            intentCommit: .init(key: .registrationIntent(intent.operation, intent.destination), previousRevision: 0, committedRevision: 1),
            commit: .init(key: .registration(intent.operation, server.registration), previousRevision: 1, committedRevision: 2))
        #expect(aliasRegistration.isCommitted) // Legacy equality normalizes strings.
        #expect(throws: BackendContractError.notCommitted) {
            try OriginalUploadAcceptanceRequest(parent: request.parent, storeIdentity: request.storeIdentity,
                registration: aliasRegistration, scope: .single, targets: [first])
        }
        #expect(throws: BackendContractError.invalidValue) { try OriginalUploadAcceptancePlan(request: request, presences: []) }
        let plan = try OriginalUploadAcceptancePlan(request: request, presences: [.unknown])
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        object["presences"] = []
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: BackendContractError.invalidValue) { try JSONDecoder().decode(OriginalUploadAcceptancePlan.self, from: invalid) }
    }

    @Test func onlyTheNewExactReceiptCanCommitAnInitialMemberAndItStillCannotRun() throws {
        let binding = try uploadAcceptanceDomainBinding("saved")
        let request = try uploadAcceptanceDomainRequest([.init(operation: .init(rawValue: "child"), binding: binding)], parent: "parent-\u{00e9}")
        let plan = try OriginalUploadAcceptancePlan(request: request, presences: [.present(byteCount: binding.original.content.byteCount)])
        let initial = MediaRequest(operation: request.targets[0].operation, target: .original(binding.original), purpose: .upload,
            registration: request.registration.server.registration, expectedStartRevision: 41)
        for key in [BackendCommitKey.batch(.init(rawValue: request.parent.rawValue), [], request.registration.server.registration),
            .request(initial.operation, initial.target, initial.registration),
            .originalUploadAcceptance(.init(rawValue: "parent-e\u{0301}"))] {
            var value = initial
            #expect(throws: BackendContractError.notCommitted) {
                try value.acceptOriginalUploadAcceptanceCommit(.init(key: key, previousRevision: 41, committedRevision: 42), plan: plan)
            }
        }
        let receipt = BackendCommitReceipt(key: .originalUploadAcceptance(request.parent), previousRevision: 41, committedRevision: 42)
        var member = initial
        try member.acceptOriginalUploadAcceptanceCommit(receipt, plan: plan)
        #expect(member.startCommitted && !member.canRun && !member.hasReconciled)
        #expect(member.transport == .queued && member.intent == .running && member.waits.isEmpty)
        #expect(member.attempt == nil && member.session == nil && member.remote == .unknown && member.lastObservation == nil)
        var wrongRevision = MediaRequest(operation: initial.operation, target: initial.target, purpose: .upload,
            registration: initial.registration, expectedStartRevision: binding.saveCommit.committedRevision)
        #expect(throws: BackendContractError.notCommitted) { try wrongRevision.acceptOriginalUploadAcceptanceCommit(receipt, plan: plan) }
        var nonmember = MediaRequest(operation: .init(rawValue: "foreign-child"), target: initial.target, purpose: .upload,
            registration: initial.registration, expectedStartRevision: 41)
        #expect(throws: BackendContractError.notCommitted) { try nonmember.acceptOriginalUploadAcceptanceCommit(receipt, plan: plan) }
    }

    @Test func theImmutableInitialRecordReconstructsItsEnvelopeAfterCurrentIntentChanges() throws {
        let binding = try uploadAcceptanceDomainBinding("saved")
        let request = try uploadAcceptanceDomainRequest([.init(operation: .init(rawValue: "child"), binding: binding)])
        let plan = try OriginalUploadAcceptancePlan(request: request, presences: [.present(byteCount: binding.original.content.byteCount)])
        let receipt = BackendCommitReceipt(key: .originalUploadAcceptance(request.parent), previousRevision: 17, committedRevision: 18)
        var initial = MediaRequest(operation: request.targets[0].operation, target: .original(binding.original), purpose: .upload,
            registration: request.registration.server.registration, expectedStartRevision: 17)
        try initial.acceptOriginalUploadAcceptanceCommit(receipt, plan: plan)
        let child = OriginalUploadAcceptanceChild(target: request.targets[0], presence: plan.presences[0], decision: .accepted, initialRequest: initial)
        let record = StoredOriginalUploadAcceptance(plan: plan, children: [child], commit: receipt, expectedStoreIdentity: request.storeIdentity)
        var current = initial; current.pause(); current.setWait(.recording, active: true)
        #expect(record.isCommitted && record.children[0].initialRequest?.intent == .running && current.intent == .paused)
        #expect(record.mutation.expectedRevision == 17 && record.mutation.change == .originalUploadAcceptance(plan))
        #expect(record.mutation.expectedStoreIdentity == request.storeIdentity)
        let changed = StoredOriginalUploadAcceptance(plan: plan,
            children: [.init(target: child.target, presence: child.presence, decision: .accepted, initialRequest: current)],
            commit: receipt, expectedStoreIdentity: request.storeIdentity)
        #expect(!changed.isCommitted)
        let wrongStore = StoredOriginalUploadAcceptance(plan: plan, children: [child], commit: receipt,
            expectedStoreIdentity: .init(rawValue: UUID()))
        #expect(!wrongStore.isCommitted)
    }
}

nonisolated private func uploadAcceptanceDomainBinding(_ capture: String) throws -> OriginalBinding {
    let f = try CaptureFixture(clip: capture)
    let record = try syntheticResult(f)
    return .init(original: .init(capture: f.context.capture, generation: .init(rawValue: 1),
        content: try .init(byteCount: f.file.byteCount, algorithm: "sha256", digest: String(repeating: "a", count: 64))),
        reference: f.intent.original, saveRecord: record, saveCommit: f.receipt(f.token(4), previous: 1))
}
nonisolated private func uploadAcceptanceDomainRequest(_ targets: [OriginalUploadAcceptanceTarget],
    parent: String = "parent", scope: OriginalUploadAcceptanceScope = .single) throws -> OriginalUploadAcceptanceRequest {
    let intent = RegistrationIntent(operation: .init(rawValue: "register"), destination: .init(rawValue: "destination"))
    let server = RegistrationServerReceipt(intent: intent, registration: .init(destination: intent.destination,
        id: .init(rawValue: "registration"), generation: .init(rawValue: 1)))
    let registration = DeviceRegistration(server: server,
        intentCommit: .init(key: .registrationIntent(intent.operation, intent.destination), previousRevision: 0, committedRevision: 1),
        commit: .init(key: .registration(intent.operation, server.registration), previousRevision: 1, committedRevision: 2))
    return try .init(parent: .init(rawValue: parent), storeIdentity: .init(rawValue: UUID()), registration: registration, scope: scope, targets: targets)
}
