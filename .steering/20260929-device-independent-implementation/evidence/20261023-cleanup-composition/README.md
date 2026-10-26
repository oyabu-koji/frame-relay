# S34 条件付き複数容量整理（2026-10-23）

通常のCompositionから、固定した複数原本の確認→動画別の最新条件/全使用者終端の再判定→実unlink→結果/通常一覧/再起動を接続した。保存検証・同版の有効確認・支持schema・原本対応・失効の最終writer guardを維持し、全transport receipt/inventoryのfenceを整理にも共用する。未解決子を保留し、独立した終端子だけ受付を再開する。

この部分の非実機検証は完了。正式証拠producer、通常strict通信、新規Photos/複数保存、実機・品質・PRD受入とS34全体は未完了。合成proof/SDK callbackを実転送・標準Rec.709の成立へ昇格しない。[部分判定](partial-acceptance.json)と[現行tasklist](../../tasklist.md)を正本にする。

| 検証 | 結果・実行版 |
| --- | --- |
| 新規の通常Composition/削除境界 | 8宣言27展開成功。両storeのhash中/最終writerの関連変更拒否・別動画許容、混在結果、未実行非再開、原本/外部保持。最終292入力 |
| 通常UI | `cleanup-ui-06` 1成功。新規の空rootに4本を生成し、3本選択→キャンセル→再確認→確定→2成功/1未実行→通常一覧/空履歴→再起動の同batchを確認 |
| 結果の厳格AX監査 | `cleanup-post-07` 通常文字1成功、`cleanup-max-08` 最大文字1成功。いずれも削除の再実行なし。最大文字後はlargeへ復元 |
| seed / UI後実disk照合 | seed1成功/VERIFY1skip、UI後VERIFY1成功/seed1skip。2原本のみ不在、条件不足/保持/外部sentinelのhashとimmutable manifest不変、全logical/media reader空、元verification/confirmation/request不変 |
| build | `cleanup-ios-build-10` generic iOS/Debug/CODE_SIGNING_ALLOWED=NO成功。compiler/analyzer診断0 |
| 全Unit回帰 | `cleanup-unit-final-09`は600宣言中568成功/31skip/1失敗、940展開成功/1失敗。既存Photos取消し/失効境界1枝をS31へ診断引渡し。全Unit合格とは扱わない |

Xcode27.0(27A266a)/Swift compiler6.4・言語5.0/iOS27.0、実在project/scheme/test plan FrameRelay、Debugを確認。専用Simulatorは[cleanup](simulator.json)と[regression](regression-simulator.json)。各runのcommand/result/source manifest/stdoutは[runs](runs/)に保持し、実行前後の292入力は不変。raw xcresult/DerivedData/開始時copyは `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-implementation-20261023-_coslmwo/` に保持する。

初回関連38宣言109展開成功、seedの型不整合によるcompile失敗/0実行、新規回帰の準備ID不一致1失敗と修正後4成功を全て保持。後続の全Unitで観測した既存Photos失敗も保持し、試験の除外・assertion緩和で処理しない。前回独立検証の新規指摘0/P2-STOP非実機合格は[inherited-validation-summary.json](inherited-validation-summary.json)で継承する。

mainはApp8/既存test1/新test4の加算差分と所有を確認。[ソース](implementation-source-manifest.json)、[原本・manifest保全](cleanup-fixture-preservation.json)、[文書レビュー](documentation-review.json)を参照。独立validationは開始していない。
