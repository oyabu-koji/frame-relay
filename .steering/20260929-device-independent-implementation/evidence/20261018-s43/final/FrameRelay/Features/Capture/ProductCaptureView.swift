import SwiftUI

struct ProductCaptureView: View {
    @Bindable var model: ProductCaptureCoordinator
    let close: () -> Void
    @State private var showsSettings = false
    @State private var isClosing = false
    @State private var visit: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let source = model.previewSource as? NativeCapturePreviewSource {
                        ProductCapturePreview(source: source)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .background(.black)
                            .accessibilityLabel("カメラの構図プレビュー")
                    } else {
                        ContentUnavailableView("撮影の準備が必要です", systemImage: "camera",
                                               description: Text("撮影設定を選び、現在のカメラで使える条件を確認してください。"))
                    }
                    Text("プレビューの標準Rec.709変換は未対応です。色の仕上がりを確認する表示には使えません。")
                        .font(.footnote)
                    if let issue = model.issue {
                        Text(issue).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("capture.issue")
                    }
                    if model.isPreparing { ProgressView("カメラの条件を確認しています") }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("希望する設定").font(.headline)
                        Text(desiredDescription)
                            .accessibilityIdentifier("capture.desired")
                        Button("撮影設定", systemImage: "slider.horizontal.3") {
                            let currentVisit = visitForUserAction()
                            Task {
                                await model.load(visit: currentVisit)
                                guard model.captureVisit == currentVisit, !Task.isCancelled else { return }
                                showsSettings = true
                            }
                        }
                            .disabled(model.isBusy || model.isPreparing)
                            .accessibilityIdentifier("capture.settings")
                        Button("保存した設定で再準備", systemImage: "arrow.clockwise") {
                            let currentVisit = visitForUserAction()
                            Task {
                                await model.load(visit: currentVisit)
                                await model.discover(visit: currentVisit)
                                await model.prepare(visit: currentVisit)
                            }
                        }
                        .disabled(model.isBusy || model.isPreparing || model.preferences.desired == nil
                                  || model.preferences.outputCandidate == nil)
                        .accessibilityIdentifier("capture.prepare")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("現在の適用状態").font(.headline)
                        Text(appliedDescription).accessibilityIdentifier("capture.applied")
                        Text("実機での記録方式・画質の確認は未完了です。")
                            .font(.footnote)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ホワイトバランス").font(.headline)
                        Text(whiteBalanceDescription).accessibilityIdentifier("capture.whiteBalance")
                        Button("WBを合わせ直す", systemImage: "white.balance.sun") {
                            Task { await model.refreshWhiteBalance() }
                        }
                        .disabled(!model.canRefreshWhiteBalance || isClosing)
                        .accessibilityIdentifier("capture.refreshWhiteBalance")
                        if model.prepared != nil,
                           model.prepared?.capabilities.whiteBalanceRefresh != .supported(true) {
                            Text("この撮影条件ではWBの合わせ直しを利用できません。")
                                .font(.footnote)
                        }
                    }
                    ProductCaptureAudioView(state: model.currentAudio, recovery: model.audioRecovery,
                        canRetry: model.canRetryAudio && !isClosing) { Task { await model.retryAudio() } }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("録画と直近の保存結果").font(.headline)
                        Text(phaseDescription).accessibilityIdentifier("capture.phase")
                        Text(saveDescription).accessibilityIdentifier("capture.save")
                    }
                    Button("ライブラリへ戻る", action: finish)
                        .disabled(isClosing)
                        .accessibilityIdentifier("capture.close")
                }
                .padding()
            }
            .navigationTitle("撮影")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: finish)
                        .disabled(isClosing)
                        .accessibilityIdentifier("capture.closeToolbar")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 24) {
                    Button("REC", systemImage: "record.circle") { Task { await model.record() } }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .disabled(!model.canRecord || isClosing)
                        .accessibilityIdentifier("capture.rec")
                    Button("STOP", systemImage: "stop.fill") { Task { await model.stop() } }
                        .buttonStyle(.bordered)
                        .disabled(!canStop || isClosing)
                        .accessibilityIdentifier("capture.stop")
                }
                .padding().frame(maxWidth: .infinity).background(.bar)
            }
            .sheet(isPresented: $showsSettings) {
                ProductCaptureSettingsView(model: model, visit: visit)
            }
            .task {
                guard !Task.isCancelled else { return }
                let currentVisit = model.enterCapture()
                visit = currentVisit
                await model.load(visit: currentVisit)
                await model.discover(visit: currentVisit)
                if model.preferences.desired != nil, model.preferences.outputCandidate != nil, !model.isBusy {
                    await model.prepare(visit: currentVisit)
                }
            }
        }
    }

    // Backgrounding ends the visit without necessarily dismissing this View. Only a
    // fresh user action (or a newly presented View) may start another visit.
    private func visitForUserAction() -> UUID {
        if let visit, model.captureVisit == visit { return visit }
        let currentVisit = model.enterCapture()
        visit = currentVisit
        return currentVisit
    }

    private func finish() {
        guard !isClosing else { return }
        isClosing = true
        close()
    }

    private var desiredDescription: String {
        guard let desired = model.preferences.desired else { return "未選択。撮影設定から条件を選んでください。" }
        return ProductCaptureText.settings(desired.configuration, exposure: desired.exposure, zoom: desired.zoom,
                                           camera: model.cameras.first { $0.id == desired.configuration.camera }?.label)
    }

    private var appliedDescription: String {
        guard let values = model.prepared?.applied.values.value else { return "未確認。希望する設定はまだ実適用値として確認できていません。" }
        return ProductCaptureText.settings(values.configuration, exposure: values.exposure, zoom: values.zoom,
                                           camera: model.cameras.first { $0.id == values.configuration.camera }?.label)
    }

    private var canStop: Bool {
        model.capture?.phase == .starting || model.capture?.phase == .recording
    }

    private var whiteBalanceDescription: String {
        guard model.prepared != nil else { return "未確認。カメラの準備後に状態を表示します。" }
        switch model.capture?.whiteBalance {
        case .automatic, nil: return "Auto・録画開始時の値で固定します"
        case .locking: return "REC時点のWBを固定しています"
        case .locked: return "固定中"
        case .refreshing:
            return model.capture?.phase == .stopping ? "停止に向けてWBを再固定しています" : "WBを再測定・再固定しています"
        case .restoringAutomatic: return "録画終了・Autoへ戻しています"
        case .unavailable: return "WBの適用を確認できません。撮影条件を確認して再準備してください。"
        }
    }

    private var phaseDescription: String {
        switch model.capture?.phase {
        case .ready, nil: return model.canRecord ? "録画できます" : "準備待ち"
        case .starting: return "録画開始を受け付けました・実開始待ち"
        case .recording: return "録画中"
        case .stopping: return "停止要求済み・録画の終了待ち"
        case .ended: return "録画は終了しました"
        case .blocked: return "録画を開始できません"
        }
    }

    private var saveDescription: String {
        switch model.saveResult {
        case .saved: return "アプリ内への保存完了。ライブラリで原本の再生可否を確認できます。"
        case .partial: return "部分保存。保存された範囲の確認が必要です。"
        case .unknown: return "保存結果不明・要照合。正常保存として扱いません。"
        case .failed: return "保存失敗。ライブラリで保存記録を確認してください。"
        case nil:
            return model.isBusy ? "録画・保存の処理中。保存結果はまだ確定していません。" : "この撮影の保存結果はまだありません。"
        }
    }
}

