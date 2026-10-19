# Tasklist — 実機なし先行実装の4段階

## 状態と実行規則

2026-10-01、明示 `$prepare-steering` で計画作成後、明示 `$implement-steering` で実装を開始した。各taskの状態・証拠は以下を正本とする。`pending → in-progress → done / blocked / cancelled` を使い、書込みは原則1件ずつ進める。状態・所有・実行版・証拠・残件はこのファイルへ都度同期し、設計変更時だけrequirements／designも更新する。

今回の明示入力は `$implement-steering .steering/20260929-device-independent-implementation/`。N00で担当と現行正本を確定済み。旧撮影／backend tasklistは過去実績と元の受入義務の参照元とし、今回へ引き渡した作業を旧台帳でも並行実行しない。旧文書未更新期間も新confirmed仕様の限定差分と本計画の開始条件を適用する。旧Ideas／旧steeringの実更新はM07〜M10の別明示Workflowに残し、その待ちを独立コードの一括停止条件にしない。

全タスクは [requirements](requirements.md) と [design](design.md) の安全・所有・検証規則を継承する。役割名は予定担当であり、N00で具体agentを束縛する。同じファイルを同時所有せず、他者の差分を戻さない。実機・G1・G2B・段階全体の未完了を、記載されていない依存として追加しない。各タスクの必要試験が失敗／未実行なら当該taskをdoneにせず、理由・不足事実・影響・独立して進めるtask・再開条件を記録する。

Start／Finishを分けたタスクは、N01等のStartが満たされれば独立部からin-progressにできる。substatus（規則／SDK候補／UI／実接続／検証）の各状態・所有・証拠を記録し、Finishが不足すればtask全体のdoneは保留する。別独立タスクへ移る時は残件と再開条件を明記する。

全本体タスクの共通Verifyは、対象diff・意味ある関連単体試験・必要build／診断・実I/O／UI確認・mainレビュー（V-REVIEW）である。下記Verifyは追加する具体試験。共通Stopは、所有衝突、無断要求変更、禁止動作、実データ範囲不明、必要検証失敗。外部依存・ツール追加、重大未合意方式、実データ消失操作が必要になれば該当箇所だけ保留する。軽微可逆判断は記録して進め、段階ごとの再承認を要求しない。

## 現在の再開点（2026-10-18、S47独立部分実装・必要検証完了、ISO本人判断待ち）

- **S47 / blocked（ISOの本人判断・通常経路への注入待ち）**: 目標選択→構図予告→開始→目標/途中停止、ズーム停止と録画停止の分離、実SDK由来の停止候補・版付き暫定設定をS41/S44へ接続した。対応レンズ制御・限定ISO・手動優先・切替後保持・実値表示の本体と注入試験も完了。ISO基準/上限案は未回答のため通常Factoryはpolicy=nil、レンズ切替は理由付き無効のままとする。
- **E-S47-01**: 最終final-test-09で全Unit365宣言/496展開ケース成功、17skip、失敗0、通常撮影UI3件成功。Simulator test buildとgeneric iOS署名なしbuild成功。最終220入力はtest/iOSbuild/現物で一致。初期compile失敗・新fixture失敗/中断も `evidence/20261018-s47/` に保持した。
- **保全・所有**: 開始時7599fileを基準に既存10file変更・新10file、削除/所有外変更/旧証跡変更0を確認。worker2名はコード/testの所有を分離、document_authorは関連永続2文書、mainはtasklist/証跡/構成確認/実行検証/最終diffを担当。doc_reviewer指摘なし。Simulator保存設定は開始時hash一致。
- **残件・再開条件**: 提示済み案は「最後の本人指定ISOとその時のF値を基準、F比の二乗、基準±1段と機器範囲の共通部分、切替後固定、手動変更で基準更新」。本人判断後に同じS47の通常注入・関連Composition/UI検証を行う。実カメラdestinationがなく、DV-08/09の停止精度/画角・crop/画質・負荷/露出保持/映像音声連続性は未確認。S48以降・他task・全steering受入は進めていない。独立validationは同じsteeringへの明示 `$validate-implementation` で別途実施し、今回のmain確認では代行しない。

### 前回のS46製品接続完了記録（履歴）

- **S46 / done（本人合意・製品接続・自動検証範囲）**: 「2はOK」と、端末内リアルタイム解析の古い案内を失効させる期限でバックエンド非依存と説明後の「OK 理解 よろしく」を受領。入力観測から暫定1秒と交換可能な未校正基準による方向/理由の参考表示を合意し、通常Factoryから同一policyをNative/coordinatorへ接続した。NDをRECの阻害条件にしない。
- **E-S46-02**: test-02のUnit26宣言/34展開＋通常UI1件が全成功。Simulator test buildとgeneric iOS署名なしbuild成功、失敗/skip/runtimeWarnings/compiler/analyzer 0。最終210入力はtest-02・ios-build-01・現物で一致。初回test-01の新規test macro隔離compile失敗/0件も保持。証跡 `evidence/20261018-s46-approved/`。
- **保全・所有**: 開始時7503file/165,634,783bytesをhash照合し、既存10file変更/7493不変＋新規Composition test1file、削除/所有外変更/旧証跡変更0。mainはsteering・証跡・最終diff、worker s46_implはコード/test6file、document_author s46_docsは関連永続2文書を所有。doc_reviewer指摘なし。開始時copyとraw xcresultは `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-s46-approved-20261018-x4qojjkd/`。
- **残件と次工程**: 実カメラdestinationなし。実入力/実WB KVO/連続Autoでの保留/実ROI・crop/実写方向/黒・反射/品質・負荷・数値採用はDV-07、FR-06受入は未確認。独立validationは同steeringへの明示 `$validate-implementation` で別途実施する。S47以降・他task既知残件は今回進めていない。

### 前回のS46本体・注入試験記録

- **E-S46-01**: 通常構成の関連Unit48宣言/64展開、修正後ND16宣言/22展開、最後の時刻境界修正後Native ND12宣言/18展開、通常UI1件が各成功。generic iOS署名なしbuild成功。各版と差分/継承範囲を下記S46と `evidence/20261018-s46/` に記録し、重複caseを合算しない。当時は製品policy判断待ちで、今回E-S46-02で合意・接続した。
- **前回保全**: 開始時7311fileのhash、証跡外copy、git差分は `/private/tmp/fr-s46-20261018-ck1k643l/`。今回も旧証跡/README/memo/他taskを保持した。

### 直前のS45実装完了記録

- **S45 / done（実装・自動検証範囲）**: 前セッションの本体を継承し、Simulatorで同一特徴量を別人へ誤適用する問題を修正。本人承認の位置指定AF・撮影意図選択/保存復元・暫定3秒の猶予を、同一policyで通常FactoryのNative/coordinatorへ接続した。REC非阻害を維持。
- **E-S45-02**: 最終Unit81宣言/112展開ケース、通常UI3件すべて成功、skip/runtimeWarnings 0。Simulator test build・generic iOS署名なしbuild成功、compiler/analyzer診断0。202入力は各最終run/現物で一致。証跡 `evidence/20261018-s45-resume/`。
- **保全・残件**: 開始時7218fileのhashと証跡外snapshotは `/private/tmp/fr-s45-resume-20261018-1tlmtf7y/`。過去のE-S45-01失敗履歴を保持。DV-06の実機AF/同一性/追従/負荷品質、SimulatorのSDK内部原因、S46以降・他task既知残件・独立validationは未確認。今回はS45だけを実施した。

### 直前のS44実装完了記録

- **S44 / done（本体接続・関連自動検証完了）**: 補正候補を現在のカメラ/4K/fps/Logへ限定し、初回標準候補・保存希望の復元・非対応理由を接続。Movie/sample writerのconnection支持/要求/active読戻し、現在補正/倍率/format/実カメラの観測と旧画角失効、REC受理前/予約後の再照合を実装。補正cropとpreview一致は未確認のまま、S47へ渡す状態契約までを完了した。
- **検証 / E-S44-01**: test-03のUnit53宣言/76展開ケースが成功、UIは旧1成功/新1失敗。画面録画で正しい初期表示を確認し、取得方法だけを修正したui-04はUI2成功。App/Unit/projectはtest-03・ios-build-01・最終版で同一、最終187入力はui-04と一致。Simulator test buildとgeneric iOS署名なしbuild成功、最終失敗/skip/runtimeWarnings0。test-01/02のcompile失敗・0件実行とtest-03のUI失敗を保持する。
- **保全・所有**: 開始時6445file/121,908,241bytesのhashと証跡外356fileを `/private/tmp/fr-s44-20261018-o1usgoo1/` に保全。既存16file変更/6429不変、新5ソース、欠落/旧証跡変更/所有外変更0（今回追加証跡除外）。main＝本steering/証跡/差分確認、worker `s44_impl`＝限定App/test、document_author `s44_docs`＝functional-design/architectureの補正箇所。doc_reviewerは指摘なし。証跡は `evidence/20261018-s44/`。
- **残件と次工程**: 実機DV-04/D01/G2B/補正効果・画角・同期・継続性、S47予告consumer、全FR-03受入は未確認。S43独立validation/S42修正後報告未受領、S27詳細等の既知残件を保持。S45以降は未着手。独立検証は同steeringへの明示 `$validate-implementation` で別途実施し、本実装内のtest/main確認を独立validationに代用しない。

### 直前のS43実装完了記録


- **S43 / done（合意反映・製品接続・関連検証完了）**: 本人が「提案通り進めてください」と回答。無到着2秒、本人の再試行ごとに音声入力/出力だけ1回再構成、復旧上限5秒を変更可能な暫定製品設定v1として合意。同一policyをNativeとcoordinatorへ注入した。復旧中も2秒の無到着判定が働き、5秒は全体上限である。実機採用・品質合格にはしない。
- **今回の検証 / E-S43-02**: test-03はUnit19宣言/23展開ケース＋UI1が成功、失敗/skip/runtimeWarnings 0。Simulator test buildとgeneric iOS署名なしbuild成功。test-01の新規test記法修正後、test-02の未変更actor隔離診断は、ソース無変更の新DerivedDataでtest-03が成功。途中2回のcompile失敗/0件実行を保持。最終182入力一致、iOS buildとの差分はUnit test1fileだけでApp/project入力は一致。
- **今回の保全・所有**: 開始時6205file/116,464,636bytesのhashと証跡外355fileを `/private/tmp/fr-s43-approved-20261018-1rjgalcn/` へ保全。既存8file変更/6197不変、新規test1file、欠落/旧証跡変更/所有外変更0（今回追加証跡除外）。mainがtasklist/design/証跡/関連実行検証/最終diff、workerがFactory/関連test/Recoveryの説明コメント1箇所、document_authorがfunctional-design/architectureの音声箇所とPRD Q10音声行を所有。文書P2は修正・再確認済み。証跡は `evidence/20261018-s43-approved/`。
- **引渡し残件**: S42修正後の独立再検証報告は本文/保存先未受領のため反映保留。修正前報告やS43成功で判定を補わない。S43の独立検証は同steeringを指定した `$validate-implementation` による別セッション。実機DV-10/D01/G2B等の既知残件、S27詳細保留・S44以降未着手を保持する。

以下は前回部分実装時の記録。

- **S43 / blocked（製品policy合意・接続待ち）**: 音量/入力/到着/書込の実観測と通常UI、確認済み障害のREC抑止/停止/保存分類、旧通知拒否を接続。有限復旧の本体/注入試験も完了したが、現ProductCaptureFactoryはaudioPolicy未注入で通常経路の無到着期限判定・本人再試行は未有効。提示した「無到着2秒、本人retryごと音声入力/出力だけ1回、5秒timeout」の暫定案は回答未受領のため製品採用しない。合意後に同じS43の接続・必要検証を再開する。
- **検証**: test-03＝Unit60宣言/87展開＋UI1、既存探索の互換修正後test-04＝Unit26宣言/32展開が全成功。重複を除く73宣言/102展開ケース、失敗/skip/runtimeWarnings 0。最終Simulator test buildとgeneric iOS署名なしbuild-02成功、181入力と現物hash一致。初回compile失敗0件・test-02の1件失敗/4issuesも保持。E-S43-01、`evidence/20261018-s43/` を参照。
- **S42今回独立再検証 / 報告反映待ち**: 本人から今回結果の反映依頼を受領。保存先のvalidation-report.txtは修正前P2報告で、修正後の独立再検証本文は本steering/S42関連一時証跡では未発見。本文/保存先を本人へ確認中。修正時の成功で合格を捏造せず、新しい独立検証も開始しない。報告受領後に判定・指摘・範囲を追記する。
- **範囲・保全**: S43だけを実施。S27詳細・S44以降は未着手。開始時5521file/106,676,450bytesのhashと証跡以外349fileを `/private/tmp/fr-s43-20261018-v4sxn_hx/` に保全し現物へ加算。既存17file変更/5504不変、新規音声関連6file（追加証跡除外）、欠落/旧証跡変更/所有外変更0。mainが最終diff・テスト版・所有を確認。実機音声/同期/故障/復旧品質、D01/G2B/DV-03/DV-10・S16等の既知残件を保持。

### 直前のS42修正記録（履歴、2026-10-17）

- **S42 P2修正 / done**: 本人の明示 `$implement-steering` により、WB再測定開始失敗の理由がSTOP・記録終端へ引き継がれない独立検証指摘1件を修正。Nativeで失敗通知前に理由を保持し、本人STOP先行時も停止時の再固定成功で理由を消さない。関連Unit43宣言/65展開ケース（新規7ケース含む）＋UI1件とgeneric iOS署名なしbuildが成功、失敗/skip/runtimeWarnings 0。開始時347file/4,097,161bytesを `/private/tmp/fr-s42-p2-fix-20261017-pp27gwwf/baseline/` に保全し、既存2file変更/345不変、新規2ソースだけを加算（追加証跡を除く）。E-S42-02と `evidence/20261017-s42-p2-fix/` に実行版・結果・差分を記録。修正後の独立検証は未実施で、次工程は同steeringの明示 `$validate-implementation` によるS42限定再検証。実機/DV-03の既知未確認、S27詳細・S43以降未着手を維持する。以下は修正前の履歴。

- **S41独立検証合格**: 本人の明示validateにより `implementation_validator` がS41修正後をread-only検証し、指摘なし・限定合格。E-S41-03の173入力と検証時現物hashは全一致、E-S41-02の実MOV→共通保存→再open→一覧→AVPlayer成功は関連依存不変を照合して継承。追加build/test不要と判定、検証中347fileとgit status不変。実機D01/G2B/Log/ProRes/画質・既知未完了を保持する。
- **S42実装完了 / done**: 続く本人の条件付き明示implementに従い、通常撮影のWB固定・本人再固定・記録終端を接続。最終Unit64宣言/89展開ケース＋UI1件、Simulator testのbuildとgeneric iOS署名なしbuildが成功、失敗/skip/runtimeWarnings 0。173入力は実行版と一致。開始時347file/4,063,807bytesを `/private/tmp/fr-s42-20261017-9w3w5h1m/baseline/` に保全し、今回13file変更/334不変、新規/欠落/所有外変更0（追加証跡を除く）。証跡は `evidence/20261017-s42/`。実機色・継続性・最終フレーム品質は未確認。S42の独立最終検証は未実施で、次工程は同steeringの明示 `$validate-implementation` によるS42限定検証。S27詳細検証・S43以降は開始していない。

### 直前の修正記録（履歴）

- **S41修正完了 / done**: 独立検証のP1（開始拒否後の終端欠落）とP2（遅延準備が離脱を解除）を修正。最終版の関連Unit50宣言/71展開ケース（新規23ケースを含む）とUI1件、Simulator build・generic iOS署名なしbuildが成功。失敗/skip/runtimeWarnings 0。E-S41-03と `evidence/20261017-s41-fixes/` に実行コマンド・結果・差分・版を記録。開始時345fileを `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-s41-fixes-20261017-l5fssrub/baseline/` に保全し、既存5ソース変更＋新規2ソースとtasklistだけを加算。実機D01/G2B/Log/ProRes・既知未完了項目は維持。次工程は同steeringの明示 `$validate-implementation`。S27詳細検証・S42以降・独立validationは開始していない。以下の2026-10-16記録は修正前の履歴。

- **S41完了**: 本人が3点を承認し、初回fpsは本人選択、Movie/sample writerは自動切替なし、撮影日時はREC受付時に一度確定とした。暦時計を製品経路へ接続し、条件成立時のRECを有効化。設定保存/現在条件照合→REC/STOP→共通保存→一覧/既存原本再生の実装と限定検証を完了した。前回Unit48ケース/UI1件に加え、今回の変更後は関連Unit14ケース/UI1件とgeneric iOS buildが成功。証跡は `evidence/20261016-s41/` と `evidence/20261016-s41-approved/`。実機撮影・両方式D01・G2B・Log/ProRes・画質は未確認。S27詳細検証保留・既存変更保持・S42以降未着手を維持。
- 今回の作業はここで終了。独立した実装検証は `$validate-implementation .steering/20260929-device-independent-implementation/` の別明示工程。S42以降へ自動で進まない。
- 今回は明示implementを受領しS41のみ再開。S27の詳細検証は保留、既存差分を保持。以下の停止記録は再開前の履歴として保持する。
- ユーザーは「次に実装する内容を整理したい。その上で別のセッションで実装する」と指示。現在の実装・検証を停止した。次セッションで明示implementを受けるまでS27のbuild/HTTP/pytestやS41実装を開始しない。実装優先の希望を維持し、検証環境の網羅的な仕上げを再開の前提にしない。
- S27は実装差分を保持してblocked（必要検証未実施・今回作業停止）。iOSは既存4変更＋新13、全App/Tests/project158fileをmainがhash照合。製品静的型確認成功はworker報告/保存ログにあるが、Xcode build-01はsandboxのCoreSimulator接続拒否でexit70、コンパイル成功・test成功なし。build-02の権限付き再試行は中断され、log/xcresultとも未作成。環境権限変更後も再実行していない。
- 停止証拠は `evidence/20261016-s27-pause/`（244copy/2,333,586bytes＋manifest/notes）。App158file、現backend overlay、wire/最小準備、未完成HTTP草稿、静的確認とbuild失敗logを保全。backendは最終担当報告未受領の現物として保持し、準備helper/import/pytest/HTTPは未実行。停止時のprocess照会で該当Xcode/publication listener/supervisorなし、collaboration一覧はmainのみ。
- 次セッションの第一候補はS41の通常撮影動線。設定保存/条件付き復元→実能力/実適用表示→試験票不要のREC/STOP→既存共通保存/一覧再生を対象とする提案。S42/WB再固定、S43音声メーター/復旧、S44以降の撮影補助は別作業へ分ける。S27の未検証部分を完了扱いせず、S41の直接変更に必要なbuild/中核確認だけ行う。

