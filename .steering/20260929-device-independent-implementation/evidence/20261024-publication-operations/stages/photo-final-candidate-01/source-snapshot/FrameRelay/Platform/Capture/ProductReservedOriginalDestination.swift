import Foundation
import AVFoundation

/// Product save has already reserved the destination before accepting REC.
actor ProductReservedOriginalDestination: ExplorationOriginalDestinationPort {
    private let store: ManagedOriginalStore
    init(store: ManagedOriginalStore) { self.store = store }
    func reserve(original: CaptureOriginalReference) async throws -> URL {
        try await store.reservedURL(for: original)
    }
    func byteCount(for original: CaptureOriginalReference) async throws -> UInt64 {
        try await store.byteCount(for: original)
    }
}

/// Session configuration/running stays on the capture actor. UI only attaches its preview layer.
nonisolated final class NativeCapturePreviewSource: ProductCapturePreviewSource, @unchecked Sendable {
    let session: AVCaptureSession
    init(session: AVCaptureSession) { self.session = session }
}
