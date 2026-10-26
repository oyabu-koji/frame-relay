# P2修正・再検証（2026-10-22）

独立検証 `/private/tmp/fr-validation-20261022-lh_5wn0r/validation-summary.json` の厳格AX4失敗とfresh Library fixture作成失敗を修正した。S14/S16は既存Done/Verifyに対応する非実機検証を完了。他task・段階・全steering、実機・品質・PRD受入へ完了判定を広げない。独立validationは未開始。

## 原因と修正範囲

- **LibraryView.swift**: SwiftUI Textの動的再配置で、実描画とAX文字領域・寸法の整合が崩れる条件を再現。rootのVStack化は無効だった。状態・履歴・操作結果の12箇所を、実提案幅・無制限高で計測するnative複数行UILabelへ変更した。semantic body/headline、全12文字サイズ、全文、元ID、結合読み上げ、scroll/nav配置を保持。詳細Contrastは同じnavbar付近の位置・完全なAX文字を維持して成功し、可視文字の配色不良やSDK誤検知とは断定していない。
- **ProductLibrarySeedTests.swift**: 非legacy cleanupへの`.reserveRemoval`と実検査unknownのMOVが現行cleanup契約に合っていなかった。既存test-only fixtureでcleanupにだけ明示合成saved/検証/確認・非開始reader事実と`.reserveCleanup`を与え、製品guard・discard契約・実再生原本のunknownを維持した。通常Unitでも隔離tmp rootの同じ作成経路・再open・投影・内容/全readerを検査する。App root seedは明示opt-inのまま、無関係な非empty rootや部分seedを修復しない。
- **LibraryFlowTests.swift**: 選択後もtap前snapshotを参照した失敗は、同IDのfresh親/実childの値を既存5秒内・両String1で照合するよう修正。最大文字では部分可視の結合親がhit=falseでも同linkの可視titleはtrueだったため、通常は従来親、必要時だけ同じ親配下の実文字を通常tapし、期待する詳細identityへ到達する。35回/同swipe/未達失敗を保持した。
- **4文書/tasklist**: 旧AX失敗を履歴とし、現行結果と通常Unitのfixture作成回帰を限定同期。document_author/doc_reviewerが4文書5箇所を担当し、指摘なし、ローカルリンク55件の欠落0。

監査mask・全issueを未処理にするfalse handler・診断・共通reveal/topは開始版と同一。[監査不変確認](audit-preservation-final-02.json)を参照。ignore、handler受理、対象除外、文字サイズ制限は行っていない。`audit-preservation-final-01.json`は最大文字helper追加前の履歴であり、最終確認は02。

## 構成と結果

実在するFrameRelay.xcodeproj、FrameRelay scheme、自動Test plan、Debug、有効なFrameRelayTests/FrameRelayUITestsを再確認した。Xcode27.0(27A266a)、Swift6.4 compiler/言語5.0、最低iOS27.0を維持。iPhone18Pro/iOS27.0の専用新規Simulator 2台を使用した。[構成](configuration-summary.json)、[実コマンド/全run](run-index.json)を参照。

| 確認 | run | 結果 |
| --- | --- | --- |
| 新規App rootでの初回fixture生成 | fresh-seed-01 / fresh-seed-final-01 | 各2成功・verify1skip、失敗0。CFコピーなし |
| 最終通常UI・厳格AX | ui-final-04 | 17成功/失敗0/skip0。厳格6件（既知4件を含む）、unhandled issue0 |
| 未登録環境の初回接続 | initial-connection-final-01 | 1成功/skip0。登録合成Libraryと前提を分離 |
| 別fresh seedでの既知4監査 | fresh-strict-final-01 | 4成功/失敗0/skip0、issue0 |
| 最大AX5の全文・通常操作・実VO | max-visible-title-01 + ui-max-final-02 | 計4成功/失敗0/skip0。終了時にも最大を再取得しlargeへ復元 |
| 全Unit | unit-final-01 | 590宣言中562成功/28skip、915展開成功（空template1を除く有意味914）、失敗0 |
| 最終UI後の原本照合 | post-ui-final-01 | identity照合＋隔離root回帰2成功/seed1skip、失敗0。secondaryも全Unit内の照合成功 |
| generic iOS署名なしbuild | ios-build-final-04 | 成功、compiler/analyzer error/warning 0 |

