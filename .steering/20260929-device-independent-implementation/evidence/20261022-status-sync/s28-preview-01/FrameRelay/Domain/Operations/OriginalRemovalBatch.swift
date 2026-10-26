/// A local, explicitly accepted operation. It is independent of registration
/// and never authorizes a later automatic retry of an unprocessed target.
nonisolated struct OriginalRemovalTarget: Equatable, Sendable, Codable {
    let original: OriginalContent
    let reference: CaptureOriginalReference
    let operation: MediaOperationID
}

nonisolated enum OriginalRemovalAuthorization: Equatable, Sendable, Codable {
    case cleanup
    case discardRiskAcknowledged(OriginalRemovalTarget)
}

nonisolated struct OriginalRemovalBatch: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let purpose: RemovalPurpose
    let targets: [OriginalRemovalTarget]
    let authorization: OriginalRemovalAuthorization

    init(operation: MediaOperationID, purpose: RemovalPurpose, targets: [OriginalRemovalTarget],
         authorization: OriginalRemovalAuthorization) throws {
        self.operation = operation; self.purpose = purpose
        self.targets = targets; self.authorization = authorization
        try validate()
    }

    func validate() throws {
        guard !operation.rawValue.isEmpty, !targets.isEmpty,
              Set(targets.map(\.original.capture)).count == targets.count,
              Set(targets.map(\.reference)).count == targets.count,
              Set(targets.map(\.operation)).count == targets.count,
              targets.allSatisfy({ !$0.operation.rawValue.isEmpty && $0.operation != operation }) else {
            throw BackendContractError.duplicateTarget
        }
        switch (purpose, authorization) {
        case (.cleanup, .cleanup): break
        case (.discard, .discardRiskAcknowledged(let target)):
            guard targets == [target] else { throw BackendContractError.identityMismatch }
        default: throw BackendContractError.identityMismatch
        }
    }

    func intent(for target: OriginalRemovalTarget) -> RemovalIntent {
        .init(operation: target.operation, original: target.original, purpose: purpose)
    }
}

nonisolated enum OriginalRemovalNonExecution: Equatable, Sendable, Codable {
    case ineligible, terminationUnconfirmed, identityMismatch, unavailable
}

nonisolated enum OriginalRemovalTargetStatus: Equatable, Sendable {
    case unprocessed
    case reserved(RemovalIntent)
    case notExecuted(OriginalRemovalNonExecution)
    case resolved(RemovalResolution)
}

nonisolated struct OriginalRemovalTargetRecord: Equatable, Sendable {
    let target: OriginalRemovalTarget
    var status: OriginalRemovalTargetStatus = .unprocessed
    var failure: BackendFailure? = nil
}

nonisolated struct OriginalRemovalBatchRecord: Equatable, Sendable {
    let batch: OriginalRemovalBatch
    let commit: OriginalStoreCommitReceipt
    var targets: [OriginalRemovalTargetRecord]
}
