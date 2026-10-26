# S27 canonical publication wire の隔離 HTTP probe

この支援は、S27 backend の正規 `fr-publication-v1` router と本物の iOS codec を別 process の loopback 接続で検証する。使用する authority は `backend/tests/frame_relay_publication_fixture.py` の明示 factory に限る。通常の製品 router/default factory は正式品質 proof 未接続を拒否したままで、環境変数や API に authority 切替を追加しない。

合成 Movie は S25 の 969,998 byte、SHA256 `8a77b6c2cfdedbe850148210eada8851956f10942203aec4eae8f9e552a8b984` を read-only 入力とし、新 runtime へ copy する。ftyp `qt  ` と `video/quicktime` を一致させる。S24 実受信/finalize と S26J の fenced technical copy adapter から同一 original の別 candidate を作り、V1 だけを初期公開する。Rec.709 変換・出力品質・製品全 owner の受入証拠ではない。

## 所有と準備

新規所有は `prepare_publication_probe.py`、`publication_fixture_listener.py`、`run_publication_fixture.py`、`run_publication_simulator_probe.py`、本 README の 5 file。既存 `prepare_rendition_fixture.py` の stdlib metadata helper、`isolation_guard.py`、`listener_lifecycle.py`、`run_pytest.py` の設定/FD helper を変更せず固定 copy する。

backend 担当の `prepare_publication_snapshot.py` による凍結済み `run-config.json` と `checkpoint-files.json` を入力とする。準備 helper は checkpoint の指定 SHA256、config/provenance/snapshot 全 file、外部 source/interpreter/site-packages/.pth、wire を照合し、新 HTTP snapshot へ copy する。backend snapshot の生成をこの helper で重複しない。wire の固定 SHA256 は `455868ebe8d057ad32471a169396333c03cd1bcf2b4a4986f3147935f2617e0a`。

以下は再実行の手順であり、個別の成功判定には実行版と証跡を対応させる。2026-10-22のS27実HTTP成功は [E-S27-01のmain確認](../../evidence/20261022-publication/s27-http-final-review-02.json)、S28 metadata-onlyの最終288入力での成功は [E-S34-BG01のHTTP確認](../../evidence/20261022-removal-terminal/s34-terminal-metadata-final-02-main-review.json) を参照する。全製品接続・正式proof・実機受入の成立は示さない。2026-10-22の再開前は `s27-resume-before-02/server-isolation/` に保全済み。欠落した旧 tmp/snapshot/runtime を復元・再利用せず、main が今回の凍結版から新規準備する。

1. backend 6file と HTTP 5file の全担当を凍結し、main が差分と hash を確認する。backend の新 `prepare_publication_snapshot.py` が作る `run-config.json`/`checkpoint-files.json` を使用し、旧137node/160case prefix＋publication全33node/70case＝170node/230case の回帰を先に実行・評価する。HTTPのSwift 1caseとは別の集合である。
2. 実在する `FrameRelay.xcodeproj`、scheme/test plan `FrameRelay`、Debug、現在のSimulator destinationを確認する。同じApp/Tests版で `FrameRelayTests/PublicationHTTPFixtureTests/canonicalPlaybackConfirmationInvalidationAndReplacement()` だけを SDK に列挙し、errors空・1宣言/1実行である列挙JSON、構成とdestination一覧を保存する。過去の固定UDIDを使わない。専用の新DerivedDataを選ぶ。
3. backend provenance の `interpreter.entry` に記録した外部Python3.12を `-I -B -S` 付きで使い、repo側 `prepare_publication_probe.py` に次表の全引数を渡す。実値のargvと入力hashはmainの新実行記録へ保存する。準備helperも凍結review後にmainだけが実行する。

| 必須引数 | 実行時に束縛する値 |
| --- | --- |
| `--revision` | 既存directoryと衝突しない3桁NNN |
| `--backend-config` | 今回生成したS27 backend preparationの `run-config.json` 絶対path |
| `--backend-checkpoint-sha256` | その `checkpoint-files.json` の実SHA256 |
| `--fixture-movie` | 上記size/hashに一致する保全S25 QuickTime fixtureの絶対path |
| `--enumeration` | 現sourceの指定1caseだけを列挙したSDK JSONの絶対path |
| `--xcode-list` / `--destinations` | 同じ現構成の実観測を保存したfileの絶対path |
| `--destination-udid` | 一覧中の今回実行するSimulator UUID |
| `--derived-data` | `/private/tmp/fr-di-20261015-s27/` 内の今回専用・未使用の絶対path |

