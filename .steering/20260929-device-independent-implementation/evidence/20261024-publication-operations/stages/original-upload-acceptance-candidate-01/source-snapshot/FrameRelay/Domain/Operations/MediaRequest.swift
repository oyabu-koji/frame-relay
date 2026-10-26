nonisolated enum MediaUserIntent: Equatable, Sendable, Codable { case running, paused, cancelled }
nonisolated enum MediaPurpose: Equatable, Sendable, Codable { case upload, download, playback }
nonisolated enum MediaWaitReason: Hashable, Sendable, Codable {
    case wiFiUnavailable, recording, saving, recovery, authentication, serverUnavailable
    case operatingSystem, targetUnavailable, queued
}
nonisolated enum MediaTransportState: Equatable, Sendable, Codable {
    case queued, active, stopRequested, stopped, completed
}

nonisolated struct RemoteOperationContext: Hashable, Sendable, Codable {
    let operation: MediaOperationID
    let registration: RegistrationIdentity
    let target: MediaTarget
    let session: UploadSessionID?
}

nonisolated struct RemoteOperationResult: Equatable, Sendable, Codable {
    let context: RemoteOperationContext
    /// Monotonic reconciliation generation for this operation, retained across recovery.
    /// Arrival order and wall-clock timestamps must not be substituted for this generation.
    let observation: RemoteObservationGeneration
    let result: BackendOutcome<EvidenceID>
}

/// Intent, environmental waits, local I/O, and the Mac's result are independent axes.
nonisolated struct MediaRequest: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let target: MediaTarget
    let purpose: MediaPurpose
    let registration: RegistrationIdentity
    let expectedStartRevision: UInt64
    private(set) var intent: MediaUserIntent = .running
    private(set) var waits: Set<MediaWaitReason> = []
    private(set) var transport: MediaTransportState = .queued
    private(set) var attempt: TransferAttemptID?
    private(set) var remote: BackendOutcome<EvidenceID> = .unknown
    private(set) var session: UploadSessionID?
    private(set) var startCommitted = false
    private(set) var playbackEnded = false
    private(set) var hasReconciled = false
    private(set) var lastObservation: RemoteObservationGeneration?

    init(operation: MediaOperationID, target: MediaTarget, purpose: MediaPurpose,
         registration: RegistrationIdentity, expectedStartRevision: UInt64) {
        self.operation = operation
        self.target = target
        self.purpose = purpose
        self.registration = registration
        self.expectedStartRevision = expectedStartRevision
    }

    var canRun: Bool {
        guard startCommitted, intent == .running, waits.isEmpty, !playbackEnded,
              transport != .completed, transport != .active, transport != .stopRequested,
              hasReconciled else { return false }
        switch remote {
        case .unknown, .succeeded: return false
        case .notExecuted, .inProgress, .failed: return true
        }
    }

    mutating func acceptStartCommit(_ receipt: BackendCommitReceipt) throws {
        guard receipt.matches(.request(operation, target, registration), revision: expectedStartRevision) else {
            throw BackendContractError.notCommitted
        }
        startCommitted = true
    }

    /// The new fixed acceptance has its own real receipt. It never borrows a
    /// legacy .batch/.request receipt or changes the initial queue's other axes.
    mutating func acceptOriginalUploadAcceptanceCommit(_ receipt: BackendCommitReceipt,
        plan: OriginalUploadAcceptancePlan) throws {
        try plan.validate()
        guard receipt.matches(.originalUploadAcceptance(plan.request.parent), revision: expectedStartRevision),
              OriginalUploadAcceptanceValueValidation.exact(receipt.key, BackendCommitKey.originalUploadAcceptance(plan.request.parent)),
              OriginalUploadAcceptanceValueValidation.exact(registration, plan.request.registration.server.registration),
              plan.request.targets.contains(where: {
                  OriginalUploadAcceptanceValueValidation.exact($0.operation, operation)
                      && OriginalUploadAcceptanceValueValidation.exact(MediaTarget.original($0.binding.original), target)
              }), self == MediaRequest(operation: operation, target: target, purpose: .upload,
                  registration: registration, expectedStartRevision: expectedStartRevision) else {
            throw BackendContractError.notCommitted
        }
        startCommitted = true
    }

    // Only TransferBatch calls this after the atomic fixed-target commit.
    fileprivate mutating func acceptBatchCommit() { startCommitted = true }

    mutating func setWait(_ reason: MediaWaitReason, active: Bool) {
        if active { waits.insert(reason) } else { waits.remove(reason) }
        if active, transport == .active { transport = .stopRequested }
    }

    mutating func pause() {
        guard intent != .cancelled, transport != .completed else { return }
        intent = .paused
        if transport == .active { transport = .stopRequested }
    }

    mutating func resume() throws {
        guard intent == .paused, !playbackEnded else { throw BackendContractError.wrongStage }
        intent = .running
    }

    mutating func cancel() {
        intent = .cancelled
        if transport == .active { transport = .stopRequested }
    }

    mutating func endPlayback() throws {
        guard purpose == .playback else { throw BackendContractError.wrongStage }
        playbackEnded = true
        if transport == .active { transport = .stopRequested }
    }

    mutating func beginAttempt(_ next: TransferAttemptID) throws {
        guard canRun, next != attempt else { throw BackendContractError.wrongStage }
        attempt = next
        transport = .active
        hasReconciled = false
    }

    mutating func observeStop(_ receipt: TransportStopReceipt) throws {
        guard receipt.operation == operation, receipt.attempt == attempt, receipt.target == target,
              receipt.registration == registration else { throw BackendContractError.identityMismatch }
        guard transport != .completed else { throw BackendContractError.wrongStage }
        transport = .stopped
    }

    /// Transport completion is not final-save or independent-verification success.
    mutating func observeCompletion(_ receipt: TransportCompletionReceipt) throws {
        guard receipt.operation == operation, receipt.attempt == attempt, receipt.target == target,
              receipt.registration == registration else { throw BackendContractError.identityMismatch }
        guard transport == .active || transport == .stopRequested else { throw BackendContractError.wrongStage }
        transport = .completed
    }

    mutating func reconcile(_ value: RemoteOperationResult) throws {
        guard value.context.operation == operation, value.context.registration == registration,
              value.context.target == target,
              session == nil || session == value.context.session else {
            throw BackendContractError.identityMismatch
        }
        if let lastObservation, value.observation.rawValue <= lastObservation.rawValue {
            throw BackendContractError.staleGeneration
        }
        // A failed query cannot erase a previously committed external success.
        if case .succeeded = remote {
            if case .succeeded(let next) = value.result, remote != .succeeded(next) {
                throw BackendContractError.identityMismatch
            }
            lastObservation = value.observation
            return
        }
        lastObservation = value.observation
        if let knownSession = value.context.session { session = knownSession }
        remote = value.result
        hasReconciled = true
    }
}

