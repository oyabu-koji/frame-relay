# Tasklist — バックエンド連携

## 状態・実行規則

- 計画日・実装開始日: 2026-09-28。明示された `$implement-steering` により実装工程を開始。各taskの状態を以下で管理し、受入は証跡が得られるまで未評価。入力は [確定仕様](../../docs/ideas/20260928-backend-integration.md)、要求とAC対応は [requirements.md](requirements.md)、設計・G0〜G6・V01〜V16は [design.md](design.md) を正本として併読する。
- 今回の明示 `$implement-steering` は本steeringの実装依頼として受領した。各操作の既存許可と具体範囲をT01／T04で照合し、既に許可された同一範囲へ再確認を増やさない。稼働環境変更・実DB移行・旧データ操作は依頼の対象外であり、実機・接続・品質条件は各ゲートで確認する。
- `pending`→`in-progress`→`done` を基本とし、障害・外部判断待ちは理由付き `blocked`、不要になったtaskは理由付き `cancelled` とする。書込みtaskは原則1件ずつ開始し、Ownerを実担当者名と実ファイルへ具体化してから編集する。完了条件と検証証拠を満たすまで `done` にしない。
- mainが判断・割当・統合・最終diff・進捗更新を所有する。着手taskのOwnerは実担当と所有ファイルを示し、pending taskのOwnerは予定役割として扱う。workerには他者変更を戻さないことを伝える。共有store、撮影ID／共通Port、Composition、`ContentView.swift`、project設定、MediaVault共通finalizerを同時所有しない。引渡し時に前担当の差分と所有解除を確認する。
- 本書の `Files` はtaskごとの変更候補範囲。空ディレクトリの先行生成や外部repo書込みを一括許可しない。テストは対応する既存targetに置く。新project／target／依存追加、iOS `27.0`・Swift言語モード `5.0` の変更を前提にしない。
- 初回および環境変更時の各build／test前に、実在するproject／workspace・scheme・destination・test構成を確認する。T03等の早期taskにも適用し、T24まで確認を先送りしない。backend試験も対象repoの実行規則・実在test構成・隔離先を先に確認する。
- 撮影D01／D04／D02とCF-08／P09の原本生成・保存分類・結果commit・復旧は既存撮影steeringが所有する。**G2Aは外部保存store、G2Bは外部撮影保存事実、G2Cは本steering T11が実装する追加access契約の完成条件。** T07はG2Aだけを外部前提とし、T09は`OriginalAccessPort`の契約fakeで完了できる。T11が既存OriginalStore／共通LocalStoreの引渡し契約を拡張して内容世代・全内容識別・read lease／実解放を追加し、T12がG2Cを消費する。T07／T09はT11成果を待たず、T08／T10は外部G2待ちでもT06Aの登録基盤を使って先行可。
- 必要な前提が欠けたtaskだけ停止し、依存しないtaskは同じsteering内で進められる。製品範囲・本人操作・品質・P0を変える判断はmainが影響・代案を提示して合意を得る。方式不成立を前景限定・全量取得必須・品質緩和へ置換しない。

## 段階・ゲートの対応

| 段階 | タスク | 開始／完了の境界 |
| --- | --- | --- |
| S0 契約・復旧 | T01〜T03 | G0の範囲確認。撮影実媒体を必要としない契約・fakeまで先行可 |
| S1 早期通信判断 | T04〜T06 | G0隔離後にG1を観測し、製品実装を広げる前に方式判断 |
| S2 初回登録・転送・保存検証 | T06A、T07、T07A、T08〜T12 | T06A→T08、T07A→T09／T12を守る。外部G2A→T07、外部G2B→T11、T11製G2C→T12。保存証拠はG4、独立backendは外部G2待ちでも可 |
| S3 軽量版・品質 | T13〜T16 | 撮影D02とG3事前合意、G5の出力選定。技術fixtureと本人品質評価を区別 |
| S4 確認・登録・後続契約 | T17〜T22 | 端末commitと全公開経路の失効ACK、再登録、G4障害証拠。写真／削除は契約まで |
| S5 結合・引渡し | T23〜T26 | G6実回線・実機・品質・全AC追跡。実装完了／検証工程完了／PRD達成を別判定 |

G0〜G6（G2はG2A／G2B／G2C）の全文はdesignを適用する。G3は品質試験前の具体案への本人合意、G5は実評価後の採用判定であり、互いに代用しない。Tasksは既存T01〜T26と追加T06A／T07Aの全28件。現在の状態は各taskを参照する。

## Tasks

- [x] **T01 実行範囲・既存資産・共有所有者を確定する**
  - Status: done
  - Owner: main。
  - Files: 本steering3文書の範囲・証跡欄。FrameRelay／MediaVaultのAGENTS・現状差分・設定は読取り対象。
  - Depends: 明示 `$implement-steering`。G0の既存許可と予定操作の照合。
  - Done when: 両repoのbaseline、対象revision、保存対象の旧動画／管理記録、再利用・変更・新規の区分、撮影担当との共有ファイル単一所有を記録する。外部repo・接続先・実機・試験データごとの実行可能範囲と保留範囲が識別できる。
  - Verify: V16。差分・設定・対象パスをread-onlyで確認し、実DB移行／デプロイ／旧データ削除を実行範囲へ混入させない。BI-14／AC-BI-31。
  - Stop: 現工程の計画許可しかない操作、所有衝突、対象不明は当該作業を停止。未追跡媒体・既存差分を除去しない。
  - Progress (2026-09-28): mainがGit・入力3文書・skillsを読取り確認。HEAD `b2895ed3d1f2442c8ceea3743735feedd0557731`。開始時の変更は `docs/ideas/memo.md`、未追跡は本steering・確定仕様・`README.md`。125ファイルのSHA-256と既存差分・3文書を `/private/tmp/fr-backend-20260928-hqkp_gij/` に保存。既存内容を保った追記・限定更新で進捗を同期し、README／memo／入力仕様は編集しない。外部repoはexplorerによるread-only調査中。
  - Result (2026-09-28, E-BI-01): 両explorerのread-only調査とmainの入力・差分照合を完了。MediaVaultは `/Users/oyabu/dev/rep/latest_template`、HEAD `c56d4a25a46acfa99dd66c4586621b5261af4d39`、追跡差分なし・未追跡JPEG 1件保持。適用規則は同repoのAGENTS。design「MediaVault」の再利用／変更／新規区分は現ソースでも一致。旧媒体・DB・公開pointer／履歴・JPEGは保全対象であり操作しない。稼働版・実データ配置は未確認のまま。
  - Ownership / G0: mainは本steeringのみを編集。T03 workerへ連携新規Domain／Port／testの実ファイルを単独割当し、既存撮影型は参照のみ。既存撮影ID／CapturePorts、store、OriginalStore、coordinator、Composition、ContentView、projectは撮影側所有のまま編集保留。G2A／G2BはP09 pending・D01／D04未選定で引渡し未成立。FrameRelay内の契約実装・fake／Simulator試験と `/private/tmp` の証跡作成を実行範囲とし、外部repoの書込み、稼働環境、実DB、旧媒体、実機／実回線は未実行。T04で具体的隔離先と起動範囲を別途確定する。G0全体通過を意味しない。

