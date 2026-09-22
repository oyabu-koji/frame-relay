---
name: implement-steering
description: 指定された.steeringタスクのrequirements、design、tasklistに従って機能を実装し、進捗と検証証跡を同期する。計画済みタスクを実行する場合に明示的に使用する。計画作成、計画なしの実装、独立した最終検証には使用しない。
---

# Implement Steering

`.steering/`を進捗の正本として、所有範囲を分けながらタスクを1件ずつ実装する。

## 入力契約と停止条件

- `.steering/[YYYYMMDD]-[task]/`を1件、明示入力として受け取る。
- 引数なし、複数候補、対象が曖昧な場合は、ユーザーへ対象steeringを確認する。最新・未完了などの理由で別のsteeringを勝手に選択しない。
- 対象が存在しない、または`requirements.md`、`design.md`、`tasklist.md`のいずれかが不足する場合は変更を開始せず、`$prepare-steering`を案内する。新しいsteeringを勝手に作成せず、別Workflowも暗黙に開始しない。`.steering/`外の指定は受け付けず対象の再指定を求める。
- 要求、設計、taskの矛盾や実装に必要な重要判断がある場合は、main agentがユーザーへ確認する。
- 未コミット変更と所有対象が重なる場合は、既存変更を保護できる方針を確定するまで停止する。

## 実行手順

1. main agentが3文書と関連する永続文書を読み、taskの依存順、受け入れ条件、技術制約を確認する。
2. `$steering`を明示使用し、着手するtaskを`in-progress`として`tasklist.md`へ反映する。一度に進行中にする書き込みtaskは1件にする。
3. 必要な読み取り調査を組み込み`explorer`へ委任する。独立した調査やログ解析は並列化してよいが、書き込みtaskとファイル所有を重ねない。
4. 組み込み`worker`へtaskごとの実装とテストを委任する。所有ファイルまたはディレクトリ、入力、制約、完了条件を明示し、同じコードベースに他の作業者がいること、他者の変更を戻さないことを伝える。
5. 書き込みが競合するtaskは直列に実行する。複数workerを使う場合は所有範囲が重ならないことをmain agentが事前に確認する。
6. workerから結論、変更内容、根拠、実行した検証、残課題の要約を受け取る。main agentがdiff、要求との対応、所有範囲外の変更を確認する。
7. taskの受け入れ条件を満たした場合だけ`done`へ更新する。失敗または外部判断待ちは`blocked`として理由を記録し、次の依存taskへ進まない。
8. 実装が設計を変えた場合は、ユーザーが承認した安定した判断だけを`design.md`へ反映する。task状態と検証証跡は毎task後に`tasklist.md`へ同期する。

## ビルド・テスト構成と検証

1. [Xcode検証手順](../development-guidelines/references/process.md) を読み、実在するproject/workspace、scheme、app/test target、configuration、destinationと環境を確認する。アプリ実装でproject/workspaceがなければ独自生成せず、人間によるXcodeでのiOS App / SwiftUI / Swift作成を案内して停止する。テンプレート・文書のみのtaskではアプリ構成を要求しない。
2. 確認済みの構成からtaskに関連する `xcodebuild build` / `xcodebuild test` の引数を決める。project名、scheme名、Simulator名を固定しない。testはTest actionの有効なテスト対象と実行可能なdestinationを確認してから行う。
3. 未設定、失敗、環境・権限による未実行を区別する。未設定だけを自動的に失敗とはしないが、受け入れ条件が要求する検証は省略して完了にしない。
4. 固定カバレッジ閾値は`docs/development-guidelines.md`で合意済みの場合だけ適用する。外部lintやテスト基盤を検証のためだけに追加しない。
5. 検証失敗や必須項目の未確認があればtaskを完了扱いにせず、理由と再現方法を記録する。実行コマンド、対象構成、テスト実行件数、結果の場所を証跡に残す。
6. 必要な起動確認はSimulatorまたは実機で行い、build成功とは区別する。署名設定や依存を無断変更せず、生成物への書き込みも親ターンの権限に従う。

## 完了条件

- tasklistの対象taskが受け入れ条件と検証証跡付きで完了している。
- requirements、design、実装、テストが整合し、未解決事項が明示されている。
- 確認済み構成で必要な検証が実行され、結果と未確認範囲が記録されている。
- main agentが最終diffと所有範囲を確認している。
- 独立した最終検証は代行せず、同じsteeringディレクトリを明示して`$validate-implementation`を次の工程として案内する。暗黙に開始しない。
