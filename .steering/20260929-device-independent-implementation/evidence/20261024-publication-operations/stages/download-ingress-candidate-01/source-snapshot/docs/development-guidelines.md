# Development Guidelines

## 基本原則

- [PRD](product-requirements.md)の全21要求・79受入条件（FR-01〜FR-17、NFR-01〜NFR-04、全P0）を維持する。既存76条件のIDを維持し、補足R3のAC-FR-11-04・AC-FR-14-07・AC-FR-15-05を含む。撮り逃しの抑制、設定・音声・原本の保持、操作結果の復旧、対象を取り違えない手動削除を優先する。技術的に成立しない条件は制約・代替案を示し、要求の再確認へ戻す。
- 技術前提は[PROJECT_CONTEXT.md](../PROJECT_CONTEXT.md)、責務と不変条件は[アーキテクチャ設計](architecture.md)、配置と参照方向は[リポジトリ構造](repository-structure.md)に従う。本書はその実装・レビュー・検証規約であり、機能要件や技術候補を新たに確定しない。
- 人間が作成した既存Xcode projectを利用する。外部依存・ツール、別target/package、project generatorを標準導入しない。必要な追加は必要性と範囲を合意してから行う。
- 実装前に対象仕様と `.steering/[YYYYMMDD]-[task]/` の `requirements.md`・`design.md`・`tasklist.md` を読む。実装中はtaskの完了と検証証跡を都度同期し、安定した要求・設計・用語・規則の変更は関連する `docs/` へ反映する。Workflowの開始条件と専門agentの役割は[AGENTS.md](../AGENTS.md)に従う。
- 本書は2026-09-25作成、2026-10-22に確定DIと実装証拠を同期した。機能設計U1〜U3の操作別の複数選択、streaming第一候補、既開始通信の条件付き自動再開、OS許可範囲の背景/ロック、媒体なしモバイル状態同期、個別失敗後の独立動画続行/共通問題の待機は確定事項とする。削除表示・Photos権限・ズームの確定契約、本人合意済み暫定設定も回答待ちへ戻さない。処理順/選択・停止UI、一時媒体の上限/期限、未合意のISOや品質値等は補完せず、実装・製品接続・実機品質の残件を分ける。
- DIの4段階（共通store/原本/一覧、連携/媒体制御/公開、Photos/削除、撮影/補助表示）は主な変更のまとまりであり、前段の実機合格や段階全体の完了を独立後段の開始条件にしない。[現行tasklist](../.steering/20260929-device-independent-implementation/tasklist.md)の直接依存・Start/Finish・substatus・部分引渡しに従う。実機・資材待ちは依存する処理だけに残し、必要検証の失敗/未実行は当該taskの完了を保留する。

## 開発環境

2026-10-22時点の実在構成・実行証跡と、実行のたびに確認する環境を分ける。実行版・実値・結果は現行tasklistを正本とし、以下を将来の固定環境にしない。

| 項目 | 確認状況・方針 |
| --- | --- |
| Language / UI / Platform | Swift / SwiftUI / native iOS |
| IDE / build system | 実行証跡ではXcode `27.0 (27A266a)`、Swiftコンパイラ `6.4`、iOS/Simulator `27.0` SDKを使用。使用時の選択・版は再確認する |
| 最低対応iOS・言語モード | iOS Deployment Target `27.0`、`SWIFT_VERSION = 5.0`を維持。言語モードをコンパイラのバージョンと同一視しない |
| ビルド入口 | [FrameRelay.xcodeproj](../FrameRelay.xcodeproj/project.pbxproj)。`project.xcworkspace`はproject内部の構成であり、独立したルートworkspaceではない |
| target / configuration | `FrameRelay`、`FrameRelayTests`、`FrameRelayUITests`の3 target。`Debug` / `Release`が存在する |
| 並行処理設定 | App targetに `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`、各targetに `SWIFT_APPROACHABLE_CONCURRENCY = YES`。既存設定を保持し、実際の隔離・診断は使用コンパイラで確認する |
| テストソース | [単体テスト雛形](../FrameRelayTests/FrameRelayTests.swift)・[UI雛形](../FrameRelayUITests/FrameRelayUITests.swift)を保持し、Domain/Application/Platform/IntegrationのSwift TestingとFlowsのXCTestが実在する。空の例・opt-in/skipと意味ある実行を分ける |
| scheme / Test action | CLIでscheme/test plan `FrameRelay`、App/Unit/UIの対象を確認し実行済み。repo共有 `.xcscheme`・`.xctestplan`は未配置であり、CLI確認と共有ファイルの存在を混同しない。各action・対象testは実行前に再確認する |
| 実行環境 | 専用iPhone 18 Pro/iOS 27.0 Simulator、generic iOS署名なしbuild、隔離backend/loopback HTTPに版付き証跡がある。destination IDは再確認する。実機・実回線/OS中断・稼働Mac miniの契約適合・実データ品質は未受入で、要求上の端末の利用可能性を推定しない |

今回の文書同期ではXcodeコマンド、build/test、Simulator・実機起動、外部接続、動画の生成・転送・削除を実行していない。既実行の証拠と今回の静的確認を分け、以下の手順は次の実装・検証時にも使う。

## コーディング規約

### Swift / SwiftUI

- 値と不変のsnapshotを基本にし、不在はOptional、有限の状態・待機理由・失敗はenum等の型で表す。保存・検証・変換・確認・失効・写真登録・削除の独立した状態を一つの `isComplete` に潰さない。
- アクセス範囲は必要最小限にする。同一module内の公開窓口は `public` を要求しない。内部補助は `private` 等で隠し、テストのためだけに本番の可視性を広げない。型から分からない副作用、所有権、commit・取消しの意味は契約のコメントに記す。
- 通常起こる失敗を強制unwrap、`try!`、無視する `try?` で隠さない。入力・能力・世代・外部応答を境界で検証し、未知schemaや状態を成功へ丸めない。
- Viewは表示、入力、画面内の一時状態を扱う。親所有値・Bindingと独自所有状態を区別し、表示状態はApplicationのsnapshotから作る。Viewの `body` や描画の再評価からI/O・削除・写真追加を起動しない。
- SwiftUIにUIKitのcontrolを混在させる場合は、SwiftUIのdisabled状態とnative controlの`isEnabled`を一致させ、引数の可否と`Environment.isEnabled`の両方を反映する。通常UIで状態更新後・再表示時の無効化と理由表示、実actionを確認する。本文全文・文字拡大・操作領域・IDを保持し、AX用の代替や監査除外で整合を代用しない。
- 希望設定、能力照会、実適用値、実機評価済み条件を分ける。UIの選択だけで端末へ適用済みとせず、非対応・未確認時に形式、露出、補正等を黙って代替しない。観測・解析・予告を原本への焼込みや本人の確認へ転用しない。
- UI更新はMainActorで行い、録画データ、ハッシュ、動画I/O、解析をUI状態更新へ載せない。既定MainActor隔離を踏まえ、端末APIの実行領域はPort内で明確にする。新API利用のために最低対応iOSやSwift設定を無断変更しない。

### 命名とファイル