- [x] **T02 識別・Port・wire契約と判断台帳を具体化する**
  - Status: done
  - Owner: main（契約判断と撮影／backend担当の調整）。
  - Files: 本steeringのdesign／tasklist。API・schema・既存Portは読取り照合。
  - Depends: T01。
  - Done when: 接続先・初回登録意図／結果・登録世代・操作・試行・原本内容・保存証拠・版・配信内容・確認／失効世代を区別した入出力と不明状態、commit／実解放境界を定める。capability／wire版・論理操作を洗い出し、具体endpoint・DB・通信／配信方式・値の採用はT06へ分離する。G2A／G2Bの外部producer・証拠と、T11が新規実装するG2Cを分ける。
  - Verify: V01、V02、V04、V11〜V13、V15のシナリオを契約へ対応付ける。BI-01〜BI-14とrequirementsのAC表に欠落がないことを確認。
  - Stop: 内容世代と撮影設定／store revisionの混同、対象同一性や後続順序が定義不能なら該当契約を保留。API名だけで耐障害保証を確定しない。
  - Result (2026-09-28, E-BI-02): design「T02 契約具体化」に識別8区分、Portの型付き入出力・commit／不明・実解放境界、論理wire capability、固定対象／停止／失効／配布・公開／再登録／後続順序、J01〜J06判断台帳を記録。V01／02／04／11〜13／15を対応付け、BI-07／13の品質とBI-12／14のUI・保全を後続taskへ保持。具体endpoint・DB・digest・方式・運用数値の選定は行っていない。G2A／G2BのproducerとT11製G2Cを分離。既存撮影型とPortをread-only照合し、設計への割当をmainが確認。

- [x] **T03 Domain・状態規則・Portと契約fakeを用意する**
  - Status: done
  - Owner: `ios_contracts` worker（連携新規Domain／Portと残るfake／test）、`contract_tests` worker（`FrameRelayTests/Domain/BackendOperationRulesTests.swift`、`BackendPublicationRulesTests.swift`、`FrameRelayTests/Support/BackendOperationFixture.swift`の3ファイルのみ）。同一T03内で所有を分割し、既存撮影ファイルは参照のみ。
  - Files: `FrameRelay/Domain/Media/`、連携用`Domain/Operations/`、`Application/Ports/`、対応`FrameRelayTests/`。
  - Depends: T02。
  - Done when: 固定対象・本人停止／取消・待機集合・外部結果、確認／失効、配布／公開、後続証拠の規則を副作用から分離する。原本／store／transport／後続consumerのfakeで決定規則を検査し、fakeを製品原本・製品storeとして注入しない。
  - Verify: V01、V02、V04、V11〜V13、V15の契約試験。AC-BI-01、AC-BI-05、AC-BI-10〜13、AC-BI-20〜30の順序・旧世代・不明のケース。後続実削除達成とは記録しない。
  - Stop: D01／D04を独自選定する必要が生じた場合は撮影側へ返す。共有Portに同時変更があれば所有引渡しまで停止。
  - Progress (2026-09-29): 新規契約値・純粋規則・Port・test target内fakeを実装中。mainの先行差分確認で、期待revisionの自己照合、版を省略した結果照合、古い照会応答、実通信完了とMac成功の分離、削除照合失敗時の予約保持を確認し、担当workerへ修正／試験を依頼。build／test前であり受入未判定。
  - Result (2026-09-29, E-BI-04〜06): 上記修正と、store読戻しだけから登録commit・保存検証証拠を復元する契約を含め、新規App 15ファイル・test/fake 7ファイルを実装。V01／02／04／11〜13／15の新規35試験、既存単体試験を含む89 test・100実行が成功（パラメータ化11 test／22実行、既存空雛形1を除く有意味99実行、失敗0・skip0）。buildとSimulator起動も成功。mainが全新規ファイルと既存baselineへの差分を確認、既存App／project／撮影steering／README／memo／入力仕様は不変。fakeの製品Composition注入なし。T03契約層だけを完了し、disk永続性・G2C・実通信／実再生／実Photos／実削除は未確認。

- [x] **T04 MediaVaultの隔離試験先とデータ保全を準備する**
  - Status: done
  - Owner: `backend_isolation` worker、mainがG0・差分を確認。
  - Files: 許可されたMediaVaultの隔離設定・fixture・対応testと本steering証跡。稼働設定・既存DB／媒体は変更しない。
  - Depends: T01、T02。外部repo書込み・試験操作の具体範囲が許可済み。
  - Done when: 使い捨てDB、media root、API／worker、port、token、全設定とcleanup対象を列挙し、既存mountとの非共有を確認する。起動時migration／backfill／worker復旧の副作用が隔離先だけに限定される。
  - Verify: V16。起動前に解決後設定と実パスを照合し、許可範囲内の隔離起動後も旧fixtureの内容・記録不変を確認する。AC-BI-31。
  - Stop: DBだけ隔離して媒体やworkerを共有する構成、実環境に向く設定、秘密を記録する操作では起動しない。実DB移行は計画外。
  - Scope (2026-09-29): 外部repoへ書き込まず、`/private/tmp/fr-backend-20260928-hqkp_gij/T04/` の追跡ソースsnapshot・使い捨てDB／合成媒体／設定・fixture・証跡だけをworkerへ割当。既存Python 3.12環境をread-only利用し依存を追加しない。APIはTestClientのin-process起動、workerは空job状態でrun_once、port／外部通信なし。実効設定の全パス非共有・秘密非出力を起動前に確認し、起動時migration／backfill／復旧／回収の影響を合成fixtureで照合。既存repo・稼働環境・実データは操作しない。cleanupは専用T04 rootだけを候補とし今回は削除しない。
  - Result (2026-09-29, E-BI-07): 固定HEADの追跡249ファイルsnapshot、全22設定、解決後パス、DB／媒体／一時領域の非共有、秘密redact、API／worker／port／cleanup範囲を確認。合成pre-004 DBでAPI起動時の004〜007 migrationとbackfill 1件、空jobのworker単発実行と指定孤児preview 1件の回収を観測。保全5ファイルの全内容hashと旧asset既存列／derived／session記録は不変。限定既存8ファイル・58 pytest成功。初回pytestはログ先の隔離guard拒否で収集前exit3、専用log先を設定して解消。mainがlauncher／guard／smoke・結果を読取り確認。外部repoと未追跡metadata、snapshotはbaseline一致。Python guardの監査限界と実データ・実回線・品質の未確認を保持し、この隔離構成だけでT04完了とする。

- [ ] **T05 背景・回線・固定版再生の早期小規模探索を行う**
  - Status: blocked
  - Owner: `backend_isolation` worker（T05専用隔離probeのみ）、main（G1の証跡・未確認条件整理）。実機探索担当は未割当。
  - Files: 許可されたiOSの通信／再生探索adapter・対応test、T04隔離配信fixture、観測証跡。project設定はmainの単一所有。
  - Depends: T03、T04。G0の実機・接続・非私的fixture使用範囲。
  - Done when: LAN／外出先Wi-Fi＋Tailscale、基礎回線切替、背景／ロックupload／download・復帰callback・保護条件、認証付き固定版実再生／Range負荷、REC相当停止と一時量／解放を小規模に観測する。URLSession／Network／再生候補の可否・制約・観測限界をG1資料へ記録する。
  - Verify: V05、V07〜V09。AC-BI-07、AC-BI-09、AC-BI-14、AC-BI-18の技術的成立性を実byte・callback・版identityで確認し、実撮影受入・画質合格とは区別する。
  - Stop: 観測できない媒体経路、cellular漏出、認証／版混在、背景不成立、Range負荷の重大制約は製品拡張前に比較案へ戻す。P09未完了を理由に本探索を終盤へ送らない。
  - Scope (2026-09-29): T03／T04の完了後、`/private/tmp/fr-backend-20260928-hqkp_gij/T05/` の合成byte・使い捨てDB・probe／証跡だけをworkerへ割当。T04 snapshotはread-only参照。in-process APIの固定Range、認証欠落、公開pointer更新後の旧版要求を測定し、全hash量・transaction／writer競合・媒体byteを記録する。性能閾値・方式・運用値は採用せず、実動画・実再生・ネットワークの証拠と混同しない。実機／回線条件は本人へ確認中、Simulator列挙だけではG1の必須観測を満たさない。
  - Partial result (2026-09-29, E-BI-08): 2,097,169 byteの合成V1から`bytes=1024-2047`を取得し、206・1,024媒体byteと固定ID／hash／size／Rangeの一致を確認。全hashは2回・計4,194,338 byte、2回目は`BEGIN IMMEDIATE`内。別requestでその間の他writerが`SQLITE_BUSY`、応答後に取得可能と確認。認証欠落401、不正Range416、V2公開後V1のGET／Range／If-Range付き再開は3件とも409・媒体byte 0（JSON bodyは存在）。正常完了とiterator明示closeで媒体descriptor解放を確認。公開前受理descriptorはV2後もV1 byteを返す既存挙動を別のservice直接呼出で観測。配布台帳／失効ACKの新要件は未実装のまま。mainがprobe・全論理DB差分・外部保全結果を確認した。
  - Blocked / resume: 実行先一覧に利用可能なiPhone実機がなく、本人への接続可否確認は未回答。LAN／外出先Wi-Fi＋Tailscaleの実経路、背景／ロックupload／downloadと復帰callback・保護条件、認証付き固定版実再生、基礎回線切替、REC相当停止・一時量／実解放の必須観測は未実施。再開には対象端末／OS・接続可能状態、隔離APIの接続先／portと回線条件、使用する非私的な再生可能fixtureを具体化する。未回答を許可やG1成立と扱わない。T06とその全依存taskはpendingを維持し、前景限定・全量取得必須へ要求を縮小しない。撮影P09待ちだけを理由に停止したものではなく、独立して可能な本Range観測は実施済み。

