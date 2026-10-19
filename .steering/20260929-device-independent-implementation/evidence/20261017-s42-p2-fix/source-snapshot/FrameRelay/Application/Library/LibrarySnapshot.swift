import Foundation

/// Read-only presentation values. These are never a deletion or confirmation authority.
nonisolated enum LibraryAxis: String, CaseIterable, Identifiable, Sendable {
    case save, original, transfer, verification, publication, retrieval, confirmation, invalidation, photos, removal

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
        case .photos: "写真への保存"
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
                     state: OriginalPersistentState?) -> LibraryItem {
        let bindingMatches = state.map {
            $0.binding.reference == recording.intent.original
                && $0.binding.original.capture == recording.intent.context.capture
                && $0.binding.saveRecord == recording.result
                && $0.binding.saveCommit == recording.resultCommit
        } ?? true
        let bound = bindingMatches ? state : nil
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
                case .present: value = "原本あり"
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
                    ? "確認の失効状態はまだ取得できません"
                    : "失効処理の予約あり・結果の照合が必要です"
            case .transfer: value = "転送機能がまだ利用できないため状態を取得できません"
            case .verification: value = "Mac miniの保存検証記録はまだ取得できません"
            case .publication: value = "軽量版の公開状態はまだ取得できません"
            case .retrieval: value = "軽量版の取得状態はまだ確認できません"
            case .confirmation: value = "軽量版の確認記録はまだ取得できません"
            case .photos: value = "写真への保存記録はまだ取得できません"
            }
            return LibraryStatus(axis: axis, text: value)
        }
        return LibraryItem(recording: recording, file: file, original: bound?.binding.original,
            removal: removal,
            requiresReconciliation: !bindingMatches || saveUnresolved || fileUnresolved || removalUnresolved,
            statuses: statuses)
    }
}