出力は `/private/tmp/fr-di-20261015-s27/S27/http-preparation-NNN` と `http-snapshot-NNN`。この段階では `runtime-publication-NNN` を作らない。helperはApp/Tests全hashに加え、実AVPlayerの `elapsedSeconds > 0.1 && decodedFrames > 0` 条件、同じ観測点の `0 < bytesAtProgress < total` assertion、固定名の添付を現Swift sourceに照合する。条件やSDK添付形式が変われば黙ってfallbackせず新たに整合させる。

4. main が新 `config.json`、`checkpoint.json`、`commands.json` の具体値、全source/dependency/provenance、snapshot、専用destination/DerivedDataを確認する。`commands.json` の `dry_run` に保存されたargvをそのまま使い、source/config/Movie/provenance検査とchild command表示を確認する。この処理はbackend import/HTTPを開始しない。
5. 同じ `commands.json` の `execute` に保存された完全argvをmainが実行する。引数を書き換えず、source-snapshot内supervisorから実listenerとSimulator wrapperを起動する。既存preparation/runtimeの上書き、listener/wrapperの手動再利用、失敗したrunの成功証拠への置換はしない。

## 試験契約

環境は `FR_S27_HTTP_FIXTURE=1`、`FR_S27_ORIGIN`、`FR_S27_BEARER`、`FR_S27_REGISTRATION_SECRET`、`FR_S27_FIXTURE_SECRET`、`FR_S27_FIXTURE_JSON` の 6 値だけを `TEST_RUNNER_` 付きで渡す。JSON は 16 KiB 以下で、schema/run identity、wire/source hash、既存 registration receipt、original、V1 rendition、未生成の `v2:null`、tests-owned authority/candidate provenance を含む。秘密 3 値は独立生成し、JSON に含めない。

登録は既存 registration service/repository で作成し、iOS fixture 専用 vault へ exact receipt/secret を注入する。canonical endpoint は `/frame-relay/v1/publication/` の manifest、distributions、operations/lookup、media、confirmations、invalidations、acknowledgements だけ。control は別の tests-only `POST /__s27_fixture__/control` で、header `X-FrameRelay-Fixture-Secret` と厳密 JSON `{run_identity,action}` を要求する。

| action | 動作と結果 |
| --- | --- |
| arm-confirmation-response-loss | 次の confirmation が実 commit した成功 envelope を捨て、fixture 503 `publication_result_unknown` に置換。result は `{armed:true}` |
| begin-replacement | 同 original の V2 candidate を replacement にし、V1 pointer を維持。result は backend の replacement_id/rendition/media_type/invalidation_id/invalidation_generation |
| publish-replacement | ACK 前は backend の 409 `publication_awaiting_acknowledgements`。ACK 後だけ backend の公開 commit result を返す |

成功 control envelope は `{run_identity,action,result}`。V2 の server UUID は begin-replacement で初めて確定する。confirmation fault は「実 commit 後の受理 receipt 欠落→unknown→exact lookup」の技術証拠であり、TCP 切断や実網の応答喪失を再現したとは扱わない。listener は元 request/result の canonical hash と lookup の original_request/original_result の hash を照合する。

SDK 試験は parameter なしの 1 宣言/1 実行、failure/skip/expected failure 各 0 を要求する。V1 実 AVPlayer 進行→本人操作の確認 commit→outbox 送信/lookup→replacement/失効取得→fixture scope の実終端/reconcile→ACK→V2 公開を実行する。消費済 ticket の再利用は V1 が current の間に拒否し、事前に受理した別の未使用 V1 ticket を V2 公開後に初めて GET して拒否する。再登録/古い ACK の競合は別の local disk/backend tests の範囲であり、この HTTP 成功へ含めない。

listener は各実 request の endpoint/phase/status、Content-Type/Length/Range、media body と JSON error body の送出 byte 区分、handler return と実終端を記録する。拒否 GET は 409 だけで合格にせず、JSON body の実送出と media byte 0、対応 ticket、実終端を照合する。ASGI send の受理 byte と端末受信 byte は別観測である。親は listener の bool をそのまま信用せず、保存された各観測から同じ stage 判定を導出する。

全量前進行は親の `REQUIRED_OBSERVATIONS` の `avplayer_progress_before_full_download` として必須とする。wrapperは実Xcode終了後にraw summary/test tree/build-resultsを回収し、さらに当該test IDだけを `xcresulttool export attachments --test-id` でprivate `playback-attachments/` へexportする。各SDK metadata/export呼出しは10秒上限、4呼出し分を含む終了監査待ちは50秒。秘密環境を渡さず、directory0700/file0600、manifestと期待text以外・symlink/hardlink・大き過ぎるfile・秘密の反映を拒否する。全診断や他testの添付をexportしない。

