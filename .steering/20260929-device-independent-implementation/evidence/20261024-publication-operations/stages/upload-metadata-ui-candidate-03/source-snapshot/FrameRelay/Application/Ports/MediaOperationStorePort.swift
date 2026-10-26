nonisolated enum BackendStoreChange: Equatable, Sendable, Codable {
    case registrationIntent(RegistrationIntent)
    case registration(RegistrationServerReceipt)
    case batch(TransferBatch)
    case request(command: MediaOperationID, value: MediaRequest)
    case verification(command: MediaOperationID, expected: RemoteOperationContext, evidence: VerificationEvidence)
    /// Confirmation and its sync outbox are one commit.
    case confirmation(ConfirmationIntent)
    /// Invalidation tombstone and its ACK outbox are one commit.
    case invalidation(InvalidationRecord, InvalidationPermit)
    case requestTransition(command: MediaOperationID, operation: MediaOperationID,
                           target: MediaTarget, registration: RegistrationIdentity, value: MediaRequestTransition)
    case publication(PublishedRenditionObservation)
    case delivered(BackendSyncDelivery)
    case distribution(MediaDistributionObservation)
    case temporary(command: MediaOperationID, value: TemporaryMediaChange)
    case photo(command: MediaOperationID, value: PhotoRegistrationChange)
    case photoBatch(command: MediaOperationID, value: PhotoSaveBatchChange)
    case backgroundTask(command: MediaOperationID, value: BackgroundMediaTaskChange)
    case remoteInventory(RemoteInventoryObservation)
    /// A metadata observation grants no distribution, confirmation or invalidation authority.
    case publicationManifest(PublicationManifestObservation)
    case personControl(MediaPersonControlPlan)
    // Keep sizeable registration/save evidence out of every enum copy's frame.
    indirect case originalUploadAcceptance(OriginalUploadAcceptancePlan)
    indirect case uploadMetadata(UploadMetadataChange)

    var key: BackendCommitKey {
        switch self {
        case .registrationIntent(let intent): .registrationIntent(intent.operation, intent.destination)
        case .registration(let receipt): .registration(receipt.intent.operation, receipt.registration)
        case .batch(let batch): batch.commitKey
        case .request(let command, let value): .request(command, value.target, value.registration)
        case .verification(let command, let expected, let evidence): .verification(command, evidence.id, expected)
        case .confirmation(let intent): intent.key
        case .invalidation(let record, _): record.key
        case .requestTransition(let command, let operation, let target, let registration, _):
            .requestTransition(command, operation, target, registration)
        case .publication(let value):
            .observedPublication(value.command, value.registration, value.rendition, value.observation)
        case .delivered(let value):
            .outboxDelivery(value.command, value.entry.commit.committedRevision, value.registration)
        case .distribution(let value):
            .distributionObservation(value.command, value.lease.id, value.observation)
        case .temporary(let command, let value): .temporary(command, value.id)
        case .photo(let command, let value): .photo(command, value.key)
        case .photoBatch(let command, let value): .photoBatch(command, value.batch)
        case .backgroundTask(let command, let value): .backgroundTask(command, value.intent.id)
        case .remoteInventory(let value): value.key
        case .publicationManifest(let value): value.key
        case .personControl(let plan): .personControl(plan.parent)
        case .originalUploadAcceptance(let plan): .originalUploadAcceptance(plan.request.parent)
        case .uploadMetadata(let value): value.key
        }
    }
}

nonisolated struct BackendStoreMutation: Equatable, Sendable, Codable {
    let expectedRevision: UInt64
    let change: BackendStoreChange
    /// Optional only for journal compatibility and existing non-registration consumers.
    let expectedStoreIdentity: RegistrationStoreIdentity?

    init(expectedRevision: UInt64, change: BackendStoreChange,
         expectedStoreIdentity: RegistrationStoreIdentity? = nil) {
        self.expectedRevision = expectedRevision
        self.change = change
        self.expectedStoreIdentity = expectedStoreIdentity
    }
}

nonisolated enum BackendSyncEntry: Equatable, Sendable, Codable {
    case confirmation(ConfirmationRecord)
    case invalidation(InvalidationAcknowledgement)

    var commit: BackendCommitReceipt {
        switch self { case .confirmation(let value): value.commit; case .invalidation(let value): value.commit }
    }
    var registration: RegistrationIdentity {
        switch self {
        case .confirmation(let value): value.intent.playback.distribution.registration
        case .invalidation(let value): value.record.registration
        }
    }
}

