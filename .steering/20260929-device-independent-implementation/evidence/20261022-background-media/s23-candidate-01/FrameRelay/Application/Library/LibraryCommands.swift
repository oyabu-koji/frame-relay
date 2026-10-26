nonisolated enum LibraryAction: String, CaseIterable, Sendable, Identifiable {
    case transfer, saveToPhotos, cleanup, playOriginal, playRendition, confirmRendition, discard

    var id: String { rawValue }
    var supportsMultiple: Bool { self == .transfer || self == .saveToPhotos || self == .cleanup }
    var isPlayback: Bool { self == .playOriginal || self == .playRendition }
    static var multiple: [Self] { allCases.filter(\.supportsMultiple) }
    static var single: [Self] { allCases.filter { !$0.supportsMultiple } }

    var title: String {
        switch self {
        case .transfer: "Mac miniへ転送"
        case .saveToPhotos: "軽量版を写真に保存"
        case .cleanup: "原本の容量整理"
        case .playOriginal: "iPhone原本を再生"
        case .playRendition: "軽量版を再生"
        case .confirmRendition: "この軽量版を確認"
        case .discard: "不要な原本を破棄"
        }
    }

    var unavailableReason: String {
        switch self {
        case .transfer: "Mac miniへの転送機能はまだ利用できません。"
        case .saveToPhotos: "軽量版の取得と写真への保存機能はまだ利用できません。"
        case .cleanup: "保存検証・明示確認の照合と容量整理機能はまだ利用できません。"
        case .playOriginal: "原本の再生機能はまだ利用できません。"
        case .playRendition: "軽量版の取得・再生機能はまだ利用できません。"
        case .confirmRendition: "同じ軽量版の実再生と確認記録の保存が必要です。この機能はまだ利用できません。"
        case .discard: "原本の破棄と削除結果の照合機能はまだ利用できません。"
        }
    }
}

nonisolated enum LibraryActionAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
    var reason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

nonisolated struct LibraryCommandTarget: Equatable, Sendable {
    let capture: CaptureID
    let reference: CaptureOriginalReference
    let original: OriginalContent?
}

/// Fixed at the explicit start. Selection changes cannot insert or remove targets.
/// The receiving operation coordinator must persist its own intent and recheck
/// every target/identity and latest evidence; this UI snapshot is not authority.
nonisolated struct LibraryCommandRequest: Equatable, Sendable {
    let id: MediaOperationID
    let action: LibraryAction
    let targets: [LibraryCommandTarget]
    let displayedRevision: UInt64
    let discardRiskAcknowledged: Bool
}

nonisolated enum LibraryCommandResponse: Equatable, Sendable {
    case accepted
    case rejected(String)
    case unknown
}

nonisolated protocol LibraryCommandPort: Sendable {
    /// Display hint only. submit must re-evaluate after any intervening changes.
    /// UI availability can read a MainActor-owned player without unsafe isolation escapes.
    @MainActor
    func availability(_ action: LibraryAction, items: [LibraryItem]) -> LibraryActionAvailability
    func submit(_ request: LibraryCommandRequest) async -> LibraryCommandResponse
}

nonisolated struct UnconnectedLibraryCommands: LibraryCommandPort {
    func availability(_ action: LibraryAction, items: [LibraryItem]) -> LibraryActionAvailability {
        .unavailable(action.unavailableReason)
    }
    func submit(_ request: LibraryCommandRequest) async -> LibraryCommandResponse {
        .rejected(request.action.unavailableReason)
    }
}

/// Transient input feedback. It deliberately has no success case.
nonisolated enum LibrarySubmissionPhase: Equatable, Sendable {
    case submitting, awaitingRecordedResult, playbackHandedOff, rejected(String), reconciliationRequired
    var text: String {
        switch self {
        case .submitting: "開始を依頼中・結果未確定"
        case .awaitingRecordedResult: "開始受付済み・結果の記録待ち"
        case .playbackHandedOff: "再生機能に引き渡しました。再生状態はプレーヤーで確認してください。"
        case .rejected(let reason): "開始できません：\(reason)"
        case .reconciliationRequired: "受付結果不明・記録の照合が必要です"
        }
    }
}

nonisolated struct LibrarySubmission: Equatable, Sendable, Identifiable {
    let request: LibraryCommandRequest
    var phase: LibrarySubmissionPhase
    var id: MediaOperationID { request.id }
}

/// The dialog owns these exact values. Refresh and selection changes cannot
/// substitute another content generation/reference under the same capture ID.
nonisolated struct LibraryRemovalReview: Equatable, Sendable, Identifiable {
    let id: MediaOperationID
    let action: LibraryAction
    let targets: [LibraryCommandTarget]
    let displayedRevision: UInt64
    let information: [String]
}
