# Tasklist — 実機なし先行実装の4段階

## 状態と実行規則

2026-10-01、明示 `$prepare-steering` で計画作成後、明示 `$implement-steering` で実装を開始した。各taskの状態・証拠は以下を正本とする。`pending → in-progress → done / blocked / cancelled` を使い、書込みは原則1件ずつ進める。状態・所有・実行版・証拠・残件はこのファイルへ都度同期し、設計変更時だけrequirements／designも更新する。

今回の明示入力は `$implement-steering .steering/20260929-device-independent-implementation/`。N00で担当と現行正本を確定済み。旧撮影／backend tasklistは過去実績と元の受入義務の参照元とし、今回へ引き渡した作業を旧台帳でも並行実行しない。旧文書未更新期間も新confirmed仕様の限定差分と本計画の開始条件を適用する。旧Ideas／旧steeringの実更新はM07〜M10の別明示Workflowに残し、その待ちを独立コードの一括停止条件にしない。

全タスクは [requirements](requirements.md) と [design](design.md) の安全・所有・検証規則を継承する。役割名は予定担当であり、N00で具体agentを束縛する。同じファイルを同時所有せず、他者の差分を戻さない。実機・G1・G2B・段階全体の未完了を、記載されていない依存として追加しない。各タスクの必要試験が失敗／未実行なら当該taskをdoneにせず、理由・不足事実・影響・独立して進めるtask・再開条件を記録する。

Start／Finishを分けたタスクは、N01等のStartが満たされれば独立部からin-progressにできる。substatus（規則／SDK候補／UI／実接続／検証）の各状態・所有・証拠を記録し、Finishが不足すればtask全体のdoneは保留する。別独立タスクへ移る時は残件と再開条件を明記する。

全本体タスクの共通Verifyは、対象diff・意味ある関連単体試験・必要build／診断・実I/O／UI確認・mainレビュー（V-REVIEW）である。下記Verifyは追加する具体試験。共通Stopは、所有衝突、無断要求変更、禁止動作、実データ範囲不明、必要検証失敗。外部依存・ツール追加、重大未合意方式、実データ消失操作が必要になれば該当箇所だけ保留する。軽微可逆判断は記録して進め、段階ごとの再承認を要求しない。

## 独立検証の2指摘修正（2026-10-26）

明示 `$implement-steering` の範囲は以下の2指摘だけとし、内部 `$steering` を使用する。本節を今回2指摘の現行進捗とし、以下の中断チェックポイントは範囲外の未完了・保全の履歴として保持する。過去の中断・失敗・skip・既知8保全差分と原因/影響未解明を保持し、未適用WIP12file、import B/C、strict正dispatch/native正resume、全媒体producerは続行しない。独立validationは開始しない。

- **開始照合**: DI-SOURCE-20261025-23の515入力すべてが現物とbyte一致（manifest `e7491f7c0d503437f94a207b7caf8be241a75736cc8063e1456c97cad70ac0f5`）。既存dirtyを含む35,665file/881,591,253bytesのhash、515入力＋tasklistの変更前copy、HEAD/index/diffをrepo外 `/private/tmp/fr-finding-fixes-20261026-ia9hki7h/` へ保存済み。復元せず最小差分を加算する。
- **PHOTO-QUEUED-RETENTION-UI-01 / done（限定修正）**: 所有はworkerのLibraryPhotoSaveCommands.swift・ProductPhotoCaptureStopTests.swift、document_authorのdevelopment-guidelines.md（保持説明だけ）、mainのdesign.md・tasklistと新規 `evidence/20261026-review-findings/`。queuedの媒体保持保証を除き、intent前REC停止での回収後queued/明示続行unavailable・表示/Photos未開始/合成source保持を既存試験で確認する。保持policy・回収・再取得/自動再追加は変更しない。
- **P2検証**: DI-SOURCE-20261026-01/515入力の不変copyで、新専用Simulator 3FCAB321-BD4B-43EC-8B80-B09DA5FE7255、FrameRelay/Debug/Test plan FrameRelay・関連4suiteを実行。29宣言/42展開成功・失敗0/skip0、compiler/analyzer/runtime warning0、515入力前後不変。ビルドlogのAppIntents依存なしmetadata抽出skip警告3行は別記し、test skipへ数えない。保持説明のdoc_reviewer指摘0。[回帰結果](evidence/20261026-review-findings/photo-regression-01-summary.json)、[P2 binding](evidence/20261026-review-findings/p2-source-binding.json)。
- **DOC-METADATA-STATUS-01 / done（限定文書同期）**: document_authorが所有する永続4文書の古いmetadata未確定/Photos最終SDK guard未完了表記をDI14/DI18の限定証拠へ同期する。実行版別の成否・継承はtasklistと各stageを参照し、過去失敗/skipと実際の残件を保持する。
- **P3検証・最終束縛**: 永続4文書の5箇所（repository-structureの同一同期漏れ203行も含む）を修正し、doc_reviewer指摘0/相対123リンク欠落0。最終版 DI-SOURCE-20261026-02、515入力/508不変7変更・追加欠落0、manifest 54c30a6983bf9b8336ba9dfc077760a62145f87a0fd4a379557f03b2f159499d。P2実行版01と410コード入力は全一致のため関連29宣言42展開の結果をこの限定範囲で継承。新しい全Unit/全UI/実Photos/HTTP/実機検証とはしない。[今回証跡](evidence/20261026-review-findings/README.md)。
- **今回の保全限界**: 既知8差分と原因/影響未解明を維持。DI23 checkpoint3295pathとの開始前byte差分17件を記録し、今回開始→終了の3295pathは全一致・読取error0、旧Simulator state変化0。原DB接続/修復/reseed/原本Photos削除なし。専用Simulator停止要求は拒否で未実行・再試行せず、終了読取ではShutdownを観測。WIP12未適用を維持。
- **検証・完了条件**: 対象関連test/build診断、保持説明/リンク/差分の確認と新実行版hash・差分・結果の束縛後だけ各指摘をdoneにする。全steering、実機/品質/PRD受入は未完了のまま。

## 中断チェックポイント（2026-10-25、ユーザー指示によるレビュー準備）

ユーザーの「1セッションが長いため、キリのいいところで中断してレビューを受けたい」を受け、download callback FD固定UnitAを区切りとし、新規実装を停止した。全体の完了判定ではない。独立validationは自動開始しない。下の履歴のin-progress/確認中は当時の経過であり、現在状態は本節を優先する。

- **実行版**: DI-SOURCE-20261025-23、515入力（App/Unit/UI/project410、server97、永続文書6、steering要求/設計2）。manifest `e7491f7c0d503437f94a207b7caf8be241a75736cc8063e1456c97cad70ac0f5`。関連182は108宣言成功/Native2skip・317展開成功。実Native183は1成功/skip0、suspended未resume→実cancelled→同owner未固定FD0→session終了、artifact0/verified0/transport lease保持。generic184成功、最終全Unit185は940宣言中884成功/56skip・失敗0、1762展開成功（空template1を除く有意味1761）。全run診断/runtime warning0・410入力前後不変。
- **書込み停止・WIP保全**: Core/App両workerが停止後、後段importの12ファイルを[未適用WIP](evidence/20261024-publication-operations/deferred-download-import-wip-20261025/manifest.json)へcreate-only/hash付きで退避した。9既存ファイルをDI23 bytesへ戻し、新規3ファイルだけをcopy/hash確認後に作業ツリーから除いた。既存dirtyや他者変更の取り消しなし。[復帰照合](evidence/20261024-publication-operations/download-import-wip-freeze-restoration.json)で全515入力一致・コード追加差分0を確認。WIPは未コンパイル・未検証で完成範囲に含めない。
- **残件**: Bは実応答の同writer記録・guarded import・source最終fstat/実close・lease終端・テストが未完成。Cは通常download beginの正当なproducer/条件、full-read ticket、取得前の固定複数Photos意思を再評価してから再開する。原本source ticketをread ticketへ流用せず、単調時刻を撮影日へ代用しない。strict正resume/正式全媒体producer・全S28/S31/S34/S49・steering全体・標準資材/ISO本人判断/実機/品質/PRD受入は未完了。
- **部分の判定・中断**: FD固定UnitAは182/183/184/185とmain確認・文書reviewを束縛して非実機の限定部分done。新規実装を停止し、製品コード・永続文書の書込みownerを解除した。[中断引継ぎ](evidence/20261024-publication-operations/handoff-paused-20261025.md)へ実装範囲/実行版/skip/失敗/未確認/保全/再開条件を整理済み。全専用Simulatorはデータ保持でShutdown、旧CFは操作しない。B/C・全体はdoneにしない。

## 現在の再開点（2026-10-24、独立validation引継ぎ・残実装を継続）

- **独立検証の受領**: `fr-validation-20261024-iczx3nc8/validation-summary.json` とimplementation/documentation専門agent報告を読了。5部分の非実機範囲は合格・新規指摘0。DI-SOURCE-20261023-02の414入力と開始現物は全件一致。旧P2修正、失敗・skip・未確認、全S28/S31/S34/S49・全steering・実機/品質/PRD受入の未完了を保持する。
- **保全・所有**: `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-implementation-20261024-l0p333tn/` に開始全19,251file/565,458,544bytesのhash、dirty/status/HEAD/index/binary diff、対象source/docs/steeringのcopyを保存。既存fixture/原本/Keychain/Photosはread-only hashで保全し、修復・再seed・削除はしない。既存未commitへ限定加算し、mainが本tasklist・新規`evidence/20261024-publication-operations/`・構成/実行証跡・最終diffを所有する。
- **S28 manifest投影 / done（非実機の限定部分）**: 内部 `$steering` を明示使用。現登録/同store UUIDの既知原本（local＋有効catalog）に対するmanifest観測を、確認authorityと分けて同writerへ加算し、nil/版ID/mediaType/置換待ちと取得/再生可否の限定表示をlocal/remote一覧へ投影する。metadataから媒体開始・確認・失効/ACK・削除権限を生成しない。worker `manifest_projection` の具体所有は同証跡`manifest-ownership.json`。書き込みtaskは本部分1件だけ、必要検証前は部分doneにしない。
- **初回manifest-unit-01**: 新規DerivedData/専用Simulator/316入力、compile exit65・0実行。新PublicationManifestStoreTestsの`allSatisfy(\.isCommitted)`を含むTesting macro展開でtry不足1件（build中止を含むerror2、warning/analyzer0）。凍結後のLibraryPublicationProjection防御guard追加もbefore/after差分として保持し、このrunを成功・確定実行版にしない。元source/log/xcresult要約を新evidence/runsへ保存、test1箇所を事前値へ展開して再凍結する。
- **manifest-unit-02 / seed-03**: 凍結316入力の関連9suiteは61宣言/105展開成功、skip/失敗/compiler/analyzer/runtimeWarnings0、前後入力一致。初回macro失敗は新testの事前let評価1箇所だけで修正。新規専用Simulator8D2B4837-8EC9-4A8B-9511-6914BFD0EE85のseed-03は1成功/VERIFY1skip、旧登録manifest1・現登録のV1/V2置換待ち/nil3観測とlocal1/remote3を同writerへ保存し、新規実MOV/外部sentinel/immutable manifestを束縛。既存fixture再seedなし。通常/最大UIとUI後VERIFYは継続中。永続4文書とdesignの安定境界を限定同期し、件数/成功の先取りをしない。
- **manifest-ui-04 / 途中失敗**: 通常UIは1失敗/skip0、compile/診断/runtimeWarnings0・316入力一致。新testの期待改行に対しnative UILabelのAX labelがspaceを返す全文比較だけで失敗（語句/記号/順序一致）。実labelは変えず、期待AX表現の改行だけを単一spaceへ対応させる。原本/外部sentinel/immutable manifestは不変、size largeへ復元、修復/reseedなし。失敗を保持して再検証する。永続4文書の限定doc_reviewerは指摘なし（実装独立validationではない）。
- **manifest-ui-05 / generic build-06**: 通常flowは再launch前後の18監査を実行し、同じ`library.itemReconciliation`のContrast2指摘で全体1失敗/skip0（source316不変、診断/runtimeWarnings0）。要照合のAX領域y86.3/h20.3とnavbar裏blurの重なりを添付で確認。可視配色やSDK誤検知が原因とは断定せず、その1labelを既存native文字計測/描画へ統一しbody太字/全12サイズ/原文/IDを保持する限定修正を行う。監査mask/handler/条件/既存P2非変更。06のgeneric iOS署名なしbuildは修正前316版で成功・compiler/analyzer0。UI05後の合成MOV/外部sentinel/immutable manifestは不変、再seedなし、largeへ復元。
- **manifest-ui-07 / build-08**: 要照合1labelのbody太字/全12sizeを既存native計測へ統一した316入力で、通常一覧/詳細/remote3状態/再launchのUI1件・18厳格監査が成功（skip/失敗/未処理指摘0）。generic iOS署名なしbuild-08も成功し、両runの入力前後一致・compiler/analyzer/runtimeWarnings0。通常UI後の原本/sentinel/immutable manifest不変・large復元を確認。最大文字09と最終VERIFYを継続し、その必要確認前は部分doneにしない。
- **main V-REVIEW追加境界**: catalogのUTF8-distinct Unicode aliasを非nil publication authorityへ渡す新規経路で、既存writerの正規化同値比較が同logicalへ併合し得る静的疑義をworkerのread-only追補で確認。純metadataのexact保持は成立するが、authority/後続失効のowner対応には上位guardが必要。旧writer replay/schema/過去証跡は変えず、最新logical exact対応と最終CAS直前をcoordinatorで再判定し、非nil両順序・非採用側失効の回帰を追加する。最大UI09の凍結実行終了までコード編集は待機する。この必要確認前は部分doneにしない。
- **manifest-max-09**: 最大accessibility-extra-extra-extra-large/AX5で全文・local詳細・remote3状態・再launchを含むUI1件/18厳格監査が成功。skip/失敗/指摘・診断/runtimeWarnings0、316入力前後一致。合成MOV/外部sentinel/immutable manifest不変・large復元。aliasの追加guardはcoordinator/新test2fileだけをその後に直列修正し、render/View bytes・通常起動非同期なし・canonical専用fixtureへの影響を照合してUI07/09を限定継承する。追加Unit/VERIFY/build前はS28部分doneを保留する。
- **alias guard / unit-verify-10 / build-11**: coordinatorと新test2fileだけの追加で、非nil両順序・旧併合履歴でもpure metadata両件exact保持/先着authorityのみ/異原本owner停止・ACKなしを確認。10は10suite65宣言中64成功/seed1skip・110展開成功、11はgeneric iOS署名なしbuild成功。316入力前後一致・compiler/analyzer/runtimeWarnings0。同10でUI後の元原本/sentinel/immutable manifest・同writer再open/全reader0/Keychain空のVERIFYも成功し、旧履歴/schemaは不変。永続architecture/guidelinesへexact logical guardを限定追補。
- **実HTTP新規結合中**: 既存frozen S27 backend273とsource9をread-only照合し、旧runtime/DBを再利用せずmetadata-only専用003を新作。current snapshot helperのstale diffは変更・実行せず、archiveと全一致の現存preparation-002を入力に既存probe helperだけを使う。SDK列挙12は対象1宣言/構成照会のみ、prepare13/dry14は未実行の意味を保持。既存HTTP testの11追加assertionでpure manifest journal全項目/commit/identity/reopenを検査し、旧観測JSON/2HTTP/zero-media契約を維持したactual15を実行中。秘密・既存fixture/原本/Keychain/過去証跡の変更はしない。
- **S28 manifest部分の結了 E-S28-MANIFEST-01**: `stages/manifest/`のDI-SOURCE-20261024-01（421入力、cbb7f9a9…）へ束縛。actual15は実HTTP1成功/skip0、2 metadata/媒体0byte・新確認/ACK0、pure journal全項目/commit/UUID/登録とSQLite再openを確認。parent/listener/wrapper実exit0、全handler/thread/DB-media FD閉鎖・guard拒否0・秘密はlistenerが削除、SDK実task/session数は未観測を保持。postHTTP16の専用VERIFY1成功/seed1skipとbuild11、通常/最大UI07/09各18監査、Unit10の110展開を層別に結合。mainが最終diff/所有・P2/旧証跡/index/HEADの保持を確認、永続4文書と追加guard2節のdoc_reviewer指摘0。全S28は未完了。
- **保全上の例外**: 旧1456保護file中1454はbyte一致。CF SimulatorのPhotos WALは開始時の先頭5706232bytesが全一致し1page追記、SHMも変化。Photos本体DBはbyte一致、読取コピーの100表比較では`ZGLOBALKEYVALUE`の日時/更新counterだけが異なりasset等99表とschema/行数は一致。既存PhotosプロセスのFD保持を観測し、mtimeは新Simulator作成/初テストより前。原因は断定せずraw2差分を記録し、元Photos DB接続/復元/修復/kill/Photos削除はしない。旧28台state/17container、原本/Keychain/5fixture/過去証跡は一致。privateコピーはrepo外のみ。
- **S28 既取得軽量版の単数再生・確認 / in-progress**: 前部分を閉じ、内部`$steering`で次の直接依存へ直列着手。同writerの完全取得/正の配布記録と現登録/版/失効を入力に、app lifetime temporary owner・同registry・local/remote単数再生と同live token本人確認を接続する。所有は`local-rendition-ownership.json`。旧unknown useを採用/解放せず、自use最後の解放による既存temp回収を別検証し、原本や旧fixtureを保護する。通常strict/正式producer/全S28/実機受入へ拡張しない。
- **local-unit-17〜19 / 部分検証中**: 17は新コマンドMainActor境界、18は新testのactor property読み出しでcompile失敗・実行0件。最小隔離修正後19は関連8suite56宣言55成功/1失敗・105展開成功/1失敗、327入力前後一致・compiler/analyzer/runtimeWarnings0。唯一の失敗は原本退避時の既存「アクセスできません・要照合」に対する新期待「原本なし」で、独立軽量版の実再生/保持assertは通過。既存表示を保護して新期待だけ整合する。旧停止の遅延join/新presentation保護、実SDK終端・unknown use保持等を確認、まだ部分doneにしない。
- **local-unit-20 / seed-21 / UI22・VERIFY23**: 新fixtureを正規OriginalStore予約APIの合成MOVへ整合し、退避前後present→absent・独立軽量版を確認。関連9suite59宣言/110展開成功、seed21は1成功/VERIFY1skip。通常UI22は全機能導線を完走したが詳細見出し/有効軽量版buttonのContrast2件で失敗、5監査/327入力前後一致・診断0。raw110attachmentと失敗を保持しnative実renderを修正中。VERIFY23は1成功/seed1skip、原本/sentinel/immutable manifest/fullhash・SQLite再open/reader0、正当な一時媒体2本回収/確認-outbox2・未消費max2を確認。raw後照合scriptの旧container固定による見かけmissingは、移動後current containerの相対hashで再測定し対象temp2件以外不変（旧誤測定も保持）。旧rootを再seedせず、新規D4AFACDE専用rootで通常再試験し既存32123811の未消費maxを使う。
- **local UI28〜33 / native境界修正**: 再試験28は別reconciliation見出しContrast1件と、新nativebuttonのdisabled反映不一致で失敗（local再生/停止/確認完了後、remote未実行）。rawの取得/確認stateとunavailable理由は更新済み、通常再launch観測29でもnativeだけenabledのredを再現。既存reader/modelは維持しSwiftUI.disabledとUIKit引数&&Environment.isEnabledを一致、指摘header1要素を同ID/fulltextのnativeへ整合。30は独立指定normal.local1件消費のVERIFY、31は同rootのSDKstartなし観測greenで全指摘前後を保存。32はD4の未消費max名pairを実際のlarge文字で使い、通常全UI1/5厳格監査が成功（0skip/指摘/診断・327入力一致）。33は独立期待3件の回収/確認-outbox・normal.remote未消費・全原本/sentinel/manifest/hash/SQLite再open/reader0を確認。root修復/再seedなし。最大34は321の未消費max pairをAX5で実行中。
- **local UI34〜40 / 最大文字の追補**: 34は最大AX5で全操作を完走したが、停止後のnav題名UILabel1件・elapsed SwiftUI2件のContrastで失敗。35の原本/hash/全reader/4確認-outbox4/SQLite再openは成功。題名背景opaque化と同locale/小数1桁/AXlabel-valueを保つnative elapsedで36build/38通常UI1・5監査/39normal2本VERIFYが成功（327入力一致・診断0）。40はContrast0/2監査通過後、60秒合成素材の開始158.72sから64.46秒後、全文scroll中stop存在期待で失敗し残3監査未到達。原本/sentinel/manifest/source保持、maxlocal1本回収・本人確認未実施、remote未実施を成功へ拡張しない。期待/mask/全文を維持し、新規19086AB5専用root用のbounded180秒合成素材をtest-only helperで準備中。旧SyntheticMovieFixture制限/既存媒体/rootを修復・再seedしない。消費と本人確認の独立期待を分離して後照合する。
- **local UI43〜51 / 読取範囲と末尾余白**: 新180秒seed42は実native動画/音声duration・4MiB上限を含め成功。43は停止を維持しContrast0だが全文両端到達が未達、録画で大swipeのup/down往復を確認。player実navbarで可視域を計測する短いslow dragとassert前geometry添付へ限定修正し、45で冒頭/scroll進行は正常化、末尾AXframe bottom524に対しscrollmax518の6pt差が残った（glyph末尾は画像上可視、文字欠け/機序は断定しない）。44/46は消費・本人確認の独立期待で回収1/2・確認0・全原本/hash/manifest/sentinel/reopen/readers0を確認。native内容VStackの理想縦サイズ固定と標準bottom16余白を実scroll範囲へ含め、328入力の関連47は59宣言/110展開、48generic iOS build、50通常UI1/5厳格監査、51normal2本VERIFYが成功（compiler/analyzer/runtimeWarnings/skipは通常UI・関連Unitで0、seed/VERIFY対側1skipを保持）。842A7F12の新専用root49は1回だけseed、旧19086は保全後shutdown/data保持、修復/再seedなし。最大52は同842の未消費max pairを実行中。
- **local最大52・VERIFY53 / gesture再確認**: 52は冒頭到達・停止固定/可達/min44・Contrast0/2監査を保持したが全文末端AXframe底524と可視域底518の差が解消せず失敗、残3監査とremoteは未実行。53は独立期待でnormal2本＋max.local回収3・確認/outbox2、max.remote未消費、全原本/source/sentinel/manifest/reopen/readers0が成功（seed1skip、328入力不変・診断0）。約154ptのdrag要求で実移動約144pt、終盤の10pt要求で移動0となる記録から、scroll終端ではなくpan認識閾値の影響を再調査する。UI helperの実gesture最小距離だけを修正候補とし、±2/28回/実viewport/全文/固定footer/監査条件は保持。既存842 rootは再seedせず、新規専用Gesture rootで再実行する。
- **local最大55 / VERIFY56 / 限定tail検証へ**: 6th新規専用76647BEFの1回seed54と、実AX5でnormal名の未消費pairを使用。32pt最小dragで全文両端へ到達し、実9→10秒/停止固定/本人確認/local・remote/背景停止の全操作・5厳格7種監査は指摘0。ただしclose後の一覧が最下部100%でremote row未生成となり、上側を探せないUI helperがunreachableで全caseは失敗（失敗履歴保持、再launchは未到達）。56はnormal2回収・確認/outbox2/max2未消費・全原本/hash/sentinel/manifest/reopen/readers0成功、seed1skip。Appは47/48/50とbyte一致、test変更だけを照合し、通常top gestureを加えた消費済みremoteの末尾/再launch専用checkで必要範囲だけ再実行する。copy復元/再seed/SDK新開始はしない。
- **S28 local consumer部分結了 E-S28-LOCAL-01**: DI-SOURCE-20261024-02、433入力/f6cd0fdd…、App/Unit/UI/project328へ束縛。57は既消費normalの実AX5末尾・再launch1件/厳格7種1監査が成功、SDK新開始0・全MOV/sentinel/immutable manifest不変、large復元。58VERIFY1成功/seed1skipでnormal2消費/確認/outbox2・未消費max2・全原本/hash/reopen/readers0を確認。App byteは47/48/50/55/57/58で一致、Unit47の110展開/Build48/通常UI50の全5監査、失敗55内で完走した全5監査と実SDK操作、成功57の未到達tailを層別に継承（修正後のfull max method再実行はしておらず55の失敗を保持）。mainが20file全差分/所有/既存P2・旧証跡/HEAD/indexを確認、永続4文書＋native/material追補のdoc_reviewer指摘0。原本/Keychain等1454file一致、旧Photos補助2fileは4frame追記・100表中日時/counter1行のみ変化を別読取copyで追跡し、原因未断定/元DB接続・修復・復元・削除なし。全S28未完。
- **S31/S34 単数・固定複数Photos consumer / in-progress**: 内部`$steering`で次の1書込みtaskへ着手。所有は`photo-batch-ownership.json`、core9fileとApp19fileは重複せず、mainが実行/証跡/進捗/最終diffを所有。同writerの固定source/child予約とexisting PhotoRegistration結果を接続し、初回native Wi-Fi観測、受理済みlocal続行、capture時未開始hold、明示continue/cancel/retryと重複防止を扱う。正式producer/通常strict正resume/全媒体停止・全S31/S34/実機受入は引き続き未完。新規専用合成rootだけを使用し既存Photos/原本/Keychain/rootを再seed・修復・削除しない。
- **Photos関連59 / 初回compile失敗**: core9/App19を凍結し342入力、関連17suiteを選択。App compile通過後、新Support/ProductPhotoSaveBatchFixtureのPhotoBatchLibrary actor/typeとinitのnonisolated推論診断でexit65・実行0。build要約はsource error1＋testing取消1、warning1/analyzer0/runtimeWarnings0、前後source一致。現物とsnapshotに明示nonisolated修飾は無く、test fixtureのdefault MainActor/ApproachableConcurrency推論を限定確認する。元診断/log/342snapshotを保持し、許可する再編集はApp worker所有の同newFixture1fileだけ、業務検証成功には数えない。新E436専用rootのNativePhotoKit/通常Appseed/UIは未実行。
- **Photos関連60〜61 / 実行回帰を修正中**: fixtureのactor生成をdefault引数からMainActor bodyへ移す最小修正で初回診断解消。60はtestprobe async witnessのMainActor変異2error/0実行、1注釈修正後61は342入力前後一致・compile/analyzer/runtime診断0、128宣言111成功/16失敗/専用Native1skip・256展開成功。15失敗はnewPhotoStore boundaryでSIGBUS stack guard crash、原ipsを新rawへ保全しcore所有内で調査。別1失敗は従前S28実再生停止後のreclaimed/reader解放で、SDK停止/monitor/tokenは成功、App owner側で調査する。旧S28成功はDI-SOURCE-20261024-02の実行版の限定証拠として保持し、今回regression成功には使わない。NativePhotoProbe/通常seed/UIは未実行、各原因修正/必要再検証前は部分doneにしない。永続4文書reviewの限定P2一文はauthor修正後doc_reviewer再確認で指摘0、link58欠落0（実行結果/独立validationの検証ではない）。
- **Photos stack/使用権修正・関連63成功**: 61の15ipsは大再帰なし41〜64frame/stackguardで、新boundaryの巨大child/associated payload複製が同時にstackへ配置される観測と整合。派生ChildStatusのみindirect化し、新Projectionをindex走査/小guardへ分割（journal/Codable/全guard/試験条件不変）。RFactory.releaseはexact temporary owner＋全usage bytesのretained taskへ合流し、inProgressだけ5ms/最大2秒待機、caller取消でもjoin・unknown/failedは推測再試行なし。新実AV＋実temporary busy inspection/barrier回帰を追加しSDK/原本/hash/reader/reclaimを検証。62は新testbarrierのOriginalStorePort転送不足2error/1warning/0実行を保持、転送だけ追加後63は342入力前後一致・17suite129宣言128成功/Native1skip、289展開成功/失敗0/compiler/analyzer/runtime診断0。既存S28試験・core test77展開は期待値不変。新E436専用へ写真add/readを明示grantし、通常Unitでskipした実NativePhotoKit64を1probeだけ実行中（metadata受付WiFi注入を通常strict正開始へ拡張しない）。
- **Photos Native65・通常UI70の限定実績**: 64はSwift Testing selectorの括弧不足で0実行を保持。65は専用NativePhotoKit1成功/skip0で実追加・同writer結果/終端・自身use/reader0/reopenを確認（受付Wi-Fi注入、native経路wiFi観測を正式受付証明へ拡張しない）。66のread-only INSPECTは既存asset7を実測、67generic iOS build/68一回seedは344入力前後一致・診断0、原本2/媒体3・batch0/PhotoRecord0・旧asset7不変。69はrunner期待JSON欠項目でApp launch前失敗、70は通常Appのnative Wi-Fi受付→単数実追加成功/重複抑止表示/媒体1回収まで到達し厳格7種1監査指摘0、その後の非操作label探索helperがunreachableで全case失敗。混合2本は未処理、保持MOV/原本/sentinel/immutable manifest/hash/inode不変・large復元。失敗を保持し、source App/core28は凍結、new Seed/UI2だけで実viewport/fulltextを維持したhelper・partial VERIFY・既成功child固定tailを準備する。単数再追加/修復/reseedはしない。
- **Photos partial VERIFY71→72 / tail73**: 71は新VERIFYのreclaiming=false期待が既存回収履歴policyと不一致で1失敗、製品/fixtureは不変。新Seed1guardだけを消費済reclaimed/reclaiming双方true・未消費双方falseへ整合後、72は1成功/skip0/344入力前後一致・全診断0。exact batch1/child1/PhotoRecord1・baseline7∪実asset1・resource全hash/日時/動画音声、媒体1回収＋2保持/全原本/sentinel/immutable manifest/inode/Keychain空/SQLite再open/readers0を確認。通常App/core28は65/70/72でbyte一致、既成功child固定・単数再追加なしの73tailで混合2本→再起動だけを続行。queued/prepared holdはperforming Task固定前までで、開始後local jobのREC取消/native add直前SDK排他・REC中全媒体開始0は未成立として保持する。
- **Photos通常tail73 / 部分UI修正**: 新text helperで旧single child/全文/過去成功/重複抑止を確認したが、厳格7種1監査が旧local photo.reconcile blue20.3pt ButtonのContrast1件を指摘。その後local toggleのcenter tapがvalue0のままで停止し、混合新要求/SDK追加/媒体回収0。344入力前後一致・全診断0、保持hash/inode不変・large復元。失敗/添付を保存し、LibraryViewの該当button1箇所だけを原文/ID/処理保持で既存native44buttonへ統一、新UI1fileだけで実switchへの1tapと厳密value待機を整える。Seed/同writer/SDK/既存test/fixtureは不変、修復/再seed/単数再追加なし。
- **Photos通常tail74・VERIFY75**: 74は全機能/混合2本実追加/過去単数再追加0/再launch exact3 childを完走、媒体2本だけ追加回収・保持hash/inode不変・large復元。ただし厳格7種4監査はDynamicType5（汎用header/transfer・cleanupと理由）/Contrast2（navbar下の旧local過去成功Text/newremote Toggle label）でcase失敗、先の単数結果監査成功の中間見込みを最終指摘で訂正する。75の独立状態VERIFYは1成功/skip0/344入力前後一致・診断0、batch2/child3/PhotoRecord3・baseline7∪実asset3/全resource hash/日時/動画音声・全媒体回収3/全原本/sentinel/manifest/inode/Keychain空/再open/readers0を確認。E436は後照合後shutdown/data保持、再追加/修復/reseedなし。View1fileだけで指摘描画を既存native全12sizeへ最小統一し、old P2 tests/削除確認dialog/原文/ID/有効条件を維持する。新規専用82CD3937/nonce5a0dfd38をcontextへ加算して通常fullflowを新媒体だけで再実行し、未seedのEDAC最大文字も続ける。
- **Photos描画修正後76〜78**: LibraryViewだけをnative全12sizeへ限定統一し、local Photos表示/remote Toggle label/汎用local-count header/generic操作/理由へ適用。UIButton.roleで旧discard.destructiveも保持し、確認dialog〜messageの完全byte一致をmain照合、他App/core/test27fileはafter65不変。76generic iOS buildは344入力前後一致・全診断0。新82CDの77 read-only INSPECTは初期asset6を実測（許可は新deviceだけ明示grant、test自体のFactory.openなし）。78は現存empty0 rootへの1回だけseed中で、新規素材3本で通常全flowを確認し、旧E436の3成功/7asset基準/全旧媒体・証跡を保持する。
- **Photos最終通常79・partial80・tail81**: 78の一回seed成功後79は現Appで単数実追加/2厳格監査指摘0を通過し、混合選択/native gate有効の確認でnew UIのheight>=44が43.99999999999977ptとして失敗、混合tap0。実frame y631/maxY675のULP合計2.2737367544323206e-13ptと差が一致するため、新UI1fileだけを有限性・誤差上限1e-8pt未満の座標表現精度込み比較へ限定修正（44pt/実不足拒否/全文/viewport±2/監査mask不変、整数/pixelへの丸めなし）。80は1成功/skip0/344入力前後一致・診断0でbaseline6∪実asset1/1回収＋2保持/全原本hash-inode/readers0/reopenを確認。App/coreは76/79/80で不変、既成功child24E69140を固定した81tailで単数再保存0・未処理混合2本だけを続ける。79の失敗を保持する。
- **Photos通常結合81〜82・最大文字85→86→87**: 81tailは1成功/skip0/厳格7種4監査指摘0、通常Appのnative Wi-Fiで混合2本実追加・単数再追加0・再起動exact3を確認、82の全3結果/原本/Photos6∪3/resource/日時/音声/全reader0/reopenも成功。Appは76/79/81/82でbyte一致し、79の先行2監査と単数実操作を限定継承（full通常method79の失敗自体は保持）。EDACの83 INSPECT/84一回seedは初期6asset/固定2batch3queued/Photo0/use0/owner0を確認。85 AX5は最初の巨大カードh1926ptの中心hittable探索がviewport758pt内で往復し、0監査/SDK追加0で失敗。86はexact queued3/Photo0/asset6不変/全媒体3保持/原本hash-inode/readers0/reopenが成功。newUI1fileだけをnative title h126ptの全文/実viewport上下±2/hittable/1tap→exact詳細へ直し、reseedなしの87でMAX fullmethodを再実行。通常・最大のcode344前後一致/診断0、失敗と元証跡を保持する。共有native操作描画の既存P2・新規専用2C248の容量整理確認dialog/実unlink回帰と、Factory release修正の未消費766 max pair実AV再確認を次に必要範囲だけ実施する。
- **Photos最大87〜90の実操作と残UI**: 87は実タイトルnavigation/単数実保存/厳格3監査指摘0後、SDK監査によるreflow/scroll移動で混合resumeがAX treeから外れtap失敗。88は単数1成功・混合queued2/asset6∪1/1回収＋2保持/原本hash-inode/readers0/reopenを確認。audit後にbuttonを再取得するnewUIだけの修正で89は混合2本を実明示続行・媒体2回収、単数再追加0/監査1指摘0だが、上側の結果/登録ラベルがAX省略となりdown-only探索でcase失敗。90は1成功/skip0/344入力一致・診断0で全3PhotoRecord/実asset6∪3/resource全hash/日時/音声/全原本・source・manifest・sentinel/inode/Keychain空/readers0/reopenを確認。既成功を再追加せず、Rootだけ最上部から探索し直すnewUIとread-only MAX結果/再起動2監査を準備中。87/89失敗を保持し、必要UI確認前は部分doneにしない。
- **追加直接依存の再確認（read-only）**: `pending-direct-operations.json`へexplorer結論を保存。通常requestの本人停止/取消/再開意思/全件停止UIはLUT/ISO/Q01に依存せずBG既知停止後へ直列候補。原本uploadも固定集合のlocal queued受付は既存describe全hash/TransferBatch/.batchを入力に独立実装可能で、metadata POST/GET→session照合は端末remote・wire・開始前同writer query世代producerが不足する実装枝として残す（標準資材の外部待ちではない）。whole-source upload portとserver chunk PUTの差、strict正dispatchは別枝。generic SDR取込はrequirements108の外、現captureはLog1/2のみ。既成Rec709ならLUT不要でも正確な入力encoding/独立検証/正式proof producerが未成立であり、legacy compress-only/technical fixtureを正式producerへ昇格しない。独立validationは開始しない。
- **Photos最大read-only91成功**: Rootの未生成/画面外要素はcapture markerへ戻り通常下方探索、DetailではRoot topを呼ばないnewUI修正後、91は1成功/skip0/厳格7種2監査指摘0。全3固定child成功全文・remote登録・再追加disabledを通常再起動前後で確認、save/resume/retry tap0・新SDK開始0、全MOV/原本/sentinel/manifest/inode不変・large復元、344入力一致/全診断0。Seedコメントtwo→threeだけ正確化しApp/coreは76/87/89/90/91で不変。87の単数2監査と実保存、89の混合開始前監査と実保存、90の全状態を限定結合し、失敗87/89や未再実行full MAX methodは保持する。92の最終VERIFYと共通操作/P2回帰前はS31/S34部分doneを保留。
- **保全追補03（限定差分を保持）**: 旧1456保護file中1452 byte一致、旧28state/17container・歴史5fixture・全原本/媒体・P2/旧証跡/HEAD/indexは不変。既知Photos補助2fileに加え旧起動中CFのKeychain WAL/SHM変化を検出。本体DBと開始WAL2987032byte prefixはSHA一致、20frame追記。原本へSQLite接続せず私有copyだけで比較し、28表中genpの43行中1行のmdat/data/sha1が変化・他42行/27表は一致。変更行のaccess groupは公開apple literalと一致するがserviceはopaque20byte indexで対象範囲未確定、復号/平文値出力0。securityd PID108の10月19日起動を観測しても原因は未断定とし、復元/修復/削除/killなし。Photosは先頭prefix一致/8frame追加、100表中ZGLOBALKEYVALUE日時/counter1行だけ・asset等99表不変。`protection-followup-03/summary.json`へ訂正/限界とhash/metadataだけ保存、DB/WAL/SHM私有copyはrepo外に保持する。全Keychain byte保全の成功とは報告しない。
- **共有Factory影響のS28実AV再確認93〜94**: このsessionで作成した766の未使用max pairだけを正規使用し、現在344入力/App凍結版の93はMAX全method1成功/skip0・厳格7種5監査指摘0、actual AV local180/remote30・実9→10秒・停止固定・同live token本人確認・背景停止・再launch/自動再生なしを確認。予定temp2本だけ正規回収、全原本/MOV/sentinel/manifestのhash不変・large復元。94は1成功/skip0で既消費normal2＋max2の4確認/outbox4・全原本/hash/readers0/再openを確認、766はその後shutdown/data保持。旧55失敗や段階02の433実行版は保持し、新evidenceでFactory release修正と現在共通描画の影響を別に束縛する。95は新規2C248/nonce1efa9fbaの空rootへ容量整理fixtureを一回だけ作成中、既存root/原本/Photos/Keychainの修復・再seed・削除なし。
- **共通native操作の確認dialog/実unlink回帰95〜97**: 新規2C248/nonce1efa9fbaの一回seed95は1成功/skip0。96 raw helperの参照stemに.movを付けない事前guardはApp launch/test/SDK前に停止、helperだけ正規pathへ修正し元失敗を記録。実96 UIは1成功/skip0でnative共通button→固定3対象review→取消→再確認→明示確定→結果→再起動を確認。新規合成a/bの2.movだけ実unlink、不適格missing/保持keep・外部sentinel/manifest/reservation/hash/inodeは不変・large復元。97は1成功/skip0で固定batch3・2removed/1notExecuted・保持原本/証拠/verification/confirmation/request/Photos0とSQLite再openを確認。344入力前後一致・全診断0、2C248は後照合後shutdown/data保持。既存P2試験/OriginalPlaybackViewはbyte不変で、新規64ADの98一回S16/P2 seedが成功、fresh history99→通常/最大文字・VoiceOver回帰を続ける。
- **既存P2通常99〜100 / 回帰修正中**: 99 fresh historyは1成功・厳格7種2監査指摘0。100の既存8methodは6成功/2失敗・skip0、344入力前後一致・全診断0・全原本/MOV/manifest/hash-inode不変・large復元。detail-actions監査はnav背後の既存SwiftUI説明文`library.detailReconciliationExplanation`にContrast1件、VoiceOver履歴は5check中history removalだけ不足（UI hierarchyには全原文/状態を含むcombined labelが存在、発話原因未確定）。元失敗と添付を`diagnostics/p2-final-normal-100/`に保持し、worker所有LibraryViewの該当説明文だけを既存native bodyへ修正、履歴AX/既存P2test/OriginalPlaybackViewは保持して必要再確認を行う。S31/S34部分doneとBG書込み開始は保留。
- **P2限定再確認101 / 履歴順序を修正**: Viewの説明文1箇所を同原文/IDのnative bodyへ統一後、一覧・詳細1method/厳格7種3監査は成功・指摘0。VoiceOver1methodは同じhistory removalだけ失敗し、assertion直前の診断4行で実発話を保全（旧test期待/loop/監査/復元は全byte保持）。historyとsubmissionの長utteranceはいずれも64文字で終わり、全文AX122文字の90文字目以降にある破棄結果だけ未取得、原因をSDK仕様と断定しない。履歴だけ原本不在の直後へ同じ破棄状態のnative表示を移し、publication/retrieval等全状態・全文/ID/combineを保持して再確認する。101は2件1成功/1失敗・344入力一致・全診断0・全原本hash-inode不変/large復元、失敗を保持。
- **P2通常修正後102成功**: 履歴だけ削除結果を原本状態の直後へ置き、通常一覧順・全状態/原文/ID/native/combineを保持したView726500…で既存2methodが成功/skip0。厳格7種3監査指摘0、実VoiceOverで履歴原本なし/破棄済み＋submission対象/操作/引渡し状態の5checkを取得。344入力一致・全診断0・全原本hash-inode不変/large復元、旧100/101失敗は保持。P2testへの加算はassert直前の診断添付4行だけで、期待/64loop/assert/VO復元/監査maskの全byte保持をmain照合。永続functional-designへ表示方針2文だけ同期し専門read-only review中。最大文字103の4既存methodと現iOSbuild104、後VERIFY前は部分doneを保留。
- **S31/S34 local Photos consumer部分結了 E-S31-S34-PHOTO-01**: DI-SOURCE-20261024-03の449入力/5a9f2c29…/code344へ束縛。103最大文字の既存4method・104generic iOS署名なしbuild・105原本同一性/全reader0後照合は全成功/skip0/診断0/source前後一致、large復元/全MOV・manifest hash-inode不変。102の通常strict/実VO、100の非影響6成功、関連63の289展開・実Native65、通常79→81→82/最大87→89→91→92の限定phase、sharedFactory93→94、専用合成整理95→96→97を影響/版照合して結合（全failed fullmethod/compile/SIGBUS/skip/0実行を保持）。mainが31file差分/所有とP2診断4行だけの加算・旧全assert/loop/audit保持を確認、永続4文書と最終表示方針のdoc_reviewer指摘0。詳細は`stages/photo-batch/`。全S28/S31/S34/S49/全steering、最終PhotoSDK開始排他・受理済Photos取消/全媒体停止、正式producer/実機/品質/PRDは未完了。旧CF補助4fileの保全例外は追補03を保持しKeychain全byte不変としない。
- **BG既知owner停止→通常失効同期 / in-progress**: 内部`$steering`で次の1書込みtaskへ直列着手。worker publication_uiの所有8fileは`background-invalidation-ownership.json`。same-writer実invalidation reservation/epoch/storeUUID/登録を用い、first pollの実cancel→inProgress/ACK0、次の明示pollで実SDKterminal/自身FD閉鎖/lease absence/stopped＋fresh全inventory/journal exactを照合して既存media終端/ACKへ接続する。removal seal偽造・本人intentのcancel化・旧owner採用・正native resume・全媒体完了は行わない。Native検証は新64AD内の別新規UUID custom rootだけ、既存default P2fixture/原本/Photos/Keychainには触れない。
- **追加直接ready: Photos最終SDK開始排他**: read-only strict_dispatchの調査で、local PhotosのperformChanges直前へ既存capture単回同期許可を接続でき、LUT/ISO/Q01/通常URLSession strictには依存しないことを確認。heldBeforeStartを永続notAttemptedへ丸めず、live intent/useと確定SDK非開始を保持しlock外wake・同intentで再開する型境界/producerが実装残件。BG→本人操作→原本受付/metadataと直列に進める候補。既受理performChangesの取消handle欠如は別限界として保持。
- **保全追補04 / Photo stage03後**: 12:13 UTCのread-only bytes照合で開始1456file中1452一致・旧28state/17container/歴史5fixture/全原本を保持。Keychain全protectedfileは追補03観測時と同一で、以前の暗号化1行変更/opaque service/原因未断定を保持。Photosは既知prefix SHA一致の9frame追記へ増え、元DBに接続せず私有copyだけの100表比較でZGLOBALKEYVALUEのZDATEVALUE/Z_OPT1行のみ・他99表/asset/schema不変。元DB/WAL/SHMのcopy前後hash一致、復元/修復/reseed/削除/killなし。safe hash/表digestだけ`protection-followup-04/`へ保存し私有DBはrepo外のみ。全Keychain byte不変とは報告しない。
- **BG関連106 / 新規test compile修正中**: 全8個別hashと現物の一致を確認し348入力へ凍結。App側compileは通過したが新BackgroundInvalidationTestsのopen引数candidate不足・immutable requests代入のsource診断2件（取消を含むbuild error3）、実行0/exit65を保持。source前後一致・warning/analyzer/runtime0。worker再編集は同new Unit1fileだけを許可、条件/guard/期待を保持して必要修正後に同関連範囲を再実行する。永続4文書のBG差分は専門read-only reviewで指摘0/相対60link欠落0（実行検証ではない）。
- **BG関連107 / 新規7宣言の実行不具合を修正中**: compile2箇所だけ修正し他7file不変で再凍結。107は348入力一致/全compiler-analyzer-runtime診断0、14suite86宣言76成功/7失敗/Native3skip・181展開成功/7展開失敗（14issue）。新Core4宣言は停止前guardでinProgress/SDKstopに届かず、新Composition3宣言は新fixtureのRegistrationConnection生成時invalidConfiguration。旧関連の失敗はなく、Native新probeはまだ未実行。worker最終応答のmodel容量エラー後、mainが2compilefix全文を確認して再実行し、実行修正の所有をworker manifest_projectionへCoreCoordinator/newUnit/newCompositionTestの3fileだけ移管、他5file/docs4は凍結。新fixtureのcanonical登録と、fresh SDK/journal安全観測のproducerを切り分け、guard/期待/既存removal意味を保持して原因修正する。107失敗/skipを保持し部分doneにはしない。
- **BG原因修正108→109再確認中**: newCore stopのepochを、ManagedOriginalAccessのprivate原本owner epochとwriterのmedia reconciliation epochへ分離。writer epochは実reservationと引数のexact、原本側は同live owned lease/source/binding exactを維持し異種epochの同一比較だけを除いた。新Unitは両実epochが異なることと代用拒否/stop0を加え、旧unclosed拒否・正停止条件は保持。Composition新専用rootの初期登録/planを既存inventoryRegisterのcanonical UUIDで作り、旧helper/fixtureは修復しない。108は別fileのfileprivate uploadLease helper参照でcompile1診断/実行0（cancel含む2）を保持、mainがnewUnit1箇所を同source.upload patternへ替え他7fileを保持して109同関連を再実行。永続architectureの2epoch追補は専門read-only review指摘0。Nativeは新64AD内の一回限り別UUID tmp rootだけを用意、関連成功後に明示optinで実行する。
- **BG失効接続部分結了 E-S27-S28-BG-02**: DI-SOURCE-20261024-04、453入力/7f22d315…/code348へ束縛。109関連14suite86宣言83成功/Native3skip・188展開成功、110実SDK非送信1成功/skip0、111generic iOS署名なしbuild、112全Unit725宣言680成功/45skip・1185展開（空template1を除く有意味1184）が全成功/診断0・code348全前後一致。110は新64AD別UUID tmp rootでresume拒否由来の実cancel1/SDKcallback1・source自身FD保持のfirstACK0→実EBADF/leaseabsence/stopped→後normal poll ACK1/再openを確認、metadata/permit/Mac notExecutedは注入・新失効stopのnative発行証拠にはしない。defaultP2原本/manifest/hash-inode不変・large復元、customroot11fileを112後保持。mainが8file最終差分/所有・旧removal/sourceunknown/epoch2軸/Keychain非fallbackを確認、永続4文書とepoch追補の専門review指摘0。106〜108失敗/45skip/旧CF補助4file例外を保持。詳細`stages/background-invalidation/`。正式activeupload/正URLSession resume/allmedia/全task・実機品質・PRDは未完了。
- **本人通信操作の単数/固定全件停止 / in-progress**: 内部`$steering`で次の1書込みtaskへ直列着手。`request-control-ownership.json`のcore13/UI9は重複なし、core worker manifest_projectionが先にtyped contract/atomic journalを作り、UI workerはその合意済み型が揃うまでread-only。新schema7 additive1caseでparent指示ID/単数・全件/action/固定targets/子IDを永続化し、同writerで子別適格性と本人意思/記録済・未処理理由を原子的に投影。unknownは元mutationだけexact照合、確定CAS conflictだけ同plan再評価。SDKstop/実終端は記録と分離して対象別に照合、再openのplanからSDKを自動再実行しない。全件対象はbackend.requestsのみでlocal player/Photosを混ぜず、native正resume拒否・capture wait別軸・旧journal互換・P2を保持する。新通常/MAX専用2環境の一回合成fixtureでUI/再openを確認する予定。
- **本人通信操作・compile診断追補**: 116は旧test fixtureへ修飾なしinit 1行を試したが未解消、追加行だけ除去し元hash634da287…へ完全復元。117は新規DerivedDataでも同じactor暗黙nonisolated診断1+warning1、0実行/356入力不変。旧112成功時は該当fileがincremental再利用であり、frontend再評価の証拠と分離する。raw専用scratchの最小typecheckで原因を絞る間、core/App/fixtureは凍結、Seed/UI未作成・既存data保全。
- **本人通信操作・最終差分確認**: 117の実151入力/15primaryをrepo外で再現し、RenditionテストとPhotos fixtureのprimary対で同診断を再現。actor factory1行とその呼出1箇所だけの同値境界で元15primaryが診断0（runtime検証は未実施）。元default/protocol/assertionを保持。mainが3回確定CAS競合後の照合孤立を検出し、確定未commit時の競合返却と回帰testを同workerへ依頼。Core2/新SeedUI2/structure文書1は同一task内の重複なし所有、実seed/SDKは未実施。
- **2026-10-25 本人操作の実行追補 / in-progress**: 118全Unit754宣言707成功47skip/1228展開（空templateを除く有意味1227）・119generic iOS buildは全成功/診断0/358入力不変。120/121の専用通常/MAXへ各一回seed成功。122はmainがtoolbar IDを誤認して取消し（失敗1のまま保持）、実際にはlocalPauseとstrict2監査が完了し指摘0。123の未消費期待は不一致、124はXcode container UUID変更に対する検査の絶対path比較だけが失敗。元manifest・root/4file inode/hashは不変、read-only検査helperを限定修正し125でlocalPause1親1子・再open・全reader0を確認した。126は未消費の停止解除からtail検査中、MAXは未操作。修復/reseed/削除なし。App/project全同hash、118/119は新Seed/UI2helperだけの差を限定継承。全task/全体doneではない。
- **2026-10-25 固定原本upload受付store core / in-progress（唯一の書込みtask）**: 本人操作のApp/Core・全Unit/buildを束縛した463入力の候補版DI-SOURCE-20261025-01をread-onlyコピー化し、その残るUI検査は独立DerivedDataから継続する（部分全体doneへは進めない）。次の直接依存が揃った原本転送の固定受付store core12fileだけを`original-upload-core-ownership.json`で単独workerへ直列引渡し。新schema7 eventは固定全集合/子ID・子別queuedまたは未処理・不変初期recordと実receiptを保ち、legacy.batchを変更せず、原本statをhash済・通信開始へ昇格しない。UI/metadata/送信producerは後続、標準資材/ISO/Q01はこのstore部分の阻害条件ではない。

- **2026-10-25 本人操作の実行追補（部分全体は確認中）**: 118全Unitは754宣言中707成功/47skip・1228展開（有意味1227）、119 generic iOSは診断0、358入力を固定。通常UI122中断/126失敗を保持し、128の残操作と129の実writer照合で6親/10子・本人意思/全wait/再open・全合成媒体hash/inode・readers0を確認した。MAX130はlocal pause/resumeだけ実施後、厳格監査後の片方向探索で対象を再取得できず失敗し、131の実writer照合は2親/2子のまま成功。全成功にはしない。旧候補463入力を保全し、UI探索1fileだけの派生候補DI-SOURCE-20261025-02（463入力、82ac7923…）を分離した。135では業務tapなしで同じMAX prefix2と監査前後のnativeボタンを確認中。既存データの再seed/済み操作の再送はしない。
- **2026-10-25 原本upload受付・通常製品接続の追補**: Core12/App13をfreezeし、同writerの専用実receipt・不変初期record/現在requests別投影・単数/固定複数の通常操作を接続。callback後のUUID/同exact record再照合をmain確認で補強した。133関連14suiteは113宣言/294展開成功・skip0/診断0、134 generic iOSは370入力不変・診断0。132の新test引数compile失敗/0実行を保持する。永続4文書は専門read-onlyレビュー指摘0/77リンク欠落0。次は新規専用normal/MAXのSeed/UI2だけを同taskの書込み所有とし、実行はmainが担当する。受付時statは短時間FDの観測であり、fullhash・媒体送信・strict通信許可・実SDK開始の証拠ではない。metadata照合/全producer/全S28・S31・S34・S49/実機・品質・受入は未完了。
- **2026-10-25 不変候補での実行続行**: 原本受付477入力のDI-SOURCE-20261025-03（3a2d67bb…）で136全Unitは789宣言中740成功/49skip・1307展開成功、診断0/372コード入力不変。137は新規通常rootの一回seedが成功し、saved binding3/実在2/最初から未作成1・要求0を照合。文書2リンク追補も専門レビュー指摘0/全79リンク欠落0。本人操作135はMAXの業務tapなし監査・同一Button再取得・全履歴map不変が成功し、138のwriter照合もprefix2のまま成功した。旧130失敗は保持。2新UIの探索だけを改善し、他本文/全assert/7種監査を保持した派生候補04（本人463）/05（受付477）を不変copy化した。139は未消費remotePause以降、140は新規MAX受付seedを確認中。全体doneではない。
- **2026-10-25 upload metadata予約/照合core / in-progress（唯一の書込みtask）**: [所有Core12](evidence/20261024-publication-operations/upload-metadata-core-ownership.json)へ直列着手。通信前begin queryの単調世代を同writerで予約し、実begin receipt・UUID・query・応答全payloadのfingerprintを持つatomic observeへ接続する。旧nil provenance/旧verification receiptを保持し、新観測receiptを明示authorityとする型付き証拠だけを採用する。POSTのsession確立をstatus/実送信へ昇格せず、session不明のpause/cancel中はPOSTしない。既知sessionのGETは本人意思を戻さず照合し、cancelledをnotExecutedへ偽変換しない。旧候補の実行は読み取りコピーから継続し、Core以外の新feature書込はまだ許可していない。標準資材/ISO/Q01はmetadata部分の直接阻害条件ではない。
- **後続の直接依存**: 単数/複数操作、S23/S49 strict dispatch/native正resume、S31/S34通常Photos/全媒体producerをread-only調査中。標準資材/ISO/実機条件は直接依存枝だけに残す。独立validationは自動開始しない。

- **保全追補05（2026-10-25 02:05 JST）**: 旧1456file中1451byte一致。旧起動中CFのKeychain本体/WAL/SHMとPhotos WAL/SHMに差分があり、旧28state/17container/歴史5fixtureは一致。私有copyのみの論理比較はKeychain genp/sqlite_sequenceの2表、Photos ZGLOBALKEYVALUEの日時/カウンタ1表だけが相違。Keychainのサービス/原因/製品範囲は未確定とし、旧時点の本体byte一致や暗号化1行だけという範囲を現在へ拡張しない。詳細は[保全05](evidence/20261024-publication-operations/protection-followup-05/summary.json)。原DBへのSQLite接続・修復・復元・旧process停止なし。
- **追加実行141〜147・全体未完**: 原本受付141は単数A→固定3本→再起動→明示記録lookupまで到達したが、厳格16監査で同じmissing行ToggleのDynamicType2/Contrast1により失敗。142実writer照合は2親4子/受付2・既受付1・原本不在1/要求2、全receipt/UUID/再open/readers0/全hash-inode保持で成功した。native選択ラベルとroot nav背景の表示2hunkだけを旧477へ分離し、DI-SOURCE-20261025-06（4dd5e198…）で144読み取り確認・145 generic iOSが成功、MAX146は未消費fixtureから実行中。本人操作139はremotePause1tap後のAX cullingで`.label`取得失敗、143はremotePauseの3親3子を照合して成功。次はremoteResume以降だけを再開する。元失敗は保持し、全flow成功へ変えない。
- **metadata Core13部分・App15凍結**: 既存writer実装1fileを加えたCore13で、同writer同期callbackがactual suspended metadata dataTask.resumeの順序を本人意思/UUID/登録/latestqueryへ束縛する。1call内1actionと同ownerTask合流であり、永続SDK開始済証明ではない。Coreだけの不変DI-SOURCE-20261025-07（482入力、8bafc7e7…）で147は7suite59宣言167展開/skip0/診断0/377コード入力不変で成功。うち新2suite18宣言56展開。App15は26宣言73展開（通常68/実HTTP opt-in5）を定義して凍結し、compile/HTTP/通常UIは未実施。GETのliteral plusのpercentencodingと復元時latestquery exact joinを補強した。永続4文書は旧全文を保持した追加25行・91リンク欠落0・専門レビュー指摘0。現在の唯一書込みは本人操作UI1fileのposttap再取得/存在guardだけで、Core/App/文書は凍結中。
- **直接依存の再確認**: [strict native根拠](evidence/20261024-publication-operations/strict-native-readiness-20261025.json)の公式background redirect制限とVPN基礎回線/OS再試行のbyte前保証は、現正resumeの局所条件。別APIの不存在や全実装不可とはしない。[チャンクproducer次計画](evidence/20261024-publication-operations/chunk-producer-next-plan.json)の範囲算術/独立hash/bounded copy/typed source/実suspended取消・FD・lease終端は直接ready。Photos最終SDK開始はcapture tokenだけでなく同writer最終scopeと共有per-intent claimも必要で、旧cached原本不在許容を保持して次に接続する。LUT/ISO/Q01はこれらの枝を一律停止する理由ではない。

- **原本upload queued受付部分の結了 E-S28-UPLOAD-ACCEPT-01**: DI-SOURCE-20261025-06（477入力/4dd5e198…、code372/cd822c75…）の146 MAX全flowは1成功・厳格7種16監査/issue0/skip0/診断0、153実writer VERIFYは2親4子（accepted2/alreadyRequested1/fileMissing1）・現在要求2/独立再open/readers0/全保護hash-inode不変で成功した。通常141の機能全到達とstrict3指摘の失敗を保持し、2表示hunk修正後144は読み取りstage2/5監査だけの成功と明記する。全Unit136の789宣言740成功49skip/1307展開を、Unit/表示2hunk以外の製品一致と145 build/144・146で限定継承。通常修正後のfull method成功やglobal SDK0を主張しない。[main最終確認](evidence/20261024-publication-operations/original-upload-main-review-final-01.json)と[生証跡照合](evidence/20261024-publication-operations/original-upload-146-153-evidence-check.json)。実送信/strict/正式producer/全S28等は未完。
- **metadata予約/照合の実行151〜157**: DI-SOURCE-20261025-11（492入力/c3655a58…）で151関連13suite95宣言93成功/実HTTP2skip・208展開、152 generic iOSが診断0で成功。148のNetwork import不足・150のnested Testing macro compile失敗は実行0として保持。新規Seed/UI2だけを加えたDI12で154全Unit835宣言782成功53skip/1431展開（有意味1430）・失敗0、未使用UI変数warning1を検出し、assertionを変えずunderscoreへ置換してDI13/14へ分離した。DI14は494入力/0a90dd8f…、code389/56b2c680…、structure2リンク追補は専門review0/93リンク欠落0。157は新専用rootのSeedがsource絶対pathの/private/var別名guardでwriter/資格情報作成前に失敗、媒体・fixture未変更。元失敗を保持し、記録済み/var pathと実inode/hash照合を保つraw helper v3で初回作成を続行する。
- **metadata実HTTPと通常UI / in-progress**: 新規backend274/source-v2・使い捨て登録だけの155/156はnative1+4case/実POST1 GET2/全handler・DB owner・FD・thread終端を確認したが、mainの相対prepared引数による終了時input照合FileNotFoundErrorでlistener全体exit70を保持。旧rootを修復せず、新nonce/絶対引数の別rootで159/160を実行する。共有用証跡に秘密環境を転記しない。通常UIは新7AD/MAX52C端末・create-only exact2資格情報・閉鎖HTTPS origin専用で検証し、native global media SDK件数は未測定のまま分離する。本人操作149はDI08のMAX未消費remoteResume以降だけ継続中。
- **Photos最終SDK開始 / in-progress（唯一の製品書込みtask）**: worker manifest_projectionへ指定PhotoCoordinator/Native/ports/同writer/capture observer/製品factoryと関連testだけの所有を移管した。metadataまでの現物はDI14で不変copy済み、並行検証はコピーだけで実行する。writer→capture単回許可→共有操作claim→同期performChanges登録を接続し、heldの同intent/use待機、別coordinatorの重複SDK禁止、既存intent復元のunknownを保持する。標準資材/ISO/Q01は直接阻害条件ではない。既受理PhotoKitの取消handle欠如・全媒体停止/正式producerは別未完。独立validationは開始しない。
- **保全追補06（2026-10-25 04:00 JST）**: 旧1456file中1451byte一致、旧28state/17container/歴史5fixtureを保持。Keychain本体/WAL/SHMとPhotos WAL/SHMの5差分を分離。私有copy比較でKeychain28表中genp/sqlite_sequenceのみ相違、43行のまま同rowid3行のmdat/data/sha1相違と11旧rowid不在/11新rowidを確認した。Photosは100表中ZGLOBALKEYVALUE日時/counterだけでasset等99表は一致。05の狭い変更件数を現在へ継承しない。サービス・原因・製品範囲は不明、秘密値復号/原DB SQLite接続/修復/復元/旧process killなし。[保全06](evidence/20261024-publication-operations/protection-followup-06/summary.json)。

- **metadata実HTTP159/160・専用Seed161/158成功**: 同DI11のnative1宣言1実行＋1宣言4引数はskip/失敗/診断0、387入力前後一致。新nonce da0d98e9…の本物storage routerはPOST1/GET2・新登録1/receiving session1/chunks・evidence・jobs・assets・媒体byte0、redirect1/target0・oversize1・wrong MIME1・cancel到達1/実disconnectを観測。全handler・DB owner明示close・DB/media FD0・thread join・listener FD閉鎖を救済close前に確認、全入力hash不変・拒否0・秘密fileだけ削除、mainが元PID46917/session91237の実exit0を観測した。[実HTTP結合](evidence/20261024-publication-operations/http-metadata-002/main-review.json)。155/156の全体失敗70は保全。DI14ではsourceの記録済み/var pathをstrict resolveで実inodeへ照合するraw helper v3により、normal161/MAX158の初回create-only Seed各1/skip0/診断0/389入力一致が成功。157はsource guard前の失敗でwriter/資格情報未作成、fixture修復/reseedなし。各saved1/queued1/原本受付親子1/新current namespace2、秘密はhashだけ、通常UI162・最大163を別DerivedDataで確認中。synthetic登録/受付を実native Wi-Fi/サーバー登録/媒体SDK全数の証拠へ拡張しない。

- **metadata通常162/164・source限定継承**: DI14の通常全flow162は1成功/skip0/診断0/389入力一致、厳格7種27監査の前後activityが全対応・issue0。閉鎖HTTPS照会→local記録照合→pause/cancelと新準備拒否→再launchと同query照合を確認。164実writer VERIFYはquery1/observation0・本人2親2子/current cancelled/queued・attempt/session nil、実begin receipt、原本受付不変、全source/manifest/rootとfile inode/資格情報2item bundle hash/reader0/独立SQLite一致を確認。native HTTP全数/媒体SDK inventoryは未測定、capture wait行使なし。[継承照合](evidence/20261024-publication-operations/stages/upload-metadata-ui-candidate-03/execution-inheritance.json)はDI12全Unit154からApp/Unit/project全一致、差が新UIの未使用binding1箇所とstructure1行だけと証明し、現在compile診断0の161/158/162/164へ限定接続した。最大163は継続中。本人操作149はremoteResume/allPause/localCancelを消費済み、prefix5までの履歴一致・全件停止後waiting controlsでContrast1指摘を保持し、後続履歴/再起動と実writer照合は未完。
- **Photosの追加直接ready / REC preflight**: 新live claim/taskが揃ったため、既知PhotosのpreSDK cancel/wakeと受理済SDKの実completion→FD閉鎖→exact terminal/use releaseを共通REC preflightへ加算中。単純idle待ちはcapture-held taskと循環するため使わず、未知ownerやlocal終端不明をreadyにしない。外部Photos結果unknownでもlocal全終端が別に確定すれば録画待機解除を妨げない。本人民意の親batch取消へ変換せず、await中prepareと現RECowner/世代を確認する。ProductCaptureMediaBoundaryをCore所有へ、新ProductPhotoCaptureStopTestsをAppの新test専用所有へ追加。SDK/全媒体/実機/品質の完成ではなく、必要検証は未実行。

- **Photos最終SDK/既知owner REC停止部分の確認 E-S31-S49-PHOTO-FINAL-01**: DI-SOURCE-20261025-18（500入力/a3766d6e…、code395/d8c273ca…）。165は既存fixture actor初期化推論compile失敗/0実行を保持し、同値factory境界で修正、166の両store/実FD driftは7宣言30展開成功。167は関連109宣言105成功/2既存ProductBatch SIGBUS/Native2skip・200展開成功/warning1。ipsは42frames・Stack Guard内、fresh writer replayの大frameを非inline helperへ分割しguard/台帳形式/全assertを維持。169は当該2件を含む47宣言45成功/Native2skip・110展開成功、170は新専用F6E8の実PhotoKit1成功/skip0、171 generic iOS build成功、395入力前後一致/診断0。170はbaseline6全asset/resource/hash/日時保持、旧/stale/ABA/consumed入口の追加0と別新操作1件のactualcompletion、動画全bytes/date/video-audio各1track/source保持/ownFD-reader0/SQLite再open/再追加なしを確認。publicationは技術fixture入力、native Wi-Fi admission・正式producer・全SDK-global停止・実機REC/品質は証明しない。current ordinary positive Photos全UIは再実行せず、旧449 UIを実行版限定、現product Unit/Native boundaryとの範囲を分離する。[部分記録](evidence/20261024-publication-operations/stages/photo-final-candidate-02/README.md)。
- **main補強と文書同期**: PHOTO-CAPTURE-NIL-01（未登録UUIDnil/Photos0の初回RECまで拒否）をfresh noPhoto/noUnknownReaderの非破壊正例と3展開で修正。PHOTO-START-AFTER-01はSDK action実行後writerfalseを未開始扱いせずactualcallbackまでFD/useを保持する回帰で確認。RECのprepare await/held cancel/accepted SDK/外部unknownとlocalunknown/STOP-leave内部join・旧owner非再使用を実storeと制御callbackのUnitで確認。4docsは29行追補と時点依存9文言の限定訂正、doc_reviewer再確認0指摘/99リンク。全S31/S34/S49・全steering・実機・品質・PRD受入は未完、独立validationは開始しない。
- **保全追補07（20:32 UTC）**: 旧1456file中1448一致、旧28state/17container/歴史5fixture・原本/媒体は保持。Keychain3/Photos補助2にPhotos管理appPrivateData.plist3件のbyte差分を追加検出し、baseline内容copyがないためtimestampだけの変更とは断定しない。私有copyのKeychain genp43行は同rowid3行の暗号化列相違/13旧rowid不在・13新rowid、sequence1行のみ、Photos main100表はZGLOBALKEYVALUE日時/counter1行だけでassetを含む99表一致。旧06の11/11件数を現在へ継承しない。秘密値復号/原DB SQLite接続/修復/復元/旧process停止は0。[保全07](evidence/20261024-publication-operations/protection-followup-07/summary.json)。
- **本人操作149/168と次の書込所有**: MAX149は全残り操作3tap→6親10子・relaunch最終導線まで到達したが厳格11監査のwaiting paused sceneでUILabel Contrast1によりFAIL、diag0/358入力不変・全保護hash/inode/large復元。168のactual writer/reopen/全receipt/readers0照合は成功。issue通知にID/frameはなく、必要添付のnav背後blurは候補所見に留める。後続DI14以降に既存opaque nav指定があり、現行同scene再監査前は解消を主張しない。唯一の書込taskをControl UI1fileの読取phase/新rawhelperへ移管し、local cancelled＋waiting pausedを業務tap0で確認する。Photo製品codeは全凍結、metadataMAX163は旧DI14copyで継続中。続いて直接readyのbounded chunk producerへ進む。

- **S23/S28 bounded chunk producer / in-progress（唯一の製品書込みtask）**: PhotosはDI18、Control読取phaseはDI19（500入力/54f3dbe2…、395code/e99b46dd…）へ凍結し、通常172は1成功/診断0・MAX173はreadonly実行中。UnitAをworker original_upload_appの新Domain値/既存ManagedUploadSource/新test2の4file所有へ限定した。同一原本lease/FDから64KiB以内の範囲copyとchunk独立hash/readback、O_EXCL/unknown leaf保持、whole source mode分離を実装する。strict/default拒否の前に原本lease/source/SDKを作らず、実native正resume・正式producer・全媒体停止・chunk receipt永続採用/whole完了へ拡張しない。UnitAはDI20（503入力/5b57a099…、398code/63fb24db…）へfreezeし関連177をimmutable copyで実行中。UnitBのCore8file（同writer adapter追加）/App8fileを非重複所有で開始し、C(ownerClosed)<R(lease release)<S(stopped)<G(GET)<A(beginAttempt)<P(prepared)をactual prefixで照合する。metadataMAX163/176は成功・own keeper閉鎖済み、独立validationは開始しない。

- **metadata限定部分 E-S28-UPLOAD-METADATA-01 の確認**: DI14のMAX163は1成功/skip0/診断0・389code不変、実xcresult activitiesの27監査前後が全対応しissue0。176 actual writerはquery1/observation0、本人2親2子・current cancelled/queued・attempt/sessionなし、実query receipt/独立SQLite再open/原本受付・全reader0/保護file-inode/資格情報bundle hash一致で成功。通常162/164と同範囲で限定結了し、MAX全flowの6110.947秒成功を保持した。自分の閉鎖origin keeperは176後にsession23998の実exit0/FD閉鎖・PID不在を確認、listen/forward0。native HTTP全数/media SDK inventory/capture wait・strict正開始・正式producer・全S28は未完。[部分記録](evidence/20261024-publication-operations/stages/upload-metadata-ui-candidate-03/README.md)と[最大最終照合](evidence/20261024-publication-operations/upload-metadata-163-176-evidence-check.json)。155/156全体失敗・157 guard失敗と53skip等は保全、既存root修復/reseedなし。

- **本人通信操作の現在scene・実writer確認 E-S28-PERSON-CONTROL-01**: DI19/500の172通常・173最大は各strict7監査2回issue0、native全文13件一致、本人/metadata業務tap0・navigation2、enabled controlは44pt以上/hittableを確認。174/175 actual writerは6親10子/7記録3未処理・全reader0・再open・6保全fileとsource input hash/inode・字体large復元で成功。MAX149の11監査中Contrast1/FAILを保持し、現行2sceneから過去全flow成功や個別原因特定を主張しない。DI18→19は読取UI入口1fileのみ、残499入力一致。全SDK/global call inventoryは未測定。mainはphase/guard/diffとMAX添付を確認し、[部分記録](evidence/20261024-publication-operations/stages/request-control-render-candidate-01/README.md)へ限定結了した。
- **chunkローカルproducer177 / UnitA限定成功**: DI20/503入力の関連4suite32宣言69展開が全成功、skip/診断0・398code前後不変。新Domain9宣言30展開＋Storage10宣言22展開でoverflow/UTF8/Codable、全3位置/短末尾・両diskの同原本FD/64KiB、実partial write/EINTR/独立pread、await中差替・取消/duplicate・unknown leaf/reopen、caller lease保持とwhole/chunk分離を確認。技術合成bytes/検査注入を正式保存producerやSDK開始へ拡張しない。UnitB Core8/App8のtyped接続・全prior history最終guardを継続する。

- **chunk main補強 CHUNK-GET-ORDER-01 / 実装中**: 前attempt停止Sより前のGETがS後に観測commit Gされた場合をfreshとしない。Core共通before/reserved/current・同writer prefixにselected queryの実予約commit Q>Sを追加し、C<R<S<Q<G<A<Pの正例とQ<S<G遅延反例を両diskへ追加中。古いread-only契約は変更せず[main finding](evidence/20261024-publication-operations/chunk-get-order-main-finding.json)へ差分を記録。実行未確認。177b所有照合は欠落/範囲外0・過去evidence/HEAD/index一致、既知P2診断4行だけの差分を保持。通常/最大Controlとmetadata・Photoの新規自分所有idle端末はshutdown/data保持、旧CF等のprocess停止なし。

- **chunk停止照合と実SDK root保全の補強 / 実行未確認**: CHUNK-STOP-ATTEMPT-02により複数chunkの各taskへ別attemptのstopを借用しないexact joinを追加中。Core所有へBackgroundInvalidationPorts 1fileを明示追加し計9、App8とは非競合。CHUNK-NATIVE-ROOT-01は実SDK試験だけnonce/実Simulator ID付きcreateNew専用rootへ替え、成功/失敗どちらでもsource/原本/台帳を保持する。新D7DC端末は自分が作成・boot済み、Native実行は未着手。4docsのchunk追補19行＋既存2時点句だけの訂正はdoc_reviewer再確認0指摘/108リンク欠落0。旧P2指摘をreview01に保存し、strict/native/正式producer/実機未成立は保持する。

- **chunk接続DI21 / 関連178の結果**: 509入力/844ac0ec…、404code/c4ff832d…の全21差分（Core9/App8/Doc4、A4不変）をfreeze。178は22suite155宣言152成功1失敗2skip、展開438成功2失敗2skip・診断0/404入力不変。失敗はnew StoreTestsのremoval前提作成が両diskでnotCommittedとなった2caseだけで、他の時系列/borrow拒否・App/wire/旧BG・Photos回帰は成功。production拒否を弱めず所有をnewStoreTests1fileだけへ戻してfixture順序を訂正中。180generic iOS buildは診断0/404入力不変で成功。179は修正と無関係なDI21 immutable copy・新D7/nonce専用rootでactualsuspended→非resume→実cancel/terminal/自身FD/lease/stoppedを確認中。178失敗を保持し、全関連PASSへ書換えない。

- **chunk限定部分 E-S23-UPLOAD-CHUNK-01 の確認**: DI22/509（efa5779d…、404code/ae87476a…）はtest helper1fileだけ訂正しproduction不変。181両store全13宣言80展開成功/skip診断0、178の他関連成功は入力/依存限定で継承し元失敗2を保持。179は新D7/nonce専用rootでactual1成功/skip0、suspended bytes0→実cancelled→ownerClosed18（ownFD0/lease reader1）→実解放→stopped20（reader0）・原本/source保持/namespace閉鎖を確認し10file privatecopyも保全。180generic build成功/診断0をproduction全一致で継承。全run404入力不変。chunk HTTP送信/正native resume/whole verification/finalize・全S23/S49等は未完、最終統合全Unitは残る独立ready枝の後に実行する。[限定部分](evidence/20261024-publication-operations/stages/upload-chunk-candidate-02/README.md)。次の唯一の書込みtaskをdownload callback FD固定componentへ移管し、実responseとcontrol-plane read ticketを区別、prepared receiptをmedia permissionへ昇格せずfinalimportは別に検証する。

- **download FD-pin UnitA / in-progress（唯一の製品書込みtask）**: chunkをDI22 immutable copyへ退避しApp workerへ明示9fileを割当てた。latest因果順報告ではGET前DistributionReceiptはcontrol-plane発行ticketで、actualGET admitは別・新server BackendCommitReceiptは返らない。以前のCore0 mandatory grant案を採用せず、Aはuntrusted expected proposal＋actualprepared lookup＋同process knowncreationのresource対応でFDだけ固定する。callbackはO_NOFOLLOW/fstatのみ、同FDを64KiB有界処理・stop/join/実closeし、private temporary URL/数値FDをauthorityへ出さない。元fingerprintは緩めず、SDK unlink専用fact型を使う。responseの同writer観測/guardedverifiedimportと通常fullplanは後続へ残す。旧unknown採用/既存fixture操作/原本・Photos削除はしない。専門agentの実装のみ、必要検証・独立validationは未実行。

- **保全追補08（22:11 UTC）**: 旧1456file中1448一致/8差分、旧28state/17container/歴史5fixture・原本/媒体を保持。Keychain3fileとPhotos管理plist3は07とbyte完全一致し、Keychain genp3行暗号列/13旧不在13新・sequence1行の分析をsource family hash一致で限定継承。更新されたPhotos WAL/SHMは新しい私有copyだけで比較し、100表中ZGLOBALKEYVALUE1行のZ_OPT/ZDATEVALUEだけ、asset等99表/schema一致。原因・サービス・製品範囲・plist semantics不明を維持し、Keychain全保全成功へ拡張しない。原DB SQLite接続/修復/復元/旧process停止0。[保全08](evidence/20261024-publication-operations/protection-followup-08/summary.json)。

## 直前の引渡し（履歴: 2026-10-24、S34/S31/S49/S28の部分引渡し・全体未完了）

- **前回独立検証の引継ぎ**: `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-validation-20261023-ye694zwe/validation-summary.json` を読了。新規確定指摘0件、P2-STOPは今回の非実機範囲で合格。全Unit590宣言中561成功/29skip/失敗0（空templateを除く有意味913展開成功）、UI18種類/20実行成功、generic iOS build成功、compiler/analyzer診断とxcresult runtimeWarnings 0。前回のseed/原本digest/reader・repo不変の観測を継承し、未実装・未接続・実機/品質/PRD受入の完了へ拡張しない。
- **保全・所有**: 開始17,341fileのhash、既存dirty/untracked 9,347fileの現物copy、HEAD/status/unstaged/staged差分を `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-implementation-20261023-_coslmwo/` に保全。現物への限定加算だけを行い、既存P2修正・入力仕様・project設定・過去証跡を保持する。mainが本tasklistと新規 `evidence/20261023-cleanup-composition/`、構成確認・実行証跡・最終差分を所有する。
- **直接依存・S34部分引渡し**: S14/S16、S32の固定batch/実unlink/同writer最終再判定とS34-BG01の全transport inventory/確定終端を入力に、条件付きの通常複数容量整理を接続した。新規8宣言27展開、通常複数UI/再起動1・通常/最大文字の厳格AX各1、専用seed/実disk照合、generic iOS buildを確認。適格2本だけ実unlink、条件不足1本/保持1本/外部sentinelのhashとimmutable manifestを保持。正式証拠producer/Photos等を残しS34全体はblocked。全Unit回帰の下記既存Photos失敗を容量整理成功で置換しない。
- **S31競合修正の引渡し**: `cleanup-unit-final-09`の既存Photos1失敗は全証跡を保持。決定的barrierで別途確定した閉鎖FileHandle参照crashと、同exact回収の競合を修正した。関連36宣言86展開、全Unit604宣言中573成功/31skip・952展開（空templateを除く951）、実PhotoKit許可/拒否各2成功/各2skip、generic iOS署名なしbuildが成功し、292入力前後一致・compiler/analyzer診断/xcresult runtimeWarnings 0。元09の返値分岐を断定せず、旧8枝/新回帰/元結果・identifier/unknownコピー保持を維持した。全S31は正式producer/通常複数保存等の不足でblocked、実機は未実施。
- **S49部分引渡し**: 単回同期許可の契約・配線・競合試験を完了し、通常native resumeはnotExecutedを維持。全Unitの有意味963展開/31skip、非送信実SDK3、通常UI6種類（途中旧理由期待値1失敗は限定修正後成功）、UI後の両root照合、generic iOS buildを確認。最終395入力の版・途中失敗・原本保全は [S49証跡](evidence/20261023-capture-resume/README.md)。全S49は正の実SDK開始・全媒体実停止・実通信中RECのFinish不足でblocked。次の直接依存の独立部はS28の明示新登録として着手する。
- **S28の独立部**: 明示新登録/別namespaceと、現登録で旧保存原本identityを有界発見→同writer→remote専用通常一覧を接続。server002は新49＋既存230＝279case成功。端末34は36宣言75展開、35は実SDK新登録→namespace認証→32+1取得/reopen33件・媒体0/旧行・原本保全/全owner終端成功。metadata UI49/50は通常/最大各1・全12監査、51はVERIFY成功。入力UI58/59は最大/通常各1、60は旧Keychain2/空current/原本0のVERIFY、61は新第5空環境で既存初回/再照合UI2件が成功。途中失敗と必要表示/focus修正を保持し、最新414入力を [DI-SOURCE-20261023-02](evidence/20261023-remote-inventory/source-binding.json)（e74ef2a3…）へ束縛。最終全Unit62は638宣言602成功/36skip・1020展開（有意味1019）、通常/最大の旧一覧・再生停止63/64は各2成功、65/66の照合と67のgeneric iOS署名なしbuildが成功。必要13runの版/差分/継承範囲は [execution binding](evidence/20261023-remote-inventory/execution-binding.json)。全S28/通常HTTPS/正式manifest・通常媒体・全producer・実機の未完了は維持する。
- **共通検証・保全の結了**: 全67runの成功/途中失敗/0実行と版を保存。最終code309入力はUnit62/旧UI63/64/照合65/66/build67前後で一致、compiler/analyzer診断/xcresult runtimeWarnings0。新5環境の原本/外部sentinel/immutable manifest・登録/Keychain・全logical/media readerを用途別に照合し、データ保持で全5台shutdown。停止後content_size queryはunknownであり、停止前のlarge復元の実行証拠と分ける。既存Simulatorのstate変更0。全source414入力/生xcresult/開始dirty baselineを保持する。
- **完了判定の範囲**: 条件付き複数整理、Photos同exact回収競合、単回同期resume許可契約、明示新登録、remote原本metadata一覧の実装/必要非実機検証だけを部分引渡しする。全S28/S31/S34/S49・全steering・実機/品質/PRD受入は未完。既知原本の公開manifest→版ID付き投影等の資材不要な残実装も残し、標準変換資材/ISO本人判断/実機条件の不足をその直接依存外へ広げない。独立validationは別の明示Workflowとして未開始。

## 直前の引渡し（履歴: 2026-10-22、原本再生の停止位置P2修正・必要検証完了）

- **S16 / P2-STOP done（非実機範囲）**: 明示implementで独立validation `fr-validation-20261022-ikt29oug` のP2 1件と必要関連変更だけを修正した。**E-P2-STOP-20261022 / [証跡](evidence/20261022-playback-stop-layout/README.md)**。最大文字・全文を維持し、ScrollViewと停止/閉じるを上下の兄弟領域へ分離した。reader実解放後の停止完了契約と既存I/O/Modelは不変。初回失敗のdispatch瞬間・直接原因や停止内部の不具合は未確定のまま保持する。
- **操作・全文・AX**: 最終04では通常/AX5とも実秒数一桁→二桁の更新中に停止位置0pt、説明全文への通常scroll中も0pt。AX5の秒数自体は63.3/125.3ptの1行/2行を往復した。freshなframe/有効/到達、単一tap→停止開始または完了→stop/player不在、背景停止維持/再起動を検査した。初期playing監査を維持し、説明1箇所だけ既存Libraryと同じnative UILabelの実幅・無制限高計測/semantic footnote/全12sizeへ限定調整。監査mask/false handler/共通reveal・top以降は開始bytesと同一、受理/除外/文字制限なし。
- **構成・結果**: 実在のFrameRelay.xcodeproj/FrameRelay scheme/自動Test plan/Debug/有効Unit・UIと新規iPhone18Pro/iOS27 Simulatorを確認。Xcode27.0(27A266a)/Swift6.4 compiler・言語5.0/最低iOS27.0を維持。最終04のgeneric iOS署名なしbuild、Unit14宣言/17展開、通常UI3、最大UI2、UI後2成功/seed1skipは失敗0、compiler/analyzer診断とruntimeWarnings 0。UIは全てskip0。全Unit/全UIや実機の新規合格へ拡張しない。
- **原本・実行版・保全**: fresh seedは空の専用rootで2成功/verify1skip、既存rootのcopy/修復/再seedなし。UI後は同じbinding3件・immutable manifest bytes・原本485,721bytes/SHA-256・映像音声各30秒/音声1trackを保持し、単一store再openで全logical/media reader空を確認。物理container移動は観測として分離。最終389入力は開始からView/UIの2sourceだけ変更・387不変、必要6runは前後04 bytes一致。開始16,673fileの既存変更はこの2コードとtasklistだけ、新規は今回証跡のみ。通常stop contrast失敗、最大説明contrast失敗、無効な構造単独案と01〜03版を保持。canonical docs/requirements/design/project/guard/旧証跡は保全。
- **引渡し・残件**: 専用Simulator `664DEF26-9030-4889-9715-FED5B9E0D675` はlargeへ復元・データ保持でshutdown、既存Simulatorのstate変更0。前回の実文字AX/fresh fixture修正を保持し、他task・段階・全steering・Q01/A01〜18・実機/実撮影/実回線・品質・PRD受入の未完了は維持する。次は明示 `$validate-implementation .steering/20260929-device-independent-implementation/`。独立validationは暗黙に開始しない。

## 修正中の記録（履歴: 2026-10-22、原本再生の停止位置P2）

- **S16 / in-progress、P2-STOP**: 明示 `$implement-steering .steering/20260929-device-independent-implementation/` により、独立validation `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-validation-20261022-ikt29oug/` のP2 1件だけを修正する。AX5の秒数折返しで停止ボタンが約62pt移動した事実と、初回停止待機失敗・限定再試験成功を分けて保持する。初回失敗の直接原因や停止内部の不具合は未確定。
- **所有・保全**: mainは本tasklistと新規 `evidence/20261022-playback-stop-layout/`、workerは `FrameRelay/Features/Playback/OriginalPlaybackView.swift` と `FrameRelayUITests/Flows/LibraryFlowTests.swift` の2fileだけを所有する。既存16,673file/352,478,405bytes・未コミット差分と対象3fileを `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-playback-stop-20261022-yzlo6h2y/` に退避済み。既存変更の現物へ限定差分を追加し、旧証跡/原本/設定を保持する。
- **受入・必要検証**: 最大文字・全文表示を維持し、停止ボタンを下部固定領域へ配置して秒数更新から独立させる。reader実解放後だけ停止完了を表示する既存契約は維持する。実時間更新中のframe安定・タップ到達・停止遷移、関連Unit、build/診断、通常/AX5 UIとAX監査、UI後の原本identity/digest/全reader解放を確認する。未確認のままdoneにしない。
- **途中検証・関連調整**: 下部safeAreaInset案は通常/AX5とも秒数更新中のstop移動0pt・単一tap停止/背景/再起動に成功。追加playing監査で通常はstopのcontrast指摘1件を検出し、既存closeと同じprimary tintへ限定修正後に通常2case成功。AX5は5case中4成功/説明Textのcontrast1失敗。画像では説明が操作領域の境界で一部表示、AX領域は下へ続くことを照合した。初期playing監査を維持したまま、ScrollViewとfooterを外側VStackの兄弟へ分け、説明全文への通常scroll到達/stop固定位置も検査する関連修正を実施中。失敗・source01/02はrawへ保持し、SDK誤検知や既存停止処理の欠陥とは断定しない。
- **範囲の上限**: 前回解消した実文字AX/fresh fixtureを保持し、他task・全steering・実機/品質/PRD受入の未完了を維持する。独立validationは本修正後の別明示工程。

## 直前の引渡し（履歴: 2026-10-22、P2 2件の修正・必要再検証完了）

- **範囲・正本**: 明示 `$implement-steering .steering/20260929-device-independent-implementation/` により、独立検証 `/private/tmp/fr-validation-20261022-lh_5wn0r/validation-summary.json` のAX4失敗とfresh Library fixture作成失敗だけを修正した。結果は **E-P2-20261022-FIX / [今回証跡](evidence/20261022-p2-ax-fixture/README.md)**。以下の直前再開点・旧E行は当時の履歴として保持する。独立validationは未開始。
- **P2-FIXTURE / done**: test-only cleanupが非legacyの`.reserveRemoval`を使い、実検査unknownのMOVをcleanup入力にしていた不整合を修正。既存合成fixtureのsaved/検証/確認・非開始reader事実と`.reserveCleanup`へ整合し、製品guard・discard契約・実再生原本のunknownを維持。通常Unitに隔離tmp rootの作成/再open/投影/digest/全reader回帰を追加した。専用新規2環境の初回App root seedが各2成功/verify1skip。CFコピー・既存rootの修復/再seedなし。
- **P2-AX / done**: freshでも既知4件を再現した`ax-baseline-01`（4失敗/32issue）と無効なVStack比較を保持。実描画とAX文字領域の整合を、実提案幅・無制限高で計測する複数行UILabel本文へ限定修正。semantic body/headline・全12文字サイズ・全文・ID・combine・同じscroll/nav配置を保持した。native子ID伝播不足の途中4成功やUI取消を最終合格にしない。最終`ui-final-04`は17成功/0失敗/0skip、厳格6件（既知4件を含む）・unhandled issue0。監査mask/false handler/共通reveal・topは開始bytesと同一、ignore・受理・対象除外・文字サイズ制限なし。SDK誤検知/可視配色不良とは断定しない。
- **UI観測と最大文字**: `ui-final-02`の選択1失敗はON描画後もtap前と同hashのsnapshotを参照していたため、同IDのfresh親/実childを既存5秒内・両String1で照合する。最大文字の初回4失敗とfresh親比較1失敗も保持。部分可視の結合親がhit=falseでも同linkの可視titleはtrueであり、通常は従来親、必要時だけその実文字を通常tapして期待詳細identityまで検証する。最終最大AX5は全文7項目1件＋一覧/選択/詳細/履歴/再起動・実再生/停止/背景・実VO3件の**4成功/skip0**。17→53pt参照と実画像/AXの高さ伸長、全文、VO既存5条件を確認し、largeへ復元/再取得した。聴取品質評価にはしない。
- **構成・最終実行版**: Xcode27.0(27A266a)/Swift6.4 compiler、言語5.0/iOS27.0を維持。FrameRelay.xcodeproj/FrameRelay scheme/自動Test plan/Debug/有効Unit・UI targetと具体iPhone18Pro/iOS27 destinationを再確認。最終UI/最大文字/build/UI後照合は288入力が実行前後不変。全Unitは590宣言中562成功/28skip、915展開成功から空template1を除く**有意味914成功/失敗0**（通常新規回帰1＋明示VERIFY1を含む）。その後の差は非UnitのLibraryFlowTestsだけで、App/Unit実行バイナリhash一致。今回の389入力bindingは旧H01版から7変更/382不変、旧bindingは履歴として保持する。
- **前提別UI・UI後照合**: 旧18件と同じcase集合を、合成登録Libraryの17件と別新規未登録環境の初回接続1件で全成功（skip0）へ照合した。別環境では初回seed後のstrict4も成功。primaryの最終UI後は照合＋隔離回帰2成功/seed1skip、secondaryも全Unit内の照合成功。両rootのstable binding/digest/485721bytes・映像音声各30秒が一致し、logical readersとmediaReadersは全て空。物理container移動は観測として保持する。最終generic iOS署名なしbuild成功、compiler/analyzer診断とxcresult runtimeWarningsは0。
- **保全・差分**: 開始15,858file/340,070,485bytes、HEAD/status/diff/staged差分は `/private/tmp/fr-p2-implement-20261022-8hp33bnm/` に保全。今回の既存変更はView/seed Unit/UI testの3コード、4文書、tasklistの計8fileだけ、新規は今回証跡のみ。初期全file欠落0、CF保護15file・既存project/guard・過去証跡を維持。既存Simulator（独立検証の2台を含む）は変更せず、専用572096FA-13EC-4FAD-B14C-FE0DBF919FC0と070E0EC1-1A62-410E-BDD7-F0D80E500B6Cだけを使用し、データ保持でshutdown済み。前実装rawも保持する。
- **task判定・残件**: S14/S16は既存Done/Verifyに対するUnit・通常/最大UI・strict・build・UI後照合とmainレビューを結合し、非実機範囲をdoneへ更新する。S1V/他段階・S23/S27/S28/S34/S49の部分実装/blocked、S32/S33/S26A/M02〜M06/H01の既存done範囲は維持。H01は準備のみ。限定SDK・metadata HTTP・279入力の公開HTTP・登録metadata専用UIは今回再実行していない。permit/Mac注入を通常strict開始/resume/全媒体完成へ昇格せず、実機・品質・PRD受入/全D0・R部分証拠を維持する。
- **次工程**: 同じsteeringへの独立した `$validate-implementation .steering/20260929-device-independent-implementation/` を案内する。別Workflowは開始しない。

## 直前の再開点（履歴: 2026-10-22、独立validationのP2修正から直接依存の揃うtaskを継続）

- **明示入力・範囲**: 同steeringへの `$implement-steering` と「今回のP2を修正し、その後も直接依存が揃っているタスクを順に進める」を受領。S14のV-UIを再開し、必要な修正・関連検証と直接依存の揃う独立taskを順に実行した。別Workflowや独立validationは暗黙に開始しない。
- **保全**: 開始時の既存dirty/untrackedを含む8,910file/207,821,020bytesを `/private/tmp/fr-implement-20261021-j6xbqszu/baseline/` へcopy/hash保全し、HEAD/status/diffを保存した。S31/S48の既存成果へ加算し、旧証跡・repo rootの`README.md`・入力仕様・旧steering・project設定を保護する。
- **直前の独立検証**: `/private/tmp/fr-validation-20261021-k4a4q31t/validation-report.txt` はUnit有意味652成功/21skip、UI14成功/5監査失敗、iOS build成功。新Photos見出しを含む画面外AXと説明文/履歴のDynamic Type等がP2として未解決。可視文字の配色不良やSDK誤検知とは断定しない。245入力とS31実Photosの保存証跡は一致、コード/docs/steering変更なし。
- **所有**: mainがsteering・証跡・最終差分を統合した。全App/Tests/project/support helper・永続文書は最終版を凍結して所有解除。コードの実行版は288入力、docs等を含む引渡し版はH01-SOURCE-01の389入力。旧証拠・既存dirty/untracked・入力仕様・project設定を保護した。
- **今回の結果**: S32/S33とS26A、M02〜M06同期、H01引渡し準備はdone。S23/S27/S28/S34/S49は必要検証付きの部分引渡し、全taskはstrict通信/資材/全媒体/製品操作等の不足をblockedに保持。S2V/S4Vも部分集約済みblocked。独立してreadyな追加コードはなく、P2/S14の厳格監査4失敗とS16/S1Vは未達。次は同pathの明示 $validate-implementation、実機はcase別Q01束縛から進める。
- **P2最終部分証拠**: 子identifier除去の09は2件とも失敗し効果がなかったため全identifierを復元。最終の自然高SwiftUI版で実文字/VoiceOverの追加2件は通常largeと最大AX5で各2件成功、全文・伸長・実読み上げを確認した。監査条件は変更していない。`p2-library-05` の6成功/4失敗は途中Geometry版の観測であり、最終版の全監査合格とは扱わない。その後の最終画面の厳格監査s34-regression-10は14成功/4失敗。LibraryViewは以後S28/S34-BG01でも同hashを保持し、現288入力でstrict全件再実行したとは扱わない。`p2-post-verify-12` は既存seed検証1成功/seed実行1skip、同一digest/reader0、253入力変化0。証跡は同P2ディレクトリ。
- **P2部分改善と未達**: 純SwiftUIのScrollView/自然高cardへ限定変更したcandidate01で説明Dynamic Type-onlyと通常操作/実再生/停止/背景/再起動/VoiceOver/停止player監査を確認。`p2-library-05` はLibrary10件中6成功/4失敗、skip/runtime/compiler/analyzer診断0、実行中245入力変更0。旧「撮影する」のcontrast/clippedとfresh履歴のDT7件は消えたが、履歴clipped・handoff DT・詳細画面外contrastは残る。GeometryReader/containerRelativeFrameは無効、native containmentでAX viewportを(0,116,402,724)へ制約しても完全画面外の文字が監査対象になり解消せず、追加構造は撤去した。candidate07個別fixedSizeの`p2-text-08`も2件失敗で撤去済み。監査全issueを失敗として保持しP2全体解消とはしない。失敗版/compile0件/実行版/スクリーンショットは `evidence/20261021-library-accessibility/` と開始rootに保全する。
- **S32の開始判断**: S12の原本保存/復旧、S13の内容対応/実FD/lease/ordering部分、S21の同writer削除guardは引渡し済み。S13全体/S23の旧OS reader復旧は未達だが、unknown readerを解放せず削除拒否する独立実装を開始できる。固定集合と子intentの永続化→全使用者実終端→直前再判定/予約→実unlink→結果commit、起動照合は観測だけで未実行削除を再実行しない。実データは対象外、合成fixtureで確認する。

## 直前の再開点（履歴: 2026-10-21、S31のPhotos終端・使用権と失効接続を検証完了）

- **S31 / blocked（今回の終端・使用権残件は解消、通常producer/複数保存は未接続）**: 結果とは別にSDK非開始/実終端とFD閉鎖の証拠を同writerへ保存し、exactな元photo useだけを解放する。unknown/failed/notAttemptedの結果・identifier・コピーを保持したまま、scope全解放→失効tombstone/ACKへ接続した。旧unknown/意図のみ・finish失敗・別intent応答から終了を推定せず、旧成功限定回収を維持する。
- **直前検証の確認**: 独立検証 `fr-validation-20261020-6rjehf5d/validation-report.txt` はS31着手前のS48/M04/S41版を対象に新規指摘なし、S41既知2件解消、全体未完。その後のS31実装E-S31-01も確認した。今回のmain確認は独立validationの代行ではない。
- **E-S31-02**: 空DerivedDataの全Unit440宣言/653展開ケース成功・既存/opt-in21skip、通常撮影/写真権限UI4成功。新規境界2suiteは11宣言/35展開成功。実NativePhotoLibraryは許可/拒否各2件成功・各2skip、generic iOS署名なしbuild成功。4runと現物245入力は全一致、runtime/compiler/analyzer診断0。Unitの既存空example1件を除く有意味な実行は652、skipは成功に含めない。
- **保全・証跡**: 開始8480file/196,657,895bytesと証跡外417fileのcopy・HEAD/status/diffをrepo外 `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-di-resume-20261021-xxox35mt/` へ保全。既存変更へ加算し、旧証跡/既存Render/project/Composition/README/入力仕様/旧steeringは変更しない。限定永続3文書を同期しdoc_reviewer指摘なし。新規専用Simulatorだけを試験後shutdown。保存証跡は `evidence/20261021-s31-terminal/`、raw xcresult/DerivedDataは同repo外rootに保持する。
- **残件・再開条件**: 正式Rec.709供給とS23/S27、通常保存coordinator/固定複数集合の製品接続を進める。新終端証拠なしの旧使用権は保守的保持し、unknown/失敗コピーの自動回収・保持期限/容量policyや旧extensionless媒体のPhotos再利用は未実装。初回OS許諾/限定アクセス/本人写真削除後/実機品質はDV-16。S47 ISO、S48標準資材、他task/全steering/PRD受入は未完。次の独立検証は同pathの明示 `$validate-implementation` とする。

## 直前の再開点（履歴: 2026-10-20、S31独立下位処理・関連検証完了、製品接続は保留）

- **S31 / blocked**: Photos共有契約、同writerの登録意図/結果/存在観測、実PhotoKit adapter、S25完全媒体/使用権、成功commit後の限定回収、Libraryの理由付き明示照合を実装した。通常の新規写真保存開始・正式Rec.709媒体producer・複数取得操作は未接続であり、利用可能に見せない。
- **E-S31-01**: 最終Unit429宣言/618展開ケース成功・既存/opt-in20skip、実Photos許可/拒否各1成功、通常Library/撮影UI4成功、generic iOS署名なしbuild成功。最終5runと現物の243入力は一致、各run前後の変更0、runtime/compiler/analyzer診断0。初回compile失敗2版、Photos拒否2版、同bytes適合probeも保持した。
- **保全・文書**: 開始8119fileのうち変更は許可済み20file、新規source/test16file、削除/旧証跡/既存Render変更0。Photos関連の永続3文書を部分同期し、doc_reviewerのD7指摘を修正後、追加命名境界も指摘なし。証跡は `evidence/20261020-s31/`、raw xcresult/DerivedData/全開始copyは `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-di-s31-20261020-00r0892r/` に保持。新規専用Simulatorだけを試験後shutdownした。
- **残件・再開条件**: S23/S27と正式Rec.709供給、通常保存coordinator/固定複数集合の製品接続が必要。unknown/失敗の一時本体・使用権回収と失効/全reader解放への接続、旧extensionless媒体のPhotos再利用も未実装。期限/容量policyや無断移行は追加していない。初回OS許諾・限定選択・本人の写真側削除後・実機品質はDV-16。S47 ISO、S48資材、他task/全steering/PRD受入は未完のまま。独立validationは未開始。

## 直前の再開点（履歴: 2026-10-20、S31 Photos登録・結果照合に着手）

- **S31 / in-progress**: 明示implementにより、既存S25の完全媒体・使用権とS21の同一writerを再利用してPhotos登録を先行する。共有契約/永続化→SDK下位処理→媒体接続→権限理由UIを所有別に引き渡す。標準Rec.709製品媒体の未成立を技術fixtureで補わず、Finish不足は局所保留する。
- **既存変更の保護方針**: S48/M04のdirty/untrackedを現状のまま保全し、加算変更だけを行う。開始8119file/186,781,360bytesをhash照合し、証跡外398fileのcopy・git status/diff/HEADを `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-di-s31-20261020-00r0892r/` へ保存。reset/revert/stashを使わず、旧証跡・既存Render・repository-structureは凍結する。
- **残件の分離**: S47のISO本人判断、S48の標準資材、S23/S27の未完はその直接依存へ保持し、S31下位処理の追加依存にしない。独立validationは開始しない。

## 直前の再開点（履歴: 2026-10-20、S48独立描画基盤の関連検証・M04文書同期完了）

- **S48 / blocked（適合標準資材・実Log変換・通常capture/UI接続待ち）**: 描画専用の3sourceと実画素/競合試験を追加した。空の標準catalogはLog1/2を個別に拒否し、生成cubeによるencoded BGRA技術描画だけを扱う。CGImage出力・原本入力の読取専用契約・1処理中＋1置換待機・世代/連番/停止後の旧結果拒否までを先行し、標準Rec.709完成とはしない。
- **E-S48-01**: 新規DerivedDataのs48-test-02はUnit19宣言/24展開ケース（新規7/10）＋通常撮影UI1件が成功、失敗/skip/runtimeWarnings/compiler/analyzer診断0。Simulator test buildとs48-ios-build-01のgeneric iOS署名なしbuildが成功、224入力が各実行前後・最終版で一致。初回s48-test-01の新規test macro compile失敗/0件と5警告も保持した。stdoutの既存AppIntents metadata警告はコンパイラ診断と区別する。
- **S48の保全・main確認**: 開始git clean、証跡外240fileをhash付きでrepo外rootへ保全。S48時点の既存変更は本tasklistとarchitectureの表示境界だけ、新規App/testは所有4fileだけ。mainが全diff・原本へ戻すAPIの不在・未接続・版一致を確認し、doc_reviewerは限定文書差分に指摘なし。証跡は `evidence/20261020-s48/`、raw xcresult/DerivedData/開始時copyは `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-di-20261020-wa275djf/` に保持する。
- **M04 / done**: S48の証跡固定後、同じimplement内でrepository-structureだけを同期した。実在配置・製品接続/未接続・単一writer/原本/Ports/Composition所有・test媒体・履歴責務を更新。main指摘の設計例外化を戻し、doc_reviewerの一時媒体/原本unlinkの曖昧さを修正して最終指摘なし。15ローカルリンク切れ0、実在path/表構造/所有を確認、224ソース入力はS48検証版のまま。文書のみのためbuild/testは再実行せず、証跡は `evidence/20261020-m04/` に保存する。
- **残件・再開条件**: S48本体には対象Logごとの標準資材実体・由来/版/hash・利用条件・数値域/入力適合を確認し、実Log変換と既存capture/UIの接続・検証が必要。入力不変はproducer契約、stopは描画SDK完了/資源解放の証拠ではない。実原本の非焼込み/録画両立/画質はDV-05へ残す。S47は前回ISO案を今回も確認したが未回答のため通常policy=nilを維持。他task・全steering/PRD受入・独立validationは未完了のまま。

## 直前の再開点（履歴: 2026-10-18、独立validation指摘2件の修正完了）

- **S41 / done（validation差戻し2件の修正・必要検証完了）**: 同steeringへの明示implementにより、直前のP1テストcompile再現失敗とP2保存後ハッシュ/一覧更新による次REC抑止を修正した。全体の未完了taskやS47の未回答ISO方針は保持する。今回のmain確認は独立validationの代行ではない。
- **直前の独立validation**: App Simulator buildは成功。別々の空DerivedDataで通常Unit/撮影UI testを2回実行し、`ProductCaptureCoordinatorTests.swift` の3actor隔離診断で両方exit65/0件実行。保存結果commit後も全量digestと一覧更新を`isSaving`へ含める経路がarchitectureの次REC条件に違反。元ログ・xcresultは `/private/tmp/fr-validation-20261018-zzhjxcwh/` に保持する。
- **保全・所有**: 開始時7981file/180454194bytesを全hash付きで `/private/tmp/fr-validation-fixes-20261018-bu8tvcdc/baseline/` へcopy済み。既存dirty/untrackedへ限定変更し、reset/revert/stashは使わない。mainはtasklist/新規証跡/実行検証/最終差分、`compile_investigation` と `postsave_design` はread-only調査。コードworkerの所有は調査後に確定し、P1→P2の順に同一ファイルの所有を直列で引き渡す。
- **完了条件**: 標準Xcode設定・新規DerivedDataから必要testが実行でき、保存の安全終端後は内容対応/一覧更新だけで次RECを抑止せず、後処理中の次録画・離脱・失敗が新クリップを壊さないこと。未binding原本の転送/整理禁止、原本保全・復旧を維持する。実機性能や全steering受入へ昇格しない。
- **P1所有確定**: worker `validation_fixes` が `FrameRelayTests/Application/ProductCaptureCoordinatorTests.swift` の3actor準拠宣言だけを単独所有する。actor状態/await/試験意味を保持し、既存の本番実装と同じextension準拠へ移す最小案を検証する。project/言語/Portsは変更しない。P2コードはP1引渡し・検証後に所有を追加する。
- **P1検証 / 完了**: 3actorの準拠だけを空extensionへ移した。mainはbaselineとの差分6箇所・本体不変を確認し、新規DerivedDataの`p1-test-01`でCoordinator 21宣言/21実行成功、skip/失敗/compiler・analyzer診断0。標準Debug/Swift5/iOS27.0を維持、220入力の実行中変更0。Xcode27.0/Swift6.4、実在scheme/test plan/3targetと当日のiPhone18 Pro Simulatorを確認して実行。過去2回のcompile失敗は保持し、最終P2回帰でも新規DerivedDataから共有helperを再確認する。
- **P2所有・判断 / 着手**: 同workerへProductCaptureCoordinatorと新規後処理owner、ManagedOriginalStoreと必要なdigest helper、LibrarySnapshot/LibraryModel、各対応Unit/Storage試験だけを単独引渡し。保存commit応答までは安全境界を保持し、以後は原本固定queueの単一Taskでbind→一覧更新を所有する。hashは専用actorへ渡して予約actorの全量読取占有を除き、同FD/64KiB/前後stat/取消検査を維持する。後処理は現在クリップを変更せず、未bindingは原本軸の要照合・操作不可として表示する。追加refreshを取りこぼさない。既存schemaとread-only復旧を維持し、再起動後の自動bind/新規再試行UIは追加しない。
- **関連所有追加**: `ProductCaptureAudioCoordinatorTests.swift` の保存待ち/音声retryを検証する1testだけ同workerへ追加。実保存待ち中のretry拒否は保持し、commit後の一覧更新待ちを音声復旧条件から外す新境界に合わせる。永続文書2件は`postsave_docs`が所有し、`postsave_docs_review`は今回diffに指摘なし。steering designはmainが同じ境界を反映した。
- **P2部分検証**: mainの新規DerivedData `p2-targeted-01` は関連10suite/72宣言・102展開成功、失敗/skip/compiler・analyzer診断0、223入力不変。実FD/hash処理中の別原本予約、取消/改変時の同FD終端解放、未binding実Movieの再openと操作拒否、保存境界/後処理遅延/次clip/離脱/失敗/重複通知、一覧refresh取りこぼしを検証した。
- **E-S41-VFIX-01 / 最終検証**: 別の新規DerivedData `final-test-01` は全Unit374宣言/510展開成功、既存17skip、通常撮影UI3件成功、失敗/runtimeWarnings/compiler・analyzer診断0。skipは外部HTTP/probe・fixture生成・製品Libraryの明示seed実行用であり、成功に含めない。`final-ios-build-01` は確認済みgeneric iOS destination・署名なしでbuild成功。test/実機向けbuild/現物の223入力は一致。stdoutの既存AppIntents metadata警告は保持し、実機起動/品質/速度の成功としない。
- **E-S41-VFIX-01 / main差分確認**: baselineに対し既存12file変更、新3source/testを追加。内訳はApp/test11file、永続docs2file、steering design/tasklist。project/README/memo/要求/旧steering/旧証跡を含む所有外変更・欠落0、diff-check成功。証跡は `evidence/20261018-validation-fixes/`、raw xcresultと全開始時copyはrepo外rootに保持する。過去validationの失敗ログも同証跡へ保全した。
- **残件・次工程**: 原本保存前の安全検査を省略せず、内容対応未完了の転送/整理/再生を拒否する。アプリ終了で未bindingが残った場合の自動再bind/新規再試行UIは未実装であり、保存結果と実原本を保持して一覧の要照合へ復元する。実機次REC性能/DV、S47のISO方針、他task/全steering受入の既知残件を保持する。独立再検証は同pathの明示 `$validate-implementation` へ引き渡す。

## 直前のS47実装記録（2026-10-18、独立部分実装・必要検証完了、ISO本人判断待ち）

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

- [x] Status: done
  - E-P2-20261022-FIX（2026-10-22）: 既存Done/VerifyをProjection13/Model15/StoreReader17 Unit、通常Library12件を含むUI17＋前提別初回1、strict6、最大字4、再起動・実VO・UI後全reader/identity照合へ対応付け、非実機範囲done。未接続操作の理由表示を製品処理の成功にせず、他taskの製品複数操作・実機・受入は維持。
  - 以下は修正前の履歴。当時の失敗・blocked/部分引渡しを保持し、現在の判定は上記証跡を参照する。
  - 最終比較・保全（2026-10-22）: `p2-lazy-13` は2件とも失敗（contrast2指摘残存、従来成功の説明DT-onlyも15指摘）。native Sectionのstatus独立lazy childは不採用とし、S34最終Viewのexact bytesへ復元。260入力全一致を確認し所有解除した。復元版の最大AX5 `s34-actual-ax5-11` は実文字/VoiceOver2件成功、`p2-final-cf-verify-14` は旧seed照合1成功/seed1skip・内容同一/reader0。文字large/67bytes設定hashを開始時へ復元し、runtime/compiler/analyzer診断0。厳格監査4失敗を別検証の成功で置き換えず、全失敗/候補13/復元証拠をP2ディレクトリへ保全。次は既述S23独立部を進める。
  - 最終限定比較（2026-10-22）: S34統合版のCF18件は14成功/厳格監査4失敗。Appleのlazy subview説明と現物の保持単位を照合し、未試行の「詳細statusをLazyVStack直下の独立childへ分解」をView1fileだけで比較する。全Text/semantic font/順序/ID/combine/監査条件を保持し、contrast-onlyの上下位置と説明DT-onlyを1回実行する。改善がなければS34最終Viewへ戻しblockedとしてS23独立部へ進む。wrapperが原因と確定せず、監査の無視・AX隠蔽は行わない。
  - 限定再開の結果（2026-10-21）: identifier A/Bは無効で復元済み。最終App/UIの253入力を凍結した実文字サイズ/VoiceOver追加2件はlargeと最大AX5で各2件成功、runtime/compiler/analyzer診断0。history/removalとhandoff結果の全文、文字高さの伸長、実読み上げ5条件を確認した。これを既存の厳格監査成功へ代用せず、P2の監査残件を保持する。既存seedのpost verifyは1成功/1skip、全reader0/内容同一。新証跡 `evidence/20261021-library-accessibility/`、S34後に変更画面の全Library監査を再実行する。
  - 限定再開（2026-10-21、S32完了後）: 親combine/identifier・全Text/semantic font・全文読み上げを保ち、item/submissionの非対話子identifierだけを除去するA/Bを試す。識別子が原因との公式保証はなく、独立headerや監査条件を変更せず実結果で判定する。所有は元のView/UI test2file、core/Ports/Compositionは凍結。
  - 部分修正・局所保留（2026-10-21）: 上記P2検証の純SwiftUI版を部分引渡し。説明DTと複数既存監査は改善したが、履歴clipped/DT・画面外contrastを含む必須V-UIは未達。全issueを失敗として保持、独立S32を継続する。最終関連回帰/seed/settings保全は同実装内で追跡する。
  - 再開（2026-10-21、独立validation P2）: mainが開始版を保全し、`library_ui_fix`へ上記View/UI testの2fileだけを引き渡す。既知S14/S16残件と今回S31追加UIの監査5caseを原因切分けし、表示/AX/文字サイズの必要修正と関連操作・再起動・reader解放を検証する。必要検証が失敗/未実行の間はdoneにしない。
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

- [x] Status: done
  - E-P2-STOP-20261022（2026-10-22）: 上記「現在の引渡し」と今回READMEの受入・Verifyを完了。下部操作と本文領域の分離/説明の全文AX計測、実更新/scroll中0pt・単一tap停止遷移、既存解放契約、関連17 Unit・通常3/最大2 UI/AX・UI後全identity/digest/reader・build/診断とmain差分/保全を結合し、非実機範囲doneへ戻す。他task・全steering・実機受入は未完。
  - 以下の再開記録は修正中の履歴。現行の判定はE-P2-STOP-20261022を参照する。
  - 再開 P2-STOP（2026-10-22）: 上記「現在の作業」の独立指摘1件と必要関連変更だけを対象とする。旧E-P2-20261022-FIXは実文字AX/fresh fixture解消の履歴として保持し、今回の停止位置・tap/停止遷移・UI後照合とmain差分確認後に非実機範囲を再判定する。
  - E-P2-20261022-FIX（2026-10-22）: Composition7/OriginalPlayback9/CaptureSavePlayback1 Unit、製品入口→一覧/実再生/停止/背景/再起動、通常/最大UI・strict6とbuild/診断0、UI後stable identity/digest/全reader空を結合し既存Done/Verifyの非実機範囲done。探索ticket・Simulator拒否と通常Libraryを分離し、fixtureはtest targetのみ。S1Vや実機/品質/PRD受入は昇格しない。
  - 以下は修正前の履歴。当時の失敗・blocked/部分引渡しを保持し、現在の判定は上記証跡を参照する。
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

- [ ] Status: blocked
  - 今回の直接依存部分（2026-10-25）: 通常単数/固定全件の本人通信操作は同writerの不変親子planへ接続済み。MAX149は全残操作後のrelaunchまで到達したがstrict Contrast1でFAILを保持し、DI19の現行同scene読取172/173は通常・最大各1成功、actual writer174/175は各6親10子・全reader0・保護file/reopen一致。upload metadataのquery予約/実begin receipt/取得結果atomic観測はDI11/14で関連/全Unit/実HTTP159・160を確認し、通常/最大UI162・163とactual writer164・176が各成功。いずれもstrict送信許可・正のmedia SDK resume・全媒体停止の完成ではない。後続chunk producerは最新GETの実観測と1chunk/attemptを前提にUnitAの値/実FD範囲copyを4fileで実装中、UnitBはCore8/App8の非重複所有で、実stopped履歴と最新GETの時系列を同writerへ接続中。strict拒否時のattempt/lease/copy/SDKfactory0を維持する。最新証跡は `evidence/20261024-publication-operations/`。
  - E-S23-01 / 独立部分引渡し（2026-10-22）: A/B/Cの所有21file（既存6＋新15）をmainが全文・S34最終版からの差分で確認。同schema7 writerへ固定context/OS session世代/task/実終端/owner閉鎖を保存し、exact mutation lookup・旧登録終端・create/attach gap・numeric ID/description再利用拒否を接続した。管理upload copyは実原本leaseから64KiB単位で読み、全量hash＋出力FD全読戻し、実writer closeと保持read FDのexact terminal後closeを確認する。再openで旧sourceを採用せず、task一覧の不在・cancel受付・finishEventsからremote非実行/全reader解放を作らない。
  - E-S23-01 / 実行結果: Xcode27/Debug/同scheme・test plan・Swift5/iOS27の凍結275入力で、`s23-unit-02` は509宣言/816展開成功・25skip（空example1を除く有意味815）、新S23の通常39宣言/90展開成功。`s23-sdk-01` は実背景URLSessionの2宣言/2ケース成功（空session列挙→実invalidation、upload/download各1を一度もresumeせずsuspended列挙→cancel→実completion→実invalidation、source実close）。SDK専用flagはtestのみ。`s23-ui-01` 通常撮影/接続/一覧・履歴再起動3件成功、`s23-cf-verify-01` 旧seed照合1成功/seed実行1skip、既存MOV digest/reader0と67bytes設定hashを保全。generic unsigned iOS `s23-ios-build-02` 成功。5runと現物275入力全一致、実行中変更0、runtime/compiler/analyzer診断0。初回成功時の未使用capture/冗長require警告3件は2file/3行だけ修正し、初回候補・結果も保持した。
  - E-S23-01 / 残件・次工程: 通常strict admissionはattempt/lease/copy/SDK factoryより前で拒否し、SDK resume自体もnotExecutedを維持。VPN基礎回線と背景redirectの送信前保証、downloadの安全な永続ingress、再起動後の旧source/lease所有採用、全媒体の製品dispatch/S49、実OS lock/kill/relaunch（DV-12）は未成立。OS配送handler完了を全owner解放やremote成功へ昇格しない。全S23はblocked、S24I等の正の通信依存へ進めず、Start依存が独立するS49の同期admission/REC・保存境界から先行する。証跡 `evidence/20261022-background-media/`、raw xcresult/DerivedDataは開始repo外root、main最終確認 `s23-main-final-review-03.json`。P2厳格監査4失敗のViewは不変・blockedを保持する。
  - 独立部分へ着手（2026-10-22）: S13の内容対応/実FD・lease、S21同writer、S22C登録commit、S20隔離境界を部分引渡し。通常strict admissionは未成立のまま閉じ、attempt/source copy/lease/SDK task factory前で拒否する。OS session/task対応・管理upload source所有・実SDK終端・復帰イベントのdisk/resource drainを先行し、Wi-Fi/VPN基礎回線/背景redirectの保証不足を実機待ちだけへ置換しない。
  - 所有・実装順: A `original_removal_core` は新BackgroundMediaTask/BackgroundMediaPorts/BackgroundMediaStoreProjectionと既存BackendCommit/MediaOperationStorePort/MediaOperationStoreAdapter/MediaStoredValueValidation、専用Domain/Storage testsだけを所有。先にimmutable APIを引渡し、B SDK/fileとC coordinator/recovery/背景handlerを同task内の別fileへ割当てる。mainが統合後の凍結sourceで実SDK非送信試験/両store故障・再open/通常UI/unsigned iOS buildを実行する。原本/削除/Photos既存差分と過去証跡を戻さない。
  - B所有束縛: worker `background_sdk` は新規 `Platform/Network/BackgroundMediaSession.swift`、`Platform/TemporaryMedia/ManagedUploadSource.swift` と専用 `FrameRelayTests/Integration/{Remote/BackgroundMediaSessionTests,Storage/ManagedUploadSourceTests}.swift` だけを所有。AのAPI確定まで独立した実FD/copy・SDK境界から進め、共有Domain/Ports/storeは変更しない。通常resumeは接続せず、実SDK試験は一意identifierの空session/一度もresumeしないsuspended taskの列挙・取消・実completion/invalidationだけをmainが明示実行する。
  - C所有束縛: AのDomain/Ports APIを受領し、`library_ui_fix`へ新規BackgroundMediaCoordinator/BackgroundMediaRecovery/ProductBackgroundMediaFactory/ProductBackgroundEventRouter、既存FrameRelayApp/ProductCompositionの最小背景接続と専用Composition/EventDrain testsを単独割当てる。A共有file/B SDK/file/View/削除coreは凍結。唯一stream consumerがstore準備・exact終端commit・自身のresource処理をdrainしてからMainActorのOS handlerを一度だけ呼び、handler呼出しを全owner解放へ昇格しない。download ingress保持は未対応を明示し、TemporaryMedia成功を作らない。
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

- [x] Status: done
  - E-S26A-01（2026-10-22）: designへLog1=BT.2020 primaries／Log2=Apple Gamutの区別、SDK識別とYCbCr matrixの限界、各別Apple製Rec.709 LUTの公式記述、実体/由来/版/hash/利用条件/数値域/既知入力・期待出力の未取得を記録した。取得経路の不存在/一律認証必須は断定せず、生成identity/swapや検出規則v2を標準資材/Log2 LUTへ昇格しない。技術適合と同一標準参照を使うG3色/圧縮比較案、Q01未合意値とG5採用を分離した。main全差分・一次資料対応・ローカルリンク切れ0を確認し、資料/前後design/hashを `evidence/20261022-transform-research/` に保全。資材取得/認証/変換/品質試験は未実施、S26/S48の当該資材待ちは維持する。
  - 着手（2026-10-22）: 読取担当の公開一次資料再確認を受領し、mainがdesignのLog1/2別資材・入力条件・未取得箇所と技術適合/G3比較案を記録する。資材download・認証・変換・品質試験は行わない。S26/S48の資材待ちは維持する。
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
  - 部分引渡し E-S27-01（2026-10-22）: 保護namespaceは正規化componentとroot/ASCII大小文字aliasをwriter/publish両側/removeで拒否し、全旧入口gateを保持した。旧137node160case＋publication全33node70caseの明示170node230caseを新snapshot273fileで実行。`s27-backend-pytest-02` は全230成功・failure/error/skip0、guard拒否/SQLite残存/close失敗/所有thread違反0、全22設定・外部source246/依存1657/.pth/interpreter/実行source不変。初回001の定数export削除による173成功/57失敗（同じAttributeError）も保持し、既存SEALED_PREFIXを戻した新002で再検証した。
  - E-S27-01 / 実HTTP: 新HTTP002は1宣言1実行成功・skip/runtime/compiler/analyzer診断0、30request/4control。319,116/969,998byteの時点で実AVPlayer進行/decoded frameを確認し、本人確認commit→応答置換503→exact lookup→全scope実終端→失効commit/ACK→V2公開、消費済/旧版GETのmedia0byte拒否を通した。SDK実開始/完了8/8、cache0、ACK1。raw xcresultのPassedと実SDK添付のtest/device/値を親が再計算した。guard救済前のpending/GC未close/tracked接続/DB媒体FD/不明regular FD/残存thread0、全生成threadjoin・親のchild実exit0/0・signal0・秘密env削除を確認。HTTP001の接続前失敗はfixture metadata.sizeのJSON数値がstrict parserに拒否されたためで、test-only文字列表現だけを修正し製品parserを維持した。
  - E-S27-01 / main確認・版: backend6file/HTTP5fileだけの差分と追加互換定数・metadata修正を全確認。旧SQL001〜003/登録26試験/guard/lifecycle/run_pytestは不変。全App/Unit/UI/project279入力はS49最終版のまま、HTTP前後も変更0のため既存Unit841展開/iOS build証拠を層別継承する。現backend273はpytest002と同一、現HTTP9はHTTP002と一致。証跡 `evidence/20261022-publication/` に新snapshot/凍結支援/全入力manifest/失敗版/生要約/添付/guard/親終端を833file/25,119,148bytesで保全。raw xcresult/DerivedData/DBはrepo外 `/private/tmp/fr-di-20261015-s27/S27/`、main実行logは開始rootに保持する。
  - 残件／再開条件: 製品authorityは引き続きpublication_proof_not_implementedで正式proof未接続を拒否する。tests専用authorityのQuickTime fixture公開は実Log/Rec.709品質/本番公開の証拠にしない。S23を含む製品external/recovery全owner、S28通常再生・確認・同期UI、実回線/実機の接続・必須検証が残る。該当producer/正式proof/製品動線を引き渡す時に全S27を再開し、独立S26A/M/H01は続行する。
  - 再開（2026-10-22）: 今回の明示implementと直接依存順の継続に従い、S21/S22C/S25の成果と現iOSの確認／wire 11宣言18展開成功を受領。旧中断時の未実行記述は履歴として保持する。mainが新core6file・共有8差分・fixture／全33試験と旧test2差分、隔離HTTP支援／guardを読み取り確認した。既存93support fileと全App279入力を再保全し、外部source246／依存1657／.pth1／Python実体・pyvenvを保存provenanceへ照合した。旧tmp欠落を復元せず、保全S26J archiveの265snapshotを入力にする。
  - 今回の限定所有: `original_removal_core`はserver-implementationのframe_relay_files.py／test_frame_relay_publication.py／prepare_publication_snapshot.py／cases-publication.json／backend-publication-overlay.diff／README-publication.mdの6file。`background_sdk`はserver-isolationのprepare_publication_probe.py／publication_fixture_listener.py／run_publication_fixture.py／run_publication_simulator_probe.py／README-publication.mdの5file。保護namespaceの正規化alias・ASCII大小文字による迂回を閉鎖し、旧137node160case＋publication全33node70caseを明示選択する。HTTPはseed前thread母集団・guard救済前の所有SQLite閉鎖・全量前の実AVPlayer進行の親照合を仕上げる。main凍結レビュー後だけ準備helper／import／pytest／HTTPを実行する。外部repo、旧SQL001〜003／登録26試験、既存guard/lifecycle/runner、App/Tests/projectは変更しない。
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

- [ ] Status: in-progress
  - 今回の限定部分: E-S28-MANIFEST-01（421入力）と既取得軽量版の単数実再生/本人確認（433入力）は必要な非実機検証まで完了。原本uploadの単数/固定複数queued受付はDI20261025-06（477入力）で全Unit136・表示build145・MAX全flow146/16厳格監査と実writer153を確認し部分結了。通常141のstrict失敗と修正後readonly144を別範囲で保持する。本人操作MAX149・metadata通常/最大UI162/163とwriter照合は確認中。全task/正式producer/strict正送信/実機のFinish不足を維持する。詳細は `evidence/20261024-publication-operations/README.md`。
  - 部分引渡し E-S28-NEW-01 / E-S28-INVENTORY-01（2026-10-24）: 明示新登録/別namespace・保存原本catalog/同writer/remote通常一覧と必要な非実機検証を完了。入力最大58/通常59各1・旧Keychain/空current照合60・新第5初回UI61の2件、最終全Unit62/旧UI通常63・最大64各2/照合65・66/build67が成功。metadata通常49/最大50/照合51はその実行版を保持し、後続の入力focus/別新test helperだけの差分を層別に引き継ぐ。最終414入力/13必要run・67全runの版はDI-SOURCE-20261023-02とexecution binding。正式manifest/通常媒体/確認/複数操作・全producer/実機のFinish不足で全S28はblocked、独立validationは未開始。
  - 直接残件/再開: 資材不要の既知原本publication manifest取得結果→同writer→版ID/利用可能状態の投影、単数/複数の製品操作導線は未実装部分を残す。S14/S21とS25/S27の当該metadata/port部分を入力に、元のStart/Finishを再確認して個別着手でき、標準資材や全S23を一括前提へ足さない。通常strict dispatch/native正開始・全媒体producer回収はS23/S49のコード残件として別管理。正式変換/品質が必要な枝だけS26資材・Q01条件を直接依存とする。
  - 新登録UI54〜58の入力到達確認（2026-10-24 JST）: 通常54はkeyboard後のApp全体swipeでdestination到達失敗。新helperを実ScrollView内/viewport判定へ修正し通常55は1成功/skip0。最大56はbearer y666に対しcontent下端427.7/keyboard583で到達失敗、57はinteractive指定だけでも未解消。6入力のfocusを束縛し本人dragのinteracting時だけ解除する表示対応を加え、58でdest→bearer実入力まで到達済み、全flowは継続中。原文/ID/Task/登録・Keychain契約/全P2を保持し、再seedなし。失敗・実geometry/画像/版と診断をnew-registration証跡へ保持する。
  - 最大50/UI後51成功（2026-10-24 JST）: 同309入力で最大AX5 fullflow1/全12監査・skip0が成功、largeへ復元。51はVERIFY1成功/seed1skip、同writer/reopenと登録/Keychain/全logical・media reader空、原本+外部MOV2本とimmutable manifestのbytes不変を確認。第4はデータ保持でshutdown。別第3の初回接続/HTTPローカル拒否と新登録SEED→通常/最大UI/VERIFY、最後の全Unit/buildは継続確認する。全S28/実機/品質/受入の未完了は維持。
  - 通常UI48/49成功（2026-10-24 JST）: Formを自然高ScrollView/カード・native本文/見出しへ変更し、全原文/既存ID・全Task/disabled/入力設定/固定footer/lifecycleを47比で照合。48は元fullflow/11監査、49はsync操作/説明への通常scroll・閉じるframe不変/content境界を加えたfullflow/12監査が各1成功/skip0。actual閉鎖HTTPSへの失敗→記録保持→close→一覧/再起動を確認し、309入力前後不変・compiler/analyzer診断/runtimeWarnings0。Appは48以後不変、既存P2/helper/監査条件を維持。最大50と別新登録/初回入力/最終照合を継続し、この通常成功を全S28/実機へ拡張しない。
  - UI46/47の表示境界調整（2026-10-24 JST）: 46で新説明、47で新ButtonのDynamicType指摘が解消した後、47は画面外syncのContrastで失敗。element370×74ptのcropは全画像の(16,723.7)ptのfooterと222行中216行完全一致し、対象frameは未記録。Form clip外を含むAX領域の推定に基づき、表示だけを既存Libraryと同じ自然高ScrollView/カードへ調整する。全control/本文/IDs/入力設定/disabled/Task/離脱時消去/固定footerと全監査を保持し、既存初回接続UIも追加確認する。途中後のlocal/external MOVとimmutable seed hashは一致、logical/Keychain最終照合は別VERIFYに残す。
  - UI44/45の継続確認（2026-10-24 JST）: 44は見出し修正後に新metadata操作の青字Contrastで失敗し、登録済2Buttonをprimary tintへ限定修正。45で当該指摘が消えた後、新inventory説明TextのDynamic Type部分未対応で失敗した。新説明/結果2箇所だけを既存Libraryと同じ実幅/無制限高native UILabelへ調整する。失敗/選択画像/actual説明/309入力一致と閉鎖origin前後実測を保持し、全監査/本文/ID/全12size/P2・seedを維持する。
  - UI42/43の限定修正（2026-10-23）: footer化した42も通常全体は失敗し、接続Formの既定「端末登録」見出しに実Contrast不足を検出。43最大は登録済messageが存在し、465.7ptの本文後の登録世代がForm表示域外で未生成だった。登録失敗とはしない。添付/現版一致をmain/explorerが読み取り確認し、登録済3headerのsemantic primary色と、新test2箇所の通常scroll後の世代1確認だけをworkerに割当てる。監査全件・P2・全本文/IDs・操作/固定footer・immutable seedを保持する。42/43の実exit65と条件/画像/AXを保持し、runnerの将来のshell exit伝播も整合した。
  - 新UIの途中確認（2026-10-23）: seed37成功後の通常UI38は長いfull identifierをXCTestの128文字制限付きqueryへ渡して失敗し、UI helper1行だけを全文一致NSPredicateへ変更。39は新row headerのContrast1件で失敗、文字を含まない選択element画像/不完全AX snapshotから座標は未確定とし、既存native文字計測へ新header1箇所だけ統一した。40/41はcatalog3状態のassertion/全監査3回を通過したがConnectionの閉じるContrastで失敗し、metadata操作/再起動は未到達。semantic tint単独では解消せず、既存再生画面と同じForm兄弟の固定操作域へ閉じるを移す限定表示修正を実装中。全監査/既存P2/helper/原本・登録/seedは保持し、同rootで再検証する。各失敗/前後source/画像/閉鎖origin前後実測をevidence/20261023-remote-inventory/runsへ保持、Unit36/実SDK35成功でUIの未達を置換しない。
  - 最終共有版の検証中（2026-10-23）: 新rowのcontain/native label IDだけを調整し、新seed/UI2fileを加えた309入力へ凍結。全Unit36は638宣言602成功/36skip・1020展開（有意味1019）成功、compiler/analyzer診断/xcresult runtimeWarnings0・入力不変。専用第4Simulatorのseed37は1成功/VERIFY1skip、既存3fixture/原本へ非操作。現在通常UI38、続けて最大文字/全監査・UI後VERIFYを実行する。新登録第3rootのSEED/UIも別入力・別環境で確認し、正HTTPS/全S28/実機を先取りしない。文書P2の確認済みSDK範囲の曖昧さは一文限定修正後、doc_reviewer最終指摘0。
  - 端末metadata部分検証（2026-10-23）: schema7同writer観測/元mutation lookup/current登録UUID guard/UTF8 exact・別remote一覧/通常Compositionを接続。34は関連7suite36宣言75展開成功、35は隔離実HTTP1成功、307入力前後不変・診断/runtimeWarnings0。35は残存foreign global接続→実SDK明示新登録/別namespace auth→32+1取得→同writer/reopen33行を確認。server実parent/child exit0、GET時DB変更0/旧行・原本hash保持/新登録1件だけ増加、媒体0・全handler/Thread/task/socket/DB-media FD0・秘密JSON削除。compile33の新test witness隔離診断は準拠分離だけで修正して保持。証跡 [HTTP結合判定](evidence/20261023-remote-inventory/server-runs/http-001/combined-result.json)。この307版を凍結し、新rowだけのAX調整と専用seed/UIへ進む。通常HTTPSのUI成功/正式proof/全媒体/全S28/実機は未完。
  - metadata server再検証（2026-10-23）: 新testの例外/code/HTTP409/body/items不在を既存拒否契約へ厳密化し、旧001は不変保持。snapshot002は001比で新test1fileだけ変更、新規16宣言49展開＋既存230＝全279case成功、skip0。guard/import違反0、外部246source/既存依存/274snapshot不変、実子process exit0。端末接続/実HTTP/UIの必要検証は後続で、成功だけで全S28へ拡張しない。証跡 [002](evidence/20261023-remote-inventory/server-runs/002/)。
  - metadata server初回検証（2026-10-23）: support8fileを凍結し、既存230caseを保持した新16宣言49展開/全186node279展開を準備。新snapshot274file/外部246source/既存依存を保全し、guarded pytest001は278成功/新1失敗・外部/依存/snapshot変更0・guard/import違反0。欠落tableに対する既存StorageError storage_schema_unavailable/HTTP409拒否を新testがFrameRelaySchemaError/503と誤期待していた。空成功へは転じていない。元失敗を [001証跡](evidence/20261023-remote-inventory/server-runs/001/) に保持し、既存拒否契約へ新testだけを厳密化して別revision002で再検証する。実HTTP/端末/UIはこの時点では未実施。
  - 新登録の限定検証（2026-10-23）: 最終32は関連5suite/31宣言47展開成功、skip/診断/runtimeWarnings0、296入力不変。新2suite10宣言18展開で旧bytes保持・新namespace・concrete/Port dispatch一致・current孤立initial/同store中断/UUID不明・置換/応答欠落/並行を確認。compile29/30と31のconcrete async default解決失敗は全保持し、明示async wrapper＋private同期helperで修正。App5/Support/新Unit2を32版へ凍結、`cleanup_connection` は専用新seed/UI2fileだけへ移行。Connection Appの所有を `inventory_client` へ明示引渡しし、[端末側所有](evidence/20261023-remote-inventory/client-ownership.json) のApp15/新test5にmetadata journal/remote専用通常一覧を接続する。
  - 同task内の独立metadata部（2026-10-23）: 新登録後のremote-only通常一覧は既存manifestだけでは未接続だが、BI-10の既存OriginalContentと同destinationの保存済みbindingから、媒体/正式proof不要で列挙producerを追加できる。隔離serverの有界認証metadataページを先行し、下位契約凍結後に端末の同writer観測とremote専用一覧投影へ直列接続する。worker `inventory_server` は [server所有](evidence/20261023-remote-inventory/server-ownership.json) の限定support8fileだけ、登録workerのApp5/test4と非競合。稼働checkout/DB/media/旧snapshot/guardは変更しない。
  - 独立再開（2026-10-23）: S49同期許可の部分検証/所有解除後、BI-10/AC-BI-25と旧登録保留・新登録通常利用の直接依存を再点検。正式媒体/strict transport/ISO/実機を要しない、別storeUUIDの有効残存資格情報を保持した明示新登録開始を先行する。worker `cleanup_connection` は [所有](evidence/20261023-new-registration/ownership.json) のApp5file/専用新test4fileのみを所有。旧account非上書き/非削除、同writer UUID確定後の別namespace create-only、普通のrestore/register/continue拒否、同store中断/不明/破損の照合を維持。remote-only履歴列挙/媒体UIは別substatusに残し、全S28をdoneにしない。
  - 独立着手（履歴: 2026-10-22）: designの媒体なし別gateと、S14同revision投影・S21同writer・S25/S27 metadata/outbox/失効APIの部分引渡しを直接入力にする。通常strict送信・正式LUT/proof・S14監査全体は本metadata部分の開始条件にしない。全S28のFinishには下記の全必要接続を維持する。
  - 今回のまとまり: 既存登録/既知原本の本人「状態を同期」→媒体なしmanifest/失効1page・明示続行→元mutation/outboxのexact照合→同writer→動画別表示。未解決とcursorを分離し、再openはnullから再照合。同期から媒体開始や本人確認を生成しない。新登録拡張・通常媒体操作・実機受入は残件。
  - 所有: worker status_sync＝新規Application/MediaOperations/BackendStatusSynchronizationCoordinator.swift、Application/Ports/StatusSynchronizationPort.swift、Composition/ProductStatusSynchronization.swift、既存Composition/ProductComposition.swift、Features/Connection/{ConnectionModel,ConnectionView}.swift、Application/Library/{LibraryStoreReader,LibrarySnapshot}.swift、対応する新規StatusSynchronization系Application/Storage/Composition testsと既存UITests/Flows/ConnectionFlowTests.swift。LibraryModelは必要時にmainへ追加依頼。main＝steering/証拠/実行/最終diff。background_sdkはsupport/server-isolationのprepare_publication_probe.py/publication_fixture_listener.py/run_publication_fixture.py/run_publication_simulator_probe.py/README-publication.mdだけを非重複所有し、新metadata-only実HTTP専用modeを準備。旧S27の全12観測経路を保持し、新runは別必須観測/実passed/zero-media/全owner終端を判定する。その他App279・support93・docs・projectは凍結、共有store/schema/wire/既存SDK/LibraryView/旧P2試験は変更不可。
  - 初回検証 s28-unit-01: 285入力前後一致、compile exit65・0実行。新test fakeのasync protocol witness隔離とstore引数の不足を修正し、製品契約/assertion/HTTP添付条件を維持してcandidate02へ再凍結。失敗版と診断を保全、unit02で再検証する。
  - substatus: 媒体なし既存状態同期/明示新登録/原本catalog発見・同writer観測/通常remote一覧・関連検証は部分引渡し済み。正式manifest投影/通常媒体・確認・複数操作/全producer接続を残し全S28はblocked、実機未実施。登録/current storeはawait後もexact再照合し、原本使用者未知・背景履歴のproducer不足は当該失効をunknownに保ちACKなし。既存invalidation予約による新規lease/prepared/resume拒否と競合を検証する。
  - E-S28-01（2026-10-22）: 既存登録・既知原本の明示1page同期/続きを同writerへ接続。未解決失効をcursorから独立保持し、再openはnull再照合、元mutation/outboxのexact lookup・登録/storeのawait後照合を維持。失効済V1のpointer据置を確認復活なしで扱い、撮影日時で動画別表示する。背景履歴/未知ownerは対象ACKを保留し、同期から媒体/確認を生成しない。
  - E-S28-01 / 検証: candidate02の285入力で全Unit546宣言/868展開成功（空template1を除く有意味867）、28skip/失敗0。専用Status Simulator（702E398D-FFE9-404E-8024-622F10848C65）のseed/UI/reopen各1成功、generic iOS build成功、全run前後入力変化0・runtime/compiler/analyzer各0。HTTPは明示metadata-onlyの別modeでSDK1宣言/1実行成功・skip0、失効一覧→manifestの実2要求/媒体byte0/確認・ACK・lookup0、SQLite再open一致。新8必須観測、pre-rescue接続/FD残留0、全thread join・子exit0/0・signal0・秘密env削除・設定22/外部source246/依存1657とbackend273/新HTTP9source不変。SDK task/session件数は未観測falseとsource-await契約を分けた。checkpoint be8d06046ef49269679da205b216042a8859c0fe28839216784837fee0759720。
  - E-S28-01 / 引渡し: [証跡manifest](evidence/20261022-status-sync/archive-manifest.json)、[main最終確認](evidence/20261022-status-sync/s28-main-final-review-01.json)、[HTTP最終確認](evidence/20261022-status-sync/s28-http-main-final-review-01.json)。失敗したunit01と修正差分を保全。support他88file/LibraryView/共有schema/SDK/projectを保持、S27の旧実証拠/全12観測は昇格・置換しない。全S28/正式proof/全媒体/実機は未達のまま所有解除。
  - Depends: S14,S23,S25,S27。
  - Owner / Files: O-IOS-BI＋O-LIBRARY＋O-COMPOSE（直列）／`FrameRelay/Platform/Remote/` の状態adapter、`FrameRelay/Features/{Connection,Library,Playback}/`、`FrameRelay/Composition/` と対応test。
  - Done when: 媒体なしモバイル同期、旧登録保留と新登録通常利用、動画別段階／停止／不明表示、単数確認／複数転送導線。
  - Verify: V-UI／V-SERVER、旧確認非復元、別動画続行、未取得offline表示。
  - Stop: 全履歴再確認を通常一覧条件にする、同期待ちで自動媒体取得。

### S2V 段階2の結合・障害・レビュー

- [ ] Status: blocked
  - 着手（2026-10-22）: mainが利用可能な各snapshotの部分集約を行う。S24I/S26等のFinish不足を保持し、独立validationや未接続コードの追加実装は開始しない。所有は本tasklist・集約証跡と、support/server-isolation/README-publication.mdの実行結果リンクに限る。実行helperは変更しない。
  - 部分集約（2026-10-22）: 同writer/登録・S24/S25・S27 backend230/実HTTP1・S28明示metadata接続の版別証拠をmain確認。現288入力で全Unit913展開成功/29skip、metadata UI1/reopen1/実HTTP1（2要求/媒体0byte）を確認した。旧publication HTTPの279入力と現288入力を分け、全S24I/正式資材と変換S26/全公開ownerとUI/再登録全導線・全媒体は不足のため本集約はblocked。実機/G3待ちだけとは扱わない。実行helperは凍結、READMEの未実行記述2箇所だけを実証拠リンクへ補正（support93中1file、HTTP実行source8/overlay不変（snapshot9中README1のみ後補正））。独立S31以降や文書/H01は続行可。証拠: evidence/20261022-stage-aggregation/stages-aggregation-final-02.json。
  - Depends: S24I,S25,S26,S27,S28。
  - Owner / Files: main／本tasklist（段階2コードと証拠はレビュー対象）。
  - Done when: 非実機の保存／配信／確認／登録／通信制御が接続され全必須検証・レビューが揃う。変換不足は当該taskと本集約に残す。
  - Verify: V-SERVER／V-PUBLISH／V-PLAY／V-STORE／V-UI／V-REVIEW。
  - Stop: 本集約の未完了だけでS31以降を止めない。G1実機・G2B・G3品質はA12〜A15へ。

### S31 Photos実登録・必要時読取・不明照合

- [ ] Status: blocked
  - 今回のconsumer部分（2026-10-25）: 完全取得済みlocal軽量版の単数/固定複数Photos製品導線はDI-SOURCE-20261024-03（449入力）で関連289展開・actual PhotoKit65・通常/最大UI/実resource hash-date-audioとwriter再openを確認して部分結了。通常strict/正式producerは未完であり、65の受付Wi-Fi条件注入は実native admission証明にしない。最終SDK開始の同writer/capture/共有claim・retained FD再確認・開始前取消は現在の独立実装中で、実行前は未検証とする。全S31/実機品質は未完。
  - 修正完了 E-S31-OWNER-01（2026-10-23）: ManagedTemporaryMediaの同exact登録/結果/terminal/mode回収を単一Taskへ合流し、既完了useはintent/terminal/releaseのexact lookupと同use/dir/file/storeidentityを再照合。自ownerの実FD終端が確定した閉鎖後はread-onlyで返し、root再open/回収/再追加を行わない。部分閉鎖はunknown、閉鎖状態guardでFileHandle descriptor参照を拒否する。旧8枝とbarrierを維持した新4宣言11展開を含み、関連36宣言86展開/全Unit604宣言952展開（有意味951、31skip）/実PhotoKit許可拒否各2/unsigned iOS buildが成功、診断/runtimeWarnings 0。292入力は全必要run前後一致。mainが製品1/test2の全差分と保護を確認し、永続2節追補のdoc_reviewer指摘なし。旧09失敗/0実行11/決定的crash12も保持。通常Photos producer/正式媒体/複数保存/実機のFinish不足は残し、全S31をdoneにしない。
  - 再開（2026-10-23）: S34最終全Unitで既存Photos/失効/取消し境界1枝の呼出結果不整合を観測。元結果・terminal/use解放/ACKは実diskに保持され、S34 App8file差分から当該Photos経路への変更はない。結果捨棄と断定せず、同一photo use回収/owner閉鎖の競合を決定的に診断する。worker `cleanup_connection` がまず既存 `FrameRelayTests/Integration/Publication/PhotoInvalidationBoundaryTests.swift` だけを所有し、元8枝を維持したbarrier回帰を追加。製品修正の所有はred結果/最小案のmain確認後に引き渡す。通常Photos producer・正式媒体/複数保存/実機の残件は維持する。
  - 決定的診断（2026-10-23）: `photo-owner-red-11` の単独method指定は0実行であり成功にしない。suite全体の `photo-owner-red-12` は旧8枝成功/新1枝でApp crash。SDK結果/終端commit→実invalidation/同use解放/root閉鎖/ACK→遅延した同exact releaseの順を強制すると、`ManagedTemporaryMedia.requireRoot`が閉鎖済みFileHandleのfileDescriptorへ触れ、NSFileHandleOperationExceptionで終了することを確認した。これは元09の返値分岐を確定する証拠ではなく、同じ競合領域の別の確定不具合。後続として同workerへManagedTemporaryMedia.swiftと必要なPhotoTerminalRecoveryTests.swiftだけを追加所有し、既完了exact releaseのread-only照合、同一回収join、閉鎖FD非参照を最小修正する。元assertion/unknownコピー保持/未証明reader拒否/schemaを維持する。
  - E-S31-02 / 実装（2026-10-21）: 内部 `$steering` を明示使用し残件を再開。PhotoUsageTerminalとPhotoTerminalUsageRelease、terminal/releaseTerminalUsage commandをschema7の同writerへ加算。実SDK非開始または完了＋FD閉鎖・元owner/use/epoch/dir/fileとexact intent/terminal commitから該当useだけを解放する。登録結果/identifier/再追加抑止とは独立とし、終端proofなしの旧unknown/意図のみ、終了/閉鎖不明・別intent・補助FD残留は解放しない。旧success回収互換を保持する。
  - E-S31-02 / 接続・判断 S31-P02: 登録結果によるcopy保持を共通の派生規則にし、一般temporary release/reclaim経路でもunknown/failed/notAttempted本体を回収しない。restore/closeOwnerが新終端proofを照合しscope/全reader解放・失効ACKへ接続する。明示retryOf付き本人操作だけ同媒体/版/日時へ新使用権を獲得し、確定intent拒否では未使用new useを安全解放。不明では元mutation/useと生存coordinatorのSDK非開始事実を保持し、exact照合後だけ終端記録へ進める。再起動でその事実を推定せず、SDK再実行もしない。期限/容量・未知copy自動回収policyの合意ではない。
  - E-S31-02 / 構成・実行: Xcode27.0(27A266a)/Swift compiler6.4、実在project/scheme/test plan FrameRelay、Debug/App/Unit/UI、Swift5/iOS27/MainActor設定を再確認。新規専用iPhone18Pro iOS27 Simulator `52DFD2D6-682C-4567-B77F-F9859A2D84D7` を作成してshowdestinationsへ実在確認。test-01は空DerivedDataから `-only-testing:FrameRelayTests -only-testing:FrameRelayUITests/ProductCaptureFlowTests -only-testing:FrameRelayUITests/PhotoPermissionsFlowTests`、実Photosは `TEST_RUNNER_FR_PHOTOS_INTEGRATION=authorized/denied` とNativePhotoLibraryTestsのみ。generic iOSは `CODE_SIGNING_ALLOWED=NO build`。全引数/exit/sourceは証跡runs、raw bundle/log/DerivedDataは上記root。
  - E-S31-02 / 結果: test-01 Unit440宣言/653展開＋UI4成功、失敗0・既存/opt-in21skip。新PhotoTerminalRecoveryTests10宣言/27展開、新PhotoInvalidationBoundaryTests1宣言/8展開の35case成功。実Photos authorized-02/denied-03は各2成功/2skipで、coordinator経由のSDK非開始/完了→terminal→使用権解放、許可時本体回収と拒否時本体保持、従来adapterの媒体bytes/日時/音声/AVPlayerを確認。ios-build-01成功、4run前後/現物245入力一致、runtime/compiler/analyzer各0。空template example1件を除くUnit有意味実行652。stdoutの既存AppIntents metadata警告は別記。初回xcresulttool summary抽出のみDB生成競合でexit64、逐次抽出で成功しtestの再実行なし、元ログ保持。
  - E-S31-02 / 境界検証: 両store×4結果、SDK遅延/本人Task取消し中のFD/use保持とACK不発行→実MOV/実ProductMediaTerminationの2scope終端→tombstone/ACK/outbox→SQLite再open、他用途/別copy・未知結果/identifier保持を確認。terminal/release commit前後応答欠落/元mutation保持、owner/lease/epoch/dir/file/command/commit改変拒否、後日同一不明結果の成功確定時の本体回収、fresh retryの確定拒否/不明intent、別媒体retry拒否を確認。Photos順序のfixtureを実PhotoKit完了証拠と混同しない。
  - E-S31-02 / V-REVIEW・残件: mainが差分・同writer/実I/O/全解放・所有・既存保全を確認し、document_authorが3文書を限定同期、doc_reviewer指摘なし。正式Rec.709 producer/通常保存開始/固定複数集合・S23/S27全製品接続、未知copy自動回収policy、旧証拠不足use、旧extensionless再利用とDV-16は残るためS31全体blocked。独立validationは開始しない。
  - 今回の所有（2026-10-21）: worker `s31_terminal`へPhotoRegistration.swift、PhotoLibraryPorts.swift、RenditionMediaPorts.swift、PhotoSaveCoordinator.swift、PhotoStoreProjection.swift、MediaStoredValueValidation.swift、ManagedTemporaryMedia.swiftと専用Photos/Storage/Domain関連testを単独引渡し。共有writer/schema7・既存enum/保存互換を保ち、元の成功限定回収を保持する。追加引渡し: 同workerへMediaOperationStorePort.swiftの新terminal mutation拡張、TemporaryMediaStoreProjection.swiftの結果不明/失敗copy保持guardも単独割当。失効結合試験worker `s31_invalidation_tests`は新規FrameRelayTests/Integration/Publication/PhotoInvalidationBoundaryTests.swiftだけを単独所有し、実装workerのPhotos fixture/契約は変更しない。文書author `s31_terminal_docs`はdocs/architecture.mdのPhotos境界、docs/functional-design.mdのD7/S7、docs/repository-structure.mdの関連責務/test行だけを所有し、今回の終端/使用権と結果/コピー保持の区別を同期する。ほかのworkerはtasklist/証跡/docs/project/Compositionを変更しない。
  - 着手/保全（2026-10-20）: mainが指定3文書・関連永続文書と既存変更を確認し、内部 `$steering` を明示使用。上記rootへ開始manifest/copyを保存して既存S48/M04変更の保護方針を確定した。mainは本tasklist/新規証跡/構成照会/検証実行/最終diffを所有し、explorer `s31_contract_map` と `s31_ui_map` はread-only。実装workerの所有は引渡し前に下欄へ追記する。一度に進行中の書込みtaskはS31だけとする。
  - 共有契約/永続化の所有引渡し: worker `s31_core` に新PhotoRegistration値/PhotoLibraryPorts、既存BackendCommit・MediaOperationStorePort、同writerのMediaOperationStoreAdapter/MediaStoredValueValidationと新PhotoStoreProjection、必要最小のRecordingStoreDocument互換変更、専用新規Domain/Storage試験だけを単独割当。既存mutation/lookup/journalとS25 resolverを再利用する。共有APIを確定してからSDK/consumerへ引き渡し、同じファイルの重複所有を避ける。既存他testの変更はmainへの事前引渡し後に限る。
  - SDK/用途文の所有引渡し: worker `s31_photokit` は新規Platform/Photos/NativePhotoLibraryと専用Integration/Photos試験だけを所有し、共有API凍結後に実装する。O-COMPOSEの前提追加としてprojectのApp Debug/ReleaseにPhotos追加/必要時読取の用途文4行だけを同workerへ割当。既存言語/OS/署名/他設定は凍結。実Photos試験には既存Simulatorの写真を変更せず、新規専用 `7FD88306-1CFD-4181-83E6-ED765F8830B0`（iOS27/iPhone18Pro）を作成・起動し、同project/schemeからdestinationを再確認する。新規合成媒体と写真だけを使用する。
  - consumerの所有引渡し: worker `s31_coordinator` は新PhotoSaveCoordinatorと専用Integration/Photos/PhotoSaveCoordinatorTests・PhotoSaveFixtureだけを単独所有する。core/SDK/consumerでファイルを分け、同一S31の内部を接続する。起動時の旧photo使用権はowner/epochだけで奪取せず、実終端/FD閉鎖後の成功commitと元useの照合を必要とする。追加の既存ファイル変更はmainによる所有引渡し後に限る。
  - 限定回収/Libraryの追加引渡し: `s31_coordinator`へ新PhotoRegistrationReconcilerと専用PhotoTemporaryRecoveryTests、ManagedTemporaryMediaの成功proof限定回収、RenditionMediaPortsのcontentType optional追加/終端コメントだけを追加所有する。`s31_core`が成功record/元use限定の新photo releaseUsage commandを同writerへ追加し、一般temporaryの旧epoch規則を緩めない。`s31_library`は既存LibraryStoreReader/Snapshot/Model/View、新LibraryPhotoReconciliation、ProductComposition/ProductLibraryFactoryの読取接続と専用試験だけを所有する。通常保存startの未接続を維持し、既存記録の明示照合導線だけを接続する。
  - 文書の部分同期: document_author `s31_docs`へarchitectureのPhotos関係だけを単独割当。既存S48差分/他節/他文書を保持し、M03全体doneを先取りしない。必要な別文書の引渡しとread-only doc_reviewerはmainが後段で直列に行う。
  - 軽微可逆判断 S31-P01（main）: 同じ撮影/変換版のsuccess・unknown・意図のみ中断は新追加を拒否する。SDK未実行の権限拒否等はnotAttemptedとして実SDK失敗/不明と分離し、未追加が確定した直前操作に明示retryOfを束縛した本人再試行だけを許す。写真側未発見/本人削除は再保存の許可にしない。既存journalのenum加算と派生projectionを使用し、別DB/非optional保存項目を追加せずschema7を維持する。
  - substatus / 着手時: Photos共有契約・同writer意図/結果=未実装、実PhotoKit下位処理=未実装、S25完全媒体使用権/終端との接続=未実装、権限理由UI=未実装、正式製品媒体/全操作導線=後続接続待ち、実機権限/品質=未確認。
  - 初回検証 s31-unit-01: 確認済みXcode27/Debug/専用iOS27 Simulator、全Unit指定でcompile exit65・0件。新LibraryPhotoReconciliationのsubmitからMainActor availabilityへの同期呼出し1error、compiler warning0。243入力は実行前後一致、全実行source/command/log/xcresultを上記rootへ保持。所有workerが利用不可説明をnonisolated static定数へ分離し、unsafe解除なしで修正・再凍結。新run s31-unit-02で再検証する。
  - 中間検証: s31-unit-02は新fault fixtureのasync witness隔離6error/unused switch値2warningでcompile exit65・0件。@MainActor witnessとreturn switchへ修正し、SDK後result commitの確定拒否もunknownへ揃えた。s31-unit-03は全Unit425宣言/614展開ケース成功・既存/opt-in19skip・失敗0、runtime/compiler/analyzer診断0、243入力前後一致。stdoutの既存AppIntents metadata warningは別記する。後続reconcilerの遅延応答対象を厳密化する修正1件を加えて最終Unitを再実行予定。
  - 実Photos初回 s31-photos-authorized-04: 新規専用Simulatorでphotos-add/photosを明示grantし実1件を実行、PhotoKitが合成MOVをinvalidMediaとして拒否しexit65/1失敗。243入力前後一致を確認し、失敗版source/command/log/xcresultを保持。未実行やfake成功へ置換せず、Native担当がMIME/拡張子/fixture適合を限定調査した。初回OS許諾dialog/限定アクセス/実機品質の確認ではない。
  - 実Photos適合修正: originalFilenameをMIMEに揃えたauthorized-05もPHPhotosErrorDomain3302で1失敗。compatibility-06は同一H264/PCM8k MOVの元.mov URLが成功、実S25 extensionless URLが3302拒否と観測した（raw SDK診断で製品成功commitなし）。追加所有を同coordinator workerへ直列引渡しし、TemporaryMediaState内TemporaryMediaLeaf・TemporaryMediaStoreProjection.create・ManagedTemporaryMedia.create/openFileの共通規則を変更。新規だけMIME完全一致のUUID.mov/mp4とし、旧UUID-onlyのread/reopen互換と同inode/bytesを保持、schema7/既存fileのrename・移行なし。原本や音声/動画bytesは変えていない。診断testは現在、明示opt-inの元.mov/legacy-extensionless比較として製品S25と分離する。
  - substatus / 終了時: 共有契約/同writer/SDK下位処理/S25完全媒体・真終端/成功限定回収/明示照合UI/技術検証/main確認=完了。正式Rec.709媒体と通常保存開始/固定複数集合/全媒体gate・失効との製品接続=未完。unknown/失敗copy/use回収・旧extensionlessのPhotos再利用=未対応。実機権限/品質=未確認。これらはS31 Finish残件であり、下位処理の成功だけでtask全体をdoneにしない。
  - E-S31-01 / 構成・コマンド: Xcode27.0(27A266a)/Swift compiler6.4、実在project/scheme/test plan FrameRelay、App/Unit/UI3target・Debug・Swift5/iOS27/既定MainActorを確認。testは `-destination 'platform=iOS Simulator,id=7FD88306-1CFD-4181-83E6-ED765F8830B0' -parallel-testing-enabled NO -collect-test-diagnostics never`、各runの専用DerivedData/resultBundleを指定。実Photosは `TEST_RUNNER_FR_PHOTOS_INTEGRATION=authorized/denied` を明示、通常Unitではopt-in実行しない。generic iOSは `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。全引数/実行版/exit/resultは証跡の各command/result JSONを参照。
  - E-S31-01 / 最終結果: authorized-07で実PhotoKit callback成功、完全登録resource bytes一致、撮影日時/video/audio track/AVPlayer進行・decode、SDK終端前のFD/use保持→結果commit後の実unlinkを確認。denied-08は実addOnly/readWrite拒否下でSDK未開始/照合不可/媒体と未実行証拠の保持を確認。unit-final-09は429宣言/618展開成功・20skip・失敗0（既存17＋実Photos/診断opt-in3を成功へ含めない）。ui-10は新規1＋通常撮影3成功、写真拒否でもLibrary refresh/撮影移動・設定復元・再起動を確認。ios-build-11成功。runtimeWarnings/compiler/analyzer各0、stdoutの既存AppIntents metadata/Simulatorログは診断と区別して保持。最終5runと現物243入力は一致。
  - E-S31-01 / 境界・限界: intent/結果commit前後欠落→instance破棄/reopen、success/unknown/identifierなし非再追加、明示retryOf、limited/denied/authorized未発見、古い照合応答、遅延SDK/取消し/finish失敗、成功proofだけの旧photo use回収/他use・他動画保持、旧leaf読取・危険なleaf原子拒否を検証。実OSの初回dialog/limited選択/本人による写真側削除後は未実施。notFound実試験はランダムidentifierであり本人削除の代替ではない。新規合成媒体はLog/Rec.709/実撮影品質の採用証拠ではない。再open試験は同processのinstance破棄で実process終了・電源断の証明ではない。
  - V-REVIEW / 保全: mainが全所有diff・未追跡source・副作用順/実I/O/用途文4行・未接続を確認。開始既存変更へ加算し、20file変更/16新規source以外の変更なし、旧証跡/Render/README/memo/入力仕様/旧steeringを保持。文書authorが3文書をPhotos範囲だけ更新し、doc_reviewerのD7指摘を修正、命名追補も最終指摘なし。全79ACのIDと他task状態を保持。`evidence/20261020-s31/` にcommand/結果/失敗版/版hash/範囲確認を保全し、raw xcresultとDerivedDataは上記repo外rootに保持する。独立validationは代行していない。
  - blocked / 再開条件: 正式Rec.709版の通常取得producer・S23/S27と、ProductCompositionへの保存coordinator/固定複数集合・使用権ownerの製品接続を実装/検証する。unknown/失敗の復旧記録を保持した一時本体/use回収、失効時の全解放・旧extensionless再利用も必要。未知結果を未保存へ丸めず、容量/保持期限や写真側削除後の新しい再保存を勝手に採用しない。実機はDV-16で別判定する。
  - 読取引渡し（2026-10-10、registration_probe_audit/main）: TemporaryMediaReceipt.photoHandoffは完全範囲/同版/content/未解放photoHandoff使用権/capturedAtの値検証を既存試験付きで再利用可能。ただしPhotoKitが読めるlocal媒体の解決/実保持Port、Photos intent/result/localIdentifier/権限/現在存在の型・同writer commandは未実装。MediaRequestはupload/download/playbackだけのため遠隔自動再開規則をPhotosへ転用しない。O-PORT/STOREがschema5/journal/exact commitを加算し、S25未完でも専用resolver＋合成MOV/明示fixture日時による実PhotoKit下位処理・disk再open・非再追加を先行できる。SDK performChangesに取消しhandleなし、Task取消しを未実行/解放とせず完了まで媒体保持、shouldMoveFile=false。用途文2件はO-COMPOSEの前提追加が必要。製品暦日時producerはS41未接続、対応不明/限定/未発見は要確認、日時・名前による推定同定は不可。アルバム/手動再保存/上限期限は未合意のまま。調査のみで書込/PhotoKit/新試験なし。
  - 読取更新（2026-10-20、remaining_tasks/main）: 上記は当時の履歴。現S25には `TemporaryLocalMediaPort` と `ManagedTemporaryMedia.resolvePhotoMedia/finishPhotoMedia` があり、完全媒体/同版/hash/photoHandoff使用権、PhotoKit実終端までのFD保持と終端後解放を再利用できる。resolverを重複作成しない。S41の暦日時producerも接続済み、現共有storeはschema7。Photos専用型/Port・意図/結果/識別子の同writer command・実PhotoKit adapter/通常導線は未実装で、S31本体は今回未着手。次は共有契約→実下位処理→同writer永続接続→S25媒体→製品導線を所有別に引き渡す。登録成功→管理commit前にidentifier自体が失われ得るため、名前/日時で推定同定せず、不明/未発見を未保存や再追加許可へ変えない。S23/S27や正式Rec.709 proof未成立をfixtureで補わず、製品媒体接続は別substatusで判定する。
  - Depends: Start＝N01・既存T03の完全媒体／使用権・操作契約。登録下位処理・権限UI・不明照合規則は試験実媒体で先行可。永続接続＝S21の単一writer、製品媒体接続＝S25。Finish＝両接続と必須検証を含む全substatus。
  - Owner / Files: O-PHOTOS／新規 `FrameRelay/Platform/Photos/`、`FrameRelay/Application/MediaOperations/PhotoSaveCoordinator.swift`、O-LIBRARY／`FrameRelay/Features/Library/` の権限理由UI。O-STOREが同じstoreへPhotos意図／結果commandを追加し、共有PortはO-PORT、project用途文はO-COMPOSEだけが更新する。各対応testを含めファイル別直列。
  - Partial handoff: 下位処理／権限UIは実Photos adapter・拒否／限定／未発見規則・実行可能Simulatorの検証をS34へ渡す。永続接続は意図→登録→結果commitとinstance破棄→再open・不明時非再追加の証拠を渡す。製品媒体接続はS25の同一完全媒体・使用権と解放までを照合する。各substatusに版・所有・証拠・残件を記録し、S25待ちでも下位処理・永続接続を進める。
  - Done when: 追加権限時機、意図／実登録／管理commit、限定・拒否・未発見の要確認、連打／再試行非再追加、不要一時媒体解放を製品経路へ実接続。下位処理やmock試験の成功だけではS31全体をdoneにしない。
  - Verify: V-PHOTOS／V-STORE、実行可能Simulator Photos追加、権限UI、中断・写真側削除非復活。試験専用媒体／境界代替の証拠と製品接続の証拠を別記し、fakeや未接続を製品成功として注入しない。
  - Stop: fakeだけのPhotos完成、未合意のアルバム／再保存意味、未知結果を未保存へ変換。

### S32 容量整理の実削除・復旧

- [x] Status: done
  - 完了 E-S32-03（2026-10-21）: worker `original_removal_core` のcore15 Swift変更をmainが受領。固定batch/子intent/対象別結果をschema7既存journalへ追加し、最新証拠・全reader/epoch・同FD全hash・管理root/lock/reservation/leafを確認してMOVのみ実unlink。最終結果のfile再検査/FD実close/commitも同writer lockで直列化し、別adapterの古いnotRemovedとlegacy照合の競合を解消した。復旧は観測だけ、旧unknown/未実行を自動unlinkしない。
  - 最終検証 E-S32-03: `s32-unit-05` は全Unit454宣言/685展開成功・21skip（空example1を除く有意味684）、新規14宣言/32展開を含む。`s32-ios-build-06` generic iOS/CODE_SIGNING_ALLOWED=NO build成功。runtimeWarnings/compiler/analyzer診断0、既存Fig/AppIntents stdoutは別保持。両runと現物253入力一致、実行中変更0。両disk再open、実MOV対象別unlink/外部保持、全使用者/古いreceipt拒否、hash/path/lock/root差替、最新登録/証拠変化、失効両順序、8中断境界、別adapterの新旧両API stale結果拒否を確認。
  - V-REVIEW-S32: mainが全core差分と実I/O/故障回帰を通読。全開始8,910file中既存変更10件はsteering1/P2 View・test2/core7のみ、削除/所有外/旧証跡変更0。新規core8file、既存S31差分・project/README/docs/入力仕様/旧steeringは保全。`s32-main-review.json` と `evidence/20261021-removal-core/` を参照。通常Composition/UI接続はS34、単数破棄coordinatorはS33、実機DV-17は未実施。
  - 中間版 E-S32-02: fixture全owner照合等を修正した03は13宣言12成功/1失敗・30展開29成功/1失敗、旧zero-reader receiptの再照合不足だけが残った。修正後の `s32-unit-04` は全Unit453宣言/683展開成功・21skip（空example1を除く有意味682）、runtime/compiler/analyzer診断0、253入力不変。ただしmainレビューで、別adapterの古いpresent観測がunlink後にnotRemovedをcommitできる競合を発見し、完了判定を保留。結果commitにも同writer内の最終ファイル照合を加え、legacy経路と合流するB案と別adapter回帰を実装中。既存の成功を競合解消の証拠へ流用しない。
  - 途中検証 E-S32-01（2026-10-21）: 新規専用Simulator `CA378511-84F8-415D-A025-CD7CB59B54D3`（iPhone18 Pro/iOS27.0）を作成し、boot/再showdestinationsで確認。`s32-focused-01` はcompiler error4/警告7＋build取消1、test0件で失敗。明示隔離を修正した02はcompile診断0・12宣言実行で失敗。publication後の全owner照合を欠く新fixtureと、再openで変わるsession-only epochを含む比較を修正中。安全guardは保持し、false-positiveな試験成功を使わない。実行前後253入力の変化0。raw rootは開始root、初回証跡は `evidence/20261021-removal-core/` へ保全。
  - 着手（2026-10-21）: mainが直接依存の部分引渡しを確認。worker `original_removal_core` が下記core/Port/storeと専用testを単独所有する。固定batch/子intentと状態を既存journalから導出し、予約・結果と同じcommitで更新する。旧schema読取・S31既存差分・unknown reader・未実行自動削除禁止を保持し、UI/Compositionは本task中変更しない。
  - Depends: S12,S13,S21。
  - Owner / Files: O-ORIGINAL＋O-STORE（直列）／`FrameRelay/Platform/OriginalStore/` の削除実装、`FrameRelay/Application/MediaOperations/CleanupCoordinator.swift`、`FrameRelay/Platform/LocalStore/` の記録と対応test。
  - Done when: 各動画実行直前の証拠再判定、複数固定集合、ordering・全解放・unlink・再open照合。offline有効証拠で整理可。
  - Verify: V-DELETE、失効との両順序、前後中断、不明／未削除／削除済、外部非削除。
  - Stop: 有効確認なし削除、未実行削除自動実行、再接続／写真強制、削除予約喪失。

### S33 単数破棄の実削除・復旧

- [x] Status: done
  - 完了 E-S33-01（2026-10-21）: 所有3fileをmainが全差分確認。exactな単数risk ackをdurable batchへ保存し、S32の実停止/全解放・予約・同FD全hash/unlink・同writer結果観測を再利用する。保存/検証/確認を昇格せず、同ID再入力/再openの未処理を自動実行しない。通常UI接続はS34へ引渡し。
  - 検証 E-S33-01: `s33-unit-01` は全Unit461宣言/706展開成功・21skip（空example1を除く有意味705）、新規7宣言/21展開。実MOVの未転送/実検査unknown×両store、risk欠落/対象違い/複数拒否、SDK/旧unknown reader、失効中拒否と失効後の別明示破棄、8中断境界/3 exact lost reply、再open、非empty Mac/Photos記録/外部sentinel保持を確認。Simulator build成功、runtime/compiler/analyzer診断0、255入力変化0。generic iOS buildはS34後の最終統合版で確認し、S32の成功を本版の成功へ代用しない。`evidence/20261021-discard-core/` と `s33-main-review.json`。実機DV-17未実施。
  - 着手（2026-10-21）: S32の同一固定batch/予約/実unlink/観測機構を引き渡し、worker `original_removal_core` が新規DiscardCoordinator・専用Integration testと共有OriginalRemovalFixtureだけを単独所有する。対象とリスクのexactな単数commit、旧状態の非昇格、未転送/未検証/不明/失効・reader競合・再open/外部保持を確認する。UI/Composition/既存証跡/他sourceは凍結し、必要な共有変更はmainへ境界を申し出る。
  - Depends: S12,S13,S21。
  - Owner / Files: O-ORIGINAL＋O-STORE（直列）／`FrameRelay/Platform/OriginalStore/` の共通削除実装、`FrameRelay/Application/MediaOperations/DiscardCoordinator.swift`、`FrameRelay/Platform/LocalStore/` の記録と対応test。
  - Done when: 対象／消失リスク本人確認を単数でcommitし、同じ実削除機構と照合を使用。検証／確認を昇格せず管理記録保持。
  - Verify: V-DELETE、未転送／未検証／不明／失効、競合読書込、再起動、Mac／写真非削除。
  - Stop: 複数一括・自動破棄、rename／trashを削除成功とする、受付だけで履歴化。

### S34 写真・整理・破棄を一覧／履歴へ接続

- [ ] Status: blocked
  - 今回のPhotos導線部分（2026-10-25）: S31と同じ完全local軽量版の単数/固定複数Photos受付・対象別結果・通常一覧/履歴・明示記録照合をDI20261024-03で限定確認済み。適格cache自身の回収と原本保持を分離し、旧未確定コピーや既存Photosを削除しない。通常strict/全媒体producer/正式proofは未完、最終SDK開始の新guardは検証待ち。既存P2と途中失敗を保持する。
  - 部分引渡し E-S34-CLEANUP-01（2026-10-23）: 条件付きの通常複数容量整理の実接続/対象別最終判定と実unlink/通常一覧/再起動/通常・最大文字AXを確認。新規8宣言27展開は成功、専用UI1・read-only AX通常/最大各1、seed1/VERIFY1（各逆条件1skip）、generic iOS署名なしbuild成功、凍結292入力の実行中変更0。適格2本のみ不在、条件不足1本/保持1本/外部sentinelのbytes/hashとimmutable manifest不変。App8/既存test1/新test4の全差分をmain確認し、永続4文書の限定同期/P2記述矛盾修正後doc_reviewer指摘なし。全Unit09の既存Photos1失敗はS31へ診断を引き渡し、全Unit合格へ丸めない。正式証拠producer/通常Photos/全S34・実機受入は未完了。
  - 再開（2026-10-23）: 前回独立検証の新規指摘0/P2-STOP非実機合格を受領。S32/S16とS34-BG01の確定終端/同writer inventoryを再利用し、通常複数容量整理を条件付き接続する。全動画別の有効証拠・実終端・最終unlink条件を維持し、正式媒体producer不足/未知transportは当該対象だけ保留する。所有と結果は今回の再開記録/証跡へ同期し、Photos/全S34/実機受入は完了へ変更しない。
  - 所有/部分検証 E-S34-CLEANUP-01（2026-10-23）: worker `cleanup_connection` が `evidence/20261023-cleanup-composition/ownership.json` の限定App/Unit/UIを単独所有。stage1は既存9file＋新Unit2file、mainが全加算差分と新Unitを確認し、凍結290入力の `cleanup-unit-01` で関連6suite/38宣言109展開成功、失敗/skip/compiler/analyzer診断/xcresult runtimeWarnings 0・実行中入力変更0。同原本の全transport fenceをcleanupにも適用し、cleanup固有の最終writer証拠再判定/旧CAS/schema7を保持。先頭のunknown子は保留しつつ、後続の終端済み子のadmissionを独立解放する。専用seed/通常複数UI/最終回帰/buildは未実施のため当該部分も完了にしない。永続4文書の限定同期は `cleanup_docs` が所有し、成功件数を先取りしない。
  - 部分引渡し E-S34-01（2026-10-22）: 単数破棄の通常Composition/リスク確認/実unlink/動画別結果/成功履歴/再起動を接続し、`s34-ui-08` 専用UI1成功＋`s34-verify-09` 実disk照合1成功/seed1skip。exact binding4件、整理・明示破棄のみ実file不在、予約中・保持対象のhashと外部sentinel不変、全reader0、同batch履歴を確認。途中UI05のPopover cancel不在はtest1fileだけ実表示へ修正し、警告guardは保持した。App/Unit/projectは最終Unit04・iOSbuild04と同一、260入力の実行中変更0。
  - CF回帰・main確認: `s34-regression-10` はUI18件中14成功/既存P2監査4失敗、skip/runtime/compiler/analyzer診断0。接続/撮影/写真権限非要求/実再生/停止/背景/再起動/実文字・VoiceOverは成功。`s34-cf-verify-12` は既存seed照合1成功/seed1skip、原本digest/reader0を保持。撮影設定は同じ値のJSON key順だけ再符号化されていたため、App終了後に開始時67bytesへ戻しhash一致・文字largeを確認した。mainは全19差分（S33から既存14/新5）、削除・失効別seal/共通epochとplayer epochの分離/観測だけの照合/未接続拒否を確認。開始8,910fileの変更20件は本steering/P2/S32〜S34所有範囲だけ、欠落/旧証跡/既存project/docs変更0。`s34-main-code-review-13.json` と `evidence/20261022-removal-composition/`。
  - 未達・再開条件: 正常単数破棄の部分は引渡し済み。通常の複数整理は過去transportのS23実終端producer、通常Photos保存/複数操作はS31と正式媒体producerを待つ。厳格P2の詳細contrast/履歴clipped/handoff DTは未達。S34全体/S3V/実機DV-17を完了にしない。全sourceを凍結して所有解除し、まずS14の独立lazy child候補を有界比較、その後S23の独立session/task記録・実終端部分へ進む。
  - 専用UI途中05（2026-10-22）: `s34-ui-05` は1件失敗、260入力変化0・runtime/compiler/analyzer診断0。確定tap前のguardが「キャンセル」button不在で停止した。mainが画面/AX treeを確認し、exact対象・消失リスク・Mac/写真非削除の全文表示と、システムPopoverの`PopoverDismissRegion`によるキャンセルを確認。通常原本の破棄は未実行、失敗時の専用root14fileをrepo外へcopy/hash保全。同guardの対象/警告照合は保持してUI test1fileだけ実表示のキャンセル方法へ修正する。App/Unit sourceは凍結のまま。
  - 部分検証 E-S34-01（2026-10-22）: diagnostic03の実SDK返値/同lease解放から、失敗は短いfixtureの自然終端をmutable activeSourceで取り逃すtest側と確定。実progress・elapsed・exact source/session・同leaseの実解放を根拠に修正した `s34-unit-04` は全Unit470宣言/726展開成功・23skip（空example1を除く有意味725）、新S34 9宣言/20展開成功。`s34-ios-build-04` generic iOS署名なしbuild成功、`s34-seed-03` は新専用Simulator空root限定で1成功/VERIFY1skip。通常root同writerのS32実unlink済み整理/予約中破棄/保持/新UI破棄対象を準備した。3runと現物260入力一致、実行中変更0、runtime/compiler/analyzer診断0。専用UI/VERIFYとCFの厳格監査は実行中・未確認のため全完了にしない。
  - 途中検証02（2026-10-22）: compileを修正した `s34-unit-02` は全Unit465宣言成功/5失敗・23skip、717展開成功/9失敗、runtime/compiler/analyzer診断0・260入力不変。失敗は追加Composition試験共通の実player再開確認helper（admitted/source=nil）9枝だけ。通常Compositionの実破棄/dialog対象固定/reader表示8枝と既存回帰は成功。SDK受付拒否・媒体の準備/自然終端を未確定のまま、test fixture/有界診断の2fileに限定して原因を調べ、実progress/lease解放の基準は保持する。候補02全入力と失敗を同証跡へ追加保全。
  - 途中検証（2026-10-22）: 通常の未転送単数破棄、exact dialog対象/結果投影/明示observe-only照合、削除と失効の独立admission所有を候補化。新専用seed/UIの実行前に `s34-unit-01` はtest内actor.scopes参照2箇所のawait不足でcompile失敗（compiler error2＋test取消1、test0件/warnings0、260入力変化0）。全入力候補と失敗証跡を `evidence/20261022-removal-composition/` に保全し、test fixtureのbatch操作ID2箇所とplayer固有epoch/共通writer epochの混同も限定修正する。実unlink/UI成功・全S34完了とは扱わない。
  - 着手（2026-10-21）: mainがS32/S33 coreを引き渡し、`original_removal_core`へ通常終端producer/削除専用admission所有・shared Composition・Library投影/操作/明示結果照合と専用testを直列で割当てる。既存CF seedは削除せず、新規専用Simulatorの新規合成原本だけで破壊的UIを検証する。写真通常保存/正式媒体は未接続を保持。cleanupの正式proofに伴う過去transport終端はS23 producer不足として局所拒否し、neverStartedを偽装しない。未転送単数discardから通常経路を接続する。
  - 追加着手（2026-10-22、S34-BG01）: S28検証版の所有解除後、S49で得た実SDK終端→source実FD閉鎖→ownerClosed commit→exact lease解放→request.stoppedを入力に、確定終端済background履歴がある原本の単件破棄を独立接続する。通常cleanup成功・活動中自動停止・旧不明source回収・正式品質proofは開始しない。target全transport inventoryをhash前に固定し、同writer最終unlinkで再構築/照合してABA/新attempt/task/登録変更を拒否し、別動画更新は許す。
  - S34-BG01 / 初回unit01: candidate01の288入力前後一致、compile/runtime/analyzer診断0。908展開成功/2失敗/29skip。新12宣言42展開は成功したが、既存通常未転送原本破棄とS28 reader停止中の予約競合の2case（11issues）が回帰し、同じ所有内で根因修正する。assertionや安全条件を弱めず失敗版・raw結果を保持する。
  - S34-BG01所有: worker removal_terminal＝ProductBackgroundMediaFactory/BackgroundMediaCoordinator/ProductRemovalTermination/ProductComposition/LibraryStoreReader/OriginalRemovalPorts/OriginalStorePort/OriginalRemovalStoreProjection/ExplorationRecordingStores/ManagedOriginalAccessの10既存file＋新規OriginalRemovalTransportFenceTests/ProductHistoricalRemovalTestsの2testだけ。background_sdk＝新規Remote/BackgroundRemovalTerminalTests.swiftだけを非重複所有（未作成状態でremoval_terminalが返却ACK）。main＝tasklist/証拠/実行/最終diff。共有schema/Codable旧command/project/その他App・support・docs・旧証拠は凍結し、追加所有はmainが明示する。
  - E-S34-BG01 / 修正・引渡し（2026-10-22）: 両具象storeの新inventory照会を明示async witnessへ統一し、protocol既定unknownへ解決される回帰を修正。共有neverStartedは従来upload条件へ復元し、削除専用neverStartedForRemovalで全対象/派生版/backgroundを照合する。targeted02は16宣言47展開成功/skip0。candidate02の288入力で全Unit560宣言/913展開成功（空template1を除く有意味912）、29skip/失敗0。新2suiteは14宣言45展開成功。実行中・最終現物の入力変化0、runtime/compiler/analyzer診断各0。
  - E-S34-BG01 / 実SDK: 専用gateでBackgroundRemovalTerminalTestsの1宣言1実行成功/skip0。実suspended task1→native resume拒否（要求1/受付0）→実cancel callback1→ManagedUploadSource.finishと自身のFD閉鎖実測1→ownerClosed commit→exact lease解放→stopped→通常modelの明示リスク破棄→実MOV unlink/SQLite再open履歴1、実session invalidation1/forwarder joinを確認。別原本とupload copyは保持、Photos呼出0。strict permit/Mac notExecutedは注入であり、実network・SDK所有全FD・通常cleanup成功へ昇格しない。
  - E-S34-BG01 / 最終回帰: generic iOS署名なしbuild、通常Connection/Library/撮影UI6件、専用metadata UI1件と再open1件が成功。現288入力のmetadata-only実HTTPも1件成功/skip0、実2要求/媒体0byte/新確認・ACK0、8必須観測・pre-rescue残留0・全thread join・子exit0/0・signal0・秘密削除・設定/source/deps不変。checkpoint a97713f1321d44d30809139c3108f3d5cd9961087f09e118f75dcdcfb9d2ce04。CF既存原本照合1成功/seed1skip、元MOV digest・reader0と開始時設定67bytes/hashを保持。厳密P2監査4失敗は未解決のまま、今回の通常UI成功と区別する。
  - E-S34-BG01 / 証拠・残件: [証跡manifest](evidence/20261022-removal-terminal/archive-manifest.json)、[main最終確認](evidence/20261022-removal-terminal/s34-terminal-main-final-review-03.json)、[実SDK観測](evidence/20261022-removal-terminal/s34-terminal-sdk-main-review-01.json)、[HTTP最終確認](evidence/20261022-removal-terminal/s34-terminal-metadata-final-02-main-review.json)。mainが13file差分と修正6fileの全差分/所有を確認し、旧失敗版を保全して全コード所有を解除。全task receipt集合とhash前inventoryを同writerの最終unlinkで再構築し、未知/旧source/再利用task/同operation複数attempt・活動中自動停止は保守的拒否。通常cleanup・Photos/複数操作・正式proofは未達のためS34全体はblocked。未検証の新コードは残さずM02〜06/H01へ進む。
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
  - 再開・完了（2026-10-18、独立validation差戻し）: 上記現在の再開点のP1/P2を修正し、標準構成・新規DerivedDataで全Unit374宣言/510展開＋通常撮影UI3件成功、既存17skipを別記。generic iOS build成功、223入力一致。保存後処理と次RECを分離し、実FD・再open・遅延/失敗/離脱の回帰も成功した。E-S41-VFIX-01、`evidence/20261018-validation-fixes/`。過去の実装/成功/失敗証拠は保持し、実機/全体受入へ昇格しない。
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

- [ ] Status: blocked
  - 再開/独立部着手（2026-10-20）: 明示implementに従いStart=N01の描画分離・資材/世代契約・既知入力の実描画試験を先行する。S47の未回答ISO判断は同taskだけへ保持。通常Rec.709変換と画面接続は適合標準資材待ちであり、独立部の成功で全体doneにしない。
  - 保全/所有: 開始git clean。App/Unit/UI/project・関連docs・steeringの証跡外240fileをhash付きで `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-di-20261020-wa275djf/baseline/` へ保全。mainはtasklist/新規証跡/構成確認/検証実行/最終diff、worker `s48_render` は新規 `FrameRelay/Platform/Render/CaptureDisplay*.swift` と `FrameRelayTests/Platform/Render/` のみを単独所有する。既存Native/Preview/Factory/project/storeと旧証跡は変更しない。他者の変更を戻さない。
  - substatus / 着手時: 描画分離・資材/世代契約・既知入力試験=着手、標準資材適合/実Log変換/通常画面接続=未実装・資材待ち、実機品質=未確認。生成テストcubeは技術試験専用で、標準Log→Rec.709成立やFR-02受入の証拠にしない。
  - 初回検証（s48-test-01）: 新規DerivedData/Debug/確認済みiOS27 Simulatorでexit65・0件実行。新試験の入れ子 `#require` がrecursive expansion、同様のmacro内呼出にcompiler warning5件。本体3fileの診断なし。失敗版4source/224入力hash/ログ/xcresultを保全し、test helperを事前letへ展開して意味を保持した。再度新規DerivedDataのs48-test-02で同じ対象が成功。失敗を成功件数へ含めない。
  - substatus / 終了時: 描画分離/資材・世代契約/技術fixture実描画/関連自動検証/main確認=完了。標準資材適合/実Log変換/通常capture・UI接続=未実装・保留、実機品質=未確認。通常Native/Preview/Factoryは変更しておらず、生成cubeを製品へ供給しない。所有は上記worker4file、document_author `s48_docs` のarchitecture表示境界、mainのsteering/新証跡だけ。
  - 実装境界: 技術fixtureの由来/版/用途/hash/0…1・opaque alphaと入力タグを照合し、Core Imageで別の即時CGImageへ描画する。出力はtechnicalFixture固定で、writerへ戻すpixel/sample buffer APIを持たない。原本入力と明示された未変換入力だけを読取り、表示context/連番と内部epochで旧世代・逆順・context往復/同context再有効化・停止後の旧結果を拒否する。保持は処理中1＋置換待機1。producerの同時書込防止と実SDK終端は別契約であり、stopを描画完了通知と扱わない。
  - E-S48-01 / 検証構成・結果: Xcode27.0(27A266a)/Swift compiler6.4、実在project/scheme/test plan `FrameRelay`、Debug、Swift5/iOS27.0/既定MainActor、App/Unit/UI3targetを再確認。`-destination 'platform=iOS Simulator,id=DFE46693-E8DD-4814-8957-4F327699F719' -parallel-testing-enabled NO -collect-test-diagnostics never` のtest-02でCaptureDisplayTests7宣言/10展開＋ExplorationCoordinatorTests12/14＋通常撮影UI1成功、失敗/skip/runtimeWarnings/compiler/analyzer0。別DerivedDataの `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` も成功。全コマンド・設定・結果・224入力hash・初回失敗は証跡へ保持し、両最終run/現物の入力一致を確認。Simulatorの通常製品設定hashもcontainer移転後の相対pathで一致した。
  - E-S48-01 / 受入対応と限界: 実画素identity/赤青swap、全入力byte/両attachment mode不変、出力即時detach、Log1/2の個別拒否、信号/不正cube/hash/二重変換拒否、1＋1置換・古い順序・停止/世代往復を確認した。既存D02拒否と通常画面の未対応表示・REC阻害/Library復帰は回帰成功。技術fixtureの成功は標準Log変換、実撮影原本の非焼込み、画角・色・負荷・FR-02受入を証明しない。
  - 標準資材の読取再確認（2026-10-20）: 公式FCPガイドはLog1/2それぞれのRec.709 3D LUTを説明するが実体/版/利用条件/入力域は今回も未取得。Developer Downloadsへの今回の未認証経路はSign In画面へのredirectを観測し、認証後一覧は未閲覧。全取得経路で認証必須とは断定しない。一般的なSDK色プロパティとLogTransferFunction設定だけを標準変換保証にせず、ACESのLog1→ACES IDTもRec.709/Log2/Apple表示LUTの代用として採用しない。一次資料URLと不足項目を証跡へ記録する。
  - V-REVIEW / 再開条件: mainが4source/testの全diff・実I/O試験・CGImageだけの出力・未接続・224入力一致を確認し、architecture限定差分のdoc_reviewer指摘なし。既存保護対象/旧証跡/project/README/memoの変更なし、空白診断成功。S48は適合標準資材を確認して変換本体/通常表示へ実接続し、既知Log入力・非焼込み/二重変換・必要UIを検証してから全体doneを判定する。独立validationは代行していない。
  - Depends: Start＝N01（描画分離・既知入力試験準備）、変換本体はS26Aの当該適合資材取得。Finish＝S41,S26A（当該入力適合資材取得）の実接続。着手時に独立部分と接続部分を別substatusで記録し、接続まで満たす前はtask全体をdoneにしない。
  - Owner / Files: O-CAPTURE／`FrameRelay/Platform/Render/`、`FrameRelay/Platform/Capture/` の表示分岐、`FrameRelay/Features/Capture/` と対応test。
  - Done when: 由来／入力適合済み標準変換を表示経路へ実装し、記録経路へ流さず、確認状態と分離。
  - Verify: 既知入力の実変換・描画、非焼込み境界・二重変換拒否。品質はA05。
  - Stop: 資材不足、未変換画像／独自係数でRec.709完成表示。

### S49 REC・保存状態を媒体gateへ独立接続

- [ ] Status: blocked
  - Photosの最終SDK開始へ独立着手（2026-10-25）: 既存同capture admissionと同writerを入力に、writer→単回capture許可→共有操作claim→同期PhotoKit登録、実retained FDの最終fingerprint照合を実装中。同live intent/useのheld待機、lock外wake、fixed live childだけの開始前取消、二coordinator重複SDK禁止を接続する。既受理PhotoKitは取消handleがなく実completionを待つ。SDK/必要検証前はこの部分もdoneとせず、全S49/全媒体/通常strict正開始の未完を維持する。所有は `photo-final-sdk-ownership.json` と `photo-final-sdk-test-ownership.json`。
  - 部分引渡し完了（2026-10-23）: E-S49-RESUME-01の同期許可契約・配線と必要な非実機検証を完了。通常画面回帰24は5成功/旧cleanup理由期待値1失敗を保持し、identity条件の全文一致だけへ更新した25で当該1成功。他の5caseとP2 assertionは不変。UI後26は2成功/seed1skip、27は整理済root1成功/seed1skip、最終28はgeneric iOS署名なしbuild成功。25〜28は最終294入力前後一致、compiler/analyzer診断/runtimeWarnings 0。全Unit22はApp/Unit/project同一で有意味963成功/31skip、最終UIとの差1箇所は実行版照合に記録。395入力をDI-SOURCE-20261023-01へ束縛し、原本/manifest/readerの保全を確認。全S49は下記native正開始/全媒体のFinish不足でblocked。証跡は [S49同期許可](evidence/20261023-capture-resume/README.md)。
  - 独立再開（履歴: 2026-10-23）: S31修正のcode/test所有解除後、N01/S41/S23部分引渡しを入力に同期許可契約を先行する。worker `cleanup_connection` はCaptureMediaAdmission/BackgroundMediaPorts/BackgroundMediaCoordinator/BackgroundMediaSessionと専用新test・既存3背景testのprotocol適合だけを単独所有する。許可発行→await後の実action直前に同lockでrevision/hold/単回性を再判定し、async処理をlock内へ置かない。通常native正送信はnotExecutedを維持。関連単体/競合/非送信実SDK・通常撮影UI/buildを確認し、この契約・配線だけを部分引渡しする。全S49の実SDK正開始・全媒体・実通信RECの未成立は維持する。
  - 部分検証 E-S49-RESUME-01（2026-10-23）: 元admission/origin/revision/単回性を同NSLockで実action直前に照合し、throw/hold/ABA後の旧許可を拒否する必須port契約を追加。App4/既存test3/新test2の差分をmain確認。compile失敗18のactor準拠を空extensionへ分離し、成功19の試験Thread由来QoS警告3は2Threadを待機側のuserInitiatedへ揃えて解消した。最終20は関連28宣言44展開成功、21は実背景SDK3成功、22は全Unit609宣言578成功/31skip・964展開（有意味963）成功。294入力前後一致・compiler/analyzer診断/xcresult runtimeWarnings 0。実nativeはidle/holdでも偽strict permitを拒否し、一度もresumeしないsuspended列挙/実cancel callback/invalidation・自身source終端を確認。正の実SDK開始/全媒体停止/実通信RECの証明にはしない。通常UI/最終build・保全照合は後続。
  - 部分引渡し E-S49-01（2026-10-22）: 同期admission・owner別REC／保存／復旧wait、token発行前の取消可能なlocal-stop preflight、同writer exact停止と製品Compositionを接続。保存応答失敗より先着したfile／unconfirmedの待機漏れはtest-firstで再現後に修正し、旧save drainのdeferもownerで分離した。保存file実returnまで待機し、postSave hash/bind/一覧更新は次RECを止めない。既存pause/cancel・重畳waitと未知旧ownerを保持する。
  - E-S49-01 / 最終検証: candidate03の同279入力で `s49-unit-03` 525成功宣言／841成功展開（空template1を除く有意味840）・既存/opt-in25skip、`s49-ui-01` 通常撮影3成功、`s49-ios-build-03` generic iOS署名なしbuild成功、`s49-cf-verify-01` 既存seed検証1成功／seed1skip。失敗／runtime/compiler/analyzer診断0、全run前後と最終現物の変更0。新3suiteは16宣言25展開（既存postSave2caseも強化）。CF原本digest／reader0を保持し、UIによる設定JSONのキー順差だけを退避後、開始67bytesのhashへ復元した。mainが全12fileと追加3file差分・所有を確認。実行版／再現失敗／raw要約／版照合は `evidence/20261022-capture-media/`、raw xcresult/DerivedDataは開始rootに保持。
  - 残件／再開条件: 単回同期許可の契約・port配線はE-S49-RESUME-01で実装/検証済み。通常strict dispatchとnative正開始での当該許可消費、S25等を含む全媒体producerの実停止、実通信中RECの必須Verifyは未成立。SDK suspended cancelや注入終端の成功を全媒体実停止へ昇格しない。該当adapter・producerと実試験を接続する時に再開し、独立S27をこの全体未完の完了待ちにしない。
  - 差分レビュー／再現（2026-10-22）: candidate01は全Unit524宣言839展開成功・25skip、generic iOS build成功（279入力変化0）。ただしmainの差分確認で、recordingEndedの永続応答失敗より先にfile／終了未確認通知を受けた場合、旧ownerのsaving待機を消費できない分岐を発見した。追加試験だけを先行した `s49-order-red-02` は9宣言中8成功/1失敗、13展開成功/2失敗、診断0で両順序の漏れを再現。旧contextだけをactual return後に終了する修正と、条件付きtest closureのSendable警告1件の解消を進める。成功版・意図した失敗版を `evidence/20261022-capture-media/` へ保持する。
  - 着手（2026-10-22）: StartのN01/既存CaptureLifecycle/媒体gate契約と、S41保存境界・S23独立実終端の部分引渡しを受領。通常strict通信未成立は閉鎖したまま、同期admission hold→context/visit/nonce固定preflight→同writerのrecording/saving/recovery wait→exact local終端の独立接続を先行する。S23全完了・AF/ND/表示資材は新たな開始条件にしない。
  - 所有: worker `library_ui_fix`へ既存ProductCaptureCoordinator/ProductCaptureFactory/ProductComposition/BackgroundMediaCoordinator/ProductBackgroundMediaFactoryと、専用ProductCapturePostSaveTests/BackgroundEventDrainTests/ProductBackgroundCompositionTests、新規CaptureMediaBoundaryPort/CaptureMediaAdmission/ProductCaptureMediaBoundary/ProductCaptureMediaBoundaryTestsだけを単独割当。mainはsteering/証跡/凍結後実行/最終diffを所有し、S23 SDK/file・共有store/Domain・View・projectは凍結。既存dirtyと他者変更を戻さない。
  - 実装境界: 最初のawait前にholdし、local-stop待ちはLifecycleのrecording token発行前に置く。preflight中STOP/leaveはそのticketだけを取消し、実start未送信のまま実終端待ちへ入らない。STOP受付だけでwaitを解除せず、録画実終端/確実な未開始とfile/save結果応答までowner別に保持する。postSaveのhash/bind/refreshは次REC条件にしない。旧context/snapshotの遅延応答が新ownerのwaitを消さず、pause/cancelと他waitを保持する。
  - 局所残件の保持（履歴: 2026-10-22。同期契約の先行実装は上記E-S49-RESUME-01へ更新）: SDK terminal→自身source実close→ownerClosed commit→exact lease actual release後だけ当該attemptのstoppedを記録する。copy中/attach gap/未知source/再openのlive owner不在は停止成功にしない。最終SDK resumeと同期holdの排他契約、未接続S25等の全媒体実停止・実通信中RECは未成立を残し、suspended cancelや注入試験だけで全S49をdoneにしない。
  - Depends: Start＝N01・既存CaptureLifecycle／媒体gate契約。Finish＝S41のREC／保存境界、S23の実通信adapter。AF・ND・表示変換資材・Photosの完了は不要。
  - Owner / Files: O-CAPTURE／`FrameRelay/Application/Capture/` のcoordinator、O-IOS-BI／`FrameRelay/Application/MediaIO/`、O-COMPOSE／`FrameRelay/Composition/`（ファイル別直列）、対応integration tests。
  - Done when: RECで全媒体の実通信を停止し録画中・保存／異常終了処理中は再開せず、全条件と本人意思で再開する。Mac ACKをREC開始条件にせず、Mac既開始処理を止めない。
  - Verify: 実通信中のREC境界・保存完了前後・回線離脱重畳・停止／取消保持・解放callback、V-CAPTURE／V-SERVER。端末負荷はA11／A12へ残す。
  - Stop: SDK停止受付だけで実停止扱い、保存前再開、S4Vや資材待ちを本接続の前提にする。

### S4V 撮影・全体接続の集約レビュー

- [ ] Status: blocked
  - 着手（2026-10-22）: mainがS41〜49の利用可能snapshotと最終288入力の回帰を集約する。所有は本tasklistと集約証跡のみ、App/Testsは凍結。
  - 部分集約（2026-10-22）: S41〜46の独立経路、S48描画候補、S49のREC/保存owner・実SDK終端/lease解放をmain確認。最終288入力で全Unit913展開成功/29skip、通常撮影を含むUI6件とmetadata UI1件、generic iOS build、既存原本/設定保全が成功。REC前停止は本人pause/cancel・重畳waitを保持し、Mac ACKを条件へ追加していない。S47の未回答ISO policy=nil、S48標準資材/通常表示、S49 strict resume/全媒体producer・実通信とREC/Mac継続、厳密AX4失敗を未達としてblocked。撮影/音声/色/AF/ND/倍率・負荷の実機品質はA01〜11へ残す。証拠: evidence/20261022-stage-aggregation/stages-aggregation-final-02.json。
  - Depends: S42,S43,S44,S45,S46,S47,S48,S49。
  - Owner / Files: main＋O-COMPOSE／本tasklist（統合コードと証拠はレビュー対象。変更は該当所有taskを再開）。
  - Done when: S49の独立接続証拠と、解析／表示／音声／記録の独立経路、起動・復帰UI・必須自動検証・レビューを集約。本集約の未完了は既に独立成立する通信接続等を止めない。
  - Verify: V-CAPTURE／V-UI、REC／保存で通信実停止、次REC、Mac処理継続。実機品質はA01〜A11。
  - Stop: 通信ACKをREC条件に追加、未接続・未実装を実機未確認だけで隠す。

### H01 実機引渡し票・未接続一覧を版へ束縛

- [x] Status: done
  - 着手（2026-10-22）: M02〜M06を凍結してmainが全DV母行/35軸更新と最終source bindingを反映する。所有は本tasklistと引渡し証跡だけ。App/Tests/全docs/support helperは凍結し、実機実施・独立validationは開始しない。
  - 準備完了（2026-10-22）: 全18票を76母行へ展開し、全79AC/CF11/BI34/DI18と旧C01〜19/B1〜7/U01〜05/V01〜16を双方向対応した。6旧親行・79行順序と非IAR列を保持、35行のI/A/Rだけを具体化、全D0/全A01〜18 pending・PRD受入未評価を維持。76は実行件数ではなく、全パラメータ/実組合せ/有限反復/品質・対象別許可はQ01で束縛する。
  - 版・検証: [H01-SOURCE-01](evidence/20261022-device-handoff/source-binding.json)へHEAD/dirty差分hashと全389入力（App/Unit/UI/project288、support93、永続6文書、requirements/design2）の現物snapshotを固定。層別実行証拠は現288/旧publication279/旧strict260を分離。main/読み取り調査に指摘なし、[準備版静的照合](evidence/20261022-device-handoff/h01-candidate-static-01.json)で欠落ID/重複/ローカルリンク切れ/source差分0・diff-check成功。実装/実機/製品受入の完了ではなく、引渡し準備だけdone。
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
| M02／done | `docs/functional-design.md` | N00、該当実装の更新時snapshot／同implement | U1／U2／U4、F1〜F5のズーム／権限／整理／履歴と不明遷移、機能設計T01〜T21の先行試験／実機残件を整合。U3の背景・携帯状態同期・個別失敗続行はbackend確定事項を反映し未合意へ戻さない。2026-10-22、機能遷移/試験と確定U3・削除表示/Photos権限/ズームを同期。PRD79対応表は完全不変、T01〜21/既存成果保持、ローカル10リンク切れ0・diff-check成功。main全差分とdoc_reviewer確認、再登録ACK/局所無期限保留のP2追記後に最終指摘なし。最終sha4337f594…de8781、証拠 `evidence/20261022-stable-docs/m02-main-review-01.json`。文書同期のみ、App279/support93入力不変・追加build/testなし。S28/S34-BG01後の最小追加を専門/mainレビューし指摘なし、sha8b600563…428413・App288/support93不変・他文書変更0。PRD79表/T01〜21/旧Photos詳細保持、追加証拠 `evidence/20261022-stable-docs/m02-post-main-review-01.json` |
| M03／done | `docs/architecture.md` | N00、S11／S13／S21等の判断が生じる都度／同implement | D01非依存共通store、単一writer／原本／lease、削除管理記録、Photos限界、暫定設定、候補接続と実採用、4軸と層別検証。内部方式採用は実装証拠付き、実機能力は未確認を保持。2026-10-22、同writer CoreData/SQLite採用・AtomicFile比較、実FD/lease/削除最終境界、S23/S49/S27・未接続/4軸を同期。main全差分/doc_reviewer確認、採用endpoint表現P3を1セル修正後に最終指摘なし。A1〜11/旧Photos節/既存撮影詳細を保持、ローカル12リンク切れ0・diff-check成功。sha9c356262…bb6c92、証拠 `evidence/20261022-stable-docs/m03-final-main-review-01.json`。App279/support93不変・追加build/testなし。新S28等の成果後は必要な最小加算を行う。S28/S34-BG01後の設計最小加算を専門/mainレビューし指摘なし、sha9e46899d…5a90・App288/support93と他文書不変。A1〜11/撮影/Photos詳細保持、追加証拠 `evidence/20261022-stable-docs/m03-post-main-review-01.json` |
| M04／done | `docs/repository-structure.md` | N00、各taskの実ファイル確定時／同implement | 2026-10-20、document_author s48_docsが同文書だけを同期。実在配置/接続状態/所有/試験媒体/履歴責務を対応。15ローカルリンク切れ0、主要App35path/代表test path実在、未作成7path/表構造/禁止規則保持を確認。main/doc_reviewerの指摘2件を修正後、最終指摘なし。証跡 `evidence/20261020-m04/`。コード/構成移動なし。2026-10-22のS23/S28/S31/S32〜34/S49等の実在配置/責務/接続状態へ再同期し、107 Swift参照・15リンク・表/柵・main全差分/専門レビュー指摘なし。sha4645b907…01025、App288/support93と他文書不変、追加build/testなし。旧M04履歴を保持、追加証拠 `evidence/20261022-stable-docs/m04-post-main-review-01.json` |
| M05／done | `docs/development-guidelines.md` | N00／同implement | 直接依存だけの保留、4段階、軽微可逆裁量、4軸・レビュー証拠、分割本体doneと製品DoD、まとめた実機票を反映。必須検証／品質事前合意／実データ許可／coverage方針維持。2026-10-22、確定通信/削除/Photos・暫定policy・検証環境と本体Done/製品DoDを同期。main全差分/専門レビューのP3用途主語を1段落で修正し最終指摘なし。sha c5f9c63b…fd7f6、14リンク正常・diff-check成功、必須チェック/品質G3/実データ/coverage方針と他文書/App288/support93保持。文書のみ追加build/testなし、証拠 `evidence/20261022-stable-docs/m05-final-main-review-01.json` |
| M06／done | `docs/glossary.md` | N00／同implement | 原本本体／管理記録、履歴≠ゴミ箱、削除成功／要照合、追加権限／読取照合限界、未実装／探索／未接続／実装済み実機未確認、暫定／採用値、4軸／局所保留を他5文書と照合。2026-10-22、原本/管理記録・削除表示・同期・写真キー/完全identity・用途別lease/回収・登録別ACK・内部採用・DI4状態/4軸を同期。main全差分/専門レビュー指摘なし、sha512044c2…b95fed、94参照リンク/11参照先/41節・表/柵・diff-check正常。旧52見出し/要求ID/S45詳細・未合意を保持、App288/support93と他5文書不変。証拠 `evidence/20261022-stable-docs/m06-main-review-01.json`、追加build/testなし |
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
| FR-02 | AC-FR-02-01 | 固定Rec.709表示・非焼込み | P06/P12;CF-05 | EC:表示拒否境界,E-S48-01 | S48 | dep(S48)＋対応A/Q01 | O-CAPTURE | 表示専用CGImage/技術描画のみ実装、標準Log変換・通常接続は未実装 | E-S48-01:生成cube実描画/入力全byte・タグ不変/二重変換拒否 | D0 | 標準資材・実原本非焼込み・FR-02未受入 | DV-05 |
| FR-02 | AC-FR-02-02 | 確認状態分離・描画/録画品質 | P06/P12;CF-05 | EC:表示拒否境界,E-S48-01 | S48,S4V | dep(S48,S4V)＋対応A/Q01 | O-CAPTURE | 未接続の表示専用基盤・1＋1保持/世代失効のみ実装 | E-S48-01:旧世代/逆順/停止失効・既存D02拒否/通常UI回帰 | D0 | 標準表示と記録の両立・品質・負荷未受入 | DV-05、DV-11 |
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
| FR-10 | AC-FR-10-01 | 原本/軽量版再生・複数結果/単数操作 | P08/P09/P21,T15/T20;CF-01/08,BI-15/33 | ES,EB,E-S13/14/15/25 | S14,S15,S25,S28,S34 | dep(S14,S15,S25,S28,S34)＋対応A/Q01 | O-LIBRARY | 原本製品再生と固定軽量版の実I/O・canonical wire・既存登録の明示metadata同期/動画別投影を接続、条件付き複数容量整理を接続、通常軽量版/転送・Photos複数操作UIは未接続、P2厳格AX4件はE-P2-20261022-FIXで解消  明示新登録と旧保存原本identityの発見/remote専用一覧を部分接続。 | E-S15/E-S25に加えE-S27-01。E-S34-01単数破棄/履歴、旧UI14成功/strict4失敗は履歴保持。E-P2-20261022-FIXで通常17＋未登録初回1・strict6/最大字4/fresh作成/全Unit/UI後照合/build成功。E-S28-01:既存登録の明示metadata1page/動画別表示、Unit新21宣言27展開、専用UI1/reopen1/実HTTP1成功（metadata2要求/媒体・確認・ACK0）。 E-S34-CLEANUP-01: 通常3対象/2成功1未実行・同batch再起動、結果AX通常/最大各1成功。  E-S28-NEW-01/INVENTORY-01: 新登録関連31宣言47展開・inventory関連36宣言75展開、隔離実SDK新登録/namespace認証→32+1件/再open33件を確認（媒体/確認/ACK0）。専用UIは検証中。 | D0 | 部分証拠、実機受入未評価 | DV-14、DV-16、DV-17 |
| FR-10 | AC-FR-10-02 | 保存中断再起動の4分類 | P08/P09/P21,T15/T20;CF-01/08,BI-15/33 | ES,EB,E-S11,E-S12 | S12,S14 | dep(S12,S14)＋対応A/Q01 | O-LIBRARY | 通常REC/STOPから共通保存/復旧/分類/一覧へ接続済、実撮影の正常/部分/不明/失敗は実機未確認 | E-S12/E-S41保存境界、E-S49-01先着/後着終端と次REC、全Unit841展開/通常撮影UI3成功 | D0 | 部分証拠、実機受入未評価 | DV-02 |
| FR-10 | AC-FR-10-03 | 整理後offline・再接続等非強制 | P08/P09/P21,T15/T20;CF-01/08,BI-15/33 | ES,EB（実再生なし） | S14,S32,S34 | dep(S14,S32,S34)＋対応A/Q01 | O-LIBRARY | 条件付きの通常複数整理開始/実unlink/通常一覧/原本なしを接続、通常軽量版UIと正式証拠producerは未接続 | E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合。接続/Photosを条件へ追加せず、offline製品操作は未確認 E-S34-CLEANUP-01: 通常UI/再起動と未取得offline不可表示、元binding/hash保持を確認。 | D0 | 部分証拠、実機受入未評価 | DV-14、DV-17 |
| FR-11 | AC-FR-11-01 | 指示原本の転送・全内容検証 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB,EI,E-S24 | S24,S24I | dep(S24,S24I)＋対応A/Q01 | O-IOS-BI/O-SERVER | 登録/内容に束縛したserver受信・独立最終全read・証拠/job同commit実装済、iOS転送未接続 | E-S24:guard12/pytest126/実HTTP20＋別process再起動5成功、合成16777473byte全比較 | D0 | server保存の部分証拠・製品転送/実G2B/G2C/実機未確認 | DV-12 |
| FR-11 | AC-FR-11-02 | 回線離脱待機・検証不明原本保持 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB:規則のみ,EI:隔離 | S23,S24I | dep(S23,S24I)＋対応A/Q01 | O-IOS-BI/O-SERVER | Wi-Fi/本人意思の規則・同writer要求/背景task/実SDK終端を実装、通常strict転送と再開UIは未接続 | E-S21/E-S23-01/E-S49-01の重畳wait/本人停止保持/未知source保持。実基礎回線切替は未実施。E-S28-01:既存登録の明示metadata1page/動画別表示、Unit新21宣言27展開、専用UI1/reopen1/実HTTP1成功（metadata2要求/媒体・確認・ACK0）。 | D0 | 部分証拠、実機受入未評価 | DV-12 |
| FR-11 | AC-FR-11-03 | 結果受信中断・HTTPとcommit分離 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB,EI,E-S21,E-S24 | S21,S24I | dep(S21,S24I)＋対応A/Q01 | O-IOS-BI/O-SERVER | 端末同writerの証拠/要求/commit照会とserver保存証拠実装済、端末への実受信commit未接続 | E-S21:実disk26新規/全Unit211有意味、E-S24:commit応答欠落/境界rollback/再照会を含む126成功・実HTTP25成功 | D0 | 両永続境界の部分証拠・製品転送/受信統合未確認 | DV-12 |
| FR-11 | AC-FR-11-04 | 複数固定集合・動画別結果 | T03/T08/T09/T10/T11/T12;BI-01〜06 | EB:規則のみ,EI:隔離,E-S21 | S23,S24I,S28 | dep(S23,S24I,S28)＋対応A/Q01 | O-IOS-BI/O-SERVER | 固定batch/動画別requestを同writerへ永続化・実転送/UI未接続 | E-S21:両disk固定集合とrequest再open成功 | D0 | 集合/結果保持の部分証拠・実通信/表示未確認 | DV-12 |
| FR-12 | AC-FR-12-01 | 保存検証後生成・原本保持 | T13/T14/T16;BI-16/17/32 | EB＋E-S26J-ACCEPT | S26J,S26 | dep(S26J,S26)＋対応A/Q01 | O-SERVER | 証拠起点候補/job実装、標準変換未接続 | 実store/worker160case成功、原本保持/未公開fixture確認 | D0 | 周辺処理の部分証拠、実変換未達 | DV-13 |
| FR-12 | AC-FR-12-02 | 実Rec.709・媒体特性/日時保持 | T13/T14/T16;BI-16/17/32 | EB:変換前提契約のみ | S26 | dep(S26)＋対応A/Q01 | O-SERVER | Log別適合資材・actual-log-parser/正式変換は未実装、S26J候補/job周辺だけ実装 | E-S26J-ACCEPTとE-S27-01は技術fixtureの候補/配布証拠。E-S26A-01で資材/入力域不足を記録 | D0 | 正式変換の製品結合は未達、媒体品質・実機受入は未評価 | DV-13 |
| FR-12 | AC-FR-12-03 | 旧compress-only非代用・差替条件 | T13/T14/T16;BI-16/17/32 | EB:変換前提契約のみ | S26,S27 | dep(S26,S27)＋対応A/Q01 | O-SERVER | 旧compress-only非代用と候補/公開分離・全必要ACK gateを技術実装、標準変換は未接続 | E-S27-01:隔離backend170node230case/実HTTP1case成功、全量前AVPlayer/確認commit/exact lookup/実解放/失効ACK後公開。formal proof/通常UIは未接続 | D0 | 周辺規則の部分証拠、正式映像/設定変更の製品結合未達 | DV-13、DV-14 |
| FR-13 | AC-FR-13-01 | 単数途中実再生＋明示確認 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER,E-S20-04,E-S25 | S25,S27 | dep(S25,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 実再生token/本人action/同writer確認/実wireをfixture経路で接続、正式映像と通常確認UIは未接続 | E-S27-01:隔離backend170node230case/実HTTP1case成功、全量前AVPlayer/確認commit/exact lookup/実解放/失効ACK後公開。formal proof/通常UIは未接続 | D0 | 部分証拠、実機受入未評価 | DV-14 |
| FR-13 | AC-FR-13-02 | 受付と確認commit・不明 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER（実再生/ACKなし）,E-S21 | S21,S27 | dep(S21,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 確認＋outbox/完全mutation exact照会・応答欠落/reopenを実装、通常本人確認UIは未接続 | E-S21のdisk faultに加えE-S27-01の応答置換503→exact lookup。commit前未記録action非生成 | D0 | 部分証拠、実機受入未評価 | DV-14 |
| FR-13 | AC-FR-13-03 | 失効前V1維持・offline整理 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER（実再生/ACKなし） | S27 | dep(S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 失効前V1維持/候補分離とoffline整理規則・条件付き通常整理UI/実unlinkを接続、正式映像producerは未接続 | E-S27-01:隔離backend170node230case/実HTTP1case成功、全量前AVPlayer/確認commit/exact lookup/実解放/失効ACK後公開。formal proof/通常UIは未接続。E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合 E-S34-CLEANUP-01: 保存検証/有効確認の最終再判定と、確認後の失効対象拒否/別対象続行を確認。 | D0 | 部分証拠、実機受入未評価 | DV-14、DV-17 |
| FR-13 | AC-FR-13-04 | 失効commit後全必要ACK・非復活 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER,E-S21,E-S22,E-S22C | S27,S28 | dep(S27,S28)＋対応A/Q01 | O-IOS-BI/O-SERVER | 失効commit/owner実終端/ACK outbox/登録別全必要ACK公開gateを技術結合、製品external/recovery全ownerと通常UIは未接続  別storeの有効残存資格情報を保持する明示新登録と新namespaceを接続、旧確認/必要ACKの自動移植なし。 | E-S27-01:隔離backend170node230case/実HTTP1case成功、全量前AVPlayer/確認commit/exact lookup/実解放/失効ACK後公開。formal proof/通常UIは未接続。E-S31-02 Photos終端proofも部分引渡し。E-S28-01:既存登録の明示metadata1page/動画別表示、Unit新21宣言27展開、専用UI1/reopen1/実HTTP1成功（metadata2要求/媒体・確認・ACK0）。  E-S28-NEW-01: UUID/登録空条件・旧bytes/create-only/current孤立資格情報拒否・応答不明/並行を確認。INVENTORY-01は新登録で旧原本identityだけ取得し旧確認/ACKを生成しない。 | D0 | 部分証拠、実機受入未評価 | DV-14、DV-15 |
| FR-13 | AC-FR-13-05 | 初回/V2/失効後失敗の区別 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER＋E-S26J-ACCEPT | S26J,S27 | dep(S26J,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 初回有効版なし/旧確認維持/失効後非復活と候補失敗を技術実装、正式変換と通常UIは未接続 | E-S27-01:隔離backend170node230case/実HTTP1case成功、全量前AVPlayer/確認commit/exact lookup/実解放/失効ACK後公開。formal proof/通常UIは未接続。E-S28-01:既存登録の明示metadata1page/動画別表示、Unit新21宣言27展開、専用UI1/reopen1/実HTTP1成功（metadata2要求/媒体・確認・ACK0）。 | D0 | 部分証拠、実機受入未評価 | DV-14 |
| FR-13 | AC-FR-13-06 | 同一映像再取得/切断非失効 | T03/T15/T17/T18/T19/T22;BI-18〜26 | EB,ER,E-S25 | S25,S27 | dep(S25,S27)＋対応A/Q01 | O-IOS-BI/O-SERVER | 同版再取得/不通だけで失効せず、失効後旧token/新GET拒否を実wire技術結合。既存登録の媒体なし明示同期・動画別表示を接続、明示新登録/remote保存記録は部分接続、通常媒体UIは未接続 | E-S25固定版I/Oに加えE-S27-01実HTTPの版/単回GET/失効後非復活。実回線は未確認。E-S28-01:既存登録の明示metadata1page/動画別表示、Unit新21宣言27展開、専用UI1/reopen1/実HTTP1成功（metadata2要求/媒体・確認・ACK0）。 | D0 | 部分証拠、実機受入未評価 | DV-14 |
| FR-14 | AC-FR-14-01 | 有効証拠と手動整理・写真不要 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則,E-S21 | S32 | dep(S32)＋対応A/Q01 | O-ORIGINAL/O-STORE | 同一保存証拠/有効確認を各unlink直前に再判定するcoreと条件付き通常複数整理を接続、正式証拠producerは未接続 | E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合 E-S34-CLEANUP-01: 適格2本/証拠不足1本の固定集合、写真非条件/外部保持を確認。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-14 | AC-FR-14-02 | 不明/欠落/失敗/失効は不可 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則,E-S21 | S32 | dep(S32)＋対応A/Q01 | O-ORIGINAL/O-STORE | 未知/欠落/失敗/失効/別内容を拒否する同writer最終guard・実FD照合と条件付き通常UIを接続 | E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合 E-S34-CLEANUP-01: hash中/最終writerで関連証拠/登録/ABA変化を拒否し、別動画更新だけを許容。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-14 | AC-FR-14-03 | offline有効記録で整理 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32 | dep(S32)＋対応A/Q01 | O-ORIGINAL/O-STORE | 最後の有効記録で条件付き通常整理を実行し、再接続/再生/Photosを条件に追加しない。正式証拠producerは未接続 | E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合 E-S34-CLEANUP-01: 資格保管/接続に依存せず実unlinkと通常結果を確認。実回線offlineの実機受入は未実施。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-14 | AC-FR-14-04 | 外部現在存在を保証しない | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32,S34 | dep(S32,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | 通常確認UIで最後の有効記録と外部現在存在の非保証を表示、実外部消失試験は未実施 | E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合 E-S34-CLEANUP-01: 対象別の最終検証記録/不足理由、offline時の非保証/外部非削除を確認画面で照合。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-14 | AC-FR-14-05 | 実削除と記録一致・一覧保持 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32,S34 | dep(S32,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | actual unlink/result commitと条件付き通常整理UI/通常一覧/原本なし投影を接続 | E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合 E-S34-CLEANUP-01: 通常UIで適格2本の実不在・同目的/同batch成功・再起動後通常一覧を実diskと照合。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-14 | AC-FR-14-06 | 削除境界中断・要照合 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32 | dep(S32)＋対応A/Q01 | O-ORIGINAL/O-STORE | ローカルobserve-only復旧と要照合/動画別結果を通常導線へ接続、未実行自動削除なし | E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合 E-S34-CLEANUP-01: 予約済み/未処理の明示照合だけで元MOV hashと固定batchを保持、再unlinkなし。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-14 | AC-FR-14-07 | 複数動画別再判定・結果 | T03/T21;BI-27/29（旧は契約まで） | EB:整理証拠/順序規則 | S32,S34 | dep(S32,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | 固定複数batch/子intent/各対象直前判定/動画別結果を条件付き通常UIへ接続、正式証拠producerは未接続 | E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合 E-S34-CLEANUP-01: 通常3本選択の2成功/1未実行、選択後の固定集合/別対象保持/同batch再起動を確認。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-15 | AC-FR-15-01 | 手動写真保存・実登録・一時解放 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約,E-S31-01,E-S31-02 | S31,S34 | dep(S31,S34)＋対応A/Q01 | O-PHOTOS | 実PhotoKit/同writer/S25完全媒体接続済・終端proofから元use解放/失効接続済・通常保存開始未接続 | E-S31-01:実Photos登録/resource bytes/日時/音声/再生/解放、Unit/UI成功（合成）、E-S31-02:終端/使用権分離・実Photos両権限成功 E-S31-OWNER-01: 同exact使用権回収/owner実閉鎖後の遅延releaseを修正。旧8枝/決定的crash回帰、全Unit604宣言952展開(有意味951)/31skip、実PhotoKit許可拒否各2成功を確認。 | D0 | 下位処理の部分証拠・正式Rec.709/製品導線/実機未確認 | DV-16 |
| FR-15 | AC-FR-15-02 | 同撮影同版・連打/再試行非重複 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約,E-S31-01,E-S31-02 | S31 | dep(S31)＋対応A/Q01 | O-PHOTOS | 登録キー排他/意図exact/unknown非再追加/確定未追加の明示retryOf/fresh use実装済 | E-S31-01:連打/取消し/遅延終端/commit前後欠落/reopenで非再追加成功、E-S31-02:fresh意図拒否/不明と終端commit境界成功 E-S31-OWNER-01: 同exact使用権回収/owner実閉鎖後の遅延releaseを修正。旧8枝/決定的crash回帰、全Unit604宣言952展開(有意味951)/31skip、実PhotoKit許可拒否各2成功を確認。 | D0 | 重複防止の部分証拠・製品接続/実機未確認 | DV-16 |
| FR-15 | AC-FR-15-03 | 登録直後中断・写真側削除非復活 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約,E-S31-01,E-S31-02 | S31 | dep(S31)＋対応A/Q01 | O-PHOTOS | 追加結果/過去成功/現在存在を分離し中断後の再追加を抑止 | E-S31-01:実disk結果commit前後/reopen・限定/拒否/未発見保持成功、実notFoundは別identifier E-S31-OWNER-01: 同exact使用権回収/owner実閉鎖後の遅延releaseを修正。旧8枝/決定的crash回帰、全Unit604宣言952展開(有意味951)/31skip、実PhotoKit許可拒否各2成功を確認。 | D0 | 中断規則の部分証拠・実OS登録境界/本人写真削除後未確認 | DV-16 |
| FR-15 | AC-FR-15-04 | 回線離脱/復帰・整理順序非強制 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約,E-S31-01,E-S31-02 | S23,S31 | dep(S23,S31)＋対応A/Q01 | O-PHOTOS | 完全取得後local登録はWi-Fi非依存、取得/復帰gateはS23未接続 | E-S31-01:S25完全local媒体からSDK登録/解放成功、実回線切替は未実行 | D0 | local部分証拠・実Wi-Fi/条件付き取得再開/製品接続未達 | DV-12、DV-16 |
| FR-15 | AC-FR-15-05 | 複数保存・動画別結果/不明 | T03/T15/T21;BI-10/30（旧は契約まで） | EB:完全媒体/使用権契約,E-S31-01,E-S31-02 | S31,S34 | dep(S31,S34)＋対応A/Q01 | O-PHOTOS | 動画別意図/結果/Library表示済、固定複数集合の保存開始未接続 | E-S31-01:複数記録/別動画回収非阻害のUnit・通常UI4成功 | D0 | 動画別状態の部分証拠・複数保存開始/取得/実機未確認 | DV-16 |
| FR-16 | AC-FR-16-01 | 全媒体Wi-Fi・local offline再生 | T03/T05/T09/T11/T15/T23;BI-07〜15 | EB,ER,E-S15,E-S25 | S15,S23,S25 | dep(S15,S23,S25)＋対応A/Q01 | O-IOS-BI/O-CAPTURE | 全媒体共通gateとS23背景resource基盤/S25固定版I/Oを実装、通常strict通信/全producer接続未成立 | E-S21/E-S23-01/E-S25の規則・SDK/I/O部分。実Wi-Fi/Tailscale/cellular切替未確認。E-S28-01:既存登録の明示metadata1page/動画別表示、Unit新21宣言27展開、専用UI1/reopen1/実HTTP1成功（metadata2要求/媒体・確認・ACK0）。 | D0 | 部分証拠、実機受入未評価 | DV-12、DV-14 |
| FR-16 | AC-FR-16-02 | REC実停止・保存優先・Mac継続 | T03/T05/T09/T11/T15/T23;BI-07〜15 | EB,ER:契約/部分観測 | S23,S49 | dep(S23,S49)＋対応A/Q01 | O-IOS-BI/O-CAPTURE | 同期REC/save/recovery holdとexact local停止・単回同期許可の契約/SDK port配線を部分接続、正のSDK resume/全媒体実停止は未成立 | E-S49-01:16新宣言25展開と全Unit841、UI3/build成功。実通信中REC/Mac継続は未検証 E-S49-RESUME-01: origin/revision/単回/throw・各hold/ABA・実2Thread排他とSDK直前の注入action0/1を確認。関連28宣言44展開/非送信実SDK3/全Unit609宣言964展開(有意味963)/31skip成功、最終診断/runtimeWarnings0。正の実SDK/全媒体へ昇格しない。 | D0 | 部分証拠、実機受入未評価 | DV-11、DV-12 |
| FR-16 | AC-FR-16-03 | 開始済対象だけ全条件再確認再開 | T03/T05/T09/T11/T15/T23;BI-07〜15 | EB,ER:契約/部分観測,E-S21 | S23,S28,S49 | dep(S23,S28,S49)＋対応A/Q01 | O-IOS-BI/O-CAPTURE | 本人停止/取消と重畳wait・保存実終端を別所有で保持、再開規則/復旧基盤済、通常strict resume・全媒体再開producerは未成立、通常再開UI未接続 | E-S21/E-S23-01/E-S49-01の停止・旧owner・通知両順序を確認。実回線/通常resumeは未成立 E-S49-RESUME-01: origin/revision/単回/throw・各hold/ABA・実2Thread排他とSDK直前の注入action0/1を確認。関連28宣言44展開/非送信実SDK3/全Unit609宣言964展開(有意味963)/31skip成功、最終診断/runtimeWarnings0。正の実SDK/全媒体へ昇格しない。 | D0 | 部分証拠、実機受入未評価 | DV-12 |
| FR-17 | AC-FR-17-01 | 単数対象と消失リスク確認 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33,S34 | dep(S33,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | 通常単数破棄の対象/消失リスク確認と実unlink/履歴を接続。exact SDK終端・source閉鎖・lease解放・stoppedが揃う履歴も許可、活動中/未知source等は保持 | E-S33-01:単数risk/非偽装/外部保持/中断21case成功。E-S34-01:通常単数UI1＋実disk再open1成功。E-S34-BG01:新14宣言45展開＋実suspended SDK1case、exact全履歴/ownFD閉鎖/lease/stopped→通常risk・実unlink・再open。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-17 | AC-FR-17-02 | 明示操作なしの破棄禁止 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33 | dep(S33)＋対応A/Q01 | O-ORIGINAL/O-STORE | 単数明示risk/取消/再判定を実装、自動不要判定/整理から破棄への自動移行なし | E-S33-01:単数risk/非偽装/外部保持/中断21case成功。E-S34-01:通常単数UI1＋実disk再open1成功。E-S34-BG01:新14宣言45展開＋実suspended SDK1case、exact全履歴/ownFD閉鎖/lease/stopped→通常risk・実unlink・再open。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-17 | AC-FR-17-03 | iPhone対象だけ削除・外部保持 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33 | dep(S33)＋対応A/Q01 | O-ORIGINAL/O-STORE | 選択したiPhone原本だけ実unlink、非empty Mac/Photos記録と外部媒体を保持 | E-S33-01:単数risk/非偽装/外部保持/中断21case成功。E-S34-01:通常単数UI1＋実disk再open1成功。E-S34-BG01:新14宣言45展開＋実suspended SDK1case、exact全履歴/ownFD閉鎖/lease/stopped→通常risk・実unlink・再open。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-17 | AC-FR-17-04 | 保存/確認状態の非偽装 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33,S34 | dep(S33,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | 破棄目的/実結果と保存検証・確認を独立保持し製品投影へ接続 | E-S33-01:単数risk/非偽装/外部保持/中断21case成功。E-S34-01:通常単数UI1＋実disk再open1成功。E-S34-BG01:新14宣言45展開＋実suspended SDK1case、exact全履歴/ownFD閉鎖/lease/stopped→通常risk・実unlink・再open。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-17 | AC-FR-17-05 | 実削除照合と成功履歴 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33,S34 | dep(S33,S34)＋対応A/Q01 | O-ORIGINAL/O-STORE | exact batch/目的/内容・file不在/result一致後だけ成功履歴、再open照合を製品接続 | E-S33-01:単数risk/非偽装/外部保持/中断21case成功。E-S34-01:通常単数UI1＋実disk再open1成功。E-S34-BG01:新14宣言45展開＋実suspended SDK1case、exact全履歴/ownFD閉鎖/lease/stopped→通常risk・実unlink・再open。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| FR-17 | AC-FR-17-06 | 破棄境界中断・要照合 | T03/T21;BI-28/29（旧は契約まで） | EB:破棄/解放/順序規則 | S33 | dep(S33)＋対応A/Q01 | O-ORIGINAL/O-STORE | intent/unlink/result各境界とobserve-only復旧・unknown通常要照合を実装、未実行再削除なし | E-S33-01:単数risk/非偽装/外部保持/中断21case成功。E-S34-01:通常単数UI1＋実disk再open1成功。E-S34-BG01:新14宣言45展開＋実suspended SDK1case、exact全履歴/ownFD閉鎖/lease/stopped→通常risk・実unlink・再open。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| NFR-01 | AC-NFR-01-01 | 起動/次REC/通信停止の実測 | P18,T23;CF-09,BI-09 | EC,EB:時刻/抑止契約 | S41,S43,S49,S4V | dep(S41,S43,S49,S4V)＋対応A/Q01 | O-CAPTURE/O-IOS-BI | 時刻・通常入口/次REC/同期hold基盤を実装、全媒体重畳と実機時間/目標適合は未測定 | E-S41/E-S43/E-S49-01:postSave非阻害と実return境界/通常UI。2〜3秒目標を自動成功から推定しない | D0 | 部分証拠、実機受入未評価 | DV-11、DV-12 |
| NFR-02 | AC-NFR-02-01 | 保存/検証受信/確認の中断 | P09/P19,T10/T18/T21/T22;CF-08,BI-04/05/20/23/29/30/33 | ES,EB,E-S11,E-S12,E-S21,E-S24 | S12,S21,S24I,S27 | dep(S12,S21,S24I,S27)＋対応A/Q01 | O-STORE/O-ORIGINAL/O-PHOTOS | 通常保存/端末証拠/確認outbox・server保存復旧と実wire確認を技術接続、通常転送/確認UIは未接続 | E-S12/E-S21/E-S24に加えE-S49-01先着通知保存境界、E-S27-01実HTTP exact確認。E-S28-01:既存登録の明示metadata1page/動画別表示、Unit新21宣言27展開、専用UI1/reopen1/実HTTP1成功（metadata2要求/媒体・確認・ACK0）。 | D0 | 部分証拠、実機受入未評価 | DV-02、DV-12、DV-14 |
| NFR-02 | AC-NFR-02-02 | 失効維持・写真直後中断 | P09/P19,T10/T18/T21/T22;CF-08,BI-04/05/20/23/29/30/33 | ES,EB:境界規則とdisk部分,E-S21,E-S31-01,E-S31-02 | S21,S27,S31 | dep(S21,S27,S31)＋対応A/Q01 | O-STORE/O-ORIGINAL/O-PHOTOS | 失効永続/ACKとPhotos意図/結果/非再追加・使用権実解放を技術結合、全製品producer/通常UIは未接続 | E-S21/E-S31-01/02/E-S27-01:commit前後/reopen/SDK終端/旧確認非復活。実OS中断は未実施。E-S28-01:既存登録の明示metadata1page/動画別表示、Unit新21宣言27展開、専用UI1/reopen1/実HTTP1成功（metadata2要求/媒体・確認・ACK0）。 E-S31-OWNER-01: 同exact使用権回収/owner実閉鎖後の遅延releaseを修正。旧8枝/決定的crash回帰、全Unit604宣言952展開(有意味951)/31skip、実PhotoKit許可拒否各2成功を確認。 | D0 | 部分証拠、実機受入未評価 | DV-14、DV-16 |
| NFR-02 | AC-NFR-02-03 | 不明/失敗と復旧表示 | P09/P19,T10/T18/T21/T22;CF-08,BI-04/05/20/23/29/30/33 | ES,EB:境界規則とdisk部分,E-S31-01 | S14,S28,S31,S34 | dep(S14,S28,S31,S34)＋対応A/Q01 | O-STORE/O-ORIGINAL/O-PHOTOS | 保存/写真/削除の不明・失敗を独立投影し、明示metadata同期/照合と単数破棄UIへ接続、未接続媒体操作は保持  remote保存記録を原本/公開状態と分離し、unknown日時/内容衝突/現在存在未照合を保持。 | E-S14/E-S31/E-S34-01の状態UIとE-S49-01保存結果分岐。E-P2-20261022-FIXで既知strict4を含む6監査成功。実救済/継続の未接続範囲は未保証。E-S28-01:既存登録の明示metadata1page/動画別表示、Unit新21宣言27展開、専用UI1/reopen1/実HTTP1成功（metadata2要求/媒体・確認・ACK0）。E-S34-BG01:新14宣言45展開＋実suspended SDK1case、exact全履歴/ownFD閉鎖/lease/stopped→通常risk・実unlink・再open。 E-S31-OWNER-01: 同exact使用権回収/owner実閉鎖後の遅延releaseを修正。旧8枝/決定的crash回帰、全Unit604宣言952展開(有意味951)/31skip、実PhotoKit許可拒否各2成功を確認。  E-S28-INVENTORY-01: 同writer/exact lookup/lost reply/登録変更拒否と旧schema再open、実SDK metadataの部分証拠。 | D0 | 部分証拠、実機受入未評価 | DV-02、DV-14、DV-16 |
| NFR-02 | AC-NFR-02-04 | 整理/破棄の実削除境界復旧 | P09/P19,T10/T18/T21/T22;CF-08,BI-04/05/20/23/29/30/33 | ES,EB,E-S13:境界規則とdisk部分 | S32,S33,S34 | dep(S32,S33,S34)＋対応A/Q01 | O-STORE/O-ORIGINAL/O-PHOTOS | 両目的の実unlink/同writer結果commit/observe-only復旧と、単数破棄/条件付き複数整理の通常導線を接続 | E-S32-03:実MOV unlink/全内容・reader/予約/失効両順序/8境界・再open成功。E-S34-01:整理後通常投影/実file照合。E-S33-01:単数risk/非偽装/外部保持/中断21case成功。E-S34-01:通常単数UI1＋実disk再open1成功。E-S34-BG01:新14宣言45展開＋実suspended SDK1case、exact全履歴/ownFD閉鎖/lease/stopped→通常risk・実unlink・再open。 E-S34-CLEANUP-01: 固定複数集合の実unlink/動画別結果/通常一覧/再起動・予約/未処理の非再unlinkを確認。 | D0 | 部分証拠、実機受入未評価 | DV-17 |
| NFR-03 | AC-NFR-03-01 | 全必須gateの実施と品質適合分離 | P17/P18/P20;CF-02〜10 | EC:部分探索のみ | S41〜S49,S4V | dep(S41〜S49,S4V)＋対応A/Q01 | O-CAPTURE | 全gateを追跡し撮影補助/保存/媒体基盤を部分接続、標準表示/ISO/全通信/総合は未成立 | S41〜S49各E証拠、E-S26A-01とH01枝票。試験実施と品質適合を分離、実機未実施 E-S49-RESUME-01: origin/revision/単回/throw・各hold/ABA・実2Thread排他とSDK直前の注入action0/1を確認。関連28宣言44展開/非送信実SDK3/全Unit609宣言964展開(有意味963)/31skip成功、最終診断/runtimeWarnings0。正の実SDK/全媒体へ昇格しない。 | D0 | 部分証拠、実機受入未評価 | DV-01、DV-03、DV-04、DV-05、DV-06、DV-07、DV-08、DV-09、DV-10、DV-11 |
| NFR-03 | AC-NFR-03-02 | Log原本・設定/音声/継続品質 | P17/P18/P20;CF-02〜10 | EC:部分探索のみ | S42〜S49,S4V | dep(S42〜S49,S4V)＋対応A/Q01 | O-CAPTURE | WB/音声/補正/AF/NDを通常接続、ズーム・レンズISO/標準変換/同時品質は未成立 | S42〜S46およびE-S49-01の技術証拠。実Log/AV同期/継続の全組合せ品質は未確認 | D0 | 部分証拠、実機受入未評価 | DV-03、DV-04、DV-05、DV-07、DV-08、DV-09、DV-10、DV-11 |
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
| AC-BI-25 | S22C,S28 | DV-15、新登録へ旧確認非復元・通常利用  E-S28-NEW-01の明示入力/namespaceとINVENTORY-01の旧原本identityのみを部分接続、旧確認/ACKは非移植、通常媒体は未接続 |
| AC-BI-26 | S28 | DV-15、旧ACK無期限待ち・別動画続行  新inventoryは旧必要ACKを消さず別remote記録を投影、全owner/正式媒体/通常確認の再登録結合は残件 |
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

### H01 引渡し準備版（2026-10-22、実施結果ではない）

現在の追加差分は [DI-SOURCE-20261023-02](evidence/20261023-remote-inventory/source-binding.json) の414入力へ別束縛した。以下のH01-SOURCE-01/389入力と旧票は当時の準備履歴として不変保持する。実機はcaseごとのQ01で最新source/build/実条件/品質合意を再束縛してから行い、今回の非実機成功をD0やA票/PRD受入へ昇格しない。

18票を76の母行へ具体化した。各母行の列挙パラメータを全て展開してrun枝番を作り、79ACの全文とCF11・BI34・DI18、旧C01〜C19／B1〜B7／U01〜U05／V01〜V16を引き継ぐ。76は実行ケース数や成功数ではない。Q01で実集合・各組合せID・有限の反復数・長さ・再現手段を束縛してから分母を確定し、不能・未到達・未実施も分母と理由を残す。代表1件の成功で他セルを達成にしない。

共通の実装束縛は **[H01-SOURCE-01](evidence/20261022-device-handoff/source-binding.json)**。HEADとdirtyソースmanifestを持ち、App/Unit/UI/project、backend支援、永続6文書、requirements/designを含む。自己参照を避けtasklist/evidenceをソースhash対象から除く。各実行証拠の対象層と版も別に照合し、文書更新をアプリ再build済みとせず、以前のbuildを変更後コードへ流用しない。実機buildID、端末、実媒体、接続先、日付、保管先、時計誤差、品質条件・許可IDは未束縛で、各run直前のQ01が実値を記録する。既存の `CF-RUN-v0.1-draft`／`EXP-v0.1-draft` の例示値は採用しない。

直近のコード実行版はApp/Unit/UI/projectの288入力。全Unitは560宣言/913展開成功（空template1を除く有意味912）・29skip、generic iOS build、通常UI6件・状態同期UI1件/再open1件、実background SDK1件、metadata-only実HTTP1件が成功した。HTTPは実2要求・媒体0byte・新確認/ACK0であり、SDK終端1件は注入permit/Mac観測と自身sourceFDの実閉鎖を区別する。以前のS27 publication HTTPは279入力、厳格AX監査は260入力の14成功/4失敗で、現288入力の全機能合格へ読み替えない。具体command/result/診断と版の対応はsource binding内のexecution_bindingを参照する。

枝番は `DV-xx/case/combinationID/conditionVersion/repetitionID`。各行の根拠AC・旧ケース、条件→操作、期待、証拠、直接依存/必要substatus、実装状態/実施可否を引き継ぐ。実施可能と記した部分もQ01束縛前は実機未実施であり、全A01〜A18のpending・D0・受入未評価は変えない。品質枝はG3等の事前合意前に品質合格試験を行わない。注入・使い捨てdisk・実OS・実媒体を別runにし、実到達を示せなかった境界を実施済みにしない。

| 展開キー | 全枝を作る規則・未束縛値 |
| --- | --- |
| C／L／S／O・全能力セル | 実camera集合C、4K24/30、LT/422/Proxy、実Log集合L、OFFと実補正S、二記録候補O（Movie file output／sample buffer writer）を能力表で照合。対応/非対応/未確認/適用失敗を別セルで保持し、全実行可能セルを音声付き録画・保存検査へ渡す。候補間を自動切替しない。実機未取得の能力を空集合で省略しない |
| B／B0・差異セル | Bは全実行可能LT標準セル（各C×fps×L×S×O）、B0は各C×fps×L×OのOFF基準。OFF不能は理由を残し比較条件を本人が別途束縛。codec/出力/Log/camera/fpsで実挙動・契約差のある非LTセルは、WB/音声/表示/ズーム/保存等の該当単独票にも追加し、能力表の成功を機能全組合せの成功へ転用しない |
| E・画角/レンズ | 各camera/形式/Log/補正/出力の全有向移行E。往路/復路を別枝、対応Eと非対応Eの実行抑止を両方残す。経路なしも根拠付き未実施。予告/実倍率/実camera/補正crop/停止候補あり・なしを対応付ける |
| 境界・保存分類 | B1〜B7各前/後と、各行のintent/SDK/file/検査/結果commit/応答を実到達で区別。正常/部分/不明/失敗と保存可能区間を実ファイル・store・表示から判定。プロセス中断や権限変更は許可した新規試験対象だけ、実容量埋め/旧App削除を前提にしない |
| 回線・本人意思・待機 | upload/download/stream・Range/一時取得/thumbnailの全実装経路×直接LAN/外出Wi-Fi＋Tailscale×前景/背景/lock/再開。各行の独立waitについて成立可能な全部分集合・解除順を作り、本人継続/停止/取消を掛ける。recording→saving等の実順序を崩す架空の枝は理由付き対象外。全wait解除後も本人停止/取消は保持する |
| 公開登録集合R・順序 | 同一公開対象の全受取登録Rを固定/追加時点付きで記録し、複数必要登録の片ACK/重複/不正/全件と到着順を展開する。R1/R2/R3は識別の例で、実集合はQ01へ束縛。確認同期未到達の受取と待ち中追加を落とさず、V1配布受理先行/新版公開先行、失効先行/削除確定区間先行を別runにする |
| 比較・品質・反復 | 同一実装/場面/手動値/音源/長さで原則一要因比較。補正OFF→候補→OFF、記録単独→表示併用→単独、静止記録→ズーム/切替→静止記録を組とする。C16/C17の代表長と連続二本以上は旧要求を維持し、実時間/本数/反復/冷却/許容はQ01へ残す。暫定AF3秒/ND1秒、音声2秒・1本人操作1試行・5秒は承認済みpolicy、実機品質の採用とは別。ISO戻り/上限/基準は未回答、通常policy=nil |

| 旧自動ケース | 引渡す証拠・実機で残す範囲 |
| --- | --- |
| U01 | S41/S44/S45/S46の希望/能力/実値/復元・REC非阻害と世代をUnitで検証。実能力・AF/ND品質はDV-01/04/06/07へ |
| U02 | S42/S43/S49のWB/音声/終端・通知先後・旧owner/有限復旧を技術試験。最終実frame・実OS音声・REC負荷はDV-02/03/10/11へ |
| U03 | S11/S12/S21/S28/S31/S32/S33のdisk commit/reopen/障害/実file・実unlink境界。端末保護・実中断の実到達はDV-02/12/14/16/17へ |
| U04 | 独立状態/保存結果/実値/非対応拒否/非確認生成とS28媒体なし明示同期を投影・UI/実HTTP試験で部分確認。製品未接続状態と実映像品質は該当票へ保持 |
| U05 | 通常撮影/Library/再生/権限と実文字/VoiceOverに部分成功。厳格AX監査4件は未解消、縦横・実カメラ操作は未実施。DV-18/c04から各実装済画面を展開し、監査失敗を無視しない |

| DI条件 | 対応する机上証拠／実機枝・現時点の限界 |
| --- | --- |
| AC-DI-01 | 全79行とDV母行の双方向対応、DV-18/c03。部分証拠を全文達成へ昇格しない |
| AC-DI-02 | 各母行の必要substatusと拒否枝の独立依存。G1/G2B/品質の全体待ちを追加しない |
| AC-DI-03 | S1V〜S4Vの状態と各E証拠。4段階全体とA票は未完 |
| AC-DI-04 | N00の所有/引渡し、S11/S13/S21同writer・原本/lease、S23/S49部分引渡し。S34は歴史的なexact全終端後の単数破棄だけ追加、未知ownerは保持 |
| AC-DI-05 | 全79行のI/A/D/Rと各行の実施可否。未接続と実機未確認を区別 |
| AC-DI-06 | DV-17/c01.01/c05.01。S32実unlink、S34整理後通常投影、通常整理/複数UIは未接続 |
| AC-DI-07 | DV-17/c02.01。S33/S34単数破棄の通常UI/実unlink/成功履歴と、確定background終端履歴の実SDK→通常model破棄を合成fixtureで確認、実原本未受入 |
| AC-DI-08 | DV-17/c06/c08。intent/unlink/result独立・observe-only再open、未実行非再削除 |
| AC-DI-09 | DV-16/c02。add-onlyと理由付きreadWrite、拒否で無関係撮影を止めない。通常新規保存開始は未接続 |
| AC-DI-10 | DV-16/c03/c05。限定/未発見/不明非再追加、写真側削除非復活、失敗copy回収方針は未成立 |
| AC-DI-11 | DV-08/c01/c02。目標→予告→明示開始→目標/途中停止、REC停止と分離、非焼込み。S47/S48残件あり |
| AC-DI-12 | DV-08/c02/c03。版付き暫定値/候補根拠と実機採用を分離。許容/実値はQ01 |
| AC-DI-13 | 各Eのraw結果/失敗・skip・診断/入力hash/mainレビューと本source binding。独立validationは別明示工程 |
| AC-DI-14 | N00と版付き承認済policy/ISO未回答/Q01品質判断を分離。重大未合意をmain裁量で採用しない |
| AC-DI-15 | 旧失敗/途中版を保全し、全A票D0/受入未評価を保持。M09/M10の旧台帳整合は別Workflow待ち |
| AC-DI-16 | 全76母行と共通run schema/source binding。実環境・媒体・品質・反復はQ01未束縛で実施前に確定 |
| AC-DI-17 | 保存/ACK/削除/通信/標準変換/原本不変の各技術証拠と該当全DV。通常strict通信/資材/全媒体等は未成立 |
| AC-DI-18 | N00保全・M01〜M06同期と明示Workflow。M07〜M10/H02/全実機は未完、旧仕様/README/PRD本文を変更しない |

既存DV-12/c02/c03、DV-14/c01、DV-17/c03/c04/c05の6親行は保持し、以下の子枝がその条件を具体化する。各票の「関連AC」は索引であり、下表に引用したIDのPRD全文・CF/BI/DI条件が優先する。caseの拒否理由に必要のない正常G2B、標準資材、他A票全体doneを足さない。

### A01 / DV-01 形式・手動設定

- [ ] Status: pending
  - Depends: S41,S43,Q01。当該形式候補のSDK接続。
  - 関連AC・gate: AC-FR-01-01〜04、AC-CF-01/02、撮影D01/C-G03・B-G2B。
  - 対象・操作: 1. カメラ／Log／形式／補正の実能力表を取得。2. 標準4K24/30とLT/422/Proxyの全実行可能必須セルで音声付き撮影。3. 手動値を変更し停止、原本検査、再起動・復元して再撮影。4. 原本の写真非追加を照合。
  - 期待結果: 希望／能力／実値／保存形式が対応、無断代替なし。未対応理由が分かり実原本と音声を確認。
  - Verify / 証拠: 能力表、適用値・時刻、実原本と特性、写真側非追加、実機方式の採否根拠。
  - 事前合意・Stop: 対象セル・手動値・新規媒体操作。品質はC-G04条件版。未対応を環境不足と区別。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-01/c01<br>AC-FR-01-01、AC-FR-01-02、AC-FR-01-04<br>C01–03/U01; CF-01/02 | 全C×{4K24,4K30}×{LT,422,Proxy}×L×S×O。能力=対応/非対応/未確認、適用=成功/拒否/不明/失敗<br>→ 全セルの能力・希望を記録し、実行可能セルを読戻し後に音声付きREC/STOP。標準不能セルも残す | 希望/能力/実値/原本の対応。自動代替なし。標準不能は制約/代案/要求再確認。原本の写真非追加 | 能力全表、実値、原本codec/fps/色/音声/日時/向き、写真非追加 | S41/S43、当該SDK・保存経路、Q01 | S41/S43の通常撮影接続・Unit/UI確認済。Q01後に実端末を観測可能、実Log/品質は未確認 |
| DV-01/c02<br>AC-FR-01-03、AC-FR-01-04<br>C04/U01 | B0、シャッター/ISOの異なる有効値、絞り対応/非対応、設定なし/保存済/条件変化/再起動<br>→ 本人が各値を変更し前中後を比較、同条件と非対応条件で再openし再撮影 | 手動値維持、非対応絞りUIなし、WBは待機Auto、補正は対応条件復元。無断で戻さずND再評価 | 設定store/再open、実値時系列、画面、原本 | S41/S44/S46、Q01 | S41/S43の通常撮影接続・Unit/UI確認済。Q01後に実端末を観測可能、実Log/品質は未確認。補正/ND品質はDV-04/07 |

### A02 / DV-02 保存・復旧

- [ ] Status: pending
  - Depends: S12,S41,S43,Q01。当該実録画はA01の方式観測後。
  - 関連AC・gate: AC-FR-10-02、AC-NFR-02-01/03、AC-CF-08、B-G2A/G2B/G4。
  - 対象・操作: 1. 正常停止を保存・再起動照合。2. 記録終端／ファイル確定／意図・結果commitの許可した境界で中断。3. 再起動して実原本・管理記録・一覧を照合。4. 合意した端末保護条件で同じ照合。
  - 期待結果: 正常／部分／不明／失敗を分け、存在だけで正常にしない。未知／破損でも証拠保持。
  - Verify / 証拠: 境界時系列、前後ファイル／store対応、保護条件・画面、G2A非実機証拠との差分。
  - 事前合意・Stop: 中断方法・位置・対象。実容量埋め／実データ削除は行わない。救済成功を保証しない。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-02/c01<br>AC-FR-10-02、AC-NFR-02-01、AC-NFR-02-03<br>C13/U03; CF-08 | B0、通常STOP、正常/部分/不明/失敗の保存分類<br>→ STOP受付→実記録終端→file確定→検査→結果commit→再open→再生を照合 | 存在/受付だけで正常にしない。内容と必要trackに基づく分類、未知/破損は証拠保持 | 原本/intent/結果/画面の三者、各実到達時刻、再生・lease | S12/S41/S43、Q01 | S41/S43の通常撮影接続・Unit/UI確認済。Q01後に実端末を観測可能、実Log/品質は未確認 |
| DV-02/c02<br>AC-FR-10-02、AC-NFR-02-01、AC-NFR-02-03<br>C14–15/B1–B7/U03; CF-08 | B1–B7各前/後×実OS中断/背景/ロック/本人終了再起動/制御注入。実到達の取れる枝を個別run<br>→ 許可した新規試験原本で中断、復帰/再openして旧clipと次clipを照合 | 受付≠実終端。救済を保証せず正常/部分/不明/失敗を区別、旧callbackが新clipを成功化しない | 中断到達hook、媒体/store前後、最終frame/WB、再open表示 | S12/S41/S43、該当保護・中断手段、Q01 | S41/S43の通常撮影接続・Unit/UI確認済。Q01後に実端末を観測可能、実Log/品質は未確認。任意境界の実OS再現不能は未到達として保持 |
| DV-02/c03<br>AC-NFR-02-03<br>C14/U03 | 書込/検査/intent・結果commit×失敗/アクセス不能/容量相当注入、未知schema/破損/世代競合<br>→ 使い捨て領域へ障害を与え再openし、実端末の保護状態観測と分離 | 不明を未実行/正常にせず空storeへ置換しない。既存データ削除/端末容量埋めなし | 注入根拠、分類/エラー、原本/DB保持、実端末観測の別記 | S11/S12、Q01 | disk境界は自動確認済。実保護・実中断はQ01後、注入を実容量枯渇の証拠にしない |

### A03 / DV-03 WB

- [ ] Status: pending
  - 先行引渡し E-S42-01: 通常撮影の本人再固定、測定/固定適用とSTOPの順序、終端後Auto、二本/旧通知拒否を接続し、関連Unit89ケース/UI1・iOS build成功。Simulatorは実カメラでのone-shot測定/KVO、色、最終フレーム、継続性を証明しない。両記録候補・対応能力・実機版を束縛して下記操作を実施する。
  - Depends: S42,Q01,A01の該当記録経路。
  - 関連AC・gate: AC-FR-04-01〜03、AC-CF-03。
  - 対象・操作: 1. Auto安定前にREC。2. 録画中に本人が再固定、他手動値も記録。3. STOP直後に待機Autoを確認し次の1本。4. 最後の記録フレームまで設定と色を照合。
  - 期待結果: 安定待ちなし、本人操作のみ再固定、最終フレームまで固定、次clip新測定、他設定不変。
  - Verify / 証拠: 原本フレーム・WB実値・時刻、色変化／音声／継続。
  - 事前合意・Stop: シーン・再固定操作・色変化／継続の品質条件を事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-03/c01<br>AC-FR-04-01<br>C05/U02; CF-03 | B0、Auto安定前REC/ND判定完了/本人操作なし<br>→ 照明変化直後にRECし最初から最後の記録frameと固定値を観測 | 安定待ちで開始せず現在値固定、ND契機の固定なし、録画中Autoへ戻さない | REC/固定/最初・最後frame、WB/手動値/色 | S42、当該A01記録経路、Q01 | S42通常接続/順序試験済。実測WB/KVO/色はQ01後 |
| DV-03/c02<br>AC-FR-04-02<br>C05/U02 | B0、明示再固定とSTOPの先行/後着/重複・旧通知、再測定開始/固定適用の拒否・unknown・失敗とSTOP先後<br>→ 録画中に本人再固定しSTOPを重ね、他の手動値/色/音声継続を照合 | 本人操作だけ更新、最終frameまで固定、ISO/絞り/シャッター無断変更なし。実固定済/未確認/失敗を表示で混同しない | 操作/SDK適用/終端時系列、原本比較、品質条件版 | S42、Q01 | 順序技術試験済。実カメラ再測定と品質は未確認 |
| DV-03/c03<br>AC-FR-04-03<br>C05/C15/B3/U02 | 異なる照明で連続二本、正常/障害STOP後<br>→ 一本目終端→待機Auto→二本目REC、ND解析も継続 | 一本目最終frameまで固定、待機Auto、二本目新測定。値の持越しなし | 二本の原本・設定/固定/Auto時系列 | S42/S43、Q01 | 通常接続済。二本の実frameはQ01後 |

### A04 / DV-04 補正

- [ ] Status: pending
  - Depends: S44,S47,Q01,A01の該当形式。
  - 関連AC・gate: AC-FR-03-01〜05、AC-NFR-03-01〜02、AC-CF-06。
  - 対象・操作: 1. OFFと複数モードを選び読戻し。2. 歩き／静止手持ち／ゆっくりパンを同条件で撮影。3. 再起動・条件変更で復元と非対応案内。4. ズーム／切替を重ね画角と補正を照合。
  - 期待結果: 表示と実補正一致、復元条件・非対応説明、予告への画角反映、音声同期・継続。標準不成立は未達。
  - Verify / 証拠: 比較原本、モード／実値／画角／同期／継続、組合せ表。
  - 事前合意・Stop: 各組合せと3場面、画角・補正効果・継続の許容範囲を事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-04/c01<br>AC-FR-03-01、AC-FR-03-02、AC-FR-03-05、AC-FR-01-04<br>C09/U01/U04; CF-06 | B全S、初回/同条件再open/非対応条件変更、適用成功/拒否/不明<br>→ OFFと複数実モードを選択/読戻し。標準相当を初回候補、非対応条件で本人選択 | 表示=実適用、無断代替なし。標準不成立は未達・制約/代案を残す | モード/能力/実値/保存希望、画面、条件表 | S44、当該A01セル、Q01 | S44接続/復元試験済。実機対応はQ01後 |
| DV-04/c02<br>AC-FR-03-03、AC-NFR-03-02<br>C10; CF-06 | B各モード×{歩き撮り,静止手持ち,ゆっくりパン}、OFF→候補→OFF<br>→ 同一場面/手動値/音源/長さで比較撮影し原本を評価 | 補正効果/構図/音声同期/継続を合意範囲で判定、録画中に形式/モード/方針を変えない | 比較原本、画角/揺れ/実値/音声・同期、合意条件 | S44、Q01品質合意、当該A01セル | 制御接続済。補正品質/全セルは実機未確認 |
| DV-04/c03<br>AC-FR-03-04<br>C10–12; CF-06/07 | B×有向E、補正維持可能/不能、予告/停止支援と実画角<br>→ 補正下で予告→ズーム→切替を行い画角/負荷を比較。不能Eは実行拒否 | 補正cropを予告/停止支援へ反映、維持不能を無通知実行しない | 前中後原本/予告/実倍率/crop/補正、制約 | S44/S47、Q01 | S47規則/UIは部分、ISO方針未回答。統合の該当枝は未接続 |

### A05 / DV-05 固定Rec.709表示

- [ ] Status: pending
  - Depends: S48,Q01,A01の採用Log・適合資材。
  - 関連AC・gate: AC-FR-02-01〜02、AC-CF-05、撮影D02。
  - 対象・操作: 1. 入力Log・標準資材由来／版を照合。2. 待機／録画で標準表示。3. 同じ保存Log原本と画面を比較。4. 録画と描画を重ね負荷・確認状態を観測。
  - 期待結果: 実標準Rec.709、原本非焼込み・二重変換なし、録画と描画両立、軽量版確認非生成。
  - Verify / 証拠: 資材・入力条件、画面と原本、描画／記録観測。
  - 事前合意・Stop: 資材利用条件・実Log適合、表示／録画品質の事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-05/c01<br>AC-FR-02-01<br>C08; CF-05 | B0各Log×待機/録画、資材適合/不一致/欠落/二重変換<br>→ Log別に由来/版/hash/利用条件/数値域を確認し標準参照と表示・原本を照合 | 実Rec.709だけ成功。原本非焼込み、Log不一致/二重変換を拒否 | 資材/既知入力/期待出力、表示frame、実Log原本不変 | S26A適合資材/S48、Q01 | 標準資材未取得・通常表示未接続。生成cubeの技術描画だけ確認済 |
| DV-05/c02<br>AC-FR-02-02<br>C08/U04 | 記録単独→表示併用→単独、同一B0/場面/音源<br>→ 待機/録画で表示を重ね再生token・確認/Photos状態と描画/録画を観測 | 閲覧だけで軽量版確認/写真状態を生成せず、表示性能と記録安定性を別判定 | 原本/描画時刻/落ち/AV同期、状態前後、品質条件 | S48、Q01品質合意 | 表示本体が未接続。実負荷は未実施 |

### A06 / DV-06 人物AF

- [ ] Status: pending
  - Depends: S45,Q01,A01の該当制御経路。
  - 関連AC・gate: AC-FR-05-01〜05。
  - 対象・操作: 1. 複数露出対象と一人主役を選択。2. 主役前後移動・退出／同一復帰・別人通過・保持期限超過・再指定。3. 追跡OFFで人物優先AF。4. 人物なし・検出未完了RECを確認。
  - 期待結果: 通常合焦・前後追従、同一主役再捕捉、別人自動移行なし、OFFは固定でなく人物AF、REC非阻害。
  - Verify / 証拠: 対象／距離／光／移動・保持設定版、主役状態と原本・合焦記録。
  - 事前合意・Stop: S45で人物なしタップAF・初回本人意図選択/保存復元/REC非阻害・変更可能な暫定3秒後保持/再指定を承認済み。距離・照明・移動・補正/Log条件と許容品質、暫定値の実機採用は未合意/未確認。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-06/c01<br>AC-FR-05-01<br>U01/U04 | 意図3種/未選択、複数露出対象/一人主役、保存復元、人物なし<br>→ 本人が露出対象と主役を別選択、再open、人物なしで位置タップ | 意図保存/復元、露出と主役を混同せず、人物なし位置AF | 選択/検出/AF命令/実合焦、保存希望と復元 | S45、Q01 | 本人承認済policyを通常接続/技術試験済。実合焦は未確認 |
| DV-06/c02<br>AC-FR-05-02<br>U02 | 同一主役復帰が暫定3秒前/境界/後、別人通過、再指定<br>→ 主役退出→同一復帰/別人/期限超過を別run、本人再指定 | 猶予内は同一主役のみ復帰、期限後保持/控えめ表示/再指定待ち、別人自動移行なし | 主役identity/時刻/猶予policy版/原本/状態 | S45、Q01品質合意 | 暫定3秒は承認済。実機採用と追跡品質は未確認 |
| DV-06/c03<br>AC-FR-05-03<br>U01/U02 | 検出未完了/古い世代/意図未選択/候補不確か<br>→ 条件中に本人RECし、停止後・カメラ変更後の古い解析も到着させる | 必要記録条件成立ならREC可。不確か/旧結果を現在確定表示しない | 解析/世代/REC受理時系列、UI/原本 | S45/S41/S43、Q01 | REC非阻害/世代技術試験済。実機解析は未確認 |
| DV-06/c04<br>AC-FR-05-04、AC-FR-05-05<br>U01/U04 | 通常合焦/前後移動×追跡ON/OFF、合意距離/照明/速度、人物＋背景<br>→ ONで指定主役を前後移動、OFFで人物優先AFを独立比較 | ON追従とOFF人物AFを各合意範囲で判定。選択/再捕捉だけで品質完成にしない | 実原本/合焦/距離/光/動き/方式/品質条件 | S45、Q01品質合意 | SDK接続済。AF品質とOFF実動作は実機未確認 |

### A07 / DV-07 ND

- [ ] Status: pending
  - Depends: S46,Q01,A01/A03の該当設定事実。
  - 関連AC・gate: AC-FR-06-01〜04、AC-FR-01-03。
  - 対象・操作: 1. 濃く／薄く／両立困難の合意場面を撮影。2. 太陽・反射・黒を加える。3. WB・手動値・露出対象を変更。4. 解析遅延／停止時の旧表示とREC継続を確認。
  - 期待結果: 方向／理由が本人判断に有用、不確かなら保留し旧OK失効。飽和から精密量を捏造せずREC可能。
  - Verify / 証拠: 場面・本人判断・案内／根拠・時刻／世代・原本。
  - 事前合意・Stop: 代表例・露出意図・評価方法／許容条件、有効期間等の設定版を事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-07/c01<br>AC-FR-06-01<br>U01/U04 | 意図別の濃く/薄く/現基準許容の合意場面<br>→ 本人判断とND方向/理由を同一場面で比較 | 方向/理由が本人判断に一致。常時保留だけで合格にしない | 場面/本人判断/解析入力信号/結果/暫定基準版 | S46、Q01品質合意 | 実画素解析/通常接続済。閾値は交換可能な暫定、品質未確認 |
| DV-07/c02<br>AC-FR-06-02<br>U01/U04 | 人物背景両立困難、太陽/反射/黒い服の有無<br>→ 各対象を加減し意図/評価対象を切替 | 単一対象を無条件正解にせず理由/難しさを示す。存在だけでNGにしない | 入力場面/露出対象/信号/方向理由/本人判定 | S46、Q01品質合意 | 制御/実画素試験済。シーン評価は未確認 |
| DV-07/c03<br>AC-FR-06-03、AC-FR-01-03、AC-NFR-03-02<br>U01/U02 | 遅延/停止/根拠不足/旧世代×暫定1秒前/境界/後、手動ISO/絞り変更<br>→ 解析を止め/遅延し設定変更、警告/保留中にREC | 旧OK失効、精密段数量を捏造せずRECを妨げない。変更値で再評価し勝手に戻さない | 入力観測時刻/失効/世代/手動値/REC/原本 | S46/S41/S43、Q01 | 暫定1秒は承認済。実端末期限/信号適合は未確認 |
| DV-07/c04<br>AC-FR-06-04<br>U01/U04 | 待機Auto WB変化→REC固定、飽和/低情報入力<br>→ WB前後でND評価継続、飽和入力で根拠を観測 | RGB一致をWB目標にせず、飽和から正確な余裕を逆算しない | WB/入力信号/ND根拠/時刻/原本 | S42/S46、Q01 | WB/ND接続技術確認済。実Log入力は未確認 |

### A08 / DV-08 ズーム

- [ ] Status: pending
  - Depends: S47,Q01,A01/A04の該当カメラ・補正。
  - 関連AC・gate: AC-FR-07-01〜03、AC-CF-07、AC-DI-11/12。
  - 対象・操作: 1. 目標選択して予告中の実倍率を記録。2. 寄る／引くを開始し目標自動停止。3. 再操作で途中停止、録画は継続。4. 待機／録画・補正・停止候補有無を変え予告と実画角・画質を比較。
  - 期待結果: 予告倍率不変・非焼込み、ズーム停止とREC停止別、目標超過せず停止、根拠ある近傍支援。
  - Verify / 証拠: 操作動画、実倍率／camera／補正、予告／原本、停止前後画質、暫定／採用設定版。
  - 事前合意・Stop: 速度・停止精度・吸着許容差・滑らかさ・画角差・画質・負荷の事前条件。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-08/c01<br>AC-FR-07-01<br>C11/U04; CF-07; DI-11 | B0×待機/録画、寄る/引く、camera/補正/倍率変更と旧予告<br>→ 目標選択→構図予告、開始前に実倍率と原本を照合 | 予告だけで実倍率不変、非焼込み、旧予告失効。別カメラ画質を完全再現としない | 予告/実倍率/camera/crop/原本frame | S47/S48の当該予告、Q01 | ズームUI/規則は部分。標準表示とISO関連は未接続 |
| DV-08/c02<br>AC-FR-07-02<br>C11; CF-07; DI-11/12 | B0×寄る/引く×目標自動停止/本人途中停止、速度/精度/吸着設定版<br>→ 明示移動開始、目標/途中停止後も録画、別操作でREC停止 | 目標超過なし、ズームと録画停止を区別、合意範囲の滑らかさ/精度 | 倍率/操作/SDK時刻/原本、暫定設定の目的/根拠/変更箇所/版 | S47、Q01品質合意 | 制御候補は部分、実機採用値は未決。未合意値を採用しない |
| DV-08/c03<br>AC-FR-07-03<br>C10–11; CF-06/07; DI-12 | B全補正×実経路、停止近傍候補あり/なし、ズーム中/停止後<br>→ 予告と実画角、近傍停止位置画質、引き方向と補正画角/負荷を別比較 | 整数倍率で画質保証せず、動作中/停止後の画質・画角差・負荷を各合意条件で評価 | 停止候補根拠/camera/codec/解像度/比較原本/予告/負荷 | S44/S47、Q01品質合意 | 候補規則は部分。近傍支援の画質/数値採用は未確認 |

### A09 / DV-09 レンズ・ISO

- [ ] Status: pending
  - Depends: S47,Q01,A01/A04の対応経路。
  - 関連AC・gate: AC-FR-08-01〜03、AC-CF-07。
  - 対象・操作: 1. 録画中の対応切替と戻し。2. 手動ISO変更後にも同じ操作。3. 非対応条件／補正維持不能を選択。4. 前中後の映像音声と実値・時刻を比較。
  - 期待結果: 切替中だけ限定補正、以後保持、常時Autoなし。他設定無断変更なし、非対応無通知実行なし。
  - Verify / 証拠: 前中後の原本／音声／実値／時刻、戻り基準と制御版。
  - 事前合意・Stop: 戻り／手動変更後ISO基準・上限・方式未合意を解消し、連続性・品質条件を事前合意。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-09/c01<br>AC-FR-08-01<br>C12; CF-07 | B×全有向E、往路/復路、本人手動ISO変更前/後<br>→ 前→切替中→後、戻しと手動変更後の再移行を各run | 限定区間だけISO補正し終了値保持、常時Autoなし、shutter/fps/WB方針無断変更なし | 実camera/ISO/WB/shutter/fps/補正/時刻、原本 | S47、Q01とISO方針合意 | ISO戻り/上限/基準の本人回答待ち。通常policy=nil、該当機能不可 |
| DV-09/c02<br>AC-FR-08-02<br>C12/U04 | 対応/非対応E、形式不一致/補正維持不能/実適用失敗・不明<br>→ 本人切替要求と実値読戻し、非対応要求を観測 | 表示は実値、不能切替を無通知実行しない。未確認を対応済みにしない | 能力・実値・拒否/制約表示/対象経路 | S47/S44、Q01 | 拒否/規則候補は試験済。実レンズ経路未確認 |
| DV-09/c03<br>AC-FR-08-03<br>C12/C16; CF-07 | 全対応E、静止記録→移行あり→静止記録、同一場面/音源<br>→ 前中後の途切れ/明るさ/色/ピント/位置/時間/音声同期/継続を評価 | 各事前許容範囲を満たすか制約/代案を残す。試験実施だけで対応済みにしない | 比較原本/時系列/AV同期/品質条件/不成立分類 | S47、Q01品質合意 | ISO方針/実経路/品質未成立のため該当評価不可 |

### A10 / DV-10 音声・障害

- [ ] Status: pending
  - Depends: S43,S12,Q01,A01の該当記録。
  - 関連AC・gate: AC-FR-09-01〜04、AC-CF-04。
  - 対象・操作: 1. 通常音と静寂で待機／録画。2. 合意した権限・入力・書込障害を各段階へ。3. 停止と保存分類を照合。4. 有限復旧・失敗後導線と本人RECを確認。
  - 期待結果: 音量／入力／到着／書込別、静寂正常、確認済み障害で抑止／停止、部分／不明／失敗を分け、復旧後も自動RECなし。
  - Verify / 証拠: メーター・入力・到着／書込・保存音声、障害／復旧時系列。
  - 事前合意・Stop: 障害再現方法・猶予／上限・復旧範囲の事前確認、必要な品質条件。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-10/c01<br>AC-FR-09-01<br>C06/U02; CF-04 | B0×待機/録画×通常音/静寂/小音量/安全な音割れ相当、初期化/再接続確認中<br>→ レベル・入力有効性・データ到着・書込・保存音声を別照合 | 静寂だけで×/開始禁止/停止にしない、音割れ≠入力不能、確認中を区別 | メーター/音声到着/書込/原本音声/表示 | S43、当該A01記録、Q01 | 通常policy/メーター/実sample試験済。実聴取/入力品質は未確認 |
| DV-10/c02<br>AC-FR-09-02、AC-FR-09-04、AC-NFR-03-02<br>C07/C14/U02; CF-04 | 権限拒否/入力不達/経路中断/writer音声書込失敗×REC前/中×正常/部分/不明/失敗<br>→ 合意手段で障害、実抑止/停止/保存分類と画面を照合 | 確認済み障害だけ抑止/停止し可能部分保存を試す。保存成功や救済を保証せず音声非省略 | 障害根拠/2秒到着猶予policy/停止/原本音声/分類/表示 | S43/S12、Q01 | 障害・保存境界は技術試験済。実OSと注入を分けてQ01後 |
| DV-10/c03<br>AC-FR-09-03<br>C07/U02 | 復旧成功/有限失敗/5秒期限/画面離脱、本人操作1回につき1試行<br>→ 明示復旧→結果→本人REC。権限不足なら設定案内、失敗なら保存結果と開き直し案内 | 復旧成功でも自動RECなし、無限retry/アプリ自動再起動/動画・App削除の手順なし。期限受付だけで待機を消さずSDK復旧/取消actual returnまで次REC/重複復旧を拒否 | 復旧/取消actual return/期限/本人操作/保存結果 | S43/S49復旧wait、Q01 | 2秒/1試行/5秒policy承認・接続済。実機復旧能力は未確認 |

### A11 / DV-11 起動・次REC・負荷

- [ ] Status: pending
  - Depends: S49,S4V,Q01。単独開始測定はS41/S43から可。
  - 関連AC・gate: AC-NFR-01-01、AC-NFR-03-01〜02、AC-CF-09。
  - 対象・操作: 1. 初回権限／通常起動／復帰を別測定。2. 連続撮影の次RECを測定。3. 通信・解析・表示・保存を重ねREC。4. 通常利用内の熱／空き容量を記録。
  - 期待結果: 2〜3秒目標と制約を把握、音声省略・無断設定変更・自動削除なし。安全な継続。
  - Verify / 証拠: 操作→実記録の時計対応・設定・温度／容量の取得可能範囲・原本。
  - 事前合意・Stop: 組合せ・負荷・反復と品質。端末容量埋め／極限温度の推測合格なし。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-11/c01<br>AC-NFR-01-01<br>C01/C17; CF-09 | 初回権限/通常起動/背景復帰、保存設定あり/なし<br>→ 本人入力→準備→実記録可能/最初frameの時計対応と所要時間を測る | 通常2〜3秒目標と制約を記録。初回権限と通常を混同せず音声を省略しない | 版/実値/起終点/時計誤差/全反復値/原本 | S41/S43、Q01 | 単独開始計時のコードは接続済。S49/S4V全完了不要、実測は未実施 |
| DV-11/c02<br>AC-NFR-01-01<br>C13/C17/B7; CF-09 | 連続二本以上、保存中/結果commit後/遅いhash・bind・一覧更新中の次REC<br>→ STOP→保存境界→次RECを各条件で計時 | 保存実終端前は待機、後処理だけを次RECの一律条件にしない。旧saveが新REC状態を変えない | clip別owner/時刻/保存結果/後処理/次REC原本 | S41/S43/S49保存境界、Q01 | owner/通知両順序/次REC技術試験済。実録画での時間は未確認 |
| DV-11/c03<br>AC-NFR-01-01、AC-NFR-03-01、AC-NFR-03-02<br>C16/C17; CF-09 | 標準集合B全セル×手動/WB/音声/Rec709/補正/寄る・引く・停止/全対応E、代表長と連続二本以上<br>→ 単独基準と同時成立を同条件で比較し通常範囲の熱/空き容量/負荷を記録 | 全必須要素の動作と品質を別評価。不能経路も残し、LT以外で標準成功を代替しない | 全設定時系列/原本/描画/AV同期/保存/次REC/比較、品質条件 | 該当S41–S49接続、Q01品質合意 | 標準表示/ISO/全媒体が不足。現在同時成立評価は不可、単独枝は継続可能 |
| DV-11/c04<br>AC-FR-16-02、AC-NFR-01-01<br>C16/C17/V07 | 各媒体実I/O/hash中REC、録画/保存/異常処理とWi-Fi待機の重畳<br>→ local実停止→REC→保存actual return→全条件再照合、Mac既開始処理を並行観測 | Mac ACKをREC条件にせずMac検証/変換は継続。未接続を実負荷確認済みにしない | 端末SDK/source/lease/recording/save、Macjob/通信byte、開始遅延 | S23/S49全媒体実接続、Q01 | S23/S49は独立基盤のみ。通常strict通信・全媒体接続不足により製品実通信は不可 |

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


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-12/c01.01<br>AC-FR-11-01、AC-FR-11-04<br>V01/V03; BI-01/03/06 | Wi-Fi、複数選択/選択だけ/開始済順番待ち/新撮影、個別送信・検証・変換失敗/共通回線・認証・Mac容量問題<br>→ 開始時集合固定し保存先全内容照合、未指示を追加せず動画別に処理 | HTTP完了≠保存検証。個別失敗を残し独立残件続行、共通障害は影響集合だけ待機、変換失敗で原本再送なし | 固定集合/操作ID/端末・保存先hash/保存証拠/job/動画別状態 | S13/S23/S24/S24I/S28、当該G2B/G2C原本、Q01 | S23/S49は独立基盤のみ。通常strict通信・全媒体接続不足により製品実通信は不可 |
| DV-12/c01.02<br>AC-FR-11-02、AC-FR-11-03、AC-NFR-02-01、AC-NFR-02-03<br>V03/V04; BI-04/05 | chunk受信/組立/最終確定/独立全読戻し/証拠commit/job受付/応答の各前/後×切断/再起動/破損/不一致/容量相当<br>→ 許可隔離先で故障後同一操作を照合して必要処理だけ再開 | 不明を未実行/verified/整理可能にせず原本/登録/job無条件重複なし | 端末/サーバfile・DB・全hash/操作/応答欠落/exact照会 | S24I/S28、Q01 | 保存先S24境界は隔離試験済。端末通常転送結合は未接続 |
| DV-12/c01.03<br>AC-FR-16-01、AC-FR-11-02、AC-FR-15-04<br>V05; BI-07 | 原本upload/軽量download/stream・Range/一時取得/thumbnail×直接LAN/外出Wi-Fi+Tailscale×前景/背景/途中再開×Wi-Fi離脱/基礎回線切替<br>→ 各経路で実byte通信と実停止を観測。取得済ローカル再生を別観測 | 媒体cellular移行なし、VPN表示だけで判断せず待機。local再生はネット不要 | 基礎回線/byte/SDK callback/固定identity/停止資源/画面 | S23/S24I/S25/S28の当該producer、Q01 | S23/S49は独立基盤のみ。通常strict通信・全媒体接続不足により製品実通信は不可 |
| DV-12/c01.04<br>AC-FR-16-02、AC-FR-16-03<br>V07; BI-09/10 | 全媒体×REC/保存/異常終了×Wi-Fi離脱復帰×saving terminal先着/後着。Wi-Fi/REC・保存/認証の成立可能な全待機部分集合と解除順、三条件同時×本人継続/停止/取消（recording→saving実順序維持）<br>→ 通信中REC、STOP/保存を段階別に解消、本人意思・認証・対象/版を再照合 | 録画/保存中再開なし、全条件成立後の既開始未完了だけ再開。Mac停止ACK非条件、Mac既開始処理継続。最後のwait解消前は通信せず、停止/取消は全解消後も保持 | local actual stop/lease/hold/保存応答/再開/byte/Macjob時系列 | S23/S49/S28実接続、Q01 | S23/S49は独立基盤のみ。通常strict通信・全媒体接続不足により製品実通信は不可 |
| DV-12/c01.05<br>AC-FR-16-03<br>V01/V04; BI-10/11/12 | 本人pause/resume/cancel/全件停止×実行中/指示済待ち/自動待機×Wi-Fi/REC/認証wait×再起動。Wi-Fi/REC・保存/認証の成立可能な全待機部分集合と解除順、三条件同時×本人継続/停止/取消（recording→saving実順序維持）<br>→ 各操作後に環境復帰、再open、本人再開も他wait残存中/解消後に行う | pause/cancelを解除せず、全件停止は指示済待ちも含む。未指示/完了/終了済再生/未実行削除/unknownPhotosを自動開始しない。最後のwait解消前は通信せず、停止/取消は全解消後も保持 | 意図/固定集合/重畳wait/operation/再open/byte/表示 | S23/S28当該操作、REC重畳のみS49、Q01 | S23/S49は独立基盤のみ。通常strict通信・全媒体接続不足により製品実通信は不可 |
| DV-12/c01.06<br>AC-FR-16-01、AC-FR-16-03<br>V08; BI-14 | 本人開始upload/download×別App/lock/OS待機・中断/強制終了復帰×Wi-Fi断/認証断/本人停止<br>→ OS条件と実callback/結果を記録して復帰照合 | OS許可範囲の継続/待機/中断を区別、本人意思と全再開条件維持。前景成功は背景証拠にしない | 端末/OS/保護/ネット/SDK task journal/実終端・source閉鎖/復帰結果 | S23通常adapter/S28、Q01 | S23/S49は独立基盤のみ。通常strict通信・全媒体接続不足により製品実通信は不可 |
| DV-12/c01.07<br>AC-FR-16-01、AC-FR-16-03<br>V06; BI-08/24 | モバイル状態照会/保存検証変換結果/版情報/既存確認outbox/失効commit・ACK、認証失敗/古い応答/媒体混入<br>→ 状態のみ同期し最終取得と最新照合/量・頻度を観測 | 媒体自動取得/再生/新確認なし。失効受信≠commit、commit後はWi-Fiなしでも整理不可 | 要求種別/byte/版/commit/outbox/ACK/最終照合時刻/表示 | S27/S28制御同期、Q01 | E-S28-01で既存登録の明示1page metadata同期/通常UI/実HTTP2要求・媒体0を確認。全mobile実網/頻度量・全producer/再登録は未確認 |
| DV-12/c01.08<br>AC-FR-11-03、AC-FR-11-04、AC-FR-16-03、AC-NFR-02-01、AC-NFR-02-02<br>V04; BI-05/10/11/33 | 端末request/batch意図・本人停止・証拠・確認/失効outbox commit各前/後、送達前/後×応答欠落/再open/未知schema/破損/保護/容量相当/世代競合<br>→ 元mutation・固定集合・本人意思・outbox/exact結果を再openして照合。確認/失効の詳細はDV14、PhotosはDV16へ対応 | 未記録の本人actionを生成せずunknownを未実行にしない。停止意思/未確定証拠を維持、別登録へ付替・一律再送なし。HTTP受付だけでoutboxを退役しない | 各commit/送達の実到達、元payload/lookup/再open/保全/動画別状態 | S21/S22C/S23/S24I/S27/S28の該当永続操作、Q01 | S23/S49は独立基盤のみ。通常strict通信・全媒体接続不足により製品実通信は不可 |
| DV-12/c02.01<br>AC-FR-11-01、AC-FR-11-02<br>V02; BI-02 | 書込中/normal/partial/unknown/failed/検査不足/アクセス不能/復旧未完了/別内容、内容対応commit前後/設定・store更新<br>→ 各状態で対象固定転送を要求し、正常だけG2B/G2C証拠を追加 | 拒否枝に正常撮影合格を前提追加せず、別file代替/正常化/原本削除なし | 状態準備とidentity/拒否/byte/前後file・store・表示 | S13/S24I入口、書込中だけS41、Q01 | 原本内容・lease規則は試験済。通常転送入口/UI未接続 |
| DV-12/c03.01<br>AC-FR-11-03、AC-FR-16-03<br>V01; BI-13 | 本人cancel→後発Mac成功→新本人再実行、応答喪失/再open<br>→ 前操作実結果をexact照合して新操作に必要な処理だけ実行 | 依頼終了とMac実成功を別表示、原本保持、無条件全量再送/新登録なし | 操作/登録/原本identity、cancel/成功/再操作/byte/永続結果 | S24I/S28、RECなしならS49不要、Q01 | 規則・exact照会基盤あり。通常転送再実行UIは未接続 |

### A13 / DV-13 軽量版品質

- [ ] Status: pending
  - Depends: S26,Q01。採用実LogはA01、品質G3合意後。
  - 関連AC・gate: AC-FR-12-01〜03、AC-BI-16/17/32、撮影D02・B-G3/G5。
  - 対象・操作: 1. 許可された採用Log素材と標準資材を照合。2. 縦横／24・30fps・肌／空／暗部／細部／動き／音声を候補変換。3. 本人通常サイズ／通常再生で色と圧縮劣化を別比較。4. 許容候補の容量／取得時間を比較して採用版を記録。
  - 期待結果: 原本不変・実Rec.709、fps／構図／向き／音声／日時／開始終端／同期維持。別高品質版を製品へ追加しない。
  - Verify / 証拠: 資材版／変換条件、入力出力照合、本人比較・採用理由・取得量／時間。
  - 事前合意・Stop: G3素材・表示条件・比較方法・許容範囲を試験前合意。旧MediaVault使用範囲はNFR-04、写真最終結合はDV-16。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-13/c01<br>AC-FR-12-01、AC-FR-12-02、AC-FR-12-03<br>V10; BI-16/17 | 採用実Log別×縦/横×24/30×音声、標準資材適合/欠落/誤Log/二重変換<br>→ 保存検証証拠後に変換し元原本/出力を独立照合、旧compress-onlyも区別 | 実標準Rec709だけ成功、原本不変、高品質版追加なし、fps/向き/比率/構図/音声/日時/冒頭末尾/長さ/同期保持 | 入力出力hash/特性/変換資材条件/実映像、禁止補正なし | S26適合資材と実Logadapter、当該A01素材、Q01 | 標準資材/actual-log-parser未適合。正式変換不可、job周辺のみ確認済 |
| DV-13/c02<br>AC-FR-12-02、AC-NFR-03-01、AC-NFR-03-02<br>V10; BI-32 | 肌/空/暗部/細部/動き/音声、同一標準変換参照と圧縮候補、本人iPhone通常サイズ/通常再生<br>→ G3事前条件で色と圧縮劣化を別比較、許容候補の容量/取得時間を比較 | 未合意/未測定/範囲外は合格なし。G5採用と技術生成を分け、写真最終結合はDV16 | 比較入力/表示/方法/許容/有限候補数/出力版/本人判断/容量時間 | S26、Q01 G3品質事前合意 | 具体素材/表示/許容/候補数/出力設定未束縛。品質試験不可 |
| DV-13/c03<br>AC-FR-12-03<br>V12; BI-21 | 変換設定新版、V1公開/有効確認あり、V2生成成功/失敗<br>→ 旧原本を保持し候補だけ作成、公開/確認状態を別照合 | 原本上書きなし。V2生成だけでV1差替/確認失効/原本再転送をしない | 候補/claim/旧公開・確認/原本hash/失敗結果 | S26J/S27、品質比較はQ01 | job/candidate技術確認済。正式映像はS26待ち |
| DV-13/c04<br>AC-FR-12-01<br>V03/V10; BI-03/16 | 保存証拠なし/unknown/失敗/旧file_verifiedだけ/別原本・登録・session対応<br>→ 各不適格証拠で変換job開始を要求し、原本/公開版/確認を照合 | 自動変換やverifiedへ進まない。LUT取得や正常G2B全体を拒否枝の前提にしない | 証拠payload/対象対応/拒否/job未開始/旧公開版保持 | S24/S26Jの保存証拠入口、Q01 | 入口拒否とjob技術試験済。実端末/隔離実行は当該条件束縛後、S26資材不要 |

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


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-14/c01.01<br>AC-FR-10-01<br>C01/C13/V09; BI-15 | 保存対応済み実撮影原本1本、online/offline、途中停止/再open<br>→ 製品Library→対象原本playerで映像/音声を実再生し停止/再選択 | 媒体一致、実停止/lease解放、原本閲覧だけで軽量版確認/Photos状態を生成しない | clip/内容世代/digest/保存証拠、player進行/音声/lease/前後状態 | S13/S15/S16、当該A01/A02原本、Q01 | 原本/通常UI/実AVPlayer技術確認済。P2 strict監査4件は未解消、実撮影原本は未確認 |
| DV-14/c01.02<br>AC-FR-10-03、AC-FR-16-01<br>V09; BI-15 | 取得済local/未取得軽量版/原本なし×Wi-Fiなし/Mac不通<br>→ 各所在状態から再生と表示を照合 | 取得済localのみoffline可。未取得を再生可能と偽らず、単なる不通では有効確認失効なし。整理へ接続/写真を強制しない | 所在/取得範囲/再生可否/確認/整理候補/画面 | S14/S25/S28の該当UI、Q01 | local原本と保存済metadataの通常投影を接続。公開記録をoffline再生可能の証拠にしない。軽量版の通常再生UIは未接続 |
| DV-14/c02.01<br>AC-FR-13-01<br>V09/V11; BI-18/19 | 固定公開版1本、全量前の実再生/seek/Range・切断再開/認証失敗、同じ写真用映像、redirect/別版/MIME不一致/短い・過大body、同時Range/停止中buffer・reader遅延解放<br>→ 実進行後に本人1本確認しcommit。閲覧だけ/同期/背景/複数選択/撮影予告/未変換Logも別要求 | 全量/全編を要求せず実再生+本人+同版commitだけ確認。byte/認証/版混在拒否、確認だけでPhotos済にしない。redirectや版不一致を別媒体へのfallbackにせず資源終端を照合。一時量とSDK/FD/leaseの実終端を確認し、取消受付で解放済みにしない | bytesAtProgress<total、decoded/音声/再生token/本人操作/commit/媒体identity/一時量 | S25/S27/S28、製品品質枝だけ当該A13採用版、Q01 | S25とS27の技術証拠を参照。正式変換proofと通常軽量版/本人確認UI・再登録接続不足（S28既存登録metadata/UIのみ部分接続）、fixtureを製品受入にしない |
| DV-14/c02.02<br>AC-FR-13-02、AC-NFR-02-01、AC-NFR-02-03<br>V04/V11; BI-20 | 確認受付/commit各前後×失敗/中断/応答欠落/旧版応答/失効競合<br>→ 本人確認後に障害、exact lookupと再openで対象/世代を照合 | 不明/拒否を有効確認/整理可能へしない。commit前未記録actionを自動生成せず旧tokenで復活なし | 完全mutation/commit/lookup/outbox/世代/画面 | S21/S27/S28、Q01 | S25とS27の技術証拠を参照。正式変換proofと通常軽量版/本人確認UI・再登録接続不足（S28既存登録metadata/UIのみ部分接続）、fixtureを製品受入にしない |
| DV-14/c02.03<br>AC-FR-13-03、AC-FR-13-05<br>V12; BI-21 | 初回V1変換失敗、未失効V1有効中のV2成功/失敗、失効前offline<br>→ V2候補を生成/失敗させ、V1公開・有効確認・offline整理を照合 | 初回有効版なしは整理不可、未失効V1なら他条件維持。V2生成だけで無通知差替なし | 候補/公開head/旧確認/最後の保存証拠/整理可否 | S26J/S27、整理はS32/S34当該操作、Q01 | S25とS27の技術証拠を参照。正式変換proofと通常軽量版/本人確認UI・再登録接続不足（S28既存登録metadata/UIのみ部分接続）、fixtureを製品受入にしない |
| DV-14/c02.04<br>AC-FR-13-04、AC-FR-13-05、AC-NFR-02-02<br>V04/V12; BI-22/23 | 失効commit前/後→ACK前/後→公開前/後×切断/再open/V2失敗<br>→ 旧版受取登録（確認同期未到達を含む）へ失効、実owner終了後commit/ACKを照合 | commit前は旧有効確認保持、後は再起動/保留/失敗でも非復活。全必要exact ACK前は公開不可 | recipient/registration/失効ID/SDK・FD・lease/commit/ACK/head時系列 | S27全owner終端/S28、Q01 | S25とS27の技術証拠を参照。正式変換proofと通常軽量版/本人確認UI・再登録接続不足（S28既存登録metadata/UIのみ部分接続）、fixtureを製品受入にしない |
| DV-14/c02.05<br>AC-FR-13-04<br>V12; BI-22/26 | 全公開入口、旧/別登録/別原本・映像/別世代ACK、ACK改変/欠落/timeout、旧登録応答不能。同一公開対象R1/R2（R2は確認同期未到達）＋待ち中の新受取R3、ACK一部/重複/全件、R1→R2とR2→R1の両順序、対応commit未確認のACK<br>→ 各ACKと再登録を与え公開を要求、該当動画と別動画を照合 | 旧登録の必要応答を代用せず該当差替無期限保留。正常別動画と利用可能旧版を妨げない。各required登録が別に確定するまで保留し、新受取を集合から落とさない。受信だけ/未commit ACKで集合を満たさない | 必要ACK集合/完全payload/exact lookup/公開pointer/動画別結果 | S27/S28、Q01 | S25とS27の技術証拠を参照。正式変換proofと通常軽量版/本人確認UI・再登録接続不足（S28既存登録metadata/UIのみ部分接続）、fixtureを製品受入にしない |
| DV-14/c02.06<br>AC-FR-13-04<br>V09/V12; BI-18/22 | V1配布受理・台帳commit先行/V2公開pointer先行、manifestだけ→遅延GET/Range/再開、消費済ticket、全hash中の公開切替/受理済応答中のleaf差替<br>→ 両順序を再現し媒体byte前の判定、受理済V1応答と新要求を分離 | V1受理先行は必要集合追加/公開待機、公開先行は新V1要求byte0。単回GET再利用拒否、受理済応答に別版混在なし。受理済旧応答のSDK実completion/invalidation・same-FD閉鎖・lease解放も確認。既知app writerはsealed aliasを拒否。任意外部in-place改変は検出中断の限界を記録し、送出済byte取消/全版混在防止を保証しない | 配布/commit/pointer/GET順序、same-FD digest/range/byte0、原本/登録identity | S27全公開入口とS25/S28、Q01 | S25とS27の技術証拠を参照。正式変換proofと通常軽量版/本人確認UI・再登録接続不足（S28既存登録metadata/UIのみ部分接続）、fixtureを製品受入にしない |
| DV-14/c02.07<br>AC-FR-13-04、AC-FR-13-06、AC-NFR-02-02<br>V09/V12; BI-20/23/24 | 失効後の遅延受理済応答/local取得済V1再生/旧token確認、同版再取得/通常再open/Wi-Fi断だけ<br>→ 失効あり/なしを別runで再生・確認/整理状態照合、mobile失効commitも実施 | 失効済旧確認は復活なし、新版明示再確認まで整理不可。再取得/不通だけでは未失効確認を消さない | 版/epoch/失効commit/token/確認/ACK/実再生/画面 | S27/S28、local媒体はS25、Q01 | S25とS27の技術証拠を参照。正式変換proofと通常軽量版/本人確認UI・再登録接続不足（S28既存登録metadata/UIのみ部分接続）、fixtureを製品受入にしない |

### A15 / DV-15 新登録・旧登録

- [ ] Status: pending
  - 先行引渡し E-S22-01/S22C: server destination/intent/registration/世代/秘密を実SQLiteへ束縛し、同意図再送・応答欠落後再open・新登録と旧資格情報分離を新規26caseで確認（全46成功）。S22Cで端末同writer commit/Keychainのstore UUID束縛、同store中断と新store/残存資格情報の区別・実HTTP6件を確認済み。wire/copy/diffを保全。旧確認/必要ACK/公開との製品接続はS27/S28、実再インストール/保護領域は本票へ残し、実再登録受入には昇格しない。
  - Depends: S22C,S27,S28,Q01。
  - 関連AC・gate: AC-BI-25/26、AC-FR-13-04。
  - 対象・操作: 1. 許可方法で新登録条件を用意し通常再起動と比較。2. 旧確認を照合し新端末で通常一覧／取得／再生。3. 応答不能旧登録を必要ACK集合へ残し差替要求。4. 別動画処理と新確認後の整理候補を確認。
  - 期待結果: 旧確認を新登録へ復元せず、旧ACKを代用しない。該当差替だけ保留、通常利用・別動画継続。
  - Verify / 証拠: 接続先／登録世代、配布／必要ACK／公開、再確認対象と別動画結果。
  - 事前合意・Stop: 登録変更の対象／方法。既存App削除・データ初期化を前提にしない。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-15/c01<br>AC-FR-13-04<br>V13; BI-25 | 同store通常再起動/意図commit前後中断/結果応答欠落/端末commit前後/新store+残存Keychain/接続先不一致/bearerのみ<br>→ 同意図exact照会と新登録を分け、保護領域と世代を照合 | 重複初回登録なし、登録不明は媒体保留、新storeへ旧資格を無断採用しない | storeUUID/intent/登録世代/Keychain束縛/exact結果/再open | S22C、Q01 | 登録disk/Keychain/旧HTTP6件に加えE-S28-NEW-01のUUID/別namespace保持とINVENTORY-01の明示新登録/旧原本metadata実SDK取得を確認済。実端末交換/保護・許可操作は未実施 |
| DV-15/c02<br>AC-FR-13-04<br>V13; BI-25/26 | 新登録、旧有効確認/旧応答不能必要ACK、対象動画/独立別動画<br>→ 新登録へ状態取得→通常一覧/取得/再生→整理対象だけ本人再確認 | 旧確認を自動復元せず、全履歴再確認/一律原本再転送・再生成・写真再保存を要求しない | 登録世代/旧確認/required ACK/利用可能版/新確認/別動画状態 | S22C/S27/S28、Q01 | S25とS27の技術証拠を参照。正式変換proofと通常軽量版/本人確認UIは不足。明示新登録/別namespace/旧原本identityのremote専用一覧はE-S28-NEW/INVENTORYで部分接続、fixtureを製品受入にしない |

### A16 / DV-16 写真保存

- [ ] Status: pending
  - Depends: S31,Q01、S34の写真操作の実接続・必須検証の部分引渡し。S34の整理／破棄完了は不要。製品同一軽量版caseはA13/A14の当該版identityと証拠を使い、両票全体のdoneは待たない。
  - 関連AC・gate: AC-FR-15-01〜05、AC-NFR-02-02〜03、AC-BI-30、AC-DI-09/10。
  - 対象・操作: 1. 保存時初回追加権限・拒否を試し撮影導線も確認。2. Photos登録直後／管理commit前に合意手段で中断。3. 理由付き読取案内・拒否・限定・未発見を照合。4. 連打／再試行・複数保存・試験写真側削除後を確認。
  - 期待結果: 追加と読取を適時分離、不明は要確認・無条件再追加なし、写真側削除を自動復活しない。映像／日時／音声が同一、不要copy解放。
  - Verify / 証拠: 権限遷移・意図／結果／対応記録、写真再生／日時／音声・重複有無・tmp解放。
  - 事前合意・Stop: 試験媒体だけの写真側操作、実権限変更／中断方法。アルバム／手動再保存の未合意は採用しない。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-16/c01<br>AC-FR-15-01、AC-FR-15-04<br>V05/V15; BI-30; DI-09 | Wi-Fi本人開始、完全同一媒体/部分buffer/別版/範囲不足、取得中回線離脱/完全取得後offline<br>→ 同じ写真用映像を完全取得/使用権で渡しPhotosへ。部分/不一致は拒否。成功対象を写真で映像・音声・日時まで実再生する | 取得完了≠Photos済。取得はWi-Fi待機、正当に取得済みlocal登録にWi-Fi継続を要求しない | 媒体ID/範囲/hash/usage/SDK結果/Photos再生/日時/音声/tmp | S25/S31/S34写真操作、当該A13/A14版、Q01 | S31 SDK/永続/照合は技術確認済。新規保存producerとS34写真開始/複数UI未接続 |
| DV-16/c02<br>AC-FR-15-01、AC-FR-15-02、AC-NFR-02-03<br>V04/V15; DI-09/10 | 追加初回/許可/拒否/制限、撮影起動/本人写真保存/不明照合、readWrite拒否/限定/許可未発見/対応不明<br>→ 保存時add-only、必要な照合時だけ対象/理由を示すreadWrite案内。撮影も操作 | 一律読取要求なし、拒否で無関係撮影を止めず、未発見/限定を未保存の証明にせず要照合 | 権限/用途/意図/identifier/存在観測/理由/撮影UI | S31/S34該当権限UI、Q01 | 理由付き照合UI/許可拒否SDK確認済。通常新規保存UI未接続 |
| DV-16/c03<br>AC-FR-15-02、AC-FR-15-03、AC-NFR-02-02、AC-NFR-02-03<br>V04/V15; DI-10 | 連打/本人retry/SDK未開始/SDK成功・失敗・unknown、登録直後/管理commit前後中断、写真側本人削除<br>→ 同版intent/結果/identifierを再open照合し必要時のみ理由付き照会 | 無条件再追加/写真自動復活なし、過去成功と現在存在別。不明copy/証拠を捨てず他写真削除なし。失敗一時copyの回収方式/容量上限/期限は未合意・未実装を明記し、無制限保持を採用済みにしない | exact intent/terminal/FD閉鎖/usage/result/存在観測/実Photos件数 | S31/S34写真操作、Q01と当該写真側操作許可 | S31 SDK/永続/照合は技術確認済。新規保存producerとS34写真開始/複数UI未接続 |
| DV-16/c04<br>AC-FR-15-01、AC-FR-15-05、AC-FR-10-01<br>V01/V14/V15; BI-30/33 | 複数開始固定集合、一部取得/登録失敗・unknown・未処理/既保存/結果不明、整理前/後<br>→ 順次取得・登録し動画別結果を再open、不要copyと他usageを照合 | 全件成功表示なし、既保存/不明へ無条件再追加なし。最後の使用者実終端/成功後だけ不要copy回収、整理順序非強制 | 集合/動画別取得・登録・tmp/全usage/画面、同一映像・日時・音声 | S31/S34複数写真UIとproducer、Q01 | S31 SDK/永続/照合は技術確認済。新規保存producerとS34写真開始/複数UI未接続 |
| DV-16/c05<br>AC-FR-15-01、AC-FR-15-02<br>V15; BI-30 | 既知失敗+全usage実終端の不要copy/unknown照合に必要なcopy/他owner使用中/成功済<br>→ 回収候補と保持理由を分け、許可した使い捨て媒体だけで回収producerの実結果を照合 | unknown証拠/他usageを捨てず、既知失敗payloadを無制限残留させない。方針未成立なら未達、TTL/容量値を新設しない | 結果分類/terminal/usage全件/copy前後/回収意図結果/保持理由 | S31/S34の回収producerと合意方針、Q01 | 成功限定回収は実装済。失敗copy回収・容量/期限policy未合意/未実装の該当枝は不可 |

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


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-17/c01.01<br>AC-FR-14-01、AC-FR-14-03、AC-FR-14-05、AC-FR-10-03<br>V15; BI-27; DI-06 | 同一原本の有効保存検証+同一Rec709確認、Photosなし/backupなし、online/offline/Mac不通<br>→ 本人単数/複数整理、各unlink直前に証拠とreaderを再判定、再open照合 | 本人前は非削除、再接続/再生/Photos/高品質版非強制。実file不在+result一致後も通常一覧/独立状態を保持 | 元identity/完全証拠/意図/全reader終端/直前guard/unlink/result/一覧 | S32/S34整理UI、当該A12/A14有効run、Q01 | S32/S33に加えE-S34-CLEANUP-01で条件付き通常複数整理/固定3対象2unlink/不適格保持/再openを合成fixtureで確認。全正式producer/通常Photos/活動中・未知sourceの全停止は未接続 |
| DV-17/c02.01<br>AC-FR-17-01、AC-FR-17-02、AC-FR-17-03、AC-FR-17-04、AC-FR-17-05、AC-FR-10-01<br>V15; BI-28; DI-07 | 未転送/未検証/未確認/失効/部分/unknown対象、警告取消/別対象/リスク変化/明示単数指示<br>→ 対象と原本消失リスクを確認し一本ずつ破棄。Mac/Photosは前後保全 | 明示なし/一括/整理不適格から自動破棄なし。選択iPhone原本だけunlink、保存検証/確認は昇格せず成功だけ履歴、履歴は記録で非ゴミ箱 | 本人操作/対象リスク/実file・batch result/履歴/外部sentinel/独立状態 | S33/S34単数破棄部分引渡し、当該保存対応、Q01 | 通常単数UI/実unlink/再openの合成fixtureと、確定履歴の実SDK終端→通常modelの明示リスク確認→実unlink/再openを確認。実原本と未知transportは未受入 |
| DV-17/c03.01<br>AC-FR-14-02、AC-FR-14-07<br>V02/V15; BI-27 | online/offline×記録/対応=不明/欠落/失敗/失効/別内容/原本不在/未変換Log確認/旧候補だけ/再生だけ<br>→ 各枝で整理要求、正常G2Bや有効確認を拒否枝の前提にしない | 全枝非削除・破棄へ非移行、証拠昇格なし。理由と要照合を保持 | 準備根拠/identity/拒否/前後file・DB/画面 | S32/S34整理操作、Q01 | S32/S33に加えE-S34-CLEANUP-01で条件付き通常複数整理/固定3対象2unlink/不適格保持/再openを合成fixtureで確認。全正式producer/通常Photos/活動中・未知sourceの全停止は未接続 |
| DV-17/c04.01<br>AC-FR-14-04<br>V15; BI-27 | 最後の有効証拠後offline、端末未取得のMac試験原本消失<br>→ 別明示許可した隔離先試験原本だけ外部消失→端末手動整理 | 最後の有効記録で許容、現在Mac存在を保証せず接続/再生/Photos非強制。外部消失≠連動削除 | 外部操作許可/最後の取得時点/未取得証拠/表示/ローカルunlink照合 | S32/S34整理UI、当該A12/A14有効run、Q01と外部対象別許可 | S32/S33に加えE-S34-CLEANUP-01で条件付き通常複数整理/固定3対象2unlink/不適格保持/再openを合成fixtureで確認。全正式producer/通常Photos/活動中・未知sourceの全停止は未接続 |
| DV-17/c05.01<br>AC-FR-14-07、AC-FR-10-01<br>V01/V14/V15; DI-06 | 適格/不適格混合固定集合、一部失敗/unknown/未処理、各対象直前失効/世代変化<br>→ 複数整理開始後に条件変化/中断を与え再open | 毎本直前再判定、不適格は非削除/破棄非移行。動画別成否/必要照合、未実行自動削除なし | 固定集合/動画別guard・証拠/実file/結果/通常一覧/再open | S32/S34複数整理UI、適格枝のみ当該A12/A14run、Q01 | S32/S33に加えE-S34-CLEANUP-01で条件付き通常複数整理/固定3対象2unlink/不適格保持/再openを合成fixtureで確認。全正式producer/通常Photos/活動中・未知sourceの全停止は未接続 |
| DV-17/c06<br>AC-FR-14-06、AC-FR-17-06、AC-NFR-02-04<br>V04/V15; DI-08 | 整理/破棄×intent commit前/後・実unlink前/後・result commit前/後×失敗/中断/再open/応答喪失/アクセス不能<br>→ 境界actual到達を記録し再起動、照合だけを実施 | 実file/記録で削除済/未削除/要照合を分類。受付だけ成功化せず未実行unlink再試行なし、未知は通常導線で要照合 | batch/子intent/内容・dir/leaf identity/actual syscall/FD close/result/画面 | S32/S33/S34当該操作、Q01 | S32/S33に加えE-S34-CLEANUP-01で条件付き通常複数整理/固定3対象2unlink/不適格保持/再openを合成fixtureで確認。全正式producer/通常Photos/活動中・未知sourceの全停止は未接続 |
| DV-17/c07<br>AC-FR-14-05、AC-FR-14-06、AC-FR-17-03、AC-FR-17-05、AC-FR-17-06<br>V02/V15; BI-28 | 転送/再生/検査/Photos等の複数reader、停止受付/SDK実終端/FD閉鎖/lease実解放の各遅延、未知旧owner<br>→ 各目的の削除を要求し資源を一つずつ終了、別内容差替/新reader取得も試す | 全実解放前は非削除。不明旧ownerを空辞書で消さず、対象/同writer最終guardを通る時だけunlink | reader全表/SDK/FD/lease/epoch/reservation/hash/対象限定実unlink/外部保全 | S13/S23/S25/S31終端の当該接続、S32/S33/S34、Q01 | S32/S33に加えE-S34-CLEANUP-01で条件付き通常複数整理/固定3対象2unlink/不適格保持/再openを合成fixtureで確認。全正式producer/通常Photos/活動中・未知sourceの全停止は未接続。未知readerは拒否側だけ実施可能。E-S34-BG01は本物のsuspended1task終了から通常model破棄の技術証拠で、全owner/active停止の受入ではない |
| DV-17/c08<br>AC-FR-14-02、AC-FR-14-06、AC-FR-13-04、AC-NFR-02-04<br>V12/V15; BI-29 | 同一原本で失効commit先行/削除最終予約先行、両目的、各commit/unlink前後再起動<br>→ 失効と整理/破棄を両順序で競合しACKまで照合 | 失効先行は整理不可（破棄は別明示規則）。削除確定区間先行は結果照合まで失効ACK待機、旧確認非復活 | 同writer順序/予約/intent/unlink/result/tombstone/ACK/再open | S27該当失効とS32/S33/S34当該操作、Q01 | S32/S33に加えE-S34-CLEANUP-01で条件付き通常複数整理/固定3対象2unlink/不適格保持/再openを合成fixtureで確認。全正式producer/通常Photos/活動中・未知sourceの全停止は未接続。正式製品の失効結合は未接続 |

### A18 / DV-18 実データ範囲・全AC照合

- [ ] Status: pending
  - Depends: N00,S20,H01,Q01。各caseの実施可能範囲、実転送はA12。
  - 関連AC・gate: AC-NFR-04-01〜02、AC-CF-11、AC-BI-31/34、全79AC。
  - 対象・操作: 1. 対象／許可／経路を一覧化し旧MediaVaultは変換／preview、新規FrameRelay原本は転送へ限定。2. 前後保全と実施結果を各ACへ対応。3. リリース前整理の具体対象・方法・影響を提示し別明示合意。4. 合意後の対象だけ整理し結果・未実施／再試験を記録。
  - 期待結果: 許可範囲を逸脱せず未実施／不適合を残す。旧写真原本削除・汎用移行を前提にせず、整理の未許可を成功にしない。
  - Verify / 証拠: 対象／許可ID／操作、前後保全、79AC証拠対応、整理対象・方法・結果、未確認一覧。
  - 事前合意・Stop: 実データ削除／上書き・本番DB移行・デプロイは別許可。後二者は本計画スコープ外。未束縛条件はQ01、未接続は対応本体taskへ戻す。


引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:

| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |
| --- | --- | --- | --- | --- | --- |
| DV-18/c01<br>AC-NFR-04-01<br>V16; BI-31 | 旧MediaVault原本の変換/preview、新規FrameRelay原本の転送、許可対象/対象外<br>→ 匿名対象/経路/許可/前後保全を対応させ対象だけ操作 | 旧写真原本削除/汎用移行/無断上書きなし。旧実データを未許可接続で保持確認しない | 対象別許可/前後hash/両repo差分/媒体・管理記録/実施範囲 | N00/S20/H01/Q01、実転送のみ該当A12 | 隔離snapshot保全は確認済。実旧媒体は未操作、対象束縛後の許可範囲だけ可 |
| DV-18/c02<br>AC-NFR-04-02<br>V16; BI-31/34; CF-11 | リリース前試験データ整理、対象/方法/影響未合意→具体提示→対象別明示合意後<br>→ 消す/残す対象と復旧保全を提示し、合意後だけ整理結果を記録 | この要求だけで旧実原本/本番相当記録を削除しない。未許可は未実施、deploy/本番DB移行へ派生なし | 対象・破壊操作別許可/保全/実行結果/未処理 | N00/H01/Q01/H02の当該範囲 | 整理操作は未実施。具体対象・方法と別許可が必要、H01準備だけで実施済みにしない |
| DV-18/c03<br>AC-NFR-03-01、AC-NFR-03-02<br>C18/C19/V16; CF-10/11; BI-33/34 | 全失敗/不一致/証拠不足/原因未確認、全21要求79AC・CF11・BI34・DI18<br>→ 各runから原本・store・ログを辿り一要因比較/反証と影響AC/代案/次調査を記録 | 非対応/実装問題/原因不明を分離、一度失敗や機種名で断定せず、工程/実装/自動/実機/PRD/初期版を別判定 | 実装版/条件版/全ACの部分証拠・残件・再試験/品質合意/判定 | H01/H02、該当本体修正とQ01 | 机上追跡は今実施可。全実機D0/R未評価、H02・M07–10は未完 |
| DV-18/c04<br>AC-FR-10-01、AC-FR-10-02、AC-NFR-02-03<br>C01/C19/U05/V14; BI-33 | 実装済の撮影待機/開始/録画/保存/音声障害・復旧/設定/一覧通常・要照合・原本なし/詳細/履歴/原本・軽量player/登録/媒体操作結果×通常/最大文字×縦/横、読み上げとREC連打<br>→ 各実装状態の色以外の名称/値/理由/次操作を読み上げ、文字拡大/縦横/連打後も対象と結果を照合。未接続画面は未実施として残す | 全文/操作到達/44pt等の既存規則と入力排他を確認し、受付/一部成功を確定・全件成功にしない。strict監査失敗を無視せずP2残件を区別 | 画面/AX tree/読み上げ・文字/向き/二重command/永続証拠、strict監査結果・版 | 当該画面S14/S16/S28/S34/S41–S49部分引渡し、Q01 | E-P2-20261022-FIXで通常18件（前提別）・strict6/最大字4成功、実VO既存5条件を確認。聴取品質/実機/縦横の全状態は未評価、未接続画面は不可 |

## 検証証跡・レビュー記録

| 証拠ID | 日付・担当 | task／AC／DV | 実装版・条件版・環境 | コマンド／操作・対象 | 結果・件数・skip・診断 | 証拠参照・未確認・再開条件 |
| --- | --- | --- | --- | --- | --- | --- |
| E-S28-NEW-01 | 2026-10-24、worker/main/document_author/doc_reviewer | S28・BI-25/26、DV-15部分 | 32版296→現309入力、別第3root・残存foreign v2/空current store | 明示新登録/別namespace/create-only/UUID再照合、旧bytes非移植、入力取消/HTTP拒否/離脱・再起動 | 関連31宣言47展開、隔離実SDK35、既存初回UI52は2成功/skip0。SEED53は1成功/VERIFY1skip、UI54/最大56・57の失敗を保持し、helper/focusの限定修正後に58最大/59通常各1、60 VERIFY1/seed1skip、最新初回61は2成功。最終Unit62/旧UI63・64/照合65・66/unsigned build67成功 | [新登録証跡](evidence/20261023-new-registration/README.md)。正HTTPS UI/正式媒体/全S28/実機未完。29〜31/54失敗と原本0/旧Keychain保持を分離 |
| E-S28-INVENTORY-01 | 2026-10-24、worker/main/document_author/doc_reviewer | S28・FR-10/13/NFR-02、DV-15部分 | 307→現309入力、隔離server snapshot274・専用第4root | 認証metadata32+1→同writer/exact lookup→remote一覧/内容衝突/現在存在未照合、閉鎖HTTPSの通常失敗 | server279case、端末関連36宣言75展開、実SDK35は33件/再open/media0/全owner終端。UI49/50は通常/AX5各1成功・各12全監査、51はVERIFY1成功/seed1skip・全reader空とMOV2/manifest/Keychain不変。最新Unit62は有意味1019成功/36skip、通常・最大旧UI各2/照合65・66/unsigned build67成功 | [inventory証跡](evidence/20261023-remote-inventory/README.md)。33/38〜47の途中失敗保持、通常HTTPS/正式manifest・媒体操作/全S28/実機未完 |
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
| E-S48-01 | 2026-10-20、explorers/worker/document_author/doc_reviewer/main | S48独立部、AC-FR-02-01/02と既存拒否/UI回帰 | 最終224入力、test-02/ios-build-01/現物一致 | 各command/run/source hash、実fixture描画/入力不変/二重変換拒否/有界保持/世代と停止失効 | Unit19宣言24展開＋UI1成功、Simulator/iOS build成功、失敗/skip/runtimeWarnings/compiler/analyzer0。初回compile失敗/0件・5警告保持 | `evidence/20261020-s48/`。S48本体は標準資材/実Log/通常接続待ちblocked、DV-05・独立validation未確認 |
| E-S31-02 | 2026-10-21、explorer/workers/document_author/doc_reviewer/main | S31終端/use解放・失効接続、AC-FR-15/AC-NFR-02と限定回帰 | 最終245入力、test-01/ios-build-01/実Photos2run/現物一致 | 各run/source、両store/commit欠落/実MOV2scope/取消し/全解放/ACK/再open・実PhotoKit許可拒否 | Unit440宣言653展開＋UI4、実Photos許可/拒否各2、build成功、skip21/実Photos各2を分離、失敗/診断0 | `evidence/20261021-s31-terminal/`。初回result抽出DB競合保持。S31全体は通常producer/複数保存等でblocked、実機/独立validation未確認 |
| E-S14-P2-20261022 | 2026-10-21〜22、worker/main | S14/S16・Library AX | 当時のstrict最終260入力、当時のLibraryView同hash | strict監査/実文字/VoiceOver/CF保全 | strict14成功/4失敗、通常・最大AX5文字確認は成功 | evidence/20261021-library-accessibility/ と evidence/20261022-removal-composition/。当時P2未解消/現288全strict未実行、修正後はE-P2-20261022-FIX |
| E-S32-03 | 2026-10-21、worker/main | S32・原本実削除 | 253入力、両store/実MOV | 固定batch/同FD全hash/最終guard/unlink/中断/再open | Unit685展開成功(有意味684)/21skip、iOS build成功、診断0 | evidence/20261021-removal-core/。core done、製品整理UI/実機は別 |
| E-S33-01 | 2026-10-21、worker/main | S33・単数risk破棄 | 255入力、S32実機構 | 本人risk/目的分離/実unlink/外部保持/不明照合 | Unit706展開成功(有意味705)/21skip、Simulator build成功、診断0 | evidence/20261021-discard-core/。core done、UIはS34へ |
| E-S34-01 | 2026-10-22、worker/main | S34単数UI・結果/履歴 | 260入力、専用合成seed | 通常確認UI→実unlink→再open/履歴/保持対象照合 | Unit726展開/23skip、専用UI1/実disk照合1成功、seed1skip | evidence/20261022-removal-composition/。全S34/通常整理/Photos/複数UI未完 |
| E-S23-01 | 2026-10-22、workers/main | S23背景資源基盤 | 275入力、schema7/同writer | session/task/context/event drain/管理source copy・自身FD終端 | Unit816展開(有意味815)/25skip、実SDK2/UI3/build/CF照合成功、診断0 | evidence/20261022-background-media/。strict開始/resume/download受入口/旧source採用・全媒体は未成立 |
| E-S49-01 | 2026-10-22、worker/main | S49 REC/保存hold | 279入力、candidate03 | owner別wait/preflight/実file return/通知両順序/次REC | Unit841展開(有意味840)/25skip、通常UI3/build/CF照合成功、診断0 | evidence/20261022-capture-media/。最終SDK resume排他/全媒体実停止/実網RECは未成立 |
| E-S27-01 | 2026-10-22、workers/main | S27公開/確認/失効の技術結合 | backend273・iOS279、凍結checkpoint | 隔離pytest/実HTTP/AVPlayer/確認commit-exact lookup/解放/ACK後V2公開 | 170node230case・実HTTP1成功/skip0、全12観測と実process/FD/thread終端 | evidence/20261022-publication/。正式proof/全製品owner/通常UI/品質未成立、旧失敗保持 |
| E-S26A-01 | 2026-10-22、main | S26A資材事実/比較案 | design D02/一次資料 | Log1/Log2入力差/標準資材不足/技術適合とG3比較を記録 | 資料・diff/hash/リンク確認、資材取得・変換・品質試験は未実施 | evidence/20261022-transform-research/。資材実体/由来・版/hash/利用条件/数値域/既知入出力待ち |
| E-S28-01 | 2026-10-22、worker/main | S28既存登録の明示metadata同期 | 285入力、同writer/専用Status Simulator | 1page/続き/失効cursor分離/旧mutation-outbox/登録store/動画別表示 | Unit868展開(有意味867)/28skip、UI1/reopen1/build/実metadataHTTP1成功(2要求/媒体0) | evidence/20261022-status-sync/。全再登録/全媒体/全S28未達、最終共有版はE-S34-BG01 |
| E-S34-BG01 | 2026-10-22、workers/main | S34歴史的確定upload終端後の単数破棄・最終回帰 | 288入力candidate02、全run前後一致 | 全receipt/inventory・同writer最終照合/実SDK終端→ownFD-close→lease/stopped→通常risk/unlink/reopen | Unit913展開(有意味912)/29skip、実SDK1/metadataHTTP1/UI7/reopen1/build成功、CF1/seed1skip、診断0 | evidence/20261022-removal-terminal/。permit/Macは注入、SDK全FD/通常strict/全媒体/正式proof等へ昇格しない |
| E-H01-01 | 2026-10-22、main/読み取り調査 | H01・18票/全79AC | H01-SOURCE-01/389入力 | 全76母行/35軸更新/6旧親行保持/層別実行版を照合 | 準備版静的検証成功、実機未実施/全D0/受入未評価 | evidence/20261022-device-handoff/。実機実値/品質/許可/全組合せと反復はQ01未束縛 |
| E-P2-STOP-20261022 | 2026-10-22、explorer/worker/main | 独立指摘AX5の秒数折返し/停止位置P2、S16必要関連範囲 | 最終P2-STOP-SOURCE-20261022-04の389入力、開始からView/UIだけ変更・387不変 | 実更新/scroll中の位置・全文・単一tap/停止/背景/再起動、初期playing/停止後AX、Unit/実reader/UI後原本照合、generic iOS | Unit14宣言17展開、通常3/最大2 UI、UI後2成功/seed1skip、build/診断0。移動量0pt、全reader空、digest/485721bytes不変。途中失敗01〜03保持 | [今回証跡](evidence/20261022-playback-stop-layout/README.md)。S16非実機done、初回失敗の直接原因は未確定。全steering・実機/品質/PRD受入は未完 |
| E-P2-20261022-FIX | 2026-10-22、explorer/workers/main、document_author/doc_reviewer | 独立指摘AX4件/fresh fixture不整合、S14/S16非実機Verify | 最終288入力不変、389 binding/旧H01から7変更382不変 | 新規App root seed・Unit/strict/通常/最大UI/実VO・UI後全reader/identity/digest・generic iOS | 全Unit590宣言562成功28skip/915展開（有意味914）、通常18前提別/strict6・最大4成功、seed各2成功1skip、UI後2成功1skip、build/診断0。失敗・取消・0件も保持 | [今回証跡](evidence/20261022-p2-ax-fixture/README.md)。S14/S16非実機done、他task/全steering/実機/品質/受入へ波及させない |

| E-INHERITED-20261023 | 2026-10-23、main | 前回独立検証引継ぎ・P2-STOP | 開始17,341file＋ignored7file、前回validation-summary | 既存dirty/新規/HEAD/indexを保全し前回validationと共通fileを照合 | 新規確定指摘0、P2-STOP非実機合格、前回全Unit有意味913/UI18種類20実行/build/診断0を限定継承 | [引継ぎ](evidence/20261023-cleanup-composition/inherited-validation-summary.json)。今回成果や未実装/実機受入へ拡張しない |
| E-S34-CLEANUP-01 | 2026-10-23、worker/main、document_author/doc_reviewer | S34条件付き通常複数整理・V-UI/STORE/ORIGINAL | 292入力、専用fresh root、Xcode27/Debug/iOS27 Simulator＋generic iOS | 固定3本確認/取消/再確認、毎本最終writer再判定/実unlink/通常一覧/再起動、通常/最大文字strict AX | 新規8宣言27展開、通常UI1・AX各1成功、適格2本だけ削除、保持/外部hash不変。全Unit09は既存Photos1失敗を保持 | [証跡](evidence/20261023-cleanup-composition/README.md)。全S34/正式proof/通常Photos/実機は未完。09はS31で診断/修正 |
| E-S31-OWNER-01 | 2026-10-23、explorer/worker/main、document_author/doc_reviewer | S31同exact使用権回収とowner閉鎖 | 292入力、実SQLite/FD/隔離PhotoKit、Xcode27/Debug/iOS27 | barrier red→単一回収/閉鎖後read-only exact再照合→関連/全Unit/実PhotoKit許可拒否/build | 関連36宣言86展開、全Unit604宣言573成功/31skip・有意味951、実PhotoKit各2成功/build成功、診断0。0実行11/閉鎖FileHandle crash12を保持 | [証跡](evidence/20261023-photo-release-owner/README.md)。09元返値分岐は未断定。正式媒体/通常複数Photos/実機は残件 |
| E-S49-RESUME-01 | 2026-10-23、worker/main、document_author/doc_reviewer | S49単回同期許可契約・SDK port配線 | DI-SOURCE-20261023-01/395入力、各run294入力不変、専用Simulator＋generic iOS | origin/revision/hold/ABA/単回/throw/実ThreadとSDK executor競合、非送信SDK、全Unit/通常UI/実disk/build | 関連28宣言44展開・SDK3・全Unit609宣言578成功/31skip・有意味963成功、UI6種類（24旧理由期待値1失敗→25成功）、post26/27・build28成功、最終診断0。compile18/QoS19保持 | [証跡](evidence/20261023-capture-resume/README.md)。native正resume/全媒体実停止/実通信REC・全S49/実機は未完 |

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
| V-REVIEW-S31-TERMINAL | E-S31-02の最終245入力、既存17file変更＋新test2file | main、文書はdoc_reviewer | 結果/終端/元use解放/copy保持、旧証拠互換、pending exact/明示retry、全scope/ACK、所有/既存保全を確認。専門文書review指摘なし | `evidence/20261021-s31-terminal/main-final-review.json` とdoc-review.json。独立validationではない |
| V-REVIEW-20261022-CODE | E-S32/S33/S34/S23/S49/S27/S28、最終288入力 | main | 各taskの全差分/所有と修正差分を確認、全run source一致、旧失敗・P2 strict4・未接続を保持 | 各task main-reviewとH01-SOURCE-01のexecution_binding。独立validationではない |
| V-REVIEW-20261022-DOCS | M02〜M06の最終5文書 | main/document_author/doc_reviewer | 1fileずつ同期・他文書/source保全、PRD79対応/旧制約保持、M05のP3主語を修正して全最終指摘なし | evidence/20261022-stable-docs/。文書のみ追加build/testなし |
| V-REVIEW-H01 | 全76母行/35軸/389入力source binding | main/読み取り調査 | 旧枝条件/直接依存/未接続と未実機・層別証拠を照合、指摘なし | evidence/20261022-device-handoff/。準備のみdone、A01〜18/Q01/製品受入は未完 |
| V-REVIEW-P2-20261022-FIX | 開始baselineとの3コード/4文書/tasklist、389入力と全run版 | main、文書はdocument_author/doc_reviewer | native実文字/全semanticサイズ/AX領域・全ID/combine・監査不変、cleanup現行guard/合成契約/通常回帰、実可視title tap/最新値観測、全差分・保全/適用範囲を照合 | E-P2-20261022-FIXとmain-review-final-01.json、文書指摘なし。独立validationは別明示工程 |

| V-REVIEW-S34-CLEANUP | E-S34-CLEANUP-01、App8/既存test1/新test4 | main、文書はdocument_author/doc_reviewer | 同writer最終証拠/失効/全transport fence、対象別独立解放、確認/未実行非再開、全差分/所有と原本保全を確認。repository-structureの旧未接続記述を修正して文書最終指摘0 | 全体はblocked、[S34証跡](evidence/20261023-cleanup-composition/README.md)。独立validationではない |
| V-REVIEW-S31-OWNER | E-S31-OWNER-01、製品1/test2 | main、文書はdocument_author/doc_reviewer | 同exact回収join/完全commit証拠/閉鎖FD guard/unknownコピー保持・元8枝維持/決定的crashを確認。記録成功を写真成功へ昇格しない文書追補も指摘0 | [S31証跡](evidence/20261023-photo-release-owner/README.md)。全S31/実機未完、独立validationではない |
| V-REVIEW-S49-RESUME | E-S49-RESUME-01、App4/既存test3/新test2とUI期待値1箇所 | main、文書はdocument_author/doc_reviewer | 同origin lock/単回/throw/ABA/同期actionとnative拒否維持、Thread QoS解消/各実行版と必要範囲を照合。旧UI期待値だけ厳密化し他P2を保持、文書最終指摘0 | [S49証跡](evidence/20261023-capture-resume/README.md)。正の実SDK/全媒体/全S49は未成立、独立validationではない |
| V-REVIEW-S28-NEW | E-S28-NEW-01、App5/既存Support/新test4 | main、文書はdocument_author/doc_reviewer | 旧拒否/foreign v2/新namespace/current孤立資格情報/await UUID・登録空/clearbearerを確認。concrete witness修正と全旧assertion/旧bytes保持、文書最終指摘0 | [新登録証跡](evidence/20261023-new-registration/README.md)。専用通常/最大/VERIFYと最新初回・全Unit/buildを確認。独立validationではない |
| V-REVIEW-S28-INVENTORY | E-S28-INVENTORY-01、App15/新test5/server8とConnection表示調整 | main、文書はdocument_author/doc_reviewer | metadata限界/厳密wire/同writer exact観測/UTF8 identity・remote別投影を確認。全旧server230case/guard/SQL/auth、P2/全監査を保持。Connection全原文/ID/Task/disabled/6入力/lifecycle/固定footerを47比で照合。文書P2一文修正後指摘0 | [inventory証跡](evidence/20261023-remote-inventory/README.md)。最新全Unit/旧UI/照合/buildと全差分・所有を確認。独立validationではない |

- 2026-10-24 今回続行・本人通信操作: core13/App7を実装し、固定親子plan・atomic本人意思とexact停止対象・unknown lookup・再open非再発行を確認中。113/114は新規async witnessのactor推論compile失敗を限定修正、115は旧PhotoSaveLibraryの暗黙init診断1件+警告1件で0実行。各356入力不変、元失敗を保持。新規2 Simulatorは未seed、Seed/UI2は関連Unit通過後。文書4件は専門read-onlyレビュー0指摘/68リンク欠落0。全task/全steering完了ではない。

## 振り返り・引渡し

- 2026-10-24: 前回独立検証（新規確定0/P2-STOP非実機合格）を引き継ぎ、S34/S31/S49/S28の上記5部分を実装・必要検証・文書同期した。DI-SOURCE-20261023-02の414入力、67runの途中失敗/0実行と最終13必要run、5つの専用rootの保全を束縛。全S28/S31/S34/S49・全steering/全D0/R部分証拠・Q01/A01〜18・実機/品質/受入の未完了を維持する。次の独立した工程は、明示 `$validate-implementation .steering/20260929-device-independent-implementation/`。本セッションでは開始していない。

- 2026-10-22 停止位置P2修正後: E-P2-STOP-20261022で今回1件とS16の必要な非実機検証を完了。mainが開始差分・最終389入力・所有範囲・全run/途中失敗・原本/readerとSimulator保全を照合した。既存の全task状態・全steering/実機/品質/受入の未完了を維持し、独立した次工程は同pathの明示validationのみ。

- 2026-10-22 P2修正後: E-P2-20261022-FIXで2指摘とS14/S16の非実機Verifyを完了。以下の旧最終記録は修正前の履歴として保持する。今回も他task/段階/全steering、実機・品質・受入の未達を継承し、次工程は同pathの明示独立validationのみ。

- 計画作成日: 2026-10-01。実装完了日・実機工程完了日・PRD受入達成日は未確定。
- 残る判断: 実機方式・能力、資材適合、品質条件／採用、ISO基準・既承認暫定値の実機採用等、実環境・対象別操作。各task／Q01へ局所対応し、4段階の合意を未確定へ戻さない。
- 今回は本steeringに従いコードとM02〜M06の永続文書を同期し、M01のPRD79条件を保持した。入力仕様・旧steering・repo rootの`README.md`・memoを保全し、既存未追跡コードはbaselineを保持した加算変更に限る。PLAN-01の「3文書だけ」は計画作成時点の記録である。
- 今回の明示 `$implement-steering .steering/20260929-device-independent-implementation/` で直接readyな範囲の実装/関連検証/文書同期/引渡し準備を終えた。全steering・実機・PRD受入は未完。次の独立検証は同pathを明示する `$validate-implementation` とし、自動開始しない。

- 実装単位: 操作に必要な下位I/O・同writer永続化・製品接続/画面・再open照合・関連検証を一つの引渡しにまとめ、書込みtask/所有は1件ずつ管理した。
- 最終保全: [開始時8,910file照合](evidence/20261022-implementation-final/final-preservation-01.json) と [source/所有照合](evidence/20261022-implementation-final/final-source-scope-01.json)。既存CF原本digest/reader0・設定67bytesを保持し、今回作成した2 Simulatorだけshutdownしてdataを保持した。
