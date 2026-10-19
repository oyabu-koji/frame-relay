import Foundation
import Observation

@MainActor @Observable final class ConnectionModel {
    private let coordinator: RegistrationCoordinator
    private(set) var state: RegistrationState = .needsConnection
    private(set) var isWorking = false
    private(set) var hasLoaded = false
    private(set) var permitsInitialInput = false
    var origin = ""
    var destination = ""
    var bearer = ""

    init(coordinator: RegistrationCoordinator) { self.coordinator = coordinator }

    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false; hasLoaded = true }
        state = await coordinator.restore()
        permitsInitialInput = await coordinator.permitsInitialInput()
    }
    func register() async {
        guard !isWorking else { return }
        isWorking = true
        let token = bearer
        bearer = ""
        defer { isWorking = false }
        do {
            let connection = try RegistrationConnection(endpoint: .init(httpsOrigin: origin),
                destination: .init(rawValue: destination))
            state = await coordinator.register(connection: connection, bearer: token)
            if case .registered = state { origin = ""; destination = "" }
        } catch { state = .unavailable(.configuration) }
        permitsInitialInput = await coordinator.permitsInitialInput()
    }
    func registerSavedConnection() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        state = await coordinator.registerSavedConnection()
        permitsInitialInput = await coordinator.permitsInitialInput()
    }
    var message: String {
        switch state {
        case .needsConnection:
            "Mac miniの接続先と登録情報を入力してください。"
        case .needsRegistration:
            "接続情報を保持しています。端末の登録開始はまだ確定していません。登録を続ける操作で、保存した情報を照合します。"
        case .registered:
            "この端末の登録を保存しています。動画の転送・写真保存・確認状態とは別の記録です。"
        case .pending:
            "登録の結果を確認できていません。照合では前回と同じ登録情報を使います。"
        case .unavailable(let issue):
            switch issue {
            case .configuration: "HTTPSの接続先URL（パスなし）と接続先ID、認証情報を確認してください。"
            case .credentials: "保存した認証情報を利用できません。端末のロック状態を確認してから再照合してください。"
            case .credentialConflict: "保存した認証情報との対応が一致しません。登録情報を保持しています。"
            case .storage: "端末の登録記録を確認できません。保存領域の状態を確認してから再照合してください。"
            case .identity: "接続先または登録の対応が一致しません。前回の記録を保持しています。"
            case .authentication: "認証が成立しませんでした。初回入力は認証情報を確認し、登録済みの場合はMac mini側の設定を確認してください。"
            case .connection: "接続を確認できません。回線とMac miniを確認してから再照合してください。"
            case .protocolMismatch: "接続先の登録方式に対応していません。Mac mini側の対応状況を確認してください。"
            case .busy: "登録の処理中です。"
            }
        }
    }
}
