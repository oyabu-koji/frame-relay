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

    /// S45 v1, agreed 2026-10-18. These values remain changeable pending DV-06
    /// device evaluation; image-similarity thresholds are not identity proof.
    nonisolated static let provisionalSubjectPolicyV1 = CaptureSubjectPolicy(
        version: "s45-provisional-v1", lostGrace: 3, noPersonFocus: .tapPosition)

    /// S46 v1, agreed 2026-10-18: local reference advice expires one second after
    /// its input frame. Signal-specific bands remain provisional and uncalibrated
    /// pending DV-07; neither analysis nor expiry depends on a backend connection.
    nonisolated static let provisionalNDPolicyV1 = CaptureNDPolicy.provisionalV1(maximumResultAge: 1)

    /// S47 reversible evaluation settings. Slow ramp and narrow candidate radius
    /// allow control tests; DV-08 must still adopt actual quality/precision values.
    nonisolated static let provisionalZoomPolicyV1 = CaptureZoomPolicy.provisionalV1

    /// Proposal only: ordinary composition leaves compensation disabled until
    /// the user's ISO baseline/limit decision has been recorded.
    nonisolated static let proposedLensISOPolicyV1 = CaptureLensISOPolicy(version: "s47-lens-iso-proposal-v1", maximumStops: 1)

    static func make(services: ProductLibraryServices,
                     didSave: @escaping @MainActor @Sendable () async -> Void) -> ProductCaptureCoordinator {
        make(services: services, didSave: didSave, makeDeviceWithControls: { candidate, audioPolicy, subjectPolicy, ndPolicy, zoomPolicy, lensPolicy in
            #if !targetEnvironment(simulator)
            guard await permission(for: .video) else { throw ExplorationIssue.permissionDenied }
            guard await permission(for: .audio) else {
                throw ProductCaptureAudioPreparationError.microphonePermissionDenied
            }
            #endif
            return NativeExplorationCapture(candidate: candidate,
                originals: ProductReservedOriginalDestination(store: services.originals),
                audioPolicy: audioPolicy, subjectPolicy: subjectPolicy, ndPolicy: ndPolicy,
                zoomPolicy: zoomPolicy, lensISOPolicy: lensPolicy)
        })
    }

    /// Keep the device builder and coordinator on the same versioned policy.
    static func make(services: ProductLibraryServices,
                     didSave: @escaping @MainActor @Sendable () async -> Void,
                     makeDevice: @escaping @Sendable (ExplorationOutputCandidate, ProductCaptureAudioPolicy, CaptureSubjectPolicy, CaptureNDPolicy) async throws
                        -> any ProductCaptureDevicePort) -> ProductCaptureCoordinator {
        make(services: services, didSave: didSave, makeDeviceWithControls: { candidate, audio, subjects, nd, _, _ in
            try await makeDevice(candidate, audio, subjects, nd)
        })
    }

    static func make(services: ProductLibraryServices,
                     didSave: @escaping @MainActor @Sendable () async -> Void,
                     makeDeviceWithControls: @escaping @Sendable (ExplorationOutputCandidate, ProductCaptureAudioPolicy, CaptureSubjectPolicy, CaptureNDPolicy, CaptureZoomPolicy, CaptureLensISOPolicy?) async throws
                        -> any ProductCaptureDevicePort) -> ProductCaptureCoordinator {
        let audioPolicy = provisionalAudioPolicyV1
        let subjectPolicy = provisionalSubjectPolicyV1
        let ndPolicy = provisionalNDPolicyV1
        let preferences = CapturePreferenceStore(url: services.run.url.appendingPathComponent("capture-preferences.json"))
        let save = OriginalSaveCoordinator(store: services.store, originals: services.originals,
                                           inspection: AVOriginalInspectionAdapter(originals: services.originals))
        return ProductCaptureCoordinator(preferences: preferences, makeDevice: { candidate in
            try await makeDeviceWithControls(candidate, audioPolicy, subjectPolicy, ndPolicy, provisionalZoomPolicyV1, nil)
        }, save: save, bindOriginal: { reference in
            let operation = MediaOperationID(rawValue: "capture-bind-" + UUID().uuidString)
            if case .succeeded = await services.access.bind(reference, operation: operation) { return true }
            return false
        }, didSave: didSave, audioPolicy: audioPolicy, subjectPolicy: subjectPolicy, ndPolicy: ndPolicy, zoomPolicy: provisionalZoomPolicyV1,
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
