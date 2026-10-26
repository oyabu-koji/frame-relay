# Design — 実機なし先行実装の4段階

## 現状と設計の範囲

2026-10-01 の読み取り調査に基づく計画である。Swift／SwiftUI と既存3 targetを使い、依存追加・独自 project 生成を行わない。保存方式の内部比較、交換可能な候補接続を実装時に進めるが、実機方式・品質・未合意の製品挙動を採用済みにしない。

| 現在のファイル・境界 | 再利用する部分 | 不足と今回の処理先 |
| --- | --- | --- |
| `Application/Capture/CaptureLifecycle.swift`、`RecordingSaveLifecycle.swift`、`Application/Recovery/CaptureAudioRecovery.swift` | REC／WB／音声／保存分類の独立規則 | 製品 coordinator、再起動復旧、実撮影接続は S12／S41〜S43 |
| `Domain/Capture/`、`Domain/Media/RecordingEvidence.swift`、`Domain/Operations/CaptureIdentity.swift` | 希望・能力・実適用、ID・世代・時刻・観測限界 | 製品設定復元、AF／ND／ズーム等の値と根拠を追加。既存IDを重複定義しない |
| `Platform/LocalStore/ExplorationRecordingStores.swift`、`RecordingStoreDocument.swift` | file候補／Core Data＋SQLite候補、schema 1、意図 revision 1→結果2、未知schema／破損拒否 | S11で実diskを評価して同じ正本を拡張。端末の連携専用別DBを作らない |
| `Platform/OriginalStore/ManagedOriginalStore.swift`、`AVOriginalInspectionAdapter.swift`、`ExplorationRunDirectory.swift` | 予約、安全なURL解決、SHA-256、Reader検査候補 | 内容世代・lease・全解放・削除／照合・実原本の完全性は未実装／未確認。S12／S13／S32／S33 |
| `Application/Ports/BackendMediaPorts.swift`、`MediaOperationStorePort.swift`、`OriginalOperationOrderingPort.swift`、`RemoteStatusPort.swift` と連携 Domain | T03の型付き契約、固定対象・登録・確認／失効・公開・後続順序 | 製品adapter、wire、永続化、通信・実再生・Photos・削除は未接続。PlaybackSourceはremote／temporary renditionのみで、S13で原本再生契約を追加 |
| `Platform/Capture/NativeExplorationCapture.swift`、`Application/Capture/ExplorationCoordinator.swift` | Movie出力／sample writer候補、適用読戻し・WB順序・探索記録 | 音量は `level_measurement_not_implemented`、実ズーム・レンズISO・AF・ND・製品復元は不足。候補をS41〜S47で拡張する |
| `Platform/Render/ExplorationDisplayBoundary.swift` | Rec.709未実装を拒否する境界 | 標準変換・表示はS48。未取得資材で成功を返さない |
| `Composition/ExplorationComposition.swift`、`ContentView.swift`、`Features/Capture/ExplorationView.swift` | 探索専用の窓口・履歴 | Live factoryはticket必須・Simulator拒否・毎回別run。製品一覧の起動条件に流用せず、S16で製品Compositionを接続。探索の背景停止を製品背景通信の仕様へ流用しない |
| `FrameRelayTests/`、`FrameRelayUITests/ExplorationFlowTests.swift` | 規則・disk・合成Movie・探索UIの部分試験 | 新機能の本体実I/O・UI・境界試験を追加。古い証拠の対象版・現存をN00で照合 |

上表の App 相対パスは全て `FrameRelay/` 配下。Library／Playback／Connection、MediaOperations／MediaIO、Network／Remote／Photos／Credentials／TemporaryMediaの製品実装は現在ない。名前だけの空ディレクトリは作らず、必要ファイルを各タスクで割り当てる。

MediaVault は旧 T01 の `/Users/oyabu/dev/rep/latest_template`、記録revision `c56d4a2` を調査根拠とする。稼働版や現行実データの配置を推定しない。`backend/app/services/upload_sessions.py`、`upload_finalize.py`、固定result配信、job／repositoryを再利用する。`upload_finalize.py` の組立hash→replace→DB→jobをそのまま保存証拠にせず、最終保存先の独立全内容読戻しを追加する。外部repoの書込み・listener・実機接続は旧T04のin-process許可から派生しない。

## 状態・責務・単独所有

