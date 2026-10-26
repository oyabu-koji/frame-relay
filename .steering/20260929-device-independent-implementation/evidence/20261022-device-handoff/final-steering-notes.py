from pathlib import Path
import json,re,difflib,hashlib
r=Path(__file__).parent
p=Path('.steering/20260929-device-independent-implementation/tasklist.md')
s=p.read_text();before=s
binding=json.loads((p.parent/'evidence/20261022-device-handoff/source-binding.json').read_text())
proof=json.loads((r/'h01-candidate-static-01.json').read_text())
assert len(binding['files'])==389 and proof['mother_rows']==76 and proof['bound_source_changed']==[]
assert all('| M%02d／done |'%n in s for n in range(2,7))
for rel,row in binding['files'].items():assert hashlib.sha256(Path(rel).read_bytes()).hexdigest()==row['sha256'],rel
assert (p.parent/'evidence/20261022-implementation-final/final-preservation-01.json').is_file()
a=s.index('### H01 実機引渡し票');b=s.index('### Q01 ',a);part=s[a:b]
assert '- [ ] Status: in-progress' in part
part=part.replace('- [ ] Status: in-progress','- [x] Status: done',1)
part=part.replace('  - Depends:', '  - 準備完了（2026-10-22）: 全18票を76母行へ展開し、全79AC/CF11/BI34/DI18と旧C01〜19/B1〜7/U01〜05/V01〜16を双方向対応した。6旧親行・79行順序と非IAR列を保持、35行のI/A/Rだけを具体化、全D0/全A01〜18 pending・PRD受入未評価を維持。76は実行件数ではなく、全パラメータ/実組合せ/有限反復/品質・対象別許可はQ01で束縛する。\n  - 版・検証: [H01-SOURCE-01](evidence/20261022-device-handoff/source-binding.json)へHEAD/dirty差分hashと全389入力（App/Unit/UI/project288、support93、永続6文書、requirements/design2）の現物snapshotを固定。層別実行証拠は現288/旧publication279/旧strict260を分離。main/読み取り調査に指摘なし、[準備版静的照合](evidence/20261022-device-handoff/h01-candidate-static-01.json)で欠落ID/重複/ローカルリンク切れ/source差分0・diff-check成功。実装/実機/製品受入の完了ではなく、引渡し準備だけdone。\n  - Depends:',1)
s=s[:a]+part+s[b:]
# Add concise indexes without replacing each task's detailed, versioned run history.
def line(cells):
 assert len(cells)==7
 return '| '+' | '.join(str(v).replace('|','&#124;') for v in cells)+' |\n'