- 変数・関数は `camelCase`、型・protocolは `UpperCamelCase`、真偽値は `is` / `has` / `can` / `should` 等で意味を示す。ID・世代・状態は対象が分かる名前にし、同じ意味の値型・規則を複製しない。
- Swiftファイルは主な型・責務に対応する `TypeName.swift`、テストは `TypeNameTests.swift` 等とする。配置と名称例はリポジトリ構造の「ファイル命名」を使い、内容の不明な `Manager` / `Utils` へ処理を集めない。
- 既存コードに合わせたインデント・改行を使い、変更箇所と無関係な整形をしない。コメントは判断理由・不変条件・制約を説明し、コードの逐語説明を増やさない。
- 追加・移動時は同期グループとtarget所属、資材参照を確認する。テスト用fake・fixtureをApp targetへ混入させない。フォルダの分割をmoduleによる依存強制と見なさない。

### 責務境界

| 責務 | 実装・レビュー規約 |
| --- | --- |
| View / Presentation | Applicationの公開command・snapshotを利用する。Platform具象、DB、HTTP、Photos、ファイル削除を直接呼ばない。高頻度の解析更新と読み上げ通知を分ける |
| Application | 撮影はCaptureCoordinator、媒体操作の更新権はMediaOperationsとOperationStoreに集約する。Libraryは読取投影、Recoveryは照合を担う。他担当へはcommand・型付きeventで連携し、内部状態を直接変更しない |
| Domain | 時刻・能力・証拠を入力として純粋に判定する。OS時計、SwiftUI、端末API、DB、ファイル、通信へ依存しない |
| Service / Adapter | `Application/Ports/` の契約を実装し、SDKオブジェクト、HTTP DTO、DB entityを境界内で値へ変換する。具象サービスの生成はCompositionに集約し、他adapterへの連携も注入されたPortを通す |

同じmodule内でも上記の参照方向を差分で確認する。汎用の巨大な共有状態や、任意の箇所から発火できる未型付けイベントで所有権を迂回しない。

### 非同期処理・操作の寿命

