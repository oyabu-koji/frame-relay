import SwiftUI

struct ProductCaptureNDView: View {
    let advice: CaptureNDAdvice
    let evidence: CaptureNDEvidence?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NDの参考案内").font(.headline)
            Text(title).accessibilityIdentifier("capture.ndAdvice")
            Text(advice.reasons.map(Self.reason).joined(separator: "\n"))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("capture.ndReason")
            if let evidence {
                Text("入力信号：\(evidence.signal.rawValue)。未校正の暫定基準による参考です。NDの段数・露出の正確な余裕は測定していません。")
                    .font(.footnote)
            }
            Text("物理NDは手動で調整してください。判定中や警告でも録画できます。")
                .font(.footnote)
        }
    }
    private var title: String {
        switch advice.direction {
        case .darker: "濃くする方向（参考）"
        case .lighter: "薄くする方向（参考）"
        case .acceptable: "現在の暫定基準の範囲内（参考）"
        case .difficult: "NDだけでの両立は難しい可能性があります"
        case .pending: "判定を保留しています"
        }
    }
    private nonisolated static func reason(_ reason: CaptureNDReason) -> String {
        switch reason {
        case .evaluating: "現在の入力を確認しています。"
        case .stopped: "解析入力が停止しています。以前の結果は使いません。"
        case .stale: "解析が遅れているため、以前の結果を取り消しました。"
        case .outOfOrder, .contextChanged: "撮影条件が変わったため、新しい結果を待っています。"
        case .policyUnavailable: "参考案内の評価基準はまだ設定されていません。"
        case .unknownSignal: "入力の色特性・画素形式を確認できないため評価できません。"
        case .insufficientSignal: "十分な明暗の情報がありません。黒い物や小さな反射だけでは判断しません。"
        case .saturated: "広い範囲で信号が飽和しており、正確な余裕を評価できません。"
        case .selectIntent: "撮影意図を選ぶと、その意図で評価します。"
        case .selectPeople: "人物の露出対象を選んでください。"
        case .missingPeople: "選択した人物全員の現在の情報を確認できません。"
        case .broadHighlights: "画面の広い明部が、入力信号の暫定基準を上回っています。"
        case .broadShadows: "画面の広い暗部が、入力信号の暫定基準を下回っています。"
        case .selectedPeopleBright: "選択した人物の明部が暫定基準を上回っています。"
        case .selectedPeopleDark: "選択した人物の暗部が暫定基準を下回っています。"
        case .withinReference: "評価できた対象の明暗は暫定基準の範囲内です。画質や適正露出を保証する表示ではありません。"
        case .conflictingPeople: "人物ごとに必要な調整方向が異なります。光・構図・優先対象の変更を検討してください。"
        case .peopleAndBackgroundConflict: "人物と背景で必要な調整が異なります。光・構図・優先対象の変更を検討してください。"
        }
    }
}
