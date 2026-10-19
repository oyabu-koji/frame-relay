# `.agents/` directory

Codexがリポジトリ単位で自動検出する共有Skillsを配置します。

## 構成

```text
.agents/
└── skills/
    └── <skill-name>/
        ├── SKILL.md
        ├── agents/openai.yaml
        ├── references/    # 必要時だけ読む詳細資料
        ├── assets/        # 出力へコピーして使うテンプレート等
        └── scripts/       # 決定的な処理が必要な場合だけ
```

- `SKILL.md` は `name` と、利用条件・非対象範囲を含む `description` を持つ
- `agents/openai.yaml` は表示情報と暗黙呼び出し可否を定義する
- 詳細ガイドは `references/`、出力テンプレートは `assets/` に置く
- custom agentの役割定義は `.agents/` ではなく `.codex/agents/*.toml` に置く

## Workflow Skills

| Workflow | 役割 |
| --- | --- |
| `$init-project` | 人間が作成したXcodeプロジェクトの最小開発基盤を整える |
| `$define-requirements` | 質問と回答で初期要件・追加要件を詰め、合意した仕様をdocs/ideasへ保存する |
| `$setup-project` | validな初期要件から永続6文書を初期作成・レビューする |
| `$prepare-steering` | 確定した追加仕様からrequirements / design / tasklistだけを準備する |
| `$implement-steering` | 指定steeringに従い実装・テスト・進捗更新・検証証跡の記録を行う |
| `$validate-implementation` | implementation_validatorが実装を変更せず独立検証する |
| `$review-docs` | doc_reviewerがdocs配下の指定文書を読み取り専用レビューする |

`$review-docs` だけは自然文による暗黙呼び出しを許可します。それ以外のWorkflow Skillは `$skill-name` で明示的に呼び出します。

新規アプリは `$init-project` → `$define-requirements` → `$setup-project` の順に進めます。初期セットアップ後の機能開発は `$define-requirements` → `$prepare-steering` → `$implement-steering` → `$validate-implementation` です。`$review-docs` は必要なときに独立して使います。各Workflowは次の操作を案内して終了し、別Workflowを自動実行しません。検証で修正が必要になった場合は、同じsteeringを指定して `$implement-steering` に戻ります。

`$define-requirements` は初期要件の不足・初期要件を詰めている段階では `docs/ideas/initial-requirements.md` を扱います。validでも永続6文書が不足する中間状態では `$setup-project` を案内します。validかつ永続6文書が揃った既存アプリへの変更は、`docs/ideas/YYYYMMDD-[feature-name].md` に保存します。重要な質問を原則2〜4問ずつ重ね、検証可能な受け入れ条件と確定内容への合意を得てから保存します。

呼び出し例（仕様・steeringのパスは実在する対象へ置き換えてください）:

```text
$define-requirements 録画した動画を端末内で整理する機能の要件を詰めたい
$prepare-steering docs/ideas/20260922-video-library.md
$implement-steering .steering/20260922-video-library/
$validate-implementation .steering/20260922-video-library/
```

## Specialist Skills

- `$prd-writing`
- `$functional-design`
- `$architecture-design`
- `$repository-structure`
- `$development-guidelines`
- `$glossary-creation`
- `$steering`

専門Skillsはすべて明示呼び出し専用です。`$setup-project` や各担当agentが、文書の依存順と対象作業に応じて名前を明示して使用します。

`$steering` は3文書の構造・進捗・証跡を維持する内部専門Skillです。ユーザー向けの `$prepare-steering` / `$implement-steering` とは別物で、計画作成の `feature_planner` などが明示使用します。

## Agentsとの関係

- `.codex/agents/document_author.toml`: 仕様・永続文書作成
- `.codex/agents/feature_planner.toml`: `.steering/` 計画作成
- `.codex/agents/doc_reviewer.toml`: 読み取り専用の文書レビュー
- `.codex/agents/implementation_validator.toml`: 読み取り専用の実装検証
- 組み込み `explorer`: 読み取り中心の調査
- 組み込み `worker`: 所有範囲を指定した実装

旧 `.agents/commands/`、`.agents/agents/`、`.agents/settings.json` は移行時に削除済みで、最終構成では使用しません。
