# S28 保存原本catalogの部分引渡し

現在の登録で、同じ接続先へ以前保存した原本identityを1ページずつ発見し、同writerへ観測して通常Libraryの別remote一覧へ表示する。原本の現在存在、正式Rec.709品質、公開/取得/確認/ACKには昇格しない。schema7を保ち、偽のローカル原本や撮影記録を作らない。

## 実装範囲

- 認証metadata `GET /frame-relay/v1/uploads/inventory`。limit1..32/32+1 keyset、現接続先/登録世代/limitへ束縛したcanonical cursor、response256KiB/opaque capture2048 UTF8 byte上限。破損completed状態や異常cursorはpage全体を拒否する。[wire](wire-contract.json)
- Native adapterは厳密JSON/duplicate key拒否、有界response、redirect拒否、completion/invalidation待ちと現資格情報のawait後再照合を使う。同writerの元command/payload exact lookupで応答不明を解決するまでcursorを進めない。
- remote-only/ローカル内容衝突を別表示する。UTF8 byte identityを保ち、撮影日時は不明のまま扱う。自動媒体取得・確認・ACKを生成しない。
- 接続画面の明示ボタン/続きと同じLibrary更新へ接続する。Formから自然高ScrollView/カードへ変更し、固定close・入力設定・全本文/ID/disabled/Task/離脱時消去を保持した。全文と全12文字サイズを保ち、native文字計測/semantic buttonの表示を用いる。

## 実行証拠

| 範囲 | 結果 | 証拠 |
| --- | --- | --- |
| 隔離server002 | 新16宣言49展開＋既存230＝279case成功/skip0、guard/import/依存/外部source/snapshot drift0 | [server002](server-runs/002/runtime-pytest-002/result.json) |
| 端末関連34 | 7suite36宣言75展開成功、skip/診断/runtimeWarnings0 | [Unit34](runs/inventory-unit-34/result.json) |
| 実SDK35＋隔離HTTP | 明示新登録/新namespace認証→32+1件→再open33件、media0/旧行・原本不変/全owner終端、実parent/child exit0 | [結合判定](server-runs/http-001/combined-result.json) |
| 全Unit36（表示調整前） | 638宣言602成功/36skip、1020展開（空template除く1019）、309入力不変/診断/runtimeWarnings0 | [Unit36](runs/final-unit-all-36/result.json) |
| 通常UI49 | fullflow1成功/skip0、全12監査、sync説明/操作への通常scroll、fixed close/content境界、閉鎖HTTPS拒否と保持/再起動 | [UI49](runs/inventory-ui-49/result.json) |
| 最終全Unit62 | 638宣言602成功/36skip、1020展開（空template除く1019）、最新309入力不変/診断/runtimeWarnings0 | [Unit62](runs/final-unit-all-62/result.json) |

最大UI50もfullflow1成功/skip0・全12監査が成功。49/50は同じ309入力・compiler/analyzer診断/xcresult runtimeWarnings0で、通常largeへ復元した。UI後51はVERIFY1成功/seed1skip、原本と外部sentinel2本/immutable manifestはbytes一致、同writer/Keychain/全logical・media reader空を確認した。[UI50](runs/inventory-max-50/result.json)、[VERIFY51](runs/inventory-post-51/result.json)、[実ファイル照合](inventory-fixture-after51.json)。

後続の新登録入力/focus対応は最大58・通常59/VERIFY60・新第5初回UI61で成功した。App差分はConnectionの6入力focus/本人drag時解除だけで、metadata/登録/媒体/Keychain処理は不変。49/50の非入力画面の証拠と、最終全Unit62を層別に引き継ぐ。

最終 [DI-SOURCE-20261023-02](source-binding.json) は414入力（App/Unit/UI/project309・server97・永続6・steering2）、hash `e74ef2a32f52fcf16b41395fb6aea4c65c01fa81f79804a34bf6e9e434d4be4a`。旧395/H01版は当時の履歴のまま保持する。実機Q01は最新source/buildへ別途束縛が必要。既存一覧/原本再生・停止は通常UI63/最大64が各2成功/skip0、UI後65は2成功/SEED1skip、cleanup照合66は1成功/SEED1skip、generic iOS署名なしbuild67が成功。最終code309入力は各run前後/現物が一致、compiler/analyzer診断/xcresult runtimeWarnings0。[実行版・差分・継承範囲](execution-binding.json)、[5環境の実ファイル/Simulator保全](final-fixture-simulator-preservation.json)、[開始dirtyからの差分](session-delta.json)を参照する。

今回の5部分は [tasklist](../../tasklist.md) とS34/S31/S49各証跡へ対応する。全steeringを完了とはせず、既知原本publication manifestの版付き投影等の資材不要なコード残件、通常strict dispatch/全媒体producer、正式変換/ISO本人判断/実機条件を分けて引き継ぐ。新しい独立検証は明示 `$validate-implementation .steering/20260929-device-independent-implementation/` の別工程。

## 途中失敗を保持

server001の新test1期待値（既存storage_schema_unavailable/HTTP409を503と誤期待）はtestだけを厳密化して002へ。端末compile33はtest actor準拠を分離した。既存test/guard/sourceは維持した。

UI38の長いidentifier query、39の新row見出し、40/41のclose Contrast、42の既定見出し、43の最大文字で画面外の登録世代、44の青字操作、45/46の説明/操作DynamicType、47の画面外sync監査を失敗記録/実行版/画像ごと保持する。[診断](ui42-43-diagnosis.json) と [自然高変更の比較](connection-natural-layout-review.json)。47のcropはfooter領域と画像一致したが、内部UIKit原因/actual target frameは未確定。監査mask/issue受理/除外/文字サイズ制限を追加しない。

## 保全と残件

専用第4の新規空rootだけにSEED37を一度実行。既存rootの修復/再seed/原本copyは行わない。閉鎖loopbackは前後ECONNREFUSED61を確認し、製品native adapterの失敗を使う。non-listening socketの初期準備案はpreflightで止まり、seed前に閉鎖済み。隔離HTTPは終了・秘密JSON削除、実データ/外部serverへ変更なし。

全S28/全steering/実機・品質・PRD受入は未完了。正式manifest/通常媒体・本人確認/複数操作と全producer統合を残す。標準資材/ISO判断/実機条件の不足は直接依存する枝だけの保留とし、metadata成功を未実装部分の完成へ拡張しない。新差分の独立implementation validationは別の明示Workflow。
