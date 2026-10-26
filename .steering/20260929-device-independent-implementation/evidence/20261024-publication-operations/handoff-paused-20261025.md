# レビュー用の中断引継ぎ — 2026-10-25

ユーザーの中断指示を受け、download callback FD固定UnitAを区切りに新規実装を停止した。独立validationは開始していない。次の明示 `$validate-implementation .steering/20260929-device-independent-implementation/` へ渡すための記録であり、全体の完了判定ではない。

現行は **DI-SOURCE-20261025-23、515入力**。[版binding](stages/download-ingress-candidate-01/source-binding.json)のmanifest SHA256は `e7491f7c0d503437f94a207b7caf8be241a75736cc8063e1456c97cad70ac0f5`、App/Unit/UI/project410fileのfingerprintは `ad82f8b3de6577c0e071d5e6e28cf987af079edeef48dcf6a4b98952b3a1808a`。server support97、永続文書6、steering要求/設計2を含む。作業ツリーの全515入力がこの版と一致する。開始時の前回414入力から、367不変・47既存変更・101追加・欠落0を[入力別一覧](checkpoint-input-delta-from-start.json)へ記録した。 [今回だけの実装diff](session-implementation-vs-start.diff)は変更前copyのhashを照合し、開始dirtyの差分を混ぜず148fileを収録した。

## 実装範囲と証拠

各部分の実行版・限界は[一覧](README.md)と各stageのmain確認を参照する。今回、manifest同writer永続化/版ID・可用状態投影、完全local軽量版の単数再生と本人確認、単数/固定複数Photos consumer、既知BG owner停止と通常失効同期、本人の通信操作/固定集合停止、原本upload単数/固定複数のqueued受付、upload metadataのquery予約/HTTP取得結果照合、Photos最終開始のwriter/capture/共有claimと既知owner REC前停止、独立chunk生成とtyped背景接続までを段階別に実装した。

最終のdownload UnitAは、実prepared receiptのload/lookup/loadと同processの実known creationへ結び付け、callback内はHTTP responseの固定項目照合・O_NOFOLLOW open/fstatだけを行う。private URLや数値FDを外へ渡さず、opaque referenceから同FDの64KiB有界read/独立hash・stop/join/実closeへ進む。実SDK unlinkだけを許す専用factsを用い、既存OriginalFileFingerprintは緩めていない。callback再入・遅延pin・終端/停止との競合・close不明を拒否し、失敗closeのunknown handleを空のFD0と扱わない。既存serial event loopはartifactを保持し、後続terminalを待つ処理で自身を塞がない。

## 最終検証

| 実行 | DI23での結果・限界 |
| --- | --- |
| 関連182・16suite | 110宣言中108成功/Native2skip、317展開成功・失敗0。compiler/analyzer/runtime warning0、410入力前後不変。pin/hash/SDK unlink/stop競合は専用合成fixtureのstorageテスト |
| 実Native183 | 新規専用Simulator/nonceで1成功・skip0。download1/suspended/送受信0、偽permitのresume拒否、実cancelled終端→同owner未固定FD0→実session終了。artifact固定0/verified0、transport leaseは保持。実取得成功・正resume・importの証拠にはしない |
| generic iOS184 | CODE_SIGNING_ALLOWED=NOで成功、compiler/analyzer診断0・410入力前後不変 |
| 最終全Unit185 | 940宣言中884成功/56skip・失敗0、1762展開成功（空template1を除く有意味1761）。compiler/analyzer/runtime warning0、410入力前後不変。56skipはNative/HTTP/専用Seed/VERIFY等のopt-inであり成功へ含めない。[結果・全skip一覧](runs/checkpoint-full-unit-185/result.json) |
| 文書 | 永続4文書の安定境界を同期。専門doc_reviewerは指摘0/相対111リンク・欠落0。独立実装validationは未実行 |

Native183の新規root9file/567906bytesを、実行後の前後hashと等しいprivate copyへ保存し、その専用Simulatorだけをデータ保持でshutdownした。[保全・実SDK記録](download-ingress-native-183-preservation.json)。通常UI/最大文字/実Photos/実HTTPの以前の成功は各実行版と影響範囲に限定して継承し、DI23で全UIを再実行したとはしない。実機起動・品質評価は未実施。

