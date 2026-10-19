# Tasklist — 実機なし先行実装の4段階

## 状態と実行規則

2026-10-01、明示 `$prepare-steering` で計画作成後、明示 `$implement-steering` で実装を開始した。各taskの状態・証拠は以下を正本とする。`pending → in-progress → done / blocked / cancelled` を使い、書込みは原則1件ずつ進める。状態・所有・実行版・証拠・残件はこのファイルへ都度同期し、設計変更時だけrequirements／designも更新する。

今回の明示入力は `$implement-steering .steering/20260929-device-independent-implementation/`。N00で担当と現行正本を確定済み。旧撮影／backend tasklistは過去実績と元の受入義務の参照元とし、今回へ引き渡した作業を旧台帳でも並行実行しない。旧文書未更新期間も新confirmed仕様の限定差分と本計画の開始条件を適用する。旧Ideas／旧steeringの実更新はM07〜M10の別明示Workflowに残し、その待ちを独立コードの一括停止条件にしない。

全タスクは [requirements](requirements.md) と [design](design.md) の安全・所有・検証規則を継承する。役割名は予定担当であり、N00で具体agentを束縛する。同じファイルを同時所有せず、他者の差分を戻さない。実機・G1・G2B・段階全体の未完了を、記載されていない依存として追加しない。各タスクの必要試験が失敗／未実行なら当該taskをdoneにせず、理由・不足事実・影響・独立して進めるtask・再開条件を記録する。

Start／Finishを分けたタスクは、N01等のStartが満たされれば独立部からin-progressにできる。substatus（規則／SDK候補／UI／実接続／検証）の各状態・所有・証拠を記録し、Finishが不足すればtask全体のdoneは保留する。別独立タスクへ移る時は残件と再開条件を明記する。

全本体タスクの共通Verifyは、対象diff・意味ある関連単体試験・必要build／診断・実I/O／UI確認・mainレビュー（V-REVIEW）である。下記Verifyは追加する具体試験。共通Stopは、所有衝突、無断要求変更、禁止動作、実データ範囲不明、必要検証失敗。外部依存・ツール追加、重大未合意方式、実データ消失操作が必要になれば該当箇所だけ保留する。軽微可逆判断は記録して進め、段階ごとの再承認を要求しない。

## 現在の再開点（2026-10-09）

- S22Cは完了。Keychainと共通store UUIDの束縛、同store中断/新store/移動/置換の区別、実HTTP6件、全Unit258件＋既存製品root VERIFY、UI2件、main差分確認を完了した。全4段階/PRD/実機受入の完了ではない。
- 最新App/Tests/project126fileは `evidence/20261009-s22c-complete/S22C-test-07-sources.json` に対応。再開時baselineと最終差分・所有照合、compile失敗/test0件の旧runも同archiveへ保持。実行ログ/xcresultは `/private/tmp/fr-di-20261009-resume/`、HTTPは旧rootのS22C/server/runtime-listener-002。両listener/全Xcode process終了・秘密env削除を確認済み。
- 次はS16/S14の再生・アクセシビリティ残件を直列に再開し、S23以降と独立する本体/文書作業を継続する。S16の既存診断（2026-10-05/07）と当日のread-only再確認を引継ぎ、必要な再現だけ取り直す。S23の未成立な背景Wi-Fi/VPN制約を実機待ちだけへ言い換えない。M07〜M10/独立validationは引き続き別明示Workflow。

## 停止時の再開メモ（履歴: 2026-10-08、本人指示で停止）

- 再開（2026-10-09）: 同じpathへの明示implementを受領。`/private/tmp/fr-di-20261009-resume/` に現存355ファイルのhashと開始時copy/diff/statusを保全し、停止時UI01 source121件は全一致。前回listener/Xcode試験process残存なしを権限付きで確認。以下の停止記録は履歴として保持し、S22Cの資格情報/store対応修正から再開する。
- ユーザーが一旦停止を指示。mainと全subagentの実装を停止し、既存差分・未追跡成果を保持。再開には同じ作業フォルダで `$implement-steering .steering/20260929-device-independent-implementation/` を明示する。AGENTS.md、PROJECT_CONTEXT.md、要求/設計/本tasklistと参照確定仕様を読み、N00の保全・現行正本・所有を継承する。
- 直近はS22C。登録基盤の関連Unitは39宣言/51実行成功（新規22宣言/25実行を含む）、製品接続UIは2件成功、失敗/skip/compiler/analyzer warning/errorは各0。S22Cは完了していない。先に下記のKeychain残存と新storeの取り違えを修正・検証し、その後、実登録HTTPの6probe・全Unit/既存製品root VERIFY・最終差分確認へ進む。通常UI成功をHTTPS接続成功としない。
- 未修正指摘: Keychainだけ残る再インストールと、同じstoreで意図commit前に中断したケースを現実装が区別できず、本人継続で旧登録を再利用し得る。資格情報と永続store instanceの対応を確立する必要がある。worker提案のroot path＋stat(device/inode/birthtime) digest束縛は未採用。通常のアプリ更新/container移動とstore置換を区別できるかも検討し、共有storeへの変更が必要なら単独所有を明示して引き渡す。Keychainへ論理操作台帳を複製しない。
- 直前のS22C実通信supervisor権限要求は中断され、実行許可/成功として扱わない。停止時にruntime-listener-001、integration-execution-001、ready/resultが全て未作成であることと、対象server/Xcodeプロセスが残っていないことを確認。全subagentもcompleted、source121件はUI01凍結版と一致。再開時も実在・hash・実行プロセスを確認してから起動し、古い許可や準備copyを新runの成功証拠にしない。
- 証拠rootは `/private/tmp/fr-di-20261001-5ljls2fr/`。重要証拠は本steering `evidence/20261006-checkpoint/`、`evidence/20261007-s22c-checkpoint/`、`evidence/20261008-pause/` に追加保全。N00に記録した初期baseline消失の制限、旧失敗・部分成功を保持する。外部 `/Users/oyabu/dev/rep/latest_template` は引き続きread-only、未deploy。S22実装はsupport/server-implementationのoverlayと隔離snapshotにある。
- 再開後も4段階全体が対象。S16/S14の再生・アクセシビリティ失敗、S13/S23の全owner/背景通信、S24以降、S31/S34の部分引渡し、S41以降、M02〜M06、実機票の残件を継続する。実機・変換資材・前段全体待ちは直接依存へ限定。M07〜M10と独立実装検証は別の明示Workflowまで開始しない。

## 4軸と証拠プロフィール

79AC台帳の I／A／D／R は順に実装、自動検証、実機確認、PRD受入。各行の担当／直接依存／実機票と同じ対象・版を参照する。初期値は `I0=未実装`、`I1=探索候補または契約のみ（製品未接続）`、`A0=新計画未実行`、`A1=旧部分証拠あり・新計画未実行`、`D0=未実施`、`R0=未評価`。旧部分証拠からPRD達成へ自動昇格しない。実装後は I を「本体実装済み・未接続」「必要接続を含む実装済み」等へ具体化し、暫定値・未接続を別記する。Aはbuild・単体・UI・結合の結果／件数／版／証拠、Dは組合せ・適合／不適合／判定不能、RはAC全文の部分証拠／未達／達成を個別に更新する。

| 証拠profile | 旧成果と限定された証拠 | 再利用できない判定 |
| --- | --- | --- |
| E0 | 既存の該当実装・実行証拠なし。旧計画に要求は保持 | 計画の記述を実装と数えない |
| EC | P05／P06、旧 `E-P05-01〜04`、`E-P06-01〜11`。規則・二記録候補・保存候補・診断・探索UI。最終有意味unit／integration64＋UI1 | 実機起動・記録・方式選定・標準変換・製品接続の証拠ではない。途中compile失敗を保持 |
| ES | ECのうちdisk保存・再open・schema／破損／競合、合成Movie検査・保存分類だけ | 実Log・全編再生・完全性・実端末耐久性・G2Bはunknown／未実施 |
| EB | T03、旧 `E-BI-04〜06`。App15＋test/fake7、新規35試験、既存込み有意味99実行、build／Simulator起動 | 値／Port／fakeの契約証拠。disk連携store、実通信・再生・Photos・削除は未接続 |
| EI | T04、旧 `E-BI-07`。c56d4a2の249file snapshot、全22設定、in-process API／単発worker、58pytest | 外部listener・別環境・実接続・実DB移行・実データ操作への許可／証明ではない |
| ER | T05、旧 `E-BI-08`。2,097,169 byteの合成媒体→Range1,024 byte、全hash2回／計4,194,338 byte・1回writer transaction、SQLITE_BUSY。V2後V1新要求409・媒体0、受理済descriptorのV1継続・解放 | 実動画・実再生・実network・背景・全媒体停止・失効ACK・品質の証拠ではない。単一観測から性能合格にしない |

旧証跡は [撮影tasklist](../20260926-capture-foundation-feasibility/tasklist.md) と [backend tasklist](../20260928-backend-integration/tasklist.md) を正本参照する。N00で `/private/tmp` の旧証拠現存／版一致を確認済み。今後消失・差分があれば影響を受ける必要範囲だけ取り直す。古い成功・compile失敗・guard拒否・未実施を削除しない。

## Tasks

### N00 実行範囲・現行正本・所有を確定

- [x] Status: done
  - Depends: 明示implement。
  - 実行記録（2026-10-01）: mainが所有。開始baselineは `/private/tmp/fr-di-20261001-5ljls2fr/baseline/`、全151ファイルのhashは同runの `baseline-manifest.json`（実件数はmanifest参照）。README・memo・旧steering・確定Ideasを保護し、T03未追跡成果は同じファイルへ加算変更する。進捗の現行正本は本tasklist、旧49件は下表の引渡し対応と過去証拠を保持。
  - Owner / Files: main／本steeringの `requirements.md`・`design.md`・`tasklist.md`。
  - Done when: 新仕様の差分優先、新tasklistの現行正本、旧49件の引渡しと具体agent・ファイル所有、既存許可／不足、baselineと証拠現存・版を記録。
  - Verify: git status／対象diff／旧証拠対応、README・memo・未追跡T03成果保護。
  - 証拠 N00-01: HEAD `b2895ed3d1f2442c8ceea3743735feedd0557731`。explorer `baseline_audit` による旧P06 47件・T03 22件・T04 249件のhash照合は全一致。旧証拠rootは `/private/tmp/fr-capture-20260927-bw28qd0l/`、`/private/tmp/fr-offline-20260927-tmi2p8vs/`、`/private/tmp/fr-backend-20260928-hqkp_gij/` に現存。compile失敗、Simulator起動失敗、T04 guard拒否、T05 SQLITE_BUSY・Range部分観測を含む旧ログを保全。
  - 証拠現存の後続観測（2026-10-05）: 旧backend rootを再確認すると `final-source-audit.json`、`T03-test-summary.json`、T04 run-002のpreflight/effective-settingsの4ファイルだけが現存し、249file snapshot・runner・T04/T05詳細log等は取得不能だった。N00時点の上記照合履歴は保持し、旧preflightを現在の隔離成功証拠に再利用しない。外部元repoのHEADは同じc56d4a2、追跡変更なし・既存未追跡JPEG保持。S20で新しいsnapshot/guard/必要な観測だけ再作成し、消失した旧証拠を上書き再現しない。
  - 証拠保全の後続観測（2026-10-06）: 初期baseline-manifest.jsonとbaseline内の151copy、S11-test-02-sources.jsonは現在取得不能。原因未特定、過去の比較結果を撤回/改変せず現存証拠と分離する。S21の13保護ファイル一致記録・全Unit結果、S16失敗summary/実行版、S20/S22新証拠は現存。mainが本steering `evidence/20261006-checkpoint/` に重要な結果/失敗/実行版96件・758130 bytesをcopy保全しarchive-manifestへ各hash/元path/取得不能を記録、元ファイルは保持。新しい保護文書hashはS22-main-scope-reviewへ記録するが失われた初期baselineを再現したとはしない。以後mainはevidenceの追加保全も単独所有する。
  - 所有確定: main＝本steering・判断・差分統合。`core_impl`＝O-STORE/O-ORIGINAL/O-PORT（各taskで対象ファイルを直列に取得・引渡し）。`library_impl`＝O-LIBRARY（S14から、対応testを含む）およびO-COMPOSE（S16から、製品入口・project・UI/test seedを含む）。`docs_sync`＝O-DOC（各M taskの1文書だけ、M01から）。O-IOS-BI/O-PHOTOS/O-CAPTURE/O-SERVERは着手前に具体agentを本欄へ追加し、未割当時は書込不可。調査は `baseline_audit`、`capture_map`、`ui_probe`、read-only。
  - 現行引渡し（2026-10-06）: daemon再起動で旧agent実行は終了し、成果をmainが保全/受領。S22のO-SERVERは `registration_server`（worker）へ、本task内の限定overlay/runner/evidenceだけを割当。`network_map`（explorer）はS23のread-only調査。App/共有store/Port/CompositionとS20 checkpoint04は凍結し、同じ所有対象を旧agentと重複して動かさない。
  - S22C所有引渡し（2026-10-06）: `registration_client`（worker）へ新規登録用Port、Credentials/Remoteの登録用adapter、Application/MediaOperationsの登録coordinator、Features/Connectionと専用testを割当。共有store/既存Domainは凍結して再利用、Composition/ContentView/必要なLibrary導線は当該agentへの後段単独引渡しまで凍結。`registration_server`は同taskのserver-isolation新登録listener/helper/設定とS22C隔離証拠準備だけを所有し、App側とは分離。
  - S22C後段引渡し（2026-10-07）: mainが新登録Port/vault/coordinatorを確認し、S20凍結App/Unit/UI/project109件の不変を照合。接続前6ファイルを `S22C-main-pre-composition/` にcopy/hash保存してから、同じregistration_clientへProductComposition.swift・ContentView.swift・LibraryView.swiftと新ConnectionFlowTests/登録専用Composition試験だけを単独引渡し。ProductLibraryFactory・共有store・既存LibraryFlowTests・project設定は凍結継続。
  - S22C用途文の限定追加引渡し（2026-10-07）: LANのMac miniへのTCP接続に用途文が必要なことを[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)で確認し、同じO-COMPOSEへApp Debug/ReleaseのNSLocalNetworkUsageDescriptionの2行だけを追加許可。OS/Swift/Team/ATS/Bonjour/entitlement等の設定は凍結継続。生成plist確認はmain、実端末の許可/拒否はDV-12に残す。
  - 許可: FrameRelay実装、新規合成fixture、使い捨てdisk、Simulator、repo外証拠は先行可。外部checkout書込・listenerは未許可、S20で具体差分と隔離snapshotを準備する。実データ操作・署名変更・品質採用は局所保留。旧49件とM07〜M10は変更せず、独立validationも未開始。
  - 許可の後続記録（2026-10-06）: S20 checkpoint04の確認済みcommand/configに限定した127.0.0.1:0 listener最大1200秒と、秘密envを渡すSimulator wrapperの実行権限を取得し実行/停止済み。外部checkout書込・実データ・デプロイ・実回線/実機接続への許可には拡張しない。
  - Stop: 旧計画と同じ責務の二重実行、重複差分の保護方針不明。

### N01 開発構成・証拠先を確認

- [x] Status: done
  - Depends: N00。
  - Owner / Files: main／本 `tasklist.md` と許可したrepo外証拠先。projectは読取。
  - Done when: 実在project・scheme・Build/Test action・configuration・targets・利用可能destinationとXcode／SDK／Swiftを記録。証拠runIDを固定。
  - Verify: 既存Xcode手順の-list／-showdestinations／-showTestPlans／設定照会。旧UUIDを再使用前提にしない。
  - Stop: 不足構成の当該検証だけ保留。実機未接続だけでhost／Simulatorを止めない。
  - 証拠 N01-01: Xcode 27.0 (27A266a)、Swift compiler 6.4、iOS Simulator SDK 27.0／runtime 24A434。入口 `FrameRelay.xcodeproj`、scheme／test plan `FrameRelay`、Debug、AppとUnit/UI両targetがTest action設定に存在。最低iOS 27.0／Swift mode 5.0維持、App既定隔離MainActor。
  - 実行先: 当日の `simctl list` と再度の `-showdestinations` で確認したiOS 27.0・boot済み `DFE46693-E8DD-4814-8957-4F327699F719`。最初のsandbox照会はCoreSimulator接続拒否、権限取得後の初回一覧はgenericのみ、runtime列挙後の再照会で具体destination確認。旧IDの推測採用ではない。
  - 再開確認 N01-02（2026-10-04）: `xcode-select -p`／`xcodebuild -version` は同じXcode 27.0 (27A266a)。`simctl list devices available` と当日 `-showdestinations` の両方で同じ具体destination・arm64／iOS 27.0を再確認。Shutdownだった当該Simulatorだけを `simctl boot` で起動し、S14の新規試験へ引渡した。既存合格証拠は保持し、変更範囲の必要試験から再開する。
  - 再開確認 N01-03（2026-10-09）: 同じXcode 27.0 (27A266a)／Swift compiler 6.4、project/scheme/test plan FrameRelay、App/Unit/UIのTest action、Debug／Swift mode 5.0／最低iOS27.0を再確認。simctlのsandbox接続拒否後、権限付きdevicesとshowdestinationsでboot済み `DFE46693-E8DD-4814-8957-4F327699F719`（arm64／iOS27.0）を確認。実行証拠は `/private/tmp/fr-di-20261009-resume/` のxcode-list/test-plans/destinations/build-settings/confirmed-build-settingsとdevices-verified。失敗したsandbox照会も保持、構成照会をtest成功とは扱わない。
  - 反復検証の実行条件: S14で失敗後のverbose Simulator診断回収が600秒timeoutした。現 `xcodebuild -help` で確認した `-collect-test-diagnostics never` をS15以降の通常反復へ適用し、OS原因調査を要する個別runだけ有効へ戻す。失敗記録・通常stdout・xcresult・build診断は保持する。`-parallel-testing-enabled NO` はS14-test-04で実行成功を確認し、同一端末containerを使う後続UI引渡しにも使用する。scheme/project設定は変更しない。
  - コマンド: `xcode-select -p`、`xcodebuild -version`、`xcrun swift --version`、`xcodebuild -list -project FrameRelay.xcodeproj -disableAutomaticPackageResolution`、同project/schemeの `-showTestPlans`／`-showdestinations`、`-configuration Debug -destination platform=iOS\ Simulator,id=DFE46693-E8DD-4814-8957-4F327699F719 test -showBuildSettings -json -disableAutomaticPackageResolution`。構成照会でありtest未実行。証拠root `/private/tmp/fr-di-20261001-5ljls2fr/`、DerivedData・xcresultは同root下へ。

### S11 D04共通storeをdiskで具体化

- [x] Status: done
  - Depends: N01。
  - 実行担当: `core_impl`（O-STORE）、開始2026-10-01。schema 1の非破壊読取互換と同一writerを継承する。
  - Owner / Files: O-STORE／`FrameRelay/Platform/LocalStore/`、`FrameRelay/Domain/Media/RecordingEvidence.swift` の永続表現、`FrameRelayTests/Integration/Storage/`・`FrameRelayTests/Platform/Storage/` の対応test。
  - Done when: 既存候補を比較し単一writerの方式・schema拡張を決定。意図／結果commit、読戻し、破損拒否、再openの非実機G2A証拠を確定。
  - Verify: V-STORE。保存中断、未知schema、旧schema読み取り、revision競合、transaction失敗。
  - Stop: 証拠を消すmigration、別連携DB、端末保護未観測を保証する場合。
  - E-S11-01 / V-REVIEW: mainが3ファイルのdiffと実disk試験を確認。既存SQLite候補を共通writerに採用（既存transaction・排他・再openを再利用、性能優位の主張なし）。schema 1はread時不変、次の成功commitだけschema 2へ移行。transaction revisionは設定／内容世代から分離。実装2件＋新規test1件以外のコード変更なし、`git diff --check`成功。
  - E-S11-02: N01構成、`S11-commands.txt` の対象3suite。test-01は25実行成功・Sendable警告1、値capture修正後test-02は13宣言／25実行、fail/skip/compile・analyzer warning/error各0。証拠root下 `S11-test-{01,02}.xcresult`／各sources・summary・build JSONを保持。schema／破損／revision競合、両候補commit前rollback・commit後応答欠落、instance破棄後再openを検証。I=共通writer実装済み・後続製品接続待ち、A=上記実disk部分証拠、D0/R=AC全文未評価。端末保護・OS終了・電源断はDV-02へ引渡し。

### S12 原本保存・分類・再起動照合を接続

- [x] Status: done
  - Depends: S11。
  - 実行担当: `core_impl`（O-ORIGINAL）。共有読取snapshotが必要なため、O-PORTとして `CapturePorts.swift` の追加契約→O-STOREとして同writerの読取実装→原本consumerの順で単独所有する。関連fakeの適合更新は既存契約を保持する加算変更に限る。
  - Owner / Files: O-ORIGINAL／`FrameRelay/Platform/OriginalStore/`、`FrameRelay/Application/Capture/RecordingSaveLifecycle.swift`、新規 `FrameRelay/Application/Recovery/OriginalRecovery.swift` と対応test。
  - Done when: 実ファイルの意図→確定→検査→結果保存、起動時照合で正常／部分／不明／失敗を保持。G2Bは実機未成立と記録。
  - Verify: V-ORIGINAL／V-STORE、実合成Movieの中断位置別再openと管理対応。
  - Stop: 存在だけでsaved、未取得Log／完全性を成功注入、未実行操作の自動実行。
  - E-S12-01（2026-10-02）: 共有Port→同writerの全record読取→原本予約・存在観測→保存coordinator→read-only起動照合を直列接続。record/token/revision/結果receipt根拠を保持し、歴史的保存分類と現在存在・アクセス不能を分離。Domain表現変更なし。I=保存・復旧本体接続済み、製品Composition／実Capture接続はS16/S41待ち。
  - E-S12-02: N01構成で `S12-commands.txt` の関連8suite、test-02は35宣言／54実行成功、fail/skip/compile・analyzer warning/error各0。test-01は53成功1失敗（新testの順序違反error期待値誤りを既存契約に修正）、証拠保持。root下 `S12-test-{01,02}.xcresult` とsources/summary/build JSON。実H264＋PCM Movieの意図後／bytes後／終端後／結果後、結果commit直前失敗／commit後応答欠落をinstance破棄→SQLite再openで照合。
  - 限界・引渡し: 実媒体のLog・完全性・再生はunknown。4分類保持は別の合成契約入力試験であり実媒体成功ではない。D0、R=保存・復旧部分証拠、G2B未成立。S13へ内容対応、S16へLibrary、S41へ実Captureを引渡し。S41製品経路では既存Native側のreserveを重ねず、予約済み `reservedURL` を消費する。V-REVIEW-S12: mainが7変更のdiff・実I/O・unknown保持を確認、所有外変更なし／diff-check成功。端末保護・実中断はDV-02。

### S13 内容identity・read lease・ordering・原本再生Port

