import SwiftUI

struct ProductCaptureSettingsView: View {
    @Bindable var model: ProductCaptureCoordinator
    let visit: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProductCaptureSettingsDraft
    @State private var issue: String?
    @State private var isApplying = false

    init(model: ProductCaptureCoordinator, visit: UUID?) {
        self.model = model
        self.visit = visit
        _draft = State(initialValue: ProductCaptureSettingsDraft(model.preferences))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("希望する設定") {
                    Picker("カメラ", selection: $draft.camera) {
                        Text("選択してください").tag("")
                        if !draft.camera.isEmpty, !model.cameras.contains(where: { $0.id == draft.camera }) {
                            Text("保存したカメラ（現在未確認）").tag(draft.camera)
                        }
                        ForEach(model.cameras, id: \.id) { camera in
                            Text(camera.label).tag(camera.id)
                        }
                    }
                    .accessibilityIdentifier("capture.settings.camera")
                    LabeledContent("解像度", value: "4K（3840×2160）")
                    Picker("フレームレート", selection: $draft.framesPerSecond) {
                        Text("選択してください").tag(0)
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                    }.accessibilityIdentifier("capture.settings.fps")
                    Picker("記録形式", selection: $draft.codec) {
                        Text("選択してください").tag("")
                        ForEach([CaptureCodec.proRes422LT, .proRes422, .proRes422Proxy], id: \.self) { codec in
                            Text(ProductCaptureText.codec(codec)).tag(codec.rawValue)
                        }
                    }.accessibilityIdentifier("capture.settings.codec")
                    Picker("Log", selection: $draft.log) {
                        Text("選択してください").tag("")
                        ForEach([CaptureLogEncoding.appleLog, .appleLog2], id: \.self) { log in
                            Text(ProductCaptureText.log(log)).tag(log.rawValue)
                        }
                    }.accessibilityIdentifier("capture.settings.log")
                }
                Section("手動設定") {
                    HStack {
                        Text("シャッター（秒）")
                        TextField("分子", text: $draft.shutterTicks).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("シャッター秒の分子")
                        Text("/")
                        TextField("分母", text: $draft.shutterTimescale).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("シャッター秒の分母")
                    }
                    LabeledContent("ISO") {
                        TextField("ISOを入力", text: $draft.iso).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("capture.settings.iso")
                    }
                    LabeledContent("倍率") {
                        TextField("倍率を入力", text: $draft.zoom).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("capture.settings.zoom")
                    }
                    if supportsAperture {
                        LabeledContent("絞り") {
                            TextField("変更しない", text: $draft.aperture).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("capture.settings.aperture")
                        }
                    } else if !draft.aperture.isEmpty {
                        Text("保存した絞り指定：\(draft.aperture)。現在の組合せで絞りの調整に対応するかは未確認です。")
                            .font(.footnote)
                        Button("保存した絞り指定を外す") { draft.aperture = "" }
                            .accessibilityIdentifier("capture.settings.clearAperture")
                    }
                    Picker("手ブレ補正", selection: $draft.stabilization) {
                        Text("選択してください").tag("")
                        ForEach(stabilizationChoices, id: \.self) { mode in
                            Text(ProductCaptureText.stabilization(mode)).tag(mode)
                        }
                    }
                    Text("補正の品質・動作の評価は未完了です。選んだ条件が使えるかを適用時に確認します。")
                        .font(.footnote)
                }
                Section("記録方式") {
                    Picker("記録方式の候補", selection: $draft.output) {
                        Text("選択してください").tag("")
                        Text("Movieファイル出力").tag(ExplorationOutputCandidate.movieFile.rawValue)
                        Text("サンプル書込").tag(ExplorationOutputCandidate.sampleWriter.rawValue)
                    }.accessibilityIdentifier("capture.settings.output")
                    Text("両方式とも実機での採用確認は未完了です。選んだ方式が使えない場合、自動で別方式に切り替えません。")
                        .font(.footnote)
                }
                Section("現在のカメラで確認できた条件") {
                    Text(capabilityDescription)
                        .accessibilityIdentifier("capture.settings.capabilities")
                    Text("形式・fps・Logの一覧はカメラから取得した条件です。記録方式・手動値を含む組合せと実適用値は、保存して適用すると確認します。")
                        .font(.footnote)
                    Button("カメラの条件を再確認") { Task { if let visit { await model.discover(visit: visit) } } }
                        .disabled(model.isBusy || model.isPreparing)
                }
                if let issue = issue ?? model.issue {
                    Section { Text(issue).accessibilityIdentifier("capture.settings.issue") }
                }
                Section {
                    Button("保存して適用") { Task { await apply() } }
                        .disabled(isApplying || model.isBusy || model.isPreparing)
                        .accessibilityIdentifier("capture.settings.apply")
                    Text("希望する設定を保存します。使えない条件は自動で変更しません。録画中・保存中は設定を変更できません。")
                        .font(.footnote)
                }
            }
            .disabled(isApplying)
            .navigationTitle("撮影設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() }.disabled(isApplying) }
            }
            .interactiveDismissDisabled(isApplying)
        }
    }

    private var selectedCamera: ExplorationCameraDescription? { model.cameras.first { $0.id == draft.camera } }

    private var stabilizationChoices: [String] {
        var modes = Set(selectedCamera?.formats.flatMap(\.stabilizationModes) ?? [])
        if !draft.stabilization.isEmpty { modes.insert(draft.stabilization) }
        return modes.sorted()
    }

    private var supportsAperture: Bool {
        guard let capabilities = model.prepared?.capabilities,
              let configuration = capabilities.controlsForConfiguration,
              configuration.camera == draft.camera, configuration.width == 3840, configuration.height == 2160,
              configuration.framesPerSecond == draft.framesPerSecond,
              configuration.codec.rawValue == draft.codec, configuration.logEncoding.rawValue == draft.log,
              configuration.stabilizationMode == draft.stabilization,
              case .supported(let limits) = capabilities.manualControls,
              case .supported = limits.aperture else { return false }
        return true
    }

    private var capabilityDescription: String {
        guard let camera = selectedCamera else { return "カメラは未選択、または現在の端末では確認できません。" }
        let formats = camera.formats.filter { $0.width == 3840 && $0.height == 2160 }
        guard !formats.isEmpty else { return "このカメラの4K形式は確認できません。" }
        let combinations = Set(formats.flatMap { format in
            [24, 30].filter { fps in format.frameRateRanges.contains { $0.contains(Double(fps)) } }
                .flatMap { fps in format.logEncodings.map { "4K · \(fps)fps · \(ProductCaptureText.log($0))" } }
        })
        guard !combinations.isEmpty else { return "このカメラの4K・24/30fps・Logの組合せは確認できません。" }
        return combinations.sorted().joined(separator: "\n")
    }

    private func apply() async {
        guard let visit else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let preferences = try draft.preferences()
            await model.updatePreferences(preferences, visit: visit)
            guard model.captureVisit == visit, !Task.isCancelled else { return }
            guard model.preferences == preferences, model.issue == nil else {
                issue = "設定を保存できませんでした。入力値と保存領域を確認してください。"
                return
            }
            await model.prepare(visit: visit)
            dismiss()
        } catch {
            issue = "カメラ・fps・記録形式・Log・補正・記録方式を選び、シャッター・ISO・倍率に正の数を入力してください。"
        }
    }
}