以下のApp相対パスは `FrameRelay/` 配下、`FrameRelay.xcodeproj` とtestはrepo相対、MediaVaultは指定された外部checkout配下とする。mainは新tasklistと判断・差分統合を所有する。実装時は以下の責務所有者に具体agentを割り当て、書込みタスクは原則1件ずつ進める。同じファイルをconsumerへ渡して並行変更しない。必要な共同変更は責務所有者へ依頼し、task単位で引渡しを記録する。

| 所有キー | 単独所有ファイル／ディレクトリと責務 | 引渡し時点・consumer |
| --- | --- | --- |
| O-STORE | `Platform/LocalStore/ExplorationRecordingStores.swift`、`RecordingStoreDocument.swift`、新規 `Platform/LocalStore/MediaOperationStoreAdapter.swift`、`Domain/Media/RecordingEvidence.swift` の永続表現、store用test | S11の同じwriterをS13の内容対応schema／commandとS21の連携commandへ拡張する。S13では内容対応commit→instance破棄→再open照合の証拠をO-ORIGINALへ渡し、S21全体完了を待たせない。S31／S32／S33のPhotos・削除commandも同じwriterへ追加。schema更新は常にO-STORE |
| O-ORIGINAL | `Platform/OriginalStore/`、`Application/Capture/RecordingSaveLifecycle.swift`、新規 `Application/Recovery/OriginalRecovery.swift`、新規 `Application/MediaOperations/{CleanupCoordinator,DiscardCoordinator}.swift`、原本／削除test | S12で保存分類・再open、S13で内容identity・lease・orderingの試験ファイル証拠を渡す。S41→A01／A02で実撮影G2B結合、S32／S33で実削除を同じ所有者が追加 |
| O-PORT | `Application/Ports/` 全共有契約、既存連携 `Domain/Media/{OriginalDescriptor,OriginalReadAccess,VerificationEvidence,ConfirmationRecord,TemporaryMediaReceipt}.swift`、`Domain/Operations/` の共有ID・commit・ordering・登録・配布値 | N00でT03の未追跡成果も保護して受領。S13で原本再生／lease、S21でstore、S22以降でwire／adapter境界を順次消費可能にする。既存撮影IDの変更もこの所有者と調整 |
| O-COMPOSE | `Composition/`、`ContentView.swift`、`FrameRelayApp.swift`、`FrameRelay.xcodeproj/project.pbxproj` | S16で製品store／原本／一覧／再生を1回組立。S28／S34／S49／S4Vで追加接続だけを直列反映。S34は写真／整理／破棄の必要下位処理が揃った操作から接続し、他操作の未完了を待たせない。project用途文・背景設定もこの所有者のみ |
| O-LIBRARY | 新規 `Features/Library/`、`Features/Playback/`、`Application/Library/`、`Platform/Playback/` と対応test | S14／S15からS28・S31の権限理由UI・S34の操作別接続へ同じ画面／projectionを直列引渡しする。破棄履歴の重複画面storeを作らない |
| O-IOS-BI | 新規 `Application/MediaOperations/`（`PhotoSaveCoordinator.swift`、`CleanupCoordinator.swift`、`DiscardCoordinator.swift`を除く）、`Application/MediaIO/`、`Features/Connection/`、`Platform/{Network,Remote,Credentials,TemporaryMedia}/` と対応test | S22C以降で端末登録／通信／確認を接続。共有store／Ports／Compositionへ直接重複所有しない |
| O-PHOTOS | 新規 `Platform/Photos/`、`Application/MediaOperations/PhotoSaveCoordinator.swift` とPhotos関連test | S31の登録下位処理・権限処理を既存契約と試験実媒体で先行し、S21 writer接続、S25一時媒体との製品接続を別substatusで引渡す。S34の写真接続は必要な全引渡し後に完了する。O-IOS-BIと同じ新規ファイルを割り当てない |
| O-CAPTURE | `Application/Capture/`（RecordingSaveLifecycleを除く）、`Application/Recovery/CaptureAudioRecovery.swift`、`Domain/Capture/`、`Platform/{Capture,Render}/`、`Features/Capture/` と関連test | S41〜S48。原本writerはO-ORIGINAL／O-STOREへcommandを渡す。共有PortはO-PORT。解析結果は記録映像と別経路 |
| O-SERVER | 合意した隔離checkoutの `backend/app/{api,schemas,services,repositories,workers}/` と対応test・隔離設定。実ファイル割当はS20で固定 | S22の登録→S24の受信保存→S26J周辺／S26変換→S27全公開経路。登録／保存はG2Bを待たない。外部書込み許可がない時は具体差分案・隔離snapshotまでで止める |
| O-DOC | 各Mタスクに記載した文書だけをdocument_authorが単独所有。旧steeringは各明示prepareのfeature_planner | 永続文書は新implement内の該当Mタスク。旧Ideas／旧steeringは別明示Workflow。新進捗はmainだけが更新 |