旧18件と同じcase集合を、登録合成Libraryの17件と別新規未登録環境の1件で照合し、14成功/4失敗から18成功/skip0へ改善した。[18件比較](ui-18-comparison-final-01.json)、[既知4件比較](known-four-comparison.json)を参照。fresh strict4・最大4は別の反復確認であり18件へ加算しない。metadata登録専用UIは今回の18件に含めない。

最大文字では履歴/操作結果7要素の全文と実寸の伸長を確認。参照fontは17→53pt、titleは21→126pt、removalは21→188pt、phaseは43→374pt。[実画像/AX/文字計測比較](text-size-comparison-final-01.json)を主にし、reference計測だけでclippingを判断していない。実VoiceOverはhistory removal/original absence、submission title/action/phaseの既存5条件を確認した。取得した出力文字の観測であり聴取品質評価ではない。

全Unitの有意味914は、以前の912に通常新規fixture回帰1と明示post-UI VERIFY1を加えたもの。seedはskipのまま。Unitの成功数に空template/skipを含めない。[集計](unit-final-01-metrics.json)、[skip一覧](unit-skip-index-final-01.json)を参照。最終runのxcresult runtimeWarningsは空、stdout/OS環境出力もrawに保持する。

## 版・途中結果・保全

[389入力manifest](source-manifest.json)と`source-snapshot/`に最終bytesを保存した。旧H01-SOURCE-01から7変更/382不変で、旧bindingを上書きしていない。[実行版の束縛](source-binding-final-01.json)を参照。最終通常UI/最大4/build/post-UIは288入力が前後不変。全Unit・fresh seed・初回接続後の差は非UnitのLibraryFlowTestsのみであり、App/Unit実行バイナリの完全一致を[test-products-final-02.json](test-products-final-02.json)で照合した。この一致を他媒体・通信runへ拡大しない。

全失敗・途中結果を[run-index](run-index.json)へ分類した。freshで既知4件を再現したbaseline、無効なeager比較、native子ID不足の途中4成功、UI取消、0件selector、選択観測1失敗、最大文字setup4失敗とfresh親比較1失敗を保持し、最終合格へ置き換えていない。初期287入力ではworkspaceが未収録であり、最終288入力と区別する。各runの実行前後差分、最終版との差分、skip/取消/実行0件は個別JSONを参照する。

今回raw rootは `/private/tmp/fr-p2-implement-20261022-8hp33bnm/`。全xcresult/log/実行source/全attachments/録画/初期baselineを保持。[raw索引](raw-artifacts.json)に位置とhash/metadataを記録した。repo内`observations/`は選択した観測のコピーであり、各manifestの全添付はrawの対応するattachmentsディレクトリにある。

今回開始15,858file/340,070,485bytes、既存dirty/untracked・HEAD/status/diff/staged差分を保全。既存変更は3コード・4文書・tasklistの8fileだけ、新規はこの証跡配下のみ。欠落0、CF保護15file不変、既存project/製品guard不変。以前の独立検証rawと `/private/tmp/fr-implement-20261021-j6xbqszu/` はファイル数/bytes/metadata digest一致で保全した。[保全照合](final-preservation.json)、[主担当レビュー](main-review-final-01.json)、[文書レビュー](doc-review-final-01.json)を参照。

使用した572096FA-13EC-4FAD-B14C-FE0DBF919FC0と070E0EC1-1A62-410E-BDD7-F0D80E500B6Cはデータ保持でshutdown済み。既存Simulatorの状態は開始時と同一で、独立検証の14EE25EC-8B59-4CF8-93A3-8B901E78FC5CとDDD99DE3-20A7-4A18-B766-F9ECE5EB8F97も未変更。両新規rootのmanifest・原本digest/485721bytes・映像音声各30秒は不変、post-UIではlogical readersとmediaReadersが全て空。[fixture照合](fixture-files-final-01.json)を参照。物理container移動をidentity同一と混同しない。

## 残件と次工程

S23/S27/S28/S34/S49の部分実装/blocked、他task・段階の状態を維持。S32/S33/S26A/M02〜M06/H01の既存done範囲も拡大せず、H01は引渡し準備だけ。限定SDK・metadata HTTP・279入力の公開HTTP・登録metadata専用UIは今回再実行していない。SDK permit/Mac観測注入を通常strict開始/resume・全媒体完成の証明にしない。実機、聴取/画質等の品質、縦横全状態、PRD受入は未実施、79ACのD/Rは変更していない。

次は同じsteeringへの独立した `$validate-implementation .steering/20260929-device-independent-implementation/`。本作業では別Workflowを開始していない。
