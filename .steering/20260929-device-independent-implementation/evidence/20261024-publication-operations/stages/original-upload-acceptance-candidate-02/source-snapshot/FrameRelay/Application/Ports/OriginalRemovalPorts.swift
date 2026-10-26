import Foundation

/// Supplied by the application owner after stopping actual SDK/OS users.
/// There is deliberately no default producer or positive implementation.
nonisolated struct OriginalRemovalQuiescence: Equatable, Sendable {
    let target: OriginalRemovalTarget
    let transport: TransportQuiescence
    let readers: AllReadersReleasedReceipt
    let transportFence: OriginalRemovalTransportFence?

    init(target: OriginalRemovalTarget, transport: TransportQuiescence, readers: AllReadersReleasedReceipt,
         transportFence: OriginalRemovalTransportFence? = nil) {
        self.target = target; self.transport = transport; self.readers = readers; self.transportFence = transportFence
    }
}

nonisolated protocol OriginalRemovalTerminationPort: Sendable {
    func stopForRemoval(_ target: OriginalRemovalTarget) async -> BackendOutcome<OriginalRemovalQuiescence>
}

/// Final writer fence. Hashing has already finished; only the bounded synchronous
/// descriptor check/unlink is permitted inside this transaction, without await.
nonisolated struct OriginalRemovalBoundary: Equatable, Sendable {
    let batch: OriginalRemovalBatch
    let target: OriginalRemovalTarget
    let intent: RemovalIntent
    let expectedRevision: UInt64
    let expectedInvalidation: InvalidationGeneration
    let expectedAccess: AccessGeneration
    let epoch: ReaderReconciliationEpoch
    let transportFence: OriginalRemovalTransportFence?

    init(batch: OriginalRemovalBatch, target: OriginalRemovalTarget, intent: RemovalIntent, expectedRevision: UInt64,
         expectedInvalidation: InvalidationGeneration, expectedAccess: AccessGeneration, epoch: ReaderReconciliationEpoch,
         transportFence: OriginalRemovalTransportFence? = nil) {
        self.batch = batch; self.target = target; self.intent = intent; self.expectedRevision = expectedRevision
        self.expectedInvalidation = expectedInvalidation; self.expectedAccess = expectedAccess; self.epoch = epoch
        self.transportFence = transportFence
    }
}

nonisolated protocol OriginalRemovalExecutionPort: Sendable {
    func removeOriginal(batch: OriginalRemovalBatch, target: OriginalRemovalTarget,
        evidence: CleanupEvidenceSelection?, quiescence: OriginalRemovalQuiescence)
        async -> BackendOutcome<RemovalResolutionReceipt>
    /// Observation only. A reserved, still-present original is not unlinked.
    func observeRemoval(_ intent: RemovalIntent) async -> BackendOutcome<RemovalResolutionReceipt>
}

/// A local factory-admission owner, separate from every invalidation barrier.
nonisolated struct OriginalRemovalAdmissionSeal: Equatable, Sendable {
    let batch: MediaOperationID
    let target: OriginalRemovalTarget
    let nonce: String

    func exactlyMatches(_ other: Self) -> Bool {
        PublicationStoreBoundary.exact(batch, other.batch) && PublicationStoreBoundary.exact(target, other.target)
            && nonce.utf8.elementsEqual(other.nonce.utf8)
    }
}

/// Constructed only from fresh SDK/OS observations and the exact durable row.
/// It permits new factories; it never restarts an old player or transport.
nonisolated struct OriginalRemovalAdmissionRelease: Equatable, Sendable {
    let seal: OriginalRemovalAdmissionSeal
    let epoch: ReaderReconciliationEpoch
    let access: AccessGeneration
    let invalidation: InvalidationGeneration
    let resolution: RemovalResolution?

    func validates(_ snapshot: OriginalStoreSnapshot) -> Bool {
        guard snapshot.reconciliationEpoch == epoch,
              let batch = snapshot.removalBatches.first(where: { PublicationStoreBoundary.exact($0.batch.operation, seal.batch) }),
              let row = batch.targets.first(where: { PublicationStoreBoundary.exact($0.target, seal.target) }),
              let state = snapshot.logicalOriginals.first(where: { PublicationStoreBoundary.exact($0.original, seal.target.original) }),
              state.accessGeneration == access, state.invalidationGeneration == invalidation,
              state.readersReleased(in: epoch) else { return false }
        switch row.status {
        case .notExecuted: return resolution == nil
        case .resolved(let observed): return resolution == observed
        case .unprocessed, .reserved: return false
        }
    }
}

