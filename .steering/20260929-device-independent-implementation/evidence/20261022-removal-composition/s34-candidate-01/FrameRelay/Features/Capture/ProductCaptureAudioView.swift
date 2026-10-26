import SwiftUI

struct ProductCaptureAudioView: View {
    let state: CaptureAudioState?
    let recovery: ProductCaptureAudioRecoveryStatus
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("音声").font(.headline)
            if let level = state?.level.value {
                ProgressView(value: min(level.linearAmplitude, 1))
                    .accessibilityLabel("音量")
                    .accessibilityValue("\(Int(min(level.linearAmplitude, 1) * 100))パーセント")
                    .accessibilityIdentifier("capture.audio.level")
                if level.isClipping {
                    Label("音量が上限に達しています", systemImage: "waveform.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("capture.audio.peak")
                }
            } else {
                Text("音量は未観測です").accessibilityIdentifier("capture.audio.levelUnknown")
            }
            if let failure = state?.confirmedFailure {
                Label(failureText(failure), systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("capture.audio.failure")
            } else {
                Text(inputText).accessibilityIdentifier("capture.audio.input")
            }
            Text(arrivalText).font(.footnote).accessibilityIdentifier("capture.audio.arrival")
            Text(writingText).font(.footnote).accessibilityIdentifier("capture.audio.writing")
            Text(recoveryText).font(.footnote).accessibilityIdentifier("capture.audio.recovery")
            Button("音声を再試行", systemImage: "arrow.clockwise", action: retry)
                .disabled(!canRetry)
                .accessibilityIdentifier("capture.audio.retry")
        }
    }

    private var inputText: String {
        switch state?.input {
        case .valid(let route): return "入力有効：\(route)"
        case .recovering: return "音声入力を再確認しています"
        default: return "音声入力を確認中です"
        }
    }

    private func failureText(_ failure: CaptureAudioFailure) -> String {
        switch failure {
        case .permissionDenied: return "マイクを使用できません。設定アプリでマイクの許可を確認してください。"
        case .confirmedNoSamples: return "音声データが届いていません。録画を開始・継続できません。"
        case .routeInterrupted: return "音声入力が途切れました。接続と入力を確認してください。"
        case .writerFailed: return "音声を書き込めませんでした。録画は停止し、保存結果を確認します。"
        }
    }

    private var arrivalText: String {
        if case .received = state?.arrival { return "音声データの到着を確認" }
        return "音声データ到着：未確認"
    }

    private var writingText: String {
        switch state?.writing {
        case .notStarted, nil: return "音声書き込み：開始前"
        case .accepted: return "音声書き込み：受理を確認・保存結果は未確定"
        case .completed: return "音声書き込み：終了を確認・保存結果は別に確認します"
        case .failed: return "音声書き込み：失敗"
        case .unavailable: return "音声書き込み：記録方式から個別の結果は取得できません。保存後に音声を検査します。"
        }
    }

    private var recoveryText: String {
        switch recovery {
        case .attempting(let attempt): return "音声の再試行 \(attempt) 回目・入力到着を確認しています"
        case .timedOutWaitingForRelease: return "音声の再試行が時間切れです。処理の終了を待っています。"
        case .readyForUserREC: return "音声が復旧しました。RECを押すと次の録画を開始します。"
        case .failed: return "音声を復旧できませんでした。直近の保存結果を確認し、撮影画面を開き直してください。"
        case .idle:
            if state?.confirmedFailure != nil, !canRetry {
                return "直近の保存結果と入力の状態を確認し、撮影画面を開き直してください。"
            }
            return "音量が小さいことだけでは入力障害と判断しません。保存結果は録画終了後に確認します。"
        }
    }
}
