---
name: glossary-creation
description: 5つの先行する永続文書からdocs/glossary.mdを作成・更新し、ドメイン・技術・状態・運用用語の定義と表記を統一する場合に明示的に使用する。新しい要件、用語体系、実装上の名前を独自に決定するためには使用しない。
---

# Glossary Creation

## 入力と出力

- 推奨入力: `docs/product-requirements.md`、`docs/functional-design.md`、`docs/architecture.md`、`docs/repository-structure.md`、`docs/development-guidelines.md`
- 出力: `docs/glossary.md`

先行文書の用語が矛盾する場合は独自に統一せず、候補と影響を返す。

## 手順

1. 先行文書から繰り返し使われるドメイン、画面、状態、データ、技術、運用用語を抽出する。
2. 新規作成時だけ [assets/template.md](assets/template.md) を使う。更新時は既存用語集の確定済み定義を優先する。
3. 分類と記述基準が必要な場合は [references/guide.md](references/guide.md) を読む。
4. 各用語に定義、本プロジェクトでの使用、関連用語、必要なら英語表記と参照先を記載する。
5. 同義語、表記揺れ、廃止語を明示し、実装や先行文書に存在しない概念を追加しない。

## 完了条件

- `docs/glossary.md` だけを作成・更新する。
- 重要用語が先行文書と一致し、循環定義や重複定義がない。
- 変更内容、根拠文書、表記揺れ、残課題を日本語で簡潔に返す。
