import Foundation

/// A current default-route observation used only for a new local Photos action.
/// It is never a media transport, VPN-underlay or redirect permit.
nonisolated protocol PhotoSaveStartNetworkPort: Sendable {
    func currentCondition() -> NetworkCondition
}

/// A live application capability. A durable child alone cannot recreate it.
nonisolated protocol PreparedPhotoSavePort: Sendable {
    func perform(_ child: CommittedPhotoSaveBatchChild) async -> BackendOutcome<PhotoRegistrationRecord>
    /// Only the owner may release its new use before perform has started.
    func releaseIfNotStarted() async -> Bool
}

nonisolated protocol PhotoSaveBatchExecutionPort: Sendable {
    func source(for target: LibraryRenditionTarget) async throws -> PhotoSaveSource
    func prepare(_ target: PhotoSaveBatchTarget) async throws -> any PreparedPhotoSavePort
    /// Local exact reconciliation only; this must never authorize or re-add.
    func reconcileKnownNonStarted(_ target: PhotoSaveBatchTarget) async
}

nonisolated extension PhotoSaveBatchExecutionPort {
    func reconcileKnownNonStarted(_ target: PhotoSaveBatchTarget) async {}
}

nonisolated extension PhotoSaveSource {
    func matches(_ registration: CommittedPhotoRegistrationIntent) -> Bool {
        PhotoSaveBatchValueValidation.exact(registration.intent.rendition, rendition)
            && PhotoSaveBatchValueValidation.exact(registration.intent.media, media)
            && PhotoSaveBatchValueValidation.exact(registration.intent.capturedAt, capturedAt)
            && (registration.expectedStoreIdentity == nil || registration.expectedStoreIdentity == storeIdentity)
            && PhotoSaveBatchValueValidation.exact(registration.mediaUse.lease.registration, self.registration)
            && registration.directoryIdentity == directoryIdentity && registration.fileIdentity == fileIdentity
    }
}

nonisolated struct PhotoSaveBatchRequest: Equatable, Sendable {
    let operation: MediaOperationID
    let targets: [LibraryRenditionTarget]
    let displayedRevision: UInt64
}
