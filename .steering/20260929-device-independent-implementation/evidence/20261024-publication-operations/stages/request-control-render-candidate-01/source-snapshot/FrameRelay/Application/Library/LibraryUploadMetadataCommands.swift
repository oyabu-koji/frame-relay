import Foundation

@MainActor final class LibraryUploadMetadataCommands: UploadMetadataPort {
    private struct Active {
        let request: UploadMetadataRequest
        let nonce: UUID
        let task: Task<UploadMetadataResult, Never>
    }
    private let metadata: any UploadMetadataPort
    private var active: [MediaOperationID: Active] = [:]
    init(metadata: any UploadMetadataPort) { self.metadata = metadata }
    @MainActor func refresh(_ request: UploadMetadataRequest) async -> UploadMetadataResult { await perform(request, mode: 0) }
    @MainActor func refreshKnownSession(_ request: UploadMetadataRequest) async -> UploadMetadataResult { await perform(request, mode: 1) }
    @MainActor func reconcilePending(_ request: UploadMetadataRequest) async -> UploadMetadataResult { await perform(request, mode: 2) }
    private func perform(_ request: UploadMetadataRequest, mode: Int) async -> UploadMetadataResult {
        if let old = active[request.operation] {
            guard UploadMetadataValidation.exact(old.request, request) else { return .rejected(.identityMismatch) }
            return await old.task.value
        }
        let nonce = UUID(), metadata = metadata
        let task = Task {
            let result: UploadMetadataResult
            switch mode {
            case 0: result = await metadata.refresh(request)
            case 1: result = await metadata.refreshKnownSession(request)
            default: result = await metadata.reconcilePending(request)
            }
            if case .recorded(let record) = result {
                guard record.isCommitted, UploadMetadataValidation.exact(record.observation.query.query.request, request) else { return UploadMetadataResult.unknown }
            }
            return result
        }
        active[request.operation] = .init(request: request, nonce: nonce, task: task)
        let result = await task.value
        if active[request.operation]?.nonce == nonce { active.removeValue(forKey: request.operation) }
        return result
    }
}

nonisolated enum LibraryUploadMetadataProjection {
    static func input(_ request: MediaRequest, backend: BackendStoreSnapshot) -> UploadMetadataRequest? {
        guard request.purpose == .upload, request.startCommitted, case .original(let original) = request.target,
              let identity = backend.storeIdentity,
              let registration = backend.registrations.last(where: {
                  UploadMetadataValidation.exact($0.server.registration.destination, request.registration.destination)
              }), registration.isCommitted, UploadMetadataValidation.exact(registration.server.registration, request.registration) else { return nil }
        return try? .init(storeIdentity: identity, registration: registration, operation: request.operation,
            original: original, expectedStartRevision: request.expectedStartRevision)
    }
    static func hasQuery(_ request: MediaRequest, backend: BackendStoreSnapshot) -> Bool {
        backend.uploadMetadataQueries.contains { $0.isCommitted && $0.query.request.matches(request) }
    }
    static func description(_ request: MediaRequest, backend: BackendStoreSnapshot) -> String? {
        guard request.purpose == .upload, case .original = request.target else { return nil }
        let query = backend.uploadMetadataQueries.last { $0.isCommitted && $0.query.request.matches(request) }
        let record = backend.uploadMetadataObservations.last { $0.isCommitted && $0.observation.query.query.request.matches(request) }
        if let query, query.query.generation.rawValue > (record?.observation.query.query.generation.rawValue ?? 0) {
            return "Macへの照会を予約しました。応答の記録は未確定です。この照会では原本を送信しません。"
        }
        guard let record else { return "Macへの転送準備・状態照合は未実行です。転送要求の受付だけではMacへの保存は確認できません。" }
        switch record.observation.response {
        case .created: return "Macの転送準備の受付を記録しました。原本の送信やMacの保存検証の成功ではありません。"
        case .status(let status):
            switch status.state {
            case .receiving: return "Mac側は受信待ち・受信中の記録です。この照会では原本を送信しません。"
            case .finalizing: return "Mac側は保存処理中の記録です。全内容の保存検証は未確定です。"
            case .completed: return "Macの全内容保存検証の記録を取得しました。今回の原本送信の実行証拠とは分けて表示しています。"
            case .failed: return "Mac側の処理失敗の記録があります。本人の停止・取消と原本の現在状態は別に確認してください。"
            case .cancelled: return "Mac側で取消の記録があります。本人の停止・取消とは分けて保持しています。"
            }
        }
    }
}
