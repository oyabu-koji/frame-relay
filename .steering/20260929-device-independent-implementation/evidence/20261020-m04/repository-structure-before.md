# リポジトリ構造定義書

## 適用方針

- 技術前提は[PROJECT_CONTEXT.md](../PROJECT_CONTEXT.md)のSwift + SwiftUI + native iOS + Xcode。既存の最低対応iOS `27.0`、Swift言語モード `5.0`、App・単体・UIの3 targetを維持する。Xcode・コンパイラ・SDKの実バージョンは本書で固定しない。
- 要求は2026-09-25承認済みの[PRD](product-requirements.md)（補足R2を含む）と2026-09-26の回答に基づく補足R3、機能上の境界は[機能設計](functional-design.md)、責務・依存は[アーキテクチャ設計](architecture.md)を参照する。全P0（FR-01〜17、NFR-01〜04）を対象とし、配置によって要求や優先度を変更しない。
- 構成方針はhybrid。表示は機能単位、ユースケース・純粋規則・端末I/Oは層単位に分け、層内を責務別に整理する。撮影・通信・削除の実行主体が画面寿命に引きずられず、共通の状態・規則を一か所で管理できる配置とする。
- 本書は目標配置の設計であり、ファイル移動・実装は未実施。機能設計U1〜U3はR3の回答範囲を確定し、その残件とU4〜U8は未合意。MediaVaultの配信・認証・版管理の限定ソース確認と方式比較はアーキテクチャ設計を参照し、API・実機成立やFrameRelay契約との互換性を検証済みとはしない。ディレクトリ名・型名の例で未決の操作や技術を確定しない。

## プロジェクト構造

### 現在の構造

2026-09-25の静的確認時点。個人設定・生成物とSkill内の詳細は省略する。

```text
FrameRelay/
├── FrameRelay.xcodeproj/
│   ├── project.pbxproj
│   └── project.xcworkspace/contents.xcworkspacedata
├── FrameRelay/
│   ├── FrameRelayApp.swift
│   ├── ContentView.swift
│   └── Assets.xcassets/
│       ├── Contents.json
│       ├── AccentColor.colorset/Contents.json
│       └── AppIcon.appiconset/Contents.json
├── FrameRelayTests/FrameRelayTests.swift
├── FrameRelayUITests/FrameRelayUITests.swift
├── docs/
│   ├── ideas/initial-requirements.md
│   ├── product-requirements.md
│   ├── functional-design.md
│   ├── architecture.md
│   ├── repository-structure.md              # 本書
│   ├── development-guidelines.md
│   └── glossary.md
├── .agents/
│   ├── README.md
│   ├── skills/
│   └── workspaces/.gitkeep
├── .codex/
│   ├── config.toml
│   └── agents/
├── .gitignore
├── AGENTS.md
├── PROJECT_CONTEXT.md
└── README.md
```

[FrameRelayApp.swift](../FrameRelay/FrameRelayApp.swift)が`@main`入口で、`WindowGroup`から[ContentView.swift](../FrameRelay/ContentView.swift)の初期表示を開く。撮影・ライブラリ等の機能や画面遷移はまだ実装されていない。[単体テスト](../FrameRelayTests/FrameRelayTests.swift)はSwift Testing、[UIテスト](../FrameRelayUITests/FrameRelayUITests.swift)はXCTestの雛形であり、P0の受入検証済みを意味しない。

[project.pbxproj](../FrameRelay.xcodeproj/project.pbxproj)では、3つのソースルートがそれぞれ`PBXFileSystemSynchronizedRootGroup`として同名targetへ対応する。独立したルートの`.xcworkspace`はなく、上記workspaceはproject内部の構成。共有`.xcscheme`・`.xctestplan`・独立した`Info.plist`・entitlements・`Package.swift`・外部依存設定はファイル列挙で確認されていない。個人用scheme管理plistの存在から実行可能schemeを断定せず、実行時に確認する。`.steering/`と`docs/decisions/`は現時点で未作成。

### 目標構造

以下は未作成領域を含む配置計画。既存の入口・アセット・3つのソースルートを保ち、必要な実装を置く時点で領域を作る。全フォルダ・空ファイルの先行生成はしない。

