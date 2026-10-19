# Design — バックエンド連携

## 状態・設計の読み方

2026-09-28のread-only調査から実装責務・契約・順序を定めた計画。同日の明示依頼で実装工程へ移行した。下記の論理型・Port・ファイル配置は、tasklistの実装・検証証跡が付くまでは計画であり、方式採用・実機成立の証拠ではない。要求は [requirements.md](requirements.md) と [確定仕様](../../docs/ideas/20260928-backend-integration.md)、進捗・証拠は [tasklist.md](tasklist.md) を参照する。

## 現状と接続点

### FrameRelay

- `ContentView.swift` が探索用modelを所有し、`Application/Capture/ExplorationCoordinator.swift` がセッション寿命の`@MainActor`所有者としてREC・保存effectを調停する。バックグラウンド移行時の探索停止は背景転送対応ではない。
- `Application/Ports/CapturePorts.swift` の`RecordingStorePort`は`commitIntent`、`commitResult`、`loadUnfinished`を持つ。正常原本一覧、読取lease、全アプリ復旧、転送・Library・Playback・MediaIOGateは未実装。
- `Application/Capture/RecordingSaveLifecycle.swift` は意図・終端・検査・対応結果commitの順序を表現する。原本生成／ローカル保存／再起動照合は撮影CF-08／P09の唯一の責務として再利用する。
- `Platform/OriginalStore/ManagedOriginalStore.swift` は探索runの不透明参照・予約・逐次digestの足場。製品の内容世代、永続全内容証拠、読取lease／実解放契約はまだない。`Platform/OriginalStore/AVOriginalInspectionAdapter.swift` は実Log・再生可否・完全性に`unknown`を返すため、現探索出力を正常原本入口へ昇格させない。
- `CaptureGeneration(session, settings)`は撮影設定世代、`RecordingCommitReceipt.revision`はstore更新世代。どちらも原本内容世代として再利用しない。
- 撮影steeringはP05 done、P06部分実装でblocked、P07以降pending。D01記録出力、D04保存方式、D02実Log・標準変換資材は未選定。既存の単体／UI試験成功はバックエンド成立の証拠ではない。

### MediaVault

調査対象は `/Users/oyabu/dev/rep/latest_template`、HEAD `c56d4a25a46acfa99dd66c4586621b5261af4d39`。追跡変更なし、未追跡JPEGあり。実Mac miniの稼働版・DB・媒体・権限・接続・通信保護は未確認。以下は同repo内のパスであり、計画作成時には変更・起動していない。

| 区分 | 調査根拠（`backend/app/`配下） | 計画上の扱い |
| --- | --- | --- |
| 再利用候補 | `api/upload_sessions.py`、`schemas/upload_sessions.py`、`services/upload_sessions.py` | 内容／session／chunk照合・不足範囲再送の土台。登録消失や操作ID欠落の救済を保証しない |
| 変更 | `services/upload_finalize.py`の組立hash→replace→DB確定→preview job追加 | 最終保存先の独立読戻し・耐障害順序・証拠commitを追加し、正式変換jobを証拠ゲートの後に置く。組立時hashを保存済み全内容証拠にしない |
| 再利用候補 | `repositories/jobs.py`、`workers/worker.py` | job復旧を新しい保存／変換identityへ対応付ける。worker起動は復旧・生成物回収・処理を実行するため隔離必須 |
| 再利用候補／変更 | `services/processed_result_delivery.py`、`processed_result_stream.py`、`processed_result_integrity.py` | 固定resultの配信とRangeを候補にする。Rangeごとの再解決・全hash・DBロック負荷を早期実測。検査を黙って省略しない |
| 変更 | `api/assets.py`の固定result／可変preview、`processed_result_delivery.py`のformal／managed経路 | アプリへは固定identityを返す。可変previewを確認tokenの根拠にしない。認証・全媒体制御を各取得経路へ適用 |
| 変更 | `services/formal_preview_authority.py`、`initial_release_guard.py`、変換worker | 既存Apple Log compress-onlyを正式Rec.709へ流用しない。実入力Logと変換根拠・出力版を追加 |
| 共通化が必要 | `services/processed_result_finalizer.py`、`formal_preview_finalizer.py`、`rendition_finalizer.py`、`processed_result_backfill.py`、`repositories/processed_results.py` | 全公開pointer更新が同じ配布台帳・失効ACK・期待公開世代の判定を通る。既存初回公開保護だけでは差し替え未達 |
| 新規契約 | `api/deps.py`は単一bearer認証のみ。旧確認APIはasset ID/version主体 | 接続先identity、登録identity、実再生版、失効世代、配布台帳、端末commit ACKを追加。bearerがあるだけで登録成立にしない |
| 別意味 | `services/upload_sessions.py`の既存cancel | temporary chunk回収等のサーバー操作。本人の通信依頼キャンセルと直結させない。取消は端末意思を保存して実結果を照合 |
| 起動時副作用 | `main.py`のstorage初期化・migration・backfill、`services/phase2b_migration.py`のpointer更新 | 通常起動を読み取り操作とみなさない。使い捨て環境だけで評価し、実DB移行は本計画外 |

`docker-compose.yml`の既定API／workerはDBと媒体を共有mountする。`services/disposable_database_target.py`等の一部CLI guardはAPI／worker全体の安全性を保証しない。T04でDB・媒体root・worker・port・token・全設定を隔離するまで起動しない。

## 設計概要・状態所有

既存のPresentation→Application→Domain、Port→Platformの境界を維持する。新規処理は既存App module内へ置き、撮影coordinatorにHTTPやサーバー成功判定を追加しない。

