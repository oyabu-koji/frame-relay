from pathlib import Path
import json,hashlib,subprocess,datetime
r=Path(__file__).parent;baseline=json.loads((r/'baseline-manifest.json').read_text());st='.steering/20260929-device-independent-implementation/'
allowed={st+'design.md',st+'tasklist.md',*('docs/'+n+'.md' for n in ['functional-design','architecture','repository-structure','development-guidelines','glossary'])}
allowed.update(st+'support/server-implementation/'+n for n in ['README-publication.md','backend-overlay/app/services/frame_relay_files.py','backend-overlay/tests/test_frame_relay_publication.py','backend-publication-overlay.diff','cases-publication.json','prepare_publication_snapshot.py'])
allowed.update(st+'support/server-isolation/'+n for n in ['README-publication.md','prepare_publication_probe.py','publication_fixture_listener.py','run_publication_fixture.py','run_publication_simulator_probe.py'])
missing=[];changed=[];unexpected=[]
for name,row in baseline.items():
 p=Path(name)
 if not p.is_file():missing.append(name);continue
 sha=hashlib.sha256(p.read_bytes()).hexdigest()
 if sha!=row['sha256']:
  changed.append(name)
  if name not in allowed and not name.startswith(('FrameRelay/','FrameRelayTests/','FrameRelayUITests/')):unexpected.append(name)
protected={name for name in baseline if name not in allowed and not name.startswith(('FrameRelay/','FrameRelayTests/','FrameRelayUITests/'))}
check=subprocess.run(['git','diff','--check'],capture_output=True,text=True)
report={'created_UTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'baseline_files':len(baseline),'all_initial_files_exist':not missing,'missing':missing,'changed_existing':changed,'changed_existing_count':len(changed),'protected_files':len(protected),'unexpected_protected_changes':unexpected,'project_unchanged_since_session_start':'FrameRelay.xcodeproj/project.pbxproj' not in changed,'git_diff_check':check.returncode,'diagnostics':check.stdout+check.stderr}
(r/'final-preservation-01.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='changed_existing'},ensure_ascii=False));assert not missing and not unexpected and check.returncode==0