上記で新規ファイル名は計画上の割当名。実装開始時に現存・適合を確認して必要な変更だけ行う。既存未コミット内容と重なる変更は、内容と所有の保護方針が確定するまで該当ファイルを止める。

## 共通保存・原本・非同期処理

S11は既存 Core Data＋SQLite の `SQLiteRecordingStore` とfile候補をdisk commit／再open／破損・世代・中断で比較し、理由付きで共通store内部方式を決める。第一候補は既存 SQLite候補の拡張であり、独立した連携DBや巨大な万能UI状態は作らない。schema 1 の意図／結果を失わず拡張可能な構造とmigrationを使い捨てstoreで検証する。未知schema・破損を空storeへ置換しない。端末保護・電源断耐久性はこの比較の採用理由と分けてDV-02へ残す。

writerはdisk transaction完了前にcommittedを返さない。操作ID・対象・期待revision・payloadで再照合し、確認＋outbox、失効tombstone＋ACK outboxを同じcommitにする。Photos意図／結果、削除意図／結果、内容対応はこのwriterのcommandとして追加する。ViewModelの値、diagnostics、HTTP成功を正本にしない。

S13の内容対応は、O-PORTが共有値・command契約、O-STOREがS11の単一writerのschema／command・再open試験、O-ORIGINALが実ファイルとの照合・lease consumerを担当して直列に引き渡す。内容世代・原本参照・全内容識別の対応をcommitし、store instance破棄後の再openで同じ対応と不一致拒否を確認してからS15等へ渡す。S21の登録・確認等の完成はこの引渡しの条件にしない。S13とS21の実行順によらず、O-STOREが先行schemaを継承し内容対応の別正本を作らない。

原本は予約→保存意図commit→記録→記録終端→ファイル確定→検査→結果commit→再open照合の順。映像／音声／Log／完全性の取得不能はunknownを保持する。内容世代は実ファイル内容に結び、撮影設定世代・store revision・再起動で置き換えたり再採番したりしない。全内容digestは読取り安定区間のファイルに対して計算し、登録済み内容identityとの不一致を拒否する。

S41の保存結果commit応答までは撮影側の安全終端として次RECを抑止し、以後はCompositionが保持する撮影coordinator内の`ProductCapturePostSave`が原本参照固定の単一queueでbind→一覧更新を所有する。後処理は離脱・次RECでも存続し、現クリップやRECゲートへ成功/失敗を書き戻さない。全内容digestを予約actorから専用actorへ分け、同一FD・64KiB逐次全量読取り・前後stat・取消検査を維持する。一覧の追加refresh要求は保持し、未bindingは原本対応の要照合として保存分類/削除状態と区別する。未binding原本の転送・容量整理・原本再生を拒否し、保存結果と実ファイルを保持して再起動時はread-onlyで表示する。自動再bind・新規再試行UI・schemaは追加しない。実機速度・品質は未確認であり、DV-11で別に評価する。

原本ごとのorderingはread lease、削除予約、失効の順序を共有する。新規読取りを止めたうえでupload・player・検査等の全readerを取消し、SDK完了通知とhandle解放を照合してから削除へ渡す。cancel呼出し／通信停止要求だけを解放済みにしない。削除結果不明の予約は、実ファイルと記録の照合完了まで失わない。撮影中のwriterも終端・保存分類が確定するまで削除しない。

SwiftUIはMainActor上の投影・操作受付を扱い、長いhash／DB／媒体処理をViewに置かない。既存のSwift5、MainActor既定・Approachable Concurrency設定の下で、I/Oの専用actor／queueとSendable値境界を明示する。非同期callbackはclip／操作／内容／登録／版／世代を照合し、古い結果を現行状態へ適用しない。task cancellationと外部操作の実完了・結果不明を区別する。

## ライブラリ・再生・通信・公開

ライブラリは原本保存状態、原本の現在存在、転送／保存検証、軽量版公開／取得、確認／失効、写真登録、整理／破棄の独立状態を単一storeから投影する。転送・写真・整理は固定選択集合を開始時に記録し、複数結果を個別表示する。原本再生・軽量版再生／確認・破棄は単数。原本／撮影プレビュー／構図予告の閲覧では軽量版確認を生成しない。

