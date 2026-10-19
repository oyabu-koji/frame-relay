import SwiftUI

struct LibraryView: View {
    @Bindable var model: LibraryModel
    var showExploration: (() -> Void)? = nil
    var showConnection: (() -> Void)? = nil
    @State private var showsHistory = false

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                        Section {
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
                        Section {
                            NavigationLink {
                                LibraryDetailView(model: model, capture: item.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title).font(.headline)
                                        .accessibilityIdentifier("library.itemTitle.\(item.id.rawValue)")
                                    Text(item.status(.save))
                                        .accessibilityIdentifier("library.itemSave.\(item.id.rawValue)")
                                    Text(item.status(.original))
                                        .accessibilityIdentifier("library.itemOriginal.\(item.id.rawValue)")
                                    Text(item.status(.removal))
                                        .accessibilityIdentifier("library.itemRemoval.\(item.id.rawValue)")
                                    if item.requiresReconciliation {
                                        Text("要照合").bold()
                                            .accessibilityIdentifier("library.itemReconciliation.\(item.id.rawValue)")
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                            }
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
                        Section {
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
        List {
            LibraryLoadStatus(model: model)
            if let item = model.item(capture) {
                Section {
                    Text(item.title)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("library.detailIdentity")
                }
                Section {
                    ForEach(item.statuses) { status in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.axis.title).font(.headline)
                            Text(status.text)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("library.status.\(status.axis.rawValue)")
                    }
                } header: {
                    Text("動画の状態").foregroundStyle(Color.primary)
                }
                if item.requiresReconciliation {
                    Section {
                        Text("保存記録と原本の状態に未確定の部分があります。再読み込みで現在状態を確認できます。未完了の削除や写真への追加は自動実行しません。")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("library.detailReconciliationExplanation")
                    } header: {
                        Text("確認が必要です").foregroundStyle(Color.primary)
                            .accessibilityIdentifier("library.detailReconciliationHeading")
                    }
                }
                if !item.isDiscardHistory {
                    Section {
                        ForEach(LibraryAction.single) { action in
                            LibraryActionButton(model: model, action: action, captures: [capture])
                        }
                    } header: {
                        Text("この動画の操作").foregroundStyle(Color.primary)
                    }
                }
                Section {
                    LibraryOperationResults(item: item)
                } header: {
                    Text("動画別の処理結果").foregroundStyle(Color.primary)
                }
                LibrarySubmissionStatus(model: model, capture: capture)
            } else {
                Text("この動画の記録を取得できません。再読み込みしてください。")
            }
        }
        .padding(.top)
        .clipped()
        .navigationTitle("動画の詳細")
        // Keep the inline title readable when long status rows scroll behind it.
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .refreshable { await model.refresh() }
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
            Section {
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
            Section {
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
