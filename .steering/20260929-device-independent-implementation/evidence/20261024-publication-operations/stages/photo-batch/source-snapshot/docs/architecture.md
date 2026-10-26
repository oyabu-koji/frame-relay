# アーキテクチャ設計書

## 前提と設計方針

- 対象: FrameRelayの初期版P0。[承認済みPRD](product-requirements.md)のFR-01〜FR-17、NFR-01〜NFR-04の全21要求・79受入条件を維持する。2026-09-25の補足R2を含むPRD全体承認と、2026-09-26の明示回答を反映した補足R3を根拠とし、FR-14の容量整理とFR-17の不要原本破棄を分離する。既存76受入条件のIDを維持し、R3で追加したAC-FR-11-04・AC-FR-14-07・AC-FR-15-05を含む。
- 入力: [機能設計](functional-design.md)のF1〜F5、D1〜D8、S1〜S7、I1〜I7、[バックエンド連携仕様](ideas/20260928-backend-integration.md)、[実機なし先行実装仕様](ideas/20260929-device-independent-implementation.md)（DI）の確定差分。本書は責務・依存・実行・保存の技術設計を扱い、操作フローや受入条件の正本を置き換えない。
- 技術前提: Swift + SwiftUI + native iOS + Xcode。[PROJECT_CONTEXT.md](../PROJECT_CONTEXT.md)の既存設定である最低対応iOS `27.0`、Swift言語モード `5.0`を維持する。Xcode・Swiftコンパイラ・SDKは恒久版を固定せず、各検証の実行版を証拠に残す。言語モードとコンパイラのバージョンを同一視しない。
- 対象利用端末: 要求上のiPhone 18 ProとMac mini。端末名から可変絞り、Log/ProRes、手ブレ補正、ズーム等の成立を推定しない。使用するOS・カメラ・出力経路の組合せごとに検証する。
- 状態: 要求の合意、内部方式の採用、未実装/探索候補/本体実装済み未接続/必要接続を含む実装済み、自動検証、実機採用・品質・PRD受入を区別する。R3・連携仕様・DIと後続の本人承認を維持し、共通基盤や技術試験の成功を未回答案の採用・製品全体の完成へ読み替えない。
- 優先する品質: 撮り逃しの抑制、設定と原本の保持、音声を含む記録の継続性、操作結果の復旧、対象を取り違えない手動削除。成立しない場合は理由・代替案を示し、P0を黙って縮小しない。
- 範囲: 既存Xcodeプロジェクト内の責務分離と、既存MediaVaultとの必要契約を定める。別project生成、外部依存導入、Mac mini側のSwiftへの書き換えは行わない。物理的なファイル配置・実装順序は後続文書・計画で定める。
- 進捗と検証結果は[現行tasklist](../.steering/20260929-device-independent-implementation/tasklist.md)を正本とする。本書は引渡し済みの安定した境界と残件を記載し、詳細な実行版・件数・失敗/skip・レビューを複製しない。実装、自動検証、実機確認、PRD受入の4軸を分け、未接続・方式未成立を実機だけの確認待ちへ置き換えない。

DIの実装4段階は、共通保存/原本/ライブラリ/ローカル再生、バックエンド/通信/版/軽量版、Photos/容量整理/破棄、撮影/解析/表示の単位とする。前段の実機合格を独立後段の着手条件にせず、不足する事実への直接依存だけを局所保留する。共通storeのdisk commit・再openと原本consumerは、D01の実記録方式の正式採用や実撮影G2Bから分離して先行し、試験媒体の成功を実撮影の証拠にはしない。

設計上採用するのは、単一のiOSアプリ内でのUI・ユースケース・純粋規則・端末I/Oの分離である。小規模な個人用アプリに複数プロセスや多数のpackageを追加せず、Swiftの型・プロトコルと組み立て箇所で境界を表現する。以下の名称は論理責務であり、既に同名クラスやサーバーAPIが存在するとの意味ではない。

## 要件と技術判断

各判断の「採用方式」は機能境界と内部方式を表し、実装事実を併記した範囲も実機対応・品質合格を意味しない。未合意の操作・製品仕様に依存する箇所は候補として分ける。受入条件の詳細と全件対応はPRDおよび機能設計の要件対応表を参照する。

| 判断・要件 | 採用方式 | 理由 | 代替案・制約 | 検証方法 |
| --- | --- | --- | --- | --- |
| A1 FR-01・03・08、NFR-03 | 希望設定、APIで取得した能力、実適用値、実機評価済みの組合せを別管理。撮影制御の入口を一つにする | UIの選択値や機種名を実際の記録条件と混同しない | 設定値の直接バインドは複合条件を無断変更し得るため不採用。標準形式・OFF＋複数補正が不成立なら要求再確認 | 機能設計T01/T03/T08/T20。設定照合と保存Log原本による実評価 |
| A2 FR-02・04・09、NFR-01・03 | 記録経路と表示変換経路を分離。撮影制御・音声・記録終端を同じセッション管理下で調停 | Rec.709非焼込み、REC時WB固定、音声障害停止を記録フレームに対応させる | 高水準の録画出力とsample buffer＋writerを比較。具体出力方式は成立性検証後に確定し、音声省略で簡略化しない | T02/T04/T09/T18。最初/最後のフレーム、音声到着と書込、起動時間 |
| A3 FR-05・06・07、NFR-03 | 人物/ND/構図の解析を記録と別処理にし、世代・時点・根拠を添えた結果だけ受け取る | 遅い解析でRECを待たせず、古いOKや人物選択を適用しない | 全フレーム同期解析は録画を妨げるため不採用。解析を省くだけでは有用なND・追従・予告のP0を満たさない | T05〜T07。遅延/逆順入力と合意した代表シーンによる品質評価 |
| A4 FR-10、NFR-02 | 撮影IDを中心に独立した状態軸と通常一覧/破棄履歴を同じ正本から投影。整理成功は通常一覧、照合済み破棄成功だけ履歴 | 一撮影をまとめつつ保存/検証/確認/写真/削除を混同せず、管理記録を保持する | 単一の完了フラグや原本を残すゴミ箱は不採用。不明は通常導線の要照合、配置等はU1残件 | T10/T19。中断後の実ファイル・管理記録・表示の照合 |
| A5 FR-11・12、NFR-02 | 原本全内容の識別と保存検証証拠を契約化。Mac mini変換は検証済み原本から行い、生成と公開を分離 | HTTP成功や既存compress-onlyを保存検証・Rec.709達成に流用しない | 内容識別・最終保存先全内容検証には実装/隔離証拠がある。標準変換資材・正式proof・通常通信との接続は未成立。iPhoneへの変換移動は不採用 | T11/T12。実原本、受信ファイル、変換映像・メタデータ、応答欠落 |
| A6 FR-13・14、NFR-02 | 端末の確認・失効を永続記録し、原本単位で削除と直列化。差し替えは端末の失効保存応答後だけ確定 | オフライン容量整理と、差し替え後の旧確認使用防止を両立する | 削除時の毎回サーバー照会は要求違反。タイムアウトで失効保存を推定しない。外部原本の現在存在はオフラインで保証しない | T13/T14/T19。各永続化境界の再起動、差し替えとの両順序 |
| A7 FR-17、NFR-02 | 破棄の本人確認と容量整理の証拠判定を別ユースケースにし、対象限定のローカル削除実行器だけ共有 | 未転送の不要原本を破棄でき、検証/確認状態を偽装しない | 容量整理不可からの自動フォールバックは不採用。Mac/写真への削除依存を与えない | T17/T19。未転送・未検証・未確認、競合、外部データ非削除、結果照合 |
| A8 FR-15、NFR-02 | 同一版の登録を直列化し、写真追加前に操作意図を永続化。追加結果不明時は照合へ進む | Photosとアプリ記録の間の中断で無条件に追加し直さない | ボタン無効化だけの重複防止は不採用。通常追加・必要時読取はDI-06確定。写真側削除後の手動再保存・再インストール等はU2未決 | T15/T19。追加直後の終了、権限変更、写真側削除、一時コピー回収 |
| A9 FR-16、NFR-01 | 全媒体I/Oの共通ゲートと停止契約。既開始通信だけ全条件再確認後に自動再開し、OSが許す背景/ロック継続と媒体なしモバイル状態同期を分ける | 回線表示だけに依存せず、REC/保存/本人停止の複数条件と操作寿命を維持する | S23/S49の背景資源・REC境界には部分証拠があるが、通常の厳格な通信開始と全媒体停止/再開は未成立で閉鎖。前景だけへ要求を縮小しない | T16/T18。指示済み順番待ちを含む全送受信経路でWi-Fi離脱、REC、保存、ロック |
| A10 NFR-02 | 復旧証拠を一つのトランザクション可能なローカルストアへ集約し、大きな媒体はファイルに分離 | 記録の複数更新をまとめ、媒体とDBの非原子的な間を操作記録から照合できる | ファイル削除・Photos・サーバーとの分散トランザクションは仮定しない。DBの具体案と制約は後述 | T19。保存失敗・領域不足・schema変更・プロセス中断 |
| A11 NFR-04 | 新規撮影原本と旧MediaVault原本を区別した検証データ契約 | 新規転送と既存原本の変換を別に評価できる | 旧写真原本削除や汎用移行を検証前提にしない。実データ整理の対象・破壊的操作は別の明示合意 | T21。実施範囲・対象・合意・整理証跡の確認 |

## システム境界

```text
SwiftUI View -> Presentation -> Application -> Domain
                                   |
                                   v
                              I/Oの契約
                                   ^
                                   | 実装
               Platform（撮影 / 保存 / 通信 / 再生 / Photos）
                                   |
                       iOS端末機能 / Mac mini

Composition: 起動時にApplicationへ各I/O実装を注入する
```

矢印はソースコード上の依存方向。外部からのコールバックはI/O契約の値イベントとしてApplicationへ戻し、下位層からViewを操作しない。Domainは純粋な値と規則だけを持ち、端末API・DB・HTTP・SwiftUIに依存しない。

| 境界 | 責務 | 公開インターフェース（論理名） | 許可する依存 | 禁止する依存 |
| --- | --- | --- | --- | --- |
| Presentation | 表示用snapshot、入力、画面寿命、アクセシビリティ。`@MainActor`でUI更新 | 撮影/ライブラリ/操作のsnapshot購読、本人のcommand | Applicationの公開契約、表示用の値 | ファイル削除、Photos追加、撮影設定の直接書換え、独自の削除判定 |
| Application: CaptureCoordinator | セッション、設定適用、REC/STOP、音声障害、WB、ズーム、解析結果の採否 | `prepare/apply/start/stop`、実適用値・記録イベント | Domain、CapturePort、AnalysisPort、OperationStore、MediaIOGate | UI、直接HTTP、写真追加、未合意の自動設定変更 |
| Application: MediaOperations | 手動転送、確認、容量整理、破棄、写真保存。固定した対象集合と動画別操作、原本/登録キーごとの操作順序 | 目的別command、操作ID、動画別の成否・未処理・理由付き結果 | Domain、Store/Original/Remote/Photos/Playbackの各Port、MediaIOGate | 他担当の状態の直接変更、Mac/写真の連動削除、破棄を確認イベントへ転換 |
| Application: Library/Recovery | 撮影IDによる表示投影、起動時の未完了操作照合 | 項目snapshot、照合要求と結果 | 読取契約、操作担当への復旧command | 存在するファイルを正常保存と推定、未実行削除や結果不明写真追加の自動実行 |
| Domain | 対応条件、REC/通信可否、ND有効性、確認・容量整理・破棄、結果採否 | 副作用のない判定関数、型付き状態・理由 | Swiftの値型、渡された時刻/世代/証拠 | OSへの時計照会、通信、DB・ファイル操作、フレーム処理API |
| Platform: Capture/Analysis/Render | セッション構成、音声・映像記録、能力照会、表示/解析への入力供給 | I1/I2に対応するPort実装 | AVFoundation等の標準API、型付きイベント | 容量整理判定、画像処理の原本への無断焼込み、解析からの露出変更 |
| Platform: LocalStore/OriginalStore | トランザクション、原本の固定参照、内容検査、許可済み対象の削除、一時コピー使用権 | 保存確定、期待世代付き更新、存在/内容/削除結果 | 採用済みCore Data/SQLite、FoundationファイルI/O、内容検証 | ネット接続による削除許可、外部パスの削除、DBの失効消去による復元 |
| Platform: Remote/Network | 接続/認証、手動開始済み原本の転送、保存証拠、版同期、ゲート付き動画取得と背景task所有 | I3/I6の値契約、停止完了・結果不明 | URLSession/Network、認証保管Port。通常通信開始は未成立箇所を拒否 | 撮影制御、既存サーバー削除候補の直接使用、ゲートを経ない動画I/O |
| Platform: Playback/Photos | 版を固定した再生到達、Photosへの追加と結果照合 | PlaybackToken、PhotoRegistrationKey、権限/結果/参照 | 標準再生/Photos API、取得Port、一時コピー使用権 | 確認の自動確定、独自ダウンロードによる通信制限回避、Photos削除 |
| Mac mini境界 | 原本受信・保存検証、Rec.709生成、正式版管理、失効応答を待つ差し替え | バージョン付きのRemote契約。具体endpoint/wireの採用範囲は現行tasklistを参照し、通常接続・正式proof等の残件を分ける | 既存MediaVaultの確認・必要拡張 | iPhone削除をサーバーで実行、応答のない端末の失効保存を推定 |

Application同士は公開commandと値イベントだけを利用する。Composition以外で具象サービスを直接生成しない。テストでは同じPortへ失敗・遅延・逆順応答を注入する。全状態を持つ巨大な共有オブジェクトや、任意の場所が発火できる未型付けのイベント経路は設けない。

### 状態の所有・更新・共有

| 状態 | 所有者と保存 | 更新経路・共有範囲 |
| --- | --- | --- |
| 希望する撮影設定 | 設定担当＋ローカルストア | 本人command→条件検証→永続化。適用値とは別。WB固定値は次クリップの希望値へ保存しない |
| セッション、実適用、WB/音声、REC | CaptureCoordinator。セッション中の一時状態 | CapturePortの事実で更新。録画IDを添えて原本保存担当と共有。画面離脱で録画操作を消さない |
| 人物候補/主役、ND、構図/停止候補 | 撮影側の一時状態 | 解析contextと現世代が一致した結果のみ採用。顔の恒久台帳を作らない。再起動後に追跡中へ推測復元しない |
| 原本、操作、検証、版、確認/失効、写真/削除 | MediaOperationsとOperationStoreが更新権を所有 | 項目別の直列化と期待世代付きcommitを通る。Libraryは読取専用の表示投影 |
| 複数操作の対象集合と動画別の操作/結果 | MediaOperationsとOperationStore。画面の選択状態とは別 | 開始指示のID・種別・受理時点の対象集合を固定し、動画別の操作ID・対象/版・証拠・状態を保持。一部成功で全体を成功にせず、後から未指示動画を追加しない |
| 回線・REC/保存抑止・本人停止/キャンセル | MediaIOGateと各操作の意思記録 | 一つの条件解消で他の抑止理由を消さない。開始受理済みの未完了通信だけ、全条件を再計算して自動再開。単なる選択と指示済み順番待ちを区別 |
| 再生到達、再生token、一時データの使用量/使用権 | Playback担当/TemporaryMedia担当 | 版を固定した1本の実再生イベントだけが確認候補を作る。確認の永続化は本人の明示操作を受けてMediaOperationsが行う。バッファと登録用ファイルを区別 |