- [ ] Status: blocked
  - Depends: S12（S11の単一writerを継承）。S21全体完了は不要。
  - 実行担当: `core_impl`、O-PORT→O-STORE→O-ORIGINALを直列単独所有。schema 2／S12全record snapshotを受領。内容対応commit・再open証拠を得てからconsumerへ引渡す。原本のローカル再生資格とsaved必須の転送資格を分け、fixture再生のために保存unknownを昇格しない。
  - 部分引渡し E-S13-STORE（2026-10-02）: O-PORTのbinding/journal契約→O-STOREの同writer schema 3、`S13-store-01`は17宣言／31実行成功、fail/skip/compile・analyzer warning/error各0。実H264＋PCM Movieの全sha256とunknown保存record/receiptの対応をcommit→instance破棄→再open。schema 1/2保持、偽receipt／異payload／再binding／revision競合／commit前後障害／decode拒否を検証。証拠rootの同名xcresult・sources/summary/build JSONを受領し、O-ORIGINAL consumerへ引渡し。lease/orderingとmain最終diff確認は進行中、S13全体doneではない。
  - V-REVIEW-S13途中指摘（2026-10-02）: lease永続化後、非同期open完了前のreleaseで空handleを解放済みにできる競合をmainが検出。opening状態の保留、遅延open＋取消/解放試験をO-ORIGINALへ差戻し。pread時の同サイズin-place変更検出も確認中。S21失効最終commit、S23のOS task照合は別substatusで未接続として保持し、S15等へ渡せる内容対応／再生leaseの部分引渡しを一括停止しない。
  - E-S13-LEASE / 部分引渡し（2026-10-02）: 内容対応・実FD・最大64KiB pread・SDK attachment・古い世代拒否・削除/失効予約の永続化を実装。上記open競合はopening状態＋実終端→実close→台帳releaseで修正し、同じhash区間のdev/ino/size/mtime/ctimeをpread前後でも照合。最終 `S13-lease-02` は43宣言／50実行成功、fail/skip/compile・analyzer warning/error各0。初回lease-01は確定41宣言／47実行成功（速報46件を訂正）、当該競合未カバーの旧成功として保持。
  - V-REVIEW-S13: mainが15変更ファイルと追加試験、source hash一致、既存T03へのCodable加算、所有・保全を確認。`S13-main-scope-review.json`、`S13-commands-and-handoff.txt`、各xcresult/sources/summary/buildを参照。差分空白エラー0、README/memo/入力仕様/旧steering不変。I=内容対応・reader・予約は本体接続済み、A=上記実disk/FD部分、D0、R=部分証拠。
  - 残件/再開条件（S13時点）: `finishInvalidation` はS21の同writer上のtombstone＋ACK outbox実commit照合までunknownで予約保持。cleanup予約はS21/S32の有効証拠再判定までnotExecuted。旧OS readerの復旧observerはS23の実SDK/OS task列挙・所有照合待ち。これらだけ局所保留し、全task doneにはしない。S15へ内容対応・lease・attachment＋bounded bytes契約を引渡し済み（実AVPlayerはS15で検証）。S14/S15/S16とS21の独立部を継続する。
  - S21部分接続更新（2026-10-05）: finishInvalidationをexact durable ACK照会へ接続し、配信後/reopenでも照合成功・偽ACK拒否を実disk確認。logical stateの媒体readerも全解放判定に含め、別instanceの古い解放観測だけでは許可しない。writer側cleanup証拠再判定も実装済み。S23実OS/SDK observer、S32最終cleanup consumerだけを局所残件として維持。
  - Owner / Files: O-PORT／`FrameRelay/Application/Ports/`、`FrameRelay/Domain/Media/{OriginalDescriptor,OriginalReadAccess}.swift`、`FrameRelay/Domain/Operations/OriginalOperationOrdering.swift` の共有契約、O-STORE／`FrameRelay/Platform/LocalStore/` の同じwriter・内容対応schema／command、O-ORIGINAL／`FrameRelay/Platform/OriginalStore/` のconsumerと各対応test（ファイル別直列）。
  - Done when: 安定内容世代・原本参照・全内容識別の対応を単一writerへcommitし、instance破棄→再openで同じ対応を照合。O-STOREが契約・schema版とV-STORE証拠をO-ORIGINALへ渡し、全reader停止／実解放、削除／失効順序、原本再生sourceの共有契約・実ファイル証拠と併せてS15等へ引き渡す。
  - Verify: V-STORE／V-ORIGINAL。内容対応commit前後中断・再open／revision競合／内容差替拒否、複数reader／取消後遅延完了／古いgeneration／書込み競合。S21が先行済みならそのschemaを継承し別正本を作らない。
  - Stop: 設定世代やstore更新で内容世代代用、cancel受付を実解放とみなす。

### S14 ライブラリ・詳細・履歴の状態と選択

- [ ] Status: blocked
  - Depends: S12。
  - 実行担当: `library_impl`（O-LIBRARY）、2026-10-02開始。S12の全record snapshot/OriginalRecovery、S13の内容対応・原本再生Port部分引渡しを使用。共有Port/store/Composition変更は各所有者へ依頼し、別正本を作らない。
  - 再開記録（2026-10-04）: 10月2日はagent使用量上限によりLibraryファイル作成前に中断。ユーザーの継続指示で同じ所有・証拠rootから再開。独立状態projection、同writerのrevision照合、固定対象command、未接続理由表示を実装中。製品入口と実UI操作はS16へ部分引渡しし、未検証のままdoneにしない。
  - 共有依頼 S14-STORE: 解決済み削除のpurposeを失わず投影するため、`core_impl` が `OriginalStorePort.swift`／`OriginalStoreDocument.swift`／`OriginalLeaseOrderingTests.swift` だけを単独所有し、解決済みintent読取とjournal replay・再open試験を追加する。新DB／新payloadは追加せず、既存journalから再構築する軽微可逆変更。Library consumerは引渡し後に使用し、統合testは `library_impl` が1回ずつ実行する。
  - 途中検証（2026-10-04）: mainが全動画を一括抑止する入力guardを指摘し、同対象・同副作用操作（整理と破棄は相互）だけの抑止へ修正。再生はセッション所有者へ引渡し、別動画は続行可能とした。`S14-test-01` は新規test stubが存在しないerror caseを使用したcompile error 1／warning 0／test 0件で停止。既存の `wrongStage` へtest側を修正し、失敗bundle/source hashを保持してtest-02を実行中。
  - 環境待機履歴: test-02はcompile通過後もrunner出力なし。SimulatorがShutdownへ戻ったためmainが権限付きで再bootし、`bootstatus -b` の起動完了を確認したが、当該runは8分46秒時点でもtest host起動を観測できず継続待機。確認済み当該xcodebuildだけをSIGINTで中断し、証拠を保持する。終了結果／実行件数を回収後、権限付きtest-03で再確認する。test-02をコード失敗または合格とは扱わない。
  - 診断訂正・差戻し: test-03の詳細logでXcodeが専用clone上にhostを起動し、元端末を複製のためShutdownへ遷移させたことを確認。上記「runner起動待機」は当時の推定であり原因確定ではない。test-03は29宣言・4suiteを実行し、原本予約を欠く新規fixtureがabsentを期待した失敗1件。実順序の予約→意図へ修正し、予約欠落はunavailableを保つ別caseを追加。同runには `withStorageRun` がCoreDataのFD存命中にfixtureをunlinkするSQLite診断もあり、O-STORE所有者へ `FrameRelayTests/Support/Storage/StorageFixture.swift` を追加割当して即時cleanupを撤去。UUID隔離fixtureを診断用に保持し、解放をsleepで仮定しない。test-03はSIGINTで中断し証拠保持、mainが修正後test-04を並列runner無効で実行して結果とruntime診断を再確認する。
  - E-S14-01 / 部分引渡し（2026-10-04）: Library本体5件＋test3件、共有intent投影2件＋test1件、fixture保持修正1件の計12件をmainが確認。store読取失敗を空一覧にせず、共通revision照合、保存4分類と現在存在の分離、成功整理の通常一覧維持・成功破棄だけ履歴、未接続理由と対象別入力抑止を実装。`S14-main-scope-review.json` でsource hash不一致0、projectはbaseline不変。I=本体実装・共通store接続済み、製品入口/操作下位処理は未接続。
  - E-S14-02: N01構成・関連4suite、`S14-test-04` は30宣言／44実行成功、fail/skip/compiler・analyzer warning/error各0。実SQLite＋Movie unknown/bindingの再open、予約欠落の不明保持、revision競合、別動画続行、固定集合を検証。SQLite vnode/invalidated fd診断は両0をexportしたstdoutで確認。AVFoundationのFig診断はstdoutに保持し、xcresult runtimeWarnings空だけで全実行時出力なしとは主張しない。A=上記部分証拠、D0、R=部分証拠。
  - 旧run確定: test-02/03のsummary回収結果は共に29宣言／43実行、42成功1失敗・skip0。同じ新fixture期待値失敗であり、未実行ではなかった。test-03は診断回収600秒timeout後exit75/TEST INTERRUPTED。test-01 compile失敗、02/03 bundle・source/summaryを保持。04は `-parallel-testing-enabled NO` で約25秒、exit0。全証拠はN01 rootの同名xcresult/sources/summary/build/diagnostics/commands。
  - 残件/再開条件: V-UIの製品入口からの一覧/詳細/履歴操作、文字サイズ/読み上げ検査はS16接続後に実行する。S21/S28/S31〜34の操作別状態は未取得理由を表示し、現在のコマンド受付/合成結果試験を製品操作成功にしない。S15とS16へ本体を部分引渡しし、全task doneはV-UIまで保留する。
  - Owner / Files: O-LIBRARY／新規 `FrameRelay/Features/Library/`・`FrameRelay/Application/Library/` と対応 `FrameRelayTests/`・`FrameRelayUITests/`。
  - Done when: store由来の独立状態、複数3操作／単数3操作、原本なし・要照合・破棄成功履歴を投影。未接続操作は理由表示。
  - Verify: V-UI、再起動・複数一部失敗・二重入力・文字サイズ／読み上げ。
  - Stop: 画面値を正本化、一覧非表示だけで削除成功、未接続操作に成功表示。

### S15 原本のローカル実再生

- [x] Status: done
  - Depends: S13。
  - 実行担当: `library_impl`（O-LIBRARY）、2026-10-04開始。S13の内容対応/lease/attachment/bounded実FD部分とS14本体を受領。S13のS21/S23待ちだけを本再生の停止条件にしない。共有Port/store/原本/Compositionは変更せず所有者へ依頼する。
  - 途中検証: SDK objects/delegateをMainActorへ統一し、実bytesだけを原本actorへ委譲。mainがSDK外部参照禁止、preroll取消、読取結果不明時にもLibraryへ戻る導線を確認し、consumerへ反映。50msの停止監視と15秒の開始観測期限は暫定内部値で、実機の応答/負荷採用値ではない。`S15-test-01` はasync protocol witnessの隔離推論によりmodel操作がMainActorへ入らないcompile error 1／warning 0で停止。実装methodへ明示MainActorを加えてtest-02へ進み、旧bundle/source/logを保持。
  - E-S15-01 / V-REVIEW（2026-10-04）: mainが新規player/resource loader/model/view/test＋LibraryCommand隔離注釈の6件を確認。単一管理FDのbounded read、SDK外部参照禁止、実停止/drain後のlease解放、古いsession拒否、解放不明を保持して画面を閉じる導線を実装。巻戻し後の位置停滞を差戻し、現在位置と連続進行の観測を分離しseek通知で基準を破棄する修正を確認。source hash不一致0、所有外コード変更0、diff-check成功（`S15-main-scope-review.json`）。
  - E-S15-02: N01構成、`S15-test-04` は26宣言／33実行成功、fail/skip/compiler・analyzer warning/error各0。実AVPlayer時間進行・decoded frame・PCM音声track、破損媒体、buffer後停止、遅延read/openの実解放待ち、解放commit不明、pause→巻戻し→resumeを検証。custom scheme＋外部参照禁止のローカル経路でありネット接続を要求せず、保存unknown/確認状態を変更しない。各runのxcresult/sources/summary/build/action/stdoutをN01 rootへ保存。Fig/audio/XPC等のSDK stdout診断は保持、vnode診断0。音声の聴取・実端末オフライン・負荷採用はDV-14へ。
  - 旧run・引渡し: test-02は25宣言／32実行中31成功1失敗（破損媒体のunknown理由をtestが誤指定）。実inspection由来の保存record全体を保持するassertionへ修正し、test-03は同32実行全成功。test-04は上記seek修正と追加試験後の最終版。初回compile失敗も保持。I=本体と原本reader接続済み・製品入口はS16待ち、A=実再生部分証拠、D0、R=原本再生の部分証拠。S16は同じManagedOriginalAccessからplayer/model/commandsを1回構成し、画面を閉じてもadapterを保持する。
  - Owner / Files: O-LIBRARY／新規 `FrameRelay/Features/Playback/`・`FrameRelay/Platform/Playback/` と実再生test。
  - Done when: lease付き再生可能fixtureをAVPlayer経路で再生・停止・解放。オフライン動作、確認状態非生成。
  - Verify: V-PLAY。再生進行／破損媒体／停止／全解放、実音声track。
  - Stop: URLやreceipt確認だけで再生成功、原本再生で軽量版確認生成。

### S16 製品入口・共有Compositionとtarget接続

- [ ] Status: blocked
  - Depends: S14,S15。
  - 実行担当: `library_impl`（O-COMPOSE/O-LIBRARY）、2026-10-04開始。S14本体とS15を受領し、S14のV-UIを本taskで検証する。共通store/原本/共有Portはcore所有を継続し、変更が必要なら引渡しを依頼。製品の固定Application Support rootを探索runから分離し、単一store・原本access・playerをアプリで保持する。合成媒体のseedはApp-hosted Unit test targetに限定、通常製品にはfixture分岐を設けない。
  - 軽微可逆判断: Simulatorの通常製品containerにtest-only合成fixtureを投入したrunを先に完了し、同じdestination/parallel無効の別UI runへ引渡して再openを検証する。履歴の合成状態は投影試験であり製品削除成功の証明にはしない。Dynamic Typeは公式simctl、VoiceOverは現SDKのXCUIDeviceサービスで初期設定を記録して復元する。実機聴取や全受入への昇格はしない。
  - 共有試験媒体 S16-FIXTURE: UI操作中の停止を1秒fixtureの自然終了と取り違えないため、`core_impl` が既存 `FrameRelayTests/Support/Storage/SyntheticMovieFixture.swift` のみを単独所有し、既定1秒を保持する任意長さ引数を追加する。映像時間とPCMサンプル数を同じ長さにし、実生成物をS16 seedの検証へ渡す。試験用30秒は製品の録画制限/品質値ではない。
  - 実行待ち履歴: `S16-test-01` はsource manifest保存後、`env TEST_RUNNER_FR_LIBRARY_SEED=1 xcodebuild ...` の権限付き実行から正常返却/承認結果/セッションIDを取得できず、約1111秒後にmainが担当turnを中断した。tool表示は `aborted by user` だが、本Workflow中止のユーザー指示ではない。mainの2回のprocess確認でもxcodebuild/runnerなし、bundle/logなしのため未実行と記録し、コード失敗/合格にしない。次はseedを分離した通常の関連unit runへ進む。UIの停止継続観測とVoiceOver初期状態復元のreview指摘は次版で修正する。
  - 途中compile: direct xcodebuildによる `S16-test-02` は約1秒で実行sessionを取得。UI targetもbuildされ、VoiceOver APIのSwift綴り `__moveForward` でcompile error 1とbuild取消1、warning/analyzer 0、test 0件。現SDK診断が指定した `moveForward` へ修正し、同じseedなし関連suiteのtest-03で再確認する。背景復帰後はisInverted expectationで3秒間の変化を監視し、VoiceOverは初期設定と異なる場合だけ復元する修正を反映。失敗bundle/source/logは保持。
  - E-S16-UNIT: `S16-test-03` は33宣言／49実行成功、fail/skip/compiler・analyzer warning/error 0。製品fixed root再open、同writer/access再利用、marker/DB欠落・破損・symlinkの既存bytes保持、Library/Playback/Inspectionを確認。source hash一致、diff-check成功。SDK等stdout診断66行を別記しvnode診断0。UI操作の証拠ではない。mainがseed投入を限定した権限付きコマンドを別途要求し、承認後 `S16-seed-01` の実行開始sessionを確認、通常UI runへの引渡しを進める。
  - 長媒体の途中失敗と修正: `S16-seed-01` は1件開始後、30秒fixture生成中に進行を観測できず中断（exit75、summaryは0成功1失敗 `Testing was canceled`、compiler/analyzer 0）。32036 bytesの途中Movie・予約・保存意図、source/bundle/summary/build/host stackを保持。SDKの入力間待機仕様を確認し、交互awaitを各receiver専用producerの同時供給へ修正。stackだけで今回の原因を確定せず、エラー時のwriter取消→両producer実終端後確定を実装した。`S16-test-04` は34宣言／50実行成功、fail/skip/compiler/analyzer 0。隔離tmpの30秒生成、video/audio各30秒・音声1track、実AVAssetReader全読取完了の新caseを含む。新caseの成功は詳細tests.jsonで照合、追加printはaction出力で取得できず、その限界も保持。
  - seed再開方針: 旧 `s16-original` の途中状態を修復/削除せず、新規 `s16v2-*` と別manifestで実行する。今回の固定3bindings・digest/byte数・媒体時間を照合し、旧項目が一覧へ残ることもUI待機へ反映。host終了を別途要求した時点ではSimulator Shutdownで実行不可（exit149/code405）、既存媒体は保持。修正後source hash一致をmainが確認し、承認済み限定envコマンドで `S16-seed-02` を開始した。
  - E-S16-SEED: `S16-seed-02` は1宣言／1実行成功、fail/skip/compiler/analyzer 0。実video/audio各30秒・音声1track、485721 bytesと全sha256、保存unknown/commit/bindingをimmutable manifestへ保存。`S16-seed-02-app-manifest.json`、summary/build、export diagnosticsをmainが回収。旧32036 bytesの途中Movieも現rootへ保持され、Shutdown中に証拠rootのproduct-snapshotとhashへ追加保全した。これは実合成媒体の保存/投影準備であり、製品整理/破棄の成功証拠ではない。
  - container照合の補正: 再installでOSのApplication container UUIDが変わり、相対管理rootと旧データが引き継がれることを観測した。絶対パスは観測履歴に残し、同じbundle/通常ApplicationSupport root・固定binding/saveRecord/receipt・全内容hash/byte数/track長の一致でseed→UI→再openを照合する。manifestを新パスへ上書きせず、物理パス一致だけを永続同一性の条件にしない。UI途中失敗でも可能なら実player終了を待つtest teardownを追加し、通常サイズUI runへ引渡した。
  - E-S16-UI途中結果: `S16-ui-01` は5実行中3成功2失敗、skip/compiler/analyzer 0、exit65。原本再生進行/停止/背景復帰、VoiceOver実読み上げ、探索入口の3件成功。アクセシビリティは `Contrast nearly passed`、一覧はtransfer reason文言assertionで失敗。bundle/source/summary/build/log/list activities保持。添付exportの権限付き呼出しは約396秒返却未取得でmainが担当turnを中断（export開始未確認、UI自体は既に終了）。原因特定/修正/再実行を残すためS16全体はblocked、独立したM01を先行する。
  - 再開条件: 添付でコントラスト対象と一覧reasonの表示/選択/AXを特定し、正当な理由を期待文言に合わせて変更せず修正する。seed照合testのURL末尾差をpath比較へ、成功ログの前提をrequireへ修正。通常UI再実行、大文字サイズでの操作/監査と設定復元、別Unit runで保存identityとreader全解放を照合し、main最終差分レビュー後だけdoneへ進める。S13/S21/S23待ちの残件は引続き局所保持。
  - 添付確認/V-REVIEW途中: mainが `S16-ui-01-attachments` をexportし実画像/AX/VoiceOver文字列を確認。コントラスト対象は「動画の状態」のグレーSection見出し。一覧失敗時は両Switch値0・「選択した0本」で、理由表示「対象の動画を選択してください」は正当。identifier付き外側行Switchと内側実Switchのframeが異なるため、実control操作と選択結果を試験で照合する。原本再生/背景停止の画面添付、実VoiceOverの不明/選択の読上げ文字列を保持。M01中はS16コード凍結、これらを修正引渡しとして記録する。
  - Owner / Files: O-COMPOSE／`FrameRelay/Composition/`、`FrameRelay/ContentView.swift`、`FrameRelay/FrameRelayApp.swift`、`FrameRelay.xcodeproj/project.pbxproj`、`FrameRelayUITests/` の対応test。
  - 再開（2026-10-04）: M01のmain差分確認を閉じ、同じ担当・所有で修正と再検証を再開する。見出しの明示的なprimary色、内側Switchの実操作と値/選択数の照合、seedのpath比較と成功前提requireを対象とする。製品の未選択理由や禁止条件を変更せず、通常UI・大文字・再open照合を残す。
  - UI再試験: `S16-ui-02` は5実行4成功1失敗、compiler/analyzer 0。Switchの実操作/値1/選択2本から理由表示・詳細全状態・履歴・再起動が成功し、原本再生/背景停止・VoiceOver・探索入口も成功。残る監査は同じ見出しのコントラスト。`.foregroundStyle(.primary)` はSection内の階層styleを継承するため明示 `Color.primary` へ見出しだけ修正し、未成功の監査caseを `S16-ui-03` で再試験する。ui02 source/bundle/summary/build/添付を保持。大文字とpost-UI照合はまだ未実施。
  - 監査の次の指摘: `S16-ui-03` は1実行失敗。見出し黒表示とdetail-top通過を確認し、次のdetail-actionsで別の `Contrast nearly passed`。element screenshotがなく対象未特定のため、issueHandlerで対象elementと説明を添付して常に未処理を返す診断を追加する。監査抑制・推測の一括色変更はせず、原因を特定してから修正する。旧bundle/source/添付を保持。
  - 監査診断: `S16-ui-04` のissue添付で対象は青actionでなくNavigationBarのinline「動画の詳細」（UILabel）と特定。スクロール内容が透ける背景をdetailに限って動的systemBackgroundの不透明表示へ変更し、監査を再実行する。対象element・画像・全失敗は保存し、診断handlerも常に未処理=失敗を返す。
  - 監査継続: `S16-ui-05` で上記navigationタイトルのcontrastを通過し、長い要照合説明文に `Dynamic Type partially unsupported` を検出。対応する長文Textへsemantic body/縦の自然高さを明示し、同じ種類の履歴・読込不明説明も含めて再検証する。通常/最大文字の操作検証とpost-UI原本identity・全reader照合は未完了のまま保持。
  - 監査全件回収: `S16-ui-06` は1case失敗、全画面で19 issueを記録（detailのdynamicType1/対象nil contrast4、playerのelapsed description1/停止済みbutton contrast1/閉じるcontrastとdynamicType各1、historyのdynamicType9/title clipping1）。監査呼出し内だけcontinueAfterFailureを退避変更/復元し、全issueを失敗として維持。既にsemantic fontの複数Textにも指摘があり、原因未確定を誤検出とは断定しない。elapsedをlabel/valueへ分離、不要な停止済みStopを非表示、Closeを拡大時にも到達可能な操作へ限定修正した後、実最大文字サイズの操作/画像で拡大と全表示を確認する。通常監査未合格は保持。
  - 最大文字実操作（main所有）: player限定修正と操作5地点の画像/AX添付を凍結し `S16-ui-large-01-sources.json` に保存。最初のcontent_size照会はShutdownでunknown、当該Simulatorをboot後の元値はlarge。最大 `accessibility-extra-extra-extra-large` へ設定/再取得し、監査による自動文字変更を含まない一覧/詳細/選択/履歴/再起動と再生/停止/背景復帰の2caseをN01構成で実行開始。`S16-content-size-observations.json` に元値と復元義務を保存し、run後はlargeへ戻して照合する。合格/実拡大は結果未取得のため未判定。
  - 最大文字途中結果: `S16-ui-large-01` は2実行2失敗、skip/compiler/analyzer 0。実行中/直後も最大設定を再取得し、終了後largeへの復元/再取得を確認した。失敗は履歴の画面外discard行とClose後の画面外playOriginal行をスクロールせずexistsだけ待った箇所。画像/AXで実拡大・折返し、選択2本、10状態軸/理由、実再生2.2秒→Stop→停止表示→Closeまで確認。履歴行・再再生/背景/再起動の続行とplayer大見出しの実省略・説明全文の視認は残件。通常監査19指摘を成功へ変更しない。
  - post-UI照合開始（2026-10-05）: source凍結のまま `S16-post-ui-01` でFR_LIBRARY_VERIFYだけをtest hostへ渡し、seed再投入caseを除外したFrameRelayTests全体を実行。保存identity/全reader解放と段階1共有store・規則の回帰を合わせて確認する。envコマンドの承認待ち後に実行session取得、対象版のhash不一致0。結果は未判定。
  - E-S16-POST-UI（2026-10-05）: 同runはexit0、146宣言/187実行成功（空example1を除く186有意味成功）、seedNormal1skip、失敗/compiler/analyzer warning/error各0。`verifySeedIdentityAndReleasedReadersAfterUI()`の実行Passを詳細一覧で確認し、正常製品rootから固定binding/saveRecord/receipt・全内容digest/byte数/媒体時間一致と全reader解放を照合。sources/summary/build/tests-complete/log/xcresultを保存。初回CLIの詳細JSON出力は省略されていたためtruncated.txtとして保持し、完全JSONを別途取得した。これはUI監査合格や実削除/実Captureの証拠ではない。最大文字の画面外行へのスクロールとplayer見出し省略の限定修正へ戻す。
  - 最大文字再試験: player見出しを「原本の再生」へ短縮、履歴/再生再開行のrevealと説明/Stop到達画像を追加した `S16-ui-large-02` は2実行中一覧/詳細/選択/履歴/再起動1成功、再生caseはwait timeout1失敗、skip/compiler/analyzer 0。設定は実行前/直後の最大を確認し、largeへ復元/再取得済み（observations-02）。全証拠を保持して再生失敗の位置を調査し、最新表示で通常監査 `S16-ui-07` を実行する。最大文字だけで中間サイズのDT11指摘や通常contrastを反証せず、同じ履歴でも再生後の操作照合4要素と詳細要照合の長説明は別確認を残す。
  - 最新監査/局所保留（2026-10-05）: `S16-ui-07` は1case失敗、compiler/analyzer 0、1281.985秒。source/summary/build/log/xcresult/全添付を保持し、先行runより長い実行時間の原因は未確定。`large-02` の再生失敗は最初の再生開始後の進行待ちであり、背景復帰失敗ではない。文字サイズ/contrast未解決、最大サイズの再生継続・背景・再起動、原因の切分けを残し、S14/S16のV-UIをdoneにしない。独立したS21へ進み、UI再開時に同じ対象/サイズ/操作と失敗診断を確認する。
  - 最大文字再生の診断: library担当が元screen recordingを保持したまま既存ffmpegで55/68秒frameを抽出し、`S16-ui-large-02-player-frame-{55,68}.png` を確認。製品phaseはfailed、再生位置0.0秒、理由は進行未確認（15秒のmonitor判定）、player/Stop非表示・Close全文。短縮タイトルも最大文字で全文表示。SDKが進行しなかった原因は証拠不足で未確定。再開時はtimeControlStatus/rate/item status・error/待機理由/loader読取・終端と、assert前の失敗AX/画像を記録する。根拠なく時間を延長・成功条件を緩和しない。post-ui-02でこの失敗後も全reader解放を別途照合済み。
  - ui07到達範囲の確定: issueHandler添付はdetail-actionsのDynamic Type説明文1＋対象nilのcontrast failed3/nearly1の計5件。library/detail-top/detail-actions監査後にplay tap→playerのelapsed探索へ進んだが、進行待ちもtimedOutで失敗し、player-stopped/historyの監査へ未到達。19→5を14件解消としない。activitiesは09:36:41.104〜09:52:57.119のelapsed探索間に976.015秒の空白、直後にtimeout、Close→status消失のteardown完了。host/Simulator/AX/再生のどの待機かは未確定で、player表示修正の監査通過もまだ未確認。
  - 再開用読取調査（library、2026-10-05）: large-02のtap→elapsed待機開始は15.783秒、通常ui07も15.891秒で、テストpredicate開始前に製品startup監視15秒が経過する。large-01は同じ30秒媒体/最大文字で初回2.2秒進行→Stop→Close成功のため、文字サイズ固有とはしない。S15からadapter/loader/model hashは一致、S15主条件の1秒/画面非添付と製品30秒/sheet/VideoPlayerの差が残る。次はSDK破棄前の状態/loader/monitor間隔とView出入を同時刻軸で記録し、同じ30秒媒体のView非添付→現在View通常サイズ→最大サイズの最小比較へ。表示変更を原因と断定せず、timeout延長/自動play再試行なし。本調査は読取だけで新たな成功証拠ではない。
  - E-S16-POST-UI-02: 最新UI07後の同一source版でVERIFYだけを渡しProductLibrarySeedTestsを実行。`verifySeedIdentityAndReleasedReadersAfterUI()` 1成功、seed1skip、fail/compiler/analyzer各0、exit0。固定binding/saveRecord/receipt・全内容hash/byte数/媒体時間一致、全reader解放を確認した。再seed/補修なし。N01 rootの `S16-post-ui-02-{sources,summary,build-results,tests}.json` とlog/xcresultを保存。全unitは前回186有意味成功を継承し、以後変更した表示/UIと最新reader照合を区別する。
  - 読取切分け追加（network_map/main、2026-10-07）: 進行未確認の分岐はaudio loadが戻りplay()した後のstartup期限であり、load永久待機とは分ける。player公開→audio await→playとVideoPlayer装着の前後は固定されていないが、装着pause等は未観測の仮説。S20 probeも同じOriginalResourceLoaderを使用し、HTTP read closure・video/duration事前load・VideoOutput有り・画面無しが相違。単純に別loader成功とは扱わない。同じ30秒/製品VideoOutput無しのadapter単独→通常Viewを先に比較し、closeSDK前のrate/timeControlStatus/item error/waiting reasonとmonitor await間隔・View出入・loader終端を有界で残す。新しいコード変更/実行/合格証拠なし。
  - V-REVIEW-S16部分: mainがComposition/fixed root/入口/player表示/操作testを確認。製品fixture分岐なし、既存破損を空storeへ置換せず、同writer/access/adapterを保持し、Closeは解放後のmodel更新へ接続。最新source不一致0、diff-check成功、README/memo/projectのbaseline一致。I=通常製品入口まで接続済み、A=上記成功とUI失敗併存、D0、R=部分証拠。UI監査の失敗は誤検出と断定せず保持する。
  - Done when: 単一store／原本／一覧／再生を組立。探索ticket・Simulator拒否を製品Libraryの起動条件から分離。用途文・target所属確認。
  - Verify: N01構成でbuild／診断、V-UI、Simulator起動・一覧→原本再生。fixtureはtest targetのみ。
  - Stop: 探索証跡破棄、fakeの製品注入、OS／Swift／Teamの無断変更。

