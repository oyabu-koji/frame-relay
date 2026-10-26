from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
repo=Path('/Users/oyabu/dev/rep/FrameRelay');root=Path(__file__).resolve().parent
steer=repo/'.steering/20260929-device-independent-implementation';e=steer/'evidence/20261023-remote-inventory'
binding=json.loads((e/'source-binding.json').read_text());final={p:v for p,v in binding['files'].items() if v['group']=='App/Unit/UI/project'}
for p,v in binding['files'].items():assert hashlib.sha256((repo/p).read_bytes()).hexdigest()==v['sha256'],p
required=['inventory-ui-49','inventory-max-50','inventory-post-51','new-registration-max-58','new-registration-ui-59','new-registration-post-60','connection-legacy-final-61','final-unit-all-62','regression-ui-63','regression-max-64','regression-post-65','cleanup-post-66','final-ios-build-67']
runs={};failures=[];zero=[]
for d in sorted(root.iterdir()):
 if not (d.is_dir() and (d/'result.json').is_file() and (d/'sources-before.json').is_file()):continue
 result=json.loads((d/'result.json').read_text());before=json.loads((d/'sources-before.json').read_text());tests=result.get('tests') or {};build=result.get('build') or {}
 changed=sorted(p for p in before.keys()&final.keys() if before[p]['sha256']!=final[p]['sha256'])
 missing=sorted(final.keys()-before.keys())
 item={'exit_code':result['exit_code'],'source_files':result['source_files'],'sources_unchanged':result['sources_unchanged'],'source_fingerprint':result['source_fingerprint'],'snapshot':result['snapshot'],'declared_tests':tests.get('totalTestCount'),'passed_declarations':tests.get('passedTests'),'skipped_declarations':tests.get('skippedTests'),'expanded':result.get('counts',{}).get('expanded'),'compiler_errors':build.get('errorCount'),'compiler_warnings':build.get('warningCount'),'analyzer_warnings':build.get('analyzerWarningCount'),'xcresult_runtimeWarnings':tests.get('runtimeWarnings'),'changed_vs_final':changed,'added_since_run':missing,'raw_bundle':str(d/'result.xcresult')}
 runs[d.name]=item
 if result['exit_code']!=0:failures.append(d.name)
 if result.get('kind','test')=='test' and not tests.get('totalTestCount') and 'build' not in d.name:zero.append(d.name)
for n in required:
 v=runs[n];assert v['exit_code']==0 and v['sources_unchanged'],(n,v)
 assert v['compiler_errors']==0 and v['compiler_warnings']==0 and v['analyzer_warnings']==0,(n,v)
 if n!='final-ios-build-67':assert v['declared_tests'] and v['xcresult_runtimeWarnings']==[],(n,v)
for n in ['final-unit-all-62','regression-ui-63','regression-max-64','regression-post-65','cleanup-post-66','final-ios-build-67']:
 assert not runs[n]['changed_vs_final'] and not runs[n]['added_since_run'],(n,runs[n])
result={'binding_id':binding['id'],'binding_hash':binding['source_manifest_sha256'],'created_UTC':datetime.now(timezone.utc).isoformat(),'required_final_runs':required,'runs':runs,'retained_failures':failures,'zero_test_runs_not_success':zero,'inheritance':['UI49/50/VERIFY51 precede only Connection input focus/keyboard modifiers and the separate NewRegistrationFlowTests helper; catalog/registered metadata screen/test code are unchanged, data later unchanged on fourth shutdown root. No claim of a final focus-version rerun on fourth.','HTTP35 native coordinator/store/vault/wire and server002 scope frozen; later App changes are view text/layout/focus, with dedicated UI and final Unit/build checked separately.','S34/S31/S49 historical scoped SDK/UI results are retained with exact earlier source snapshots. Latest full Unit is a regression, not a substitute for formal producers/all media/device acceptance.'],'scope_limits':['36 default opt-in skips remain explicit; scoped SDK/SEED/VERIFY runs are separate.','No new independent implementation validation, real device/real network/quality/PRD acceptance.','Old H01/395 input bindings are historical and unchanged; Q01 must bind latest source/build/actual conditions.']}
(e/'execution-binding.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'binding':binding['id'],'recorded_runs':len(runs),'required':len(required),'retained_failures':failures,'zero_tests':zero},ensure_ascii=False))
