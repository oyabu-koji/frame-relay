# BG既知upload終端から通常失効同期への接続部分

DI-SOURCE-20261024-04、453入力（code348）。実失効予約・store UUID・現在の媒体照合epochに束縛し、既知live uploadだけ停止要求、後の明示同期で実終端・自身FD・lease・全履歴を照合してACKへ渡す。閉鎖確定の旧履歴は観測し、未閉鎖旧sourceを採用しない。原本readerのowner epochとstoreの媒体epochを混同しない。

[main確認](main-review.json)、[実行束縛](execution-binding.json)、[入力](source-binding.json)を参照。関連188展開、実SDK非送信1件、全Unit725宣言680成功/45skip・有意味1184展開、generic iOS buildが成功。全code348前後一致、compiler/analyzer/xcresult runtimeWarnings0。106〜108の失敗は保持。

実SDKprobeのcancelは、native.resume拒否後の既存stop経路から発行された。新しい失効stopのSDK発行分岐自体はUnitで検証し、正式active upload・正のURLSession媒体resume・全媒体停止の成立へ拡張しない。注入permit/metadata・Mac notExecutedはtechnical入力。自身FDだけを確認しSDK全FDは主張しない。

新64ADの別UUID tmp rootを一回だけ使用し、原本/外部sentinel/コピー・再openを照合、112後も11file保持。default P2 fixtureはhash/inode保持・large復元。旧fixtureの保全は[時点付き追補04](../../protection-followup-04/summary.json)に従い、Keychainの既知補助差分を不変成功へ置き換えない。全S23/S27/S28/S31/S34/S49・steering・実機/品質/PRDは未完了。独立validation未開始。