| 担当（論理名） | 所有状態・責務 | 窓口／寿命 |
| --- | --- | --- |
| `MediaOperations` | 固定バッチ、動画別本人意思、対象／試行、通信・外部結果の調停 | `startTransfers/startDownload/pause/resume/cancel/pauseAll/confirm`等のcommand。アプリ寿命、画面離脱で消さない |
| `MediaIOGate` | 回線、REC／保存抑止、認証、対象有効性と許可lease | 操作意思を読み抑止理由集合を返す。再開は全条件を再評価。撮影側とは型付きcommand/eventのみ |
| `LibraryProjection` | 動画別の独立状態・表示理由・次操作のsnapshot | store／担当から読取り投影。選択・表示cacheを操作証拠へ戻さない |
| `BackendRecovery` | 未完了通信・サーバー結果・失効／確認同期の起動時照合 | 撮影復旧完了／対象未確定を受ける。原本ファイルを独自に正常分類しない |
| `PlaybackSession` | 1本の固定版・再生到達・再生token | 再生画面の寿命。閉じた再生は終了し、通信復帰で再開しない |
| `TemporaryMedia` | 部分範囲、完全取得、内容対応、用途別使用権、使用量・解放 | 再生／ダウンロード／後続写真への受渡しを区別。永続証拠と別に回収 |
| `OperationStore` | 本人意思、操作・証拠・版・登録・確認／失効と更新世代 | 単一writer契約、期待世代付きcommit。物理storeは撮影D04と合流し二重正本を作らない |
| 撮影側 | 原本生成、保存正常／部分／不明／失敗、確定参照、結果commit、再起動復旧、記録資源 | CF-08／P09が所有。保存storeと保存事実・REC／保存状態をG2A／G2Bとして渡す |
| 連携側の原本access担当 | 独立した内容世代・全内容識別、`OriginalAccessPort`、read lease／実解放receipt | T11が既存OriginalStore／LocalStore上へ追加してG2Cを生成。撮影の書込・保存分類・復旧は再実装しない |
| Macの受信／検証担当 | 受領範囲、最終保存先・証拠、変換受付 | 操作／登録／原本内容を対応付け、独立した全内容検査を所有 |
| Macの版公開担当 | 不変軽量版、公開／候補、配布登録、失効対象・ACK | 原本単位の短いtransaction／期待世代で配布と公開を順序付ける |

### SwiftUIと共有

- `Features/Library/`に必要な対象選択・動画別状態・開始／停止／再開／取消・全件停止を置き、`Features/Playback/`に単体再生と明示確認を置く。画面名・最終配置・ジェスチャーは未固定。写真保存済み・削除済みを作る操作は追加しない。
- `@MainActor`のPresentation modelはsnapshotと本人入力を扱う。選択はView側の一時状態、開始済み対象集合はOperationStoreの永続状態。再表示で未指示動画をバッチへ加えない。
- 状態は「端末保存」「本人依頼」「受信」「Mac保存／検証」「変換」「公開／候補」「再生」「確認／失効」を別に提示する。写真・削除は未実装または後続からの既知事実として扱い、取得完了から推定しない。
- Compositionが撮影側と連携側のPortを注入する。`ContentView`・Composition・共通Port・project設定はT01で単一所有者を決め、撮影作業と同時編集しない。

## モデル・Port契約

外部DTO／DB rowをDomainへ流さず、下記の値へ境界変換する。具体的な型名の微調整は可能だが、識別の意味を統合しない。

| 値 | 必要情報・意味 |
| --- | --- |
| `DestinationIdentity`／`DeviceRegistration` | 認証した接続先のidentity、初回登録操作・登録identityと世代の永続対応。端末の意図／サーバー確定結果／端末commit・不明を分ける。ホスト名・IP・bearer・アプリ再起動を同じ概念にしない |
| `OriginalDescriptor` | 撮影ID、不透明ローカル参照、撮影側保存結果、独立した内容世代、全内容識別、存在／アクセス可否。撮影設定世代やstore revisionと分離 |
| `TransferBatch`／`MediaRequest` | 本人操作ID、受理時の固定対象、動画別操作ID・用途・対象原本／版、本人開始／停止／取消、試行、複数待機理由。試行IDは原依頼を置換しない |
| `RemoteReceipt`／`VerificationEvidence` | 登録・接続先・操作・受付session、受領範囲、原本内容、最終保存結果、独立検証、証拠schema版・取得時点。送信完了とverifiedを分離 |
| `RenditionIdentity` | 原本内容、入力Log、標準変換資材の識別・版、出力設定、変換版、生成物identity／内容、公開世代。再生成は同一映像と推定しない |
| `PlaybackToken` | 固定RenditionIdentity、配信内容の対応、実再生到達、再生session、対象登録、確認に使う失効世代。tokenだけで確認済みにしない |
| `ConfirmationRecord`／`InvalidationRecord` | 本人操作、実再生対象、登録、期待世代、commit receipt。失効は失効ID・対象・世代・commit／ACK状態。受信済みと端末保存済みを分離 |
| `DistributionReceipt`／`PublicationIntent` | 現公開対象との一致確認後に媒体配布を受理した登録、原本／映像、公開世代。候補版、失効世代、必要ACK集合、差し替え保留／確定。manifest取得は配布受理ではない |
| `TemporaryMediaReceipt` | 固定版、取得範囲／完全性、内容照合、用途・使用権、使用量、回収状態。部分streamを完全媒体にしない |
| 後続引渡し値 | 整理用証拠snapshot、実停止／読取解放receipt、原本単位の削除確定区間と復旧状態、写真用の同一完全媒体receipt。実削除／登録成功の偽receiptを作らない |

| Port（論理名） | 入出力と責務 | 確定／不明の境界 |
| --- | --- | --- |
| `OriginalAccessPort` | T11が撮影側の確定参照・保存結果から内容世代／全内容識別を対応付け、固定内容のread lease取得／実解放を実装 | 存在確認・読取権・実解放は別。未確定／partialをnormalへ昇格しない。T09は契約fakeで先行検証 |
| `MediaOperationStorePort` | 固定開始対象、本人意思、結果、確認／失効、同期outboxを期待世代付きでcommit／読戻し | 親contextまでのsaveやUI受付で成功を返さない。未知schema／破損を初期化しない |
| `RemoteStatusPort` | capability／identity照合、登録、受領範囲／保存／変換／版照会、既確認同期、失効受信／ACK | 媒体byte・サムネイルを含めない。結果不明と未実行を区別 |
| `MediaTransportPort` | gate lease付きupload／download／固定版range、実停止イベント | callback取消とOS task停止・file lease解放を別イベントにする |
| `PlaybackPort` | gate付き固定版媒体または取得済みlocal参照から再生し実再生tokenを返す | AVPlayerの準備完了・URL表示を実再生にしない。独自媒体通信の抜け道を作らない |
| `TemporaryMediaPort` | 用途別範囲・完全取得・照合・使用権・量・解放を管理 | 不完全媒体を写真へ渡さず、媒体回収で証拠を消さない |
| `CredentialPort`／`NetworkConditionPort` | 秘密の保管・取得、接続先照合、基礎経路変化の通知 | Keychain等の候補をSDK・ロック条件で検証。VPN状態だけでWi-Fi許可しない |
| `OriginalOperationOrderingPort` | 原本単位に失効commitと後続削除確定区間を順序付ける | 未完了削除意図の復旧完了前に失効ACKしない。今回の具象削除は提供しない |

