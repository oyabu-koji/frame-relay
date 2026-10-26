import Foundation

/// Photos-only targets are independent of legacy commands and original-file
/// references. A remote catalog row can never become a deletion target here.
nonisolated protocol LibraryPhotoSavePort: Sendable {
    @MainActor func availability(sources: [PhotoSaveSource], reasons: [String?]) -> LibraryActionAvailability
    func submit(_ request: PhotoSaveBatchRequest) async -> LibraryCommandResponse
    func resume(_ batch: MediaOperationID) async
    func cancel(_ batch: MediaOperationID) async
    func retry(source: PhotoSaveSource, previous: MediaOperationID, operation: MediaOperationID) async -> LibraryCommandResponse
}
