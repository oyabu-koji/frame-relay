@testable import FrameRelay

/// In-memory boundary fault model only; not a durable store or a product dependency.
actor FakeBackendStore: MediaOperationStorePort {
    enum Fault { case none, beforeCommit, afterCommit }
    private var fault: Fault = .none
    private var loadFailure: BackendFailure?
    private var revision: UInt64 = 0
    private var committed: [BackendCommitIdentity: (BackendStoreMutation, BackendCommitReceipt)] = [:]
    private var changes: [BackendStoreChange] = []
    private var registrationIntents: [CommittedRegistrationIntent] = []
    private var registrations: [DeviceRegistration] = []
    private var verifications: [StoredVerificationEvidence] = []
    private var confirmations: [ConfirmationRecord] = []
    private var invalidations: [InvalidationAcknowledgement] = []
    private var outbox: [BackendSyncEntry] = []

    func inject(_ fault: Fault) { self.fault = fault }
    func makeUnreadable(_ reason: BackendFailure) { loadFailure = reason }

    func load() async -> BackendStoreLoadResult {
        if let loadFailure { return .unavailable(loadFailure) }
        return .loaded(BackendStoreSnapshot(
            revision: revision,
            registrationIntents: registrationIntents, registrations: registrations,
            batches: changes.compactMap { if case .batch(let x) = $0 { return x }; return nil },
            requests: changes.compactMap { if case .request(_, let x) = $0 { return x }; return nil },
            verifications: verifications, confirmations: confirmations, invalidations: invalidations, outbox: outbox))
    }

    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if let pair = committed[mutation.change.key.operationIdentity] {
            return pair.0 == mutation ? .committed(pair.1) : .rejected(.identityMismatch)
        }
        if let loadFailure { return .unavailable(loadFailure) }
        guard mutation.expectedRevision == revision else { return .rejected(.revisionConflict) }
        if case .invalidation(let record, let permit) = mutation.change, permit.record != record {
            return .rejected(.identityMismatch)
        }
        if case .verification(_, let expected, let evidence) = mutation.change, evidence.context != expected {
            return .rejected(.identityMismatch)
        }
        if case .registration(let server) = mutation.change {
            guard server.intent.destination == server.registration.destination,
                  registrationIntents.contains(where: { $0.intent == server.intent }) else {
                return .rejected(.identityMismatch)
            }
        }
        let next = revision.addingReportingOverflow(1)
        guard !next.overflow else { return .rejected(.revisionConflict) }
        if fault == .beforeCommit { return .unknown }
        let receipt = BackendCommitReceipt(key: mutation.change.key, previousRevision: revision,
                                           committedRevision: next.partialValue)
        changes.append(mutation.change)
        switch mutation.change {
        case .registrationIntent(let intent):
            registrationIntents.append(.init(intent: intent, commit: receipt))
        case .registration(let server):
            guard let intent = registrationIntents.first(where: { $0.intent == server.intent }) else {
                return .rejected(.identityMismatch)
            }
            registrations.append(.init(server: server, intentCommit: intent.commit, commit: receipt))
        case .verification(let command, let expected, let evidence):
            verifications.append(.init(command: command, expected: expected, evidence: evidence, commit: receipt))
        case .confirmation(let intent):
            let record = ConfirmationRecord(intent: intent, commit: receipt)
            confirmations.append(record)
            outbox.append(.confirmation(record))
        case .invalidation(let record, _):
            let acknowledgement = InvalidationAcknowledgement(record: record, commit: receipt)
            invalidations.append(acknowledgement)
            outbox.append(.invalidation(acknowledgement))
        default: break
        }
        revision = next.partialValue
        committed[mutation.change.key.operationIdentity] = (mutation, receipt)
        return fault == .afterCommit ? .unknown : .committed(receipt)
    }

    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if let loadFailure { return .unavailable(loadFailure) }
        guard let pair = committed[mutation.change.key.operationIdentity] else { return .unknown }
        return pair.0 == mutation ? .committed(pair.1) : .rejected(.identityMismatch)
    }
}