### API・保存方式の判断契約

T02／T06でwire contractの版、capability、論理操作を具体endpoint／DTO／schemaへ割り当てる。最低限、接続先・登録、操作開始と照会、受領範囲、保存証拠、変換結果、固定版媒体manifest／配信、配布登録、確認同期、失効取得／ACK、公開結果を別契約として検査する。小さい状態応答と媒体responseを分離し、未知版は停止・更新待ちへ変換する。

既存upload session／固定result／job／repositoryを再利用候補にし、既存DB内の論理記録拡張を使い捨て環境で評価する。具体schema・ID表現・制約・migrationはT06で固定するまで未選定。端末storeはCore Data＋SQLite第一案と既存候補を撮影D04に合わせて評価し、T07の製品adapterはG2Aの保存store引渡しを待つ。T11の内容世代・使用権完成をT07の前提にしない。独立したfake／使い捨てstoreの契約比較は先行できる。実DBへの適用はこのsteeringの実行範囲に含めない。

## データフローと復旧

### T02 契約具体化（2026-09-28、方式非依存）

以下は確定仕様の意味を型と遷移へ割り当てる実装契約。HTTP endpoint・認証方式・DB・digest方式・運用数値は選定しない。既存撮影ファイルを変更せず、`CaptureID`、`CaptureOriginalReference`、`RecordingSaveResult`を参照する。

| 識別・値 | 入出力と照合規則 |
| --- | --- |
| 接続先／登録 | `DestinationIdentity`と`RegistrationIdentity(id, generation)`を組にする。初回登録には独立した登録操作IDを持つ意図が必要。結果は同じ接続先と操作へ対応し、サーバー確定と端末commitを分離。通常再起動では保存済み操作を照会し、不明を新登録へ置換しない |
| 原本内容 | `CaptureID + ContentGeneration + ContentIdentity(byteCount, algorithm, digest)`を固定。不透明参照・撮影保存結果・存在・アクセス・復旧済みの事実を併記し、正常保存確定以外は転送入口で保留。内容世代をsettings／store revisionから算出しない。T03の内容値はfixture入力で、製品での生成・永続対応はT11 |
| 操作／試行 | バッチID、動画別操作ID、試行ID、登録、固定対象を区別。同じ操作のretryは試行だけ更新し、取消後の新操作は過去結果を先に照合。外部結果は未実行確定・処理中・確定成功・確定失敗・不明を区別し、接続失敗だけで既存確定結果を消さない |
| commit | 操作、対象、期待revision、commit後revisionを照合。単一writerの直列確定区間で確認／失効とoutboxをまとめる。拒否、revision競合、commit不明、未知schema／破損／保護等の読取不能を別結果にし、単なるレスポンスやメモリ更新を確定receiptにしない |
| 保存証拠 | 接続先・登録・操作・upload session・固定原本内容・最終保存完了・独立全内容読戻し一致・証拠schema・取得時点を束縛。対応不明・組立hashだけ・未commitは変換許可／整理証拠にしない |
| 軽量映像 | 原本内容、実入力Log識別、変換資材ID／版、出力設定ID、変換版、生成映像ID、配信内容identity、公開世代を固定。具体設定値は未選定。manifestは記述であり、媒体配布receipt／実再生tokenではない |
| 確認／失効 | 登録・固定映像・実再生session・失効世代へ本人の単数操作を束縛する。確認受付→世代再照合→確認／outbox commit→有効。失効受信→同原本の順序予約→失効／outbox commit→ACK可能。旧token／遅延receiptを新世代へ採用しない |
| 停止／読取解放 | 本人停止要求、transportの実停止、原本全reader実解放を別receiptにする。lease／解放receiptは原本内容とaccess世代・照合epochを固定。新reader取得や再起動で古い全解放receiptを使用できなくする。Mac実結果は解放から推測しない |

Portの具体引数・戻り値は上記型と型付き失敗で表し、任意文字列payloadやHTTP DTOをDomainへ漏らさない。時刻・ID・capabilityは呼出側入力とし、Domainが時計・乱数・I/Oを実行しない。実体未確定のwire／schema版は明示的なsupported集合と比較し、未知版を拒否する（fixtureの版を製品版の採用値にはしない）。

| Port／論理操作 | 要求と結果・確定境界 | 試験群 |
| --- | --- | --- |
| OriginalAccess: describe／acquireRead／releaseRead／reconcileReaders | 確定撮影参照→descriptor、固定内容＋操作→lease、handle実解放→個別結果、全reader照合→全解放receipt。存在／アクセス不可／復旧不明を区別 | V02、V15 |
| MediaOperationStore: load／commit／lookupCommit | 不変snapshotと期待revision付きmutation。確認／失効／outboxを一単位で保存。応答欠落は同一操作を照会して確定receiptか不明を返す | V01、V04、V11、V13 |
| RemoteStatus: capabilities／register／lookupRegistration／lookupOperation | 認証済み接続先、対応する論理capabilityとwire版、先行commit済み登録意図、受領範囲・保存証拠・job・版。媒体byteを戻り値へ含めない | V04、V13 |
| RemoteStatus: syncConfirmation／fetchInvalidations／ackInvalidation | 端末確定済み確認または失効receiptを送る。受信した失効だけではACKしない。状態通信から本人確認・媒体取得を作らない | V11〜V13 |
| MediaTransport: upload／download／range／requestStop／observeStop | 操作・試行・固定対象・登録・gate leaseを必須とし、uploadはread leaseも必要。受信receiptと実停止receiptを別に返す | V01、V02、V04 |
| Playback／TemporaryMedia | 固定版の配布受理receipt＋実再生到達からtokenを得る。local再生は取得範囲を照合。写真consumerは同一版の全取得・内容照合・有効使用権が揃ったreceiptだけを受ける | V11、V15 |
| OriginalOperationOrdering | 原本単位の削除確定区間／失効commitを排他順序へ置き、未解決削除意図は再起動後も復旧待機にする。実削除関数は今回提供しない | V04、V12、V15 |

最小wire capability群はidentity／registration-lookup、upload-reconciliation、final-storage-evidence、rendition-manifest、fixed-media-distribution、confirmation-sync、invalidation-ack、publication-reconciliation。具体文字列・版番号・endpoint・schemaはT06。未対応が一つでも該当操作を必要以上の成功へ進めない。

T03で検査する決定規則:

