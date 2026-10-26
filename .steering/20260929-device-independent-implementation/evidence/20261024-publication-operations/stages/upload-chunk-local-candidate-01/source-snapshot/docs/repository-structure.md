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

[FrameRelayApp.swift](../FrameRelay/FrameRelayApp.swift)が`@main`入口で、[ProductComposition.swift](../FrameRelay/Composition/ProductComposition.swift)を保持し、[ContentView.swift](../FrameRelay/ContentView.swift)からライブラリ、通常撮影、接続・登録、原本再生、別入口の探索画面を開く。起動時に製品storeを開くが、撮影権限要求・capture session準備は撮影入口まで遅らせる。Libraryは原本再生、既存の写真登録記録の表示と理由付き明示照合、本人リスク確認後の単数破棄/結果照合へ接続する。Connectionは既知原本の媒体なし明示状態同期と、別操作の保存原本catalog取得/続きを持ち、後者は同writer観測からLibraryのremote専用一覧へ接続する。別storeに束縛された有効v2接続情報が残る場合は、説明付きの別入力から明示新登録を開始する。条件付き複数容量整理を通常導線へ接続し、正式証拠producer・通常strict通信の未成立は残件として扱う。完全取得済みlocal軽量版はlocal/remote行から単数再生/本人確認へ接続する。完全local媒体の単数/固定複数写真保存consumerと、未接続の通常転送・未取得軽量版の取得/streaming/正式producerを分け、起動・一覧再読込みでPhotos権限を要求しない。

[project.pbxproj](../FrameRelay.xcodeproj/project.pbxproj)では、3つのソースルートがそれぞれ`PBXFileSystemSynchronizedRootGroup`として同名targetへ対応する。独立したルートの`.xcworkspace`はなく、上記workspaceはproject内部の構成。共有`.xcscheme`・`.xctestplan`・独立した`Info.plist`・entitlements・`Package.swift`・外部依存設定は配置されていない。CLI照会では実行可能なscheme/test plan `FrameRelay`を確認済みで、その証跡とrepo内の共有ファイルの有無、個人用scheme管理plistを区別する。build/test時は実在構成を再確認する。

### 主要な実装と接続状態

以下のApp相対パスはすべて`FrameRelay/`配下。実装済みの部分と通常の製品操作への接続は別に示す。

