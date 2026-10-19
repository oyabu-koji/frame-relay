# S20 checkpoint 4 — 実listenerとSimulator probeの実行前引渡し

checkpoint 1は20件中10成功/10失敗、exit71。Range能力照会の実Popen用`/dev/null`をguardが拒否した。静的調査の見落としを訂正し、旧結果を保持した。checkpoint 2はmain実行で20件全成功/skip0/exit0。checkpoint 3もmain実行でexit0、1,024 byte Rangeに全体2,097,169 byteを2回hash読込し、2回目transaction内のwriter競合を観測した。固定V1/切替/descriptor解放・外部入力不変も確認した。終了前に別thread SQLite接続6件が残った事実と実process終了を分けて保持する。このcheckpoint 4は実listenerとSimulator wrapperの準備であり、起動許可や実行済みを意味しない。旧T04の消失成果を再利用しない。

## 入力と出力

- 外部入力: `/Users/oyabu/dev/rep/latest_template`、HEAD `c56d4a25a46acfa99dd66c4586621b5261af4d39`。外部checkout・venv・未追跡JPEGへ書かない。
- 新snapshot: `/private/tmp/fr-di-20261001-5ljls2fr/S20/snapshot-001/backend`。backend追跡246ファイル、2,032,282 bytes。未追跡成果、`.venv`、実DB/media/runtimeはコピー対象外。
- provenance: `S20/preparation-001/provenance-before.json`。外部source前後、snapshot全SHA256、既存site-packages 1657ファイル、interpreter実体、pyvenv.cfg、.pth内容を保持する。`.pth`は実行しない。
- 最新実行設定: `S20/preparation-004/run-config.json`。action=`listener`、`runtime-listener-004`は未作成でなければ拒否する。旧runtime-001/002/003の失敗・成功・provenanceを保持する。
- checkpoint 4のsupport 9ファイルは `preparation-004/source-snapshot/` に凍結copyし、`checkpoint-04-files.json`で元とcopyのhash一致を保持する。checkpoint 1〜3はhash/log/probe結果を保持するが、S20証拠内に当時のrunnerコードcopyはない。過去版を推測復元せず、backend snapshotの不変性とは分けて扱う。
- 可逆な隔離設定であり、製品のwire/schema/性能閾値/変換方式の採用ではない。

## 実行コマンド（mainが具体範囲を確認しlistener起動を許可した後だけ）

```sh
/Users/oyabu/dev/rep/latest_template/backend/.venv/bin/python -I -B -S /Users/oyabu/dev/rep/FrameRelay/.steering/20260929-device-independent-implementation/support/server-isolation/run_pytest.py --config /private/tmp/fr-di-20261001-5ljls2fr/S20/preparation-004/run-config.json
```

実起動を観測して `listener-ready.json` が生成された後、mainだけが次を実行する。wrapperはlistenerを起動しない。

```sh
python3 -I -B -S /Users/oyabu/dev/rep/FrameRelay/.steering/20260929-device-independent-implementation/support/server-isolation/run_simulator_probe.py --config /private/tmp/fr-di-20261001-5ljls2fr/S20/preparation-004/run-config.json --execute-reviewed-xcode
```

wrapper内の固定Xcode条件: `/usr/bin/xcodebuild -project /Users/oyabu/dev/rep/FrameRelay/FrameRelay.xcodeproj -scheme FrameRelay -configuration Debug -destination platform=iOS\ Simulator,id=DFE46693-E8DD-4814-8957-4F327699F719 -derivedDataPath /private/tmp/fr-di-20261001-5ljls2fr/DerivedData -disableAutomaticPackageResolution -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath <runtime>/simulator-probe.xcresult -only-testing:FrameRelayTests/LegacyServerPlaybackProbeTests test -quiet`。実行時にxcode-select/Xcode version/実体hashを記録する。SDKを選び直したりinstallしない。wrapperはbackendのaudit guard外でmainのXcode実行権限を使う。書込みは指定runtimeのlog/result/stop.request、指定DerivedData/xcresultと通常のSimulator/Xcode生成物。App/Tests/sourceは変更しない。