- [ ] **T06 通信方式・API・schema・運用値を判断する**
  - Status: pending
  - Owner: main（必要な製品判断を本人と合意）。
  - Files: 本steeringdesign／tasklist、将来変更するMediaVault実ファイルの所有一覧。稼働DBは対象外。
  - Depends: T02、T04、T05。
  - Done when: G1証拠から採用／棄却理由を記録し、論理契約を具体API・DTO・schema・ID・DB制約・保存順序へ割り当てる。認証・接続先照合・初回登録／同一操作照会・再登録の具体手段、全内容識別方式、状態payload／頻度／量、retry・backoff、一時媒体方式／上限／期限、通信保護・必要設定を根拠とともに決める。全媒体取得入口の現公開対象照合・配布commitと全公開更新の短い確定区間を定める。端末製品storeの結合はG2A後のT07へ残す。
  - Verify: V03〜V09、V12、V16の観測方法と各adapter／公開経路の所有を照合。AC-BI-07、AC-BI-08、AC-BI-14、AC-BI-18、AC-BI-31。未合意値・新規依存の自動採用がない。
  - Stop: 要求に影響する通信／配信方式変更は影響と代案を提示して再合意。D04未完了はT07の製品store決定だけを保留し、本taskの独立backend契約の完了を妨げない。

- [ ] **T06A 接続先照合・サーバー初回登録と結果照会を実装する**
  - Status: pending
  - Owner: backend登録worker。共通認証／repositoryの単一所有をmainが割当。
  - Files: T06で指定したMediaVaultの接続先identity／認証・登録API／schema／repositoryと対応test。実DBは対象外。
  - Depends: T04、T06。隔離fixture clientで実施でき、T07／撮影G2は前提にしない。
  - Done when: 認証した接続先identity、初回登録操作、登録identity／世代を永続対応付け、同じ登録操作の結果照会・再送を照合する。応答欠落／サーバー再起動で無条件に重複登録せず、不明を保持する。T08が利用する確定登録の照合窓口を提供する。
  - Verify: V04、V13、V16。AC-BI-05、AC-BI-25とBI-04。接続先不一致・bearerのみ・登録不明では登録済みとせず、commit前後／応答欠落後の同一操作照会で同じ確定登録と世代を返す。端末commitはT07Aで別検証。
  - Stop: 接続先／登録の対応不能、未選定認証方式、隔離外副作用は該当登録と依存受信を停止。T17まで登録基盤を先送りしない。

- [ ] **T07 本人意思・証拠・確認／失効の端末永続化を実装する**
  - Status: pending
  - Owner: iOS store worker。撮影共有storeの実ファイルは単一所有者から引渡しを受ける。
  - Files: `Application/MediaOperations/`のstore境界、`Platform/LocalStore/`の連携adapter、対応`FrameRelayTests/`。原本保存復旧の再実装は含めない。
  - Depends: T03、T06。**製品adapter結合と完了には外部G2A（撮影D04／P09の保存store契約・証拠・所有引渡し）だけが必要。G2B／G2CやT11は依存ではない。** 使い捨てstore比較は先行可。
  - Done when: 固定対象・本人意思・結果・確認／失効・同期outboxを期待世代付きの単一writerでcommitし、再openで読める。commit前後の不明・未知schema・破損・容量不足・ロック保護を空store／成功に変えず、撮影正本と二重化しない。
  - Verify: V04のdisk再読戻し・commit境界障害。AC-BI-05、AC-BI-11、AC-BI-20、AC-BI-23。メモリ内成功・親contextへのsaveだけを確定証拠にしない。
  - Stop: G2Aの保存store引渡し欠落・未解決のschema衝突・同時所有では製品接続を停止し、探索storeで代用しない。未実装のG2Cを停止理由にしない。

- [ ] **T07A 端末の初回登録commit・不明時照合を接続する**
  - Status: pending
  - Owner: iOS登録worker。T07のstore接点は所有引渡し後に編集。
  - Files: 連携Remote／Credentials adapter、登録coordinator、`Platform/LocalStore/`の登録記録・対応`FrameRelayTests/`。
  - Depends: T06A、T07。
  - Done when: 接続先identityと初回登録意図を先行commitし、サーバー確定登録／世代を照合して同じstoreへcommitする。応答欠落・端末commit不明・通常再起動では保存済み意図から同一操作を照会して復旧し、無条件に新登録しない。媒体通信の開始条件へ確定登録を提供し、再登録でも使える共通基盤とする。
  - Verify: V04、V13。AC-BI-05、AC-BI-25とBI-04。意図／サーバーcommit／端末commit／応答の前後に中断し、再open後の接続先・登録identity／世代の一致と重複なしを確認。bearerのみ、別接続先、不明登録では媒体を開始しない。
  - Stop: 接続先照合・秘密保護・永続対応の確定不能は登録不明のままT09／T12の媒体通信を保留。新登録や空storeで救済せず、T19を初回基盤の前提にしない。

- [ ] **T08 backend受信・最終保存・独立全内容証拠を実装する**
  - Status: pending
  - Owner: backend保存worker（外部repo実ファイルの単一所有）。
  - Files: T06で固定したMediaVault `backend/app/api/`、`schemas/`、`services/upload_sessions.py`／`upload_finalize.py`、関連repository／job受付と対応test。
  - Depends: T04、T06、T06A。撮影G2やT07／T07Aは前提にせず、T06Aで登録した隔離fixture clientで先行可。
  - Done when: T06Aの接続先・確定登録／世代を照合して操作・内容・session／受領範囲を対応付け、最終保存先の独立読戻しと全内容照合結果を耐障害順序で記録する。証拠commit後だけ正式変換jobを受理し、応答欠落時に同一結果を照会できる。旧フラグ／旧原本記録を新証拠へ無条件昇格しない。
  - Verify: V03、V16。AC-BI-03、AC-BI-04、AC-BI-05。端末申告のecho・組立時hash・既存`file_verified`だけではverifiedにならないことを確認。
  - Stop: 最終保存先の検査不足、対象対応不能、既存データへの副作用が出る場合は該当確定・変換受付を停止。

