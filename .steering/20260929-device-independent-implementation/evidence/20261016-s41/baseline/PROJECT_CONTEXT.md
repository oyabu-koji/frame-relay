# Project Context

## プロジェクト

このリポジトリは、実際のiOSアプリ「FrameRelay」の開発リポジトリである。Swift iOS AI development templateを開発基盤として適用している。

## 技術前提

- Project name: FrameRelay
- App type: native iOS application
- Language: Swift
- UI framework: SwiftUI
- IDE / build system: Xcode
- Xcode project: `FrameRelay.xcodeproj`

## 既存のプロジェクト構成

- `FrameRelay/`: アプリ本体（`FrameRelay` target）
- `FrameRelayTests/`: ユニットテスト（`FrameRelayTests` target）
- `FrameRelayUITests/`: UIテスト（`FrameRelayUITests` target）

`FrameRelay.xcodeproj/project.pbxproj` で確認できる現在の設定は、iOS Deployment Targetが `27.0`、Swift言語モード（`SWIFT_VERSION`）が `5.0` である。これらは既存プロジェクトの設定値であり、将来の対応OS方針をここで新たに決定するものではない。使用するXcode・Swiftコンパイラのバージョンはここでは固定しない。

## 開発の進め方

`.agents/`、`.codex/`、`AGENTS.md` のAI開発Workflowを利用する。手順とSkillの呼び出し規則は `AGENTS.md` および既存のSkillsに従う。

FrameRelayの具体的な機能要件はこの文書では定義せず、後で `$define-requirements` を通じてユーザーとの対話により決める。過去知識や推測に基づく機能仕様・設計方針は追加しない。
