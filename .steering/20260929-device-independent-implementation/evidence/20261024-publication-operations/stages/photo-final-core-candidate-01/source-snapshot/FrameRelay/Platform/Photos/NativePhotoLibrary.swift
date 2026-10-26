import Foundation
import Photos
import Synchronization
import UniformTypeIdentifiers

/// Diagnostic codes only. Deliberately excludes descriptions, userInfo, paths,
/// filenames, and asset identifiers; these values are never registration proof.
nonisolated struct NativePhotoLibraryCompletionDiagnostic: Equatable, Sendable {
    let succeeded: Bool
    let errorDomain: String?
    let errorCode: Int?
    let underlyingErrorDomain: String?
    let underlyingErrorCode: Int?
}

/// PhotoKit is confined to this adapter. The coordinator owns intent/result
/// persistence and the temporary-media use; this adapter never releases it.
actor NativePhotoLibrary: PhotoLibraryPort {
    private let library = PHPhotoLibrary.shared()
    private let observeCompletion: (@Sendable (NativePhotoLibraryCompletionDiagnostic) -> Void)?

    init(observeCompletion: (@Sendable (NativePhotoLibraryCompletionDiagnostic) -> Void)? = nil) {
        self.observeCompletion = observeCompletion
    }

    func authorizationStatus(for access: PhotoLibraryAccess) async -> PhotoLibraryAuthorization {
        Self.authorization(PHPhotoLibrary.authorizationStatus(for: Self.accessLevel(access)))
    }

    func requestAuthorization(for access: PhotoLibraryAccess) async -> PhotoLibraryAuthorization {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: Self.accessLevel(access)) { status in
                continuation.resume(returning: Self.authorization(status))
            }
        }
    }

    /// No unguarded Native fallback exists, even for a historically committed
    /// intent. Old fake-only callers cannot turn this method into SDK authority.
    func add(_ command: PhotoLibraryAddCommand) async -> PhotoRegistrationResult {
        .init(intent: command.registration.intent, outcome: .notAttempted(.rejected))
    }

    func add(_ command: PhotoLibraryAddCommand, start: PhotoSaveStartAuthorization) async -> PhotoLibraryAddAttempt {
        let intent = command.registration.intent
        guard command.registration.isCommitted, command.media.handoff == intent.handoff,
              command.media.url.isFileURL else {
            return .completed(.init(intent: intent, outcome: .notAttempted(.invalidMedia)))
        }
        // Actor hop and permission inspection occur before consuming the final
        // permit. Only the synchronous performChanges registration is nested
        // inside writer -> capture -> the shared per-operation claim.
        let status = await authorizationStatus(for: .addOnly)
        guard status == .authorized else {
            let failure: PhotoLibraryFailure
            switch status {
            case .restricted: failure = .restricted
            case .denied, .notDetermined: failure = .authorizationRequired
            case .limited, .unknown, .authorized: failure = .inaccessible
            }
            return .completed(.init(intent: intent, outcome: .notAttempted(failure)))
        }
        guard !Task.isCancelled else {
            return .completed(.init(intent: intent, outcome: .notAttempted(.rejected)))
        }
        let identifier = PendingPhotoIdentifier(), completion = NativePhotoAddCompletion()
        let library = self.library, observeCompletion = self.observeCompletion
        let url = command.media.url, capturedAt = intent.capturedAt, contentType = command.media.contentType
        let dispatched = await start.perform(command) {
            library.performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                let type = contentType.flatMap { UTType(mimeType: $0) }
                options.contentType = type
                if let fileExtension = type?.preferredFilenameExtension {
                    options.originalFilename = UUID().uuidString + "." + fileExtension
                }
                request.creationDate = capturedAt
                request.addResource(with: .video, fileURL: url, options: options)
                let value = request.placeholderForCreatedAsset?.localIdentifier
                identifier.value.withLock { $0 = value.flatMap { try? PhotoAssetIdentifier(rawValue: $0) } }
            } completionHandler: { succeeded, error in
                let nsError = error as NSError?
                let underlying = nsError?.userInfo[NSUnderlyingErrorKey] as? NSError
                observeCompletion?(.init(succeeded: succeeded, errorDomain: nsError?.domain, errorCode: nsError?.code,
                    underlyingErrorDomain: underlying?.domain, underlyingErrorCode: underlying?.code))
                let value = identifier.value.withLock { $0 }
                let outcome: PhotoRegistrationOutcome = succeeded
                    ? .succeeded(localIdentifier: value) : Self.failedAddition(error, identifier: value)
                completion.complete(.init(intent: intent, outcome: outcome))
            }
        }
        switch dispatched {
        case .started:
            // Cancellation never resumes this continuation or closes the FD.
            // PhotoKit has no cancellation handle: only its actual callback ends it.
            return .completed(await completion.wait())
        case .heldBeforeStart: return .heldBeforeStart
        case .cancelledBeforeStart, .refused:
            return .completed(.init(intent: intent, outcome: .notAttempted(.rejected)))
        }
    }

    func lookup(_ identifier: PhotoAssetIdentifier) async -> PhotoLibraryLookupResult {
        let status = await authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return .init(identifier: identifier, authorization: status, presence: .unavailable)
        }
        // The identifier originated from this exact add or its durable record.
        // Date, filename, and other assets never participate in correspondence.
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier.rawValue], options: nil)
        let found = assets.firstObject?.localIdentifier == identifier.rawValue
        return .init(identifier: identifier, authorization: status, presence: found ? .present : .notFound)
    }

    private nonisolated static func accessLevel(_ access: PhotoLibraryAccess) -> PHAccessLevel {
        switch access { case .addOnly: .addOnly; case .readWrite: .readWrite }
    }

    private nonisolated static func authorization(_ status: PHAuthorizationStatus) -> PhotoLibraryAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        case .limited: .limited
        @unknown default: .unknown
        }
    }

    private nonisolated static func failedAddition(
        _ error: (any Error)?, identifier: PhotoAssetIdentifier?
    ) -> PhotoRegistrationOutcome {
        guard let error = error as NSError?, error.domain == PHPhotosErrorDomain else {
            return .unknown(localIdentifier: identifier)
        }
        // Only explicit rejections establish a non-addition. An interrupted or
        // internal operation (including an unfamiliar error) stays unresolved.
        switch error.code {
        case PHPhotosError.Code.accessRestricted.rawValue: return .failed(.restricted)
        case PHPhotosError.Code.accessUserDenied.rawValue: return .failed(.authorizationRequired)
        case PHPhotosError.Code.invalidResource.rawValue,
             PHPhotosError.Code.missingResource.rawValue: return .failed(.invalidMedia)
        case PHPhotosError.Code.changeNotSupported.rawValue,
             PHPhotosError.Code.requestNotSupportedForAsset.rawValue: return .failed(.rejected)
        default: return .unknown(localIdentifier: identifier)
        }
    }
}

/// PhotoKit invokes its two handlers on SDK queues. This checked Sendable
/// storage transfers only the immutable identifier, never a change request.
private nonisolated final class PendingPhotoIdentifier: Sendable {
    let value = Mutex<PhotoAssetIdentifier?>(nil)
}

/// The actual SDK callback may precede or follow waiter installation. A task's
/// cancellation cannot fabricate this completion. Resume occurs outside Mutex.
private nonisolated final class NativePhotoAddCompletion: Sendable {
    private struct State {
        var result: PhotoRegistrationResult?
        var continuation: CheckedContinuation<PhotoRegistrationResult, Never>?
    }
    private let state = Mutex(State())
    func complete(_ result: PhotoRegistrationResult) {
        let continuation = state.withLock { value -> CheckedContinuation<PhotoRegistrationResult, Never>? in
            guard value.result == nil else { return nil }
            value.result = result
            let continuation = value.continuation
            value.continuation = nil
            return continuation
        }
        continuation?.resume(returning: result)
    }
    func wait() async -> PhotoRegistrationResult {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { value -> PhotoRegistrationResult? in
                if let result = value.result { return result }
                value.continuation = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }
}
