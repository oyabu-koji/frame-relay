import SwiftUI
import UniformTypeIdentifiers

struct ExplorationView: View {
    @Bindable var model: ExplorationCoordinator
    @State private var showsImporter = false
    @State private var importIssue: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("撮影基盤の探索専用画面です。操作・値は試験条件であり、方式採用・品質合格・製品UIの確定を示しません。")
                        .accessibilityIdentifier("exploration.purpose")
                    #if targetEnvironment(simulator)
                    Text("Simulator：実カメラ・マイク・録画能力は未確認です。")
                        .accessibilityIdentifier("exploration.simulator")
                    #endif
                    Text("起動時には権限要求・録画・媒体作成を開始しません。")
                }
                Section("試験票と比較候補") {
                    Button("試験票JSONを選ぶ") { showsImporter = true }
                        .disabled(!model.canChangeInputs)
                        .accessibilityIdentifier("exploration.import")
                    if let ticket = model.ticket {
                        LabeledContent("ケース", value: ticket.caseID)
                        LabeledContent("条件版 / 反復", value: "\(ticket.conditionVersion) / \(ticket.repetitionID)")
                        LabeledContent("確認記録", value: ticket.authorizationRecordReference)
                        Text("参照記載だけでG01/G02全体の成立を判定しません。実施者は該当記録と対象を照合してください。")
                            .font(.footnote)
                    } else { Text("試験票：未束縛").accessibilityIdentifier("exploration.ticketStatus") }
                    Picker("出力候補", selection: Binding(get: { model.outputCandidate }, set: model.selectOutput)) {
                        Text("未選択").tag(ExplorationOutputCandidate?.none)
                        Text("MovieFileOutput").tag(ExplorationOutputCandidate?.some(.movieFile))
                        Text("Sample + Writer").tag(ExplorationOutputCandidate?.some(.sampleWriter))
                    }.disabled(!model.canChangeInputs)
                    Picker("保存候補", selection: Binding(get: { model.storeCandidate }, set: model.selectStore)) {
                        Text("未選択").tag(ExplorationStoreCandidate?.none)
                        Text("Atomic file").tag(ExplorationStoreCandidate?.some(.atomicFile))
                        Text("Core Data / SQLite").tag(ExplorationStoreCandidate?.some(.sqlite))
                    }.disabled(!model.canChangeInputs)
                    Text(displayDescription)
                    Button(model.isPreparing ? "準備中" : "実機探索を準備") { Task { await model.prepare() } }
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("exploration.prepare")
                }
                if !model.issues.isEmpty || importIssue != nil {
                    Section("実行できない理由") {
                        ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in Text(issue.message) }
                        if let importIssue { Text(importIssue) }
                    }.accessibilityIdentifier("exploration.issues")
                }
                Section("希望・能力・実適用") {
                    Text(desiredDescription)
                    Text(model.prepared == nil ? "能力：未照会 / 実適用：未確認" : "能力照会と適用読戻しを取得。実録画・品質とは別です。")
                        .accessibilityIdentifier("exploration.capabilityStatus")
                    if let applied = model.prepared?.applied.values.value {
                        Text("実適用：\(applied.configuration.camera) / \(applied.configuration.framesPerSecond)fps / ISO \(applied.exposure.iso) / \(applied.configuration.stabilizationMode)")
                    }
                    ForEach(model.cameras, id: \.id) { camera in
                        DisclosureGroup("\(camera.id)：\(camera.label)（\(camera.isVirtual ? "論理" : "物理")）") {
                            ForEach(camera.formats, id: \.id) { format in
                                Text("\(format.id)：\(format.width)×\(format.height) / Log: \(format.logEncodings.map(\.rawValue).joined(separator: ", ")) / \(format.stabilizationModes.joined(separator: ", "))")
                                    .font(.caption)
                            }
                        }
                    }
                }
                Section("録画操作") {
                    LabeledContent("REC", value: phaseDescription)
                    LabeledContent("WB", value: model.capture.map { String(describing: $0.whiteBalance) } ?? "待機状態も未確認")
                    HStack {
                        Button("REC") { Task { await model.record() } }
                            .disabled(model.prepared == nil || model.isBusy || model.diagnosticsIssue != nil)
                            .accessibilityIdentifier("exploration.rec")
                        Button("STOP") { Task { await model.stop() } }
                            .disabled(!canStop)
                            .accessibilityIdentifier("exploration.stop")
                    }
                    Button("WB合わせ直し（測定区間未束縛）") { model.refreshWhiteBalance() }
                        .disabled(true)
                    Text("録画開始の受付・実開始・終端・原本確定・結果commitを別々に記録します。")
                        .font(.footnote)
                }
                Section("音声と保存") {
                    if let audio = model.capture?.audio ?? model.prepared?.audio {
                        LabeledContent("レベル", value: audio.level.value.map { String($0.linearAmplitude) } ?? "未測定")
                        LabeledContent("入力", value: String(describing: audio.input))
                        LabeledContent("データ到着", value: audioArrivalDescription(audio))
                        LabeledContent("書込", value: String(describing: audio.writing))
                    } else { Text("音量・入力・到着・書込：未確認") }
                    LabeledContent("保存", value: model.save.map { String(describing: $0.phase) } ?? "未開始")
                    if let saveIssue = model.saveIssue { Text(saveIssue) }
                    Text("品質：許容範囲未合意・未測定 / PRD：未評価")
                        .accessibilityIdentifier("exploration.qualityStatus")
                }
                Section("直近の観測（診断表示）") {
                    LabeledContent("観測の永続化", value: diagnosticsDescription)
                        .accessibilityIdentifier("exploration.diagnosticsStatus")
                    if let issue = model.diagnosticsIssue { Text(issue) }
                    Text("表示は直近100件までです。観測の保存と媒体の保存結果・品質は別に確認します。")
                        .font(.footnote)
                    ForEach(Array(model.observations.enumerated()), id: \.offset) { _, observation in
                        VStack(alignment: .leading) {
                            Text(observation.code).font(.caption.monospaced())
                            Text(observation.detail).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("撮影基盤の探索")
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    Task {
                        await model.importTicket(from: url)
                        importIssue = nil
                    }
                case .failure: importIssue = ExplorationIssue.ticketReadFailed.message
                }
            }
        }
    }

    private var desiredDescription: String {
        guard let ticket = model.ticket else { return "希望値：未選択" }
        let desired = ticket.desired
        return "\(desired.configuration.camera) / \(ticket.formatID) / \(desired.configuration.width)×\(desired.configuration.height) / \(desired.configuration.framesPerSecond)fps / \(desired.configuration.codec.rawValue) / \(desired.configuration.logEncoding.rawValue) / ISO \(desired.exposure.iso) / シャッター \(desired.exposure.shutter.ticks)/\(desired.exposure.shutter.timescale) 秒"
    }

    private var displayDescription: String {
        switch model.ticket?.display {
        case .recordingOnly: return "記録単独の比較条件。Rec.709表示の成立・品質は未評価。"
        case .standardRec709AlongsideRecording: return "固定Rec.709表示は未実装・未確認。Log 1/2の変換を同一扱いしません。"
        case nil: return "表示条件は未選択。固定Rec.709変換は未実装・未確認。"
        }
    }

    private var phaseDescription: String {
        guard let phase = model.capture?.phase else { return "未開始" }
        switch phase {
        case .ready: return "待機"
        case .starting: return "開始準備・実開始未確認"
        case .recording: return "記録中"
        case .stopping: return "停止要求済み・終端待ち"
        case .ended: return "記録終端確認・保存は別状態"
        case .blocked: return "準備できません"
        }
    }

    private var canStop: Bool {
        model.capture?.phase == .starting || model.capture?.phase == .recording
    }

    private var diagnosticsDescription: String {
        if model.diagnosticsIssue != nil { return "失敗・照合が必要" }
        if let sequence = model.diagnosticsSequence { return "観測 \(sequence) まで永続化済み" }
        return model.diagnosticsReady ? "保存先を準備済み・観測待ち" : "未作成"
    }

    private func audioArrivalDescription(_ state: CaptureAudioState) -> String {
        if case .received(let span) = state.arrival { return "到着 \(span.count) samples（書込と別）" }
        return "未確認 / \(String(describing: state.arrival))"
    }
}