原本再生は `OriginalAccessPort` のlease付きローカルsourceを、軽量版は固定rendition identityのsourceを使用する。AVPlayer等の標準経路で再生開始・進行・停止・解放を検査する。テスト用の再生可能fixtureを成功するデータreceiptへ置き換えない。取得済みローカル媒体はオフラインで再生でき、未取得媒体は理由を示す。

端末の接続先／登録意図→サーバー登録／結果照会→端末commitを初回基盤にする。登録応答欠落は同一意図で照合し、通常再起動と新登録を分ける。Keychain等の標準資格情報保管候補を使い、秘密をstore／ログへ平文複製しない。具体API・schema・認証の採用はS20／S22の現行契約照合と隔離試験で記録する。

全媒体経路（原本、軽量版取得、streaming／一時取得、サムネイル）を同じ通信gateへ接続する。媒体を含まない状態同期は別gate。Wi-FiとVPN基礎回線、本人停止／取消、REC／保存、対象固定、結果不明を再開直前にも確認する。OSが許す背景upload／downloadと復帰callbackを実装し、実OS成立はDV-12へ残す。Macの既開始検証／変換をRECで止めず、Mac ACKをREC開始条件にしない。

S20で既存Range全hashとwriter競合を再観測し、内容同一性を守る検査と短い配布／公開確定区間を設計する。計画時に検査省略・負荷閾値を決めない。固定版配信は新要求の受理時に現公開版照合と配布台帳commitを行い、全公開pointer更新は期待世代＋全必要失効ACKを通す。公開前に受理した旧版応答と公開後の旧版新要求を分け、前者も必要ACK／実停止・解放と競合試験する。

サーバーの全公開経路は既存 `processed_result_finalizer.py`、`formal_preview_finalizer.py`、`rendition_finalizer.py`、`processed_result_backfill.py`、`repositories/processed_results.py`、migration／workerを列挙し、抜け道をなくす。V2候補生成は公開ではない。失効前V1は保持し、失効commit後は失敗・再取得でも旧確認を復活しない。応答不能旧登録のACKを新登録で代用しないが、別動画を止めない。

## Photos・削除

Photos追加は、同一軽量版の完全取得と使用権→登録意図commit→必要時add-only権限→実Photos登録→結果／local identifier照合→管理commit→不要一時媒体解放とする。登録直後中断では追加結果不明を保持し、必要な理由と対象を示してreadWrite権限を案内する。限定／拒否・対応不明・読取可能でも未発見は未保存の証明ではない。写真側存在と過去登録成功を分け、手動再保存の未合意意味は追加しない。

S31の登録下位処理・権限UIはN01と既存T03契約から開始し、試験実媒体を用いた実行可能SimulatorのPhotos操作を先行する。S21との永続接続、S25との完全取得媒体・使用権の製品接続を別substatusにし、未接続は製品成功にしない。S34の写真／整理／破棄UIも別substatusで管理し、整理はS32、破棄はS33の実接続・検証が揃い次第、S16の同じCompositionへO-COMPOSEだけが直列接続する。Photosの未完了は両削除操作の引渡しを止めない。S28との追加導線は当該接続だけに依存し、S34全体／S3Vのdoneには全必要接続と検証を要求する。

整理は動画別の最新ローカル保存証拠・確認・内容対応・失効を再判定して本人指示をcommitする。破棄はこれらの成立不要だが対象と消失リスクを単数で確認する。両方ともordering予約→実停止／全解放→実unlink→ローカル結果照合→commitを通る。媒体とDBの一括原子性は仮定しない。中断後は存在と記録から削除済み／未削除／要確認を示し、未実行削除を自動実行しない。整理成功は通常一覧、破棄成功だけ履歴。不明は要照合として通常の作業導線に残す。

## 撮影・解析・描画

既存二候補を交換可能に保ち、能力→希望→実適用→保存結果を結ぶ。標準4K24/30・LT／422／Proxy・実Log・補正の能力を仮定せず、製品撮影が不可でもライブラリ／設定／復旧が起動できるCompositionにする。人物なしAF・初回意図のS45合意は下記へ記録し、レンズ戻しISO基準・上限等の未合意重大判断は判断台帳へ残す。

S41の本人確定判断（2026-10-16）: 初回fpsは既定値を補わず未選択とし、本人が24/30fpsを選ぶ。選択後の希望設定は保存し、現在のカメラ・形式・能力scopeを照合して復元する。Movie出力とsample writerの二候補は交換可能に保持し、選択方式が非対応でも自動切替しない。二候補の製品接続とD01の実機正式採用は別に扱う。

