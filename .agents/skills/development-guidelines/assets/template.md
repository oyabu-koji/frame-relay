# Development Guidelines

## 基本原則

- [利用者価値と品質の優先順位]
- [技術制約と依存方針]
- [docsとsteeringを同期する方針]

## 開発環境

- Language / UI / Platform: Swift / SwiftUI / native iOS
- IDE / build system: Xcode
- Xcode・Swiftコンパイラ・Swift言語モード・最低対応iOS: [PROJECT_CONTEXT.mdの確定値 / 未決]
- project/workspace・scheme・target: [実在する構成 / 未作成]
- SDK・Simulator runtime・実機: [利用可能な検証環境 / 不足]

## コーディング規約

### Swift / SwiftUI

- [型・Optional・アクセス制御・公開契約の記述]
- [状態の所有・共有とViewの責務]
- [エラー・副作用・非同期処理・キャンセル・actor隔離]

### 命名とファイル

- 変数・関数: `camelCase`
- 型・protocol: `UpperCamelCase`
- Swiftファイル: 主な型に対応する `TypeName.swift`
- test: `TypeNameTests.swift` / `FeatureUITests.swift` など採用済みtargetの規約

### 責務境界

- View: [表示・入力・局所状態の責務]
- State / Model: [所有・共有・状態遷移の責務]
- Logic: [責務]
- Service / Adapter: [責務]

## エラーハンドリング

- [入力不正]
- [端末機能・外部I/O失敗]
- [利用者への表示]
- [ログと秘密情報]

## テスト戦略

- Unit test: [対象]
- Framework: [採用済みSwift Testing / XCTestと理由]
- Integration test: [対象]
- UI test / device test: [XCTestのUIテスト / Simulator・実機での確認対象]

## 品質ゲート

実在するproject/workspace、scheme、configuration、destination、test target・Test actionを確認してからコマンドを確定する。未確認の名前やSimulatorを埋めない。

- [ ] build・診断確認: [確認済み構成を指定するxcodebuildコマンド / 未確認理由]
- [ ] test: [確認済み構成を指定するxcodebuildコマンド / 未設定・未実行理由]
- [ ] coverage: [合意した対象・測定方法 / 対象外]
- [ ] Simulator・実機での起動確認: [対象・操作・結果 / 未実行理由]

外部lintやproject generatorは標準導入しない。buildと起動確認は区別し、テスト0件や必須検証の未実行を合格扱いにしない。コマンド・対象構成・結果・証跡の場所を残す。

## Git・Review

- Branch strategy: [方針]
- Commit convention: [方針]
- Review requirements: [項目]

## Definition of Done

- [ ] 受け入れ条件を満たす
- [ ] 利用可能な品質ゲートを通過する
- [ ] 必要なdocsとsteeringを更新する
- [ ] 未検証事項と残課題を記録する
