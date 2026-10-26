import SwiftUI
import UIKit

struct ConnectionView: View {
    @Bindable var model: ConnectionModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedInput: ConnectionInputField?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ConnectionSection {
                            ConnectionWrappingText(text: model.message, identifier: "connection.state")
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("connection.state")
                            if model.isWorking {
                                ProgressView(model.isDiscoveringRemoteInventory ? "Macの保存記録を照合しています"
                                    : model.isSynchronizing ? "状態を照合しています" : "登録情報を確認しています")
                            }
                        }
                        if case .registered(_, let registration) = model.state {
                            ConnectionSection {
                                ConnectionWrappingText(text: "登録世代 \(registration.server.registration.generation.rawValue)",
                                    identifier: "connection.registered")
                                    .accessibilityIdentifier("connection.registered")
                            } header: {
                                ConnectionWrappingText(text: "端末登録", style: .headline,
                                    identifier: "connection.registration.header")
                                    .accessibilityIdentifier("connection.registration.header")
                            }
                            if model.supportsRemoteInventory {
                                ConnectionSection {
                                    ConnectionWrappingText(text: "この接続先に保存した動画の記録を1ページずつ照合します。動画は取得しません。以前の軽量版の確認は引き継ぎません。",
                                        identifier: "connection.inventory.explanation")
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("connection.inventory.explanation")
                                    Button {
                                        Task { await model.discoverRemoteInventory() }
                                    } label: {
                                        Text(model.remoteInventoryReport?.hasMore == true ? "続きの保存記録を照合" : "Macの保存記録を照合")
                                            .font(.body)
                                    }
                                    .buttonStyle(ConnectionActionButtonStyle())
                                    .disabled(!model.canDiscoverRemoteInventory)
                                    .tint(Color.primary)
                                    .accessibilityIdentifier("connection.inventory")
                                    if let report = model.remoteInventoryReport {
                                        ConnectionWrappingText(text: report.message, identifier: "connection.inventory.state")
                                            .fixedSize(horizontal: false, vertical: true)
                                            .accessibilityIdentifier("connection.inventory.state")
                                    }
                                } header: {
                                    ConnectionWrappingText(text: "Macの保存記録", style: .headline,
                                        identifier: "connection.inventory.header")
                                        .accessibilityIdentifier("connection.inventory.header")
                                }
                            }
                            if model.supportsStatusSynchronization {
                                ConnectionSection {
                                    ConnectionWrappingText(text: "公開版と保存済みの確認・失効記録を照合します。動画は送受信しません。",
                                        identifier: "connection.synchronization.explanation")
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("connection.synchronization.explanation")
                                    Button {
                                        Task { await model.synchronizeStatus() }
                                    } label: {
                                        Text(model.synchronizationReport?.hasMore == true ? "続きの状態を照合" : "状態だけを同期")
                                            .font(.body)
                                    }
                                    .buttonStyle(ConnectionActionButtonStyle())
                                    .disabled(!model.canSynchronize)
                                    .tint(Color.primary)
                                    .accessibilityIdentifier("connection.synchronize")
                                    if let report = model.synchronizationReport {
                                        ConnectionWrappingText(text: report.message, identifier: "connection.synchronization.state")
                                            .fixedSize(horizontal: false, vertical: true)
                                            .accessibilityIdentifier("connection.synchronization.state")
                                        ForEach(report.items) { item in
                                            ConnectionWrappingText(text: "\(model.description(for: item))：\(item.disposition.text)")
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                } header: {
                                    ConnectionWrappingText(text: "状態の同期", style: .headline,
                                        identifier: "connection.synchronization.header")
                                        .accessibilityIdentifier("connection.synchronization.header")
                                }
                            }
                        } else if case .needsRegistration = model.state {
                            ConnectionSection {
                                Button("保存した情報で登録を続ける") { Task { await model.registerSavedConnection() } }
                                    .font(.body)
                                    .buttonStyle(ConnectionActionButtonStyle())
                                    .disabled(model.isWorking)
                                    .tint(Color.primary)
                                    .accessibilityIdentifier("connection.continue")
                            }
                        } else if case .pending = model.state {
                            ConnectionSection { reconcileButton }
                        } else if model.showsNewStoreRegistrationInput {
                            ConnectionSection {
                                newStoreExplanation
                                TextField("HTTPSの接続先URL（パスなし）", text: $model.origin)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                                    .accessibilityIdentifier("connection.new.origin")
                                    .focused($focusedInput, equals: .newOrigin)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minHeight: 44)
                                TextField("接続先ID", text: $model.destination)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityIdentifier("connection.new.destination")
                                    .focused($focusedInput, equals: .newDestination)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minHeight: 44)
                                SecureField("認証トークン", text: $model.bearer)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityIdentifier("connection.new.bearer")
                                    .focused($focusedInput, equals: .newBearer)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minHeight: 44)
                                Button("接続先を確認して新しい登録を開始") { Task { await model.registerNewStore() } }
                                    .font(.body)
                                    .buttonStyle(ConnectionActionButtonStyle())
                                    .disabled(model.isWorking)
                                    .tint(Color.primary)
                                    .accessibilityIdentifier("connection.new.register")
                                Button("新しい登録の入力をやめる", role: .cancel) { model.cancelNewStoreRegistrationInput() }
                                    .font(.body)
                                    .buttonStyle(ConnectionActionButtonStyle())
                                    .disabled(model.isWorking)
                                    .tint(Color.primary)
                                    .accessibilityIdentifier("connection.new.cancel")
                            } header: {
                                ConnectionWrappingText(text: "新しい登録の接続情報", style: .headline,
                                    identifier: "connection.new.input.header")
                                    .accessibilityIdentifier("connection.new.input.header")
                            }
                        } else if model.permitsInitialInput {
                            ConnectionSection {
                                TextField("HTTPSの接続先URL（パスなし）", text: $model.origin)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                                    .accessibilityIdentifier("connection.origin")
                                    .focused($focusedInput, equals: .origin)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minHeight: 44)
                                TextField("接続先ID", text: $model.destination)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityIdentifier("connection.destination")
                                    .focused($focusedInput, equals: .destination)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minHeight: 44)
                                SecureField("認証トークン", text: $model.bearer)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityIdentifier("connection.bearer")
                                    .focused($focusedInput, equals: .bearer)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minHeight: 44)
                                Button("接続先を確認して端末を登録") { Task { await model.register() } }
                                    .font(.body)
                                    .buttonStyle(ConnectionActionButtonStyle())
                                    .disabled(model.isWorking)
                                    .tint(Color.primary)
                                    .accessibilityIdentifier("connection.register")
                            } header: {
                                ConnectionWrappingText(text: "初回の接続情報", style: .headline,
                                    identifier: "connection.initial.header")
                                    .accessibilityIdentifier("connection.initial.header")
                            }
                            ConnectionSection { reconcileButton }
                        } else {
                            ConnectionSection { reconcileButton }
                            if model.permitsNewStoreRegistration {
                                ConnectionSection {
                                    newStoreExplanation
                                    Button("新しい端末登録を始める") { model.openNewStoreRegistrationInput() }
                                        .font(.body)
                                        .buttonStyle(ConnectionActionButtonStyle())
                                        .disabled(model.isWorking)
                                        .tint(Color.primary)
                                        .accessibilityIdentifier("connection.new.open")
                                } header: {
                                    ConnectionWrappingText(text: "新しい端末登録", style: .headline,
                                        identifier: "connection.new.header")
                                        .accessibilityIdentifier("connection.new.header")
                                }
                            }
                        }
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { focusedInput = nil }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
                .accessibilityIdentifier("connection.content")
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        model.cancelNewStoreRegistrationInput()
                        dismiss()
                    } label: {
                        Text("閉じる")
                            .font(.body)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .accessibilityIdentifier("connection.close")
                    .padding()
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Mac miniとの接続")
            .task { if !model.hasLoaded { await model.restore() } }
            .onDisappear { model.cancelNewStoreRegistrationInput() }
        }
    }
    private var newStoreExplanation: some View {
        ConnectionWrappingText(text: "以前の登録情報を保持したまま、このアプリを新しく登録します。以前の軽量版の確認・失効への応答は引き継ぎません。接続先と認証情報を入力して開始してください。",
            identifier: "connection.new.explanation")
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("connection.new.explanation")
    }
    private var reconcileButton: some View {
        Button("保存した登録を再照合") { Task { await model.restore() } }
            .font(.body)
            .buttonStyle(ConnectionActionButtonStyle())
            .disabled(model.isWorking)
            .tint(Color.primary)
            .accessibilityIdentifier("connection.reconcile")
    }
}