- カメラ構成・設定・開始停止は専用の直列実行領域、音声/映像sampleはAPIが要求する領域に閉じる。SDKオブジェクトをactor間で自由に渡さず、警告を消すためだけの `@unchecked Sendable` や隔離解除を追加しない。
- 非同期結果には操作ID、対象ID、内容/確認/解析の必要な世代を対応付ける。重複・逆順・古いcallbackは現状態へ無条件に適用せず、元操作の照合に必要な証拠を残す。二重入力防止はUIだけでなく実行側に置く。
- 原本転送・同じMac mini生成Rec.709軽量版のPhotos保存・条件を満たす容量整理は複数選択してまとめて開始/実行し、内部は順次処理でよい。開始受理時の対象集合を固定し、動画別の操作ID・対象/版・証拠・成否・未処理を保持する。選択だけの動画と指示済み順番待ちを区別し、未指示動画を後から追加しない。プレビュー再生・明示確認・不要動画の破棄は1本ずつとし、複数選択を確認の自動確定や一括破棄へ使わない。
- 原本転送のqueued受付は、同revisionのLibrary snapshotから親/全子ID・store UUID・commit済みの現登録・順序付きbinding/保存commitを最初のawait前に固定する。初期native Wi-Fiのunknown/cellular/offlineでは予約やmutationを作らず、この観測をstrict許可/VPN基礎回線証拠にしない。`observeFile`の短命FD statを使い、受付で全hash・転送lease・copy・SDK開始を行わない。commit後の存在/内容を保証せず、実senderの`acquireRead / openBoundRead`全hashと正常保存条件を別途要求する。capture中の受付は可能とし、known commit後だけ同じ背景factoryの`synchronizeCapture`で待機を投影し、実SDK直前のgateを省略しない。
- upload metadataは依頼別の明示操作と既知session GET-only状態同期を入口にし、constructor/再launchでHTTPを始めない。POSTはsession未確定かつ本人intentがrunningの場合だけとし、created応答をstatus/送信/検証へ昇格しない。GETの外部cancelledはtyped holdを保持してnotExecutedへ変換せず、応答から本人intent/waits・attempt/local transportを復元しない。nativeのsuspended data taskは構築/資格情報await後、`performUploadMetadataIfCurrent`の同writer同期callback内で現在UUID/登録・実query receipt・最新pending世代・本人意思/sessionを照合して直接resumeする。callbackに重い構築・await・redispatch・writer再入を置かない。1 API呼出しに最大1action、同owner内は保持Taskへ合流し、永続SDK開始済み証跡やstrict媒体の正のresumeの成立にしない。
- chunk範囲は完全binding/indexからchecked UInt64で導出し、decode時に再検証する。local producerはInt64/off_t非対応を拒否し、同じowner.lock namespaceと全内容照合済み原本FDから最大64KiBのpread/copyを使う。範囲の独立hashとwriter close後のchunk全読戻し/fingerprintを照合し、原本hashを代用しない。自分のcopy attachmentだけを終了してcaller leaseを保持し、unknown/部分leafの上書き・削除・再採用をしない。
- 新sourceはindirect uploadChunkとcompact metadata参照に限り、full snapshot/BackendStoreMutation/完全観測を埋め込まない。実query/observeのkey/fingerprint/receipt/UUID・現登録を同writerでexact joinし、最新GET/receiving・完全binding・未受領index・pending/holdなしを要求する。operation/query/observe参照を新command導入と区別し、旧whole/downloadのencoding・fingerprint・namespace、原本lease/store照合epochの別軸とPhotos/P2契約を保つ。
- 逐次chunkは実commitのC(ownerClosed)<R(release)<S(stopped)<Q(新GET予約)<G(観測)<A(begin)<P(prepared)を全先行attemptへ要求する。Gだけ停止後でもQが停止前なら拒否し、初回はQ<G<A<Pとする。最終writerは履歴prefixと実lease releaseを照合し、未来のfactで旧Pを救済しない。beginでhasReconciled=falseとなった後はrequireReservedAttempt等で元GET/現attemptを再判定し、偽descriptor/hashを作らない。await後のUUID/登録/対象/予約/capture・新queryの変化を再判定し、unknown mutationの元revision/payloadを付け替えない。
- strict拒否はbegin/lease/copy/request/SDK生成の前とし、保持Taskへ同入力を合流して1chunk/attemptを維持する。次chunk/retryは新GET予約/観測と新attempt/sourceを必要とし、自動次chunk・再launch送信・旧owner採用を行わない。SDK実terminal、自身FD close、ownerClosed、lease実release、stoppedを個別に照合し、chunk sourceとfull original leaseを混同しない。SDK completedをwhole完了/保存検証/finalizeへ変換せず、全履歴の実receipt/既存削除fenceを保持する。型付き背景接続でもnative正resume・正式producer/全媒体/実機品質は未成立として、実行版ごとの検証状況・未実施/失敗を含む記録は現行tasklistと証跡を参照する。
- downloadのexpected proposalはuntrustedとし、実prepared `.download`の元mutation/receiptを`load / lookupCommit`へexact照合してもresource対応だけとする。GET前の実`DistributionReceipt`はcontrol-plane read ticketであり、実GET受理/受信成功にしない。callback responseはlocal witnessとして扱い、新しいserver commit receiptを捏造しない。
- callbackは同processのknown actual creation・session/binding・slotの応答期待値を照合し、private system URLをreadonly `O_NOFOLLOW` open/fstatにだけ使う。URL/response objectを保持・再open・eventへ送出せず、全read/copy/hashをcallbackへ置かない。eventはid/ownerGeneration/bindingのsmall referenceだけとし、数値FDや旧task/再openをauthorityにしない。
- 同保持FDのread/hashを最大64KiBとし、SDK unlink専用factsで同identity/size/mtimeと一回のnlink 1→0/対応ctimeだけを許す。原本Fingerprintの規則は緩めない。将来readをrevokeして進行中worker/awaitを実joinした後にcloseし、実SDK terminalと自身FD閉鎖を分ける。pin失敗のclose不明をunknownに保持し、artifact不在/空registryからFD0・旧owner閉鎖を推定しない。
- 後段のresponse観測保存/guarded verified importは設計規則として、実ticket/local response観測commit・現UUID/登録/rendition/失効/削除予約/epoch・記録由来capturedAt・完全coverage/fullhash・同bindingの成功SDK terminalと自身source閉鎖を要求する。日時/ticket欠落を拒否し、単調acceptedAtをcapturedAtに代用しない。現FD固定componentからverified temporary/ownerClosed commit/lease release/媒体成功を作らず、通常full plan・実SDK受信・strict native正resume・正式producer/全媒体・実機品質の未完と、実行版ごとの検証状況・未実施/失敗を含む現行tasklist/証跡を保持する。
- 完全local軽量版のPhotos consumerは、初回だけnative default-routeの現在Wi-Fi観測で受け付け、不明・offline・cellular等では受付/使用/SDKを開始しない。受理済みlocal段階にWi-Fi継続や原本所在・明示確認・Mac再接続を要求しない。同writerの固定batch/source/子IDとPhotoKey予約を使い、queued/startingと単独登録の重複を防ぐ。結果は固定sourceで既存Photo記録へexact joinし、別の成功状態を作らない。app lifetime jobの未開始子はcapture holdで準備済み使用権を保ち、lock外wakeで現在snapshotを再読する。再起動queuedは明示continue/cancel、starting/intent/unknownはSDK再追加せず元mutationを照合する。prepare→begin間の旧orphan useを採用・推定解放せず、known-not-addedの明示retryだけ既存coordinatorでfresh useを一度獲得する。合成cache/注入Wi-Fiの成功を正式producer・通常strict送信・全媒体/実機Photos受入へ昇格しない。
- Photosのactor handoffでcapture holdを観測した`inProgress`は、生存する準備済みcapabilityを保持して扱う。実行中wakeをdriver終端でdrainし、完了履歴を自動driveしない。本人batch照合/続行からのknown-nonstarted intent回収は、既存live owner/coordinatorの`restore()`だけを使用し、新owner・SDK呼出し・unknown結果の成功化を生成しない。再起動後の旧unknownを、このinstanceのSDK非開始証拠で置き換えない。
- Photosの最終SDK開始はwriter→capture→共有claimの順を固定し、`performPhotoSaveIfCurrent`で現在UUID・実intent mutation/receipt・最新の結果/終端/解放記録不在・現登録/版/失効/削除予約・完全媒体/元use/reader epochを照合する。権限確認とactor hop後、短い同期`performChanges`登録呼出しだけを許可内で実行し、await/Task/redispatch/hash/再入やchangeBlock内への許可持越しを禁止する。製品には同background factoryのcapture admissionを明示注入し、Native旧add・default guardedの拒否をlegacy fallbackや空の独立gateで回避しない。
- Photos用local read witnessは、temporary ownerが保持FDの全hashを終えたfingerprintと借用file/dir FDだけを渡す。最終writerでは名前と保持FDをfstat/fstatat/lstatで再照合し、read/hash/open・新しいFD所有/close権限を追加しない。有効なcached軽量版のlocal処理には物理原本・local original binding・削除済みresolutionによる拒否条件を追加しない。
- 同一Photos操作のprocess共有claimはstore UUID・raw UTF8 operation・全intent/入力へ束縛し、prepare/commitを含む最初のawait前に予約する。別coordinatorはSDK・結果/終端・使用解放を生成せず、第一ownerのFD閉鎖後から結果commit前の使用も退役しない。capture holdは同じlive intent/use/FD/Taskを保つ`heldBeforeStart`とし、notAttemptedへ丸めない。changesを先に購読して初期wakeを受け、複数observerへの通知/continuationはlock外とする。通知を許可として使わず、fresh許可とwriter条件を再判定する。
- Photos開始前取消は同じ固定batchの既存live childだけをatomic claimへ渡し、非開始確定→FD閉鎖→終端/結果のexact commit→元use解放を分ける。受理済みPhotoKitには取消handleがないため、実completionまでowner/FDを保持し、外側からperforming useを解放しない。意図commitの冪等性や再起動後の空claim registryをSDK追加許可にせず、既存intent/unknownは自動再追加しない。実行版ごとの検証状況・未実施/失敗を含む記録は現行tasklistと証跡を参照する。全Photos取消/全媒体停止・通常strict送信・正式producer・実機品質を別に残す。
- REC preflightはshared hold後に既知のPhotos prepare Task/世代をjoinし、live子のpreSDK取消/wake、受理後の実completion/自身FD閉鎖/witness失効、exact intent/terminal/use releaseの照合までを扱う。本人のbatch取消集合を変更せず、hold解除を待つdriverの単純waitForIdleやclaim.finishedをreadyにしない。fresh UUID・同writer revision・registry/共有claim世代・現REC ownerとphoto use/logical readerの不在を確認し、Photos/背景の両ready後も背景条件を再照合する。UUID nil/no Photosの正常rootでは全use/readerと旧疑義の不在を同条件で照合し、UUID自動生成をしない。
- 実SDK actionの.started後はwriter falseでも実completionを待ち、非開始結果やFD早期閉鎖へ戻さない。STOP/leaveではそのREC callerだけをcancelledとし、内部join Taskをappに保持する。外部Photos結果unknownはlocal readyの拒否理由に直結させず、実終端/解放のexact証拠で判定する。local証拠unknown/旧ownerは待機し、新owner採用・推定解放・古いRECの開始/次REC解除をしない。実行版ごとの検証状況・未実施/失敗を含む記録は現行tasklistと証跡を参照する。既存P2・品質/全媒体の残件を保持する。
- 同一原本・写真登録キーの操作は予約付きで直列化する。`await` を含むactorメソッドだけで操作全体が排他になると考えず、再入・期待世代・二重commitを検証する。大きなI/O中のストア全体排他や、ロック/予約を持ったサーバー応答待ちを避ける。
- 原本/local軽量版/remote行の再生入口は最初のawait前に共通MainActor予約を取り、非同期handoff中も単数画面を維持する。完全取得済みlocal枝は同writerの正の配布記録・現store/登録/版/失効世代・exact論理原本とfull coverage/hashを再照合し、実root/lock/inode/全内容確認後に使用権を渡す。消費側は既存root/lockだけを開き、欠落領域の生成やネット取得をしない。app lifetimeの同root owner/open処理を合流させ、失効/削除と同じregistryへ登録する。
- local軽量版の明示確認は実再生進行で得た現在画面の同tokenに対する単数本人操作だけとし、停止/自然終了後も同画面で扱える。閉鎖/再起動ではtokenを消去し、自動再生・自動確認やunknownの新actionへの置換をしない。不明は同token/actionのexact照合へ戻す。画面終了で実SDK終端と自分の新useだけを解放し、最後のuseの回収は既存規則に従う。同じtemporary actor/元usageの全bytesに対する解放は保持Taskへ合流させ、caller取消しでも結果を待つ。`inProgress`だけ有界に待ち、unknown/failedをbusyとして推定再試行しない。他ownerの旧unknown useや写真結果による本体保持を消さず、scope全closeは既存失効/削除の窓口を通す。消費側の合成receipt試験を正式producer・通常通信・全媒体停止/実機品質の証拠へ昇格しない。
- 解析・画面内再生のtaskは所有するセッション/画面の終了時に取消す。録画・保存・写真登録・削除・失効の寿命と証拠は画面から分離する。画面離脱・task取消し・プロセス終了を副作用の取消し成功として扱わない。
- 取消し受付、読取/送受信の実停止、外部副作用の結果を別イベントにする。原本の記録・読取・削除と一時コピーに使用権を設け、削除/回収は使用の実解放後に行う。
- REC/保存/復旧のholdはowner別に最初のawait前から保持し、recording token発行前の取消可能なlocal-stop preflightと実記録開始を分ける。停止受付だけで待機を解除せず、先着/後着のfile・終了未確認を元contextへ束縛し、保存file処理の実returnまで待つ。古いownerの応答で新RECの待機を消さず、postSaveのhash/bind/一覧更新を次RECの一律条件にしない。
- 媒体resumeの内部許可は元admission/revisionへ束縛し、hold更新と同じNSLock内でorigin・revision・未hold・未消費を再判定して単回消費する。actionは短い非escaping/nonasync処理とし、lock内でawait・redispatch・admission再入を行わない。SDK portはawait/queue hop後のactual action直前に消費し、発行時のsnapshotを実行済みと扱わない。有効なhold開始の返却後とbegin→end後は古い許可を使わず、throwでも消費を戻さない。本人承認の追加ではなく内部の排他契約であり、nativeの正のresume/通常strict通信は未成立のまま、契約・注入試験・正の実SDK実行/全媒体RECの証拠を分ける。
- streamingを含む全動画送受信はMediaIOGateを通す。原本転送・Photos保存の新規開始はWi-Fi時だけ受理し、不在時の開始予約を作らない。Wi-Fi、REC/保存、本人停止/キャンセルの抑止を独立して維持する。Wi-Fi復帰や録画・保存終了後は、本人が開始受理済み・未完了・未停止/未キャンセルの通信だけを、全抑止条件・操作意思・同一対象/版・既完了結果・認証/接続・操作寿命の再照合後に自動再開する。指示済み順番待ちも同じ条件とし、録画終了だけで再開しない。
- OSが許す既開始upload/downloadの背景/画面ロック継続、個別停止/再開/取消と全件媒体停止を維持する。全件停止は指示済み順番待ち/自動待機を含み、本人停止を回線復帰・REC/保存終了・再起動で解除しない。通信の自動再開を未実行削除・結果不明のPhotos追加・終了済み再生へ適用せず、再生終了時は専用通信を終了し使用権を解放する。
- 通信依頼の本人操作は親/子ID・store UUID・単数/全件停止・action・固定対象を同schema 7 writerの一つのjournalへ保存し、適格子の意思と未処理理由を原子的に投影する。replayは当時の順序を使い、親子namespace・UTF8 exact payloadを保護して後発対象を足さない。unknownは元mutation/revisionのlookupだけとし、確定CAS conflict時だけ同planを再評価する。停止/取消の元登録を保ち、停止解除は現登録/対象版/未完了を再判定しても待機理由を解消せずSDKを開始しない。同processのexact owner/attempt/source/bindingに限る停止要求は並行取消・停止解除で落とさず、新attemptや再openの記録照合から再発行しない。意思記録・停止要求・実terminal/FD閉鎖/使用解放を別に検証し、この導線の`backend.requests`とlocal player/Photosを混ぜない。
- 媒体を含まない保存/検証/変換結果・版・既存確認/失効の同期は別gateでモバイル回線でも許可し、媒体取得や新確認を生成しない。S28の既存登録向け明示1page/続きは未解決失効とcursorを分離し、元mutation/旧outbox、await後のexact登録/storeを照合する。背景履歴/未知ownerの終端を照合できない対象はACKを保留する。処理順/配置・寿命/期限・頻度等の未合意値と、通常strict開始/resume・全媒体producerの未接続を分ける。
- 通常metadata失効から背景ownerを使う場合は、実失効予約・store UUID・現在epoch/登録・原本をexact照合し、既知live uploadだけを停止対象にする。停止を扱ったpollはcallback即完了でも`inProgress`/ACKなしとし、後の明示pollで実terminal・自身FD閉鎖・ownerClosed exact commit・元lease不在・stopped、fresh全SDK inventoryと対象の全journal/receiptを再照合する。閉鎖確定旧uploadの観測で旧未閉鎖sourceをopen・採用・解放せず、unknown/reused/誤attempt登録/copy/開始gap/downloadは保留する。sealなし観測を削除権限にせず、removalの実seal/fenceを維持する。新失効stop分岐の制御試験と、別の停止経路による非送信native cancel/終端から失効ACKへ結ぶSDK試験を層別に扱い、正native開始・全媒体・正式Rec.709・実機品質へ昇格しない。
- manifest同期の対象はlocalの論理原本と、同store UUID/現登録のcommit済みcatalogからUTF8 exactの内容identityで固定する。純metadata観測をschema 7の同writerへ加算し、未公開・版ID/世代・媒体形式・置換待ちを保持する。既存の版採用/確認状態/配布・ACK guardを置き換えず、観測から原本bind・確認・失効/ACK・媒体許可・削除権限を生成しない。退行や同revisionの版/形式矛盾を拒否し、nil観測でも過去authorityを消さない。unknown commitは元mutationのexact lookupを維持し、authorityだけの確定をmanifest観測までの照合完了へ昇格しない。local/remoteの表示は取得記録と実媒体未照合を分け、metadataからオンライン到達・正式品質・再生可能を推定しない。
- UTF8-distinctなUnicode正規化同値のcapture IDはmetadataで区別して保持する。既存writer/replayの互換比較へ渡す前に、coordinatorが版採用開始時と同revision CASの直前に最新論理原本のexact対応を照合し、異なるexact identity/内容との衝突は未解決にする。失効handoffは衝突なしのexact論理原本が存在する場合だけ許可し、別ownerへ作用せず未解決recordを保持する。旧併合履歴の修復・自動binding・schema変更は追加しない。
- 保存原本catalogは既知原本の状態同期と別のmetadata操作とし、現登録のBearer/secretと同destinationへ束縛する。1操作1ページ最大32件・JSON256KiB・cursor640ASCII・capture ID2048UTF8 bytesをこの列挙専用の上限とし、超過・不正cursor・completed/evidence不整合はページ全体を拒否する。切詰め/黙示除外や既存保存APIのopaque identity契約縮小で回避しない。元capture bytesとcanonical UInt64の内容世代/byte数を保持し、SDKのredirect拒否・実completion/invalidation待ちと、前後の現在Keychain/登録/store照合を維持する。