一覧表示のキャッシュ、サムネイル、ボタンの有効状態は正本ではない。削除実行時は最新証拠から再判定し、古い画面の候補表示を実行許可として受け取らない。

### 並行処理・寿命・キャンセル

- UI更新はMainActorへ集約する。カメラの構成・開始停止・設定適用は専用の直列実行領域、音声/映像sample処理はそのAPIが要求する実行領域に閉じ込める。録画データをViewの状態更新に載せない。
- Swift Concurrencyによる所有者隔離を設計方針とするが、SDKオブジェクトをactor間で自由に渡せるとは仮定しない。MainActor外のI/OはPort内部で所定のqueueへ接続する。Swift言語モードは変更せず、使用コンパイラで隔離・送受信可能性の診断を確認する。
- 同一原本のcommandは、操作中の予約を持つ直列実行器で一件ずつ処理する。`await`を含むactorメソッドを書くだけで全操作の排他が成立したとみなさない。予約中の失効・削除は待機し、callbackは操作IDに対応させる。DBの期待世代も照合し、同一操作の二重commitを拒否する。
- 原本転送・同じRec.709軽量版の写真保存・条件を満たす容量整理は複数選択してまとめて開始/実行し、内部は順次処理でよい。軽量プレビュー再生・明示確認と破棄は1本ずつとし、複数選択を確認の自動昇格や一括破棄へ使わない。通信の個別失敗は独立動画を続行し、共通問題は影響範囲を待機させる。個別停止/再開/取消・開始済み動画通信の全件停止も確定済みで、処理順・配置・停止UI等は残件とする。
- 原本の使用権は読取（転送/再生/検査）、記録、削除を区別する。削除は対象の記録終了と全読取の実解放後にのみ実行する。待機中に本人確認の対象・状態が変われば再提示する。複数容量整理でも各削除直前に最新条件・失効・排他を照合し、この原本単位の規則を省略しない。
- 一時的な解析・再生のtaskはセッション/画面に属し、終了時に取消す。保存・写真登録・削除・失効の操作証拠はアプリの管理状態に属し、画面離脱やtask取消しで消さない。プロセス終了後にtask自体が存続するとは扱わない。
- 取消しの受付、読取や送受信の実停止、外部の副作用の結果は別イベントとする。Macに保存済み、Photosに追加済みの可能性が残れば照合する。古い試行の応答は新しい表示へ無条件に適用せず、元操作の証拠として照合できる状態を残す。
- ロック/予約を持ったままサーバー応答を待たない。削除と失効の直列化は端末内で完結させる。DB更新は短いcommit単位とし、大きなハッシュ計算・動画I/O中にストア全体の排他を占有しない。複数キー操作が必要なら取得順を固定し、循環待ちを防ぐ。

## 技術スタック

標準frameworkを第一候補とし、外部依存は追加しない。標準APIの一般契約を参照したことと、このprojectのSDKでのcompile・実機成立を分ける。具体symbolのavailability、deprecated状態、必要な署名・設定は実装前に使用SDKで確認する。

| 技術 | バージョン方針 | 用途・選定理由 | 代替案・制約・検証 |
| --- | --- | --- | --- |
| Swift / SwiftUI / Xcode | PROJECT_CONTEXTの既存値を維持 | ネイティブUIと型付きの機能境界。既存App targetを利用 | RNへの置換、project generator導入は行わない。Xcode/コンパイラの実行版は証拠ごとに記録し恒久固定しない |
| Swift Concurrency＋端末APIの直列queue | 言語モード5.0を維持しSDK適合を確認 | 状態所有、task寿命、UI隔離。リアルタイムI/OはAPIの実行制約に従う | 全部をMainActorに載せない。独自並行runtimeは不要。callback橋渡しと中断を検証 |
| AVFoundation / Core Media | OS同梱。使用symbolを組合せごとに確認 | カメラ・音声・時間・書込・再生。既存framework内で記録と表示を分離 | MovieFileOutputとDataOutput＋AssetWriterの二候補を通常撮影へ接続し自動切替しない。D01の正式採用とLT/Proxy＋Log・補正・手動値・音声監視の同時成立は実機比較へ残す |
| Core Image / Metal | S48の独立技術描画にCore Imageを使用。Metalを製品方式として採用済みにしない | `CIColorCube`から表示専用CGImageを生成 | 標準Log→Rec.709資材と通常capture/UIは未接続。ND規則自体をframeworkへ委ねず、負荷・品質は別評価 |
| Vision | S45の人物解析本体で使用。通常経路のpolicy接続・検証はS45で管理 | 端末内の上半身検出、追跡候補、画像特徴量の照合 | SDKの追跡IDや画像類似度を人物同一性の証明にしない。再捕捉・AF・負荷の実機品質は未確認 |
| Core Data（ローカルSQLite store） | S11の比較後、通常Compositionの共通writerへ採用 | 既存のtransaction・排他・再openを再利用。親なしprivate queue contextからSQLite coordinatorへsaveし、schema 7の記録・journalを同じ正本に保持。媒体は格納しない | AtomicFile候補も同契約で比較・障害試験し保持。性能優位や電源断耐久性を採用理由にせず、実機保護/OS終了はDV-02。SwiftData/SQLite直接操作等への置換はしない |
| FoundationファイルI/O＋CryptoKit SHA-256 | OS同梱。S13以降の実ファイル内容照合に使用 | 大きな原本を逐次読取り、ファイル全体の同一性をサイズとdigestで照合。S24は最終保存先を独立に全読戻し | ファイル名/日時/サイズだけでは不足。hashは認証・保存品質・端末耐障害性そのものを証明しない |
| URLSession＋Network | 固定版Rangeと背景資源adapterを実装。通常の厳格な通信開始は閉鎖 | 動画ゲート、cellular禁止設定、経路変化、停止/照合とOS task所有を共通化 | 監視だけでWi-Fi/VPN基礎回線・背景redirectを送信前に拘束できたとしない。同期許可の契約/配線と、正の実SDK resume・全媒体producer・実回線の成立を分ける |
| Photos / PhotoKit | OS同梱。通常addOnly・必要時readWriteはDI-06確定 | `NativePhotoLibrary`が軽量版追加と実SDK完了、保存済みidentifierの照合を担当 | 写真保存履歴と現在存在を分離。追加権限だけで全結果を照合できるとは仮定しない |
| Keychain / OSLog | OS標準を利用。S22/S22Cの初回登録・資格保管に加え、S28の別storeに対する明示新登録開始を部分接続 | HTTPS origin/接続先、store identity、登録意図に束縛したBearer/登録秘密をKeychainで照合し、新登録は現在store UUIDのnamespaceへcreate-onlyで追加。診断を操作証拠と分離 | 通常再起動と明示新登録を分け、資格情報の欠落/旧store不整合を自動採用や上書きで解決しない。保存原本catalog/manifest観測の部分接続と正式proof・通常媒体・秘密更新等の残件を分け、独自分析サービスやログ送信を追加しない |
| Swift Testing / XCTest | 既存targetで使用 | 単体・統合はSwift Testing、UIはXCTest | 雛形は受入検証ではない。テスト依存・固定カバレッジ閾値を追加しない |

