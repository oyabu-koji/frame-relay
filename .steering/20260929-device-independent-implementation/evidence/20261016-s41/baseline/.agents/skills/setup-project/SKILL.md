---
name: setup-project
description: validなdocs/ideas/initial-requirements.mdから6つの永続プロジェクト文書を依存順に初期作成する。新規プロジェクトの要件・設計文書をbootstrapする場合に明示的に使用する。追加機能の計画、コード実装、未入力要件からの文書生成には使用しない。
---

# Setup Project

初期要件を検証し、専門Skillとcustom agentを順番に使って6つの永続文書を作成する。

## 入力と事前確認

1. 入力を`docs/ideas/initial-requirements.md`に固定する。日付付き追加仕様を入力にしない。
2. [initial-requirements-validation.md](../define-requirements/references/initial-requirements-validation.md)を読み、必須6領域を同じ定義で判定する。
3. `missing`または`blank`なら永続文書を一切生成せず、領域ごとの不足を列挙して停止し、`$define-requirements`を案内する。
4. `valid`でも、永続文書の内容を大きく変える`Open Questions`があればmain agentがユーザーへ確認する。
5. 既存の永続文書がある場合は、初期作成か更新か、所有対象をユーザーと確定してから進む。暗黙に上書きしない。

## 作成順序

以下の順序を守り、各`document_author`へ出力1ファイルと必要な先行文書だけを渡す。新しいagentインスタンスを文書ごとに使ってよい。委任時は所有ファイルを明示し、同じコードベースに他の作業者がいること、他者の変更を戻さないことを伝える。

1. `document_author`に`$prd-writing`を明示使用させ、`docs/product-requirements.md`を作成する。
2. `doc_reviewer`にPRDだけをレビューさせる。main agentが重大度順に結果を統合し、ユーザーの承認を得る。承認までは次へ進まない。
3. `document_author`に`$functional-design`を明示使用させ、`docs/functional-design.md`を作成する。
4. `document_author`に`$architecture-design`を明示使用させ、`docs/architecture.md`を作成する。
5. `document_author`に`$repository-structure`を明示使用させ、`docs/repository-structure.md`を作成する。
6. `document_author`に`$development-guidelines`を明示使用させ、`docs/development-guidelines.md`を作成する。
7. `document_author`に`$glossary-creation`を明示使用させ、`docs/glossary.md`を作成する。
8. `doc_reviewer`に6文書すべての完全性と相互整合性をレビューさせる。

## main agentの責務

- 入力状態、作成順、ユーザー承認、未決事項を管理する。
- 委任プロンプトを目的、入力パス、出力パス、制約、完了条件に絞る。
- 各agentから結論、根拠、変更概要またはfinding、検証結果、残課題の要約を受け取る。
- 各段階のdiffと所有範囲を確認し、文書間の矛盾を統合する。
- custom agentや必須専門Skillを利用できない場合は、その工程をmain agentだけで代行せず停止する。

## 完了条件

- 6つの永続文書がすべて存在し、初期要件と整合する。
- PRDレビュー、ユーザー承認、6文書の最終レビューが完了している。
- 各委任の所有範囲外に変更がなく、未解決findingが報告されている。
- アプリコードと`.steering/`を変更していない。
