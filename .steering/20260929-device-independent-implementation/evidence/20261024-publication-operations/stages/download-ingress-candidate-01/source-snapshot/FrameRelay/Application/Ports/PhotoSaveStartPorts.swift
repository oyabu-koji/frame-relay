import Foundation
import Synchronization

/// Borrowed descriptors only. This does not own/close/reopen either FD. The
/// existing temporary owner retains them until the actual Photos completion.
nonisolated final class PhotoSaveLocalReadWitness: Equatable, Sendable {
    let fileDescriptor: Int32
    let directoryDescriptor: Int32
    let fingerprint: OriginalFileFingerprint
    private let active = Mutex(true)
    init(fileDescriptor: Int32, directoryDescriptor: Int32, fingerprint: OriginalFileFingerprint) {
        self.fileDescriptor = fileDescriptor; self.directoryDescriptor = directoryDescriptor; self.fingerprint = fingerprint
    }
    var isCurrent: Bool { active.withLock { $0 } }
    /// Revokes only this borrowed observation, never closes any descriptor.
    func invalidate() { active.withLock { $0 = false } }
    static func == (left: PhotoSaveLocalReadWitness, right: PhotoSaveLocalReadWitness) -> Bool { left === right }
}

/// This is process-local capture admission, never Wi-Fi or a storage receipt.
nonisolated protocol PhotoSaveCaptureStartPort: Sendable {
    func authorizeResume() -> CaptureMediaResumeAuthorization?
    /// Subscribe before inspecting admission. Values are wakeups; always read
    /// fresh state/authorization rather than treating a buffered value as a grant.
    func changes() -> AsyncStream<CaptureMediaAdmission.Snapshot>
}

nonisolated enum PhotoLibraryAddAttempt: Equatable, Sendable {
    case heldBeforeStart
    case completed(PhotoRegistrationResult)
}

nonisolated enum PhotoSaveStartDisposition: Equatable, Sendable {
    case started, heldBeforeStart, cancelledBeforeStart, refused
}

/// Prepared outside the writer. The only nested locks are writer -> capture ->
/// claim, followed by a short synchronous SDK registration. No task/await/hop,
/// file reading, hashing, callback or writer reentry belongs in that action.
nonisolated struct PhotoSaveStartAuthorization: Sendable {
    let store: any MediaOperationStorePort
    let capture: CaptureMediaResumeAuthorization?
    let claim: PhotoSaveDispatchClaim

    /// Old fake-only suites may explicitly implement a nil-capture witness.
    /// Native and the protocol default always refuse that input. Product
    /// composition supplies the shared capture port and never takes this path.
    var isLegacyTestInput: Bool { capture == nil }

    func perform(_ command: PhotoLibraryAddCommand,
                 action: @escaping @Sendable () -> Void) async -> PhotoSaveStartDisposition {
        guard let capture, let input = claim.dispatchInput(for: command.registration.intent) else { return .refused }
        let observed = Mutex<PhotoSaveStartDisposition>(.refused)
        let current = await store.performPhotoSaveIfCurrent(command) {
            let captured = capture.performPhotoStart {
                let value = claim.performIfPending(input: input, action: action)
                observed.withLock { $0 = value }
            }
            if captured == .held { observed.withLock { $0 = .heldBeforeStart } }
        }
        let actual = observed.withLock { $0 }
        // The synchronous SDK action already happened. A later transaction/
        // lock-cleanup failure cannot turn it into non-start or close its FD.
        if actual == .started { return .started }
        guard current else { return .refused }
        return actual
    }
}

/// Cancellation reaches only an exact live child. A started PhotoKit request
/// has no cancellation handle and must retain its owner until completion.
nonisolated protocol PhotoSavePendingCancellationPort: Sendable {
    func cancelBeforeSDKStart() async
    func stopForCapture() async -> Bool
}
