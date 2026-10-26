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
    /// Presentation hint only; the single writer rechecks current authority.
    var cleanupUnavailableReason: String? = nil
    /// Candidate only; the consumer rechecks the current writer and real bytes.
    var localRenditionUnavailableReason: String? = LocalRenditionSelection.unavailableReason
    var photoSaveSource: PhotoSaveSource? = nil
    var photoSaveUnavailableReason: String? = LocalRenditionSelection.unavailableReason
    var mediaRequests: [LibraryMediaRequest] = []
    /// Exact saved input for a new request; presence is checked separately.
    var uploadCandidateBinding: OriginalBinding? = nil
    var originalUploadAcceptances: [StoredOriginalUploadAcceptance] = []

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
    var remoteItems: [LibraryRemoteItem] = []
    var photoSaveBatches: [PhotoSaveBatchRecord] = []
    var storeIdentity: RegistrationStoreIdentity? = nil
    var mediaRequests: [LibraryMediaRequest] = []
    var personControls: [StoredMediaPersonControlPlan] = []
    var uploadRegistration: DeviceRegistration? = nil
    var originalUploadAcceptances: [StoredOriginalUploadAcceptance] = []
    var recordings: [LibraryItem] { items.filter { !$0.isDiscardHistory } }
    var history: [LibraryItem] { items.filter(\.isDiscardHistory) }
}

/// A server metadata row never manufactures a capture save or local file reference.
nonisolated struct LibraryRemoteItem: Equatable, Sendable, Identifiable {
    let destination: DestinationIdentity
    let original: OriginalContent
    let hasIdentityConflict: Bool
    var publicationDescription: String = "公開版の保存記録なし（未照合を含む）"
    var retrievalDescription: String = "端末内の軽量版の取得記録なし・オフライン再生不可"
    var localRenditionUnavailableReason: String? = LocalRenditionSelection.unavailableReason
    var photoSaveSource: PhotoSaveSource? = nil
    var photoSaveUnavailableReason: String? = LocalRenditionSelection.unavailableReason
    var photoRegistrations: [LibraryPhotoRegistration] = []
    var mediaRequests: [LibraryMediaRequest] = []
    var id: RemoteInventoryOriginalID { .init(destination: destination, original: original) }
    var title: String { "動画 \(original.capture.rawValue)" }
    var captureDateDescription: String { "撮影日時不明" }
    var storageDescription: String { "Macの原本保存記録あり（今回の原本の現在存在は未照合）" }
    var localDescription: String {
        hasIdentityConflict ? "同じ動画の識別情報に異なる内容があります。原本の対応は要照合です。"
            : "このiPhoneの原本保存記録との対応はありません。"
    }
    var mediaDescription: String {
        localRenditionUnavailableReason == nil
            ? "完全取得済みの軽量版を端末内から再生できます。開始時に実媒体を照合します。取得記録や再生だけでは明示確認済みになりません。"
            : "軽量版の取得・再生はまだ利用できません。保存記録の取得だけでは確認済みになりません。"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.hasIdentityConflict == rhs.hasIdentityConflict
            && lhs.publicationDescription == rhs.publicationDescription
            && lhs.retrievalDescription == rhs.retrievalDescription
            && lhs.localRenditionUnavailableReason == rhs.localRenditionUnavailableReason
            && lhs.photoSaveSource == rhs.photoSaveSource
            && lhs.photoSaveUnavailableReason == rhs.photoSaveUnavailableReason
            && lhs.photoRegistrations == rhs.photoRegistrations
            && lhs.mediaRequests == rhs.mediaRequests
    }
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
        let state = backend.confirmationStates.first(where: {
            PublicationStoreBoundary.exact($0.registration, identity)
                && PublicationStoreBoundary.exact($0.current.original, original)
        })
        let media = LibraryPublicationProjection.statuses(original: original, registration: identity, backend: backend)
        result[.publication] = media.publication
        if let state, let confirmation = state.validConfirmation,
           PublicationStoreBoundary.exact(confirmation.intent.playback.distribution.registration, identity),
           PublicationStoreBoundary.exact(confirmation.intent.playback.distribution.rendition, state.current),
           PublicationStoreBoundary.exact(confirmation.commit.key, confirmation.intent.key) {
            result[.confirmation] = "有効な明示確認の保存記録あり（現在の記録版）"
        } else {
            result[.confirmation] = state?.invalidation == nil ? "現在の記録版の明示確認なし"
                : "確認は失効済み・有効な明示確認なし"
        }
        if let ack = backend.invalidations.last(where: {
            PublicationStoreBoundary.exact($0.record.registration, identity)
                && PublicationStoreBoundary.exact($0.record.rendition.original, original) && $0.isCommitted
                && PublicationStoreBoundary.exact($0.commit.key, $0.record.key)
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
        result[.retrieval] = media.retrieval
        let verification = backend.verifications.last(where: {
            PublicationStoreBoundary.exact($0.expected.registration, identity)
                && PublicationStoreBoundary.exact($0.expected.target, MediaTarget.original(original))
        })
        let verified = verification.map { proof in
            guard proof.isCommitted, PublicationStoreBoundary.exact(proof.expected, proof.evidence.context),
                  PublicationStoreBoundary.exact(proof.commit.key, proof.key),
                  case .finalDestinationReadBack(let content) = proof.evidence.verification,
                  PublicationStoreBoundary.exact(content, original.content) else { return false }
            return proof.evidence.verifies(original, destination: identity.destination, supportedSchemas: ["fr-final-read-v1"])
        } ?? false
        result[.verification] = verified
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
            else if request.transport == .queued { result[.transfer] = "転送要求は受付済み・通信はまだ開始していません" }
            else { result[.transfer] = "開始済みの転送記録あり・結果は要照合" }
        } else { result[.transfer] = "この登録からの転送開始記録なし" }
        return result
    }
}