```text
FrameRelay/
├── FrameRelayApp.swift                     # 既存のApp入口
├── ContentView.swift                       # 既存。将来はルート表示を担当
├── Composition/                            # 依存の組み立て
├── Features/                               # Presentation層
│   ├── Capture/                            # 撮影・撮影設定
│   ├── Library/                            # 一覧・詳細・管理操作の確認
│   ├── Playback/                           # 原本/軽量版再生と明示確認
│   └── Connection/                         # 接続・処理状況
├── Shared/Presentation/                    # 機能に依存しない表示部品
├── Application/
│   ├── Capture/
│   ├── MediaOperations/
│   ├── Library/
│   ├── Recovery/
│   ├── MediaIO/
│   └── Ports/
├── Domain/
│   ├── Capture/
│   ├── Media/
│   └── Operations/
├── Platform/                               # 下表のI/O責務ごとに配置
└── Assets.xcassets/                         # 既存の位置を維持

FrameRelayTests/
├── FrameRelayTests.swift                    # 既存の雛形
├── Domain/
├── Application/
├── Presentation/
├── Platform/
├── Integration/
└── Support/                                # Fakes/、Fixtures/を必要時に配置

FrameRelayUITests/
├── FrameRelayUITests.swift                  # 既存の雛形
├── Flows/
└── Support/
```

`Features/<機能>/`では必要に応じて`Views/`と`Presentation/`を分ける。ここでのPresentationは画面の表示状態・入力窓口を指し、永続操作や撮影セッションの所有者ではない。各層は同一の`FrameRelay` module内の論理境界であり、フォルダ分割だけでは依存をコンパイラで強制できない。別target・packageへの分割は要求しない。

## ディレクトリ詳細

### App入口・機能表示・共有表示

下表のソースはすべて`FrameRelay` targetに所属する。「公開入口」は他の責務から使ってよい窓口を示し、Swiftの`public`指定を要求するものではない。

| 配置 | 責務・配置するもの | 配置しないもの・公開入口 | 主なテスト配置 |
| --- | --- | --- | --- |
| `FrameRelayApp.swift`、`ContentView.swift` | アプリ/Scene入口、注入済みの機能Viewをつなぐルート表示。画面遷移の具体方式は操作設計後に決める | 撮影制御・削除規則・DB/HTTP処理は置かない。入口はAppとルートView | `FrameRelayUITests/Flows/` |
| `Composition/` | Port実装の生成、Applicationへの注入、画面とアプリ管理状態の寿命の接続 | 業務判断・独自の成功判定を置かない。入口例は`AppComposition` | `FrameRelayTests/Integration/` |
| `Features/Capture/` | V1/V2。撮影・設定・音声・ND・人物・ズームの表示とcommand発行 | カメラAPIや解析処理を直接持たない。撮影/設定Viewと表示状態が入口 | `FrameRelayTests/Presentation/Capture/`、`FrameRelayUITests/Flows/` |
| `Features/Library/` | V3/V5。一覧・詳細、転送/写真保存/条件を満たす容量整理の複数選択・開始、1本ずつの破棄、動画別の成否/未処理の表示と本人入力 | 選択状態を開始受理済み対象集合と分け、削除可否・重複防止を再実装しない。Libraryのsnapshotと目的別commandを利用 | `FrameRelayTests/Presentation/Library/`、`FrameRelayUITests/Flows/` |
| `Features/Playback/` | V4。1本ずつの再生・明示確認、再生元、再生到達、版、バッファ待ち/一時容量不足の表示と入力 | 再生だけで確認を確定しない。写真保存は別操作・状態。独自の動画取得はしない。再生Viewが入口 | `FrameRelayTests/Presentation/Playback/`、`FrameRelayUITests/Flows/` |
| `Features/Connection/` | V6。接続・権限、動画別の待機理由・成否/未処理/要確認、既開始通信の条件付き自動再開/本人停止の表示と入力 | 指示済み順番待ちと未指示を区別し、秘密情報の保管や通信再開条件を所有しない。接続/処理状況Viewが入口 | `FrameRelayTests/Presentation/Connection/`、`FrameRelayUITests/Flows/` |
| `Shared/Presentation/` | 複数画面で実際に共有する表示部品、表示専用の値整形、アクセシビリティ表現 | 特定featureの内部型、共有セッション、汎用の巨大な状態オブジェクトは置かない。値とactionを受ける部品が入口 | `FrameRelayTests/Presentation/Shared/` |

撮影固有の音量表示や構図表示は、再利用箇所がない段階ではCapture内に置く。共有の製品規則は`Shared/`へ集めずDomainへ、共有のI/O契約はApplicationのPortsへ配置する。

### Application・Domain

すべて`FrameRelay` targetに所属し、テストは`FrameRelayTests/`の同じ層・責務名へ対応させる。