- バッチはWi-Fi時の明示開始で固定し、空・重複・不適格原本を拒否。個別依頼の本人意思、複数の環境待機理由、transportの状態、外部結果を独立に持つ。全件停止は順番待ち／自動待機を含む未完了依頼へ適用。後発成功や回線復帰で停止／取消を解除しない。終了済み再生は再開不可。
- 再送前に同じ接続先・登録・操作・内容・sessionを照会し、不明／不一致は保留。登録bearerだけ・未commitの登録では媒体を開始しない。
- manifestを取得しても配布台帳を増やさない。配布受理は現公開版との一致照合＋台帳commitを同じ短い確定区間で行う。V2公開先行ならV1 GET／Range／再開を拒否。V1受理先行なら進行中応答も必要失効ACK集合へ入れ、待機中の新規受理登録も追加。全ACK前の公開、別登録／古い世代のACK、timeoutでの代用を拒否する。
- 確認は実再生token＋本人操作＋同じ登録／映像／未失効世代＋端末commitで成立。全量取得／全編再生は条件にしない。失効commit後は遅い応答・旧local再生・V2失敗から旧確認を復活させず、新登録へ旧確認を移さない。接続不能だけでは最後の有効確認を失効させない。
- 後続整理条件は存在する同一ローカル内容＋最後の対応する保存検証＋同一映像の有効確認。オンライン・写真保存を追加条件にしない。失効先行は整理不可、削除確定区間先行は結果照合まで失効ACK待ち。停止要求だけ・古い全解放receiptだけでは削除consumerへ渡さない。fakeは実削除／実Photos成功を生成しない。

| 判断台帳 | 現在の扱い・producer→consumer |
| --- | --- |
| J01 識別・不明・commit・順序 | 上記をT03の方式非依存契約として実装。BI-01〜06、08〜12とV01／02／04／11〜13／15へ対応 |
| J02 物理store／撮影引渡し | D04／P09→G2A→T07、D01／D04／P09→G2B→T11。いずれも未成立。T11→G2C→T12。T03 fakeを製品storeや製品原本へ注入しない |
| J03 API・DB・wire版・登録認証・digest・保存順序 | T04隔離＋T05/G1の結果を入力にT06で選定。T03のopaque ID・schema支持集合は採用値を確定しない |
| J04 背景／配信・通信量・retry・一時使用量 | T05で観測しT06へ。未知値を定数で補わない。失効ACK期限は設けず旧登録の該当差し替えを保留 |
| J05 標準変換・出力・本人品質 | BI-07／13、D02→T13/G3→T14／T16/G5。技術fixtureを品質合格へ昇格しない |
| J06 保全・UI・全AC | BI-12／14はT04／T20／T25。既存撮影とデータを保持し、T03結果は契約層の部分証拠のみ。全34ACとPRD79ACはrequirementsの追跡を維持 |

### 接続先照合・初回登録

1. T06で具体API・認証／登録手段を選定し、T06Aが接続先identity照合、初回登録・同一登録操作の結果照会、登録identity／世代のサーバー永続化を実装する。T08はこの確定登録を受信・保存証拠へ束縛し、bearerだけで登録済みにしない。
2. T07AはT07のstore上に接続先と初回登録意図を副作用前に保存し、サーバー結果を同じ接続先・操作へ照合して登録identity／世代を端末commitする。応答欠落・端末commit不明は同一操作を照会し、通常再起動で無条件に新登録しない。照合不能な登録は不明のまま媒体通信を保留する。
3. T09／T12の媒体通信はこの登録確定を前提にする。T17の配布台帳とT19の状態同期／再登録はT06A／T07Aを再利用し、別の初回登録経路を作らない。新登録と通常再起動、旧確認の非復元、旧登録の必要ACKを分ける。具体的な再登録操作もT06の選定範囲とする。

### 撮影保存事実と連携用原本access

- 撮影D04／P09は保存storeの契約・単一writer・結果commit／読戻しをG2A、D01／D04・CF-08／P09は確定参照・保存分類・再起動照合・REC／保存状態をG2Bとして渡す。撮影P09のDoneは保存確定分類／復旧までで、連携用の追加使用権契約の完成を保証しない。
- T11がG2A／G2Bを入力に、既存OriginalStore／共通LocalStoreの引渡し契約を拡張する。撮影側の確定参照・保存記録と同じ正本へ内容世代・全内容識別の対応を確定し、`OriginalAccessPort`のread lease／実解放を追加する。「独立した内容世代」は撮影設定世代・commit revisionと異なる意味を示し、連携サービスに別の原本世代正本を作る意味ではない。通常再起動・再試行・別のstore更新で再採番せず同一内容の対応を保つ。不一致・対応不明は別内容／不明として保留し、同一内容として継承しない。全内容識別の具体方式はT06で選定する。
- leaseは対象内容・利用者・操作を固定し、要求取消、端末通信実停止、全readerのhandle／使用権解放を別に観測する。実解放receiptは該当原本の全read leaseの解放を確認して返す。再起動時はOS task／残る読取と対象を再照合し、古いreceiptやプロセス終了だけで現在の全解放を推定しない。媒体を逐次検査しても原本書込・正常／部分等の分類・撮影復旧は再実装しない。
- T09は`OriginalAccessPort`の契約fakeで制御・通信adapterを検証して完了できる。T11が具象accessと撮影gateを結合しG2Cを生成、T12がG2Cを消費して実原本転送を受け入れる。T07→T09→T11→T12へ進み、T07／T09がT11成果を待つ循環を作らない。

### 手動転送・取消・保存証拠

1. T07Aの接続先／登録確定を照合し、本人操作時にWi-Fi、原本保存結果・内容参照を再照合して固定対象と動画別開始意思をcommitする。Wi-Fi不在時は新規予約を作らない。受理後の切断は既開始待機として保存する。
2. 初期実装は順次転送を基本とする。処理順は固定対象に対して安定させ、並列数や並びの製品選択を未合意値で固定しない。動画別個別失敗は残し、認証・回線・容量等の共通問題は影響対象を待機させる。
3. read leaseと媒体gate leaseを得て必要な全内容識別／送信を行う。大きいファイルは逐次処理し、RECで停止できる境界を持つ。hash完了をRECの一律条件にしない。
4. 再試行前に操作・登録・内容・sessionを照会し、サーバー確定受領範囲だけから不足を送る。応答消失やID不足は要照合として依存処理を保留する。
5. Macは意図・受領範囲を記録し、確定前ファイルから最終保存先へ確定する。保存／flush／rename／directory／DBの具体順序はT06／T08で選定して障害試験する。特定API名だけで耐障害性を宣言しない。
6. 最終保存先を独立に再読取りし、端末側全内容識別と対応する結果を証拠としてcommitする。組立中のdigestやクライアント申告値のechoを使わない。応答前のクラッシュでもファイルと記録を再照合し、検証不足はunknown／failedを保持する。
7. 証拠確定後だけ正式変換jobへ渡す。iPhoneは返された証拠の対象・内容・接続先・版を照合してcommitし、「送信済み」と「保存検証済み」を別に表示する。
8. 停止／取消は端末の本人意思を先に保存して媒体I/Oを止める。既存server cancelへそのまま写像しない。Macの保存／検証／変換継続と遅れて届いた成功は実結果として照合し、本人停止・取消を解除しない。再実行は新しい本人操作と過去結果の照合を要する。

