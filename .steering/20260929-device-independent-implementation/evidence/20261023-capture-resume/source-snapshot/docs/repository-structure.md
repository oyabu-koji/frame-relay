# リポジトリ構造定義書

## 適用方針

- 技術前提は[PROJECT_CONTEXT.md](../PROJECT_CONTEXT.md)のSwift + SwiftUI + native iOS + Xcode。既存の最低対応iOS `27.0`、Swift言語モード `5.0`、App・単体・UIの3 targetを維持する。Xcode・コンパイラ・SDKの実バージョンは本書で固定しない。
- 要求は2026-09-25承認済みの[PRD](product-requirements.md)（補足R2を含む）と2026-09-26の回答に基づく補足R3、機能上の境界は[機能設計](functional-design.md)、責務・依存は[アーキテクチャ設計](architecture.md)を参照する。全P0（FR-01〜17、NFR-01〜04）を対象とし、配置によって要求や優先度を変更しない。
- 構成方針はhybrid。表示は機能単位、ユースケース・純粋規則・端末I/Oは層単位に分け、層内を責務別に整理する。撮影・通信・削除の実行主体が画面寿命に引きずられず、共通の状態・規則を一か所で管理できる配置とする。
- 本書は2026-10-23時点の実在配置と責務を示し、未作成領域・未接続機能は区別する。進捗・検証証跡・実機残件は[現行tasklist](../.steering/20260929-device-independent-implementation/tasklist.md)を正本とし、ファイルの存在を製品接続や受入完了の証拠にしない。合意済みの操作・暫定policyと未合意事項は機能設計・アーキテクチャ設計に従う。

## プロジェクト構造

### 現在の構造

主要な実在領域だけを示す。個人設定・生成物、各層の補助ファイルは省略する。