| 配置 | 責務・配置するもの | 公開入口・配置しないもの |
| --- | --- | --- |
| `Application/Capture/` | CaptureCoordinator、設定適用、REC/STOP、WB/音声、解析採否、ズームの調停 | `prepare/apply/start/stop`等のcommandと型付きsnapshot/event。View・端末API実装は置かない |
| `Application/MediaOperations/` | 転送、確認/失効、容量整理、破棄、写真保存、再生要求と一時媒体使用権の調停。開始受理時の対象集合と動画別の操作/対象/版/証拠/結果を保持し、原本/登録キー単位の操作順序を管理 | 目的別commandと操作ID・理由付き結果/未処理。容量整理と破棄の入口を分ける。DB/HTTP/Photos/ファイルAPIは置かない |
| `Application/Library/` | 撮影IDから動画別の状態・成否/未処理を統合した読取専用の一覧/詳細投影 | snapshotと読取契約。保存結果・確認・失効を直接変更しない |
| `Application/Recovery/` | 起動時の未完了操作照合と操作担当への復旧要求 | 照合commandと結果。未実行削除・結果不明の写真追加を自動再実行せず、終了済み再生を自動再開しない |
| `Application/MediaIO/` | MediaIOGate、Wi-Fi/REC/保存/本人停止・キャンセルの抑止とlease管理。開始受理済み・未完了・未停止/未キャンセルの通信だけ、全条件を再確認して自動再開 | ゲート契約と理由付き状態。指示済み順番待ちも対象とし、選択だけで開始しない。背景/ロック等の未合意方針やOS通信実装を混入させない |
| `Application/Ports/` | Capture/Analysis/OperationStore/Original/Remote/Photos/Playback/一時媒体/認証保管等のI/O契約、層を越えるcommand・snapshot・eventの契約 | protocolと値の契約。Domainの型を利用し、具象サービス・DB entity・HTTP DTO・SDKオブジェクトを公開契約へ漏らさない |
| `Domain/Capture/` | 希望値/実適用/対応条件、WB・音声・人物・ND・ズームの値と純粋規則（D1/D2） | 理由付き判定と型。フレーム処理・時計照会・カメラ制御は置かない |
| `Domain/Media/` | 原本同一性、保存証拠、版、確認/失効、容量整理と破棄の別規則、写真登録キー（D3〜D7） | 副作用のない値・判定。永続化表現・パス操作・リモート削除を置かない |
| `Domain/Operations/` | 開始指示と固定対象集合、動画別の操作ID/世代、本人意思、待機理由、結果採否、再開可否（D8） | 時刻・能力・証拠を入力とする判定。選択と指示済み順番待ちを区別し、task・queue・通信・DBを所有しない |

容量整理と破棄はDomainの規則とApplicationのcommandを別にし、共通化は対象限定の削除実行・照合に留める。失効保存と容量整理の順序はMediaOperationsで一元化し、Libraryや画面に別の更新経路を作らない。

原本転送・同じMac mini生成Rec.709軽量版の写真保存・条件を満たす容量整理は、複数選択してまとめて開始/実行し、内部は順次処理でよい。開始受理時の対象集合へ後から未指示動画を追加せず、動画別の証拠と結果/未処理を維持する。複数容量整理でも各削除直前に最新の確認/失効・対象・排他を照合し、不可なら破棄へ自動移行しない。再生・明示確認・破棄は1本ずつとし、複数選択を確認の自動確定や一括破棄へ使わない。通信の自動再開を未実行削除・結果不明Photos追加・終了済み再生へ拡張しない。

### Platform

下記はすべて`FrameRelay/Platform/`配下の目標サブディレクトリ。`FrameRelay` targetに所属し、外部への入口は`Application/Ports/`の実装とする。使用framework・出力方式・保存方式の候補はarchitectureの検証条件を継承する。

