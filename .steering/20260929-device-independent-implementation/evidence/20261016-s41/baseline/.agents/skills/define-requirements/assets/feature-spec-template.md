# Feature Spec Template

このテンプレートは、追加機能の仕様を `docs/ideas/YYYYMMDD-[feature-name].md` として作成するときに使います。

## 役割

- `define-requirements` が対話と合意後に追加仕様を新規作成するときのベースにする
- `docs/ideas/` に置く追加仕様の正本にする
- `prepare-steering` の入力にする
- 安定した仕様になった後、`docs/` 更新要否を判断する材料にする

## 使わないケース

- `docs/ideas/initial-requirements.md` には使わない
- `.steering/` の計画書や進捗メモには使わない

## 命名規則

- 形式: `YYYYMMDD-[feature-name].md`
- 例: `20260407-login-refresh.md`
- `YYYYMMDD` は仕様を作成または大きく更新した日付
- `[feature-name]` は英小文字のケバブケースを使う
- 既存仕様の更新では指定パスを保持し、日付変更だけで改名しない

---

# Feature Spec

## Metadata

- Date: YYYY-MM-DD
- Feature name:
- Status: draft | confirmed（確定内容へのユーザー合意後にconfirmed）
- Related files:

## Background

- なぜこの仕様が必要か
- どの課題を解決するか

## Target Users / Use Cases

- 誰が使うか
- どの場面で使うか

## Scope

- 今回含めること

## Out of Scope

- 今回含めないこと

## User Flow

- ユーザー操作の流れ

## Functional Requirements

- 要件1
- 要件2

## Behavior / Exceptions

- UI / UX上の期待とユーザーに見える状態遷移
- 関係するデータ、権限、外部I/Oの期待する振る舞い
- 重要な例外・エラー時の表示、回復方法
- 既存機能との関係、意図した仕様変更とその影響

今回に関係する論点だけを具体化し、該当しない論点は省く。

## Non-Functional / Technical Notes

- Swift / SwiftUI / native iOS 前提の制約。Xcode、Swift言語モード、最低対応iOS、対象端末は `PROJECT_CONTEXT.md` の合意内容を参照する
- 必要なプラットフォーム機能の利用可能条件。実現可能性の調査結果と未確認事項を示し、具体APIや内部実装方式の新規選定は設計工程へ残す
- 端末機能、パフォーマンス、オフライン、権限など

## Acceptance Criteria

- 条件・操作・観測可能な結果で記載し、主要挙動と重要な例外から完成を判断できること
- 条件1
- 条件2

## Open Questions

- 設計やスコープを大きく左右する事項は確定前に解消する。残す軽微な事項は影響と後で判断できる理由を記載し、なければ「なし」とする
- 未決事項1
- 未決事項2

## Durable Docs Impact

- 更新候補:
- 更新要否:
- 理由:
