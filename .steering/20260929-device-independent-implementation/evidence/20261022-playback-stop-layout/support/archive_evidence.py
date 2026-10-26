import pathlib,json,hashlib,shutil,subprocess,difflib,datetime
RUN=pathlib.Path(__file__).resolve().parent
ROOT=pathlib.Path('/Users/oyabu/dev/rep/FrameRelay')
OUT=ROOT/'.steering/20260929-device-independent-implementation/evidence/20261022-playback-stop-layout'
def read(p):return json.loads(p.read_text())
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
owned=['FrameRelay/Features/Playback/OriginalPlaybackView.swift','FrameRelayUITests/Flows/LibraryFlowTests.swift']
versions=[read(RUN/n) for n in ['source-manifest.json','source-manifest-final.json','source-manifest-03.json','source-manifest-04.json']]
final=versions[-1]
assert all(sha(ROOT/p)==m['sha256'] for p,m in final['files'].items())
required=['build-ios-04','unit-04','ui-normal-04','ui-max-audit-04','ui-max-flow-04','post-ui']
for name in required:
 assert read(RUN/(name+'-exit.json'))['exit_code']==0,name
 if not name.startswith('build-ios'):
  summary=read(RUN/(name+'-test-results-summary.json'))
  assert summary['failedTests']==0 and summary['passedTests']>0,name
assert read(RUN/'unit-04-metrics.json')['expanded']=={'Passed':17}
fixture=read(RUN/'fixture-after-ui.json');assert fixture['post_ui_store_identity_and_all_logical_and_media_readers_empty']
OUT.mkdir(parents=True,exist_ok=False)
run_index=[]
for bundle in sorted(RUN.glob('*.xcresult')):
 name=bundle.stem
 build_file=RUN/(name+'-build-results.json')
 if not build_file.exists():
  build=subprocess.check_output(['xcrun','xcresulttool','get','build-results','--path',str(bundle)],text=True)
  build_file.write_text(build+'\n')
 summary_file=RUN/(name+'-test-results-summary.json')
 before=read(RUN/(name+'-sources-before.json'));after=read(RUN/(name+'-sources-after.json'))
 assert before==after,name
 matches=[v['id'] for v in versions if v['files']==before];assert len(matches)==1,(name,matches)
 if name in required:assert matches==[final['id']],(name,matches)
 row={'name':name,'source_id':matches[0],'source_changed_during_run':False,'command':name+'-command.json','exit':read(RUN/(name+'-exit.json')),'bundle':str(bundle),'build':read(build_file)}
 if summary_file.exists():row['test_summary']=read(summary_file)
 run_index.append(row)
for p in RUN.glob('*.json'):shutil.copy2(p,OUT/p.name)
save(OUT/'run-index.json',run_index)
shutil.copytree(RUN/'source-snapshot-04',OUT/'source-snapshot-04')
for label,directory in [('01','source-snapshot'),('02','source-snapshot-final'),('03','source-snapshot-03')]:
 for rel in owned:
  dst=OUT/'iterations'/label/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(RUN/directory/rel,dst)
shutil.copytree(RUN/'prior-validation',OUT/'prior-validation')
for script in ['run_command.py','run_xcode.py','summarize_bundle.py','archive_evidence.py']:
 dst=OUT/'support'/script;dst.parent.mkdir(exist_ok=True);shutil.copy2(RUN/script,dst)
selection_prefixes=['playback-stop-','playback-explanation-','operation-original-stop-stable','operation-original-stopped-after','operation-original-playback-progress','accessibility-player-playing-with-stop-before','accessibility-player-playing-with-stop-after','accessibility-player-stopped-after']
observations=[]
for name in ['ui-normal','ui-max','ui-max-audit-03','ui-max-audit-04','ui-max-flow-04','ui-normal-04']:
 src=RUN/(name+'-attachments');manifest=read(src/'manifest.json');selected=[];issues=[]
 for test in manifest:
  for a in test['attachments']:
   human=a.get('suggestedHumanReadableName','');f=src/a['exportedFileName']
   issue='unhandled-issue' in human
   if issue:issues.append({'name':human,'file':a['exportedFileName']})
   keep=(name in ['ui-max-audit-04','ui-max-flow-04','ui-normal-04'] and any(human.startswith(k) for k in selection_prefixes)) or issue or (name in ['ui-normal','ui-max','ui-max-audit-03'] and human.startswith('accessibility-player-playing-with-stop-before'))
   if not keep or f.suffix not in ['.txt','.png']:continue
   dst=OUT/'observations'/name/a['exportedFileName'];dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,dst)
   selected.append({'test':{k:v for k,v in test.items() if k!='attachments'},**a,'sha256':sha(f)})
  
 dst=OUT/'observations'/name/'manifest.json';dst.parent.mkdir(parents=True,exist_ok=True)
 save(dst,{'selection_only':True,'full_raw_manifest':str(src/'manifest.json'),'attachments':selected})
 observations.append({'run':name,'unhandled_issues':issues,'selected_attachments':len(selected)})
 if name.endswith('04'):assert not issues,(name,issues)
save(OUT/'observation-index.json',observations)
patch=''
for rel in owned:
 patch+=''.join(difflib.unified_diff((RUN/'baseline'/rel).read_text().splitlines(keepends=True),(ROOT/rel).read_text().splitlines(keepends=True),fromfile='start/'+rel,tofile='final/'+rel))
(OUT/'implementation.patch').write_text(patch)
ui0=(RUN/'baseline'/owned[1]).read_text();ui1=(ROOT/owned[1]).read_text();anchor='    @MainActor private func audit('
assert ui0[ui0.index(anchor):]==ui1[ui1.index(anchor):]
changed=[p for p,m in final['files'].items() if sha(ROOT/p)!=read(RUN/'baseline-manifest.json')[p]['sha256']]
assert sorted(changed)==sorted(owned)
review={'reviewer':'main','final_source':final['id'],'final_source_inputs':len(final['files']),'changed_sources_from_start':changed,'unchanged_sources_from_start':len(final['files'])-len(changed),'audit_mask_handler_and_common_helper_tail_unchanged':True,'reader_contract_sources_unchanged':True,'checks':['Fixed footer is a sibling of scrolling text and has intrinsic height with semantic fonts/full text.','Normal and AX5 actual elapsed updates cross the single/double digit boundary with zero stop displacement; same after explanation scroll.','One ordinary tap starts/completes stop; final stopped requires stop/player AX absence.','Delayed SDK/open and failed release Unit boundaries are unchanged and all 17 related expanded cases passed.','Initial playing audit remains enabled; native explanation keeps full semantic footnote/all 12 categories; no audit issue is accepted/filtered.','Full explanation reaches the own player viewport with complete label and screenshot.','Post-UI stable original bindings/digest and all logical/media reader release passed.'],'findings':[],'limits':['Initial independent validation failure dispatch timing and direct/internal cause remain undetermined.','Implementation checks are not independent final validation.','Other steering tasks, device, real recordings/network and quality/PRD acceptance remain incomplete.']}
save(OUT/'main-review-final.json',review)
summary={'evidence_id':'E-P2-STOP-20261022','scope':'S16 原本再生の停止位置P2と必要関連変更','final_source':final['id'],'required_runs':required,'unit_declarations_passed':14,'unit_expanded_passed':17,'normal_ui_passed':3,'max_ui_passed':2,'final_failed_tests':0,'post_ui_passed':2,'post_ui_skipped_seed':1,'original_digest':fixture['original']['sha256'],'original_bytes':fixture['original']['bytes'],'reader_release_verified':True,'normal_elapsed_stop_displacement_pt':0,'max_elapsed_stop_displacement_pt':0,'max_explanation_scroll_stop_displacement_pt':0,'historical_failures_preserved':['ui-normal: stop contrast nearly passed, 11/12 passed','ui-max: SwiftUI explanation contrast, 4/5 passed','ui-max-audit-03: same explanation contrast, 0/1 passed'],'steering_overall_complete':False,'device_acceptance_complete':False,'independent_final_validation_started':False,'next_workflow':'$validate-implementation .steering/20260929-device-independent-implementation/'}
save(OUT/'verification-summary.json',summary)
readme='''# 原本再生の停止位置P2修正（2026-10-22）

独立validationのAX5で秒数折返しに伴い停止操作が約62pt移動するP2 1件を修正した。S16の非実機範囲だけを対象とし、全steering・実機・品質・PRD受入は未完了のまま。初回停止待機失敗のdispatch瞬間・直接原因や停止処理内部の不具合は断定していない。元の失敗・限定再試験成功は[元validation](prior-validation/validation-summary.json)と2件のfailure観測JSONに保持した。

## 変更と契約

- OriginalPlaybackViewだけで、ScrollViewと停止/閉じる操作を外側VStackの兄弟へ分けた。操作領域の高さは全文とsemantic bodyで決まり、秒数や本文スクロールから独立する。停止は44pt以上で、既存isBusy/停止中disabled/model.stop呼出を保持。停止文字色は既存closeと同じprimary。
- 追加playing監査で説明文のAX領域/表示にcontrast指摘が出たため、該当説明1箇所だけ既存Libraryと同じUILabelの実提案幅・無制限高による計測へ変更。semantic footnote、全12文字サイズ、全文・AX全文とIDを保持。Libraryの既存実文字AX修正・seed/guard・Model/SDK解放順序は変更していない。
- UIはスクロールせず5〜10秒台の実値と一桁/二桁境界でfresh stop frame/到達を観測。説明全文への専用ScrollView内の通常スクロールと可視領域包含・停止位置を検査し、1回の通常tap後の停止開始/完了・stop/player消失を確認。短命なstoppingだけの観測は要求しない。
- 初期playingと停止後の監査、既存背景停止・再起動を維持。監査mask/全issue未処理のhandler/共通reveal・topを含む末尾は開始bytesと同一。issue受理・除外・文字サイズ制限なし。

## 検証結果

実在のFrameRelay.xcodeproj / FrameRelay scheme / 自動FrameRelay Test plan / Debug / 有効なUnit・UI target、iPhone18Pro/iOS27 Simulatorを確認。Xcode27.0(27A266a)、Swift6.4 compiler・言語5.0・最低iOS27.0を維持した。[構成](environment.json)、[全run・実コマンド](run-index.json)、[集計](verification-summary.json)を参照。

| 最終版04の確認 | run | 結果 |
| --- | --- | --- |
| generic iOS署名なしbuild | build-ios-04 | 成功、compiler/analyzer error/warning 0 |
| 原本SDK・遅延drain/open・解放失敗・保存/Composition Unit | unit-04 | 14宣言/17展開成功、失敗・skip 0 |
| 通常の再生中/停止後・引渡し履歴AX、実時間stop/背景/再起動 | ui-normal-04 | 3成功、失敗・skip 0 |
| 最大AX5の初期playing/停止後AX・説明全文 | ui-max-audit-04 | 1成功、未処理issue 0 |
| 最大AX5の実時間位置・全文scroll・単一tap/背景/再起動 | ui-max-flow-04 | 1成功、移動量は更新中/scroll中とも0pt |
| UI後の単一store再open・固定原本identity/digest/全reader | post-ui | 2成功・seed 1skip、失敗0 |

最終通常/AX5は停止ボタンy710.0/671.3ptで一定。最大文字の秒数表示自体は63.3/125.3ptの1行/2行を行き来したが、停止位置は変わらなかった。単一tap直前はexists/enabled/hittable、tap後は停止完了・stop/player不在。内部reader実解放はUI文言だけから推定せず、遅延SDK等のUnitとUI後store検査を結合した。[最大観測](max-stop-observations.json)、[通常観測](normal-stop-observations-final.json)、[選択画像/AX/実測](observation-index.json)を参照。

fresh-seedは新しい空の専用App rootで2成功/verify 1skip。既存rootのコピー/修復/再seedなし。UI後はimmutable seed manifestのbytes、stable binding3件、原本485,721bytesと全SHA-256、映像/音声各30秒・音声1trackを保持し、全logical readers/mediaReaders空を照合した。物理container移動は観測として記録し永続identityへ代用しない。[UI後の独立file hash/試験根拠](fixture-after-ui.json)を参照。

最大文字は設定取得後に実行し、最大run後も同値を取得。largeへ復元/再取得後に通常04を実行し、終了後もlarge。作成した専用Simulatorだけデータ保持でshutdown。既存Simulatorのstate変更0。[保全](simulator-preservation.json)を参照。実機・実撮影/実回線・品質・縦横全状態・PRD受入は未実施であり、既存Q01/A01〜18等の未完了状態を保持する。固定coverage閾値の合意はなく、今回は未計測。

## 実行版・途中失敗・保全

最終[389入力manifest](source-manifest-04.json)とsource-snapshot-04/が実行版。開始版からView/UIの2sourceだけ変更、残り387不変。最終6runは同じ04 bytesと実行前後一致。過去の01〜03 sourceはmanifest・iterations内の変更2fileとrawの完全snapshotへ分離した。初回通常11成功/stop contrast 1失敗、primary tint後の通常2成功、最大4成功/説明contrast1失敗、兄弟配置後の最大監査1失敗をすべて保持し、最終成功へ上書きしない。前回のLibrary実文字AX/fresh fixtureは同hashを保持し、今回再実行していない全領域まで合格に拡張しない。

開始16,673file/352,478,405bytesと既存未コミット差分をrawへ退避し、対象3fileの開始bytesから加算した。[実装差分](implementation.patch)、[main差分レビュー](main-review-final.json)、final-preservation.jsonを参照。コード変更はView/UIの2file、進捗はtasklist、新規はこの証跡だけ。requirements/design・canonical docs・project/guard・過去証跡を保全する。

rawは /var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-playback-stop-20261022-yzlo6h2y/。xcresult・全ログ・全添付・開始差分/退避と完全snapshotを保持。observations/は各manifestが明示する選択コピーであり、rawの全添付と区別する。

独立した最終validationは未開始。次工程は明示 `$validate-implementation .steering/20260929-device-independent-implementation/`。
'''
(OUT/'README.md').write_text(readme)
print(json.dumps({'evidence':str(OUT),'runs':len(run_index),'source_inputs':len(final['files']),'modified_sources':changed,'final_checks_passed':True},ensure_ascii=False))
