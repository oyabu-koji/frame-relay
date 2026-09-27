import Foundation

/// Platform-internal destination resolution. Application only handles opaque references.
nonisolated protocol ExplorationOriginalDestinationPort: Sendable {
    func reserve(original: CaptureOriginalReference) async throws -> URL
    func byteCount(for original: CaptureOriginalReference) async throws -> UInt64
}