private struct ProductCaptureSettingsDraft {
    var camera = ""
    var framesPerSecond = 0
    var codec = ""
    var log = ""
    var stabilization = ""
    var output = ""
    var shutterTicks = ""
    var shutterTimescale = ""
    var iso = ""
    var zoom = ""
    var aperture = ""

    init(_ preferences: ProductCapturePreferences) {
        output = preferences.outputCandidate?.rawValue ?? ""
        guard let desired = preferences.desired else { return }
        camera = desired.configuration.camera
        framesPerSecond = desired.configuration.framesPerSecond
        codec = desired.configuration.codec.rawValue
        log = desired.configuration.logEncoding.rawValue
        stabilization = desired.configuration.stabilizationMode
        shutterTicks = String(desired.exposure.shutter.ticks)
        shutterTimescale = String(desired.exposure.shutter.timescale)
        iso = String(desired.exposure.iso)
        zoom = String(desired.zoom)
        aperture = desired.exposure.aperture.map { String($0) } ?? ""
    }

    func preferences() throws -> ProductCapturePreferences {
        guard let codec = CaptureCodec(rawValue: codec), let log = CaptureLogEncoding(rawValue: log),
              let output = ExplorationOutputCandidate(rawValue: output),
              let ticks = Int64(shutterTicks), let timescale = Int32(shutterTimescale),
              let iso = Double(iso), let zoom = Double(zoom),
              aperture.isEmpty || Double(aperture) != nil else { throw CaptureContractError.invalidValue }
        let configuration = try CaptureConfiguration(camera: camera, width: 3840, height: 2160,
            framesPerSecond: framesPerSecond, codec: codec, logEncoding: log, stabilizationMode: stabilization)
        let exposure = try CaptureManualExposure(shutter: .init(ticks: ticks, timescale: timescale),
                                                 iso: iso, aperture: Double(aperture))
        let preferences = ProductCapturePreferences(
            desired: try DesiredCaptureSettings(configuration: configuration, exposure: exposure, zoom: zoom),
            outputCandidate: output)
        guard preferences.isValid else { throw CaptureContractError.invalidValue }
        return preferences
    }
}