| 配置 | 配置するもの | 配置しないもの・接続境界 |
| --- | --- | --- |
| `Capture/` | カメラ/音声能力照会、セッション、記録出力、SDKのqueue/callback橋渡し | SwiftUI状態、容量整理判定。記録と表示/解析入力を分岐し、型付き事実を返す |
| `Analysis/`、`Render/` | 人物等のフレーム解析、固定Rec.709撮影表示、表示面adapter | NDに基づく露出の無断変更、原本への表示変換/予告の焼込み。表示面に必要なSDK橋渡しはここに閉じる |
| `LocalStore/` | 操作・固定対象集合・動画別結果・設定・確認/失効等の永続化、schema/migration、値との変換。Core Data採用時のmodelもここ | 動画本体、表示状態の正本化。Core Dataのmodelファイルは未作成・採用検証前 |
| `OriginalStore/`、`TemporaryMedia/` | アプリ所有原本の固定参照・内容検査・許可対象の削除、streamingバッファ/軽量版一時ファイルの用途・取得範囲・所有者・使用権・動画別/全体の一時使用量・解放管理 | 独自の削除許可、外部パス/Photos/Mac miniの削除、原本の自動回収。使用中の媒体や復旧証拠を無断回収せず、部分バッファをPhotos登録用の完全ファイルとしない |
| `Remote/`、`Network/` | MediaVault契約adapter、HTTP DTO/変換、接続/経路観測、ゲート付き動画送受信。同じRec.709軽量版の全体取得を待たないstreamingを第一候補とし、再生/再開時も原本/変換版/映像IDと配信内容の対応を固定 | サーバー本体、撮影制御、旧削除候補フラグの直接利用。配信/認証/版固定の限定ソース確認は実機成立の証拠にせず、具体方式とendpointは未確定 |
| `Playback/`、`Photos/` | 版固定の再生・実到達イベント、写真追加/動画別結果照合、SDK橋渡し | 確認の自動確定、独自の通信経路、写真削除。取得と一時参照は注入されたPortを利用し、streaming再生とPhotos登録を分離 |
| `Credentials/`、`Diagnostics/` | 認証保管adapter、最小限の診断出力 | 接続秘密や家族動画をソース/ログへ保存しない。診断ログを復旧証拠の代わりにしない |

Mac miniの変換器・サーバー・保存ディレクトリがこのrepoにあるとは扱わない。iOS側の契約はPortsとRemoteへ置き、サーバー側の配置・変更は既存MediaVaultの調査と合意した作業範囲で定める。`backend/`やMac用targetを本書だけを根拠に作らない。

### テスト領域

| 配置 | 所属target・方式 | 配置対象・入口 |
| --- | --- | --- |
| `FrameRelayTests/Domain/`、`Application/`、`Presentation/` | `FrameRelayTests`、Swift Testing | 純粋規則、固定対象集合と動画別結果、条件付き自動再開、Portへの失敗/遅延/逆順注入、表示投影と入力。`@Test`を入口とし`@testable import FrameRelay`で参照 |
| `FrameRelayTests/Platform/`、`Integration/` | 同上 | adapter契約、使い捨てのdiskストア/ファイルを用いた復旧・削除照合、制御可能な通信先との契約。実環境の実行条件は計画で区別 |
| `FrameRelayTests/Support/Fakes/`、`Fixtures/` | 同上。必要時に作成 | Portのfake、固定入力・小さな検証用資材。アプリtargetへ含めない。実原本や認証秘密をfixture化しない |
| `FrameRelayUITests/Flows/`、`Support/` | `FrameRelayUITests`、XCTest | F1〜F5と状態別操作、3操作の複数選択と動画別の成否/未処理、1本ずつの再生/明示確認/破棄、権限導線、アクセシビリティ。`XCUIApplication`を通す。SupportはUI操作の補助のみ |

試験観点と受入条件の対応は機能設計T01〜T21を正本とする。実機の録画品質・回線制限・Photos成立をfakeやSimulatorで代替済みにしない。NFR-04の実データ参照先・合意・試験結果は対象steeringへ記録し、家族動画やMac mini原本をアプリbundleやrepoへ複製する配置にはしない。既存雛形を受入試験へ置き換える順序と実行コマンドは実装計画で決める。

## ファイル命名

Swiftファイルは主な型・責務と同じ`UpperCamelCase.swift`、フォルダは表の責務名を用いる。以下は未作成ファイルの命名例であり、具体型の実装を確定しない。

