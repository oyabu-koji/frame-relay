/// Binding is immutable for an original. Content generation is allocated once,
/// independently of settings, store revisions and reader generations.
nonisolated struct OriginalBinding: Equatable, Sendable, Codable {
    let original: OriginalContent
    let reference: CaptureOriginalReference
    let saveRecord: RecordingResultRecord
    let saveCommit: RecordingCommitReceipt
}

/// Codable representation without changing the existing invalidation contract.
nonisolated struct OriginalInvalidationReservation: Equatable, Sendable, Codable {
    let id: InvalidationID
    let rendition: RenditionIdentity
    let registration: RegistrationIdentity
    let generation: InvalidationGeneration

    init(_ record: InvalidationRecord) {
        id = record.id; rendition = record.rendition
        registration = record.registration; generation = record.generation
    }
    var record: InvalidationRecord {
        .init(id: id, rendition: rendition, registration: registration, generation: generation)
    }
}

nonisolated enum OriginalStoreChange: Equatable, Sendable, Codable {
    case removalBatch(OriginalRemovalBatch)
    case removalIssue(batch: MediaOperationID, target: OriginalRemovalTarget, failure: BackendFailure)
    case removalNotExecuted(batch: MediaOperationID, target: OriginalRemovalTarget, reason: OriginalRemovalNonExecution)
    case bind(OriginalBinding)
    case acquire(OriginalReadLease)
    case release(OriginalReadLease)
    case reserveRemoval(RemovalIntent, expectedInvalidation: InvalidationGeneration, expectedAccess: AccessGeneration)
    case resolveRemoval(RemovalIntent, RemovalResolution)
    case reserveInvalidation(OriginalInvalidationReservation)
    case acquireMedia(MediaReadLease)
    case releaseMedia(MediaReadLease)
    case reconcileMedia(MediaReaderReconciliation)
    case reserveCleanup(RemovalIntent, CleanupEvidenceSelection, expectedInvalidation: InvalidationGeneration,
                        expectedAccess: AccessGeneration)
}

nonisolated struct OriginalStoreMutation: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let expectedRevision: UInt64
    let change: OriginalStoreChange
}

nonisolated struct OriginalStoreCommitReceipt: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let previousRevision: UInt64
    let committedRevision: UInt64
}

nonisolated enum OriginalStoreCommitResult: Equatable, Sendable {
    case committed(OriginalStoreCommitReceipt)
    case rejected(BackendContractError)
    case unavailable(BackendFailure)
}

nonisolated struct OriginalPersistentState: Equatable, Sendable {
    let binding: OriginalBinding
    let bindingCommit: OriginalStoreCommitReceipt
    var accessGeneration = AccessGeneration(rawValue: 0)
    var invalidationGeneration = InvalidationGeneration(rawValue: 0)
    var readers: [OriginalReadLease] = []
    var removal: RemovalIntent?
    /// The intent paired with removalResolution, reconstructed from the journal.
    /// A new reservation clears both; prior results remain in the journal.
    var resolvedRemoval: RemovalIntent?
    var removalResolution: RemovalResolution?
    var invalidation: OriginalInvalidationReservation?
}

/// One ordering authority for a content identity, with or without a local file.
/// The legacy binding-required snapshot is a projection, never another ledger.
nonisolated struct LogicalOriginalState: Equatable, Sendable {
    let original: OriginalContent
    var binding: OriginalBinding?
    var bindingCommit: OriginalStoreCommitReceipt?
    var accessGeneration = AccessGeneration(rawValue: 0)
    var invalidationGeneration = InvalidationGeneration(rawValue: 0)
    var readers: [OriginalReadLease] = []
    var mediaReaders: [MediaReadLease] = []
    var requiresMediaReconciliation = false
    var mediaReconciliation: MediaReaderReconciliation?
    var removal: RemovalIntent?
    var resolvedRemoval: RemovalIntent?
    var removalResolution: RemovalResolution?
    var invalidation: OriginalInvalidationReservation?

    var localProjection: OriginalPersistentState? {
        guard let binding, let bindingCommit else { return nil }
        return .init(binding: binding, bindingCommit: bindingCommit, accessGeneration: accessGeneration,
            invalidationGeneration: invalidationGeneration, readers: readers, removal: removal,
            resolvedRemoval: resolvedRemoval, removalResolution: removalResolution, invalidation: invalidation)
    }
    var readersReleased: Bool {
        readers.isEmpty && mediaReaders.isEmpty && (!requiresMediaReconciliation
            || mediaReconciliation?.accessGeneration == accessGeneration)
    }
    func readersReleased(in epoch: ReaderReconciliationEpoch?) -> Bool {
        readersReleased && (!requiresMediaReconciliation || (epoch != nil && mediaReconciliation?.epoch == epoch))
    }
}

/// Selects evidence for a new cleanup command; the writer rechecks its own
/// current records and configured supported schemas. This is not eligibility.
nonisolated struct CleanupEvidenceSelection: Equatable, Sendable, Codable {
    let registration: RegistrationIdentity
    let verificationCommand: MediaOperationID
    let confirmationOperation: MediaOperationID
}

nonisolated struct OriginalStoreSnapshot: Equatable, Sendable {
    let revision: UInt64
    let originals: [OriginalPersistentState]
    var logicalOriginals: [LogicalOriginalState] = []
    /// A new writer instance requires a new SDK/OS observation before a new ACK.
    var reconciliationEpoch: ReaderReconciliationEpoch? = nil
    var removalBatches: [OriginalRemovalBatchRecord] = []
}

nonisolated protocol OriginalStorePort: Sendable {
    func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot>
    /// Read-only, ephemeral inventory from this writer's existing journal.
    func loadRemovalTransportInventory(_ original: OriginalContent) async -> BackendOutcome<OriginalRemovalTransportInventory>
    /// Exact mutation replay returns the prior receipt. Same operation with a
    /// different payload or expected revision is rejected, never overwritten.
    func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult
    func lookupOriginalCommit(_ mutation: OriginalStoreMutation) async -> BackendOutcome<OriginalStoreCommitReceipt>
    func performRemovalBoundary(_ boundary: OriginalRemovalBoundary,
        effect: @Sendable () throws -> Void) async -> BackendOutcome<RemovalResolutionReceipt>
    /// Observation and its result commit share the writer lock. A stale full
    /// read can never commit notRemoved after another adapter has unlinked.
    func commitRemovalObservation(_ mutation: OriginalStoreMutation,
        check: @Sendable () throws -> Void) async -> OriginalStoreCommitResult
    func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID>
}

extension OriginalStorePort {
    nonisolated func loadRemovalTransportInventory(_ original: OriginalContent) async -> BackendOutcome<OriginalRemovalTransportInventory> { .unknown }
    nonisolated func lookupOriginalCommit(_ mutation: OriginalStoreMutation) async -> BackendOutcome<OriginalStoreCommitReceipt> { .unknown }
    nonisolated func performRemovalBoundary(_ boundary: OriginalRemovalBoundary,
        effect: @Sendable () throws -> Void) async -> BackendOutcome<RemovalResolutionReceipt> { .unknown }

    nonisolated func commitRemovalObservation(_ mutation: OriginalStoreMutation,
        check: @Sendable () throws -> Void) async -> OriginalStoreCommitResult { .unavailable(.inaccessible) }

    nonisolated func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> {
        .unknown
    }
}