### 全媒体gate・背景／ロック

- lease条件は「本人開始受理済み・未完了・未停止／未取消」「許可Wi-Fi」「RECなし」「保存／異常処理なし」「認証／対象／版が有効」を別入力から毎回導出する。複数理由は集合として保持し、一つの解除で他を消さない。
- REC受理時に新leaseを閉じ、進行中upload・download・streaming・一時取得・サムネイル・再開／背景taskへ停止を通知する。端末実停止と読取解放を観測し、Mac停止ACKをREC条件にしない。撮影開始・次RECへの影響を実測する。
- 録画終端、原本保存完了、異常処理終了は別eventとし、終端だけでgateを開かない。原本不明の復旧中は当該対象を開かない。状態照会は媒体gateと別契約だが、撮影／保存優先と通信量管理に従う。
- URLSession＋Networkを第一候補として、背景upload／download、OS taskと操作ID対応、再起動callbackの復旧、ファイル保護、基礎回線とTailscale切替を早期に検証する。APIの設定値やNWPathの表示だけで全媒体Wi-Fi強制済みにしない。
- 背景taskを再列挙して既存操作へ結び付け、未知taskや版不一致は停止・要照合にする。OS中断／強制終了からの復帰は同一結果を照合して全条件を再確認する。終了済み再生は再作成せず、未実行削除・結果不明写真登録へ再開規則を流用しない。
- 状態通信は明示した小さいDTOのみ。既確認outbox・失効ACK再送は許可できるが、同期をきっかけに再生・媒体取得・明示確認を作らない。更新頻度、payload量、retry上限・backoffの値はT06で測定目的とともに決め、常時即時同期を約束しない。

### 固定版・一時媒体・確認

1. 保存証拠に対応する不変原本から、採用Logと資材に適合する標準Rec.709を生成する。変換仕様・出力・生成物を別identityで保持し、原本・既存公開版を上書きしない。
2. 配信manifestで原本・変換版・映像・配信内容・要求公開世代を固定する。manifestは媒体配布の許可や本人確認を作らない。各GET／Range／途中再開は下記の現公開対象照合・配布commitをbyte前に通り、公開後の旧版要求は拒否する。V2へ自動差替え・redirect・混在再生せず、拒否応答から確認を確定しない。初期版streamingを第一候補とし、認証付き固定result・gate・実再生観測を実機で比較する。
3. Playbackは認証済み固定媒体を共通gate経由で読み、実際に表示／再生へ到達した同一版のtokenを作る。AVPlayer独自取得を使う候補では、その全取得・認証・Wi-Fi／REC停止をT05で観測できなければ採用しない。
4. 本人が1本への確認操作を行ったとき、token・登録・原本内容・変換／映像identity・現在の失効世代を端末storeで再照合し、期待世代付きcommitに成功して初めてvalidにする。全量取得・全編再生は不要。端末内で既に失効が先行した旧tokenを拒否し、サーバーの毎回接続を確認維持条件にしない。
5. valid確認とサーバーへの同期outboxを同じcommit境界へ置く。同期未達でもサーバーは配布台帳から確認存在可能性を扱う。記録保存失敗／不明は有効にしない。同じ映像の再取得、通常再起動、単なるMac不通だけではvalidを消さない。
6. 再生終了で再生専用I/Oと使用権を解放する。確認／失効・不明結果の証拠は保持する。ダウンロード部分・再生buffer・写真へ渡せる完全媒体を分離し、取得完了を写真登録成功にしない。取得済みlocal媒体はオフライン再生可、未取得版を再生可能と偽らない。

### 配布台帳・失効先行公開・再登録

- 製品の全媒体取得入口（固定URL、GET／Range／途中再開、download／stream／一時取得／サムネイル、formal／managed等のラッパーを含む）は、認証した接続先・確定登録と要求した原本／版／映像／公開世代を現在の公開対象へ照合する。この一致確認と`登録×原本内容×変換版×映像×公開世代`の配布台帳commitを公開pointer更新と同じ原本単位の短い確定区間へ置き、commit成功後だけ媒体byteを返す。固定URLの存在・manifest取得・認証成功だけでは配信を許可しない。確認同期の有無とは独立に記録し、配信失敗でも確認不存在を推定して台帳から消さない。
- 競合順序は二つに分ける。V1 manifest取得→媒体未取得／台帳未登録→V2公開確定→V1 GET／Range／途中再開なら、現公開対象不一致としてbyte前に拒否する。旧台帳の後付けで許可したり、V2へ自動差替え／redirectして継続したり、manifest／拒否応答から本人確認を作らない。逆にV1の配布受理commitが公開更新より先なら、その登録は必要失効ACK集合に入り、公開は対応する端末失効commit／ACKを待つ。
- 公開V1と候補V2を分ける。候補生成／失敗だけでV1確認を失効しない。差し替え要求は原本単位に失効世代と必要登録集合を持つ。公開pointer更新と配布受付を同じ順序付けへ載せる。
- 差し替え待ち中にV1を新しい登録へ配布する場合、その配布登録と対応失効を必要ACK集合へ同じ確定区間で追加する。追加後に再度集合・期待公開世代・全ACKを照合する。全ACK確認とpointer更新の間に未失効登録へのV1配布が割り込まないようにする。短いtransaction等の具体方式はT06／T17で固定し、ネット応答待ちのままDB全体をlockしない。
- 配布受理済みV1の進行中応答は台帳／必要ACKの保護下にあり、応答終了まで確定区間を保持しない。端末で失効commitが先行した場合、遅れて届いたV1のbyte・実再生tokenでも旧確認を新規確定／復活させない。V2公開後の新たなV1 GET／Range／再開は、以前の配布receiptがあっても拒否する。取得済みlocalのオフライン再生は別に維持し、失効済みV1の再生で新版確認を代替しない。
- 端末は失効の対象・登録・世代を検査し、原本単位の順序付けで旧確認の失効とACK outboxを永続commitする。commit成功後だけ対応ACKを送る。重複失効は記録照合後に冪等応答し、古い／別登録／別世代ACK、timeout、単なる受信通知を代用しない。
- 公開担当は必要な登録のACKを照合し、候補の完全性と期待公開世代を再検査して差し替える。固定result、formal、managed、rendition、backfill等のすべての公開経路を共通判定へ通す。移行スクリプトからの実DBpointer操作は別途許可された移行なしに行わない。
- 失効commit前のオフラインではV1とvalid確認を維持する。commit後はACK消失・再起動・V2失敗・公開保留でも旧確認を復活させない。失効済みV1の再取得／再生は新版確認の代わりにならない。
- 新登録は既存の保存証拠・版を照合取得し、旧確認を有効復元しない。通常一覧・取得・再生に全履歴再確認を要求しない。整理対象だけ新しい実再生と明示確認を行う。
- 戻らない旧登録の必要ACKは新登録で代用しない。該当差し替えを無期限保留し、利用可能な公開版・新端末の通常利用・別動画処理を維持する。旧版不能／失効済みはそのまま表示する。