`--execute-reviewed-xcode`を省けばcommandの表示だけでSDKを実行しない。secret 0600 JSONを読み、許可した7項目だけTEST_RUNNER_前置のenvへ渡す。CLIへtokenを載せず、stdout/logへ出る同token文字列は伏字化する。HOME等の必要環境だけ継承し、以前のTEST_RUNNER_FR設定・proxy・秘密環境は引継がない。Xcode内部診断がenvを保持する可能性はwrapperだけでは排除できないため、恒久秘密を使わず、終了時にlistenerを止めて使い捨てtokenを失効させる。

readyにはrun identity・PID・起動monotonic時刻・期限を保存する。wrapperはconfig/secret/readyの対応、PIDの実在と実command、同じURL、残存期限を照合してからXcodeを開始する。期限は `min(1100, 残り秒数 - 60)`、180秒未満なら開始を拒否し、停止確認後の新runtime準備へ戻る。Xcode version確認後にも期限を再計算する。60秒は停止処理の余裕であり、製品timeoutではない。期限超過・中断時は自分が開始したXcode process groupだけへSIGINT→TERM→KILLの順で停止を試み、結果を記録する。

通常の手動停止要求（実停止とは別の受付）:

```sh
python3 -I -B -S /Users/oyabu/dev/rep/FrameRelay/.steering/20260929-device-independent-implementation/support/server-isolation/request_listener_stop.py --config /private/tmp/fr-di-20261001-5ljls2fr/S20/preparation-004/run-config.json
```

wrapperも終了時に同runtimeのstop.requestを作る。listenerは実ready後のmonotonic 1200秒、stop.request、SIGINT/SIGTERMを終了入口にし、Uvicornの実shutdownを待つ。1200秒はXcode起動/build/Simulator待ちを含む隔離期限であり、製品timeoutの採用値ではない。`server.should_exit`を実停止と扱わず、server task終端・listener FD close・media descriptor・secret削除・process実終了を別々に記録する。

SIGKILL/電源断でfinallyが走らなければsecret残存を成功へ変えない。mainがlistener-readyのPIDと実processを照合して停止を確認した後、以下でPIDが現存しない場合だけsecretを削除する。PID現存/再利用/権限不明なら拒否して再照合へ戻す。

```sh
python3 -I -B -S /Users/oyabu/dev/rep/FrameRelay/.steering/20260929-device-independent-implementation/support/server-isolation/request_listener_stop.py --config /private/tmp/fr-di-20261001-5ljls2fr/S20/preparation-004/run-config.json --cleanup-secret-after-exit
```

既存Python 3.12と依存を使用し、installしない。runnerはinterpreter実体と全入力hashを再確認してから新runtimeを作る。guardを登録した後に限りsnapshot backendと既存site-packagesをsys.pathへ明示追加する。環境継承はHOME/LANG/LC_ALL/LC_CTYPE/TZだけ、HOME値は変更しない。PATHを固定し、proxy、Python/pytest追加設定、外部plugin設定は継承しない。`-I -B -S`でユーザーsite・環境Python path・bytecode生成・.pth処理を無効化する。

`action=pytest`の場合はrunnerがpytest引数を記録する。`--noconftest --capture=sys`、snapshotのpyproject、`-o addopts=`、runtime内cache/log/junit、新規未作成のbasetempを明示する。基底全testは実行しない。`cases.json`の13 node/20 parameter caseだけを対象とする。0件、skip、失敗を成功と扱わない。最新`action=range-probe`ではpytest.mainを再実行せず、guard登録後の実app/SQLite/TestClientと既存seed helperを追加観測に使用する。

## 実効22設定

