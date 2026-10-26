import Foundation

/// The App owner retains an unknown whole plan. Only an explicit lookup of
/// that exact plan may resolve it; recreating a command is never a retry.
@MainActor final class LibraryMediaRequestCommands: MediaRequestControlPort {
    private let controls: any MediaRequestControlPort
    private var pending: MediaPersonControlPlan?
    private var inFlight = false

    init(controls: any MediaRequestControlPort) { self.controls = controls }

    @MainActor func submitPersonControl(_ plan: MediaPersonControlPlan) async -> MediaPersonControlResult {
        guard !inFlight else { return .unknown }
        if let pending {
            guard MediaPersonControlValueValidation.exact(pending, plan) else { return .rejected(.wrongStage) }
            return await lookupPersonControl(plan)
        }
        pending = plan
        inFlight = true
        let result = await controls.submitPersonControl(plan)
        inFlight = false
        return finish(result, plan: plan)
    }

    @MainActor func lookupPersonControl(_ plan: MediaPersonControlPlan) async -> MediaPersonControlResult {
        guard !inFlight, let pending, MediaPersonControlValueValidation.exact(pending, plan) else { return .unknown }
        inFlight = true
        let result = await controls.lookupPersonControl(plan)
        inFlight = false
        return finish(result, plan: plan)
    }

    private func finish(_ result: MediaPersonControlResult, plan: MediaPersonControlPlan) -> MediaPersonControlResult {
        if case .recorded(let record, let stops) = result {
            guard LibraryMediaRequestProjection.matches(record, stops: stops, plan: plan) else { return .unknown }
        }
        switch result {
        case .recorded, .rejected: pending = nil
        case .unknown: break
        }
        return result
    }
}

/// A read-only row for one durable backend request. Local players and Photos
/// do not produce this value and cannot enter a communication control plan.
nonisolated struct LibraryMediaRequest: Equatable, Sendable, Identifiable {
    let request: MediaRequest
    var resumeUnavailableReason: String? = nil
    var id: MediaOperationID { request.operation }
    var target: MediaPersonControlTarget { .init(request) }
    var accessibilityToken: String { target.accessibilityToken }
    var title: String {
        switch request.purpose {
        case .upload: "送信の通信要求"
        case .download: "取得の通信要求"
        case .playback: "再生の通信要求"
        }
    }
    var identityDescription: String { LibraryMediaRequestProjection.identity(target) }
    var intentDescription: String {
        switch request.intent {
        case .running: "本人の意思：継続の記録あり（通信の開始・実際の再開とは別です）"
        case .paused: "本人の意思：停止の記録あり"
        case .cancelled: "本人の意思：取消の記録あり"
        }
    }
    var waitsDescription: String {
        let reasons: [(MediaWaitReason, String)] = [(.wiFiUnavailable, "Wi-Fi条件"), (.recording, "撮影中"),
            (.saving, "原本の保存中"), (.recovery, "復旧中"), (.authentication, "認証"),
            (.serverUnavailable, "Macへの接続"), (.operatingSystem, "OSの待機"),
            (.targetUnavailable, "対象の照合"), (.queued, "順番待ち")]
        let labels = reasons.filter { request.waits.contains($0.0) }.map(\.1)
        return labels.isEmpty ? "待機条件：記録なし（通信の開始・再開を保証しません）"
            : "待機条件：" + labels.joined(separator: "、")
    }
    var transportDescription: String {
        let state: String
        switch request.transport {
        case .queued: state = "開始待ち"
        case .active: state = "実行中"
        case .stopRequested: state = "停止要求中"
        case .stopped: state = "停止"
        case .completed: state = "完了（Macの保存検証とは別です）"
        }
        return "通信状態の記録：\(state)。通信処理の終了・媒体の使用解放は別に確認が必要です。"
    }

    func availability(_ action: MediaPersonControlAction) -> LibraryActionAvailability {
        guard request.startCommitted else { return .unavailable("開始指示の保存記録を確認できません。") }
        guard !request.playbackEnded else { return .unavailable("この通信再生は終了済みです。") }
        guard request.transport != .completed else { return .unavailable("この通信要求は完了済みです。") }
        if case .succeeded = request.remote { return .unavailable("この通信要求には完了の照合記録があります。") }
        guard request.intent != .cancelled else { return .unavailable("この通信要求は本人取消済みです。") }
        switch action {
        case .pause:
            return request.intent == .paused ? .unavailable("本人停止の記録があります。") : .available
        case .cancel: return .available
        case .resumeIntent:
            guard request.intent == .paused else { return .unavailable("停止した通信だけ停止を解除できます。") }
            return resumeUnavailableReason.map { .unavailable($0) } ?? .available
        }
    }
}