enum ProductCaptureText {
    static func codec(_ codec: CaptureCodec) -> String {
        switch codec {
        case .proRes422LT: "ProRes 422 LT（標準）"
        case .proRes422: "ProRes 422（上位）"
        case .proRes422Proxy: "ProRes 422 Proxy（容量優先）"
        }
    }

    static func log(_ log: CaptureLogEncoding) -> String {
        log == .appleLog ? "Apple Log" : "Apple Log 2"
    }

    static func stabilization(_ mode: String) -> String {
        switch mode {
        case "off": "OFF"
        case "standard": "標準"
        case "cinematic": "シネマティック"
        case "cinematicExtended": "拡張シネマティック"
        case "cinematicExtendedEnhanced": "強化拡張シネマティック"
        case "auto": "自動"
        default: mode
        }
    }

    static func settings(_ configuration: CaptureConfiguration, exposure: CaptureManualExposure,
                         zoom: Double, camera: String?) -> String {
        "\(camera ?? "保存したカメラ") · \(configuration.width)×\(configuration.height) · \(configuration.framesPerSecond)fps\n"
            + "\(codec(configuration.codec)) · \(log(configuration.logEncoding))\n"
            + "シャッター \(exposure.shutter.ticks)/\(exposure.shutter.timescale) 秒 · ISO \(exposure.iso.formatted()) · 倍率 \(zoom.formatted())×\n"
            + "補正：\(stabilization(configuration.stabilizationMode))"
    }
}