actor FakeBackendOriginalAccess: OriginalAccessPort {
    let descriptor: OriginalDescriptor
    private var readers: OriginalReadersState

    init(descriptor: OriginalDescriptor, readers: OriginalReadersState) {
        self.descriptor = descriptor
        self.readers = readers
    }

    func describe(_ reference: CaptureOriginalReference) async -> OriginalDescriptionResult {
        reference == descriptor.reference ? .described(descriptor) : .unavailable(.inaccessible)
    }

    func acquireRead(_ original: OriginalContent, operation: MediaOperationID,
                     leaseID: ReadLeaseID) async -> BackendOutcome<OriginalReadLease> {
        guard descriptor.isTransferEligible, original == descriptor.original else { return .failed(.rejected) }
        do { return .succeeded(try readers.acquire(id: leaseID, operation: operation)) }
        catch { return .unknown }
    }

    func releaseRead(_ lease: OriginalReadLease) async -> BackendOutcome<ReadReleaseReceipt> {
        // A request cannot substitute for an observed closed handle.
        readers.active[lease.id] == lease ? .inProgress : .unknown
    }

    func observeHandleClosed(_ lease: OriginalReadLease) throws { try readers.observeRelease(.init(lease: lease)) }

    func reconcileReaders(_ original: OriginalContent) async -> BackendOutcome<AllReadersReleasedReceipt> {
        guard original == readers.original else { return .failed(.contentMismatch) }
        guard let receipt = readers.allReleased else { return .inProgress }
        return .succeeded(receipt)
    }
}

actor FakeBackendTransport: MediaTransportPort {
    private var requested: Set<TransferAttemptID> = []
    private var stopped: [TransferAttemptID: TransportStopReceipt] = [:]

    func upload(_ command: UploadMediaCommand) async -> BackendOutcome<RemoteOperationResult> {
        command.identitiesMatch ? .inProgress : .failed(.contentMismatch)
    }

    func retrieve(_ command: RetrieveMediaCommand) async -> BackendOutcome<TemporaryMediaReceipt> {
        // This fake does not implement the server's per-request publication transaction.
        command.identitiesMatch ? .unknown : .failed(.contentMismatch)
    }

    func requestStop(_ lease: MediaGateLease) async { requested.insert(lease.attempt) }
    func observeStop(_ lease: MediaGateLease) async -> BackendOutcome<TransportStopReceipt> {
        guard let receipt = stopped[lease.attempt] else { return .inProgress }
        guard receipt.operation == lease.operation, receipt.target == lease.target,
              receipt.registration == lease.registration else { return .failed(.contentMismatch) }
        return .succeeded(receipt)
    }

    func observeTaskStopped(_ receipt: TransportStopReceipt) { stopped[receipt.attempt] = receipt }
}

/// A downstream consumer with no file/Photos operations. Captures only ordering and handoff evidence.
actor FakeBackendRemovalConsumer: OriginalOperationOrderingPort {
    private var ordering: OriginalOperationOrdering

    init(ordering: OriginalOperationOrdering) { self.ordering = ordering }

    func reserveInvalidation(_ record: InvalidationRecord) async -> BackendOutcome<InvalidationPermit> {
        do { return .succeeded(try ordering.beginInvalidation(record)) } catch { return .inProgress }
    }

    func finishInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> {
        do { try ordering.finishInvalidation(acknowledgement); return .succeeded(acknowledgement.record.id) }
        catch { return .unknown }
    }

    func reserveRemoval(_ request: RemovalBoundaryRequest) async -> BackendOutcome<RemovalIntent> {
        do {
            try ordering.beginRemoval(request.intent, eligibility: request.eligibility, stopped: request.stopped,
                                      expectedTransport: request.expectedTransport, released: request.released,
                                      readers: request.readers)
            return .succeeded(request.intent)
        } catch { return .failed(.rejected) }
    }

    func reconcileRemoval(_ intent: RemovalIntent,
                          result: BackendOutcome<RemovalResolutionReceipt>) async -> BackendOutcome<RemovalIntent> {
        do {
            try ordering.reconcileRemoval(intent, result: result)
            return ordering.reservation == .idle ? .succeeded(intent) : .unknown
        } catch { return .unknown }
    }
}
