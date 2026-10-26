import Foundation

/// Read-only presentation values. These are never a deletion or confirmation authority.
nonisolated enum LibraryAxis: String, CaseIterable, Identifiable, Sendable {
    case save, original, transfer, verification, publication, retrieval, confirmation, invalidation, photos, photoPresence, removal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .save: "原本の保存結果"
        case .original: "iPhone原本の現在状態"
        case .transfer: "原本の転送"
        case .verification: "Mac miniの保存検証"
        case .publication: "軽量版の公開"
        case .retrieval: "軽量版の取得"
        case .confirmation: "軽量版の明示確認"
        case .invalidation: "確認の失効"
        case .photos: "写真への過去の登録結果"
        case .photoPresence: "写真側の存在の照合"
        case .removal: "原本の削除"
        }
    }
}

nonisolated struct LibraryStatus: Equatable, Sendable, Identifiable {
    let axis: LibraryAxis
    let text: String
    var id: LibraryAxis { axis }
}

nonisolated enum LibraryRemoval: Equatable, Sendable {
    case none
    case removed(RemovalPurpose)
    case notRemoved(RemovalPurpose)
    case reconciliationRequired(RemovalPurpose?)
}

/// A result loaded from the operation store, not a command return value.
/// Later operation adapters must correlate the exact command and capture IDs.
nonisolated struct LibraryOperationResult: Equatable, Sendable, Identifiable {
    let id: MediaOperationID
    let action: LibraryAction
    let outcome: LibraryRecordedOutcome
}

nonisolated enum LibraryRecordedOutcome: Equatable, Sendable {
    case pending, succeeded, failed(String), unknown, notProcessed

    var text: String {
        switch self {
        case .pending: "処理中"
        case .succeeded: "成功（記録確認済み）"
        case .failed(let reason): "失敗：\(reason)"
        case .unknown: "結果不明・要照合"
        case .notProcessed: "未処理"
        }
    }
}

nonisolated struct LibraryItem: Equatable, Sendable, Identifiable {
    let recording: RecordingStoreEntry
    let file: OriginalFileObservation
    let original: OriginalContent?
    let removal: LibraryRemoval
    let requiresReconciliation: Bool
    let statuses: [LibraryStatus]
    var operationResults: [LibraryOperationResult] = []
    var photoRegistrations: [LibraryPhotoRegistration] = []
    var removalOperations: [LibraryRemovalOperation] = []
    var removalUnavailableReason: String? = nil
    var removalReviewInformation: String? = nil

    var id: CaptureID { recording.intent.context.capture }
    var title: String { "動画 \(id.rawValue)" }
    var capturedAt: Date? { recording.intent.capturedAt }
    var captureDateDescription: String {
        guard let capturedAt else { return "撮影日時不明" }
        return "撮影日時：\(capturedAt.formatted(date: .abbreviated, time: .standard))"
    }
    var isDiscardHistory: Bool { removal == .removed(.discard) }
    func status(_ axis: LibraryAxis) -> String {
        statuses.first { $0.axis == axis }?.text ?? "状態を取得できません"
    }
}

nonisolated struct LibrarySnapshot: Equatable, Sendable {
    let revision: UInt64
    let items: [LibraryItem]
    var recordings: [LibraryItem] { items.filter { !$0.isDiscardHistory } }
    var history: [LibraryItem] { items.filter(\.isDiscardHistory) }
}

nonisolated enum LibraryReadFailure: Equatable, Sendable {
    case inaccessible, unknownSchema, corruptStore, changing, identityMismatch

    var message: String {
        switch self {
        case .inaccessible: "保存記録を読み込めません。アクセス可能になってから再読み込みしてください。"
        case .unknownSchema: "この保存記録の形式には対応していません。記録を保持しています。"
        case .corruptStore: "保存記録を確認できません。記録を保持しています。"
        case .changing: "保存記録が更新中です。再読み込みしてください。"
        case .identityMismatch: "原本と保存記録の対応を確認できません。記録の照合が必要です。"
        }
    }
}

nonisolated enum LibraryLoadResult: Equatable, Sendable {
    case loaded(LibrarySnapshot)
    case unavailable(LibraryReadFailure)
}

nonisolated protocol LibraryReadPort: Sendable {
    func loadLibrary() async -> LibraryLoadResult
}