/// Upload history only. S25 invalidation owns its separate rendition stop and
/// lease inventory; this legacy predicate is not an all-media removal proof.
nonisolated enum OriginalRemovalTransportHistory {
    static func neverStarted(_ original: OriginalContent, backend: BackendStoreSnapshot) -> Bool {
        backend.requests.filter { $0.target == .original(original) }.allSatisfy {
            $0.attempt == nil && $0.session == nil && $0.transport == .queued
        } && !backend.verifications.contains(where: { $0.expected.target == .original(original) })
    }

    /// S34-only admission: every same-original target, including rendition and
    /// prepared background work, must be unstarted. It never replaces S25's
    /// actual owner stop with an upload-history condition.
    static func neverStartedForRemoval(_ original: OriginalContent, backend: BackendStoreSnapshot) -> Bool {
        backend.requests.filter { $0.target.original == original }.allSatisfy {
            PublicationStoreBoundary.exact($0.target.original, original)
                && $0.attempt == nil && $0.session == nil && $0.transport == .queued
        } && !backend.verifications.contains(where: { $0.expected.target.original == original })
            && !backend.backgroundTasks.contains(where: { $0.intent.context.target.original == original })
    }

    /// Presentation hint only. Actual SDK owners and exact commits are checked
    /// again by the sealed producer and the final writer transaction.
    static func stoppedTasks(_ original: OriginalContent, backend: BackendStoreSnapshot) -> [TransportStopReceipt]? {
        let requests = backend.requests.filter { $0.target.original == original }
        let tasks = backend.backgroundTasks.filter { $0.intent.context.target.original == original }
        guard !tasks.isEmpty, let identity = backend.storeIdentity,
              requests.allSatisfy({ PublicationStoreBoundary.exact($0.target.original, original) }),
              tasks.allSatisfy({ PublicationStoreBoundary.exact($0.intent.context.target.original, original) }) else { return nil }
        var stops: [TransportStopReceipt] = []
        for request in requests {
            let matches = tasks.filter { PublicationStoreBoundary.exact($0.intent.context.operation, request.operation) }
            if request.attempt == nil, request.session == nil, request.transport == .queued, matches.isEmpty { continue }
            guard request.transport == .stopped, let attempt = request.attempt, matches.count == 1,
                  backend.registrations.contains(where: {
                      $0.isCommitted && PublicationStoreBoundary.exact($0.server.registration, request.registration)
                  }),
                  let task = matches.first, let binding = task.binding, let terminal = task.terminal,
                  let closed = task.ownerClosure, task.intent.context.storeIdentity == identity,
                  PublicationStoreBoundary.exact(task.intent.context.target, request.target),
                  PublicationStoreBoundary.exact(task.intent.context.registration, request.registration),
                  PublicationStoreBoundary.exact(task.intent.context.attempt, attempt),
                  PublicationStoreBoundary.exact(binding, terminal.binding), PublicationStoreBoundary.exact(binding, closed.binding),
                  closed.tasksJoined, closed.handlesClosed, !task.events.isEmpty else { return nil }
            switch task.intent.source {
            case .upload(let session, let lease, let source):
                guard PublicationStoreBoundary.exact(request.session, Optional(session)),
                      PublicationStoreBoundary.exact(lease.original, original),
                      PublicationStoreBoundary.exact(lease.operation, request.operation),
                      PublicationStoreBoundary.exact(closed.uploadSource, Optional(source)) else { return nil }
            case .download:
                // S23 has no protected download owner/source terminal producer.
                return nil
            }
            stops.append(.init(operation: request.operation, attempt: attempt, target: request.target, registration: request.registration))
        }
        guard stops.count == tasks.count,
              backend.verifications.filter({ $0.expected.target.original == original }).allSatisfy({ proof in
                  requests.contains { request in
                      PublicationStoreBoundary.exact(request.operation, proof.expected.operation)
                          && PublicationStoreBoundary.exact(request.target, proof.expected.target)
                          && PublicationStoreBoundary.exact(request.registration, proof.expected.registration)
                          && PublicationStoreBoundary.exact(request.session, proof.expected.session)
                          && request.transport == .stopped
                  }
              }) else { return nil }
        return stops
    }
}

