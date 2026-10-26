# 2026-10-24 残実装・進捗と証跡

ユーザー指示によりレビュー用の区切りで中断する。現行は **DI-SOURCE-20261025-23 / 515入力**。[中断引継ぎ](handoff-paused-20261025.md)と[入力差分](checkpoint-input-delta-from-start.json)を参照。独立validationは開始していない。全steering・実機・品質・PRD受入は未完了。進捗の正本は[tasklist](../../tasklist.md)。

| 部分 | 入力版 | 状態・証跡 |
| --- | --- | --- |
| S28 manifest永続化・一覧投影 | DI-SOURCE-20261024-01 / 421 | [限定部分の結了](stages/manifest/README.md) |
| S28 完全local軽量版の単数実再生・本人確認 | DI-SOURCE-20261024-02 / 433 | [main確認](stages/local-rendition/main-review.json)、[実行束縛](stages/local-rendition/execution-binding.json) |
| S31/S34 完全local軽量版の単数・固定複数Photos consumer | DI-SOURCE-20261024-03 / 449 | [限定部分の結了](stages/photo-batch/README.md) |
| BG既知owner停止→通常失効同期 | DI-SOURCE-20261024-04 / 453 | [限定部分の結了](stages/background-invalidation/README.md) |
| 本人の通信操作・固定全件停止 | DI-SOURCE-20261025-01/08 / 463、読取19 / 500 | [main限定確認](stages/request-control-render-candidate-01/README.md)。通常128/実writer129とMAX149機能全到達、149 FAIL/Contrast1保持。現行172/173は各2監査issue0・業務tap0、174/175実writerは各6親10子/全reader0/原本・file・再open一致 |
| 原本uploadの単数・固定複数queued受付 | DI-SOURCE-20261025-03/05/06 / 477 | [main最終確認](original-upload-main-review-final-01.json)。全Unit136/build145・MAX全flow146（16厳格監査/issue0）とwriter153（2親4子/現在要求2）成功。通常141のAX3指摘失敗と修正後読み取り144の5監査成功を分離して保持。実送信・正式producer未完 |
| upload metadataのquery予約・取得結果照合 | DI-SOURCE-20261025-11 / 492、Seed/UI追加14 / 494 | 関連151は95宣言93成功/HTTP2skip・208展開、build152は診断0。全Unit154は835宣言782成功53skip/1431展開、UI未使用変数warning1は派生13/14で修正。[実HTTP159/160](http-metadata-002/main-review.json)の1+4case・実POST1/GET2・媒体0・全終端/入力一致/実process exit0。155/156のlistener終了時input照合失敗は保持。専用Seed161/158各1成功、通常162は全flow/27厳格監査issue0、writer164はquery1/obs0/本人2親2子・全媒体/資格情報/reader0・再open一致。最大163も全flow/27厳格監査issue0、writer176成功。詳細は[限定部分](stages/upload-metadata-ui-candidate-03/README.md)。[文書review02](upload-metadata-doc-review-02.json)指摘0/93リンク |
| Photos最終SDK開始の同writer/capture/共有claimと既知owner REC前停止 | DI-SOURCE-20261025-18 / 500 | [限定部分の確認](stages/photo-final-candidate-02/README.md)。関連169は47宣言45成功/Native2skip・110展開、実Native170は1成功・既存6assets保持/別新操作1追加/ownFD-reader0/再open、generic171成功/診断0。167の2stackguard crashを保持。全媒体/strict/正式producer/実機品質は未完 |
| 原本chunk独立生成・typed背景接続 | DI-SOURCE-20261025-20/21/22 / 503→509 | [限定部分](stages/upload-chunk-candidate-02/README.md)。177は32宣言69展開成功、178のfixture2失敗を保持し181両store全80成功、Native179は実suspended/cancel/ownFD-lease-stopped1成功・root保持、180build成功/診断0。strict正resume/実HTTPchunk/whole完了未成立 |
| download callback FD固定・同FD有界処理・局所close | DI-SOURCE-20261025-23 / 515 | [限定部分](stages/download-ingress-candidate-01/README.md)。関連182は108宣言/317展開成功・Native2skip、実Native183は1成功/未resume・artifact0/verified0/lease未解放、generic184成功、いずれも診断0。最終全Unit185は940宣言884成功/56skip・失敗0、1762展開（有意味1761）成功/診断0。B未検証12fileは[未適用WIP](deferred-download-import-wip-20261025/manifest.json)として別保全 |