- S22Cは完了。Keychainと共通store UUIDの束縛、同store中断/新store/移動/置換の区別、実HTTP6件、全Unit258件＋既存製品root VERIFY、UI2件、main差分確認を完了した。全4段階/PRD/実機受入の完了ではない。
- S22C完了時App/Tests/project126fileは `evidence/20261009-s22c-complete/S22C-test-07-sources.json` に対応。再開時baselineと最終差分・所有照合、compile失敗/test0件の旧runも同archiveへ保持。実行ログ/xcresultは `/private/tmp/fr-di-20261009-resume/`、HTTPは旧rootのS22C/server/runtime-listener-002。登録listener終了・秘密env削除を確認済み。
- S16は8fileに匿名・有界の再生診断、監査分離/失敗添付、action文字色と詳細Listの可視範囲修正を追加。最新source126件は再開root `S16-ui-13-sources.json`。通常の再生/一覧/VoiceOver3件、最大文字の再生/一覧2件が診断無効で成功。原本関連Unit9件＋既存root VERIFY1件成功、全reader0/内容同一、文字largeへ復元済み。DT/textClipped/対象nil contrastが残るためS14/S16はblocked、旧再生開始失敗も未再現・原因未修正。App/Testコードは凍結。途中証拠は `evidence/20261010-s16-*` に追加保全。
- S24は完了。独立した最終全read、証拠/asset/session/jobの同commit、古いclaimと旧処理の拒否を実装し、guard12件・pytest126件・実HTTP20件＋実process再起動後5件を全成功。新S24 snapshot261件と証跡を `evidence/20261013-s24-complete/` に386file/6,965,916bytesで保全。旧tmp S20に続きS22基底/provenanceも欠落したため、全256entry一致のrepo保全S22を新入力として使った。原因は未確定、旧tmp復元/現存保証なし。全child終了・秘密削除・App/Tests/project126件不変を確認。
- S26Jは完了。同一jobの候補版とclaim世代を分け、exact内部retry、未接続adapterの明示失敗、未公開技術fixtureを実装。137node/160case全成功、main差分/所有確認済み。`evidence/20261014-s26j-complete/` に実行snapshot265件を含む345file/7,166,325bytesを保全。旧tmpの再開baselineも欠落したため、S22C archiveのhash/size一致baselineで355件を再照合した。既知33件変更/322件不変、原因は未確定。
- S25は完了。固定版の実AVPlayer再生、64KiB有界buffer、完全取得媒体/複数usage/Photos保持、root使用量と同writer/実終端を実装。test-04の217宣言286実行、HTTP004の5宣言10実行が全成功。最終source145件、共有7変更/新19、main所有確認を `evidence/20261015-s25-complete/` に保全。HTTP001/002の再生失敗、HTTP003の親側旧64B判定失敗、test-04警告1も旧証拠へ保持し、最終HTTP004の診断0/全child実exit0/秘密削除と分離する。S27製品wire/本人確認、S23背景・VPN、実機/聴取/標準変換品質は未完。
- 直前の単独書込taskはS27（現在停止、所有はS27欄）。S23の未成立な背景Wi-Fi/VPN制約を実機待ちだけへ言い換えない。4段階全体の残件は保持し、次セッションは本人が指定する範囲を優先する。M07〜M10/独立validationは引き続き別明示Workflow。
- 進め方の補正（2026-10-15）: ユーザーから現在の検証の必要性と次実装優先について質問を受け、mainが検証準備の過剰拡大を見直した。S27は本体実装とbuild/中核の保存・ACK・失効確認へ絞り、専用HTTP支援・網羅競合・全回帰の仕上げは後段へ延期する。既存成果/失敗を保持し、未実施Verifyをdoneとせず明記したうえで次の独立実装へ進む。全体停止や安全条件の削減ではない。
- 次実装の優先判断（2026-10-15）: ユーザーから初期要件を参照した次実装の見解を求められ、mainはS27を区切った後のS41→S42/S43→S44以降を提案。撮影入口が探索用のままなので、通常設定・REC/STOP・既存原本保存/一覧へ接続するS41を先に進める。初期要件を新たな実装正本へ昇格せず、現confirmed仕様/本steeringを適用。S27書込中はS41の限定read-only調査だけを行う。

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
  - 最新部分結果/局所保留（2026-10-10）: UI13は通常サイズ・診断env0で再生進行/Stop/再生再開/背景停止維持/再起動、一覧/選択/履歴/再open、VoiceOverの3case成功、library/detail監査1失敗（detail-actionsのDT説明1＋対象nil contrast1）、skip/build診断0。全監査合格ではなくS14/S16はblockedを維持する。source126件/所有8fileと他root保護21fileを照合、旧開始失敗は再現なし・原因未修正。最大文字の同版UI-large-04と後続VERIFYはmainが検証のみ継続し、App/Test書込は凍結。再開条件は残る監査指摘の原因/実表示の特定と必要範囲の修正・再検証。位置比較を成立させるための不要な製品余白/文字制限は追加しない。独立S24を次の単独書込taskとする。
  - 再開/所有（2026-10-09）: S22C完了後、現App/Tests/project126fileを `S16-resume-start/` とsources.jsonへ追加保全。同じ30秒合成媒体の製品条件（VideoOutput無し）と通常Viewから再生失敗を切り分ける。`registration_fix`へAVOriginalPlayback/OriginalResourceLoader/OriginalPlaybackModel/OriginalPlaybackView/OriginalPlaybackTests/LibraryFlowTests/PlaybackTestCleanupの7fileだけを単独引渡し、必要な有界・匿名SDK/loader/View診断とassert前添付を先行する。期限延長/自動play再試行/再seedなし。共有store/登録/Composition/project/LibraryViewは凍結し、mainがtasklist/統合実行/差分を所有。アクセシビリティの画面別分離・修正は後続の明示引渡しで行う。
  - 診断比較初回（2026-10-10）: DEBUG Simulatorの明示env時だけ匿名SDK/loader/Viewのmonotonic診断をメモリ512件＋標準OSLogへ追加。App独自恒久ログなし。mainは7fileの差分・再生期限/停止手順不変を確認。N01構成の `S16-test-05`（OriginalPlaybackTests）は9件中8成功1失敗、skip0、compiler warning1。新30秒/VideoOutput無しcaseは実進行・30秒duration・停止/SDK detach/lease解放・内容不変のassert成功後、診断drop0という過剰な期待値だけ失敗（257 drop）。raw512event添付/summary/build/tests/source/commandを保持し、全caseの成功とは扱わない。同期errorLog()のiOS27非推奨/呼出thread block懸念は補助log field除去へ差戻し、bounded仕様に合わせdrop metadataと終端summaryを保持する。通常View比較は未実施。
  - 診断比較再試験 E-S16-PLAYBACK-30（2026-10-10）: 同同期APIを除去しitem.error数値/SDK状態を維持、bounded reportにdrop数と最初のSDK close前/解放後summaryを追加した `S16-test-06` はOriginalPlaybackTests9件全成功、fail/skip/compiler/analyzer warning/error0。30秒/VideoOutput無しの実adapter進行と停止・内容不変/reader解放を確認。これはView装着時の開始成功ではない。OSLogのloader出力でmonitor枠が尽きないよう独立予算に分ける診断だけの限定修正後、通常サイズViewの最小UIへ進む。証拠は10月9日再開root内の同名sources/command/summary/build-results/tests/添付/xcresultに保持。
  - 通常View比較 E-S16-UI-08（2026-10-10）: OSLogのloader192/monitor192/lifecycle96/terminal32を独立上限にし総512を維持。再生動作は不変の `S16-ui-08`（新規testOriginalPlaybackDiagnosticStartStop、文字large）は1件成功、fail/skip/compiler/analyzer warning/error0。View出現→VideoPlayer出現→audio load完了/play、実2.709秒進行→停止、160request/read全終了・pending0・SDK currentItemなし/rate0・releaseSucceededを同時刻軸で回収した。monitorの採取sample最大間隔75.4ms/reader await0.769ms。このrunで旧失敗原因は再現せず、未修正のまま最大文字の停止後再生/背景/再起動を確認する。sources/command/summary/build/tests/OSLog抽出39event/画像AX8添付を保持。旧失敗を解消済みとは扱わない。
  - 最大文字 E-S16-UI-LARGE-03（2026-10-10）: 同じsource版で最大サイズを設定/実前後照合し、既存testOriginalPlaybackProgressStopBackgroundAndRestartが1件成功、fail/skip/compiler/analyzer warning/error0。初回進行→Stop→Close→再生→Home→復帰後停止維持3秒→Close→再起動→再生→Closeまで到達。3sessionのSDK detach/loader pending0/releaseSucceededを標準ログ回収し、画像/AX/timing18添付を保持。終了後largeへの復元/再取得を `S16-content-size-resume.json` に記録。診断有効のrunであり、旧開始失敗は原因未確定・再現なし。最終UIは診断を無効にしても成立することを確認する。監査残件を次に扱い、全reader/identity VERIFYとmain最終差分はその後。
  - 監査修正所有引渡し（2026-10-10）: 実行終了/設定復元後、同workerへLibraryView.swiftを追加し、LibraryFlowTests.swift/PlaybackTestCleanup.swiftと計3fileだけを単独所有として再開。最初は安定identifierと監査状態/種類の分離、最終試験用の診断既定無効化まで。AVOriginalPlayback/loader/model/viewと全S22C/store/Composition/projectは凍結。推測の色一括変更/監査抑制はしない。
  - 分離監査 S16-ui-09（2026-10-10）: LibraryViewはidentifierだけ追加し、監査を4状態＋contrast-only/DT-onlyへ分離。通常testの再生診断を既定無効化した版でfocused2件を実行、2件失敗・skip/compiler/analyzer0。contrast-onlyの5指摘は全associatedElement有りで、active playOriginal（nearly）/disabled playRendition・confirmRendition・discard（fail）を画像/AXで特定。5件目はNavigationBar下のstatus.confirmation子Text（y59.7）で、SDK対象画像には文字が見えずback controlの一部だけ写るため別調査へ。DT-onlyは要照合説明の1指摘が再現。旧nil4件を根拠に推測修正せず、このrunの実対象を修正入力とする。mainはsource3copy/hash・summary/build/52添付/xcresultを保持し、LibraryViewだけへlabel contrastと説明文1箇所のwrapper比較を引渡した。他の2監査状態/最終全監査は未実行、largeへの設定不変も再取得。
  - 限定修正 S16-ui-10（2026-10-10）: action labelをprimary文字の最小ButtonStyleへ変更しdisabled/理由/role/明示余白は維持。要照合Text1箇所をVStackで包んだ比較はDT指摘が同じまま残り、効果なし。focused2件はcontrast-only1成功/DT-only1失敗・skip/build診断0。前後画像でcontrast runのscroll位置が09より約60pt下、discardが下端に掛かるため旧4buttonとnav下issueの全解消とは扱わない。次は効果のないwrapperを戻し、contrastを上部/末尾位置で確認、DTの実サイズ変化をSDK録画から調査する。UI09はrepo `evidence/20261010-s16-audit09/` に51file/3.7MB保全、UI10 source/summary/build/tests/24添付をtmp保持。
  - 監査到達 S16-ui-11（2026-10-10）: wrapperを戻し、contrastにdiscard理由までrevealする末尾監査を追加。診断env0で4caseを実行し、stoppedPlayerの全監査1成功、contrast/freshHistory/historyAfter3失敗・skip/build診断0。再生受付→Close→history操作照合4要素まで到達。指摘44は同要素の複数監査を含むcontrast2/DT37/title clipping5で、44個の異なる欠陥とは数えない。ボタン色の指摘は上/下ともなく、contrast残件はnavbar下status.confirmationの同見出しだけ。履歴/操作照合のDTと履歴title clippingは保持。SDK録画では説明文も実フォント拡大/折返しがある一方、上側行増高で画面外へ退出し、同字高への復元時にも全体369pt下へ移るため位置依存を次に比較する。List viewportをsafe-area内へ縮める限定候補と、説明を最上可視row付近に配置する試験を同2file所有で準備。監査抑制/フォント制限なし。UI11source2copy/hash、全結果/添付/簡潔issues一覧、設定large不変を保持。
  - 可視範囲比較 S16-ui-12（2026-10-10）: 詳細List外側の標準top padding/clippedによりCollectionViewはy132、navbar下端116となり、contrast-onlyは成功。DT-onlyは配置比較のassertで失敗し監査未到達（計1成功1失敗、skip/build診断0）。説明はy409.7→301.7でList末尾に達し、目標y169.1へ移せず、8回の座標dragをtraceに保持。監査成功/失敗とは扱わない。位置仮説の専用helper/call/assertは除去し、DT監査手順をUI11同等へ戻した。上/下のcontrast監査位置は実際には同じになっており、あらゆる境界位置の解消を保証しない。
  - 診断無効/原本照合 E-S16-FROZEN-04（2026-10-10）: UI13と同source126件の `S16-ui-large-04` は最大文字で一覧/選択/詳細/履歴/再起動と原本の実進行/Stop/再生再開/背景停止維持/再起動の2case成功、fail/skip/build診断0。サイズを前後再取得しlargeへ復元。`S16-test-07` はOriginalPlaybackTests9＋ProductLibrarySeedTests.verifySeedIdentityAndReleasedReadersAfterUI1の10宣言/実行全成功、fail/skip/build診断0。既存製品rootの全binding/内容digest/485721byte/video/audio各30秒/保存unknownを保持し全reader0、再seed・修復なし。summary初回読取DBErrorは別error記録へ残し、同bundle再読取で10成功を取得（再実行なし）。mainはmax画像/停止操作・実VoiceOver添付・8file全差分と126hashを確認。S14/S16の残る監査、旧開始失敗原因、実機聴取/品質は未完了のまま。
  - 保全/所有引渡し（2026-10-10）: mainが `evidence/20261010-s16-audit11-12/` に290file/24,688,922bytes（監査結果/添付、UI11source、UI12製品source、位置trace、録画の重要12frame）、`evidence/20261010-s16-frozen/` に119file/8,629,487bytes（UI13/最大04/Unit07結果・添付/所有8source/全差分/最終review/状態snapshot）をhash付き保全。動画・raw xcresultはtmpに保持、UI12の除去した試験helper実行版copy未取得もmanifestへ明記。最初の355file baselineのうち既知所有/新S24所有外314fileは不変。全Xcode/UITest runner/登録listener終了を確認し、App/Testsの書込所有を解除せず凍結、S24へ単独書込を引渡した。
  - 履歴title録画の読取（2026-10-10）: UI11の2回の監査とも、titleは拡大中に「動画 s16v」「2-discard」の2行で全文表示後、先行row増高に伴いviewport外へ退出。ellipsis/行数強制の実描画根拠なし。通常サイズ復元後のissue画像だけを固定幅・省略の証明にしない。TextのlineLimit/fixedSize追加は採用せず、DT/textClippedのSDK指摘は未解決として保持。抽出frameはS16-history-title-analysis、説明DT比較はS16-dt-frame-analysis。S16-ui-13で診断無効の通常再生/一覧/VoiceOverと現在版library/detail監査を確認後、最大文字の操作/再生と既存root VERIFYを残す。
  - 監査分離の読取引渡し（2026-10-10）: explorerがlibrary/detail、fresh history、再生受付→Close→historyのメモリ内操作照合、player-stoppedの4状態を分ける案を提示。fresh historyだけでは従来の操作照合4要素が消えるため旧監査を代替しない。Dynamic Typeとcontrastを分けた対象限定run、同Textの起動前/表示中サイズ変更・frame/画像比較から原因を特定する。SDKのissue.elementはnullableでnil時の座標APIなし。まだ修正/新成功なし。
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
  - 保証根拠の限定再確認（2026-10-10）: allowsCellularAccess=falseのcellular禁止は公開契約で、request側から緩和不可。一方VPN外側回線の切替中も媒体0byteという明示根拠は今回も未発見で、「VPNで効かない/公開APIで絶対不可能」の実証とはしない。NWPathは観測で将来の背景送信経路拘束ではない。background redirect常時追従/delegate非通知/custom URLProtocol不可は明示SDK制約で、connection単位TLS trustを全hop送信前origin審査へ代用できる保証も未確認。要求を維持し、session/task永続対応・uploadファイル所有・復帰callback・全実終端を独立先行する。公開cellular policy＋限定OS/VPN試験や管理server非redirect契約へ受入保証を弱める案は未採用。資料: Apple URLSessionConfiguration.allowsCellularAccess、redirect delegate、Tech Talks 111378、現SDK NSURLSession.h:1346/1517/1652/1732。追加probeなし。
  - Owner / Files: O-IOS-BI／`FrameRelay/Application/MediaIO/`、`FrameRelay/Application/MediaOperations/`（PhotoSave／Cleanup／DiscardCoordinatorを除く）、`FrameRelay/Platform/Network/` と対応test。
  - Done when: 固定対象、Wi-Fi／基礎回線、REC／保存、本人停止／取消・全件停止、条件付き再開、OS背景／復帰callbackを実adapterへ接続。
  - Verify: 実転送停止・buffer／handle解放、条件重畳・遅延応答・モバイル媒体拒否。実REC接続はS4V。
  - Stop: 停止要求だけを完了解放、未指示／終了済み再生／不明写真／削除の自動再開。

### S24 サーバー受信・最終保存・全内容検証

- [x] Status: done
  - E-S24-ACCEPT（2026-10-13）: mainが両担当の凍結差分を確認し、archive入力の新preparation-001（checkpoint `90f5d5f3c7099a47ebc6bf97513fc50c5cdcf522aa393b7c14b8721d27f04aac`）から実行。外部Python3.12 -I -B -Sの凍結run_pytestは118node/126case全成功、fail/error/skip/guard拒否/残存SQLite/所有thread外接続0。全22設定を明示、外部source246件・依存1657件・snapshot261件は実行前後不変。
  - E-S24-HTTP（2026-10-13）: http-preparation-001のconfig/command/checkpointをmain確認しdry-run後、許可されたloopback supervisorを実行。合成16,777,473bytesを3chunkで送信、初回20case成功。listener PID75767の実終了と全terminal証拠/hash/inodeをparentが確認し、DB/mediaをcopyせずPID75774で再openした5caseも成功。両phaseとも独立した新FDで全bytes/hash比較、同じ原本fingerprint/証拠/登録/一意finalize done＋conversion queuedを確認。4 child全exit0、signal0、全worker/AnyIO thread join、server接続/task/SQLite0、秘密0600 file全削除。プロセス再起動の成功であり、強制crash/実回線/TLS/品質/変換/公開の証拠ではない。
  - V-REVIEW/保全（2026-10-13）: mainが保存/claim/旧入口gate/migration/API、guard実dir_fd、HTTP両processと秘密/終端をレビュー。source57/supportとsnapshot261は凍結hash一致、App/Tests/project126件はS16凍結版と一致、開始baseline355件中322件不変・欠落0（33変更は既知S22C/S16/今回所有）、所有範囲外変更0。git diff --check成功、Xcode/HTTP/pytest残存process0。`evidence/20261013-s24-complete/` に386file/6,965,916bytesをhash付き保全。runtime DB/media/秘密は収録せず、次task入力の全実行snapshotを保持。外部deploy/実機/S24I/iOS接続を完了へ昇格しない。
  - backend凍結/静的確認（2026-10-11）: `s24_backend` の所有30 Python fileがASTと非実行compileを通過。future import順序違反5fileを修正し、SQL001と旧登録26宣言はbyte一致。新保存39node＋旧S22 39node/46case＋関連40nodeの計118node/126caseを明示列挙。capture_idは端末のopaque UTF-8文字列を無変換で保持し、pathはserver UUIDだけを使用。加算diff SHA256 `f68fe8ab4854f40bdac758ca891b33ee593c3337153115a321c562e072b9f80c`。backend import/pytest/HTTPは未実行、静的成功を受入完了としない。
  - 基底消失の追加観測（2026-10-11）: 旧tmpのS22/snapshot-001とpreparationの元provenanceも欠落を確認（原因未確定）。repo保全 `evidence/20261010-s24-base-s22/` の全256entry hash、253snapshotと保全provenance、provenanceと元checkpointは全一致。既存tmpを復元せず、新準備の入力をこのarchiveへ明示変更するためbackend担当のprepare_storage_snapshot.py/README-storage.mdだけ再開し、製品overlay/cases/diffは凍結を維持。旧tmp現存確認は過去観測として保持する。
  - E-S24-GUARD（2026-10-11）: guard2fileを先行凍結/copyし、S22と同hashの外部Python3.12を-I -B -Sで使用。専用 `/private/tmp/fr-s24-guard-20261011-001/` の12別process caseは全成功、期待した6拒否と外側fixture不変、実dir_fd pathのaudit、absolute/posix/thread/readonly/invalid FDを確認。backend import/HTTPなし。source/各result/audit/集計を `evidence/20261011-s24-guard/` に28file hash付き保全。isolation_guard SHA256 `74015efc998eb3dc8fe45387bc65b9e9bb2bbacd24ece43991ee644eff2e8265`、check helper `6d2bc6eebd477609b4546f7f8e46ee19732cd89730222ee111085e41801da628`。
  - guard所有の限定追加（2026-10-11）: `s24_http` にdir_fdの実親FDを照合する最小os.open/posix.open wrapperと新check_storage_guard.pyを追加割当。Python open audit eventにdir_fdが含まれないため、cwd相対だけの判定を実書込先確認へ補強する。新専用trialの内側作成/外側FD/親越境/symlink/絶対path/予約path等を別processで検査し、他runtime・実データに触れない。書込root/socket/SQL/subprocessの規則を緩めず、旧登録listenerの再配線も別freeze契約に影響するため保留。main review後の実行を維持。
  - daemon復帰/所有再束縛（2026-10-10）: 旧agent全終了を確認し、mainが途中support51fileを上記recovery rootへcopy/hash保全。全Python AST成功、S16 source126件とS22 archive256件の不一致0、実行中Xcode/HTTP/pytestなし。下記backend所有を `s24_backend`、HTTP支援所有を `s24_http` へ同じ境界で引継ぐ。旧agent報告だけで完成とせず、両source凍結→main review→新snapshot準備→実pytest/HTTPの順を維持。
  - 基底の現存再確認（2026-10-10）: S20/snapshot-001はapp/main.py 1file、preparation-001はparent-resultのみになり、元provenanceは取得不能。原因未確定、過去確認を改変せず復元/再利用成功とも扱わない。S22/snapshot-001の253fileはS22 provenance全hash・S22C/server/snapshot-002と全一致をmainが照合し、現存する新入力基底として採用。S24 helperはS22からの加算差分を使い、旧領域へ書かない。mainがこの基底253file＋provenance/checkpoint3件を `evidence/20261010-s24-base-s22/` に256file/2,980,755bytesで保全。runtime秘密/私的媒体/実DBは含めない。
  - 着手/所有（2026-10-10）: 直接依存S20/S22完了を確認。S14/S16監査/S23背景方式/G2Bを追加依存にしない。`registration_probe_fix`（worker）へO-SERVERとしてsupport/server-implementationのbackend-overlay（受信/保存/evidence/claimと必要な旧入口gate、worker、migration/tests）、新prepare_storage_snapshot.py/cases-storage.json/README-storage.md/backend-storage-overlay.diffを単独割当。mainはtasklist/design・差分/実行/証拠を所有。外部checkout/既存S20/S22/S22C snapshot・runtime・venv・App/Tests・既存isolation_guard/run_pytestは凍結。新S24専用名前空間だけへcopy準備し、隔離実行はmainの具体確認後。最終保存先新FDの全readをwriter外へ置き、現在claim再照合後に証拠＋session/asset＋一意変換jobを同じcommitへ束縛する。最終先/旧媒体を上書きせず、古いworkerの成功/失敗/cleanupを世代tokenで拒否する内部方式を比較・実装する。変換成功/公開は生成せずS26J/S26/S27へ残す。
  - HTTP所有の限定追加（2026-10-10）: 実process再起動を伴うV-SERVER用に `registration_fix`（worker）へserver-isolationの新storage_listener.py/prepare_storage_listener.py/run_storage_integration.py/storage_http_probe.py/listener_lifecycle.pyと、既存run_pytest.py/isolation_guard.py/registration_listener.py/README.mdの必要最小箇所だけを単独引渡し。backend-overlay/準備helperは前workerの所有で非競合。guardの変更は同runtime内のfresh phase証拠先だけで、書込境界/socket/SQL/subprocess規則は維持。phase1実process終了と全終端・parent観測checkpoint/hashを必須にした同一新S24 runのphase2再openだけを追加し、過去runtimeの再実行やDB/media copyを再起動証拠にしない。App/Tests/外部/既存snap/runtimeは凍結継続。両support書込凍結後のmain差分確認なしにimport/試験/listenerを開始しない。
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