- [ ] **T09 転送・停止・取消・条件付き再開を接続する**
  - Status: pending
  - Owner: iOS通信worker。
  - Files: `Application/MediaOperations/`、`Application/MediaIO/`、`Platform/Remote/`、`Platform/Network/`、対応`FrameRelayTests/`。撮影接続はT11へ渡す。
  - Depends: T03、T06、T07、T07A、T08。`OriginalAccessPort`は契約fakeで検証し、T11／G2Cの具象実装は依存にしない。
  - Done when: T07Aの接続先・確定登録／世代を照合し、Wi-Fiで受理した固定対象だけを送信して再送前に受領範囲・実結果を照合する。個別失敗／共通障害、全件停止の順番待ち、取消後成功、OS task復旧を独立状態で保持する。全媒体に共通gateを適用し、状態DTOと媒体を分離する。原本accessとREC／保存は契約入力で制御でき、実原本の使用権・実解放の実装結合はT11へ渡す。
  - Verify: V01、V03〜V08、V13。AC-BI-01、AC-BI-05〜14、AC-BI-28の停止要求／通信実停止とfake lease解放通知の順序。未指示・完了・本人停止／取消・終了済み再生が自動開始せず、登録不明なら媒体を保留。fake成功を実原本の実解放証拠にしない。
  - Stop: gateを迂回する媒体通信、登録未確定・未知OS task・対象／世代不一致・未照合の結果不明は通信を保留。server cancelを本人取消に直結しない。G2C未実装だけでは契約／adapterの完了を妨げない。

- [ ] **T10 保存境界の障害・再起動・重複防止を検証する**
  - Status: pending
  - Owner: backend保存worker、mainが証拠を確認。
  - Files: MediaVaultのT08対応test／障害注入点、隔離DB／媒体、tasklist証跡。必要修正は同じT08所有ファイルに限定して再割当。
  - Depends: T08。T07／T09／撮影G2待ちでも独立実施可。
  - Done when: chunk受信・組立・最終確定・読戻し・証拠commit・job受付・応答の各前後で中断／再起動し、fileとrecordの実結果を照合する。不一致・容量／記録失敗・応答消失で不明／失敗を保持し、重複作成・証拠前変換がない。
  - Verify: V03全境界、V16旧fixture不変。AC-BI-03〜06。G4のサーバー側証拠として実行環境・故障点・再読戻し結果・保証限界を記録する。
  - Stop: 稼働DB／媒体への障害注入、照合不能を未実行に置換する復旧、再現未解決の損失は次の製品結合を停止。

- [ ] **T11 連携用内容識別・原本accessを追加しREC／保存抑止へ接続する**
  - Status: pending
  - Owner: mainが指定した撮影連携worker。共有Port／Compositionの編集権を一人へ引き渡す。
  - Files: `Application/Ports/`、連携`MediaIO/`、撮影coordinatorの接続窓口、既存`Platform/OriginalStore/`／共通`LocalStore/`の内容対応・read lease追加、Composition、対応test。共有ファイルは撮影担当から引渡し。
  - Depends: T07、T09、**外部G2A／G2B（撮影D01／D04・CF-08／P09の保存store・確定参照／保存結果・復旧／REC状態の引渡しと証拠）**。G2Cは本taskが生成する成果。
  - Done when: 撮影の確定参照・保存分類を基に同じstoreの引渡し契約を拡張し、独立した内容世代・全内容識別を永続対応付ける。撮影設定世代／commit revisionを流用せず、再起動／再試行で再採番せず同一内容を安定照合する。`OriginalAccessPort`・read lease／全reader実解放receiptを新規実装し、T09のfakeを具象へ置換する。REC受理から保存／異常処理終了まで抑止し、端末実停止と全lease解放を分離してG2Cを完成する。原本世代の別正本、原本書込・保存分類・撮影復旧の二重実装は作らない。
  - Verify: V02、V07、V15。AC-BI-02、AC-BI-09、AC-BI-10、AC-BI-28。内容対応commit前後中断・再open／再試行・別store更新でも同一対応、別内容／不明の拒否、複数readerと再起動後の全解放照合を確認。Mac停止ACKをREC条件にせず、探索unknownを正常化しない。G2C証拠をT12／T21／T23へ渡す。
  - Stop: G2A／G2Bの撮影保存事実・store契約欠落や所有衝突、原本生成／分類／復旧自体の不足は該当実接続を止めて撮影担当へ返す。内容世代／access／解放receiptの未実装は本taskの作業であり着手停止条件にしない。これらを正しく実装・検証できない場合はG2C未完了として依存する実原本受入を止める。

- [ ] **T12 実原本と実保存先の転送・検証を統合する**
  - Status: pending
  - Owner: iOS／backend結合worker（書込みは各所有範囲を順次引渡し）、mainがG4を判定。
  - Files: T06A／T07AとT07〜T11の連携adapter・対応test、許可された実原本・隔離保存先の証跡。撮影原本／稼働データは改変しない。
  - Depends: T07A、T10、T11（G2C完成、入力のG2A／G2B証拠）、G0の具体的原本・保存先使用範囲。
  - Done when: 接続先とサーバー／端末の確定登録・世代を照合してから、T11の内容識別／使用権を用い、撮影が確定した同一原本からMacの最終保存先まで全内容を対応付ける。原本不変、送信／保存／検証の時点分離、証拠後変換受付、再起動照合を実I/Oで示す。部分／不明／アクセス不能を拒否し、使用した媒体と保証限界を記録する。
  - Verify: V02〜V04、V13。AC-BI-02〜05。登録不明／別接続先を拒否し、登録応答欠落復旧後も同じ登録・内容で照合する。端末disk証拠と独立した保存先読戻しを照合してG4を更新し、fixture成功を実原本成功に流用しない。
  - Stop: G2C未完了、接続先／登録未確定、原本との対応不明、保存証拠欠落なら依存する受入を保留。実保存先に接続不能でも別fixtureを実受入の代用にしない。

- [ ] **T13 採用Log・変換根拠と具体的品質比較案を合意する**
  - Status: pending
  - Owner: main（担当側が案を作成し本人へ提示）、撮影担当からD02を受領。
  - Files: 本steeringdesign／tasklistの判断台帳・合意証跡。許可素材の識別一覧を記録し、私的媒体自体はrepoへ追加しない。
  - Depends: T02、T06、撮影D02の採用実Log・標準変換資材／版／由来／利用条件。T12完了は本提案の前提にしない。
  - Done when: 縦横・24／30fps、肌／空／暗部／細部／動き・音声を含む具体素材、1080p HEVC等の候補、本人iPhone・明るさ等の表示条件、色と圧縮を分ける比較方法、技術照合と許容範囲を提案し、品質試験前に本人合意を記録する。未選定の出力を採用値にしない。
  - Verify: V10の試験計画照合。AC-BI-16、AC-BI-17、AC-BI-32。G3の対象素材・候補・表示条件・方法・許容範囲・合意日時が揃う。
  - Stop: D02未選定、資材根拠／利用条件不明、具体案への本人合意未取得なら品質試験を開始しない。一般的な評価方針の合意だけでG3通過にしない。

- [ ] **T14 検証済み原本から標準Rec.709候補を生成する**
  - Status: pending
  - Owner: backend変換worker（T08のjob接点は所有引渡し後）。
  - Files: T06で指定したMediaVault変換worker／authority／生成物記録、対応test。最終公開pointerはT17の共通判定へ接続する。
  - Depends: T08、T10、T13（G3）。
  - Done when: 採用実Logに適合する標準変換と出力候補を実装し、原本・資材・設定・変換版・生成物identityを保持する。原本と旧公開版を上書きせず、変換だけ失敗した場合は検証済み原本から再試行する。候補生成と公開を分ける。
  - Verify: V03、V10。AC-BI-06、AC-BI-16、AC-BI-17。原本不変、実色変換、fps／向き／構図／音声／日時／開始終端／AV同期を技術照合し、compress-only・タグ変更・二重変換・無断補正を拒否する。品質採用はT16。
  - Stop: 未検証原本、Log／変換資材の対応不明、禁止補正や旧公開上書きが必要な経路は停止。