/// Existing journal facts only. These values never add a persisted command or
/// claim that a resource has closed. Keeping exact mutations detects ABA edits.
nonisolated struct OriginalRemovalTransportJournalFact: Equatable, Sendable, Encodable {
    // Journal .request/.batch values must equal a new MediaRequest in
    // validateInitialRequest, so their waits Sets are necessarily empty.
    // Later waits are scalar .requestTransition(.wait) mutations.
    let mutation: BackendStoreMutation
    let commit: BackendCommitReceipt
}

nonisolated struct OriginalRemovalTransportInventory: Equatable, Sendable {
    let original: OriginalContent
    let epoch: ReaderReconciliationEpoch
    let storeIdentity: RegistrationStoreIdentity?
    let requests: [MediaRequest]
    let tasks: [BackgroundMediaTaskState]
    let verifications: [StoredVerificationEvidence]
    let registrations: [DeviceRegistration]
    let journal: [OriginalRemovalTransportJournalFact]

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = lhs.canonicalBytes, let right = rhs.canonicalBytes else { return false }
        return left == right
    }

    var canonicalBytes: Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(Payload(original: original, epoch: epoch, storeIdentity: storeIdentity,
            requests: requests.map(RequestPayload.init), tasks: tasks.map(TaskPayload.init),
            verifications: verifications, registrations: registrations, journal: journal))
    }

    nonisolated private struct Payload: Encodable {
        let original: OriginalContent
        let epoch: ReaderReconciliationEpoch
        let storeIdentity: RegistrationStoreIdentity?
        let requests: [RequestPayload]
        let tasks: [TaskPayload]
        let verifications: [StoredVerificationEvidence]
        let registrations: [DeviceRegistration]
        let journal: [OriginalRemovalTransportJournalFact]
    }

    /// Set iteration order is not part of a request's meaning. Every other
    /// field, including opaque UTF-8 spelling and observation, is retained.
    nonisolated private struct RequestPayload: Encodable {
        let operation: MediaOperationID; let target: MediaTarget; let purpose: MediaPurpose
        let registration: RegistrationIdentity; let expectedStartRevision: UInt64
        let intent: MediaUserIntent; let waits: [MediaWaitReason]; let transport: MediaTransportState
        let attempt: TransferAttemptID?; let remote: BackendOutcome<EvidenceID>; let session: UploadSessionID?
        let startCommitted: Bool; let playbackEnded: Bool; let hasReconciled: Bool
        let lastObservation: RemoteObservationGeneration?
        init(_ value: MediaRequest) {
            operation = value.operation; target = value.target; purpose = value.purpose; registration = value.registration
            expectedStartRevision = value.expectedStartRevision; intent = value.intent
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            waits = value.waits.sorted { (try? encoder.encode($0))?.lexicographicallyPrecedes((try? encoder.encode($1)) ?? Data()) == true }
            transport = value.transport; attempt = value.attempt; remote = value.remote; session = value.session
            startCommitted = value.startCommitted; playbackEnded = value.playbackEnded; hasReconciled = value.hasReconciled
            lastObservation = value.lastObservation
        }
    }

    nonisolated private struct TaskPayload: Encodable {
        let intent: BackgroundMediaTaskIntent; let binding: BackgroundMediaTaskBinding?
        let resumeRequested: Bool; let stopRequested: Bool
        let terminal: BackgroundMediaSDKTerminal?; let ownerClosure: BackgroundMediaOwnerClosure?
        let events: [OriginalRemovalTransportJournalFact]
        init(_ value: BackgroundMediaTaskState) {
            intent = value.intent; binding = value.binding; resumeRequested = value.resumeRequested; stopRequested = value.stopRequested
            terminal = value.terminal; ownerClosure = value.ownerClosure
            events = value.events.map { .init(mutation: $0.mutation, commit: $0.commit) }
        }
    }
}