### S1V 段階1の接続・検証・レビューを閉じる

- [ ] Status: blocked
  - Depends: S11,S12,S13,S14,S15,S16。
  - 部分照合（2026-10-05）: S11/S12/S15の実disk/実媒体/実再生と、S16-post-ui-01の186有意味unit成功、最新post-ui-02の正常製品root再open/全reader解放を受領。S14/S16の必須V-UI未解決、S13のS21失効commit/S23 OS reader照合/S32 cleanup guard未接続を保持する。段階1全体は未完了だが、S21はS11だけを直接依存とするため着手可。実機A01/A02/A14は別途引渡し、未実施だけを当該自動検証の失敗理由にしない。
  - Owner / Files: main／本tasklist（段階1コードと証拠はレビュー対象）。
  - Done when: disk・原本・UI・再生・Compositionの版一致と必須確認が揃い、実機残件A01／A02／A14を分離。
  - Verify: V-STORE／V-ORIGINAL／V-PLAY／V-UI／V-REVIEW、未接続一覧。
  - Stop: 必須自動検証の未実行・失敗、レビュー未解決。DV未実施だけは阻害しない。

### S20 隔離範囲・早期host通信・方式を具体化

- [x] Status: done
  - 実行開始（2026-10-05）: S21凍結/全Unit確認後、O-SERVERをcore_implへ引渡す。所有は本steeringのsupport/server-isolationと新規証拠root内S20だけ。外部repo/venvはread-only、新snapshot・実効設定・guard/runner・明示試験を準備し、mainがレビュー後に限定実行する。listener承認と実行は具体command/範囲が揃ってから。
  - 同task内の非重複所有: library_implは新規 `FrameRelayTests/Integration/Remote/LegacyServerPlaybackProbeTests.swift` と同dir専用helperだけを担当。明示opt-in/loopbackだけの旧配信HTTP認証・固定Range・実AVPlayer進行/停止/drain probeを準備する。App/共有Port/Composition/project/UIは凍結し、製品配布/確認receiptを生成しない。試験用30秒合成MovieはS16保全ファイルのcopyだけを使用し、Log変換/製品品質へ流用しない。実行はmainがlistener範囲確認後に担当。
  - Depends: N01。
  - 読取準備（2026-10-05、main/ui_probe）: 外部repoのAGENTS/PROJECT_CONTEXTとbackend実コードを確認。HEAD c56d4a2、backend追跡246件、app/tests/assets＋pyproject/uv.lock/READMEの216件は計1,979,074 bytes・symlinkなし。旧T04詳細成果はN00後続観測のとおり取得不能。新snapshot/launcherはまだ未作成・未実行。外部source・venv・未追跡JPEGは未変更。
  - 隔離候補: 既存Python3.12を `-I -B -S` で起動、guard後にsnapshot backendと既存site-packagesのみ追加。全22設定、DB/media/tmp/LUT/cache/log/pytest出力を新規runtimeへ束縛、HOME変更なし、pytest plugin/proxy等を継承しない。pytestは明示node・`--noconftest --capture=sys`・新規未作成basetemp・明示log-file（既定/dev/null write回避）を使用する案。匿名AF_UNIX socketpairとlistener/外向き通信を分ける。audit hookだけでnative SQLite等の全書込抑止を保証せず、接続先/SQL追加ファイル経路・前後manifest/import origin/生成物を検査する。実効成立は未確認。
  - 最小試験候補: `test_asset_read_api::test_asset_list_rejects_invalid_authentication`、test_dbのmigration作成/rollback/WAL、test_storageの初期化/path traversal/temporary cleanup原本保持、test_worker_jobsのunsupported job保持、test_processed_result_streaming_apiのfull/range/invalid range/descriptor後pointer切替/descriptor前supersededの13node（静的20件見込）。実app lifespan/SQLite/run_once/HTTP in-processの範囲で、worker変換成功や実再生ではない。現集合にffmpeg/ffprobe subprocess許可は不要。実listenerは完成launcher/hash/新規root/実効設定/停止手順を揃えてから127.0.0.1:0の具体実行許可を確認する。
  - 第1checkpoint/初回実行: tracked246件・2,032,282 bytesのsnapshot-001とSP1657件のprovenanceを作成し、mainがrunner/guard/全22設定を読取確認。`preparation-001/checkpoint-01-files.json` の凍結版をdefault sandboxで `python -I -B -S .../run_pytest.py --config .../preparation-001/run-config.json` 実行。runtime-pytest-001は20件/10成功/10失敗/skip0、1.836秒、exit71。Range APIがphase2_rollout→detector runtime→ffprobe -versionのPopen準備で/dev/null O_RDWRをopenし、guardが拒否。「subprocess不要」の静的見込みを訂正する。source/SP/snapshot前後hash不変、未承認import origin0、実process終了確認済み。stdoutは切詰め版として保存し、全traceはpytest.xml、result/audit/provenance/parent-resultを保持。外部listener未実行。
  - 再試行準備: configured runtime/disabled-ffprobeは不存在のまま、完全一致argvの実Popen試行とOS ENOENT→既存unavailable分岐だけを観測する最小案を検討。例外をfakeで生成したりphase2検査を省略して通さない。/dev/nullの必要な限定deviceFD以外、外部書込/別binary/外向き通信拒否を維持し、main差分確認後にfresh runtime-002で再実行する。
  - E-S20-02: checkpoint02をmainが既存bounded_subprocess実呼出しと照合。完全一致の不存在ffprobe argv/kwargs・CPython devnull stackだけを許し、予約path作成を拒否、実ENOENTをそのまま再throwする（fake例外なし、POSIX短命子の可能性は別記）。fresh runtime-pytest-002は20件全成功/skip0/0.480秒/exit0。10試行＝10限定deviceFD＝10実ENOENT、guard拒否0、SQLite66接続・終了前survivor/他thread残存/close失敗0、source/SP/snapshot前後不変、未知import0。実process終了・最終audit/XMLhashをparent-resultへ保存。証拠はS20/preparation-002とruntime-pytest-002、旧001失敗も保持。これはin-process/合成bytesの限定成功で実通信・変換ではない。
  - E-S20-PROBE-BUILD: library担当のtest-only2ファイルをmain読取確認し `S20-probe-build-01` をN01構成・only-testing:FrameRelayTests/LegacyServerPlaybackProbeTests・opt-inなしで実行。build成功・診断0・0pass/2skip。固定URL/identity・bounded Range・redirect拒否・実進行/decoded frame・SDK/loader/URLSession終端を別記録する準備で、実listener/実再生はまだ未実行。source/log/summary/build-results/xcresultを保持。
  - E-S20-03（2026-10-05）: checkpoint03凍結manifest SHA256 `bbe57b7c481afba3ba5842107a9e052b90eba71bc259961ea1ce469aeee2869e` をmainが読取確認し、同runnerのaction=range-probeをfresh runtime-range-003で実行、exit0。2,097,169 bytesから1,024 bytesのRangeが206/内容一致、実全hash2回で計4,194,338 bytesを読込み、2回目はSQLite transaction内。2回目の実read後に試験barrierで保持した間、別接続BEGIN IMMEDIATEは25ms busy timeoutでSQLITE_BUSY（観測37.6ms）。これは順序・競合の証拠で通常負荷の閾値ではない。accepted V1 descriptor後のpointer切替でも旧bytes完走、新V1要求409/current V2は206、descriptor前切替409/未open。3 stream descriptorと全hash descriptorの実close、request thread終端/errorsなしを確認。guard拒否0/未知import0/source・SP・snapshot前後不変。SQLite connection objectは別thread所属6件が終了前aliveのため強制closeせず、その後の実process終了0を別途観測（媒体FD解放と区別）。`S20/preparation-003/range-003-parent-result.json`、log、runtimeのprobe/results/audit/provenanceを保持。変換・実通信・製品配布receiptの証拠ではない。
  - 次checkpoint: 限定listener/一時Movie/停止期限/秘密を含まない実行commandを準備し、mainレビュー後に具体実行許可へ進む。全S20はin-progress、実機G1は引続き未確認。
  - S27への読取引渡し: 同一FDを読取leaseで保持してwriter外で全hash→短いtransactionで現公開版/登録/世代/失効再照合＋配布commit→同FD送信を候補とする。検査cache/省略は採用しない。legacy previewの遅延open、formal別pointer配信、finalizer/backfill/migration/workerの全pointer変更も対象。FD保持だけではin-place書込を防げず、別名/全writer/回収を含むartifact不変性の実装と実I/O試験が必要。新契約対象を旧endpointで無登録配信する迂回を許さない。詳細は証拠rootの `S20-s27-design-input.md`。既存データの新契約移行や性能閾値は未採用。
  - checkpoint04実行前引渡し/中断復旧（2026-10-06）: mainがlistener/guard/実行wrapper/停止helperを読取確認。manifest `47560563b287de73f9770c07225d64d6a1c5f4bd91f6a64dbaf6af7700728248`、config `d0376f944a6cb740911685b498d579b5bbc806d3fcae8f35063ab3c085a3f0f8`、support9件の実行版copyをpreparation-004/source-snapshotへ保全。01〜03はhash/log/結果があり当時runner copyはないという限界も保持。前日の起動許可toolはdaemon再起動でaborted、許可/実行完了とは扱わない。復旧時にruntime-listener-004/secretなし・対象実processなし・9件元/copy hash一致を確認。127.0.0.1:0の単独listener、fresh DB/media、30秒合成Movie、1200秒monotonic期限と実終端を別記録。wrapperはrun identity/PID/残期限を照合し、起動許可後の実通信/2case成否は未取得。
  - E-S20-04（2026-10-06）: 上記の具体listenerと秘密env wrapperの権限確認後、127.0.0.1:52478で実起動→N01 Simulatorへ接続。2宣言/2実行成功、skip/fail/compiler/analyzer 0（HTTP0.612秒、player2.311秒）。認証なし401を実終端まで確認、認証付き64/31 byte Range206と内容一致。30秒/485721 byte Movieから107157 bytesを実取得し、AVPlayerは4回連続進行・0.165秒・decoded frame1・audio/video各1track、全156応答の版/digest/size/Range一致。音声聴取/映像品質・製品receiptは別未確認。stop後SDK detach/rate0、loader closed/pending0、URLSession実invalidation callback/task0、0.5秒不変を確認。App側9 JSONをpreparation-004/simulator-observationsへcopy/hash保全。
  - E-S20-04終端/差分: サーバー158 descriptor全てbody終了時close（緊急closeなし）、yield計107252 bytes、server connections/tasks0、listen FD close、secret削除、listener/wrapper両process exit0をmainが別観測。SQLite322接続、終了直前は別thread所属16 connection objectがaliveであり、媒体FD解放と区別し全process終端へ委ねた。guard拒否0/import逸脱0/source・SP・snapshot不変、App/Unit/UI/project109件の試験前後差分0、README/memo/project/M01 PRDの保護hash一致。最終audit SHA256 `870270a9e3046a8169bb00d42e47e6e5df8360a32f2eed71a931231753666908`。preparation-004のparent-result/summary/build-results/tests、runtimeのxcresult/log/lifecycleを保持。独立validationではない。
  - 方式/4軸の引渡し: I＝隔離実サーバー＋test-only認証付きRange/AVPlayer接続、A＝20 pytest/実Range競合/probe2成功、D0、R＝部分技術証拠。版固定streaming＋bounded resource loaderの成立候補をS25へ渡し、全量取得必須へ縮小しない。旧APIを新製品の登録/配布台帳としては使わず、S22/S27のwire/gateを接続する。全hashと能力照会のRange毎負荷、SQLite所有thread解放は後続改善対象。G1の実Wi-Fi/Tailscale/背景/ロック/REC・実負荷、変換/聴取/品質、実データ適用はDV-12/13/14/18へ残す。
  - Owner / Files: O-SERVER＋O-IOS-BI（所有別）／許可された隔離checkout／snapshotと対応test・設定、`FrameRelay/Platform/{Network,Remote}/` の探索。外部実ファイルは旧backend designの一覧をS20で確定。
  - Done when: DB・media・tmp・worker・port・token・設定・回収候補を具体化。認証／固定版実再生／Range／停止・解放の可能な観測からwire・負荷方式とG1実機残件を記録。
  - Verify: V-SERVER／V-PLAY。旧全hash／writer競合を再観測、実listener利用時は実効隔離・許可確認。
  - Stop: 外部書込み／listener未許可部分、稼働root共有、媒体gateや版固定に重大不成立。独立契約は続行。

### S21 同じstoreへ連携・操作・証拠を拡張

- [x] Status: done
  - Depends: S11。
  - 実行担当（2026-10-05）: `core_impl`、O-PORT→O-STORE→O-ORIGINALを同task内で直列単独所有。S16 post-ui-02後の凍結版を受領し、既存schema3/binding/lease journalを継承する。T03値/契約へ加算し、同writerの連携journal・receipt・outbox、現公開版/操作遷移、S13 finishInvalidationとcleanup用最新snapshotを実装する。mainが本tasklistと差分統合を所有、他agentはread-only。
  - S21内の試験所有引渡し: coreの明示引渡し後、`library_impl` が新規 `FrameRelayTests/Integration/Storage/MediaStoreLegacyMigrationTests.swift` だけを単独所有する。固定旧schema3 payloadのcleanup履歴/未解決reader保持、read-only非書換、成功commit時だけschema4へ移行を担当。coreは当該ファイルを変更せず、backend mutation/reader/競合試験を所有する。同じS21内の非重複分担であり、S16や別書込taskは開始しない。mainが全App/Unit/UI/project104ファイルを `S21-start/` とmanifestへ保全し、統合build/testを所有する。
  - S21試験の追加分担: legacy file凍結後、`library_impl` へ新規 `MediaStoreRequestPersistenceTests.swift` だけを追加割当。実SQLiteで登録/公開採用後の単独request・型付き遷移、本人停止/取消・複合待機・試行/遠隔世代、再open/exact replay/CASを担当し、coreのbatch/証拠/確認/失効/reader/fault試験と分離する。legacy試験は2宣言/両候補で予定4実行を作成済み、初回run後の固定JSON hash期待値追加が残件。新規の検証成功はまだない。
  - 内部方式/互換境界: schema4で同一revision順のjournalを検証再生。remote-only原本も同じOriginalContentキーのlogical stateに保持し、localBindingを任意とする内部表現から既存binding有りsnapshotを投影する。将来bindでreader/予約/失効を失わず、別台帳や内容再採番を作らない。旧schema3の正当な履歴は当時の規則で再生し、移行境界以後だけ新cleanup/reader guardを要求する。旧未解決予約だけで新たな実削除を許可しない。実OS/transport/一時媒体owner接続はS23/S25へ別引渡し。
  - V-REVIEW-S21途中: 共有Port/Domainの最初の加算差分（型付き操作遷移、公開観測、outbox配信照合、logical original）をmainが確認。媒体leaseにoperation/owner/epochだけでなくattempt/session/usageの用途別contextを永続束縛する修正を依頼（S21-R01）。既存binding付きprojectionは媒体readerを含まないため、原本consumerの全解放/削除/失効が必ずlogical stateも照合することを試験で確認する（S21-R02）。writer/consumerと実disk検証は作成中で、当該指摘は未解決として保持。
  - writer途中レビュー: schema4/merged replay/両store委譲をmainが確認し、誤った登録・版・世代の失効予約を残して解除不能にする経路（R03）、ACK後の旧版をcurrent一致だけで再request/lease許可する経路（R04）、manifestだけ観測した非配布登録が新公開版/新失効世代を採用できない経路（R05）を差戻し。coreは現登録/current/世代guard、tombstone照合、使用履歴のない観測と失効済み状態からの安全な公開採用へ修正中。R01の型付き用途contextはコードへ反映済み、まだ検証未了。旧S16 seedのfresh cleanup作成は新guardで拒否されるため再投入せず、既存schema3の正常root再openを使う（新しい製品cleanupの証拠ではない）。
  - 初回統合実行（2026-10-05）: core21ファイル＋library2試験を凍結し、N01構成の全FrameRelayTestsを `S21-test-01` で実行。`RecordingStoreDocument.validate` の同一scope内変数名 `originals` 重複でcompile失敗、test未実行。source manifest・log・xcresultを保持し、O-STOREへ変数名修正を差戻し。R01〜05の修正をmainが読取確認したが、検証未了を維持。
  - compile再試行: `S21-test-02` はApp compileを通過したが、MediaOperationStoreTestsの `#expect(allSatisfy(keyPath))` macro展開のrethrows推論でTests compile失敗。該当期待値を明示closureへ直す。source/log/xcresultとtest未実行の履歴を保持。
  - 初回test到達: `S21-test-03` はbuild成功・compiler/analyzer 0。159宣言成功/1失敗/2opt-in skip（parameter展開210成功/1失敗）。失効後outbox配信・reopen後のconcrete storeへのACK照会1件が失敗し、O-STOREへ差戻し。他の確認/失効fault・要求遷移・旧schema試験4実行は成功。旧schema3固定payloadは4件全て29,974 bytes／SHA256 `a2b178bb26ca04d3bd8cbd3b319ec9521a048c4839195d91db613611cc10a9ba`、mainが実ファイル照合・保全し、固定期待値追加をlibrary担当へ引渡し。source/log/summary/build-results/tests/xcresult/fixture証拠を保持。全taskは引続き未完了。
  - E-S21-01/02（2026-10-05）: test-03の原因はconcrete actor呼出しがprotocol extensionのasync既定unknownへ解決される宣言差。両disk actorのlookupを明示asyncへ揃え、legacy入力hashを固定した `S21-test-04` は161宣言/212実行成功・seed作成1skip・失敗0・compiler/analyzer 0。空のexampleを除く211有意味実行、新規store/legacy/requestは15宣言26実行。`env TEST_RUNNER_FR_LIBRARY_VERIFY=1 xcodebuild` にN01のproject/scheme/Debug/destination/DerivedData/自動解決禁止/並列NO/diagnostics never、`-resultBundlePath /private/tmp/fr-di-20261001-5ljls2fr/S21-test-04.xcresult -only-testing:FrameRelayTests test -quiet`。既存正常製品rootのidentity/hash/reader全解放もVERIFY-onlyで成功、再seedなし。全source/log/summary/build-results/tests/xcresultを保持。tests詳細取得の初回xcresulttool同時読取は内部DB展開競合で失敗し、直列再取得で完全JSONを保存（test結果には影響なし）。
  - V-REVIEW-S21: mainがS21開始snapshotとの23所有source差分・R01〜05・migration/replay/consumerを確認。read lease用途context、logical全reader判定、不正予約拒否、ACK後旧版拒否、未受理/実受理/不明の配布観測、旧cleanup履歴保全を実diskで検証。`S21-main-scope-review.json` はtest前後source差分0、保護13ファイル不変、diff-check成功。所有外はXcodeのUserInterfaceStateだけで保持、Composition/UI/project設定変更なし。独立validationではない。
  - 4軸/引渡し: I＝単一writer製品adapter・S13 exact durable ACK照会接続済、A＝上記disk/再open/fault/全Unit成功、D＝未実施、R＝対応ACの永続境界だけ部分証拠。S22C/S23/S25/S27へ登録・媒体操作・配布観測・outboxを引渡す。実SDK/OSのreader owner列挙、サーバー未受理照合producer、backend Compositionは未接続。observerなしはunknown、cleanup supported schema既定は空のままwire採用待ち、S32最終consumerへ接続待ち。G2B/実機を本taskの偽証拠にしない。
  - Owner / Files: O-STORE＋O-PORT（直列）／新規 `FrameRelay/Platform/LocalStore/MediaOperationStoreAdapter.swift`、`FrameRelay/Platform/LocalStore/RecordingStoreDocument.swift`、`FrameRelay/Application/Ports/MediaOperationStorePort.swift`、`FrameRelay/Domain/Operations/` の関連値・対応test。
  - Done when: T03契約の製品adapterを単一writerへ接続。登録意図、固定集合、本人意思、保存証拠、確認＋outbox、失効＋ACK outboxを永続commit・照合。
  - Verify: V-STORE、EBの規則を実diskでも検査。G2A部分引渡し記録。
  - Stop: D01／G2B待ちを追加、別store、読戻しだけで未commit証拠を生成。

### S22 サーバー接続先identity・初回登録・照会

- [x] Status: done
  - Depends: S20。
  - 開始（2026-10-06）: S20の隔離/実通信部分引渡しを受領。O-SERVERが本steeringのsupport/server-implementation/backend-overlayとfresh S22 snapshotへ変更を保存し、外部checkout/venvはread-only維持。共有runnerの明示test集合/provenance入力拡張は同所有者だけが行い、checkpoint04のcopyを保持する。mainがtasklist、内部方式判断、差分/統合実行を所有。wire v1候補はDB永続destination、別fr migration ledger、登録意図一意性/単調世代、bootstrap bearerとclient生成登録secretの分離。要求不変条件を変えない可逆な内部方式として実装し、試験後に採否を記録する。
  - 読取入力（2026-10-05、ui_probe）: 既存認証はapp/api/deps.pyの共有API_TOKENのみ。候補は同DBのfr_*専用migration ledger（既存001〜007と別runner008/009/010を変更しない）、DB永続接続先ID、(接続先,登録意図)一意性、短いtransactionでの単調登録世代、receipt再送/照会。既存phase2c/detector-v2が008以降の最新migration名を厳密照合するため既存ledgerへ単純な011追加は不適合。資格情報は登録許可bearerと登録ごとの秘密digestを分ける案。S21が要求するstrictly greater世代を維持し、旧登録/ACKを置換しない。全て未実装・wire未採用で、S20後の隔離試験で根拠を確認する。
  - 実装途中/可逆wire候補: `/frame-relay/v1/capabilities`、POST `registrations`、GET `registration-intents/{operation_id}`。IDはcanonical lowercase UUID、正63bit世代はdecimal string、64 lowercase hexのclient生成secretを専用headerへ渡し、同destination/intentへ束縛したdigestだけ保存。bootstrap bearerは全endpoint、同意図再送/照会は同secretも必要。別fr ledger・append-only receipt・destination不変triggerを同DBへ加算。ACK等の未実装能力をcapabilityへ出さない。新規コードはoverlayだけで外部未反映、まだimport/試験未実行。
  - V-REVIEW-S22途中 R01: mainがAPI/schema/service/repository/migrationを確認。直接JSONResponseはresponse_model出力検証を通らず、receiptの不正UUID/日時等をstr()で成功へ変える余地を指摘。全field/digest/generationの型・範囲検証と破損disk拒否試験を差戻し、修正/検証待ち。既知不在以外のDB不明/busy/未知schemaを404へ変換しない規則を維持。
  - E-S22-01（2026-10-06）: R01修正後、overlay8件/新snapshot253件、runner/全source21件の凍結copy・diffをmainが確認。checkpoint SHA256 `d496b6751ce32caffc85f5ce74bfbfa4b5e3bf240f3ddb4410f322e5aae2a5bb`。`python -I -B -S /private/tmp/fr-di-20261001-5ljls2fr/S22/preparation-001/source-snapshot/server-isolation/run_pytest.py --config /private/tmp/fr-di-20261001-5ljls2fr/S22/preparation-001/run-config.json` を既存3.12 interpreter/default sandboxで実行。39node/46case（既存20＋新26）が0.92秒で全成功、skip/fail/error0、pytest/process exit0。実ASGI/SQLiteで登録/再送/再open/並行6要求/commit前後fault/旧登録保持/上限/型・receipt破損/既知不在/認証/legacy不変/DDL rollbackを確認。実機・iOS登録接続の証拠ではない。
  - 終端/採用/引渡し: SQLite191接続、終了前survivor/他thread残存/close失敗0、guard拒否0/未知import0、外部source・SP・新snapshot不変、mainが実process exit0観測。最終audit SHA256 `13706915c76cf3b5c16f86021aa082fd45eb5ef463d1859ff04da0cd6c02f273`。実行版/設定/XML/log/parent-resultと `S22-main-scope-review.json`、repo内evidence copyへ保全。App/Unit/UI/project109件変更0、既知README/memo/M01 PRD hash一致、凍結source21件不変、diff-check成功。I＝隔離snapshotで製品API実装、A＝46成功、D0、R＝登録サーバー境界の部分証拠。上記wireをS22C内部実装へ引渡し、server responseと端末commitを分離する。外部checkoutへは未反映/未deploy、確認/ACK/配布は未実装、TLS/実回線/OS保護は未確認。独立validationではない。
  - Owner / Files: O-SERVER／許可隔離checkoutの `backend/app/{api,schemas,services,repositories}/` の登録関連実ファイル・test（S20で具体割当）。
  - Done when: 接続先／登録世代／登録意図を照合し、応答欠落でも同一登録を回復。再登録と通常再起動を区別。
  - Verify: V-SERVER、同一意図再送／応答欠落／別接続先拒否。
  - Stop: 具体書込先未許可、bearerだけを登録成立とする。端末store・G2は不要。

### S22C 端末登録commitと不明時照合

- [x] Status: done
  - Depends: S21,S22。
  - 完了/引渡し（2026-10-09）: E-S22C-IDENTITY/REGRESSION/HTTP-02とV-REVIEW-S22Cで非実機のDone条件を充足。I＝製品初回登録/同writer commit/Keychain/通常再起動・不明照合まで接続済、A＝関連88・全Unit258（VERIFY含む）・障害fixture修正後10・UI2・実HTTP6成功、D0、R＝登録境界の部分証拠。実再インストール/端末保護/TLS/LAN/Tailscale/旧登録の全再登録UIと確認ACK/公開への接続はS28/DV-02/12/15へ保持。新storeに旧v1/v2資格情報を自動採用せず、UUIDを含む完全copy/rollback検知は保証しない。
  - 再開・単独所有（2026-10-09）: mainが現在差分を上記baselineへ保全し、既存成果への限定加算方針を確定。`registration_fix`（worker）へRegistrationPorts／RegistrationCoordinator／KeychainRegistrationVault、同writerのRecordingStoreDocument・ExplorationRecordingStores・MediaOperationStoreAdapter、必要な登録専用Composition接続と関連testだけを単独引渡し。共有storeはこのtask中だけ同worker所有とし、他のApp/project/文書/旧証拠は凍結。mainはtasklist・新証拠・実行/差分統合を所有。`registration_audit` と `registration_probe_audit` は読取のみ。
  - 内部方式 S22C-ID-01（2026-10-09）: path/inodeではなく同じ永続documentにstore instance UUIDを保存し、同writerの明示的な確定処理をKeychain保存より先に行う。読取だけの旧schema移行でUUIDを生成・書換しない。通常再open/container移動は同identityを維持、新storeは別identity。対応不明の旧資格情報や不一致を自動束縛せず保持/拒否する。操作journalや秘密をKeychain/store間で複製しない。実OSの再インストール/保護領域はDV-15/02へ残し、同store中断・移動・置換を実diskで検証する。
  - 追加所有/境界（2026-10-09）: 同workerへBackendCommit.swiftのstore identity値、MediaOperationStorePort.swiftのsnapshot/期待identity、URLSessionRegistrationRemote.swiftのauthorization適合を追加引渡し。writer内の期待UUID比較でawaitを跨ぐ別storeへのcommitを拒否する。存命SQLite contextの物理差替はsession内guardで停止し、永続資格情報の対応にはpath/statを使わない。UUIDを含むstore全体copy/backup rollbackの検知はこの方式の保証外。
  - 実通信再開監査（2026-10-09）: `registration_probe_audit` が旧preparation-001のarchive/live6件、凍結support11件、S22/S22C snapshot253件、外部source246件・site-packages1657件・interpreter一致とruntime/execution/ready/result/secret未作成をread-only確認。未実行001を準備入力として再利用し、App修正版を新source manifestへ凍結後に今回の具体supervisor権限で初回実行する。旧中断要求は許可/成功と扱わない。新revisionを作る場合のsupervisor/checkpoint自己参照問題は、今回の未実行001再利用には影響しない。
  - E-S22C-IDENTITY（2026-10-09）: 修正16file＋新store identity test1fileを単独workerから受領。schema5 metadata UUIDは明示commitまでnil、既存journal/revisionを不変とし、期待UUID journalのUUID欠落は破損拒否。Keychain v2の接続/秘密をUUIDへ束縛し、旧v1は保持/拒否。test-04は追加testのmacro内try不足1件でcompile失敗/未実行/exit65。1箇所修正した `S22C-test-05` はN01-03構成、関連9suiteの58宣言/88実行成功、fail/skip/compiler/analyzer warning/error各0、exit0。同store中断・並行確定・再open・container移動・同path置換・await中置換・schema1〜4読取非書換・identity commit前後fault・v1保持/拒否を確認。新規22caseを含む。実行版126file/source copy・summary/build/tests/logを再開証拠rootへ保存。実HTTP6件/全Unit/製品root VERIFY/UI再確認・最終diffは残件。
  - E-S22C-HTTP-01（2026-10-09）: 今回承認された凍結supervisorを初実行。listener/wrapper/stop helperの実exitは全0、secret削除・listener終端/FD解放・残task/connection0、guard拒否/未知import0・input不変。ただしxcresultは0件、server全route到達0であり実HTTP成功ではない。Xcode enumerationによりSwift Testingの正確な6method IDは末尾`()`を含み、旧only-testing指定が不一致と確認。`registration_probe_fix`（worker）へsupport/server-isolationのwrapper/supervisor/新prepare helperとpreparation-002だけを単独引渡し、正確な6IDと実行件数/結果検査を追加。旧001のruntime/結果/失敗は保持。App/project/backend overlay/guardの権限範囲は拡張しない。
  - E-S22C-REGRESSION（2026-10-09）: 凍結App版の `S22C-test-06` は全Unit＋既存製品root VERIFYで195宣言/258実行成功、fail/skip/compiler/analyzer各0、exit0。実通信8件、再seed、空exampleは明示的に対象外とし、VERIFYは実実行/原本identity・全hash・reader解放一致。action logに旧RecordingStorePersistenceTestsの生きたSQLiteへatomic corruptionを注入する準備によるvnode診断1件を検出（test-05にはなし）。同workerへ当該test1fileだけを追加所有し、破損branchをwriter未openのfresh fixtureへ分離して再検証する。`S22C-ui-02` のConnectionFlowTestsは2件成功、fail/skip/compiler/analyzer各0。UIの成功を実HTTPS登録や実LAN権限の証明にしない。
  - 診断解消（2026-10-09）: RecordingStorePersistenceTestsの破損branchだけを別fresh fixtureへ分離し、DB writer未openのfileへ破損bytesをwithoutOverwritingで作る。`S22C-test-07` は同5宣言/10実行成功、fail/skip/compiler/analyzer各0、action logのvnode/CoreData error/SQLITE_IOERR各0。App実装はtest-05/06/UI02と同一、test準備だけ変更のため関連suiteを再実行し、既存全Unit成功は対応版付きで保持。
  - E-S22C-HTTP-02（2026-10-09）: 002の固定6ID/0件拒否wrapper・hash束縛supervisorをmainレビュー後、今回の権限で初実行。N01-03構成、実URLSession＋実Keychain＋同SQLite writer＋隔離登録APIで6件全成功、skip/fail/compiler/analyzer各0、exit0。サーバー登録5件・POST成功5/認証拒否1、照会成功4/不在4/認証拒否1、通常再openの追加通信0、三つの不明境界から同登録へ照合/POST重複なし。redirect-target到達0、既知Content-Length16385byte応答の保持0/refuse、slow実到達→cancel後disconnect、全task/session/continuation終端各1と300ms安定をclient13JSON/サーバー時系列で照合。未知長body、実HTTPS/実回線/背景/実機は未確認。
  - 終端・最終レビュー/保全（2026-10-09）: listener/wrapper/stop helperの実exit全0、secret削除・残server task/connection0、FD解放、guard拒否/未知import/SQLite他thread残存/close失敗0、外部/隔離入力不変。mainがApp/Test18file・support4fileの限定差分、126source版一致、保護199file不変、空白問題0を確認。証拠root `S22C-main-scope-review.json`／`S22C-resume-final.patch` と `evidence/20261009-s22c-complete/` の114file/1807983bytes＋archive-manifestへ保全（raw xcresult/秘密env/private HTTP actionはrepoへ複製しない）。全UnitとUIのexact commandは各command.txt、HTTPはpreparation-002/integration-command.json、関連testは上記suiteとN01構成を参照。独立validationではない。
  - 開始（2026-10-06）: S21同writer/既存RegistrationRecoveryとS22 wire v1/46成功を受領。新規registration_clientがO-IOS-BI＋必要なO-PORTを単独所有し、Keychain・厳密wire/実URLSession・登録coordinator・試験を実装する。共有契約引渡し後に同taskのO-COMPOSEを直列取得する。registration_serverはS22コードを凍結し、S22C用の隔離listener/試験設定だけを非重複所有。mainが具体範囲レビューと実行、tasklist/差分統合を担当。
  - 契約checkpoint（2026-10-07）: 製品入口はHTTPSの厳密origin＋期待destination＋bootstrap入力を一時authorizationで実照合してからKeychainへ保存する可逆な内部方式を選択。誤入力で未確定profileを固定しない。Keychainの32byte secret保存→同writer意図commit→server→同writer結果commitを守り、資格情報だけ残った中断を自動POSTにしない。正常再起動は確定登録を再利用し、欠落/不整合を未登録へ戻さない。DEBUGかつSimulatorの明示probe constructorだけ127.0.0.1のHTTPを許容し、製品ATS設定は無変更。既存Domain/store/RemoteStatusPortは再利用/凍結し、新登録Portを加算する。登録3routeだけ公開するfresh隔離listenerとsecret env wrapperは準備中、現時点でS22C実通信・Keychain・build/testは未検証。
  - 途中レビュー/初回実行（2026-10-07）: mainがApp/Unit/UI/projectの変更17件を確認しcopy/hash凍結、新Unit22宣言/25実行と既存共有store/契約/製品rootVERIFYの集合を選定。`S22C-test-01` はsandbox CoreSimulator接続拒否でbuild/test前にexit70。権限取得後、同じsourceの `test-02` はURLSessionRegistrationRemoteのproxyConfigurations参照でcompile error1、test未実行、exit65。installed SDKではNetwork moduleのURLSessionConfiguration拡張であることをmainが確認し、import不足を担当へ差戻し。両source/log/xcresultを保持し、失敗を上書きしない。製品初回formは同writer/Keychainが共に未設定と確認できる時だけ表示し、資格情報不明は再照合へ分離済みだが実UI未確認。
  - 実通信試験準備: S22成功snapshot253件と同一のfresh S22C snapshot、source11件、確定6methodsを `S22C/server/preparation-001/` へ凍結。登録APIに加え同bootstrap認証必須のmetadata専用probeをlistener toolingへ限定追加（同origin302とtarget到達数、16385byte過大応答、最大5秒slow/実到達・disconnect観測）。guard不変、秘密env4件、single127.0.0.1:0/1200秒/stop規則を保持。checkpoint SHA256 `81046378b07ffee00ebfafe6d302cd538858b832aa9bdad8f98cfd957374bda5`、config SHA256 `53494f6bbe9c315ac6e868cb8f43f24906df524d9c662b29eb8cf429849136d6`。現時点はAST/dry-runだけでbackend import/listener/実probeは未実行。TLS/LAN/Tailscale/端末保護はこのloopback試験へ含めない。
  - 途中4軸/証拠保全: I＝初回登録本体と同writer製品入口を実装中、A＝test-01環境拒否/test-02 compile失敗・新規test未実行、D0、R＝未達。実probe/実UI/全Unit/最終差分確認を残す。mainが `evidence/20261007-s22c-checkpoint/` に初回失敗・凍結source・接続前copy・server準備48件/884846 bytesを追加copy保全し、archive-manifestへhash/元pathを記録。旧証拠は保持、準備copyを実行成功とは扱わない。
  - E-S22C-UNIT（2026-10-07）: import Network修正と実probe6件追加後のsource121件を凍結。`S22C-test-03` はN01構成/Debug/並列NO/diagnostics neverでRegistrationWireTests、KeychainRegistrationTests、RegistrationCoordinatorTests、RegistrationCompositionTests、BackendContractBoundaryTests、MediaOperationStoreTestsを実行し39宣言/51実行成功、fail/skip/compiler/analyzer各0、exit0。新規22宣言/25実行を含む。実Keychain原子追加/再open/破損拒否、実SQLite意図/結果commit前後fault/再open、通常再起動POSTなし、共有store回帰を確認。HTTPはfakeによる境界試験で実server6probeは未実行。xcresulttoolの初回sandbox展開拒否は権限付き直列再取得で解決、summary/build/tests/log/sourceを保持。実行前後source差分0、生成Info.plistの用途文/iOS27.0/ATS例外なしを確認。
  - E-S22C-UI（2026-10-07）: 同じ凍結版、N01構成の `-only-testing:FrameRelayUITests/ConnectionFlowTests test -quiet` による `S22C-ui-01` は2件成功、fail/skip/compiler/analyzer各0、exit0。製品入口→再照合→戻る→再起動と、初回HTTP URLの送信前拒否を確認。既存資格情報/原本の削除・再seedなし。summary/build/log/sourceを保持。実HTTPS登録成功や実LAN権限の証拠ではない。
  - 残件/停止（2026-10-08）: workerの追加点検で、Keychain残存＋新storeを意図commit前中断と区別できず旧登録を再利用し得る指摘を受領。修正未着手/方式未採用のためS22Cをblockedとし、本人指示で全作業を停止。現在の成功試験はこのケースをカバーしない。I＝登録基盤/製品入口接続済みだが上記不整合あり、A＝51実行＋UI2成功・実HTTP6件/全Unit/VERIFY未実施、D0、R＝未達。冒頭の再開メモに従い当該修正から再開する。
  - Owner / Files: O-IOS-BI＋O-COMPOSE（直列）／新規 `FrameRelay/Platform/Credentials/`・`FrameRelay/Features/Connection/`・`FrameRelay/Application/MediaOperations/` の登録関連、`FrameRelay/Composition/` と対応test。
  - Done when: サーバー登録結果を端末writerへ確定保存、応答不明を照合、通常起動で重複登録しない。
  - Verify: V-STORE／V-SERVER／V-UI、登録commit前後中断。
  - Stop: T19相当の全再登録UI待ちを追加、旧確認の新登録自動復元。

### S23 全媒体gate・本人意思・背景接続

- [ ] Status: pending
  - Depends: S13,S21,S22C,S20。
  - 読取引渡し（2026-10-06、network_map/main）: 既存gate/意思/reader epoch契約を再利用し、同writerへ背景session/task→operation/attempt/target/registration/leaseの永続対応、管理upload一時ファイル所有、継続消失後のcallback受け口を加える候補。getAllTasksと全owner実終端を照合し、task不在を遠隔未実行にしない。installed iOS27の背景URLSessionはredirect常時追従/独自URLProtocol不可、cellular等の禁止はあるがWi-Fi interface種別拘束APIは確認できない。厳密なVPN基礎回線制約/送信前redirect拒否は方式未成立として局所保留し、実装可能な永続対応/OS終端/背景callbackを先行する。前景限定へ要求を縮小せず、未成立を実機確認だけ待ちへ言い換えない。詳細/SDK行根拠は証拠root `S23-network-design-input.md`、実回線/背景/RECはDV-12へ。
  - Owner / Files: O-IOS-BI／`FrameRelay/Application/MediaIO/`、`FrameRelay/Application/MediaOperations/`（PhotoSave／Cleanup／DiscardCoordinatorを除く）、`FrameRelay/Platform/Network/` と対応test。
  - Done when: 固定対象、Wi-Fi／基礎回線、REC／保存、本人停止／取消・全件停止、条件付き再開、OS背景／復帰callbackを実adapterへ接続。
  - Verify: 実転送停止・buffer／handle解放、条件重畳・遅延応答・モバイル媒体拒否。実REC接続はS4V。
  - Stop: 停止要求だけを完了解放、未指示／終了済み再生／不明写真／削除の自動再開。

### S24 サーバー受信・最終保存・全内容検証