- [ ] **T15 固定版配信・実再生・一時媒体管理を接続する**
  - Status: pending
  - Owner: iOS再生workerとbackend配信workerをmainが順次割当。
  - Files: `Platform/Playback/`、`Platform/TemporaryMedia/`、連携Remote adapter、Playback用Application、MediaVault固定result配信／integrity、対応test。
  - Depends: T06、T07、T09、T14。
  - Done when: 原本・変換版・映像・配信内容・公開世代をmanifestで固定し、認証・Range／seek・切断再開・実再生tokenを共通gateと接続する。manifestだけで配信許可／本人確認を作らず、公開後の旧版取得拒否を自動V2差替え／redirect／混在へ変換しない。部分／完全取得、用途別使用権、一時使用量／回収、local再生を分離する。T17前は公開判定fake／隔離候補fixtureで検証し、製品配布はT17の全取得入口・台帳・公開ゲート接続後だけ有効にする。
  - Verify: V05、V09、V11、V12、V15。AC-BI-07、AC-BI-15、AC-BI-18〜20、AC-BI-22、AC-BI-30。V1 manifestのみ→V2公開→V1 GET／Range／再開拒否をfakeで与え、媒体混在・自動差替え・確認確定なしを確認。受理済み進行中応答とlocal再生は区別し、失効後の旧tokenで確認しない。実公開競合はT17／T22へ渡す。
  - Stop: AVPlayer等の独自取得をgateで制御／観測できない場合や旧版拒否を迂回する場合は方式判断へ戻す。全量取得・恒久コピーを黙って標準化せず、T17未接続で製品配布を開かない。

- [ ] **T16 本人品質評価を行い出力を選定する**
  - Status: pending
  - Owner: mainが比較と証跡を準備し、本人が通常鑑賞を判定。
  - Files: 合意した隔離出力候補、技術測定／本人評価証跡、本steeringのG5判断。採用設定の実ファイルは変換担当へ一時引渡し。
  - Depends: T13、T14、T15。G3合意済み条件と許可された実素材。
  - Done when: 本人iPhoneの同一条件・通常サイズ／通常再生で色と圧縮を分け、技術特性も照合する。許容された候補の容量・取得時間を比較し出力を採用する。評価対象identity・合否・根拠を記録し、写真登録後の最終鑑賞は後続必須として残す。
  - Verify: V10。AC-BI-16、AC-BI-17、AC-BI-32。G5に素材・出力値・表示条件・技術結果・本人評価・容量／取得時間が揃う。停止／拡大は補助に留める。
  - Stop: 不適合・未評価・未選定ならFR-12未達／未評価を保持。条件を緩和せず原因・代案・再評価範囲を提示し、合意外素材や別表示条件の成功を流用しない。

- [ ] **T17 配布台帳・現公開対象照合と失効ACK先行の全公開経路を実装する**
  - Status: pending
  - Owner: backend公開worker（配信／共通finalizerを単一所有）。
  - Files: MediaVault配布記録・失効／ACK schema／repository、全媒体取得入口、固定result／formal／managed／rendition／backfillを含む全公開pointer更新経路、対応test。T06Aの登録基盤は既存接点として再利用。
  - Depends: T06、T06A、T08、T15。候補fixtureで実装検証可、製品採用出力の受入はT16結果を用いる。
  - Done when: T06Aの確定登録を利用し、全製品取得入口で要求版／公開世代と現公開対象の一致確認・配布台帳commitを公開pointer更新と同じ短い確定区間へ置く。V2公開後の遅延V1 GET／Range／再開はbyte前に拒否する。V1配布受理が先行すれば、進行中応答も含め必要ACK集合へ加えて全ACK後だけ公開する。全公開経路が共通判定を通り、旧登録無応答なら該当差し替えだけ無期限保留する。
  - Verify: V09、V12、V13、V16。AC-BI-18、AC-BI-21、AC-BI-22、AC-BI-25、AC-BI-26、AC-BI-31。登録済み端末がV1 manifestだけを取得（配布台帳には未登録）→V2公開→遅延GET／Range／再開はbyte 0で拒否。逆順の配布commit先行・待機中の追加登録では集合／失効ACKが揃うまで公開しない。既受理端末の公開後の新規要求も拒否し、全入口／全公開経路・古いACK・timeout・V2失敗を照合する。
  - Stop: 現公開対象照合の欠落・台帳commit前配布・失効ACKなし公開・実DB backfillが必要な経路は止める。ネット応答終了までDB lockを保持せず、新登録で旧ACKを代用しない。

- [ ] **T18 端末の明示確認・失効commit・ACKを実装する**
  - Status: pending
  - Owner: iOS確認worker（storeと原本単位順序窓口は所有引渡し後）。
  - Files: `Application/MediaOperations/`の確認／失効、連携store／outbox、対応`FrameRelayTests/`。
  - Depends: T07、T15、T17。
  - Done when: 単体の実再生token・本人操作・登録・原本／版／失効世代を再照合し、確認と同期outboxのcommit後だけvalidにする。manifest／取得拒否から確認を作らない。失効は端末commit後だけACK可能とし、重複・逆順・応答消失を照合する。受理済みV1応答の遅着・取得済みlocal再生・再起動・V2失敗でも、失効後の旧確認を復活させない。
  - Verify: V04、V09、V11、V12。AC-BI-19〜24。V1 manifestのみ→V2公開→遅延取得拒否では確認なし、V1配布受理→失効commit／ACK→V2公開→旧応答／token遅着では旧確認非復活を確認する。失効後local再生も旧確認を作らず、単なるMac不通・同一映像再取得・通常再起動だけなら既存validを維持。途中再生可・全量／全編不要も守る。
  - Stop: 確認／失効の確定保存・対象世代が不明ならvalid／ACKを返さない。実削除consumerはT21の契約のみ使用。

- [ ] **T19 状態同期・再登録・旧登録保留を接続する**
  - Status: pending
  - Owner: iOS復旧／登録worker。
  - Files: `Application/Recovery/`、連携Remote／Credentials adapter、登録・状態同期coordinator、対応test。
  - Depends: T07A、T09、T17、T18。
  - Done when: T06A／T07Aの初回登録・結果照会・永続対応を再利用し、モバイルでは小さい照会・既確認／失効同期だけを行う。最終取得と最新照合を分け、通常再起動では同じ確定登録を照合し、新登録で旧確認を有効復元しない。整理対象だけ再確認し、全履歴の再確認／再転送／再生成を通常利用条件にしない。旧登録応答不能でも別動画と利用可能な既存版は使える。
  - Verify: V04、V06、V12、V13。AC-BI-08、AC-BI-13、AC-BI-24〜26。同期の媒体混入・自動取得／再生／本人確認なし、取消後結果、旧版不可・失効の保持を確認。
  - Stop: 接続先／登録identity不一致、秘密保護条件不成立、未知schema・照合不能は当該同期／再開を保留する。

- [ ] **T20 必要な選択・動画別状態・操作・再生導線を組み立てる**
  - Status: pending
  - Owner: iOS UI worker、mainがComposition／`ContentView.swift`の単一所有を引渡し。
  - Files: `Features/Library/`、`Features/Playback/`、`Application/Library/`、Composition／`ContentView.swift`、必要なunit／UI test。
  - Depends: T09、T11、T15、T18、T19。
  - Done when: 複数対象選択・手動開始、個別停止／再開／取消・全件停止、動画別独立状態・理由／次操作、単体実再生・明示確認を接続する。View選択と永続開始集合を分け、画面離脱で依頼を消さず、色以外でも状態を伝える。取得を写真保存済み・契約判定を削除済みにしない。
  - Verify: V01、V09、V11、V14。AC-BI-01、AC-BI-12、AC-BI-15、AC-BI-19、AC-BI-33。表示値と永続証拠、UI受付とcommit、動画別一部成功／不明が一致する。
  - Stop: 最終ライブラリ全UIや写真／実削除操作へ範囲拡張が必要なら該当導線を保留し、既存撮影入口を無断置換しない。

