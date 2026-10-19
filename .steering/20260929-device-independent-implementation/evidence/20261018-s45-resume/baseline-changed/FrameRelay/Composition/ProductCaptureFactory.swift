import AVFoundation
import Foundation

/// Shares the product writer and original directory. Creating the model does
/// not request capture permissions or open a capture session.
@MainActor enum ProductCaptureFactory {
    /// S43 v1, agreed 2026-10-18. Provisional until DV-10 device evaluation.
    /// The two-second arrival deadline also applies during recovery. The outer
    /// timeout is five seconds; SDK ownership remains held until actual release.
    nonisolated static let provisionalAudioPolicyV1: ProductCaptureAudioPolicy = {
        do {
            return try ProductCaptureAudioPolicy(noArrivalGrace: .init(ticks: 2, timescale: 1),
                recovery: .init(maximumAttempts: 1, attemptTimeout: .init(ticks: 5, timescale: 1)))
        } catch {
            preconditionFailure("Invalid S43 v1 audio policy: \(error)")
        }
    }()

    static func make(services: ProductLibraryServices,
                     didSave: @escaping @MainActor @Sendable () async -> Void) -> ProductCaptureCoordinator {
        make(services: services, didSave: didSave, makeDevice: { candidate, audioPolicy in
            #if !targetEnvironment(simulator)
            guard await permission(for: .video) else { throw ExplorationIssue.permissionDenied }
            guard await permission(for: .audio) else {
                throw ProductCaptureAudioPreparationError.microphonePermissionDenied
            }
            #endif
            return NativeExplorationCapture(candidate: candidate,
                originals: ProductReservedOriginalDestination(store: services.originals), audioPolicy: audioPolicy)
        })
    }

    /// Keep the device builder and coordinator on the same versioned policy.
    static func make(services: ProductLibraryServices,
                     didSave: @escaping @MainActor @Sendable () async -> Void,
                     makeDevice: @escaping @Sendable (ExplorationOutputCandidate, ProductCaptureAudioPolicy) async throws
                        -> any ProductCaptureDevicePort) -> ProductCaptureCoordinator {
        let audioPolicy = provisionalAudioPolicyV1
        let preferences = CapturePreferenceStore(url: services.run.url.appendingPathComponent("capture-preferences.json"))
        let save = OriginalSaveCoordinator(store: services.store, originals: services.originals,
                                           inspection: AVOriginalInspectionAdapter(originals: services.originals))
        return ProductCaptureCoordinator(preferences: preferences, makeDevice: { candidate in
            try await makeDevice(candidate, audioPolicy)
        }, save: save, bindOriginal: { reference in
            let operation = MediaOperationID(rawValue: "capture-bind-" + UUID().uuidString)
            if case .succeeded = await services.access.bind(reference, operation: operation) { return true }
            return false
        }, didSave: didSave, audioPolicy: audioPolicy,
            calendarNow: { Date() }, captureNow: { ExplorationCaptureValues.now() })
    }

    private nonisolated static func permission(for media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: media)
        default: return false
        }
    }
}
