---
name: review-docs
description: docs配下のMarkdown文書を1件、複数件、または既定の6永続文書としてread-onlyレビューする。文書の品質、完全性、整合性、曖昧さを確認する依頼で使用する。コード実装の検証、docs外のファイル、文書修正そのものには使用しない。
---

# Review Docs

入力対象を確定し、必ずcustom agent `doc_reviewer`へ文書レビューを委任する。

## 入力契約

- 1件指定時は、そのMarkdownファイルだけを対象にする。
- 複数件指定時は、指定されたMarkdownファイル群だけをまとめて対象にする。勝手に追加・置換しない。
- ファイル指定がない場合だけ、次の6つを既定対象にする。
  - `docs/product-requirements.md`
  - `docs/functional-design.md`
  - `docs/architecture.md`
  - `docs/repository-structure.md`
  - `docs/development-guidelines.md`
  - `docs/glossary.md`

各入力を正規化し、実体がリポジトリの`docs/`配下に留まること、存在する通常ファイルであること、拡張子が`.md`であることを確認する。1件でも不正または不足ならレビューを開始せず、該当パスと理由を示して再指定を求める。

## 実行手順

1. main agentが確定した対象パスと、必要ならレビュー観点を整理する。
2. `doc_reviewer`へ対象ファイル、関連する`docs/`または`.steering/`の必要最小限の参照先、制約、出力形式を渡す。
3. `doc_reviewer`にread-onlyで、正確性、完全性、文書間整合性、検証可能性、曖昧さ、運用上の危険を確認させる。ファイルを変更させない。
4. agentの完了を必ず待つ。利用できない場合はmain agentだけで代行せず、レビュー未完了として停止する。
5. main agentがfindingを重大度順に統合し、各findingに根拠ファイルと位置、影響、推奨修正を付けて日本語で簡潔に報告する。
6. findingがない場合は、その旨と確認範囲、残存リスクを報告する。

## 完了条件

- 指定契約どおりのファイルだけを`doc_reviewer`がレビューしている。
- main agentがagentの完了を待ち、結果を重大度順に統合している。
- 文書、コード、`.steering/`を変更していない。
- 実装検証が必要な依頼は`$validate-implementation`へ案内する。