### 永続化・復旧・削除

- 副作用の前に対象・目的・操作意図、後に結果を保存する。DB、原本ファイル、Photos、Mac miniの一括原子更新を仮定しない。commitは永続storeまでの成功であり、UI表示、子contextのsave、HTTP成功を代用にしない。
- 採用済みのCore Data/SQLiteとschema 7の同writer/journalへ原本・確認/失効・outbox・Photos・背景task・削除意図/結果を集約し、別storeへ複製しない。期待revision/対象/世代/元mutationを照合し、内容の違う再入力や応答欠落を新操作へ置き換えない。
- 固定原本転送は新case `.originalUploadAcceptance(plan)`と不変recordに全対象・初期判断/初期request・実receipt・期待store UUIDを保存し、現在のrequestsとはexact joinする。legacy `.batch`や借用receiptを作らず、受理子の`startCommitted`は新receipt/member/期待revisionの専用guardで確定する。同writer最終CASで正常保存binding/commit・現登録/UUID・予約/失効/削除・存在/byte数・重複を再判定し、子の不適格を未処理に残して独立した子を継続する。親不正・登録/UUID・namespace衝突は親拒否とし、黙示縮小で通さない。
- 受付unknownは元plan/envelope revision/payloadのexact lookupだけとし、確定CAS conflictだけ同じ固定requestの別proposalを許可する。有界競合の上限では競合拒否し、再openも不変recordの`mutation`から照合する。本人操作後のcurrent requestsや再statから元payloadを再構築しない。親/全子IDは未処理分もperson・queued Photos子・nested legacy batch・新commandとの双方向namespace保護に含め、正当なoperation参照と新ID導入を区別する。新journalを原本削除inventoryへ加え、旧replay・別軸のstore/lease owner epoch・既存削除fenceを保持する。固定集合・子別判断・unknown/reopen・ID衝突の検証と、実通信/全媒体/品質の成立を別に記録する。
- `.uploadMetadata`のbegin/observeは同schema 7へ加算し、通信前に依頼別の`max(最終観測, 全予約世代) + 1`を永続予約してoverflowを拒否する。beginで旧照合による実行許可を失効し、pendingは最新queryのexact observeだけで解除する。query/実begin receipt・UUID・全typed応答payloadのfingerprintを保持し、最新世代だけを同writerで観測/証拠へ原子的に反映する。query/観測commandと既存固定親子/未処理子・nested legacy等のID導入を双方向保護し、削除inventory・旧replay/fenceを保つ。
- metadata保存検証は8項目すべてのfinal-read証拠を新しい実observation receiptとtyped provenanceで`StoredVerificationEvidence`へ接続する。偽`.verification` receiptを作らず、nil provenanceの旧authority/encodeを保持する。begin/observeのcommit不明は元revision/payloadのexact lookupだけとし、解決した呼出しからHTTPを追加しない。確定CAS conflictだけ有界再提案を許可する。資格情報はcurrent namespaceを読取り専用で照合し、custom factoryにKeychain fallbackを加えず、秘密をproof/journal/logへ保存しない。code/tests・実HTTPの実行結果未確定と、chunk送信/local Photos最終SDK guard・通常strict/全producer・資材/ISO/実機の残件を分ける。
- 明示新登録は、登録意図/登録記録が空の現在storeと、別store UUIDに束縛された有効なv2残存connectionを確認できた場合の独立APIからだけ開始する。通常restore/register/続行/初回入力ではforeign bindingを採用しない。remote接続先検査とKeychain追加より前に同writerの現在UUIDを永続確定し、await後も同UUID・登録空を照合する。同storeの中断は既存の照合/続行を維持し、別intentや新secretで回避しない。
- 新登録のKeychainは`store.<UUID>.connection`/`store.<UUID>.initial.<destination>`へcreate-onlyで追加する。現在UUIDのconnectionを優先し、不正/読取不能でも旧globalへfallbackしない。同UUIDのconnectionがなくてもinitialが宛先を問わず残る場合は新登録を保留し、別destinationで回避しない。旧global byte列の移動/上書き/削除と、旧secret・確認・ACKの継承をしない。v1 unbound・破損・不明を新登録許可にせず、旧global initialの確定した`SecItemNotFound`もremote未実行の証拠にしない。説明付きの別入力/明示開始とcancel/離脱/再照合による入力閉鎖時のbearer消去を保ち、新登録開始と保存原本catalogの部分接続を正式版metadata・通常媒体・UI/実機受入の完成へ昇格しない。
- 保存原本catalogのpageは元request cursor・現登録/store UUID・commandとともに同じschema 7 journalへ観測加算する。unknown commitは元mutationのexact lookupまでcursorを進めず、別ページへ進まない。空/重複で旧観測を消さず、再open後は先頭から明示再照合する。Libraryは`remoteItems`へ別投影し、撮影保存記録/原本参照/正常保存/自動bind/破棄履歴を作らない。UTF8 exactの同capture別内容やlocal衝突、日時不明、現在の外部ファイル未照合を保持し、正式保存検証・公開・確認・ACKにしない。custom登録factoryへ製品Keychainを暗黙付与しない。接続と端末/実HTTP/専用UI等の検証結果は現行tasklistで分ける。
- 再起動時は未完了操作と実ファイル・外部結果を照合する。未実行の削除や結果不明の写真追加を自動再実行せず、アクセス不能を消失と断定しない。schema移行失敗・破損を空ストアへの初期化で成功扱いにしない。
- 容量整理と破棄は別の規則・command・本人確認を保つ。容量整理は同一原本のMac保存/全内容検証、軽量版、永続化済みの有効な明示確認から判定する。Wi-Fi再接続、再視聴、Photos保存、追加バックアップを削除条件に加えない。破棄は対象と消失リスクの本人確認に基づき、検証や確認を偽装しない。
- 表示済み候補や他の動画の成功を削除許可に流用せず、複数容量整理でも各削除の実行直前に対象・世代・最新の確認/失効・証拠と使用権・排他を再確認する。本人確認後の対象/リスク変化は再提示する。対象限定の削除実行・照合だけを共通化し、容量整理不可から破棄へ自動切替しない。
- 全reader/実handleの解放、管理root/leaf/予約を照合し、原本を固定した同FDの全hash後、同writer内で最終条件を再判定してMOVだけをunlinkする。結果の実不在/FD閉鎖と記録も最終照合し、復旧は観測だけとする。task一覧の不在・取消受付・配送handler完了から全解放や遠隔未実行を推定しない。
- S34-BG01の既存historical upload全taskの実SDK終端→自身source FD閉鎖→ownerClosed→exact lease解放→stoppedの照合を、単数リスク破棄と条件付き複数容量整理に共用する。全receipt集合とhash前inventoryを同writer最終unlinkで再構築・再判定し、ABA/新attempt/task/関連登録変更を拒否する。容量整理では保存検証・有効確認・支持schemaも最終writerで再判定する。無関係な別clip更新と旧callerの全writer revision CASを区別し、schema 7/Codable旧commandを維持する。unknown/copy中/attach gap/旧source/再利用task/同operation複数attempt/download/活動中の自動停止や回収へ広げず、upload copyを保持する。
- 通常複数整理の表示上の受付は、全選択原本の存在・内容/保存記録の対応と、適格候補1件以上を条件とする。固定集合への本人確認後も、表示用の適格性を削除権限にせず動画別の最新条件を再判定し、条件不足/終了不明の子を未実行/要照合として残す。未解決子の受付閉鎖を維持しつつ、独立して終端した子だけを再観測・解放する。一部成功や全体の不明結果で子結果を上書きせず、再入力・明示照合から未実行削除を再開しない。正式証拠producerや通常strict通信の未成立を合成証拠/SDK fakeで埋めず、接続・必要検証・実機受入を区別する。
- 確認失効と削除を原本単位で直列化する。失効tombstone＋ACK outboxを同writerへcommitしてから応答し、Mac miniの差し替え公開は登録別の全必要ACK後とする。新登録ACKで旧登録ACKを代用せず、応答不能なら該当差し替えだけ無期限保留して新登録の通常利用は継続する。旧確認を新登録へ自動復元せず容量整理対象だけ再確認し、全履歴再確認・一律再転送/再生成/写真再保存を通常利用条件にしない。失効済み確認を通信断・差し替え保留・再起動で復活させない。失効前のオフライン容量整理は有効な最後の証拠を利用し、外部原本の現在存在までは保証しない。
- 削除済み表示は実ファイルと結果記録の一致後に限る。整理成功は通常一覧で原本なし・軽量版取得/再生可否・確認・Photosを独立表示し、照合済み破棄成功だけ履歴へ分ける。不明は通常導線で要照合等を示し、管理記録を保持する。履歴を原本本体のゴミ箱にせず、中断後の照合はローカルで完結させる。アプリ管理原本の固定参照のみを削除器へ渡し、Mac miniやPhotosの削除権限を渡さない。

