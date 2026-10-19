import Foundation
import Observation

@MainActor @Observable final class OriginalPlaybackModel {
    let playback: AVOriginalPlayback
    private(set) var target: LibraryCommandTarget?
    private(set) var sessionID: PlaybackSessionID?
    private var startTask: Task<Void, Never>?

    init(playback: AVOriginalPlayback) { self.playback = playback }

    var canOpen: Bool { target == nil && !playback.isBusy }

    /// Presentation/acceptance only; AVOriginalPlayback publishes actual SDK progress.
    func open(_ target: LibraryCommandTarget, operation: MediaOperationID) -> Bool {
        guard canOpen, let original = target.original, original.capture == target.capture else { return false }
        playback.recordPresentation(.modelOpen)
        self.target = target
        let id = PlaybackSessionID(rawValue: UUID().uuidString)
        sessionID = id
        startTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            playback.recordPresentation(.modelStartTask)
            _ = await playback.open(original, operation: operation, session: id)
        }
        return true
    }

    func stop() async {
        playback.recordPresentation(.modelStop)
        startTask?.cancel()
        if let sessionID { await playback.stopOriginal(sessionID) }
        await startTask?.value
    }

    func close() async {
        playback.recordPresentation(.modelClose)
        await stop()
        // SDK admission is closed even when durable release needs reconciliation.
        // Keep that session in the adapter, but let the user return to the library.
        target = nil; sessionID = nil; startTask = nil
    }
}

/// S16 injects this into LibraryModel and presents OriginalPlaybackView with the
/// same model. It creates no database, original reader, or AVPlayer itself.
@MainActor final class OriginalPlaybackLibraryCommands: LibraryCommandPort {
    private let model: OriginalPlaybackModel
    init(model: OriginalPlaybackModel) { self.model = model }

    func availability(_ action: LibraryAction, items: [LibraryItem]) -> LibraryActionAvailability {
        guard action == .playOriginal else { return .unavailable(action.unavailableReason) }
        if model.playback.phase == .releaseNeedsReconciliation {
            return .unavailable("原本の読み取り終了を照合できないため、新しい再生を開始できません。管理記録を保持しています。")
        }
        guard model.canOpen else { return .unavailable("再生画面を閉じ、原本の読み取り終了を確認してから選んでください。") }
        guard items.count == 1, items[0].original != nil, case .present = items[0].file else {
            return .unavailable("原本の所在と保存記録の対応を確認できません。再読み込みしてください。")
        }
        return .available
    }

    @MainActor func submit(_ request: LibraryCommandRequest) async -> LibraryCommandResponse {
        guard request.action == .playOriginal, request.targets.count == 1 else {
            return .rejected(request.action.unavailableReason)
        }
        return model.open(request.targets[0], operation: request.id)
            ? .accepted : .rejected("現在の原本と再生状態を確認してから選び直してください。")
    }
}
