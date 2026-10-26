# S26J 変換周辺job・未公開候補の独立実装

S24で確立した保存証拠を、同じSQLite／jobsの変換周辺処理へ接続する。実Log検出・適合標準資材・実Rec.709変換・公開は未実装。周辺処理の成功をS26／S27の完了や実機品質へ読み替えない。API、利用者の再試行UI、外部依存、製品設定の追加はない。

## 入力・準備と未実行範囲

基底はrepoの `evidence/20261013-s24-complete/`。archive-manifestのSHA-256を `9b7b00c81b68dfb8e480deefd8d8b1ec24f9db421ac4bfd4b29fbbf896d6e247` に固定する。全386entryの集合／size／hash、S24 preparationのcheckpointとprovenance、261件のsnapshotとpytest終了後provenanceを照合する。copy後もarchive全体を再照合し、外部source246件・site-packages1657件・interpreter／.pth／pyvenvの照合を継続する。旧tmpの復元・現在の再検証は主張しない。

`backend-conversion-overlay.diff` はこのS24基底からの加算差分。SQL001／002、登録test26、S24 helper／cases／diff／README、server-isolationと過去archiveは変更しない。現在overlayのS24試験は新段階の期待へ限定更新するが、旧S24成功版はarchiveに残る。

mainのsource凍結レビュー後の準備コマンド:

```sh
python3 -I -B -S .steering/20260929-device-independent-implementation/support/server-implementation/prepare_conversion_snapshot.py --revision 001
```

helperはstdlib／AST／非実行compileだけで、新しい `/private/tmp/fr-di-20261001-5ljls2fr/S26J/snapshot-001` と `preparation-001` を作る。`runtime-pytest-001` は作らず、既存revisionを拒否する。実行は生成された `command.json` と実効configをmainが確認してから行う。backend import／pytest／HTTP／helperの実行成功は本書では主張しない。

## 永続化と世代

ordered003 migrationは既存001／002のdigestとdestinationを保持する。同DBに次を加え、公開pointerや確認台帳には書かない。

| table | 記録 |
| --- | --- |
| `fr_conversion_candidates` | 原本session／保存evidence／asset／exact job payloadに束縛する候補ID・候補版世代・状態・失敗／未公開output |
| `fr_conversion_heads` | 同じ一意conversion jobの現在候補 |
| `fr_conversion_claims` | jobのclaim世代・UUID token・対象候補 |
| `fr_conversion_retry_intents` | 明示的な内部retry意図とその受理候補。更新／削除不可 |

S24の一意 `fr_conversion` jobを再利用する。初回claimはcandidate generation 1を作る。期限切れの再claimは同じ候補版を使い、claim generation／tokenだけを更新する。通常失敗はjobと候補をfailedにし、queueへ自動復帰させない。未接続adapterも明示 `conversion_adapter_not_implemented` で1回の処理を終える。未接続時はexact保存証拠とclaim確認後に失敗し、大きい原本を不要に全readしない。

候補ID／由来／候補pathはimmutable。claim、候補作成、現在候補の選択は同transactionでcommitする。保存証拠の照会は変換jobのqueued／running／failed／doneから独立するが、exact evidence／session／asset／binding digest／schemaの対応を引き続き要求する。不明・欠落・別対象の証拠はadapterへ渡さない。入口で拒否したjobは同claim transactionでfailedにし、候補を作らない。`is_log=0` は入力検出・変換適合の根拠に使わない。

## 内部retry契約

`repository.retry` はsession、直前のfailed候補ID、canonical UUIDのintent ID、exact source payloadを受ける内部serviceである。本人操作UIやネットワークrouteはS28以後の接続対象であり、このtaskでは追加しない。

初回受理では同jobをqueuedへ戻し、新しい候補版世代を1つ作る。同intentの再送は受理済みのcandidate ID／generationを維持する。返すdictのstatus／outputはその候補の**現在観測**であり、queuedからrunning／failedへ変化し得る。受理事実の同一性と結果の現在観測を混同しない。同intentのpayload変更は拒否し、別intentで旧候補を再指定しても新しい現在候補を上書きしない。retry commit応答欠落は同intentで照合する。原本再受信は行わない。

## 入出力とclaim fence

実adapterを渡した経路では、新しいread-only FDで原本をEOFまで全readし、S24のbyte数／digest／fingerprintを照合する。SQLite writerは全read中に保持しない。同じFDを先頭へ戻してadapterの同期呼出しへ渡し、実returnとFD closeまで保持する。pathの再openをadapterへ委任しない。呼出し前の短いtransactionでclaim／候補／由来を再判定し、実処理前後のFDとpathのfingerprintも確認する。

adapterは同期終端契約 `fr-conversion-adapter-v1` を持ち、適合判定、候補／claim／入力context、実output byte数とdigestを返す。現在受理する成功種別は試験用 `unpublished_technical_fixture` だけ。compress-only、タグ変更、実Rec.709成功への置換をしない。製品workerはadapter=Noneである。fixture adapterはtest注入だけで、標準資材・実変換の実装として広告しない。

outputはclaim固有の排他stagingへ書き、flush／fsync／close後に新FDで全readする。短いcurrent-claim transactionでserver生成の候補pathへno-overwrite publishし、候補pathも新FDで全readする。最後の短いtransactionで現在claim／source fingerprint／candidate fingerprintを再照合し、候補の技術結果とjob doneを同時commitする。outputには `published=false`、`rec709_verified=false` を固定する。既存候補byteを上書きせず、原本・V1公開pointer／byte／確認を変更しない。

success／failure／renew／cleanupはjob running、有効lease、claim世代／token、現在候補とexact由来を再判定する。cleanupは同期attemptの実終端後にそのattempt stagingだけを対象とし、期限切れworkerは自分の旧stagingを含め削除できない。古いattempt残存やcommit前publish済み候補は保持し、後続の対象別回収方針へ残す。OS外からの改変防止やfileとDBの一括atomic性は主張しない。

旧formal／rendition／preview finalizer、backfill、processed_result repositoryの `legacy_entry` 拒否は維持する。新候補を旧即時公開・compress-only fallbackへ接続しない。

## 検証予定

`cases-conversion.json` はS24の118node／126caseを引き継ぎ、worker段階更新による1nodeの明示renameと期待変更を含む。新19node／34caseを加え、合計137node／160caseをASTで固定する。loop内部の条件を別pytest caseへ水増ししない。0件／不足／skipは成功にしない。

実S24受信保存→本worker、証拠欠落／別session／asset／binding／schema、未接続／不適合adapter、exact retry再送、SQLite失敗／commit前後中断とreopen、原本差替え／短縮、実threadでの旧claim遅延とwriter解放、V1 fixtureのpointer／byte／確認保持を対象にする。fixture成功は未公開候補技術試験に限り、実撮影G2B・Log適合・標準変換資材・実Rec.709映像・公開ACK・実機受入を満たさない。