暦上の撮影日時は、RECの準備条件を満たして本人のRECを受け付けた時点で一度観測する。`ProductCaptureFactory`が端末の暦時計をcoordinatorへ注入し、同じ観測をミリ秒精度へ一度揃えて保存意図と両記録候補のQuickTime creationDateへ渡す。保存完了・一覧更新・転送・写真登録の日時で置換せず、既存の単調時計`acceptedAt`とも区別する。旧記録に暦日時を補完しない。日時と設定の合意は、実カメラ能力・Log/ProRes・G2B・画質・標準Rec.709表示の受入を意味しない。

WBは記録終端まで固定し、本人再固定だけを許す。音声は音量・入力・到着・書込みを別々に実装する。障害確認で開始抑止／停止・可能部分保存、復旧は有限で手動RECへ戻す。解析は映像の解析用分岐を消費し、録画へ結果画像を戻さない。AFの主役・露出対象、NDの設定／WB／対象世代、ズーム予告のカメラ／補正／倍率世代を別に扱う。

S42の再固定制御（2026-10-17）: 録画中の本人操作を、現在の再測定能力が確認できる場合だけ受け付ける。後方互換のoptional能力がnilなら未確認を保持する。対応するSDKのone-shot `autoWhiteBalance`から`locked`への遷移を観測し、現在gainの固定適用完了を再固定の確定に使う。固定秒数・品質閾値は導入せず、機器のmode/custom gains対応を照合する。測定中のSTOPは観測を失効させて現在gainを固定し、適用完了後に記録停止へ進む。旧context/tokenの観測・適用callbackは拒否し、記録終端後だけ待機Autoへ戻す。露出値は変更せず、次クリップは新しく測定する。実機の色・連続性・最終フレームの対応はDV-03で別に評価する。

S43の音声接続（2026-10-18）: 両記録候補で観測用AudioDataOutputを使い、到着した実sampleの形式に従って音量を算出する。入力確認・到着・書込を別軸とし、無音sampleは正常到着、メーター解析不能は音量未確認のまま扱う。Movieへの書込成功は観測用sampleから推定しない。最新1件の音声snapshotと障害/記録終端の制御通知を分け、セッション/設定世代・クリップ・単調な通知順序で旧結果を拒否する。音声障害は停止通知より前にNativeで保持し、先行するWB故障も成功へ戻さない。録画終端・保存結果・WB Auto復帰を確認してから、本人操作による音声入力/出力だけの復旧を試みる処理を設ける。実sampleの再到着で成功を判定し、時間切れ/離脱では旧試行を失効させ、SDK所有の終了が確認できるまで次REC・重複試行を抑止する。

無到着の猶予と復旧回数/時間は注入契約で分離する。2026-10-18に本人が暫定案を承認し、無到着2秒、本人の再試行操作ごとに音声入力/出力だけ1回再構成、復旧上限5秒を変更可能な製品設定として合意した。復旧中も2秒の無到着判定を適用するため、5秒は成功待ちを保証する時間ではなく試行全体の上限である。ProductCaptureFactoryが版付きの同一policyをNativeとcoordinatorへ明示注入する。失敗後の再試行には改めて本人操作を要し、タイムアウト後もSDKの処理終了まで次REC・重複試行を抑止する。製品接続・関連検証の進捗はS43に記録し、実音声/同期/OS障害・復旧品質と数値の実機採用はDV-10へ残す。U7の他の負荷・容量判断はこの合意に含めない。

S44の補正接続（2026-10-18）: 既存SDK候補IDと保存希望を保持し、PRDの初回標準第一候補を変更可能な設定下書きへ反映する。候補をカメラ・4K・fps・Logで絞り、コーデック/記録方式を含む出力接続の対応と実適用はprepareで別に照合する。初回候補やformatの対応一覧を実機での効果・品質採用へ昇格させず、非対応の希望をOFFや別方式へ無断置換しない。preview専用候補は現在の4K記録へ適用せず理由を示す。

NativeはMovie/sample writerの記録connectionを確認し、preferred要求とactive読戻しを分ける。補正・実倍率・format・主カメラ・セッション状態の変更を世代/連番付きsnapshotで渡し、Applicationは旧世代/逆順/別希望scopeを拒否する。失効後も同世代の通知高水位を保持し、再準備/離脱で旧画角を捨てる。REC受理前と原本予約後の実開始直前は共通規則で希望/出力/カメラ/寸法/倍率/準備時formatとの一致を再確認し、録画中に希望値を書き戻す補正変更は行わない。画面は準備時の適用値と現在の補正観測を分ける。

