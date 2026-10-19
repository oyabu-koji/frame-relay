import AVFoundation
import Foundation

/// Shares the product writer and original directory. Creating the model does
/// not request capture permissions or open a capture session.
@MainActor enum ProductCaptureFactory {
    static func make(services: ProductLibraryServices,
                     didSave: @escaping @MainActor @Sendable () async -> Void) -> ProductCaptureCoordinator {
        let preferences = CapturePreferenceStore(url: services.run.url.appendingPathComponent("capture-preferences.json"))
        let save = OriginalSaveCoordinator(store: services.store, originals: services.originals,
                                           inspection: AVOriginalInspectionAdapter(originals: services.originals))
        return ProductCaptureCoordinator(preferences: preferences, makeDevice: { candidate in
            #if !targetEnvironment(simulator)
            guard await permission(for: .video) else { throw ExplorationIssue.permissionDenied }
            guard await permission(for: .audio) else {
                throw ProductCaptureAudioPreparationError.microphonePermissionDenied
            }
            #endif
            return NativeExplorationCapture(candidate: candidate,
                originals: ProductReservedOriginalDestination(store: services.originals))
        }, save: save, bindOriginal: { reference in
            let operation = MediaOperationID(rawValue: "capture-bind-" + UUID().uuidString)
            if case .succeeded = await services.access.bind(reference, operation: operation) { return true }
            return false
        }, didSave: didSave, calendarNow: { Date() }, captureNow: { ExplorationCaptureValues.now() })
    }

    private nonisolated static func permission(for media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: media)
        default: return false
        }
    }
}
