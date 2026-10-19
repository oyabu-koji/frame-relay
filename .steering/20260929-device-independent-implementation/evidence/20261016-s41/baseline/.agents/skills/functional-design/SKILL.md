---
name: functional-design
description: docs/product-requirements.mdからdocs/functional-design.mdを作成・更新する。PRDの要件を画面・ユースケース・状態・データ契約・エラー処理・テスト観点へ落とし込む場合に明示的に使用する。技術基盤の選定、リポジトリ配置、コード実装には使用しない。
---

# Functional Design

## 入力と出力

- 必須入力: `docs/product-requirements.md`
- 出力: `docs/functional-design.md`
- 補助入力: `PROJECT_CONTEXT.md` と既存の関連文書

PRDが存在しない、または対象要件と受け入れ条件が不足している場合は作成を開始せず、不足内容を返す。

## 手順

1. PRDのP0要件、対象外、用語、受け入れ条件を抽出する。
2. 新規作成時だけ [assets/template.md](assets/template.md) を使う。更新時は既存文書の確定済み構造を維持する。
3. 記述粒度や確認観点が必要なときは [references/guide.md](references/guide.md) を読む。
4. 画面・利用者フロー、状態遷移、データ契約、コンポーネント責務、外部インターフェース、異常系、テスト観点を定義する。
5. データ契約はSwiftの型例または表で表現し、View、状態の所有・更新、端末API、純粋ロジックの境界を示す。具体的な状態管理方式の選定はアーキテクチャ設計へ残す。
6. 各P0要件が設計要素とテスト観点へ追跡できることを確認する。

## 完了条件

- 機能設計書だけを作成・更新し、アーキテクチャ選定や実装へ進まない。
- 正常系、異常系、入力制御、空・待機・失敗状態を確認する。
- 変更ファイル、要件との対応、検証、残課題を日本語で簡潔に返す。
