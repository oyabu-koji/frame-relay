import AVKit
import SwiftUI
import UIKit

struct OriginalPlaybackView: View {
    @Bindable var model: OriginalPlaybackModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                        OriginalPlaybackExplanationText(text: "原本の再生では軽量版の明示確認や写真への保存は行いません。")
                            .accessibilityIdentifier("originalPlayback.explanation")
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("originalPlayback.content")
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
                        .tint(Color.primary)
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
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(Color(uiColor: .systemBackground))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("原本の再生")
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

/// Measure the complete semantic footnote at its actual proposed width.
private struct OriginalPlaybackExplanationText: UIViewRepresentable {
    let text: String
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
        label.accessibilityIdentifier = "originalPlayback.explanation"
        label.font = .preferredFont(forTextStyle: .footnote, compatibleWith:
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