| 責務 | 主要実ファイル | 現在の境界 |
| --- | --- | --- |
| 共通store・原本・組立 | `Composition/ProductLibraryFactory.swift`、`Platform/LocalStore/ExplorationRecordingStores.swift`、`RecordingStoreDocument.swift`、`Platform/OriginalStore/ManagedOriginalStore.swift`、`ManagedOriginalAccess.swift` | 製品rootのCore Data/SQLiteによる`SQLiteRecordingStore`、schema 7の同writer/journal、原本領域、内容対応・read leaseを共有。`Exploration`という既存名だけで探索専用と判断しない |
| 撮影・補助表示 | `Composition/ProductCaptureFactory.swift`、`Application/Capture/ProductCaptureCoordinator.swift`、`Platform/Capture/NativeExplorationCapture.swift`、`Features/Capture/ProductCaptureView.swift` | 通常の設定・REC/保存・WB・音声・補正・人物/ND・ズームへ接続。S49のREC/保存境界は下記の共通通信担当へ渡す。レンズISO policyの通常注入は保留。実方式・能力・品質は実機未確認 |
| 一覧・原本再生 | `Application/Library/LibraryStoreReader.swift`、`LibrarySnapshot.swift`、`Features/Library/LibraryModel.swift`、`Features/Playback/OriginalPlaybackModel.swift`、`Platform/Playback/AVOriginalPlayback.swift` | 単一storeから一覧/履歴を投影し、原本再生・既存写真記録の明示照合・単数破棄・条件付き複数容量整理を接続。整理候補の表示と削除直前の権限再判定を分け、状態同期後も同じ読取担当から動画別に表示する。保存原本catalogは`remoteItems`へ別投影し、ローカル保存記録/原本参照/履歴を作らない。完全local媒体の写真保存は下記consumerの範囲とし、正式証拠/通常取得producerは未接続 |
| 写真登録・存在照合 | `Platform/Photos/NativePhotoLibrary.swift`、`Application/MediaOperations/PhotoSaveCoordinator.swift`、`PhotoRegistrationReconciler.swift`、`Application/Library/LibraryPhotoReconciliation.swift` | 実SDK追加・同writerへの意図/結果/終端証拠保存・完全取得媒体の受渡し、過去結果/現在存在の表示と明示照合。終端後は結果と独立して元photo useを解放し、復元/owner閉鎖を失効時の全reader解放へ接続する。完全local媒体の固定複数consumerと分け、正式Rec.709媒体の通常取得producerは未接続 |
| local軽量版の写真保存batch | `Domain/Media/PhotoSaveBatch.swift`、`Platform/LocalStore/PhotoSaveBatchStoreProjection.swift`、`Application/Ports/PhotoSaveBatchPorts.swift` | 同schema 7 journalの親操作・固定source/子operationとqueued/starting/notProcessedを持ち、結果は既存Photo記録へexact joinする。同PhotoKeyをqueued/startingと単独登録間でも予約する。元mutation/receiptを照合し、別の成功状態やSDK再実行の許可を作らない |
| local軽量版の写真保存consumer | `Application/MediaOperations/PhotoSaveBatchCoordinator.swift`、`Composition/ProductPhotoSaveBatch.swift`、`Platform/Network/NativePhotoStartNetwork.swift`、`Application/Ports/LibraryPhotoSavePort.swift`、`Application/Library/LibraryPhotoSaveCommands.swift` | local/remote行の写真用固定選択、初回Wi-Fi受付、受理済local段階、capture holdと再起動時の明示continue/cancelを同じComposition/writerへ接続。`ProductRenditionFactory.photoSource/preparePhoto`は共有owner/registryから直接photo使用権を渡し、known-not-addedだけ既存coordinatorのretryでfresh useを一度得る。本人batch照合/続行のrestoreは既存live cacheだけを使い、新ownerやSDK追加を作らない。正式媒体の通常取得producer・旧unknown useの採用/回収と、接続/必要検証の結果を分ける |
| Photos最終SDK開始境界 | [Application/Ports/PhotoSaveStartPorts.swift](../FrameRelay/Application/Ports/PhotoSaveStartPorts.swift)、[Application/MediaOperations/PhotoSaveDispatchClaims.swift](../FrameRelay/Application/MediaOperations/PhotoSaveDispatchClaims.swift)、[Platform/LocalStore/PhotoSaveStartStoreBoundary.swift](../FrameRelay/Platform/LocalStore/PhotoSaveStartStoreBoundary.swift) | writer→capture→process共有claim→同期performChanges登録を型付きで渡す。全hash後の保持FD/dir FDを借用するwitnessと最終stat、実intent/receipt・現登録/版/使用権/epochを同writerで照合する。`ProductRenditionFactory`には同background factoryのcapture admissionを注入し、Native旧add/default guardedは拒否する。heldは同intent/use/FD/Taskを保持しlock外wakeで再判定、取消は固定live子のpreSDKだけ、受理後は実completionを待つ。別coordinatorの二重SDK/結果/終端/解放を防ぎ、再openの既存intentは開始許可にしない。物理原本なしの正当cached Photosを許容し、全媒体/strict送信・正式producer/実機品質の残件を分ける。実行版ごとの検証状況・未実施/失敗を含む記録は現行tasklistと証跡を参照する |
| PhotosとREC前のlocal終端 | `Composition/ProductCaptureMediaBoundary.swift`、`ProductRenditionFactory.swift`、`Application/MediaOperations/PhotoSaveBatchCoordinator.swift`、`PhotoSaveCoordinator.swift` | 同capture hold後、既知prepare/live子のpreSDK取消/wakeと受理済み処理をjoinし、fresh UUID/revision/registry世代/現REC owner・exact終端/use release・FD witness失効/reader不在を照合する。本人のbatch取消へ置換せず、Photos/背景の両readyを要求する。STOP/leaveでcallerを取り消しても内部joinは保持する。外部結果unknownとlocal証拠unknownを分け、UUID nil/no Photosの正常rootでは非破壊のfresh照合だけでreadyとする。実行版ごとの検証状況・未実施/失敗を含む記録は現行tasklistと証跡を参照する |
| 接続・登録 | `Application/MediaOperations/RegistrationCoordinator.swift`、`Platform/Remote/URLSessionRegistrationRemote.swift`、`Platform/Credentials/KeychainRegistrationVault.swift`、`Features/Connection/ConnectionModel.swift` | 製品store・資格保管・登録画面へ接続。有効な別storeのv2 connectionに対する明示新登録開始は、現在UUIDの永続確定→別namespaceのcreate-only追加→同writer登録意図へ渡す。通常の復元/続行ではforeign bindingを採用せず、同store中断を維持。既知原本の状態同期・保存原本catalog/manifest観測の部分接続と、正式proof/通常媒体の残件、通常HTTPS/新namespace資格情報の実SDK受渡し・UI等の必要検証、再登録全体・実機受入を別substatusにする |
| 媒体なし状態同期 | `Application/MediaOperations/BackendStatusSynchronizationCoordinator.swift`、`Application/Ports/StatusSynchronizationPort.swift`、`Composition/ProductStatusSynchronization.swift` | S28の現登録に対する明示1page/manifest同期と続き、元mutation/旧outboxのexact照合→同writer→動画別表示を接続。対象はlocalの論理原本と同store UUID/現登録のcommit済みcatalogから固定する。未解決失効とcursorを分け、再openはnullから照合。新確認/媒体開始を生成せず、終端を照合できない背景履歴/未知ownerの対象ACKは保留 |
| 背景upload終端と通常失効 | `Application/Ports/BackgroundInvalidationPorts.swift`、`Application/MediaIO/BackgroundMediaCoordinator.swift`、`Composition/ProductBackgroundMediaFactory.swift`、`ProductStatusSynchronization.swift` | 同appの背景ownerを実失効予約/store UUID/現在epoch/登録へ束縛して渡す。既知live uploadの停止pollはACKなし、後の明示pollで実terminal/自身source閉鎖/ownerClosed/lease不在/stoppedとfresh SDK inventory・対象全journalを照合し、既存media終端/ACKへ接続。新しい観測値はsealを持たず、removalの実seal/fenceを置き換えない。閉鎖済旧履歴の観測と旧未閉鎖sourceの採用を分け、正native開始/全媒体の成立にはしない |
| 公開manifestの観測・投影 | `Domain/Media/PublicationManifestObservation.swift`、`Platform/LocalStore/PublicationManifestStoreProjection.swift`、`Application/Library/LibrarySnapshot.swift`の`LibraryPublicationProjection` | `PublicationManifest`をCodable値として定義し、未公開を含む全metadataを`.publicationManifest`で同schema 7 journalへ保存する。既存`.publication`の確認authority/失効guardと分け、unknownは元mutationを照合する。local一覧/詳細とremote一覧へ版ID/世代・形式・置換待ち・部分/完全取得記録/実媒体未照合を投影し、正式proof・媒体取得/再生・確認の成立にはしない |
| 保存原本catalog | `Domain/Media/RemoteInventory.swift`、`Application/Ports/RemoteInventoryPorts.swift`、`Application/MediaOperations/RemoteInventoryCoordinator.swift`、`Platform/Remote/RemoteInventoryWire.swift`、`URLSessionRemoteInventoryRemote.swift`、`Platform/LocalStore/RemoteInventoryStoreProjection.swift` | 現登録で同destinationの保存完了/evidence対応identityを有界に取得し、元cursor/store UUID/登録/command/pageを同schema 7 journalへ観測加算。unknown commitはexact lookupまで続きを止める。通常Connection→同Composition vault/writer→Library refreshを接続し、custom登録factoryへ製品Keychainを暗黙付与しない。日時不明・同capture別内容/local衝突・現在存在未照合を保持し、保存検証/正式版/確認/ACK/媒体を生成しない。接続と必要検証は現行tasklistで分ける |
| 背景session・task・復帰 | `Application/MediaIO/BackgroundMediaCoordinator.swift`、`Application/Recovery/BackgroundMediaRecovery.swift`、`Composition/ProductBackgroundMediaFactory.swift`、`ProductBackgroundEventRouter.swift`、`Platform/Network/BackgroundMediaSession.swift` | S23のOS session/taskと固定contextの永続対応、直列delegateからのevent drain、App delegate配送を同じ製品writerへ接続。通常strict開始/resume・安全なdownload受入口・旧未閉鎖source所有採用は未接続、全媒体producerの接続は未完 |
| 通信依頼の本人操作 | [Domain/Operations/MediaPersonControl.swift](../FrameRelay/Domain/Operations/MediaPersonControl.swift)、[Application/Ports/MediaRequestControlPort.swift](../FrameRelay/Application/Ports/MediaRequestControlPort.swift)、[Platform/LocalStore/MediaPersonControlStoreProjection.swift](../FrameRelay/Platform/LocalStore/MediaPersonControlStoreProjection.swift)、[Application/Library/LibraryMediaRequestCommands.swift](../FrameRelay/Application/Library/LibraryMediaRequestCommands.swift) | 単数停止/取消・停止解除の意思と固定全件停止を同schema 7 journalへ加算し、`BackendStoreSnapshot.personControls`から子別の記録/未処理理由を復元する。Library読取/model/viewと共通Compositionから背景factoryへ接続し、同processのexact ownerだけへ停止を要求する。再openの照合からSDK停止を再発行せず、意思記録・実停止/資源解放を分ける。対象は`backend.requests`で、local player/Photos・通常strict開始/正resume・全媒体の成立とは分ける |
| 原本転送の固定queued受付record | [Domain/Operations/OriginalUploadAcceptance.swift](../FrameRelay/Domain/Operations/OriginalUploadAcceptance.swift)、[Application/Ports/OriginalUploadAcceptancePort.swift](../FrameRelay/Application/Ports/OriginalUploadAcceptancePort.swift)、[Platform/LocalStore/OriginalUploadAcceptanceStoreProjection.swift](../FrameRelay/Platform/LocalStore/OriginalUploadAcceptanceStoreProjection.swift) | 同schema 7へ`.originalUploadAcceptance(plan)`を加算し、`BackendStoreSnapshot.originalUploadAcceptances`に固定全集合・未処理を含む全子ID・初期判断/request・実receiptを不変に保持する。現在requestsは別joinし、legacy batch/借用receiptを作らない。新command導入IDとの双方向保護と削除inventoryを同writerへ追加し、旧replay/epochの別軸/削除fenceを維持する |
| 原本転送の固定queued受付導線 | [Application/Library/LibraryTransferCommands.swift](../FrameRelay/Application/Library/LibraryTransferCommands.swift)、[Application/MediaOperations/OriginalUploadAcceptanceCoordinator.swift](../FrameRelay/Application/MediaOperations/OriginalUploadAcceptanceCoordinator.swift)、[Composition/ProductOriginalUploadAcceptance.swift](../FrameRelay/Composition/ProductOriginalUploadAcceptance.swift)、[Platform/Network/NativeUploadStartNetwork.swift](../FrameRelay/Platform/Network/NativeUploadStartNetwork.swift) | 同revisionのLibrary snapshotから現登録/UUID・選択binding/保存commit・親/全子をawait前に固定し、詳細単数/既存複数transferをtyped Portへ渡す。初期Wi-Fi・短命stat観測→同writer最終再判定→子別queued/未処理とし、unknownは元envelopeのexact lookupへ戻す。known commit後に同background factoryの`synchronizeCapture`で待機を投影する。新registry/認証/remote/source/SDK開始を持たない受付契約で、実行版・必要検証とmetadata session producer/実送信・正式proof/全S28を分ける |
| upload metadataのquery/観測 | [Domain/Operations/UploadMetadata.swift](../FrameRelay/Domain/Operations/UploadMetadata.swift)、[Application/Ports/UploadMetadataPorts.swift](../FrameRelay/Application/Ports/UploadMetadataPorts.swift)、[Platform/LocalStore/UploadMetadataStoreProjection.swift](../FrameRelay/Platform/LocalStore/UploadMetadataStoreProjection.swift) | 同schema 7のbegin/observeに通信前の単調世代予約、最新query/実begin receipt・UUID・全応答fingerprintを束縛する。beginで旧許可を失効し、最新のexact observeだけでpendingを解除する。完全8項目のfinal-read証拠を同writerの新実receipt/typed provenanceから既存保存検証へ接続し、偽verification receiptを作らずnil provenance/旧encodeを維持。namespace/削除inventory・旧replay/fenceを保つ |
| upload metadataの明示操作・wire | [Application/Library/LibraryUploadMetadataCommands.swift](../FrameRelay/Application/Library/LibraryUploadMetadataCommands.swift)、[Application/MediaOperations/UploadMetadataCoordinator.swift](../FrameRelay/Application/MediaOperations/UploadMetadataCoordinator.swift)、[Composition/ProductUploadMetadata.swift](../FrameRelay/Composition/ProductUploadMetadata.swift)、[Platform/Remote/UploadMetadataJSON.swift](../FrameRelay/Platform/Remote/UploadMetadataJSON.swift)、[UploadMetadataWire.swift](../FrameRelay/Platform/Remote/UploadMetadataWire.swift)、[URLSessionUploadMetadataRemote.swift](../FrameRelay/Platform/Remote/URLSessionUploadMetadataRemote.swift) | 依頼別明示操作/既知session GET-only同期と、HTTPを追加しない元envelope照合を分ける。constructor/再launchはHTTPを始めず、POST session確立をstatus/送信/検証へ昇格しない。`MediaOperationStorePort.performUploadMetadataIfCurrent`と`ExplorationRecordingStores.swift`の同writer同期callbackでsuspended metadata taskを直接resumeし、同ownerの保持Taskへ合流する。current namespaceの資格情報は読取り専用でcustom factoryへfallbackせず、旧JSONのnumber拒否/新parserのindices限定整数を保つ。code/tests・実HTTPの実行結果は未確定で、chunk送信/strict媒体の正開始・全producer/品質・実機の完成と分ける |
| REC/保存と通信の境界 | `Application/MediaIO/CaptureMediaAdmission.swift`、`Application/Ports/CaptureMediaBoundaryPort.swift`、`Composition/ProductCaptureMediaBoundary.swift` | S49のowner別REC/save/recovery hold、token前の取消可能preflight、exact local stopと保存file実returnまでの待機を通常撮影へ接続。同ファイルの`CaptureMediaResumeAuthorization`は元admission/revisionに束縛した単回同期許可で、coordinatorからasync SDK portへ渡しactual action直前に消費する契約。nativeの正のresume・全媒体実停止の成立とは分ける |
| 容量整理・破棄 | `Application/MediaOperations/CleanupCoordinator.swift`、`DiscardCoordinator.swift`、`Application/Library/LibraryRemovalCommands.swift`、`Composition/ProductRemovalTermination.swift` | S32/S33の目的別coreとS34通常単数破棄・条件付き複数容量整理を同じCompositionへ接続。全historical uploadの実終端/自身source FD閉鎖/ownerClosed/exact lease解放を照合し、容量整理固有の保存検証/有効確認は別途再判定する。固定集合と動画別の成功/未実行/要照合を保持し、整理成功は通常一覧、破棄成功は履歴へ投影。正式証拠producer・未取得媒体のPhotos保存・全S34/実機受入とは区別 |
| 固定軽量版・一時媒体 | `Platform/Playback/AVRenditionPlayback.swift`、`Platform/Network/FixedRenditionRangeReader.swift`、`Platform/TemporaryMedia/ManagedTemporaryMedia.swift`、`Application/MediaIO/RenditionScopeRegistry.swift` | 固定版の実再生・取得・lease/一時媒体管理の下位実装。完全取得済みlocal枝は下記の製品factoryを通し、通常ネット取得/streamingは未接続。画面の自use解放、scope全停止、コピー本体の回収を分け、旧unknown useやunknown/failed/notAttemptedの写真コピーを保持する |
| local軽量版の製品消費側 | `Application/Ports/LibraryRenditionPorts.swift`、`Application/Library/LocalRenditionSelection.swift`、`RenditionPlaybackLibraryCommands.swift`、`Composition/ProductRenditionFactory.swift`、`Features/Playback/RenditionPlaybackModel.swift`、`RenditionPlaybackView.swift` | 現store/登録/版・exact論理原本・同writerの正の配布記録と完全coverage/hashを再判定し、既存root/lock/inode・全内容照合後にlocal/remote単数再生へ渡す。app lifetime owner/open合流と共有registry、await前の原本/軽量版共通予約、実進行tokenから同画面の本人確認を接続。閉鎖/再起動でtokenを消去し、unknownは同token/action照合。ネット開始や正式producerの成立にはしない |
| 確認・失効・公開の周辺 | `Application/MediaOperations/MediaConfirmationCoordinator.swift`、`MediaInvalidationCoordinator.swift`、`BackendOutboxCoordinator.swift`、`Composition/ProductMediaTermination.swift`、`Platform/Remote/PublicationWire.swift` | S27の固定版/登録別失効・全必要ACKと製品rootの原本player/同writerを共有する終端窓口。S28へ失効/outboxを接続するが、正式proof・全製品owner・通常取得/streaming/公開の完成とは区別する |
| 表示描画 | `Platform/Render/CaptureDisplayTransform.swift`、`CaptureDisplayRenderer.swift`、`CaptureDisplayPipeline.swift` | 生成cubeを使うencoded-BGRA技術描画。標準資材未取得、実Log変換・通常capture/UI接続は未実装 |
| 探索 | `Composition/ExplorationComposition.swift`、`Application/Capture/ExplorationCoordinator.swift`、`Features/Capture/ExplorationView.swift` | 試験票・方式候補・試験runを持つ独立入口。探索条件や結果を製品採用へ昇格しない |