### 性能とプライバシー

- 記録、固定Rec.709表示、解析を分離する。解析入力は有界にし、古い入力をためない。大きな原本の一括メモリ読込みを避け、ハッシュ・サムネイル・サーバー同期を次のRECの一律条件にしない。
- 軽量プレビューは全体の一時取得を待たないstreamingを第一候補とし、Photos保存用と同じMac mini生成Rec.709軽量版を使う。原本/変換版/映像IDと配信内容の対応を再生・再開時も固定し、1本ずつの実再生到達と本人の明示操作を確認へ結び付ける。全体取得・全編再生を条件にせず、再生を原本全内容検証や別操作のPhotos保存の成功へ転用しない。
- streamingバッファと登録用一時ファイルの用途・取得範囲・所有者・使用権・動画別/全体の一時使用量を管理する。空き容量不要とは扱わず、部分バッファを完全な登録用ファイルにしない。Photosは実SDK非開始または完了と必要なFD閉鎖・exact終端証拠から元useだけを解放し、登録結果と分ける。再生専用データは使用終了後に回収する。Photos登録用コピー本体のunlinkは登録成功かつ全使用権解放後とし、unknown/failed/notAttemptedの本体と照合証拠は保持する。再起動で終端を推定せず、未合意の保持容量/期限・自動回収policyを追加しない。
- 性能は本人入力から実記録まで測る。通常起動2〜3秒は目標として扱い、初回権限・通常起動・復帰を分ける。形式/カメラ/補正、音声、温度、容量等の条件を残す。未合意の固定閾値や録画時間上限を追加しない。
- 負荷対応は測定に基づきU7で合意する。速度達成のための音声省略、設定の無断変更、原本自動削除をしない。補助解析の遅延は確認済み音声障害と区別する。
- 秘密は認証保管の境界で扱い、ソース・設定・fixture・文書・ログへ保存しない。家族動画、顔画像、音声、完全なURL/パスを診断ログへ入れず、最小限の相関ID・段階・結果・時間を残す。診断ログを復旧証拠の正本にしない。
- Photos保存時はaddOnly、必要な不明結果等の照合時だけ対象と理由を示してreadWriteを案内する。拒否・限定・対応不明・未発見を未保存や再追加許可へ変えず、無条件再追加/写真側削除後の自動復活をしない。権限拒否で無関係な撮影を止めず、アルバム/手動再保存等の未合意事項を補わない。
- 必要な権限は用途ごとに扱い、拒否の影響を該当操作へ限定する。通信/背景動作の残件を理由にATS例外、Background Modes、写真読取等を一括追加しない。外部入力のID・サイズ・内容・schema/版を検証する。
- upload metadataの数値tokenは新専用parserのchunk indexesだけに限定し、旧`PublicationJSON`の全number拒否を維持する。bindingの世代/byte数/chunk sizeはcanonical十進文字列、observed_atはserver ISO文字列とし、欠落・余分なkey・重複key・不正型を拒否する。応答量制限/redirect拒否とtask completion/session invalidation待ちを保持し、parserや制御試験の定義を実HTTP成功にしない。

