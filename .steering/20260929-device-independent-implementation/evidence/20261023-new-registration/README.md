# S28 明示新登録の部分引渡し

別storeに束縛された有効なv2 Keychain情報を保持したまま、本人が別入力から新しい登録を始める経路を追加した。通常のrestore/register/保存情報で続行は旧資格情報を採用しない。

- current storeの登録intent/recordが空の場合だけ、明示入力を許す。UUIDを同writerで確定してからnetwork/Keychainへ進み、await後も同UUIDと登録空条件を確認する。
- 新情報は `store.<uuid>.connection` / `store.<uuid>.initial.<destination>` へcreate-onlyで保存する。旧global accountのbytes/secretを上書き・削除せず、current namespaceの破損/孤立initialも旧globalへのfallbackで隠さない。
- 同store中断は通常の続行とexact照合へ戻す。v1/unbound/破損/読取不明は新登録の許可にしない。旧確認/必要ACKは移植しない。
- 入力取消・開始前・離脱時にbearerを消去する。入力するURLはHTTPSのoriginだけ。UIからの正HTTPS成功は別の未確認範囲。

## 検証と版

[関連Unit32](runs/new-registration-unit-32/result.json) は5suite/31宣言47展開成功、skip0。新2suiteは10宣言18展開。29/30のcompile失敗と31のconcrete async default witness解決失敗を保持し、明示async wrapperとprivate同期helperで修正した。既存Supportのactor準拠は空extensionへ分離しただけで既存assertionは保持する。

[隔離実SDK35](../20261023-remote-inventory/server-runs/http-001/combined-result.json) では明示新登録→別namespace資格情報による旧保存原本metadata取得を確認した。正HTTPS UIや実機の証明にはしない。

専用第3SimulatorのSEED53は1成功/VERIFY1skip。最終の最大UI58と通常UI59は各1成功/skip0で、取消・HTTP拒否・bearer消去・離脱/再入場・再起動を確認した。UI後60はVERIFY1成功/SEED1skip、旧Keychain2件のhash/current UUID・revision/空intent・登録・原本0とimmutable manifestを保持した。309入力は各実行前後不変、compiler/analyzer診断/xcresult runtimeWarnings0。[UI58](runs/new-registration-max-58/result.json)、[UI59](runs/new-registration-ui-59/result.json)、[VERIFY60](runs/new-registration-post-60/result.json)、[fixture](fixture-after60.json)。App launch fixture/資格情報の自動修復/既存root再seedは行わない。

54はキーボード後のApp全体swipeで入力欄へ届かず、新test helperだけを実ScrollView/viewportへ修正して通常55成功。最大56/57ではbearerがcontent下端427.7ptより下の666/680.7ptに残り、interactive指定だけでは解消しなかった。6入力のfocusを束縛し本人drag中だけ解除する表示対応を加え、58/59で成功した。[54診断](ui54-diagnosis.json)、[56/57診断](ui56-diagnosis.json)、[focus差分](keyboard-focus.diff)。全本文/既存ID/Task/入力設定/登録・資格情報契約/全P2は維持し、失敗も保持した。

初回接続の既存2件は52で成功。最新focus対応後の未登録初回UI61も、新しい第5空環境で2件成功/skip0・原本0を確認した。[UI61](runs/connection-legacy-final-61/result.json)。全Unit62（有意味1019成功/36skip）とunsigned iOS build67が成功し、最新414入力と実行版は [共通引渡し](../20261023-remote-inventory/README.md) へ集約した。

## 未完了と再開

全S28は未完了。通常HTTPSの新登録UI成功、正式公開版のmanifest投影/通常取得・再生・本人確認/複数操作、全媒体producer/実機受入を残す。既存formal producer/strict媒体の不足を本metadata/新登録の部分成功で置換しない。入力仕様・Xcode設定と既存P2を保持する。
