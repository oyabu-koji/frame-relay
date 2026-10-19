import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    private let reader: any LibraryReadPort
    private let commands: any LibraryCommandPort
    private(set) var snapshot: LibrarySnapshot?
    private(set) var failure: LibraryReadFailure?
    private(set) var isLoading = false
    private(set) var selected: Set<CaptureID> = []
    private(set) var submissions: [LibrarySubmission] = []
    var submission: LibrarySubmission? { submissions.last }
    private(set) var inputIssue: String?
    @ObservationIgnored private var refreshRequested = false
    @ObservationIgnored private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    init(reader: any LibraryReadPort, commands: any LibraryCommandPort = UnconnectedLibraryCommands()) {
        self.reader = reader
        self.commands = commands
    }

    func refresh() async {
        if isLoading {
            refreshRequested = true
            await withCheckedContinuation { refreshWaiters.append($0) }
            return
        }
        isLoading = true
        repeat {
            refreshRequested = false
            switch await reader.loadLibrary() {
            case .loaded(let value):
                snapshot = value
                failure = nil
                selected.formIntersection(Set(value.recordings.map(\.id)))
            case .unavailable(let reason):
                // Keep prior rows explicitly stale. Never replace a read failure with an empty library.
                failure = reason
            }
        } while refreshRequested
        isLoading = false
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func select(_ capture: CaptureID, selected shouldSelect: Bool) {
        guard snapshot?.recordings.contains(where: { $0.id == capture }) == true else { return }
        if shouldSelect { selected.insert(capture) } else { selected.remove(capture) }
    }

    func item(_ capture: CaptureID) -> LibraryItem? { snapshot?.items.first { $0.id == capture } }

    func availability(_ action: LibraryAction, captures: Set<CaptureID>) -> LibraryActionAvailability {
        guard !submissions.contains(where: { blocks($0, action: action, captures: captures) }) else {
            return .unavailable("この対象の開始済み操作を照合しています。結果を再読み込みしてください。")
        }
        guard !isLoading, failure == nil, let snapshot else {
            return .unavailable("現在の保存記録を読み込んでから操作してください。")
        }
        guard !captures.isEmpty else { return .unavailable("対象の動画を選択してください。") }
        guard action.supportsMultiple || captures.count == 1 else {
            return .unavailable("この操作は1本ずつ行ってください。")
        }
        let items = snapshot.items.filter { captures.contains($0.id) }
        guard items.count == captures.count, items.allSatisfy({ !$0.isDiscardHistory }) else {
            return .unavailable("通常一覧にある対象を選び直してください。")
        }
        return commands.availability(action, items: items)
    }

    func submit(_ action: LibraryAction, captures: Set<CaptureID>, discardRiskAcknowledged: Bool = false) async {
        let current = availability(action, captures: captures)
        guard current == .available, let snapshot else {
            inputIssue = current.reason
            return
        }
        guard action != .discard || discardRiskAcknowledged else {
            inputIssue = "対象と消失リスクを確認してから破棄してください。"
            return
        }
        let targets = snapshot.items.filter { captures.contains($0.id) }.map {
            LibraryCommandTarget(capture: $0.id, reference: $0.recording.intent.original, original: $0.original)
        }
        let request = LibraryCommandRequest(id: .init(rawValue: UUID().uuidString), action: action,
            targets: targets, displayedRevision: snapshot.revision,
            discardRiskAcknowledged: action == .discard && discardRiskAcknowledged)
        // Set before the first suspension: repeated taps cannot submit a second command.
        inputIssue = nil
        submissions.append(.init(request: request, phase: .submitting))
        let response = await commands.submit(request)
        guard let index = submissions.firstIndex(where: { $0.id == request.id }) else { return }
        switch response {
        case .accepted:
            // Playback owns a live session, not a durable side-effect result.
            // Its handler's availability must reflect that session until stop/release.
            submissions[index].phase = action.isPlayback ? .playbackHandedOff : .awaitingRecordedResult
        case .rejected(let reason): submissions[index].phase = .rejected(reason)
        case .unknown: submissions[index].phase = .reconciliationRequired
        }
        await refresh()
    }

    private func blocks(_ submission: LibrarySubmission, action: LibraryAction, captures: Set<CaptureID>) -> Bool {
        switch submission.phase {
        case .rejected, .playbackHandedOff: return false
        default: break
        }
        if submission.request.action.isPlayback {
            // Prevent two simultaneous handoffs; S15 owns ongoing player/session availability.
            return action.isPlayback && submission.phase == .submitting
        }
        let bothRemove = [.cleanup, .discard].contains(action) && [.cleanup, .discard].contains(submission.request.action)
        guard action == submission.request.action || bothRemove else { return false }
        // A result for one target never releases an unresolved peer, or blocks a different video.
        return submission.request.targets.filter { captures.contains($0.capture) }.contains { target in
            if submission.phase == .submitting { return true }
            guard let result = item(target.capture)?.operationResults.first(where: {
                $0.id == submission.request.id && $0.action == submission.request.action
            }) else { return true }
            switch result.outcome {
            case .succeeded, .failed, .notProcessed: return false
            case .pending, .unknown: return true
            }
        }
    }
}
