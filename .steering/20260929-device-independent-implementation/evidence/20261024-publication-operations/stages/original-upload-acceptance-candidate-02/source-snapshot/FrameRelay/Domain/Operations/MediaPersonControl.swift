import Foundation

nonisolated enum MediaPersonControlAction: String, Equatable, Sendable, Codable {
    case pause, cancel, resumeIntent
    var transition: MediaRequestTransition {
        switch self { case .pause: .pause; case .cancel: .cancel; case .resumeIntent: .resume }
    }
}
nonisolated enum MediaPersonControlScope: String, Equatable, Sendable, Codable { case single, allPause }

/// Fixed request identity, not permission to start a transport or local player.
nonisolated struct MediaPersonControlTarget: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let target: MediaTarget
    let purpose: MediaPurpose
    let registration: RegistrationIdentity
    let expectedStartRevision: UInt64
    let attempt: TransferAttemptID?
    var accessibilityToken: String { Data(operation.rawValue.utf8).base64EncodedString() }
    func matches(_ request: MediaRequest) -> Bool { MediaPersonControlValueValidation.exact(self, Self(request)) }
}
nonisolated extension MediaPersonControlTarget {
    init(_ request: MediaRequest) {
        self.init(operation: request.operation, target: request.target, purpose: request.purpose,
            registration: request.registration, expectedStartRevision: request.expectedStartRevision, attempt: request.attempt)
    }
}

nonisolated struct MediaPersonControlChild: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let target: MediaPersonControlTarget
}

/// The complete immutable parent and membership are one schema-7 journal event.
/// A revision-conflict retry changes only the mutation envelope's CAS revision.
nonisolated struct MediaPersonControlPlan: Equatable, Sendable, Codable {
    let parent: MediaOperationID
    let storeIdentity: RegistrationStoreIdentity
    let scope: MediaPersonControlScope
    let action: MediaPersonControlAction
    let children: [MediaPersonControlChild]

    init(parent: MediaOperationID, storeIdentity: RegistrationStoreIdentity, scope: MediaPersonControlScope,
         action: MediaPersonControlAction, children: [MediaPersonControlChild]) throws {
        self.parent = parent; self.storeIdentity = storeIdentity; self.scope = scope
        self.action = action; self.children = children
        try validate()
    }
    func validate() throws {
        try MediaPersonControlValueValidation.text(parent.rawValue)
        guard !children.isEmpty, scope != .single || children.count == 1,
              scope != .allPause || action == .pause else { throw BackendContractError.invalidValue }
        var commands: Set<MediaOperationID> = [parent], operations = Set<MediaOperationID>()
        for child in children {
            try MediaPersonControlValueValidation.text(child.command.rawValue)
            try MediaPersonControlValueValidation.text(child.target.operation.rawValue)
            if let attempt = child.target.attempt { try MediaPersonControlValueValidation.text(attempt.rawValue) }
            guard commands.insert(child.command).inserted, child.command != child.target.operation,
                  parent != child.target.operation, operations.insert(child.target.operation).inserted else {
                throw BackendContractError.duplicateTarget
            }
        }
        guard commands.isDisjoint(with: operations) else { throw BackendContractError.duplicateTarget }
    }
    private enum CodingKeys: String, CodingKey { case parent, storeIdentity, scope, action, children }
    init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(parent: value.decode(MediaOperationID.self, forKey: .parent),
            storeIdentity: value.decode(RegistrationStoreIdentity.self, forKey: .storeIdentity),
            scope: value.decode(MediaPersonControlScope.self, forKey: .scope),
            action: value.decode(MediaPersonControlAction.self, forKey: .action),
            children: value.decode([MediaPersonControlChild].self, forKey: .children))
    }
}

nonisolated enum MediaPersonControlNonProcessing: String, Equatable, Sendable, Codable {
    case missingRequest, identityChanged, completed, cancelled, playbackEnded, notPaused
    case registrationChanged, targetUnavailable
}
nonisolated enum MediaPersonControlDecision: Equatable, Sendable {
    case recorded
    case notProcessed(MediaPersonControlNonProcessing)
}
nonisolated struct MediaPersonControlChildRecord: Equatable, Sendable {
    let child: MediaPersonControlChild
    let decision: MediaPersonControlDecision
}
nonisolated struct StoredMediaPersonControlPlan: Equatable, Sendable {
    let plan: MediaPersonControlPlan
    let commit: BackendCommitReceipt
    let children: [MediaPersonControlChildRecord]
    var isCommitted: Bool {
        commit.matches(.personControl(plan.parent), revision: commit.previousRevision)
            && MediaPersonControlValueValidation.exact(commit.key, BackendCommitKey.personControl(plan.parent))
            && MediaPersonControlValueValidation.exact(children.map(\.child), plan.children)
    }
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision, change: .personControl(plan), expectedStoreIdentity: plan.storeIdentity)
    }
}

nonisolated enum MediaPersonControlValueValidation {
    static func text(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BackendContractError.invalidValue }
    }
    static func exact<T: Encodable>(_ left: T, _ right: T) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let lhs = try? encoder.encode(left), let rhs = try? encoder.encode(right) else { return false }
        return lhs == rhs
    }
}