records=[
['E-S14-P2-20261022','2026-10-21〜22、worker/main','S14/S16・Library AX','strict最終260入力、現LibraryView同hash','strict監査/実文字/VoiceOver/CF保全','strict14成功/4失敗、通常・最大AX5文字確認は成功','evidence/20261021-library-accessibility/ と evidence/20261022-removal-composition/。P2未解消、現288全strict再実行ではない'],
['E-S32-03','2026-10-21、worker/main','S32・原本実削除','253入力、両store/実MOV','固定batch/同FD全hash/最終guard/unlink/中断/再open','Unit685展開成功(有意味684)/21skip、iOS build成功、診断0','evidence/20261021-removal-core/。core done、製品整理UI/実機は別'],
['E-S33-01','2026-10-21、worker/main','S33・単数risk破棄','255入力、S32実機構','本人risk/目的分離/実unlink/外部保持/不明照合','Unit706展開成功(有意味705)/21skip、Simulator build成功、診断0','evidence/20261021-discard-core/。core done、UIはS34へ'],
['E-S34-01','2026-10-22、worker/main','S34単数UI・結果/履歴','260入力、専用合成seed','通常確認UI→実unlink→再open/履歴/保持対象照合','Unit726展開/23skip、専用UI1/実disk照合1成功、seed1skip','evidence/20261022-removal-composition/。全S34/通常整理/Photos/複数UI未完'],
['E-S23-01','2026-10-22、workers/main','S23背景資源基盤','275入力、schema7/同writer','session/task/context/event drain/管理source copy・自身FD終端','Unit816展開(有意味815)/25skip、実SDK2/UI3/build/CF照合成功、診断0','evidence/20261022-background-media/。strict開始/resume/download受入口/旧source採用・全媒体は未成立'],
['E-S49-01','2026-10-22、worker/main','S49 REC/保存hold','279入力、candidate03','owner別wait/preflight/実file return/通知両順序/次REC','Unit841展開(有意味840)/25skip、通常UI3/build/CF照合成功、診断0','evidence/20261022-capture-media/。最終SDK resume排他/全媒体実停止/実網RECは未成立'],
['E-S27-01','2026-10-22、workers/main','S27公開/確認/失効の技術結合','backend273・iOS279、凍結checkpoint','隔離pytest/実HTTP/AVPlayer/確認commit-exact lookup/解放/ACK後V2公開','170node230case・実HTTP1成功/skip0、全12観測と実process/FD/thread終端','evidence/20261022-publication/。正式proof/全製品owner/通常UI/品質未成立、旧失敗保持'],
['E-S26A-01','2026-10-22、main','S26A資材事実/比較案','design D02/一次資料','Log1/Log2入力差/標準資材不足/技術適合とG3比較を記録','資料・diff/hash/リンク確認、資材取得・変換・品質試験は未実施','evidence/20261022-transform-research/。資材実体/由来・版/hash/利用条件/数値域/既知入出力待ち'],
['E-S28-01','2026-10-22、worker/main','S28既存登録の明示metadata同期','285入力、同writer/専用Status Simulator','1page/続き/失効cursor分離/旧mutation-outbox/登録store/動画別表示','Unit868展開(有意味867)/28skip、UI1/reopen1/build/実metadataHTTP1成功(2要求/媒体0)','evidence/20261022-status-sync/。全再登録/全媒体/全S28未達、最終共有版はE-S34-BG01'],
['E-S34-BG01','2026-10-22、workers/main','S34歴史的確定upload終端後の単数破棄・最終回帰','288入力candidate02、全run前後一致','全receipt/inventory・同writer最終照合/実SDK終端→ownFD-close→lease/stopped→通常risk/unlink/reopen','Unit913展開(有意味912)/29skip、実SDK1/metadataHTTP1/UI7/reopen1/build成功、CF1/seed1skip、診断0','evidence/20261022-removal-terminal/。permit/Macは注入、SDK全FD/通常strict/全媒体/正式proof等へ昇格しない'],
['E-H01-01','2026-10-22、main/読み取り調査','H01・18票/全79AC','H01-SOURCE-01/389入力','全76母行/35軸更新/6旧親行保持/層別実行版を照合','準備版静的検証成功、実機未実施/全D0/受入未評価','evidence/20261022-device-handoff/。実機実値/品質/許可/全組合せと反復はQ01未束縛']]
for x in records:assert '| '+x[0]+' |' not in s
at=s.index('本体検証ではproject/workspace');s=s[:at].rstrip('\n')+'\n'+''.join(line(x) for x in records)+'\n'+s[at:]
reviews=[
'| V-REVIEW-20261022-CODE | E-S32/S33/S34/S23/S49/S27/S28、最終288入力 | main | 各taskの全差分/所有と修正差分を確認、全run source一致、旧失敗・P2 strict4・未接続を保持 | 各task main-reviewとH01-SOURCE-01のexecution_binding。独立validationではない |\n',
'| V-REVIEW-20261022-DOCS | M02〜M06の最終5文書 | main/document_author/doc_reviewer | 1fileずつ同期・他文書/source保全、PRD79対応/旧制約保持、M05のP3主語を修正して全最終指摘なし | evidence/20261022-stable-docs/。文書のみ追加build/testなし |\n',
'| V-REVIEW-H01 | 全76母行/35軸/389入力source binding | main/読み取り調査 | 旧枝条件/直接依存/未接続と未実機・層別証拠を照合、指摘なし | evidence/20261022-device-handoff/。準備のみdone、A01〜18/Q01/製品受入は未完 |\n']
at=s.index('## 振り返り・引渡し');s=s[:at].rstrip('\n')+'\n'+''.join(reviews)+'\n'+s[at:]
# Current restart notes reflect the completed authorized unit; historical sections remain.
for heading,replacement in [
('所有','mainがsteering・証跡・最終差分を統合した。全App/Tests/project/support helper・永続文書は最終版を凍結して所有解除。コードの実行版は288入力、docs等を含む引渡し版はH01-SOURCE-01の389入力。旧証拠・既存dirty/untracked・入力仕様・project設定を保護した。'),
('進行中','S32/S33とS26A、M02〜M06同期、H01引渡し準備はdone。S23/S27/S28/S34/S49は必要検証付きの部分引渡し、全taskはstrict通信/資材/全媒体/製品操作等の不足をblockedに保持。S2V/S4Vも部分集約済みblocked。独立してreadyな追加コードはなく、P2/S14の厳格監査4失敗とS16/S1Vは未達。次は同pathの明示 $validate-implementation、実機はcase別Q01束縛から進める。')]:
 pattern=r'^- \*\*'+re.escape(heading)+r'\*\*: [^\n]+$'
 assert re.search(pattern,s,re.M);s=re.sub(pattern,'- **'+('今回の結果' if heading=='進行中' else heading)+'**: '+replacement,s,count=1,flags=re.M)
