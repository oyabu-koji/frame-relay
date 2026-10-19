# S27 canonical publication wire の隔離 HTTP probe

この支援は、S27 backend の正規 `fr-publication-v1` router と本物の iOS codec を別 process の loopback 接続で検証する。使用する authority は `backend/tests/frame_relay_publication_fixture.py` の明示 factory に限る。通常の製品 router/default factory は正式品質 proof 未接続を拒否したままで、環境変数や API に authority 切替を追加しない。

合成 Movie は S25 の 969,998 byte、SHA256 `8a77b6c2cfdedbe850148210eada8851956f10942203aec4eae8f9e552a8b984` を read-only 入力とし、新 runtime へ copy する。ftyp `qt  ` と `video/quicktime` を一致させる。S24 実受信/finalize と S26J の fenced technical copy adapter から同一 original の別 candidate を作り、V1 だけを初期公開する。Rec.709 変換・出力品質・製品全 owner の受入証拠ではない。

## 所有と準備

新規所有は `prepare_publication_probe.py`、`publication_fixture_listener.py`、`run_publication_fixture.py`、`run_publication_simulator_probe.py`、本 README の 5 file。既存 `prepare_rendition_fixture.py` の stdlib metadata helper、`isolation_guard.py`、`listener_lifecycle.py`、`run_pytest.py` の設定/FD helper を変更せず固定 copy する。

backend 担当の `prepare_publication_snapshot.py` による凍結済み `run-config.json` と `checkpoint-files.json` を入力とする。準備 helper は checkpoint の指定 SHA256、config/provenance/snapshot 全 file、外部 source/interpreter/site-packages/.pth、wire を照合し、新 HTTP snapshot へ copy する。backend snapshot の生成をこの helper で重複しない。wire の固定 SHA256 は `455868ebe8d057ad32471a169396333c03cd1bcf2b4a4986f3147935f2617e0a`。

main が実 project/scheme/test plan/destination を確認し、同 source の `PublicationHTTPFixtureTests/canonicalPlaybackConfirmationInvalidationAndReplacement()` を SDK に列挙した後に使う。

```sh
python3 -I -B -S .steering/20260929-device-independent-implementation/support/server-isolation/prepare_publication_probe.py --revision 001 --backend-config /private/tmp/fr-di-20261015-s27/S27/preparation-001/run-config.json --backend-checkpoint-sha256 <review済hash> --fixture-movie <S25保全Movie.mov> --enumeration <SDK列挙.json> --xcode-list <実構成.txt> --destinations <実destination.txt> --destination-udid DFE46693-E8DD-4814-8957-4F327699F719 --derived-data /private/tmp/fr-di-20261015-s27/DerivedData
```

これは placeholder を含む説明であり、そのまま実行しない。不足入力を架空 manifest で補わない。出力は新 `S27/http-preparation-NNN` と `http-snapshot-NNN`。`runtime-publication-NNN` はまだ作成しない。既存 preparation/runtime を再利用しない。

`commands.json` の `dry_run` は source/config/Movie/provenance の検査と child command 表示だけ。`execute` は main の具体 review 後に限り、次の形で実行する。

```text
<固定外部Python3.12> -I -B -S <http-preparation-NNN>/source-snapshot/run_publication_fixture.py --config <http-preparation-NNN>/config.json --checkpoint-sha256 <固定hash> --execute-reviewed-integration
```

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

fixture ASGI middleware は正常 media block だけを 4 KiB/10 ms に分割する。header/byte 内容、canonical admission/FD 所有、製品 source を変えない。これは S25 と同じ全量前進行を観測する合成 schedule であり、製品性能基準や timeout 方針ではない。

## 隔離・終端・証拠

外部 Python 3.12 `-I -B -S`、既存依存と source hash を import 前に照合する。runtime 作成直後に既存 Guard を install し、その後だけ backend/tests factory/site-packages を import する。書込は新 runtime 内、SQL authorizer と実 dir_fd 境界を維持し、外向 socket/全 subprocess を禁止、listener は 1 process で 1 回の `127.0.0.1:0` bind だけ。ffprobe 例外も使わない。22 設定を明示し、実 Settings と照合、HOME は値を変えず継承する。

親と Simulator wrapper は listener と別 process。ready/stop は run identity、実 PID、確定 loopback origin、1200 秒期限へ束縛する。秘密 file は0600、秘密値を CLI/公開 artifact hash へ載せない。Xcode stdout と metadata/stderr は秘密 3 値を伏字にし、metadata tool には秘密環境を渡さない。stderr は伏字後の先頭 8 KiB と切詰め表示を保持する。Xcode の非0/timeoutでも実終了後に summary/全 test tree/build-results を個別回収し、試験失敗と抽出失敗を分離する。内部 xcresult の使い捨て環境保持はあり得るため、listener 終了で秘密を失効させる。

Uvicorn task/connection、response handler、生成 thread を全終端/joinし、全 SQLite 接続の所有 thread による explicit close を監査する。process exit/GC は close の代用にしない。媒体/DB FD の実 inventory が残存 0、guard denial 0、source/依存/原本不変を要求する。秘密は listener finally で削除し、親も実 `Popen.wait()` 後に不在を確認する。強制 signal、親による秘密の救済削除、未終端/未 close、artifact 欠落は失敗として保持する。

静的 compile/準備/dry-run は実 HTTP/AVPlayer 成功ではない。TLS、Wi-Fi/VPN、背景/ロック/実機、Rec.709/聴取品質、製品の external/recovery owner producer は別の未確認範囲として残す。