nonisolated enum LibraryMediaRequestProjection {
    /// Preserve exact immutable and opaque identities while comparing the one
    /// unordered field as a set. JSON array ordering is not a wait change.
    static func samePresentation(_ left: MediaRequest, _ right: MediaRequest) -> Bool {
        MediaPersonControlTarget(left).matches(right)
            && left.intent == right.intent && left.waits == right.waits && left.transport == right.transport
            && MediaPersonControlValueValidation.exact(left.remote, right.remote)
            && MediaPersonControlValueValidation.exact(left.session, right.session)
            && left.startCommitted == right.startCommitted && left.playbackEnded == right.playbackEnded
            && left.hasReconciled == right.hasReconciled && left.lastObservation == right.lastObservation
    }

    static func rows(backend: BackendStoreSnapshot, originals: OriginalStoreSnapshot) -> [LibraryMediaRequest] {
        backend.requests.map { request in
            .init(request: request, resumeUnavailableReason: resumeReason(request, backend: backend, originals: originals))
        }
    }

    static func matching(_ rows: [LibraryMediaRequest], original: OriginalContent,
        destination: DestinationIdentity? = nil) -> [LibraryMediaRequest] {
        rows.filter { row in
            MediaPersonControlValueValidation.exact(row.request.target.original, original)
                && (destination.map { MediaPersonControlValueValidation.exact(row.request.registration.destination, $0) } ?? true)
        }
    }

    private static func resumeReason(_ request: MediaRequest, backend: BackendStoreSnapshot,
        originals: OriginalStoreSnapshot) -> String? {
        guard let registration = backend.registrations.last(where: {
            MediaPersonControlValueValidation.exact($0.server.registration.destination, request.registration.destination)
        }), registration.isCommitted,
            MediaPersonControlValueValidation.exact(registration.server.registration, request.registration) else {
            return "この通信要求の登録は現在の登録と一致しません。元の登録への停止・取消を確認してください。"
        }
        let original = request.target.original
        guard let state = originals.logicalOriginals.first(where: {
            MediaPersonControlValueValidation.exact($0.original, original)
        }), !originals.logicalOriginals.contains(where: {
            $0.original.capture == original.capture && !MediaPersonControlValueValidation.exact($0.original, original)
        }), state.removal == nil, state.invalidation == nil, state.removalResolution != .removed else {
            return "同じ原本の現在の対応・削除・失効状態を確認できません。"
        }
        if case .rendition(let rendition) = request.target {
            guard let current = backend.confirmationStates.first(where: {
                MediaPersonControlValueValidation.exact($0.registration, request.registration)
                    && MediaPersonControlValueValidation.exact($0.current.original, original)
            }), MediaPersonControlValueValidation.exact(current.current, rendition),
                !current.invalidatedRenditions.contains(rendition.rendition) else {
                return "同じ軽量版の現在の公開・失効状態を確認できません。"
            }
        }
        return nil
    }

    static func matches(_ record: StoredMediaPersonControlPlan, stops: [MediaPersonControlStopResult],
        plan: MediaPersonControlPlan) -> Bool {
        guard record.isCommitted, MediaPersonControlValueValidation.exact(record.plan, plan),
              stops.count == plan.children.count else { return false }
        var known: [MediaOperationID] = []
        for stop in stops {
            guard plan.children.contains(where: { MediaPersonControlValueValidation.exact($0.command, stop.child) }),
                  !known.contains(where: { MediaPersonControlValueValidation.exact($0, stop.child) }) else { return false }
            known.append(stop.child)
        }
        return plan.children.allSatisfy { child in
            known.contains { MediaPersonControlValueValidation.exact($0, child.command) }
        }
    }

    static func identity(_ target: MediaPersonControlTarget) -> String {
        let media: String
        switch target.target {
        case .original: media = "原本"
        case .rendition(let rendition): media = "軽量版ID：\(rendition.rendition.rawValue)"
        }
        return "対象：動画 \(target.target.original.capture.rawValue)・\(media)"
    }

    static func actionDescription(_ action: MediaPersonControlAction) -> String {
        switch action {
        case .pause: "停止"
        case .cancel: "取消"
        case .resumeIntent: "停止解除・待機"
        }
    }

    static func decision(_ child: MediaPersonControlChildRecord, action: MediaPersonControlAction) -> String {
        switch child.decision {
        case .recorded:
            switch action {
            case .pause: "停止指示を保存しました。通信処理の終了・媒体の使用解放は未確認です。"
            case .cancel: "取消指示を保存しました。Mac側の結果と通信処理の終了・媒体の使用解放は未確認です。"
            case .resumeIntent: "停止解除の意思を保存しました。通信の開始・実際の再開は行っていません。"
            }
        case .notProcessed(let reason):
            switch reason {
            case .missingRequest: "未処理：元の通信要求が見つかりません。"
            case .identityChanged: "未処理：元の通信の対象や接続先、実行状況が変わっています。"
            case .completed: "未処理：通信要求は完了済みです。"
            case .cancelled: "未処理：通信要求は本人取消済みです。"
            case .playbackEnded: "未処理：通信再生は終了済みです。"
            case .notPaused: "未処理：本人停止の記録がありません。"
            case .registrationChanged: "未処理：現在の登録と元の通信要求の登録が一致しません。"
            case .targetUnavailable: "未処理：同じ対象の現在の状態を確認できません。"
            }
        }
    }

    static func stop(_ disposition: MediaPersonControlStopDisposition) -> String {
        switch disposition {
        case .notRequired: "停止要求：今回の対象では不要でした。通信処理の終了・媒体の使用解放は別に確認が必要です。"
        case .notRequested: "停止要求：保存した指示を表示しています。自動で要求を繰り返しません。通信処理の終了・媒体の使用解放は未確認です。"
        case .requested: "停止要求：通信処理へ要求しました。通信処理の終了・媒体の使用解放は未確認です。"
        case .unknown: "停止要求：要求の結果が不明です。通信処理の終了・媒体の使用解放は未確認です。"
        }
    }
}