未作成領域は`Shared/Presentation/`、`Platform/Analysis/`、`Resources/`等。現在の人物/ND解析は`Platform/Capture/`内、表示状態の試験は`FrameRelayTests/Application/`等にあり、配置計画だけを理由に移動しない。未取得媒体からの写真保存producer、条件付き複数整理の正式証拠producer、通常strict開始/resume・全媒体producer、正式Log/標準Rec.709資材・品質proof、再登録全体は今後の担当taskへ残す。接続と必要検証の実行版・結果は現行tasklistへ記録し、既存のgate契約・純粋規則・本人意思の永続化や実削除coreを未実装へ戻さない。

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
| `Features/Playback/` | V4。`OriginalPlaybackModel/View`の原本再生と、`RenditionPlaybackModel/View`の完全取得済みlocal軽量版の単数再生/本人確認。長文本文と固定footerを分け、全12文字サイズを扱う | 再生だけで確認を確定せず、同画面の実進行tokenへの本人操作だけを確認担当へ渡す。写真保存は別操作・状態。独自の動画取得はしない | `FrameRelayTests/Integration/Playback/`、`Application/RenditionPlaybackModelTests.swift`、`FrameRelayUITests/Flows/LibraryFlowTests.swift`、`LocalRenditionFlowTests.swift` |
| `Features/Connection/` | V6。`ConnectionModel`と`ConnectionView`による接続先・登録・照合と、既知原本の明示状態同期/続き・動画別撮影日時と保存事実の表示。保存原本catalogは別の明示ボタン/続きから取得しLibraryを更新 | 指示済み順番待ちと未指示を区別し、秘密情報の保管や通信再開条件を所有しない。起動/登録復元だけで同期やcatalog取得を開始しない | `FrameRelayTests/Integration/Registration/`、`Integration/Remote/RemoteInventoryTests.swift`、`FrameRelayUITests/Flows/ConnectionFlowTests.swift` |
| `Shared/Presentation/`（未作成） | 複数画面で実際に共有する表示部品、表示専用の値整形、アクセシビリティ表現 | 特定featureの内部型、共有セッション、汎用の巨大な状態オブジェクトは置かない。値とactionを受ける部品が入口 | 必要時に責務に対応する試験を配置 |

