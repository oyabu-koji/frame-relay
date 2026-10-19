---
name: steering
description: docs/ideasの日付付き仕様から作成された.steering/[YYYYMMDD]-[task]/のrequirements.md、design.md、tasklist.mdを計画・実装・検証の間で維持する場合に明示的に使用する。initial-requirementsからの直接計画、仕様正本の代替、実装検証中の進捗改変には使用しない。
---

# Steering

## 役割

- `.steering/[YYYYMMDD]-[task]/` を実装単位の要求、設計、進捗、検証証跡の正本にする
- `docs/ideas/` の仕様を複製せず、今回の実装範囲と判断へ変換する
- `$prepare-steering`、`$implement-steering`、`$validate-implementation` の受け渡しを保つ
- `$steering`は内部で明示使用する専門Skillであり、ユーザー向けの計画・実装Workflowとは別に維持する

## 入力契約

- `$prepare-steering`: `docs/ideas/YYYYMMDD-[feature-name].md`
- `$implement-steering` / `$validate-implementation`: `.steering/[YYYYMMDD]-[task]/`
- `docs/ideas/initial-requirements.md` から直接steeringを作らない

## 成果物

- `requirements.md`: 目的、要件、受け入れ条件、スコープ外
- `design.md`: 現状、設計、依存関係、エラー、テスト、実装順
- `tasklist.md`: 小さなtask、状態、所有範囲、検証証跡、振り返り

新規作成時は [assets/requirements.md](assets/requirements.md)、[assets/design.md](assets/design.md)、[assets/tasklist.md](assets/tasklist.md) を土台にし、対象に不要な節は削る。

## 状態と更新規則

- `pending`: 未着手
- `in-progress`: 所有者と対象を確定して実行中
- `done`: 受け入れ条件と検証証跡を満たす
- `blocked`: 外部判断または技術的障害を理由付きで記録
- `cancelled`: 方針変更により不要になった理由を記録

書き込みtaskは原則1件ずつ `in-progress` にし、完了またはblockedを記録してから依存taskへ進む。設計判断が変わった場合だけrequirements/designも更新する。

## Validationへの引き継ぎ

- 利用可能なビルド・診断確認、test、合意済みcoverage、Simulator・実機での起動確認の結果をtasklistへ残す。実行コマンド、project/workspace、scheme、destination、テスト対象、証跡の場所を記録する
- 未実行項目は理由と未確認範囲を記録する
- validation中はsteeringを変更せず、findingをmain agentへ返す

## 完了条件

- 3文書が相互整合し、元仕様と実装へ追跡できる。
- task状態と実際のdiffが一致する。
- 同じsteeringパスを次工程へ明示入力できる。
