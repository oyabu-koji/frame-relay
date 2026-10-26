import Foundation

@MainActor final class LibraryPhotoSaveCommands: LibraryPhotoSavePort {
    private let coordinator: PhotoSaveBatchCoordinator
    private let network: any PhotoSaveStartNetworkPort
    init(coordinator: PhotoSaveBatchCoordinator, network: any PhotoSaveStartNetworkPort) {
        self.coordinator = coordinator; self.network = network
    }
    func availability(sources: [PhotoSaveSource], reasons: [String?]) -> LibraryActionAvailability {
        guard !reasons.isEmpty else { return .unavailable("写真に保存する動画を選択してください。") }
        guard let reason = reasons.compactMap({ $0 }).first else {
            guard sources.count == reasons.count else { return .unavailable(LocalRenditionSelection.unavailableReason) }
            guard network.currentCondition() == .wiFi else { return .unavailable(PhotoSaveBatchCoordinator.wifiReason) }
            return .available
        }
        return .unavailable(reason)
    }
    func submit(_ request: PhotoSaveBatchRequest) async -> LibraryCommandResponse { await coordinator.submit(request) }
    func resume(_ batch: MediaOperationID) async { await coordinator.resume(batch) }
    func cancel(_ batch: MediaOperationID) async { await coordinator.cancel(batch) }
    func retry(source: PhotoSaveSource, previous: MediaOperationID, operation: MediaOperationID) async -> LibraryCommandResponse {
        await coordinator.retry(source: source, previous: previous, operation: operation)
    }
}

nonisolated enum LibraryPhotoSaveProjection {
    static func source(backend: BackendStoreSnapshot, originals: OriginalStoreSnapshot,
                       target: LibraryRenditionTarget) -> PhotoSaveSource? {
        guard let selected = try? LocalRenditionSelection.select(backend: backend, originals: originals, target: target),
              let file = selected.media.fileIdentity else { return nil }
        return .init(storeIdentity: selected.identity, registration: selected.registration, rendition: selected.rendition,
            media: selected.media.id, capturedAt: selected.media.capturedAt, directoryIdentity: selected.media.directoryIdentity,
            fileIdentity: file, leaf: selected.media.leaf, contentType: selected.media.contentType)
    }

    static func unavailable(_ source: PhotoSaveSource?, backend: BackendStoreSnapshot) -> String? {
        guard let source else { return LocalRenditionSelection.unavailableReason }
        if let previous = backend.photoRegistrations.last(where: { PhotoSaveBatchValueValidation.exact($0.registration.intent.key, source.key) }) {
            return previous.outcome?.permitsExplicitRetry == true
                ? "前回は追加されていません。対象の登録結果から明示的に再試行してください。"
                : "この軽量版には写真への追加記録があります。再追加せず、登録結果と写真側の存在を確認してください。"
        }
        if backend.photoSaveBatches.contains(where: { batch in
            batch.targets.contains { child in
                guard PhotoSaveBatchValueValidation.exact(child.target.key, source.key) else { return false }
                switch child.status { case .queued, .starting: return true; case .notProcessed: return false }
            }
        }) { return "この軽量版の写真保存要求は受付済みです。対象別の処理状況を確認してください。" }
        return nil
    }

    static func registrations(_ records: [PhotoRegistrationRecord], original: OriginalContent,
                              destination: DestinationIdentity?) -> [LibraryPhotoRegistration] {
        let matching = records.filter {
            PhotoSaveBatchValueValidation.exact($0.registration.intent.rendition.original, original)
        }
        // Destination belongs to the fixed distribution lease, not a capture ID
        // or a filename. Never join a remote row by capture alone.
        let exact = matching.filter { record in
            destination.map { PhotoSaveBatchValueValidation.exact(record.registration.mediaUse.lease.registration.destination, $0) } ?? true
        }
        return exact.map { record in .init(record: record, isLatestAttempt:
            exact.last(where: { PhotoSaveBatchValueValidation.exact($0.registration.intent.key, record.registration.intent.key) })
                .map { PhotoSaveBatchValueValidation.exact($0.registration.intent.operation, record.registration.intent.operation) } == true) }
    }
}

nonisolated extension PhotoSaveBatchChildRecord {
    var progressDescription: String {
        let acquisition = "取得：受付時の完全取得済み軽量版（現在の実媒体は開始時に再照合）"
        let photos: String
        let management: String
        switch status {
        case .queued: management = "要求受付済み・未着手。撮影待機では媒体を保持し、再起動後は明示的な続行が必要です"
        case .starting: management = "開始予約の保存記録あり。追加結果が未確定なら自動で再追加しません"
        case .notProcessed(let value):
            switch value.reason {
            case .cancelled: management = "未処理の取消を記録済み"
            case .ineligible: management = "開始条件不適合の未処理を記録済み"
            case .unavailable: management = "媒体準備不適合の未処理を記録済み"
            }
        }
        if let registration { photos = LibraryPhotoRegistration(record: registration, isLatestAttempt: true).registrationResult }
        else {
            switch status {
            case .queued: photos = "未着手・待機中。再起動後は明示的な続行が必要です"
            case .starting: photos = "開始の予約あり・追加結果未確定。自動で再追加しません"
            case .notProcessed(let value):
                switch value.reason { case .cancelled: photos = "未処理（本人取消）"; case .ineligible: photos = "未処理（開始条件不適合）"; case .unavailable: photos = "未処理（媒体を準備できません）" }
            }
        }
        return "対象：動画 \(target.source.rendition.original.capture.rawValue)\n軽量版ID：\(target.source.rendition.rendition.rawValue)\n\(acquisition)\n写真：\(photos)\n管理：\(management)\n要求の受付・取得・写真の登録結果は別々の記録です。"
    }
}
