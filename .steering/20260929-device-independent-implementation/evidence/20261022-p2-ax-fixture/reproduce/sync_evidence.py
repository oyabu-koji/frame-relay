from pathlib import Path
import json, hashlib, shutil, datetime
REPO=Path('/Users/oyabu/dev/rep/FrameRelay')
RAW=Path(__file__).parent
DEST=REPO/'.steering/20260929-device-independent-implementation/evidence/20261022-p2-ax-fixture'

def sha(data): return hashlib.sha256(data).hexdigest()
def dump(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def copy(src,dest):
    dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
source=json.loads((DEST/'source-manifest.json').read_text())
current={p:{'sha256':v['sha256'],'size':v['size']} for p,v in source['files'].items() if v['group']=='App/Unit/UI/project'}
assert len(current)==288
classes={
'configuration-01':'構成・列挙のみ、test成功に含めない',
'fresh-seed-01':'最初の専用新規root作成成功。fixture修正のみの証拠、AX修正前',
'ax-baseline-01':'fresh fixtureで既知4失敗を再現',
'ax-eager-01':'VStack案不採用、3失敗を保持',
'ax-native-status-01':'詳細native本文だけの限定A/B、最終全件成功ではない',
'ax-native-all-01':'native本文4成功。ただしnative子ID伝播不足、最終版扱いしない',
'ui-final-01':'native子ID不足のため途中取消。3成功/取消1、全体合格扱いしない',
'ios-build-final-01':'native子ID明示前の途中build',
'post-interrupt-verify-01':'selector誤りで実行0件、成功扱いしない',
'post-interrupt-verify-02':'中断後のreader/identity照合、隔離root回帰2成功/seed1skip',
'ui-final-02':'17件中16成功/選択観測1失敗、最終UI成功扱いしない',
'ios-build-final-02':'製品最終native本文・旧UI観測helper版のbuild',
'selection-live-01':'選択のfresh観測だけの1成功、全UI代替ではない',
'ui-final-03':'製品最終版の17成功。最大字item探索helper追加前の全件run',
'ios-build-final-03':'最大字item探索helper追加前のbuild、製品sourceは最終版と同一',
'initial-connection-final-01':'別の新規未登録環境で初回接続1成功。LibraryFlowTestsだけ後に変更、Connection/Appは最終版と同一',
'fresh-seed-final-01':'別の新規empty Library rootで初回作成2成功/verify1skip。最終製品/fixtureと同一、CFコピーなし',
'fresh-strict-final-01':'別のfresh seed上の既知4 strict成功。後変更はLibraryのitem探索helperのみ、監査条件/Appは同一',
'unit-final-01':'全Unit、opt-in VERIFY有効。Unit/App/project全入力は最終版と同一、後変更は非UnitのLibraryFlowTestsのみ',
'ui-max-final-01':'最大字4件ともsetup探索失敗、本体/AX未到達。0 issueを監査合格に数えない',
'max-query-01':'最大字fresh親queryも1失敗。親hit=false/同link可視child hit=trueを観測',
'max-visible-title-01':'最終288入力、最大字の全文7項目と実可視title tap成功',
'ui-max-final-02':'最終288入力、最大字の一覧/選択/詳細/履歴/再起動・再生/停止/背景・実VOの3成功',
'ios-build-final-04':'最終288入力、generic iOS署名なしbuild成功',
'ui-final-04':'最終288入力、通常17UI（厳格6を含む）成功',
'post-ui-final-01':'最終288入力、UI後identity/digest/全reader照合＋隔離root回帰2成功/seed1skip',
}

def cases(tree):
    out={}
    def visit(n):
        if n.get('nodeType')=='Test Case':out[n['name']]=n.get('result')
        for child in n.get('children',[]):visit(child)
    for n in tree.get('testNodes',[]):visit(n)
    return out
runs=[]
for command in sorted(RAW.glob('*-command.json'),key=lambda p:json.loads(p.read_text()).get('start',0)):
    label=command.name.removesuffix('-command.json');exitpath=RAW/(label+'-exit.json')
    if not exitpath.exists():raise RuntimeError('run incomplete: '+label)
    e=json.loads(exitpath.read_text());s=RAW/(label+'-summary.json');s=json.loads(s.read_text()) if s.exists() else {}
    b=RAW/(label+'-build.json');b=json.loads(b.read_text()) if b.exists() else {}
    inputs=json.loads((RAW/(label+'-sources.json')).read_text());differences=[p for p in current if current[p]!=inputs.get(p)]
    tree=RAW/(label+'-tests.json');testcases=cases(json.loads(tree.read_text())) if tree.exists() else {}
    issues=RAW/(label+'-issue-index.json');issues=json.loads(issues.read_text()) if issues.exists() else None
    item={'label':label,'classification':classes.get(label,'未分類、rawを参照'),'exit_code':e['exit_code'],'source_count':len(inputs),'source_changed_during_run':e['source_changed'],'source_differences_from_final_288':differences,'counts':{k:s[k] for k in ['totalTestCount','passedTests','failedTests','skippedTests'] if k in s},'build':{k:b[k] for k in ['status','errorCount','warningCount','analyzerWarningCount'] if k in b},'runtime_warnings':s.get('runtimeWarnings'),'test_results':testcases,'accessibility_tests_selected':any(n.startswith('testAccessibility') for n in testcases),'unhandled_issue_attachments':len(issues) if issues is not None else None,'raw_log':str(RAW/(label+'.log')),'raw_xcresult':str(RAW/(label+'.xcresult')) if (RAW/(label+'.xcresult')).exists() else None}
    assert not item['source_changed_during_run']
    runs.append(item)
    for suffix in ['command','exit','sources','summary','build','tests','issue-index','issues','metrics']:
        p=RAW/(label+'-'+suffix+'.json')
        if p.exists():copy(p,DEST/'runs'/p.name)
dump(DEST/'run-index.json',runs)

known=['testAccessibilityDetailActionsContrastOnly()','testAccessibilityFreshHistory()','testAccessibilityHistoryAfterPlaybackHandoff()','testAccessibilityLibraryAndDetail()']
prior=Path('/private/tmp/fr-validation-20261022-lh_5wn0r')
old=cases(json.loads((prior/'ui-strict-01-tests.json').read_text()))
new=next(r for r in runs if r['label']=='ui-final-04')['test_results'];fresh=next(r for r in runs if r['label']=='fresh-strict-final-01')['test_results']
comparison=[{'test':n,'independent_previous':old[n],'fresh_reproduction':next(r for r in runs if r['label']=='ax-baseline-01')['test_results'][n],'final_normal':new[n],'second_fresh_strict':fresh[n]} for n in known]
assert all(c['final_normal']=='Passed' and c['second_fresh_strict']=='Passed' for c in comparison)
dump(DEST/'known-four-comparison.json',comparison)
for name in ['validation-summary.json','ui-strict-01-command.json','ui-strict-01-summary.json','ui-strict-01-issue-index.json','new-library-seed-01-command.json','new-library-seed-01-summary.json']:
    p=prior/name
    if p.exists():copy(p,DEST/'prior'/name)
for name in ['configuration-summary.json','environment-commands.json','test-enumeration.json','simulator-create.json','unconfigured-simulator-create.json','ui-environment-01.json','unconfigured-simulator-boot.json','max-content-size-before.json','max-content-size-restored-final-01.json','audit-preservation-final-01.json','audit-preservation-final-02.json','doc-review-final-01.json','unit-final-01-metrics.json','text-size-comparison-final-01.json','test-products-final-01.json','test-products-final-02.json','non-accepting-runs.json','ui-final-01-interrupt.json','fixture-files-interim-01.json','fixture-files-final-01.json','final-preservation.json','source-binding-final-01.json','main-review-final-01.json','investigation-final-01.json','ui-18-comparison-final-01.json','unit-skip-index-final-01.json']:
    p=RAW/name
    if p.exists():copy(p,DEST/name)
for run in ['ax-baseline-01','ax-native-status-01','ui-final-02','selection-live-01','ui-final-03','max-query-01','max-visible-title-01','ui-max-final-02','ui-final-04']:
    folder=RAW/(run+'-attachments')
    if not (folder/'manifest.json').exists():continue
    manifest=json.loads((folder/'manifest.json').read_text());copy(folder/'manifest.json',DEST/'observations'/run/'manifest.json')
    for t in manifest:
        for a in t['attachments']:
            name=a.get('suggestedHumanReadableName','');p=folder/a['exportedFileName']
            if p.suffix=='.txt' and any(term in name for term in ['measurements','semantic-text-environment','actual-VoiceOver-speech','library-selection-live','library-seed-row-fresh-query','library-item-target','candidate-frames']):copy(p,DEST/'observations'/run/p.name)
            if p.suffix=='.png' and any(name.startswith('text-layout-'+key+'-screen') for key in ['history-removal','submission-phase']):copy(p,DEST/'observations'/run/p.name)
for name in ['run.py','export_ax.py','sync_evidence.py']:
    copy(RAW/name,DEST/'reproduce'/name)
raw_artifacts={}
for run in runs:
    label=run['label'];files={}
    for suffix in ['.log','-sources.json','-command.json','-exit.json']:
        p=RAW/(label+suffix)
        if p.exists():data=p.read_bytes();files[str(p)]={'size':len(data),'sha256':sha(data)}
    bundle=RAW/(label+'.xcresult');xc=None
    if bundle.exists():
        rows=sorted((str(p.relative_to(bundle)),p.stat().st_size,p.stat().st_mtime_ns) for p in bundle.rglob('*') if p.is_file())
        xc={'path':str(bundle),'files':len(rows),'bytes':sum(n[1] for n in rows),'metadata_sha256':sha(json.dumps(rows).encode())}
    raw_artifacts[label]={'files':files,'xcresult':xc}
dump(DEST/'raw-artifacts.json',{'raw_root':str(RAW),'metadata_hash_definition':'SHA256(json.dumps(sorted tuples(relative path, size, mtime_ns)))','runs':raw_artifacts})
print(json.dumps({'runs':len(runs),'known_four':comparison,'destination':str(DEST)},ensure_ascii=False))