nonisolated struct OriginalRemovalTransportFence: Equatable, Sendable {
    let seal: OriginalRemovalAdmissionSeal
    let inventory: OriginalRemovalTransportInventory
    /// All exact stopped requests, not one representative task's authority.
    let stops: [TransportStopReceipt]

    func validatesHistory(_ backend: BackendStoreSnapshot) -> Bool {
        guard PublicationStoreBoundary.exact(seal.target.original, inventory.original),
              inventory.storeIdentity == backend.storeIdentity, inventory.matchesProjection(backend) else { return false }
        if stops.isEmpty {
            return OriginalRemovalTransportHistory.neverStartedForRemoval(inventory.original, backend: backend)
                && backend.backgroundTasks.allSatisfy { $0.intent.context.target.original != inventory.original }
                && backend.requests.filter { $0.target.original == inventory.original }.allSatisfy {
                    $0.attempt == nil && $0.session == nil && $0.transport == .queued
                }
        }
        guard let actual = OriginalRemovalTransportHistory.stoppedTasks(inventory.original, backend: backend),
              PublicationStoreBoundary.exact(stops, actual) else { return false }
        // A durable stopped transition after ownerClosed is the producer's
        // post-release fact. Check its exact journal position, not caller counts.
        for task in inventory.tasks {
            guard let closed = task.events.last(where: { if case .ownerClosed = $0.change { return true }; return false }),
                  inventory.journal.contains(where: { fact in
                      guard fact.commit.committedRevision > closed.commit.committedRevision,
                            case .requestTransition(_, let operation, let target, let registration, .stopped(let receipt)) = fact.mutation.change else { return false }
                      return PublicationStoreBoundary.exact(operation, task.intent.context.operation)
                          && PublicationStoreBoundary.exact(target, task.intent.context.target)
                          && PublicationStoreBoundary.exact(registration, task.intent.context.registration)
                          && stops.contains(where: { PublicationStoreBoundary.exact($0, receipt) })
                  }) else { return false }
        }
        return true
    }
}

extension OriginalRemovalTransportInventory {
    nonisolated func matchesProjection(_ backend: BackendStoreSnapshot) -> Bool {
        let requests = backend.requests.filter { $0.target.original == original }
        let tasks = backend.backgroundTasks.filter { $0.intent.context.target.original == original }
        let proofs = backend.verifications.filter { $0.expected.target.original == original }
        let destinations = requests.map(\.registration.destination) + tasks.map(\.intent.context.registration.destination)
            + proofs.map(\.expected.registration.destination)
        let registrations = backend.registrations.filter { row in
            destinations.contains { PublicationStoreBoundary.exact($0, row.server.registration.destination) }
        }
        return self == .init(original: original, epoch: epoch, storeIdentity: backend.storeIdentity,
            requests: requests, tasks: tasks, verifications: proofs, registrations: registrations, journal: journal)
    }
}

/// A removal seal never starts/stops transport. It observes already confirmed
/// owners; unresolved work remains sealed until an exact resolved batch release.
nonisolated protocol OriginalRemovalBackgroundPort: Sendable {
    func sealForRemoval(_ seal: OriginalRemovalAdmissionSeal) async -> BackendOutcome<OriginalRemovalTransportFence>
    func releaseAfterRemoval(_ release: OriginalRemovalAdmissionRelease) async -> Bool
}