| 設定 | 値 |
| --- | --- |
| MEDIA_ROOT | runtime/media |
| API_TOKEN | runtime起動時生成の使い捨て値、出力は伏字 |
| DATABASE_PATH | runtime/db.sqlite3 |
| LUT_PATH | runtime/assets/lut/rec709.cube |
| USER_LUT_ROOT | runtime/user-lut |
| BUILT_IN_PRESET_ROOT | runtime/assets/lut/presets |
| APPLE_LOG_DETECTOR_ROOT | runtime/assets/detectors/apple-log-v2 |
| FFPROBE_BINARY | runtime/disabled-ffprobe（不存在予約path、下記完全一致照会だけ） |
| DETECTOR_PROBE_TIMEOUT_MS | 15000 |
| DETECTOR_PROBE_MAX_STDOUT_BYTES | 1048576 |
| DETECTOR_PROBE_MAX_STDERR_BYTES | 1048576 |
| DETECTOR_EVIDENCE_MAX_BYTES | 4096 |
| PRESET_MANIFEST_MAX_BYTES | 65536 |
| PRESET_LUT_MAX_BYTES | 16777216 |
| SQLITE_BUSY_TIMEOUT_MS | 5000 |
| JOB_LEASE_SECONDS | 300 |
| PROCESSED_RESULT_RECOVERY_GRACE_SECONDS | 300 |
| UPLOAD_SESSION_CHUNK_SIZE_BYTES | 8388608 |
| UPLOAD_SESSION_MAX_SIZE_BYTES | 1099511627776 |
| UPLOAD_SESSION_ACTIVE_LIMIT | 2 |
| UPLOAD_SESSION_EXPIRY_SECONDS | 604800 |
| UPLOAD_SESSION_RETRY_AFTER_SECONDS | 30 |

LUT/catalogは追跡snapshotからruntimeへコピーする。実Log変換・品質合格を主張しない。testがMEDIA_ROOT/DATABASE_PATH/API_TOKENをmonkeypatchしても、媒体/DBはruntime配下basetempへ限定する。TMPDIR/TMP/TEMP/SQLITE_TMPDIR/XDG_CACHE_HOMEもruntimeの専用dirへ固定する。

## guardと記録の境界

- Python書込open、rename、remove、mkdir、link/symlink、chmod/chown/utime/truncate、chdirはcanonical runtime内だけ。dir_fdとFDはmacOS F_GETPATHで解決する。hardlink/symlinkは元もruntime外を拒否する。
- SQLite接続はruntime内のcanonical pathとsidecarを確認する。追加DB経路のATTACH/VACUUM INTO、path変更PRAGMA、拡張読込を拒否する。接続factoryとauthorizerの差替えを拒否する。
- subprocess/fork/spawn、listener、外向きconnect/DNS/sendtoを原則拒否。唯一のsubprocess例外は、書込禁止で不存在を確認した `runtime/disabled-ffprobe -version` の完全一致argvと既存bounded_processのshell=False/cwd=None/env=None/stdin=DEVNULL/stdout・stderr=PIPE/start_new_session=True/close_fds=True/pass_fds=()での実Popen試行。`/dev/null` O_RDWRも当該CPython Popen._get_devnullと同じconstructor stackに限定する。実OS由来のFileNotFoundError(ENOENT)を観測してそのまま再throwし、backend既存unavailable処理を通す。fake例外や能力検査のskipを注入しない。POSIX内部の短命forkはあり得るため「子process一切なし」とは扱わず、実binaryの起動なしを限定して観測する。installed ffprobe実行は許可しない。
- TestClient/asyncioの匿名AF_UNIX stream socketpairを許可する。listener actionだけAF_INET streamを加算し、bindは1回の127.0.0.1:0に限定。IPv6/外部アドレス/固定port/再bindは拒否し、外向きconnectは引続き拒否する。Uvicornはasyncio/h11/wsなし・1 worker・reloadなし・proxy headersなし・access logなしで起動する。
- audit hookはOS sandboxやnativeコードの完全な隔離と同一保証ではない。外部入力前後hash、import origin、書込観測、生成物/sidecarとFDも保存する。未知のguard拒否を迂回して試験を通さない。
- SQLite既定check_same_threadを変えない。接続owner thread、明示close、GC、他threadの未明示closeを区別する。context manager終了はcloseではない。runnerのFD記録は終了前の観測で、実process終了はmainが別途記録する。
- 証拠はruntime内 `preflight.json`、`effective-settings-redacted.json`、`audit.jsonl`、`import-origins.json`、`provenance-after.json`、`artifacts.json`、`result.json`と各probe出力。listenerはready/results/events、Simulatorはxcresult/伏字log/wrapper-resultを追加する。secret JSONはartifact hash一覧からも除外し、値を証拠へ展開しない。result後の終了処理でaudit行が増え得るため、mainは実process終了後の最終hashを採取する。