S47への供給は画角revisionと観測条件までとし、formatの水平FOVを補正後cropへ換算しない。補正後画角は取得不能、独立したpreview connectionと記録の画角一致はOFFでも未確認として保持する。これらの未観測だけをREC阻害条件へ追加せず、構図予告/停止支援consumerの接続はS47、補正効果/構図/同期/継続性はDV-04の実機評価に残す。S44の実装・自動検証進捗はtasklistを正本とする。

S45の本人承認（2026-10-18）: 人物がいないときはプレビューでタップした位置へAFする。撮影意図は初回に本人が選択し、選択後は保存・復元する。未選択・保存中・人物未確定・解析待ちをRECの阻害条件にしない。見失い猶予は変更可能な暫定3秒とし、猶予中もピントを保持し、同じ主役と確認できた場合だけ復帰する。期限後は保持したまま本人の再指定を待ち、別人へ自動移行しない。`ProductCaptureFactory` が版付きの同一 `CaptureSubjectPolicy` をNativeとcoordinatorへ注入する。撮影意図と露出対象の選択はISO・シャッターの自動変更を意味しない。

人物候補・主役・特徴量はセッション内だけに保持し、永続的な人物台帳を作らない。撮影意図だけを既存設定storeへ保存する。解析は処理中1件と置換可能な待機1件に制限し、古い世代・逆順・期限超過の結果を拒否する。SDKの検出/追跡IDや画像特徴量は人物同一性の保証にしない。技術的な画像照合閾値は変更可能な実装設定であり、3秒の本人承認やSimulator試験を実機品質の採用へ昇格させない。合焦・前後追従・別人通過・同一主役再捕捉・人物優先AF・距離/照明・補正cropとpreview座標・Log入力・継続/負荷はDV-06で未確認として残す。Simulatorで別画像から同一FeaturePrintと初回微差を観測したため、固定参照の同一ROIから上限2回取得した特徴量と、Visionとは独立した実画素digestを照合する。特徴量が完全一致しても実画素が異なる場合は同一IDの継続・再捕捉を拒否する。距離閾値は緩和せず、別画像で固定参照を更新しない。raw bufferを追加保持せず、digestはセッション内だけに置く。SimulatorのSDK内部原因は未確定で、この防御をSDK自体の修復と扱わない。同じ人物も画素変化と特徴量衝突で保持になり得る制約、2回生成の追加負荷は実機未確認として残す。S45の接続・検証結果はtasklistに記録する。

S46の本人承認（2026-10-18）: 入力信号別の交換可能な暫定基準で、撮影意図に応じた対象からND方向・理由・両立困難を参考表示する。結果の有効期間は入力映像の観測時点から暫定1秒とし、新しい結果が得られなければ旧案内を取り消して保留を示す。これは端末内リアルタイム解析の鮮度管理であり、バックエンドへの要求や通信を使わない。`ProductCaptureFactory` が `CaptureNDPolicy.provisionalV1(maximumResultAge: 1)` の同じ版をNativeとcoordinatorへ注入する。NDの保留や警告をREC開始・継続の条件にせず、露出設定・WB・物理ND・録画映像へ書き戻さない。

実画素の符号値による未校正の基準であり、正確なND段数・EV・IRE・センサー余裕の測定ではない。信号のattachment、全体/各選択人物/背景、WB・構図・選択・解析失効の世代と単調時刻を照合する。変更や停止の観測時刻より前の入力は新contextでも受け付けず、KVOの変化通知がA→B→Aに戻っても失効する。この時刻境界はフレーム固有のWB gainを証明せず、Auto WBが変化し続ける間は保留が続き得る。基準・1秒・実写の方向一致・入力信号・ROI・WB・負荷の実機評価はDV-07へ残す。実装・製品接続・自動検証はS46に記録し、FR-06受入や実機採用へ昇格させない。

ズームは目標選択時点では実倍率を変えない。制御中の観測実倍率で目標超過を防ぎ、目標・途中停止を同じ制御器へ渡す。停止支援候補は実カメラ・形式・解像度・補正の根拠付きとし、整数倍率だけで品質保証しない。設定は目的・根拠・適用範囲・版・変更箇所・未採用フラグ付きの暫定値、DV-08後の採用値を別記録する。数値・吸着方式・詳細設定画面を計画で追加決定しない。

