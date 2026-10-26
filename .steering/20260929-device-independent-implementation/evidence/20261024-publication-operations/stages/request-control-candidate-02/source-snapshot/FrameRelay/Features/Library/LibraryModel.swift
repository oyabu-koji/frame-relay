import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    private let reader: any LibraryReadPort
    private let commands: any LibraryCommandPort
    private let photos: (any LibraryPhotoReconciliationPort)?
    private let removals: (any LibraryRemovalReconciliationPort)?
    private let remoteRenditions: (any LibraryRemoteRenditionPort)?
    private let photoSaves: (any LibraryPhotoSavePort)?
    private let requestControls: (any MediaRequestControlPort)?
    var hasPhotoSavePort: Bool { photoSaves != nil }
    var hasMediaRequestControlPort: Bool { requestControls != nil }
    private(set) var pendingMediaControlPlan: MediaPersonControlPlan?
    private(set) var isSubmittingMediaControl = false
    private(set) var mediaControlMessage: String?
    private(set) var mediaControlStops: [MediaOperationID: MediaPersonControlStopDisposition] = [:]
    private(set) var remotePhotoSelected: Set<RemoteInventoryOriginalID> = []
    private(set) var photoSaveMessage: String?
    private(set) var isSubmittingPhotos = false
    private(set) var pendingPhotoAcceptance: PhotoSaveBatchRequest?
    @ObservationIgnored private var photoRetryActions: [MediaOperationID: MediaOperationID] = [:]
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
         remoteRenditions: (any LibraryRemoteRenditionPort)? = nil,
         photoSaves: (any LibraryPhotoSavePort)? = nil,
         requestControls: (any MediaRequestControlPort)? = nil) {
        self.reader = reader
        self.commands = commands
        self.photos = photos
        self.removals = removals
        self.remoteRenditions = remoteRenditions
        self.photoSaves = photoSaves
        self.requestControls = requestControls
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
                remotePhotoSelected.formIntersection(Set(value.remoteItems.map(\.id)))
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

    func mediaRequestAvailability(_ action: MediaPersonControlAction, request row: LibraryMediaRequest) -> LibraryActionAvailability {
        guard requestControls != nil, !isLoading, failure == nil, let snapshot, snapshot.storeIdentity != nil else {
            return .unavailable("現在の通信要求の保存記録を読み込んでから操作してください。")
        }
        guard !isSubmittingMediaControl, pendingMediaControlPlan == nil else {
            return .unavailable("先の通信操作の記録を照合してください。")
        }
        guard let current = snapshot.mediaRequests.first(where: {
            LibraryMediaRequestProjection.samePresentation($0.request, row.request)
        }) else { return .unavailable("通信要求が更新されました。再読み込みして確認してください。") }
        return current.availability(action)
    }

    var allMediaPauseAvailability: LibraryActionAvailability {
        guard requestControls != nil, !isLoading, failure == nil, let snapshot, snapshot.storeIdentity != nil else {
            return .unavailable("現在の通信要求の保存記録を読み込んでから操作してください。")
        }
        guard !isSubmittingMediaControl, pendingMediaControlPlan == nil else {
            return .unavailable("先の通信操作の記録を照合してください。")
        }
        guard !snapshot.mediaRequests.isEmpty else { return .unavailable("開始指示済みの通信要求はありません。") }
        guard snapshot.mediaRequests.contains(where: { $0.availability(.pause) == .available }) else {
            return .unavailable("停止を記録できる通信要求はありません。対象別の記録を確認してください。")
        }
        return .available
    }

    func controlMediaRequest(_ action: MediaPersonControlAction, request row: LibraryMediaRequest) async {
        let available = mediaRequestAvailability(action, request: row)
        guard available == .available else { mediaControlMessage = available.reason; return }
        await beginMediaControl(action: action, scope: .single, requests: [row])
    }

    func pauseAllMediaRequests() async {
        let available = allMediaPauseAvailability
        guard available == .available, let snapshot else { mediaControlMessage = available.reason; return }
        // Includes queued/waiting and terminal rows. The same writer evaluates
        // every fixed child and records its individual nonprocessing reason.
        await beginMediaControl(action: .pause, scope: .allPause, requests: snapshot.mediaRequests)
    }

    private func beginMediaControl(action: MediaPersonControlAction, scope: MediaPersonControlScope,
        requests: [LibraryMediaRequest]) async {
        guard let identity = snapshot?.storeIdentity, let requestControls,
              !isSubmittingMediaControl, pendingMediaControlPlan == nil else { return }
        let plan: MediaPersonControlPlan
        do {
            plan = try .init(parent: .init(rawValue: UUID().uuidString.lowercased()), storeIdentity: identity,
                scope: scope, action: action, children: requests.map {
                    .init(command: .init(rawValue: UUID().uuidString.lowercased()), target: $0.target)
                })
        } catch {
            mediaControlMessage = "通信要求の対象を固定できません。保存記録を再読み込みしてください。"
            return
        }
        // Reserve the complete immutable plan and all child IDs before await.
        pendingMediaControlPlan = plan
        isSubmittingMediaControl = true
        let result = await requestControls.submitPersonControl(plan)
        isSubmittingMediaControl = false
        receiveMediaControl(result, plan: plan)
        await refresh()
    }

    func reconcileMediaControl() async {
        guard !isSubmittingMediaControl, let plan = pendingMediaControlPlan, let requestControls else { return }
        isSubmittingMediaControl = true
        let result = await requestControls.lookupPersonControl(plan)
        isSubmittingMediaControl = false
        receiveMediaControl(result, plan: plan)
        await refresh()
    }

    private func receiveMediaControl(_ result: MediaPersonControlResult, plan: MediaPersonControlPlan) {
        switch result {
        case .recorded(let record, let stops):
            guard LibraryMediaRequestProjection.matches(record, stops: stops, plan: plan) else {
                mediaControlMessage = "元の通信操作の記録を確定できません。同じ指示の記録を照合してください。"
                return
            }
            pendingMediaControlPlan = nil
            for stop in stops { mediaControlStops[stop.child] = stop.disposition }
            mediaControlMessage = plan.action == .resumeIntent
                ? "停止解除の指示の受付結果を保存しました。対象別の結果と残る待機条件を確認してください。通信の開始・実際の再開は行っていません。"
                : "通信操作の対象別の受付結果を保存しました。本人意思・未処理理由と停止要求を確認してください。通信処理の終了は未確認です。"
        case .rejected:
            pendingMediaControlPlan = nil
            mediaControlMessage = "通信操作を記録できませんでした。保存記録を再読み込みして対象を確認してください。"
        case .unknown:
            mediaControlMessage = "通信操作の受付結果は不明です。対象\(plan.children.count)件の指示を保持しています。同じ指示の受付結果を照合してください。"
        }
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

    func selectRemotePhoto(_ id: RemoteInventoryOriginalID, selected shouldSelect: Bool) {
        guard snapshot?.remoteItems.contains(where: { $0.id == id }) == true else { return }
        if shouldSelect { remotePhotoSelected.insert(id) } else { remotePhotoSelected.remove(id) }
    }

    func photoSaveAvailability(captures: Set<CaptureID>, remotes: Set<RemoteInventoryOriginalID>) -> LibraryActionAvailability {
        guard !isLoading, failure == nil, let snapshot, let photoSaves else {
            return .unavailable("現在の保存記録を読み込んでから操作してください。")
        }
        guard !isSubmittingPhotos, pendingPhotoAcceptance == nil else {
            return .unavailable("写真保存要求の受付結果を照合してください。")
        }
        let local = snapshot.recordings.filter { captures.contains($0.id) }
        let remote = snapshot.remoteItems.filter { remotes.contains($0.id) }
        guard local.count == captures.count, remote.count == remotes.count else {
            return .unavailable("対象が更新されました。動画を選び直してください。")
        }
        let sources = local.compactMap(\.photoSaveSource) + remote.compactMap(\.photoSaveSource)
        var keys: [PhotoRegistrationKey] = []
        for source in sources {
            guard !keys.contains(where: { PhotoSaveBatchValueValidation.exact($0, source.key) }) else {
                return .unavailable("同じ軽量版が複数選択されています。対象を選び直してください。")
            }
            keys.append(source.key)
        }
        return photoSaves.availability(sources: sources,
            reasons: local.map(\.photoSaveUnavailableReason) + remote.map(\.photoSaveUnavailableReason))
    }

    func submitPhotos(captures: Set<CaptureID>, remotes: Set<RemoteInventoryOriginalID>) async {
        let availability = photoSaveAvailability(captures: captures, remotes: remotes)
        guard availability == .available, let snapshot else { photoSaveMessage = availability.reason; return }
        let local = snapshot.recordings.filter { captures.contains($0.id) }
        let remote = snapshot.remoteItems.filter { remotes.contains($0.id) }
        let targets = local.compactMap { item in item.original.map { LibraryRenditionTarget(original: $0, destination: nil) } }
            + remote.map { LibraryRenditionTarget(original: $0.original, destination: $0.destination) }
        guard targets.count == captures.count + remotes.count else { return }
        let request = PhotoSaveBatchRequest(operation: .init(rawValue: UUID().uuidString), targets: targets,
            displayedRevision: snapshot.revision)
        // Fix the exact mixed set and reserve before the first suspension.
        pendingPhotoAcceptance = request
        await submitPhotoAcceptance(request)
    }

    func reconcilePhotoAcceptance() async {
        guard !isSubmittingPhotos, let request = pendingPhotoAcceptance else { return }
        await submitPhotoAcceptance(request)
    }

    private func submitPhotoAcceptance(_ request: PhotoSaveBatchRequest) async {
        guard let photoSaves else { return }
        isSubmittingPhotos = true
        let result = await photoSaves.submit(request)
        isSubmittingPhotos = false
        switch result {
        case .accepted:
            pendingPhotoAcceptance = nil
            photoSaveMessage = "写真保存要求を受け付けました。写真への登録成功ではありません。固定した動画別の処理状況を確認してください。"
        case .rejected(let reason): pendingPhotoAcceptance = nil; photoSaveMessage = reason
        case .unknown: photoSaveMessage = "受付結果を確定できません。同じ要求の受付結果を照合してください。自動で新しい追加を開始しません。"
        }
        await refresh()
    }

    func resumePhotoBatch(_ batch: MediaOperationID) async {
        guard let photoSaves, snapshot?.photoSaveBatches.contains(where: { $0.batch.operation == batch }) == true else { return }
        await photoSaves.resume(batch); await refresh()
    }
    func cancelPhotoBatch(_ batch: MediaOperationID) async {
        guard let photoSaves, snapshot?.photoSaveBatches.contains(where: { $0.batch.operation == batch }) == true else { return }
        await photoSaves.cancel(batch)
        photoSaveMessage = "未着手の取消を要求しました。開始予約や写真への追加結果が未確定の対象は、未確定の記録を保持しています。"
        await refresh()
    }

    func canRetryPhoto(_ photo: LibraryPhotoRegistration, source: PhotoSaveSource?) -> Bool {
        guard !isLoading, failure == nil, !isSubmittingPhotos, photo.isLatestAttempt,
              photo.record.outcome?.permitsExplicitRetry == true, let source, let photoSaves,
              source.matches(photo.record.registration) else { return false }
        return photoSaves.availability(sources: [source], reasons: [nil]) == .available
    }
    func retryPhoto(_ photo: LibraryPhotoRegistration, source: PhotoSaveSource?) async {
        guard canRetryPhoto(photo, source: source), let source, let photoSaves else { return }
        let action = photoRetryActions[photo.id] ?? .init(rawValue: UUID().uuidString)
        photoRetryActions[photo.id] = action; isSubmittingPhotos = true
        let result = await photoSaves.retry(source: source, previous: photo.id, operation: action)
        isSubmittingPhotos = false
        switch result {
        case .accepted: photoRetryActions[photo.id] = nil; photoSaveMessage = "再試行要求を受け付けました。新しい対象別の登録結果を確認してください。"
        case .rejected(let reason): photoRetryActions[photo.id] = nil; photoSaveMessage = reason
        case .unknown: photoSaveMessage = "再試行要求の受付結果は未確定です。同じ対象の明示操作で受付結果を照合できます。"
        }
        await refresh()
    }

    func canReconcileRemotePhotos(_ photo: LibraryPhotoRegistration, item: LibraryRemoteItem) -> Bool {
        photos != nil && !isLoading && failure == nil && photo.canReconcile
            && !photoReconciliations.contains(photo.id)
            && snapshot?.remoteItems.first(where: { $0.id == item.id })?.photoRegistrations.contains(photo) == true
            && PhotoSaveBatchValueValidation.exact(photo.record.registration.intent.rendition.original, item.original)
            && PhotoSaveBatchValueValidation.exact(photo.record.registration.mediaUse.lease.registration.destination, item.destination)
    }
    func reconcileRemotePhotos(_ photo: LibraryPhotoRegistration, item: LibraryRemoteItem) async {
        guard canReconcileRemotePhotos(photo, item: item) else { return }
        await performPhotoReconciliation(photo)
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
        guard canReconcilePhotos(photo, capture: capture) else { return }
        await performPhotoReconciliation(photo)
    }

    private func performPhotoReconciliation(_ photo: LibraryPhotoRegistration) async {
        guard let photos else { return }
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