nonisolated enum LibraryProjection {
    static func item(_ recording: RecordingStoreEntry, file: OriginalFileObservation,
                     state: OriginalPersistentState?,
                     photoRegistrations: [PhotoRegistrationRecord]? = nil,
                     backend: BackendStoreSnapshot? = nil) -> LibraryItem {
        let bindingMatches = state.map {
            $0.binding.reference == recording.intent.original
                && $0.binding.original.capture == recording.intent.context.capture
                && $0.binding.saveRecord == recording.result
                && $0.binding.saveCommit == recording.resultCommit
        } ?? true
        let bound = bindingMatches ? state : nil
        let identityUnresolved = recording.result != nil && bound == nil
        let removal: LibraryRemoval
        if let intent = bound?.removal ?? bound?.resolvedRemoval {
            if intent.original != bound?.binding.original {
                removal = .reconciliationRequired(intent.purpose)
            } else if bound?.removal != nil {
                removal = .reconciliationRequired(intent.purpose)
            } else {
                switch (bound?.removalResolution, file) {
                case (.removed, .absent): removal = .removed(intent.purpose)
                case (.notRemoved, .present): removal = .notRemoved(intent.purpose)
                default: removal = .reconciliationRequired(intent.purpose)
                }
            }
        } else if !bindingMatches || file == .absent {
            removal = .reconciliationRequired(nil)
        } else {
            removal = .none
        }
        let removalUnresolved: Bool
        if case .reconciliationRequired = removal { removalUnresolved = true } else { removalUnresolved = false }
        let intentionallyRemoved: Bool
        if case .removed = removal { intentionallyRemoved = true } else { intentionallyRemoved = false }
        let saveUnresolved = recording.result == nil || {
            if case .unknown = recording.result?.result { return true }
            return false
        }()
        let fileUnresolved: Bool
        switch file {
        case .present(let count): fileUnresolved = recording.result.map { $0.file.byteCount != count } ?? true
        case .absent: fileUnresolved = !intentionallyRemoved
        case .unavailable: fileUnresolved = true
        }
        let photoRows = LibraryPhotoRegistration.project(photoRegistrations ?? [],
            capture: recording.intent.context.capture)
        let synchronized = backend.map { synchronizedStatuses(original: bound?.binding.original, backend: $0) } ?? [:]
        let statuses = LibraryAxis.allCases.map { axis -> LibraryStatus in
            let value: String
            switch axis {
            case .save:
                switch recording.result?.result {
                case .saved: value = "正常保存"
                case .partial: value = "部分保存"
                case .unknown: value = "保存結果不明・要照合"
                case .failed: value = "保存失敗"
                case nil: value = "保存結果未確定・要照合"
                }
            case .original:
                switch file {
                case .present:
                    value = identityUnresolved ? "原本あり・内容の対応未確定・要照合" : "原本あり"
                case .absent: value = "原本なし"
                case .unavailable: value = "アクセスできません・要照合"
                }
            case .removal:
                switch removal {
                case .none: value = "削除記録なし"
                case .removed(.cleanup): value = "容量整理済み（原本削除を照合済み）"
                case .removed(.discard): value = "破棄済み（原本削除を照合済み）"
                case .notRemoved(.cleanup): value = "容量整理：原本は未削除"
                case .notRemoved(.discard): value = "破棄：原本は未削除"
                case .reconciliationRequired: value = "削除結果を確定できません・要照合"
                }
            case .invalidation:
                // A reservation is not a committed invalidation or an ACK.
                value = bound?.invalidation == nil
                    ? synchronized[axis] ?? "確認の失効状態はまだ取得できません"
                    : "失効処理の予約あり・結果の照合が必要です"
            case .transfer: value = synchronized[axis] ?? "転送機能がまだ利用できないため状態を取得できません"
            case .verification: value = synchronized[axis] ?? "Mac miniの保存検証記録はまだ取得できません"
            case .publication: value = synchronized[axis] ?? "軽量版の公開状態はまだ取得できません"
            case .retrieval: value = synchronized[axis] ?? "軽量版の取得状態はまだ確認できません"
            case .confirmation: value = synchronized[axis] ?? "軽量版の確認記録はまだ取得できません"
            case .photos:
                value = photoRegistrations == nil ? "写真への保存記録はまだ取得できません"
                    : photoRows.isEmpty ? "写真への登録記録なし"
                    : photoRows.map { "\($0.title)：\($0.registrationResult)" }.joined(separator: "\n")
            case .photoPresence:
                value = photoRegistrations == nil ? "写真側の存在はまだ照合できません"
                    : photoRows.isEmpty ? "写真側の存在の照合記録なし"
                    : photoRows.map { "\($0.title)：\($0.presenceResult)" }.joined(separator: "\n")
            }
            return LibraryStatus(axis: axis, text: value)
        }
        return LibraryItem(recording: recording, file: file, original: bound?.binding.original,
            removal: removal,
            requiresReconciliation: !bindingMatches || identityUnresolved || saveUnresolved || fileUnresolved
                || removalUnresolved || photoRows.contains(where: \.requiresReconciliation),
            statuses: statuses, photoRegistrations: photoRows)
    }

    /// These labels describe the last durable facts, not live server reachability
    /// or media availability. A failed poll never erases a valid local record.
    private static func synchronizedStatuses(original: OriginalContent?, backend: BackendStoreSnapshot) -> [LibraryAxis: String] {
        guard let original else { return [:] }
        var result: [LibraryAxis: String] = [:]
        guard let registration = backend.registrations.last, registration.isCommitted else {
            result[.publication] = "公開版の保存記録なし・端末登録を確認してください"
            result[.confirmation] = "有効な明示確認の保存記録なし"
            result[.invalidation] = "失効の保存記録なし（未照合を含む）"
            result[.retrieval] = "端末内の軽量版は未確認・オフライン再生は保証できません"
            return result
        }
        let identity = registration.server.registration
        let publication = backend.publications.last(where: {
            PublicationStoreBoundary.exact($0.observation.registration, identity)
                && PublicationStoreBoundary.exact($0.observation.rendition.original, original)
                && $0.commit.matches(BackendStoreChange.publication($0.observation).key, revision: $0.commit.previousRevision)
        })
        let state = backend.confirmationStates.first(where: {
            PublicationStoreBoundary.exact($0.registration, identity)
                && PublicationStoreBoundary.exact($0.current.original, original)
        })
        result[.publication] = publication == nil ? "公開版の保存記録なし（未照合を含む）"
            : "公開版の保存記録あり（最後に照合した版）"
        if let state, let confirmation = state.validConfirmation,
           PublicationStoreBoundary.exact(confirmation.intent.playback.distribution.registration, identity),
           PublicationStoreBoundary.exact(confirmation.intent.playback.distribution.rendition, state.current) {
            result[.confirmation] = "有効な明示確認の保存記録あり（現在の記録版）"
        } else {
            result[.confirmation] = state?.invalidation == nil ? "現在の記録版の明示確認なし"
                : "確認は失効済み・有効な明示確認なし"
        }
        if let ack = backend.invalidations.last(where: {
            PublicationStoreBoundary.exact($0.record.registration, identity)
                && PublicationStoreBoundary.exact($0.record.rendition.original, original) && $0.isCommitted
        }) {
            let entry = BackendSyncEntry.invalidation(ack)
            let delivered = backend.deliveries.contains(where: {
                PublicationStoreBoundary.exact($0.entry, entry)
                    && PublicationStoreBoundary.exact($0.registration, identity)
                    && PublicationStoreBoundary.exact($0.response, BackendSyncResponse.invalidation(ack.record.id))
            })
            result[.invalidation] = delivered ? "失効保存済み・この登録のACK送達確認済み"
                : "失効保存済み・この登録のACK送達は要照合"
        } else { result[.invalidation] = "失効の保存記録なし（未照合を含む）" }
        let temporary = backend.temporaryMedia.filter {
            PublicationStoreBoundary.exact($0.registration, identity)
                && PublicationStoreBoundary.exact($0.rendition.original, original) && !$0.reclaimed
        }
        result[.retrieval] = temporary.isEmpty ? "端末内の軽量版の取得記録なし・オフライン再生不可"
            : "端末内の軽量版の取得記録あり・再生可否は実媒体の照合が必要"
        let verification = backend.verifications.last(where: {
            PublicationStoreBoundary.exact($0.expected.registration, identity)
                && PublicationStoreBoundary.exact($0.expected.target, MediaTarget.original(original))
        })
        result[.verification] = verification?.isCommitted == true
            && verification?.evidence.verifies(original, destination: identity.destination, supportedSchemas: ["fr-final-read-v1"]) == true
            ? "最後の有効なMac mini保存検証の記録あり（現在の存在は未照合）"
            : "有効なMac mini保存検証の保存記録なし"
        let requests = backend.requests.filter {
            PublicationStoreBoundary.exact($0.registration, identity)
                && PublicationStoreBoundary.exact($0.target, MediaTarget.original(original))
        }
        if let request = requests.last {
            if request.intent == .cancelled { result[.transfer] = "本人キャンセルの記録あり（Macの実結果とは別）" }
            else if request.intent == .paused { result[.transfer] = "本人停止の記録あり" }
            else if !request.waits.isEmpty { result[.transfer] = "転送の待機記録あり" }
            else if request.transport == .completed { result[.transfer] = "端末の送信完了記録あり（保存検証とは別）" }
            else { result[.transfer] = "開始済みの転送記録あり・結果は要照合" }
        } else { result[.transfer] = "この登録からの転送開始記録なし" }
        return result
    }
}
