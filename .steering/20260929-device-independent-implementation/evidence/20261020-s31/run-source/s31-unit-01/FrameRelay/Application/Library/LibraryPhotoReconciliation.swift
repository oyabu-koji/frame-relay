/// Read-only projection of each persisted attempt. Historical registration and
/// the last observed Photos presence deliberately remain separate facts.
nonisolated struct LibraryPhotoRegistration: Equatable, Sendable, Identifiable {
    let record: PhotoRegistrationRecord
    let isLatestAttempt: Bool

    var id: MediaOperationID { record.registration.intent.operation }
    var key: PhotoRegistrationKey { record.registration.intent.key }
    var title: String { "軽量版 \(key.rendition.rawValue)" }

    var registrationResult: String {
        switch record.outcome {
        case .succeeded: "過去の登録成功"
        case .failed(let failure): "過去の登録失敗：\(failureText(failure))"
        case .notAttempted(let failure): "追加未実行：\(failureText(failure))"
        case .unknown: "過去の登録結果不明・要照合"
        case nil: "登録意図あり・追加結果未確定・要照合"
        }
    }

    var presenceResult: String {
        guard let observed = record.currentPresence else {
            return record.localIdentifier == nil ? "写真との対応不明（識別情報なし）" : "写真側の存在は未照合"
        }
        switch observed.presence {
        case .present:
            return observed.authorization == .limited ? "前回照合：限定された読取範囲で写真あり" : "前回照合：写真あり"
        case .notFound:
            return observed.authorization == .limited
                ? "前回照合：限定された読取範囲で未発見。未保存とは判定できません"
                : "前回照合：読取可能な範囲で未発見。未保存とは判定できません"
        case .correspondenceUnknown: return "写真との対応不明（識別情報なし）"
        case .unavailable:
            switch observed.authorization {
            case .denied: return "前回照合：読み取り拒否のため存在を確認できません"
            case .restricted: return "前回照合：読み取り制限のため存在を確認できません"
            case .limited: return "前回照合：限定された読取範囲では存在を確認できません"
            case .notDetermined: return "前回照合：読み取り未許可のため存在を確認できません"
            case .authorized: return "前回照合：読み取り可能ですが存在を確認できません"
            case .unknown: return "前回照合：読み取り権限が不明のため存在を確認できません"
            }
        }
    }

    var requiresReconciliation: Bool {
        switch record.outcome {
        case nil, .unknown: return true
        case .succeeded, .notAttempted, .failed: return false
        }
    }

    /// An explained user action may refresh presence for the current attempt.
    /// No request is useful when the exact persisted identifier is absent.
    var reconciliationReason: String? {
        guard isLatestAttempt else { return nil }
        switch record.outcome {
        case .notAttempted, .failed: return nil
        case nil, .unknown:
            return "この軽量版の追加結果が未確定です。写真側の存在を、保存された識別情報で照合します。存在が分かっても過去の登録結果は変更しません。"
        case .succeeded:
            return "この軽量版は過去に登録が成功しています。写真側の現在の存在を確かめるため、保存された識別情報で照合します。"
        }
    }

    var reconciliationUnavailableReason: String? {
        guard reconciliationReason != nil, record.localIdentifier == nil else { return nil }
        return "写真側の識別情報が保存されていないため照合できません。追加の読み取り許可だけでは、この動画との対応を確定できません。"
    }

    var canReconcile: Bool { reconciliationReason != nil && record.localIdentifier != nil }

    static func project(_ records: [PhotoRegistrationRecord], capture: CaptureID) -> [Self] {
        let matching = records.filter { $0.registration.intent.key.capture == capture }
        return matching.map { record in
            .init(record: record, isLatestAttempt:
                matching.last { $0.registration.intent.key == record.registration.intent.key }?
                    .registration.intent.operation == record.registration.intent.operation)
        }
    }

    private func failureText(_ failure: PhotoLibraryFailure) -> String {
        switch failure {
        case .authorizationRequired: "写真への追加権限がありません"
        case .restricted: "写真への追加が制限されています"
        case .inaccessible: "写真へアクセスできません"
        case .invalidMedia: "この動画を写真へ追加できません"
        case .rejected: "写真への追加が拒否されました"
        }
    }
}

nonisolated protocol LibraryPhotoReconciliationPort: Sendable {
    func reconcile(_ intent: PhotoRegistrationIntent,
                   action: MediaOperationID) async -> BackendOutcome<PhotoRegistrationRecord>
}

/// Composition injects the common writer and native port. Merely constructing
/// this bridge or loading the Library never queries or requests Photos access.
actor LibraryPhotoReconciliation: LibraryPhotoReconciliationPort {
    private let store: any MediaOperationStorePort
    private let library: any PhotoLibraryPort
    private var reconciler: PhotoRegistrationReconciler?
    private var storeIdentity: RegistrationStoreIdentity?

    init(store: any MediaOperationStorePort, library: any PhotoLibraryPort) {
        self.store = store
        self.library = library
    }

    func reconcile(_ intent: PhotoRegistrationIntent,
                   action: MediaOperationID) async -> BackendOutcome<PhotoRegistrationRecord> {
        guard case .loaded(let snapshot) = await store.load(),
              let identity = snapshot.storeIdentity else { return .unknown }
        // Re-check the exact displayed attempt before a possible permission prompt.
        guard let latest = snapshot.photoRegistrations.last(where: { $0.registration.intent.key == intent.key }),
              latest.registration.intent == intent else { return .notExecuted }
        let row = LibraryPhotoRegistration(record: latest, isLatestAttempt: true)
        guard row.canReconcile else { return .notExecuted }
        if storeIdentity != identity || reconciler == nil {
            storeIdentity = identity
            reconciler = PhotoRegistrationReconciler(store: store, identity: identity, library: library)
        }
        guard let reconciler else { return .unknown }
        return await reconciler.reconcile(intent.key, action: action)
    }
}

/// The save entry remains unavailable until the ordinary rendition producer is
/// connected; implemented Photos I/O does not manufacture a product rendition.
@MainActor final class PhotoAwareLibraryCommands: LibraryCommandPort {
    private let base: any LibraryCommandPort
    init(base: any LibraryCommandPort) { self.base = base }

    func availability(_ action: LibraryAction, items: [LibraryItem]) -> LibraryActionAvailability {
        guard action == .saveToPhotos else { return base.availability(action, items: items) }
        return .unavailable("Mac miniから軽量版を取得して写真に保存する操作は、まだ利用できません。過去の登録記録は表示し、必要な場合は写真側の状態を照合できます。")
    }

    func submit(_ request: LibraryCommandRequest) async -> LibraryCommandResponse {
        guard request.action != .saveToPhotos else {
            return .rejected(availability(request.action, items: []).reason ?? request.action.unavailableReason)
        }
        return await base.submit(request)
    }
}
