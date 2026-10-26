# 独立検証の2指摘修正 — 2026-10-26

明示 implement-steering による PHOTO-QUEUED-RETENTION-UI-01(P2) / DOC-METADATA-STATUS-01(P3) だけの限定修正。独立 validate-implementation は開始していない。

- P2: LibraryPhotoSaveCommands.swift:74のqueued表示を、一時媒体回収の可能性と再準備不可時の未処理へ訂正。design.md:90 / development-guidelines.md:75をintent前REC停止・intent後live使用権の区別に整合。保持policy・回収条件・再取得・自動再追加の変更はない。
- P3: functional-design.md:326 / architecture.md:381 / development-guidelines.md:106 / repository-structure.md:108,203をDI14 metadata限定実装・検証記録、DI18 Photos最終開始境界の限定接続へ同期。実行版別の成否・継承条件はtasklistと各stageを正本とし、過去の失敗・skipは保持。

[最終版binding](source-binding.json)の515入力（508不変/7変更/追加欠落0）と[今回だけの差分](session-changes.diff)を開始copyから束縛する。既存dirtyを含むDI23の515入力は開始時全一致であり、HEADへ戻す操作やWIP適用はしていない。最終のscope判定は[scope-audit.json](scope-audit.json)。

[P2実行版01](p2-source-binding.json)の不変copy、新規専用Simulatorで関連4suiteを実行し、[29宣言/42展開成功、失敗0/skip0](photo-regression-01-summary.json)。[command/cwd/入力hash](photo-regression-01-command.json)、[実test tree](photo-regression-01-tests.json)、[build診断](photo-regression-01-build.json)を保持。最終版02との差はP3文書だけで、410コード入力は全一致の限定継承。compiler/analyzer/runtime warning0。AppIntents依存なしmetadata抽出skipのtool警告3行と、初回sandbox/報告抽出の照会失敗は[verification.json](verification.json)へ分離した。

回帰は、新規合成rootのintent前prepare→REC停止join/release→実cache回収後もqueued→明示continueで同child unavailableと表示を確認。Photos全呼出0・reader0・合成sourceコピー保持を確認し、実原本/実Photos結果の証拠にはしない。受理SDK待機・外部unknown/localunknown・STOP/leave等も既存suiteで確認した。

[文書専門レビュー](p3-document-review.json)は指摘なし、[相対リンク123件](document-links.json)欠落0。[保全](preservation.json)は開始→終了の既知3295path byte差分0、旧state変化0。過去の既知8差分と原因/影響未解明を維持し、開始前からのDI23 checkpoint差分17件も別記する。全保全成功としない。WIP12はcopy/hashと既存9のbase hash/新規3不存在で未適用を照合する。

成功・失敗・skip・未実行の詳細はverification.json。今回は全Unit/全UI/実PhotoKit/HTTP/native transport/実機品質を再実行していない。独立validation、import B/C、通常strict正dispatch/native正resume、全媒体producer、全steering、実機・品質・PRD受入は未完了。Native183を実取得/import成功へ拡張しない。旧原本/Photos削除・fixture修復/reseed・原DB SQLite接続・復元は行っていない。

raw root: /private/tmp/fr-finding-fixes-20261026-ia9hki7h/ 。xcresult/DerivedData/515入力の前後snapshotと開始35,665file hashはrepo外へ保持する。専用Simulator停止要求は拒否で未実行・再試行なし。終了時の読み取り一覧では専用機はShutdown、旧CFはBootedで、データ消去はない。