D02資材は由来・版・利用条件・入力Log適合を先に確認する。資材適合待ちはS26変換本体／S48表示変換だけへ局所化し、周辺版管理・描画分離・既知入力機能試験を先行する。既知入力の技術試験は本人の画質採用試験ではない。出力1080p HEVC等は候補のまま、G3事前合意→DV-13評価→G5採用を維持する。

## ゲートと直接依存

`C-Gxx` は旧撮影の `G01〜G06`、`B-Gx` は旧backendの `G0〜G6` を示す。`D01〜D05` は旧撮影方式論点、tasklistの `A01〜A18` はDV実施タスクであり、文脈を接頭辞で区別する。機能設計のT01〜T21も旧backendタスクとは別体系である。

| 条件 | 非実機で引き渡せるもの | 保留する直接対象／再開条件 |
| --- | --- | --- |
| C-G01／G02、P02／P03 | 許可済み範囲の再利用、実行票schema・開発構成 | 実機操作の環境・対象・証拠先未束縛部分だけQ01で束縛。既存新規試験媒体の許可を毎段取り直さない |
| C-G03、撮影D01／D03、P07 | 標準SDK候補・規則・接続・自動検証 | 実方式採用・実能力受入はDV-01／04／09。独立したS11以降を止めない |
| 撮影D04／B-G2A | S11／S12の単一writer・disk commit・再open・障害・所有引渡し | DV-02の端末保護・実中断が残ることを明記。G2A全体通過としない |
| B-G2B | S12の試験保存結果consumer／S41候補接続 | 実撮影の正常／部分／不明／失敗・復旧・REC保存事実はDV-01／02で確認。実原本転送受入だけここへ依存 |
| B-G2C | S13の使い捨て実ファイルによる内容世代・全内容識別・read lease・全解放 | 実原本との結合はG2B後のDV-12。fixture証拠をG2C実原本受入へ昇格しない |
| B-G0／G1 | S20の具体隔離範囲、host／Simulator実通信・認証・固定版実再生・Range・停止観測 | 外部listener／実機接続／実回線・背景・保護・REC負荷はQ01／DV-12で確認。独立store・サーバー登録／保存を待たせない |
| 撮影D02、C-G04、B-G3／G5 | 資材調査、標準変換の既知入力機能試験、比較案 | 資材不足は変換処理のみ。品質は素材・表示・比較・許容条件の事前合意後にDV-05／13。採用は結果に基づく |
| B-G4 | 保存・確認・失効・登録・削除のdisk／隔離境界試験 | 実端末の未確認境界はDV-02／14／16／17。完了条件は緩和しない |
| C-G05／G06、B-G6 | 暫定可逆判断、全AC追跡・局所保留 | 重大製品判断は局所相談。全工程／PRD／初期版完成はH02で別判定 |

## Error handling

不明／失敗はoperation・対象・段階・理由・再試行／照合の次操作を保持する。共通認証／回線／store障害は影響する集合を待機し、個別媒体の失敗では独立動画を続行する。保存・公開・写真・削除の応答欠落を未実行や成功へ丸めない。破損・未知schemaは証拠を保持して停止する。ログにはtoken・私的媒体・顔画像を入れない。

## Test strategy