s=s.replace('まずS14のV-UIを再開し、必要な修正・関連検証を1件ずつ同期してから次の独立taskへ進む。','S14のV-UIを再開し、必要な修正・関連検証と直接依存の揃う独立taskを順に実行した。',1)
s=s.replace('人物なしAF／初回意図／ISO基準等','ISO基準・既承認暫定値の実機採用等',1)
s=s.replace('今回は本steeringに従いコードとM01〜M06の永続文書を更新する。','今回は本steeringに従いコードとM02〜M06の永続文書を同期し、M01のPRD79条件を保持した。',1)
s=s.replace('実装は今回の明示 `$implement-steering .steering/20260929-device-independent-implementation/` で進行中。実装後の独立検証は同じpathを明示する `$validate-implementation` を別途案内し、自動開始しない。','今回の明示 `$implement-steering .steering/20260929-device-independent-implementation/` で直接readyな範囲の実装/関連検証/文書同期/引渡し準備を終えた。全steering・実機・PRD受入は未完。次の独立検証は同pathを明示する `$validate-implementation` とし、自動開始しない。',1)
s+='\n- 実装単位: 操作に必要な下位I/O・同writer永続化・製品接続/画面・再open照合・関連検証を一つの引渡しにまとめ、書込みtask/所有は1件ずつ管理した。\n- 最終保全: [開始時8,910file照合](evidence/20261022-implementation-final/final-preservation-01.json) と [source/所有照合](evidence/20261022-implementation-final/final-source-scope-01.json)。既存CF原本digest/reader0・設定67bytesを保持し、今回作成した2 Simulatorだけshutdownしてdataを保持した。\n'
(r/'h01-final-notes-before-02.md').write_text(before)
(r/'h01-final-notes-diff-02.diff').write_text(''.join(difflib.unified_diff(before.splitlines(True),s.splitlines(True),fromfile='before/tasklist.md',tofile='final/tasklist.md')))
p.write_text(s)
print(json.dumps({'H01':'done, preparation only','new_evidence_index_rows':len(records),'new_review_index_rows':len(reviews),'bound_inputs':len(binding['files']),'all_A_pending':True,'PRD_acceptance':'unassessed'},ensure_ascii=False))