- [x] Status: done
  - 着手/所有（2026-10-14）: S13/S20/S21の直接依存を確認し、S26J完了後に単独着手。`s25_impl` workerへO-IOS-BI/O-LIBRARYとして新しいPlatform/Playbackのrendition実装、Platform/TemporaryMedia、Platform/Networkの固定Range reader、Application/MediaIO、Features/Playbackの新rendition専用fileと対応Unit/integration testを割当。O-PORT/O-STOREもこのtaskの一時媒体に必要な共有契約/Domain/同一writer拡張だけを同workerへ直列に束縛し、追加前に具体ファイルをmainへ報告する。既存OriginalPlayback/ResourceLoader・登録・Composition・project・UI tests・server support/外部repoは凍結し、変更が必要ならmainが範囲を再確定する。mainは進捗/差分/環境確認/実行証拠を所有。まず実HTTP→全量前AVPlayer進行、完全取得一時fileと複数使用権/再open/実終端をfixtureで検証し、旧APIから製品DistributionReceiptを捏造しない。
  - 初稿/共有所有の具体化（2026-10-15）: 新規15fileと共有7fileを受領。共有はBackendMediaPortsの既存型を維持し、新RenditionMediaPorts、TemporaryMediaReceipt/State、BackendCommit、MediaOperationStorePort、MediaOperationStoreAdapter/新TemporaryMediaStoreProjection、RecordingStoreDocumentのschema6互換移行、既存migration/registration identity test2件のschema期待を対象にする。MainActor隔離とiOS27 APIを含むbuild-01が実exit65、test未実行。`/private/tmp/fr-di-20261014-s25/` にsource hash/ログ/xcresult/build-resultsを保持。Xcode27.0(27A266a)/Swift6.4・言語5/iOS27、実在FrameRelay scheme/test plan、boot済DFE46693-E8DD-4814-8957-4F327699F719を再確認。sandbox内listのCoreSimulator接続拒否は権限付き再確認成功と区別する。
  - main-reviewからの修正（2026-10-15）: 同rootの別一時媒体instanceが他ownerの利用中fileを解放できる境界、usage/lease別commitの中断回復、reclaim再開、全owner生成/閉鎖/実終端集約、local read/Photos解決時のpath同一性、terminal件数の実観測を追加修正へ戻した。新RenditionMediaScope等を同workerへ追加所有。全owner observerはS27へ一括先送りせずS25内で検証し、旧epochの不明leaseは辞書不在から解放しない。compile修正後もこれらと実HTTP/AVPlayerが未検証の間はdoneにしない。
  - compile経過（2026-10-15）: build-02はManagedTemporaryMediaのfactory openとPOSIX openの名前衝突で5error/0warning・exit65、Darwin.open明示へ限定修正。build-03はAppコンパイル通過後、故障注入test actorのnonisolated推論1error/1warning・exit65。aliasから同等の直接protocol適合へ変更したbuild-04も同じ1error/1warning・exit65で、alias原因の仮説は棄却。いずれもtest未実行、全App/Test/project144件の実行版copy/hash、build-results/xcresultと取得stdoutをS25 rootへ保存。build-02のstdoutはtool上限による一部省略あり、診断全件はbuild-resultsを参照する。mainが02〜04のsourceと結果を `evidence/20261015-s25-build02-04/` に444件/3,530,720bytesで追加保全。
  - 終端/不明分類の追加review（2026-10-15）: 再生monitor自身からの停止で自己待ちを作らず、teardownがsetup/monitorの実終了をjoinしてからterminalを記録する修正へ引渡し。usage取得commit後のlookup不明は確定拒否ではなくunknownへ揃える。Photosの実callback終了と登録成功後の明示usage解放を分け、scope closeだけで未解決photoHandoff用途のfileを回収しない。workerの同じ所有範囲に限定し、関連故障/実再生試験で検証する。
  - 初回実行 S25-test-01（2026-10-15）: 上記修正＋test wrapperのMainActor class/明示witness隔離版のbuild-05はexit0、compiler/analyzer warning/error0。SDK列挙30宣言を同版test-without-buildingで実行し30宣言18成功/12失敗、40実行25成功/15失敗、skip0・exit65。既存migration/登録identity/lease順序の18宣言25実行は全成功、新S25の12宣言15実行は共通fixture準備でinvalidValue。実再生/復旧の成功証拠ではなく、入力契約を修正して再実行する。source144件・静的検証入力・build/列挙を `evidence/20261015-s25-build05/`（153件/1,235,439bytes）、失敗summary/tests/command等を `evidence/20261015-s25-test01/` に保全。raw xcresultはS25 rootへ保持。
  - 関連試験 S25-test-02（2026-10-15）: 未作成directory URLの末尾slashがFoundationのsymlink解決で落ちることを特定。fixture先行作成だけの回避案を戻し、init/継続root検査を正規化filesystem path照合へ修正、isFileURL/O_NOFOLLOW/実FD・inode照合を維持。leaf/親symlink拒否2実行を追加したbuild込みtestは31宣言42実行全成功、fail/skip/expected failure/compiler/analyzer warning/error0、exit0。新S25は13宣言17実行（実AV4、復旧8、一時媒体5）、既存store回帰25実行。source144件と結果/局所再現を `evidence/20261015-s25-test02/` に保全。次の同版test-03はSDK列挙210宣言の全Unit＋既存製品root VERIFY＋60秒Movie生成を実行中。再seedは選択していない。
  - 全Unit S25-test-03（2026-10-15）: 同版210宣言277実行全成功、fail/skip/expected failure/runtime warning0・exit0。test-without-buildingのためbuildは再要求せずtest-02の診断0を参照。既存製品root VERIFYと新60秒合成Movie生成を各1実行し、再seed/legacy HTTP/新HTTP/空exampleは選択外。host copyは969,998bytes、SHA256 `8a77b6c2cfdedbe850148210eada8851956f10942203aec4eae8f9e552a8b984`、元の生成添付/実fileと一致、App/Test/project144件不変。結果・列挙・Movieを `evidence/20261015-s25-test03/` に14件/1,274,262bytesで保全。旧Movie欠落をこの新Movieの再利用で隠さない。
  - HTTP準備001（2026-10-15）: 保全済み支援8fileの全hashを現sourceと照合し、新Movie/SDK HTTP5宣言/実Xcode構成を入力にreview済prepareを実行、exit0。新 `/private/tmp/fr-di-20261014-s25/S25/preparation-001` へconfig/source/依存provenanceを凍結、runtime未作成。dry-run/実listener/Simulator HTTPは未実行で、準備成功を再生成功とは扱わない。
  - 実HTTP001（2026-10-15）: dry-run確認後、checkpoint `f39a02982616941eadc41b696260ad653a98163cea302d75119b8b597818f462` の実supervisorを実行。5宣言10実行中9成功/1失敗、skip/build診断0、Xcode65・wrapper70・listener0・親70。streaming caseは30秒内に進行/decoded frameへ到達せず、token/audio trackのassertも不成立。受信3434B/969998B・131requestは先頭/tail metadataのみ、server固有送出3248B。単純な期限延長や全量先行へ変更しない。残り9実行は認証/不正版等/停止/完全取得引渡しの部分成功。
  - HTTP001終了/保全: listenerは全handler/FD/生成thread終端・connections/tasks0・guard拒否0・外部依存/source/Movie不変、秘密削除を実観測。親は2childの実exitを確認し強制signal/親fallback削除なし。wrapperがXcode非0時metadataを回収しないため親にFileNotFoundErrorも発生、mainはxcresultを抽出した（初回TestReport保存権限拒否後、同操作の権限付き抽出成功・再testなし）。公開結果/凍結support/provenance/失敗添付は `evidence/20261015-s25-http001/` に33件/1,058,788bytes保全、秘密envを保持し得るraw xcresultはtmp限定。
  - HTTP001診断引渡し: server headers→terminal中央値0.353ms/max0.571ms、要求間隔平均は最初10件23.1ms→最後10件490.3ms。各Rangeの3writer commitと全document decode/replayが候補、工程別profile前なので断定しない。`s25_impl`へ有界aggregateのstage時間/setup/current・peak管理buffer（累積byteとは別）をS25所有内に追加し、assert前添付する限定修正を割当。`s24_http`へ新5支援所有内で非0でもmetadata回収・失敗種類分離と、summary5宣言/device10実行の正しい照合を割当。既存001/source/fixture/Guard等は凍結、新版は別preparationで検証する。
  - HTTP002診断開始（2026-10-15）: 診断4fileの加算差分、支援3fileの非0時metadata回収/秘密伏字/最大量/実exit分離をmain確認し、旧5支援不変を照合。現在144sourceを `S25-http-002-source/` へ凍結、新preparation-002/checkpoint `f200ba047a6d255244356affb6d4a24a897a77ec4ac1873ce39bc8ad7d1492bc` を生成。dry-run後、同60秒Movie/同5宣言10実行・30秒判定の実listener/Simulatorを開始した。cache/使用量集計の動作変更はまだ加えず、再生工程と現在/最大管理payloadを測定する。
  - HTTP002結果/診断: 5宣言10実行9成功/streaming1失敗、skip/compiler/analyzer/runtime warning0、Xcode65・wrapper70・listener0・親70。3種metadata抽出は全成功し、非0の試験失敗を根因のまま保持。30秒時点はaudioTracks待ち、128HTTP/3418B/decoded0。read工程のawait込み累積29823ms中、lease取得6461/配布commit6485/現条件照合10235/lease解放6443/HTTP302ms（並行sumをCPU時間とはしない）。停止後player無し、active read/loader/current管理payload0、128開始/128終端/URLSession無効化を観測。全child実exit/handler/FD/thread終了、guard拒否0、source/依存/Movie不変、listenerによる秘密削除。`evidence/20261015-s25-http002/` に実行source144件を含む179件/2,240,201bytesを保全。
  - バッファ/使用量の限定修正: 上記実測を受け、同workerのS25専用reader/temporary/Port/test所有内に最大64KiB単一区間read-aheadを許可。拡張した実Rangeをauthorize/厳密検証し、返却は要求のexact slice、hitでも現gate/登録/版/epoch/permit照合。leaseを保持中bufferに束縛し、実read終端→buffer破棄→解放、取消/並行/close後の復活を拒否する。TemporaryRenditionReaderのtailが最後のDataを保持する点も修正する。root実列挙の媒体別/総file量・未知file量/usage/FD観測を追加し、stat不明を0にせず未合意TTL/容量上限は加えない。共有writer/schema/既存原本/登録/Composition/project/supportは凍結。30秒・同Movie・全量前再生条件は維持し、新版で再検証する。
  - 修正版回帰 S25-test-04（2026-10-15）: 上記9変更＋新cache test1fileをmain確認し、source145件を凍結。217宣言286実行全成功、fail/skip/expected/runtime warning0・実exit0。追加8宣言10実行にcache gate/登録/失効/epoch、並行取消/実callback待ち、2媒体/hole/未知file/回収、root欠落/差替、外部ownerによる世代変更後のreconcile拒否を含む。既存製品root VERIFYも成功、再seed/新Movie生成なし。build error/analyzer0、不要await warning1。CLIにexit0のSwiftCompileを失敗とする5表示が出たが、xcresultはbuild succeeded/error0でありログ上の相違を保持する。全test-treeの初回tool出力超過は完全JSONのfile直接出力で補完、再testなし。`evidence/20261015-s25-test04/` に実行source145件を含む164copy/1,491,921bytes＋run notesを保全。
  - HTTP003開始: 警告の試験1行だけから不要awaitを除き、製品source不変を確認。145sourceを `S25-http-003-source/` へ凍結、review済8支援不変を照合。preparation-003/checkpoint `9e970e3558f622f5b549f0814e9c9a381507e78a0a3446577183141a999c462a` のdry-run後、同Movie/同5宣言10実行のbuild込みHTTPを開始。製品static typecheck成功、別のstatic test型検証はTesting module未解決として保存し、実test-04の成功と分離する。HTTP003の再生成功・診断0はまだ未判定。
  - HTTP003結果: 5宣言10実行全成功、skip/expected/runtime warning/compiler/analyzer診断0、Xcode/wrapper/listener各実exit0。実AVPlayer elapsed0.1382秒/decoded frame1/audio track1、全969998Bのうち339596B受信で進行。8実HTTP/143cache hit、cache/client/pending最大payload各65536B。停止後のcache/client/pending/result payload0・active read/loader0・8開始8終端・SDK detachを確認。streamingのserver固有送出coverage133770Bも全量未満。実SDK内部のmemory量・聴取・品質はunknownのまま。親は旧range64/Content-Length63,65/body64固定の2判定がfalseで70、終了・秘密・隔離の他条件は全成功。再生成功と親全体失敗を分離して保持する。
  - HTTP003支援修正引渡し: `s24_http`へsupervisor/READMEの2fileだけを割当。実Rangeの長さ/上限/終端とContent-Length±1、delayed全送出=実要求長/2秒以上を照合する形へ固定64B依存を修正し、発生件数・実終端・停止後byte・秘密等の条件を維持する。App/Test145件は凍結し、修正後は別preparation004で親終了まで再確認する。
  - E-S25-HTTP/完了（2026-10-15）: 上記2支援差分・他6支援/145source不変をmain確認。checkpoint `75f2c4758cb31d9d12ed8aee37867a586e8209db3ba64242fe632b570886f17f` のHTTP004は5宣言10実行全成功、skip/expected/runtime/compiler/analyzer診断0、Xcode/wrapper/listener/親すべて実exit0。実再生elapsed0.1464秒/decoded1/audio1、受信339596<969998B、8HTTP/143hit、停止後のclient/cache/pending/result payload・active read/loader0、8開始8終端。全実Range/不正header/認証/redirect/遅延停止/条件変化/完全取得引渡しを確認。全FD/handler/thread/child終了、guard拒否/SQLite接続0、source/依存/Movie不変、listenerが秘密削除、親fallback/強制signalなし。
  - V-REVIEW-S25/保全: mainが同writerへのusage/lease同commit・unknown保持、所有root/kernel lock/inode、全量hash/写真日時、callbackと成功後usage解放の分離、全factory閉鎖/実owner終端、buffer保持中leaseとcachehit再照合を確認。開始前130保護対象はtasklist＋共有7だけ変更、他122不変/欠落0、新S25は19file。測定profile外の既存asset JSON3件はGit HEAD一致を別確認。全26S25 Swift fileの空白診断0（no-index exit1は差分ありの意味）。全Unit286成功版から最終版への差は試験の不要await1行だけ、製品source同一、最終build診断0。HTTP003は `evidence/20261015-s25-http003/`（180file/2,081,635bytes）、最終HTTP004/145source/所有確認は `evidence/20261015-s25-complete/`（183file/2,114,044bytes）へ保全。
  - 4軸/引渡し: I＝固定版下位I/O/一時媒体/owner/実AV再生実装済、製品配布wire/本人操作/CompositionはS27/S28へ。A＝新S25 Unit21宣言27実行、既存含む全Unit等286＋実HTTP10成功。D0、R＝合成媒体の部分技術証拠。Photos実登録/成功commitはS31、実OS全ownerはS23/各接続で追加照合、実機回線・聴取・品質はDV-12/14/16へ残す。SDK内部memoryを管理payloadから推定せずunknown、使用量は実regular file長とcoverageを分け、allocated blocksや未合意TTL/容量上限を追加しない。
  - HTTP支援の限定所有（2026-10-15）: `s24_http` workerへserver-isolation下の新prepare_rendition_fixture.py/rendition_fixture_listener.py/run_rendition_fixture.py/run_rendition_simulator_probe.py/README-rendition.mdのみ割当。既存Guard/lifecycle/runnerとbackendは凍結しread-only再利用。test-only /media/<mode>、Bearer、exact Range/fixture版header、不正版/hash/size/短い/過大/redirect/遅延応答、秘密envと実process終端を具体化する。旧S20 Movie実体は欠落し旧hashを再利用せず、新60秒合成Movieを生成・hash束縛して使う。全support凍結/main review後だけhelper/import/HTTP/Xcode wrapperを実行する。
  - 読取引渡し（s26j_map/main、2026-10-13）: 既存S20/S23調査を継承し、現コードとの差分を確認。OriginalResourceLoaderのread closure/64KiB/drainと原本playerの実進行/SDK detach順序を再利用候補とするが、MOVのcontent type固定を将来MP4へ流用しない。LegacyServerProbeSupportのexact Range/版/digest/size/redirect拒否/実callback待ちはtest-only、製品reader/temporary owner/全owner observerは未実装。S21のtransport/renditionPlayer/temporaryMedia leaseと単一writerを使い、各read/新Range/再開前の現共通gate照合を注入境界にする。S23全完了を開始条件に追加せず、前景だけ/全量取得必須へ縮小しない。
  - 部分引渡し境界（2026-10-13）: RetrieveMediaCommandはcommitted DistributionReceiptを必須とする一方、旧配信APIは配布receiptを生成しない。旧X-Processed-Result-*から製品receipt/tokenを捏造せず、fixtureを明示した下位I/Oを先行しS27 wire接続を残す。一時媒体は値契約だけで、実file/範囲/全hash/複数usage/使用量/再openとPhotoKit用local解決・保持portが必要。同writerを拡張し別DBを作らない。撮影日時に取得時刻を代用せず、保持期限/容量上限の未合意数値も追加しない。実HTTP→全量前のAVPlayer進行、版/短い・過大body拒否、SDK/transport/file実終端、複数usageの片方解放と最後の回収、改変/旧epochを試験対象へ引渡す。
  - Depends: S13,S20,S21。
  - Owner / Files: O-IOS-BI＋O-LIBRARY（所有別）／`FrameRelay/Platform/{Playback,TemporaryMedia}/`、`FrameRelay/Features/Playback/`、`FrameRelay/Application/Ports/BackendMediaPorts.swift`（O-PORT）と対応test。
  - Done when: 再生可能fixtureの認証・版固定streaming／一時取得・使用量／実解放。写真には完全取得の同一映像と使用権だけを渡す。
  - Verify: V-PLAY、旧版／別版拒否、Range・中断・buffer解放、部分媒体拒否。
  - Stop: S26の実Log採用をfixture実再生の前提にしない。全量取得必須への縮小は相談。

### S26A 標準変換資材・入力適合と比較案を整理

- [ ] Status: pending
  - 読取引渡し（2026-10-10、registration_audit/main）: 外部assetsのrec709.cubeは2³のIdentity、identity-v1/test-red-blue-swap-v1は17³の生成テストLUT（現物/manifest hash一致、target_color_space=null）。Apple由来標準資材ではない。apple-log-v2は検出規則v2でありLog2専用LUTではなく、Log1/2別preset参照に対応する標準資材実体なし。Apple資料はLog1=BT.2020 primaries/com.apple.rec2020.apple-log、Log2=Apple Gamut/com.apple.apple-wide-gamut.apple-logを区別。SDKのLog2 YCbCr matrix=BT.2020だけで色域BT.2020と判定しない。公式FCPは各別Rec.709 3D LUTを説明するが資材実体/版/利用条件/数値域の取得未完、Developer Downloads取得不能をログイン必須とは断定しない。S26J、S48描画分離/世代/資材契約は独立先行可。現inspectorのactual-log-parser-not-validatedと、実Log/具体素材/G3表示・比較・許容/出力採用の未合意を保持。素材download/品質試験なし。一次根拠: https://developer.apple.com/documentation/avfoundation/avcapturecolorspace/applelog 、同/applelog2 、https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_logtransferfunction 、https://support.apple.com/ja-jp/guide/final-cut-pro/ver24f966423/mac 。
  - Depends: N00。
  - Owner / Files: main＋調査担当／本 `design.md` の判断・資材参照欄。標準資材調査は読取。
  - Done when: Log条件・標準資材の由来／版／利用条件・対応入力・未取得箇所を記録し、技術試験可能範囲とG3比較案を分ける。
  - Verify: 根拠資料／既知入力・出力特性の対応、秘密／私的素材非収録。
  - Stop: 資材不明の変換部分だけ保留。品質合格試験はQ01前不可。

### S26J 変換周辺job・候補版処理を先行する

- [x] Status: done
  - E-S26J-ACCEPT（2026-10-14）: 凍結差分/準備helper/configをmain確認後、repo保全S24を入力に新preparation-001（checkpoint `97065e9b32b3c91542fc6e57c95e20838a7a6d1f20e1380bc526062d9ea73649`）を作成。外部Python3.12 -I -B -Sの凍結run_pytest.py --configを実行し、137node/160case全成功（5.58秒、既存126＋新34）、failure/error/skip0、parent実exit0。実store/workerで証拠欠落/別対象、候補失敗、retry commit前後、候補publish/commit中断、旧claim遅延・renew/cleanup拒否、全read中writer解放、原本/公開済V1/確認保持を確認。guard拒否/残存SQLite/所有thread外接続/close失敗0、全22設定/外部source246/依存1657/実行snapshot265が前後一致。
  - V-REVIEW/保全（2026-10-14）: backend既存6変更＋新4、準備4追加のみ。SQL001/002・旧登録test・server-isolation不変、App/Test/project126件不変、所有外変更0、git diff --check成功、対象process残存0。mainが候補/claimの独立世代、exact受理事実と現在観測、同FD保持/実終端・新FD全読取と短い再fence、未接続の明示失敗、未公開/Rec.709未検証、旧公開入口拒否を確認。`evidence/20261014-s26j-complete/` へ345file/7,166,325bytesを保全。加算diff SHA256 `c70165df57a89862cabfbf3335f5ee3178e38d2e7f987beacf081c907c794384`。旧attempt/commit前候補は保持し自動回収policyを追加しない。S26/S27・実機/実Log/標準変換/公開/外部deployは未完を維持。serverのみの変更のためXcode再実行なし。
  - 着手/所有（2026-10-13）: 直接依存S24完了後、`s24_backend` workerへsupport/server-implementation/backend-overlayのFR candidate/job/worker/migrationと対応test、必要な保存証拠判定の限定変更、新prepare_conversion_snapshot.py/cases-conversion.json/README-conversion.md/backend-conversion-overlay.diffを単独割当。S24実行版は上記archiveで固定、既存SQL001/002・S24準備helper/cases/diff/README、server-isolation、App/Tests/外部repoは凍結。mainはtasklist/判断/最終差分・実行・証拠を所有。他者の変更を戻さず、新S26J専用snapshot/runtimeだけを準備する。import/pytest/helper実行はmainの凍結review後。
  - 読取引渡し（s26j_map/main、2026-10-13）: S24の一意fr_conversion payloadを起点に同SQLite/既存jobsを再利用。旧formal/rendition finalizerは即時pointer公開とcompress-only fallbackを含むため直接接続しない。新003で候補版/試行・claim fenceを追加し、候補の版世代と再claim世代を分ける。保存証拠のexact由来を保持しつつ、現在queuedに固定された照会条件を変換running/failedから独立させる。未接続adapterは明示失敗/未実装とし、Rec.709成功/公開を生成しない。無限自動retry・新利用者操作は既定化せず、内部のexact retry意図で同原本再利用を検証。asset.is_log=0は入力検出事実に使わない。
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

