import Foundation

/// Shared MainActor reservation spans async original handoff. Sheet state and
/// separate model busy flags alone cannot protect the await gap.
@MainActor final class RenditionPlaybackLibraryCommands: LibraryCommandPort, LibraryRemoteRenditionPort {
    private let base: any LibraryCommandPort
    private let original: OriginalPlaybackModel
    private let rendition: RenditionPlaybackModel
    private var reservation: (owner: String, nonce: UUID)?

    init(base: any LibraryCommandPort, original: OriginalPlaybackModel, rendition: RenditionPlaybackModel) {
        self.base = base; self.original = original; self.rendition = rendition
    }
    private var canPresent: Bool {
        reservation == nil && original.target == nil && original.sessionID == nil
            && original.canOpen && rendition.canOpen
    }
    private func reserve(_ owner: String) -> UUID? {
        guard canPresent else { return nil }
        let nonce = UUID(); reservation = (owner, nonce); return nonce
    }
    private func release(_ nonce: UUID) { if reservation?.nonce == nonce { reservation = nil } }
    private var busyReason: String { "再生画面を閉じ、読み取り終了を確認してから選んでください。" }

    func availability(_ action: LibraryAction, items: [LibraryItem]) -> LibraryActionAvailability {
        if action == .confirmRendition {
            return .unavailable("軽量版を1本ずつ実際に再生し、その再生画面の「この軽量版を確認」から操作してください。")
        }
        guard action.isPlayback else { return base.availability(action, items: items) }
        guard canPresent else { return .unavailable(busyReason) }
        if action == .playOriginal { return base.availability(action, items: items) }
        guard items.count == 1, !items[0].isDiscardHistory, items[0].original != nil else {
            return .unavailable(LocalRenditionSelection.unavailableReason)
        }
        return items[0].localRenditionUnavailableReason.map { .unavailable($0) } ?? .available
    }

    @MainActor func submit(_ request: LibraryCommandRequest) async -> LibraryCommandResponse {
        guard request.action.isPlayback else { return await base.submit(request) }
        guard let nonce = reserve(request.action.rawValue) else { return .rejected(busyReason) }
        defer { release(nonce) }
        guard request.targets.count == 1 else { return .rejected("この操作は1本ずつ行ってください。") }
        if request.action == .playOriginal { return await base.submit(request) }
        guard let original = request.targets[0].original,
              original.capture.rawValue.utf8.elementsEqual(request.targets[0].capture.rawValue.utf8) else {
            return .rejected(LocalRenditionSelection.unavailableReason)
        }
        return rendition.open(.init(original: original, destination: nil)) ? .accepted : .rejected(busyReason)
    }

    func availability(_ item: LibraryRemoteItem) -> LibraryActionAvailability {
        guard canPresent else { return .unavailable(busyReason) }
        return item.localRenditionUnavailableReason.map { .unavailable($0) } ?? .available
    }
    @MainActor func play(original: OriginalContent, destination: DestinationIdentity,
              operation: MediaOperationID) async -> LibraryCommandResponse {
        guard let nonce = reserve("remote-rendition") else { return .rejected(busyReason) }
        defer { release(nonce) }
        return rendition.open(.init(original: original, destination: destination)) ? .accepted : .rejected(busyReason)
    }
}