T15／T16の候補fixture配信は隔離された技術・品質評価用であり、製品公開・配布receipt・本人確認の経路へ注入しない。T17で全取得入口と全公開更新を共通判定へ接続してから製品配布を有効化する。

### 後続写真・削除との順序

- 写真には同一軽量映像のidentity・撮影日時・完全取得／内容照合・使用権を渡す。Photos実装／権限／登録結果復旧は追加しない。後続が所有権を解放するまで必要媒体を回収せず、回収後も確認／失効／結果不明記録は残す。
- 整理条件は「存在する同一ローカル原本」「最後に確定した同一内容のMac保存・全内容検証」「同一Rec.709映像の有効確認」「未失効」から導出する。Mac現在存在、Wi-Fi、再視聴、写真保存、追加backup、高品質版を追加条件にしない。最後の証拠による判定と現在のMac存在を区別する。
- 転送中の破棄要求では、停止要求、端末実停止、すべてのread lease実解放を分けて後続へ返す。Mac結果不明の照合は別状態に残す。Mac照合の有無をローカル実解放と混同せず、破棄を検証・確認成功へ変換しない。
- 同一原本の失効commitと削除確定区間を順序付ける。失効先行なら整理不可。削除区間先行なら結果照合まで失効commit／ACKを待たせ、Macは旧公開版を維持する。再起動時は未完了RemovalIntentの照合を次の同原本commandより先に行う契約とする。
- 今回はfakeの後続consumer／削除区間を使って両順序と解放契約を検査する。実削除・結果照合・再起動復旧の受入証拠にはしない。整理不可から破棄へ自動移行しない。

## 非同期・永続化・エラー

- MainActorはPresentationと既存撮影調停への窓口に限定する。媒体I/O、逐次hash、store処理、再生callbackはPortの所定実行領域へ置き、SDKオブジェクトのactor間移送を仮定しない。
- 原本単位の予約／直列実行器と期待世代commitを併用する。`await`付きactorだけで操作全体の排他を保証しない。callbackは操作・試行・原本／版・登録・世代で照合し、古いcallbackは元操作の実結果として保持する。
- 状態storeのcommitは短く保ち、ネットや大きいhash中にDB全体の排他を持たない。サーバー応答を待って端末の失効／削除順序を確定しない。複数キー予約は順序を固定する。
- 永続storeに意図・外部結果・同期outboxを記録し、起動時は照合してから再開する。プロセス終了でtaskが消えても本人停止・取消・不明・失効を失わない。ログや表示cacheは復旧正本にしない。

| 失敗／例外 | 保持・回復 |
| --- | --- |
| 原本書込中・partial・unknown・アクセス不可 | 撮影結果を保持し依存対象を待機。存在だけでnormal／消失を推定しない |
| HTTP成功後の証拠応答欠落 | 操作の外部結果unknownとして照会。全量再送・新session／jobを無条件に作らない |
| 最終保存先不一致／容量・記録失敗 | verifiedを返さず失敗／不明。変換を開始しない。独立対象は継続可能 |
| Wi-Fi・認証・Mac不通 | 影響通信だけ待機。最後の有効証拠や確認を失効しない |
| 確認／失効commit失敗 | 確認valid／失効ACKを出さず要照合。受信済みをcommit済みにしない |
| ロック時store／原本へのアクセス不可 | OS待機として停止・復帰照合。ファイル不存在や成功へ変換しない |
| 未知schema・破損・世代競合 | 空storeで置換せず保留。古い応答を上書き成功にしない |
| 版／配信内容・現公開世代不一致 | byte前に取得を拒否し、V2への自動差替え／redirect・混在・確認確定をしない。失効済み旧確認は復活せず、単なる不通では有効確認を消さない |
| 容量不足／一時媒体消失 | 範囲と取得結果を再照合。既存原本を自動削除せず、恒久証拠を保持 |

## 判断ゲートと未選定事項

G2はG2A／G2B／G2Cの総称とする。外部撮影成果はG2A／G2B、連携側が実装する成果はG2Cであり、消費する段階を以下で分ける。