撮影固有の音量表示や構図表示は、再利用箇所がない段階ではCapture内に置く。共有の製品規則は`Shared/`へ集めずDomainへ、共有のI/O契約はApplicationのPortsへ配置する。

### Application・Domain

すべて`FrameRelay` targetに所属し、テストは`FrameRelayTests/`の同じ層・責務名へ対応させる。

| 配置 | 責務・配置するもの | 公開入口・配置しないもの |
| --- | --- | --- |
| `Application/Capture/` | `ProductCaptureCoordinator`、`CaptureLifecycle`、`RecordingSaveLifecycle`、`ProductCapturePostSave`による設定・REC/STOP・WB/音声・解析採否・ズーム・保存後処理 | `prepare/apply/start/stop`等のcommandと型付きsnapshot/event。View・端末API実装は置かない |
| `Application/MediaOperations/` | 登録、確認/失効、outbox、`BackendStatusSynchronizationCoordinator`、`RemoteInventoryCoordinator`、`PhotoSaveCoordinator`・`PhotoRegistrationReconciler`、`CleanupCoordinator`・`DiscardCoordinator`。開始時の固定対象集合と動画別の操作/証拠/結果を調停 | 目的別commandと操作ID・理由付き結果/未処理。容量整理と破棄の入口を分ける。DB/HTTP/Photos/ファイルAPIは置かない |
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
| `LocalStore/` | 撮影/原本/操作/確認・失効等の単一writerとschema/migration、設定保存。`PhotoStoreProjection.swift`は同じschema7 journalから写真登録/終端/元use解放を投影し、登録結果によるコピー保持を判定。`BackgroundMediaStoreProjection.swift`・`OriginalRemovalStoreProjection.swift`も同journalから背景task/削除意図・結果を投影する。`RemoteInventoryStoreProjection.swift`は現store/登録へ束縛したcatalog観測だけを加算する。Core Data/SQLiteのmodelは`ExplorationRecordingStores.swift`内で組み立てる | 動画本体、表示状態の正本化、feature専用の重複DB。独立した`.xcdatamodeld`は使っていない |
| `OriginalStore/`、`TemporaryMedia/` | 原本の予約・固定参照・同FD内容検査/read lease、同writerの最新条件照合→MOVのみ実unlink→結果最終照合。`ManagedUploadSource`は原本leaseから実copy/全hash/出力FD読戻しを行い、exact SDK終端後に自身の保持FDを閉鎖。`ManagedTemporaryMedia`は一時ファイル/使用量/解放を管理し、完全取得媒体は`TemporaryLocalMediaPort`から扱う。写真用はexact終端または旧成功証拠による元use解放と、登録成功かつ全使用権解放後の実unlinkを分ける | 独自の削除許可、外部パス/Photos/Mac miniの削除、原本の自動回収。自身のsource FD閉鎖をSDK所有全FDの閉鎖へ広げない。使用中の媒体や復旧証拠を無断回収せず、unknown/failed/notAttemptedの登録用コピーを保持。部分バッファをPhotos登録用の完全ファイルとしない |
| `Remote/`、`Network/` | 登録・publication・保存原本catalogのwire/HTTP adapter、固定版Range通信、`BackgroundMediaSession`の直列delegate/型付きevent。catalogは既存metadata SDKのredirect拒否/応答量制限/completion・invalidation待ちを使う。原本/変換版/映像IDと配信内容の対応を固定し、OS sessionとMac側upload sessionを区別する | サーバー本体、撮影制御、旧削除候補フラグの直接利用。具体的な契約実装と、通常strict開始/resume・全媒体の製品接続・実機成立を区別する |
| `Playback/`、`Photos/` | `AVOriginalPlayback`・`AVRenditionPlayback`とresource loaderによる実再生/停止。`Photos/NativePhotoLibrary.swift`は実PhotoKit追加/完了と保存済み識別情報だけの照合 | 確認の自動確定、独自の通信経路、写真削除。取得と一時参照は注入されたPortを利用し、streaming再生とPhotos登録を分離 |
| `Credentials/`、`Diagnostics/` | 認証保管adapter、最小限の診断出力 | 接続秘密や家族動画をソース/ログへ保存しない。診断ログを復旧証拠の代わりにしない |

