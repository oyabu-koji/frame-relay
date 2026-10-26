import Foundation

nonisolated enum OriginalUploadAcceptanceScope: String, Equatable, Sendable, Codable { case single, multiple }

/// Fixed before file observations begin. The binding is a saved fact, not a
/// fresh full-content verification or permission to read/copy/send the original.
nonisolated struct OriginalUploadAcceptanceTarget: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let binding: OriginalBinding
}

nonisolated struct OriginalUploadAcceptanceRequest: Equatable, Sendable, Codable {
    let parent: MediaOperationID
    let storeIdentity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    let scope: OriginalUploadAcceptanceScope
    let targets: [OriginalUploadAcceptanceTarget]

    init(parent: MediaOperationID, storeIdentity: RegistrationStoreIdentity, registration: DeviceRegistration,
         scope: OriginalUploadAcceptanceScope, targets: [OriginalUploadAcceptanceTarget]) throws {
        self.parent = parent; self.storeIdentity = storeIdentity; self.registration = registration
        self.scope = scope; self.targets = targets
        try validate()
    }

    func validate() throws {
        guard !parent.rawValue.isEmpty, !targets.isEmpty, scope != .single || targets.count == 1 else {
            throw BackendContractError.invalidValue
        }
        try OriginalUploadAcceptanceValueValidation.registration(registration)
        var commands: Set<MediaOperationID> = [parent]
        var captures = Set<CaptureID>(), references = Set<CaptureOriginalReference>()
        for target in targets {
            guard !target.operation.rawValue.isEmpty, commands.insert(target.operation).inserted,
                  captures.insert(target.binding.original.capture).inserted,
                  references.insert(target.binding.reference).inserted else { throw BackendContractError.duplicateTarget }
        }
        // Sets only detect collisions (including normalization aliases). Their
        // iteration order is never encoded into the immutable mutation payload.
    }

    private enum CodingKeys: String, CodingKey { case parent, storeIdentity, registration, scope, targets }
    init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(parent: value.decode(MediaOperationID.self, forKey: .parent),
            storeIdentity: value.decode(RegistrationStoreIdentity.self, forKey: .storeIdentity),
            registration: value.decode(DeviceRegistration.self, forKey: .registration),
            scope: value.decode(OriginalUploadAcceptanceScope.self, forKey: .scope),
            targets: value.decode([OriginalUploadAcceptanceTarget].self, forKey: .targets))
    }
}

/// A frozen stat observation. Present/size is not a new hash or an SDK permit.
nonisolated enum OriginalUploadFilePresence: Equatable, Sendable, Codable {
    case present(byteCount: UInt64)
    case missing, inaccessible, unknown
}

nonisolated struct OriginalUploadAcceptancePlan: Equatable, Sendable, Codable {
    let request: OriginalUploadAcceptanceRequest
    /// Exactly aligned with request.targets; no restat or silent shrinking on replay.
    let presences: [OriginalUploadFilePresence]

    init(request: OriginalUploadAcceptanceRequest, presences: [OriginalUploadFilePresence]) throws {
        self.request = request; self.presences = presences
        try validate()
    }
    func validate() throws {
        try request.validate()
        guard presences.count == request.targets.count else { throw BackendContractError.invalidValue }
    }
    private enum CodingKeys: String, CodingKey { case request, presences }
    init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(request: value.decode(OriginalUploadAcceptanceRequest.self, forKey: .request),
            presences: value.decode([OriginalUploadFilePresence].self, forKey: .presences))
    }
}

nonisolated enum OriginalUploadAcceptanceNonProcessing: String, Equatable, Sendable {
    case bindingUnavailable, bindingChanged, saveNotCompleted
    case removalReserved, invalidated, removed
    case fileMissing, fileInaccessible, fileUnknown, byteCountMismatch, alreadyRequested
}
nonisolated enum OriginalUploadAcceptanceDecision: Equatable, Sendable {
    case accepted
    case notProcessed(OriginalUploadAcceptanceNonProcessing)
}
nonisolated struct OriginalUploadAcceptanceChild: Equatable, Sendable {
    let target: OriginalUploadAcceptanceTarget
    let presence: OriginalUploadFilePresence
    let decision: OriginalUploadAcceptanceDecision
    /// The initial queue value stays immutable when backend.requests changes.
    let initialRequest: MediaRequest?
}

nonisolated struct StoredOriginalUploadAcceptance: Equatable, Sendable {
    let plan: OriginalUploadAcceptancePlan
    let children: [OriginalUploadAcceptanceChild]
    let commit: BackendCommitReceipt
    let expectedStoreIdentity: RegistrationStoreIdentity

    var isCommitted: Bool {
        guard expectedStoreIdentity == plan.request.storeIdentity,
              commit.matches(.originalUploadAcceptance(plan.request.parent), revision: commit.previousRevision),
              OriginalUploadAcceptanceValueValidation.exact(commit.key, BackendCommitKey.originalUploadAcceptance(plan.request.parent)),
              children.count == plan.request.targets.count, children.count == plan.presences.count else { return false }
        for i in children.indices {
            let child = children[i]
            guard OriginalUploadAcceptanceValueValidation.exact(child.target, plan.request.targets[i]),
                  child.presence == plan.presences[i] else { return false }
            switch child.decision {
            case .notProcessed:
                guard child.initialRequest == nil else { return false }
            case .accepted:
                var expected = MediaRequest(operation: child.target.operation, target: .original(child.target.binding.original),
                    purpose: .upload, registration: plan.request.registration.server.registration, expectedStartRevision: commit.previousRevision)
                do { try expected.acceptOriginalUploadAcceptanceCommit(commit, plan: plan) } catch { return false }
                guard let initial = child.initialRequest,
                      OriginalUploadAcceptanceValueValidation.exact(initial.operation, expected.operation),
                      OriginalUploadAcceptanceValueValidation.exact(initial.target, expected.target),
                      OriginalUploadAcceptanceValueValidation.exact(initial.registration, expected.registration),
                      initial == expected else { return false }
            }
        }
        return true
    }

    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision, change: .originalUploadAcceptance(plan), expectedStoreIdentity: expectedStoreIdentity)
    }
}

nonisolated enum OriginalUploadAcceptanceValueValidation {
    static func registration(_ value: DeviceRegistration) throws {
        guard value.isCommitted,
              exact(value.server.intent.destination, value.server.registration.destination),
              exact(value.intentCommit.key, BackendCommitKey.registrationIntent(value.server.intent.operation, value.server.intent.destination)),
              exact(value.commit.key, BackendCommitKey.registration(value.server.intent.operation, value.server.registration)) else {
            throw BackendContractError.notCommitted
        }
    }
    static func exact<T: Encodable>(_ left: T, _ right: T) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let lhs = try? encoder.encode(left), let rhs = try? encoder.encode(right) else { return false }
        return lhs == rhs
    }
}
