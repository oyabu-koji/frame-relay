import Foundation
import Observation

@MainActor @Observable final class RenditionPlaybackModel {
    typealias Confirm = @Sendable (PlaybackToken, MediaOperationID, RegistrationStoreIdentity) async -> BackendOutcome<ConfirmationRecord>
    private let factory: ProductRenditionFactory
    @ObservationIgnored private let confirmAction: Confirm
    @ObservationIgnored private let didChange: @MainActor @Sendable () async -> Void
    @ObservationIgnored private let stopJoinBoundary: (@MainActor @Sendable () async -> Void)?
    private(set) var target: LibraryRenditionTarget?
    private(set) var playback: AVRenditionPlayback?
    private(set) var session: PlaybackSessionID?
    private(set) var token: PlaybackToken?
    private(set) var isPreparing = false
    private(set) var isClosing = false
    private(set) var isConfirming = false
    private(set) var confirmation: ConfirmationRecord?
    private(set) var confirmationUnknown = false
    private(set) var confirmationFailed = false
    private(set) var message: String?
    private(set) var issue: String?
    private var presentation: UUID?
    private var identity: RegistrationStoreIdentity?
    private var action: MediaOperationID?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var confirmationTask: Task<BackendOutcome<ConfirmationRecord>, Never>?

    init(factory: ProductRenditionFactory,
         confirm: Confirm? = nil,
         stopJoinBoundary: (@MainActor @Sendable () async -> Void)? = nil,
         didChange: @escaping @MainActor @Sendable () async -> Void = {}) {
        self.factory = factory; self.didChange = didChange; self.stopJoinBoundary = stopJoinBoundary
        confirmAction = confirm ?? { token, action, identity in
            await factory.confirm(token, action: action, identity: identity)
        }
    }
    var canOpen: Bool { target == nil && !isClosing && startTask == nil }
    var isBusy: Bool {
        isPreparing || playback.map { [.preparing, .playing, .stopping].contains($0.phase) } == true
    }
    var canConfirm: Bool {
        token != nil && target != nil && !isClosing && !isConfirming && confirmation == nil && !confirmationFailed
    }

    /// The caller reserves the common presentation entry before this method.
    /// A handoff is not actual playback and never creates a confirmation.
    func open(_ target: LibraryRenditionTarget) -> Bool {
        guard canOpen else { return false }
        let nonce = UUID(), session = PlaybackSessionID(rawValue: UUID().uuidString)
        self.target = target; self.presentation = nonce; self.session = session
        token = nil; action = nil; identity = nil; confirmation = nil
        confirmationUnknown = false; confirmationFailed = false; message = nil; issue = nil; isPreparing = true
        startTask = Task { @MainActor in
            do {
                let source = try await factory.prepare(target)
                guard presentation == nonce else { _ = await factory.release(source); return }
                playback = source.owner.player; identity = source.selection.identity
                if Task.isCancelled {
                    if !(await factory.release(source)) { issue = "軽量版の使用終了を照合できません。記録を保持しています。" }
                    isPreparing = false
                    return
                }
                let outcome = await source.owner.player.play(.init(source: .local(source.receipt, source.selection.distribution),
                    session: session, invalidationGeneration: source.selection.generation))
                let released = await factory.release(source)
                guard presentation == nonce else { return }
                isPreparing = false
                if !released { issue = "軽量版の使用終了を照合できません。記録を保持しています。" }
                if case .succeeded(let value) = outcome,
                   PublicationStoreBoundary.exact(value.session, session),
                   PublicationStoreBoundary.exact(value.distribution, source.selection.distribution) {
                    token = value
                } else if !Task.isCancelled { issue = "この軽量版を再生できませんでした。媒体と現在の版を確認してください。" }
                await didChange()
            } catch {
                guard presentation == nonce else { return }
                isPreparing = false
                if !Task.isCancelled { issue = "完全取得済みの軽量版・現在の登録と版・実ファイルの対応を確認できません。媒体を作成せず記録を保持しています。" }
            }
        }
        return true
    }

    func stop() async {
        guard let nonce = presentation else { return }
        let task = startTask, player = playback, id = session, boundary = stopJoinBoundary
        task?.cancel()
        if let player, let id { await player.end(id) }
        // Optional instrumentation can delay this join, but it cannot replace
        // the actual SDK end above or the captured task's completion below.
        if let boundary { await boundary() }
        await task?.value
        guard presentation == nonce else { return }
        isPreparing = false
        await didChange()
    }

    func close(ifSession expected: PlaybackSessionID?) async {
        guard let expected, let current = session, PublicationStoreBoundary.exact(expected, current) else { return }
        await close()
    }

    func close() async {
        guard !isClosing else { return }
        isClosing = true
        await stop()
        _ = await confirmationTask?.value
        target = nil; presentation = nil; session = nil; token = nil; identity = nil; action = nil
        playback = nil; startTask = nil; confirmationTask = nil
        confirmation = nil; confirmationUnknown = false; confirmationFailed = false; isConfirming = false
        isClosing = false
    }

    /// Only the singular button in the current playback presentation calls this.
    func confirm() async {
        guard canConfirm, let token, let identity, let nonce = presentation else { return }
        isConfirming = true
        let action = self.action ?? .init(rawValue: UUID().uuidString)
        self.action = action
        let task = Task { await confirmAction(token, action, identity) }
        confirmationTask = task
        let result = await task.value
        guard presentation == nonce else { return }
        isConfirming = false; confirmationTask = nil
        switch result {
        case .succeeded(let record):
            guard PublicationStoreBoundary.exact(record.intent.playback, token),
                  PublicationStoreBoundary.exact(record.intent.operation, action) else {
                confirmationUnknown = true; message = "確認記録の対応を確定できません。同じ操作を照合してください。"; return
            }
            confirmation = record; confirmationUnknown = false
            message = "この再生版の明示確認を保存しました。Mac miniへの送達は別に照合します。"
        case .unknown, .inProgress:
            confirmationUnknown = true
            message = "確認の保存結果は未確定です。同じ再生・同じ操作の記録を照合してください。"
        case .failed, .notExecuted:
            confirmationFailed = true
            message = "現在の登録・版・失効状態で確認を保存できません。再読み込みして確認してください。"
        }
        await didChange()
    }
}
