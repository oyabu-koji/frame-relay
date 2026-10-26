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
                    if model.isWorking { ProgressView("登録情報を確認しています") }
                }
                if case .registered(_, let registration) = model.state {
                    Section("端末登録") {
                        Text("登録世代 \(registration.server.registration.generation.rawValue)")
                            .accessibilityIdentifier("connection.registered")
                    }
                } else if case .needsRegistration = model.state {
                    Button("保存した情報で登録を続ける") { Task { await model.registerSavedConnection() } }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("connection.continue")
                } else if case .pending = model.state {
                    reconcileButton
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
                }
            }
            .navigationTitle("Mac miniとの接続")
            .toolbar { Button("閉じる") { model.bearer = ""; dismiss() }.accessibilityIdentifier("connection.close") }
            .task { if !model.hasLoaded { await model.restore() } }
            .onDisappear { model.bearer = "" }
        }
    }
    private var reconcileButton: some View {
        Button("保存した登録を再照合") { Task { await model.restore() } }
            .disabled(model.isWorking)
            .accessibilityIdentifier("connection.reconcile")
    }
}
