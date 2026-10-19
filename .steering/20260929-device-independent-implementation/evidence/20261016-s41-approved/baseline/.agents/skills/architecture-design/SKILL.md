---
name: architecture-design
description: docs/product-requirements.mdとdocs/functional-design.mdからdocs/architecture.mdを作成・更新する。Swift・SwiftUI・native iOS・Xcodeの技術選定、責務境界、データ管理、品質特性、依存方針を定義する場合に明示的に使用する。機能要件の追加、リポジトリ配置、コード実装には使用しない。
---

# Architecture Design

## 入力と出力

- 必須入力: `docs/product-requirements.md`、`docs/functional-design.md`
- 補助入力: `PROJECT_CONTEXT.md`
- 出力: `docs/architecture.md`

必須文書がない、または機能境界が未定義なら設計を開始せず、不足内容を返す。

## 手順

1. 技術前提、P0要件、機能責務、非機能要件を抽出する。
2. 新規作成時だけ [assets/template.md](assets/template.md) を使う。更新時は既存の決定と理由を維持する。
3. 詳細な設計観点が必要なときは [references/guide.md](references/guide.md) を読む。
4. アーキテクチャ方針、レイヤー・モジュール境界、依存方向、データ管理、端末機能、エラー、セキュリティ、性能、テスト戦略を定義する。
5. 技術選定には要件との対応、選定理由、代替案、制約を記載する。
6. `PROJECT_CONTEXT.md`で合意したXcode、Swift言語モード、最低対応iOS、対象端末を明示依頼なしに変更しない。未決の値を補完せず、APIの利用可能条件と依存の必要性を示す。

## 完了条件

- アーキテクチャ文書だけを作成・更新し、依存追加や実装へ進まない。
- 各境界の責務、許可する依存、禁止する依存が説明されている。
- 変更ファイル、主要判断と根拠、検証、残課題を日本語で簡潔に返す。
