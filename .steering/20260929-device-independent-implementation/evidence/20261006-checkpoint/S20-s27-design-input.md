# S20 → S27 読取設計入力（2026-10-05）

現snapshotは変更していない。独立validationではなく、ui_probeのread-only調査をmainが統合した実装候補。製品方式・品質・性能閾値の確定ではない。

入力: S20/snapshot-001/backend、runtime-range-003/range-probe-results.json。短Range1024 byteに対し2,097,169 byteを2回hash、2回目transaction内。人工barrier中に別writerがSQLITE_BUSY。37.6msは通常時性能の測定ではない。

## 候補の順序

1. 登録/固定対象を照合しartifact読取leaseを取得。writer外でregular file/範囲を検査し、保持する同じFDから全hash/sizeを照合。dev/ino/size/mtime_ns/ctime_nsとlease世代を前後確認。
2. 短いtransactionで現公開版/provenance/登録世代/失効/FD対応を再照合し、配布receiptと受取登録をcommit。hash中の切替はbyte送信前に拒否。不明commitは同じ操作を照会。
3. writer解放後にそのFDから送信。応答欠落でも受取登録を消さず、完了/切断/取消/body開始前失敗の全経路でFD/leaseを解放。
4. 差替待ちのV1新受理も必要ACK集合へ加える。失効commit済み登録のV1新要求を拒否し、登録/版/世代と実reader解放に対応するACKだけを採用。
5. 公開transactionで最新必要ACK集合/候補/期待世代を再照合しpointerと公開記録を一括commit。hash・媒体送信・ACK待ちは入れない。候補生成だけではV1を失効しない。

Rangeごとの検査cache/省略は採用しない。同じFDでもin-place書込は見える。metadataだけで任意外部書込を完全防止したとはいえず、全writer終端・別名書込禁止・artifact名非再利用・読取中変更/回収禁止が必要。検出後の中断で既送信byteは取り消せない。

## 全経路の引渡し（backend相対）

- services/processed_result_stream.py: 現2回目hashと別open。
- services/preview_stream.py / media_range.py: legacy previewのbody時遅延open。
- services/processed_result_delivery.py: activeと別でもformal_preview_id一致の配信経路。
- services/processed_result_finalizer.py / formal_preview_finalizer.py / rendition_finalizer.py: candidateと即時公開を分離。formal finalizerにはtransaction内原本fullhashもある。
- services/processed_result_backfill.py: startup/worker自動公開。
- repositories/processed_results.py: setter/clear。
- dbの004/007/phase2b/phase2c trigger: pointer自動変更/supersede。
- services/phase2b_migration.py / upload_finalize.py: pointer解除/formal初期化。
- app/main.py / workers/worker.py: recovery/backfill/processor入口。
- services/storage.py: formal昇格はhard linkでcandidate別名を一時保持。DB005/006 triggerでは媒体writeを防げない。

旧APIはserver側対象分類と資格情報で分離する候補。新契約対象は旧preview/result/formal経路も共通gateまたは拒否へ。任意header/client version欠落で旧経路へ逃がさない。登録なし旧応答を新契約対象にも完全維持することと全受取登録把握は両立しない。旧データ採用には既受理legacy streamの解放/照合も必要で、実データ移行許可は与えられていない。

必要な実I/O: hash中/後の同サイズ書換・truncate・path置換・symlink/hard-link書込、配布commit/公開両順序、ACK後遅延V1、commit前後中断/reopen、body開始前/途中切断のFD解放。hash中も別writerが進むこと、拒否時byteゼロ、受理済み応答の版混在なしを観測する。

artifact不変性の保証範囲・旧対象採用境界・検査cache省略・負荷閾値は未採用。可逆な同一FD化/短いwriter区間を実装・試験してから判断する。