- [ ] Status: blocked
  - 停止/未検証（2026-10-16）: 本人が整理後の別セッション実装を希望したため停止。iOS実装17file（既存4変更/新13）は凍結hash一致、mainが全158sourceを保全。製品static typecheck最終product-06はexit0/診断0のworker報告、test source型確認/実行なし。Xcode build-01はCoreSimulator接続拒否・destination未取得でexit70、build-02再試行は中断/未作成。backendの4node/9case用準備/試験本体は保存済みだがhelper/import/pytest未実行、最終全差分reviewも未完。HTTP草稿は延期。再開条件は対象source/所有/現環境の再確認と、本人が選ぶ実装または検証範囲の明示。独立S41をこの未実施Verifyの完了待ちにしない。
  - 着手/所有（2026-10-15）: S21/S22C/S25の完了後に単独着手。`s24_backend`へO-SERVERとしてbackend-overlay内の新FR publication migration/repository/service/schema/router/対応tests、必要な既存FR files/旧入口gateとmain router、support/server-implementationの新S27準備4fileとwire契約案を割当。SQL001〜003、外部repo/venv、全既存snapshot/runtime、S25支援/App/Test/projectは凍結。まず具体wire/schemaとfixture品質境界をmainへ示し、review後にiOS担当へ同契約を引き渡す。実import/helper/pytest/HTTPは全source凍結とmainの具体確認後に実行する。S26の正式品質proof未接続を安全に拒否し、技術fixtureを製品合格へ昇格しない。
  - 開始保全（2026-10-15）: `/private/tmp/fr-di-20261015-s27/` のapp-baselineとmanifestへS25完了版App/Tests/project145fileを保全し、protected-documents.jsonへ7文書のhashを記録。backend比較元は不変の `evidence/20261014-s26j-complete/` snapshot265件とし、既に作業中のoverlayを開始前copyと呼ばない。
  - 開始metadata保全: baseline manifest・7文書hash・最終採用wireの3file/40,189bytesを `evidence/20261015-s27-start/` へ追加copyし、元path/hashをarchive-manifestへ記録。App実体145fileは既存S25-complete内のS25-http-003-sourceと同一、重複生成せず参照する。実行結果の証拠ではない。
  - wire判断（2026-10-15、main）: fr-publication-v1のsource配布→各read配布→単回GET、型別exact lookup、current=NULLの初回公開、tests専用authorityを採用して実装開始。ACK lookupはkind＋registration＋invalidation IDへ束縛し、lookup自身と元request/resultを明示区別する。server生成rendition IDのcanonical UUID、artifactの検証済みmedia_typeとmanifest/distribution/GETの一致を契約へ具体化中。QuickTime fixtureをmp4と偽装せず、mp4/quicktimeの技術的許容をS26出力品質の採用とはしない。製品authorityは正式proof未接続を常に拒否する。
  - wire引渡し/追加所有（2026-10-15）: 上記4点を具体化した `support/server-implementation/s27-wire-contract.json`（SHA256 `7d6ab80990021506dc401bad87fcba0a756b3a160db3bb326db3a19aaf3a224b`）を凍結しmain採用。`s25_impl`へ新規確認/outbox/失効coordinator、PublicationPorts/wire/remote/HTTP binding、scope registry、専用新規tests/fixture、および共有ManagedOriginalAccess.swiftの同一失効予約再開だけを単独割当。既存S25/共有store/schema/登録/Composition/UI/projectは凍結。`s24_http`へserver-isolationの新publication listener/supervisor/Simulator wrapper/preparation/READMEの5fileを割当。backend/App/supportで所有を分け、実HTTP/Xcode/helper/pytestの実行は全source凍結後にmainが行う。
  - 端末側引渡しの限界（2026-10-15）: schema6の確認＋outbox、失効tombstone＋ACK/outboxは再利用する。scope.closeは自scopeだけであり、全scopeのfactory受付閉鎖と実終端、original/S23外部ownerの実観測が必要。製品external/recovery producer未接続を空集合成功で代替しない。失効予約後の再登録は旧reservation/未ACKを保持し、新登録への付替や一律登録待機へ変更しない。未commit本人actionの再開可能範囲と必要な永続追加は実装側で具体確認中。
  - wire補正/凍結（2026-10-15）: 正当なopaque IDとrequest/result echoは既存登録用16KiB上限を超え得るため、publication専用制御応答上限256KiBを採用。失効一覧はafter_invalidation_id＋limit(1〜8)、resultのnext_afterによるkeysetと実encoded envelope192KiBの二重上限を採用し、短いpageでもcursorがあれば継続する。各pollは先頭から開始し、page取得完了を全ACK成立に置換しない。予備schema reviewでGET admissionのoperation ID単独PKと登録別操作の不整合を検出し、全wire操作/GETをregistration scopeへ統一。契約最終hashは `455868ebe8d057ad32471a169396333c03cd1bcf2b4a4986f3147935f2617e0a`、App/supportへ引渡し済み。
  - 本人actionの永続境界（2026-10-15、main採用）: 確認＋outbox commitを最初の耐久受付とし、commit前未記録actionの自動再開は追加しない。unknown時は同じ完全mutationを保持してexact lookup、再open後は既存durable確認/ACK/outboxのみ回収する。未発見を確認済み／確実な未実行に丸めず、未記録actionから確認を生成しない。schema6を維持し、旧登録の資格不在は送信保留にする。
  - 現存original ownerの追加引渡し（2026-10-15）: read-only追補で製品rootは単一AVOriginalPlayback/loader/ManagedOriginalAccessを使い、背景URLSession/Photos consumerは未実装と確認。既存stopはsetup/loader/releaseを待つがmonitorは取消のみのため、同じ`s25_impl`へOriginalPlaybackPort.swiftの専用終端契約、AVOriginalPlayback.swiftの対象別受付閉鎖＋外部からの実monitor join/保持Session照合、新ProductMediaTermination.swiftを追加割当。別動画の再生を止めず、内部monitor自己joinを避ける。Composition/Factory/Modelの変更は最小提案のmain確認まで凍結。未知の残存lease/旧ownerはunknownとし、未実装機能の不在だけで過去ownerなしを証明しない。
  - 製品rootの限定引渡し（2026-10-15）: 最小提案を受け、同じworkerへProductComposition.swiftだけを追加割当。既存AVOriginalPlaybackをModel/termination producerで共有し、同writer/accessのregistryを保持する。Factory/Model/既存UIは凍結し、open時の自動取得・同期・新登録を追加しない。失効commit後はexact ACKと現epoch/accessGeneration/予約解除を再照合して新scope/原本受付を明示再開できる設計とし、旧scope/tokenは再生可能へ戻さない。
  - backend回帰の限定引渡し（2026-10-15）: `test_frame_relay_storage.py` のmigration件数3→4、`test_frame_relay_conversion.py` のpredecessor001/002抽出だけを同backend workerへ追加割当。旧SQL001〜003/登録26試験と既存受入条件を保持し、S26J archiveを差分比較元にする。
  - 検証準備の延期（2026-10-15）: 現時点S27のHTTP/Xcode本試験は未実行。ユーザーの疑問を受けたmain判断で、本体・既知不具合修正を先に仕上げ、build＋確認commit前成功禁止/実終端前ACK禁止/失効後確認非復活の中核確認を優先する。作成中の専用HTTP5fileは保存して凍結、追加の網羅ケース/全回帰/実通信実行は後段へ延期。実装未完と検証未実施を分け、S27全体のdoneを先取りせず次の独立taskへ引き渡す。
  - HTTP草稿凍結: s24_httpの新規5fileは未完成のまま保存。Python4fileのAST/非実行compileは成功、旧S25支援8fileはprep004と一致。helper/import/HTTP/Xcode、新preparation/runtimeは未実施/未作成。残件はSwift suite実契約照合、全量前streaming親観測、seed開始時thread監査、guard.finish前SQLiteゼロ確認、main review。現稿を実行可能な完成版と扱わない。
  - 読取調査開始（2026-10-15）: S25の単独書込を維持し、`s26j_map`へ既存値/Port/storeとS26J保全snapshotの全配布/公開入口、required ACK集合、再登録/古いACKの境界だけをread-onlyで割当。新製品wireの判断候補と実I/O試験を整理し、S26の標準変換/品質未確認をfixture成功で代用しない。実装/import/HTTPは開始しない。
  - 読取引渡し（2026-10-15）: PublicationLedger.swift:42/66の配布commit/recipients/replacement/全ACK規則と、MediaOperationStoreAdapter.swift:310/329/347の確認＋outbox、失効予約→全reader解放→tombstone/ACK、exact deliveredを再利用する。server側の永続公開revision/配布完全payload/受取登録/required失効/ACK/公開結果は未実装。ACK待機中の新登録V1配布も同commitで必要集合へ追加し、新登録で旧登録ACKを代用/削除しない。current必須の値型へ架空V1を入れず、初回未公開境界を別途設計する。
  - wire/実送信境界: RenditionRangeAuthorizationPort.authorizeへ新Rangeごとのcommitted DistributionReceiptを返す候補。receipt keyにrange/attemptがないため操作IDだけで再送照合せず、serverで完全payloadを保存する。事前authorize成功を永久GET許可にせず、実GET/Range/resumeで現公開版・登録・失効・exact要求をbyte前に再照合する。manifest/配布受付・照会/固定GET/確認同期/失効取得・ACK送信を既存RemoteStatusPort等へ接続。URL/JSON・authorize/GET対応方式・初回公開表現は実装時に具体化する未採用案。
  - 全入口調査: S26J保全snapshotの主要旧finalizer/backfill/set/clear pointerはlegacy_entryでFR対象拒否済み。この拒否を解除して即時公開へ接続しない。新公開時の迂回確認対象はapi/assets.py:128/213/271、processed_result_stream.py:35、preview_stream.py:34、processed_result_delivery.py:91のformal別pointer、asset_read.py:189の旧確認、formal_preview_finalizer.py:249/phase2b_migration.py:182の直接SQL、main/worker recovery、旧004/007/phase2 trigger。headerなしを旧契約採用の根拠にせず永続FR分類でgate/拒否する。旧データ移行は未許可のまま。
  - 実I/O検証候補: 同一FD全hash→短い配布commit→同FD送信とartifact保持、配布/公開の両順序、hash中別writer/版切替/同size改変/path差替、ACK済登録V1新要求byte0、受理済V1応答の版不混在、required集合追加・古いrevision/登録/失効ACK拒否、SQLite再open/応答欠落exact照会、全旧入口拒否、実AVPlayer→本人操作→確認commit/失効後非復活を対象にする。S20-s27-design-input.md（20261006-checkpoint保全）を継承。S26J candidate_readyはpublished:false/rec709_verified:falseのまま、隔離fixture公開順序試験を製品品質gateの通過にしない。
  - 具体化した読取案（s24_backend/main、2026-10-15）: 新004に公開head(current nullable)/artifact/replacement/typed exact操作/recipients/GET admission/ACKを加算する候補。requiredはreplacement.previousの不変recipients全件から導出し、初回はNULLから期待revisionで公開する。manifestと別のsource配布commitで初期RetrieveMediaCommandの実receiptを得て、各拡張Rangeは別read配布receipt→実GET単回admissionへ束縛。消費済GETの再利用はbyte0、欠落後の新要求は再受付/再判定する。schema/URLはまだ実装採用前、S25単独書込を維持。
  - artifact/品質の案の限界: candidateと別inodeのcreate-only公開namespaceへcopyし、全writer終了/fsync/全読戻し、別名/上書き/読取中回収禁止を全アプリwriterに適用する案。同FD/permissionだけで任意の外部in-place書込を防げたとはせず、開始前拒否と途中検出中断の限界を明記する。製品公開gateは未接続の正式変換proofを要求し、技術fixture/boolean書換を拒否する。test用authority/factoryと製品wire実接続試験の境界は実装前にmainが具体化する。S26 proof schema/validatorはS26へ残し、未成立をfixtureで合格にしない。
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
  - 読取引渡し（2026-10-10、registration_probe_audit/main）: TemporaryMediaReceipt.photoHandoffは完全範囲/同版/content/未解放photoHandoff使用権/capturedAtの値検証を既存試験付きで再利用可能。ただしPhotoKitが読めるlocal媒体の解決/実保持Port、Photos intent/result/localIdentifier/権限/現在存在の型・同writer commandは未実装。MediaRequestはupload/download/playbackだけのため遠隔自動再開規則をPhotosへ転用しない。O-PORT/STOREがschema5/journal/exact commitを加算し、S25未完でも専用resolver＋合成MOV/明示fixture日時による実PhotoKit下位処理・disk再open・非再追加を先行できる。SDK performChangesに取消しhandleなし、Task取消しを未実行/解放とせず完了まで媒体保持、shouldMoveFile=false。用途文2件はO-COMPOSEの前提追加が必要。製品暦日時producerはS41未接続、対応不明/限定/未発見は要確認、日時・名前による推定同定は不可。アルバム/手動再保存/上限期限は未合意のまま。調査のみで書込/PhotoKit/新試験なし。
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

- [x] Status: done
  - E-S41-V01 / 2026-10-17 独立検証: `implementation_validator` がP1/P2修正後を限定合格・指摘なしと判定。173入力と旧保存再生統合の依存不変を照合し追加build/test不要、検証中347file不変。報告/構成確認/照合は `evidence/20261017-s42/s41-validation-report.txt` と同名関連証跡を参照。その後のS42変更はS42の限定回帰で確認し、S42独立検証は別に残す。以下E-S41-03の未検証表記は当時の履歴。
  - E-S41-03 / 2026-10-17 修正完了: P1はNative本番submitが使用する開始判定で、現行WB所有・未試行の開始要求のSDK前提不成立だけに `notStarted` 終端を一度生成。旧世代/別context/重複/開始済み要求へ終端を偽装せず、一般commandFailed規則は保持。coordinatorの保存待機が終わり、再準備→再RECと離脱解放に進める。未開始をファイル確定・正常保存へ昇格しない。
  - E-S41-03 / 離脱境界: 明示入場ごとにvisitを発行し、load/discover/設定適用/prepareとViewの連続呼出しを同visitへ束縛。各await後にvisit/離脱/取消を照合し、準備完了前は各呼出しが自身のdeviceを所有。旧処理・旧shutdownが新しいdeviceやbusy状態を消さない。録画/保存ownerは終端まで継続。背景後は新しい本人操作で再準備する。離脱中に遅延設定saveが完了した場合は再読込を要求し、変更された記録方式の旧準備を再利用しない。
  - E-S41-03 / 検証: Xcode27.0(27A266a)/Swift6.4、`FrameRelay.xcodeproj` / scheme・testPlan `FrameRelay` / Debug、実在Simulator `DFE46693-E8DD-4814-8957-4F327699F719`（iPhone18 Pro、iOS27.0）を再確認。最終 `final-tests` はUnit50宣言/71展開ケース＋UI1件成功、失敗0/skip0/runtimeWarnings0。新規23ケースはNative開始前WB/session/audio拒否・不正/重複開始、coordinator終端/再準備/離脱、遅延load/discover、factory/discover/prepare/previewの離脱と取消、再入場・旧shutdown・記録方式変更を故障注入。既存保存/保存再open、REC/STOP、探索経路、設定、Simulator通常撮影→一覧復帰も確認した。最終Simulator buildとgeneric iOS `CODE_SIGNING_ALLOWED=NO` build成功。Swift/compiler/analyzer診断0、ログには既存AppIntents依存なしのmetadata警告あり。初回同範囲成功後、遅延設定save後のload整合を修正し最終版で再実行した。
  - E-S41-03 / 証跡・main差分確認: `evidence/20261017-s41-fixes/` にcommands、環境、実行log/summary、source hash、変更patch、所有確認、変更後snapshotを保存。xcresult/DerivedData/開始時snapshotは上記一時root、具体パスは `commands.txt` と `*-run.json` を参照。開始時345file中6変更（5ソース＋tasklist）/339不変、新規2ソース、欠落/所有外変更0。最終build/testの173入力fileと現物hashを照合し、`git diff --check`成功。project/Ports/保存lifecycle/永続docsは不変で、既存設計の非同期寿命・世代照合を回復する修正としてrequirements/designは変更しない。
  - E-S41-03 / 限界・次工程: 故障注入は本番の開始判定とApplicationのPort境界で実行し、実AVCaptureSessionの故障・実カメラ録画を再現したものではない。実行可能iOS実機がdestinationにないためD01/G2B・Log/ProRes・実権限/画質/負荷は未確認。S16の既知未達監査、S27保留、S42以降、4段階全体の未完了は保持する。独立最終検証は未実施、同steeringの明示 `$validate-implementation` へ引き渡す。
  - 2026-10-17 修正再開時: 独立検証のP1/P2を受領。過去のUnit40ケース/UI1件・build成功は両故障経路の再現証拠ではなかった。S41をin-progressへ戻して限定修正・回帰を行った。
  - 修正所有: `s41_fix` worker＝NativeExplorationCapture.swift、必要な同Platform/Captureの開始判定補助、ProductCaptureCoordinator.swift、ProductCaptureView.swift、ProductCaptureSettingsView.swift、ProductCaptureCoordinatorTests.swift、必要なPlatform/Capture回帰test。`s41_fault_paths` explorer＝読取調査のみ。main＝tasklist・証跡・確認済構成でのbuild/test・差分確認。基準版から限定加算し、project/共有Ports/保存lifecycle/永続docsは所有外として保持。
  - 2026-10-16 本人が「はい」と回答し3点を承認。初回fpsは未選択から24/30を本人選択、2記録候補を保持して自動切替なし、暦撮影日時はREC受付時に一度確定。REC有効化と承認事項同期を再開。前回170sourceのhash差分0、既存変更を保持。所有: worker=s41_ui（ProductCaptureFactoryのみ）、document_author=s41_docs（functional-design/architectureのみ）、main=design/tasklist/証跡・最終diff。
  - 完了状態: `ProductCaptureFactory`から`calendarNow: { Date() }`を注入し、準備条件成立時のRECを有効化。初回fps/二候補/日時の合意をdesignと関連docsへ同期。S12の共通保存とS16の既存一覧/原本再生への接続を満たし、今回のS41実装範囲を完了とする。I＝必要接続を含む実装済み、A＝E-S41-01/02、D0、R＝自動検証による部分証拠（PRD全受入ではない）。
  - E-S41-02 / 追加検証: 同じproject/scheme/Test planと実在destinationを再確認。承認反映後170sourceで関連Unit13宣言/14展開ケースとUI1件が成功、失敗0/skip0/runtimeWarnings0。generic iOS署名なしbuild成功。Swift診断なし、AppIntents依存なしの既存SDK警告あり。前回48ケース全体を再実行せず、今回のfactory接続に関係する設定/coordinator/共通保存→実AVPlayer/UIに絞った。実機撮影を自動検証成功へ含めない。
  - E-S41-02 / main最終差分: 今回baseline345file中5file変更/340file不変、新規/欠落/所有外変更0（証跡除外）。App/Test/project170fileは実行時hashと一致、前回実行版との差分はfactoryの時計注入1行のみ。`evidence/20261016-s41-approved/` にcommands/log/xcresult/summary/source hash/main-scope-review/changes.patch/変更後snapshotを保存。S41初回開始からは既存16変更＋新規16file、S27本体・保留証拠は保持。
  - 現在のsubstatus: 設定・SDK二候補・通常UI・REC有効化・save/bind/一覧/既存原本再生接続・限定自動検証＝完了。実カメラ/両方式D01・G2B・権限拒否実機・Movie実出力metadata・Log/全編完全性・画質/負荷＝未確認。S16の未達アクセシビリティ監査は残る。S42以降・S27詳細検証・独立validationは開始していない。
  - 2026-10-16 前回停止時の状態: **S41の設定/SDK/画面/共通保存/一覧再生の接続と限定自動検証は実施済み、本人判断待ちで通常RECは未有効化**。初回fpsを未選択にする案、Movie/sample writerの2候補を交換可能・実機採用保留で接続する案、暦撮影日時をREC受付時に一度確定する案を質問済み・回答未受領。`ProductCaptureFactory`は`calendarNow`未注入、coordinatorの既定nilで`canRecord=false`を維持。未回答を承認と扱わず全体doneにはしない。S42以降は未着手、S27詳細検証は保留。
  - 前回停止時のsubstatus: 共有保存契約・希望設定永続・条件照合・SDK二候補・通常UI・save/bind/一覧/既存原本再生の接続・限定自動検証＝実装/確認済。製品REC有効化＝判断待ち。実カメラ/両方式D01・G2B・権限拒否実機・Movie実出力metadata・Log/全編完全性・画質/負荷＝未確認。S16の未達アクセシビリティ監査を解消扱いにせず、既存の部分接続を再利用した。
  - 前回停止時の再開案（上記E-S41-02で実施済み）: 本人が3点を確定後、fps回答に合わせ必要なら初回draftのみ調整し、REC受付日時案なら`ProductCaptureFactory.make`から`calendarNow: { Date() }`を注入する。日時は同一観測をミリ秒精度へ一度揃えてintentと両出力metadataへ渡す候補。実記録開始日時を採る回答なら意図commit/metadata契約から再検討する。承認された判断だけdesign/関連docsへ同期し、変更に必要な確認を実施してS41完了可否を判定する。S42へ自動移行しない。
  - 実装内容: カメラはuniqueIDで保存しformatは現在の条件から再照合、設定は`CapturePreferenceStore`で別atomic文書へ保存。希望/能力scope/読戻しを分離、未知/非対応/不一致/古い世代を採用しない。試験票・試験上限を通常経路から分離し、共通保存の予約済みURLを使ってintent commit後にREC。終端/実file→保存結果commit→内容bind→一覧refreshまで所有を保持し、途中STOP/背景/一覧refresh中の次RECを処理する。日時契約はschema7、旧記録はnilのまま非破壊読取移行。保存検査unknownを正常保存へ昇格せず既存原本再生へ接続。関連安定文書はfunctional-design/architectureの限定追記のみ。
  - E-S41-01 / 検証: Simulator build-01成功、generic iOS署名なしbuild-01/02成功。限定Unitは**33テスト（引数展開48ケース）成功・失敗0/skip0**、新規通常設定/保存/metadata/共通保存→再open→一覧から実AVPlayer進行と旧保存/移行の重要条件を対象。UIは試験票なしの通常撮影入口→Simulator理由表示→一覧復帰**1件成功**。実MOVへ書いたcreationDateの再読取も成功（Movie実カメラmetadataは未確認）。Swift診断なし、既存AppIntents依存なしのSDK警告のみ、xcresult runtimeWarnings空。必要範囲以外のS27 HTTP/pytest/全体Unit・S16全監査は実行していない。
  - 証跡/差分: `evidence/20261016-s41/` の`test-01-sources.json`（App/Test/project170file、Unit/UI/最終iOS build後hash一致）、各log、xcresult/summary、commands.json、main-scope-review.json、changes.patch。開始時329fileから既存15file変更＋新規16file、欠落0、所有外変更0（evidenceを除く）。S27は`PublicationHTTPFixtureTests`のreader→RenditionPlaybackInput互換3行だけ補正し、本体/保留証拠は保持。mainが差分/新規境界/旧変更保持を確認、独立validationは未実施。実装が完了した後の別工程は同じsteeringへの明示`$validate-implementation`。
  - 2026-10-16 S41再開: ユーザーの明示implementで通常撮影動線だけ着手。mainが進捗/判断/統合を所有。S27差分と未検証事項を保持し、S42以降は開始しない。開始時329fileを `evidence/20261016-s41/baseline/` と `baseline-sha256.json` へ保全、既存重複ファイルはこの現物への加算変更に限定する。substatus: 調査/契約整理in-progress、設定/SDK/UI/保存接続/検証pending。初回fps・記録候補・暦日時観測点を本人へ確認中で、回答依存部分は未着手。
  - 担当/所有: `s41_save_contract`＝RecordingEvidence/RecordingStoreDocument/日時store test＋限定migration期待値＋新規保存再生統合test、`s41_capture`＝Application/Capture（保存lifecycle除外）/Domain/Capture/Platform/Capture/新規ProductCapturePorts・CapturePreferenceStore＋関連test、`s41_ui`＝新規撮影UI/ProductComposition/ContentView/Library入口・日時表示/project用途文/UI test。main＝進捗/統合/限定検証/差分確認、S27 test API互換1か所（PublicationHTTPFixtureTests）のみ。共有契約実装済・検証待ち、設定/SDK/通常UI接続in-progress。
  - 構成確認: Xcode27.0(27A266a)、Swift6.4／言語5.0、iOS27.0、project/scheme FrameRelay、Debug、既存Unit/UI targetとTest plan FrameRelay、実在Simulator `DFE46693-E8DD-4814-8957-4F327699F719` を確認。初回enumerate操作はtest action未指定で通常build成功（テスト証拠ではない）。test action付きの列挙は既存S27 PublicationHTTPFixtureTestsのRenditionPlaybackInput型不一致でexit65/0件。mainがfixture検証済media_typeに合わせ呼出しだけ修正、S27実通信は未実行。証拠 `evidence/20261016-s41/environment.json` と初回log。
  - 次セッション向け読取引渡し（2026-10-16）: 通常設定保存/条件復元→製品coordinator/カメラ画面→共通保存/一覧を先行する案。DesiredCaptureSettingsと能力scope、CaptureLifecycle/OriginalSaveCoordinatorは再利用し、Nativeのticket依存/試験上限/二重reserveを製品経路へ持ち込まない。録画意図のtrialReference必須表現と暦撮影日時/媒体metadataの共有変更、列挙順camera-N/format-Nに依存しない識別が必要。既存S27のProductComposition.mediaTerminationを保持し、カメラは撮影入口で遅延準備、Simulator/権限拒否でもLibraryを起動する。初回fps・記録候補・撮影日時の確定点は未採用値を黙って転用せず着手時に整理する。現時点は提案/読取だけでS41書込未開始。
  - Depends: Start＝N01・既存P05/P06契約（設定・SDK候補・画面の独立実装）。Finish＝S12,S16の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE＋O-COMPOSE（直列）／`FrameRelay/Application/Capture/`（保存lifecycle除外）、`FrameRelay/Platform/Capture/NativeExplorationCapture.swift`、`FrameRelay/Domain/Capture/`、`FrameRelay/Features/Capture/`、`FrameRelay/Composition/` と対応test。
  - Done when: 保存設定・条件付き復元、希望／能力／実値、記録二候補と共通保存を接続。実機採用値／G2B未確認を保持。
  - 実装引渡しメモ（2026-10-04 read-only確認）: 既存 `RecordingIntent.acceptedAt` は `ExplorationCaptureValues.now()` のhost monotonicであり、暦上の撮影日時へ変換できない。製品撮影では実際の撮影日時を別に観測・保存し、媒体metadata／転送／Photosの同一日時へ渡す必要がある。共有保存契約はO-PORT/O-STOREへ依頼し、旧記録へ現在時刻やfixture日時を補わない。`TemporaryMediaReceipt.capturedAt` の取得日時代用を避ける。
  - 独立Startの読取引渡し（s26j_map/main、2026-10-14）: 希望/能力scope/実値とMovie・sample writer候補は再利用可能。製品CaptureConfigurationPort adapter、撮影前設定の独立保存/条件復元、製品撮影UIは未接続。discover()のcamera-N/format-Nは列挙順であり永続機器識別へ無条件採用しない。現在条件の能力照会→適用→読戻しが必要で、識別方式は未採用、未合意の初期fps/資源閾値を追加しない。探索ticket必須/再prepare拒否/探索timerを製品仕様へ流用せず、O-CAPTUREの独立StartとO-PORT/O-STOREの共有契約、直列O-COMPOSE接続を分ける。Library生成はcamera非依存を維持。
  - Finish/検証の読取引渡し（2026-10-14）: S12のbeginが予約した原本をNative側で二重reserveせずreservedURLへ接続する。両記録候補の暦上撮影日時を同じ意味で一度確定するproducerと媒体metadata設定が不足し、観測点は未採用。実store再open、列挙順変更/format消失/旧世代callback/適用不一致、予約一回・intent前REC禁止・早期STOP・遅延event、日時/metadata整合、Simulator camera unavailable時のLibrary導線を自動検証対象とする。実カメラ能力・両候補D01/G2B・実Log parser/全編再生/品質は実機側の未確認を維持。今回の調査は読取のみ、build/testなし。
  - Verify: V-CAPTURE、非対応／未知／適用不一致、無断代替拒否、保存経路・UI。
  - Stop: D01未採用を正常実原本へ偽装、撮影不可で製品Libraryも起動不可。

### S42 WB固定・再固定・記録終端を完成