nonisolated struct BackendStoreSnapshot: Equatable, Sendable {
    let revision: UInt64
    let registrationIntents: [CommittedRegistrationIntent]
    let registrations: [DeviceRegistration]
    let batches: [TransferBatch]
    let requests: [MediaRequest]
    let verifications: [StoredVerificationEvidence]
    let confirmations: [ConfirmationRecord]
    let invalidations: [InvalidationAcknowledgement]
    let outbox: [BackendSyncEntry]
    var storeIdentity: RegistrationStoreIdentity? = nil
    var publications: [StoredPublication] = []
    var confirmationStates: [ConfirmationState] = []
    var deliveries: [BackendSyncDelivery] = []
    var distributionObservations: [StoredMediaDistributionObservation] = []
    var temporaryMedia: [TemporaryMediaState] = []
    var photoRegistrations: [PhotoRegistrationRecord] = []
    var photoSaveBatches: [PhotoSaveBatchRecord] = []
    var backgroundTasks: [BackgroundMediaTaskState] = []
    var remoteInventory: [StoredRemoteInventoryPage] = []
    var publicationManifests: [StoredPublicationManifest] = []
    var personControls: [StoredMediaPersonControlPlan] = []
    var originalUploadAcceptances: [StoredOriginalUploadAcceptance] = []
    var uploadMetadataQueries: [CommittedUploadMetadataQuery] = []
    var uploadMetadataObservations: [StoredUploadMetadataObservation] = []
}

nonisolated enum BackendStoreLoadResult: Equatable, Sendable {
    case loaded(BackendStoreSnapshot)
    case unavailable(BackendFailure)
}

/// Single writer. Never report `committed` before the durable transaction completes.
/// Lookup reconciles a lost response for the exact mutation, including target and payload.
nonisolated protocol MediaOperationStorePort: Sendable {
    /// Explicit metadata commit before any registration credential is persisted.
    /// Does not increment the journal revision; compares identity and revision under the writer lock.
    func establishRegistrationIdentity(expectedRevision: UInt64,
        expectedIdentity: RegistrationStoreIdentity?) async throws -> RegistrationStoreIdentity
    func load() async -> BackendStoreLoadResult
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult
    /// Executes one short synchronous metadata dispatch under the same writer
    /// lock as person controls. Task allocation/credentials await outside; the
    /// action must not await, redispatch, reenter the writer, or read media.
    func performUploadMetadataIfCurrent(_ query: CommittedUploadMetadataQuery,
        action: @Sendable () -> Void) async -> Bool
}

nonisolated extension MediaOperationStorePort {
    func performUploadMetadataIfCurrent(_ query: CommittedUploadMetadataQuery,
        action: @Sendable () -> Void) async -> Bool { false }
    func establishRegistrationIdentity(expectedRevision: UInt64,
        expectedIdentity: RegistrationStoreIdentity?) async throws -> RegistrationStoreIdentity {
        throw BackendContractError.unavailable
    }
}

nonisolated extension CommittedPhotoRegistrationIntent {
    /// Reconstructs the exact persisted mutation, including its optional identity
    /// guard, for lost-response reconciliation after instance replacement.
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision,
            change: .photo(command: intent.operation, value: .intent(intent)),
            expectedStoreIdentity: expectedStoreIdentity)
    }
}

nonisolated extension StoredPhotoRegistrationResult {
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision, change: .photo(command: command, value: .result(result)),
            expectedStoreIdentity: expectedStoreIdentity)
    }
}

nonisolated extension StoredPhotoUsageRelease {
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision, change: .photo(command: command, value: .releaseUsage(release)),
            expectedStoreIdentity: expectedStoreIdentity)
    }
}

nonisolated extension StoredPhotoUsageTerminal {
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision, change: .photo(command: command, value: .terminal(terminal)),
            expectedStoreIdentity: expectedStoreIdentity)
    }
}

nonisolated extension StoredPhotoTerminalUsageRelease {
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision,
            change: .photo(command: command, value: .releaseTerminalUsage(release)),
            expectedStoreIdentity: expectedStoreIdentity)
    }
}

nonisolated extension PhotoSaveBatchRecord {
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision, change: .photoBatch(command: command, value: .accept(batch)),
            expectedStoreIdentity: expectedStoreIdentity)
    }
}

nonisolated extension CommittedPhotoSaveBatchChild {
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision,
            change: .photoBatch(command: command, value: .beginChild(batch: batch, target: target)),
            expectedStoreIdentity: expectedStoreIdentity)
    }
}

nonisolated extension StoredPhotoSaveBatchNonProcessing {
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision,
            change: .photoBatch(command: command, value: .notProcessed(batch: batch, target: target, reason: reason)),
            expectedStoreIdentity: expectedStoreIdentity)
    }
}