## 試験の意味

認証拒否は実app lifespan、migrationは実SQLite/rollback/WAL、storageは実ファイルと原本保持、workerは未対応jobをqueuedに保持する1回処理、Rangeは10 byteの固定合成bytesを使う。動画再生・変換・実ネットワーク・製品配布receiptの証拠ではない。

## 同じS20の後続checkpoint

1. checkpoint 3: 同guard下で2 MiB + 17合成bytesから先頭1024 byteのRangeを観測した。`range_probe.py`は既存hash関数の実読込byte数/呼出回数/同接続のtransaction状態を計測し、実hash結果をそのまま返す。2回目hashの最初の実read後だけEventで保持し、別接続の25ms BEGIN IMMEDIATEが返す実SQLITE_BUSYを記録した。25msと人工barrierは試験の同期設定であり、通常時のレイテンシ/性能閾値ではない。accepted V1 descriptor後のpointer切替・旧bytes継続、切替後V1新要求拒否、V2 Range、descriptor前切替拒否/未open、body実終端のFD closeも観測した。snapshotの本番コードは変更せず、計測wrapperはfinallyで戻した。結果は `runtime-range-003/range-probe-results.json` と共通guard/provenance/FD証拠、実process終了は `preparation-003/range-003-parent-result.json` に保持する。
2. checkpoint 4のlistener/Simulator wrapperは準備済み・未起動。上記command/hash/新runtime/停止方法をmainがレビューし、具体許可後だけ実行する。
3. 保全済み30秒H264/PCM Movie（485721 bytes、SHA256 `0f567596a4bd101d970dc978f38a2bd1095cefb470a66fc2e0c4b6a11f3df725`）をread-onlyで読みruntimeへcopy/hash照合する。旧helperの非Log技術fixtureへseedするが、既存verified欄は契約入力であり実upload検証/Log/変換合格/新製品receiptへ昇格しない。libraryのopt-in実AVPlayer試験に `FR_LEGACY_PROBE_*` を引渡す。元Movieの終了時hashも照合する。

## 後続のsnapshot実ファイル所有候補

次の割当はこのsnapshot上の将来task用であり、今回の準備ではbackendファイルを編集しない。外部repoへの反映・deploy・実DB操作は別の明示許可が必要。

| task | snapshot/backend内の既存実ファイル／新規追加候補 |
| --- | --- |
| S22 登録・identity | app/api/{capabilities,deps}.py、app/core/settings.py、app/main.py。登録api/schema/service/repositoryとmigrationは現契約照合後に追加パスを固定 |
| S24 保存・独立検証 | app/api/upload_sessions.py、app/schemas/upload_sessions.py、app/services/{upload_sessions,upload_finalize}.py、app/repositories/{upload_sessions,upload_chunks,assets}.py、対応tests |
| S26J/S26 job・変換 | app/workers/worker.py、app/services/{rendition_creation,rendition_processing,formal_preview_processing,ffmpeg}.py、app/repositories/{jobs,renditions}.py、対応tests |
| S27 配布・失効・公開 | app/api/{assets,renditions}.py、app/services/{processed_result_stream,processed_result_delivery,processed_result_integrity,processed_result_finalizer,formal_preview_finalizer,rendition_finalizer,processed_result_backfill}.py、app/repositories/{processed_results,formal_previews,renditions}.py、対応tests |
| migration共有 | app/db/migrations.py、app/db/migrations/、app/db/{phase2b,phase2c}/。番号・適用順・全公開経路のguardを所有者1人で引渡す |
