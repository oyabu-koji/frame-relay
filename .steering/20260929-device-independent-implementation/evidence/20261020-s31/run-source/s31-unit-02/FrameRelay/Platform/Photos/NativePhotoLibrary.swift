import Foundation
import Photos
import Synchronization
import UniformTypeIdentifiers

/// PhotoKit is confined to this adapter. The coordinator owns intent/result
/// persistence and the temporary-media use; this adapter never releases it.
actor NativePhotoLibrary: PhotoLibraryPort {
    private let library = PHPhotoLibrary.shared()

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

    func add(_ command: PhotoLibraryAddCommand) async -> PhotoRegistrationResult {
        let intent = command.registration.intent
        guard command.registration.isCommitted, command.media.handoff == intent.handoff,
              command.media.url.isFileURL else {
            return .init(intent: intent, outcome: .notAttempted(.invalidMedia))
        }
        // Status inspection must not trigger either privacy prompt. Saving uses
        // add-only even when read/write has already been granted separately.
        let status = await authorizationStatus(for: .addOnly)
        guard status == .authorized else {
            let failure: PhotoLibraryFailure
            switch status {
            case .restricted: failure = .restricted
            case .denied, .notDetermined: failure = .authorizationRequired
            case .limited, .unknown, .authorized: failure = .inaccessible
            }
            return .init(intent: intent, outcome: .notAttempted(failure))
        }
        guard !Task.isCancelled else {
            return .init(intent: intent, outcome: .notAttempted(.rejected))
        }
        let pending = PendingPhotoIdentifier()
        let url = command.media.url
        let capturedAt = intent.capturedAt
        let contentType = command.media.contentType
        // PhotoKit has no cancellation handle for performChanges. In particular,
        // cancellation of this task does not resume this continuation or close
        // the caller's media use. Only the SDK completion ends this call.
        return await withCheckedContinuation { continuation in
            library.performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                // Managed files have opaque UUID leaves. Describe their stored
                // MIME type without inventing a container or renaming/copying.
                options.contentType = contentType.flatMap { UTType(mimeType: $0) }
                request.creationDate = capturedAt
                request.addResource(with: .video, fileURL: url, options: options)
                let identifier = request.placeholderForCreatedAsset?.localIdentifier
                pending.value.withLock { value in
                    value = identifier.flatMap { try? PhotoAssetIdentifier(rawValue: $0) }
                }
            } completionHandler: { succeeded, error in
                let identifier = pending.value.withLock { $0 }
                let outcome: PhotoRegistrationOutcome
                if succeeded {
                    // Success without a surviving identifier still records the
                    // addition. It must never authorize a duplicate retry.
                    outcome = .succeeded(localIdentifier: identifier)
                } else {
                    outcome = Self.failedAddition(error, identifier: identifier)
                }
                continuation.resume(returning: .init(intent: intent, outcome: outcome))
            }
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
