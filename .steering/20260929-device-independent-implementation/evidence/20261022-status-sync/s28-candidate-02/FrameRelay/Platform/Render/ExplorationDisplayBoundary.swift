/// D02 has no accepted standard transform yet. Recording-only exploration is an
/// explicit comparison condition; it is not a product decision to omit preview.
nonisolated enum ExplorationDisplayBoundary {
    static func issue(for condition: ExplorationDisplayCondition) -> ExplorationIssue? {
        switch condition {
        case .recordingOnly: return nil
        case .standardRec709AlongsideRecording: return .rec709TransformUnverified
        }
    }

    static func status(for condition: ExplorationDisplayCondition?) -> String {
        switch condition {
        case .recordingOnly: return "記録単独の比較条件。Rec.709表示の成立・品質は未評価。"
        case .standardRec709AlongsideRecording: return "固定Rec.709表示は未実装・未確認。Log 1/2の変換を同一扱いしません。"
        case nil: return "表示条件は未選択。固定Rec.709変換は未実装・未確認。"
        }
    }
}