| 種別 | 配置先 | 命名規則・例 |
| --- | --- | --- |
| App・組み立て | 既存入口、`Composition/` | `FrameRelayApp.swift`、`AppComposition.swift` |
| View・表示状態 | `Features/<機能>/` | `CaptureView.swift`、`LibraryPresentation.swift`、`PlaybackSnapshot.swift` |
| ユースケース | `Application/<責務>/` | `CaptureCoordinator.swift`、`CleanupOriginal.swift`、`DiscardOriginal.swift` |
| I/O契約 | `Application/Ports/` | 責務を表す`…Port.swift`、既存の論理名なら`OperationStore.swift` |
| 値・純粋規則 | `Domain/<責務>/` | `CapturePreference.swift`、`CleanupEligibility.swift`、`PhotoRegistrationKey.swift` |
| I/O実装・外部表現 | `Platform/<責務>/` | `AVCaptureAdapter.swift`、`StorageVerificationDTO.swift`。技術名は採用確定後だけ付ける |
| 単体・統合テスト | `FrameRelayTests/<層・責務>/` | `CleanupEligibilityTests.swift`、`RemovalRecoveryTests.swift` |
| UIテスト | `FrameRelayUITests/Flows/` | `CaptureFlowTests.swift`、`DiscardFlowTests.swift` |
| テスト代替 | `FrameRelayTests/Support/Fakes/` | `FakeCapturePort.swift`。検証目的が分かる名前にする |

同一module内ではfeature別フォルダに置いても同名型の衝突は避けられない。`State.swift`、`Manager.swift`、`Utils.swift`のような所有責務が不明な名前を避け、`CaptureSnapshot`等で対象を示す。内部補助型は公開範囲を最小にし、他featureが内部実装を参照するために可視性を広げない。

## 依存関係

```text
FrameRelayApp -> Composition -> 各層の生成・注入
ContentView / Features -> Applicationの公開契約 -> Domain
ContentView / Features -> Shared/Presentation
Applicationの各担当 -> Application/Ports + Domain
Platform -> Application/Ports + Domain + 各端末/外部API
Shared/Presentation -> SwiftUI + 表示専用の値
Domain -> Swiftの値型・副作用のない基礎型
```

- PresentationのUI更新はMainActorで行い、端末処理を配置の都合でMainActorへ集めない。撮影・保存等の隔離と寿命はarchitectureに従う。
- Application同士は公開command・型付きevent・snapshotで連携する。Platform同士の連携も、Compositionで注入したPortを通し、他adapterの具象生成や内部状態の書換えを行わない。
- 撮影表示面などにSDK橋渡しが必要な場合は、CompositionがPlatformの表示adapterを画面へ注入する。Featuresからカメラセッションや描画の内部実装を参照しない。
- Domain内の共通ID/操作値は`Operations/`、媒体の値は`Media/`を参照元とし、同じ意味の型や規則を各機能へ複製しない。相互循環が生じる場合は責務を見直す。
- テスト用の依存注入・組み立てはテストtarget内で行う。アプリコードからテストtarget・fakeへ依存しない。

禁止事項:

- Features/SharedからPlatformの具象、ファイル削除、Photos追加、HTTP、DBへ直接依存すること。
- ApplicationからSwiftUI、具象Platform、SDKオブジェクト、外部DTOへ依存すること。Composition以外の本番コードで具象サービスを組み立てること。
- DomainからApplication/Platform/Presentation、OS時計照会、端末API、DB・ファイル・通信へ依存すること。
- 下位層からViewを操作すること、Sharedから特定featureの内部へ依存すること、feature間で表示状態を直接書き換えること。
- 撮影プレビューを軽量版確認へ流用する経路、ゲートを迂回する動画通信、容量整理不可から破棄へ自動切替する経路を設けること。

これらは単一moduleでの配置・参照規則であり、自動強制済みではない。実装時の差分とテストで参照方向・状態の所有を確認する。

## Assetと設定

- **アセット**: 既存`FrameRelay/Assets.xcassets/`の位置と`AppIcon`・`AccentColor`を維持する。追加資材は用途を表す名前（例`CaptureStatus…`）とし、`FrameRelay` targetへの所属と参照を確認する。テスト専用資材は各テストtarget配下へ置く。
- **必要時の資材**: ローカライズ等を追加する場合の目標は`FrameRelay/Resources/`。現時点では未作成で、言語追加は本書の要求ではない。標準表示変換に資材が必要なら由来・版・用途を記録してRender側の責務に対応させ、未合意のLUT選択UIや任意LUT群を作らない。
- **永続化model**: Core Data第一案を採用する場合だけ`Platform/LocalStore/`にversion付きmodelを配置し、App targetの資材として管理する。実行時のDB、原本、一時動画はアプリsandbox内のデータであり、ソースツリー・Assets・Resourcesへ置かない。ライフサイクルはarchitectureに従う。
- **ビルド設定**: 共有設定の現在の正本は`FrameRelay.xcodeproj/project.pbxproj`。iOS/Swift言語モード・既存target構成を維持する。共有schemeやtest planが必要になればproject内の共有設定として配置・対象targetを確認するが、現在存在するとは扱わない。
- **用途説明・Capabilities**: 現在は`GENERATE_INFOPLIST_FILE = YES`。生成Info.plistと独立ファイルを混同せず、実装時にApp targetの設定でカメラ・マイク・採用するPhotos権限等を扱う。通信経路・背景動作が未決のまま権限、ATS例外、Background Modes、App Groups/iCloudを追加しない。
- **個人設定・生成物**: `.gitignore`は`xcuserdata/`、`*.xcuserstate`、`DerivedData/`、`.DS_Store`を除外する。個人のscheme管理plistは共有schemeの代わりにしない。build/test生成物を文書やアプリ資材に混ぜない。
- **秘密情報**: 秘密はCredentials adapterの保管境界で扱う設計とし、Swiftソース・pbxproj・fixture・文書・ログに記載しない。具体的な接続先と認証方式は既存MediaVault調査後に決める。

