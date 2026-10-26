import SwiftUI

struct ProductCaptureZoomView: View {
    @Bindable var model: ProductCaptureCoordinator
    @State private var target = ""
    @State private var manualISO = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ズームとレンズ").font(.headline)
            if let snapshot = model.zoom.snapshot {
                Text("実倍率 \(snapshot.applied.values.value?.zoom.formatted() ?? "未確認")×")
                    .accessibilityIdentifier("capture.zoom.actual")
                Text("実カメラ：\(cameraLabel(snapshot.lens)) · ISO \(snapshot.lens.iso?.formatted() ?? "未確認") · F\(snapshot.lens.aperture?.formatted() ?? "未確認")")
                    .font(.caption).accessibilityIdentifier("capture.lens.actual")
                HStack {
                    TextField("目標倍率", text: $target).keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("capture.zoom.target")
                    Button("構図を予告") { if let value = Double(target) { model.selectZoomTarget(value) } }
                        .disabled(!model.canControlZoom || model.isUpdatingZoom || snapshot.phase.isMoving)
                        .accessibilityIdentifier("capture.zoom.forecast")
                }
                Text("設定範囲 \(snapshot.range.lowerBound.formatted())〜\(snapshot.range.upperBound.formatted())×")
                    .font(.caption)
                if !snapshot.stops.isEmpty {
                    Text("現在のカメラ・形式・補正から得た停止候補（画質未評価）").font(.caption)
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(snapshot.stops) { stop in
                                Button("\(stop.factor.formatted())× · \(basis(stop.basis))") {
                                    target = String(stop.factor); model.selectZoomTarget(stop.factor)
                                }.buttonStyle(.bordered).disabled(!model.canControlZoom || model.isUpdatingZoom || snapshot.phase.isMoving)
                            }
                        }
                    }
                }
                if let forecast = model.zoom.forecast {
                    Text("予告の目標：\(forecast.target.formatted())×（実倍率はまだ変更していません）")
                        .accessibilityIdentifier("capture.zoom.selected")
                    if forecast.isWider {
                        widerGuide(forecast)
                    }
                    Text("倍率比による構図の目安です。補正後の画角・レンズ間の位置関係や画質は未確認です。")
                        .font(.caption)
                    if let near = model.nearbyZoomStop {
                        Button("近くの候補 \(near.factor.formatted())×（\(basis(near.basis))）を選ぶ") {
                            target = String(near.factor); model.selectZoomTarget(near.factor)
                        }
                    }
                }
                if case .moving(let target) = snapshot.phase {
                    Text("\(target.formatted())×へ移動中").accessibilityIdentifier("capture.zoom.moving")
                }
                HStack {
                    Button("ズームを開始") { Task { await model.startZoom() } }
                        .disabled(!model.canStartZoom).accessibilityIdentifier("capture.zoom.start")
                    Button("ズームを停止") { Task { await model.stopZoom() } }
                        .disabled(!model.canStopZoom).accessibilityIdentifier("capture.zoom.stop")
                }
                ForEach(snapshot.lens.candidates) { lens in
                    Button("レンズ：\(lens.label)") { Task { await model.switchLens(lens.id) } }
                        .disabled(!lens.available || !snapshot.lens.switchingSupported || !model.canControlZoom || model.isUpdatingZoom)
                    if let reason = lens.constraint { Text(constraint(reason)).font(.caption) }
                }
                HStack {
                    TextField("手動ISO", text: $manualISO).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("capture.lens.iso")
                    Button("ISOを指定") { if let iso = Double(manualISO) { Task { await model.setManualISO(iso) } } }
                        .disabled(!model.canControlZoom).accessibilityIdentifier("capture.lens.setISO")
                }
                Text(snapshot.applied.values.value == nil ? "実適用値を確認中です。次のRECは確認後に開始できます。"
                     : snapshot.lens.isManualExposure ? "ISOは手動固定です。本人の指定を優先します。" : "手動露出の実動作を確認できません。")
                    .font(.caption)
                if let adjustment = snapshot.lens.adjustment, snapshot.applied.values.value != nil {
                    Text(adjustment.wasLimited ? "レンズ補正は設定または端末の上限に達しました。補正後のISOを保持します。" : "レンズ補正後のISOを保持しています。")
                        .font(.caption).accessibilityIdentifier("capture.lens.compensation")
                }
                if let reason = snapshot.lens.constraint { Text(constraint(reason)).font(.caption) }
            } else {
                Text("この撮影条件のズームとレンズ制御は未確認です。カメラの準備後に対応範囲を表示します。")
                    .accessibilityIdentifier("capture.zoom.unavailable")
                HStack {
                    Button("ズームを開始") {}.disabled(true).accessibilityIdentifier("capture.zoom.start")
                    Button("ズームを停止") {}.disabled(true).accessibilityIdentifier("capture.zoom.stop")
                }
            }
            if let issue = model.zoomIssue { Text(constraint(issue)).accessibilityIdentifier("capture.zoom.issue") }
        }
    }

    private func widerGuide(_ forecast: CaptureZoomForecast) -> some View {
        VStack(alignment: .leading) {
            Text("引く方向：外側は現在のカメラでは観測していない範囲です。")
            GeometryReader { proxy in
                let guide = forecast.guide
                ZStack {
                    Rectangle().fill(.gray.opacity(0.15))
                    Rectangle().stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    Rectangle().stroke(.yellow, lineWidth: 2)
                        .frame(width: proxy.size.width * guide.width, height: proxy.size.height * guide.height)
                    Text("現在の範囲").font(.caption)
                }
            }.aspectRatio(16 / 9, contentMode: .fit).frame(maxHeight: 110)
                .accessibilityLabel("目標範囲の中央\(forecast.visibleFraction.formatted(.percent))が現在観測中の範囲")
        }.font(.caption).accessibilityIdentifier("capture.zoom.widerGuide")
    }

    private func basis(_ basis: CaptureZoomStopBasis) -> String {
        switch basis {
        case .nativeMinimum: "カメラの最小倍率"
        case .lensSwitch: "レンズ境界"
        case .secondaryNativeResolution: "形式のネイティブ解像度候補"
        case .upscaleThreshold: "形式の拡大境界"
        }
    }

    private func cameraLabel(_ lens: CaptureLensState) -> String {
        guard let active = lens.activeCamera else { return "未確認" }
        return lens.candidates.first { $0.id == active }?.label
            ?? model.cameras.first { $0.id == active }?.label ?? "現在のカメラ（名称未確認）"
    }

    private func constraint(_ value: String) -> String {
        switch value {
        case "lens_lock_unsupported", "lens_lock_readback_unconfirmed":
            return "レンズを固定する機能を確認できません。切替操作は利用できません。"
        case "lens_iso_policy_unconfirmed": return "レンズ切替時のISO補正方針はまだ確定していません。"
        case "lens_exposure_readback_unconfirmed", "lens_iso_outside_format", "manual_iso_unavailable":
            return "手動露出の適用を確認できません。現在のISOと撮影条件を確認してください。"
        case "zoom_stop_failed": return "ズームの停止を確認できません。現在の倍率を確認してください。"
        case "lens_zoom_mapping_unconfirmed": return "このレンズに対応する倍率は未確認です。"
        default:
            if value.hasPrefix("lens_") || value.hasPrefix("zoom_") || value.hasPrefix("stabilization_") {
                return "現在の記録形式と補正を維持する操作を確認できません。撮影条件を確認してください。"
            }
            return value
        }
    }
}