- [ ] Status: pending
  - Depends: S20,S22。
  - 読取入力（upload_map/main、2026-10-07）: S22 snapshotの初回finalizeは組立hash→replaceで最終保存先の独立読戻しがなく、既存final再試行だけ全hashする。登録/原本世代に束縛した証拠repo/APIも未実装。既存session/chunk/job基盤とS22 exact登録認証を再利用し、長いreadをwriter外へ置き、短いcommitで資格を再判定する候補。completed早期return、旧worker期限切れ後の再claim/固定assembly競合、legacy preview/formal/rendition/multipart入口の証拠迂回、fr migration ledgerの002追加とworker単独起動も変更境界。証拠とjobのcommit方式/fenceは未採用で、実装時に確定。read-only調査でimport/pytest/通信/書込は未実施。
  - Owner / Files: O-SERVER／許可隔離checkoutの `backend/app/services/{upload_sessions,upload_finalize}.py`、証拠repository／jobとtest（S20で具体割当）。
  - Done when: 最終保存先を独立読戻しして全内容照合後に証拠commit、検証後だけ変換job。原本不変、再送・再起動照合。
  - Verify: V-SERVER。受信／replace／独立検証／証拠commit／job境界中断、別内容・部分失敗。
  - Stop: 組立hash・HTTP成功・file_verifiedだけを保存済み全内容証拠へ代用。G2B不要。

### S24I 試験実原本の転送・保存統合

- [ ] Status: pending
  - Depends: S13,S23,S24。
  - Owner / Files: O-IOS-BI＋O-SERVER（所有別）／`FrameRelay/Application/MediaOperations/` の転送coordinator／adapter、`FrameRelayTests/Integration/` と隔離backend integration tests。
  - Done when: 使い捨て実ファイルで登録→固定対象転送→最終保存証拠→端末commitを接続。個別失敗と共通待機、結果欠落を分離。
  - Verify: 実HTTP・disk再open・digest、複数一部失敗／未処理・再送。実撮影G2BはA12へ。
  - Stop: fixtureの正常を実撮影原本受入へ昇格、全量無条件再送。

### S25 固定版実再生・一時媒体と使用権

- [ ] Status: pending
  - Depends: S13,S20,S21。
  - Owner / Files: O-IOS-BI＋O-LIBRARY（所有別）／`FrameRelay/Platform/{Playback,TemporaryMedia}/`、`FrameRelay/Features/Playback/`、`FrameRelay/Application/Ports/BackendMediaPorts.swift`（O-PORT）と対応test。
  - Done when: 再生可能fixtureの認証・版固定streaming／一時取得・使用量／実解放。写真には完全取得の同一映像と使用権だけを渡す。
  - Verify: V-PLAY、旧版／別版拒否、Range・中断・buffer解放、部分媒体拒否。
  - Stop: S26の実Log採用をfixture実再生の前提にしない。全量取得必須への縮小は相談。

### S26A 標準変換資材・入力適合と比較案を整理

- [ ] Status: pending
  - Depends: N00。
  - Owner / Files: main＋調査担当／本 `design.md` の判断・資材参照欄。標準資材調査は読取。
  - Done when: Log条件・標準資材の由来／版／利用条件・対応入力・未取得箇所を記録し、技術試験可能範囲とG3比較案を分ける。
  - Verify: 根拠資料／既知入力・出力特性の対応、秘密／私的素材非収録。
  - Stop: 資材不明の変換部分だけ保留。品質合格試験はQ01前不可。

### S26J 変換周辺job・候補版処理を先行する

- [ ] Status: pending
  - Depends: S24。実Log採用・標準資材取得は不要。
  - Owner / Files: O-SERVER／隔離backendの変換job・worker orchestration・版repository・対応test。
  - Done when: 検証済み原本だけをjobへ渡し、版付き候補・失敗・再試行を原本再転送と分離する。変換adapter未接続／未適合なら未実装と示し、公開／Rec.709成功を生成しない。
  - Verify: 検証証拠欠落／重複job／候補失敗／旧公開版保持／原本不変の実store・worker試験。変換実映像はS26の別証拠。
  - Stop: 周辺処理成功だけを変換本体完成へ昇格する。資材待ちだけで本taskを止めない。

### S26 検証後変換・標準Rec.709処理

- [ ] Status: pending
  - Depends: S26J,S26A（当該入力適合資材取得）。
  - Owner / Files: O-SERVER／許可隔離checkoutの `backend/app/services/{formal_preview_authority,initial_release_guard}.py`、変換worker／jobとtest（S20で具体割当）。
  - Done when: 検証後起動、適合標準変換の実処理、出力版・候補、原本不変、fps／向き／構図／音声／日時保持。製品実Log品質はA13。
  - Verify: 許可された既知入力の実変換・metadata／内容照合。品質採用ではない。
  - Stop: 適合資材不足、compress-only／タグ変更／根拠なし係数、高品質版追加。

### S27 配布・全公開gate・確認／失効commit

- [ ] Status: pending
  - Depends: S21,S22C,S25。
  - Owner / Files: O-SERVER＋O-IOS-BI（所有別）／design列挙の隔離backend全finalizer／backfill／repository、`FrameRelay/Application/MediaOperations/` の確認／失効、対応test。
  - Done when: 固定再生版＋本人操作＋commitで確認、失効commit後ACK、全必要ACK後だけ公開。全取得／pointer経路・競合・再起動照合。
  - Verify: V-PUBLISH／V-STORE。V1維持・V2失敗・失効後非復活・古いACK・受理済応答競合。
  - Stop: 新登録で旧ACK代用、timeout公開、撮影／原本再生・同期で確認生成。

### S28 状態同期・再登録・動画別操作UI

- [ ] Status: pending
  - Depends: S14,S23,S25,S27。
  - Owner / Files: O-IOS-BI＋O-LIBRARY＋O-COMPOSE（直列）／`FrameRelay/Platform/Remote/` の状態adapter、`FrameRelay/Features/{Connection,Library,Playback}/`、`FrameRelay/Composition/` と対応test。
  - Done when: 媒体なしモバイル同期、旧登録保留と新登録通常利用、動画別段階／停止／不明表示、単数確認／複数転送導線。
  - Verify: V-UI／V-SERVER、旧確認非復元、別動画続行、未取得offline表示。
  - Stop: 全履歴再確認を通常一覧条件にする、同期待ちで自動媒体取得。

### S2V 段階2の結合・障害・レビュー

- [ ] Status: pending
  - Depends: S24I,S25,S26,S27,S28。
  - Owner / Files: main／本tasklist（段階2コードと証拠はレビュー対象）。
  - Done when: 非実機の保存／配信／確認／登録／通信制御が接続され全必須検証・レビューが揃う。変換不足は当該taskと本集約に残す。
  - Verify: V-SERVER／V-PUBLISH／V-PLAY／V-STORE／V-UI／V-REVIEW。
  - Stop: 本集約の未完了だけでS31以降を止めない。G1実機・G2B・G3品質はA12〜A15へ。

### S31 Photos実登録・必要時読取・不明照合

- [ ] Status: pending
  - Depends: Start＝N01・既存T03の完全媒体／使用権・操作契約。登録下位処理・権限UI・不明照合規則は試験実媒体で先行可。永続接続＝S21の単一writer、製品媒体接続＝S25。Finish＝両接続と必須検証を含む全substatus。
  - Owner / Files: O-PHOTOS／新規 `FrameRelay/Platform/Photos/`、`FrameRelay/Application/MediaOperations/PhotoSaveCoordinator.swift`、O-LIBRARY／`FrameRelay/Features/Library/` の権限理由UI。O-STOREが同じstoreへPhotos意図／結果commandを追加し、共有PortはO-PORT、project用途文はO-COMPOSEだけが更新する。各対応testを含めファイル別直列。
  - Partial handoff: 下位処理／権限UIは実Photos adapter・拒否／限定／未発見規則・実行可能Simulatorの検証をS34へ渡す。永続接続は意図→登録→結果commitとinstance破棄→再open・不明時非再追加の証拠を渡す。製品媒体接続はS25の同一完全媒体・使用権と解放までを照合する。各substatusに版・所有・証拠・残件を記録し、S25待ちでも下位処理・永続接続を進める。
  - Done when: 追加権限時機、意図／実登録／管理commit、限定・拒否・未発見の要確認、連打／再試行非再追加、不要一時媒体解放を製品経路へ実接続。下位処理やmock試験の成功だけではS31全体をdoneにしない。
  - Verify: V-PHOTOS／V-STORE、実行可能Simulator Photos追加、権限UI、中断・写真側削除非復活。試験専用媒体／境界代替の証拠と製品接続の証拠を別記し、fakeや未接続を製品成功として注入しない。
  - Stop: fakeだけのPhotos完成、未合意のアルバム／再保存意味、未知結果を未保存へ変換。

### S32 容量整理の実削除・復旧

- [ ] Status: pending
  - Depends: S12,S13,S21。
  - Owner / Files: O-ORIGINAL＋O-STORE（直列）／`FrameRelay/Platform/OriginalStore/` の削除実装、`FrameRelay/Application/MediaOperations/CleanupCoordinator.swift`、`FrameRelay/Platform/LocalStore/` の記録と対応test。
  - Done when: 各動画実行直前の証拠再判定、複数固定集合、ordering・全解放・unlink・再open照合。offline有効証拠で整理可。
  - Verify: V-DELETE、失効との両順序、前後中断、不明／未削除／削除済、外部非削除。
  - Stop: 有効確認なし削除、未実行削除自動実行、再接続／写真強制、削除予約喪失。

### S33 単数破棄の実削除・復旧

- [ ] Status: pending
  - Depends: S12,S13,S21。
  - Owner / Files: O-ORIGINAL＋O-STORE（直列）／`FrameRelay/Platform/OriginalStore/` の共通削除実装、`FrameRelay/Application/MediaOperations/DiscardCoordinator.swift`、`FrameRelay/Platform/LocalStore/` の記録と対応test。
  - Done when: 対象／消失リスク本人確認を単数でcommitし、同じ実削除機構と照合を使用。検証／確認を昇格せず管理記録保持。
  - Verify: V-DELETE、未転送／未検証／不明／失効、競合読書込、再起動、Mac／写真非削除。
  - Stop: 複数一括・自動破棄、rename／trashを削除成功とする、受付だけで履歴化。

### S34 写真・整理・破棄を一覧／履歴へ接続

- [ ] Status: pending
  - Depends: Start＝S14（各操作の画面・状態・理由を先行）。操作別Finish＝S16の共有Composition＋写真はS31、整理はS32、破棄はS33の実接続と必須検証。S28の追加導線はその接続部分だけの依存とし、S28全体や他操作の完了を先行引渡しの条件にしない。
  - Owner / Files: O-LIBRARY＋O-COMPOSE（直列）／`FrameRelay/Features/{Library,Playback}/`、`FrameRelay/Composition/`、対応 `FrameRelayUITests/`。
  - Partial handoff: 写真／整理／破棄ごとにUI・下位処理接続・Composition・検証のsubstatusを記録する。写真は複数保存・権限理由・動画別登録結果、整理は複数の条件再判定・結果・削除後通常一覧、破棄は単数の対象／リスク確認・成功履歴を引渡し単位とする。O-COMPOSEだけが準備済み操作を同じCompositionへ直列接続し、O-LIBRARYの状態投影と必須V-UI証拠を揃えた操作からA16／A17へ渡す。S31未完了でも整理／破棄を進める。
  - Done when: 全3操作の部分引渡しと必要なS28追加導線の統合・検証が揃い、動画別結果、整理後通常一覧、破棄成功履歴、不明の要照合、権限理由と次操作が単一storeから一致する。部分引渡しをS34全体やS3Vのdoneにしない。
  - Verify: 操作別V-UI、実Photos／実unlink・store再openとの表示照合、削除不明非履歴化、写真拒否でも撮影導線維持。未接続操作は理由を表示し、先行操作の成功を他操作へ流用しない。
  - Stop: 未接続成功表示、原本なし軽量版未取得をoffline再生可能表示。

### S3V 段階3の結合・障害・レビュー

- [ ] Status: pending
  - Depends: S31,S32,S33,S34。
  - Owner / Files: main／本tasklist（段階3コードと証拠はレビュー対象）。
  - Done when: S31〜S34全体の必要接続、Photos実adapter・両目的の実削除・store・各操作UIの必須自動検証が揃い、A16／A17実機未実施を分離。操作別の部分引渡しだけでは本集約をdoneにしない。
  - Verify: V-PHOTOS／V-DELETE／V-UI／V-REVIEW。
  - Stop: 必須試験未実行・失敗を実機未確認だけに丸める。

### S41 撮影設定・実適用・記録保存を製品接続

- [ ] Status: pending
  - Depends: Start＝N01・既存P05/P06契約（設定・SDK候補・画面の独立実装）。Finish＝S12,S16の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE＋O-COMPOSE（直列）／`FrameRelay/Application/Capture/`（保存lifecycle除外）、`FrameRelay/Platform/Capture/NativeExplorationCapture.swift`、`FrameRelay/Domain/Capture/`、`FrameRelay/Features/Capture/`、`FrameRelay/Composition/` と対応test。
  - Done when: 保存設定・条件付き復元、希望／能力／実値、記録二候補と共通保存を接続。実機採用値／G2B未確認を保持。
  - 実装引渡しメモ（2026-10-04 read-only確認）: 既存 `RecordingIntent.acceptedAt` は `ExplorationCaptureValues.now()` のhost monotonicであり、暦上の撮影日時へ変換できない。製品撮影では実際の撮影日時を別に観測・保存し、媒体metadata／転送／Photosの同一日時へ渡す必要がある。共有保存契約はO-PORT/O-STOREへ依頼し、旧記録へ現在時刻やfixture日時を補わない。`TemporaryMediaReceipt.capturedAt` の取得日時代用を避ける。
  - Verify: V-CAPTURE、非対応／未知／適用不一致、無断代替拒否、保存経路・UI。
  - Stop: D01未採用を正常実原本へ偽装、撮影不可で製品Libraryも起動不可。

### S42 WB固定・再固定・記録終端を完成

- [ ] Status: pending
  - Depends: Start＝N01・既存WB契約（境界制御・UI・単体試験）。Finish＝S41の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/Application/Capture/`・`FrameRelay/Platform/Capture/` のWB制御、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 安定待ちなしREC、本人再固定、最後の記録フレームまで固定、終端後Auto・次クリップ新測定。
  - Verify: V-CAPTURE、早期STOP／遅いcallback／逆順／二本・他手動値不変。
  - Stop: ND完了でWB固定、記録終端未確認でAuto、自動再固定。

### S43 音声メーター・障害・有限復旧を完成

- [ ] Status: pending
  - Depends: Start＝N01・既存音声契約（meter・入力／書込・復旧）。Finish＝S41の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/Domain/Capture/CaptureAudioState.swift`、`FrameRelay/Application/Recovery/CaptureAudioRecovery.swift`、`FrameRelay/Platform/Capture/` の音声adapter、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 音量／入力／到着／書込み実処理、静寂正常、確認済み障害で抑止／停止・保存結果、有限復旧と手動REC。
  - Verify: V-CAPTURE、無到着／書込失敗／静寂・復旧上限の変更可能試験設定。
  - Stop: 音声省略、復旧で自動REC、無限retry・App全体自動再起動。

### S44 補正選択・復元・画角状態を完成

- [ ] Status: pending
  - Depends: Start＝N01・既存能力／希望／実値契約（補正／復元規則）。Finish＝S41の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/Domain/Capture/CaptureSettings.swift`、`FrameRelay/Platform/Capture/` の補正adapter、`FrameRelay/Features/Capture/` と対応test。
  - Done when: OFF＋複数モードの対応・実適用を照合、初回候補／条件復元／非対応説明、画角世代を予告へ供給。
  - Verify: V-CAPTURE、条件変更／無断代替拒否／実値表示／旧画角失効。
  - Stop: API名を実効果として対応済み表示、標準不成立を合格化。

### S45 人物解析・主役AFの本体と接続

- [ ] Status: pending
  - Depends: Start＝N01・既存撮影契約（解析・AF候補・状態・UI）。Finish＝S41の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/{Application,Platform}/Capture/` の人物解析／AF、`FrameRelay/Domain/Capture/` の主役・意図、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 複数露出対象と単一主役、通常AF／追従・見失い保持・同一再捕捉・再指定、追跡OFF人物優先AFを実装可能経路へ接続。
  - Verify: 非私的・合成入力の実解析、古い世代拒否、別人移行なし、REC非阻害。
  - Stop: 選択UIだけ完成、人物なし／初回意図未合意を製品既定へ採用。該当選択だけ局所保留。

### S46 ND方向・理由・保留と設定再評価

- [ ] Status: pending
  - Depends: Start＝N01・既存設定／WB観測契約（ND解析・規則・UI）。Finish＝S41,S42の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/{Application,Platform}/Capture/` のND解析、`FrameRelay/Domain/Capture/` の評価対象契約、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 実解析入力・複数露出対象・設定／WB世代から濃淡方向／理由／両立困難。遅延・停止・根拠不足で旧OK失効。
  - Verify: 代表入力、太陽／反射／黒／飽和、手動変更とWB、REC非阻害。AF方式採用には依存しない。
  - Stop: 常に判定不能のみ、RGB分布一致をWB目標、飽和から精密量捏造。

### S47 ズーム・構図予告・停止支援・レンズISO

- [ ] Status: pending
  - Depends: Start＝N01・既存倍率／実カメラ／補正契約（制御・予告・UI）。Finish＝S41,S44の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/{Application,Platform}/Capture/` のzoom／レンズ制御、`FrameRelay/Domain/Capture/` の設定、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 目標→予告→開始→目標／途中停止、REC停止別、版付き暫定設定・根拠ある停止候補、対応経路の限定ISO・実値表示。
  - Verify: V-CAPTURE／V-UI、予告で実倍率不変・古い予告・目標超過・手動値優先・切替後保持。
  - Stop: 整数倍率の品質保証、未合意ISO基準／上限の製品採用、原本予告焼込み。

### S48 固定Rec.709撮影表示を接続