親はraw SDK manifestのtest ID/URL・実destination・固定名 `s27-wire-observation.txt`・添付実fileを読み直す。raw test summary/treeの1件Passed・failure/skip/expected failure各0と、添付の `0 < bytesAtProgress < total`、fixtureと同じtotal/hash、`decoded > 0`、HTTP全実終端・cache0・ACK1を再計算し、wrapper結果ともexact一致を要求する。listener boolやwrapperが作った数値JSONだけでは成功にならない。SDK添付欠落/形式変更/抽出失敗/進行条件不成立は失敗として保持する。

fixture ASGI middleware は正常 media block だけを 4 KiB/10 ms に分割する。header/byte 内容、canonical admission/FD 所有、製品 source を変えない。これは S25 と同じ全量前進行を観測する合成 schedule であり、製品性能基準や timeout 方針ではない。

## 隔離・終端・証拠

外部 Python 3.12 `-I -B -S`、既存依存と source hash を import 前に照合する。runtime 作成直後に既存 Guard を install し、その後だけ backend/tests factory/site-packages を import する。書込は新 runtime 内、SQL authorizer と実 dir_fd 境界を維持し、外向 socket/全 subprocess を禁止、listener は 1 process で 1 回の `127.0.0.1:0` bind だけ。ffprobe 例外も使わない。22 設定を明示し、実 Settings と照合、HOME は値を変えず継承する。

親と Simulator wrapper は listener と別 process。ready/stop は run identity、実 PID、確定 loopback origin、1200 秒期限へ束縛する。秘密 file は0600、秘密値を CLI/公開 artifact hash へ載せない。Xcode stdout と metadata/stderr は秘密 3 値を伏字にし、metadata tool には秘密環境を渡さない。stderr は伏字後の先頭 8 KiB と切詰め表示を保持する。Xcode の非0/timeoutでも実終了後に summary/全 test tree/build-results を個別回収し、試験失敗と抽出失敗を分離する。内部 xcresult の使い捨て環境保持はあり得るため、listener 終了で秘密を失効させる。

Uvicorn task/connection、response handler、生成threadを全終端/joinする。thread母集団は `run_fixture` 冒頭のseed/import前に固定し、seedが作ったfinalize/conversion threadも監査対象にする。

`guard.finish()` は同threadの生存SQLite接続を救済closeし得る。呼出し前に接続イベントのcopy、pending IDs、未close時GC IDs、実tracked接続とowner thread、DB/媒体FDの実inventoryを固定し、`owner_close_before_guard_finish` として保存する。pending/GC/tracked接続/DB媒体FDはいずれも0、新しいregular FDでF_GETPATHが不明のものも0を要求する。親はこの呼出し前記録から独立に再評価する。救済後のイベント/FD/zeroは別記録であり、所有側close成功へ昇格させない。`check_same_thread` を維持し、GC/process exitもexplicit closeの代用にしない。ここで失敗した場合、mainが残存ID/thread/FDとbackend所有箇所を照合し、必要なownerの `finally`/`closing` 修正を別途割り当てる。guardや条件を緩めて合格化しない。

guard denial0、source/依存/原本不変を要求する。秘密はlistener finallyで削除し、親も実 `Popen.wait()` 後に不在を確認する。強制signal、親による秘密の救済削除、未終端/未close、artifact欠落は失敗として保持する。

静的 compile/準備/dry-run は実 HTTP/AVPlayer 成功ではない。TLS、Wi-Fi/VPN、背景/ロック/実機、Rec.709/聴取品質、製品の external/recovery owner producer は別の未確認範囲として残す。

## S28 metadata-only の明示mode

`--probe-mode` を省略すると従来の `publication` となり、S27のmethod・6環境値・全12必須観測をそのまま要求する。S28は準備時に `--probe-mode metadata-only` を指定する別runとし、S27の成功結果・AVPlayer進行・SDK/HTTP件数を流用しない。旧S27の凍結5fileは `s27-http-main-review-05.json` と `evidence/20261022-publication/` に保全されている。このmodeは別runで実行し、初回285入力の [S28確認](../../evidence/20261022-status-sync/s28-http-main-final-review-01.json) と最終288入力の [再確認](../../evidence/20261022-removal-terminal/s34-terminal-metadata-final-02-main-review.json) を保存した。実2要求・媒体0byte・SQLite再openの技術fixtureの範囲であり、SDK task/session件数はこのHTTP試験では未観測のまま保持する。

準備は上表の全必須引数に `--probe-mode metadata-only` を加え、既存の成功backend273file snapshot/config/checkpoint・同じ969,998byte合成Movieを入力にする。App/tool両担当の凍結とmainの差分確認後だけ実行する。methodは `FrameRelayTests/StatusSynchronizationHTTPFixtureTests/metadataOnlyPageAndManifestUseCoordinator()` の1宣言/1実行をSDKで明示列挙する。新しい実destinationと専用DerivedDataを束縛する。