## エラーハンドリング

| 状況 | 扱い |
| --- | --- |
| 入力不正・非対応・未確認 | 適用前に理由付きで返す。希望値と実適用値を保ち、成功や別設定へ黙って置換しない |
| 待機・権限拒否・端末I/O失敗 | 待機理由、失敗した操作、可能な次操作を区別して表示する。色だけに依存せず、目的・対象・結果に読み上げ名を付ける |
| 音声・記録の障害 | 静寂と入力不達/書込失敗を分け、確認済み障害では開始禁止/停止と保存可能部分の確定を扱う。救済結果と復旧結果を別にし、有界復旧後も自動RECしない |
| 通信断・応答欠落・取消し | 保存済みの事実を通信失敗へ書き換えず、結果不明を照合する。個別失敗はその動画へ限定して独立動画を続行し、認証/回線/store等の共通問題は影響する集合を待機する。再試行は同じ操作・対象・本人意思に対応させ、無限再試行をしない |
| 保存・写真追加・削除の不明/失敗 | 成功を表示せず操作証拠を保持する。失敗、部分、結果不明、未処理、削除済み/未削除/確認が必要を動画別に分け、復旧に必要な処理へ引き渡す。一部成功を全件成功にしない |

Portは呼出側が判断できる型付き結果を返し、表示文言への変換はPresentationで行う。利用者向けの理由と診断詳細を分け、いずれにも秘密や実媒体を含めない。

## テスト戦略