- [ ] **T21 写真・整理・破棄への証拠・実解放・順序契約を完成する**
  - Status: pending
  - Owner: iOS後続契約worker。
  - Files: 連携Domain／Ports／原本単位ordering、TemporaryMedia受渡し、fake consumerを含む`FrameRelayTests/`。
  - Depends: T03、T09、T11、T15、T18。
  - Done when: 同一軽量映像の完全取得・内容・日時・使用権を写真consumerへ渡す。存在する同一原本、最後の保存検証、同一映像の有効確認・未失効から整理条件を導く。停止要求／実停止／全read lease実解放／Mac結果不明を分離し、失効と削除確定区間の両順序・復旧待機を契約化する。
  - Verify: V15。AC-BI-27〜30。オフライン・写真未保存でも条件成立、不存在／別内容／不明／失効は不成立。失効先行は整理不可、削除区間先行は結果照合まで失効ACK待機。媒体解放後も証拠保持。
  - Stop: fakeを実Photos／実削除の達成証拠にしない。原本自動削除、Mac／写真連動削除、整理不可から破棄への自動移行は追加しない。

- [ ] **T22 障害・再起動・競合を横断して照合する**
  - Status: pending
  - Owner: 結合試験worker、mainが修正を所有者へ順次割当。
  - Files: T06A／T07AとT07〜T21対応の統合test／許可された障害注入点、本steering証跡。修正範囲は原因ごとに確定。
  - Depends: T10、T12、T17、T18、T19、T20、T21。
  - Done when: 初回登録・内容対応／lease・操作意図・保存証拠・確認／失効・ACK・公開・再登録・後続fake consumerの境界中断、古い応答、容量／保護障害、世代競合を再起動後の実記録で照合する。V1媒体配布受理とV2公開の両順序を全取得入口で再現し、不明の保持・本人意思・旧確認非復活・個別継続と共通待機を確認して未解決を記録する。
  - Verify: V01〜V04、V09、V11〜V16。AC-BI-04〜06、AC-BI-11〜13、AC-BI-18、AC-BI-20〜30、AC-BI-33。V1 manifestのみ→V2公開→V1 GET／Range／再開はbyte 0、V2自動差替え／redirect／混在／確認なし。V1受理commit先行なら進行中応答を含む必要ACK待ち、失効commit／公開後の旧応答・local再生で旧確認非復活。既受理端末の公開後再要求も拒否し、不通だけならvalid維持。初回登録応答欠落／通常再起動の重複なしと内容対応安定・実解放も実記録で確認し、後続実削除／実写真復旧は未確認として分ける。
  - Stop: 未解決の損失・重複登録・内容取り違え・誤verified／valid・早期ACK／公開・公開後に新たに到着した旧版GET／Range／再開へのbyte返却、再起動での本人意思消失があれば依存受入を停止し、単なるfinding記録で解決扱いしない。公開前の配布受理済み応答は必要ACK／旧確認非復活を別に検証する。

- [ ] **T23 実回線・背景／ロック・REC／保存優先を結合検証する**
  - Status: pending
  - Owner: mainと実機検証担当。本人操作が必要なケースは対象条件を共有して実施。
  - Files: 許可実機・隔離接続先の観測証跡、必要な診断点、tasklist。秘密・私的媒体をログへ残さない。
  - Depends: T12、T16、T19、T20、T22、G0の実機・実素材・通信範囲、G2A／G2B入力とG2Cの結合証拠。
  - Done when: 全媒体経路×LAN／外出先Wi-Fi＋Tailscale×前景／背景／再開、基礎回線切替、モバイル状態同期、録画／保存／異常処理・hash中の停止を実環境で観測する。強制終了復帰・複数待機・本人停止を含め、REC／次RECへの影響と映像音声の非干渉を実測する。
  - Verify: V05〜V09、V10の非干渉、V13。AC-BI-07〜10、AC-BI-14、AC-BI-18、AC-BI-24。通信byte・OS条件・端末／OS・停止と実解放・継続／中断範囲を記録し、T05の小規模結果だけでG6達成にしない。
  - Stop: cellular媒体漏出、REC／保存への未解決影響、背景方式不成立、必須実機未実施を残した場合はG6を未達／未評価とする。前景限定へ縮小しない。

- [ ] **T24 本人の受入導線と実機起動を確認する**
  - Status: pending
  - Owner: main、実機／UI検証担当。
  - Files: 必要なUI testと実行証跡、本steering結果欄。合意出力・実原本を使用。
  - Depends: T16、T20、T22、T23。
  - Done when: 複数開始→個別／全件停止→保存検証→同一軽量版途中再生→明示確認→失効→再登録を必要な画面操作で確認し、動画別表示とdisk証拠を対応付ける。実在project／scheme／destination／test構成を確認したbuild・診断・必要test、Simulator／本人実機起動を実行し、未実行は理由と範囲を残す。
  - Verify: V01、V02、V09〜V14。AC-BI-01、AC-BI-02、AC-BI-15、AC-BI-19、AC-BI-25、AC-BI-32、AC-BI-33。品質はG3／G5の証拠を参照し、同じ条件を理由なく再試験しない。
  - Stop: 起動・必須導線・実機／品質証拠が不足すれば受入未完了。写真登録後の鑑賞や最終ライブラリ全体を今回の合格へ含めない。

- [ ] **T25 永続文書を同期し全34AC・全PRD79ACを個別追跡する**
  - Status: pending
  - Owner: mainが統合、永続6文書は所有を明示したdocument_author、docsレビューはdoc_reviewerがread-onlyで担当。
  - Files: `docs/product-requirements.md`、`functional-design.md`、`architecture.md`、`repository-structure.md`、`development-guidelines.md`、`glossary.md`の安定した変更、本steering要求／設計／tasklist。入力仕様・既存撮影steeringは変更しない。
  - Depends: T24。途中から証跡台帳の追記は可、完了判定は全結果と残件が揃ってから。
  - Done when: BI-01〜BI-14／AC-BI-01〜AC-BI-34の各条件に今回証拠・結果・部分達成・未実施／未達・後続担当を付ける。PRDの全21要求・79ACを**各IDにつき1行**へ展開し、既存撮影証跡と照合して条件別の残件を保つ。範囲行・総数だけで代用せず、全P0とR3を維持する。回答済みU1〜U3等と安定した構造／規則／用語を同期し、未選定値は採用済みにしない。
  - Verify: V16。AC-BI-31、AC-BI-34。現行PRDのID集合との全件一致・重複なし、requirementsの34行とtask／V／証跡の対応、docsのread-onlyレビューfinding、所有外diff不変を確認する。
  - Stop: AC欠落、集約による部分条件の消失、未実施を合格にする記載、入力仕様変更が必要な矛盾は完了を停止。仕様再確定は別の明示workflowへ戻す。

- [ ] **T26 完了を三分類で判定し次工程へ引き渡す**
  - Status: pending
  - Owner: main。
  - Files: 本steering3文書の最終状態・証跡・残課題。両repo最終diffは読取り確認。
  - Depends: T25と全必須task／G0〜G6の結果確認。
  - Done when: 実装完了・検証工程完了・対応PRD要求達成を別々に根拠付き判定し、未達／必須未実施がある範囲を閉じない。実装可能な必須ケースの未解決調査を残したまま検証工程完了としない。写真登録・実整理／破棄・削除復旧・写真最終鑑賞・撮影残件を後続へ引き渡し、所有外変更がないことを確認する。
  - Verify: V16、AC-BI-34。最終diff、task状態、34AC／79AC台帳、環境・コマンド・証跡・未確認範囲を照合。次の明示 `$validate-implementation .steering/20260928-backend-integration/` に渡せる入力を示す。
  - Stop: task状態と実diffの不一致、G5／G6不足、未解決必須findingがあれば該当判定を未完了にする。validation workflowを暗黙に開始せず、validation中に本書を改変しない。