| ゲート | 必要な判断・証拠 | 判断時点／未成立時 |
| --- | --- | --- |
| G0 実行範囲・隔離 | 両repoの現状・AGENTS、外部書込み、実機・データ・接続先の既存許可と具体範囲。使い捨てDB／媒体root／worker／port／token、cleanup対象 | T01／T04。計画許可を流用しない。未許可対象の操作だけ停止 |
| G1 早期方式 | 背景／ロックのOS挙動・保護、全媒体Wi-Fi・Tailscale基礎回線、認証付き版固定実再生、REC相当停止・量／解放、Range負荷 | T05／T06。小規模探索を製品実装終盤へ送らない。大きな制約は代替・影響を示し再合意 |
| G2A 保存storeの外部引渡し | producer: 撮影D04／P09。保存方式・schema・単一writer／commit・読戻し・拡張窓口と所有引渡し。完了証拠: D04決定とP09のdisk commit／再open・保存復旧試験、引渡しファイル／契約 | consumer: T07の製品store結合、T11。連携用内容世代／leaseは前提にしない。欠落時は製品storeだけ停止し、fake・独立backendは先行可 |
| G2B 撮影保存事実の外部引渡し | producer: 撮影D01／D04・CF-08／P09。原本確定参照、正常／部分／不明／失敗、結果commit、再起動照合、REC／保存状態。完了証拠: P09の保存分類／復旧試験と確定原本・eventの対応 | consumer: T11。P09完了に追加read leaseを要求しない。未知原本を正常化せず、原本生成／保存復旧の不足は撮影側へ返す |
| G2C 連携用原本accessの完成 | producer: 本steering T11。G2A／G2B上の独立内容世代・全内容識別・`OriginalAccessPort`・read lease／実解放receipt。完了証拠: V02の内容対応commit前後／再起動／再試行とV07／V15の全reader解放・REC／保存抑止 | consumer: T12の実原本転送、T21／T23の実解放使用。T07／T09は待たない。T11着手時の未実装を外部引渡し不足にせず、T11の完了条件とする |
| G3 Log・品質試験合意 | D02の採用実Log・標準変換資材／版／由来／利用条件。担当側が具体素材・候補・表示条件・比較方法・許容範囲を提案し本人合意 | T13→T14／T16。技術fixture試験と品質評価を分け、品質試験は合意前に始めない |
| G4 保存・永続性 | 最終保存先独立検査・記録順序・再起動／中断証拠、端末commitと読戻し | T10／T12／T22。既存フラグ、API名、in-memory成功を代用しない |
| G5 出力採用・品質 | 許容画質の候補、媒体特性、容量／取得時間、本人の通常鑑賞評価 | T16。出力未選定・不適合はFR-12未達／未評価、条件緩和なし |
| G6 結合受入・引渡し | 実Wi-Fi／REC／背景・登録・公開・復旧、AC-BI全件／全PRD79ACの部分・残件 | T23〜T26。実装完了／検証工程完了／PRD達成を別々に判定 |

後続選定台帳はT02／T06で更新する。通信／配信adapter、認証／登録操作、具体API／schema／DB、retry値、状態通信量／頻度、一時媒体の方式・上限／期限を採用理由・棄却理由・観測限界付きで記録する。1080p HEVC・codec／bitrate／bit depth・音声圧縮等はT13／T16の候補であり、現在の採用値はない。製品範囲・本人操作・品質に影響する判断はmainが影響を提示して合意を得る。

## テスト戦略・証拠の母集団

以下は検証範囲の定義。実施済みの層・結果はtasklistの証跡を参照し、未実施の範囲は引き続き予定として扱う。fakeは決定規則・順序、使い捨てstore／serverはI/O境界、実機はOS／回線／再生／撮影非干渉を担う。同じIDでもどの層の証拠かを記録する。

| 検証群 | 最小の正常・障害・競合ケース | 証拠の限界 |
| --- | --- | --- |
| V01 本人意思・複数対象 | 選択≠開始、Wi-Fi不在、新規追加禁止、個別失敗／共通障害、待機重畳、停止／全件停止／取消、後発成功、新操作 | fakeで全状態組合せ、disk再読戻しを別途実施 |
| V02 撮影入口・access | normal／partial／unknown／failed、別内容、書込中、アクセス不可、復旧未完了。T11の内容対応commit前後中断・再起動／再試行・撮影設定／store revision更新で同一内容照合。複数readerの停止要求／実停止／全解放と再起動時の再照合 | G2A／G2B後にT11でG2Cを証明。T09は契約fakeまで。現inspectorのunknownを正常化しない |
| V03 保存境界 | chunk受信、組立、最終確定、読戻し検査、証拠commit、job受付、応答の各前後に切断／プロセス再起動。破損・不一致・容量不足 | 使い捨てDBと媒体でfile／recordを照合。実媒体保存の保証は別評価 |
| V04 端末永続性 | 意図／本人停止／証拠／確認／失効／outbox commit前後、未知schema、破損、保護、容量・世代競合、再open | in-memoryだけで完了不可。機密データを使わない |
| V05 全媒体回線 | 原本upload、download、stream/range、一時取得、サムネイル、再開／背景×LAN／Tailscale×Wi-Fi離脱／基礎回線切替 | 経路表示だけでなく実byte通信と停止を観測。cellularへ流れない証拠を残す |
| V06 状態通信 | モバイル照会、既確認outbox、失効commit／ACK、認証失敗、古い結果、媒体混入拒否、更新頻度／量 | 同期時に媒体・再生・新確認を起動しない |
| V07 REC・保存 | 各媒体I/O／hash中のREC、停止実測、録画終端と保存／異常処理、Wi-Fi待機重畳、Mac検証継続 | 早期はREC相当gate探索。G2Bの撮影状態をT11で結合してG2Cを検証し、実撮影の開始／次REC・映像音声はT23で必須評価 |
| V08 背景・ロック | 本人開始upload／download、OS待機、ロック保護、強制終了・復帰、Wi-Fi／認証断、本人停止維持 | 前景成功は背景証拠でない。OS条件・端末・継続／中断範囲を記録 |
| V09 版固定・再生 | 固定版途中再生、Range／seek／切断再開、認証、一時量・解放、実再生token。V1 manifest取得のみ→V2公開→遅延V1 GET／Range／再開は全入口でbyte前拒否、V2差替え／redirect／混在・確認なし。配布受理済み進行中応答と取得済みlocal再生は別ケース | T15は公開判定fake／隔離候補、T17／T22で実配信判定と競合を検証。失効後の遅延tokenで確認せず、単なる不通では有効確認維持 |
| V10 Rec.709・品質 | 採用実Log、縦横・24／30fps・肌／空／暗部／細部／動き・音声、原本不変、開始終端／長さ／AV同期／日時 | G3事前合意後、本人iPhone通常サイズ／通常再生。色と圧縮を別評価し許容候補の容量／取得時間を比較 |
| V11 確認 | 単数途中再生＋本人操作、再生だけ／背景／複数選択拒否、旧token、失効競合、commit失敗／応答欠落 | 全量／全編を条件にしない。確認対象が写真用と同一である証拠を要する |
| V12 公開・失効 | V2生成／失敗、確認同期前の配布登録、失効／ACK／公開中断、古い／別登録ACK、全公開経路。公開対象照合＋台帳commitとpointer更新の両順序を競合: V1受理先行は必要ACK集合へ追加して公開保留、V2公開先行は遅延V1要求をbyte前拒否。受理済み応答が失効後に届いても旧確認非復活、既受理端末の公開後の新GET／Range／再開も拒否 | manifestだけでは配布／確認なし。端末失効commit前は保留、後はlocal再生でも復活禁止。不通のみのvalid維持・旧登録無期限保留も検査 |
| V13 初回登録・再登録 | T06Aの接続先／登録世代確定と同一登録操作照会、T07Aの意図→サーバー結果→端末commit各境界の応答欠落・再起動、接続先不一致・bearerだけの拒否。登録不明で媒体停止、通常再起動で重複初回登録なし。新登録時の旧確認非復元、対象だけ再確認、旧応答不能でも別動画／通常利用継続 | 初回基盤はT08／T09／T12前、T17／T19で再利用。再登録を旧ACK代替にしない |
| V14 UI | 独立状態と永続証拠、操作受付と確定、動画別成功／不明／待機、理由・次操作、色以外の伝達 | 最終UI全体の受入ではない。写真／削除成功を偽装しない |
| V15 後続consumer | 写真用完全媒体／部分拒否、整理条件、不存在／別内容、停止要求と実解放、失効／削除区間の両順序・再起動契約 | 契約試験のみ。実Photos、実削除、最終写真鑑賞は後続必須 |
| V16 保全・追跡 | 両repo差分・旧fixture記録の非改変、設定、全ACの証拠／部分／残件、文書同期 | 実稼働旧データ保持の確認を未許可接続で実行しない |

