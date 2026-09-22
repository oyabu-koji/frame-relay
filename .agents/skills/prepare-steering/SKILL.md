---
name: prepare-steering
description: docs/ideas配下の確定した日付付き機能仕様から.steeringのrequirements.md、design.md、tasklist.mdだけを準備する。実装前の調査と作業計画が必要な場合に明示的に使用する。initial-requirements、文書だけのレビュー、コード実装には使用しない。
---

# Prepare Steering

指定仕様を正本として、実装へ渡せるタスク計画を作成し、設計完了で停止する。

## 入力契約と停止条件

- `docs/ideas/YYYYMMDD-[feature-name].md`を1件、明示入力として受け取る。
- 引数なし、ファイル不存在、`docs/ideas/`外、Markdown以外、`docs/ideas/initial-requirements.md`の場合は変更せず停止する。
- 入力仕様の内容がユーザーと合意済みであることを確認する。`Status: confirmed`を確認し、Statusのない既存仕様では会話上の合意を根拠にしてよい。`draft`または合意不明なら計画を開始せず、`$define-requirements`での確定を案内する。仕様をこのWorkflowで確定・更新しない。
- `docs/product-requirements.md`、`docs/functional-design.md`、`docs/architecture.md`、`docs/repository-structure.md`、`docs/development-guidelines.md`、`docs/glossary.md`のいずれかが不足する場合は停止し、`$setup-project`を案内する。
- 仕様が計画に必要な判断を欠く場合は推測で埋めず、main agentがユーザーへ確認する。要件の再具体化が必要なら`$define-requirements`を案内し、暗黙には開始しない。

## 実行手順

1. main agentが入力仕様、計画範囲、出力先、完了条件を確定する。
2. 組み込み`explorer`へ、入力仕様、6つの永続文書、関連コードの読み取り調査を委任する。調査対象と問いを限定し、結論、根拠ファイル、設計上の制約、残課題だけを返させる。
3. 仕様ファイル名から`.steering/[YYYYMMDD]-[feature-name]/`を決める。既存ディレクトリがある場合は、更新対象と保持すべき内容を確認する。
4. custom agent `feature_planner`へ対象`.steering/`だけの所有権を明示して委任する。同じコードベースに他の作業者がいること、他者の変更を戻さないことを伝え、`$steering`を明示使用させる。
5. `requirements.md`へ目的、ユースケース、ユーザーフロー、機能要件、非機能要件、受け入れ条件、スコープ外を書く。
6. `design.md`へ関連コードの現状、SwiftUI View、状態の所有・共有、モデル、サービス、非同期処理、エラー処理、テスト戦略、制約を書く。アプリの変更では既存targetへの所属やproject設定への影響も確認する。対象に応じて不要な節を無理に作らず、特定の設計パターンを強制しない。
7. `tasklist.md`へ依存順の小さなタスク、状態、所有範囲、検証方法を定義する。進捗の正本として扱える形にする。
8. `feature_planner`から結論、変更ファイル、根拠、残課題の要約を受け取り、main agentが仕様との対応、最終diff、所有範囲外の変更を確認する。

## 完了条件

- 対象`.steering/`に`requirements.md`、`design.md`、`tasklist.md`だけが計画成果物として作成・更新されている。
- 3文書が相互整合し、`$implement-steering`へ渡せる。作成したsteeringパスを次の明示入力として案内する。
- アプリコード、入力仕様、永続文書を変更していない。
- 実装や実装検証を開始せず、計画作成で終了する。
