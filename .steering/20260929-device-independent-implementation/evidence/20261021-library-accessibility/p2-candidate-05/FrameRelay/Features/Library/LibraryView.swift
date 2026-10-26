import SwiftUI
import UIKit
#if DEBUG && targetEnvironment(simulator)
import OSLog
#endif

struct LibraryView: View {
    @Bindable var model: LibraryModel
    var showCapture: (() -> Void)? = nil
    var showExploration: (() -> Void)? = nil
    var showConnection: (() -> Void)? = nil
    @State private var showsHistory = false

    var body: some View {
        NavigationStack {
            LibraryScrollView {
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
                        if items.isEmpty, model.failure == nil, !model.isLoading {
                            Text(showsHistory ? "破棄の履歴はありません" : "撮影した動画はありません")
                                .accessibilityIdentifier("library.empty")
                        }
                        ForEach(items) { item in
                            LibrarySection {
                                NavigationLink {
                                    LibraryDetailView(model: model, capture: item.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.title).font(.headline)
                                            .accessibilityIdentifier("library.itemTitle.\(item.id.rawValue)")
                                        Text(item.captureDateDescription)
                                            .accessibilityIdentifier("library.itemCapturedAt.\(item.id.rawValue)")
                                        Text(item.status(.save))
                                            .accessibilityIdentifier("library.itemSave.\(item.id.rawValue)")
                                        Text(item.status(.original))
                                            .accessibilityIdentifier("library.itemOriginal.\(item.id.rawValue)")
                                        Text(item.status(.removal))
                                            .accessibilityIdentifier("library.itemRemoval.\(item.id.rawValue)")
                                        Text(item.status(.photos))
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

private struct LibraryDetailView: View {
    @Bindable var model: LibraryModel
    let capture: CaptureID

    var body: some View {
        LibraryDetailViewport {
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
                                Text(status.axis.title).font(.headline)
                                Text(status.text)
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
    @State private var discardTarget: CaptureID?

    var body: some View {
        let availability = model.availability(action, captures: captures)
        VStack(alignment: .leading, spacing: 6) {
            Button(action.title, role: action == .discard ? .destructive : nil) {
                if action == .discard { discardTarget = captures.first }
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
        .confirmationDialog("この原本を破棄しますか？", isPresented: Binding(
            get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } }), titleVisibility: .visible) {
            if let target = discardTarget {
                Button("対象の原本を破棄", role: .destructive) {
                    Task { await model.submit(.discard, captures: [target], discardRiskAcknowledged: true) }
                }
                Button("キャンセル", role: .cancel) { discardTarget = nil }
            }
        } message: {
            if let target = discardTarget {
                Text("対象：\(model.item(target)?.title ?? target.rawValue)。iPhone内の原本を削除します。Mac miniや写真にコピーがなければ、この動画を失います。Mac miniと写真の動画は削除しません。")
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
                        Text(model.item(target.capture)?.title ?? "動画 \(target.capture.rawValue)").font(.headline)
                            .accessibilityIdentifier("library.submission.title.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                        Text(submission.request.action.title)
                            .accessibilityIdentifier("library.submission.action.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                        Text(result?.outcome.text ?? submission.phase.text)
                            .accessibilityIdentifier("library.submission.phase.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("library.submission.target.\(target.capture.rawValue).\(submission.request.id.rawValue)")
                }
            } header: {
                Text("開始した操作の照合").foregroundStyle(Color.primary)
                    .accessibilityIdentifier("library.submission.header.\(submission.request.id.rawValue)")
            }
        }
    }
}

/// Pin the hosted scroll view to an actual native safe-area viewport, rather
/// than letting its native frame extend underneath the navigation bar.
private struct LibraryDetailViewport<Content: View>: UIViewControllerRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> LibraryDetailViewportController<Content> {
        LibraryDetailViewportController(content: content, environment: context.environment)
    }

    func updateUIViewController(_ controller: LibraryDetailViewportController<Content>, context: Context) {
        controller.update(content: content, environment: context.environment)
    }

    static func dismantleUIViewController(_ controller: LibraryDetailViewportController<Content>, coordinator: ()) {
        controller.detachContent()
    }
}

private struct LibraryDetailHostedContent<Content: View>: View {
    let content: Content
    let environment: EnvironmentValues

    var body: some View {
        ScrollView {
            content
        }
        .environment(\.self, environment)
    }
}

private final class LibraryDetailViewportController<Content: View>: UIViewController {
    private let hosting: UIHostingController<LibraryDetailHostedContent<Content>>
    private var contentConstraints: [NSLayoutConstraint] = []

    init(content: Content, environment: EnvironmentValues) {
        hosting = UIHostingController(rootView: LibraryDetailHostedContent(content: content, environment: environment))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        hosting.view.clipsToBounds = true
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        let safeArea = view.safeAreaLayoutGuide
        contentConstraints = [
            hosting.view.topAnchor.constraint(equalTo: safeArea.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor)
        ]
        NSLayoutConstraint.activate(contentConstraints)
        hosting.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        #if DEBUG && targetEnvironment(simulator)
        LibraryViewportDiagnostics.recordNative(view, hosted: hosting.view)
        #endif
    }

    func update(content: Content, environment: EnvironmentValues) {
        hosting.rootView = LibraryDetailHostedContent(content: content, environment: environment)
    }

    func detachContent() {
        guard hosting.parent === self else { return }
        hosting.willMove(toParent: nil)
        NSLayoutConstraint.deactivate(contentConstraints)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
    }
}

private struct LibraryScrollView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                content
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
            .clipped()
            .onAppear {
                #if DEBUG && targetEnvironment(simulator)
                LibraryViewportDiagnostics.record(viewport)
                #endif
            }
            .onChange(of: viewport.size) { _, _ in
                #if DEBUG && targetEnvironment(simulator)
                LibraryViewportDiagnostics.record(viewport)
                #endif
            }
            .onChange(of: viewport.safeAreaInsets) { _, _ in
                #if DEBUG && targetEnvironment(simulator)
                LibraryViewportDiagnostics.record(viewport)
                #endif
            }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
private enum LibraryViewportDiagnostics {
    private static let logger = Logger(subsystem: "com.oyabu.FrameRelay", category: "LibraryViewport")
    private static var remaining = 16

    static func record(_ viewport: GeometryProxy) {
        guard shouldRecord() else { return }
        let size = viewport.size
        let insets = viewport.safeAreaInsets
        let frame = viewport.frame(in: .global)
        logger.info("viewport size=(\(size.width, privacy: .public),\(size.height, privacy: .public)) safeArea=(\(insets.top, privacy: .public),\(insets.leading, privacy: .public),\(insets.bottom, privacy: .public),\(insets.trailing, privacy: .public)) frame=(\(frame.minX, privacy: .public),\(frame.minY, privacy: .public),\(frame.width, privacy: .public),\(frame.height, privacy: .public))")
    }

    static func recordNative(_ container: UIView, hosted: UIView) {
        guard shouldRecord() else { return }
        let frame = container.convert(container.bounds, to: nil)
        let insets = container.safeAreaInsets
        let hostedFrame = hosted.convert(hosted.bounds, to: nil)
        let hostedInsets = hosted.safeAreaInsets
        logger.info("native viewport frame=(\(frame.minX, privacy: .public),\(frame.minY, privacy: .public),\(frame.width, privacy: .public),\(frame.height, privacy: .public)) safeArea=(\(insets.top, privacy: .public),\(insets.leading, privacy: .public),\(insets.bottom, privacy: .public),\(insets.trailing, privacy: .public)) hostedFrame=(\(hostedFrame.minX, privacy: .public),\(hostedFrame.minY, privacy: .public),\(hostedFrame.width, privacy: .public),\(hostedFrame.height, privacy: .public)) hostedSafeArea=(\(hostedInsets.top, privacy: .public),\(hostedInsets.leading, privacy: .public),\(hostedInsets.bottom, privacy: .public),\(hostedInsets.trailing, privacy: .public))")
    }

    private static func shouldRecord() -> Bool {
        guard ProcessInfo.processInfo.environment["FR_LIBRARY_VIEWPORT_DIAGNOSTICS"] == "1",
              remaining > 0 else { return false }
        remaining -= 1
        return true
    }
}
#endif

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