### 早期小規模探索と品質評価の違い

T05は許可された短い非私的fixture・隔離環境を用い、転送量・背景callback・回線切替・固定版実再生・Range負荷・停止遅延・一時量／解放の観測方法と技術的可否を確かめる。撮影原本の品質や製品負荷を合格にしない。方式不成立なら製品実装を広げる前に比較案へ戻す。

2026-09-29のT05部分観測（tasklist E-BI-08）では、既存MediaVaultの2 MiB＋17 byteの合成媒体に対する1 KiB Range要求で全hash 2回、うち1回が書込みtransaction内であることを確認した。その間の別writerは`SQLITE_BUSY`となった。認証欠落とV2公開後の旧V1取得は媒体byte前に拒否された一方、公開前受理済みのdescriptorはV1を継続した。これは既存配信の限定観測であり、新たな配布台帳・失効ACKや実再生の成立証拠ではない。T06では内容同一性の保証を維持しながら、全hash負荷と短い配布／公開確定区間を両立する方式を検討する。現時点では検査省略・方式変更・性能閾値を採用せず、G1の実機／実回線観測も未完了とする。

T13は担当側が採用Log付きの具体素材、候補出力、本人iPhone・明るさ等の表示条件、同一標準変換を用いる色／圧縮別比較、fps等の技術照合、許容範囲を提案する。G3合意後のT16で実施し、色の不自然さ、階調、ブロック、細部、動き・音声を通常鑑賞で本人が判定する。停止／拡大は補助。開発比較参照映像を製品の高品質版要求にしない。「写真」登録後の日時／音声／表示は今回未確認のまま後続へ残す。

## 変更予定範囲・target・設定

下表は明示された実装工程の候補所有範囲。実際に着手するtaskごとにtasklistへ所有ファイルを記録する。新規ディレクトリの空生成はせず、必要ファイルが生じた時点で追加する。

| 範囲 | 変更責務／所有 |
| --- | --- |
| `FrameRelay/Domain/Media/`、`Domain/Operations/`の連携新規型 | 本人意思・証拠・版・確認／失効・後続判定。既存撮影ID／規則は共有接点として単一所有者を指定 |
| `FrameRelay/Application/MediaOperations/`、`MediaIO/`、`Library/`、`Recovery/`、`Ports/` | 連携coordinator・gate・投影・復旧・Port。撮影P09所有の原本復旧を置換しない |
| `FrameRelay/Platform/Remote/`、`Network/`、`Playback/`、`TemporaryMedia/`、`Credentials/` | 選定済み標準APIのadapter。媒体取得は共通gateへ束縛 |
| `FrameRelay/Platform/LocalStore/`、`OriginalStore/` | T07はG2A上の連携永続化、T11はG2A／G2B上の内容世代・全内容識別・read lease／実解放を追加。原本書込・保存分類・撮影復旧を二重実装しない。撮影担当から所有ファイルを引渡し、並行所有禁止 |
| `FrameRelay/Features/Library/`、`Features/Playback/`、Composition、`ContentView.swift` | 必要導線と組立。撮影探索との入口共有はT01で所有を一本化 |
| `FrameRelayTests/`、`FrameRelayUITests/` | 契約・store・状態・UI・失敗注入。fake／fixtureはtest target内だけ |
| `FrameRelay.xcodeproj/project.pbxproj`等 | 現3ルートはfilesystem同期groupでApp／unit／UI targetへ所属。追加時にtarget・resource扱いを確認。新project／target／package不要。既定MainActor／Approachable Concurrencyも既存設定を維持 |
| MediaVault `backend/app/api/`、`schemas/`、`services/`、`repositories/`、`workers/`と対応test | T06で再利用／変更／新規の実ファイルを固定し、T06A／T08／T14／T17に単一所有を割り当てる。外部repo書込み許可と隔離が前提 |
| `docs/`の永続6文書 | T25で安定した要求・構造・規則・用語だけ同期。入力仕様は更新しない。仕様変更が必要なら別の明示workflowへ戻す |

既存camera／microphone説明、生成plist、iOS／Swift設定を維持する。通信用途説明、ATS例外、Background Modes、entitlement、秘密保護属性はT05／T06のSDK・実機結果に応じた必要最小限を判断する。全接続例外や能力の一括追加を前提にしない。

## 実装順と完了判定

T01〜T03で契約、T04〜T06で隔離した早期通信判断、T06Aでサーバー初回登録、T07／T07Aで端末永続化・初回登録確定を行う。T08〜T12で保存証拠・転送と撮影原本access、T13〜T16でLog・品質合意と軽量版、T17〜T22で配布／公開・確認・状態同期／再登録・後続契約、T23〜T26で実結合と追跡を行う。全28task。T08はT06A後に独立先行でき、T09はT07A後に原本access fakeで完了、T11がG2Cを作りT12が実原本を結合する。依存しない契約／fakeやサーバー作業は撮影ゲート待ちでも進められる。書込みtaskは原則1件ずつ進め、実ファイル所有を重ねない。

実装完了はコード・必要自動チェックの範囲、検証工程完了は実行可能な必須ケースの証跡と解決状態、PRD達成は対応ACの全条件・品質適合で別記する。実機未実施、品質未選定、成立不能を残したまま全体完了にしない。次の `$validate-implementation` は明示呼び出しで行い、計画・実装から暗黙に開始しない。
