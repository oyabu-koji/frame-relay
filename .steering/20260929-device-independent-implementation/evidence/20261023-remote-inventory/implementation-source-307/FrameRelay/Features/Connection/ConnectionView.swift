import SwiftUI

struct ConnectionView: View {
    @Bindable var model: ConnectionModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.message)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("connection.state")
                    if model.isWorking {
                        ProgressView(model.isDiscoveringRemoteInventory ? "Macの保存記録を照合しています"
                            : model.isSynchronizing ? "状態を照合しています" : "登録情報を確認しています")
                    }
                }
                if case .registered(_, let registration) = model.state {
                    Section("端末登録") {
                        Text("登録世代 \(registration.server.registration.generation.rawValue)")
                            .accessibilityIdentifier("connection.registered")
                    }
                    if model.supportsRemoteInventory {
                        Section("Macの保存記録") {
                            Text("この接続先に保存した動画の記録を1ページずつ照合します。動画は取得しません。以前の軽量版の確認は引き継ぎません。")
                                .fixedSize(horizontal: false, vertical: true)
                            Button(model.remoteInventoryReport?.hasMore == true ? "続きの保存記録を照合" : "Macの保存記録を照合") {
                                Task { await model.discoverRemoteInventory() }
                            }
                            .disabled(!model.canDiscoverRemoteInventory)
                            .accessibilityIdentifier("connection.inventory")
                            if let report = model.remoteInventoryReport {
                                Text(report.message).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("connection.inventory.state")
                            }
                        }
                    }
                    if model.supportsStatusSynchronization {
                        Section("状態の同期") {
                            Text("公開版と保存済みの確認・失効記録を照合します。動画は送受信しません。")
                                .fixedSize(horizontal: false, vertical: true)
                            Button(model.synchronizationReport?.hasMore == true ? "続きの状態を照合" : "状態だけを同期") {
                                Task { await model.synchronizeStatus() }
                            }
                            .disabled(!model.canSynchronize)
                            .accessibilityIdentifier("connection.synchronize")
                            if let report = model.synchronizationReport {
                                Text(report.message).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("connection.synchronization.state")
                                ForEach(report.items) { item in
                                    Text("\(model.description(for: item))：\(item.disposition.text)")
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } else if case .needsRegistration = model.state {
                    Button("保存した情報で登録を続ける") { Task { await model.registerSavedConnection() } }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("connection.continue")
                } else if case .pending = model.state {
                    reconcileButton
                } else if model.showsNewStoreRegistrationInput {
                    Section("新しい登録の接続情報") {
                        newStoreExplanation
                        TextField("HTTPSの接続先URL（パスなし）", text: $model.origin)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .accessibilityIdentifier("connection.new.origin")
                        TextField("接続先ID", text: $model.destination)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("connection.new.destination")
                        SecureField("認証トークン", text: $model.bearer)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("connection.new.bearer")
                        Button("接続先を確認して新しい登録を開始") { Task { await model.registerNewStore() } }
                            .disabled(model.isWorking)
                            .accessibilityIdentifier("connection.new.register")
                        Button("新しい登録の入力をやめる", role: .cancel) { model.cancelNewStoreRegistrationInput() }
                            .disabled(model.isWorking)
                            .accessibilityIdentifier("connection.new.cancel")
                    }
                } else if model.permitsInitialInput {
                    Section("初回の接続情報") {
                        TextField("HTTPSの接続先URL（パスなし）", text: $model.origin)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .accessibilityIdentifier("connection.origin")
                        TextField("接続先ID", text: $model.destination)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("connection.destination")
                        SecureField("認証トークン", text: $model.bearer)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("connection.bearer")
                        Button("接続先を確認して端末を登録") { Task { await model.register() } }
                            .disabled(model.isWorking)
                            .accessibilityIdentifier("connection.register")
                    }
                    reconcileButton
                } else {
                    reconcileButton
                    if model.permitsNewStoreRegistration {
                        Section("新しい端末登録") {
                            newStoreExplanation
                            Button("新しい端末登録を始める") { model.openNewStoreRegistrationInput() }
                                .disabled(model.isWorking)
                                .accessibilityIdentifier("connection.new.open")
                        }
                    }
                }
            }
            .navigationTitle("Mac miniとの接続")
            .toolbar { Button("閉じる") { model.cancelNewStoreRegistrationInput(); dismiss() }.accessibilityIdentifier("connection.close") }
            .task { if !model.hasLoaded { await model.restore() } }
            .onDisappear { model.cancelNewStoreRegistrationInput() }
        }
    }
    private var newStoreExplanation: some View {
        Text("以前の登録情報を保持したまま、このアプリを新しく登録します。以前の軽量版の確認・失効への応答は引き継ぎません。接続先と認証情報を入力して開始してください。")
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("connection.new.explanation")
    }
    private var reconcileButton: some View {
        Button("保存した登録を再照合") { Task { await model.restore() } }
            .disabled(model.isWorking)
            .accessibilityIdentifier("connection.reconcile")
    }
}