| 層・証拠キー | 必須の意味ある確認 | 限界・実機引渡し |
| --- | --- | --- |
| V-STORE | 実disk commit→instance破棄→再open、未知schema／破損、競合revision、各commit前後中断、outbox永続化 | in-memoryだけ不可。端末保護・OS実終了はDV-02 |
| V-ORIGINAL | 合成で再生可能な実ファイルの保存分類・内容identity・複数lease・停止完了・全handle解放・digest一致 | fixtureのsavedは実撮影G2Bではない |
| V-PLAY | 実AVPlayerで原本／固定renditionの再生進行、途中停止・解放、認証失敗／古い版／オフライン、使用量観測 | Rangeのbyte成功だけ不可。実回線／OS停止はDV-12／14 |
| V-SERVER | 隔離DB／media／tmp／worker／port／認証／設定を事前確認し、実HTTP送受信→最終保存先の独立全内容比較→再起動照合 | 旧T04はin-process限定。listener・別rootの実効隔離を再確認。稼働環境への適用不可 |
| V-PUBLISH | 配布commit／公開pointer競合、全必要ACK、別／古い登録ACK拒否、V1/V2・失効前後・応答欠落・再起動・outbox | 全公開経路が同じgateを通る。旧T05 descriptor継続も再試験 |
| V-PHOTOS | 意図／追加成功／管理commit境界の障害注入＋実行可能Simulatorで実Photos追加・照合、権限UI、連打・不明時非再追加 | fakeだけでadapter完了不可。OS権限・限定・写真側削除はDV-16 |
| V-DELETE | 許可された使い捨て実ファイルのunlink、再open、削除前中後の中断、失効との両順序、全reader解放、一覧／履歴 | 外部非削除と未実行非再開も確認。実機対象は個別許可後DV-17 |
| V-CAPTURE | 既存reducer・候補の規則、設定復元、WB／音声境界、AF／ND代表入力、古い結果、ズーム予告／停止、標準変換既知入力 | 実能力・色・合焦・滑らかさ・負荷の合格は実機証拠のみ |
| V-UI | 状態・理由・次操作、複数3操作／単数操作、二重入力、権限、整理後／履歴、不明、文字サイズ・読み上げ | Simulator不能は理由・再開条件を残す。build成功を操作済みにしない |
| V-REVIEW | 変更diff・source版・要求・実I/O・未接続・所有・診断をmainがレビューし、指摘／対応／残件記録 | 通常レビュー。独立validationは明示 `$validate-implementation` とimplementation_validatorで別途read-only |

各タスクは関連するbuild／診断・意味ある単体・上表の結合／UIを実施する。S1V〜S4Vは段階の接続・版一致・レビュー漏れを確認し、既に通った不変範囲を理由なく再実行しない。必要試験の失敗・未実行が残る当該本体タスクはdoneにしない。

projectにはApp／Unit／UIの3つの `PBXFileSystemSynchronizedRootGroup` があり、同名targetへ対応する。新Appコードは `FrameRelay/`、fixture／fakeは `FrameRelayTests/`、操作testは `FrameRelayUITests/` へ置く。scheme／test planは静的ファイルだけで決められないため、N01で実在する入口・Build/Test action・configuration・対象・destinationを確認してからコマンドを確定する。旧Simulator UUIDを固定しない。

O-COMPOSEは撮影用途文を製品操作と整合させ、Photos追加／読み取り用途文、採用した標準通信に必要な背景設定だけを追加する。過大なATS例外や不要なBackgroundModes、Team／言語／OS変更で問題を回避しない。

## 実装順・判断記録

N00／N01→S11〜S16を基盤にし、S13の内容対応永続化はO-STOREがS11を拡張して先行引渡しする。S20からはS22サーバー登録・S24保存を端末storeや実原本から分離する。S21共通store拡張＋S22サーバー登録→S22C端末commit、S13＋S23＋S24→試験ファイル転送、S25固定版実再生→S27確認／失効へ進む。S31はN01／既存契約から下位処理・権限UIを先行し、S21永続接続とS25媒体接続をFinishへ分ける。S34はS14から画面を先行し、S31の写真、S32の整理、S33の破棄を各別に同じCompositionへ接続する。S28の全完了やPhotos待ちを削除画面の前提にしない。S41〜S48もN01／既存契約から独立部を開始し、実接続完了の依存をFinishへ分ける。S49はS41／S23だけでREC・保存と実通信を接続し、表示資材・AF・NDを待たない。S26Jのjob／版周辺はS26変換資材待ちと分離する。直接依存と部分引渡しの詳細はtasklistを適用する。

| 判断種別 | 記録・進め方 |
| --- | --- |
| 軽微可逆 | 配置、表示順、内部adapter分割、版付き試験設定は根拠・適用範囲・変更箇所・未採用性をtaskに記録して進行 |
| 内部方式 | 既存store拡張／wire／配信負荷改善は実効契約・disk／隔離証拠で選定。実機未確認部分を採用理由へ含めない |
| 重大／未合意 | S45承認外のAF詳細、ISO基準／上限、実機必須方式、権限による再保存意味、要求縮小・消失判断は対象処理だけ保留しmainから相談 |
| 品質採用 | Q01で組合せ・場面・操作・比較・測定・許容範囲を事前合意し、DV結果・条件版に対応。後付け閾値で過去結果を合格化しない |

各記録は `判断ID／対象task・AC／根拠／候補／暫定か採用か／影響／再開条件／担当／版` を持つ。未合意項目は全体のconfirmedを取り消さず、依存する処理の状態へ残す。