Mac miniの変換器・サーバー・保存ディレクトリがこのrepoにあるとは扱わない。iOS側の契約はPortsとRemoteへ置き、サーバー側の配置・変更は既存MediaVaultの調査と合意した作業範囲で定める。`backend/`やMac用targetを本書だけを根拠に作らない。

### テスト領域

| 配置 | 所属target・方式 | 配置対象・入口 |
| --- | --- | --- |
| `FrameRelayTests/Domain/`、`Application/` | `FrameRelayTests`、Swift Testing | 純粋規則、固定対象集合と動画別結果、条件付き自動再開、Portへの失敗/遅延/逆順注入、表示投影と入力。`@Test`を入口とし`@testable import FrameRelay`で参照。独立した`Presentation/`は未作成 |
| `FrameRelayTests/Platform/`、`Integration/` | 同上 | adapter契約、使い捨てのdiskストア/ファイルを用いた復旧・削除照合、制御可能な通信先との契約。実環境の実行条件は計画で区別 |
| `FrameRelayTests/Integration/Photos/` | 同上 | `PhotoSaveCoordinatorTests`、`PhotoTemporaryRecoveryTests`・`PhotoTerminalRecoveryTests`と`PhotoSaveFixture`。結果と終端の独立commit・元use解放・コピー保持を試験する。`NativePhotoLibraryTests`は明示opt-inの専用Simulator実Photos試験。値検証は`Domain/PhotoRegistrationTests.swift`、同writer再openは`Integration/Storage/PhotoRegistrationStoreTests.swift` |
| [PhotoSaveFinalStartTests.swift](../FrameRelayTests/Integration/Photos/PhotoSaveFinalStartTests.swift)、[PhotoSaveFinalStoreDriftTests.swift](../FrameRelayTests/Integration/Photos/PhotoSaveFinalStoreDriftTests.swift)、[ProductPhotoCaptureStopTests.swift](../FrameRelayTests/Integration/Composition/ProductPhotoCaptureStopTests.swift) | `FrameRelayTests`、Swift Testing | 最終writer/全hash後FD・名前・型/UTF8 drift、共有claim/held取消、実action後writer falseでもcompletionを待つ境界、REC前join・local証拠unknown・UUID nil/no Photos・旧owner/STOP/leaveを定義する。Native opt-in試験と制御試験を分け、実行版ごとの検証状況・未実施/失敗を含む記録は現行tasklistと証跡を参照する。定義や部分実行を全媒体停止・strict送信・正式producer/実機品質の成功にしない |
| `FrameRelayTests/Domain/PhotoSaveBatchTests.swift`、`Integration/Storage/PhotoSaveBatchStoreTests.swift`、`Application/PhotoSaveBatchCoordinatorTests.swift`、`Application/LibraryPhotoSaveTests.swift`、`Integration/Composition/ProductPhotoSaveBatchTests.swift` | 同上 | 固定source/親子ID・PhotoKey予約・既存Photos結果join、同writer再open/元mutation、初回受付条件、capture待機とlock外wake、本人continue/cancel/retry、local/remote選択を対象とする。`Support/ProductPhotoSaveBatchFixture.swift`の新規専用合成cache/注入回線とnative PhotoKitの検証を分け、定義だけで成功にしない。必要検証の実行版/結果は現行tasklistを参照する |
| [ProductPhotoSaveBatchSeedTests.swift](../FrameRelayTests/Integration/Composition/ProductPhotoSaveBatchSeedTests.swift)、[PhotoSaveBatchFlowTests.swift](../FrameRelayUITests/Flows/PhotoSaveBatchFlowTests.swift) | Unit補助 / UI・XCTest | read-onlyの実Photos baseline INSPECT→新規専用rootの一回SEED→UI→VERIFYを分離する。通常は未受付sourceから通常Appのnative Wi-Fi gateで単数/混合集合を新規手動要求し、最大文字は注入Wi-Fi/capture holdで受付済みのqueuedを本人が明示続行する別entryとする。Photos resourceのhash/日時/音声と、原本・Keychain・reader・一時媒体を照合する。定義と成否は分け、結果は現行tasklistを参照する |
| `FrameRelayTests/Integration/Registration/` | 同上 | `NewStoreKeychainTests`・`NewStoreRegistrationTests`は専用Keychain service/使い捨てstoreと制御したremote境界を用い、foreign採用拒否・明示新登録・現在UUID/namespace・旧global byte列保持・不明/中断を試験する。通常HTTPS/新規UIと、別試験の保存原本catalog結合・実機受入を区別し、結果は現行tasklistへ記録する |
| `FrameRelayTests/Integration/Remote/RemoteInventoryTests.swift`、`RemoteInventoryHTTPFixtureTests.swift`、`Integration/Storage/RemoteInventoryStoreTests.swift` | 同上 | strict wire/opaque bytes/UInt64、明示page/循環cursor、unknown commitのexact lookup、登録/store置換、共通Composition/資格情報の注入境界、同writer再open・空/重複・同capture衝突と実原本保持を試験する。HTTP fixtureは明示opt-inの新登録namespace→実SDK metadata→再open用で、定義と実行成功を分ける。専用UI/AX・全Unit等を含む必要検証は現行tasklistへ記録する |
| `FrameRelayTests/Integration/Publication/PhotoInvalidationBoundaryTests.swift` | 同上 | 実MOV・実disk・実`ProductMediaTermination`を用い、Photos終端順序のfixtureと失効時の全reader解放を接続する境界試験。実PhotoKit completionや通常保存producer・実機品質の成立とは区別 |
| `FrameRelayTests/Integration/OriginalRemovalIntegrationTests.swift`、`DiscardIntegrationTests.swift`、`OriginalRemovalTransportFenceTests.swift`、`OriginalCleanupTransportFenceTests.swift` | 同上 | S32/S33の両store・同FD全hash/実MOV unlink・中断/再open・観測だけの復旧と、全task receipt/inventory最終照合の境界。容量整理固有の証拠とhash/最終writer間の変更も試験対象。`Support/OriginalRemovalFixture.swift`を用い、外部媒体/管理記録・旧CASを保持する |
| `FrameRelayTests/Integration/Remote/`、`Integration/Storage/` | 同上 | `BackgroundMediaSessionTests`・`BackgroundEventDrainTests`・`BackgroundMediaStoreTests`・`ManagedUploadSourceTests`がOS task対応/event drain/copyと自身のFD閉鎖を試験。`BackgroundCaptureResumeTests`はcoordinator最終許可発行後のhold/ABAとSDK側の注入action直前の同期消費を試験する。`BackgroundRemovalTerminalTests`は実suspended→resume拒否→cancel callback→exact lease/stopped→通常model破棄/再openを確認する。strict permit/Mac notExecutedやdispatch actionは注入で、正の実SDK resume・通常実通信/SDK全FDの証拠ではない |
| `FrameRelayTests/Integration/Composition/`、`Application/ProductCaptureMediaBoundaryTests.swift`、`Application/ProductCapturePostSaveTests.swift`、`Application/CaptureMediaResumeAuthorizationTests.swift` | 同上 | `ProductBackgroundCompositionTests`は共通writer/REC境界、Applicationの試験はowner別hold/preflight・保存通知と次REC、および単回同期許可のorigin/消費/throw/hold/ABA・実Thread競合を扱う。`ProductRemovalCompositionTests`・`ProductHistoricalRemovalTests`は通常単数破棄/終端履歴、`ProductCleanupCompositionTests`は条件付き複数整理/固定集合/混在結果/終端子の独立解放、`ProductStatusSynchronizationTests`は既存登録の明示同期/動画別表示を試験する。seed補助と通常起動を区別する |
| [MediaPersonControlTests.swift](../FrameRelayTests/Domain/MediaPersonControlTests.swift)、[MediaPersonControlStoreTests.swift](../FrameRelayTests/Integration/Storage/MediaPersonControlStoreTests.swift)、[ProductMediaRequestControlTests.swift](../FrameRelayTests/Integration/Composition/ProductMediaRequestControlTests.swift)、[LibraryMediaRequestControlTests.swift](../FrameRelayTests/Application/LibraryMediaRequestControlTests.swift)、[ProductMediaRequestControlSeedTests.swift](../FrameRelayTests/Integration/Composition/ProductMediaRequestControlSeedTests.swift)、[MediaRequestControlFlowTests.swift](../FrameRelayUITests/Flows/MediaRequestControlFlowTests.swift) | 同上 | 親子namespace/固定対象・同writerの原子的な意思/子理由投影・履歴順replay/再open・元mutation不明・CAS競合と、exact背景ownerへの停止要求、通常Library投影を対象とする。SDKへの停止要求と実terminal/自身FD閉鎖/使用権解放の証拠を分ける。新規専用の通常/MAX 2環境向けに、一回限りの合成seed、native UIでの本人操作・履歴再open、実writerの`VERIFY`を定義する（未実行）。seedはmain供給の合成MOVをコピーし、Photos/Keychain/network/SDKを呼ばず、App起動flagの追加や既存fixtureの再seed/修復/削除を行わない。定義だけで成功や正native resume・全媒体の完成にせず、必要検証/専用fixtureの実行版と結果は現行tasklistを参照する |
| [ProductOriginalUploadAcceptanceSeedTests.swift](../FrameRelayTests/Integration/Composition/ProductOriginalUploadAcceptanceSeedTests.swift)、[OriginalUploadAcceptanceFlowTests.swift](../FrameRelayUITests/Flows/OriginalUploadAcceptanceFlowTests.swift) | Unit補助 / UI・XCTest | 新規専用rootの一回合成SEED、通常Appの単数/固定複数受付・再open/明示照合と通常/最大文字の厳格AX、実writerの`VERIFY`を定義する。通常AppのlaunchArguments/launchEnvironmentは空、資格情報seedなしとし、missing子の原本は最初から未作成で削除による再現をしない。既存P2制約を保持し、実行結果は未確定として現行tasklistへ記録する。確認対象はqueued受付までとし、実送信/SDK正開始の証拠にしない |
| [UploadMetadataTests.swift](../FrameRelayTests/Domain/UploadMetadataTests.swift)、[UploadMetadataStoreTests.swift](../FrameRelayTests/Integration/Storage/UploadMetadataStoreTests.swift)、[UploadMetadataCoordinatorTests.swift](../FrameRelayTests/Application/UploadMetadataCoordinatorTests.swift) | `FrameRelayTests`、Swift Testing | query/全応答payload・新実receipt/provenance、通信前世代予約・最新応答/overflow・pending許可失効、同writer観測/元mutation照合・旧authority/encode、同依頼Task合流・本人意思/待機保持との境界を対象とする。metadataのcode/testsは実行結果未確定で、実HTTP成功・媒体送信/SDK正開始の証拠にしない。実行版と必要検証の結果は現行tasklistへ記録する |
| `FrameRelayTests/Application/BackendStatusSynchronizationCoordinatorTests.swift`、`Integration/Storage/StatusSynchronizationStoreTests.swift` | 同上 | S28の1page/続き・未解決失効とcursorの分離・元mutation/旧outbox・exact登録/store・同writer/再openを確認。終端未照合の背景履歴/未知ownerへのACK保留、新確認/媒体開始なしを維持する |
| `FrameRelayTests/Application/BackgroundInvalidationTests.swift`、`Integration/Composition/ProductBackgroundInvalidationTests.swift`、`Integration/Remote/BackgroundInvalidationTerminalTests.swift` | 同上 | 既知live uploadの新失効stop分岐、最初のpoll ACKなし、後のfresh inventory/journalと通常状態同期/再openを対象とする。SDK probeは専用新rootのsuspended task/native resume拒否後に既存stop経路の実cancel callback・自身FD閉鎖/lease解放から失効へ結ぶ範囲とし、新失効stop分岐のnative cancel発行や正の送信開始の証拠にしない。定義と実行結果は現行tasklistで分ける |
| `FrameRelayTests/Application/PublicationManifestSynchronizationTests.swift`、`LibraryPublicationProjectionTests.swift`、`Integration/Storage/PublicationManifestStoreTests.swift` | 同上 | catalog由来既知集合、nil/版/置換待ち・世代、退行/矛盾、元mutation、同writer再openとmetadata/確認authorityの分離を試験する。`Integration/Composition/ProductPublicationSeedTests.swift`と`FrameRelayUITests/Flows/PublicationFlowTests.swift`は新規専用rootの合成metadataを通常一覧/詳細/再起動へ結ぶ検証用で、既存fixtureの修復・再seedや正式媒体producerに使わない。定義と実行結果は分け、結果は現行tasklistを参照する |
| `FrameRelayTests/Application/RenditionPlaybackModelTests.swift`、`Integration/Composition/ProductRenditionCompositionTests.swift`、`Support/ProductRenditionFixture.swift` | 同上 | 完全local媒体の実再生token/本人確認、停止/閉鎖/unknown照合、現在identity・実媒体・共有owner/registryと再生入口予約を対象とする。合成receiptを使い、正規の原本予約APIで合成MOVを保存する。原本不在枝は新規専用fixture内の退避で扱い、正式producerや旧fixtureの修復にしない。`ProductLocalRenditionSeedTests.swift`/`FrameRelayUITests/Flows/LocalRenditionFlowTests.swift`の専用root操作と、自動検証の成否・未実施は現行tasklistで区別する |
| `FrameRelayTests/Support/`、`Fixtures/Subjects/` | 同上 | Portのfake、`Support/Storage/SyntheticMovieFixture.swift`の合成動画、人物解析用の公開画像と`provenance.json`。local再生画面の長文scroll/停止用は[ProductRenditionPresentationMovie.swift](../FrameRelayTests/Support/ProductRenditionPresentationMovie.swift)へ分離し、旧生成器の制限を変えず、新規専用rootで180秒/4MiB以内の表示用合成材をnativeで構成・検査する。正式変換・カメラ・画質の証拠にはせず、実生成や最大文字UIの成否は現行tasklistで追跡する。アプリtargetへ含めず、実原本や認証秘密をfixture化しない。独立した`Support/Fakes/`は未作成 |
| `FrameRelayUITests/Flows/` | `FrameRelayUITests`、XCTest | 製品撮影・Library・接続・探索の操作と状態表示。`RemovalFlowTests.swift`は単数破棄/履歴、`ConnectionFlowTests.swift`は明示metadata同期/続きも扱う。条件付き複数整理のUI実行条件・結果は現行tasklistで追跡する。`XCUIApplication`を通し、Photos等の未接続操作や未実施の必要検証を完了扱いにしない |
| [ProductUploadMetadataSeedTests.swift](../FrameRelayTests/Integration/Composition/ProductUploadMetadataSeedTests.swift)、[UploadMetadataFlowTests.swift](../FrameRelayUITests/Flows/UploadMetadataFlowTests.swift) | Unit補助 / UI・XCTest | 新規専用rootに合成の保存原本/queued依頼・登録とcurrent UUID namespaceの資格情報をcreate-onlyで一回SEEDする。通常AppのlaunchArguments/launchEnvironmentは空とし、閉鎖HTTPS先への本人操作による結果不明、元queryのlocal照合、本人停止/取消後の新規準備拒否・再launchと通常/最大文字の厳格AXを定義する。実writer再open、原本/manifest/current資格情報のbytes/hash保持を`VERIFY`し、seedを製品native Wi-Fi受付やremote登録の成立にしない。実行結果は未確定で、通常HTTPS成功・媒体送信/SDK正開始の証拠にせず、native HTTP全数/媒体SDK inventoryは未測定とする |

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
- **秘密情報**: 登録資格は`Platform/Credentials/KeychainRegistrationVault.swift`で扱い、Swiftソース・pbxproj・fixture・文書・ログに記載しない。接続先入力・登録状態と資格の保管境界を分け、環境別の秘密値をソースへ埋め込まない。明示新登録の`store.<UUID>.connection`/`store.<UUID>.initial.<destination>`はcreate-onlyで扱い、現在namespaceの不正を旧globalへのfallbackで隠さない。旧global項目の移動/上書き/削除と旧secretの別storeへの自動採用をしない。

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

