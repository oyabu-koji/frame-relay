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
                                        LibraryWrappingText(text: item.status(.removal),
                                            identifier: "library.itemRemoval.\(item.id.rawValue)")
                                            .accessibilityIdentifier("library.itemRemoval.\(item.id.rawValue)")
                                        LibraryWrappingText(text: item.status(.photos),
                                            identifier: "library.itemPhotos.\(item.id.rawValue)")
                                            .accessibilityIdentifier("library.itemPhotos.\(item.id.rawValue)")
                                        if item.requiresReconciliation {
                                            Text("要照合").bold()
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
                                    Toggle("この動画を選択", isOn: Binding(
                                        get: { model.selected.contains(item.id) },
                                        set: { model.select(item.id, selected: $0) }))
                                    .accessibilityLabel("\(item.title)を選択")
                                    .accessibilityIdentifier("library.select.\(item.id.rawValue)")
                                }
                                LibraryOperationResults(item: item)
                            }
                        }
                        if !showsHistory, !snapshot.remoteItems.isEmpty {
                            ForEach(snapshot.remoteItems) { item in
                                LibraryRemoteInventoryRow(item: item)
                            }
                        }
                        if !showsHistory {
                            LibrarySection {
                                ForEach(LibraryAction.multiple) { action in
                                    LibraryActionButton(model: model, action: action, captures: model.selected)
                                }
                            } header: {
                                Text("選択した\(model.selected.count)本の操作").foregroundStyle(Color.primary)
                            }
                        }
                    }
                    LibrarySubmissionStatus(model: model)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(showsHistory ? "破棄の履歴" : "ライブラリ")
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
    var body: some View {
        LibrarySection {
            VStack(alignment: .leading, spacing: 8) {
                LibraryWrappingText(text: item.title, style: .headline)
                LibraryWrappingText(text: item.captureDateDescription)
                    .accessibilityIdentifier("library.remote.date.\(item.id.accessibilityToken)")
                LibraryWrappingText(text: item.storageDescription)
                LibraryWrappingText(text: item.localDescription)
                    .accessibilityIdentifier("library.remote.local.\(item.id.accessibilityToken)")
                LibraryWrappingText(text: item.mediaDescription)
                if item.hasIdentityConflict { Text("要照合").bold() }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("library.remote.item.\(item.id.accessibilityToken)")
        } header: { Text("Macの保存記録").foregroundStyle(Color.primary) }
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
                    ForEach(item.photoRegistrations) { photo in
                        LibraryPhotoRegistrationSection(model: model, capture: capture, photo: photo)
                    }
                    if item.requiresReconciliation {
                        LibrarySection {
                            Text("保存記録、原本、写真の状態に未確定の部分があります。保存記録と原本は再読み込みで確認できます。写真側の存在は、対象ごとの説明を確認して照合してください。未完了の削除や写真への追加は自動実行しません。")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("library.detailReconciliationExplanation")
                        } header: {
                            Text("確認が必要です").foregroundStyle(Color.primary)
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
                            ForEach(LibraryAction.single) { action in
                                LibraryActionButton(model: model, action: action, captures: [capture])
                            }
                        } header: {
                            Text("この動画の操作").foregroundStyle(Color.primary)
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

/// Native multiline text keeps its measured width and Dynamic Type traits
/// available to UIKit's text layout and accessibility geometry.
private struct LibraryWrappingText: UIViewRepresentable {
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

private struct LibraryPhotoRegistrationSection: View {
    let model: LibraryModel
    let capture: CaptureID
    let photo: LibraryPhotoRegistration

    var body: some View {
        LibrarySection {
            Text("過去の登録：\(photo.registrationResult)")
                .accessibilityIdentifier("library.photo.registration.\(photo.id.rawValue)")
            Text("写真側の存在：\(photo.presenceResult)")
                .accessibilityIdentifier("library.photo.presence.\(photo.id.rawValue)")
            if let reason = photo.reconciliationReason {
                Text("対象：\(model.item(capture)?.title ?? capture.rawValue)、\(photo.title)。\(reason)")
                    .accessibilityIdentifier("library.photo.reason.\(photo.id.rawValue)")
                if let unavailable = photo.reconciliationUnavailableReason {
                    Text(unavailable)
                        .accessibilityIdentifier("library.photo.unavailable.\(photo.id.rawValue)")
                } else {
                    Text("この照合の操作時だけ写真の読み取り許可を求めます。許可しなくても撮影は続けられます。")
                        .accessibilityIdentifier("library.photo.permissionReason.\(photo.id.rawValue)")
                    Button("写真の読み取りで存在を照合") {
                        Task { await model.reconcilePhotos(photo, capture: capture) }
                    }
                    .disabled(!model.canReconcilePhotos(photo, capture: capture))
                    .accessibilityIdentifier("library.photo.reconcile.\(photo.id.rawValue)")
                }
            }
            if model.photoReconciliations.contains(photo.id) {
                ProgressView("写真側の存在を照合中")
            }
            if let message = model.photoReconciliationMessages[photo.id] {
                Text(message)
                    .accessibilityIdentifier("library.photo.feedback.\(photo.id.rawValue)")
            }
        } header: {
            Text("写真の記録：\(photo.title)").foregroundStyle(Color.primary)
        }
        .fixedSize(horizontal: false, vertical: true)
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
            Button(action.title, role: action == .discard ? .destructive : nil) {
                if action == .discard || action == .cleanup { removalReview = model.prepareRemovalReview(action, captures: captures) }
                else { Task { await model.submit(action, captures: captures) } }
            }
            .buttonStyle(LibraryActionButtonStyle())
            .disabled(availability != .available)
            .accessibilityIdentifier("library.action.\(action.rawValue)")
            if let reason = availability.reason {
                Text(reason).font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("library.reason.\(action.rawValue)")
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