生成先は同じ技術fixture root `/private/tmp/fr-di-20261015-s27/S27/` 内の `metadata-http-preparation-NNN`、`metadata-http-snapshot-NNN`、`runtime-metadata-only-NNN`。S27の `http-preparation-NNN` / `http-snapshot-NNN` / `runtime-publication-NNN` とは分け、いずれも再利用しない。configには `probe_mode` と固定 `probe_contract`（method、env集合、添付名/schema、必須観測）を保存し、そのconfig hashとmodeをcheckpointへ束縛する。親・listener・Swift wrapperの各argvにも同じ `--probe-mode metadata-only` を渡し、ready・secret envelope・各resultのmode不一致を拒否する。

準備commandの形は既存 `prepare_publication_probe.py` の全必須引数に上記modeを追加する形である。準備後の実argvは `metadata-http-preparation-NNN/commands.json` の `dry_run` と `execute` を正本とする。どちらもfrozen `source-snapshot/run_publication_fixture.py`、新 `config.json`、その `checkpoint.json` の実SHA256、`--probe-mode metadata-only` を含む。mainが具体値を確認した後にdry-run→executeの順で使い、既存の `--execute-reviewed-integration` / `--execute-reviewed-xcode` と停止・実process終了確認を維持する。

Swift gateは `FR_S27_HTTP_FIXTURE=1` AND `FR_S28_METADATA_ONLY=1`。従来6値に後者だけを追加した7値を `TEST_RUNNER_` 経由で渡す。fixture JSONはS27と同じcanonical string/bool/nullの値形で、`factory_source.size` だけmetadata用のdecimal stringに写像する。登録資格情報とoriginal/V1を再利用し、fixture control secretは配布するが本testから使用しない。listenerもこのmodeではcontrol要求を拒否する。

サーバーは順番通りのPOST `invalidations`（after=null、limit="8"）→POST `manifest` の2 requestだけを許可する。失効は空の1page・next_after=null、manifestは同一originalのV1currentを要求する。媒体GET/distribution/confirmation/ACK/lookup/controlの試行は不合格とし、JSON応答の実送出・handler終端・media byte0・固定payload hashを親が再計算する。fixtureを作るseedのdisk I/Oと、testが開始したmetadata HTTPを混同しない。

SDK添付は `metadata-attachments/` のprivate0700 directory / 0600 filesへ当該testだけをexportする。固定名は `s28-metadata-observation.json`、schemaは `fr-s28-metadata-observation-v1`。親はraw test summary/treeの1Passed・failure/skip/expected failure0、test ID/URL・destination・実manifest/実添付・runIdentityを再照合し、重複JSON key、非有限値、余分なfield、型違い、別mode/schemaを拒否する。

| SDK添付field | 必須値と意味 |
| --- | --- |
| `report_schema` / `probe_mode` / `fixtureOnly` / `runIdentity` | 固定schema / `metadata-only` / true / 当該configのrun identity |
| `boundedPages` | 整数1。明示した1pageの実行結果 |
| `invalidationsStarted` / `invalidationsCompleted` / `manifestStarted` / `manifestCompleted` | それぞれ整数1。実remote呼出しとawaitからの復帰 |
| `confirmationSend` / `ackSend` / `operationLookup` / `distribute` / `lookupDistribution` | それぞれ整数0 |
| `durablePublicationCount` / `newConfirmations` | 同writerの公開記録整数1 / 新確認整数0 |
| `reopenMatches` / `coordinatorAwaitCompleted` | true / true。実SQLite再open一致とcoordinator await復帰 |
| `sdkTerminalCountsObserved` | false。既存real remoteにはSDK task/session実数の注入をしていない |
| `sdkTerminalContract` | 固定文字列 `PublicationURLSessionRequest awaits task completion and session invalidation` |

最後のSDK契約は凍結した `URLSessionPublicationRemote.swift` のperform→task completion→session invalidation→continuation復帰条件のsource/hash照合として別記録にする。実task/session件数を主張する項目ではない。実await完了counter、serverの実2 request、同writerのcommit/reopenは別の観測として照合する。

新modeの必須観測は `coordinator_metadata_commit_reopen`、`exactly_two_metadata_requests`、`all_metadata_handlers_terminal`、`one_complete_empty_invalidation_page`、`manifest_matches_current_v1`、`zero_media_and_distribution_requests`、`zero_confirmation_ack_lookup_requests`、`zero_fixture_control_requests` の8件。従来のpre-rescue pending/GC未close/tracked接続/DB媒体FD/新しい不明regular FD0、seed前からの全created thread join、子の実exit0・signal0・秘密env削除、22設定・外部source/依存/.pth/interpreter・全source不変、loopback1 bind、import provenanceも同時に必須とする。metadata-onlyの成功を全S28・通常媒体送信・実機受入の成立へ昇格しない。
