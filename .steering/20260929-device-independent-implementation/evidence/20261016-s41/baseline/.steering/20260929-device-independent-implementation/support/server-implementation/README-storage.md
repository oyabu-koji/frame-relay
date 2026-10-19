# S24 登録に束縛した受信・最終保存の独立検証

2026-10-11更新。S22登録を保持し、同じSQLite DBへ追加する隔離用overlay。外部checkout・稼働DB/media・旧snapshot/runtime・venvは変更しない。ここにある実装、AST／静的compile、ケース一覧は実行成功ではない。backend import、pytest、HTTPはmainの具体準備レビュー後に別証拠へ記録する。

## 基底と再現

現在の入力はrepo内の `evidence/20261010-s24-base-s22/`。253件のS22 source snapshot、元checkpoint、provenance-before/afterの計256entryを保全したarchiveである。helperはarchive-manifestのSHA-256を `74247944e159a6218527dfc500c4231bc19c46fc33326e8e6d9cb494ba21b737` に固定し、全256entryの件数・path集合・size・hash、provenanceとcheckpointの一致、253件のsnapshotと両provenance/checkpointの一致を確認する。copy後にもarchive全体を再照合する。

2026-10-10に旧tmp `S22/snapshot-001` と `S22C/server/snapshot-002` の253件全hash一致を観測して保全したが、2026-10-11の再開確認では旧S22 snapshotとpreparation/provenanceも取得不能となった。旧S20 snapshot/preparationの欠落と同様に原因は未確定。旧tmpの一致は歴史観測として保持し、helperは現在の入力として再検証したと称さず、旧領域を復元しない。生成provenance/checkpointにはarchive入力と旧S22/S22C tmp未再検証を明記する。S22 provenance内のS20 base hashも歴史参照として保持する。外部source246件・site-packages1657件・interpreter/.pth/pyvenvのread-only再照合は継続する。

`backend-storage-overlay.diff` はarchiveに保全されたS22からの加算差分。旧 `backend-overlay.diff`、`prepare_registration_snapshot.py`、`cases.json`、READMEと、SQL001・登録test26件は保持する。旧S22の再実行は保全済みS22 sourceを新しい隔離準備へ明示して使用し、更新後overlayを旧S22と称さない。

`prepare_storage_snapshot.py --revision 001` はstdlib/ASTだけで `S24/snapshot-001`、`preparation-001`、実行前config/command/checkpointを作り、`runtime-pytest-001` は作らない。現在server-isolation担当も変更中のため、mainが両担当のsource凍結を確認するまではhelperを実行しない。sourceがcopy中に変われば拒否し、不完全なrevisionを実行しない。既存revisionを上書きしない。

準備後、mainが実行するcommandは `preparation-001/command.json`。従来と同じ外部Python `-I -B -S` と凍結 `server-isolation/run_pytest.py --config .../run-config.json` を用いる。guardの書込/SQLite root・認証・禁止ネットワーク/subprocessはこのbackend変更では拡張しない。

## wireの内部設定

すべてのrouteはbootstrap Bearerと既存 `X-FrameRelay-Registration-Secret` によるexact登録認証が必須。秘密はbody/query/job/DB/responseへ保存しない。S22 discoveryは引き続きregistrationだけを広告する。iOS製品への受信wire採用・接続はS24I以後で別途検証する。

| route | 入力／結果 |
| --- | --- |
| `POST /frame-relay/v1/uploads` | 下記8項目をJSONで受理。同一operation/全bindingなら同じsession、異なる内容は拒否 |
| `GET /frame-relay/v1/uploads/{session_id}` | 全8項目をqueryで完全一致照合し、binding/status/chunk_indexes/evidence/failure_codeを返す |
| `PUT /frame-relay/v1/uploads/{session_id}/chunks/{index}` | 同じquery、既存Content-Range/X-Chunk-SHA256とraw body。受信完了を保存証拠にしない |
| `POST /frame-relay/v1/uploads/{session_id}/finalize` | 同じquery。全chunk後に一意finalize job。completedでも証拠とjob対応がない結果は拒否 |
| `DELETE /frame-relay/v1/uploads/{session_id}` | 同じquery。receiving/failedからcancelledへ。finalizing/completedの取消しは受理せず、旧bytesや確定原本を削除しない |

8項目は `destination_id`、`registration_id`、`registration_generation`、`operation_id`、`capture_id`、`content_generation`、`sha256`、`byte_count`。destination/registration/operation IDはS22同様canonical lowercase UUID、digestはlowercase SHA-256。`capture_id` は端末のCaptureIDと対応する非空白UTF-8のopaque文字列で、前後空白・大文字小文字・Unicode・pathのような文字も変換せずそのまま完全一致する。UUID推定変換やpath解釈はしない。登録世代は正の63bit decimal string、内容世代/byte数は正のUInt64 decimal stringで無言切捨てしない。実byte上限は既存Settings/既存hard limit/SQLite63bitの最小値を明示検査し、超過は受付拒否する。chunk size/数/active limitは既存設定を使用し、snapshot用の秘密値は導入しない。

serverが生成したsession UUIDをpathへ使用し、capture IDはpathに使わない。POSTは `binding` を返し、そこへ `session_id` とdecimal stringの `chunk_size` を追加する。statusは `receiving/finalizing/failed/cancelled/completed`。成功200、認証401/403、対象不一致・不許可状態409、形式422、DB不明503。全成功/失敗で秘密や私的pathを返さない。

