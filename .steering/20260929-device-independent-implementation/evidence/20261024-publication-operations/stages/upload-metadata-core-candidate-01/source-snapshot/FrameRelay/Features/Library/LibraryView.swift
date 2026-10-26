import SwiftUI
import UIKit

struct LibraryView: View {
    @Bindable var model: LibraryModel
    var showCapture: (() -> Void)? = nil
    var showExploration: (() -> Void)? = nil
    var showConnection: (() -> Void)? = nil
    @State private var showsHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let showCapture {
                        LibrarySection {
                            Button { showCapture() } label: {
                                Label("撮影する", systemImage: "camera.fill")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .buttonStyle(LibraryActionButtonStyle())
                            .accessibilityIdentifier("product.capture")
                        }
                    }
                    LibrarySection {
                        Picker("表示する記録", selection: $showsHistory) {
                            Text("ライブラリ").tag(false)
                            Text("破棄の履歴").tag(true)
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("library.scope")
                    }
                    LibraryLoadStatus(model: model)
                    if let snapshot = model.snapshot {
                        let items = showsHistory ? snapshot.history : snapshot.recordings
                        if showsHistory {
                            LibrarySection {
                                Text("原本の削除結果を照合できた破棄の記録です。原本を保管するゴミ箱ではありません。")
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("library.historyExplanation")
                            }
                        }
                        if items.isEmpty, (showsHistory || snapshot.remoteItems.isEmpty), model.failure == nil, !model.isLoading {
                            Text(showsHistory ? "破棄の履歴はありません" : "撮影した動画はありません")
                                .accessibilityIdentifier("library.empty")
                        }
                        ForEach(items) { item in
                            LibrarySection {
                                NavigationLink {
                                    LibraryDetailView(model: model, capture: item.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        LibraryWrappingText(text: item.title, style: .headline,
                                            identifier: "library.itemTitle.\(item.id.rawValue)")
                                            .accessibilityIdentifier("library.itemTitle.\(item.id.rawValue)")
                                        LibraryWrappingText(text: item.captureDateDescription,
                                            identifier: "library.itemCapturedAt.\(item.id.rawValue)")
                                            .accessibilityIdentifier("library.itemCapturedAt.\(item.id.rawValue)")
                                        LibraryWrappingText(text: item.status(.save),
                                            identifier: "library.itemSave.\(item.id.rawValue)")
                                            .accessibilityIdentifier("library.itemSave.\(item.id.rawValue)")
                                        LibraryWrappingText(text: item.status(.original),
                                            identifier: "library.itemOriginal.\(item.id.rawValue)")
                                            .accessibilityIdentifier("library.itemOriginal.\(item.id.rawValue)")
                                        if item.isDiscardHistory {
                                            LibraryWrappingText(text: item.status(.removal),
                                                identifier: "library.itemRemoval.\(item.id.rawValue)")
                                                .accessibilityIdentifier("library.itemRemoval.\(item.id.rawValue)")
                                        }
                                        LibraryWrappingText(text: item.status(.publication),
                                            identifier: "library.itemPublication.\(item.id.rawValue)")
                                            .accessibilityIdentifier("library.itemPublication.\(item.id.rawValue)")
                                        LibraryWrappingText(text: item.status(.retrieval),
                                            identifier: "library.itemRetrieval.\(item.id.rawValue)")
                                            .accessibilityIdentifier("library.itemRetrieval.\(item.id.rawValue)")
                                        if !item.isDiscardHistory {
                                            LibraryWrappingText(text: item.status(.removal),
                                                identifier: "library.itemRemoval.\(item.id.rawValue)")
                                                .accessibilityIdentifier("library.itemRemoval.\(item.id.rawValue)")
                                        }
                                        LibraryWrappingText(text: item.status(.photos),
                                            identifier: "library.itemPhotos.\(item.id.rawValue)")
                                            .accessibilityIdentifier("library.itemPhotos.\(item.id.rawValue)")
                                        if item.requiresReconciliation {
                                            LibraryWrappingText(text: "要照合",
                                                identifier: "library.itemReconciliation.\(item.id.rawValue)", bold: true)
                                                .accessibilityIdentifier("library.itemReconciliation.\(item.id.rawValue)")
                                        }
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityElement(children: .combine)
                                }
                                .buttonStyle(LibraryActionButtonStyle())
                                .accessibilityIdentifier("library.item.\(item.id.rawValue)")
                                if !showsHistory {
                                    Toggle(isOn: Binding(
                                        get: { model.selected.contains(item.id) },
                                        set: { model.select(item.id, selected: $0) })) {
                                            LibraryWrappingText(text: "この動画を選択")
                                        }
                                    .accessibilityLabel("\(item.title)を選択")
                                    .accessibilityIdentifier("library.select.\(item.id.rawValue)")
                                }
                                LibraryOperationResults(item: item)
                                if !item.mediaRequests.isEmpty {
                                    LibraryWrappingText(text: "通信要求は\(item.mediaRequests.count)件です。対象別の記録と本人操作は動画の詳細で確認できます。",
                                        identifier: "library.request.summary.\(item.id.rawValue)")
                                }
                            }
                        }
                        if !showsHistory, !snapshot.remoteItems.isEmpty {
                            ForEach(snapshot.remoteItems) { item in
                                LibraryRemoteInventoryRow(item: item, model: model)
                            }
                        }
                        if !showsHistory {
                            LibrarySection {
                                if model.hasTransferPort, !model.selected.isEmpty {
                                    LibraryRenditionPlaybackButton(title: "動画の選択を解除", isEnabled: true,
                                        identifier: "library.selection.clear") { model.clearSelection() }
                                }
                                ForEach(LibraryAction.multiple) { action in
                                    if action == .saveToPhotos, model.hasPhotoSavePort {
                                        LibraryPhotoSaveButton(model: model, captures: model.selected, remotes: model.remotePhotoSelected)
                                    } else {
                                        LibraryActionButton(model: model, action: action, captures: model.selected)
                                    }
                                }
                            } header: {
                                LibraryWrappingText(text: "選択した\(model.selected.count)本の操作", style: .headline)
                            }
                            LibraryPhotoBatchResults(model: model)
                            LibraryTransferAcceptanceResults(model: model)
                            LibraryMediaRequestAllPause(model: model)
                            LibraryMediaControlFeedback(model: model)
                            LibraryMediaControlHistory(model: model)
                        }
                    }
                    LibrarySubmissionStatus(model: model)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(showsHistory ? "破棄の履歴" : "ライブラリ")
            .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                if let showConnection {
                    Button("Mac miniとの接続", systemImage: "network") { showConnection() }
                        .accessibilityIdentifier("product.connection")
                }
                if let showExploration {
                    Button("撮影基盤の探索", systemImage: "camera") { showExploration() }
                        .accessibilityIdentifier("product.exploration")
                }
                Button("再読み込み", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.isLoading)
                    .accessibilityIdentifier("library.refresh")
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
    }
}

private struct LibraryRemoteInventoryRow: View {
    let item: LibraryRemoteItem
    let model: LibraryModel
    var body: some View {
        LibrarySection {
            VStack(alignment: .leading, spacing: 8) {
                LibraryWrappingText(text: item.title, style: .headline,
                    identifier: "library.remote.title.\(item.id.accessibilityToken)")
                    .accessibilityIdentifier("library.remote.title.\(item.id.accessibilityToken)")
                LibraryWrappingText(text: item.captureDateDescription,
                    identifier: "library.remote.date.\(item.id.accessibilityToken)")
                    .accessibilityIdentifier("library.remote.date.\(item.id.accessibilityToken)")
                LibraryWrappingText(text: item.storageDescription,
                    identifier: "library.remote.storage.\(item.id.accessibilityToken)")
                    .accessibilityIdentifier("library.remote.storage.\(item.id.accessibilityToken)")
                LibraryWrappingText(text: item.localDescription,
                    identifier: "library.remote.local.\(item.id.accessibilityToken)")
                    .accessibilityIdentifier("library.remote.local.\(item.id.accessibilityToken)")
                LibraryWrappingText(text: item.publicationDescription,
                    identifier: "library.remote.publication.\(item.id.accessibilityToken)")
                    .accessibilityIdentifier("library.remote.publication.\(item.id.accessibilityToken)")
                LibraryWrappingText(text: item.retrievalDescription,
                    identifier: "library.remote.retrieval.\(item.id.accessibilityToken)")
                    .accessibilityIdentifier("library.remote.retrieval.\(item.id.accessibilityToken)")
                LibraryWrappingText(text: item.mediaDescription,
                    identifier: "library.remote.media.\(item.id.accessibilityToken)")
                    .accessibilityIdentifier("library.remote.media.\(item.id.accessibilityToken)")
                if item.hasIdentityConflict { Text("要照合").bold() }
                if model.hasPhotoSavePort {
                    Toggle(isOn: Binding(
                        get: { model.remotePhotoSelected.contains(item.id) },
                        set: { model.selectRemotePhoto(item.id, selected: $0) })) {
                            LibraryWrappingText(text: "このMacの動画を写真への保存対象に選択")
                        }
                        .accessibilityLabel("このMacの動画を写真への保存対象に選択")
                        .accessibilityIdentifier("library.remote.photo.select.\(item.id.accessibilityToken)")
                    LibraryPhotoSaveButton(model: model, captures: [], remotes: [item.id],
                        identifier: "library.remote.photo.save.\(item.id.accessibilityToken)")
                }
                let availability = model.remotePlaybackAvailability(item)
                Button("端末内の軽量版を再生") { Task { await model.playRemoteRendition(item) } }
                    .buttonStyle(LibraryActionButtonStyle())
                    .disabled(availability != .available)
                    .accessibilityIdentifier("library.remote.play.\(item.id.accessibilityToken)")
                if let reason = availability.reason {
                    LibraryWrappingText(text: reason,
                        identifier: "library.remote.playReason.\(item.id.accessibilityToken)")
                        .accessibilityIdentifier("library.remote.playReason.\(item.id.accessibilityToken)")
                }
                if let feedback = model.remotePlaybackMessages[item.id] {
                    LibraryWrappingText(text: feedback,
                        identifier: "library.remote.playFeedback.\(item.id.accessibilityToken)")
                        .accessibilityIdentifier("library.remote.playFeedback.\(item.id.accessibilityToken)")
                }
                ForEach(item.photoRegistrations) { photo in
                    LibraryRemotePhotoRegistrationSection(model: model, item: item, photo: photo)
                }
                LibraryMediaRequestControls(model: model, requests: item.mediaRequests)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("library.remote.item.\(item.id.accessibilityToken)")
        } header: {
            LibraryWrappingText(text: "Macの保存記録", style: .headline,
                identifier: "library.remote.header.\(item.id.accessibilityToken)")
                .accessibilityIdentifier("library.remote.header.\(item.id.accessibilityToken)")
        }
    }
}

private struct LibraryDetailView: View {
    @Bindable var model: LibraryModel
    let capture: CaptureID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LibraryLoadStatus(model: model)
                if let item = model.item(capture) {
                    LibrarySection {
                        Text(item.title)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("library.detailIdentity")
                        Text(item.captureDateDescription)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("library.detailCapturedAt")
                    }
                    LibrarySection {
                        ForEach(item.statuses) { status in
                            VStack(alignment: .leading, spacing: 4) {
                                LibraryWrappingText(text: status.axis.title, style: .headline)
                                LibraryWrappingText(text: status.text)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("library.status.\(status.axis.rawValue)")
                        }
                    } header: {
                        Text("動画の状態").foregroundStyle(Color.primary)
                    }
                    LibraryMediaRequestControls(model: model, requests: item.mediaRequests)
                    LibraryTransferAcceptanceResults(model: model, capture: capture)
                    if let original = item.original {
                        LibraryMediaControlFeedback(model: model, original: original)
                        LibraryMediaControlHistory(model: model, original: original)
                    }
                    ForEach(item.photoRegistrations) { photo in
                        LibraryPhotoRegistrationSection(model: model, capture: capture, photo: photo)
                    }
                    if item.requiresReconciliation {
                        LibrarySection {
                            LibraryWrappingText(text: "保存記録、原本、写真の状態に未確定の部分があります。保存記録と原本は再読み込みで確認できます。写真側の存在は、対象ごとの説明を確認して照合してください。未完了の削除や写真への追加は自動実行しません。",
                                identifier: "library.detailReconciliationExplanation")
                        } header: {
                            LibraryWrappingText(text: "確認が必要です", style: .headline,
                                identifier: "library.detailReconciliationHeading")
                                .accessibilityIdentifier("library.detailReconciliationHeading")
                        }
                    }
                    if let information = item.removalReviewInformation {
                        LibrarySection {
                            Text(information).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("library.removalReviewInformation")
                        } header: { Text("原本の整理・破棄の確認情報").foregroundStyle(Color.primary) }
                    }
                    if !item.isDiscardHistory {
                        LibrarySection {
                            if model.hasPhotoSavePort {
                                LibraryPhotoSaveButton(model: model, captures: [capture], remotes: [])
                            }
                            ForEach(model.hasTransferPort ? LibraryAction.detail : LibraryAction.single) { action in
                                LibraryActionButton(model: model, action: action, captures: [capture])
                            }
                        } header: {
                            LibraryWrappingText(text: "この動画の操作", style: .headline)
                        }
                    }
                    if !item.operationResults.isEmpty {
                        LibrarySection {
                            LibraryOperationResults(item: item)
                        } header: {
                            Text("動画別の処理結果").foregroundStyle(Color.primary)
                        }
                    }
                    ForEach(item.removalOperations) { operation in
                        LibrarySection {
                            Text("この対象の削除意図と実ファイルを照合します。削除や写真への追加を新たに実行しません。")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("削除結果を照合") { Task { await model.reconcileRemoval(operation, capture: capture) } }
                                .disabled(!model.canReconcileRemoval(operation, capture: capture))
                                .accessibilityIdentifier("library.removal.reconcile.\(operation.id.rawValue)")
                            if let message = model.removalReconciliationMessages[operation.id] { Text(message).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                    LibrarySubmissionStatus(model: model, capture: capture)
                    LibraryPhotoBatchResults(model: model, capture: capture)
                } else {
                    Text("この動画の記録を取得できません。再読み込みしてください。")
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("動画の詳細")
        // Keep the inline title readable when long status rows scroll behind it.
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .refreshable { await model.refresh() }
    }
}

private struct LibraryMediaRequestControls: View {
    let model: LibraryModel
    let requests: [LibraryMediaRequest]

    var body: some View {
        ForEach(requests) { row in
            let token = row.accessibilityToken
            LibrarySection {
                LibraryWrappingText(text: row.identityDescription, identifier: "library.request.identity.\(token)")
                LibraryWrappingText(text: row.intentDescription, identifier: "library.request.intent.\(token)")
                LibraryWrappingText(text: row.waitsDescription, identifier: "library.request.waits.\(token)")
                LibraryWrappingText(text: row.transportDescription, identifier: "library.request.transport.\(token)")
                if model.hasMediaRequestControlPort {
                    ForEach([MediaPersonControlAction.pause, .cancel, .resumeIntent], id: \.rawValue) { action in
                        let availability = model.mediaRequestAvailability(action, request: row)
                        let enabled = availability == .available
                        LibraryRenditionPlaybackButton(title: title(action), isEnabled: enabled,
                            identifier: "library.request.\(action.rawValue).\(token)") {
                            Task { await model.controlMediaRequest(action, request: row) }
                        }
                        .disabled(!enabled)
                        if let reason = availability.reason {
                            LibraryWrappingText(text: reason, identifier: "library.request.reason.\(action.rawValue).\(token)")
                        }
                    }
                }
            } header: {
                LibraryWrappingText(text: row.title, style: .headline, identifier: "library.request.title.\(token)")
            }
        }
    }

    private func title(_ action: MediaPersonControlAction) -> String {
        switch action {
        case .pause: "この通信を停止"
        case .cancel: "この通信を取り消す"
        case .resumeIntent: "停止を解除して待機"
        }
    }
}

private struct LibraryMediaRequestAllPause: View {
    let model: LibraryModel
    var body: some View {
        if model.hasMediaRequestControlPort, let snapshot = model.snapshot, !snapshot.mediaRequests.isEmpty {
            LibrarySection {
                LibraryWrappingText(text: "保存済みの通信要求\(snapshot.mediaRequests.count)件を、操作時に固定して全件停止の対象にします。開始待ち・条件待ちも含め、対象別に本人停止の記録と未処理理由を表示します。端末内の再生と写真への追加は独立した処理です。",
                    identifier: "library.request.allPause.explanation")
                let availability = model.allMediaPauseAvailability
                let enabled = availability == .available
                LibraryRenditionPlaybackButton(title: "開始指示済みの通信を全件停止", isEnabled: enabled,
                    identifier: "library.request.allPause") {
                    Task { await model.pauseAllMediaRequests() }
                }
                .disabled(!enabled)
                if let reason = availability.reason {
                    LibraryWrappingText(text: reason, identifier: "library.request.allPause.reason")
                }
            } header: {
                LibraryWrappingText(text: "開始指示済みの通信操作", style: .headline,
                    identifier: "library.request.allPause.heading")
            }
        }
    }
}

private struct LibraryMediaControlFeedback: View {
    let model: LibraryModel
    var original: OriginalContent? = nil
    var body: some View {
        if original == nil, let message = model.mediaControlMessage {
            LibrarySection {
                LibraryWrappingText(text: message, identifier: "library.request.feedback")
            }
        }
        if let plan = model.pendingMediaControlPlan,
           original.map({ original in plan.children.contains {
               MediaPersonControlValueValidation.exact($0.target.target.original, original)
           } }) ?? true {
            LibrarySection {
                LibraryWrappingText(text: "対象\(plan.children.count)件の\(LibraryMediaRequestProjection.actionDescription(plan.action))指示を保持しています。受付結果は未確定です。同じ指示の受付結果を照合してください。",
                    identifier: "library.request.pending.\(plan.parent.rawValue)")
                ForEach(plan.children, id: \.command) { child in
                    LibraryWrappingText(text: LibraryMediaRequestProjection.identity(child.target),
                        identifier: "library.request.pendingChild.\(child.command.rawValue).\(child.target.accessibilityToken)")
                }
                let enabled = !model.isSubmittingMediaControl
                LibraryRenditionPlaybackButton(title: "同じ指示の受付結果を照合", isEnabled: enabled,
                    identifier: "library.request.lookup") {
                    Task { await model.reconcileMediaControl() }
                }
                .disabled(!enabled)
            } header: {
                LibraryWrappingText(text: "未確定の通信操作", style: .headline)
            }
        }
    }
}

private struct LibraryMediaControlHistory: View {
    let model: LibraryModel
    var original: OriginalContent? = nil
    var body: some View {
        ForEach(model.snapshot?.personControls ?? [], id: \.plan.parent) { record in
            let children = record.children.filter { child in
                original.map { MediaPersonControlValueValidation.exact(child.child.target.target.original, $0) } ?? true
            }
            if !children.isEmpty {
                LibrarySection {
                    LibraryWrappingText(text: "\(LibraryMediaRequestProjection.actionDescription(record.plan.action))の指示・固定対象\(record.plan.children.count)件",
                        identifier: "library.request.historyPlan.\(record.plan.parent.rawValue)")
                    ForEach(children, id: \.child.command) { child in
                        let token = child.child.command.rawValue
                        LibraryWrappingText(text: LibraryMediaRequestProjection.identity(child.child.target),
                            identifier: "library.request.historyIdentity.\(token).\(child.child.target.accessibilityToken)")
                        LibraryWrappingText(text: LibraryMediaRequestProjection.decision(child, action: record.plan.action),
                            identifier: "library.request.historyDecision.\(token)")
                        if child.decision == .recorded {
                            if record.plan.action == .resumeIntent {
                                LibraryWrappingText(text: "この指示は停止解除の意思の記録です。通信の開始・実際の再開は行っていません。",
                                    identifier: "library.request.historyStop.\(token)")
                            } else {
                                LibraryWrappingText(text: LibraryMediaRequestProjection.stop(model.mediaControlStops[child.child.command] ?? .notRequested),
                                    identifier: "library.request.historyStop.\(token)")
                            }
                        }
                    }
                } header: {
                    LibraryWrappingText(text: record.plan.scope == .allPause ? "全件停止の保存記録" : "単数の通信操作の保存記録",
                        style: .headline, identifier: "library.request.historyHeading.\(record.plan.parent.rawValue)")
                }
            }
        }
    }
}

/// Native multiline text keeps its measured width and Dynamic Type traits
/// available to UIKit's text layout and accessibility geometry.
private struct LibraryWrappingText: UIViewRepresentable {
    let text: String
    var style: UIFont.TextStyle = .body
    var identifier: String? = nil
    var bold = false
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
        let font = UIFont.preferredFont(forTextStyle: style, compatibleWith:
            UITraitCollection(preferredContentSizeCategory: contentSizeCategory))
        if bold, let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitBold)) {
            label.font = UIFont(descriptor: descriptor, size: font.pointSize)
        } else { label.font = font }
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

private struct LibraryPhotoRegistrationSection: View {
    let model: LibraryModel
    let capture: CaptureID
    let photo: LibraryPhotoRegistration

    var body: some View {
        LibrarySection {
            LibraryWrappingText(text: "過去の登録：\(photo.registrationResult)",
                identifier: "library.photo.registration.\(photo.id.rawValue)")
            LibraryWrappingText(text: "写真側の存在：\(photo.presenceResult)",
                identifier: "library.photo.presence.\(photo.id.rawValue)")
            if model.hasPhotoSavePort, photo.isLatestAttempt, photo.record.outcome?.permitsExplicitRetry == true {
                LibraryPhotoRetryButton(model: model, photo: photo, source: model.item(capture)?.photoSaveSource)
            }
            if let reason = photo.reconciliationReason {
                LibraryWrappingText(text: "対象：\(model.item(capture)?.title ?? capture.rawValue)、\(photo.title)。\(reason)",
                    identifier: "library.photo.reason.\(photo.id.rawValue)")
                if let unavailable = photo.reconciliationUnavailableReason {
                    LibraryWrappingText(text: unavailable, identifier: "library.photo.unavailable.\(photo.id.rawValue)")
                } else {
                    LibraryWrappingText(text: "この照合の操作時だけ写真の読み取り許可を求めます。許可しなくても撮影は続けられます。",
                        identifier: "library.photo.permissionReason.\(photo.id.rawValue)")
                    let enabled = model.canReconcilePhotos(photo, capture: capture)
                    LibraryRenditionPlaybackButton(title: "写真の読み取りで存在を照合", isEnabled: enabled,
                        identifier: "library.photo.reconcile.\(photo.id.rawValue)") {
                        Task { await model.reconcilePhotos(photo, capture: capture) }
                    }
                    .disabled(!enabled)
                }
            }
            if model.photoReconciliations.contains(photo.id) {
                ProgressView("写真側の存在を照合中")
            }
            if let message = model.photoReconciliationMessages[photo.id] {
                LibraryWrappingText(text: message, identifier: "library.photo.feedback.\(photo.id.rawValue)")
            }
        } header: {
            LibraryWrappingText(text: "写真の記録：\(photo.title)", style: .headline)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LibraryPhotoSaveButton: View {
    let model: LibraryModel
    let captures: Set<CaptureID>
    let remotes: Set<RemoteInventoryOriginalID>
    var identifier = "library.action.saveToPhotos"
    var body: some View {
        let availability = model.photoSaveAvailability(captures: captures, remotes: remotes)
        VStack(alignment: .leading, spacing: 8) {
            LibraryRenditionPlaybackButton(title: "選択した\(captures.count + remotes.count)本の取得済み軽量版を写真に保存", isEnabled: availability == .available,
                identifier: identifier) { Task { await model.submitPhotos(captures: captures, remotes: remotes) } }
                .disabled(availability != .available)
            LibraryWrappingText(text: "ローカル\(captures.count)本とMacの記録\(remotes.count)本、合計\(captures.count + remotes.count)本を対象にします。Macの記録の選択は写真への保存専用です。完全取得済みの軽量版だけを固定して写真への追加を要求します。最初の受付時にWi-Fi経路を確認します。受付後の端末内処理はオフラインでも続きます。撮影・保存・復旧中は未着手の処理を保持して待機します。要求の受付は写真への登録成功ではありません。",
                identifier: identifier + ".explanation")
            if let reason = availability.reason {
                LibraryWrappingText(text: reason, identifier: identifier == "library.action.saveToPhotos"
                    ? "library.reason.saveToPhotos" : identifier + ".reason")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LibraryPhotoRetryButton: View {
    let model: LibraryModel
    let photo: LibraryPhotoRegistration
    let source: PhotoSaveSource?
    var body: some View {
        let enabled = model.canRetryPhoto(photo, source: source)
        LibraryWrappingText(text: "前回の登録は追加されなかったことが確定しています。同じ現在版を明示的に再試行できます。結果不明や過去の成功から再追加はしません。",
            identifier: "library.photo.retryExplanation.\(photo.id.rawValue)")
        LibraryRenditionPlaybackButton(title: "この未追加の軽量版を再試行", isEnabled: enabled,
            identifier: "library.photo.retry.\(photo.id.rawValue)") {
                Task { await model.retryPhoto(photo, source: source) }
            }.disabled(!enabled)
        if !enabled {
            LibraryWrappingText(text: "現在の同じ完全取得済み軽量版とWi-Fi経路を確認できるときに再試行できます。",
                identifier: "library.photo.retryUnavailable.\(photo.id.rawValue)")
        }
    }
}

private struct LibraryRemotePhotoRegistrationSection: View {
    let model: LibraryModel
    let item: LibraryRemoteItem
    let photo: LibraryPhotoRegistration
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryWrappingText(text: "過去の登録：\(photo.registrationResult)",
                identifier: "library.remote.photo.registration.\(photo.id.rawValue)")
            LibraryWrappingText(text: "写真側の存在：\(photo.presenceResult)",
                identifier: "library.remote.photo.presence.\(photo.id.rawValue)")
            if model.hasPhotoSavePort, photo.isLatestAttempt, photo.record.outcome?.permitsExplicitRetry == true {
                LibraryPhotoRetryButton(model: model, photo: photo, source: item.photoSaveSource)
            }
            if let reason = photo.reconciliationReason {
                LibraryWrappingText(text: "対象：\(item.title)、\(photo.title)。\(reason)",
                    identifier: "library.remote.photo.reason.\(photo.id.rawValue)")
                if let unavailable = photo.reconciliationUnavailableReason {
                    LibraryWrappingText(text: unavailable, identifier: "library.remote.photo.unavailable.\(photo.id.rawValue)")
                } else {
                    LibraryWrappingText(text: "この照合の操作時だけ写真の読み取り許可を求めます。許可しなくても撮影は続けられます。",
                        identifier: "library.remote.photo.permissionReason.\(photo.id.rawValue)")
                    let enabled = model.canReconcileRemotePhotos(photo, item: item)
                    LibraryRenditionPlaybackButton(title: "写真の読み取りで存在を照合", isEnabled: enabled,
                        identifier: "library.remote.photo.reconcile.\(photo.id.rawValue)") {
                            Task { await model.reconcileRemotePhotos(photo, item: item) }
                        }.disabled(!enabled)
                }
            }
            if let message = model.photoReconciliationMessages[photo.id] {
                LibraryWrappingText(text: message, identifier: "library.remote.photo.feedback.\(photo.id.rawValue)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LibraryPhotoBatchResults: View {
    let model: LibraryModel
    var capture: CaptureID? = nil
    var body: some View {
        if let message = model.photoSaveMessage {
            LibrarySection {
                LibraryWrappingText(text: message, identifier: "library.photoBatch.feedback")
            }
        }
        if model.pendingPhotoAcceptance != nil {
            let enabled = !model.isSubmittingPhotos
            LibraryRenditionPlaybackButton(title: "同じ写真保存要求の受付結果を照合", isEnabled: enabled,
                identifier: "library.photoBatch.lookup") { Task { await model.reconcilePhotoAcceptance() } }
                .disabled(!enabled)
        }
        ForEach(model.snapshot?.photoSaveBatches ?? [], id: \.batch.operation) { batch in
            let children = batch.targets.filter { capture == nil || $0.target.source.rendition.original.capture == capture }
            if !children.isEmpty {
                LibrarySection {
                    ForEach(children, id: \.target.operation) { child in
                        LibraryWrappingText(text: child.progressDescription,
                            identifier: "library.photoBatch.child.\(child.target.operation.rawValue)")
                    }
                    if children.contains(where: { child in
                        if child.registration != nil { return false }
                        switch child.status { case .queued, .starting: return true; case .notProcessed: return false }
                    }) {
                        LibraryWrappingText(text: "続行は未着手の対象だけを開始します。開始予約や写真の登録意図が残る対象は、自動でも再起動後でも再追加しません。取消も既に開始した写真への追加を取り消しません。",
                            identifier: "library.photoBatch.explanation.\(batch.batch.operation.rawValue)")
                        LibraryRenditionPlaybackButton(title: "未着手を明示的に続行・受付結果を照合", isEnabled: true,
                            identifier: "library.photoBatch.resume.\(batch.batch.operation.rawValue)") {
                                Task { await model.resumePhotoBatch(batch.batch.operation) }
                            }
                        LibraryRenditionPlaybackButton(title: "この要求の未着手を取り消す", isEnabled: true,
                            identifier: "library.photoBatch.cancel.\(batch.batch.operation.rawValue)") {
                                Task { await model.cancelPhotoBatch(batch.batch.operation) }
                            }
                    }
                } header: {
                    LibraryWrappingText(text: "写真保存要求：\(batch.batch.operation.rawValue)", style: .headline)
                }
            }
        }
    }
}

private struct LibraryTransferAcceptanceResults: View {
    let model: LibraryModel
    var capture: CaptureID? = nil

    var body: some View {
        if let message = model.transferMessage {
            LibrarySection {
                LibraryWrappingText(text: message, identifier: "library.transfer.feedback")
            }
        }
        if let request = model.pendingTransferAcceptance,
           capture == nil || request.targets.contains(where: { $0.binding.original.capture == capture }) {
            LibrarySection {
                LibraryWrappingText(text: "この転送要求は選択時の\(request.targets.count)本を保持しています。選択や保存記録が変わっても別の原本に置き換えません。",
                    identifier: "library.transfer.pending.explanation")
                ForEach(request.targets, id: \.operation) { target in
                    LibraryWrappingText(text: "対象：動画 \(target.binding.original.capture.rawValue)",
                        identifier: "library.transfer.pending.target.\(target.operation.rawValue)")
                }
                let enabled = !model.isSubmittingTransfer
                LibraryRenditionPlaybackButton(title: "同じ転送要求の受付結果を照合", isEnabled: enabled,
                    identifier: "library.transfer.lookup") { Task { await model.reconcileTransferAcceptance() } }
                    .disabled(!enabled)
            }
        }
        ForEach(model.snapshot?.originalUploadAcceptances.filter { record in
            capture == nil || record.plan.request.targets.contains { $0.binding.original.capture == capture }
        } ?? [], id: \.plan.request.parent) { record in
            LibrarySection {
                LibraryWrappingText(text: "受付時に固定した\(record.children.count)本すべての結果です。未処理の対象もこの要求に残します。受付はMacへの保存や通信の成功を示しません。",
                    identifier: "library.transfer.explanation.\(record.plan.request.parent.rawValue)")
                ForEach(record.children, id: \.target.operation) { child in
                    VStack(alignment: .leading, spacing: 8) {
                        LibraryWrappingText(text: "動画 \(child.target.binding.original.capture.rawValue)", style: .headline,
                            identifier: "library.transfer.child.title.\(child.target.operation.rawValue)")
                        LibraryWrappingText(text: LibraryTransferProjection.decision(child),
                            identifier: "library.transfer.child.decision.\(child.target.operation.rawValue)")
                        if child.decision == .accepted {
                            if let current = LibraryTransferProjection.currentRequest(child, record: record,
                                rows: model.snapshot?.mediaRequests ?? []) {
                                LibraryWrappingText(text: current.intentDescription,
                                    identifier: "library.transfer.child.intent.\(child.target.operation.rawValue)")
                                LibraryWrappingText(text: current.waitsDescription,
                                    identifier: "library.transfer.child.waits.\(child.target.operation.rawValue)")
                                LibraryWrappingText(text: current.transportDescription,
                                    identifier: "library.transfer.child.transport.\(child.target.operation.rawValue)")
                            } else {
                                LibraryWrappingText(text: "同じ対象の現在の通信要求を確定できません。受付時の記録を保持しています。",
                                    identifier: "library.transfer.child.currentUnavailable.\(child.target.operation.rawValue)")
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if model.hasTransferPort {
                    let enabled = !model.isSubmittingTransfer && model.pendingTransferAcceptance == nil
                    LibraryRenditionPlaybackButton(title: "この転送要求の保存記録を照合", isEnabled: enabled,
                        identifier: "library.transfer.record.lookup.\(record.plan.request.parent.rawValue)") {
                            Task { await model.lookupRecordedTransfer(record) }
                        }.disabled(!enabled)
                    LibraryWrappingText(text: "保存記録の照合だけを行います。通信は開始しません。再びアプリを開いても未開始の通信を自動で始めません。",
                        identifier: "library.transfer.record.lookupExplanation.\(record.plan.request.parent.rawValue)")
                }
            } header: {
                LibraryWrappingText(text: "原本の転送要求・\(record.children.count)本", style: .headline,
                    identifier: "library.transfer.header.\(record.plan.request.parent.rawValue)")
            }
        }
    }
}

private struct LibraryLoadStatus: View {
    let model: LibraryModel
    var body: some View {
        if model.isLoading {
            ProgressView("保存記録を読み込み中")
                .accessibilityIdentifier("library.loading")
        }
        if let failure = model.failure {
            LibrarySection {
                Text(failure.message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if model.snapshot != nil {
                    Text("以下は前回読み込んだ状態です。操作前に再読み込みしてください。")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("読み込めませんでした").foregroundStyle(Color.primary)
            }
            .accessibilityIdentifier("library.loadFailure")
        }
    }
}

private struct LibraryActionButton: View {
    let model: LibraryModel
    let action: LibraryAction
    let captures: Set<CaptureID>
    @State private var removalReview: LibraryRemovalReview?

    var body: some View {
        let availability = model.availability(action, captures: captures)
        VStack(alignment: .leading, spacing: 6) {
            LibraryRenditionPlaybackButton(title: action.title, isEnabled: availability == .available,
                identifier: "library.action.\(action.rawValue)", role: action == .discard ? .destructive : .normal) {
                    if action == .discard || action == .cleanup { removalReview = model.prepareRemovalReview(action, captures: captures) }
                    else { Task { await model.submit(action, captures: captures) } }
            }
            .disabled(availability != .available)
            if let reason = availability.reason {
                LibraryWrappingText(text: reason, style: .footnote, identifier: "library.reason.\(action.rawValue)")
            }
        }
        .confirmationDialog(action == .discard ? "この原本を破棄しますか？" : "選択した原本を容量整理しますか？", isPresented: Binding(
            get: { removalReview != nil }, set: { if !$0 { removalReview = nil } }), titleVisibility: .visible) {
            if let review = removalReview {
                Button(action == .discard ? "対象の原本を破棄" : "確認した原本を整理", role: .destructive) {
                    removalReview = nil
                    Task { await model.submit(review) }
                }
                Button("キャンセル", role: .cancel) { removalReview = nil }
            }
        } message: {
            if let review = removalReview {
                Text(review.information.joined(separator: "\n") + (review.action == .discard
                    ? "\niPhone内の原本を削除します。Mac miniや写真にコピーがなければ、この動画を失います。Mac miniと写真の動画は削除しません。"
                    : "\n最後に取得した保存検証と軽量版の有効な明示確認に基づき、削除直前に動画別に照合します。条件を満たさない原本は削除しません。オフラインではMac mini原本の現在の存在を確認していません。iPhone内の原本だけを削除し、Mac miniと写真の動画は削除しません。"))
            }
        }
    }
}

/// The native control owns the title's rendering, hit area and accessibility
/// state together, including multiline Dynamic Type measurement.
private struct LibraryRenditionPlaybackButton: UIViewRepresentable {
    let title: String
    let isEnabled: Bool
    let identifier: String
    var role: UIButton.Role = .normal
    let action: @MainActor @Sendable () -> Void
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.isEnabled) private var environmentIsEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(action: { @MainActor @Sendable in action() })
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.setTitleColor(.label, for: .normal)
        button.setTitleColor(.label, for: .disabled)
        button.setTitleColor(.label, for: .highlighted)
        button.isAccessibilityElement = true
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.addTarget(context.coordinator, action: #selector(Coordinator.activate), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = { @MainActor @Sendable in action() }
        button.role = role
        button.setTitleColor(.label, for: .normal)
        button.setTitleColor(.label, for: .disabled)
        button.setTitleColor(.label, for: .highlighted)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith:
            UITraitCollection(preferredContentSizeCategory: contentSizeCategory))
        button.isEnabled = isEnabled && environmentIsEnabled
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = title
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView button: UIButton, context: Context) -> CGSize? {
        guard let proposedWidth = proposal.width, proposedWidth.isFinite else { return nil }
        let width = max(0, proposedWidth)
        let measured = button.titleLabel?.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)) ?? .zero
        return CGSize(width: width, height: max(44, ceil(measured.height)))
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

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor @Sendable () -> Void
        init(action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
        @objc func activate() { action() }
    }
}

private struct LibraryActionButtonStyle: ButtonStyle {
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

private struct LibraryOperationResults: View {
    let item: LibraryItem
    var body: some View {
        ForEach(item.operationResults) { result in
            Text("\(result.action.title)：\(result.outcome.text)")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("library.result.\(item.id.rawValue).\(result.id.rawValue)")
        }
    }
}

private struct LibrarySubmissionStatus: View {
    let model: LibraryModel
    var capture: CaptureID?
    var body: some View {
        if let issue = model.inputIssue { Text(issue).accessibilityIdentifier("library.inputIssue") }
        ForEach(model.submissions.filter { submission in
            capture == nil || submission.request.targets.contains { $0.capture == capture }
        }) { submission in
            LibrarySection {
                ForEach(submission.request.targets.filter { capture == nil || $0.capture == capture }, id: \.capture) { target in
                    let result = model.item(target.capture)?.operationResults.first {
                        $0.id == submission.request.id && $0.action == submission.request.action
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        LibraryWrappingText(text: model.item(target.capture)?.title ?? "動画 \(target.capture.rawValue)", style: .headline,
                            identifier: "library.submission.title.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                            .accessibilityIdentifier("library.submission.title.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                        LibraryWrappingText(text: submission.request.action.title,
                            identifier: "library.submission.action.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                            .accessibilityIdentifier("library.submission.action.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                        LibraryWrappingText(text: result?.outcome.text ?? submission.phase.text,
                            identifier: "library.submission.phase.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                            .accessibilityIdentifier("library.submission.phase.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("library.submission.target.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                }
            } header: {
                LibraryWrappingText(text: "開始した操作の照合", style: .headline,
                    identifier: "library.submission.header.\(submission.request.id.rawValue)")
                    .accessibilityIdentifier("library.submission.header.\(submission.request.id.rawValue)")
            }
        }
    }
}

/// These sections grow with their text instead of using collection-view cell
/// heights. The scroll view owns clipping and accessibility scroll geometry.
private struct LibrarySection<Content: View, Header: View>: View {
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

private extension LibrarySection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() })
    }
}
