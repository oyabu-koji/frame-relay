---
name: prd-writing
description: validなdocs/ideas/initial-requirements.mdからdocs/product-requirements.mdを作成・更新する。新規プロジェクトのPRDを定義し、ユーザー、課題、価値、スコープ、優先度、受け入れ条件、成功指標を合意可能な形にする場合に明示的に使用する。機能設計、アーキテクチャ設計、追加機能だけの仕様化には使用しない。
---

# PRD Writing

## 入力と出力

- 入力: `docs/ideas/initial-requirements.md`
- 出力: `docs/product-requirements.md`
- 前提: 初期要件の必須項目が具体的に記入され、`valid` と判定されていること

入力が存在しない、必須項目が空、またはプレースホルダーのままなら作成を開始せず、不足項目を返す。

## 手順

1. `PROJECT_CONTEXT.md`、初期要件、既存PRDがあればその順に読む。
2. 新規作成時だけ [assets/template.md](assets/template.md) を出力の土台にする。更新時は既存PRDの構造と確定済み判断を優先する。
3. 詳細な記述基準が必要なときは [references/guide.md](references/guide.md) を読む。
4. ユーザー、解決する課題、提供価値、目標、MVP、対象外、機能要件、非機能要件、優先度、受け入れ条件、成功指標を初期要件から具体化する。
5. 初期要件にない製品判断、数値、期限を推測で確定しない。不明点は未決事項として分離する。
6. 各P0要件が検証可能な受け入れ条件へ対応していることを確認する。

## 完了条件

- PRDだけを作成・更新し、機能設計や実装へ進まない。
- 初期要件との対応、測定可能性、スコープ境界、未決事項を確認する。
- 変更ファイル、判断根拠、残課題を日本語で簡潔に返す。
