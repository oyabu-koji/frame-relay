nonisolated struct RegistrationCommand: Equatable, Sendable {
    let intent: RegistrationIntent
    let intentCommit: BackendCommitReceipt

    var isCommitted: Bool {
        intentCommit.matches(.registrationIntent(intent.operation, intent.destination),
                             revision: intentCommit.previousRevision)
    }
}

nonisolated struct RemoteStatusSnapshot: Equatable, Sendable {
    let operation: RemoteOperationResult
    let receivedRanges: [MediaByteRange]
    let verification: VerificationEvidence?
    let conversion: BackendOutcome<BackendJobID>
    let published: RenditionIdentity?
}

/// Only control-plane values cross this boundary. No media bytes, file URLs or automatic fetch action.
nonisolated protocol RemoteStatusPort: Sendable {
    func capabilities(for destination: DestinationIdentity) async -> BackendOutcome<BackendCapabilities>
    func register(_ command: RegistrationCommand) async -> BackendOutcome<RegistrationServerReceipt>
    func lookupRegistration(_ intent: RegistrationIntent) async -> BackendOutcome<RegistrationServerReceipt>
    func lookupOperation(_ context: RemoteOperationContext) async -> BackendOutcome<RemoteStatusSnapshot>
    func syncConfirmation(_ record: ConfirmationRecord) async -> BackendOutcome<MediaOperationID>
    func fetchInvalidations(_ registration: RegistrationIdentity) async -> BackendOutcome<[InvalidationRecord]>
    func acknowledge(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID>
}
