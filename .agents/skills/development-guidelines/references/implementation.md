# Swift・SwiftUI・iOS実装ガイド

## 基本方針

- 新規コードはSwiftで実装し、UIはSwiftUIを基本とする。型、Optional、enum、protocolで必要な契約を表現する
- Viewは表示と入力、状態を所有するモデルは状態遷移、serviceは端末・外部I/O、純粋logicはUI・端末API非依存の処理を担当する。特定の設計パターンや不要な層を強制しない
- iOS APIの最低対応バージョン、利用不可、権限拒否、Simulatorと実機の差異を扱う
- 既存の `docs/development-guidelines.md` に別の境界があれば、そちらを優先する

## 命名とファイル

- 変数・関数: `camelCase`
- 型・protocol: `UpperCamelCase`
- 真偽値: `is`、`has`、`can`、`should` で意図を示す
- View: `FeatureView.swift`、`ItemRow.swift`など主な型名に合わせる
- model、service: `FeatureState.swift`、`StorageService.swift`など責務に合わせる
- test: `FeatureStateTests.swift`、`FeatureUITests.swift`など既存targetの規約に従う
- ファイル追加時は対象targetへの所属とアクセス範囲を確認する。ディレクトリだけでmodule境界を定義したことにしない

## 型と公開契約

不在をOptional、有限の状態をenum、回復可能な失敗を適切なErrorで表現する。強制unwrapや `try!` で通常の失敗を隠さない。公開範囲は必要最小限とし、制約・副作用を型から判断できない場合にドキュメントコメントを補う。

```swift
struct UserProfile {
    let id: String
    let displayName: String
}

enum ProfileState {
    case idle
    case loading
    case loaded(UserProfile)
    case failed(message: String)
}
```

## 状態と非同期処理

- Viewの局所状態、親から渡す値・Binding、共有状態の所有者とライフサイクルを区別する
- Observationなどの採用方式は最低対応iOSと確定済み設計に従う。新しいAPIを使うために対応OSを引き上げない
- Viewの `body` にI/Oを置かず、非同期処理の開始条件、重複防止、キャンセル、古い結果の扱いを定義する
- UI状態の更新は必要なMainActor隔離を明示し、高コスト処理でUIを塞がない。境界を越える値や共有可変状態はSwift言語モードに応じて安全性を確認する
- 警告を消すためだけに `@unchecked Sendable` や隔離の解除を追加せず、状態所有と依存境界を見直す

## エラーと品質

- 入力不正は呼び出し側が判定できる明示的なエラーにする
- recoverableな端末機能失敗はUI全体を壊さず、必要な通知とログを残す
- エラー表示とログへ秘密情報を含めない
- 不要な権限を要求しない
- 高コスト処理と不要な再描画を測定せずに最適化しない

## テスト

- 純粋logicはunit testを優先する
- 状態モデルとserviceの接続は必要に応じてintegration test、利用者に見える操作はXCTestのUI testや端末確認で検証する
- 端末API境界は必要なadapterやprotocolを通し、成功・拒否・失敗を検証する。外部mockライブラリを前提にしない
- Unit testは採用済みのSwift TestingまたはXCTestに従い、同じテスト内で両者のAPIを混在させない
- 実行前に [process.md](process.md) の手順でproject/workspace、scheme、test target、destinationを確認する