/// Last durable metadata and local retrieval facts are presentation only. They
/// neither promise current reachability nor authorize playback or deletion.
nonisolated enum LibraryPublicationProjection {
    static func statuses(original: OriginalContent, registration: RegistrationIdentity,
        backend: BackendStoreSnapshot) -> (publication: String, retrieval: String) {
        guard let current = backend.registrations.last(where: {
            PublicationStoreBoundary.exact($0.server.registration.destination, registration.destination)
        }), current.isCommitted, PublicationStoreBoundary.exact(current.server.registration, registration) else {
            return ("公開版の保存記録なし・現在の端末登録を確認してください",
                "現在の登録での取得状態は未確認・オフライン再生は保証できません")
        }
        let observation = backend.publicationManifests.last { row in
            row.isCommitted && row.observation.storeIdentity == backend.storeIdentity
                && PublicationStoreBoundary.exact(row.observation.registration, registration)
                && PublicationStoreBoundary.exact(row.observation.original, original)
        }?.observation
        let authority = backend.publications.last { row in
            PublicationStoreBoundary.exact(row.observation.registration, registration)
                && PublicationStoreBoundary.exact(row.observation.rendition.original, original)
                && row.commit.matches(BackendStoreChange.publication(row.observation).key, revision: row.commit.previousRevision)
                && PublicationStoreBoundary.exact(row.commit.key, BackendStoreChange.publication(row.observation).key)
        }?.observation
        let rendition = observation?.manifest.current ?? authority?.rendition
        let publication: String
        if let observation {
            let manifest = observation.manifest
            if let current = manifest.current {
                publication = "公開版の保存記録あり（最後に照合した版）\n公開版ID：\(current.rendition.rawValue)"
                    + "\n公開世代：\(current.publicationGeneration.rawValue)・観測版：\(manifest.revision)・失効世代：\(manifest.invalidationGeneration.rawValue)"
                    + "\n媒体形式：\(manifest.mediaType ?? "不明")"
                    + (manifest.replacementPending ? "\n置換待ち（現在の取得・再生可否とは別）" : "\n最後の照合時に置換待ちなし")
            } else {
                publication = "最後の照合では公開版なし（観測版：\(manifest.revision)・失効世代：\(manifest.invalidationGeneration.rawValue)）"
                    + (authority == nil ? "" : "\n以前の公開・確認の記録は保持しています。現在の公開状態は要照合です。")
            }
        } else if let authority {
            publication = "公開版の保存記録あり（最後に照合した版）\n公開版ID：\(authority.rendition.rendition.rawValue)"
                + "\n公開世代：\(authority.rendition.publicationGeneration.rawValue)・観測版：\(authority.observation.rawValue)"
                + "\n媒体形式・置換待ちは未照合"
        } else { publication = "公開版の保存記録なし（未照合を含む）" }
        let temporary = backend.temporaryMedia.filter { media in
            PublicationStoreBoundary.exact(media.registration, registration) && !media.reclaimed && !media.reclaiming
                && rendition.map { PublicationStoreBoundary.exact(media.rendition, $0) } == true
        }
        let invalidated = rendition.map { current in
            backend.invalidations.contains { row in
                row.isCommitted && PublicationStoreBoundary.exact(row.record.registration, registration)
                    && PublicationStoreBoundary.exact(row.record.rendition, current)
            }
        } ?? false
        let retrieval: String
        if observation != nil && observation?.manifest.current == nil {
            retrieval = "最後の照合では公開版なし・取得や再生の利用可否は要照合です"
        } else if invalidated {
            retrieval = "この版は失効済み・再生に利用できません（過去の取得記録とは別）"
        } else if temporary.isEmpty {
            retrieval = "端末内の軽量版の取得記録なし・オフライン再生不可"
        } else if temporary.contains(where: { $0.complete && $0.verifiedContent == $0.rendition.deliveryContent }) {
            retrieval = "この版の完全取得の記録あり・再生可否は実媒体の照合が必要"
        } else {
            retrieval = "この版の部分取得の記録あり・完全媒体と再生可否は未確認"
        }
        return (publication, retrieval)
    }
}