metadata MAX163/176・本人操作172〜175・chunk177〜181は上表の限定範囲で結了。download UnitAをDI23へfreezeし、後段import Bのwriterを停止した。B12fileのhash付きcreate-only archiveを確認後、9既存fileをDI23へ戻し、新規3fileだけを作業ツリーから除いた。[復帰照合](download-import-wip-freeze-restoration.json)は515入力/410コード全一致。唯一の書込みtaskはなく、mainによる最終検証と引継ぎだけを行う。通常strict/native正開始、取得後import、全媒体producer、正式資材/ISO/実機/品質の残件は中断引継ぎへ分離した。

開始時dirty/HEAD/indexと19,251fileの現物hash・414入力との一致をrepo外のraw rootへ保存した。既存fixtureの修復/reseed/原本やPhotos削除は行わず、削除試験は新規専用合成rootだけ。[保全追補04](protection-followup-04/summary.json)では旧1456file中1452一致、旧28state/17container/歴史5fixtureを保持。旧起動中CFのKeychain/Photos WAL/SHM4補助fileは差分を分離している。両main DBは開始時byte一致だが、Keychainは以前に暗号化1行の変更を観測しservice/原因未確定で、全byte保全成功とはしない。原DBへのSQLite接続・修復・復元・killはしない。私有DB copyはrepo外のみ。

最新の[保全追補05](protection-followup-05/summary.json)（2026-10-24 17:05 UTC）では旧1456file中1451一致、Keychain本体/WAL/SHMとPhotos WAL/SHMの5差分となった。旧28state/17container/歴史5fixtureは一致。私有copyだけの比較でKeychainは28表中genpとsqlite_sequence、Photosは100表中ZGLOBALKEYVALUEの日時/カウンタだけが相違しassetを含む99表は一致した。genpは43行のまま、同rowidの1行でmdat/data/sha1相違、別に10旧rowid不在/10新rowidを検出した。サービス・原因・製品範囲は未確定で、以前の「Keychain本体byte一致」を現在へ継承しない。秘密値は出力せず、原DBへの接続・修復・復元・旧process停止は行っていない。

最新の[保全追補06](protection-followup-06/summary.json)（2026-10-24 19:00 UTC）も旧1456file中1451一致。旧28state/17container/歴史5fixtureを保持し、Keychain28表中genp/sqlite_sequence、Photos100表中ZGLOBALKEYVALUEだけの相違を私有copyで確認した。genpは43行のまま同rowid3行の暗号化mdat/data/sha1相違と11旧rowid不在/11新rowidへ変化しており、05の狭い件数は継承しない。サービス・原因・製品範囲は不明、asset等Photos99表は一致。原DB接続・修復・復元・旧process停止は行わない。

元失敗・skip・0実行は[runs](runs/)とdiagnosticsに保持。mock/注入の成功を正式producer・正の実SDK開始・全媒体停止の成立へ拡張しない。raw root: `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-implementation-20261024-l0p333tn/`。

[保全追補07](protection-followup-07/summary.json)（20:32 UTCのbyte snapshot）は旧1456file中1448一致・8差分。従来Keychain3/Photos補助2に旧CFのPhotos管理appPrivateData.plist3件が加わり、baseline内容copyがないためtimestampだけの変更とは断定しない。私有DB copyではgenp43行・同rowid3行の暗号化列相違/13旧rowid不在・13新rowid、sqlite_sequenceの1行、Photos main100表中ZGLOBALKEYVALUE1行のみ相違。旧28state/17container/歴史5fixture・原本/媒体は保持。原因・サービス・製品範囲は未確定、原DBへの接続/修復/復元・旧process停止なし。

最新の[チェックポイント保全照合](protection-checkpoint-23-summary.json)（22:59 UTC）は旧1456file中1448一致・8差分で、保護対象全hashが[追補08](protection-followup-08/summary.json)と一致。旧28state/17container・歴史5fixture・原本/媒体を保持。Keychain3file/Photos補助2file/Photos管理plist3fileの既知差分と未解明範囲は解消していない。[最終scope照合](scope-paused-final.json)は欠落/所有外変更0、HEAD/index/旧証跡不変。P2 Viewは不変、旧LibraryFlowTestsの差は既記録の診断4行のみ。
