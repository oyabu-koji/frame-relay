import Foundation

/// Status queries never prompt. Requests belong only to the corresponding
/// explicit save or result-reconciliation action, not capture startup.
nonisolated protocol PhotoLibraryAuthorizationPort: Sendable {
    func authorizationStatus(for access: PhotoLibraryAccess) async -> PhotoLibraryAuthorization
    func requestAuthorization(for access: PhotoLibraryAccess) async -> PhotoLibraryAuthorization
}

nonisolated struct PhotoLibraryAddCommand: Equatable, Sendable {
    let registration: CommittedPhotoRegistrationIntent
    let media: TemporaryLocalMedia

    init(registration: CommittedPhotoRegistrationIntent, media: TemporaryLocalMedia) throws {
        guard registration.isCommitted, media.handoff == registration.intent.handoff,
              media.url.isFileURL else { throw BackendContractError.identityMismatch }
        try registration.intent.validate()
        self.registration = registration
        self.media = media
    }
}

nonisolated struct PhotoLibraryLookupResult: Equatable, Sendable {
    let identifier: PhotoAssetIdentifier
    let authorization: PhotoLibraryAuthorization
    let presence: PhotoAssetPresence
}

nonisolated protocol PhotoLibraryPort: PhotoLibraryAuthorizationPort {
    /// The coordinator must confirm the exact intent mutation with lookupCommit
    /// before calling this method. The implementation waits for the real SDK
    /// completion even if the caller task is cancelled, and never moves the file.
    /// It preserves capturedAt and returns identifiers only for this add request.
    func add(_ command: PhotoLibraryAddCommand) async -> PhotoRegistrationResult
    /// Fetches only this exact persisted identifier. No name/date matching and
    /// no permission prompt; a missing asset is never permission to add again.
    func lookup(_ identifier: PhotoAssetIdentifier) async -> PhotoLibraryLookupResult
}

/// Reclaims only the exact persisted successful photo usage, after proving the
/// old SDK owner has terminated and the original temporary root is held. It must
/// never release unrelated usages or replay an unknown Photos addition.
nonisolated protocol PhotoTemporaryUsageRecoveryPort: Sendable {
    func recoverSuccessfulPhotoUsage(_ record: PhotoRegistrationRecord) async -> BackendOutcome<TemporaryMediaID>
}
