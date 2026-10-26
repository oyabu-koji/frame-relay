import AVKit
import SwiftUI

struct OriginalPlaybackView: View {
    @Bindable var model: OriginalPlaybackModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let player = model.playback.player {
                    VideoPlayer(player: player)
                        .frame(minHeight: 240)
                        .accessibilityLabel("iPhone原本の動画プレーヤー")
                        .accessibilityIdentifier("originalPlayback.player")
                        .onAppear { model.playback.recordPresentation(.videoViewAppeared) }
                        .onDisappear { model.playback.recordPresentation(.videoViewDisappeared) }
                }
                Text(status).accessibilityIdentifier("originalPlayback.status")
                Text("再生位置：\(model.playback.elapsedSeconds, format: .number.precision(.fractionLength(1)))秒")
                    .accessibilityLabel("再生位置")
                    .accessibilityValue(Text("\(model.playback.elapsedSeconds, format: .number.precision(.fractionLength(1)))秒"))
                    .accessibilityIdentifier("originalPlayback.elapsed")
                if let issue = model.playback.issue { Text(issue) }
                Text("原本の再生では軽量版の明示確認や写真への保存は行いません。")
                    .font(.footnote)
            }
            .padding()
            }
            .navigationTitle("原本の再生")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if model.playback.isBusy {
                        Button {
                            Task { await model.stop() }
                        } label: {
                            Text("再生を停止")
                                .font(.body)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(model.playback.phase == .stopping)
                        .accessibilityIdentifier("originalPlayback.stop")
                    }
                    Button {
                        Task {
                            await model.close()
                            if model.target == nil { dismiss() }
                        }
                    } label: {
                        Text("閉じる")
                            .font(.body)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .accessibilityIdentifier("originalPlayback.close")
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
            }
        }
        .interactiveDismissDisabled()
        .onAppear { model.playback.recordPresentation(.viewAppeared) }
        .onDisappear {
            model.playback.recordPresentation(.viewDisappeared)
            Task { await model.close() }
        }
    }

    private var status: String {
        switch model.playback.phase {
        case .idle: "再生を準備しています"
        case .preparing: "原本を読み込み中"
        case .playing: "原本を再生中"
        case .paused: "原本の再生を一時停止中"
        case .stopping: "再生を停止し、原本の読み取り終了を確認しています"
        case .ended: "再生が終了しました"
        case .stopped: "再生を停止しました"
        case .failed: "原本を再生できませんでした"
        case .releaseNeedsReconciliation: "読み取り終了の照合が必要です"
        }
    }
}