proofは `schema_version=fr-final-read-v1`、`method=final_destination_read_back`、evidence UUID、全byte数/digest、UTC observed_at、committed/final_save_completedを持つ。外側bindingへoperation/登録/対象/内容世代/sessionを束縛し、同時刻やHTTP成功でidentityを代用しない。

## 保存・claim・復旧

同DBのimmutable `fr_upload_bindings` と `fr_upload_chunks`、可変 `fr_upload_states`、`fr_job_claims`、immutable `fr_storage_evidence` を追加する。legacy sessionの一括期限処理/全temporary directory cleanupと新受信の所有範囲を混ぜないため、FRのstate/chunk台帳を分離した。別DB・別worker queueを作らず、既存settings/range検証/jobs claim・lease recovery/asset tableを再利用する。legacy媒体・旧verified/completedは自動移行しない。

1. exact登録と8項目を短いtransactionで受付bindingへ固定。再送は全項目一致を要求する。
2. receiverごとにserver生成private stagingを排他作成。上限・chunk全hashを測定し、flush/fsync/close後に同じbinding/receiving状態を再確認する。chunkはno-overwrite publishし、commit応答欠落で残ったchunkはwriter外の独立read後に再照合する。既存commitのchunkが消失・変化していれば再送の成功応答を返さず、raceで新しく現れたpathは次のrequestで独立readする。cancelはactive stagingを削除せず、実stream終端後のcallbackを拒否し、そのreceiver自身のstagingだけ片付ける。
3. 全chunk受信後、`fr_upload_finalize` を既存jobsへ一意enqueue。既存 `claim_next_job` と同transactionで単調世代＋UUIDtokenを発行する。job ID/秒精度時刻をclaim identityにしない。success/failure/renew/cleanupはrunning＋有効lease＋世代/token＋全bindingを毎回照合する。
4. attempt固有assemblyを排他作成、全chunkを実readし、flush/fsync/close。短いfenced transaction内でfinalへno-overwrite hardlink publishする。原本pathが既存なら上書きせず、後段で必ず独立検査する。組立hashだけでは成功にしない。
5. writerを解放してfinalを**新FDでEOFまで**独立readし、byte数/digestと前後FD/pathのdev/inode/size/mtime/ctimeを照合する。読みながら別writerが進むことを実thread barrier試験へ束縛する。
6. 短い再fence transactionで最新claim/binding/最終statを照合し、evidence＋asset＋session completed＋証拠付き一意 `fr_conversion` job＋finalize doneをatomic commit。証拠INSERT/job INSERT/commit前の失敗は全DB結果をrollback。publish後のファイルは保持する。commit応答欠落はexact GETで確定する。

finalは他媒体を置換しない。期限切れworkerは自分の旧assemblyを含めcleanupできず、新attempt・chunks・finalを破壊しない。旧attempt残存やcommitted chunksは保持し、後続の対象別cleanup方針へ残す。実ファイルとDBの一括atomic性は主張しない。無関係な外部writerがファイルを変更することはFD/stat照合で検出するが、バックアップ巻戻しやOS外からの改変防止を提供するものではない。

`fr_conversion` はsupported job集合に含めず、S24ではqueuedのまま。Log検出・変換資材・品質・公開receiptを捏造しない。App起動/S22登録のdiscoveryを変換対応済みにしない。

## legacy入口のgate

`legacy_entry` は永続bindingとasset.original_pathから管理対象を確認し、旧session GET/PUT/finalize/cancel、旧upload finalize worker、preview/formal/renditionの受付・processor・finalizer・backfill・processed_result repository・job完了/失敗の早期returnより前に拒否する。FR schemaが存在して壊れている場合やFR namespace/状態にbindingがない場合はlegacyへfallbackしない。S26/S27まで、検証済みFR原本も旧変換/公開へ流さない。

001のSQL digestとdestinationを保ったordered002 migrationを同transactionで適用する。worker単独起動もrecovery/claimより前にmigration検査し、未知/破損ledgerを拒否する。新FR処理と共通startup backfillの接続は明示closeする。

## ケースと未確認

`cases-storage.json` は旧S22 39node/46caseを先頭のまま保持し、新FR 39nodeと関連upload/job/worker、旧processor/finalizer/backfill/multipart回帰40nodeを個別指定する。合計118node/126case。旧authの3値、streaming rangeの3値／4値、新たに対象に含めたlegacy finalizeの2値をASTから数え、各nodeの展開数をcheckpointへ残しconfigへ固定する。loop内の中断境界・各不一致条件を別pytest case数へ水増ししない。0件・不足・skipを成功にしない。

再開時はASTのみ成功していたが、静的compileでformal_preview_finalizer/formal_preview_processing/rendition_creation/rendition_finalizer/rendition_processingの5fileのfuture import順序違反を検出し修正した。helperもASTに加えてbackendを実行しないcompileを行う。新fixtureの4byte chunkはmax_size=524288と組にして既存Settingsのchunk数制約を満たし、製品既定値は変更しない。

試験は初回/既存final全read、chunk/最終ファイルの欠損・切詰め・差替え・symlink、各write/commit境界中断とreopen、実threadの旧claim/新claim競合、writer外hash、受信中cancel/遅延callback、schema rollback/001保持、legacy入口gate、job非変換を扱う。合成bytesによる保存技術試験であり、実撮影G2B、TLS/Wi-Fi/Tailscale、変換/公開、実機受入を満たさない。実pytestと2process HTTP再起動試験は未実施。
