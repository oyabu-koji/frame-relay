---
name: init-project
description: 人間がXcodeで作成したSwift・SwiftUIのiOS Appを確認し、最小開発基盤を整える場合に明示的に使用する。project/workspaceがなければ作成方法を案内して停止する。独自のプロジェクト生成、機能実装、技術バージョンの更新には使用しない。
---

# Init Project

実際のアプリrepoの最小開発基盤を整える。初期iOS Appは人間がXcodeで作成し、その後のSwiftコード実装をCodexへ引き継ぐ。このAIテンプレートrepo自体にはXcodeプロジェクトを作らない。

## 入力

- 対象リポジトリのルートを受け取る。省略時は現在のリポジトリルートを使う。
- `AGENTS.md` と `PROJECT_CONTEXT.md` を読み、技術スタック、確定済みのXcode・Swift設定・最低対応iOS、禁止事項を正本として扱う。

## 事前確認と停止条件

1. 対象ルート、既存ソース、Git状態、`.xcodeproj` / `.xcworkspace` を確認する。存在しない場合はファイルを書かず、「Xcodeで新規プロジェクトを作成し、iOS App / SwiftUI / Swiftを選択して対象repoへ保存してください」と案内して停止する。Codexが `.xcodeproj` / `.xcworkspace` を独自生成したり、XcodeGen・Tuist・その他のproject generatorを導入したりしない。
2. 作成済みなら [Xcode検証手順](../development-guidelines/references/process.md) に従い、project/workspaceの実体、scheme、app/test target、configuration、destinationを確認する。複数候補や壊れた参照があり対象を特定できなければ確認事項を返す。既存アプリは再生成・上書きせず、不足する基盤だけを対象にする。
3. 選択中のXcodeとSwiftコンパイラ、プロジェクトのSwift言語モード・最低対応iOSを正本と照合する。不一致・環境不足では内容を報告し、合意なしに指定値、端末全体のXcode選択、署名設定を変更しない。
4. 対象ルート、変更範囲、重要な技術判断が未確定、または既存変更を保護できない場合は書き込みを開始しない。

## 実行手順

1. main agentが作成対象、技術制約、完了条件を確定する。
2. 基盤ファイルに変更が必要な場合だけ組み込み`worker`へ委任する。所有ファイルを列挙し、同じコードベースに他の作業者がいること、他者の変更を戻さないこと、機能実装をしないことを伝える。
3. 人間が作成したSwiftUI Appのentry pointとtarget設定を確認する。不足があれば報告し、独自のプロジェクト再生成で補わない。既存構成の補修は合意した範囲だけに限定する。
4. 必要なら `.gitignore` を整え、DerivedData、ビルド・テスト生成物、個人用の `xcuserdata` を対象にする。project設定や共有schemeを一括で除外しない。
5. SwiftLint、CocoaPods等の外部ツールや不要な依存を追加しない。既存依存も初期化を理由に更新しない。
6. 確認したbuild/test構成と利用可能な検証を報告する。test targetやtest plan、外部lintを一律に追加・必須化しない。
7. 構成と権限を確認できた検証だけを実行する。build成功とSimulator・実機での起動確認を分け、未実行の理由と未確認範囲を示す。
8. workerから結論、変更ファイル、実行した検証、残課題の要約を受け取る。main agentが最終diffと所有範囲外の変更がないことを確認する。

## 完了条件

- 人間が作成したSwift・SwiftUIのiOS Appについて、対象project/workspace、scheme、target、実行先が特定されている。
- 必要な共通開発ファイルが整い、独自のプロジェクト生成や外部ツール追加を行っていない。
- 利用可能な検証と結果が報告されている。プロジェクト作成待ちや必須検証不能は完了扱いにしない。
- 要件定義、`.steering/`作成、アプリ機能実装を行っていない。
- 次の操作として`$define-requirements`を案内する。
