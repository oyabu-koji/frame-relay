import Foundation

/// Remote catalog rows have no local recording reference. This exact target
/// deliberately cannot be submitted to original-removal commands.
nonisolated struct LibraryRenditionTarget: Equatable, Sendable {
    let original: OriginalContent
    let destination: DestinationIdentity?
    var title: String { "動画 \(original.capture.rawValue)" }
}

nonisolated protocol LibraryRemoteRenditionPort: Sendable {
    @MainActor func availability(_ item: LibraryRemoteItem) -> LibraryActionAvailability
    func play(original: OriginalContent, destination: DestinationIdentity,
              operation: MediaOperationID) async -> LibraryCommandResponse
}