AVFoundationはファイルへの記録とsample bufferへのアクセスを区別して提供し、formatにはfps・色空間・補正等の対応情報がある。この情報を能力照会の入口とするが、標準LT＋Apple Log等の複合要求が成立する証拠にはしない。[音声・映像キャプチャ](https://developer.apple.com/documentation/avfoundation/audio-and-video-capture)、[AVCaptureDevice.Format](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format)

## データ管理

### 保存場所とライフサイクル

| データ | 保存場所 | 形式・所有 | ライフサイクル・理由 |
| --- | --- | --- | --- |
| 撮影原本・確定可能な部分原本 | Application Support配下の製品管理root `FrameRelayLibrary` | 不透明な原本参照と `.mov`。予約・内容対応・実FDを照合。拡張子だけで実形式/品質を保証しない | 本人の容量整理/破棄まで保持し、自動容量回収しない。原本をPhotosに保存しない |
| 記録中の出力 | 同じ管理領域の確定前領域 | 撮影IDと対応する一時名。キャッシュと区別 | 書込終端・媒体検査後に確定。中断したからといって自動で消さず、部分/不明/失敗を照合 |
| 撮影希望設定・記録方式候補 | 製品保存領域の `capture-preferences.json` | `CapturePreferenceStore`がschema付き設定文書をatomic置換。共通記録storeとは別の保存単位 | 現在の能力・実適用値を再確認して復元する。未知schema・破損を通常の設定保存で上書きしない |
| 撮影・操作・検証・版・確認/失効・削除・写真登録・catalog/manifest観測 | 同じ製品rootの `recordings.sqlite` | Core DataのDocument payloadにschema 7 `RecordingStoreDocument`を保存。固定対象集合と動画別操作/証拠/結果、原本/連携journalを同じwriterで更新 | 再起動後の正本。整理/破棄で本体を削除しても、撮影・内容対応・本人操作・検証/確認・写真・削除結果を保持。metadata観測はローカル保存記録、確認の有効性や削除権限と区別 |
| サムネイル・表示索引 | 再生成可能なキャッシュ | 撮影/内容世代を付与 | 消失しても確認・容量整理判定を変えない。容量整理後に必要な撮影記録と区別 |
| streamingバッファ/取得中/再生/Photos受渡しの軽量版 | 使用メモリとアプリ管理の一時領域 | 原本/変換版/映像ID、取得範囲・検証結果、用途・所有者・使用権・使用量、断片の操作ID | 恒久保存にしない。再生用は使用終了後、登録用は登録成功かつ使用者なしで回収し、再取得可能な本体と復旧証拠を分離。方式・上限/期限はU2で合意/評価 |
| 主役候補・ND入力・フレーム | セッションのメモリ | boundedな最新入力とcontext | セッション終了時解放。人物識別台帳や未要求のクラウド解析を追加しない |
| 接続秘密情報 | `KeychainRegistrationVault` | 接続origin/期待destinationとstore identityに束縛した接続情報、登録意図に対応する秘密。明示新登録の接続/initialは現在store UUID別のnamespaceに置き、重複追加は既存値をexact照合して置換しない | 同writerの登録意図が操作の正本。秘密を設定JSON・ログ・原本名へ複製せず、旧資格情報を別storeへ自動採用しない。現在namespaceの不正を旧globalへのfallbackで隠さず、旧global項目は上書き/削除しない。通常HTTPS等の結合・秘密更新・実機保護は別に確認 |
| 診断ログ | OSLog | 操作種別、匿名化した相関ID、段階・結果・時間 | OS管理の診断用としアプリ独自の恒久ログを作らない。保持日数を保証しない。復旧証拠は別ストアに保存 |
| Mac mini原本・軽量版 | 既存MediaVaultを拡張した隔離snapshotで検証。稼働構成は別確認 | 原本は不変、軽量版は原本/映像/変換版を関連付け。公開artifactと候補を別所有 | iPhone削除後の原本の正本。別バックアップの存在やiCloud経由の保全を仮定しない |

原本の保存root・不透明参照・予約/FD照合は実装済みの選択とし、バックアップ除外・ファイル保護属性と実端末のロック時アクセス/耐障害性は別に確認する。クラウド同期・追加バックアップをP0の削除条件へ追加しない。アプリ削除・再インストールによって失われた確認を、Macの旧フラグから有効へ復元しない。

### 内容同一性・保存証拠

内容識別は、`原本ID＋内容世代＋byteCount＋digestAlgorithm＋全ファイルdigest`を保持する。S13は書込確定後の実原本を同じFDから逐次読み、SHA-256を内容対応へcommitして再openで照合する。内容世代を撮影設定・store revision・再起動で代用しない。S24の隔離実装も最終保存先を新しいFDから独立に全読戻しし、短い最終transactionで対象/世代を再照合して保存・検証証拠を確定する。送信元digestのechoやHTTP成功だけでは検証済みにしない。大容量時の実機負荷・保存品質の受入は別証拠とする。[SHA-256の逐次更新](https://developer.apple.com/documentation/cryptokit/sha256/update%28bufferpointer%3A%29)

- digestは全内容の対応を示すためのもので、認証・保存の永続性・映像が正しく撮れたことを単独で保証しない。転送中に原本を変更しない使用権と、サーバー保存結果の契約を併用する。
- ハッシュ完了を次のRECの一律の条件にしない。未確定の原本識別は転送/容量整理へ渡さず、検査I/Oも録画資源と調停する。短いファイル名や時間長だけへの省略はしない。
- 軽量版は原本識別、映像ID、変換仕様の版、出力内容照合情報を持つ。同一ファイルの再取得では確認を維持する。同じ設定で再生成したことだけで同一映像とせず、映像同一性を証明できなければ別版として失効手順に従う。
- 軽量プレビューは全体の一時取得を待たず内容を確認できるstreamingを第一候補とする。Photos保存用と同じMac mini生成Rec.709軽量版について、URLだけでなく不変の原本/変換版/映像IDと配信内容の対応を再生・通信再開時も固定する。1本ずつの実再生到達と本人の明示操作を確認へ結び付け、全体取得・全編再生を条件にしない。実再生到達は原本全内容の保存検証やPhotos登録成功を意味しない。S25/S27には固定版の隔離HTTP/実AVPlayerの技術証拠があるが、正式媒体・未取得媒体の通常取得/streamingとの接続は残る。大きな制約があれば一時取得との比較・代案を示し、大規模配信基盤の採用を承認済みにしない。
- schema不明・対応不一致・古い世代の証拠は、有効な検証や確認として採用しない。単なる接続失敗は既知の保存成功を保存失敗に変えず、取得済み事実と鮮度を分ける。

S13の読取leaseは操作/owner/epochとSDK attachmentへ結び付け、実FD・最大64KiBのpread・前後のdevice/inode/size/mtime/ctimeを照合する。open途中の取消でも実open終端→close→台帳releaseを待ち、辞書不在や取消要求を解放証拠にしない。削除/失効はlogical state上の媒体readerも含む全使用者を照合する。新しい終端証拠のない旧OS/source ownerはunknownを保持し、S23の部分実装を旧readerの全復旧完了にしない。

S28のlocal軽量版消費側は、`LocalRenditionSelection`で同revisionのwriter/論理原本、現store UUID/登録/公開版・失効世代、成功が永続化された同版の配布記録、完全coverage/内容hashを選別する。表示上の候補だけで読取りを許可せず、`ProductRenditionFactory`が実root/lock・directory/file identityと全内容hashを照合してから、local/remote一覧の単数再生へ渡す。原本本体の現在存在を軽量版再生の条件に追加しない。消費側はネットfactoryを持たず、`FrameRelayLibrary/renditions-v1/<原本identityのSHA-256>`の既存root/lockだけを開き、未取得媒体や欠落rootを作らない。これは取得済みlocal枝の配線であり、streaming第一候補を全量取得必須へ置き換えない。

`ProductRenditionFactory`はアプリ寿命で同rootのownerを一つ保持し、同時openを合流させ、既存の失効/削除と同じ`RenditionScopeRegistry`へ登録する。再生画面の停止/閉鎖は実SDK終端とその再生が取得した使用権の解放を待ち、scope全体の閉鎖は失効/削除の窓口へ残す。同じtemporary actorと元usageの全bytesに束縛した解放は保持した単一Taskへ合流し、呼出元の取消し後もその結果まで待つ。`inProgress`だけを有界に待ち、unknown/failed等を解放済みやbusyと推定して再試行しない。最後の使用権がなくなれば既存の回収規則を適用し、別ownerの旧unknown useや写真結果に基づく保持を消さない。原本/軽量版/remoteの画面開始は最初のawait前に共通MainActor予約を取り、遅延handoffの間の二重開始を拒否する。

`RenditionPlaybackModel`は実AVPlayer進行で得た同一再生tokenに対する、現在の単数画面の本人操作だけを`MediaConfirmationCoordinator`へ渡す。停止/自然終了後も同画面のtokenを使えるが、画面閉鎖/再起動では消去し、自動再生・自動確認や新しいactionへの不明結果の置換をしない。不明時は同token/actionを照合する。`RenditionPlaybackView`は全文が伸長する本文と固定footerを分け、全12文字サイズを扱う。正式媒体producer・通常取得/streaming・全媒体制御は未接続の範囲を残し、このlocal消費側と合成receiptのfixtureを正式Rec.709・実機品質・全S28受入へ昇格しない。必要検証の実行版/結果は現行tasklistへ記録する。

### commitと復旧の契約

S11でCore Data/SQLite候補とAtomicFile候補のcommit前rollback・commit後応答欠落・再open・旧schema/破損/revision競合を比較し、既存transaction・排他・再openを再利用できるSQLite候補を共通writerへ採用した。性能優位を示す比較ではなく、D01の記録方式採用から独立した内部方式判断である。通常 `ProductLibraryFactory` は `SQLiteRecordingStore` を生成し、同じ実体を記録・原本・連携の各Portへ渡す。AtomicFile候補は比較/障害試験用として同じ契約を維持する。

採用実装は親を持たないprivate queue contextをSQLiteのpersistent store coordinatorへ直接接続し、単一DocumentのCodable payloadをsaveする。Core Data modelの版と、payloadのschema 7は別の版である。各transactionはprocess共有のfile lock内で最新disk snapshotを読み、期待revision・操作ID・対象・payloadを照合する。S21以降も同じwriter/journalを拡張し、確認＋outbox、失効tombstone＋ACK outbox、Photos、背景task、削除意図/結果に別DBを作らない。[NSManagedObjectContext.save](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/save%28%29)

`commit成功`はPortが永続storeへの保存成功を確認した段階と定義する。saveのcallback、ファイルの確定、再起動後の読戻し、領域不足・保護領域へのアクセス不可・破損を試験し、OS強制終了等で要求する復旧境界を確認する。Core Dataを選んだだけで電源断を含む全耐障害性が証明されたとはしない。自動保存だけに失効応答・削除許可を依存させない。

| 操作 | 副作用より前の記録 | 確定の条件 | 中断/再起動時 |
| --- | --- | --- | --- |
| 原本保存 | 撮影ID・出力参照・記録中 | 書込終了、必要な音声/映像を含む対象検査、保存結果commit | 原本と記録を照合。存在だけで正常保存へ進めない。部分/不明/失敗を分離 |
| 原本転送 | 本人の開始、原本識別、操作ID | サーバー保存・全内容検証証拠のcommit | HTTP結果から推定せず同一操作を照会。再送条件はサーバーと照合 |
| 明示確認 | 再生tokenと本人操作、原本/映像/確認世代 | 最新世代の再照合とvalid記録のcommit | 不明なら容量整理不可。画面上の受付表示は有効記録の代わりにならない |
| 失効 | 失効ID・旧原本/映像・新世代 | 旧確認を失効させるcommit完了後だけ応答 | 同じ失効IDは冪等応答。応答消失でも失効維持、失効保存失敗では応答しない |
| 両目的の原本削除 | 対象/目的/本人操作/判定世代を持つRemovalIntent | 実ファイルの対象照合・削除結果と管理記録の一致 | ローカルで削除済み/未削除/確認が必要を復旧。再接続不要。未実行意図を自動再実行しない |
| 写真登録 | 登録キーと操作ID、登録に渡す版・日時・一時媒体使用権。意図のexact commit確認 | 実SDK完了または未開始確定、FD閉鎖、結果のexact commit確認。成功後に使用権解放 | 追加済みの可能性を保持して照合。記録なしだけで再追加しない。成功commit後の未解放は元photo useだけを限定回収 |

DB、原本ファイル、Photos、Mac miniを一括で原子的に更新できるとは扱わない。外部副作用の前に意図、後に結果を保存し、間の不確実性を照合で扱う。応答欠落は元のmutation全体によるexact commit照会を優先し、別payloadの同IDを成功にしない。未知schema・破損・不正なjournal・Core Data model非互換は拒否し、既存DBの欠落/アクセス不能を空DBへ置換して正常復旧にしない。旧schemaの読取互換と、端末保護・OS終了・電源断の未確認範囲を分ける。

S41の共有記録契約では `RecordingStoreDocument` schema 7により、`RecordingIntent.trialReference: String?` と `capturedAt: Date?` を扱う。通常撮影は試験参照なしを許可する一方、暦日時を必須とする。旧schema 1〜6は試験参照と既存証拠を保持し、暦日時をnilのまま読み取り時に移行する。読み取りだけでは保存文書を書き換えず、現在時刻や単調時計の `acceptedAt` から日時を捏造しない。旧記録の日時欠損と未知schema・破損の拒否を区別する。

### 容量整理・破棄・失効の直列化

容量整理の許可は、同一ローカル原本、Mac mini保存・全内容検証、Rec.709軽量版、同一映像への永続化済みの有効な明示確認から導出する。Wi-Fi、Mac再接続、再生し直し、Photos保存、追加バックアップ、高品質版を条件に加えない。破棄の許可は本人の対象・消失リスク確認と明示指示から評価し、上記証拠が未成立でも受け付け得る別の規則とする。

容量整理では本人がまとめて指示した対象集合を固定し、以下を動画別に実行する。選択時の判定や他の動画の成功で許可を代用せず、不成立の動画を削除したり破棄へ自動移行したりしない。破棄は1本ずつ対象・消失リスクの確認を受ける。

1. 固定batchと動画別の子操作/対象/本人意思を同じjournalへ保存する。対象の書込終端・全readerのSDK実終端/handle解放を照合し、不明ownerを解放済みにしない。待機中の状態変化は本人確認へ反映する。
2. 同じwriterで原本参照・内容世代・目的・本人操作・全reader/epochを再照合し、RemovalIntentと予約をcommitする。容量整理は最新の保存・全内容検証・明示確認・対応・失効・登録/証拠schemaを再判定し、破棄は提示した単数対象と消失リスクの一致を確認する。全内容hashはwriter transaction外で同じ実FDを読み、管理root・lock・reservation・MOVの同一性を保持する。
3. `performRemovalBoundary`はprocess共有writer lock内で最新条件・予約・世代を再判定し、その短い確定区間で管理root/lock/FD/leafを再照合して `unlinkat` する。削除対象はその原本の `.mov` だけで、reservationやディレクトリの再帰削除、rename/trash、サーバー/Photos削除を行わない。媒体とDBを一括原子的な副作用とは扱わない。
4. 削除側FDの実close後に新しい存在/内容観測を用意し、`commitRemovalObservation`で同じwriter lock内の最終ファイル照合・観測FDのcloseから結果commitへ進む。別adapterや旧APIの古いpresent観測でunlink後を未削除へ巻き戻さない。実ファイルと同じ対象/目的/操作の結果が一致して初めて削除済みとし、参照不可・対応不明・close/記録失敗は要照合を保持する。
5. 照合済み結果で予約を解決し、待機していた失効を処理する。失効のcommitが先なら容量整理を拒否する。削除確定区間が先なら結果照合まで失効応答を待たせ、Mac mini側は正式旧版を維持する。不明の予約は保持する。

再起動でメモリ上の予約が失われた場合も、未完了RemovalIntentのローカル照合を同じ原本の次commandより先に行う。複数対象の成否・未処理・要確認を個別に保持し、中断後の未実行/未削除は新しい本人操作から再判定する。通信復帰を未実行削除の自動実行へ使わない。失効保存後は差し替え保留や通信断でも旧確認を復活させない。失効前にオフラインなら未失効の旧版確認は維持でき、他の条件を満たす容量整理を許可する。この操作は最後に取得した証拠に基づき、未取得のMac mini原本消失を検知できない。

S32/S33の復旧は実ファイルとjournalを観測するだけで、再起動・再入力・一覧refreshから未実行unlinkを再開しない。Libraryは整理成功を通常一覧に残し、原本なし・軽量版の取得/再生可否・確認・Photos状態を独立投影する。同じ破棄目的・実不在・成功結果を照合できたものだけ履歴へ分類し、不明/未処理/未削除は通常導線で要照合等を示す。管理記録を保持し、履歴に原本本体を移動・隠蔽するゴミ箱を作らない。S34の通常単数破棄には確認UI→実unlink→結果/履歴→再openの接続証拠があり、条件付きの通常複数容量整理も同じCompositionへ接続した。接続と必要検証の実行版・結果は[現行tasklist](../.steering/20260929-device-independent-implementation/tasklist.md)で追跡し、実機DV-17・全S34の完了と分ける。

複数整理の受付では、選択した全原本が存在し内容と保存記録の対応が確定していることと、適格候補が1件以上あることを表示上の条件にする。本人の確認対象と子操作を固定した後も、動画別に最新の保存検証・有効確認・失効・登録・全使用者終了を再判定する。表示用の適格性を削除権限にせず、証拠不足や通信終了不明の動画は未実行/要照合として独立した動画を処理する。終了処理も対象別に集約し、未解決子の受付閉鎖を保持しながら、確定した別の子だけを最新epoch/accessで再観測して受付を開く。共通storeの不明結果は成功に丸めず、明示照合から未実行削除を再開しない。

S34-BG01は対象の全historical uploadについてSDK実終端→ManagedUploadSource自身の保持FD閉鎖→ownerClosed commit→exact lease解放→stoppedを照合し、通常modelの本人リスク確認→単数MOV unlink→再open/履歴へ接続する。`OriginalRemovalTransportFence`は一つの代表receiptだけを権限にせず、全taskのstopped receipt配列とhash前に固定した対象別inventoryを持つ。inventoryは同原本のrequest/task/検証/関連登録と、その変更を含む既存の不変journalから導出する。

unlink直前の同writer lock内でinventoryと全receipt集合を再構築・再判定し、関連状態が元へ戻るABA、新attempt/task・関連登録変更、対象/世代/予約/readerの不一致を拒否する。対象に無関係な別clip更新だけでは新fenceを無効にせず、fenceなしの旧callerは従来の全writer revision CASを維持する。seal/inventoryは一時的な照合値で、共有schema 7・Codable文書/旧commandを変更しない。同じfenceを容量整理にも適用し、容量整理固有の保存検証・有効確認・支持schemaを最終writerでも再判定する。unknown・copy中・attach gap・旧source・task再利用/同operation複数attempt・download・活動中は保守的に拒否し、未知の自動復旧や活動中taskの自動停止へ広げない。原本unlink後もupload copyと管理記録を保持し、回収policyを追加しない。正式Rec.709の証拠producer、通常strict通信、未取得媒体からのPhotos保存、全S34・実機受入は残件であり、合成証拠やSDK fakeによる技術試験をその成立へ昇格しない。

## 端末機能・外部I/O

### 利用条件と権限

| 対象 | 利用方法・APIの対応条件 | 利用不可・拒否・失敗時 | 権限・必要なCapabilities |
| --- | --- | --- | --- |
| カメラ/記録 | AVFoundationでカメラ・format・出力を照合。4K/24・30fps/LT・422・Proxy/Apple Log、補正、WB、手動値の組合せを実機確認 | 未確認/非対応を区別。無断形式変更なし。絞り操作は実制御可能と確認したカメラだけ | 現projectのカメラ用途説明を使用し、必要時に権限を求める。説明設定を実機の許可・記録成立と混同しない |
| 音声 | 入力到着、入力経路、音量、writer結果を分離して観測 | 入力確認中は準備中、確認済み障害で開始禁止/録画停止、部分保存を試行。有界復旧後も本人REC | マイク用途説明と権限。外部マイク等の対応を先取りしない |
| プレビュー/解析 | 記録のLog経路から分岐し表示だけ固定Rec.709変換。人物/ND/予告は有界の入力を使用 | 古い解析を保留。表示の成立・負荷は未検証。予告のための複数カメラ常時起動を前提にしない | 追加の顔識別サービス・クラウド権限は要求しない。人物のVision本体と通常経路への接続はS45、実機品質はDV-06。S48の独立描画境界と、標準資材待ちの通常表示接続を分ける |
| 動画通信 | 共通ゲートを通るURLSession等。cellular禁止と経路判定・停止を扱い、保証不足の通常開始は閉鎖 | Wi-Fi消失/REC/保存で待機。停止要求と実停止を区別し、結果不明を照合 | 既存のローカルネットワーク用途説明を維持。Bonjour等を必要性なく追加せず、通信経路未成立を権限/例外追加で迂回しない |
| 再生 | ローカル原本、版固定したRec.709軽量版。軽量版確認は1本ずつstreamingを第一候補とし、AVFoundation/AVKitを検討 | ローカル再生はオフライン可。未取得の軽量版でオフライン再生は保証しない。既存配信/認証/版管理との成立性と一時使用量を検証し、大きな制約時は一時取得を比較 | Photosから読む方式を採る場合の権限はU2。再生不能を容量整理条件へ追加しない |
| Photos | PhotoKit追加、実完了結果、保存済みidentifierだけの照合 | 拒否/限定/権限変更/結果不明を分離。追加権限で読み取りが保証されるとはしない | 保存操作時だけ必要なaddOnly、対象と理由を示す本人の照合操作時だけ必要なreadWriteを要求。両用途文を設定し、起動/一覧refreshでは要求しない |
| 永続化・ロック | ローカルストアと管理ファイル。選ぶ保護属性・ロック時アクセスを確認 | アクセス不能を消失と扱わず、失効応答・削除成功・写真成功を推定しない | 一般のアプリsandboxを前提。App Groups/iCloud等を必要性なく追加しない |
| 背景・中断 | OSが許す既開始upload/downloadの背景/ロックと復帰イベントを対象にし、S23のsession/task所有へ接続 | 録画や通信の無条件継続を保証しない。復帰時に条件/対象/結果を照合し自動RECなし | 背景URLSessionの実終端・App delegate配送を先行実装。Capabilitiesを推測で追加せず、通常通信・旧owner復旧と実OS成立の残件を分ける |

### 記録・表示・解析の経路

通常撮影の `ProductCaptureCoordinator` は、希望設定の読込み→現在の能力確認→適用・読戻しを担当する。初回fpsは未選択とし、本人が選んだ24/30fpsを保存して以後の復元に使う。`ProductCaptureFactory`はライブラリと同じ原本領域・共通writerを渡し、カメラの準備を撮影入口まで遅らせる。試験票なしの通常撮影でもMovie/sample writerの二候補を保持し、非対応時は自動切替しない。共通保存が予約した出力先を使用して二重予約を避ける。

暦時計はCompositionから注入し、REC受付時に一度だけ観測する。ミリ秒精度へ揃えた同一値を `RecordingIntent.capturedAt` と両記録候補の媒体metadataへ渡し、単調時計の `acceptedAt`、実記録開始、最初のフレームの時刻とは区別する。後続の転送/Photosにもこの撮影日時を保持する。

記録意図のcommit後に実記録開始へ進み、記録終端とファイル確定を `OriginalSaveCoordinator` へ渡す。保存結果のcommit応答までは撮影側の保存処理として次RECを抑止する。応答後は保存結果を保持し、原本参照を固定した `ProductCapturePostSave` の単一queueへ渡す。内容対応のbindと続く一覧再読込みはこの後処理ownerが直列に行い、その完了を次RECの条件にしない。撮影coordinatorはCompositionが保持し、後処理は画面離脱や次の撮影でも存続する。後処理の成功・失敗を現在クリップの状態やRECゲートへ書き戻さない。

全内容digestは原本予約を扱うactorから専用actorへ渡し、全量読取りによって次の予約を占有しない。同一の開いたファイル記述子を使い、64KiB単位の全量読取り、前後のstat照合、取消検査を維持する。一覧の読込み中に追加更新を求められた場合は、その要求を保持して再読込みする。保存結果と内容対応は別軸で、未bindingだけを削除結果不明にせず、原本の対応未確定・要照合として表示する。未binding原本は転送・容量整理・原本再生へ渡さない。

アプリ終了後も保存済みの結果と原本ファイルを保持し、再起動時は既存記録とファイルの読取りから未bindingを表示する。後処理queueの永続化、自動再bind、新規の再試行UIやschemaは今回追加しない。初回fps・記録二候補の扱い・暦日時の観測点は2026-10-16のS41で合意済みだが、実機での記録方式の正式採用D01・G2B・画質・次RECの性能は未確認として保持する。

記録経路は音声/映像のタイムスタンプ、実適用設定、writer終端をCapturePort内で追跡する。REC時のWB固定をND完了やUI描画に依存させず、最後の記録フレーム後に待機Autoへ戻す。音量値がゼロであること、入力が届かないこと、書込が失敗したことを別の観測としてApplicationへ渡す。部分ファイル救済の成功を保証しない。

WB再固定はApplicationが録画状態と現在の対応能力から本人操作の可否を判定し、Native側が機器のmode・custom gains対応を照合する。後方互換のoptional能力値がnilの場合は未確認とし、対応済みへ補完しない。対応する機器では本人操作でone-shot `autoWhiteBalance`を開始し、`locked`への遷移観測後に現在のgainを固定する。その適用完了を再固定の確定とし、固定の測定秒数や色の品質閾値を追加しない。ISO・絞り・シャッターは変更しない。

合わせ直しとSTOPが競合した場合、Native側は測定観測を失効させ、現在のgainの固定適用後に記録停止へ進む。記録終端までは固定を保持し、その後に待機Autoへ戻す。KVO観測と適用完了callbackはcontext・tokenを照合し、旧操作・旧クリップの通知を現在の状態へ反映しない。次クリップへ固定値を持ち越さず、実機での色・録画継続性・最終フレーム品質はDV-03の未確認範囲として保持する。S42の進捗と検証証跡は対象steeringのtasklistを正本とする。

音声観測は `NativeCaptureAudioObservation` が入力経路・実sample到着・PCM音量・書込結果を分けて保持し、待機中から開始する。ゼロ音量は有効な到着として扱い、メーター非対応形式だけを入力障害へ変換しない。sample writerはappend受理とwriter終了を観測し、Movie方式は観測用sampleの到着をMovieの音声書込成功へ昇格させない。Movieが公開しない個別の書込事実は取得不能を保持し、既存の保存後検査と区別する。

メーター表示は最新1件のsnapshot経路で更新し、確認済み障害・停止・記録終端を扱う制御イベント経路と分ける。snapshotにはセッション/設定世代・任意のクリップID・単調な通知順序を付け、`ProductCaptureCoordinator` は現在の所有者に一致するものだけ受け取る。待機の観測で録画中のクリップ状態を上書きせず、旧セッションや旧クリップの通知を拒否する。確定した故障理由は後続の正常sampleや音量更新だけで解除せず、停止クリップの保存結果を次の入力復旧と別に扱う。

無到着期限判定と有限復旧には、2026-10-18のS43で本人が合意した変更可能な暫定製品policyを使う。`ProductCaptureFactory` は無到着2秒、本人の再試行ごとに1回、復旧上限5秒の同一 `audioPolicy` をNativeとcoordinatorへ注入する。Nativeの再構成範囲は音声入力/出力だけとし、カメラ・形式・WB・Movie出力は保持する。復旧中も2秒の無到着判定が働き、5秒は復旧全体の上限である。音声復旧は試行ごとの世代・操作ID・順番で所有し、完了・時間切れ・取消を照合する。取消要求だけでSDK資源を解放済みにせず、同じ試行の終了を確認するまで次RECと重複復旧を抑止する。成功は実入力到着の再確認で判定し、本人のREC待機へ戻す。S43の製品接続・実装完了判定・検証証跡は現行tasklistを正本とし、暫定合意を実機採用・品質合格へ昇格しない。実機の音声・同期・復旧品質はDV-10の未確認範囲として保持する。

S44の `CaptureStabilizationCatalog` は既存SDK候補の `off`、`standard`、`cinematic`、`cinematicExtended`、`previewOptimized`、`cinematicExtendedEnhanced` を保持する。保存希望がない初回の `standard` はPRDの第一候補を具体化した可逆な希望で、保存希望を上書きしない。`ProductCaptureConfigurationMatcher` は現在のカメラ・4K・fps・Logのformat条件で候補を絞り、コーデック・記録方式を含む支持と実適用は未確認として分離する。`previewOptimized` はプレビュー用で、現在の4K記録では候補理由を示して拒否する。候補外の保存希望も保持し、OFF・別モード・別の記録方式へ自動切替しない。

`NativeCaptureStabilization` はMovieFileOutputとVideoDataOutput＋AssetWriterの両候補で記録用video connectionの存在を確認し、OFF以外では補正支持も要求して `preferredVideoStabilizationMode` を設定・読戻しする。要求値の読戻しだけでは実適用の証拠にしない。`NativeExplorationCapture` はセッションとconnectionの動作・有効状態を照合し、`activeVideoStabilizationMode` を別の観測として渡す。OFFでもconnectionの存在・動作と実active値を確認し、希望・要求・実動作の一致を記録開始条件にする。

補正観測はactive/preferredモード、connectionのactive/enabled、倍率、active format、仮想カメラの実撮影カメラ、sessionの実行/中断をKVOで受け、Nativeの直列所有者上で現在値を読み直す。`CaptureStabilizationSnapshot` はセッション/設定世代・単調な連番・出力候補・カメラ/実カメラ・format/解像度・倍率と補正値を持ち、最新1件のstreamでApplicationへ渡す。`ProductCaptureCoordinator` は現在の所有者と世代を照合し、`CaptureFramingState` は旧世代・重複・逆順を拒否して状態のrevisionを更新する。再準備・中断・観測終了で旧状態を失効させても、同じ世代の受理済み連番の最大値は保持する。

RECの受理前にcoordinatorが現在のsnapshotを希望設定と準備時のformatへ照合する。Nativeも開始命令の受理前と、記録先の非同期予約が戻った実記録開始直前にSDKの現在値を読み直し、`matchesRecordingRequest` で世代・出力・補正の希望/要求/実active・カメラ・format・解像度・倍率を再照合する。予約待ちの間に条件が変わっていれば開始を拒否し、古い準備結果を開始許可に使わない。画角観測を供給しない既存adapterの互換経路は準備時の実適用照合を維持するが、現在の画角やプレビューとの一致を補完しない。

`CaptureFramingState` はS47の構図予告・停止候補の条件照合へ観測元とrevisionを供給する。`format.videoFieldOfView` は未補正のformat画角としてのみ保持し、補正後cropの数値へ換算しない。補正後の画角は取得不能、プレビューと記録の一致はOFFでも未確認のままとする。補正による実画角・3場面の品質・ズーム/切替との両立はDV-04/08/09等の実機検証へ残す。接続・検証証跡は現行tasklistを正本とし、SDK候補の保持をモード数・名称・強さの正式採用や全FR-03受入へ昇格させない。

S41のカメラ表示は構図確認用で、標準Rec.709変換を備えた表示の達成証拠にはしない。S48の `CaptureDisplayTransform` は技術試験用cubeの由来・版・用途・入力信号を明示し、cubeの数値範囲とSHA-256を照合する。`CaptureDisplayRenderer` はsRGB/Rec.709の色特性を持つ32BGRA入力だけを受け、暗黙の色管理を無効にした `CIColorCube` でencoded値を描画する。生成cubeによる技術描画を、標準Log→Rec.709変換の成立証拠にしない。

出力は技術試験用と識別した `CGImage` で、記録へ戻すpixel/sample bufferやwriter APIを持たない。変換済み入力は明示的な入力区分で拒否する。`CaptureDisplayPipeline` は処理中1件と置換可能な待機1件を保持し、セッション/設定世代・表示revision・単調な連番を照合して旧世代・重複/逆順を拒否する。再有効化や停止で処理中の旧結果の通知を失効させる。入力bufferの不変性はproducerとの契約であり、停止は描画処理の完了待ちやSDK資源解放を表さない。

標準資材は未取得で、`CaptureDisplayTransformCatalog` はApple LogとApple Log 2を別キーで拒否する。実Log変換と通常capture/UIへの接続は未実装のままS48へ残す。標準表示変換は入力Log種別と色特性が判明した経路だけに適用し、二重変換を避ける。Apple LogとApple Log 2には異なる色空間定義があるため、機種名やファイル名から一律に同じ変換を適用しない。採用するLog種別と標準資材の由来・版・利用条件・入力適合、表示とMac miniの変換整合、実原本への非焼込み・記録との両立・実機品質は別途検証する。進捗と検証証跡はS48のtasklistを正本とする。[AVCaptureColorSpace.appleLog](https://developer.apple.com/documentation/avfoundation/avcapturecolorspace/applelog)

S26Aは一次資料に基づく入力条件と比較案の記録までで、資材取得・変換・品質試験ではない。Apple LogのBT.2020 primariesとApple Log 2のApple Gamutを分け、Log 2のYCbCr matrixをprimariesの証拠にしない。各別のApple製Rec.709 LUTの説明と、実体/由来/版/hash/利用条件/数値域/既知入力・期待出力の未取得を区別する。生成identity/swapや検出規則 `apple-log-v2` を標準資材・Log 2用LUTへ昇格しない。技術適合と、同一標準参照を用いる色変換/圧縮比較の案、G3事前合意→DV-13品質評価→G5採用を分け、未合意の出力値・試験条件を追加しない。

解析用の待ち行列は有界とし、古い入力をためて追いつこうとしない。解析が追いつかない間は現在の有効なND/人物結果がないことを表す。どの処理頻度をどこまで下げるかはU7・実機測定で決め、シャッター/ISO/WB/補正や記録形式を勝手に変更しない。ND方向の有用性、同一主役の再捕捉、停止候補の画質は別の品質検証であり、無効化規則のテストだけで完成にしない。

S45では `CaptureSubjectSession` が露出対象集合・単一主役・追跡状態を分け、`ProductCaptureDevicePort` のcommand/snapshotとcoordinatorを介して人物枠・選択UIへ渡す。`ProductCaptureFactory` からNativeとcoordinatorへ同一の `subjectPolicy` を注入し、人物なし時のタップ位置AFと見失い猶予の変更可能な暫定3秒を通常撮影へ接続する。初回撮影意図は本人が選択して保存・復元し、未選択をREC条件に追加しない。これらのU5判断は2026-10-18に本人合意済みであり、接続・検証の進捗はS45のtasklistを正本とする。

`NativeCaptureSubjectAnalysis` は処理中1件と置換可能な待機1件の入力を保持し、専用queueでVisionを実行する。`NativeSubjectVisionEngine` は上半身検出とobject trackingに、明示選択時に固定した参照のFeaturePrint照合を組み合わせる。近傍の人物で参照を更新せず、複数候補の対応が曖昧なら主役として採用しない。SDKのUUIDは人物IDへ流用せず、画像類似度による照合を顔認識や同一人物の保証と扱わない。候補・特徴量はセッション内だけに保持し、恒久的な人物台帳を作らない。

S45のSimulator技術試験では、Vision revision 2のCPU経路で異なる入力から完全に同一の特徴量が返り、初回のみ微差が出る場合も観測した。ROI・crop・scale・入力形式・Core Imageのsoftware処理・CPU指定を比較しても残り、SDK内部の原因詳細は未確定である。この特徴量を人物同一性の根拠にしないため、検出ROIの実画素のSHA-256をVisionと独立に解析queueで計算する。固定参照の同一フレーム・ROIから上限2回生成した特徴量を保持し、特徴量が一致しても実画素が異なる候補は、候補IDの継続と主役の再捕捉に採用しない。上限2回の生成は初回微差による選択直後の別人受理を防ぐためで、通常の距離閾値は緩和せず、別画像で固定参照を更新しない。画素hashの一致も人物同一性の証明にはしない。

この確認のためにraw bufferを追加保持せず、hashと画像情報はセッション内だけで扱い、永続記録・送信しない。同じ人物でも画像が異なり特徴量が衝突する場合は、追従・再捕捉を続けず保持へ進む制約がある。この制約の影響と追加計算負荷はDV-06で未確認として評価する。Simulatorの特徴量出力自体が修復されたことや、実機の人物同一性品質を保証するものではなく、最終検証結果はS45のtasklistを正本とする。

解析結果にはセッション/設定・構図・対象選択の世代、連番、入力時点を付け、旧世代・重複/逆順・期限超過を拒否する。解析停止や構図失効で旧候補を現在の結果として残さず、見失い猶予後もピントを保持して本人の再指定を待ち、別人へ自動移行しない。解析専用出力の座標を正規化し、共有する記録入力は向き・鏡像が適合するものだけ受け取る。人物解析のために記録接続の向き・鏡像を変更せず、プレビューの枠・タップ位置はSDKの座標変換を使う。補正後の画角対応は実機確認を残す。

`NativeCaptureSubjectFocus` は主役への継続AF、見失い時の保持、追跡OFFの人物優先AF、人物なし時のタップ位置AFを能力照合して適用する。主役指定中は自動の顔切替を無効にし、非対応のAFを無断で固定へ代替しない。変更対象はフォーカス設定だけとし、読戻しによる適用・非対応・失敗を合焦品質から分離する。公開の上半身画像fixtureによる実Vision解析は技術試験の入力であり、別人通過・前後移動・再捕捉・距離/照明・補正crop座標・Log・記録負荷の実機受入を代替しない。製品接続、検証結果、未確認範囲はS45/DV-06で追跡する。

S46のND経路では、`NativeCaptureNDAnalysis` が処理中1件と置換可能な待機1件を専用queueで処理し、`NativeCaptureNDPixels` が解析分岐の実 `CVPixelBuffer` をread-onlyで読む。入力の色特性attachmentと画素形式・video/full rangeを照合し、撮影希望やプレビュー変換から入力信号を推定しない。画素を有界に標本化し、全体・選択した各人物のROI・その外側の背景を分ける。人物の鮮度・座標・選択全員の情報が揃わなければ、その人物を評価から黙って除外せず保留する。解析は端末内で完結し、バックエンド通信を使わず、解析画像や案内を原本へ書き戻さない。

`CaptureNDSession` は人物AFとは別のcontextにセッション/設定・構図・対象選択・WBの世代と撮影意図を持つ。`NativeExplorationCapture` はWB modeと実gainの変化を観測し、入力時と結果受理時にcontextを照合する。設定・対象・意図・WBの変更、逆順・遅延・期限超過・解析停止で旧結果を失効させ、`ProductCaptureDevicePort` の最新1件のsnapshotからcoordinatorとND表示へ渡す。coordinatorも現在の所有者・世代・順序・期限を確認し、入力映像の観測時刻から変更可能な暫定1秒の期限で結果を消して判定待ちへ戻す。解析完了や表示の時刻から1秒を数え直さない。WB変化の観測前に取得した入力を拒否するため、連続Auto WBで保留が続く可能性がある。現在のgainをフレーム固有のWB証拠とは扱わない。WB固定後も解析を継続し、ND未完了や警告をREC条件に追加せず、露出・WB・物理NDを操作する命令を持たせない。

`CaptureNDPolicy` は入力信号ごとの交換可能な未校正のcode-domain暫定基準を持ち、撮影意図に応じた対象から方向・理由・両立困難を参考表示する。2026-10-18のS46で、この参考表示と入力映像の観測から暫定1秒での失効について本人の承認を得た。通常 `ProductCaptureFactory` からNativeとcoordinatorへ同一policyを注入する。符号値の分布は表示IRE・EV・ND段数・センサー余裕の測定ではなく、飽和や情報不足から精密量を補完しない。製品接続と実機品質の受入を区別し、進捗・検証証跡はS46のtasklistを正本とする。方向の有用性、実入力色特性、WB変化・ROI・記録負荷、暫定基準・期限の実機評価とFR-06受入はDV-07の未確認範囲として残す。

### ズーム予告・移動とレンズ制御

S47は `ProductCaptureDevicePort` の `zoomSnapshots` / `updateZoom` を通じ、S41の撮影coordinatorとS44の画角観測へ接続する。`CaptureZoomSnapshot` はセッション/設定世代・revision・単調な通知番号、実倍率・実露出、現在の補正/formatと停止候補、命令の操作IDを持つ。`CaptureZoomState` は旧世代・逆順を拒否し、失効後も通知番号の最大値を保持する。coordinatorは本人が開始した命令と操作IDが一致した結果だけをセッション内希望へ反映し、次RECの照合に使う。周囲のSDK観測から本人の希望を作り直さず、保存済み設定と開始済み `RecordingIntent` は不変とする。

`CaptureZoomRequest.sequence` は準備世代内の本人命令を単調に並べ、予告の `context.revision` やsnapshotの通知番号とは分離する。Nativeの `NativeCaptureZoomCommandOrder` は受理済み命令番号の最大値以下を拒否し、非同期で遅れた移動・停止・手動ISO指定に最新操作を上書きさせない。移動・レンズ切替は現在のcontextも要求し、停止・手動ISOは同じ準備世代の新しい命令番号で先行操作を上書きできる。

目標選択は `CaptureZoomForecast` だけを作り、移動命令を出さない。予告のcontextと `CaptureFramingState` のrevisionを開始時にも照合し、倍率・実カメラ・format・補正の変更や観測終了で古い予告を失効させる。寄る側は `ProductCapturePreview` の表示層へ枠を重ね、引く側は `ProductCaptureZoomView` の操作欄に範囲図を表示する。いずれもwriterへ渡さず、倍率比だけを図示して未観測領域の映像や補正後の実画角を生成しない。

`NativeCaptureZoom` は現在の可動範囲、formatの拡大開始点・secondary native resolution、virtual deviceの切替倍率を根拠別の停止候補へまとめる。候補は実カメラ・format・解像度・補正を持つsnapshotに結び付け、画質確認済みとは表示しない。近傍候補は別ボタンで本人が選び、予告目標へ自動吸着しない。SDKのrampへ目標を指定し、両方向で観測実倍率と目標境界を照合する。目標停止と途中停止は同じ制御経路を使い、ramp取消だけで減速中にし続けず停止倍率を指定する。ズーム停止命令は記録終端命令から分離する。

`CaptureZoomPolicy.provisionalV1` は `s47-provisional-v1`、速度0.5（SDKのpowers-of-two/秒）、停止許容差0.005、近傍候補の許容差0.05と `isDeviceAdopted = false` を持つ。倍率は選択したcapture deviceの値を用い、`snapTolerance` は候補提示範囲であって自動吸着の指定ではない。制御と境界試験を先行する変更可能な評価値としてFactoryから注入する。変更箇所は [CaptureZoom.swift](../FrameRelay/Domain/Capture/CaptureZoom.swift) で、滑らかさ・停止精度・画角・画質・負荷の採用根拠にはしない。実機採用値と条件はDV-08で別記録する。

`NativeCaptureLens` は実active constituentの露出読戻しと切替前の条件照合を担当する。対応するvirtual deviceでは準備時のactive constituentを固定し、カメラ・倍率・ISO・シャッター・F値が変わっていないことを確認する。自動fallbackによる手動値変更を避ける可逆な実装方針で、Movie固有の記録時切替overrideを無効にして両記録候補を同じdevice制御へ接続する。ズームは現在固定したレンズの実可動範囲内とし、別レンズは本人の明示選択を要求する。固定非対応は制御の制約として表示し、未確認のレンズ制御を元のREC条件に追加しない。

現在の記録形式・解像度はS44のvirtual inputと記録connectionの観測を正本とし、physical constituentからはISO・F値・シャッター・手動露出状態を読む。センサー側の寸法が記録出力と異なるだけで次RECを拒否しない。明示レンズ切替の事前条件では、切替先のactive formatが記録の寸法・fps・Log・補正支持と一致することを保守的に要求し、照合できない経路は切替の制約として表示する。

レンズ選択では所属、固定対応、format/fps/Log、補正、手動露出、ISO policy、Movie overrideを副作用前に照合する。`CaptureLensISOPolicy` とNativeの補正処理は交換可能にし、本人が未合意の間は通常Factoryへpolicyを注入せず、切替不可と理由を示す。最終手動ISO/F値を基準とするF値比二乗・±1EV案はU6の回答待ちであり、実装済みの規則を製品合意済みにしない。補正範囲と端末範囲が交わらなければ拒否し、手動変更のrevisionを優先して旧補正完了を適用しない。実ISO/F値・カメラ・補正制約を読戻しから表示し、ISO変更開始/完了と実露出変化でNDの旧結果を失効させる。切替後保持・戻り基準・実経路の接続はS47で追跡し、途切れ・明るさ/色/ピント/位置・切替時間・音声同期・記録継続性はDV-09へ残す。

ISO適用中はsnapshotの `applied.values` を `.unavailable(.notMeasured)` として最新状態に保持し、coordinatorとNativeの両方で次RECの開始を抑止する。準備時の旧適用値を代用せず、この待機だけで進行中の録画を停止しない。`NativeCaptureLensExposureOrder` は適用revisionと手動revisionのticketを照合し、新しい手動指定が補正を上書きした後は旧完了通知を拒否する。通常Factoryの `lensISOPolicy` は引き続きnilで、候補処理と本人合意後の製品接続を分離する。

### 全動画通信の共通契約

`MediaIOGate`の規則は操作ID・対象内容・本人意思を受け、許可中のleaseと抑止理由を返す。原本送信、写真保存用取得、確認再生用取得/streaming、サムネイルの全媒体経路が対象である。REC受理時に新しい媒体開始を閉じ、既存I/Oへ停止を通知する。保存/異常終了処理の抑止は対応する処理の終端まで維持する。Mac miniで開始済みの検証/変換には停止命令を送らず、Mac ACKをREC開始条件にしない。

URLSessionの`allowsCellularAccess`はcellular禁止を設定できるが、`NWPath`の経路観測だけでは将来の背景送信のWi-Fi/VPN基礎回線を拘束しない。背景redirectの送信前origin審査も含め、厳格な開始許可は未成立である。実機試験だけを残す実装済み経路とはせず、通常のstrict admissionはattempt・原本lease・sourceコピー・SDK factoryより前で拒否し、SDK `resume`も`notExecuted`を維持する。要件を前景限定や保証の弱い方式へ縮小せず、方式の不足と実回線/OS検証を分ける。[allowsCellularAccess](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/allowscellularaccess)、[NWPath](https://developer.apple.com/documentation/network/nwpath)

原本転送・写真保存の新規開始はWi-Fi接続時だけ受理し、不在時の開始予約を作らない。選択しただけの動画と、受理済み対象集合内の指示済み順番待ちを区別する。Wi-Fi復帰や録画・保存終了後には、本人が開始受理済み・未完了・未停止/未キャンセルの通信だけを、全抑止条件、同じ原本/変換版/映像、既完了結果、認証/接続、操作寿命の再照合後に自動再開する。指示済み順番待ちも同じ規則とし、録画終了だけで再開せず未指示動画を追加しない。

OSが許す既開始upload/downloadの背景・画面ロック継続、個別停止/再開/取消・開始済み動画通信の全件停止、個別失敗後の独立動画続行と共通問題の待機は確定済みである。全件停止には指示済み順番待ち/自動待機を含め、本人停止は回線復帰・REC/保存終了・再起動で解除しない。通信の自動再開を未実行削除、結果不明Photos追加、終了済み再生へ拡張しない。再生を閉じたときは再生専用通信と使用権を終了し、転送/保存の操作証拠は画面移動で失わない。処理順・配置・操作寿命/期限等の具体値は残件とする。

媒体を含まない状態照会・保存/検証/変換結果・版・既存確認/失効の同期はモバイル回線でも許可する別gateとする。状態応答へ媒体を混ぜず、同期を契機に媒体を自動取得しない。動画通信の全件停止と全通信遮断を同一視せず、録画/保存優先と通信量管理を維持する。S28は既存登録・既知原本の本人による失効1page/manifest同期と明示的な続きを、元mutation/旧outboxのexact照合→同writer→動画別表示へ部分接続した。既知原本はlocalの論理原本と、同じstore UUID/現登録のcommit済みcatalogを合わせた固定集合とし、原本identityのUTF8 bytes・内容世代/hash/byte数で重複を区別する。

`PublicationManifestObservation`は、対象原本・現登録・store UUID・commandと、未公開を含むcurrent/revision/失効世代/置換待ち/媒体形式を同じschema 7 journalへ保存する純metadata観測である。既存の`.publication`による版採用・確認状態・配布/ACK guardとは別commandとし、観測だけで原本対応、確認、失効tombstone、ACKや媒体取得の許可を生成しない。古い観測・同revisionの版/形式の矛盾を拒否し、nil公開版でも過去の公開/確認authorityを消さない。commit不明は元mutationをexact照合し、authorityだけが確定してmanifest観測が未保存のpollを照合完了へ昇格しない。

catalogにUTF8 bytesが異なるUnicode正規化同値のcapture IDがある場合も、純metadata観測は各exact identityを保持する。既存writer/replayの互換契約は変えず、同期coordinatorが版採用の開始時と最終commitの同revision CAS直前に最新の論理原本を照合し、正規化同値のcaptureに異なるexact identityや内容があれば採用を未解決に残す。失効担当へのhandoffは衝突のないexact論理原本の存在を必須とし、別ownerへの作用やACKを発生させず未解決recordを保持する。旧併合履歴の修復、自動bindingやschema変更をこのguardから派生させない。

`LibraryPublicationProjection`は最後に保存した公開版ID/公開世代・観測版/失効世代・媒体形式・置換待ちをlocal一覧/詳細とremote一覧へ投影する。公開の観測、現在の失効、部分/完全取得の記録、実媒体の照合を分け、未取得はオフライン再生不可、完全取得記録も実媒体の照合が必要と示す。metadataの表示から現在のネット到達、正式Rec.709品質や通常媒体操作の成立を保証しない。

未解決失効とcursorを独立に保持し、再openではnullから再照合する。await後も登録/current storeをexact照合し、撮影日時と取得済みの保存・検証/版・失効の事実を分ける。旧版pointerが据置でも失効済み確認を復活させず、同期から新確認や媒体開始を生成しない。背景履歴/未知ownerの終端を照合できない対象はACKを保留する。この既存登録の明示同期と、再登録全体・通常媒体UI・全S28/実機受入の残件を区別する。

S23は同じschema 7 journalへOS session識別子/世代とtask、固定context（store・接続先/登録・操作・対象・attempt・lease/owner/epoch）の対応を保存する。Mac側のupload sessionとOS sessionを区別し、task数値IDやdescriptionだけの再利用を拒否する。`BackgroundMediaSession`は直列delegate queueと一つのevent streamを持ち、coordinatorの単一consumerがdisk commitと資源処理を順にdrainする。App delegateの背景配送handlerはこのdrain後にMainActorで一度だけ完了させ、handler完了やfinishEventsを全owner解放・遠隔成功の証拠にしない。

`ManagedUploadSource`は実原本leaseから有界にコピーし、全hashと出力FDの全読戻しで内容を照合する。実writer close後の保持read FDを固定taskへ束縛し、exactなSDK終端→自身のFD close→ownerClosed commit→当該leaseの実releaseを区別する。取消受付・OS task一覧の不在から遠隔未実行や全reader解放を作らない。再起動後の旧source/lease所有採用、安全なdownloadの永続受入口は未接続で、旧unknownは保持する。非送信の実背景URLSession task列挙/取消/実completion/invalidation試験は、この資源境界の証拠に限定する。

S49の `CaptureMediaAdmission` は最初のawait前にcontext/visit/nonceを持つowner別のrecording/saving/recovery holdをプロセス内で同期記録する。REC受付の単調な `acceptedAt` と暦日時はlocal-stop待ちより前に一度固定し、取消可能なpreflightをrecording token発行前に置く。STOP/leaveはそのticketだけを取り消し、旧returnで別RECを開始・解除しない。SDK実終端と自身のsource close・exact lease解放を照合した当該attemptだけをlocal stoppedにし、copy中・attach gap・未知旧ownerを停止済みと扱わない。

`authorizeResume`は同じadmissionとrevisionへ束縛した`CaptureMediaResumeAuthorization`を発行する。`performIfCurrent`はhold更新と同じNSLock内でorigin・revision・未hold・未消費を再判定し、一度だけ消費して短い非escaping/nonasync actionを実行する。有効なhold開始が返った後は、その前の許可からactionを開始しない。begin→endでholdが空へ戻っても古い許可は失効し、actionがthrowしても消費を戻さない。lock内でawait、後続処理のredispatch、admissionへの再入を行わない。この許可はプロセス内部の実行契約であり、新しい本人承認や操作を追加するものではない。

coordinatorの最終resume境界で発行した許可は、asyncな`BackgroundMediaSessionPort.resume`へ必須引数として渡す。SDK側はawait/queue hopの後、actual actionの直前に同じ許可を同期消費する契約とし、発行時のsnapshotだけを実行済みと扱わない。nativeの`BackgroundMediaSession`は正の`URLSessionTask.resume()`を追加せず、`notExecuted`を維持する。単回許可・hold/ABA・注入action・実Thread競合の試験範囲と実行結果は現行tasklistで追跡し、正の実SDK開始や実通信中RECの成立へ昇格しない。

停止受付や `recordingEnded` の応答失敗だけではsaving holdを解除しない。先着/後着するfile/終了未確認の通知を元contextで一度だけ消費し、file処理の実returnまで待機する。旧save drainとownerは新しいUI/REC/保存待機を変更せず、postSaveのhash/bind/一覧更新は次REC条件から分離する。通常Compositionへのこの部分接続と同期許可の契約/配線を、正の実SDK resume時の同期hold排他・S25等を含む全媒体producer・実通信中RECの未接続/未検証から分ける。S23/S49全体の停止/再開成立、実OS lock/kill/relaunch・回線/負荷は未受入のままDV-12等へ残す。

### Mac miniとの必要契約

PRDのMediaVault参照は限定スナップショット（`latest_template`、HEAD `c56d4a25a46acfa99dd66c4586621b5261af4d39`、2026-09-24）と、下表の2026-09-26の同HEAD限定ソース確認を起点とする。現行steeringでは、この系統の隔離snapshotで登録・受信保存/全内容検証・候補job・版公開と実HTTP/Swift再生を追加検証した。稼働API・実データ・実機の成立とは分ける。下表の必要契約と過去の不足は、現在の部分実装・正式proof/通常接続の残件を併記して扱う。

| 契約 | 必要な情報・不変条件 | 未確認・検証対象 |
| --- | --- | --- |
| 原本受信/保存検証 | 原本同一性、冪等な操作ID、受領範囲と保存/全内容検証結果を分離 | S22/S24の登録/保存は隔離証拠あり。S23の厳格な通信開始と通常原本転送統合、実原本/実回線は残る |
| 軽量版生成/取得 | verified原本から実映像をRec.709変換。原本不変。版固定の内容・日時・向き/fps/音声 | S26J候補jobとS25/S27固定版取得の技術証拠を、資材未取得のS26正式変換・U8出力採用・品質と分ける |
| 版公開/失効 | 公開V1と候補V2、失効ID/世代、配布先登録、端末commit後の全必要ACK、公開確定を分離 | S27の登録別台帳/公開gateに隔離証拠あり。正式authority、全製品owner、通常UIと実機は未成立 |
| 保存原本catalog | 現登録で同destinationのcompleted bindingと有効な保存evidenceの対応を照合し、原本identityだけを有界に列挙 | S28の明示取得→同writer観測→remote専用一覧を部分接続。現在の外部ファイル存在、端末の正式保存検証、正式版/媒体取得、旧確認/ACKの証拠にはしない。必要検証は現行tasklistで追跡 |
| 状態照会 | 操作/原本/版に対応する確定結果・不明・失敗を返し、媒体なしモバイル同期を別gateで許可 | 既存「削除候補」と新しい容量整理証拠を混同しない。S28の既存登録の明示ページ同期/同writer/表示は部分接続済みで、再登録全体・通常媒体操作等は残る |

クライアントの確認同期がまだ届いていなくても、旧版を配布した登録を必要失効対象にする。S27は配布台帳から登録別の必要ACKを保持し、差し替え待ち中の旧版配布受理も必要集合へ加え、最終公開transactionで全ACKを再照合する。端末は失効tombstone＋ACK outboxをcommitしてから応答し、古い/別登録・新登録のACKで旧登録の必要ACKを代用しない。timeoutや既存削除候補フラグによる省略はない。

再登録後も戻らない旧登録の必要ACKが得られなければ、初期版では該当動画の差し替えだけを無期限保留する。利用可能な既存公開版と新登録の通常一覧/取得/再生、別動画の独立操作を止めない。旧確認を新登録へ自動復元せず、容量整理する対象だけ再生・明示再確認する。全履歴再確認や一律の原本再転送・再生成・写真再保存を通常利用条件にしない。通常再起動と再登録を区別し、多端末サービスを新たにP0へ加えない。S28の再登録全体・通常媒体UIとDV-15実機受入は残件とする。

S28の明示新登録開始は、登録意図・登録記録が空の現在storeに、別store UUIDへ束縛された有効なv2 connectionが残る場合だけを扱う独立経路である。通常のrestore/register/保存済み接続による続行・初回入力からforeign bindingを採用しない。表示前の読取確認を書込み許可にせず、明示API内で同writerの現在store UUIDを永続確定してからremoteの接続先検査とKeychain追加へ進む。await後も同じUUIDと登録意図/登録記録が空であることを照合する。同storeでの中断は既存の照合/続行へ戻し、保存済みintentを別IDや新secretへ替えない。

この経路のKeychain追加は`store.<UUID>.connection`と`store.<UUID>.initial.<destination>`へcreate-onlyで行い、旧globalのconnection/initialのbyte列を移動・上書き・削除しない。再openでは現在UUIDのconnectionを優先し、その記録が不正/読取不能なら旧globalへfallbackしない。現在UUIDのconnectionがなくても同UUIDのinitialが宛先を問わず残る場合は、secret値を取得しない属性照合で検出して新登録を保留する。別destinationの入力でその中断/不明を回避しない。v1 unbound・破損・対応不明を新登録許可へ変換せず、旧global initialが存在する場合は旧connectionとの束縛を確認する。旧global initialの確定した`SecItemNotFound`は既知のconnection-before-intent形として区別するが、remote未実行や旧登録不在の証明にはしない。旧secret・有効確認・失効ACKを新登録へ継承しない。

Connection画面は旧記録保持と確認/ACK非継承を説明し、接続先/認証情報の別入力と明示開始を受ける。同じMac miniと既存bootstrap情報を本人が再入力する場合も含み、別Macや新しいtoken発行を必須にしない。キャンセル・離脱や再照合で新登録入力を閉じるときはbearer入力を消す。新登録開始と以下の保存原本catalogは別の部分接続とし、通常HTTPSでの正の結合、新namespace資格情報の実SDK受渡し、専用UI等の必要検証を現行tasklistで追跡する。

S28の保存原本catalogは、現登録のBearerと登録secretで認証した`GET /frame-relay/v1/uploads/inventory`から、同destinationの旧登録による保存完了原本も発見する。隔離serverはcompleted bindingと保存evidence/asset/job/claimの対応を検査する。1操作1ページ最大32件、JSON応答256KiB、cursor640ASCII、capture ID2048UTF8 bytesをこのmetadata列挙だけの上限とし、超過・completed/evidence不整合・不正cursorはページ全体を拒否する。既存保存APIのopaque identity契約を縮小せず、切詰めや行の黙示除外で成功にしない。元capture bytesと内容世代/byte数のcanonical UInt64値を保持し、cursorを不変session UUIDの順序と現destination/registration/generation/limitへ束縛する。

`URLSessionRemoteInventoryRemote`は既存metadata SDKのredirect拒否・応答量制限・実completion後のsession invalidation待ちを再利用し、前後に現在store/登録とKeychain資格情報を照合する。`RemoteInventoryCoordinator`は元request cursorと応答を照合し、store UUID・現登録・command・pageの観測を同じschema 7 journalへ加算する。commit不明では元mutationのexact lookupが確定するまでcursorを進めず、別ページを取得しない。続きは明示操作とし、再open後も観測を保持して先頭から再照合する。空/重複ページを過去項目の削除根拠にしない。

通常Connectionの「Macの保存記録を照合」/明示続行は同じCompositionのvault/writerへ接続し、結果後にLibraryを再読込みする。custom登録factoryへ製品Keychainを暗黙付与しない。Libraryの`remoteItems`はローカル項目と別の読取投影で、`RecordingStoreEntry`・原本参照・正常保存・自動bind・破棄履歴を生成しない。captureのUTF8 exactで同IDの別内容やlocal衝突を保持し、未提供の撮影日時は不明、現在のMacファイル存在は未照合とする。catalog取得だけで正式保存検証・公開版・確認・ACKを確定せず、その原本を含む明示状態同期のmanifest観測と分ける。未取得軽量版の通常取得/streaming・正式producer・全媒体・再登録全体は残件で、metadataの部分接続を実HTTP/専用UI/全Unitの成功、全S28・実機/PRD受入や本番反映へ拡張しない。稼働DBは操作しない。

2026-09-26の限定ソース確認では、`/Users/oyabu/dev/rep/latest_template` の以下を根拠とした。表のパスは同リポジトリの `backend/app/` からの相対パスで、行番号は上記HEADに対応する。実環境への適用や性能の証拠ではない。

| 観点 | 限定された根拠・FrameRelayへの含意 |
| --- | --- |
| ファイル配信・認証 | `api/assets.py:128` はその時点の正式版を解決する `/assets/{asset_id}/preview` と、指定結果の `/results/{result_id}` を持つ。`services/media_range.py:25` は単一byte/suffix/open Range、200/206、範囲ヘッダ、不正/複数Rangeの416を扱う。`services/processed_result_stream.py:129` はSHA-256のETag・result ID/size等を返す。`api/deps.py:8` はBearerを必須とし、Phase 2対象では `services/phase2_rollout.py:43` がクライアント版ヘッダも検査する。確認経路に署名URL/URL token認証はない |
| 版情報・出力 | `services/formal_preview_read.py:149` はgeneration、変換情報、preview/result ID、SHA-256、size、exact URLを返す。`services/ffmpeg.py:13` はH.264/AAC MP4＋faststartで、HEVCの実績ではない。既存RNにもremote再生と全量cacheの経路があるが、Swiftでの成立を示さない |
| 共通の不足 | `services/formal_preview_authority.py:20` と `services/initial_release_guard.py:24` のApple Logはcompress-only/transform none/unavailableで、Rec.709変換は未達。`api/assets.py:271` の確認入力はasset ID/versionで実再生版のID/generationを受け取らず、`services/asset_read.py:129` のサーバーsnapshot再照合だけでは本人が見た版を保証しない。`services/formal_preview_finalizer.py:199` は既存正式版がある公開を拒否し、確認範囲に端末の失効commit応答を待つ差し替え契約は見当たらない。初回公開保護をS5の達成としない |
| Rangeごとの負荷 | `services/processed_result_stream.py:55,90` の正常な指定結果の経路はtransaction前と`BEGIN IMMEDIATE`後に再解決し、`services/processed_result_integrity.py:61,103` で各回全ファイルSHA-256を計算する。開始/seekごとの応答時間・Mac I/O・SQLite write lock保持時間は重要な測定対象だが、性能不成立とは未判定 |

| 確認再生の比較案 | 利点・検証すべき制約 |
| --- | --- |
| 既存MP4 Range＋同じ正式resultのID固定URL | streaming第一候補。可変の `/preview` URLだけに版固定を依存せず、Bearer/版ヘッダと固定版契約を使う。S25/S27には全体取得前の実再生の技術証拠があるが、正式媒体・Wi-Fi/REC強制・実機負荷との結合は残る |
| アプリ管理のRange取得adapter | S25はAVPlayer resource loaderへ固定版の取得を渡し、一時媒体/使用権/終端を実装・技術検証した。通常の厳格なgate・全製品producerとの接続と実機負荷は未成立で、fixture成功を通常通信の採用完了にしない |
| 全量一時取得後のローカル再生 | 大きな制約がある場合の代案。取得完了までの待ちと全量分の一時容量をstreamingと比較する。全体取得を現行の明示確認条件へ追加せず、方式変更は比較結果を示して判断する |

S25の固定Range adapter/AVPlayer resource loaderは実再生到達と完全取得を分け、一時媒体の用途/使用権/実終端を同じwriterへ記録する。S27のsource配布commitを初回取得へ渡し、各readは固定source/登録/gateに束縛した新しいRange配布ticketを一度だけ消費する。全hashはtransaction外で新FDを読み、短いtransactionで現公開版・登録・ACK・payload・fingerprintを再判定してから同じFDで送出する。消費済ticketや公開後の旧版新要求は媒体0byteで拒否し、過去のexact replayを現在の配布権限へ戻さない。

公開artifactは候補とは別inodeにcreate-onlyで作り、全writer終端・fsync/close後に新FD全読戻しを行う。sealed namespaceはrootと正規化component、ASCII大小文字aliasを含め既知の書込・別名publish・回収から保護し、旧finalizer/backfill/pointer/確認/取得の入口もFR対象を拒否する。公開前に受理済みの応答は保持FDで旧inodeを読み得るため、端末の全scope終端/解放と失効commit/ACKを分けて照合する。read-only mode・保持FDだけで外部の直接in-place書込や任意SQLを防げるとはせず、hash/fingerprintによる拒否/中止の限界を明示する。既送出bytesの取消や外部改変中の版混在防止まで保証せず、全既知writerがsealed artifactを変更・回収しない所有規則を前提とする。

S27の製品authorityは正式品質proof未接続を `publication_proof_not_implemented` として拒否し、tests専用factoryのtechnical fixture authorityだけで公開/配布・実HTTPを検証する。環境変数/APIで製品authorityを解除せず、fixtureのQuickTime再生を正式Log/Rec.709や本番公開へ昇格しない。全製品external/recovery owner、S28の未取得媒体の通常取得/streaming・再登録全体、適合標準資材と品質・実回線/実機は残る。完全取得済みlocal枝の再生/本人確認の配線も、この正式producerの成立とは分ける。大規模HLS/CDN導入や検査省略を採用せず、streamingに大きな制約がある場合だけ全量一時取得との比較・代案を提示する。

### Photosと一時コピーの境界

Photosへの変更とアプリの操作記録は別の保存境界になる。S31の意図・追加結果・存在観測・SDK終端証拠・使用権解放は、共通writerのschema 7 `backendJournal`へcommandを加算する。`PhotoRegistrationRecord`はjournal再生から生成する派生projectionで、写真専用DBや別の正本を作らない。store identity・command・登録キー・期待revision・payloadを含む元mutationを`lookupCommit`で照合し、応答欠落を未保存や新しい追加許可へ変えない。

S31/S34の完全local軽量版consumerは、同じschema 7 journalに`PhotoSaveBatch`の親IDと順序付き固定子集合を保存する。各`PhotoSaveSource`はstore UUID・登録・版・媒体ID・撮影日時・MIME・directory/file identityを固定し、子は`queued → starting / notProcessed`として管理する。Photos結果は子operationと固定sourceを既存`PhotoRegistrationRecord`へexact joinし、batch専用の成功flagを作らない。同PhotoKeyをqueued/startingと単独の登録操作の間でも予約し、画面の選択変更や連打で対象を差し替えない。不明commitは元mutationをexact lookupし、期待revisionの付替やSDK再実行で解決しない。

初回の本人による保存受付は、nativeのdefault-routeが現在Wi-Fiである観測を必要とする。不明・offline・cellular等ではbatch受付・媒体使用・PhotoKitを開始しない。この観測はlocal写真操作の受付条件であり、通常動画通信のWi-Fi/VPN基礎回線を厳格に拘束する保証へ流用しない。取得完了local段階の受理後にはWi-Fi継続、iPhone原本本体の現在存在、軽量版の明示確認やMac再接続を追加条件にしない。子ごとに現store/登録/公開版・失効、元UTF8 exact原本、完全媒体の内容・日時・MIME・dir/file対応を再照合し、共有temporary owner/registryから直接`photoHandoff`使用権を得る。

batchの実行jobはアプリ寿命で所有し、同sessionで本人が受理・明示続行した集合だけを処理する。captureでは未開始子をholdし、準備済みの使用権を保持したまま、同期hold lockの外から起こされた処理が現在snapshotを読み直す。再起動後のqueuedは明示continue/cancelだけを扱い、starting・登録意図・結果不明からSDK追加を再実行しない。perform/releaseの処理は最初のawait前に一つへ固定し、SDK開始後のunknownを外側から使用終了としない。prepare→子開始の間で中断した旧orphan useを採用・推定解放せず、既存の不明保持を維持する。実装・接続と必要検証、正式Rec.709 producer・通常取得・全媒体/実機受入の残件は現行tasklistで分ける。

`ProductPreparedPhotoSource`はactorへのhandoff中にcapture holdが入った場合も`inProgress`として生存capabilityを保持する。driver実行中のwakeは終端でdrainし、完了履歴や生存capabilityのない不明開始を自動drive対象にしない。本人のbatch照合/続行は、同じlive cacheの既存owner/coordinatorだけを`PhotoSaveCoordinator.restore()`へ接続し、このinstanceがSDK非開始を保持している意図の保存結果を回収できる。新owner/coordinatorを生成せず、PhotoKit呼出しや写真結果unknownの成功化を行わない。再起動後の旧unknownにはこの非開始事実を補完しない。

`PhotoSaveCoordinator`はS25の完全取得・内容検証済み媒体と`photoHandoff`使用権を受け、意図exact commit確認→必要時addOnly→完全媒体のresolve→実SDK完了または未開始確定→保持FDの閉鎖を通る。SDK非開始の確定、または実completionとFD閉鎖を`PhotoUsageTerminal`として追加結果とは別にcommitし、そのexact commitを確認して元の使用権だけを解放する。結果commitの不明を登録失敗へ丸めず、使用権を解放しても結果・identifier・再追加抑止の記録を維持する。`NativePhotoLibrary`は元の撮影日時と`shouldMoveFile = false`で追加し、placeholderだけを成功証拠にしない。Task取消しをSDK終端とみなさず、実完了まで媒体を保持する。[写真ライブラリへの変更要求](https://developer.apple.com/documentation/photokit/requesting-changes-to-the-photo-library)

`BackendOutcome.succeeded(record)`は対応する操作記録を確定できたという応答であり、`record.outcome`の写真追加成功とは別の軸である。確定した記録内のunknown/failed/notAttemptedやidentifierを保持し、使用権解放の成功を写真保存成功の表示・再追加許可へ変換しない。

新規一時ファイル名はMIMEの完全一致に従い、`video/quicktime`は`UUID.mov`、`video/mp4`は`UUID.mp4`とする。原本の命名や媒体byte列・音声を変えず、拡張子だけを実container・Rec.709適合の証拠にしない。旧extensionless UUIDの読取互換と既存媒体を保護し、無断rename・移行はしない。旧extensionless媒体のPhotos再利用は未対応で、通常取得producerの接続時に扱う。

撮影ID・変換版の登録キーごとに直列化し、成功・不明・意図のみの中断から新追加を許可しない。未追加が確定した直前の`notAttempted`/`failed`だけに、新しい本人操作の`retryOf`を束縛できる。同じ媒体・版・撮影日時を照合して新しいphoto使用権を獲得し、新意図へ束縛する。旧useは再利用しない。この再試行は、本人が写真側で削除した後の手動再保存の合意ではない。

既存登録の照合はLibraryの対象・理由付き本人操作から`PhotoRegistrationReconciler`へ渡し、必要時だけreadWriteを求め、保存済みidentifierだけをexact fetchする。名前・日時による推定同定はしない。identifier欠落は対応不明とし、限定・拒否・読取許可済みでも未発見なら未保存や再追加許可にしない。写真側の存在観測と過去の追加結果は別々に保存・表示し、存在を確認できても過去の不明結果を成功へ書き換えない。起動・一覧refreshで権限要求やPhotos照合を行わず、写真権限の不足で撮影を止めない。[Photosの権限](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app)

使用権の解放とコピー本体の回収を分ける。新しい終端証拠は登録意図・元use・owner/lease/epoch・directory/file identityへ束縛し、意図と終端のexact `lookupCommit`後に`.releaseTerminalUsage`でそのphoto useだけを解放する。`restore`と`ManagedTemporaryMedia.closeOwner`はこの証拠を使い、失効時の全reader解放へ接続する。SDK稼働中、Task取消しだけ、finish失敗、別intentの応答、終端証拠のない旧unknown/意図のみの記録から終端を推定しない。他用途や一般の旧epoch使用権へ解放許可を広げない。

同じ登録・結果列・終端証拠・回収方式に対する呼出しが重なった場合、その回収だけを単一Taskへ合流させる。scope閉鎖のTask自体は待ち合わせ対象にせず、別の証拠や回収方式を同じ処理へ混ぜない。使用権が既に解放済みでも、元intent・releaseと回収方式が要求するterminalまたは成功結果のmutation/commitを同じwriterでexact照合し、同じuse・directory/file・store identityと使用中でないことを再確認する。単なる解放済みIDの存在から成功を返さない。

失効側のowner閉鎖が先行した後に同じcallerの解放要求が到着した場合は、上記の耐久記録と自ownerの実FD終端が一致する場合だけ、読取照合による使用権解放の成功を返す。rootを再openしたり、新しいFD・回収・unlink・Photos再追加を開始したりしない。rootの部分閉鎖や終端不明、別owner/use、証拠不足はunknownを維持する。一般のファイルAPIもrootの閉鎖状態を確認して拒否し、閉鎖済みFileHandleのdescriptorを参照しない。

既存の成功限定回収も維持する。成功commit後・解放前の中断から再openした場合、実completion→finish成功後に保存された成功recordと意図のexact commit・元use・directory/file identityを照合する。同じ一時rootの排他lockは旧ownerとの同時存在を防ぐが、SDK終端そのものの証拠にしない。いずれの使用権解放でも、登録結果がunknown/failed/notAttemptedのコピーは保持し、登録成功かつ全使用者なしの本体だけを回収する。原本や復旧記録の削除で代用しない。instance破棄・再openの試験を、実プロセス終了の証明として扱わない。

複数の写真保存でも受理時の対象集合と動画別の操作/版を固定し、取得・登録の成否と未処理を分けて保持する。取得済み版を登録するローカル段階にはWi-Fiの継続を要求しない。streaming確認とPhotos登録は別操作・状態であり、部分バッファを完全な登録用ファイルへ昇格させない。

TemporaryMedia担当はstreamingバッファを含む用途・取得範囲・所有者・解放可否と、動画別/全体の一時使用量を管理する。空き容量不要とは扱わず、容量不足では新規取得を止め、使用中のデータを無断回収しない。再生用は使用終了後、登録用コピー本体は登録成功かつ全使用者なしで回収し、恒久的な再生コピーへ転用しない。取得中断の断片は次回起動等で照合し、再開対象でない本体を回収しても確認記録と未解決結果の照合情報を残す。終端済みでも結果不明・失敗の登録用コピーを自動回収する方針は未実装で、バッファ方式・容量上限・保持期限とともにU2の残件とする。

実SDK adapter・同writer・S25媒体/使用権の下位接続、完全local媒体の単数/固定複数保存consumer、正式Rec.709媒体の生成/通常取得producerを区別する。未取得媒体のproducerは未接続で、local消費側の接続・必要検証を正式媒体や通常取得からの新規保存の完成へ拡張しない。自動検証の結果は現行tasklistを正本とし、SDK実装を検証成功や実機品質へ昇格しない。初回OS許諾・限定アクセス・本人の写真側削除後・実写真の映像/日時/音声/品質はDV-16へ残す。

## 品質特性

### 性能

| 項目 | 目標 | 測定条件 |
| --- | --- | --- |
| 撮影準備 | 通常起動で2〜3秒を目標。音声確認等の必須条件を省略しない | 初回権限・通常起動・復帰を分離。保存設定、端末/OS、温度、容量、音声経路を記録 |
| 次RECと通信停止 | 保存/サムネイル/解析/管理表示/サーバー応答を不要な待ちにしない。固定の追加数値は未合意 | 連続撮影、全動画通信中のREC、保存/異常終了、既実行削除との競合を個別測定 |
| 記録と表示/解析 | Log原本、音声同期、固定Rec.709表示と解析を合意品質で両立 | 4K・24/30fps・各ProRes/Log/カメラ/補正を区別し、歩行/パン/人物移動/ズームを評価 |
| I/O・メモリ | 原本/取得ファイルの全体メモリ展開を避ける。有界bufferと使用権で処理 | 通常30秒・時々2〜3分を代表例として大きいデータも確認。これらを録画上限にしない |
| 空き容量・熱 | 開始可否・停止・補助処理削減の基準は実機評価後に決める | 既存原本、取得断片、次の記録領域を区別。原本自動削除や音声省略で負荷を隠さない |

起動時は必要設定、撮影資源、未完了操作の安全な状態を先に準備する。過去全動画のハッシュ再計算・サムネイル作成・サーバー同期を撮影開始の一律の前提にしない。破損等で必要な操作記録を安全に確定できない場合は理由を示し、目標時間だけのために記録を省略しない。性能測定はAPIの処理時間だけでなく、本人の入力から実記録までを含む。

### セキュリティ・プライバシー

- 原本の削除器はアプリ管理領域内の確定した不透明参照だけを受理する。外部URL、文字列の任意パス、参照先が管理領域外となるリンクを対象にしない。削除直前の同一性を照合し、Mac mini/Photosの削除権限を注入しない。
- ネットワークからのサイズ・ID・schema/版・日時・内容情報を検証し、未知の状態を成功へ変換しない。認証された保存先と通信保護の具体方式は既存構成を調査して定め、全接続への例外や平文化を先に設定しない。
- 本人の家族動画、顔画像、音声、秘密情報、完全なURL/パスを診断ログへ入れない。解析は端末内を基本とし、新たな収集・広告・分析基盤を導入しない。ログの相関情報は最小限にする。
- 撮影、追加、必要なら写真読取、接続に必要な権限を用途に応じて扱う。権限拒否は該当操作に限定して示し、写真権限を撮影や有効証拠による容量整理の条件にしない。
- 診断ログと操作証拠を分ける。ログが消えても失効・削除結果・写真重複防止を失わない。診断用の任意送信やエクスポートを初期版必須に加えない。

### 信頼性・オフライン

| 状況 | 隔離・復旧方針 |
| --- | --- |
| ND/人物解析の遅延 | 有効な解析なしを示し、必要条件が整えばREC可。確認済み音声障害とは別に扱う |
| 音声/記録障害 | 録画中表示を終了し保存可能な部分を確定。保存結果と復旧結果を分離し、自動REC/無限再試行なし |
| Mac mini不通・認証切れ | 既開始操作の意図と証拠を保持。通信不可を保存失敗/確認失効へ変換しない |
| オフライン容量整理 | 有効な最後の記録に基づき手動実行可。現在の外部原本存在は保証しない。ローカル削除照合にMac再接続不要 |
| 確認/失効の保存失敗 | 有効確認や失効応答を出さない。失効済み記録は通信断・再起動で復活させない |
| Photos結果不明 | 未完了登録と照合情報を維持し、無条件再追加を止める。権限不足を写真消失と断定しない |
| 原本削除失敗/不明 | ローカル実体と操作記録を照合。本人の新たな操作なしに削除を再試行しない |
| 一時領域の消失 | 使用権/ファイルの存在を再照合して再取得待ちへ。確認記録やPhotos成功履歴は媒体cacheの消失だけで取り消さない |
| ストア破損/未知schema | 証拠が確定するまで容量整理不可。記録を初期化して失効・登録意図を失わせない。復旧可能性を個別検証 |

### アクセシビリティ

音量と入力障害、処理待ちと失敗、容量整理と破棄を色だけで区別しない。操作の目的・対象・動画別の結果/未処理に読み上げ名を付ける。人物枠/NDの高頻度更新はUI通知と分離し、毎フレーム読み上げない。R3の操作粒度を維持し、画面構成・選択/停止UIはU1等の残件として、VoiceOver・文字サイズ・縦横時の操作評価へ渡す。

## テスト戦略

本書では戦略、技術証拠の境界、未接続・実機残件を定義する。機能設計T01〜T21とPRDの79受入条件を維持し、以下の層へ割り当てる。実装・自動検証・実機確認・PRD受入は別軸で、実行済みの部分試験を全AC達成へ昇格しない。今回のM03は静的な文書同期だけで、build/test/helper/import・端末/外部操作を追加実行しない。

| 層・環境 | 主な検証対象 | 代替できない範囲 |
| --- | --- | --- |
| Swift Testing: Domain | REC/通信可否、容量整理と破棄、世代照合、ND期限、WB/主役/ズーム規則。clock/能力/証拠を値で注入 | 実際の色・合焦・音声到着・画質は実機で評価 |
| Swift Testing: Application | Portへ遅延・逆順・重複・不明・失敗を注入。固定対象集合・動画別の証拠/結果、選択と指示済み順番待ち、本人停止、条件付き自動再開、task寿命、原本単位の直列化、RECとゲート | fake停止成功だけでOSの実停止を証明しない |
| ローカル統合 | 一時的なテスト用ストア/原本でcommit前後の終了・再起動、schema、アクセス不可、領域不足、同一性、原本削除照合 | in-memory storeだけでdisk永続性を証明しない。無断で実原本を試験対象にしない |
| 通信契約統合 | 同じ操作の再送、保存検証、同じRec.709版のstreaming/認証/版固定、再開時の対応、失効のcommit応答、サーバー公開、古い応答、一時使用量/解放 | 限定ソース確認はFrameRelay契約との互換性検証ではない。制御可能な試験先で確認 |
| XCTest UI | 3操作の複数選択と動画別の成否/未処理、1本ずつの再生/明示確認/破棄、容量整理と破棄の分離、音声障害、二重入力、権限導線、アクセシビリティ | UIボタンの無効化だけで下位の排他/削除安全性を合格にしない |
| Simulator | 規則・表示・通常の保存/復旧、代替I/Oによる状態操作 | 対象カメラ、Log/ProRes、補正、音声経路、無線切替、性能の受入代替にはしない |
| iPhone実機＋実ファイル | 全撮影組合せ、WBフレーム境界、AF/ND/ズーム/補正、音声同期、起動/熱/容量、Wi-Fi切替、Photos | 機種名/API列挙を実機品質の証拠にしない。条件・許容範囲は事前合意 |
| Mac mini＋合意済みデータ | 旧MediaVault原本のRec.709変換/軽量プレビュー、新規FrameRelay原本の転送/検証、版差し替え | 旧写真原本の削除や汎用移行は前提外。対象・削除/上書きの合意は別途必要 |

中断試験では、意図保存前後、外部副作用前後、結果commit前後を区別する。特にV2生成、失効commit、応答、公開の各境界へ通信断/再起動を挿入し、容量整理との順序を両方試す。失効前のオフラインでは有効なV1による容量整理を維持し、失効後は旧確認を復活させない。FR-17では転送前・一部受信・Mac保存結果不明のいずれでも本人確認と対象排他を守り、Mac/Photosを連動削除しないことを確認する。

R3の追加条件AC-FR-11-04・AC-FR-14-07・AC-FR-15-05はT11/T14/T15へ対応させる。固定対象への順次処理、一部失敗・中断後の動画別結果、各削除直前の失効、未指示動画の追加禁止を確認する。T13/T16では全体取得前の実再生と原本全内容検証を分け、条件付き再開が終了済み再生・未実行削除・結果不明Photos追加へ波及しないことを確認する。

### 既存の検証構成

- [FrameRelay.xcodeproj/project.pbxproj](../FrameRelay.xcodeproj/project.pbxproj)のApp/単体/UIの3 target、最低iOS `27.0`、Swift言語モード `5.0`を維持する。実行時のscheme/test plan/destination、Xcode/コンパイラ/SDK・署名条件は現行tasklistのN01・各E証拠で確認済み範囲を追跡し、次の実行でも再確認する。
- 通常Compositionは共通store/原本/一覧/実再生、通常撮影、理由付きPhotos照合、単数破棄等へ接続されている。Swift Testing/XCTestは雛形だけでなく各境界の試験を持つ。空example・0件実行・skipを有意味な成功に数えず、過去の失敗・中間版を保持する。

| 証拠の層 | 主な実施範囲と限界 |
| --- | --- |
| disk・実ファイル | E-S11/S13/S21等のcommit/再open/内容対応/leaseと、E-S32/S33の実unlink・中断・結果照合がある。別storeを作らずschema 7へ拡張。fixtureとinstance再openを実撮影G2B・実OS終了・電源断へ昇格しない |
| iOS Unit・SDK・build | S23の非送信実背景URLSession試験、S31の実Photos/終端、S41〜47/49の撮影制御・所有境界と必要なSimulator/generic iOS buildに証拠がある。S34-BG01は実suspended task→resume拒否→cancel callback→自身source FD閉鎖→exact lease/stopped→通常model破棄/再openを確認し、permit/Mac notExecutedは注入。FD閉鎖はManagedUploadSource自身の保持FDだけで、SDK所有全FDの証明ではない。S48は技術描画のみ。最終版・依存が一致する範囲だけ証拠を継承し、通常strict通信・全媒体REC・正式資材へ昇格しない |
| 隔離backend・実HTTP | E-S24/S26Jに受信保存/全内容検証・候補job、E-S27にはbackend全230caseと実HTTP1件の成功証拠がある。後者は全量前AVPlayer進行→確認commit応答欠落/照合→scope終端→失効commit/ACK→V2公開を技術fixtureで確認。S28とBG01最終版にはmetadata-only実HTTPの失効page→manifestの2要求/媒体0byte/新確認・ACKなしの別証拠があり、旧S27証拠を置換しない。製品authorityは正式proofを拒否したままで、実Log/Rec.709・通常UI/全製品owner・実回線受入ではない |
| 通常UI・実体照合 | 一覧/原本再生/撮影/既存Photos照合、S28既存登録の明示同期とS34単数破棄の通常UI・実unlink/再openに部分証拠がある。BG01最終版のUnit/generic iOS build・通常UI/専用metadata UI/再openでも確認。S14の厳格アクセシビリティ監査4失敗は旧BG01版と直後の独立検証の過去証跡として保持する。P2修正後の結果と、その後の条件付き複数整理の接続・必要検証は[現行tasklist](../.steering/20260929-device-independent-implementation/tasklist.md)と各証跡の実行版を参照し、通常操作や実文字/VoiceOverの成功を監査合格にしない。完全local軽量版の単数再生/本人確認と単数/固定複数Photos消費側はそれぞれの接続・必要検証を別に追跡し、未取得媒体の通常取得/streaming・正式producer・再登録全体の未接続を保持 |
| 実機・PRD受入 | DV-01〜18/全79ACへ実装版・環境・対象・事前合意・証拠を束縛する。実装task done、自動試験成功、実機採用、AC全文充足を別々に判定し、未接続を実機待ちだけへ隠さない |

- 実行版・コマンド・件数・診断・失敗/skip・main差分レビュー・独立validationの区別は現行tasklistを正本とする。層ごとのソース版と依存不変を照合した証拠継承を、新しいbuild/testの実行と混同しない。稼働Mac mini/実データの成立や操作許可は隔離試験から導かない。
- 文書検証は要求ID対応、Markdown構造、ローカルリンク、確定/未合意・実装/未接続の区別、差分と所有範囲を静的に確認する。固定カバレッジ閾値を新設しない。

## 技術的制約と未決事項

### 製品動作の合意待ち

| 機能設計のID | R3の確定部分と残る未合意の内容 | 本書が維持する境界 |
| --- | --- | --- |
| U1 | 確定: 転送/写真保存/条件を満たす整理は複数開始、再生/確認/破棄は単数。整理成功は通常一覧、実削除照合済み破棄成功だけ履歴、不明は通常導線で要照合、管理記録保持/非ゴミ箱。残件: 選択/全選択・配置・処理順、録画後の画面、競合待機/停止導線等の具体方式 | 同じ正本から独立状態と一覧/履歴を投影し、本人確認・目的分離・最新条件・排他を維持。S34単数破棄/条件付き複数整理の接続を正式証拠producer・全S34・実機受入の完成へ昇格せず、外部連動削除・確認昇格・自動破棄なし |
| U2 | 確定: 全量取得を待たない同じ軽量版のstreaming第一候補、写真は別操作/状態。保存時addOnlyと必要な不明照合時だけ理由付きreadWrite。拒否/限定/対応不明/未発見は未保存と断定せず無条件再追加/写真側削除後の自動復活なし。残件: 再生元UI、アルバム/手動再保存、再インストール、保持上限/期限等 | 版固定・一時媒体/Photos下位処理と、完全local媒体の単数/固定複数消費側を分け、正式媒体/通常取得producerは未接続として保持。Wi-Fi/REC・確認/失効を維持し、大きな制約時は一時取得を比較。全量取得/常時写真読取を条件にせず、空き容量不要や大規模配信基盤採用としない |
| U3 | 確定: 既開始/未完了/本人未停止・未取消の通信だけ全条件再確認後に自動再開。OS許可範囲の既開始背景/ロック、媒体なしモバイル状態同期、個別失敗後の独立続行/共通問題待機、個別停止/再開/取消・全件媒体停止。残件: 処理順/配置/停止UI・寿命/期限・通信量/頻度等の具体方式/値 | S28の既存登録の明示ページ同期は部分接続済みで、未知背景対象のACKは保留。S23/S49の資源・REC境界と、厳格な開始許可/全媒体/旧source所有・再登録全体等の未接続を区別。実機未確認を理由に前景限定・状態通信Wi-Fi限定へ縮小しない。未実行削除・不明Photos追加・終了済み再生へ自動再実行なし |
| U4 | DI-07確定: 目標選択・予告・本人開始・目標/途中停止とREC停止の分離。S47の可逆実装: 倍率比の図示、根拠付き近傍候補の本人選択、自動吸着なし。残件: 速度/許容差と実画角・品質の実機採用 | 予告と実倍率、観測/推定、候補根拠と画質を分離。版付き暫定設定をDV-08の採用値へ昇格しない |
| U5 | S45合意: 人物なし時はタップ位置AF、初回意図は本人選択・保存復元・REC非阻害、見失い猶予は変更可能な暫定3秒で以後保持・再指定待ち。残件: 手動フォーカスの採否・操作、表示詳細、実機品質・猶予の実機採用 | 主役と露出対象を分離し、同一主役が不明なら他人へ自動移行しない。製品policy接続とDV-06の実機受入を区別 |
| U6 | S47のISO案は本人回答待ち: 最終手動ISO/F値基準、F値比二乗、基準±1EVと端末範囲、切替後保持・戻り基準・手動変更で更新。残件: 補正モード名/数/強さ、録画中の補正切替、Lens Match | 未合意policyは通常Factoryへ注入しない。保存希望/セッション希望/実値を分離し、限定ISO補正以外の無断変更を認めない。OFF＋複数モード要求を維持 |
| U7 | S43暫定合意: 無到着2秒、本人再試行ごと音声入力/出力のみ1回再構成、復旧上限5秒。復旧中も無到着2秒判定。残件: 音声policyの実機採用・品質、負荷削減・熱/容量基準 | 音声障害と静寂/解析遅延を分離。変更可能な暫定製品設定とDV-10の実機採用を区別し、有界復旧、自動REC/全体再起動禁止を維持 |
| U8 | 解像度/コーデック/品質/ビット深度/音声圧縮 | 1080p/HEVCは候補。原本不変、Rec.709実変換、元fps/構図/向き/音声/撮影日時の保持 |

U1〜U3はR3・連携仕様・DIの確定部分を維持する。U5の3判断はS45で合意済み、U7の音声policyはS43で暫定合意済みとし、S46の参考基準/入力観測から1秒の暫定期限も本人承認済みである。これらやS47の版付き暫定ズーム設定を実機採用・品質合格へ昇格せず、S47 ISO案の未回答を含む残件は保持する。streaming第一候補は無条件採用を意味せず、未合意値の保留をP0縮小の理由にしない。

### 技術成立・接続契約の検証待ち

| 対象 | 必要な証拠・決定時点 | 不成立/未確認時の扱い |
| --- | --- | --- |
| 撮影出力方式・端末能力 | 二つの記録候補と通常接続を維持し、D01の正式方式採用・各カメラ/形式/色空間/補正/手動値/音声/ズームの実ファイルを実機で評価 | API名だけでLT/Proxy＋Logや可変絞りを対応済みにしない。共通store/独立consumerをD01待ちに戻さず、代替と要求再確認を局所化 |
| 表示/解析 | 正しい入力色特性、標準変換の由来、ND/AF/構図/ズームの代表条件・事前許容・測定結果 | プレビュー表示だけ・常時保留だけ・人物枠だけで完成にしない |
| 保存方式/schema | Core Data/SQLiteの共通writer採用とAtomicFile比較、schema 7・disk commit/再open・削除最終照合の証拠を保持し、端末保護/実OS終了・旧owner引継ぎ等を追加確認 | 未確認境界を保証せず、確認/失効/削除の保存成功を装わない。未知schema/破損を空storeへ置換しない |
| MediaVault | S22/S24/S26J/S27の隔離証拠を保持し、正式Log/標準変換資材・品質proof、全製品owner/通常UI、実原本/稼働版/実機との接続を確認 | 技術fixtureを正式Rec.709や本番公開にせず、旧登録の必要ACKを代用しない。streamingに大きな制約があれば一時取得を比較。実データ操作は対象別合意を維持 |
| ネットワーク強制 | S28の既存登録明示同期を保持し、通常strict admissionの送信前経路/redirect保証、downloadの永続受入口、正の実SDK resume時の同期hold排他、全媒体producer等を接続・技術検証する。追加した単回同期許可の契約/配線と、実回線/OS/RECの成立は分ける | 制限を通過できない経路を有効化せず、未接続を実機待ちだけにしない。背景Capabilitiesを推測で追加しない |
| Photos/一時コピー | 合意した権限での動画別結果照合、登録直後の終了、同一版重複、写真側削除、バッファ/登録用ファイルの使用量・所有者・解放 | 不明を維持し無条件再追加なし。重複防止のためのユーザー写真削除なし。容量不要とはせず具体上限/期限は未決 |
| 実データ評価・整理 | 評価条件/方法/許容範囲、対象ファイル、試験環境、破壊的操作の明示合意 | 受入試験の実施だけで達成としない。実原本・本番相当記録を無断変更しない |

文書構造と記述観点は[architecture-design Skill](../.agents/skills/architecture-design/SKILL.md)、[新規作成テンプレート](../.agents/skills/architecture-design/assets/template.md)、[設計ガイド](../.agents/skills/architecture-design/references/guide.md)に従う。Workflow・所有範囲・実行条件は[AGENTS.md](../AGENTS.md)を参照する。