private enum ConnectionInputField: Hashable {
    case origin, destination, bearer, newOrigin, newDestination, newBearer
}

private struct ConnectionSection<Content: View, Header: View>: View {
    private let content: Content
    private let header: Header

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.content = content()
        self.header = header()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .font(.headline)
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension ConnectionSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() })
    }
}

private struct ConnectionActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Availability is conveyed by the disabled trait and the adjacent reason.
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(Color.primary)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Uses the proposed width and semantic font to keep complete body text readable
/// at every Dynamic Type size, without a fixed height or text truncation.
private struct ConnectionWrappingText: UIViewRepresentable {
    let text: String
    var style: UIFont.TextStyle = .body
    var identifier: String? = nil
    @Environment(\.sizeCategory) private var sizeCategory

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.isAccessibilityElement = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.accessibilityIdentifier = identifier
        label.font = .preferredFont(forTextStyle: style, compatibleWith:
            UITraitCollection(preferredContentSizeCategory: contentSizeCategory))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        guard let proposedWidth = proposal.width, proposedWidth.isFinite else { return nil }
        let width = max(0, proposedWidth)
        label.preferredMaxLayoutWidth = width
        let measured = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }

    private var contentSizeCategory: UIContentSizeCategory {
        switch sizeCategory {
        case .extraSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .extraLarge: .extraLarge
        case .extraExtraLarge: .extraExtraLarge
        case .extraExtraExtraLarge: .extraExtraExtraLarge
        case .accessibilityMedium: .accessibilityMedium
        case .accessibilityLarge: .accessibilityLarge
        case .accessibilityExtraLarge: .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