- [x] Status: done
  - 2026-10-18 S43合意後の報告引渡し状況: 音声復旧案への承認は受領したが、S42修正後の独立再検証報告本文/保存先は未受領。依頼された判定・指摘・範囲の反映は保留する。`evidence/20261018-s43-approved/handoff-notes.txt` に未受領と探索範囲を記録。S43実装完了をS42独立再検証の結果へ転用しない。
  - 2026-10-18引渡し: 今回の修正後独立再検証結果は本文/保存先の受領待ち。以下の「独立検証未実施」は修正完了時の履歴であり今回判定を表さない。前回test-01の174管理対象入力とS43開始baseline、git ignoredのscheme管理plist1件と構成照会後の現物が一致（計175入力、`evidence/20261018-s43/s42-handoff-check.json`）。修正前P2報告・実装時成功を今回結果に転用しない。
  - E-S42-02 / 2026-10-17 P2修正完了: Nativeのrefresh開始throwをcommandFailed通知前に現在録画contextへ記録し、adapterFailure STOPも保持する。本番共用のNativeRecordingTerminationでMovie/sample writer終端へ渡し、STOP時の固定成功で失敗を.completedへ戻さない。本人STOPが先行してLifecycleから追加のadapterFailure STOPが出ない場合も保持する。初回REC/旧clip/非activeのcommand失敗を混入させず、リセット位置と既存音声/SDK終端失敗優先を維持した。
  - E-S42-02 / 関連検証: 実Lifecycle→本番WB順序→本番共用終端→実SaveLifecycleで両方式×本人STOP先行有無を確認。完全な合成検査でも部分保存(元理由)、次clipは通常保存。新規3宣言/7ケースを含む関連Unit43宣言/65展開＋UI1成功、失敗/skip/runtimeWarnings 0。Simulator test buildとgeneric iOS署名なしbuild成功、compiler/analyzer診断0、既存AppIntents metadata警告あり。Xcode27.0(27A266a)/Swift6.4・言語5.0・iOS27.0、FrameRelay.xcodeproj / scheme・plan FrameRelay / Debug、実在Simulator `DFE46693-E8DD-4814-8957-4F327699F719` と3target/Test actionを再確認。
  - E-S42-02 / 証跡・main差分: `evidence/20261017-s42-p2-fix/`。test-01/ios-build-01の各175入力が実行中不変・現物hash一致。Native1fileと本tasklistだけ既存変更、新規NativeRecordingTermination/Testsの2file、開始時の残り345fileと旧証跡は不変。project/設定/共有Ports/保存契約/UI/docs/designへの変更なし。git diff --check成功。実SDK throw/KVO・実機色/継続性/最終フレームは未確認、修正後独立検証は未実施。
  - 2026-10-17 P2限定修正開始: 独立検証で要修正1件。再測定開始時のSDKロック取得失敗→adapterFailure STOP→停止時の固定成功で、失敗理由が失われ`.completed`終端を生成する。現行実検査adapterは結果不明を維持するが、完全な検査証拠では正常保存へ分類され得る。既存failure fakeは自ら中断を生成するため該当分岐の証拠にならない。
  - 所有: main＝tasklist・証跡・構成確認・build/test実行・差分統合。`s42_p2_test_seam` explorerの最小境界調査を完了し、`s42_p2_fix` workerへNativeExplorationCapture・新規NativeRecordingTermination・対応testを割当。STOP理由保持/終端生成だけを本番とtestで共有し、実Lifecycleの開始失敗→固定後停止→完全検査でも部分保存を検証する。旧成果を戻さず、仕様/UI/共有保存契約は変更しない。
  - substatus: 原因追跡/限定修正/回帰試験/実行検証/main差分確認は完了。実機色/継続性/最終フレームと既知残件は維持。修正後の独立検証は別明示工程。以下E-S42-01は修正前の実装・検証履歴。
  - E-S42-01 / 完了状態: 通常撮影にWB状態/未確認理由/本人合わせ直しを接続。現在能力が確認できた録画中だけ有効とし、連打・開始中・停止中・離脱後を拒否。Nativeのone-shot測定→Locked観測→現在値固定の適用と実gain読戻しを接続。STOP/離脱/音声障害は測定を失効して固定適用後に記録停止、固定失敗は中断を保持する。初回RECは安定待ちなし、記録終端後Auto、次clipは新測定。旧KVO/固定callbackをcontext/tokenで拒否し他露出設定APIは変更しない。
  - E-S42-01 / 最終検証: Xcode27.0(27A266a)/Swift6.4・言語5.0・iOS27.0、FrameRelay.xcodeproj / scheme・test plan FrameRelay / Debug、実在Simulator `DFE46693-E8DD-4814-8957-4F327699F719` を再確認。test-02はUnit64宣言/89展開ケース＋UI1件成功、失敗/skip/runtimeWarnings 0。本人再固定・測定/適用待ちSTOP・離脱・音声障害・固定失敗・旧/逆順通知・二本・他手動値維持・未確認能力decodeを確認。S41開始拒否/遅延準備の回帰、実MOV→共通保存→再open→一覧→実AVPlayerも成功。Simulator testのbuildとgeneric iOS署名なしbuild-02成功、compiler/analyzer診断0、既存AppIntents metadata警告あり。
  - E-S42-01 / 証跡・main差分: `evidence/20261017-s42/` に実行command/log/summary/source hash、初回compile失敗、S41独立検証報告、開始時manifest、今回差分と変更前後copyを保全。最終2実行の173入力と現物hash一致、13file変更/334不変、所有外/欠落/新規ソース0、`git diff --check`成功。既存のproject/Ports/保存/store/Composition/S27差分は不変。code9file、永続docs2file、design/tasklist2fileだけを加算した。
  - substatus: WB境界・SDK候補・通常UI・S41製品接続・関連自動検証＝完了。実one-shot/KVO・実カメラ故障・色/最終フレーム・録画継続性・D01/G2Bは未確認、A03/DV-03へ引渡す。Simulator UIは未確認/無効表示と一覧復帰だけで、実録画中のUI操作を実機成功としない。旧探索P10の保留UI、S16監査、S27詳細保留、S43以降未着手を保持。S42独立最終検証は未実施。
  - 2026-10-17開始: S41独立検証合格後、本人の明示implementでS42だけ開始。既存WB契約/Native候補を継承し、S41のnotStarted終端・visit/取消・SDK所有解放を保持する。substatus: 調査in-progress、WB境界/UI製品接続/関連自動検証pending、実機色/連続性は未確認。
  - 所有: main＝本tasklist・証跡・build/test実行・最終diff。`s42_map`＝読取調査。予定worker `s42_impl`＝Application/Capture（RecordingSaveLifecycleを除く）、Domain/Capture、Platform/CaptureのWB制御、Features/Captureと対応testのみ。共有Ports/Composition/保存/store/project/docs変更が必要なら着手前にmainへ依頼し、重複所有しない。
  - 調査/内部方式（2026-10-17）: `s42_map` の読取調査とXcode27 SDKのAVCaptureDevice契約を根拠に、本人操作で対応するone-shot Autoを開始し、Lockedへの遷移観測→現在gain固定の適用完了で再固定を確定する。固定の測定秒数・色の品質閾値は追加しない。機器のmode/custom gains能力を照合し、未確認/非対応を成功にしない。STOP競合は測定観測を失効させ、現在値の固定適用後に記録停止する。SDKと同じ順序制御を故障注入対象とし、実機色/継続性はDV-03へ残す。
  - worker `s42_impl` へ上記所有を正式束縛。Domainの後方互換optional再固定能力、Native制御、coordinator操作/可否、WB状態/操作UIと関連testを実装中。既存通常撮影UI fixtureはないため、専用Composition導線は追加せず、Simulatorの未確認/無効表示と一覧復帰をUI検証し、録画中の境界はApplication/Native共用制御testで検証する。
  - 初回検証: 確認済みXcode27/Debug/FrameRelay scheme・test plan/iOS27 Simulatorで関連test-01を実行したが、新規WB順序testのmutating呼出しを直接 `#expect` に渡したマクロ展開がcompile errorとなりexit65、テスト0件。generic iOS署名なしbuild-01は成功。両実行の172ソース入力は実行中不変。旧失敗は一時rootのlog/xcresult/summaryへ保持し、workerがtest記述とcurrent-gains固定時の実適用読戻しを限定補強中。成功へ読み替えない。
  - 文書所有追加: `s42_docs` document_authorがfunctional-design/architectureのWB操作/SDK境界だけを限定同期。mainがdesignのS42内部方式を追記。既存文書差分を保持し、実機品質の達成や要求変更は記載しない。
  - Depends: Start＝N01・既存WB契約（境界制御・UI・単体試験）。Finish＝S41の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/Application/Capture/`・`FrameRelay/Platform/Capture/` のWB制御、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 安定待ちなしREC、本人再固定、最後の記録フレームまで固定、終端後Auto・次クリップ新測定。
  - Verify: V-CAPTURE、早期STOP／遅いcallback／逆順／二本・他手動値不変。
  - Stop: ND完了でWB固定、記録終端未確認でAuto、自動再固定。

### S43 音声メーター・障害・有限復旧を完成

- [x] Status: done
  - E-S43-02 / 合意・接続完了: `ProductCaptureFactory.provisionalAudioPolicyV1` に無到着2秒・本人再試行ごと1回・復旧上限5秒を集約し、同一policyをNative/coordinatorへ明示注入。音声入出力だけの再構成、復旧中の無到着2秒判定、SDK終了待ち、自動REC禁止は既存本体を接続。design/functional-design/architecture/PRD Q10の音声合意を同期した。暫定設定と実機採用は分離する。
  - E-S43-02 / 現在のsubstatus: E-S43-01の音量/入力/到着/書込、静寂正常、障害時の抑止/停止/保存結果、通常UI/探索互換に加え、暫定製品policy合意・Factory接続・有限復旧/手動RECの関連検証/main差分確認を完了。S43の実装範囲はdone。実音声/同期/OS故障/両方式/復旧品質はA10/DV-10未確認、独立validationは別セッション。S42報告未受領は独立した引渡し残件として保持。
  - E-S43-02 / 最終検証: Xcode27.0(27A266a)/Swift6.4、`FrameRelay.xcodeproj` / scheme・testPlan `FrameRelay` / Debug、実在iOS27.0 iPhone18 Pro Simulator `DFE46693-E8DD-4814-8957-4F327699F719` のApp/Unit/UI Test actionを確認。test-03はUnit19宣言/23展開＋UI1成功（新規2宣言）、失敗/skip/runtimeWarnings 0。Factory経由の同policy/実5秒timeout、1本人操作1試行、失敗/timeout後の本人再試行、重複拒否/実終了待ち/自動RECなし、無到着2秒境界、旧音声規則・保存/実原本再生・通常画面起動/一覧復帰を確認。Simulator test buildとgeneric iOS署名なしbuild-01成功、compiler/analyzer診断0（ログに既存AppIntents依存なしmetadata警告）。
  - E-S43-02 / 失敗と版照合: test-01は新規testのmacro内throw2箇所でcompile失敗/0件実行し、workerが期待値構築だけをmacro外へ移した。test-02は未変更actor3宣言の隔離診断/同期init警告3件でcompile失敗/0件実行。explorerが旧成功版hash・設定不変を照合し、同一182入力の新DerivedDataによるtest-03成功を確認した。増分状態/型属性推論は仮説のまま、原因を断定せず記録。最終182入力と現物一致。generic iOS build後の差分は新規Unit test1fileのみで、App/project不変のため同build成功を継承。
  - E-S43-02 / 証跡・main差分確認: `evidence/20261018-s43-approved/` に実行command/環境/ログ/summary/source hash、変更前後/最終source snapshot、patch、所有照合、文書レビュー、S42報告引渡し状況を保存。xcresult/DerivedDataと開始時証跡外355fileは `/private/tmp/fr-s43-approved-20261018-1rjgalcn/`。既存8file変更/6197不変、新規test1file、欠落/旧証跡変更/所有外変更0（追加証跡除外）、git diff --check成功。requirements/project/共有Ports/store/保存契約/Native/coordinator本体/S27は不変。doc_reviewerのP2（既存の復旧失敗案内を未決に戻す文言）は同U7行の修正後に解消・追加指摘なし。
  - 次工程: 同steeringへの明示 `$validate-implementation` をS43限定で別セッション実施。今回の実装内test/main差分確認は独立検証ではない。S27詳細・S44以降へ進まない。以下は今回と前回の実装経過。
  - 2026-10-18 合意後再開: 本人が無到着2秒・本人retryごと音声入出力のみ1回・復旧上限5秒（復旧中も無到着2秒判定）の暫定案を承認。同一policyの製品Factory接続と関連試験を本S43内で実施する。過去の判断待ち記録は履歴として保持。S42再検証報告本文/保存先は別の未受領事項として残す。
  - 合意後test-01: 実在構成を再確認して限定testを実行。新規Composition試験のthrowing値を含むSwift Testing macro 2か所でcompile失敗、exit65/実行0件。generic iOS署名なしbuild-01は成功。各182入力は実行中不変。証跡を `/private/tmp/fr-s43-approved-20261018-1rjgalcn/` に保持し、workerへ新規testだけの修正を戻した。製品接続本体のcompile診断は0、既存AppIntents依存なしSDK警告のみ。
  - 合意後test-02: 新規testの期待値構築をmacro外へ移して再実行。既存ProductCaptureCoordinatorTestsの未変更actor3宣言でnonisolated適用診断・同期init警告3件が発生し、exit65/実行0件。初回失敗後の増分状態と新testの参照の影響を限定調査中。ソース182入力は実行中不変、失敗結果を保持する。
  - E-S43-01 / 部分引渡し: 両記録候補の実PCM観測、音量/入力/到着/書込表示、静寂・音量上限と故障の分離、開始抑止/停止/保存分類、旧通知拒否を接続。Movie観測sampleを個別書込成功にせず取得不能を保持。本人STOP先行/SDK完了でも障害を正常保存へ戻さず先行WB理由を保持。既存探索もchecking準備後の遅延sampleを受け取り再準備なしでRECへ進む。
  - 前回部分実装時のsubstatus: 音声観測/確認済み故障処理/通常UI/探索互換/有限復旧本体/注入試験/main差分確認＝完了。無到着猶予・復旧policyの製品採用/Factory接続＝本人判断待ち。未接続を「実機未確認だけ」と扱わない。実機音声/同期/OS故障/両方式/復旧品質はA10/DV-10へ残す。
  - 当時の再開条件（音声はE-S43-02で解決）: 本人が猶予・開始方法/回数/timeout/再構成範囲を確定後、Nativeとcoordinatorへ同policyを注入し関連検証する。S42報告は受領後に反映する。S27詳細・S44以降・独立validationを自動開始しない。
  - E-S43-01 / 最終検証: test-03 Unit60宣言/87展開＋UI1、test-04 Unit26宣言/32展開が全成功。test-03から最終版はExplorationPorts/Coordinator/対応testの3fileだけが変わり、その範囲をtest-04で再検証して他の不変証跡を継承。重複除外73宣言/102展開ケース、失敗/skip/runtimeWarnings 0。最終181入力はtest-04/ios-build-02/現物一致。Simulator test build・generic iOS署名なしbuild成功、compiler/analyzer診断0（既存AppIntents SDK警告のみ）。新規試験計19宣言、既存UI1件の音声未確認/再試行無効表示も確認。実録画UI/実カメラ音声の合格ではない。
  - E-S43-01 / 証跡・main照合: `evidence/20261018-s43/` に各runのcommand/source/hash/log/xcresult/summary、途中失敗、環境、変更前後copy/差分、文書レビュー/所有照合を保存。開始時5521file中17変更/5504不変、新規6source、欠落/旧証跡変更/所有外変更0（archive追加除外）。git diff --check成功。requirements/project/言語/OS/共有store/保存契約/S27差分は保持。以下は実装経過。
  - 2026-10-18開始: S43限定の明示implementを受領。mainが本tasklist・判断・証跡・構成確認・限定build/test・最終差分を所有し、`s43_map` explorerが既存音声契約/SDK/製品接続を読取調査する。書込workerの具体所有は調査後に束縛する。未合意の障害猶予・復旧回数/時間・再構成範囲を製品採用済みにせず、必要判断を切り分ける。
  - 所有束縛: `s43_impl` workerがO-CAPTUREの音声Domain/Recovery/Native/専用部品、CaptureLifecycle/ProductCaptureCoordinator、ProductCaptureView/専用音声UIと関連testを単独所有。O-PORTとしてProductCapturePortsと音声専用新規Port、O-COMPOSEとしてProductCaptureFactoryだけを直列に引き渡す。共有store/保存契約/project/その他Compositionは凍結し、必要変更はmainへ戻す。mainがtasklist/証跡/build/test/差分確認を担当する。
  - 未合意判断: 本人へ無到着2秒・本人の再試行1回につき音声入力/出力だけを1回再構成・5秒timeoutという変更可能な暫定案を確認中。未回答を承認とせず、注入可能な処理・試験を先行し製品既定値の採用は回答待ちとする。S42修正後独立再検証は保存報告を発見できず、本文/保存先を確認中。修正前P2報告や実装時成功で代用しない。
  - substatus: 契約/SDK/接続調査完了、meter/障害/有限復旧/通常UI/関連test実装in-progress、製品policy採用判断待ち、実行検証pending。実機音声・同期・障害猶予/復旧品質はDV-10へ残す。S27詳細・S44以降は未着手。
  - 初回検証（test-01）: 確認済みXcode27.0(27A266a)/Swift6.4・言語5.0/iOS27、FrameRelay.xcodeproj/scheme・plan FrameRelay/Debug、App/Unit/UIの有効Test actionとboot済みSimulator `DFE46693-E8DD-4814-8957-4F327699F719` で限定試験を開始。test helperのnonisolated actor宣言がcompile error、旧AVAudioFormat initializerとactor initializerの新規警告もありexit65/0件。181入力は実行中不変。`/private/tmp/fr-s43-20261018-v4sxn_hx/test-01*` に失敗を保持し、workerへ限定修正を返した。
  - test-03 / ios-build-01: テスト側の復旧受付待ちを保存終了だけからWB Auto復帰を含むcanRetryAudioへ修正し、実PCM helperのsending警告を解消。Unit60宣言/87展開ケース＋UI1が全成功、失敗/skip/runtimeWarnings 0、Simulator test build・generic iOS署名なしbuild成功、compiler/analyzer診断0（既存AppIntents SDK警告のみ）。各181入力は実行中不変。復旧policyは未注入のままで、注入fixtureの成功を製品有効化へ昇格しない。
  - 最終差分中の互換修正: 共有Nativeがprepareで音声checkingを返す場合、既存ExplorationCoordinatorが待機中の後続sampleを受け取れずRECへ進めないことを検出。同workerへExplorationPorts.swift/ExplorationCoordinator.swift/既存ExplorationCoordinatorTestsの3fileだけを追加所有し、既存snapshotの世代/clip/順序照合による互換接続を実施する。探索gate・復旧機能やS27詳細/S44以降へ範囲を広げない。
  - test-02: compileは成功、Unit60宣言＋UI1件中60成功/1失敗、skip/runtimeWarnings 0。復旧後の次RECを検査する新規coordinator試験1件で4issuesを検出し、送出/処理の順序と本体を点検中。PCM test closureのsending警告1件も修正対象。181入力は実行中不変。初回失敗を成功へ置換せず、test-02のlog/xcresult/summary/build-resultsを同runへ保存。
  - 所有追加: 同workerへNativeRecordingTermination.swift/対応testの音声故障時に先行WB理由を上書きしない限定変更を引渡し。次clip開始時の書込表示resetも含め修正する。文書は`s43_docs` document_authorがfunctional-design/architectureの音声境界のみ更新。`s43_docs_review` doc_reviewerが未接続表記のP2を指摘し、policy未注入/通常経路未有効の明記後に解消・追加指摘なし。
  - Depends: Start＝N01・既存音声契約（meter・入力／書込・復旧）。Finish＝S41の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/Domain/Capture/CaptureAudioState.swift`、`FrameRelay/Application/Recovery/CaptureAudioRecovery.swift`、`FrameRelay/Platform/Capture/` の音声adapter、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 音量／入力／到着／書込み実処理、静寂正常、確認済み障害で抑止／停止・保存結果、有限復旧と手動REC。
  - Verify: V-CAPTURE、無到着／書込失敗／静寂・復旧上限の変更可能試験設定。
  - Stop: 音声省略、復旧で自動REC、無限retry・App全体自動再起動。

### S44 補正選択・復元・画角状態を完成

