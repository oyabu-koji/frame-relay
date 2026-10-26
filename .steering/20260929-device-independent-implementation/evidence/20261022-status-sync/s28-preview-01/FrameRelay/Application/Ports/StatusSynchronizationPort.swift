import Foundation

/// Presentation of one explicit, bounded metadata operation. Durable facts are
/// always read back from the common writer; this report is not confirmation or
/// permission to retrieve media.
nonisolated enum StatusSynchronizationDisposition: Equatable, Sendable {
    case recorded, unchanged, noPublishedRecord, unresolved

    var text: String {
        switch self {
        case .recorded: "状態の記録を保存しました"
        case .unchanged: "保存済みの状態と照合しました"
        case .noPublishedRecord: "今回は公開版の情報がありません。媒体は取得していません"
        case .unresolved: "状態の照合が必要です。保存済みの記録を保持しています"
        }
    }
}

nonisolated struct StatusSynchronizationItem: Equatable, Sendable, Identifiable {
    let original: OriginalContent
    let disposition: StatusSynchronizationDisposition
    var id: CaptureID { original.capture }
}

nonisolated struct StatusSynchronizationReport: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case checked, partial, waitingForCapture, unavailable, busy }
    let phase: Phase
    var items: [StatusSynchronizationItem] = []
    var hasMore = false
    var unresolvedInvalidations = 0

    var message: String {
        switch phase {
        case .checked: "今回の状態照合を終えました。ライブラリには保存済みの記録を表示します。"
        case .partial: "状態照合は一部だけ終わっています。続きや未解決の記録を照合してください。"
        case .waitingForCapture: "録画・保存を優先しています。終了後に状態を照合してください。"
        case .unavailable: "登録と保存記録の対応を確認できません。前回の記録を保持しています。"
        case .busy: "状態を照合中です。"
        }
    }
}

nonisolated protocol StatusSynchronizationPort: Sendable {
    func synchronize(connection: RegistrationConnection, registration: DeviceRegistration) async -> StatusSynchronizationReport
}
