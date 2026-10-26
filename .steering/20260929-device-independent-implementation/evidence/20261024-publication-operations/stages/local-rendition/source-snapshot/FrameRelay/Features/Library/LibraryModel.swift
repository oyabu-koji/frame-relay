import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    private let reader: any LibraryReadPort
    private let commands: any LibraryCommandPort
    private let photos: (any LibraryPhotoReconciliationPort)?
    private let removals: (any LibraryRemovalReconciliationPort)?
    private let remoteRenditions: (any LibraryRemoteRenditionPort)?
    private(set) var remotePlaybackMessages: [RemoteInventoryOriginalID: String] = [:]
    private var remotePlaybackPending: Set<RemoteInventoryOriginalID> = []
    private(set) var snapshot: LibrarySnapshot?
    private(set) var failure: LibraryReadFailure?
    private(set) var isLoading = false
    private(set) var selected: Set<CaptureID> = []
    private(set) var submissions: [LibrarySubmission] = []
    var submission: LibrarySubmission? { submissions.last }
    private(set) var inputIssue: String?
    private(set) var removalReconciliations: Set<MediaOperationID> = []
    private(set) var removalReconciliationMessages: [MediaOperationID: String] = [:]
    private(set) var photoReconciliations: Set<MediaOperationID> = []
    private(set) var photoReconciliationMessages: [MediaOperationID: String] = [:]
    @ObservationIgnored private var photoReconciliationActions: [MediaOperationID: MediaOperationID] = [:]
    @ObservationIgnored private var refreshRequested = false
    @ObservationIgnored private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    init(reader: any LibraryReadPort, commands: any LibraryCommandPort = UnconnectedLibraryCommands(),
         photos: (any LibraryPhotoReconciliationPort)? = nil,
         removals: (any LibraryRemovalReconciliationPort)? = nil,
         remoteRenditions: (any LibraryRemoteRenditionPort)? = nil) {
        self.reader = reader
        self.commands = commands
        self.photos = photos
        self.removals = removals
        self.remoteRenditions = remoteRenditions
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

    func remotePlaybackAvailability(_ item: LibraryRemoteItem) -> LibraryActionAvailability {
        guard !isLoading, failure == nil, snapshot?.remoteItems.contains(item) == true,
              !remotePlaybackPending.contains(item.id), let remoteRenditions else {
            return .unavailable("現在の保存記録を読み込んでから操作してください。")
        }
        return remoteRenditions.availability(item)
    }

    func playRemoteRendition(_ item: LibraryRemoteItem) async {
        guard remotePlaybackAvailability(item) == .available, let remoteRenditions else { return }
        remotePlaybackPending.insert(item.id)
        let result = await remoteRenditions.play(original: item.original, destination: item.destination,
            operation: .init(rawValue: UUID().uuidString))
        remotePlaybackPending.remove(item.id)
        switch result {
        case .accepted: remotePlaybackMessages[item.id] = "再生機能に引き渡しました。再生状態はプレーヤーで確認してください。"
        case .rejected(let why): remotePlaybackMessages[item.id] = why
        case .unknown: remotePlaybackMessages[item.id] = "再生の受付結果を確認できません。"
        }
        await refresh()
    }

    func select(_ capture: CaptureID, selected shouldSelect: Bool) {
        guard snapshot?.recordings.contains(where: { $0.id == capture }) == true else { return }
        if shouldSelect { selected.insert(capture) } else { selected.remove(capture) }
    }

    func item(_ capture: CaptureID) -> LibraryItem? { snapshot?.items.first { $0.id == capture } }

    func canReconcilePhotos(_ photo: LibraryPhotoRegistration, capture: CaptureID) -> Bool {
        photos != nil && !isLoading && failure == nil && photo.canReconcile
            && !photoReconciliations.contains(photo.id)
            && item(capture)?.photoRegistrations.contains(photo) == true
    }

    /// Called only by the explained, per-record user action. Refresh and capture
    /// preparation never call the Photos reconciliation port.
    func reconcilePhotos(_ photo: LibraryPhotoRegistration, capture: CaptureID) async {
        guard canReconcilePhotos(photo, capture: capture), let photos else { return }
        photoReconciliations.insert(photo.id)
        photoReconciliationMessages[photo.id] = nil
        let action = photoReconciliationActions[photo.id] ?? .init(rawValue: UUID().uuidString)
        photoReconciliationActions[photo.id] = action
        let result = await photos.reconcile(photo.record.registration.intent, action: action)
        photoReconciliations.remove(photo.id)
        switch result {
        case .succeeded:
            photoReconciliationActions[photo.id] = nil
            photoReconciliationMessages[photo.id] = "写真側の存在の照合結果を記録しました。過去の登録結果とは分けて表示しています。"
        case .notExecuted:
            photoReconciliationActions[photo.id] = nil
            photoReconciliationMessages[photo.id] = "対象の登録記録が更新されているか、照合に必要な識別情報がありません。再読み込みした記録を確認してください。"
        case .failed:
            photoReconciliationActions[photo.id] = nil
            photoReconciliationMessages[photo.id] = "照合結果を保存できませんでした。保存記録を再読み込みしてください。"
        case .inProgress:
            photoReconciliationMessages[photo.id] = "この登録記録は照合中です。完了後に再読み込みしてください。"
        case .unknown:
            photoReconciliationMessages[photo.id] = "照合結果の保存を確定できません。再読み込みしてから、必要な場合は同じ照合を再試行してください。"
        }
        await refresh()
    }

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

    func prepareRemovalReview(_ action: LibraryAction, captures: Set<CaptureID>) -> LibraryRemovalReview? {
        let current = availability(action, captures: captures)
        guard [.cleanup, .discard].contains(action), current == .available, let snapshot else {
            inputIssue = current.reason; return nil
        }
        let items = snapshot.items.filter { captures.contains($0.id) }
        guard items.count == captures.count, items.allSatisfy({ $0.original != nil }) else {
            inputIssue = "原本の内容と保存記録の対応を確認してください。"; return nil
        }
        return .init(id: .init(rawValue: UUID().uuidString), action: action,
            targets: items.map { .init(capture: $0.id, reference: $0.recording.intent.original, original: $0.original) },
            displayedRevision: snapshot.revision,
            information: items.map { $0.removalReviewInformation ?? "対象：\($0.title)。\($0.captureDateDescription)" })
    }

    func submit(_ review: LibraryRemovalReview) async {
        await submit(review.action, captures: Set(review.targets.map(\.capture)),
            discardRiskAcknowledged: review.action == .discard, fixedReview: review)
    }

    func canReconcileRemoval(_ operation: LibraryRemovalOperation, capture: CaptureID) -> Bool {
        removals != nil && !isLoading && failure == nil && !removalReconciliations.contains(operation.id)
            && !submissions.contains(where: { $0.id == operation.batch && $0.phase == .submitting })
            && item(capture)?.removalOperations.contains(operation) == true
    }

    func reconcileRemoval(_ operation: LibraryRemovalOperation, capture: CaptureID) async {
        guard canReconcileRemoval(operation, capture: capture), let removals else { return }
        removalReconciliations.insert(operation.id)
        let result = await removals.reconcile(operation)
        removalReconciliations.remove(operation.id)
        switch result {
        case .succeeded: removalReconciliationMessages[operation.id] = "削除結果を照合しました。新しい削除は実行していません。"
        case .notExecuted: removalReconciliationMessages[operation.id] = "対象が更新されました。再読み込みして確認し直してください。"
        default: removalReconciliationMessages[operation.id] = "削除結果を確定できません。原本と記録を保持しています。"
        }
        await refresh()
    }

    func submit(_ action: LibraryAction, captures: Set<CaptureID>, discardRiskAcknowledged: Bool = false,
                fixedReview: LibraryRemovalReview? = nil) async {
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
        if let fixedReview {
            guard fixedReview.action == action, fixedReview.targets == targets else {
                inputIssue = "対象が更新されました。対象と消失リスクを確認し直してください。"
                return
            }
        }
        let request = LibraryCommandRequest(id: fixedReview?.id ?? .init(rawValue: UUID().uuidString), action: action,
            targets: fixedReview?.targets ?? targets, displayedRevision: fixedReview?.displayedRevision ?? snapshot.revision,
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
