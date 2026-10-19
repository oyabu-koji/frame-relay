# Swift iOS AI Development Template

## 1. このテンプレートについて

Swift / SwiftUIによるネイティブiOSアプリを、Codexと段階的に開発するためのAI開発環境です。要件整理、設計文書、実装計画、実装、独立検証を別々の工程として進めます。

このリポジトリ自体はiOSアプリではありません。アプリ固有の要件やコード、Xcodeプロジェクトは含まず、実際のiOSアプリのリポジトリで使うためのテンプレートです。Xcodeプロジェクトの生成機能もありません。

## 2. 技術前提

| 項目 | 前提 |
| --- | --- |
| 言語 | Swift |
| UI | SwiftUI |
| プラットフォーム | ネイティブiOS |
| 開発・ビルド | Xcode |

Xcodeのバージョン、Swiftコンパイラ・言語モード、最低対応iOS、対象端末は、このテンプレートでは固定していません。実際のアプリで確定し、[PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)へ記録します。技術上の制約も同ファイルを正本とします。

## 3. 最初にどう使うか

新しいアプリを始めるときは、次の順に進めます。

1. このテンプレートのAI開発環境を、開発対象のアプリリポジトリに用意する。
2. 人間がXcodeで「iOS App / SwiftUI / Swift」を選び、そのリポジトリにプロジェクトを作成する。
3. Codexで`$init-project`を実行し、既存プロジェクトと最小開発基盤を確認する。プロジェクトがなければ作成を案内して停止する。
4. `$define-requirements`で初期アプリ要件を対話で具体化し、`docs/ideas/initial-requirements.md`に保存する。
5. 初期要件が十分に固まったら、`$setup-project`で6つの永続文書を作成・レビューする。
6. 以降は、機能ごとに要件定義から独立検証までのWorkflowを進める。

## 4. 基本Workflow

| Workflow | いつ使うか・何をするか・工程の境界 |
| --- | --- |
| `$init-project` | 人間がXcodeプロジェクトを作成した後に使う。構成と開発基盤を確認し、なければ作成を案内して停止する。プロジェクトは生成しない。 |
| `$define-requirements` | 初回要件または既存アプリへの変更を相談するときに使う。必要な質問を重ね、合意した要件を`docs/ideas/`へ保存する。設計や次工程は開始しない。 |
| `$setup-project` | 初回の有効な初期要件ができた後に使う。6つの永続文書を作成・レビューする。追加機能ごとの計画やコード実装はしない。 |
| `$prepare-steering` | 追加仕様が確定した後に使う。実装用の`requirements.md`、`design.md`、`tasklist.md`を準備する。実装は開始しない。 |
| `$implement-steering` | 対象steeringを指定して使う。計画に従い実装、必要なテスト、利用可能な検証、task進捗と証跡の更新を行う。独立した最終検証は代行しない。 |
| `$validate-implementation` | 実装後に指定steeringとの整合を確認するときに使う。専門agentが読み取り専用で独立検証し、コードやtasklistを修正しない。 |
| `$review-docs` | 文書の品質を確認したいときに使う。`docs/`配下のMarkdownを読み取り専用でレビューする。文書修正や実装検証はしない。 |

詳しい入力条件と停止条件は、それぞれの`.agents/skills/<workflow>/SKILL.md`を参照してください。

## 5. 新規プロジェクトの流れ

```text
$init-project
    ↓
$define-requirements
    ↓
$setup-project
    ↓
通常の機能開発へ
```

初期要件が有効でも永続6文書がまだ揃っていなければ、追加仕様の作成には進まず、`$setup-project`へ進みます。

## 6. 通常の機能追加の流れ

```text
$define-requirements
    ↓
$prepare-steering
    ↓
$implement-steering
    ↓
$validate-implementation
```

矢印は次に使うWorkflowを示します。各工程はそこで停止し、次の工程はユーザーが明示して開始します。`$review-docs`は必要なときに独立して利用できます。

## 7. 生成・管理される主な文書

| 保存先 | 役割 |
| --- | --- |
| `docs/ideas/` | 初期要件`initial-requirements.md`と、日付付きの追加・変更仕様`YYYYMMDD-[feature-name].md` |
| `docs/` | 安定したプロダクト・設計・開発規則の永続文書 |
| `.steering/[YYYYMMDD]-[task]/` | 実装単位の要求、設計、task進捗、検証証跡の正本 |

`$setup-project`が初期要件から作成する永続文書は次の6つです。

- `docs/product-requirements.md`
- `docs/functional-design.md`
- `docs/architecture.md`
- `docs/repository-structure.md`
- `docs/development-guidelines.md`
- `docs/glossary.md`

各steeringでは`requirements.md`、`design.md`、`tasklist.md`を使います。これらの文書は対象アプリで工程を進めたときに作成されます。

## 8. Workflowの呼び出し方

`$init-project`、`$define-requirements`、`$setup-project`、`$prepare-steering`、`$implement-steering`、`$validate-implementation`は、名前を付けて明示的に呼び出します。`$review-docs`だけは、自然文のレビュー依頼でも呼び出せます。

```text
$define-requirements 家族で動画メモを使うアプリの初期要件を詰めたい
$prepare-steering docs/ideas/20260922-video-library.md
$implement-steering .steering/20260922-video-library/
$review-docs docs/architecture.md
```

パス付きの例は、対象の仕様・steering・文書が実在する状態で、そのパスに置き換えて使ってください。`$define-requirements`は対話の結果から保存先を決めます。

## 9. 内部構成

- `.agents/skills/`：ユーザー向けWorkflowと、工程内で使う専門Skill。概要は[.agents/README.md](.agents/README.md)を参照。
- `.codex/agents/`：文書作成、計画、文書レビュー、実装検証を担当する専門subagent。
- [AGENTS.md](AGENTS.md)：Codexが従うWorkflowの呼び出し・委任・実行ルール。
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)：目的と技術前提の正本。

## 10. 開発上の考え方

まずユーザーと「何を実現するか」を決め、確定した仕様から計画を作り、計画に沿って実装します。実装結果は別の専門agentが独立して検証します。main agentはユーザー対話、判断、進捗と差分の確認を担い、専門agentには所有範囲を明確にして作業を渡します。実装中の進捗と検証証跡は対象の`.steering/`を正本として管理します。
