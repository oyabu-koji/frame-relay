# S27 公開・配布・確認台帳

FR 専用の nullable current head、候補別 sealed artifact、公開／配布／確認／ACK の exact operation 台帳を同じ SQLite に追加する。SQL 001〜003、旧登録 26 試験、既存準備 helper／cases は保持する。正式 S26 proof authority は未接続であり、製品起動は `publication_proof_not_implemented` として公開／配布を拒否する。技術 fixture の成功は実 Log 判定・Rec.709 品質の証拠ではない。

## 本体と wire

契約正本は `s27-wire-contract.json`（SHA-256 `455868ebe8d057ad32471a169396333c03cd1bcf2b4a4986f3147935f2617e0a`）。opaque ID を無変換で保持し、server が生成する rendition UUID だけを path に使用する。登録単位の typed operation と完全 payload で再送を照合する。lookup は lookup 自身を echo し、受理時の `original_request`／`original_result` を返す。ACK の operation ID は invalidation ID であり、新しい操作 ID を発明しない。

初回公開は current=NULL から始める。replacement 中は旧版を保持し、配布受理と同じ transaction で追加した全 recipient を動的 required 集合とする。登録更新は旧登録を置き換えず、ACK 済み登録の旧版新要求を拒否する。最後の公開 transaction 内で全件 ACK を再照合する。過去の exact replay は当時の受理結果であり、現在の配布権限・確認状態を復活させない。

source 配布の実 commit receipt が初期 RetrieveMediaCommand の入力となる。各実 read は source／registration／gate に束縛した新しい range 配布を受理し、GET はその ticket を一度だけ消費する。全 hash は writer transaction 外で新 FD を読み、短い transaction で current／登録／ACK／payload／fingerprint を再判定して admission を commit し、同 FD から送出する。消費済み ticket の再送は media 0 byte。応答欠落・途中切断・URLSession 内部再送で ticket を再消費せず、新しい実要求を受理し直す。公開前に受理済みの response は旧 inode を保持できる。

artifact は candidate とは別 inode を create-only で作り、全 writer 終了・fsync・close 後の新 FD 全 readback を経る。共通 app file helper の書込／別名 publish／回収は sealed namespace を拒否する。既知の旧取得／確認／finalizer／backfill／pointer 経路は FR 対象を拒否し、header 省略 fallback を作らない。004 は旧 active pointer／確認更新と processed_result 挿入にも拒否 trigger を加える。任意の外部直接 SQL 全般を保証するものではない。

read-only mode と同 FD だけで外部直接 in-place 書込を不可能にはしない。fingerprint／hash の観測で開始拒否または途中中止するが、送出済み bytes の取消や外部改変中の版混在防止までは主張しない。candidate の別名書込は sealed artifact と inode が異なる。アプリの全既知 writer が sealed artifact を変更・回収しない所有規則を前提にする。

`media_type` は bounded ftyp length／brand 照合で確認した `video/quicktime` または `video/mp4` を永続化し、manifest／配布結果／GET Content-Type を一致させる。これはコンテナ識別だけで、codec・出力形式・S26 品質の採用決定ではない。invalidations は binary keyset、最大 8 件かつ実 serialized envelope 192 KiB 以下。同じ JSON bytes を送信し、短いページの next_after を尊重する。各 poll は null から開始し、空ページに nonnull cursor を返さない。

## fixture 境界

`tests/frame_relay_publication_fixture.py` の明示 factory だけが `FixturePublicationAuthority` を注入する。stored proof_kind は `technical_fixture`、候補 output は published=false／rec709_verified=false のまま。製品 router は factory を import せず、環境変数や API で解除できない。同じ fixture DB を通常 authority で再 open しても拒否する。

`seed_candidate(settings, registration, secret, movie_bytes, capture_id, operation_id, source_bytes=None)` は実 S24 受信／最終保存と S26J claim／技術 adapter を通す。戻り値は candidate_id、session_id、evidence_id、asset_id、original、movie_sha256、media_type、binding。同 original の V2 は同 capture/source_bytes と別 upload operation で作る。同期関数なので async HTTP からは threadpool で呼ぶ。HTTP の実 fixture は既存 QuickTime 動画を使い、canonical wire は実 iOS adapter と共通にできるが、loopback／使い捨て DB／秘密／fixture-only 証跡を必須とする。専用 HTTP 支援の仕上げ・実行は後回し。

## 最小確認と未実施

`cases-publication.json` は 4 node／9 case だけを実行対象にする。

- 動的全 ACK、旧登録保持、ACK 後 V1 新要求拒否: 1 case。
- production authority の fixture DB 再 open 拒否: 5 case。
- 配布 commit 前後の応答欠落と exact lookup: 2 case。
- canonical QuickTime GET と current のままでの ticket 再利用拒否: 1 case。

現在の新試験本体 33 node／70 case と既存 137 node／160 case は保持する。網羅 230 case の実行は今回の前提にしない。残る競合／SQLite fault／FD 終端／外部改変／parser／pagination 試験、旧回帰、実 iOS HTTP 結合は未実施として引き渡す。ここでは backend import／pytest／HTTP／helper の実行成功を主張しない。

main が source と実効隔離設定を確認した後の準備:

```sh
python3 -I -B -S .steering/20260929-device-independent-implementation/support/server-implementation/prepare_publication_snapshot.py --revision 001
```

基底は `evidence/20261014-s26j-complete/` の 265 snapshot files。archive-manifest SHA-256 `ba9870b16789430f9d0b6372ede698a537628b9d5a65b1985bb261951f9d6c18` と全 345 entry、checkpoint／provenance／pytest 終了後 snapshot を照合する。外部 source・依存・interpreter の不変照合も既存 helper と同じ。旧 tmp を復元・再検証したとは扱わない。

新しい `/private/tmp/fr-di-20261015-s27/S27/snapshot-001` と `preparation-001` を作り、既存 revision は拒否する。runtime-pytest-001 は未作成のまま保持する。実行は生成 `command.json` の exact command を使い、既存 frozen `server-isolation/run_pytest.py` と guard を再利用する。新 runner は追加しない。command／config のレビュー後に main が 4 node／9 case、skip=0 と runtime 終端を確認する。`backend-publication-overlay.diff` は不変 S26J snapshot に対する加算差分であり、旧 archive 成功版を改変しない。