## 検証証跡と判定台帳

### 初回計画作成時の確認（修正前の記録）

以下は初回作成時点の記録を保持する。26task／外部G2としての確認結果は当時の範囲であり、今回判明した配布競合・責務・依存の不足を解消した証拠にはしない。現計画は下記の修正後確認を参照する。

| 日付 | 検証 | 結果 | 備考 |
| --- | --- | --- | --- |
| 2026-09-28 | 入力の`Status: confirmed`、AGENTS／PROJECT_CONTEXT、prepare-steering／steeringとassetsの読取り | 確認済み | 本仕様・既存requirements／designと親agentのread-only調査結果を根拠にタスク化 |
| 2026-09-28 | 26taskの依存・所有・完了／停止条件、G0〜G6／V01〜V16・34AC・79AC追跡の整合 | 確認済み | Pythonによる文書静的確認で26task全pending・必須項目あり・依存先は先行IDのみ・ローカルリンク切れ0・34AC／21要求79ACを確認。D04依存は外部G2後のT07へ分離し、G2の循環なし |
| 2026-09-28 | 計画の差分・所有範囲 | 確認済み | 作業開始時124ファイルのSHA-256と保存後を照合し、tasklist追加のみ。既存requirements／designと所有外ファイルは不変。親agentがtasklistの全差分を確認 |
| 2026-09-28 | build・診断・unit／UI test・Simulator／実機起動 | 未実施 | 現工程は計画作成のみ。アプリ／backendの実装・成立性は未確認 |
| 2026-09-28 | サービス起動・外部接続・実媒体／DB・障害注入・品質比較 | 未実施 | G0隔離・操作範囲、G2撮影引渡し、G3品質案合意、実装工程が必要。今回の文書確認はG1〜G6通過証拠ではない |

### レビュー3件への計画修正と文書確認

| 日付 | 修正・確認 | 結果 | 根拠・限界 |
| --- | --- | --- | --- |
| 2026-09-28 | 公開後の遅延V1取得と配布／公開競合 | 計画修正済み | BI-08／BI-09、AC-BI-18／20／22に対応。全取得入口の現公開対象照合＋台帳commitとpointer更新、V1受理先行／V2公開先行、進行中応答／取得済みlocalをdesign V09／V12とT15／T17／T18／T22へ割当。媒体byte・実確認の挙動は未検証 |
| 2026-09-28 | 原本accessのproducerと外部引渡し | 計画修正済み | 撮影P09のDone／Verifyを読取り照合。G2A／G2Bは撮影保存成果、G2CはT11の追加実装・証拠と定義。共有storeの同一正本、内容世代と撮影設定／revisionの分離、再採番なし、V02／V07／V15をBI-01／BI-11・AC-BI-02／09／10／28へ対応。T09は契約fake、実原本はT11→T12 |
| 2026-09-28 | 初回登録の前提順序 | 計画修正済み | BI-03／BI-04／BI-10、AC-BI-05／25に対応。T06A→T08、T07A→T09／T12、T17／T19の基盤再利用を明示。接続先／登録世代の永続対応と応答欠落／通常再起動の重複抑止をV04／V13へ追加。具体API／認証方式はT06の未実施判断を維持 |
| 2026-09-28 | 3文書の構造・参照・依存の静的確認 | 確認済み（文書のみ） | Pythonで28task全pending・必須7項目・既知task参照・先行依存・G2A／G2B／G2Cのproducerを含む依存図の非循環を確認。ローカルリンク切れ0、AC-BI全34行、PRD21要求・79AC保持。`git diff --no-index --check`で3文書の空白エラー出力なし。早期通信、品質事前合意、旧登録無期限保留、写真／実削除後続の境界を読取り照合 |
| 2026-09-28 | 開始時baselineとの内容照合 | 確認済み（main最終確認へ引渡し） | `/private/tmp/fr-backend-steering-fix-r6c5i11_/manifest.json`の125ファイルSHA-256と比較し、変更は本steering3文書のみ、所有外変更0、新規ファイル0。既存のmemo等の差分を保持 |
| 2026-09-28 | build／アプリ・backend試験／外部通信／起動／実データ／品質 | 未実施 | 今回は既存計画の修正と文書静的確認のみ。28task・全ACは未着手／未評価、G1〜G6・実機／品質の通過証拠にはしない |

### 実装時に追記する証跡の形式

| 証跡ID | 日時・担当・task／V／AC | 環境と対象 | 操作・観測 | 結果と限界 | 保存先 |
| --- | --- | --- | --- | --- | --- |
| E-BI-01 | 2026-09-28、main／backend_inventory／capture_contracts、T01／V16 | FrameRelay `b2895ed`、MediaVault `c56d4a2` | Git・AGENTS・設定・関連ソースのread-only照合と125ファイルbaseline保存 | 既存変更を保持。撮影G2A／G2B未成立、旧データと稼働環境は操作対象外。実データの内容検査は未実施 | `/private/tmp/fr-backend-20260928-hqkp_gij/baseline.json`、`initial-status.txt`、`initial.diff`、agent報告 |
| E-BI-02 | 2026-09-28、main、T02／V01・02・04・11〜13・15 | 確定仕様・既存撮影型／Port | design「T02 契約具体化」とJ01〜J06を追加し、入力要求・残判断と照合 | 方式非依存契約を具体化。物理I/O／wire／DB／運用値／品質は未選定 | 本design、開始時designとの差分 |
| E-BI-03 | 2026-09-28、main、T03構成確認 | Xcode 27.0 (27A266a)、Swift compiler 6.4、iPhoneSimulator SDK 27.0 | `xcode-select -p`、`xcodebuild -version`、`xcrun swift --version`、`xcodebuild -list -project FrameRelay.xcodeproj -disableAutomaticPackageResolution`、同project／schemeの`-showdestinations`／`-showTestPlans`／`test -showBuildSettings -json` | scheme／test plan FrameRelay、Debug、Test actionのFrameRelayTests／FrameRelayUITests／Appを確認。iOS27.0・Swift言語5.0・MainActor既定等を保持。実行先は列挙済みbooted Simulator `DFE46693-E8DD-4814-8957-4F327699F719`。sandbox内CoreSimulator接続拒否は承認されたsandbox外の再照会で解消。build／test結果ではない | 同証跡rootの`destinations.txt`（制約発生）、`destinations-verified.txt`、`test-plans.txt`、`test-settings.json`／`.stderr` |
| E-BI-04 | 2026-09-29、main、T03 build／診断 | E-BI-03のproject／scheme／Debug／Simulator | 下記共通引数＋`-resultBundlePath <証跡root>/T03-build-01.xcresult -quiet build` | 終了0、Swiftコンパイル／リンク成功。従前のSupported platforms一覧診断あり。後続のstore読戻し契約補強はE-BI-05最終testの再コンパイル／リンクで確認 | `T03-build-01.xcresult` |
| E-BI-05 | 2026-09-29、main／T03両worker、V01・02・04・11〜13・15 | E-BI-03、FrameRelayTests全体 | 下記共通引数＋`-resultBundlePath <証跡root>/T03-tests-01.xcresult -only-testing:FrameRelayTests -parallel-testing-enabled NO -quiet test`。macro内allSatisfyのkey pathをclosureに修正し、登録／証拠読戻し補強後に同引数で`T03-tests-02.xcresult`へ再実行 | 初回はtest compile失敗・試験未実行。最終は終了0、89 test／100実行成功、失敗0・skip0。新規35 test、既存空雛形1を除く有意味99実行。parameterizedは11 test／22実行。UI test・実機・物理store永続性・通信は対象外／後続未実施 | `T03-tests-01.xcresult`、`T03-tests-02.xcresult`、`T03-test-summary.json` |
| E-BI-06 | 2026-09-29、main、T03起動・保全 | 最終testがbuild／installした同Simulator、bundle `com.oyabu.FrameRelay` | `xcrun simctl launch DFE46693-E8DD-4814-8957-4F327699F719 com.oyabu.FrameRelay`、baseline SHA-256比較、新規22ファイルの`git diff --no-index --check`とmain差分確認 | 起動終了0・PID5198。既存125ファイルの変更は本steering3文書のみ、App15＋test/fake7を追加。空白警告0、所有外既存ファイル不変。起動成功を実機撮影／連携UIの受入にしない | セッション出力、`T03-source-audit.json` |
| E-BI-07 | 2026-09-29、backend_isolation／main、T04／V16・AC-BI-31の隔離部分 | MediaVault固定HEAD snapshot249ファイル、既存Python3.12.13、T04内のDB／合成媒体、in-process APIと単発worker | 下記T04 command。全22設定・実パス照合後、合成旧DBのmigration／backfill／回収と保全比較、既存8ファイルのpytest | 起動smoke成功、保全5ファイルと旧記録不変。pytestは初回guardのlog先拒否で収集前exit3、専用log先への修正後58成功・失敗／error／skip0。外部repo状態／未追跡metadataとsnapshot不変。全旧データの安全性、実環境の移行、実ネットワークは未検証 | `T04/README.md`、`final-result.json`、`run-001/preservation-result.json`、before／after論理DB・hash、`run-002/pytest-junit.xml`、各runのpreflight・settings・guard report |
| E-BI-08 | 2026-09-29、backend_isolation／main、T05／V09の既存固定配信・Range負荷部分 | T04のread-only snapshot、T05使い捨てDB・全22設定・合成2 MiB＋17 byte、TestClient、ネットワーク／listenerなし | 下記T05 command。HTTP計7要求（認証付き6・tokenなし1）、別に受理済みservice応答とiterator早期closeの2観測。通常計時とwriter競合診断を分離 | 全観測成功。正常1 KiB配信に全hash2回／計4,194,338 byte、うち1回は書込みtransaction内。通常sampleのrequest 4.465 ms、transaction 0.843 ms、hash 0.846／0.712 ms。診断時writer競合、応答後取得可。旧版3要求は409／媒体0。外部baselineとsnapshot不変。単一sample・warm cache・wrapper込みの参考値で製品性能／実再生／G1成立を表さない | `T05/run-001/probe-result.json`、`summary.json`、`probe.log`、前後論理DB／媒体hash、preflight／settings／guard report、`T05/README.md` |
| E-BI-09 | 2026-09-29、main、今回の最終差分・状態照合 | 開始時125ファイルbaselineとT03最終test済みsource hash、対象steering3文書 | 全既存ファイル／新規一覧／hashと最終diffを確認し、task状態・checkbox・34AC行・ローカルリンク・空白を静的照合 | 既存変更は本steering3文書だけ、新規App15＋test7、test済みsourceは不変。所有外変更なし。done4／blocked1／pending23、リンク切れ・空白警告0。requirementsは工程説明以外不変でPRD79AC追跡を保持。T26の全体完了やvalidation完了とは判定しない | `final-source-audit.json`、`final-steering.diff`、E-BI-06〜08の差分・保全証跡 |

