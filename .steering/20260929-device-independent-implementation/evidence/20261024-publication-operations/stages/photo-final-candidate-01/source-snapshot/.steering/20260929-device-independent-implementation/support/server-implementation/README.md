# S22 登録サーバー overlay

2026-10-06。S20の不変 `snapshot-001/backend` に適用する完全ファイル形式の差分候補。外部checkout、本番DB/media、既存S20 snapshot/runtime、venvは変更しない。具体方式はS22の隔離試験とmain確認後に採否を記録する。ここを保存しただけでは試験実行・デプロイ・実機受入の証拠にならない。

## 所有と変更

- `backend-overlay/`: 既存 `app/main.py` 1件と、新規専用migration/SQL、schema、repository、service、API、test。ベースの全文から再現できる `backend-overlay.diff` を併置。
- `prepare_registration_snapshot.py`: 標準libraryだけでbase/overlayのhash照合、fresh snapshot生成、実行源凍結、別provenance/config/manifest生成。backend/pytestをimportせず、listenerも起動しない。
- `cases.json`: S20の既存13node/20caseに新規26node/26caseを加えた、明示39node/46case。
- 既存 `../server-isolation/run_pytest.py` だけを可逆拡張。case file/hash、期待node/case数をconfigから読めるようにし、未指定は従来13/20を保持。JUnitの実数・skipを照合し、不足/skipはexit 72。pytestの実exitとguard/件数検査後のexitを別記する。`isolation_guard.py` は変更しない。

`main.py` はlegacy migration後に専用migrationを呼び、新routerを接続する。startup DB connectionを明示closeする。それ以外の既存backend file、legacy schema/migration、worker、媒体、配信、確認、ACKは変更しない。

## wire v1 の内部判断

| 項目 | 契約候補 |
| --- | --- |
| discovery | `GET /frame-relay/v1/capabilities`。`protocol_version: 1`、DB永続 `destination_id`、`capabilities: ["registration-intent-v1"]` のみ |
| 登録 | `POST /frame-relay/v1/registrations`。bodyは `destination_id` と `operation_id` だけ。未知fieldは422 |
| 照会 | `GET /frame-relay/v1/registration-intents/{operation_id}?destination_id=…` |
| bootstrap | 全routeで既存 `Authorization: Bearer API_TOKEN` 必須。共有bearerだけでは登録意図の照会・再送を認証しない |
| 登録秘密 | POST/照会は `X-FrameRelay-Registration-Secret` 必須。client生成32byte乱数を64文字lowercase hexで送る。fixtureの反復文字は試験専用。serverはdestination/operationとdomain separatorで束縛したSHA-256 digestだけ永続化 |
| ID | destination/operation/registrationは36文字canonical lowercase UUID。Swift `UUID().uuidString` は大文字のまま送らず `.lowercased()` する。全IDを同じものとして代用しない |
| generation | 正の符号付き63bit整数をdecimal **string**で送る。`1`〜`9223372036854775807`、先頭0・符号・数値JSONは禁止。SQLite INTEGERとの対応を検査 |
| receipt | `destination_id`、`operation_id`、`registration_id`、`generation`、`created_at`。秘密/digestは返さない。時刻は `YYYY-MM-DDTHH:MM:SS.ffffff+00:00` の実UTC時刻で全fieldを検証 |
| 正常 | POST初回も再送も200、同一意図・秘密なら同じreceiptを返す。照会も200。成功/不在/error応答はno-store |
| 不在 | 認証済み・正しいdestination・健全なschema/DBに対する照会だけ404 `registration_not_executed` と対象destination/operationを返す |
| その他 | bootstrap/secret形式欠落401、既存意図のsecret不一致403、destination不一致/世代枯渇409、request不正422、DB/未知schema/破損503。これらを404へ変換しない |

404は照会時点の不在であり、並行する元POSTの将来commitを否定しない。復旧は**同一意図・同一秘密**を使い、新意図へ無条件に作り替えない。commit直後の応答欠落・DB例外でも、照会で確定できるまでは実行結果不明として扱う。HTTPキャンセルだけを未実行の証明にしない。

S22Cはsecretを登録意図の前にKeychainへ保持し、store/診断へ平文複製しない。server receiptが存在しても端末store commit済みを意味しない。TLS/実Wi-Fi/OS背景・保護・bootstrap入手UIの採用はこのin-process試験の対象外。

## SQLite と旧登録

既存 `schema_migrations` に011を加えると、phase2c/detector-v2の008以降の厳密latest照合を壊す。そこで同じSQLite DBの `fr_schema_migrations` を分け、version/SQL digestを照合する。初回schema・destination・ledger作成は1回の `BEGIN IMMEDIATE` 内でatomicに行う。適用済みledgerなのにdestinationがない場合は新identityを補わない。backend startup以外でmigrationを暗黙実行しない。

登録は短い `BEGIN IMMEDIATE` で、一意 `(destination_id, operation_id)`、全registrationで一意ID、destination内一意generationを同時commitする。同一意図の並行POSTは同receiptへ収束する。counter上限は新規だけ拒否し、旧receipt replayは許す。counterの型/範囲・receipt全field・secret digestの破損、未知schemaは拒否する。

SQL triggerは旧receiptのUPDATE/DELETE、destination置換/削除、counter後退を拒否する。`authenticate_registration` はexact destination/registration ID/正のint generation/secretだけを照合し、「最新登録」で旧登録を代用しない。新登録から旧確認・旧ACKへ変換する処理は存在しない。確認/配布/ACKの本体と公開gateはS27等へ残す。

## 準備とmain実行

初回の準備コマンド（backend importなし）:

```sh
python3 -I -B -S .steering/20260929-device-independent-implementation/support/server-implementation/prepare_registration_snapshot.py --base /private/tmp/fr-di-20261001-5ljls2fr/S20/snapshot-001 --provenance /private/tmp/fr-di-20261001-5ljls2fr/S20/preparation-001/provenance-before.json --output /private/tmp/fr-di-20261001-5ljls2fr/S22 --revision 001
```

mainがdiff/runner/guard/configを確認してから実行するexact候補（まだ実行していない）:

```sh
/Users/oyabu/dev/rep/latest_template/backend/.venv/bin/python -I -B -S /private/tmp/fr-di-20261001-5ljls2fr/S22/preparation-001/source-snapshot/server-isolation/run_pytest.py --config /private/tmp/fr-di-20261001-5ljls2fr/S22/preparation-001/run-config.json
```

runnerはbackend/pytest import前にinterpreter、外部tracked246件、site-packages全1657件、新snapshotを別manifestへ照合する。guardは全write/SQLiteをfresh runtime内へ限定し、network/subprocessを拒否する。S20と同じ完全一致の不存在ffprobe `-version` 実ENOENT例外のみ許可。既存runtimeは再使用しない。

期待は39node/46case、skip 0、pytest/process exit 0、guard denial 0、全input不変。実際の結果は実行後の `runtime-pytest-001/result.json`、`pytest.xml`、`provenance-after.json` とmainのprocess終了観測で確認する。新規26testはHTTP認証/不在/再送、実SQLiteの並行同一/異なる意図、before/after commit障害と再open、旧資格情報保持、世代上限/型破損、receipt/digest破損、legacy schema/rows/ledger/triggers不変、migration rollback/identity再生成拒否を扱う。

準備時はASTによる非import構文確認だけ。実test、実listener、iOS接続、実機受入は未実施。外部checkoutへ適用していないため、稼働サーバーの機能追加を完了とはしない。