```text
FrameRelay/
├── FrameRelay.xcodeproj/
│   ├── project.pbxproj
│   └── project.xcworkspace/contents.xcworkspacedata
├── FrameRelay/
│   ├── FrameRelayApp.swift
│   ├── ContentView.swift
│   ├── Composition/                         # 製品の単一組立と探索専用組立
│   ├── Features/{Capture,Library,Playback,Connection}/
│   ├── Application/
│   │   ├── Capture/
│   │   ├── Library/
│   │   ├── Recovery/
│   │   ├── MediaOperations/
│   │   ├── MediaIO/
│   │   └── Ports/
│   ├── Domain/{Capture,Media,Operations}/
│   ├── Platform/
│   │   ├── Capture/
│   │   ├── Render/
│   │   ├── LocalStore/
│   │   ├── OriginalStore/
│   │   ├── TemporaryMedia/
│   │   ├── Playback/
│   │   ├── Photos/
│   │   ├── Network/
│   │   ├── Remote/
│   │   ├── Credentials/
│   │   └── Diagnostics/
│   └── Assets.xcassets/                      # AppIcon・AccentColor
├── FrameRelayTests/
│   ├── FrameRelayTests.swift                 # 雛形を保持
│   ├── Domain/
│   ├── Application/
│   ├── Platform/
│   ├── Integration/{Storage,Playback,Photos,Composition,Registration,Remote,Publication}/
│   ├── Support/                             # fake・生成媒体・固定入力の補助
│   └── Fixtures/Subjects/                    # 人物解析用画像とprovenance
├── FrameRelayUITests/
│   ├── FrameRelayUITests.swift               # 起動・性能の雛形を保持
│   └── Flows/                               # 製品/探索/一覧/接続の操作試験
├── docs/
│   ├── ideas/initial-requirements.md
│   ├── product-requirements.md
│   ├── functional-design.md
│   ├── architecture.md
│   ├── repository-structure.md              # 本書
│   ├── development-guidelines.md
│   └── glossary.md
├── .steering/                               # タスク別3文書・support・証跡
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

[FrameRelayApp.swift](../FrameRelay/FrameRelayApp.swift)が`@main`入口で、[ProductComposition.swift](../FrameRelay/Composition/ProductComposition.swift)を保持し、[ContentView.swift](../FrameRelay/ContentView.swift)からライブラリ、通常撮影、接続・登録、原本再生、別入口の探索画面を開く。起動時に製品storeを開くが、撮影権限要求・capture session準備は撮影入口まで遅らせる。Libraryは原本再生、既存の写真登録記録の表示と理由付き明示照合、本人リスク確認後の単数破棄/結果照合へ接続する。Connectionは既存登録の媒体なし明示状態同期と続きを持つ。条件付き複数容量整理を通常導線へ接続し、正式証拠producer・通常strict通信の未成立は残件として扱う。通常転送・写真の新規保存・軽量版再生/確認は未接続と表示し、起動・一覧再読込みでPhotos権限を要求しない。

[project.pbxproj](../FrameRelay.xcodeproj/project.pbxproj)では、3つのソースルートがそれぞれ`PBXFileSystemSynchronizedRootGroup`として同名targetへ対応する。独立したルートの`.xcworkspace`はなく、上記workspaceはproject内部の構成。共有`.xcscheme`・`.xctestplan`・独立した`Info.plist`・entitlements・`Package.swift`・外部依存設定は配置されていない。CLI照会では実行可能なscheme/test plan `FrameRelay`を確認済みで、その証跡とrepo内の共有ファイルの有無、個人用scheme管理plistを区別する。build/test時は実在構成を再確認する。

### 主要な実装と接続状態

以下のApp相対パスはすべて`FrameRelay/`配下。実装済みの部分と通常の製品操作への接続は別に示す。

| 責務 | 主要実ファイル | 現在の境界 |
| --- | --- | --- |
| 共通store・原本・組立 | `Composition/ProductLibraryFactory.swift`、`Platform/LocalStore/ExplorationRecordingStores.swift`、`RecordingStoreDocument.swift`、`Platform/OriginalStore/ManagedOriginalStore.swift`、`ManagedOriginalAccess.swift` | 製品rootのCore Data/SQLiteによる`SQLiteRecordingStore`、schema 7の同writer/journal、原本領域、内容対応・read leaseを共有。`Exploration`という既存名だけで探索専用と判断しない |
| 撮影・補助表示 | `Composition/ProductCaptureFactory.swift`、`Application/Capture/ProductCaptureCoordinator.swift`、`Platform/Capture/NativeExplorationCapture.swift`、`Features/Capture/ProductCaptureView.swift` | 通常の設定・REC/保存・WB・音声・補正・人物/ND・ズームへ接続。S49のREC/保存境界は下記の共通通信担当へ渡す。レンズISO policyの通常注入は保留。実方式・能力・品質は実機未確認 |
| 一覧・原本再生 | `Application/Library/LibraryStoreReader.swift`、`LibrarySnapshot.swift`、`Features/Library/LibraryModel.swift`、`Features/Playback/OriginalPlaybackModel.swift`、`Platform/Playback/AVOriginalPlayback.swift` | 単一storeから一覧/履歴を投影し、原本再生・既存写真記録の明示照合・単数破棄・条件付き複数容量整理を接続。整理候補の表示と削除直前の権限再判定を分け、状態同期後も同じ読取担当から動画別に表示する。新規写真保存・正式証拠producer等は未接続 |
| 写真登録・存在照合 | `Platform/Photos/NativePhotoLibrary.swift`、`Application/MediaOperations/PhotoSaveCoordinator.swift`、`PhotoRegistrationReconciler.swift`、`Application/Library/LibraryPhotoReconciliation.swift` | 実SDK追加・同writerへの意図/結果/終端証拠保存・完全取得媒体の受渡し、過去結果/現在存在の表示と明示照合。終端後は結果と独立して元photo useを解放し、復元/owner閉鎖を失効時の全reader解放へ接続する。正式Rec.709媒体の通常取得・複数保存producerは未接続 |
| 接続・登録 | `Application/MediaOperations/RegistrationCoordinator.swift`、`Platform/Remote/URLSessionRegistrationRemote.swift`、`Platform/Credentials/KeychainRegistrationVault.swift`、`Features/Connection/ConnectionModel.swift` | 製品store・資格保管・登録画面へ接続。既存登録の明示状態同期は別の担当へ渡し、再登録全体・全媒体の製品接続と分ける |
| 媒体なし状態同期 | `Application/MediaOperations/BackendStatusSynchronizationCoordinator.swift`、`Application/Ports/StatusSynchronizationPort.swift`、`Composition/ProductStatusSynchronization.swift` | S28の既存登録・既知原本に対する明示1page/manifest同期と続き、元mutation/旧outboxのexact照合→同writer→動画別表示を接続。未解決失効とcursorを分け、再openはnullから照合。新確認/媒体開始を生成せず、背景履歴/未知ownerの対象ACKは保留 |
| 背景session・task・復帰 | `Application/MediaIO/BackgroundMediaCoordinator.swift`、`Application/Recovery/BackgroundMediaRecovery.swift`、`Composition/ProductBackgroundMediaFactory.swift`、`ProductBackgroundEventRouter.swift`、`Platform/Network/BackgroundMediaSession.swift` | S23のOS session/taskと固定contextの永続対応、直列delegateからのevent drain、App delegate配送を同じ製品writerへ接続。通常strict開始/resume・安全なdownload受入口・旧source所有採用・全媒体producerは未接続 |
| REC/保存と通信の境界 | `Application/MediaIO/CaptureMediaAdmission.swift`、`Application/Ports/CaptureMediaBoundaryPort.swift`、`Composition/ProductCaptureMediaBoundary.swift` | S49のowner別REC/save/recovery hold、token前の取消可能preflight、exact local stopと保存file実returnまでの待機を通常撮影へ接続。同ファイルの`CaptureMediaResumeAuthorization`は元admission/revisionに束縛した単回同期許可で、coordinatorからasync SDK portへ渡しactual action直前に消費する契約。nativeの正のresume・全媒体実停止の成立とは分ける |
| 容量整理・破棄 | `Application/MediaOperations/CleanupCoordinator.swift`、`DiscardCoordinator.swift`、`Application/Library/LibraryRemovalCommands.swift`、`Composition/ProductRemovalTermination.swift` | S32/S33の目的別coreとS34通常単数破棄・条件付き複数容量整理を同じCompositionへ接続。全historical uploadの実終端/自身source FD閉鎖/ownerClosed/exact lease解放を照合し、容量整理固有の保存検証/有効確認は別途再判定する。固定集合と動画別の成功/未実行/要照合を保持し、整理成功は通常一覧、破棄成功は履歴へ投影。正式証拠producer・新規Photos/複数保存・全S34/実機受入とは区別 |
| 固定軽量版・一時媒体 | `Platform/Playback/AVRenditionPlayback.swift`、`Platform/Network/FixedRenditionRangeReader.swift`、`Platform/TemporaryMedia/ManagedTemporaryMedia.swift`、`Application/MediaIO/RenditionScopeRegistry.swift` | 固定版の実再生・取得・lease/一時媒体管理の独立実装。写真終端の元use解放とコピー本体の回収を分け、unknown/failed/notAttemptedのコピーを保持する。通常Libraryの軽量版操作への接続は未完 |
| 確認・失効・公開の周辺 | `Application/MediaOperations/MediaConfirmationCoordinator.swift`、`MediaInvalidationCoordinator.swift`、`BackendOutboxCoordinator.swift`、`Composition/ProductMediaTermination.swift`、`Platform/Remote/PublicationWire.swift` | S27の固定版/登録別失効・全必要ACKと製品rootの原本player/同writerを共有する終端窓口。S28へ失効/outboxを接続するが、正式proof・全製品owner・通常軽量版再生/確認/公開の完成とは区別する |
| 表示描画 | `Platform/Render/CaptureDisplayTransform.swift`、`CaptureDisplayRenderer.swift`、`CaptureDisplayPipeline.swift` | 生成cubeを使うencoded-BGRA技術描画。標準資材未取得、実Log変換・通常capture/UI接続は未実装 |
| 探索 | `Composition/ExplorationComposition.swift`、`Application/Capture/ExplorationCoordinator.swift`、`Features/Capture/ExplorationView.swift` | 試験票・方式候補・試験runを持つ独立入口。探索条件や結果を製品採用へ昇格しない |

未作成領域は`Shared/Presentation/`、`Platform/Analysis/`、`Resources/`等。現在の人物/ND解析は`Platform/Capture/`内、表示状態の試験は`FrameRelayTests/Application/`等にあり、配置計画だけを理由に移動しない。写真の通常保存開始/固定複数集合、条件付き複数整理の正式証拠producer、通常strict開始/resume・全媒体producer、正式Log/標準Rec.709資材・品質proof、再登録全体は今後の担当taskへ残す。接続と必要検証の実行版・結果は現行tasklistへ記録し、既存のgate契約・純粋規則・本人意思の永続化や実削除coreを未実装へ戻さない。

`Features/<機能>/`は現在ViewとModelを同じ機能フォルダへ置く。必要になれば`Views/`と`Presentation/`を分けるが、表示状態・入力窓口を永続操作や撮影セッションの正本にしない。各層は同一の`FrameRelay` module内の論理境界であり、フォルダ分割だけでは依存をコンパイラで強制できない。別target・packageへの分割は要求しない。

## ディレクトリ詳細

### App入口・機能表示・共有表示

下表は現在の実装と今後追加する責務の配置規則。接続状態は前表に従う。実在ソースはすべて`FrameRelay` targetに所属し、「公開入口」は他の責務から使う窓口を示す。Swiftの`public`指定を要求するものではない。

| 配置 | 責務・配置するもの | 配置しないもの・公開入口 | 主なテスト配置 |
| --- | --- | --- | --- |
| `FrameRelayApp.swift`、`ContentView.swift` | アプリ/Scene入口、注入済みの機能Viewをsheet等でつなぐルート表示 | 撮影制御・削除規則・DB/HTTP処理は置かない。入口はAppとルートView | `FrameRelayUITests/Flows/` |
| `Composition/` | `ProductComposition`、`ProductLibraryFactory`、`ProductCaptureFactory`と背景/REC境界/削除終端/状態同期の生成・注入、画面を越える所有者の保持 | 業務判断・独自の成功判定を置かない。探索専用の`ExplorationComposition`と区別 | `FrameRelayTests/Integration/Composition/` |
| `Features/Capture/` | V1/V2。撮影・設定・音声・ND・人物・ズームの表示とcommand発行 | 解析・記録処理を持たない。`ProductCapturePreview`のSDK表示橋渡しは後述の限定境界 | `FrameRelayTests/Application/ProductCaptureCoordinatorTests.swift`等、`FrameRelayUITests/Flows/ProductCaptureFlowTests.swift` |
| `Features/Library/` | V3/V5。`LibraryModel`と`LibraryView`による一覧・履歴、複数/単数の選択・入力と理由表示、単数破棄のリスク確認と結果照合 | 選択状態を開始受理済み対象集合と分け、削除可否・重複防止を再実装しない。Libraryのsnapshotと目的別commandを利用 | `FrameRelayTests/Application/Library/`、`FrameRelayUITests/Flows/LibraryFlowTests.swift`、`RemovalFlowTests.swift` |
| `Features/Playback/` | V4。現在は`OriginalPlaybackModel`と`OriginalPlaybackView`による原本再生・停止・状態表示。軽量版の明示確認等は追加時もここ | 再生だけで確認を確定しない。写真保存は別操作・状態。独自の動画取得はしない | `FrameRelayTests/Integration/Playback/`、`FrameRelayUITests/Flows/LibraryFlowTests.swift` |
| `Features/Connection/` | V6。`ConnectionModel`と`ConnectionView`による接続先・登録・照合と、既存登録の明示状態同期/続き・動画別撮影日時と保存事実の表示 | 指示済み順番待ちと未指示を区別し、秘密情報の保管や通信再開条件を所有しない。起動/登録復元だけで同期を開始しない | `FrameRelayTests/Integration/Registration/`、`FrameRelayUITests/Flows/ConnectionFlowTests.swift` |
| `Shared/Presentation/`（未作成） | 複数画面で実際に共有する表示部品、表示専用の値整形、アクセシビリティ表現 | 特定featureの内部型、共有セッション、汎用の巨大な状態オブジェクトは置かない。値とactionを受ける部品が入口 | 必要時に責務に対応する試験を配置 |

撮影固有の音量表示や構図表示は、再利用箇所がない段階ではCapture内に置く。共有の製品規則は`Shared/`へ集めずDomainへ、共有のI/O契約はApplicationのPortsへ配置する。

### Application・Domain

すべて`FrameRelay` targetに所属し、テストは`FrameRelayTests/`の同じ層・責務名へ対応させる。

| 配置 | 責務・配置するもの | 公開入口・配置しないもの |
| --- | --- | --- |
| `Application/Capture/` | `ProductCaptureCoordinator`、`CaptureLifecycle`、`RecordingSaveLifecycle`、`ProductCapturePostSave`による設定・REC/STOP・WB/音声・解析採否・ズーム・保存後処理 | `prepare/apply/start/stop`等のcommandと型付きsnapshot/event。View・端末API実装は置かない |
| `Application/MediaOperations/` | 登録、確認/失効、outbox、`BackendStatusSynchronizationCoordinator`、`PhotoSaveCoordinator`・`PhotoRegistrationReconciler`、`CleanupCoordinator`・`DiscardCoordinator`。開始時の固定対象集合と動画別の操作/証拠/結果を調停 | 目的別commandと操作ID・理由付き結果/未処理。容量整理と破棄の入口を分ける。DB/HTTP/Photos/ファイルAPIは置かない |
| `Application/Library/` | 撮影IDから動画別の状態・成否/未処理を統合した読取専用の一覧/詳細投影。`LibraryPhotoReconciliation`は既存写真記録の表示と明示照合、`LibraryRemovalCommands`は本人確認と破棄/結果照合の橋渡し | snapshotと読取契約、目的別担当へのcommand。保存結果・確認・失効を直接変更しない |
| `Application/Recovery/` | `OriginalRemovalReconciler`による削除結果の観測照合、`BackgroundMediaRecovery`によるOS session/task対応の照合と復旧要求 | 照合commandと結果。未知の旧source所有を採用せず、未実行削除・結果不明の写真追加を自動再実行せず、終了済み再生を自動再開しない |
| `Application/MediaIO/` | `RenditionReadLeases`、`RenditionMediaScope`、`RenditionScopeRegistry`、`RenditionTemporaryRetrieval`による軽量版の使用権・owner終端・一時取得。`BackgroundMediaCoordinator`は固定taskのevent drainと資源終端、`CaptureMediaAdmission`は同期的なowner別holdと同じlockで判定/消費する単回resume許可を所有 | ゲート契約と理由付き状態。Wi-Fi/REC/保存/本人停止を下位でも照合し、本人が開始した未完了通信だけ条件付き自動再開。内部許可の発行をSDK実行済みと扱わず、新しい本人操作を要求しない。OSが許す背景/ロック中の継続や媒体を含まない状態同期の確定要件を縮小しない。部分接続を全媒体gateの完成にしない |
| `Application/Ports/` | Capture/Analysis/OperationStore/Original/Remote/Photos/Playback/一時媒体/認証保管等のI/O契約、層を越えるcommand・snapshot・eventの契約。`BackgroundMediaPorts.swift`・`CaptureMediaBoundaryPort.swift`・`OriginalRemovalPorts.swift`・`StatusSynchronizationPort.swift`もここ。`PhotoLibraryPorts.swift`は追加/権限/識別情報照合/成功・終端証拠に基づく使用権復旧の窓口 | protocolと値の契約。Domainの型を利用し、具象サービス・DB entity・HTTP DTO・SDKオブジェクトを公開契約へ漏らさない |
| `Domain/Capture/` | 希望値/実適用/対応条件、WB・音声・人物・ND・ズームの値と純粋規則（D1/D2） | 理由付き判定と型。フレーム処理・時計照会・カメラ制御は置かない |
| `Domain/Media/` | 原本同一性、保存証拠、版、確認/失効、容量整理と破棄の別規則（D3〜D7）。`PhotoRegistration.swift`は写真登録キー/意図/追加結果/存在観測と、結果から独立した終端証拠・使用権解放の値。旧成功限定解放の値も保持 | 副作用のない値・判定。永続化表現・パス操作・リモート削除を置かない |
| `Domain/Operations/` | 開始指示と固定対象集合、動画別の操作ID/世代、本人意思、待機理由、結果採否、再開可否（D8）。`BackgroundMediaTask.swift`はOS task対応の値/純粋規則、`OriginalRemovalBatch.swift`は目的別batch/対象/結果の値 | 時刻・能力・証拠を入力とする判定。選択と指示済み順番待ちを区別し、実行中task・queue・通信・DBを所有しない |

容量整理と破棄はDomainの規則とApplicationのcommandを別にし、共通化は対象限定の削除実行・照合に留める。失効保存と容量整理の順序はMediaOperationsで一元化し、Libraryや画面に別の更新経路を作らない。

共通storeの正本は`SQLiteRecordingStore`と`RecordingStoreDocument`で、連携の永続表現・commandは同じ`Platform/LocalStore/`のadapterへ集める。製品の`ProductLibraryFactory`が単一writer・`ManagedOriginalStore`・`ManagedOriginalAccess`を保持し、撮影・一覧・再生・登録・背景/削除/状態同期へ同じinstanceを渡す。`ProductBackgroundMediaFactory`は通常CompositionとApp delegateから同じ製品rootを開き、`ProductBackgroundEventRouter`が既知OS sessionのdrain後に配送handlerを完了させる。この完了を全reader解放や遠隔成功の証拠にしない。原本ファイルの予約・読取と内容対応/leaseの操作は原本担当、共有契約は`Application/Ports/`、具象の生成・製品への追加接続は`Composition/`を単独所有とする。各featureで別store・独自の原本参照・重複Portを作らず、変更時の具体ファイル所有と引渡しはsteeringに記録する。

`LibrarySnapshot`は保存記録と現在の原本状態を投影し、破棄成功を照合した項目だけを履歴へ分ける。容量整理成功は通常一覧に残し、不明を削除成功へ変えない。容量整理の表示用適格性は同じwriterの保存検証/有効確認と原本状態から導出し、`LibraryRemovalCommands`が固定対象を既存`CleanupCoordinator`へ渡す。表示や一部成功を削除権限にせず、各削除直前と最終writerで条件を再判定する。履歴は管理記録であり、原本を移すゴミ箱や別の媒体保存領域ではない。通常単数破棄/条件付き複数整理の接続を正式証拠producer・全S34や実機受入の完了へ昇格しない。

S34-BG01の`OriginalRemovalTransportFence`は、全task receipt集合とhash前の対象別inventoryを保持する一時的な契約で、単数破棄と条件付き複数容量整理に共用する。`ManagedOriginalAccess`の同FD全hash後、同writer最終unlinkで`OriginalRemovalStoreProjection`がinventoryと全receipt集合を再構築・再判定し、ABA/新attempt/task/関連登録変更を拒否する。容量整理の保存検証/有効確認/支持schemaは最終writerでも再判定する。対象に無関係な別clip更新は許し、fenceなし旧callerの全writer revision CAS、共有schema 7/Codable旧commandは維持する。unknown/copy中/attach gap/旧source/task再利用/同operation複数attempt/download/活動中を自動停止・回収せず、原本unlink後もupload copyを保持する。`ProductRemovalTermination`は未解決子の受付閉鎖を保持しつつ、独立した終端子だけを最新epoch/accessで再観測して解放する。

原本転送・同じMac mini生成Rec.709軽量版の写真保存・条件を満たす容量整理は、複数選択してまとめて開始/実行し、内部は順次処理でよい。開始受理時の対象集合へ後から未指示動画を追加せず、動画別の証拠と結果/未処理を維持する。複数容量整理でも各削除直前に最新の確認/失効・対象・排他を照合し、不可なら破棄へ自動移行しない。再生・明示確認・破棄は1本ずつとし、複数選択を確認の自動確定や一括破棄へ使わない。通信の自動再開を未実行削除・結果不明Photos追加・終了済み再生へ拡張しない。

### Platform

下記は`FrameRelay/Platform/`配下の実在領域と追加時の配置先。`FrameRelay` targetに所属し、外部への入口は`Application/Ports/`の実装とする。使用framework・出力方式・保存方式の採用と未確認範囲はarchitectureの検証条件を継承する。

| 配置 | 配置するもの | 配置しないもの・接続境界 |
| --- | --- | --- |
| `Capture/` | カメラ/音声能力照会、セッション、記録出力、SDKのqueue/callback橋渡し | SwiftUI状態、容量整理判定。記録と表示/解析入力を分岐し、型付き事実を返す |
| `Capture/`内の解析、`Render/` | `NativeCaptureSubjectAnalysis`・`NativeCaptureNDAnalysis`等のフレーム解析、`CaptureDisplay…`の独立技術描画。`Analysis/`は未作成 | NDに基づく露出の無断変更、原本への表示変換/予告の焼込み。標準Rec.709変換と通常表示の接続は資材待ち |
| `LocalStore/` | 撮影/原本/操作/確認・失効等の単一writerとschema/migration、設定保存。`PhotoStoreProjection.swift`は同じschema7 journalから写真登録/終端/元use解放を投影し、登録結果によるコピー保持を判定。`BackgroundMediaStoreProjection.swift`・`OriginalRemovalStoreProjection.swift`も同journalから背景task/削除意図・結果を投影する。Core Data/SQLiteのmodelは`ExplorationRecordingStores.swift`内で組み立てる | 動画本体、表示状態の正本化、feature専用の重複DB。独立した`.xcdatamodeld`は使っていない |
| `OriginalStore/`、`TemporaryMedia/` | 原本の予約・固定参照・同FD内容検査/read lease、同writerの最新条件照合→MOVのみ実unlink→結果最終照合。`ManagedUploadSource`は原本leaseから実copy/全hash/出力FD読戻しを行い、exact SDK終端後に自身の保持FDを閉鎖。`ManagedTemporaryMedia`は一時ファイル/使用量/解放を管理し、完全取得媒体は`TemporaryLocalMediaPort`から扱う。写真用はexact終端または旧成功証拠による元use解放と、登録成功かつ全使用権解放後の実unlinkを分ける | 独自の削除許可、外部パス/Photos/Mac miniの削除、原本の自動回収。自身のsource FD閉鎖をSDK所有全FDの閉鎖へ広げない。使用中の媒体や復旧証拠を無断回収せず、unknown/failed/notAttemptedの登録用コピーを保持。部分バッファをPhotos登録用の完全ファイルとしない |
| `Remote/`、`Network/` | 登録・publicationのwire/HTTP adapter、固定版Range通信、`BackgroundMediaSession`の直列delegate/型付きevent。原本/変換版/映像IDと配信内容の対応を固定し、OS sessionとMac側upload sessionを区別する | サーバー本体、撮影制御、旧削除候補フラグの直接利用。具体的な契約実装と、通常strict開始/resume・全媒体の製品接続・実機成立を区別する |
| `Playback/`、`Photos/` | `AVOriginalPlayback`・`AVRenditionPlayback`とresource loaderによる実再生/停止。`Photos/NativePhotoLibrary.swift`は実PhotoKit追加/完了と保存済み識別情報だけの照合 | 確認の自動確定、独自の通信経路、写真削除。取得と一時参照は注入されたPortを利用し、streaming再生とPhotos登録を分離 |
| `Credentials/`、`Diagnostics/` | 認証保管adapter、最小限の診断出力 | 接続秘密や家族動画をソース/ログへ保存しない。診断ログを復旧証拠の代わりにしない |

Mac miniの変換器・サーバー・保存ディレクトリがこのrepoにあるとは扱わない。iOS側の契約はPortsとRemoteへ置き、サーバー側の配置・変更は既存MediaVaultの調査と合意した作業範囲で定める。`backend/`やMac用targetを本書だけを根拠に作らない。

### テスト領域

| 配置 | 所属target・方式 | 配置対象・入口 |
| --- | --- | --- |
| `FrameRelayTests/Domain/`、`Application/` | `FrameRelayTests`、Swift Testing | 純粋規則、固定対象集合と動画別結果、条件付き自動再開、Portへの失敗/遅延/逆順注入、表示投影と入力。`@Test`を入口とし`@testable import FrameRelay`で参照。独立した`Presentation/`は未作成 |
| `FrameRelayTests/Platform/`、`Integration/` | 同上 | adapter契約、使い捨てのdiskストア/ファイルを用いた復旧・削除照合、制御可能な通信先との契約。実環境の実行条件は計画で区別 |
| `FrameRelayTests/Integration/Photos/` | 同上 | `PhotoSaveCoordinatorTests`、`PhotoTemporaryRecoveryTests`・`PhotoTerminalRecoveryTests`と`PhotoSaveFixture`。結果と終端の独立commit・元use解放・コピー保持を試験する。`NativePhotoLibraryTests`は明示opt-inの専用Simulator実Photos試験。値検証は`Domain/PhotoRegistrationTests.swift`、同writer再openは`Integration/Storage/PhotoRegistrationStoreTests.swift` |
| `FrameRelayTests/Integration/Publication/PhotoInvalidationBoundaryTests.swift` | 同上 | 実MOV・実disk・実`ProductMediaTermination`を用い、Photos終端順序のfixtureと失効時の全reader解放を接続する境界試験。実PhotoKit completionや通常保存producer・実機品質の成立とは区別 |
| `FrameRelayTests/Integration/OriginalRemovalIntegrationTests.swift`、`DiscardIntegrationTests.swift`、`OriginalRemovalTransportFenceTests.swift`、`OriginalCleanupTransportFenceTests.swift` | 同上 | S32/S33の両store・同FD全hash/実MOV unlink・中断/再open・観測だけの復旧と、全task receipt/inventory最終照合の境界。容量整理固有の証拠とhash/最終writer間の変更も試験対象。`Support/OriginalRemovalFixture.swift`を用い、外部媒体/管理記録・旧CASを保持する |
| `FrameRelayTests/Integration/Remote/`、`Integration/Storage/` | 同上 | `BackgroundMediaSessionTests`・`BackgroundEventDrainTests`・`BackgroundMediaStoreTests`・`ManagedUploadSourceTests`がOS task対応/event drain/copyと自身のFD閉鎖を試験。`BackgroundCaptureResumeTests`はcoordinator最終許可発行後のhold/ABAとSDK側の注入action直前の同期消費を試験する。`BackgroundRemovalTerminalTests`は実suspended→resume拒否→cancel callback→exact lease/stopped→通常model破棄/再openを確認する。strict permit/Mac notExecutedやdispatch actionは注入で、正の実SDK resume・通常実通信/SDK全FDの証拠ではない |
| `FrameRelayTests/Integration/Composition/`、`Application/ProductCaptureMediaBoundaryTests.swift`、`Application/ProductCapturePostSaveTests.swift`、`Application/CaptureMediaResumeAuthorizationTests.swift` | 同上 | `ProductBackgroundCompositionTests`は共通writer/REC境界、Applicationの試験はowner別hold/preflight・保存通知と次REC、および単回同期許可のorigin/消費/throw/hold/ABA・実Thread競合を扱う。`ProductRemovalCompositionTests`・`ProductHistoricalRemovalTests`は通常単数破棄/終端履歴、`ProductCleanupCompositionTests`は条件付き複数整理/固定集合/混在結果/終端子の独立解放、`ProductStatusSynchronizationTests`は既存登録の明示同期/動画別表示を試験する。seed補助と通常起動を区別する |
| `FrameRelayTests/Application/BackendStatusSynchronizationCoordinatorTests.swift`、`Integration/Storage/StatusSynchronizationStoreTests.swift` | 同上 | S28の1page/続き・未解決失効とcursorの分離・元mutation/旧outbox・exact登録/store・同writer/再openを確認。背景履歴/未知ownerへのACK保留、新確認/媒体開始なしを維持する |
| `FrameRelayTests/Support/`、`Fixtures/Subjects/` | 同上 | Portのfake、`Support/Storage/SyntheticMovieFixture.swift`の合成動画、人物解析用の公開画像と`provenance.json`。アプリtargetへ含めず、実原本や認証秘密をfixture化しない。独立した`Support/Fakes/`は未作成 |
| `FrameRelayUITests/Flows/` | `FrameRelayUITests`、XCTest | 製品撮影・Library・接続・探索の操作と状態表示。`RemovalFlowTests.swift`は単数破棄/履歴、`ConnectionFlowTests.swift`は明示metadata同期/続きも扱う。条件付き複数整理のUI実行条件・結果は現行tasklistで追跡する。`XCUIApplication`を通し、Photos等の未接続操作や未実施の必要検証を完了扱いにしない |

Unit targetはApp hostを使用し、UI targetは`FrameRelay`を操作対象とする。各同期rootは対応targetだけに所属し、現projectにmembership例外はない。試験専用画像はUnit root、合成媒体の生成器はUnitのSupportへ置き、本番Appにfixture生成・自動seedの分岐を追加しない。既存の`Integration/Composition/ProductLibrarySeedTests.swift`の`seedNormalAppContainer`は明示opt-inで通常App rootのwriterへ試験データを投入する補助であり、通常起動処理ではない。同suiteの`freshFixturesReopenWithRemovalProjectionsAndUnchangedOriginal`は通常Unitで隔離tmp rootを作り、製品guardを維持した現行cleanup契約、再open、内容同一性とreader解放を検証する。合成証拠やSDK fakeを実Log/標準Rec.709・実通信・正式証拠producer・品質/実機受入の証明にしない。実通信probeも環境変数によるopt-inで、通常のUnit実行と区別する。

試験観点と受入条件の対応は機能設計T01〜T21を正本とする。実行版・件数・結果・未実行理由はsteeringの証跡へ残し、雛形の`example`やskip/未実行を機能検証の成功にしない。厳格アクセシビリティ監査4失敗は旧BG01版と直後の独立検証の過去証跡として保持し、P2修正後の結果は[現行tasklist](../.steering/20260929-device-independent-implementation/tasklist.md)と各証跡を参照する。通常UI/専用metadata UIや実文字/VoiceOverの成功から監査合格を作らない。実機の録画品質・回線制限・Photos成立をfakeやSimulatorで代替済みにせず、NFR-04の実データ参照先・合意・試験結果も対象steeringへ記録する。家族動画やMac mini原本をアプリbundleやrepoへ複製しない。

## ファイル命名

Swiftファイルは主な型・責務と同じ`UpperCamelCase.swift`、フォルダは表の責務名を用いる。以下は実在する命名例であり、今後の追加も責務と対応させる。

| 種別 | 配置先 | 命名規則・例 |
| --- | --- | --- |
| App・組み立て | 既存入口、`Composition/` | `FrameRelayApp.swift`、`ProductComposition.swift` |
| View・表示状態 | `Features/<機能>/` | `ProductCaptureView.swift`、`LibraryModel.swift`、`OriginalPlaybackView.swift` |
| ユースケース | `Application/<責務>/` | `ProductCaptureCoordinator.swift`、`RegistrationCoordinator.swift` |
| I/O契約 | `Application/Ports/` | `OriginalStorePort.swift`、`RenditionMediaPorts.swift` |
| 値・純粋規則 | `Domain/<責務>/` | `CaptureZoom.swift`、`OriginalDescriptor.swift`、`MediaRequest.swift` |
| I/O実装・外部表現 | `Platform/<責務>/` | `AVOriginalPlayback.swift`、`RegistrationWire.swift`。技術名は現実装と対応させ、実機採用と区別する |
| 単体・統合テスト | `FrameRelayTests/<層・責務>/` | `Domain/CaptureZoomTests.swift`、`Integration/Storage/OriginalSaveRecoveryTests.swift` |
| UIテスト | `FrameRelayUITests/Flows/` | `ProductCaptureFlowTests.swift`、`LibraryFlowTests.swift` |
| テスト代替 | `FrameRelayTests/Support/` | `BackendContractFakes.swift`、`CaptureFixture.swift`。検証目的が分かる名前にする |

同一module内ではfeature別フォルダに置いても同名型の衝突は避けられない。`State.swift`、`Manager.swift`、`Utils.swift`のような所有責務が不明な名前を避け、`CaptureSnapshot`等で対象を示す。内部補助型は公開範囲を最小にし、他featureが内部実装を参照するために可視性を広げない。

## 依存関係

```text
FrameRelayApp -> Composition -> 各層の生成・注入
ContentView / Features -> Applicationの公開契約 -> Domain
ContentView / Features -> Shared/Presentation（共有部品が必要になった場合）
Applicationの各担当 -> Application/Ports + Domain
Platform -> Application/Ports + Domain + 各端末/外部API
Shared/Presentation -> SwiftUI + 表示専用の値
Domain -> Swiftの値型・副作用のない基礎型
```

- PresentationのUI更新はMainActorで行い、端末処理を配置の都合でMainActorへ集めない。撮影・保存等の隔離と寿命はarchitectureに従う。
- Application同士は公開command・型付きevent・snapshotで連携する。Platform同士の連携も、Compositionで注入したPortを通し、他adapterの具象生成や内部状態の書換えを行わない。
- 撮影表示面などにSDK橋渡しが必要な場合は、CompositionがPlatformの表示adapterを画面へ注入する。現在の`Features/Capture/ProductCapturePreview.swift`は`NativeCapturePreviewSource`を受けて`AVCaptureVideoPreviewLayer`を表示し、人物枠/タップ座標を変換している。これは目標の参照方向・Platform表示adapterへの分離との差分であり、設計例外の承認ではない。現状の記述を依存規則の緩和や他のFeaturesから撮影内部を操作する根拠にしない。
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
- **必要時の資材**: ローカライズ等を追加する場合の目標は`FrameRelay/Resources/`。現時点では未作成で、言語追加は本書の要求ではない。標準表示変換の資材は未取得で、Renderの空catalogへ未確認LUTを登録しない。取得時は由来・版・利用条件・入力適合を記録し、未合意のLUT選択UIや任意LUT群を作らない。
- **永続化model**: 現在は`Platform/LocalStore/ExplorationRecordingStores.swift`内でCore Data modelを生成し、`RecordingStoreDocument.swift`が保存payloadのschemaを扱う。独立したmodel資材の存在を前提にしない。製品DBと原本はApplication Supportの`FrameRelayLibrary`配下、探索は別runの領域を使う。実行時DB、原本、一時動画はソースツリー・Assets・Resourcesへ置かない。
- **ビルド設定**: 共有設定の現在の正本は`FrameRelay.xcodeproj/project.pbxproj`。iOS/Swift言語モード・既存target構成を維持する。CLIで確認済みのscheme/test planと、未配置の共有`.xcscheme`/`.xctestplan`を区別し、照会成功だけで共有ファイルを新設しない。
- **用途説明・Capabilities**: 現在は`GENERATE_INFOPLIST_FILE = YES`で、App target設定にカメラ・マイク・ローカルネットワーク用途説明がある。Photos追加と必要時読取の用途説明はAppのDebug/Releaseへ追加済み。独立したentitlements・Background Modesは未追加。生成Info.plistと独立ファイルを混同せず、今後必要な権限や背景設定は担当taskで確認し、ATS例外やApp Groups/iCloudを配置の都合で追加しない。
- **個人設定・生成物**: `.gitignore`は`xcuserdata/`、`*.xcuserstate`、`DerivedData/`、`.DS_Store`を除外する。個人のscheme管理plistは共有schemeの代わりにしない。build/test生成物を文書やアプリ資材に混ぜない。
- **秘密情報**: 登録資格は`Platform/Credentials/KeychainRegistrationVault.swift`で扱い、Swiftソース・pbxproj・fixture・文書・ログに記載しない。接続先入力・登録状態と資格の保管境界を分け、環境別の秘密値をソースへ埋め込まない。

## Docs・AIワークフロー

| 配置 | 責務・命名・扱い |
| --- | --- |
| `PROJECT_CONTEXT.md`、`AGENTS.md` | 技術前提とWorkflowの正本。アプリのソース/資材targetには含めない |
| `docs/` | 安定した要求・機能設計・architecture・本書・開発規則・用語集の6文書。`product-requirements.md`等の既定名を用い、PRDを要求更新先とする。開発規則は[development-guidelines.md](development-guidelines.md)、用語は[glossary.md](glossary.md)を参照する |
| `docs/ideas/` | `initial-requirements.md`はsetupのbootstrap入力。追加・変更仕様は`YYYYMMDD-[feature-name].md`でprepare-steeringの標準入力とする |
| `docs/decisions/` | 未作成。決定理由・代替・影響の記録を必要時に置く。ファイル名は`YYYYMMDD-[topic].md`とし、要求や計画の正本を重複させない |
| `.steering/[YYYYMMDD]-[task]/` | 撮影探索・連携・実機なし先行実装の3計画が存在する。`requirements.md`・`design.md`・`tasklist.md`が計画/進捗の正本。現行の進捗は`20260929-device-independent-implementation/`、旧計画は履歴と元の受入義務として保持 |
| 現行steeringの`support/`、`evidence/` | 隔離サーバー用overlay・試験runnerと、実行版/診断/結果・合成媒体等の試験証跡。製品Appの資材やMacサーバーの稼働配置ではない。S27のpublication支援にはbackend全230case/実HTTP1件、S28/BG01には別modeのmetadata-only実HTTP2要求/媒体0byteの版付き実行証拠がある。正式品質proof・本番公開の完成へ昇格せず、私的媒体・秘密は保存しない |
| `.agents/skills/` | 明示Workflowと専門Skillの`SKILL.md`、template、guide。製品実装を置かない |
| `.agents/workspaces/` | 現在は`.gitkeep`のみ。Workflowの補助作業領域として用い、仕様・永続文書・進捗の正本にしない |
| `.codex/config.toml`、`.codex/agents/` | agent設定。`document_author`等の役割設定を置き、Skill手順や製品コードの配置先と混同しない |
| `README.md` | リポジトリの入口。要求・技術・作業手順は各正本へリンクし重複定義しない |

Workflowの開始条件、専門agentへの所有範囲の指定、review/validationの読み取り専用規則は[AGENTS.md](../AGENTS.md)に従う。本書の配置計画だけで別Workflowや実装を開始しない。

現行supportの`server-implementation/backend-overlay/`は登録/保存/候補job/publicationの隔離実装、`server-isolation/prepare_publication_probe.py`・`run_publication_simulator_probe.py`・`publication_fixture_listener.py`は試験用準備/起動/HTTP支援である。iOS側入口は`FrameRelayTests/Integration/Remote/PublicationHTTPFixtureTests.swift`。実行版と観測はtasklist E-S27-01/E-S28-01/E-S34-BG01と各evidenceを参照し、S27旧実証拠を後続metadata試験で置換しない。旧M04の`evidence/20261020-m04/`も配置確認の履歴として保持する。

## 移行上の注意

1. 対象仕様とsteeringが用意された実装工程で、関係する責務から配置する。現状の`FrameRelayApp.swift`、`ContentView.swift`とアセットを入口にし、構造整理だけの一括移動はしない。
2. ソース追加/移動時はファイルシステム上の位置、Xcodeでの表示、同期グループ、target所属、資材参照を照合する。同期グループであることだけで誤ったtarget所属が起きないとはみなさない。
3. ロジックを先に必要なPort/Domainの責務へ割り当て、PlatformとPresentationの依存が逆転していないことを確認する。既存の共通store・原本・Ports・Compositionを拡張し、採用済み内部方式と未確認の実方式・品質を分けてarchitecture/steeringへ反映する。
4. build/test前に実在project・scheme・destination・テスト構成を確認する。製品接続、自動検証、実機確認、PRD受入を独立に記録する。確定した操作・背景/状態同期の要件や本人合意済み暫定policyを未合意へ戻さず、未接続・未実行・実機品質の残件をファイル配置だけで完了にしない。

人間が作成した既存Xcode projectを利用し、構造定義のためのproject/workspace生成、project generator、空のpackage、外部依存やMac用targetは追加しない。今回の変更は本書だけであり、コード移動、build/test、Simulator/実機起動、外部接続、動画の生成・転送・削除は行っていない。

構成と記述観点は[repository-structure Skill](../.agents/skills/repository-structure/SKILL.md)、[テンプレート](../.agents/skills/repository-structure/assets/template.md)、[ガイド](../.agents/skills/repository-structure/references/guide.md)に従う。
