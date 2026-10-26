import AVKit
import SwiftUI
import UIKit

struct RenditionPlaybackView: View {
    @Bindable var model: RenditionPlaybackModel
    @State private var presentedSession: PlaybackSessionID?
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let target = model.target {
                            RenditionPlaybackText(text: target.title, identifier: "renditionPlayback.target")
                        }
                        if let player = model.playback?.player {
                            VideoPlayer(player: player)
                                .frame(minHeight: 240)
                                .accessibilityLabel("端末内の軽量版の動画プレーヤー")
                                .accessibilityIdentifier("renditionPlayback.player")
                        }
                        RenditionPlaybackText(text: status, identifier: "renditionPlayback.status")
                        let elapsed = elapsedValue
                        RenditionPlaybackText(text: "再生位置：\(elapsed)", identifier: "renditionPlayback.elapsed",
                            accessibilityLabel: "再生位置", accessibilityValue: elapsed)
                        if let token = model.token {
                            RenditionPlaybackText(text: "再生版ID：\(token.distribution.rendition.rendition.rawValue)",
                                identifier: "renditionPlayback.version")
                        }
                        RenditionPlaybackText(text: "完全取得済みの軽量版を端末内から再生します。Wi-FiやMac miniへの接続は不要です。実際に再生した同じ版を、本人の操作で1本ずつ確認できます。再生だけでは確認済みになりません。停止や終了後も、この画面の同じ再生版を確認できます。画面を閉じると、この再生に対する確認操作は終了します。使用を終えた一時媒体は既存の回収条件に従って解放され、次回は取得が必要になる場合があります。iPhone原本とMac mini、写真の動画は削除しません。",
                            style: .footnote, identifier: "renditionPlayback.explanation")
                        if let issue = model.issue { RenditionPlaybackText(text: issue, identifier: "renditionPlayback.issue") }
                        if let message = model.message { RenditionPlaybackText(text: message, identifier: "renditionPlayback.confirmation") }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding()
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("renditionPlayback.content")
                VStack(spacing: 12) {
                    if model.isBusy {
                        Button("再生を停止") { Task { await model.stop() } }
                            .disabled(model.playback?.phase == .stopping)
                            .accessibilityIdentifier("renditionPlayback.stop")
                    }
                    Button(model.confirmationUnknown ? "同じ確認操作を照合" : "この軽量版を確認") {
                        Task { await model.confirm() }
                    }
                    .disabled(!model.canConfirm)
                    .accessibilityIdentifier("renditionPlayback.confirm")
                    Button("閉じる") { Task { await model.close() } }
                        .buttonStyle(.bordered)
                        .disabled(model.isClosing)
                        .accessibilityIdentifier("renditionPlayback.close")
                }
                .buttonStyle(RenditionPlaybackButtonStyle())
                .tint(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(Color(uiColor: .systemBackground))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("軽量版の再生と確認")
            .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
        .interactiveDismissDisabled()
        .onAppear { if presentedSession == nil { presentedSession = model.session } }
        .onDisappear {
            let session = presentedSession
            Task { await model.close(ifSession: session) }
        }
    }

    private var elapsedValue: String {
        (model.playback?.elapsedSeconds ?? 0).formatted(.number.precision(.fractionLength(1)).locale(locale)) + "秒"
    }

    private var status: String {
        if model.isPreparing { return "完全取得済みの軽量版を照合・準備中" }
        switch model.playback?.phase {
        case .playing: return "端末内の軽量版を再生中"
        case .preparing: return "軽量版を読み込み中"
        case .stopping: return "再生を停止し、軽量版の読み取り終了を確認しています"
        case .stopped: return "軽量版の再生を停止しました"
        case .ended: return "軽量版の再生が終了しました"
        case .failed: return "軽量版を再生できませんでした"
        case .releaseNeedsReconciliation: return "軽量版の読み取り終了の照合が必要です"
        default: return model.issue == nil ? "軽量版を準備しています" : "軽量版を開始できませんでした"
        }
    }
}

private struct RenditionPlaybackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            .foregroundStyle(Color.primary).opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct RenditionPlaybackText: UIViewRepresentable {
    let text: String
    var style: UIFont.TextStyle = .body
    let identifier: String
    var accessibilityLabel: String? = nil
    var accessibilityValue: String? = nil
    @Environment(\.sizeCategory) private var sizeCategory

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0; label.lineBreakMode = .byWordWrapping
        label.adjustsFontForContentSizeCategory = true; label.textColor = .label
        label.isAccessibilityElement = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text; label.accessibilityIdentifier = identifier
        label.accessibilityLabel = accessibilityLabel; label.accessibilityValue = accessibilityValue
        label.font = .preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        guard let proposedWidth = proposal.width, proposedWidth.isFinite else { return nil }
        let width = max(0, proposedWidth); label.preferredMaxLayoutWidth = width
        return CGSize(width: width, height: ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }
    private var category: UIContentSizeCategory {
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
