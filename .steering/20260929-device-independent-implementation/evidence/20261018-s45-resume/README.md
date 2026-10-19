# S45再開の検証証跡 — 2026-10-18

E-S45-01の本体を継承し、本人承認3点の通常アプリ接続とSimulator別人拒否の修正を実施した。進捗正本は [tasklist](../../tasklist.md) のS45 / E-S45-02。S45は実装・自動検証範囲でdone、FR-05実機受入は未達である。

## 結果

| 検証 | 結果 | 証跡 |
| --- | --- | --- |
| 関連Unit | 81宣言 / 112展開すべて成功、skip/runtimeWarnings 0 | test-final-01-run.json / summary.json / tests.json / log |
| 通常アプリUI | 3件成功。撮影意図の選択・再起動復元と既存撮影/設定画面。Simulator設定は元の不存在へ復元 | ui-final-01-*、ui-preference-restoration.json |
| Simulator / generic iOS build | 成功、error/compiler/analyzer 0。iOSは署名なしbuildで実機起動とは別 | 各build-results.json、ios-build-final-01-* |
| 文書レビュー | 総則の未合意表現3箇所を修正後、指摘なし | doc-review.json |
| main差分確認 | 既存15file変更・7203不変、欠落/旧証跡変更/所有外変更0。最終202入力はUnit/UI/build/現物一致 | main-scope-review.json、final-s45-resume.patch |

## 原因と修正

確認したSimulatorのVision rev2 CPU経路は、異なるNASA公開肖像の実画素から同じ特徴量を返し、初回だけ微差も生じた。ROI、明示crop、scale、画像入力形式、CI software、CPU指定方式を比較しても残る。SDK内部の具体的原因は未確定であり、SDKの修復を宣言しない。

アプリ側でこの出力をそのまま同一人物と信頼する欠陥を修正した。同一固定ROIから上限2回取得した特徴量と、Visionとは独立した実画素digestを保持する。特徴量が一致しても画素が異なる場合は同一IDの継続/再捕捉を拒否する。距離閾値・既存assertを緩和せず、選択直後の直接/blank後の別人置換も、新プロセス単独実行で確認した。固定参照を別画像で更新せず、raw buffer追加保持・人物情報の永続化/送信は行わない。

過去の失敗に加え、今回の診断と単一参照では初回微差を取り逃した失敗も `vision/` に保持。最終は同ディレクトリのworker-report.json、collision-fix-03 / collision-cold-immediate-04を参照。

## 未確認

同じ人物でも画素が変化して特徴量が衝突すると保持へ進む。動く人物の同一性、別人通過/遮蔽/再捕捉、通常合焦・前後追従、追跡OFF人物優先AF、タップ/補正cropとpreview座標、実Log/カメラ入力、両writerの継続・同期、2回生成の追加負荷、暫定3秒の実機採用はDV-06未確認。利用可能な実機destinationはなく、Simulatorから実機品質へ昇格していない。

## 再現と保全

完全な実行コマンド、環境、source hash、時刻、終了コードは environment.json と各 *-run.json / *-sources.json。xcresult/DerivedData原本と開始時全hash/証跡外baselineは `/private/tmp/fr-s45-resume-20261018-1tlmtf7y/`。buildだけのresult bundleが返すtest count 0はテスト成功へ数えていない。stdoutのAppIntents metadata警告・画像decoder診断はログに保持する。

今回差分の変更前後は baseline-changed/ と final-source/。S46以降・他task修正・独立validationは未実施。次工程は明示 `$validate-implementation .steering/20260929-device-independent-implementation/`。