- [x] Status: done
  - 完了記録（2026-10-18）: 規則/SDK候補/通常UI/S41実接続/関連自動検証＝完了。現在条件の候補と出力実接続を分離し、保存希望優先・初回標準候補・非対応説明を実装。両出力の支持/要求/active、世代/連番/実カメラ/format/倍率を観測し、失効後の高水位を維持。RECの受理前と原本予約後に同じ判定で再照合する。S47への画角状態供給契約までであり、実crop/preview一致・予告UI・実機品質・PRD受入を完了にしない。
  - 判断 S44-01: 既存6 SDK候補を保護し、PRD既存の標準第一候補を可逆なdraftへ具体化。新しい効果/品質・モード正式採用ではない。previewOptimizedは現4K記録に使用しない。format FOVから補正後cropを推定せず、未知の画角だけではRECを抑止しない。根拠は既存FR-03/DI-08と `sdk-observation-notes.txt` / `apple-references.json`。
  - E-S44-01 / 検証: 確認済みFrameRelay.xcodeproj/scheme/test plan FrameRelay・Debug・App/Unit/UI、Xcode27.0 (27A266a)/Swift6.4・言語5.0/最低iOS27.0。当日確認Simulator `DFE46693-E8DD-4814-8957-4F327699F719` でtest-03 Unit53宣言/76展開全成功（候補条件/OFF等3モードのstore再open/実値相違/旧通知/失効/録画中設定拒否/開始前条件/観測終了/既存音声・保存・実AVPlayer）。ui-04は通常撮影と初期設定UI2成功。generic iOS署名なしbuild成功。xcresultのcompiler/analyzer/runtime診断0、stdoutの既存AppIntents依存なしメタデータ警告は保持。
  - 途中失敗: test-01はSwift API名、test-02は新規testのmutating呼出し記法でcompile失敗/0件実行。test-03は新UIのPicker値取得が1失敗、映像上のfps未選択/標準未確認は正しく、UI testのみ修正。該当source hashに一致する失敗時copyとlog/xcresultを保持。mainレビューで発見した観測終了後の旧prepare fallbackは修正・中核test成功。
  - 実行版/差分: `evidence/20261018-s44/` の各run.json/log/xcresult/summary/sources、`main-scope-review.json`、`changes.patch`、実行入力source-snapshotを参照。test-03とiOS buildは187入力一致。最終ui-04との差分はUI test1fileだけでApp/Unit/project不変。既存16file＋新5ソースのみ、旧6445file中6429不変/欠落0。mainが全差分/所有を確認、文書レビューは指摘なし。
  - 引渡し残件: D01/実機全組合せ/3場面の補正効果/構図/音声同期/継続性/ズーム・レンズ切替維持はDV-04等。構図予告/停止支援の実consumerはS47。SDKの実KVO発火・実カメラRECはSimulatorでは未確認。S44独立検証は別明示 `$validate-implementation`。
  - 今回所有: `s44_impl` がO-CAPTUREのDomain/Capture補正契約（新規含む）、ProductCaptureCoordinator、ProductCaptureConfigurationMatcher、NativeExplorationCapture/ExplorationCaptureValuesと新補正adapter、ProductCaptureSettingsView/ProductCaptureView/ProductCapturePreview、および補正関連Unit/UI testを単独所有。共有Portの補正観測追加が必要な場合はProductCapturePorts/ExplorationPortsだけを同workerへ直列引渡し、既存WB/音声契約を保持。Composition/LocalStore/project/その他taskは凍結。mainはtasklist/design/新証跡だけを所有。
  - Depends: Start＝N01・既存能力／希望／実値契約（補正／復元規則）。Finish＝S41の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/Domain/Capture/CaptureSettings.swift`、`FrameRelay/Platform/Capture/` の補正adapter、`FrameRelay/Features/Capture/` と対応test。
  - Done when: OFF＋複数モードの対応・実適用を照合、初回候補／条件復元／非対応説明、画角世代を予告へ供給。
  - Verify: V-CAPTURE、条件変更／無断代替拒否／実値表示／旧画角失効。
  - Stop: API名を実効果として対応済み表示、標準不成立を合格化。

### S45 人物解析・主役AFの本体と接続

- [x] Status: done
  - E-S45-02 / 再開（2026-10-18）: 本人が人物なし時のタップ位置AF、初回撮影意図の本人選択・保存復元・REC非阻害、変更可能な暫定3秒の見失い猶予後の保持/再指定・別人自動移行なしを承認。E-S45-01の本体を継承し、Simulator別人拒否失敗の調査修正、通常Factory接続、必要検証だけを進める。
  - E-S45-02 / 保全・所有: 開始時7218file/155,818,979bytesのhashと証跡外snapshotを `/private/tmp/fr-s45-resume-20261018-1tlmtf7y/` に保存。未コミット/未追跡成果へ加算し、既存証跡・他task・project設定を戻さない。main＝steering/証跡/実行検証/最終差分、explorer＝読み取り調査、worker＝後記S45限定コード、document_author＝関連永続文書のみ。S46以降・独立validationは開始しない。
  - E-S45-02 / 完了範囲: 既存Domain/SDK/選択UI/意図storeを再実装せず継承。`ProductCaptureFactory.provisionalSubjectPolicyV1`（`s45-provisional-v1`、tapPosition、lostGrace=3）をNativeとcoordinatorへ同一注入。初回意図nil・本人選択後のdisk保存/復元、未選択/保存待ち/解析なしのREC非阻害、複数露出対象と一人の主役の分離、追跡OFF人物優先AF、期限後の保持/再指定を接続した。
  - E-S45-02 / 失敗原因と修正: 確認済SimulatorのFeaturePrint rev2 CPU経路で、異なる実画像が同じ768要素を返すことと初回のみ距離約0.0017806の微差を再現。ROI/明示crop/scale/CGImage/JPEG/CI software/CPU APIの比較でも残り、SDK内部原因は未確定。アプリがこの出力をそのまま同一性根拠にした欠陥を修正。同一固定ROIから上限2回得る特徴量と、Visionを通さず読む実画素digestを保持し、完全一致した特徴量なのに画素が異なる場合は同一IDの継続/再捕捉を拒否する。別画像で固定参照を更新せず、既存距離閾値・assertを緩和しない。raw buffer追加保持なし、digest/特徴量はセッション内だけ。BGRA・8/10bit 420 video/fullの全planeを扱い、不正bounds/未知形式は解析不確実へ戻す。
  - E-S45-02 / 有効性と限界: 元の別人拒否/同一画像復帰/曖昧候補拒否3件を維持。選択直後に他人が現れる直接置換/blank後置換を追加し、新appプロセス単独でも2展開成功。実画素が違う同一人物も特徴量衝突時は保持となる。Simulatorの動く人物追跡を修復・保証した意味ではなく、一般的な人物同一性/実AF/2回生成の追加負荷はDV-06未確認。
  - E-S45-02 / 最終検証: Xcode27.0(27A266a)/Swift6.4、FrameRelay.xcodeproj/scheme・testPlan FrameRelay、Debug、App/Unit/UI、Swift言語5/最低iOS27.0を確認。実在Simulator DFE46693-E8DD-4814-8957-4F327699F719（iPhone18Pro/iOS27.0）で`test-final-01`のUnit81宣言/112展開が全成功、`ui-final-01`の通常画面3件（意図選択→再起動復元を含む）が全成功。skip/runtimeWarnings 0、compiler/analyzer/error 0。`ios-build-final-01`のgeneric iOS署名なしbuild成功、compiler/analyzer/error 0。各runの202入力は実行中不変・相互一致。UIのSimulator設定は停止中退避し、実行後に元の不存在へ復元済み。buildと起動/操作を別証拠にした。
  - E-S45-02 / 実行・証跡: 完全なxcodebuild引数/日時/exit/sourcehashは `evidence/20261018-s45-resume/*-run.json`、`*-sources.json`、logs、summary/tests/build-resultsへ保存。`vision/`に診断01/02、単一参照の修正失敗、初回微差診断、最終限定成功/cold成功、診断ソースとworker-reportを保存。xcresult/DerivedData原本は `/private/tmp/fr-s45-resume-20261018-1tlmtf7y/`（Visionは同配下vision）。stdoutの既存AppIntents metadata警告・NASA JPEG decoder診断等はログに保持し、成功を実機品質へ昇格しない。
  - E-S45-02 / 所有・最終確認: worker `s45_product_connect`＝FactoryとSubjectCoordinator/SubjectSession/既存AudioComposition/UI testの5file、worker `s45_vision_fix`＝NativeCaptureSubjectAnalysisと同testの2file、document_author `s45_resume_docs`＝関連永続5文書、main＝本steering3文書/証跡。mainは最終diff・要求対応・所有範囲を確認、既存15変更/7203不変、欠落/旧証跡変更/所有外変更0（詳細main-scope-review.json）。doc_reviewerは総則の未合意表現3箇所を指摘し修正後は指摘なし。実装内test/main確認であり独立validationではない。
  - E-S45-02 / 実機未確認と次工程: 実カメラを利用可能なdestinationがなく、実合焦/前後追従/別人通過・遮蔽・同一主役復帰/追跡OFF人物優先AF/タップ座標/補正crop・preview一致/実Log入力/両記録方式の継続・同期・解析負荷/暫定3秒の実機採用はDV-06へ残す。FR-05受入は未達のまま。独立検証は明示 `$validate-implementation .steering/20260929-device-independent-implementation/` が次工程。S46以降は開始しない。
  - 以下のE-S45-01は前セッション当時の履歴。未回答/未接続/失敗は当時の状態であり、今回の確定状態はE-S45-02を参照する。
  - E-S45-01 / 部分実装: 複数露出対象と単一主役、追跡OFF人物優先AF、見失い保持/固定参照による再捕捉/再指定、撮影意図のoptional保存、通常画面/preview操作を注入可能な経路へ接続。SDKの検出/追跡UUIDを人物同一性へ流用せず、固定FeaturePrintと曖昧候補拒否を使用。入力は処理中1件+置換待機1件、解析専用dropを録画失敗にせず、記録用connectionの回転/mirrorを変更しない。世代/構図/WB/選択/時刻の照合、解析失敗・座標変換失敗と人物不在の分離、AF適用読戻しを実装した。
  - E-S45-01時点のsubstatus: Domain/SDK候補/操作UI/設定保存/関連自動検証の部分＝実装済。通常Factoryのpolicy注入＝本人判断待ち、実Visionの人物同一性確認＝Simulator1件失敗。通常アプリでは人物機能未有効、撮影意図pickerも未有効。人物未確定/意図未選択/解析失敗はREC条件に追加していない。
  - E-S45-01時点の本人判断待ち: 人物なし時のAF（提案:画面タップ位置）、初回意図（提案:本人選択後に保存/復元しREC非依存）、見失い猶予（提案:暫定3秒後に保持/再指定）。質問済み・回答未受領。試験の3秒や技術閾値を製品の合意済み値へ昇格しない。requirements/designは変更せず、製品注入を保留する。
  - E-S45-01 / 最終検証: 確認済みFrameRelay.xcodeproj/scheme・testPlan FrameRelay/Debug/App・Unit・UI、Xcode27.0(27A266a)/Swift6.4・言語5/最低iOS27.0。実在Simulator DFE46693-E8DD-4814-8957-4F327699F719で`test-final-05`はUnit76宣言/99展開中75宣言/98展開成功、1宣言2issues失敗（skip/runtimeWarnings 0）。新規24宣言のうち23成功。状態境界/世代失効/REC非阻害/設定保存/座標/AF計画/既存音声・WB・保存再生は成功。`test-01`の通常撮影/設定UI2件成功はUI不変・policy未注入の範囲で継承し、人物操作実機成功とはしない。Simulator test build・`ios-build-03` generic iOS署名なしbuild成功、compiler/analyzer診断0（stdoutに既存AppIntents依存なしmetadata警告）。
  - E-S45-01時点の未解決失敗: `realVisionDetectsTracksRejectsAnotherPersonAndReacquiresFixedReference`で別人に主役IDを与え、復帰の再捕捉区分も失敗。CPU指定後の診断03/04では、異なる実画素/検出ROIのNASA公開肖像2件から完全同一の768要素FeaturePrint（距離0）が返ることを観測。画像をmainが確認し、opaque BGRA/alpha=255を検証しても不変で透明度仮説は不支持。hostの同4ソースでは距離0.7411（自動）/0.7247（CPU）、別人拒否/同一復帰を観測した。Simulator差の原因は未確定。閾値調整・assert緩和・skipで成功化せず、最終失敗を保持する。
  - 失敗履歴/限定性: ios-build-01のVNObservation型診断、enumeration-01のmutating `#expect` 記法は修正。初回host probeの範囲外ROI拒否を交差処理で修正。test-01のVision Code9推論context失敗はSimulatorのみ標準compute APIのCPU指定で解析可能になったが、test-02/診断03/04/最終05の同一特徴量問題は未解決。一時診断は証跡へ保存してtest本体から撤去。公開画像はtest targetだけに含め、人物識別/合焦/Log/ライブ継続/負荷/両方式/補正crop・preview一致/向きの品質を証明しない（DV-06）。
  - E-S45-01 / main差分・証跡: 最終203入力はtest-final-05/ios-build-03/現物hash一致。開始時7057fileから既存11変更/7046不変、新規13file（公開fixture2件/出典を含む）、欠落/旧証跡変更/所有外変更0。requirements/design/project/設定/README/memo/S27等の既存差分を保持。`evidence/20261018-s45/`へ各runのcommands/log/summary/source hash、失敗版/変更前後snapshot/patch/main-scope-review/文書レビュー/出典を保存。xcresult/DerivedData原本は `/private/tmp/fr-s45-20261018-ow_sx8bp/`。doc_reviewerは関連2文書の限定差分を指摘なしと報告。mainの実装内確認であり独立validationではない。
  - E-S45-01時点の再開条件: 上記3回答と実Vision未解決問題を確認後に同policyをNative/coordinatorへ注入し、通常経路を限定検証する。S45全体done・実機採用・S46以降・独立validationへ暗黙移行しない。以下は実装経過。
  - 再開記録（2026-10-18）: 明示implementを受領。開始時baselineは `/private/tmp/fr-s45-20261018-ow_sx8bp/`。未コミット/未追跡成果を保全し同じ現物へ加算する。mainが本steering・証跡・差分確認を所有し、`s45_explore` がSDK/接続点をread-only調査。
  - substatus: 規則/解析SDK候補/注入可能UI・接続＝一次実装、通常Factoryへのpolicy注入＝本人判断待ち、検証＝進行中。人物なしAF・初回撮影意図・再捕捉待ちの保持秒数は確認中。仮の製品既定で補わず、独立部分を先行する。
  - 実装所有: worker `s45_impl`＝S45のDomain/Capture新規型、ProductCaptureCoordinator/新規人物調停、ProductCapturePorts、NativeExplorationCapture/新規人物解析・AF、Capture画面、ProductCapturePreferences/CapturePreferenceStoreの意図保存、ProductCaptureFactoryのS45注入、対応UnitとProductCaptureFlowTests。その他共有コード・project・docsは所有外。mainがsteering/証跡/実行検証を所有し、同じファイルへ並行書込しない。
  - 文書所有: document_author `s45_docs`＝functional-design/architectureの人物AF箇所のみ。doc_reviewer `s45_doc_review`が同差分をread-only確認。U5未合意・通常経路未注入・実機品質未確認を保持する。
  - 途中検証: Xcode27.0/Swift6.4、既存FrameRelay scheme/Debug/有効test plan FrameRelayと実在Simulatorを確認。host Vision限定probeは公開NASA肖像2件で半身検出各1件・特徴量生成を確認。初回probeの画面外ROI拒否を保持し、画像範囲との交差後に成功。generic iOS署名なしios-build-01はVNObservationの型診断でexit65、テスト実行なし。workerへ修正依頼済。証跡 `evidence/20261018-s45/`、実行原本 `/private/tmp/fr-s45-20261018-ow_sx8bp/`。
  - 追加検証経過: `ios-build-02`はgeneric iOS build成功。`test-enumeration-01`は新規testのmutating呼出しを直接`#expect`へ渡した記法でcompile失敗/0件、修正後`test-enumeration-02`は実在Test actionの列挙成功（実行成功へ数えない）。`test-01`は関連Unit73宣言中70成功/実Vision3失敗（Code9推論context生成）、UI2成功。Simulatorだけ標準compute APIでCPUを指定した`test-02`はUnit76宣言/99展開中75宣言/98展開成功、実Visionの別人拒否/復帰1宣言2issues失敗。入力203fileは各実行中不変。失敗を環境由来と決めつけず実画像/特徴量を調査中。
  - Depends: Start＝N01・既存撮影契約（解析・AF候補・状態・UI）。Finish＝S41の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/{Application,Platform}/Capture/` の人物解析／AF、`FrameRelay/Domain/Capture/` の主役・意図、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 複数露出対象と単一主役、通常AF／追従・見失い保持・同一再捕捉・再指定、追跡OFF人物優先AFを実装可能経路へ接続。
  - Verify: 非私的・合成入力の実解析、古い世代拒否、別人移行なし、REC非阻害。
  - Stop: 選択UIだけ完成、人物なし／初回意図未合意を製品既定へ採用。該当選択だけ局所保留。

### S46 ND方向・理由・保留と設定再評価

- [x] Status: done
  - E-S46-02 / 完了範囲: 本体/通常製品接続/関連自動検証を完了。2026-10-18の本人合意に従い、`ProductCaptureFactory.provisionalNDPolicyV1` は `CaptureNDPolicy.provisionalV1(maximumResultAge: 1)`。同じ値を両記録候補のdevice builder→Nativeとcoordinatorへ注入し、未校正の参考表示とする。端末内で完結し、通信・NDの保留や警告をREC条件にしない。正確な段数や実機品質を承認済みにしない。
  - E-S46-02 / 挙動検証: 新Composition試験は両候補でFactoryから渡ったpolicyを実解析queueへ接続し、実BGRA→参考案内、250msの配送遅延でも入力観測から1秒で失効、途中更新した結果を旧timerが消さないこと、失効後REC開始・方向案内/解析終了でも録画継続を確認。撮影制御はfakeであり実カメラ/WB/録画画質の証明ではない。既存NDの5画素形式/4信号・複数ROI・旧世代/入力時刻境界・失効、Subject/Audio接続、実MOV保存→一覧→AVPlayerの限定回帰を再実行。
  - E-S46-02 / 最終結果: `test-02` Unit26宣言/34展開＋通常UI1成功、失敗/skip/runtimeWarnings 0。通常UIは入口・ND保留理由（評価基準未設定ではなく入力待ち）・閉じる操作を確認。Simulator test build・`ios-build-01` generic iOS/CODE_SIGNING_ALLOWED=NO build成功、compiler/analyzer診断0。stdoutの既存AppIntents metadata警告は保持。buildのtest0件は合格件数へ含めない。
  - E-S46-02 / 最終版・証跡: test-02/ios-build-01/現物の210入力一致、run中変更0。各command/run/source hash・所有source copy・ログ・xcresult要約/test tree/build-results・開始時差分を `evidence/20261018-s46-approved/` に保存。全raw bundle/DerivedData/開始時copyは着手行の作業root。test-01の失敗版も保持し、結果は後続成功で上書きしない。
  - E-S46-02 / 最終review・保全: mainがコード/test6file、永続2文書、steering3文書の開始時差分を確認。開始時7503file中、変更10/不変7493、新規test1、削除/所有外変更/旧証跡変更0。project/README/memo/既存store等を保持。doc_reviewerは指摘なし。実装内のmain確認であり独立validationではない。
  - E-S46-02 / 引渡し: DV-07の実入力/実WB/連続Auto/ROI・crop/実写方向・反射・黒・負荷・暫定基準/1秒の採用、FR-06受入は未確認。独立検証は `$validate-implementation .steering/20260929-device-independent-implementation/` の明示で別途実施。今回の合意/Unit成功を全体完成や実機受入にせず、S47以降・他taskの既知残件を保持。
  - E-S46-02 / 着手: 2026-10-18、上記2点の本人承認を受領。mainはsteering/証跡/差分確認、worker s46_implはFactoryと関連Composition/Application/UI test、document_author s46_docsはfunctional-design/architectureのND記述を所有。開始時7503fileのhashと証跡外copyを `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-s46-approved-20261018-x4qojjkd/` に保全。既存未コミット成果・旧証跡は保持する。
  - E-S46-02 / 途中検証（履歴）: 通常Factoryの同一policy接続・両候補Composition試験・UI期待を更新。test-01は新規test内のSwift Testing property-access macroがactor隔離に違反するcompile失敗で0件実行。新規test内でlocalへ読み出す最小修正後、test-02が成功した。既存actor/言語/project設定は変更しない。command/source copy/log/xcresultは上記作業root。
  - E-S46-01 / 前回時点（履歴）: 本体・注入可能なNative/coordinator/UIと関連自動検証＝実装済。通常Factoryの同policy採用/有効化＝本人判断待ち。暫定1秒とcode-domain暫定基準による方向/理由の参考表示は質問済み・未回答。通常画面は評価基準未設定の保留を明示し、S46全体done・FR-06受入にはしない。
  - E-S46-01 / 本体: BGRA、8/10bit bi-planarのfull/video range（5形式）と実attachmentを照合し、709/sRGB/AppleLog/Log2を区別する。最大96×96標本、処理中1件＋置換待機1件。複数人物を平均で潰さず、人物外背景との相反/方向/理由/根拠不足を評価。全面黒/白・平坦・小反射だけを正解にせず、EV/IRE/正確なND段数へ変換しない。解析から録画画像/露出設定/REC可否へ書き戻さない。
  - E-S46-01 / 失効: 設定/構図/選択/意図/独立WB revision、入力時刻/順序/期限と解析失効epochを照合。選択処理中・人物欠落・停止後のin-flight復活、古い高sequence通知で現結果の期限が無効になる問題を修正。開始/変更/失効の単調時刻validAfterより前の実bufferは新contextでも拒否する。WB KVOは通知時の変化を確認しA→B→Aも失効。validAfterは保守的な観測下限でありフレーム固有gainの証明ではない。Auto WBが変わり続ける間は保留が続く可能性を実機残件とする。
  - E-S46-01 / 検証: `worker/test-06` 通常構成48宣言/64展開成功。再停止epoch修正後 `test-07` ND16宣言/22展開成功。最後のvalidAfter/KVO修正後 `test-09` Native ND12宣言/18展開成功。fail/skip/runtimeWarnings/compiler/analyzer 0。`ui-final-01` は通常撮影入口/ND保留・理由/閉じる操作1件成功。UI後の変更はDomain/Native/対応Unitの3fileのみで、UI/未注入Factory/coordinatorは不変のためUI結果を継承。`ios-build-final-01` はgeneric iOS、CODE_SIGNING_ALLOWED=NOで成功（buildでありtest0件は合格件数へ含めない）。stdoutの既存AppIntents依存なしmetadata警告は保持。
  - E-S46-01 / 版と証跡: 最終test-09の201 Swift sourceは現物・iOSbuildの209入力の対応部分と一致。各command/exit/log/source hash/summary、関連test tree/build-results、失敗/最終の所有sourceと開始時差分を `evidence/20261018-s46/` へ保存。raw xcresult/DerivedData/完全な開始時copyは `/private/tmp/fr-s46-20261018-ck1k643l/`。test-01〜03のcompile失敗・test0件を保持。診断用test-04のdisable-batch成功は通常構成の証明にしない。新規test helperのpolicy default引数を明示引数へ変えたtest-05以降は通常batchで成功し、既存actor/project設定は不変。コンパイラ内部原因は未確定。
  - E-S46-01 / 最終差分: mainが開始時7311fileと所有差分を確認。コード/対応test13file、関連永続2文書、本tasklistだけを変更し、旧証跡・project・README・memo・共有store等を保持。文書差分はdoc_reviewer指摘なし。mainの実装内確認であり独立validationではない。
  - 前回の再開条件（本人回答は今回受領）: 上記2点の本人回答後、同じ版付きpolicyを通常FactoryのNative/coordinatorへ注入し、必要なComposition/通常UIの限定検証を行う。実カメラdestinationがないため実入力/実WB KVO/補正crop座標/実写の方向一致・黒い服や反射・品質/負荷はDV-07に残す。未校正の人工入力成功を本人合意の代表場面の合格にしない。独立validationは本体の製品接続後に同じsteeringへの明示 `$validate-implementation` で行い、暗黙開始しない。他taskの独立部分へ新しい依存は追加しない。
  - 再開当初（2026-10-18、履歴）: 明示implement、開始baseline `/private/tmp/fr-s46-20261018-ck1k643l/`。S41/S42/S45の既存接続を継承。mainがsteering/証跡/統合を所有、`s46_explore` がSDK入力と世代接続をread-only調査。
  - 所有引渡し: worker `s46_impl`＝新規ND Domain/解析/調停/表示と、接続に必要なNativeExplorationCapture、ProductCaptureCoordinator、ProductCapturePorts、ProductCaptureFactory、ProductCaptureView、対応Capture Unit/Composition/UI testだけ。mainは本steering/証跡を所有。project/共有store/原本/他媒体機能/docsはworker所有外。既存変更を戻さず、同じファイルへ並行書込しない。
  - 追加所有: ROI逆変換に必要なNativeCaptureSubjectGeometryと対応testも同workerへ単独引渡し。document_author `s46_docs` は `docs/architecture.md` と `docs/functional-design.md` のND構造だけを同期し、未合意policy/製品未接続/実機未確認を保持する。コードと文書の所有は重ねない。
  - 構成再確認: Xcode27.0(27A266a)/Swift6.4、既存project/scheme/testPlan FrameRelay、Debug/App・Unit・UIを実照会。iOS27.0のboot済みSimulator DFE46693-E8DD-4814-8957-4F327699F719を当日のdevices/showdestinationsで確認。Swift言語5/最低iOS27.0を保持。構成照会は試験成功と区別し、build-settingsとcommandをbaseline rootへ保存。
  - 途中結果: 実buffer解析/有界入力/独立WB監視/ND状態とUIを追加。初回compile失敗と既存actorへの隔離診断を保持し、診断用 `-disable-batch-mode` のtest-04は14宣言/20展開ケース成功、fail/skip/runtimeWarnings 0。通常構成の成功とは分け、通常batch再検証とmain指摘の期限・in-flight境界修正を継続中。source/command/log/xcresultはbaseline rootの `worker/`。製品policy回答は未受領のため通常Factoryへ注入していない。
  - Depends: Start＝N01・既存設定／WB観測契約（ND解析・規則・UI）。Finish＝S41,S42の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/{Application,Platform}/Capture/` のND解析、`FrameRelay/Domain/Capture/` の評価対象契約、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 実解析入力・複数露出対象・設定／WB世代から濃淡方向／理由／両立困難。遅延・停止・根拠不足で旧OK失効。
  - Verify: 代表入力、太陽／反射／黒／飽和、手動変更とWB、REC非阻害。AF方式採用には依存しない。
  - Stop: 常に判定不能のみ、RGB分布一致をWB目標、飽和から精密量捏造。

### S47 ズーム・構図予告・停止支援・レンズISO

- [ ] Status: blocked
  - 2026-10-18開始: 本人の明示implementによりS47だけを対象とする。S41〜S46の前回独立検証は限定合格・新規指摘なし（全Unit347宣言/470展開成功・17skip、通常UI3成功）。報告原本を今回証跡へ保全し、実機/全体未完了を維持。
  - 保全方針: 開始時7599file/169,931,513bytesのhashと証跡外copyを `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-s47-20261018-m815eusl/` に保存。既存dirty/untrackedへ加算し、revert/reset/stashは使わない。mainはtasklist/証跡/判断/最終差分を所有、explorer2名はread-only。worker所有は下記へ確定してから引渡す。
  - 所有引渡し: worker `s47_app`＝S47新Domain/共有ProductCapturePorts・必要時ExplorationPorts、ProductCaptureCoordinator/UI/Preview/Factoryと対応Domain/Application/Composition/UI test。worker `s47_native`＝NativeExplorationCapture、新S47 Platform helperと対応Platform test。Domain/Portはappが先に作成してNativeへ引渡す。同じファイルは重複所有しない。mainは本steering/証跡/構成確認/実行検証/最終差分。
  - ISO判断: 最終本人指定ISOと指定時F値を基準、F値比の二乗で補正、基準±1段と機器範囲へ制限、切替後固定・戻り時基準へ復帰・手動変更で基準更新の暫定v1案を本人へ提示。回答までは製品注入を保留し、ズーム等の独立部分を続行。
  - 暫定判断 S47-Z01/v1（main、軽微可逆・実機未採用）: SDK ramp rateを0.5（2のべき/秒）、停止判定の倍率差0.005、近傍候補の表示差0.05として処理から分離。倍/半分へ約2秒の低速候補と読戻し境界の技術試験用であり、滑らかさ/停止精度/画質の許容値ではない。変更箇所は `CaptureZoomPolicy.provisionalV1`。近傍候補は別ボタンで本人が選択し、入力倍率を無断吸着しない。DV-08で事前条件と採用を別判定する。
  - 暫定判断 S47-L01/v1（main、軽微可逆・実機未採用）: 対応virtualでは現在のactive constituentを固定して自動fallbackによる無断値変更を避ける。現在レンズの実可動範囲内でズームし、別レンズへは明示選択。Movie出力固有のrecording switching overrideを無効化して両候補の方針を揃える。非対応/条件不一致は制御だけ理由付き拒否し、未確認切替を成功扱いしない。実倍率・実ISO等を読戻し、DV-09の実機切替品質は未確認。
  - substatus / 2026-10-18終了: 規則・ズームUI/通常接続=実装済、SDK制御本体=実装/compile済、レンズ/限定ISO=本体・注入試験済/通常接続保留、必要自動検証/main差分確認=完了、実機受入=未確認。blocked理由は未回答ISO基準/上限の製品採用待ちであり、実機待ちでズーム独立部分を停止していない。
  - 実装: 予告は実倍率を変えず、寄る枠をpreview layer、引く範囲と画面外未確認を別図へ表示。writer/sample原本には流さない。S44の実画角変更で予告を失効し、同値通知では有効な予告を破棄しない。世代/revision/命令sequence/operationを分け、古い開始・停止後の開始・旧ISO完了/失敗・旧画面離脱を拒否。SDK rampの目標境界で停止し、途中停止とREC停止を別命令にした。
  - 実装 / レンズISO: virtualと切替先双方の露出能力、形式/fps/Log/補正を事前照合し、不明/非対応は拒否。実露出はeffective physical、記録形式はvirtual input/recording connectionから読む。ISO適用待ちは実値未確認として次RECを抑止し、手動指定を最新基準として優先、補正後も同じ基準を保持する。次RECは操作の実適用値を使い、保存希望・開始済みRecordingIntentを後から書き換えない。AF/NDの画角/時刻失効も既存接続を再利用。
  - E-S47-01 / 最終検証: final-test-09で全Unit365宣言/496展開成功・既存17skip・失敗0、通常UI3件成功。新規S47は18宣言/26展開。対応レンズ→遅延補正200→新手動240→旧成功/失敗完了拒否→切替後120保持→基準レンズ240復帰を含む。ios-build-10はgeneric iOS/CODE_SIGNING_ALLOWED=NOで成功。最終220入力はtest/iOSbuild/現物で一致、runtimeWarnings/compiler/analyzer診断0（stdoutの既存AppIntents metadata警告は保持）。UIは通常入口/未確認・無効表示/ズーム停止と録画停止の識別を確認した範囲で、実カメラ動作を証明しない。
  - E-S47-01 / 中間版・失敗保全: unit-01のcontains引数compile失敗、unit-02のtest macroによるmutating隔離compile失敗は各0件。unit-03は新fixtureのprotocol default stream選択で新規3件失敗、gate待ち1件をmain中断（276宣言成功/2skip/4fail表記）。fixture streamを保持しgate待ちを有界化してzoom-04成功、unit-05全Unit365宣言/495展開・17skip成功、ui-06 UI3成功。test具体化後lens-07のsuite5件とios-build-08も成功。その後の旧nil完了拒否1行とtest2ケース化を含め最終test/buildを再実行済み。中間の重複caseは合算しない。
  - E-S47-01 / 最終差分: 開始baselineと全7599fileをhash照合し、既存10file変更/7589不変＋新10file、削除/所有外変更/旧証跡変更0。コード/対応test17file、関連docs2file、本tasklistだけを変更し、project/README/memo/共有storeを保持。全79ACの行と他task状態を保持。docsはdocument_author、doc_reviewerの最終指摘なし。証跡は `evidence/20261018-s47/`、raw xcresult/開始時の証跡外copyはrepo外rootに保持。mainの実装内確認であり独立validationではない。
  - 残件と再開条件: ISO案の本人回答後に通常Factoryへ注入し、通常経路の関連Composition/UIを再検証する。実機の倍率停止精度/滑らかさ/予告crop一致・画面外構図/停止候補画質/熱負荷、レンズ実切替/ISO・shutter・WB保持/映像音声継続性はDV-08/09/11へ残す。未採用設定を受入閾値とせず、実機待ちを他の独立作業の追加依存にしない。
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
| FR-01 | AC-FR-01-01 | 音声付き4K24/30原本・写真非追加 | P05/P06/P09;CF-02/08 | EC,ES | S12,S41 | dep(S12,S41)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | 通常撮影・保存・一覧再生接続済（実Log/品質未確認） | E-S41-01/02/03: 最新71case/UI1・開始拒否終端/離脱回帰・build | D0 | 部分証拠、実機未受入 | DV-01、DV-02 |
| FR-01 | AC-FR-01-02 | 3形式・カメラ対応・無断代替禁止 | P05/P06/P09;CF-02/08 | EC,ES | S41 | dep(S41)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | 現能力照合・希望/実値・自動代替拒否を製品接続済 | E-S41-01/02: 設定/条件照合・build | D0 | 部分証拠、全組合せ未確認 | DV-01 |
| FR-01 | AC-FR-01-03 | 手動値維持・ND再評価 | P05/P06/P09;CF-02/08 | EC,ES | S41,S46 | dep(S41,S46)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | 手動設定・ND実画素/失効と通常policy接続済 | E-S41-01/02、E-S46-01/02: 設定世代/時刻境界/期限・REC非阻害 | D0 | 実装/自動検証済、実機未受入 | DV-01、DV-07 |
| FR-01 | AC-FR-01-04 | 保存設定・WB/補正の条件復元 | P05/P06/P09;CF-02/08 | EC,ES,E-S44-01 | S41,S44 | dep(S41,S44)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | S41希望保存・S44補正候補/条件復元接続済 | E-S41-01/02/03、E-S44-01: store再open/条件照合/非代替/初期UI | D0 | 部分証拠、実機補正未受入 | DV-01、DV-04 |
| FR-02 | AC-FR-02-01 | 固定Rec.709表示・非焼込み | P06/P12;CF-05 | EC:表示拒否境界のみ | S48 | dep(S48)＋対応A/Q01 | O-CAPTURE | I0 | A1 | D0 | R0 | DV-05 |
| FR-02 | AC-FR-02-02 | 確認状態分離・描画/録画品質 | P06/P12;CF-05 | EC:表示拒否境界のみ | S48,S4V | dep(S48,S4V)＋対応A/Q01 | O-CAPTURE | I0 | A1 | D0 | R0 | DV-05、DV-11 |
| FR-03 | AC-FR-03-01 | OFF＋複数実モード | P05/P06/P13;CF-06 | EC:能力/適用契約,E-S44-01 | S44 | dep(S44)＋対応A/Q01 | O-CAPTURE | OFF＋複数SDK候補・両出力支持/active照合/現在値UI接続済 | E-S44-01: 候補条件/connection拒否/実値差/REC前再照合 | D0 | 本体の部分証拠、実機効果/正式採用未受入 | DV-04 |
| FR-03 | AC-FR-03-02 | 初回候補・対応条件復元 | P05/P06/P13;CF-06 | EC:能力/適用契約,E-S44-01 | S41,S44 | dep(S41,S44)＋対応A/Q01 | O-CAPTURE | 初回standard候補・保存希望優先・条件復元/非代替を接続済 | E-S44-01: OFF/standard/cinematicExtendedの再open・条件照合・初期UI | D0 | 部分証拠、実機未受入 | DV-01、DV-04 |
| FR-03 | AC-FR-03-03 | 3場面品質・設定不変 | P05/P06/P13;CF-06 | EC:能力/適用契約,E-S44-01 | S44,S4V | dep(S44,S4V)＋対応A/Q01 | O-CAPTURE | 録画中の設定変更拒否・現在補正観測を接続、品質未評価 | E-S44-01: 録画中不変/観測・保存/音声回帰 | D0 | 3場面品質/全体継続性未受入 | DV-04、DV-11 |
| FR-03 | AC-FR-03-04 | 補正画角・予告・切替保持 | P05/P06/P13;CF-06 | EC:能力/適用契約,E-S44-01,E-S47-01 | S44,S47 | dep(S44,S47)＋対応A/Q01 | O-CAPTURE | S44画角revisionのS47 consumer接続、旧予告失効・同値通知保持 | E-S44-01、E-S47-01: 世代/命令順序・実値/予告・切替条件 | D0 | crop/preview実一致・切替実機維持未受入 | DV-04、DV-08、DV-09 |
| FR-03 | AC-FR-03-05 | 標準不成立の制約と相談 | P05/P06/P13;CF-06 | EC:能力/適用契約,E-S44-01 | S44 | dep(S44)＋対応A/Q01 | O-CAPTURE | 非対応/未確認/実値不一致理由と本人選択・再準備導線済 | E-S44-01: 非代替/preview専用拒否/希望保持/UI | D0 | 実機標準成立・必要な要求再確認は未評価 | DV-04 |
| FR-04 | AC-FR-04-01 | 安定前RECと固定 | P05/P06/P10;CF-03 | EC,E-S42-01 | S42 | dep(S42)＋対応A/Q01 | O-CAPTURE | 安定待ちなしの既存固定・製品接続済 | Unit89/UI1・iOS build成功、早期STOP/旧callback回帰 | D0 | 制御の部分証拠・実色/記録開始未確認 | DV-03 |
| FR-04 | AC-FR-04-02 | 本人再固定・他設定維持・品質 | P05/P06/P10;CF-03 | EC,E-S42-01,E-S42-V01,E-S42-02 | S42 | dep(S42)＋対応A/Q01 | O-CAPTURE | 対応能力確認/SDK再測定/固定/本人UI接続済、開始失敗理由の終端保持P2修正済 | E-S42-01 Unit89/UI1＋P2修正Unit65/UI1・iOS build成功、本人STOP競合/完全検査でも部分保存 | D0 | 本体/制御の部分証拠・修正後独立検証/実機色/継続性未確認 | DV-03 |
| FR-04 | AC-FR-04-03 | 最終フレーム・待機Auto・二本 | P05/P06/P10;CF-03 | EC,E-S42-01 | S42,S46 | dep(S42,S46)＋対応A/Q01 | O-CAPTURE | 終端後Auto/二本新測定/旧通知拒否接続済、NDはS46 | Unit89/UI1・iOS build成功、測定/固定待ちSTOP/二本/逆順 | D0 | 終端制御の部分証拠・実最終フレーム/ND実機統合未確認 | DV-03、DV-07 |
| FR-05 | AC-FR-05-01 | 複数露出対象と単一主役・意図 | P05のREC非依存のみ;CF-09部分/後続必須 | E-S45-01,E-S45-02 | S45 | dep(S45)＋対応A/Q01 | O-CAPTURE | 本体・通常Factory接続済、意図保存復元/位置指定AF | E-S45-02: 分離/両候補policy/実disk復元/通常UI成功 | D0 | 実装・自動検証済、実機未受入 | DV-06 |
| FR-05 | AC-FR-05-02 | 見失い保持・同一再捕捉・再指定 | P05のREC非依存のみ;CF-09部分/後続必須 | E-S45-01,E-S45-02 | S45 | dep(S45)＋対応A/Q01 | O-CAPTURE | 固定参照/衝突拒否/暫定3秒保持/再指定を製品接続 | E-S45-02: 実Vision別人拒否・即時置換・同一画像復帰/猶予変更成功 | D0 | 静止fixtureの技術証拠、動く人物/同一性品質未受入 | DV-06 |
| FR-05 | AC-FR-05-03 | 人物未確定でもREC | P05のREC非依存のみ;CF-09部分/後続必須 | EC,E-S45-01,E-S45-02 | S45,S41 | dep(S45,S41)＋対応A/Q01 | O-CAPTURE | 人物/意図/解析をREC条件へ追加せず通常接続 | E-S45-02: 未選択/解析なし/遅延保存中REC・継続/両候補Factory成功 | D0 | REC非阻害の自動検証済、実機未受入 | DV-06 |
| FR-05 | AC-FR-05-04 | 通常合焦・前後追従品質 | P05のREC非依存のみ;CF-09部分/後続必須 | E-S45-01,E-S45-02 | S45 | dep(S45)＋対応A/Q01 | O-CAPTURE | SDK AF計画/読戻し/不成立表示を製品接続 | E-S45-02: AF計画/座標/状態境界成功 | D0 | 実合焦/前後追従・衝突防御の保持制約/負荷品質未受入 | DV-06 |
| FR-05 | AC-FR-05-05 | 追跡OFFの人物優先AF品質 | P05のREC非依存のみ;CF-09部分/後続必須 | E-S45-01,E-S45-02 | S45 | dep(S45)＋対応A/Q01 | O-CAPTURE | 追跡OFF人物優先AFとscene後復帰を製品接続 | E-S45-02: OFF非固定/人物再登場/AF計画成功 | D0 | 実人物優先AF品質未受入 | DV-06 |
| FR-06 | AC-FR-06-01 | 濃く/薄くの方向と理由 | P05/P10設定事実;CF-09部分/後続必須 | E-S46-01/02 | S46 | dep(S46)＋対応A/Q01 | O-CAPTURE | 実画素の方向/理由と本人合意の通常policy接続済 | E-S46-02: 5画素形式/4信号・両候補Factory→実解析→案内成功 | D0 | 実装/自動検証済、実写一致未受入 | DV-07 |
| FR-06 | AC-FR-06-02 | 人物背景両立困難・太陽反射黒 | P05/P10設定事実;CF-09部分/後続必須 | E-S46-01/02 | S46 | dep(S46)＋対応A/Q01 | O-CAPTURE | 人物別/背景別・相反/不足を通常接続済 | E-S46-02: 複数対象/相反/小反射/黒/飽和の人工入力回帰成功 | D0 | 実装/自動検証済、実写材質/意図との一致未受入 | DV-07 |
| FR-06 | AC-FR-06-03 | 停止遅延保留・旧OK失効・REC | P05/P10設定事実;CF-09部分/後続必須 | E-S46-01/02 | S46,S41 | dep(S46,S41)＋対応A/Q01 | O-CAPTURE | 世代/時刻/停止・暫定1秒失効とREC非阻害を通常接続済 | E-S46-02: 遅延配送/更新/期限・失効後REC/録画継続成功 | D0 | 実装/自動検証済、実機未受入 | DV-07 |
| FR-06 | AC-FR-06-04 | WB状態と飽和情報の限界 | P05/P10設定事実;CF-09部分/後続必須 | E-S46-01/02 | S46,S42 | dep(S46,S42)＋対応A/Q01 | O-CAPTURE | 独立WB/validAfter/飽和保留を通常接続済 | E-S46-02: 新context付き古フレーム拒否/飽和/境界入力回帰成功 | D0 | 実装/自動検証済、実WB KVO/連続Auto/実写未受入 | DV-03、DV-07 |
| FR-07 | AC-FR-07-01 | 目標構図予告・倍率不変・非焼込み | P05/P14;CF-07（予告は後続必須） | EC:倍率/停止契約のみ,E-S47-01 | S47 | dep(S47)＋対応A/Q01 | O-CAPTURE | 目標選択と非駆動予告・preview専用表示を接続済 | E-S47-01: 予告時不変・旧画角失効・記録intent不変 | D0 | 実装/自動検証済、実画角一致未受入 | DV-08 |
| FR-07 | AC-FR-07-02 | 目標/途中停止・操作と品質 | P05/P14;CF-07（予告は後続必須） | EC:倍率/停止契約のみ,E-S47-01 | S47 | dep(S47)＋対応A/Q01 | O-CAPTURE | 目標/途中停止・REC停止別・SDK ramp/境界停止を接続済 | E-S47-01: 超過/停止競合/旧命令拒否・REC独立/UI | D0 | 実装/自動検証済、停止精度/操作品質未受入 | DV-08 |
| FR-07 | AC-FR-07-03 | 停止支援・引く予告・画角/画質/負荷 | P05/P14;CF-07（予告は後続必須） | EC:倍率/停止契約のみ,E-S47-01 | S47,S44 | dep(S47,S44)＋対応A/Q01 | O-CAPTURE | SDK由来候補・任意選択・引く予告・未採用v1設定を接続済 | E-S47-01: 候補範囲/補正条件・無断吸着なし・画面外未確認 | D0 | 実装/自動検証済、画角/画質/負荷未受入 | DV-04、DV-08、DV-09 |
| FR-08 | AC-FR-08-01 | 限定ISOと切替後保持 | P05/P14;CF-07 | EC:実値/限定ISO契約のみ,E-S47-01 | S47 | dep(S47)＋対応A/Q01 | O-CAPTURE | 限定ISO/手動優先/保持の本体と注入試験済、通常policy=nil | E-S47-01: 基準/上限・遅延補正対手動・切替後保持/戻り | D0 | 本人基準/上限判断と製品注入待ち、実機未受入 | DV-09 |
| FR-08 | AC-FR-08-02 | 実値表示・非対応切替拒否 | P05/P14;CF-07 | EC:実値/限定ISO契約のみ,E-S47-01 | S47,S44 | dep(S47,S44)＋対応A/Q01 | O-CAPTURE | 実値/適用待ち表示・対応条件と非対応拒否本体接続済 | E-S47-01: 形式/補正/露出能力・旧完了拒否・未確認REC抑止 | D0 | 通常レンズ切替は未有効、実機未受入 | DV-04、DV-09 |
| FR-08 | AC-FR-08-03 | 映像音声・切替継続品質 | P05/P14;CF-07 | EC:実値/限定ISO契約のみ,E-S47-01 | S47,S4V | dep(S47,S4V)＋対応A/Q01 | O-CAPTURE | 記録intent不変・次REC実値同期を接続、切替品質未評価 | E-S47-01: RECとzoom停止独立・新旧intent/保存再生回帰 | D0 | レンズ製品注入/映像音声継続品質未受入 | DV-09、DV-11 |
| FR-09 | AC-FR-09-01 | 待機/録画音量・静寂と障害 | P05/P06/P11;CF-04/08 | EC,ES:音声規則/保存探索 | S43 | dep(S43)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | 音量/入力/到着・暫定無到着policyの製品接続済 | E-S43-01/02:実PCM/静寂/待機/旧通知/UI/合意2秒境界 | D0 | 部分証拠・実機未評価 | DV-10 |
| FR-09 | AC-FR-09-02 | 確認済障害で停止・保存分類 | P05/P06/P11;CF-04/08 | EC,ES:音声規則/保存探索 | S43,S12 | dep(S43,S12)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | 入力/書込故障の抑止・停止/保存・暫定無到着policy接続済 | E-S43-01/02:障害/本人STOP/終端/保存分類/2秒境界 | D0 | 部分証拠・全障害実機未評価 | DV-02、DV-10 |
| FR-09 | AC-FR-09-03 | 有限復旧・手動REC | P05/P06/P11;CF-04/08 | EC,ES:音声規則/保存探索 | S43 | dep(S43)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | 有限復旧・暫定製品policyを含む必要接続済 | E-S43-01/02:Factory/1本人操作1試行/実5秒timeout/実所有/手動REC | D0 | 部分証拠・復旧品質/実機未確認 | DV-10 |
| FR-09 | AC-FR-09-04 | 到着/書込み・保存音声 | P05/P06/P11;CF-04/08 | EC,ES:音声規則/保存探索 | S43,S12 | dep(S43,S12)＋対応A/Q01 | O-CAPTURE/O-ORIGINAL | 実到着/書込観測接続済・Movie個別書込取得不能保持 | E-S43-01/02:実PCM/書込故障/実保存再生回帰 | D0 | 部分証拠・保存実音声未確認 | DV-02、DV-10 |
| FR-10 | AC-FR-10-01 | 原本/軽量版再生・複数結果/単数操作 | P08/P09/P21,T15/T20;CF-01/08,BI-15/33 | ES,EB,E-S13/14/15/25 | S14,S15,S25,S28,S34 | dep(S14,S15,S25,S28,S34)＋対応A/Q01 | O-LIBRARY | 原本製品入口と固定軽量版下位I/O/AVPlayer実装済、S16監査・S27 wire/S28 UI未完 | E-S13:50/E-S14:44/E-S15:33、E-S16通常3/最大文字2成功、E-S25新Unit27/全Unit等286・HTTP10成功/全reader解放。旧失敗保持 | D0 | 原本製品操作と合成軽量版の部分証拠・製品配布/UI/実機未確認 | DV-14、DV-16、DV-17 |
| FR-10 | AC-FR-10-02 | 保存中断再起動の4分類 | P08/P09/P21,T15/T20;CF-01/08,BI-15/33 | ES,EB,E-S11,E-S12 | S12,S14 | dep(S12,S14)＋対応A/Q01 | O-LIBRARY | S12保存/復旧＋S14分類投影/製品UI接続済、実Capture未接続 | E-S12:54/E-S14:44、E-S16保存unknown/要照合の実表示・post-UI再open | D0 | 保存/reopen/分類/製品UIの部分証拠・実Capture未確認 | DV-02 |
| FR-10 | AC-FR-10-03 | 整理後offline・再接続等非強制 | P08/P09/P21,T15/T20;CF-01/08,BI-15/33 | ES,EB（実再生なし） | S14,S32,S34 | dep(S14,S32,S34)＋対応A/Q01 | O-LIBRARY | S14整理後通常一覧の製品UI投影済・実整理未接続 | E-S14:44、E-S16通常UIの整理/破棄投影・履歴操作成功（test seed） | D0 | 投影/製品表示の部分証拠・実整理未確認 | DV-14、DV-17 |
| FR-11 | AC-FR-11-01 | 指示原本の転送・全内容検証 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB,EI,E-S24 | S24,S24I | dep(S24,S24I)＋対応A/Q01 | O-IOS-BI/O-SERVER | 登録/内容に束縛したserver受信・独立最終全read・証拠/job同commit実装済、iOS転送未接続 | E-S24:guard12/pytest126/実HTTP20＋別process再起動5成功、合成16777473byte全比較 | D0 | server保存の部分証拠・製品転送/実G2B/G2C/実機未確認 | DV-12 |
| FR-11 | AC-FR-11-02 | 回線離脱待機・検証不明原本保持 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB:規則のみ,EI:隔離 | S23,S24I | dep(S23,S24I)＋対応A/Q01 | O-IOS-BI/O-SERVER | I1 | A1 | D0 | R0 | DV-12 |
| FR-11 | AC-FR-11-03 | 結果受信中断・HTTPとcommit分離 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB,EI,E-S21,E-S24 | S21,S24I | dep(S21,S24I)＋対応A/Q01 | O-IOS-BI/O-SERVER | 端末同writerの証拠/要求/commit照会とserver保存証拠実装済、端末への実受信commit未接続 | E-S21:実disk26新規/全Unit211有意味、E-S24:commit応答欠落/境界rollback/再照会を含む126成功・実HTTP25成功 | D0 | 両永続境界の部分証拠・製品転送/受信統合未確認 | DV-12 |
| FR-11 | AC-FR-11-04 | 複数固定集合・動画別結果 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB:規則のみ,EI:隔離,E-S21 | S23,S24I,S28 | dep(S23,S24I,S28)＋対応A/Q01 | O-IOS-BI/O-SERVER | 固定batch/動画別requestを同writerへ永続化・実転送/UI未接続 | E-S21:両disk固定集合とrequest再open成功 | D0 | 集合/結果保持の部分証拠・実通信/表示未確認 | DV-12 |
| FR-12 | AC-FR-12-01 | 保存検証後生成・原本保持 | T13/T14/T16;BI-16/17/32 | EB＋E-S26J-ACCEPT | S26J,S26 | dep(S26J,S26)＋対応A/Q01 | O-SERVER | 証拠起点候補/job実装、標準変換未接続 | 実store/worker160case成功、原本保持/未公開fixture確認 | D0 | 周辺処理の部分証拠、実変換未達 | DV-13 |
| FR-12 | AC-FR-12-02 | 実Rec.709・媒体特性/日時保持 | T13/T14/T16;BI-16/17/32 | EB:変換前提契約のみ | S26 | dep(S26)＋対応A/Q01 | O-SERVER | I1 | A1 | D0 | R0 | DV-13 |
| FR-12 | AC-FR-12-03 | 旧compress-only非代用・差替条件 | T13/T14/T16;BI-16/17/32 | EB:変換前提契約のみ | S26,S27 | dep(S26,S27)＋対応A/Q01 | O-SERVER | I1 | A1 | D0 | R0 | DV-13、DV-14 |
| FR-13 | AC-FR-13-01 | 単数途中実再生＋明示確認 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER,E-S20-04,E-S25 | S25,S27 | dep(S25,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 固定版下位実再生とPlaybackToken実装済・製品配布wire/本人確認未接続 | E-S25:全Unit等286・実HTTP10成功、339596/969998Bで進行/decoded、停止後buffer/readers0 | D0 | 合成媒体の途中実再生の部分証拠・製品確認/実機/聴取未確認 | DV-14 |
| FR-13 | AC-FR-13-02 | 受付と確認commit・不明 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER（実再生/ACKなし）,E-S21 | S21,S27 | dep(S21,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 確認＋outbox同時commit/不明時照会実装済・軽量版player/サーバー未接続 | E-S21:両disk確認fault/reopen成功、全Unit211有意味成功 | D0 | 端末commitの部分証拠・本人実確認/サーバー未確認 | DV-14 |
| FR-13 | AC-FR-13-03 | 失効前V1維持・offline整理 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER（実再生/ACKなし） | S27 | dep(S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | I1 | A1 | D0 | R0 | DV-14、DV-17 |
| FR-13 | AC-FR-13-04 | 失効commit後全必要ACK・非復活 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER,E-S21,E-S22,E-S22C | S27,S28 | dep(S27,S28)＋対応A/Q01 | O-IOS-BI/O-SERVER | 端末tombstone/ACK outbox/旧版拒否・server登録分離・端末store UUID/Keychain登録束縛を接続、全owner/ACK経路未接続 | E-S21失効fault/epoch/配布分岐、E-S22登録26成功、E-S22C残存資格情報拒否/実HTTP6成功 | D0 | 端末永続/登録認証境界の部分証拠・全必要ACK/公開は未確認 | DV-14、DV-15 |
| FR-13 | AC-FR-13-05 | 初回/V2/失効後失敗の区別 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER＋E-S26J-ACCEPT | S26J,S27 | dep(S26J,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 候補失敗/retry実装、失効/公開接続未完 | 実store/workerで候補失敗/成功時V1 fixture保持、ACK未検証 | D0 | 候補処理の部分証拠 | DV-14 |
| FR-13 | AC-FR-13-06 | 同一映像再取得/切断非失効 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER,E-S25 | S25,S27 | dep(S25,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 同版Range/全量hash/一時usage実装済、切断は失効生成なし、製品配布wire未接続 | E-S25:不正版/不正Range/遅延停止/条件変化/完全取得を実HTTP10内で確認、cache現世代拒否を新Unit27内で確認 | D0 | 下位I/Oの部分証拠・製品配布/ACK/実回線未確認 | DV-14 |
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
| FR-16 | AC-FR-16-01 | 全媒体Wi-Fi・local offline再生 | T03/T05/T09/T11/T15/T23;BI-07〜15 | EB,ER,E-S15,E-S25 | S15,S23,S25 | dep(S15,S23,S25)＋対応A/Q01 | O-IOS-BI/O-CAPTURE | 原本/取得済軽量版local実再生と遠隔各read gate実装済、全媒体/背景/VPN制約はS23未完 | E-S15:33成功、E-S25新Unit27/HTTP10成功・localはnetwork gate非依存・cache hit/応答後のgate再照合、実回線断未検証 | D0 | localと固定版下位通信の部分証拠、全媒体Wi-Fi/VPN/実機は未達 | DV-12、DV-14 |
| FR-16 | AC-FR-16-02 | REC実停止・保存優先・Mac継続 | T03/T05/T09/T11/T15/T23;BI-07〜15 | EB,ER:契約/部分観測 | S23,S49 | dep(S23,S49)＋対応A/Q01 | O-IOS-BI/O-CAPTURE | I1 | A1 | D0 | R0 | DV-11、DV-12 |
| FR-16 | AC-FR-16-03 | 開始済対象だけ全条件再確認再開 | T03/T05/T09/T11/T15/T23;BI-07〜15 | EB,ER:契約/部分観測,E-S21 | S23,S28,S49 | dep(S23,S28,S49)＋対応A/Q01 | O-IOS-BI/O-CAPTURE | 本人意思/複合待機/試行世代を同writerへ永続化・全媒体gate/SDK未接続 | E-S21:複合待機/取消後成功/古いcallback拒否のdisk成功 | D0 | 再開規則の永続境界だけ部分証拠・実回線/REC/OS未確認 | DV-12 |
| FR-17 | AC-FR-17-01 | 単数対象と消失リスク確認 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33,S34 | dep(S33,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-02 | 明示操作なしの破棄禁止 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33 | dep(S33)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-03 | iPhone対象だけ削除・外部保持 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33 | dep(S33)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-04 | 保存/確認状態の非偽装 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33,S34 | dep(S33,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-05 | 実削除照合と成功履歴 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33,S34 | dep(S33,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| FR-17 | AC-FR-17-06 | 破棄境界中断・要照合 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33 | dep(S33)＋対応A/Q01 | O-ORIGINAL/O-STORE | I1 | A1 | D0 | R0 | DV-17 |
| NFR-01 | AC-NFR-01-01 | 起動/次REC/通信停止の実測 | P18,T23;CF-09,BI-09 | EC,EB:時刻/抑止契約 | S41,S43,S49,S4V | dep(S41,S43,S49,S4V)＋対応A/Q01 | O-CAPTURE/O-IOS-BI | I1 | A1 | D0 | R0 | DV-11、DV-12 |
| NFR-02 | AC-NFR-02-01 | 保存/検証受信/確認の中断 | P09/P19,T10/T18/T21/T22;CF-08,BI-04/05/20/23/29/30/33 | ES,EB,E-S11,E-S12,E-S21,E-S24 | S12,S21,S24I,S27 | dep(S12,S21,S24I,S27)＋対応A/Q01 | O-STORE/O-ORIGINAL/O-PHOTOS | S12保存/復旧＋S21確認/証拠disk＋S24 server保存復旧実装済、端末実転送/確認未接続 | E-S12:54実行、E-S21:commit前後中断/reopen、E-S24:境界失敗/旧claim/全readと別process再起動成功 | D0 | 保存/連携commit境界の部分証拠・製品統合/実機未確認 | DV-02、DV-12、DV-14 |
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
  - 先行引渡し E-S42-01: 通常撮影の本人再固定、測定/固定適用とSTOPの順序、終端後Auto、二本/旧通知拒否を接続し、関連Unit89ケース/UI1・iOS build成功。Simulatorは実カメラでのone-shot測定/KVO、色、最終フレーム、継続性を証明しない。両記録候補・対応能力・実機版を束縛して下記操作を実施する。
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
  - 事前合意・Stop: S45で人物なしタップAF・初回本人意図選択/保存復元/REC非阻害・変更可能な暫定3秒後保持/再指定を承認済み。距離・照明・移動・補正/Log条件と許容品質、暫定値の実機採用は未合意/未確認。未束縛条件はQ01、未接続は対応本体taskへ戻す。

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
  - 先行引渡し E-S22-01/S22C: server destination/intent/registration/世代/秘密を実SQLiteへ束縛し、同意図再送・応答欠落後再open・新登録と旧資格情報分離を新規26caseで確認（全46成功）。S22Cで端末同writer commit/Keychainのstore UUID束縛、同store中断と新store/残存資格情報の区別・実HTTP6件を確認済み。wire/copy/diffを保全。旧確認/必要ACK/公開との製品接続はS27/S28、実再インストール/保護領域は本票へ残し、実再登録受入には昇格しない。
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
| E-S41-01 | 2026-10-16、worker/main | S41・限定V-CAPTURE/STORE/PLAY/UI | test-01-sources170file、Xcode27/Debug/iOS27 Simulator＋generic iOS | commands.json、共通保存→実MOV→bind→再open→Library→AVPlayer、設定/日時/旧schema/早期STOP、通常撮影UI | Simulator/iOS build成功、33Unit/48展開ケース・UI1成功、失敗0/skip0。日時provider未接続で製品REC無効 | `evidence/20261016-s41/`。初回fps/候補/日時観測点の本人回答待ち。実機D01/G2B/画質、S27詳細、独立validationは未確認 |
| E-S41-02 | 2026-10-16、worker/document_author/main | S41承認反映・REC有効化・限定回帰 | test-01-sources170file、前回からfactory時計注入1行のみ | commands.json、設定/coordinator/実保存再生/UI、generic iOS build | Unit13宣言/14展開ケース・UI1成功、失敗0/skip0/runtimeWarnings0、iOS build成功。製品RECは条件成立時有効 | `evidence/20261016-s41-approved/`。S41実装完了、実機D01/G2B/画質・S27詳細・独立validationは未確認 |
| E-S41-03 | 2026-10-17、explorer/worker/main | S41独立指摘P1/P2修正・限定回帰 | final-tests/final-buildの173入力file一致、Xcode27/Debug/iOS27 Simulator＋generic iOS | commands.txt、Native開始前拒否の終端、遅延load/discover/prepare/取消/再入場/旧shutdown/設定保存、既存保存・UI | 最終Unit50宣言/71展開ケース（新規23）・UI1成功、失敗0/skip0/runtimeWarnings0、Simulator/iOS build成功 | `evidence/20261017-s41-fixes/`。実機D01/G2B/画質・既知未完了事項保持。独立validation未実施 |
| E-S41-V01 | 2026-10-17、implementation_validator/main | S41修正後限定独立検証 | E-S41-03の173入力、S42開始前347file不変 | 保存証拠/現物hash・構成/差分・故障境界を照合、旧保存再生証拠継承 | 合格・指摘なし、追加build/testなし | `evidence/20261017-s42/s41-validation-report.txt`。S41限定、実機/全体/S42は判定外 |
| E-S42-01 | 2026-10-17、explorer/worker/document_author/main | S42、AC-FR-04-01〜03/AC-CF-03、限定回帰 | test-02/ios-build-02の173入力一致、Xcode27/Debug/iOS27 Simulator＋generic iOS | `*-run.json`、WB測定/STOP/遅延/二本/失敗、S41回帰、実MOV保存→一覧→AVPlayer、UI | Unit64宣言/89展開＋UI1成功、失敗/skip/runtimeWarnings0、build成功。初回test compile失敗0実行は保持 | `evidence/20261017-s42/`。実機/DV-03/既知残件/S42独立validation未確認 |
| E-S42-V01 | 2026-10-17、implementation_validator/main | S42修正前限定独立検証 | E-S42-01の173入力/最終13fileと元xcresult一致、検証前後5307file不変 | WB固定/再固定/終端、通知順序、S41回帰、例外経路をread-only照合 | 要修正P2 1件、再測定開始失敗理由の終端引継ぎ漏れ。追加build/testなし | `evidence/20261017-s42-p2-fix/validation-report.txt`。実機品質/既知残件は別管理 |
| E-S42-02 | 2026-10-17、explorer/worker/main | S42 P2限定修正・関連回帰 | test-01/ios-build-01の175入力一致、Xcode27/Debug/iOS27 Simulator＋generic iOS | Native共用理由保持/終端、両方式×先行本人STOP、完全検査の部分保存/次clip成功、旧通知/S41/保存再生/UI | Unit43宣言/65展開＋UI1成功、新規7ケース、失敗/skip/runtimeWarnings0、Simulator/iOS build成功 | `evidence/20261017-s42-p2-fix/`。実SDK throw/実機品質/修正後独立validation未確認 |
| E-S43-01 | 2026-10-18、explorer/worker/document_author/doc_reviewer/main | S43部分・AC-FR-09-01〜04/AC-CF-04・探索互換 | 最終181入力一致、test-03不変範囲継承、Xcode27/Debug/iOS27 Simulator＋generic iOS | 各run.json、実PCM/静寂/故障保存/順序/有限復旧/所有/手動REC/遅延観測、UI・実保存再生回帰 | test-03 Unit60/87展開＋UI1、test-04 Unit26/32展開成功、build成功。途中失敗保持 | `evidence/20261018-s43/`。製品policy未合意/未接続でblocked、実機/DV-10/S42報告反映は未完 |
| E-S43-02 | 2026-10-18、worker/explorer/document_author/doc_reviewer/main | S43暫定製品policy合意・接続・限定回帰 | 最終182入力一致、test-02/03同一版、Xcode27/Debug/iOS27 Simulator＋generic iOS（App入力一致） | 各run.json、Factory/2秒無到着/1本人操作1試行/実5秒timeout/SDK終了待ち/再試行/自動RECなし、音声/保存再生/UI | test-03 Unit19宣言/23展開＋UI1成功、失敗/skip/runtimeWarnings0、build成功。compile失敗2回/0件実行も保持 | `evidence/20261018-s43-approved/`。S43実装done、実機/DV-10/S42報告受領/別セッション独立検証は残る |
| E-S44-01 | 2026-10-18、explorer/worker/document_author/doc_reviewer/main | S44、AC-FR-03-01〜05/AC-CF-06・限定回帰 | test-03/ios-build-01の187入力、最終差分UI test1fileのみ | 各run.json、補正候補/希望復元/実active/画角失効/REC前再照合/旧通知/音声・保存再生/UI | Unit53宣言/76展開成功、最終UI2成功、build成功、最終失敗/skip/runtimeWarnings0。compile失敗2run/0件・途中UI1失敗保持 | `evidence/20261018-s44/`。実機品質/crop/preview一致/S47 consumer/独立validation未確認 |
| E-S45-01 | 2026-10-18、explorer/worker/document_author/doc_reviewer/main | S45部分・AC-FR-05-01〜05と限定回帰 | 最終203入力、test-final-05/ios-build-03一致 | 各run.json、公開画像実Vision/世代/状態/設定保存/REC非阻害/AF計画/座標/UI、host同ソース診断 | Unit76宣言/99展開中75/98成功・1宣言2issues失敗、UI2成功、build成功、skip/runtimeWarnings0。途中失敗保持 | `evidence/20261018-s45/`。本人判断/Factory注入・Simulator同一特徴量問題でblocked。実機/独立validation未確認 |
| E-S45-02 | 2026-10-18、explorer/workers/document_author/doc_reviewer/main | S45再開・AC-FR-05-01〜05と限定回帰 | 最終202入力・Unit/UI/iOSbuild/現物一致 | 各run.json、公開画像実Vision/即時別人拒否/猶予変更/5画素形式/両候補Factory/意図実disk復元/通常UI | Unit81宣言112展開/UI3件全成功、build成功、skip/runtimeWarnings/compiler/analyzer0。診断途中失敗保持 | `evidence/20261018-s45-resume/`。S45実装・自動検証done、SDK内部原因/実機品質/独立validation未確認 |
| E-S46-01 | 2026-10-18、explorer/worker/document_author/doc_reviewer/main | S46部分・AC-FR-06-01〜04/AC-FR-01-03 | 最終201 SwiftとiOSbuild209入力を照合、UIは不変範囲継承 | 各command/run/source hash、実buffer/複数ROI/失効/REC/通常UI | 通常関連48宣言64展開、修正ND16宣言22展開、最終Native12宣言18展開、UI1成功。iOSbuild成功・診断0。重複合算なし | `evidence/20261018-s46/`。製品policy未回答/通常Factory未注入でblocked。実写/実機/独立validation未確認 |
| E-S46-02 | 2026-10-18、worker/document_author/doc_reviewer/main | S46本人合意・通常接続・限定回帰 | 最終210入力、test-02/ios-build-01/現物一致 | 各run/source hash、両候補Factory→実解析、250ms遅延/入力から1秒/更新、REC開始・継続、保存再生/通常UI | Unit26宣言34展開＋UI1全成功、Simulator/iOS build成功、最終失敗/skip/runtimeWarnings/compiler/analyzer0 | `evidence/20261018-s46-approved/`。初回compile失敗0件保持。実機DV-07/FR-06受入/独立validation未確認 |

| E-S47-01 | 2026-10-18、explorers/workers/document_author/doc_reviewer/main | S47部分、AC-FR-07/08・FR-03-04と回帰 | 最終220入力、final-test-09/ios-build-10/現物一致 | 各run/source hash、目標/途中停止・旧予告/命令・レンズ遅延補正と手動優先・保持/戻り・通常UI | 全Unit365宣言496展開/17skip/0fail、UI3成功、Simulator/iOS build成功。途中失敗保持、重複合算なし | `evidence/20261018-s47/`。ISO本人判断/通常注入待ちblocked、DV-08/09/11・独立validation未確認 |

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
| V-REVIEW-S22C | `S22C-test-07-sources.json`、App/Test18件・server support4件 | main | store UUID/Keychain v2の対応、同writer commit/replay、旧資格情報拒否/非破壊、再open/移動/置換、SDK実終端を確認。compile失敗04/HTTP0件01/runtime診断を保持し、修正後の成功・未確認を分離 | 関連88・全Unit258・fixture修正10・UI2・HTTP6成功、`S22C-main-scope-review.json`、保護199file不変、`evidence/20261009-s22c-complete/`。独立validationではない |
| V-REVIEW-S16-20261010部分 | `S16-ui-13-sources.json`＝ui-large-04/test-07、S22C後のApp/Test8file | main | 再生期限/停止/lease手順不変、診断の匿名性/上限/既定無効、全監査未処理、詳細List viewportと操作・VoiceOverを確認。最大文字の停止はスクロールで到達、全要素の全サイズ監査合格とはしない | 通常3/最大2/Unit＋VERIFY10成功、ui13監査1失敗、旧失敗保持。126source一致、所有外変更なし、`S16-main-frozen-review.json`。S14/S16 blocked、独立validationではない |
| V-REVIEW-S24 | `evidence/20261013-s24-complete/` のsnapshot261/凍結support57/準備checkpoint | main | 最終先新FD全readと短い再fence commit、証拠/asset/session/job原子確定、旧入口拒否、SQL001保持、dir_fd実境界、実process終了後の同DB/media再openを確認 | guard12/pytest126/HTTP20＋5成功、全child終了/秘密削除/全接続0、App/Test/project126不変、所有外変更0。`main-review-001.json`と386file保全。独立validation/実機/変換/公開受入ではない |
| V-REVIEW-S26J | `evidence/20261014-s26j-complete/` のsnapshot265/凍結support65/準備checkpoint | main | exact保存証拠、候補版とclaimの分離、同一job retry、入力FD保持/全read、旧claimの成功/失敗/cleanup拒否、未公開fixtureとV1保持を確認 | pytest160成功、parent実exit0/全接続0、App/Test/project126不変、所有外変更0。345file保全。標準変換/公開/独立validationの完了ではない |
| V-REVIEW-S41部分 | test-01-sources170file/changes.patch、既存15＋新規16 | main | 共有予約/intent前REC禁止/早期STOP/世代/最新音声入力/保存・一覧更新中の所有/旧日時非補完/範囲を確認。非ready beginの一覧refreshと保存refresh終了前の再RECを修正。S27本体保持 | E-S41-01、main-scope-review.json。限定48case/UI1成功。本人判断未回答で製品REC無効/S41 blocked、独立validationではない |
| V-REVIEW-S41 | E-S41-02のtest-01-sources170file、今回5file変更/340file不変 | main | 3点の本人合意、factory時計注入、design/関連docsとの整合、テスト版一致、S27保持とS42以降未変更を確認 | E-S41-02、`evidence/20261016-s41-approved/main-scope-review.json`。S41実装範囲done、実機未確認、独立validationではない |
| V-REVIEW-S41修正 | E-S41-03のfinal-tests-sources173file、既存6file変更/339不変＋新規2ソース | main | Native本番と同じ終端producer、保存非成功、画面visit/取消/SDK owner解放、旧処理の混入防止、遅延設定変更時の再準備、既存差分/所有範囲を確認 | E-S41-03、`evidence/20261017-s41-fixes/main-scope-review.json`。S41修正done、独立validationではない |
| V-INDEPENDENT-S41 | E-S41-V01、S42開始前のS41修正版 | implementation_validator/main | 開始拒否終端・未開始非正常保存、visit/取消/旧shutdown、保存/一覧/再生回帰を確認 | E-S41-V01、限定合格・指摘なし。validation中変更0 |
| V-REVIEW-S42 | E-S42-01の173入力、今回13file差分 | main | 本人操作/能力未知保持、SDK one-shot/実gain、STOP時固定→終端、旧通知拒否、S41保持、他露出API未変更、旧docs保持を照合 | E-S42-01、`evidence/20261017-s42/main-scope-review.json`。S42実装done、独立validationではない |
| V-INDEPENDENT-S42 | E-S42-V01、P2修正前のS42版 | implementation_validator/main | 6観点をread-only確認し、再測定開始失敗から終端への理由漏れ1件を検出 | E-S42-V01、要修正P2 1件。修正後は別明示validation |
| V-REVIEW-S42-P2 | E-S42-02の175入力、既存2file変更/新規2file | main | 通知前の故障保持、本人STOP競合、STOP理由/両終端の本番共用、旧clip除外、次clip reset、完全検査でも部分保存、所有範囲を照合 | E-S42-02、`evidence/20261017-s42-p2-fix/main-scope-review.json`。修正・関連検証完了、独立validationではない |
| V-REVIEW-S43部分 | E-S43-01の最終181入力、既存17file/新6file | main、文書はdoc_reviewer | PCM/4軸分離、STOP前故障保持/先行WB理由、観測順序、復旧所有、探索互換、製品未接続、旧差分/証跡保持を確認。文書P2は未有効明記で解消 | `evidence/20261018-s43/main-scope-review.json`。関連試験成功、S43全体blocked。独立validationではない |
| V-REVIEW-S43接続 | E-S43-02の最終182入力、既存8file/新test1file | main、文書はdoc_reviewer | 本人合意と同policyのNative/coordinator注入、実機未採用、1本人操作1試行/実5秒上限/SDK終了待ち/非自動REC、S42未受領、旧差分・所有を照合。文書P2修正後解消 | `evidence/20261018-s43-approved/main-scope-review.json`。S43実装done、独立validationは別セッション |
| V-REVIEW-S44 | E-S44-01、最終187入力・既存16file/新5ソース | main、文書はdoc_reviewer | 条件候補/両出力/要求・実値/旧画角・高水位/REC再照合/観測終了/互換/旧差分保護を照合。失敗原因を修正し、App/Unit不変範囲の証拠を継承 | `evidence/20261018-s44/main-scope-review.json`。S44実装done、実機/独立validation未確認 |
| V-REVIEW-S45部分 | E-S45-01、最終203入力・既存11/新13file | main、文書はdoc_reviewer | 記録経路非変更/有界解析/人物不在と解析失敗の分離/世代/REC非依存/意図保持/固定参照/適用と品質/未注入/保全を照合 | `evidence/20261018-s45/main-scope-review.json`。別人拒否1失敗を保持、本人判断/製品未注入でS45 blocked。独立validationではない |
| V-REVIEW-S45再開 | E-S45-02、最終202入力・既存15file変更 | main、文書はdoc_reviewer | 既存成果継承/本人承認/同policy注入/固定参照衝突拒否/即時置換/REC非阻害/実機境界/保全を照合 | `evidence/20261018-s45-resume/main-scope-review.json`、`doc-review.json`。独立validationではない |
| V-REVIEW-S46部分 | E-S46-01、最終201 Swift・所有コード13file/文書2file | main、文書はdoc_reviewer | 実signal/ROI/有界入力/独立WB/時刻境界/失効後復活/高水位と期限/REC非阻害/未注入/既存保全を確認・修正 | `evidence/20261018-s46/main-scope-review.json` とdoc-review.json。本人判断待ち、実機/独立validation未確認 |
| V-REVIEW-S46接続 | E-S46-02、最終210入力・既存10file/新test1file | main、文書はdoc_reviewer | 本人合意/同一policy注入/入力観測起点1秒/更新/端末内完結/REC非阻害/実機境界/既存保全を確認 | `evidence/20261018-s46-approved/main-scope-review.json` とdoc-review.json。S46実装done、実機/独立validation未確認 |
| V-REVIEW-S47部分 | E-S47-01、最終220入力・コード/test17file/docs2file | main、文書はdoc_reviewer | 予告非駆動/非焼込み・命令順序/手動優先・REC分離/現在実値・ISO未注入・所有/既存保全を確認 | `evidence/20261018-s47/main-scope-review.json` とdoc-review.json。ISO本人判断待ち、実機/独立validation未確認 |

## 振り返り・引渡し

- 計画作成日: 2026-10-01。実装完了日・実機工程完了日・PRD受入達成日は未確定。
- 残る判断: 実機方式・能力、資材適合、品質条件／採用、人物なしAF／初回意図／ISO基準等、実環境・対象別操作。各task／Q01へ局所対応し、4段階の合意を未確定へ戻さない。
- 今回は本steeringに従いコードとM01〜M06の永続文書を更新する。入力仕様・旧steering・README・memoを保全し、既存未追跡コードはbaselineを保持した加算変更に限る。PLAN-01の「3文書だけ」は計画作成時点の記録である。
- 実装は今回の明示 `$implement-steering .steering/20260929-device-independent-implementation/` で進行中。実装後の独立検証は同じpathを明示する `$validate-implementation` を別途案内し、自動開始しない。
