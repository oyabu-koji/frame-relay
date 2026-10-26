import Foundation

nonisolated protocol RemoteInventoryRemotePort: Sendable {
    func page(registration: RegistrationIdentity, after: String?) async -> BackendOutcome<RemoteInventoryPage>
}

nonisolated struct RemoteInventoryReport: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case recorded, reconciliationRequired, unavailable, busy, waitingForCapture }
    let phase: Phase
    var receivedCount = 0
    var hasMore = false
    var message: String {
        switch phase {
        case .recorded:
            "今回の保存記録\(receivedCount)件を照合しました。ライブラリに保存済みの記録を表示します。"
        case .reconciliationRequired:
            "保存記録の確定を照合中です。同じ結果を再照合するまで続きは取得しません。"
        case .unavailable:
            "Macの保存記録を照合できません。ライブラリの保存済み記録を保持しています。"
        case .busy: "Macの保存記録を照合中です。"
        case .waitingForCapture: "録画・保存を優先しています。終了後に保存記録を照合してください。"
        }
    }
}

nonisolated protocol RemoteInventoryPort: Sendable {
    func discover(connection: RegistrationConnection, registration: DeviceRegistration) async -> RemoteInventoryReport
}