nonisolated struct BatchTarget: Hashable, Sendable, Codable {
    let operation: MediaOperationID
    let original: OriginalContent
}

nonisolated struct TransferBatch: Equatable, Sendable, Codable {
    let id: TransferBatchID
    let fixedTargets: [OriginalContent]
    private(set) var requests: [MediaRequest]
    let registration: RegistrationIdentity
    let expectedRevision: UInt64

    var commitKey: BackendCommitKey {
        .batch(id, requests.map { BatchTarget(operation: $0.operation, original: $0.target.original) }, registration)
    }

    init(id: TransferBatchID, originals: [OriginalDescriptor], operations: [MediaOperationID],
         onWiFi: Bool, registration: DeviceRegistration, expectedRevision: UInt64) throws {
        guard onWiFi else { throw BackendContractError.notOnWiFi }
        guard registration.isCommitted else { throw BackendContractError.notCommitted }
        guard !originals.isEmpty, originals.count == operations.count else {
            throw BackendContractError.invalidValue
        }
        guard Set(originals.map { $0.original.capture }).count == originals.count,
              Set(operations).count == operations.count else { throw BackendContractError.duplicateTarget }
        guard originals.allSatisfy(\.isTransferEligible) else { throw BackendContractError.ineligibleOriginal }
        self.id = id
        self.registration = registration.server.registration
        self.expectedRevision = expectedRevision
        fixedTargets = originals.map(\.original)
        requests = zip(originals, operations).map {
            MediaRequest(operation: $1, target: .original($0.original), purpose: .upload,
                         registration: registration.server.registration, expectedStartRevision: expectedRevision)
        }
    }

    mutating func acceptCommit(_ receipt: BackendCommitReceipt) throws {
        guard receipt.matches(commitKey, revision: expectedRevision) else {
            throw BackendContractError.notCommitted
        }
        for index in requests.indices { requests[index].acceptBatchCommit() }
    }

    mutating func pauseAll() {
        for index in requests.indices { requests[index].pause() }
    }

    /// Does not insert a new target into an accepted batch.
    mutating func update(_ request: MediaRequest) throws {
        guard let index = requests.firstIndex(where: { $0.operation == request.operation }),
              requests[index].target == request.target,
              requests[index].registration == request.registration,
              requests[index].purpose == request.purpose,
              requests[index].expectedStartRevision == request.expectedStartRevision else {
            throw BackendContractError.identityMismatch
        }
        requests[index] = request
    }
}