現行supportの`server-implementation/backend-overlay/`は登録/保存/候補job/publicationと保存原本inventoryの隔離実装、`server-isolation/prepare_publication_probe.py`・`run_publication_simulator_probe.py`・`publication_fixture_listener.py`は試験用準備/起動/HTTP支援である。iOS側入口は`FrameRelayTests/Integration/Remote/PublicationHTTPFixtureTests.swift`。保存原本inventoryは`server-implementation/prepare_inventory_snapshot.py`・`cases-inventory.json`で版/試験集合を固定し、`server-isolation/prepare_inventory_probe.py`と`RemoteInventoryHTTPFixtureTests.swift`を限定HTTP検証の入口にする。本番反映や稼働DB操作の許可にはしない。実行版と観測はtasklist S28/E-S27-01/E-S28-01/E-S34-BG01と各evidenceを参照し、S27旧実証拠を後続metadata試験で置換しない。旧M04の`evidence/20261020-m04/`も配置確認の履歴として保持する。

## 移行上の注意

1. 対象仕様とsteeringが用意された実装工程で、関係する責務から配置する。現状の`FrameRelayApp.swift`、`ContentView.swift`とアセットを入口にし、構造整理だけの一括移動はしない。
2. ソース追加/移動時はファイルシステム上の位置、Xcodeでの表示、同期グループ、target所属、資材参照を照合する。同期グループであることだけで誤ったtarget所属が起きないとはみなさない。
3. ロジックを先に必要なPort/Domainの責務へ割り当て、PlatformとPresentationの依存が逆転していないことを確認する。既存の共通store・原本・Ports・Compositionを拡張し、採用済み内部方式と未確認の実方式・品質を分けてarchitecture/steeringへ反映する。
4. build/test前に実在project・scheme・destination・テスト構成を確認する。製品接続、自動検証、実機確認、PRD受入を独立に記録する。確定した操作・背景/状態同期の要件や本人合意済み暫定policyを未合意へ戻さず、未接続・未実行・実機品質の残件をファイル配置だけで完了にしない。

人間が作成した既存Xcode projectを利用し、構造定義のためのproject/workspace生成、project generator、空のpackage、外部依存やMac用targetは追加しない。今回の変更は本書だけであり、コード移動、build/test、Simulator/実機起動、外部接続、動画の生成・転送・削除は行っていない。

構成と記述観点は[repository-structure Skill](../.agents/skills/repository-structure/SKILL.md)、[テンプレート](../.agents/skills/repository-structure/assets/template.md)、[ガイド](../.agents/skills/repository-structure/references/guide.md)に従う。
