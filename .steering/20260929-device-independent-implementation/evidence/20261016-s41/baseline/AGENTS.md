# Codex Project Guidance

## 最初に読むもの

- プロジェクトの目的・技術前提は `PROJECT_CONTEXT.md` を正本とする
- 変更仕様は `docs/ideas/`、安定したプロダクト・設計文書は `docs/` を正本とする
- 実装前に対象 `.steering/[YYYYMMDD]-[task]/` の `requirements.md`、`design.md`、`tasklist.md` を読む
- 実装中は `.steering/` を進捗の正本とし、完了したtaskを都度更新する

## Workflow routing

書き込みまたは高コストな処理を伴う次のWorkflow Skillは、ユーザーが `$skill-name` を明示した場合だけ開始する。

- `$init-project`: 人間が作成したXcodeプロジェクトを確認し、最小開発基盤を整える
- `$define-requirements`: 初期要件または追加・変更要件を対話で詰め、合意後に仕様へ保存する
- `$setup-project`: validな初期要件から6つの永続文書を作る
- `$prepare-steering`: 確定したfeature specから `.steering/` の要求・設計・tasklistを準備する
- `$implement-steering`: 指定された `.steering/` に従って実装し、進捗と検証証跡を同期する
- `$validate-implementation`: 実装済みの変更を専門agentで検証する

同等の自然文依頼だけを受けた場合は、書き込みや高コストな処理を開始せず、対応する `$skill-name` の明示を求める。

`$review-docs` は読み取り専用レビューのため、明示呼び出しと「この文書をレビューして」のような自然文の両方を受け付ける。

初期開発は `$init-project` → `$define-requirements` → `$setup-project`、初期セットアップ後の機能開発は `$define-requirements` → `$prepare-steering` → `$implement-steering` → `$validate-implementation` の順に進める。矢印は次工程の案内であり、別Workflowを暗黙に開始する許可ではない。`$review-docs` は必要時に独立して使用する。

初期要件がvalidでも永続6文書が不足している場合、`$define-requirements`は追加仕様へ進まず`$setup-project`を案内する。専門Skillsはすべて明示呼び出し専用であり、内部の `$steering` とユーザー向けの `$prepare-steering` / `$implement-steering` を区別する。

## Agent delegation

- main agentはユーザー対話、判断、分割、結果統合、差分確認、完了判定を担当する
- 境界の明確な調査は `explorer`、実装は所有範囲を指定した `worker` に委任できる
- 仕様・永続文書の作成は `document_author`、steering計画の作成は `feature_planner` に委任する
- `docs/` 配下の文書レビューでは必ず `doc_reviewer` を使用する
- 実装検証では必ず `implementation_validator` を使用する
- ドキュメントレビューと実装検証の両方が必要なら、両agentを使用してmain agentが結果を統合する
- 書き込みagentには所有ファイルまたは所有ディレクトリを明示し、同じファイルを複数agentへ同時に割り当てない
- subagentには目的、入力パス、制約、出力形式、完了条件だけを渡し、他者の変更を戻さないよう指示する
- subagentは結論、根拠、変更概要、検証結果、残課題を日本語で簡潔に返す
- main agentは報告だけで完了とせず、最終diffと所有範囲外の変更がないことを確認する

## Engineering constraints

- Swift + SwiftUI + native iOS + Xcodeを使用する
- `PROJECT_CONTEXT.md` の確定済みXcode・Swift設定・最低対応iOSを明示依頼なしに変更しない
- 初期iOS Appは人間がXcodeで作成する。Codexによる独自のproject/workspace生成やproject generator導入は行わない
- 外部依存・外部ツールは標準導入せず、必要性と導入範囲を合意してから追加する
- build/testは実在するproject/workspace、scheme、destination、テスト構成を確認してから実行する
- 固定カバレッジ閾値は `docs/development-guidelines.md` で合意済みの場合だけ適用する

## Document and task rules

- `docs/ideas/initial-requirements.md` は `$setup-project` のbootstrap入力にだけ使用する
- `docs/ideas/YYYYMMDD-[feature-name].md` は `$prepare-steering` の標準入力とする
- 仕様は `docs/ideas/`、決定記録は `docs/decisions/`、短期計画は `.steering/` に置く
- 安定した要件・設計・用語・開発規則が変わった場合は、関連する `docs/` を更新する
- reviewとvalidationでは対象ファイルを変更しない

## Completion

- 変更範囲に応じたビルド・診断確認、test、Simulator・実機での起動確認を実行する
- 実行できない検証は、理由と未確認範囲を報告する
- `.steering/` を使う実装ではtasklistと検証証跡を最新にする
