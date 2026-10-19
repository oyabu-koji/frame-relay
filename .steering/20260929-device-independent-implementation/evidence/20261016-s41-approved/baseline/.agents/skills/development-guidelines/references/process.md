# 開発プロセスガイド

## 基本フロー

1. `docs/ideas/` の仕様と関連する永続文書を確認する
2. `.steering/[YYYYMMDD]-[task]/` のrequirements、design、tasklistを確認する
3. taskを所有範囲が判定できる粒度にする
4. taskを1件実装し、受け入れ条件を検証する
5. tasklistの状態と検証証跡を更新する
6. 全task完了後、同じsteeringをvalidationへ渡す

## Xcode検証手順

この手順はinit、implement、validationで共通利用する。文書作成時は実在する構成と利用可能な検証を記述し、文書作成だけを理由にビルドを開始しない。合意済みの `docs/development-guidelines.md` があれば対象と品質条件の正本とする。

### 実行前の確認

1. 対象がテンプレート・文書のみか、アプリの変更かを確認する。このAIテンプレートrepoにXcodeプロジェクトは不要であり、文書だけの検証のために生成しない。アプリの検証でproject/workspaceがなければ、人間がXcodeでiOS App / SwiftUI / Swiftとして作成するよう案内し、アプリ検証を停止する。
2. macOSとXcodeの利用可否を確認し、`xcode-select -p`、`xcodebuild -version`、`xcrun swift --version` を必要に応じて確認する。Command Line ToolsのみでiOSビルド可能と扱わない。未導入や不一致では報告し、ツールの導入や端末全体のXcode選択を自動変更しない。
3. `.xcodeproj` / `.xcworkspace` の存在と内容、workspaceが参照するproject、既存の開発手順を確認する。project内の内部workspaceや依存先・サンプルをアプリの入口と取り違えない。複数候補は用途から選び、特定できなければ確認する。workspaceの存在だけで優先順位を決めない。
4. 選んだ入口だけを指定して `xcodebuild -list -project "<確認済みprojectパス>"` または `xcodebuild -list -workspace "<確認済みworkspaceパス>"` を実行し、schemeを確認する。targetはproject設定または構成projectの一覧でも確認する。schemeがCLIから見えなければ既存の共有設定を確認し、名前の推測や新規scheme生成で補わない。
5. 選んだschemeのBuild/Test action、app/test target、configuration、Swift言語モード、最低対応iOSを確認する。テストはTest actionまたは採用済みtest planに対象が含まれ、有効であることを確認する。test planの新規作成は必須にしない。
6. 同じ入口とschemeを指定した `xcodebuild ... -scheme "<確認済みscheme>" -showdestinations` で利用可能な実行先を確認する。`...`は手順4で確定した `-project` または `-workspace` 引数を表す。SDK・Simulator runtime・端末の利用可否と変更対象への適合からdestinationを選ぶ。Simulator名、OS、IDを固定せず、実行時の一覧を使う。テストには実行可能な具体的destinationが必要で、ビルド専用のgeneric destinationを流用しない。

一覧確認も含め、Xcodeコマンドはキャッシュや依存解決への書き込みを伴う場合がある。権限・書き込み先・既存依存の状態を実行前に確認し、取得や設定更新が必要なら既存の権限と合意範囲に従う。権限不足で構成を取得できない場合も、推測でbuild/testを進めない。

### ビルド・テスト・起動確認

次はコマンドの形を示す例であり、そのまま実行しない。すべてのプレースホルダーを上記で確認した値へ置き換える。workspaceを入口とする場合は `-project` を `-workspace` とそのパスへ置き換え、両方を指定しない。

```sh
xcodebuild -project "<確認済みprojectパス>" -scheme "<確認済みscheme>" -configuration "<確認済みconfiguration>" -destination "<確認済みbuild用destination>" build
xcodebuild -project "<確認済みprojectパス>" -scheme "<確認済みscheme>" -configuration "<確認済みconfiguration>" -destination "<確認済みtest用destination>" test
```

- `build`は対象のコンパイル・リンクと診断を確認する。署名・Team・Capabilities・最低対応iOSをエラー回避のために無断変更しない。
- `test`は有効なtest targetとTest actionを確認できた場合に実行する。実際に実行されたテスト数、skip、失敗を結果から確認し、終了コード0でも0件実行をテスト合格扱いにしない。テスト未設定だけを自動的に失敗とはしないが、受け入れ条件が要求するテストの欠如は未達として扱う。
- Unit testは採用済みのSwift TestingまたはXCTest、UI testはXCTestの構成に従う。検証のためだけにテスト基盤や外部ツールを追加しない。
- カバレッジは対象と測定条件が合意され、実行可能な場合に取得する。固定閾値は `docs/development-guidelines.md` に合意済みの場合だけ評価する。未取得を0%や成功とみなさない。
- 起動・画面・権限・端末機能の確認は、Xcodeで対象schemeとSimulatorまたは実機を選んで行う。人間が行った確認はその旨と証跡を記録する。build成功やPreview表示だけで実機・起動確認済みにしない。
- SwiftLint等の外部lintを必須ゲートにせず、既存の合意済み構成がある場合だけ対象にする。XcodeGen、Tuist、CocoaPods、その他の外部ツールを標準導入しない。

### 権限と検証証跡

- DerivedData、result bundle、キャッシュ、Simulator状態などの書き込みを区別する。許可済みの作業用出力先を選び、必要なら `-derivedDataPath` / `-resultBundlePath` を指定する。出力先を指定しても全書き込みがそこだけに収まるとは扱わない。
- read-onlyのvalidatorは権限を変更せず、実行できないコマンド、必要な書き込み先・実行環境をmainへ返す。mainは親ターンのsandboxとapprovalに従って実行可否を判断し、実行した場合はコマンド・対象・結果をvalidatorへ返す。検証中はコード、設定、docs、steeringを更新しない。
- コマンド、Xcodeバージョン、project/workspace、scheme、configuration、destination、テスト対象、終了結果、ログまたはresult bundleの場所を記録する。implementではtasklist、validationでは報告へ残す。
- 成功、失敗、未設定、環境・権限による未実行、対象外を分ける。必須検証が未実行なら完了・合格にせず、未確認範囲を報告する。

コマンドの参照: [AppleのXcodeコマンドライン資料](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)。利用環境のオプションは `xcodebuild -help` でも確認する。

## Review

- 要求と受け入れ条件を満たすか
- architectureとrepository structureの境界を守るか
- エラー、権限拒否、空状態、待機状態を扱うか
- 変更に対応するtestがあるか
- 安定した判断が関連docsへ反映されているか
- tasklistの記録と実際のdiffが一致するか

## Git

- ユーザーの既存変更を保護する
- 無関係な差分を整形・修正しない
- commit規則とbranch戦略はリポジトリの合意を正本とする
- Conventional Commitsを採用する場合も、scopeは実際の変更境界に合わせる