T03証跡root: `/private/tmp/fr-backend-20260928-hqkp_gij`。build／testの共通引数は以下（実際に実行した構成）。

```sh
xcodebuild -project FrameRelay.xcodeproj -scheme FrameRelay -configuration Debug -destination 'platform=iOS Simulator,id=DFE46693-E8DD-4814-8957-4F327699F719' -derivedDataPath /private/tmp/fr-backend-20260928-hqkp_gij/DerivedData -disableAutomaticPackageResolution
```

結果件数は `xcrun xcresulttool get test-results summary --path /private/tmp/fr-backend-20260928-hqkp_gij/T03-tests-02.xcresult --format json` で確認。単体testのhost App起動と明示launchを実施し、変更のない画面操作／実機カメラは今回の契約taskでは検証していない。

T04も同証跡root配下。snapshot作成後、以下を順に実行した。再実行は`launch.py`が新しい`run-NNN`を作り、既存証跡を保持する。初回起動成功後は、log先を修正したpytestだけを再実行した。APIはlistenerなし、tokenは実行ごと生成・非保存、cleanupは未実行。既存Python／venvはread-only例外として利用した。

```sh
/Users/oyabu/dev/rep/latest_template/backend/.venv/bin/python -B /private/tmp/fr-backend-20260928-hqkp_gij/T04/bootstrap.py
/Users/oyabu/dev/rep/latest_template/backend/.venv/bin/python -B /private/tmp/fr-backend-20260928-hqkp_gij/T04/launch.py
/Users/oyabu/dev/rep/latest_template/backend/.venv/bin/python -B /private/tmp/fr-backend-20260928-hqkp_gij/T04/launch.py --pytest-only
```

T05は次のcommandを1回実行した。`T05/launch.py`も再実行時に新runを作る。Range等の数値は観測用fixtureの値であり、製品の出力／buffer／一時量上限には採用していない。DB context終了・transaction解消と、媒体file descriptorのcloseは別々に観測し、全DB connectionのcloseを検証したとはしない。

```sh
/Users/oyabu/dev/rep/latest_template/backend/.venv/bin/python -B /private/tmp/fr-backend-20260928-hqkp_gij/T05/launch.py
```

- build／testは実行コマンド、project／workspace、scheme、destination、OS／SDK／compiler、test target、結果と証跡パスを記録する。未実行は理由・未確認範囲を記載し、未合意の固定coverageを導入しない。
- fixture／fake、disk store、隔離backend、実原本／実保存先、実回線／実機、本人品質のどの層かを明示する。実機条件・通信量・対象版・停止／解放・品質合意と候補の対応を失わない。
- T25の個別AC台帳は `AC ID / 条件 / 関連BI・task・V / 証跡ID / 判定 / 部分達成 / 未実施理由・残条件 / 後続担当` を持つ。既存撮影steeringの証拠は参照し、本steeringの達成に無条件転記しない。
- 成功したチェックは新変更・失敗・未解決懸念がなければ理由なく反復しない。失敗修正後は影響範囲に必要な確認を再実行する。

## 振り返り・残課題

- 計画作成日: 2026-09-28。実装完了日: 未完了。
- 計画との差分: 2026-09-28のレビュー3件を受け、公開後の旧版取得拒否、G2A／G2BとT11製G2Cの責務分離、T06A／T07Aの初回登録基盤を3文書へ同期。その後の明示実装依頼によりT01〜T04を完了し、T05の独立Range測定まで実施。全28task中done 4、blocked 1、pending 23。製品の通信方式・API・DB・品質・運用値は未選定のまま。
- 今回の発見: 既存Range配信は小さい要求でも全内容hashを2回行い、うち1回はwriterを排他するtransaction内。T06で大きい媒体・並行取得・公開確定区間への影響を検討する。今回の小fixtureの時間だけで負荷許容や不成立を判定せず、内容検査を省略する最適化を採用しない。
- 未成立の前提: 外部撮影D01／D04／P09のG2A／G2B引渡し、T11で新規実装するG2C、D02のLog／変換資材、実機／実回線の具体条件と早期通信方式G1、具体品質案G3、出力採用G5、実結合G6。T04で確認したin-process隔離範囲を他の接続・実データ操作へ拡張しない。
- 後続必須: 実写真登録と不明結果復旧、写真での最終鑑賞、実整理／破棄・削除競合／再起動復旧、撮影基盤の残受入。今回の契約試験で完了にしない。
- 次の実行境界: T05のG1必須観測を揃えてT06の方式判断へ進む。撮影G2待ちでも、T06／T06A成立後のT08／T10など独立backend作業は実行可能。全体未完了のため、`$validate-implementation`はまだ案内・開始しない。