## 未適用の後段作業

import BのCore/App両workerは停止済み。12file（既存9/新規3）の途中差分を[hash付き未適用WIP](deferred-download-import-wip-20261025/manifest.json)・ファイルcopy・unapplied.patchへcreate-only保存し、DI23へ戻した。[復帰証明](download-import-wip-freeze-restoration.json)の全515一致を確認。WIPは未コンパイル・未テストで今回の実装/成功件数に含めない。再開時にpatchを無条件適用せず、現コードと契約を照合する。

- B: 実issued read ticketと実HTTP responseを分離して同writerへ記録し、実prepared・現在scope・撮影日・hash・実source close・guarded verified import・transport lease解放/停止を接続する。guarded concrete writer/driver/fenceと回帰テストは未完成。source最終fstatをinitial factsで代用せず、stat不明でも所有FDの実closeを妨げない設計が必要。
- C: [freeze済み直接依存報告](download-full-plan-readiness-contract.json)から再開する。通常downloadの正当なbegin条件/producer、full-read ticket、取得前の固定複数Photos意思が未完成。source/full ticketをread/fullへ流用せず、同temporary ownerを共有する。単調な受信/受付時刻をCalendar撮影日へ代用しない。
- S23/S49のstrict正dispatch/native正resume、S31/S34の通常取得からPhotos/全媒体producer接続は未完了。標準変換資材/正式proof、ISO本人判断、実機・品質条件は、それらへ直接依存する枝の再開条件として保持する。全S28/S31/S34/S49・steering全体・PRD受入は未完了。

## 過去の失敗・skip・保全

[runs](runs/)にcompile失敗・0実行・途中UI失敗・SDK opt-in skipを保持する。とくに本人操作MAX149のContrast1を含む失敗、原本受付通常141のAX3指摘、HTTP155/156の終了時input照合失敗、Photos167の2stackguard crash、chunk178の新fixture2失敗は消していない。後の成功は限定版/限定caseの差分修正後であり、元run全体の成功へ書き換えない。全Unit154は旧DI12でwarning1を含み、現行全Unit185の代わりにしない。注入/mocked条件の成功を正式producerや正の実SDK開始へ昇格しない。

開始時のdirty/HEAD/index/diff、19,251fileのhash、対象source/docs/steeringのcopyと過去414入力はrepo外rawに保全した。[最終scope](scope-paused-final.json)は欠落/所有外変更0、旧証跡/HEAD/index不変。既存P2 Viewはbyte不変、LibraryFlowTestsは既記録の診断4行だけの追加で旧assert/監査条件を保持する。

[最終保全照合](protection-checkpoint-23-summary.json)（22:59 UTCのsnapshot）では旧1456保護file中1448一致・8差分、旧28台state/17container・歴史5fixture・原本/媒体を保持。8差分は[追補08](protection-followup-08/summary.json)とbyte完全一致で、Keychain本体/WAL/SHM3、Photos WAL/SHM2、Photos管理appPrivateData.plist3を含む。private copy比較ではKeychain genp43行の同rowid3行暗号列相違/13旧不在13新とsequence1行、PhotosはZGLOBALKEYVALUE1行の日時/counter以外の99表/schema一致。Keychainのサービス・原因・製品影響、plistの意味は未解明であり、全Keychain保全成功とは報告しない。原DBへのSQLite接続、既存fixture修復/再seed、原本/Photos削除、旧process停止・データ復元は行っていない。

raw root: `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-implementation-20261024-l0p333tn/`。raw DB・媒体・資格情報はrepoへ載せず、各種失敗log/xcresult/DerivedData/private copyをここに保持する。専用Simulatorはすべてデータ保持のShutdown状態で、旧起動中CFだけを保持した。最終Unit用8Dへのshutdown要求は既にShutdownでSimError405となり、再boot/再試行/eraseせず状態を確認した。[状態記録](checkpoint-owned-simulator-shutdown.json)。新規実装・独立validationは次の明示呼出しまで開始しない。

[終了時の固定版/未適用WIP/hash/link/diff照合](paused-final-checks.json)は全515入力一致・WIP12file一致・欠落リンク0・diff check成功。最終scopeも開始file欠落/所有外変更0、旧証跡/HEAD/index不変である。
