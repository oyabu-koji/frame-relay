nonisolated struct OriginalReadLease: Equatable, Sendable, Codable {
    let id: ReadLeaseID
    let original: OriginalContent
    let operation: MediaOperationID
    let accessGeneration: AccessGeneration
    let epoch: ReaderReconciliationEpoch
}

/// Produced after the actual handle has closed, not after requesting cancellation.
nonisolated struct ReadReleaseReceipt: Equatable, Sendable { let lease: OriginalReadLease }

nonisolated struct AllReadersReleasedReceipt: Equatable, Sendable {
    let original: OriginalContent
    let accessGeneration: AccessGeneration
    let epoch: ReaderReconciliationEpoch
}

nonisolated struct TransportStopReceipt: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let attempt: TransferAttemptID
    let target: MediaTarget
    let registration: RegistrationIdentity
}

nonisolated struct TransportCompletionReceipt: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let attempt: TransferAttemptID
    let target: MediaTarget
    let registration: RegistrationIdentity
}

/// `neverStarted` is an authoritative operation-store reconciliation, not absence of a callback.
nonisolated enum TransportQuiescence: Equatable, Sendable {
    case neverStarted(MediaTarget)
    case stopped(TransportStopReceipt)

    var target: MediaTarget {
        switch self {
        case .neverStarted(let target): target
        case .stopped(let receipt): receipt.target
        }
    }
}

/// Snapshot of observed readers. A new acquisition invalidates every older all-released receipt.
nonisolated struct OriginalReadersState: Equatable, Sendable {
    let original: OriginalContent
    let epoch: ReaderReconciliationEpoch
    private(set) var generation: AccessGeneration
    private(set) var active: [ReadLeaseID: OriginalReadLease] = [:]
    private(set) var isReconciled = false

    init(original: OriginalContent, epoch: ReaderReconciliationEpoch, generation: AccessGeneration) {
        self.original = original
        self.epoch = epoch
        self.generation = generation
    }

    /// The adapter must enumerate outstanding OS tasks/read handles before providing this observation.
    mutating func reconcile(_ leases: [OriginalReadLease]) throws {
        guard !isReconciled, leases.allSatisfy({ $0.original == original && $0.epoch == epoch
            && $0.accessGeneration.rawValue <= generation.rawValue }),
              Set(leases.map(\.id)).count == leases.count else { throw BackendContractError.identityMismatch }
        active = Dictionary(uniqueKeysWithValues: leases.map { ($0.id, $0) })
        isReconciled = true
    }

    mutating func acquire(id: ReadLeaseID, operation: MediaOperationID) throws -> OriginalReadLease {
        guard isReconciled, active[id] == nil else { throw BackendContractError.wrongStage }
        let next = generation.rawValue.addingReportingOverflow(1)
        guard !next.overflow else { throw BackendContractError.staleGeneration }
        generation = AccessGeneration(rawValue: next.partialValue)
        let lease = OriginalReadLease(id: id, original: original, operation: operation,
                                      accessGeneration: generation, epoch: epoch)
        active[id] = lease
        return lease
    }

    mutating func observeRelease(_ receipt: ReadReleaseReceipt) throws {
        guard active[receipt.lease.id] == receipt.lease else { throw BackendContractError.identityMismatch }
        active.removeValue(forKey: receipt.lease.id)
    }

    var allReleased: AllReadersReleasedReceipt? {
        guard isReconciled, active.isEmpty else { return nil }
        return AllReadersReleasedReceipt(original: original, accessGeneration: generation, epoch: epoch)
    }

    func validates(_ receipt: AllReadersReleasedReceipt) -> Bool {
        allReleased == receipt
    }
}