既存構成を用い、単体・統合はSwift Testing、UIはXCTestとする。同じテスト内で両frameworkのAPIを混在させず、外部mockライブラリを前提にしない。配置はリポジトリ構造、受入観点の対応は[機能設計のT01〜T21](functional-design.md#テスト戦略)を正本とする。

| 種別 | 主な対象・方法 | 合格から推定しないこと |
| --- | --- | --- |
| Unit | Domainの判定、世代・期限、状態投影。時刻/能力/証拠を値で注入し、境界・不正・未知・欠落を確認 | 実機のAF・ND・色・画質・音声品質 |
| Application / adapter | Portに遅延・逆順・重複・拒否・不明を注入。固定対象集合、選択/指示済み順番待ち、動画別結果、本人意思、全条件再確認後の自動再開、取消し、実停止、再入、原本/登録キー排他を検証 | fakeによる停止がOSの全動画通信を止めること |
| ローカル統合 | 使い捨てのdiskストア/媒体で意図・副作用・結果commitの前後に中断し、再起動、schema、領域不足、保護領域、対象同一性を確認 | in-memoryの成功がdisk永続性を保証すること |
| 通信契約統合 | 制御可能な試験先で同一操作の再送、全内容検証、streamingの配信/認証/実再生版固定、失効保存応答と公開、古い応答を確認 | HTTP成功や既存MediaVaultの旧フラグが新契約を満たすこと |
| UI / Simulator | 状態別入力・表示、二重入力、操作別の複数選択/1本ずつの制約、動画別の成否/未処理、目的別削除、権限導線、VoiceOver・文字サイズ・縦横を確認 | ボタン無効化が下位の排他を保証すること、カメラ/無線/Photos等の実機評価を代替すること |
| 実機・実ファイル | T01〜T21の該当条件を実環境で評価。保存Log原本、音声同期、表示/補正/AF/ND/ズーム、Wi-Fi切替、Photos、性能を照合 | 機種名、API能力一覧、Preview表示、試験実施だけによる受入達成 |

検証は変更対象の受入条件と不変条件に合わせる。単なる実装の写しをテストにせず、失効と容量整理の両順序、失効保存前後のオフライン、写真登録直後の中断、破棄時の転送一部/保存結果不明等の故障境界を含める。差し替えはV2生成・失効commit・応答・公開の各境界で通信断/再起動を試す。

複数操作では固定対象集合と動画別結果の復旧、一部失敗・未処理、各削除直前の最新確認/失効との競合を含める。原本転送・軽量版取得・streaming/一時取得でWi-Fi離脱とREC/保存の抑止を組み合わせ、未指示・完了・本人停止/キャンセルを自動開始しないこと、未実行削除・結果不明のPhotos追加・終了済み再生へ再開を拡張しないことを確認する。

streamingは配信・認証・版管理とWi-Fi/REC制限、一時使用量・解放を組み合わせて実機評価する。S25/S27には固定版実再生・確認/失効・全必要ACKとV2公開の隔離技術証拠があるが、正式Log/標準Rec.709資材・品質proofは未成立で製品authorityは公開を拒否する。技術fixture・保持FDから外部in-place変更防止や全製品ownerの終端まで保証せず、実回線/負荷・品質の実機採用は別に確認する。大きな制約があれば全量一時取得との比較・代案を示し、大規模配信基盤の導入を確定しない。

撮影・変換品質（G3等）の評価条件・代表シーン・操作・比較方法・測定項目・許容範囲は事前にユーザーと合意する。AF距離、ND閾値、有効期間、ズーム速度/停止精度、音声障害猶予等を架空の値で固定しない。記録には受入条件ID、環境/設定、対象データ、事前合意、試験実施結果、許容範囲の充足判定、証跡場所を分けて残す。未合意・未測定・範囲外は達成としない。

S45の人物なし時のタップ位置AF、初回意図の本人選択・保存復元・未選択REC非阻害、見失い猶予の変更可能な暫定3秒と期限後のピント保持・再指定待ちは本人合意済みとする。通常経路への同一policyの接続と、非私的fixtureによる解析・別人拒否・世代・REC非阻害の技術試験を記録する。fixtureの成功や技術閾値を実機品質の採用にしない。動く人物の同一性、通常合焦・前後追従・追跡OFF人物優先AF、補正crop座標、Log、記録負荷および暫定3秒の実機採用はDV-06で別に確認する。

S43の無到着2秒・本人1操作ごとに音声入出力だけ1回再構成・復旧上限5秒、S46の入力映像観測時点から1秒でのND失効も本人承認済みの変更可能な暫定値とする。同じ版のpolicyをNative/coordinatorへ渡し、2秒の無到着判定と5秒の復旧全体上限を混同せず、NDの保留でRECを止めない。実音声/同期/復旧とND基準/鮮度の品質採用はDV-10/DV-07へ残す。S47 ISO案は本人未回答で通常policy=nilを保持し、未合意の補正や実機採用値を注入しない。

実データはNFR-04に従い、旧MediaVault原本をMac miniの変換/プレビュー、新規FrameRelay原本を転送検証に用いる。実媒体や秘密をrepo・App bundleへ複製しない。対象・操作範囲を記録し、既存実原本や本番相当記録の削除・上書きには別の明示合意を必要とする。旧「写真」原本削除・汎用移行を前提にせず、リリース前の試験データ整理も合意した対象だけに行う。

## 品質ゲート

### 構成確認と実行手順

文書だけの変更はリンク・構造・正本との整合・差分範囲を静的確認する。アプリの変更では、まず実在構成と変更への適合を確認する。以下は**後続工程での手順例であり、実行済みコマンドではない**。

1. `xcode-select -p`、`xcodebuild -version`、`xcrun swift --version` で環境を確認する。Command Line ToolsだけでiOSビルド可能と判断せず、端末全体のXcode選択や導入を自動変更しない。
2. 確認済みの入口に対して `xcodebuild -list -project "FrameRelay.xcodeproj"` を実行し、利用可能schemeを確認する。見つからない場合は共有設定等を調べ、target名からscheme名を捏造したり自動生成で補ったりしない。
3. 選ぶschemeのBuild/Test action、対象App/test targetと有効状態、configuration、言語モード・最低iOSを確認する。既存test planがあれば内容を確認するが、新規test planを必須にはしない。
4. `xcodebuild -project "FrameRelay.xcodeproj" -scheme "<確認済みscheme>" -showdestinations` で実行先を調べ、SDK/runtime・端末・署名を確認する。build用とtest用の適合を分け、testにgeneric destinationを流用しない。

一覧取得もキャッシュ・依存解決等へ書き込む場合がある。実行前に権限、既存依存、DerivedData・result bundle等の出力先を確認する。必要に応じ許可された場所へ `-derivedDataPath` / `-resultBundlePath` を指定するが、全書込みがその中だけとは扱わない。権限・環境で確認できなければ推測で続行せず、未実行の理由と必要条件を報告する。

次のコマンドは**未確認の値を含む書式例で、そのまま実行しない**。すべてのプレースホルダーを上記で確認した値に置き換える。今後独立workspaceを入口とする合意があれば、その実在参照を確認し `-project` を `-workspace` とパスへ置き換える。両方は指定しない。

```sh
xcodebuild -project "FrameRelay.xcodeproj" -scheme "<確認済みscheme>" -configuration "<確認済みconfiguration>" -destination "<確認済みbuild用destination>" build
xcodebuild -project "FrameRelay.xcodeproj" -scheme "<確認済みscheme>" -configuration "<確認済みconfiguration>" -destination "<確認済みtest用destination>" test
```

### 判定と証跡

- [ ] build・診断: 対象のコンパイル/リンクと診断を確認し、新規の警告・隔離違反を解消する。署名・Team・Capabilities・最低iOSをエラー回避だけのために変更しない。
- [ ] test: 対象test、実行数、skip、失敗を結果から確認する。終了コード0でも0件や空の雛形を受入合格にしない。テスト未設定と未実行を区別し、必要な受入検証の欠如は未達とする。
- [ ] coverage: 固定閾値は合意されていないため必須化しない。測定する場合は対象と条件を記録し、未取得を0%や成功に置換しない。
- [ ] Simulator・実機起動: 変更に必要な画面、権限、端末機能を対象環境で確認する。build成功と起動・操作確認を分け、人間の実施はその旨を残す。
- [ ] 品質・実データ: 対応するT番号/受入条件と事前許容範囲を照合し、試験実施と受入達成を別に判定する。未実施の実機・実通信・実ファイル確認を代替テストの成功で閉じない。

証跡にはコマンド、Xcode/コンパイラ、project/workspace、scheme、configuration、destination、対象testと件数、終了結果、ログ/result bundleの場所を残す。成功・失敗・未設定・環境/権限による未実行・対象外を分け、必須の未実行を完了/合格扱いにしない。実装工程ではtasklistへ同期し、read-onlyのvalidationでは対象を変更せず報告へ残す。SwiftLint等の外部lintは標準ゲートにしない。

実装I・自動検証A・実機確認D・PRD受入Rは同じ対象/版へ個別記録する。Iは契約のみ/本体実装済み未接続/必要接続を含む実装済みを具体化し、Aはbuild/単体/UI/結合の件数・結果・版、Dは組合せと適合/不適合/判定不能、RはAC全文への部分証拠/未達/達成を分ける。レビューは自動実行と別の証拠とし、source/依存が不変と照合できた範囲だけ旧証拠を継承する。消失・版違いは影響する必要範囲を再確認し、旧成功/失敗/guard拒否/未実施を上書きしない。

2026-10-22の旧E-S34-BG01最終288入力ではUnit560宣言/913展開成功（空template1を除く有意味912）・29skip、実SDK1件、metadata-only実HTTP1件（2要求/媒体0byte/新確認・ACKなし）、通常UI6件/専用同期UI1件/再open1件・generic iOS署名なしbuild成功を確認した。FD閉鎖の証拠はManagedUploadSource自身の保持source FDに限り、strict permit/Mac notExecutedは注入である。通常strict開始/resume・全媒体・正式proof・通常cleanup/新規Photos/複数UI・実機受入の完成へ昇格しない。厳格AX4失敗はBG01版と直後の独立検証の過去証跡として保持し、同hashのLibraryView保持や通常UI・実文字/VoiceOverの成功をstrict全件再実行/合格と扱わない。P2修正後の結果・実行版・詳細件数と旧失敗版は[現行tasklist](../.steering/20260929-device-independent-implementation/tasklist.md)と各evidenceを参照する。

## Git・Review

- Branch strategy / Commit convention: 固有の方式は現時点で合意されていない。既存運用と作業の指示に従い、branch命名、Conventional Commits、承認人数等を新設しない。commitする場合は目的と変更境界が分かる単位・説明にする。
- 作業前後に差分と所有範囲を確認し、他者の変更、個人設定、無関係な整形を混ぜない。生成物、秘密、実媒体を含めない。安定文書の変更と実装の進捗を対応させる。
- 配置・内部adapter分割・版付き試験設定等の軽微可逆判断は根拠/候補/暫定か採用か/影響/担当/版をtaskへ記録して進める。内部方式の採用は実効契約とdisk/隔離証拠に基づき、実機品質の採用と分ける。重大未合意・要求縮小・実データ消失等の判断は依存する処理だけを保留し、mainへ不足事実と再開条件を返す。
- reviewでは、要求/受入条件、参照方向と状態所有、MainActor/端末実行領域、操作ID/世代と再入、取消しと実停止、commit前後の復旧を確認する。
- 撮影設定と記録/表示経路の分離、全動画I/Oのゲートと条件付き自動再開、固定対象集合と動画別の成否/未処理、容量整理/破棄の分離、各削除直前の証拠と失効/排他、外部データ非削除、写真結果不明の再追加禁止、streamingの版固定と一時使用量/解放を重点確認する。UI表示だけで下位の不変条件が守られると判断しない。
- 変更に対応するテストと実機証跡、品質の事前合意、U1〜U3のR3確定部分と残件・U4〜U8の合意済み部分と残件の区別、tasklistと実diffの一致を確認する。PR等の説明には利用者から見た変更、根拠、検証と未確認範囲を記す。
- `docs/` のレビューは `doc_reviewer` を使う。通常実装のmainレビュー（V-REVIEW）と、明示 `$validate-implementation` による `implementation_validator` の独立検証を区別し、review/validationはいずれも対象を変更しない。修正は所有者へ戻し、main agentが最終差分・所有範囲・完了を判断する。

## Definition of Done

DIの本体task Doneは、割当てた本体/必要接続・全substatus/Finish・関連する意味ある試験/必要build・実I/O/UI・mainレビューを完了した範囲で判定する。必要試験の失敗/未実行がある当該taskはdoneにしない。部分引渡しは対象/版/所有/証拠/残件/再開条件を記録し、task全体の完了と区別する。実機待ちは直接依存する範囲だけを止め、独立taskの開始条件へ加えない。

製品DoDは全21要求・79AC全文と、必要な実機/実通信・事前品質合意・実データ条件の充足で別に判定する。本体taskや非実機の技術試験の成功を、実機方式/能力採用・PRD受入・初期版完成へ読み替えない。当該task自身に必須の実機検証があればその未実施を免除せず、製品受入へ残した検証とは区別する。

- [ ] 対象の要求・受入条件を満たし、全P0の範囲を縮小していない。初期版受入では全21要求・79受入条件の証跡を照合する。
- [ ] architectureの責務・不変条件とrepository structureの配置に従い、対象のU項目・技術成立条件が必要な時点までに解決されている。
- [ ] 変更に必要なbuild・診断、test、起動・操作、実機/実通信/実ファイルのゲートを通過している。文書のみの場合は対応する静的検証を完了している。
- [ ] 品質評価は事前合意した許容範囲を満たす。試験実施、未合意、未測定を合格へ置換していない。
- [ ] 実データ操作と試験データ整理は明示合意の対象・範囲に収まり、結果を記録している。
- [ ] 関連docs、対象steeringのtasklist、検証証跡を同期し、最終diffに所有範囲外の変更がない。
- [ ] 残課題・未検証の理由と影響を記録し、必須検証の未実行や未達を残したまま完了としていない。

構成と作成手順は[development-guidelines Skill](../.agents/skills/development-guidelines/SKILL.md)、[新規作成テンプレート](../.agents/skills/development-guidelines/assets/template.md)、[process](../.agents/skills/development-guidelines/references/process.md)、[implementation](../.agents/skills/development-guidelines/references/implementation.md)に従う。