## Docs・AIワークフロー

| 配置 | 責務・命名・扱い |
| --- | --- |
| `PROJECT_CONTEXT.md`、`AGENTS.md` | 技術前提とWorkflowの正本。アプリのソース/資材targetには含めない |
| `docs/` | 安定した要求・機能設計・architecture・本書・開発規則・用語集の6文書。`product-requirements.md`等の既定名を用い、PRDを要求更新先とする。開発規則は[development-guidelines.md](development-guidelines.md)、用語は[glossary.md](glossary.md)を参照する |
| `docs/ideas/` | `initial-requirements.md`はsetupのbootstrap入力。追加・変更仕様は`YYYYMMDD-[feature-name].md`でprepare-steeringの標準入力とする |
| `docs/decisions/` | 未作成。決定理由・代替・影響の記録を必要時に置く。ファイル名は`YYYYMMDD-[topic].md`とし、要求や計画の正本を重複させない |
| `.steering/[YYYYMMDD]-[task]/` | 未作成。`requirements.md`・`design.md`・`tasklist.md`を計画/進捗の正本とし、対象の検証証跡もここへ対応付ける。媒体本体・秘密は置かない |
| `.agents/skills/` | 明示Workflowと専門Skillの`SKILL.md`、template、guide。製品実装を置かない |
| `.agents/workspaces/` | 現在は`.gitkeep`のみ。Workflowの補助作業領域として用い、仕様・永続文書・進捗の正本にしない |
| `.codex/config.toml`、`.codex/agents/` | agent設定。`document_author`等の役割設定を置き、Skill手順や製品コードの配置先と混同しない |
| `README.md` | リポジトリの入口。要求・技術・作業手順は各正本へリンクし重複定義しない |

Workflowの開始条件、専門agentへの所有範囲の指定、review/validationの読み取り専用規則は[AGENTS.md](../AGENTS.md)に従う。本書の配置計画だけで別Workflowや実装を開始しない。

## 移行上の注意

1. 対象仕様とsteeringが用意された実装工程で、関係する責務から配置する。現状の`FrameRelayApp.swift`、`ContentView.swift`とアセットを入口にし、構造整理だけの一括移動はしない。
2. ソース追加/移動時はファイルシステム上の位置、Xcodeでの表示、同期グループ、target所属、資材参照を照合する。同期グループであることだけで誤ったtarget所属が起きないとはみなさない。
3. ロジックを先に必要なPort/Domainの責務へ割り当て、PlatformとPresentationの依存が逆転していないことを確認する。具体API、保存schema、出力方式はarchitectureの検証待ち事項を解決してから実装へ反映する。
4. build/test前に実在project・scheme・destination・テスト構成を確認する。実機/実データの評価、U1〜U3の残件（処理順・一部失敗後の方針・選択/停止UI・一時媒体の方式/上限/期限・背景/ロック等）と未合意のU4〜U8は後続仕様・計画で扱う。R3の確定部分を未合意へ戻さず、streaming第一候補やファイル配置の確定を機能成立の証拠にしない。

人間が作成した既存Xcode projectを利用し、構造定義のためのproject/workspace生成、project generator、空のpackage、外部依存やMac用targetは追加しない。今回の変更は本書だけであり、コード移動、build/test、Simulator/実機起動、外部接続、動画の生成・転送・削除は行っていない。

構成と記述観点は[repository-structure Skill](../.agents/skills/repository-structure/SKILL.md)、[テンプレート](../.agents/skills/repository-structure/assets/template.md)、[ガイド](../.agents/skills/repository-structure/references/guide.md)に従う。