- [ ] Status: pending
  - Depends: Start＝N01（描画分離・既知入力試験準備）、変換本体はS26Aの当該適合資材取得。Finish＝S41,S26A（当該入力適合資材取得）の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/Platform/Render/`、`FrameRelay/Platform/Capture/` の表示分岐、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 由来／入力適合済み標準変換を表示経路へ実装し、記録経路へ流さず、確認状態と分離。
  - Verify: 既知入力の実変換・描画、非焼込み境界・二重変換拒否。品質はA05。
  - Stop: 資材不足、未変換画像／独自係数でRec.709完成表示。

### S49 REC・保存状態を媒体gateへ独立接続

- [ ] Status: pending
  - Depends: Start＝N01・既存CaptureLifecycle／媒体gate契約。Finish＝S41のREC／保存境界、S23の実通信adapter。AF・ND・表示変換資材・Photosの完了は不要。
  - Owner / Files: O-CAPTURE／`FrameRelay/Application/Capture/` のcoordinator、O-IOS-BI／`FrameRelay/Application/MediaIO/`、O-COMPOSE／`FrameRelay/Composition/`（ファイル別直列）、対応integration tests。
  - Done when: RECで全媒体の実通信を停止し録画中・保存／異常終了処理中は再開せず、全条件と本人意思で再開する。Mac ACKをREC開始条件にせず、Mac既開始処理を止めない。
  - Verify: 実通信中のREC境界・保存完了前後・回線離脱重畳・停止／取消保持・解放callback、V-CAPTURE／V-SERVER。端末負荷はA11／A12へ残す。
  - Stop: SDK停止受付だけで実停止扱い、保存前再開、S4Vや資材待ちを本接続の前提にする。

### S4V 撮影・全体接続の集約レビュー

- [ ] Status: pending
  - Depends: S42,S43,S44,S45,S46,S47,S48,S49。
  - Owner / Files: main＋O-COMPOSE／本tasklist（統合コードと証拠はレビュー対象。変更は該当所有taskを再開）。
  - Done when: S49の独立接続証拠と、解析／表示／音声／記録の独立経路、起動・復帰UI・必須自動検証・レビューを集約。本集約の未完了は既に独立成立する通信接続等を止めない。
  - Verify: V-CAPTURE／V-UI、REC／保存で通信実停止、次REC、Mac処理継続。実機品質はA01〜A11。
  - Stop: 通信ACKをREC条件に追加、未接続・未実装を実機未確認だけで隠す。

### H01 実機引渡し票・未接続一覧を版へ束縛

- [ ] Status: pending
  - Depends: N00、利用可能な各taskの最新snapshot（段階doneは不要）。
  - Owner / Files: main／本tasklistのDV票・4軸・証拠欄。
  - Done when: 18票の各AC全文・旧ケースの枝条件を実行票のcase枝番へ展開し、根拠AC／条件、操作、期待結果、証拠、直接依存・必要substatus、実装版・状態・実施可能範囲・暫定判断を対応。未実装／未接続を識別して本人へ渡せる形を整える。
  - Verify: 79AC／CF／BI／DI／旧ケースの母集団と枝番を双方向照合し、代表操作だけへの縮小・枝条件漏れ・他枝番の不要な完了待ちを確認。未実装を実機未確認と区別する。
  - Stop: 不足を全件「実機のみ待ち」へ集約する。

### Q01 実機環境・実施条件・品質事前合意を束縛

- [ ] Status: pending
  - Depends: H01の当該case枝番の引渡し、各caseの実施直前。H01全体のdoneは個別caseの条件にしない。
  - Owner / Files: main＋本人／本tasklistの実行票run欄・判断台帳。
  - Done when: 端末／OS／版／対象／接続／証拠先／中断手段／担当日付、品質条件を各case枝番に束縛。枝番ごとに直接依存の引渡し証拠・実施可否を確定し、既存許可を再利用して未許可操作だけ対象別合意。
  - Verify: 票schemaの空欄、AC枝条件と旧Cケースの全必須セル、品質合意版と操作範囲を照合。未束縛値を既定値や過去結果で埋めない。
  - Stop: 未束縛のcaseだけ実施不可。品質未合意で品質合格試験不可。実機全体の再承認を求めない。

### H02 全要求・文書整合・完了範囲を照合

- [ ] Status: pending
  - Depends: 全本体taskの結果、A01〜A18、M01〜M10。
  - Owner / Files: main／本steering3文書。
  - Done when: 79AC・AC-CF11件・AC-BI34件・AC-DI18件を全条件の証拠へ対応。未達／未実施／未接続を残して実装・工程・PRD・初期版を別判定。
  - Verify: ID全数、diff・所有、各証拠の版一致・再試験、文書整合。独立validationは次の明示Workflow。
  - Stop: 必須残件があれば製品完了不可。次の独立validationを暗黙開始しない。

## 文書整合タスク（M01〜M10）

各Statusは下表、Ownerはmainが割り当てるO-DOC。各行が独立した書込みtaskであり対象以外を同時所有しない。Doneには対象diffと新仕様・関連実装の整合、旧履歴・AC識別の保持、main確認を必要とする。Verifyは記載節・ID・リンク・旧条件との照合。文書のread-onlyレビューを明示依頼する時はdoc_reviewer、実装独立検証はimplementation_validatorを使用し、どちらも対象を変更しない。文書更新を実機合格まで一括保留せず、確定差分は先に、実装事実は各成果が得られた時に反映する。

M01着手記録（2026-10-04）: S16のUI失敗を局所保留し、`docs_sync` が `docs/product-requirements.md` だけを所有。Sep29とSep28の確定差分を同期し、受入未評価と全79ACを保持する。コード書込は停止、S16証拠の読取調査は継続可。

M01完了記録（2026-10-04）: mainが確定仕様との対応と全diffを確認。21要求・79ACの本文/未チェックを完全保持、リンク切れ0、diff-check成功、baseline保護対象18ファイルのhash一致。N01証拠rootの `M01-main-review.json` にPRD hash `bba647950e85ad8b427414c704e8f08cba70439ff49c29ede8e1d81f0c75a2ca` と照合結果を保存。製品達成へ昇格せず、M07〜M10/独立レビュー・validationは未開始。

| task／状態 | 所有対象（1件ずつ） | 直接依存／明示Workflow | 更新理由・完了条件／検証 |
| --- | --- | --- | --- |
| M01／done | `docs/product-requirements.md` | N00／新しい明示 `$implement-steering` 内でdocument_author | FR-07の確定操作と暫定値、FR-10／14／17の一覧・履歴・実本体削除、FR-15追加／読取照合限界、PRD-Q01〜PRD-Q05の確定部分、順序と受入分離を反映。21要求79ID・禁止・品質を保持して差分照合 |
| M02／pending | `docs/functional-design.md` | N00、該当実装の更新時snapshot／同implement | U1／U2／U4、F1〜F5のズーム／権限／整理／履歴と不明遷移、機能設計T01〜T21の先行試験／実機残件を整合。U3の背景・携帯状態同期・個別失敗続行はbackend確定事項を反映し未合意へ戻さない |
| M03／pending | `docs/architecture.md` | N00、S11／S13／S21等の判断が生じる都度／同implement | D01非依存共通store、単一writer／原本／lease、削除管理記録、Photos限界、暫定設定、候補接続と実採用、4軸と層別検証。内部方式採用は実装証拠付き、実機能力は未確認を保持 |
| M04／pending | `docs/repository-structure.md` | N00、各taskの実ファイル確定時／同implement | 雛形だけとする古い現状を修正し、既存部分実装・新モジュール責務・共通store／原本／Ports／Composition単独所有・試験媒体分離・履歴責務を実在配置へ対応。整理目的だけの全面移動なし |
| M05／pending | `docs/development-guidelines.md` | N00／同implement | 直接依存だけの保留、4段階、軽微可逆裁量、4軸・レビュー証拠、分割本体doneと製品DoD、まとめた実機票を反映。必須検証／品質事前合意／実データ許可／coverage方針維持 |
| M06／pending | `docs/glossary.md` | N00／同implement | 原本本体／管理記録、履歴≠ゴミ箱、削除成功／要照合、追加権限／読取照合限界、未実装／探索／未接続／実装済み実機未確認、暫定／採用値、4軸／局所保留を他5文書と照合 |
| M07／pending | `docs/ideas/20260926-capture-foundation-feasibility.md` | N00／別途明示 `$define-requirements`（この旧仕様の整合を対象指定） | 新confirmed仕様の限定差分を相互参照しP06限定先行→4段階、D04とD01分離、CF受入・方式品質保持を追記。過去合意を削除しない。新規要求判断が生じればその箇所だけ確認 |
| M08／pending | `docs/ideas/20260928-backend-integration.md` | N00／別途明示 `$define-requirements`（この旧仕様の整合を対象指定） | G1実機非依存先行、G2A部分／G2B実原本／G2C分離、写真／削除本体の段階3所有を追跡。BI全34AC、D02／G3・背景／同期確定事項を保持 |
| M09／pending | `.steering/20260926-capture-foundation-feasibility/{requirements,design,tasklist}.md` | M07／当該旧仕様を明示入力に別 `$prepare-steering`、feature_planner | P07／G03の一括後段待ちを新taskへの責務参照へ更新し、P09のstore・原本と実機残件を分離。旧P全21状態／失敗／部分証拠は保持。新tasklistが現行進捗であることを3文書で一致 |
| M10／pending | `.steering/20260928-backend-integration/{requirements,design,tasklist}.md` | M08／当該旧仕様を明示入力に別 `$prepare-steering`、feature_planner | T05部分観測／未実施を維持しT06と全後段一括待ちを直接依存へ変更。T07/G2A、T11/G2B・G2C、T12実原本、T13/G3を新taskへ対応。T03再実装や旧Done拡張なし |

M07〜M10の別Workflowがまだ明示されていない時は外部待ちを記録する。本計画の作成・新implementの呼出しから暗黙開始しない。N00の正本／所有記録により独立実装は続行できるが、必要文書整合が残ればH02の製品完了条件は未達。入力の新仕様とinitial-requirements、README、memoはこれらの編集対象に含めない。

## 旧計画の依存・責務対応

旧撮影のP、旧backendのTを以下で区別する。旧Doneは当時の限定範囲だけ、blocked／pendingは履歴として保持する。新本体taskのdoneは旧task全体のdoneではない。CF／BIの実機・品質条件は後段のA／DVへ残る。

| 旧task／現在状態 | 新しい本体・整合task | 受入・旧残件の引渡し | 再利用証拠 |
| --- | --- | --- | --- |
| 撮影P01／done | N00 | 既存正本・許可・差分保持 | EC |
| 撮影P02／blocked | N01 | Q01／A01・A02の実機環境・署名 | EC |
| 撮影P03／blocked | H01,Q01 | 全DVの条件／保管先・品質 | EC |
| 撮影P04／done | S11,S20,S26A | 撮影D01〜D05の実機採用はA01〜A11 | EC |
| 撮影P05／done | S12,S13,S41〜S43 | 既存契約再利用・実接続と実機は別 | EC |
| 撮影P06／blocked | S11〜S16,S41〜S48 | D02未実装・実起動／方式比較を保持 | EC,ES |
| 撮影P07／pending | S11,S26A | Q01／A01・A02・A04・A09でC01/C02・全セル束縛 | EC |
| 撮影P08／pending | S14〜S16,S41 | A01／A14、C01/C19 | E0 |
| 撮影P09／pending | S11〜S13,S41 | A01／A02、CF-08・G2A/B/C区別 | ES |
| 撮影P10／pending | S42 | A03、C05/C15 | EC |
| 撮影P11／pending | S43 | A10、C06/C07/C15 | EC |
| 撮影P12／pending | S48 | A05、D02・C08 | EC（拒否境界のみ） |
| 撮影P13／pending | S44 | A04、C09/C10 | EC |
| 撮影P14／pending | S47 | A08／A09、C11/C12 | EC（契約のみ） |
| 撮影P15／pending | S1V,S2V,S3V,S4V | U01〜U05／B1〜B7の全必要ケース、実機限界保持 | EC,ES |
| 撮影P16／pending | S1V,S4V | A01の実機起動、buildと起動分離 | EC |
| 撮影P17／pending | S41〜S48 | A01／A03〜A10、C03〜C13 | E0 |
| 撮影P18／pending | S4V | A11、C16/C17同時成立・応答性 | E0 |
| 撮影P19／pending | S12,S32,S33,S43 | A02／A10／A17、C07/C14/C15 | ES（非実機のみ） |
| 撮影P20／pending | 各不成立taskへ修正を戻す | A01〜A18再試験、C18原因切分け | E0 |
| 撮影P21／pending | M01〜M07,M09,H02 | C19・AC-CF-01〜11・79AC引継ぎ | EC（追跡のみ） |
| backend T01／done | N00 | 外部操作・旧媒体保護 | EB,EI |
| backend T02／done | S13,S20,S21 | 契約IDと重大方式の残件 | EB |
| backend T03／done | S13,S21〜S28,S31〜S33 | 製品adapter／disk／実I/O未実装を分離 | EB |
| backend T04／done | S20 | 外部listener等は旧許可外 | EI |
| backend T05／blocked | S20,S25 | A12／A14、G1実回線・背景・実解放 | ER |
| backend T06／pending | S20,S26A | 方式ごとの直接依存・実機重大判断 | ER（部分観測） |
| backend T06A／pending | S22 | サーバー登録はG2／端末store待ちなし | E0 |
| backend T07／pending | S11,S21 | A02、G2A部分と実端末残件 | EB（契約のみ） |
| backend T07A／pending | S22C | 端末初回登録はS21＋S22、再登録全体待ちなし | EB（契約のみ） |
| backend T08／pending | S24 | A12実原本。隔離保存はG2B不要 | E0 |
| backend T09／pending | S23,S24I | A12、全媒体実停止／背景 | EB（契約のみ） |
| backend T10／pending | S24,S24I | 非実機中断は実撮影待ちなし | E0 |
| backend T11／pending | S13,S23,S41 | A01／A02がG2B、A12が実G2C結合 | EB,ES |
| backend T12／pending | S24I | A12の実撮影原本のみG2B／G2C依存 | E0 |
| backend T13／pending | S26A,Q01 | A13前の実Log／G3事前品質合意 | E0 |
| backend T14／pending | S26 | A13、実Log・本人品質未評価 | E0 |
| backend T15／pending | S25 | A14、fixture再生はS26実Log採用待ちなし | ER |
| backend T16／pending | Q01 | A13でG5出力採用 | E0 |
| backend T17／pending | S27 | A14／A15、全公開経路／全必要ACK | EB（規則のみ） |
| backend T18／pending | S21,S27 | A14、実disk／実再生／明示操作 | EB |
| backend T19／pending | S28 | A15、旧登録ACK保留・通常利用独立 | EB |
| backend T20／pending | S14,S28,S34 | A12／A14／A16／A17動画別実操作 | E0 |
| backend T21／pending | S13,S25,S31〜S33 | A16／A17。旧は後続契約、本計画がPhotos／削除本体所有 | EB |
| backend T22／pending | S2V,S3V | A02／A12／A14〜A17。非実機試験はT12待ちなし | EB（規則のみ） |
| backend T23／pending | S23,S4V | A12、実回線・背景・REC保存負荷 | E0 |
| backend T24／pending | S2V,S3V,S4V | A01〜A18受入操作・実機起動 | E0 |
| backend T25／pending | M01〜M06,M08,M10,H02 | 34BI／79AC、文書同期は実機待ちなし | EB（追跡のみ） |
| backend T26／pending | H01,H02 | 実装／検証工程／PRD／初期版を別判定 | E0 |

## PRD 全21要求・79ACの個別台帳

行の条件名は索引であり[PRD原文](../../docs/product-requirements.md)の全文と新仕様の限定差分を全て適用する。CFは旧撮影要求、BIはAC-BI番号への対応を表す（`CF-xx`の同番号AC-CFも参照）。「後続必須」は旧仕様で未実装だった要求であり今回の対象外ではない。

直接依存列 `dep(task...)` は、その行に列挙した各新本体taskのDepends／Start／Finishだけを個別参照する明示プロフィールである。タスク範囲は存在する同接頭辞IDを全て含む。実機側は対応AタスクのDepends＋Q01、品質はその票の合意版が直接依存。段階の実機合格や全タスクdoneを暗黙追加しない。担当はdesignの所有キー、行の新タスクで実ファイルを特定する。全行初期D0／R0、NFR-04-02の実装軸I0は整理操作が未実施という意味。

| 要求 | AC | 条件索引 | 旧P/T・CF/BI | 部分証拠 | 新本体task | 直接依存 | 担当 | I | A | D | R | 実機票 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FR-01 | AC-FR-01-01 | 音声付き4K24/30原本・写真非追加 | P05/P06/P09;CF-02/08 | EC,ES | S12,S41 | dep(S12,S41)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | I1 | A1 | D0 | R0 | DV-01、DV-02 |
| FR-01 | AC-FR-01-02 | 3形式・カメラ対応・無断代替禁止 | P05/P06/P09;CF-02/08 | EC,ES | S41 | dep(S41)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | I1 | A1 | D0 | R0 | DV-01 |
| FR-01 | AC-FR-01-03 | 手動値維持・ND再評価 | P05/P06/P09;CF-02/08 | EC,ES | S41,S46 | dep(S41,S46)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | I1 | A1 | D0 | R0 | DV-01、DV-07 |
| FR-01 | AC-FR-01-04 | 保存設定・WB/補正の条件復元 | P05/P06/P09;CF-02/08 | EC,ES | S41,S44 | dep(S41,S44)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | I1 | A1 | D0 | R0 | DV-01、DV-04 |
| FR-02 | AC-FR-02-01 | 固定Rec.709表示・非焼込み | P06/P12;CF-05 | EC:表示拒否境界のみ | S48 | dep(S48)＋対応A/Q01 | O-CAPTURE | I0 | A1 | D0 | R0 | DV-05 |
| FR-02 | AC-FR-02-02 | 確認状態分離・描画/録画品質 | P06/P12;CF-05 | EC:表示拒否境界のみ | S48,S4V | dep(S48,S4V)＋対応A/Q01 | O-CAPTURE | I0 | A1 | D0 | R0 | DV-05、DV-11 |
| FR-03 | AC-FR-03-01 | OFF＋複数実モード | P05/P06/P13;CF-06 | EC:能力/適用契約 | S44 | dep(S44)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-04 |
| FR-03 | AC-FR-03-02 | 初回候補・対応条件復元 | P05/P06/P13;CF-06 | EC:能力/適用契約 | S41,S44 | dep(S41,S44)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-01、DV-04 |
| FR-03 | AC-FR-03-03 | 3場面品質・設定不変 | P05/P06/P13;CF-06 | EC:能力/適用契約 | S44,S4V | dep(S44,S4V)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-04、DV-11 |
| FR-03 | AC-FR-03-04 | 補正画角・予告・切替保持 | P05/P06/P13;CF-06 | EC:能力/適用契約 | S44,S47 | dep(S44,S47)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-04、DV-08、DV-09 |
| FR-03 | AC-FR-03-05 | 標準不成立の制約と相談 | P05/P06/P13;CF-06 | EC:能力/適用契約 | S44 | dep(S44)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-04 |
| FR-04 | AC-FR-04-01 | 安定前RECと固定 | P05/P06/P10;CF-03 | EC:WB順序規則/探索 | S42 | dep(S42)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-03 |
| FR-04 | AC-FR-04-02 | 本人再固定・他設定維持・品質 | P05/P06/P10;CF-03 | EC:WB順序規則/探索 | S42 | dep(S42)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-03 |
| FR-04 | AC-FR-04-03 | 最終フレーム・待機Auto・二本 | P05/P06/P10;CF-03 | EC:WB順序規則/探索 | S42,S46 | dep(S42,S46)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-03、DV-07 |
| FR-05 | AC-FR-05-01 | 複数露出対象と単一主役・意図 | P05のREC非依存のみ;CF-09部分/後続必須 | E0（旧計画の後続要求のみ） | S45 | dep(S45)＋対応A/Q01 | O-CAPTURE | I0 | A0 | D0 | R0 | DV-06 |
| FR-05 | AC-FR-05-02 | 見失い保持・同一再捕捉・再指定 | P05のREC非依存のみ;CF-09部分/後続必須 | E0（旧計画の後続要求のみ） | S45 | dep(S45)＋対応A/Q01 | O-CAPTURE | I0 | A0 | D0 | R0 | DV-06 |
| FR-05 | AC-FR-05-03 | 人物未確定でもREC | P05のREC非依存のみ;CF-09部分/後続必須 | EC:REC非依存規則のみ | S45,S41 | dep(S45,S41)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-06 |
| FR-05 | AC-FR-05-04 | 通常合焦・前後追従品質 | P05のREC非依存のみ;CF-09部分/後続必須 | E0（旧計画の後続要求のみ） | S45 | dep(S45)＋対応A/Q01 | O-CAPTURE | I0 | A0 | D0 | R0 | DV-06 |
| FR-05 | AC-FR-05-05 | 追跡OFFの人物優先AF品質 | P05のREC非依存のみ;CF-09部分/後続必須 | E0（旧計画の後続要求のみ） | S45 | dep(S45)＋対応A/Q01 | O-CAPTURE | I0 | A0 | D0 | R0 | DV-06 |
| FR-06 | AC-FR-06-01 | 濃く/薄くの方向と理由 | P05/P10設定事実;CF-09部分/後続必須 | E0（旧計画の後続要求のみ） | S46 | dep(S46)＋対応A/Q01 | O-CAPTURE | I0 | A0 | D0 | R0 | DV-07 |
| FR-06 | AC-FR-06-02 | 人物背景両立困難・太陽反射黒 | P05/P10設定事実;CF-09部分/後続必須 | E0（旧計画の後続要求のみ） | S46 | dep(S46)＋対応A/Q01 | O-CAPTURE | I0 | A0 | D0 | R0 | DV-07 |
| FR-06 | AC-FR-06-03 | 停止遅延保留・旧OK失効・REC | P05/P10設定事実;CF-09部分/後続必須 | EC:REC非依存/設定WB事実のみ | S46,S41 | dep(S46,S41)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-07 |
| FR-06 | AC-FR-06-04 | WB状態と飽和情報の限界 | P05/P10設定事実;CF-09部分/後続必須 | EC:REC非依存/設定WB事実のみ | S46,S42 | dep(S46,S42)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-03、DV-07 |
| FR-07 | AC-FR-07-01 | 目標構図予告・倍率不変・非焼込み | P05/P14;CF-07（予告は後続必須） | EC:倍率/停止契約のみ | S47 | dep(S47)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-08 |
| FR-07 | AC-FR-07-02 | 目標/途中停止・操作と品質 | P05/P14;CF-07（予告は後続必須） | EC:倍率/停止契約のみ | S47 | dep(S47)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-08 |
| FR-07 | AC-FR-07-03 | 停止支援・引く予告・画角/画質/負荷 | P05/P14;CF-07（予告は後続必須） | EC:倍率/停止契約のみ | S47,S44 | dep(S47,S44)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-04、DV-08、DV-09 |
| FR-08 | AC-FR-08-01 | 限定ISOと切替後保持 | P05/P14;CF-07 | EC:実値/限定ISO契約のみ | S47 | dep(S47)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-09 |
| FR-08 | AC-FR-08-02 | 実値表示・非対応切替拒否 | P05/P14;CF-07 | EC:実値/限定ISO契約のみ | S47,S44 | dep(S47,S44)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-04、DV-09 |
| FR-08 | AC-FR-08-03 | 映像音声・切替継続品質 | P05/P14;CF-07 | EC:実値/限定ISO契約のみ | S47,S4V | dep(S47,S4V)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-09、DV-11 |
| FR-09 | AC-FR-09-01 | 待機/録画音量・静寂と障害 | P05/P06/P11;CF-04/08 | EC,ES:音声規則/保存探索 | S43 | dep(S43)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | I1 | A1 | D0 | R0 | DV-10 |
| FR-09 | AC-FR-09-02 | 確認済障害で停止・保存分類 | P05/P06/P11;CF-04/08 | EC,ES:音声規則/保存探索 | S43,S12 | dep(S43,S12)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | I1 | A1 | D0 | R0 | DV-02、DV-10 |
| FR-09 | AC-FR-09-03 | 有限復旧・手動REC | P05/P06/P11;CF-04/08 | EC,ES:音声規則/保存探索 | S43 | dep(S43)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | I1 | A1 | D0 | R0 | DV-10 |
| FR-09 | AC-FR-09-04 | 到着/書込み・保存音声 | P05/P06/P11;CF-04/08 | EC,ES:音声規則/保存探索 | S43,S12 | dep(S43,S12)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | I1 | A1 | D0 | R0 | DV-02、DV-10 |
| FR-10 | AC-FR-10-01 | 原本/軽量版再生・複数結果/単数操作 | P08/P09/P21,T15/T20;CF-01/08,BI-15/33 | ES,EB,E-S13/14/15 | S14,S15,S25,S28,S34 | dep(S14,S15,S25,S28,S34)＋対応A/Q01 | O-LIBRARY | 原本reader/一覧/実player/製品入口接続済・S16 UI残件、軽量版未接続 | E-S13:50/E-S14:44/E-S15:33、E-S16通常UI操作4成功・最大文字途中・post-UI/単体186有意味成功 | D0 | 原本実再生/一覧/製品操作の部分証拠・UI監査/軽量版未確認 | DV-14、DV-16、DV-17 |
| FR-10 | AC-FR-10-02 | 保存中断再起動の4分類 | P08/P09/P21,T15/T20;CF-01/08,BI-15/33 | ES,EB,E-S11,E-S12 | S12,S14 | dep(S12,S14)＋対応A/Q01 | O-LIBRARY | S12保存/復旧＋S14分類投影/製品UI接続済、実Capture未接続 | E-S12:54/E-S14:44、E-S16保存unknown/要照合の実表示・post-UI再open | D0 | 保存/reopen/分類/製品UIの部分証拠・実Capture未確認 | DV-02 |
| FR-10 | AC-FR-10-03 | 整理後offline・再接続等非強制 | P08/P09/P21,T15/T20;CF-01/08,BI-15/33 | ES,EB（実再生なし） | S14,S32,S34 | dep(S14,S32,S34)＋対応A/Q01 | O-LIBRARY | S14整理後通常一覧の製品UI投影済・実整理未接続 | E-S14:44、E-S16通常UIの整理/破棄投影・履歴操作成功（test seed） | D0 | 投影/製品表示の部分証拠・実整理未確認 | DV-14、DV-17 |
| FR-11 | AC-FR-11-01 | 指示原本の転送・全内容検証 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB:規則のみ,EI:隔離 | S24,S24I | dep(S24,S24I)＋対応A/Q01 | O-IOS-BI/O-SERVER | I1 | A1 | D0 | R0 | DV-12 |
| FR-11 | AC-FR-11-02 | 回線離脱待機・検証不明原本保持 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB:規則のみ,EI:隔離 | S23,S24I | dep(S23,S24I)＋対応A/Q01 | O-IOS-BI/O-SERVER | I1 | A1 | D0 | R0 | DV-12 |
| FR-11 | AC-FR-11-03 | 結果受信中断・HTTPとcommit分離 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB:規則のみ,EI:隔離,E-S21 | S21,S24I | dep(S21,S24I)＋対応A/Q01 | O-IOS-BI/O-SERVER | 同writerの検証証拠/要求遷移/commit照会実装済・実HTTP未接続 | E-S21:実disk26新規/全Unit211有意味成功 | D0 | 永続境界の部分証拠・実転送/受信未確認 | DV-12 |
| FR-11 | AC-FR-11-04 | 複数固定集合・動画別結果 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB:規則のみ,EI:隔離,E-S21 | S23,S24I,S28 | dep(S23,S24I,S28)＋対応A/Q01 | O-IOS-BI/O-SERVER | 固定batch/動画別requestを同writerへ永続化・実転送/UI未接続 | E-S21:両disk固定集合とrequest再open成功 | D0 | 集合/結果保持の部分証拠・実通信/表示未確認 | DV-12 |
| FR-12 | AC-FR-12-01 | 保存検証後生成・原本保持 | T13/T14/T16;BI-16/17/32 | EB:変換前提契約のみ | S26J,S26 | dep(S26J,S26)＋対応A/Q01 | O-SERVER | I1 | A1 | D0 | R0 | DV-13 |
| FR-12 | AC-FR-12-02 | 実Rec.709・媒体特性/日時保持 | T13/T14/T16;BI-16/17/32 | EB:変換前提契約のみ | S26 | dep(S26)＋対応A/Q01 | O-SERVER | I1 | A1 | D0 | R0 | DV-13 |
| FR-12 | AC-FR-12-03 | 旧compress-only非代用・差替条件 | T13/T14/T16;BI-16/17/32 | EB:変換前提契約のみ | S26,S27 | dep(S26,S27)＋対応A/Q01 | O-SERVER | I1 | A1 | D0 | R0 | DV-13、DV-14 |
| FR-13 | AC-FR-13-01 | 単数途中実再生＋明示確認 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER,E-S20-04 | S25,S27 | dep(S25,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 旧配信認証Range/実AVPlayerの技術probe接続済・製品配布/本人確認未接続 | E-S20-04:実HTTP/実進行/decoded frame/停止2成功 | D0 | 合成媒体の方式部分証拠・製品確認/実機未確認 | DV-14 |
| FR-13 | AC-FR-13-02 | 受付と確認commit・不明 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER（実再生/ACKなし）,E-S21 | S21,S27 | dep(S21,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 確認＋outbox同時commit/不明時照会実装済・軽量版player/サーバー未接続 | E-S21:両disk確認fault/reopen成功、全Unit211有意味成功 | D0 | 端末commitの部分証拠・本人実確認/サーバー未確認 | DV-14 |
| FR-13 | AC-FR-13-03 | 失効前V1維持・offline整理 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER（実再生/ACKなし） | S27 | dep(S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | I1 | A1 | D0 | R0 | DV-14、DV-17 |
| FR-13 | AC-FR-13-04 | 失効commit後全必要ACK・非復活 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER,E-S21,E-S22 | S27,S28 | dep(S27,S28)＋対応A/Q01 | O-IOS-BI/O-SERVER | 端末tombstone/ACK outbox/旧版拒否とserver登録資格情報の分離を実装・全owner/ACK経路未接続 | E-S21失効fault/epoch/配布分岐、E-S22登録26成功・旧資格情報非代用 | D0 | 端末永続/登録認証境界の部分証拠・全必要ACK/公開は未確認 | DV-14、DV-15 |
| FR-13 | AC-FR-13-05 | 初回/V2/失効後失敗の区別 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER（実再生/ACKなし） | S26J,S27 | dep(S26J,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | I1 | A1 | D0 | R0 | DV-14 |
| FR-13 | AC-FR-13-06 | 同一映像再取得/切断非失効 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER（実再生/ACKなし） | S25,S27 | dep(S25,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | I1 | A1 | D0 | R0 | DV-14 |
| FR-14 | AC-FR-14-01 | 有効証拠と手動整理・写真不要 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則,E-S21 | S32 | dep(S32)＋対応A/Q01 | O-ORIGINAL/O-STORE | writerが最新保存/確認/検証schemaを再判定・実整理consumer未接続 | E-S21:有効証拠/未知schema/組立のみ拒否のdisk成功 | D0 | 整理受付guardの部分証拠・実削除未確認 | DV-17 |
| FR-14 | AC-FR-14-02 | 不明/欠落/失敗/失効は不可 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則,E-S21 | S32 | dep(S32)＋対応A/Q01 | O-ORIGINAL/O-STORE | writerのcleanup判定は不明/未対応schema/組立のみ/失効を採用しない・実削除未接続 | E-S21:証拠選択/失効tombstoneの実disk成功 | D0 | 証拠guardの部分証拠・実削除未確認 | DV-17 |
| FR-14 | AC-FR-14-03 | offline有効記録で整理 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32 | dep(S32)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-14 | AC-FR-14-04 | 外部現在存在を保証しない | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32,S34 | dep(S32,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-14 | AC-FR-14-05 | 実削除と記録一致・一覧保持 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32,S34 | dep(S32,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-14 | AC-FR-14-06 | 削除境界中断・要照合 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32 | dep(S32)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-14 | AC-FR-14-07 | 複数動画別再判定・結果 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32,S34 | dep(S32,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-15 | AC-FR-15-01 | 手動写真保存・実登録・一時解放 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約 | S31,S34 | dep(S31,S34)＋対応A/Q01 | O-PHOTOS | I1 | A1 | D0 | R0 | DV-16 |
| FR-15 | AC-FR-15-02 | 同撮影同版・連打/再試行非重複 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約 | S31 | dep(S31)＋対応A/Q01 | O-PHOTOS | I1 | A1 | D0 | R0 | DV-16 |
| FR-15 | AC-FR-15-03 | 登録直後中断・写真側削除非復活 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約 | S31 | dep(S31)＋対応A/Q01 | O-PHOTOS | I1 | A1 | D0 | R0 | DV-16 |
| FR-15 | AC-FR-15-04 | 回線離脱/復帰・整理順序非強制 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約 | S23,S31 | dep(S23,S31)＋対応A/Q01 | O-PHOTOS | I1 | A1 | D0 | R0 | DV-12、DV-16 |
| FR-15 | AC-FR-15-05 | 複数保存・動画別結果/不明 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約 | S31,S34 | dep(S31,S34)＋対応A/Q01 | O-PHOTOS | I1 | A1 | D0 | R0 | DV-16 |
| FR-16 | AC-FR-16-01 | 全媒体Wi-Fi・local offline再生 | T03/T05/T09/T11/T15/T23;BI-07〜15 | EB,ER,E-S15 | S15,S23,S25 | dep(S15,S23,S25)＋対応A/Q01 | O-IOS-BI/O-CAPTURE | 原本local player実装・全媒体gate/軽量版未接続 | E-S15:33実行成功、custom scheme/外部参照禁止/実進行・解放、回線断未検証 | D0 | ローカル原本の部分証拠、AC全文未達 | DV-12、DV-14 |
| FR-16 | AC-FR-16-02 | REC実停止・保存優先・Mac継続 | T03/T05/T09/T11/T15/T23;BI-07〜15 | EB,ER:契約/部分観測 | S23,S49 | dep(S23,S49)＋対応A/Q01 | O-IOS-BI/O-CAPTURE | I1 | A1 | D0 | R0 | DV-11、DV-12 |
| FR-16 | AC-FR-16-03 | 開始済対象だけ全条件再確認再開 | T03/T05/T09/T11/T15/T23;BI-07〜15 | EB,ER:契約/部分観測,E-S21 | S23,S28,S49 | dep(S23,S28,S49)＋対応A/Q01 | O-IOS-BI/O-CAPTURE | 本人意思/複合待機/試行世代を同writerへ永続化・全媒体gate/SDK未接続 | E-S21:複合待機/取消後成功/古いcallback拒否のdisk成功 | D0 | 再開規則の永続境界だけ部分証拠・実回線/REC/OS未確認 | DV-12 |
| FR-17 | AC-FR-17-01 | 単数対象と消失リスク確認 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33,S34 | dep(S33,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-02 | 明示操作なしの破棄禁止 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33 | dep(S33)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-03 | iPhone対象だけ削除・外部保持 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33 | dep(S33)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-04 | 保存/確認状態の非偽装 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33,S34 | dep(S33,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-05 | 実削除照合と成功履歴 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33,S34 | dep(S33,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-06 | 破棄境界中断・要照合 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33 | dep(S33)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| NFR-01 | AC-NFR-01-01 | 起動/次REC/通信停止の実測 | P18,T23;CF-09,BI-09 | EC,EB:時刻/抑止契約 | S41,S43,S49,S4V | dep(S41,S43,S49,S4V)＋対応A/Q01 | O-CAPTURE/O-IOS-BI | I1 | A1 | D0 | R0 | DV-11、DV-12 |
| NFR-02 | AC-NFR-02-01 | 保存/検証受信/確認の中断 | P09/P19,T10/T18/T21/T22;CF-08,BI-04/05/20/23/29/30/33 | ES,EB,E-S11,E-S12,E-S21 | S12,S21,S24I,S27 | dep(S12,S21,S24I,S27)＋対応A/Q01 | O-STORE/O-ORIGINAL/O-PHOTOS | S12保存/復旧＋S21確認/証拠disk接続済・実HTTP未接続 | E-S12:54実行、E-S21:commit前後中断/reopen、全Unit211有意味成功 | D0 | 保存/連携commit境界の部分証拠・実通信/実機未確認 | DV-02、DV-12、DV-14 |
| NFR-02 | AC-NFR-02-02 | 失効維持・写真直後中断 | P09/P19,T10/T18/T21/T22;CF-08,BI-04/05/20/23/29/30/33 | ES,EB:境界規則とdisk部分,E-S21 | S21,S27,S31 | dep(S21,S27,S31)＋対応A/Q01 | O-STORE/O-ORIGINAL/O-PHOTOS | 同writer失効維持/ACK実装済・Photos未接続 | E-S21:失効前後fault/reopen/非復活成功 | D0 | 失効永続境界の部分証拠・写真直後中断未確認 | DV-14、DV-16 |
| NFR-02 | AC-NFR-02-03 | 不明/失敗と復旧表示 | P09/P19,T10/T18/T21/T22;CF-08,BI-04/05/20/23/29/30/33 | ES,EB:境界規則とdisk部分 | S14,S28,S31,S34 | dep(S14,S28,S31,S34)＋対応A/Q01 | O-STORE/O-ORIGINAL/O-PHOTOS | S14保存/削除不明投影済・Photos/製品UI未接続 | E-S14:44実行成功、read失敗/不明保持部分 | D0 | 部分証拠・Photos/実機未確認 | DV-02、DV-14、DV-16 |
| NFR-02 | AC-NFR-02-04 | 整理/破棄の実削除境界復旧 | P09/P19,T10/T18/T21/T22;CF-08,BI-04/05/20/23/29/30/33 | ES,EB,E-S13:境界規則とdisk部分 | S32,S33,S34 | dep(S32,S33,S34)＋対応A/Q01 | O-STORE/O-ORIGINAL/O-PHOTOS | S13予約/reader基盤接続済・実unlink/UI未接続 | E-S13:50実行成功、予約/reopen部分 | D0 | 基盤部分証拠・削除完了未確認 | DV-17 |
| NFR-03 | AC-NFR-03-01 | 全必須gateの実施と品質適合分離 | P17/P18/P20;CF-02〜10 | EC:部分探索のみ | S41〜S49,S4V | dep(S41〜S49,S4V)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-01、DV-03、DV-04、DV-05、DV-06、DV-07、DV-08、DV-09、DV-10、DV-11 |
| NFR-03 | AC-NFR-03-02 | Log原本・設定/音声/継続品質 | P17/P18/P20;CF-02〜10 | EC:部分探索のみ | S42〜S49,S4V | dep(S42〜S49,S4V)＋対応A/Q01 | O-CAPTURE | I1 | A1 | D0 | R0 | DV-03、DV-04、DV-05、DV-07、DV-08、DV-09、DV-10、DV-11 |
| NFR-04 | AC-NFR-04-01 | 旧MediaVault変換・新規原本転送 | P03/P21,T01/T04/T25/T26;CF-10・AC-CF-11,BI-31/34 | EI:旧隔離部分,E-S20-02/03/04 | N00,S20,H01 | dep(N00,S20,H01)＋対応A/Q01 | main | 旧backend不変snapshotの実I/O/Simulator実配信照合済・新規原本転送/標準変換未接続 | 実SQLite/API20成功、Range/hash/競合/FD終端、Simulator実通信/実再生2成功 | D0 | 隔離/旧配信の部分証拠・標準変換/製品連携/実データ未確認 | DV-13、DV-18 |
| NFR-04 | AC-NFR-04-02 | 対象別許可後のリリース前整理 | P03/P21,T01/T04/T25/T26;CF-10・AC-CF-11,BI-31/34 | E0（旧計画の後続要求のみ） | N00,Q01,H02 | dep(N00,Q01,H02)＋対応A/Q01 | main | I0 | A0 | D0 | R0 | DV-18 |

受入更新時はACの枝条件ごとに証拠・未確認を列挙する。一部証拠しかない行はR=部分証拠あり／未達を維持し、複数操作の1本成功や品質未測定から行全体を達成にしない。全79行の証拠版をH02で照合する。

## CF／BI条件を残す受入対応

以下は旧条件の引渡し先であり、全て受入未評価。AC-CF／AC-BIの原文・母集団を維持し、PRD台帳との両方をH02で照合する。CFのC01〜C19、U01〜U05、B1〜B7と形式・カメラ・fps・補正等の全必須セルはQ01で実行票枝番へ展開し、この表の代表DVだけで縮小しない。

| 旧AC | 主な新task | 実機票・保持する条件 |
| --- | --- | --- |
| AC-CF-01 | S16,S41 | DV-01／02、最小実機操作と実値・保存対応 |
| AC-CF-02 | S41 | DV-01、全カメラ×4K24/30×LT/422/Proxy・実Log・手動 |
| AC-CF-03 | S42 | DV-03、WB最終フレーム・二本 |
| AC-CF-04 | S43 | DV-10、音声4軸・全障害・復旧 |
| AC-CF-05 | S48 | DV-05、標準変換・非焼込み・品質 |
| AC-CF-06 | S44 | DV-04、複数補正・復元・3場面 |
| AC-CF-07 | S47 | DV-08／09、寄る引く・停止・切替 |
| AC-CF-08 | S12 | DV-02、正常／部分／不明／失敗・実復旧 |
| AC-CF-09 | S49,S4V | DV-11、同時成立・応答性 |
| AC-CF-10 | Q01,H02 | 全DV、原因・品質・要求達成を分離 |
| AC-CF-11 | H01,H02 | DV-18、21要求79AC・工程と初期版分離 |
| AC-BI-01 | S23,S24I | DV-12、固定複数対象・動画別結果 |
| AC-BI-02 | S13,S24I | DV-12、確定原本・内容世代・実G2B/G2C |
| AC-BI-03 | S24,S24I | DV-12、最終保存先独立全内容証拠 |
| AC-BI-04 | S24 | DV-12、不一致／書込／commit失敗・不明 |
| AC-BI-05 | S22C,S24I | DV-12、保存各境界と重複抑止 |
| AC-BI-06 | S24I,S28 | DV-12、個別失敗続行／共通待機 |
| AC-BI-07 | S23 | DV-12、全媒体・Tailscale基礎回線・背景 |
| AC-BI-08 | S28 | DV-12、モバイル状態のみ・量／頻度 |
| AC-BI-09 | S49 | DV-11／12、REC実停止・保存優先・Mac継続 |
| AC-BI-10 | S23 | DV-12、全条件再確認・既開始対象のみ |
| AC-BI-11 | S23 | DV-12、本人停止永続・明示再開 |
| AC-BI-12 | S23 | DV-12、全件停止・状態同期分離 |
| AC-BI-13 | S23,S24I | DV-12、取消と後発結果別・再送照合 |
| AC-BI-14 | S23 | DV-12、背景／ロック・OS復帰 |
| AC-BI-15 | S15,S25 | DV-14、取得済offline再生・有効確認保持 |
| AC-BI-16 | S26 | DV-13、標準Rec.709・原本非改変 |
| AC-BI-17 | S26 | DV-13、fps／向き／構図／音声／日時／両端 |
| AC-BI-18 | S25,S27 | DV-14、固定版認証実再生・量／解放 |
| AC-BI-19 | S25,S27 | DV-14、単数途中実再生＋本人操作 |
| AC-BI-20 | S21,S27 | DV-14、確認commit不明・競合 |
| AC-BI-21 | S27 | DV-14、失効前V1維持 |
| AC-BI-22 | S27 | DV-14／15、全受取登録・全必要ACK・全公開経路 |
| AC-BI-23 | S27 | DV-14、失効後非復活 |
| AC-BI-24 | S28 | DV-12／14、携帯で失効commit・媒体取得なし |
| AC-BI-25 | S22C,S28 | DV-15、新登録へ旧確認非復元・通常利用 |
| AC-BI-26 | S28 | DV-15、旧ACK無期限待ち・別動画続行 |
| AC-BI-27 | S32 | DV-17、同一有効証拠・offline整理 |
| AC-BI-28 | S13,S33 | DV-17、破棄実停止／全reader解放 |
| AC-BI-29 | S13,S32,S33 | DV-17、失効先行／削除予約先行両順序 |
| AC-BI-30 | S25,S31 | DV-16、同一完全軽量映像／使用権・結果不明保持 |
| AC-BI-31 | N00,S20 | DV-18、旧媒体／記録保持・移行許可なし |
| AC-BI-32 | Q01 | DV-13、G3事前合意とG5採用・写真最終結合別 |
| AC-BI-33 | S28,S34 | DV-12／14／16／17、永続記録と動画別表示 |
| AC-BI-34 | H01,H02 | DV-18、34BI・79PRD・部分証拠と未実施 |

## 実機実行票と受入タスク（A01〜A18／DV-01〜DV-18）

全AタスクはStatus=pending、実機軸D0、受入R0。Ownerはmain（票・結果・追跡）＋本人（実機操作／品質判断）。Filesは本tasklistと合意したrepo外証拠先だけ、修正が必要なら対応本体taskを再開して具体workerを割り当てる。Doneは列挙したAC全文・旧ケース母集団への実施証拠と適否・不足・再試験の記録が揃うこと。試験を実施しただけでPRD達成や方式採用にしない。必要操作／品質条件が未束縛、実装未接続、証拠取得不能なら当該ケースを止め、独立ケースを進める。

H01で各票に `runID=DV-xx/実装版/case/repetition`、`sourceRevision＋dirty差分hash`、`buildID`、`端末匿名ID／機種／容量／OS／空き容量／署名`、`撮影・変換・評価設定版`、`対象clip匿名ID／内容世代／digest／版／登録世代`、`接続先匿名ID／回線`、`vaultID／証拠キー`、`担当／予定日／実施日`、`中断位置／方法／反復数／時計対応と誤差`、`品質合意ID・条件版`、`既存操作許可ID／追加対象別許可ID`、`実装状態／実施可否／結果／再試験ID` を束縛する。現時点の実値は未確定でQ01が実施直前に確定する。適用しないフィールドは理由付き対象外とし、空欄で実施しない。私的パス対応表・媒体・顔画像・秘密はrepo外に置く。

Q01は各票を個別に束縛できる。全18票の束縛完了や全前段実機合格を個別票の開始条件にしない。品質行では場面・組合せ・比較・測定・許容範囲を必ず実施前に合意する。新規非私的試験媒体を基本とし、旧媒体削除・端末容量埋め・既存アプリ削除を前提にしない。

H01では各AC全文の正常・拒否・不明・失敗・順序・対象組合せを `DV-xx/case枝番` に分け、根拠AC／枝条件→操作→期待結果→証拠→必要task／substatusを記録する。同じ枝番が複数ACを支えても各条件との対応を残し、79ACのIDや受入条件を追加・置換しない。以下のA12／A14／A17の枝番は必須の展開例であり、他の枝条件・旧ケースを省略する根拠にしない。Q01で環境値・品質条件・操作許可・再現方法を枝番ごとに確定し、欠ける枝番だけ止める。実施済み枝番の部分証拠と票全体のdone／PRD達成は分け、参照先A票全体のdoneを当該証拠の引渡し条件にしない。

### A01 / DV-01 形式・手動設定

- [ ] Status: pending
  - Depends: S41,S43,Q01。当該形式候補のSDK接続。
  - 関連AC・gate: AC-FR-01-01〜04、AC-CF-01/02、撮影D01/C-G03・B-G2B。
  - 対象・操作: 1. カメラ／Log／形式／補正の実能力表を取得。2. 標準4K24/30とLT/422/Proxyの全実行可能必須セルで音声付き撮影。3. 手動値を変更し停止、原本検査、再起動・復元して再撮影。4. 原本の写真非追加を照合。
  - 期待結果: 希望／能力／実値／保存形式が対応、無断代替なし。未対応理由が分かり実原本と音声を確認。
  - Verify / 証拠: 能力表、適用値・時刻、実原本と特性、写真側非追加、実機方式の採否根拠。
  - 事前合意・Stop: 対象セル・手動値・新規媒体操作。品質はC-G04条件版。未対応を環境不足と区別。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A02 / DV-02 保存・復旧

- [ ] Status: pending
  - Depends: S12,S41,S43,Q01。当該実録画はA01の方式観測後。
  - 関連AC・gate: AC-FR-10-02、AC-NFR-02-01/03、AC-CF-08、B-G2A/G2B/G4。
  - 対象・操作: 1. 正常停止を保存・再起動照合。2. 記録終端／ファイル確定／意図・結果commitの許可した境界で中断。3. 再起動して実原本・管理記録・一覧を照合。4. 合意した端末保護条件で同じ照合。
  - 期待結果: 正常／部分／不明／失敗を分け、存在だけで正常にしない。未知／破損でも証拠保持。
  - Verify / 証拠: 境界時系列、前後ファイル／store対応、保護条件・画面、G2A非実機証拠との差分。
  - 事前合意・Stop: 中断方法・位置・対象。実容量埋め／実データ削除は行わない。救済成功を保証しない。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A03 / DV-03 WB

- [ ] Status: pending
  - Depends: S42,Q01,A01の該当記録経路。
  - 関連AC・gate: AC-FR-04-01〜03、AC-CF-03。
  - 対象・操作: 1. Auto安定前にREC。2. 録画中に本人が再固定、他手動値も記録。3. STOP直後に待機Autoを確認し次の1本。4. 最後の記録フレームまで設定と色を照合。
  - 期待結果: 安定待ちなし、本人操作のみ再固定、最終フレームまで固定、次clip新測定、他設定不変。
  - Verify / 証拠: 原本フレーム・WB実値・時刻、色変化／音声／継続。
  - 事前合意・Stop: シーン・再固定操作・色変化／継続の品質条件を事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A04 / DV-04 補正

- [ ] Status: pending
  - Depends: S44,S47,Q01,A01の該当形式。
  - 関連AC・gate: AC-FR-03-01〜05、AC-NFR-03-01〜02、AC-CF-06。
  - 対象・操作: 1. OFFと複数モードを選び読戻し。2. 歩き／静止手持ち／ゆっくりパンを同条件で撮影。3. 再起動・条件変更で復元と非対応案内。4. ズーム／切替を重ね画角と補正を照合。
  - 期待結果: 表示と実補正一致、復元条件・非対応説明、予告への画角反映、音声同期・継続。標準不成立は未達。
  - Verify / 証拠: 比較原本、モード／実値／画角／同期／継続、組合せ表。
  - 事前合意・Stop: 各組合せと3場面、画角・補正効果・継続の許容範囲を事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A05 / DV-05 固定Rec.709表示

- [ ] Status: pending
  - Depends: S48,Q01,A01の採用Log・適合資材。
  - 関連AC・gate: AC-FR-02-01〜02、AC-CF-05、撮影D02。
  - 対象・操作: 1. 入力Log・標準資材由来／版を照合。2. 待機／録画で標準表示。3. 同じ保存Log原本と画面を比較。4. 録画と描画を重ね負荷・確認状態を観測。
  - 期待結果: 実標準Rec.709、原本非焼込み・二重変換なし、録画と描画両立、軽量版確認非生成。
  - Verify / 証拠: 資材・入力条件、画面と原本、描画／記録観測。
  - 事前合意・Stop: 資材利用条件・実Log適合、表示／録画品質の事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A06 / DV-06 人物AF

- [ ] Status: pending
  - Depends: S45,Q01,A01の該当制御経路。
  - 関連AC・gate: AC-FR-05-01〜05。
  - 対象・操作: 1. 複数露出対象と一人主役を選択。2. 主役前後移動・退出／同一復帰・別人通過・保持期限超過・再指定。3. 追跡OFFで人物優先AF。4. 人物なし・検出未完了RECを確認。
  - 期待結果: 通常合焦・前後追従、同一主役再捕捉、別人自動移行なし、OFFは固定でなく人物AF、REC非阻害。
  - Verify / 証拠: 対象／距離／光／移動・保持設定版、主役状態と原本・合焦記録。
  - 事前合意・Stop: 人物なし方式／初回意図の未合意部分、保持時間、距離・照明・移動と品質を事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A07 / DV-07 ND

- [ ] Status: pending
  - Depends: S46,Q01,A01/A03の該当設定事実。
  - 関連AC・gate: AC-FR-06-01〜04、AC-FR-01-03。
  - 対象・操作: 1. 濃く／薄く／両立困難の合意場面を撮影。2. 太陽・反射・黒を加える。3. WB・手動値・露出対象を変更。4. 解析遅延／停止時の旧表示とREC継続を確認。
  - 期待結果: 方向／理由が本人判断に有用、不確かなら保留し旧OK失効。飽和から精密量を捏造せずREC可能。
  - Verify / 証拠: 場面・本人判断・案内／根拠・時刻／世代・原本。
  - 事前合意・Stop: 代表例・露出意図・評価方法／許容条件、有効期間等の設定版を事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A08 / DV-08 ズーム

- [ ] Status: pending
  - Depends: S47,Q01,A01/A04の該当カメラ・補正。
  - 関連AC・gate: AC-FR-07-01〜03、AC-CF-07、AC-DI-11/12。
  - 対象・操作: 1. 目標選択して予告中の実倍率を記録。2. 寄る／引くを開始し目標自動停止。3. 再操作で途中停止、録画は継続。4. 待機／録画・補正・停止候補有無を変え予告と実画角・画質を比較。
  - 期待結果: 予告倍率不変・非焼込み、ズーム停止とREC停止別、目標超過せず停止、根拠ある近傍支援。
  - Verify / 証拠: 操作動画、実倍率／camera／補正、予告／原本、停止前後画質、暫定／採用設定版。
  - 事前合意・Stop: 速度・停止精度・吸着許容差・滑らかさ・画角差・画質・負荷の事前条件。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A09 / DV-09 レンズ・ISO

- [ ] Status: pending
  - Depends: S47,Q01,A01/A04の対応経路。
  - 関連AC・gate: AC-FR-08-01〜03、AC-CF-07。
  - 対象・操作: 1. 録画中の対応切替と戻し。2. 手動ISO変更後にも同じ操作。3. 非対応条件／補正維持不能を選択。4. 前中後の映像音声と実値・時刻を比較。
  - 期待結果: 切替中だけ限定補正、以後保持、常時Autoなし。他設定無断変更なし、非対応無通知実行なし。
  - Verify / 証拠: 前中後の原本／音声／実値／時刻、戻り基準と制御版。
  - 事前合意・Stop: 戻り／手動変更後ISO基準・上限・方式未合意を解消し、連続性・品質条件を事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A10 / DV-10 音声・障害

- [ ] Status: pending
  - Depends: S43,S12,Q01,A01の該当記録。
  - 関連AC・gate: AC-FR-09-01〜04、AC-CF-04。
  - 対象・操作: 1. 通常音と静寂で待機／録画。2. 合意した権限・入力・書込障害を各段階へ。3. 停止と保存分類を照合。4. 有限復旧・失敗後導線と本人RECを確認。
  - 期待結果: 音量／入力／到着／書込別、静寂正常、確認済み障害で抑止／停止、部分／不明／失敗を分け、復旧後も自動RECなし。
  - Verify / 証拠: メーター・入力・到着／書込・保存音声、障害／復旧時系列。
  - 事前合意・Stop: 障害再現方法・猶予／上限・復旧範囲の事前確認、必要な品質条件。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A11 / DV-11 起動・次REC・負荷

- [ ] Status: pending
  - Depends: S49,S4V,Q01。単独開始測定はS41/S43から可。
  - 関連AC・gate: AC-NFR-01-01、AC-NFR-03-01〜02、AC-CF-09。
  - 対象・操作: 1. 初回権限／通常起動／復帰を別測定。2. 連続撮影の次RECを測定。3. 通信・解析・表示・保存を重ねREC。4. 通常利用内の熱／空き容量を記録。
  - 期待結果: 2〜3秒目標と制約を把握、音声省略・無断設定変更・自動削除なし。安全な継続。
  - Verify / 証拠: 操作→実記録の時計対応・設定・温度／容量の取得可能範囲・原本。
  - 事前合意・Stop: 組合せ・負荷・反復と品質。端末容量埋め／極限温度の推測合格なし。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A12 / DV-12 通信・背景

- [ ] Status: pending
  - 先行引渡し E-S20-04: N01 Simulator→Mac loopbackの認証/固定Range/実再生/停止・解放が成功。checkpoint04の版/config/source/2case/9端末JSON/サーバー終端を保全済み。実Wi-Fi/Tailscale・cellular切替・背景/ロック・REC負荷を観測していないため本票の代替にしない。Range毎全hash/能力照会とSQLite所有thread解放の改善版はS27等の最終版に束縛して再評価する。
  - Depends: Q01と下記caseの直接依存。通信・背景case（c01）はS24I,S28、REC／保存を重ねる枝番だけS49を追加。確定した実原本を転送する枝番はA01/A02の当該原本のG2B＋S13/G2C証拠を参照し、両票全体のdoneを待たない。入口拒否（c02）・取消後発結果（c03）は下表で分ける。
  - 関連AC・gate: AC-FR-11-01〜04、AC-FR-16-01〜03、AC-BI-01〜14/24、B-G1/G2C。
  - 対象・操作（c01）: 1. 許可隔離先でLAN、外出Wi-Fi＋Tailscaleへ接続。2. 原本／軽量版／stream／thumbnail各経路で回線離脱・復帰、背景／ロック。3. REC／保存と本人停止／再開／取消／全件停止を重ねる。4. 再起動し固定集合・最終保存全内容・状態のみ携帯同期を照合。c02／c03も別枝番で必ず実施する。
  - 期待結果: 媒体cellular移行なし、実停止／全解放・保存優先、全条件後に既開始だけ再開。背景を前景で代用せずMac既開始処理継続。
  - Verify / 証拠: 回線／転送量／callback／実停止／handle解放、動画別結果・全内容hash・OS条件。
  - 事前合意・Stop: 接続先／listener／実回線・試験媒体／背景操作を確認。REC ACK待ち非追加、品質負荷条件。未束縛条件はQ01、未接続は対応本体taskへ戻す。

| case／根拠 | 直接依存・操作 | 期待結果 | Verify／証拠 |
| --- | --- | --- | --- |
| DV-12/c02 原本入口拒否／AC-BI-02 | S13,S24Iと対象状態のUI接続・検証。書込中の再現だけS41の該当経路を追加。許可試験原本に書込中／保存不明／検査不足／アクセス不能の各状態を用意して転送操作する。正常G2B成立を拒否caseの前提にしない | 正常保存済みとして転送・検証成功へ進まず、別ファイルで代替しない。未確定理由と原本を保持 | 原本状態・対象identity・操作・拒否理由、送受信記録、前後実ファイル／store／表示。障害再現方法と実機で観測できた範囲を記録 |
| DV-12/c03 取消後のMac成功／AC-BI-13 | S24I,S28の実接続・検証。許可隔離先で成功応答を遅延し、本人取消→Mac成功到着→新しい本人操作による再実行の順を作る。REC重畳なしならS49不要 | 依頼終了とMacの実結果を分け、原本を削除しない。過去結果照合後に必要な処理だけ行い、無条件全量再送・新登録をしない | 取消／成功応答／再操作の時系列、操作・登録・原本identity、再照合と送信byte、原本保持、動画別結果と永続記録 |

### A13 / DV-13 軽量版品質

- [ ] Status: pending
  - Depends: S26,Q01。採用実LogはA01、品質G3合意後。
  - 関連AC・gate: AC-FR-12-01〜03、AC-BI-16/17/32、撮影D02・B-G3/G5。
  - 対象・操作: 1. 許可された採用Log素材と標準資材を照合。2. 縦横／24・30fps・肌／空／暗部／細部／動き／音声を候補変換。3. 本人通常サイズ／通常再生で色と圧縮劣化を別比較。4. 許容候補の容量／取得時間を比較して採用版を記録。
  - 期待結果: 原本不変・実Rec.709、fps／構図／向き／音声／日時／開始終端／同期維持。別高品質版を製品へ追加しない。
  - Verify / 証拠: 資材版／変換条件、入力出力照合、本人比較・採用理由・取得量／時間。
  - 事前合意・Stop: G3素材・表示条件・比較方法・許容範囲を試験前合意。旧MediaVault使用範囲はNFR-04、写真最終結合はDV-16。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A14 / DV-14 再生・確認・失効

- [ ] Status: pending
  - 先行引渡し E-S20-04: 30秒合成Movieの認証Range→AVPlayer進行/decoded frameと実停止/drain/ネット終端は成功。音声はtrack存在＋SDK進行まで、聴取・Rec.709品質・明示確認/ACKは未確認。S21の永続確認/失効証拠と同一製品経路へ接続するS25/S27/S28の義務を保持。
  - Depends: Q01。原本再生case（c01）はS13,S15,S16とA01/A02で保存対応を確認した当該実撮影原本。軽量版・確認／失効case（c02）はS25,S27,S28、製品軽量版を評価する枝番だけA13の当該採用版を追加。c01はS25／S27／S28やA13完了に依存しない。
  - 関連AC・gate: AC-FR-10-01/03、AC-FR-13-01〜06、AC-BI-15/18〜24。
  - 対象・操作（c02）: 1. 公開版を途中まで実再生し本人確認。2. V2候補生成／失敗とV1維持を確認。3. 失効commit前後・ACK・公開の各境界で切断／再起動、遅延要求を注入。4. 同一版再取得・offlineと一時buffer解放を照合。製品Libraryからの実原本再生はc01で別に実施する。
  - 期待結果（c02）: 版固定、実再生＋本人操作＋commitのみ確認。失効前V1維持／失効後非復活、全必要ACK前に差替なし。全編／写真保存強制なし。
  - Verify / 証拠（c02）: 版／登録／世代・commit／ACK／公開時系列、実byte・再生・buffer／解放・画面。
  - 事前合意・Stop: 対象／中断方法、c02は各登録・製品軽量版の標準変換品質採用版。fixture技術試験と製品受入を別runに。未束縛条件はQ01、未接続は対応本体taskへ戻す。

| case／根拠 | 直接依存・操作 | 期待結果 | Verify／証拠 |
| --- | --- | --- | --- |
| DV-14/c01 実撮影原本の製品再生／AC-FR-10-01、AC-BI-15 | 上記c01の依存だけで、製品Libraryから保存対応済みの実撮影原本を1本選び、映像・音声の進行、途中停止、再起動後の再選択、Wi-Fiなしのローカル再生を行う | 対象原本と再生媒体が一致し実再生・停止・lease解放できる。原本閲覧だけで軽量版の確認や写真保存状態を生成せず、ネット接続を原本再生の条件にしない | clip／内容世代／digestと保存証拠、製品Library→playerの操作、実映像・音声進行、停止／解放・offlineの観測、前後の独立状態。合成fixtureのS15証拠とは別run |

### A15 / DV-15 新登録・旧登録

- [ ] Status: pending
  - 先行引渡し E-S22-01: server destination/intent/registration/世代/秘密を実SQLiteへ束縛し、同意図再送・応答欠落後再open・新登録と旧資格情報分離を新規26caseで確認（全46成功）。wire/copy/diffを保全。端末commit/KeychainはS22C、旧確認/必要ACK/公開との製品接続はS27/S28へ残し、実再登録受入には昇格しない。
  - Depends: S22C,S27,S28,Q01。
  - 関連AC・gate: AC-BI-25/26、AC-FR-13-04。
  - 対象・操作: 1. 許可方法で新登録条件を用意し通常再起動と比較。2. 旧確認を照合し新端末で通常一覧／取得／再生。3. 応答不能旧登録を必要ACK集合へ残し差替要求。4. 別動画処理と新確認後の整理候補を確認。
  - 期待結果: 旧確認を新登録へ復元せず、旧ACKを代用しない。該当差替だけ保留、通常利用・別動画継続。
  - Verify / 証拠: 接続先／登録世代、配布／必要ACK／公開、再確認対象と別動画結果。
  - 事前合意・Stop: 登録変更の対象／方法。既存App削除・データ初期化を前提にしない。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A16 / DV-16 写真保存

- [ ] Status: pending
  - Depends: S31,Q01、S34の写真操作の実接続・必須検証の部分引渡し。S34の整理／破棄完了は不要。製品同一軽量版caseはA13/A14の当該版identityと証拠を使い、両票全体のdoneは待たない。
  - 関連AC・gate: AC-FR-15-01〜05、AC-NFR-02-02〜03、AC-BI-30、AC-DI-09/10。
  - 対象・操作: 1. 保存時初回追加権限・拒否を試し撮影導線も確認。2. Photos登録直後／管理commit前に合意手段で中断。3. 理由付き読取案内・拒否・限定・未発見を照合。4. 連打／再試行・複数保存・試験写真側削除後を確認。
  - 期待結果: 追加と読取を適時分離、不明は要確認・無条件再追加なし、写真側削除を自動復活しない。映像／日時／音声が同一、不要copy解放。
  - Verify / 証拠: 権限遷移・意図／結果／対応記録、写真再生／日時／音声・重複有無・tmp解放。
  - 事前合意・Stop: 試験媒体だけの写真側操作、実権限変更／中断方法。アルバム／手動再保存の未合意は採用しない。未束縛条件はQ01、未接続は対応本体taskへ戻す。

### A17 / DV-17 容量整理・破棄

- [ ] Status: pending
  - Depends: Q01、整理caseはS32＋S34の整理操作、破棄caseはS33＋S34の破棄操作の実接続・必須検証の部分引渡し。S31／S34写真や他方の削除操作全体の完了は不要。実原本はA01/A02の当該保存対応、有効証拠を使う整理caseだけA12の保存検証・A14の有効確認の当該runを追加。失効競合の枝番はS27の該当経路・検証も必要。参照A票全体のdoneを待たない。
  - 関連AC・gate: AC-FR-14-01〜07、AC-FR-17-01〜06、AC-NFR-02-04、AC-BI-27〜29、AC-DI-06〜08。
  - 対象・操作: 1. 別途許可した試験原本でoffline複数整理（c01）と未転送単数破棄（c02）。2. 各操作のreader／writer競合で実停止・全解放を確認。3. 失効先行／削除予約先行の両順序を試す。4. 意図／unlink／結果commit各境界を中断・再起動し実ファイルと一覧／履歴を照合。下記c03〜c05も分けて実施する。
  - 期待結果: 対象だけ実削除、整理は毎本条件再判定、破棄は単数リスク確認。整理後通常一覧・成功破棄だけ履歴、不明要照合・未実行非自動削除。整理／破棄によるMac／写真の連動削除なし。外部消失再現caseは事前状態と本操作の影響を分ける。
  - Verify / 証拠: 本人意思、前後実ファイル／store、orderingと失効ACK順序、一覧／履歴、外部媒体保持。
  - 事前合意・Stop: 削除対象・方法を実施前に別途明示合意。管理記録消去・容量埋め・原本trash化をしない。未束縛条件はQ01、未接続は対応本体taskへ戻す。

| case／根拠 | 直接依存・操作 | 期待結果 | Verify／証拠 |
| --- | --- | --- | --- |
| DV-17/c03 無効証拠の整理拒否／AC-FR-14-02、AC-BI-27 | 整理操作の部分引渡しと許可試験原本。記録／対応の不明・欠落・失敗・失効、別内容を枝分けし、online／offlineで整理操作。未変換Log確認・旧削除候補状態・再生成功だけの状態も確認。有効な保存検証・確認を持たない枝番にA12/A14の成功を前提追加しない | 全枝で整理不可。証拠を昇格せず、原本を削除せず、破棄へ自動移行しない | 状態の準備方法・根拠、対象内容と証拠の対応、拒否理由、前後ファイル／store／画面。状態の障害注入と製品事実を区別 |
| DV-17/c04 外部現在存在を非保証／AC-FR-14-04 | 整理操作の部分引渡し＋A12/A14の当該有効証拠。端末をofflineにした後、別途明示許可した隔離先の試験原本だけで外部消失を再現し、端末へ未取得のまま整理。外部操作の対象・方法が未許可なら本枝番だけ未実施 | 最後の有効記録に基づく整理を許容し、現在のMac原本存在を再確認・保証した表示にしない。再接続・再生・写真保存を強制しない | 最後の有効証拠と取得時点、端末offline、外部消失の対象別許可・実行時系列、端末の未取得状態と表示、ローカル削除照合。外部消失を整理の連動削除と混同しない |
| DV-17/c05 混合集合・一部失敗／AC-FR-14-07 | 整理操作の部分引渡し。適格原本と不適格原本を同じ選択候補に用意し、選択可否と開始時固定集合を確認。適格な複数対象の一部へ許可した失敗／中断を与え、実行直前の失効等も枝分け。有効証拠は当該原本のA12/A14のrunを使用 | 不適格を除外または実行時拒否し、複数選択で確認済みにしない。各対象直前に再判定して不適格は非削除・破棄非移行。成功／失敗／不明／未処理を動画別に表示し、未実行を自動削除しない | 固定集合・選択可否・動画別直前証拠、失効／失敗／中断の時系列、各実ファイル・store・通常一覧、再起動後の結果・必要な確認 |

### A18 / DV-18 実データ範囲・全AC照合

- [ ] Status: pending
  - Depends: N00,S20,H01,Q01。各caseの実施可能範囲、実転送はA12。
  - 関連AC・gate: AC-NFR-04-01〜02、AC-CF-11、AC-BI-31/34、全79AC。
  - 対象・操作: 1. 対象／許可／経路を一覧化し旧MediaVaultは変換／preview、新規FrameRelay原本は転送へ限定。2. 前後保全と実施結果を各ACへ対応。3. リリース前整理の具体対象・方法・影響を提示し別明示合意。4. 合意後の対象だけ整理し結果・未実施／再試験を記録。
  - 期待結果: 許可範囲を逸脱せず未実施／不適合を残す。旧写真原本削除・汎用移行を前提にせず、整理の未許可を成功にしない。
  - Verify / 証拠: 対象／許可ID／操作、前後保全、79AC証拠対応、整理対象・方法・結果、未確認一覧。
  - 事前合意・Stop: 実データ削除／上書き・本番DB移行・デプロイは別許可。後二者は本計画スコープ外。未束縛条件はQ01、未接続は対応本体taskへ戻す。

## 検証証跡・レビュー記録

| 証拠ID | 日付・担当 | task／AC／DV | 実装版・条件版・環境 | コマンド／操作・対象 | 結果・件数・skip・診断 | 証拠参照・未確認・再開条件 |
| --- | --- | --- | --- | --- | --- | --- |
| PLAN-01 | 2026-10-01、feature_planner／main | 計画3文書 | confirmed仕様・現行コードのread-only調査 | 要求／依存／所有／ID／リンクの静的照合、差分保全 | 計画照合済み: PRD79行／一意79、旧P21＋T28、CF11・BI34・DI18、DV18、task69件。未定義task参照・記名依存循環・相対リンク切れ・空白エラー0。mainのbaseline比較で既存151ファイル不変、新規は本3文書だけ。実装試験は未実施 | 本3文書、main保管の開始時baseline。旧証拠の現存はN00で確認 |
| PLAN-02 | 2026-10-01、feature_planner | S13／S31／S34／S3V、H01／Q01、A12／A14／A16／A17 | ユーザーのレビュー指摘修正依頼・同じconfirmed仕様 | design／tasklistの限定差分と正本条件、所有・引渡し・case別直接依存、ID／状態／相対リンクを静的照合 | Photosと削除の独立先行、内容対応の単一writer引渡し、実機票の枝条件を明確化。PRD79行／一意79・既存task ID／状態・PLAN-01を保持、requirements変更なし、相対リンク切れ・行末空白0。実装・build/test・実機・独立実装検証は未実施 | 修正はdesign／tasklistの2文書。Q01の実値・品質条件と旧証拠現存確認は未実施のまま保持 |

本体検証ではproject/workspace・scheme・configuration・destination・Build/Test action・対象test、source revision＋dirty hash、実コマンド、結果bundle／ログ、実行件数を記録する。隔離通信は実効DB／root／worker／port等の匿名参照を添える。実行不能は理由・対象・未確認範囲・代替で確認した範囲・再開条件・担当を記録する。秘密や私的パスを転記しない。

| Review ID | task・差分版・対象 | 確認者 | 指摘・対応・残件 | 証拠・判定 |
| --- | --- | --- | --- | --- |
| V-REVIEW-S11 | `S11-test-02-sources.json` のLocalStore2件・TransactionBoundaryTests1件 | main | 読取非破壊migration、両commit境界、再open、所有を確認。test-01警告をtest-02で解消、実機耐久性は未確認のまま | E-S11-01/02、diff確認済み。独立validationではない |
| V-REVIEW-S12 | `S12-test-02-sources.json` の7件 | main | 同writerの全record snapshot、実存在と保存分類分離、意図→副作用→結果、復旧時非再実行を確認。S13/S16/S41未接続を明記 | E-S12-01/02、`S12-main-scope-review.json`、独立validationではない |
| V-REVIEW-S13 | `S13-lease-02-sources.json` の15件 | main | opening中のrelease競合を差戻し後、実open終端/close/commitと同サイズ変更拒否を確認。S21/S23/S32の局所残件を保持 | E-S13-STORE/LEASE、`S13-main-scope-review.json`。10月4日再開時hash不一致0、独立validationではない |
| V-REVIEW-S14 | `S14-test-04-sources.json`、Library8件＋共有3件＋test fixture1件 | main | 同writer投影と解決済み削除purpose、対象別抑止を確認。全動画抑止/予約欠落fixture/FD存命中cleanupを修正。製品入口とV-UIはS16へ | E-S14-01/02、`S14-main-scope-review.json`、独立validationではない |
| V-REVIEW-S15 | `S15-test-04-sources.json`、player/loader/model/view/test＋LibraryCommand注釈の6件 | main | 実SDK進行/外部参照禁止/読取実drain、解放不明保持を確認。巻戻し位置停滞を修正し実pause/seek/resume試験追加。製品入口はS16へ | E-S15-01/02、`S15-main-scope-review.json`、独立validationではない |
| V-REVIEW-S16部分 | `S16-ui-07-sources.json`、`S16-post-ui-02-sources.json`、Composition/入口/player/UI | main | fixed root/単一writer接続・seed分離・破損保持・停止/解放導線を確認。最新UIは必須監査と再生待ちが失敗、部分成功と未到達を分離して保持 | E-S16-UNIT/SEED/POST-UI/POST-UI-02、通常UI4成功・最大一覧操作1成功、全体blocked。独立validationではない |
| V-REVIEW-S21 | `S21-test-04-sources.json`、core21＋library2 source | main | R01〜05修正と同writer/replay/旧schema/配布観測/ACK consumerを実diskで確認。test-01/02 compile、03 async dispatch失敗を保持し04で解消。実OS/通信/cleanup consumer未接続を分離 | E-S21-01/02、211有意味実行・新規26成功、`S21-main-scope-review.json`。独立validationではない |
| V-REVIEW-S20 | checkpoint04のsupport9件/copyとSwift probe2件、S20-listener-004-sources | main | exact loopback/期限/secret/終端/実行版を確認。01失敗/02成功/03負荷/04実通信を区別、App/project変更なし。旧runner copy欠落とSQLite他thread残存の限界を保持 | E-S20-02/03/04、preparation-004/listener-004-parent-result、source差分0/2case成功。独立validationではない |
| V-REVIEW-S22 | checkpoint d496b675、overlay8件＋限定runner/準備helper | main | 独立migration ledger/同DB atomic登録/旧receipt/credential保持、R01全field検証修正、明示46件・guard/source不変を確認。App/project変更なし、外部未反映と端末未接続を分離 | E-S22-01、S22-main-scope-review、46case成功。独立validationではない |

## 振り返り・引渡し

- 計画作成日: 2026-10-01。実装完了日・実機工程完了日・PRD受入達成日は未確定。
- 残る判断: 実機方式・能力、資材適合、品質条件／採用、人物なしAF／初回意図／ISO基準等、実環境・対象別操作。各task／Q01へ局所対応し、4段階の合意を未確定へ戻さない。
- 今回は本steeringに従いコードとM01〜M06の永続文書を更新する。入力仕様・旧steering・README・memoを保全し、既存未追跡コードはbaselineを保持した加算変更に限る。PLAN-01の「3文書だけ」は計画作成時点の記録である。
- 実装は今回の明示 `$implement-steering .steering/20260929-device-independent-implementation/` で進行中。実装後の独立検証は同じpathを明示する `$validate-implementation` を別途案内し、自動開始しない。
