# リポジトリ構造定義書

## 適用方針

- 技術前提: Swift + SwiftUI + native iOS + Xcode
- 構成方針: [feature-first / layer-first / hybridと理由]
- 現在との差分: [新規構成または既存構成の更新]

## プロジェクト構造

以下は実際のアプリrepoでXcodeプロジェクトを作成した後の配置例。実在するproject/workspace、target、ファイル構成に合わせて編集し、現在と将来の構造を分けて記載する。AIテンプレートrepoにはアプリやXcodeプロジェクトがなくてもよい。

```text
project-root/
├── [AppName].xcodeproj/
├── [AppName]/
│   ├── [AppName]App.swift
│   ├── Features/
│   ├── Shared/
│   └── Resources/
│       └── Assets.xcassets/
├── [UnitTestTarget]/
├── [UITestTarget]/
├── docs/
├── .agents/
├── .codex/
└── .steering/
```

`[AppName]`等は実在する名前へ置き換える。テスト領域は採用・作成済みの場合だけ現状に含め、独立した`.xcworkspace`は実在する場合だけ記載する。ディレクトリを分けるだけでは別のSwiftモジュールにはならない。

## ディレクトリ詳細

### `[path]/`

- 責務: [内容]
- 配置するもの: [内容]
- 配置しないもの: [内容]
- 命名規則: [内容]
- 公開入口: [内容]
- 所属target・module: [既存構成との対応]
- テスト配置: [内容]

## ファイル命名

| 種別 | 配置先 | 命名規則 | 汎用例 |
| --- | --- | --- | --- |
| App入口 | [アプリtargetのソース領域] | `[AppName]App.swift` | `SampleApp.swift` |
| View | [機能または共有領域] | `UpperCamelCase.swift` | `ItemRow.swift` |
| モデル | [機能または共有領域] | `UpperCamelCase.swift` | `Item.swift` |
| サービス | [設計したI/O境界] | `UpperCamelCase.swift` | `ItemStore.swift` |
| ロジック | [設計した規則・計算の境界] | `UpperCamelCase.swift` | `ItemSelection.swift` |
| テスト | [所属テストtargetの領域] | `UpperCamelCaseTests.swift` | `ItemSelectionTests.swift` |

## 依存関係

```text
[許可する依存方向]
```

禁止事項:

- [禁止する依存]

## Assetと設定

- リソース配置・命名・targetへの所属: [Asset Catalog、ローカライズ等]
- ビルド設定・共有scheme: [実在する構成と共有する範囲]
- 用途説明・Capabilities: [必要な機能と設定箇所。生成される設定とファイルを区別する]
- 個人設定・生成物: [xcuserdata、DerivedData等の管理対象外となる範囲]
- 秘密情報: [管理方針]

## Docs・AIワークフロー

- `docs/ideas/`: [役割]
- `docs/`: [役割]
- `.steering/`: [役割]
- `.agents/skills/`: [役割]
- `.codex/agents/`: [役割]

## 移行上の注意

- [現状から変更する場合の順序とtargetへの所属・リソース参照の確認]
- 最初のiOS Appプロジェクトは人間がXcodeでSwiftUI・Swiftを選択して作成する。構造定義のためにプロジェクトや空のパッケージ構成を生成しない。
