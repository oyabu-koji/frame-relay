from pathlib import Path
import json,hashlib,subprocess,datetime
r=Path(__file__).parent
baseline=json.loads((r/'baseline-manifest.json').read_text())
latest=json.loads((r/'latest-tested-source.json').read_text())
app=json.loads((r/latest['app_manifest']).read_text())
expected=json.loads((r/'m04-source-inventory-02.json').read_text())
new=sorted(rel for rel in app if rel not in baseline)
changed=sorted(rel for rel,sha in app.items() if rel in baseline and baseline[rel]['sha256']!=sha)
assert new==sorted(expected['new']) and changed==sorted(expected['changed_existing'])
assert len(new)==43 and len(changed)==29
bad=[rel for rel,sha in app.items() if not Path(rel).is_file() or hashlib.sha256(Path(rel).read_bytes()).hexdigest()!=sha]
assert not bad,bad
all_current=set(subprocess.run(['git','ls-files','--cached','--others','--exclude-standard','-z'],capture_output=True,check=True).stdout.decode().split('\0'))-{''}
new_files=all_current-set(baseline)
evidence_prefix='.steering/20260929-device-independent-implementation/evidence/'
unexpected_new=sorted(x for x in new_files if x not in new and not x.startswith(evidence_prefix))
assert not unexpected_new,unexpected_new
head=subprocess.run(['git','rev-parse','HEAD'],capture_output=True,text=True,check=True).stdout.strip()
before_head=(r/'git-head-before.txt').read_text().strip()
assert head==before_head
report={'created_UTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'App_input_count':len(app),'new_App_inputs':new,'changed_existing_App_inputs':changed,'new_App_count':len(new),'changed_existing_App_count':len(changed),'current_vs_executed_source_mismatches':bad,'new_evidence_files':len([x for x in new_files if x.startswith(evidence_prefix)]),'unexpected_new_files':unexpected_new,'HEAD_unchanged':True,'project_unchanged_since_session_start':hashlib.sha256(Path('FrameRelay.xcodeproj/project.pbxproj').read_bytes()).hexdigest()==baseline['FrameRelay.xcodeproj/project.pbxproj']['sha256'],'scope_review':'main reviewed each task delta and final source layers; no new app source after candidate02 tests'}
(r/'final-source-scope-02.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['new_App_inputs','changed_existing_App_inputs']},ensure_ascii=False))
