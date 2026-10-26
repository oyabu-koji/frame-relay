import Foundation
import Observation

@MainActor @Observable final class ConnectionModel {
    private let coordinator: RegistrationCoordinator
    private let statusSynchronization: (any StatusSynchronizationPort)?
    private let remoteInventory: (any RemoteInventoryPort)?
    private let didSynchronize: @MainActor @Sendable () async -> Void
    private let synchronizationTargetDescription: @MainActor @Sendable (OriginalContent) -> String
    private(set) var state: RegistrationState = .needsConnection
    private(set) var isWorking = false
    private(set) var isSynchronizing = false
    private(set) var isDiscoveringRemoteInventory = false
    private(set) var hasLoaded = false
    private(set) var permitsInitialInput = false
    private(set) var permitsNewStoreRegistration = false
    private(set) var showsNewStoreRegistrationInput = false
    private(set) var synchronizationReport: StatusSynchronizationReport?
    private(set) var remoteInventoryReport: RemoteInventoryReport?
    var origin = ""
    var destination = ""
    var bearer = ""

    init(coordinator: RegistrationCoordinator, statusSynchronization: (any StatusSynchronizationPort)? = nil,
         remoteInventory: (any RemoteInventoryPort)? = nil,
         didSynchronize: @escaping @MainActor @Sendable () async -> Void = {},
         synchronizationTargetDescription: @escaping @MainActor @Sendable (OriginalContent) -> String = { _ in
             "撮影日時不明（対応する日時の記録を確認できません）"
         }) {
        self.coordinator = coordinator; self.statusSynchronization = statusSynchronization
        self.remoteInventory = remoteInventory
        self.didSynchronize = didSynchronize
        self.synchronizationTargetDescription = synchronizationTargetDescription
    }

    func description(for item: StatusSynchronizationItem) -> String { synchronizationTargetDescription(item.original) }

    var supportsStatusSynchronization: Bool { statusSynchronization != nil }
    var supportsRemoteInventory: Bool { remoteInventory != nil }
    var canDiscoverRemoteInventory: Bool {
        if case .registered = state { return remoteInventory != nil && !isWorking }
        return false
    }
    func discoverRemoteInventory() async {
        guard canDiscoverRemoteInventory, let remoteInventory,
              case .registered(let connection, let registration) = state else { return }
        isWorking = true; isDiscoveringRemoteInventory = true
        defer { isWorking = false; isDiscoveringRemoteInventory = false }
        remoteInventoryReport = await remoteInventory.discover(connection: connection, registration: registration)
        await didSynchronize()
    }
    var canSynchronize: Bool {
        if case .registered = state { return statusSynchronization != nil && !isWorking }
        return false
    }
    func synchronizeStatus() async {
        guard canSynchronize, let statusSynchronization, case .registered(let connection, let registration) = state else { return }
        isWorking = true
        isSynchronizing = true
        defer { isWorking = false; isSynchronizing = false }
        synchronizationReport = await statusSynchronization.synchronize(connection: connection, registration: registration)
        await didSynchronize()
    }

    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false; hasLoaded = true }
        let previousState = state
        state = await coordinator.restore()
        if state != previousState { synchronizationReport = nil; remoteInventoryReport = nil }
        permitsInitialInput = await coordinator.permitsInitialInput()
        permitsNewStoreRegistration = await coordinator.permitsNewStoreRegistration()
        if !permitsNewStoreRegistration { cancelNewStoreRegistrationInput() }
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
        permitsNewStoreRegistration = await coordinator.permitsNewStoreRegistration()
    }
    func registerSavedConnection() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        state = await coordinator.registerSavedConnection()
        permitsInitialInput = await coordinator.permitsInitialInput()
        permitsNewStoreRegistration = await coordinator.permitsNewStoreRegistration()
    }

    func openNewStoreRegistrationInput() {
        guard permitsNewStoreRegistration, !isWorking else { return }
        origin = ""; destination = ""; bearer = ""
        showsNewStoreRegistrationInput = true
    }
    func cancelNewStoreRegistrationInput() {
        bearer = ""
        if showsNewStoreRegistrationInput { origin = ""; destination = "" }
        showsNewStoreRegistrationInput = false
    }
    func registerNewStore() async {
        guard permitsNewStoreRegistration, showsNewStoreRegistrationInput, !isWorking else { return }
        isWorking = true
        let token = bearer; bearer = ""
        defer { isWorking = false }
        do {
            let connection = try RegistrationConnection(endpoint: .init(httpsOrigin: origin), destination: .init(rawValue: destination))
            state = await coordinator.registerNewStore(connection: connection, bearer: token)
        } catch { state = .unavailable(.configuration) }
        permitsInitialInput = await coordinator.permitsInitialInput()
        permitsNewStoreRegistration = await coordinator.permitsNewStoreRegistration()
        if !permitsNewStoreRegistration { cancelNewStoreRegistrationInput() }
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
