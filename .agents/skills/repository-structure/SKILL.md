---
name: repository-structure
description: docs/architecture.mdまでの永続文書からdocs/repository-structure.mdを作成・更新する。アーキテクチャ境界を具体的なディレクトリ、ファイル命名、依存方向、テスト配置へ変換する場合に明示的に使用する。実際のディレクトリ作成、コード移動、実装には使用しない。
---

# Repository Structure

## 入力と出力

- 必須入力: `docs/product-requirements.md`、`docs/functional-design.md`、`docs/architecture.md`
- 補助入力: 現在のリポジトリツリーと `PROJECT_CONTEXT.md`
- 出力: `docs/repository-structure.md`

アーキテクチャ境界が未定義、または文書間で矛盾している場合は配置を確定せず、矛盾を返す。

## 手順

1. 既存ツリー、エントリーポイント、設定ファイル、アーキテクチャ境界を確認する。
2. 新規作成時だけ [assets/template.md](assets/template.md) を使う。更新時は実在する構造と既存判断を優先する。
3. 配置・依存ルールの詳細が必要なときは [references/guide.md](references/guide.md) を読む。
4. ルート構造、機能単位の配置、共有領域、asset、test、docs、AIワークフロー領域を定義する。
5. 各ディレクトリの責務、配置対象、命名規則、許可・禁止する依存を記述する。
6. 存在しないファイルを現状として記載せず、目標構造と現状を区別する。

## 完了条件

- 構造定義書だけを作成・更新し、ファイル移動やコード実装へ進まない。
- Swiftの`.swift`、Xcodeのプロジェクト・ターゲット構成、アーキテクチャ境界と整合している。未作成の構成は将来の例として区別している。
- 変更ファイル、根拠、現状との差分、検証、残課題を日本語で簡潔に返す。
