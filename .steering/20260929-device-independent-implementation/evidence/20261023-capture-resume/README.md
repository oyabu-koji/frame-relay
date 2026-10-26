# S49 媒体再開の単回同期許可（2026-10-23）

共通CaptureMediaAdmissionの同じNSLockで、発行元・revision・idle・未消費をSDK action直前に照合する単回許可を追加した。coordinatorから必須port引数として渡し、発行後のhold、begin→endのABA、別origin、再利用を拒否する。同期actionの前に消費し、throwでも再利用しない。lock内にawait・再dispatch・同admissionへの再入を置かない。通常native adapterは引き続き`notExecuted`であり、正のSDK resumeは追加していない。

| 検証 | 結果 |
| --- | --- |
| 関連単体・競合 | `capture-resume-unit-20` 28宣言44展開成功。3phase・複数hold・ABA・別origin・alias・throw・実2Threadのlock順序と、SDK実行側で待たせた遅延hold/解除後拒否を確認 |
| 実背景SDK | `capture-resume-sdk-21` 3成功、skip0。idle/hold両方で偽strict permitを拒否し、一度もresumeしない実suspended taskの列挙、cancel callback/invalidation、自身sourceの終端を確認 |
| 全Unit | `final-unit-all-22` 609宣言中578成功/31条件付きskip。964展開成功、空template1件を除く有意味963。失敗0 |
| 通常画面回帰 | `final-ui-regression-24` 一覧/再生/撮影/写真権限6件中5成功/1失敗。cleanup接続後の条件文に対する旧期待値だけを厳密一致へ更新し、`final-library-ui-25`で該当1件成功。他のdisabled/選択/保持/P2再生・AX・stopのassertionは不変。24の失敗・旧sourceを保持 |
| UI後実disk | 新規回帰rootの`final-regression-post-26` 2成功/seed1skip、整理済みrootの`final-cleanup-post-27` 1成功/seed1skip。再seed/修復/再削除なし、全logical/media reader空、manifest・原本・外部sentinelを照合 |
| build | `final-ios-build-28` generic iOS/Debug/CODE_SIGNING_ALLOWED=NO成功 |

上記の必要runは各294入力が実行前後一致し、compiler/analyzer診断・xcresult runtimeWarnings 0。初回18はactor witness隔離のcompile失敗/0実行。19の試験Thread由来QoS警告3件は、起動前に待機側と同じuserInitiatedへ揃えて20で解消した。診断機構・競合・timeout/assertionを緩めていない。失敗版・警告・rawログを[runs](runs/)に保持する。

[実行版照合](execution-binding.json)と[395入力binding](source-binding.json)、[source現物](source-snapshot/)、[tracked差分](tracked-source.diff)を保存した。22までの全Unit/SDK結果は最終版とApp/Unit/projectが同一で、差は25のUI期待値1箇所だけ。25〜28は294入力すべて最終版と一致する。旧H01の389入力と票は履歴として保持し、実機実行時はQ01でcaseごとに再束縛する。

[原本照合](final-fixture-preservation.json)では回帰原本485,721bytesと整理後の保持2本・外部sentinelのSHA-256、両immutable manifestのbytesが不変。両専用Simulatorの文字sizeはlarge。実PhotoKit許可/拒否は[S31証跡](../20261023-photo-release-owner/README.md)、複数整理の通常/最大文字UIは[S34証跡](../20261023-cleanup-composition/README.md)を参照する。

mainがApp4/既存test3/新test2とUI期待値1箇所の全差分を確認した。永続4文書の限定同期は[doc_reviewer指摘なし](documentation-review.json)。FrameRelay.xcodeproj/scheme/test plan、Debug、Xcode27.0(27A266a)/Swift compiler6.4、Swift5/iOS27.0を維持。raw xcresult/DerivedData/開始copyは `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-implementation-20261023-_coslmwo/` に保持する。

契約・配線の部分引渡しのみ。通常strict dispatchとnative正開始、全媒体producerの実停止、実通信中REC、全S49・各段階・実機・品質・PRD受入は未完了。注入した正のactionやsuspended cancelを正の製品通信・全媒体停止へ拡張しない。独立validationは開始していない。
