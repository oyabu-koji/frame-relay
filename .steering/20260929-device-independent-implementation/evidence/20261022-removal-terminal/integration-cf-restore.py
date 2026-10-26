from pathlib import Path
import subprocess,json,hashlib,datetime
r=Path(__file__).parent;ud='DFE46693-E8DD-4814-8957-4F327699F719';before=(r/'integration-cf-preferences-before.json').read_bytes();sha=lambda b:hashlib.sha256(b).hexdigest();assert sha(before)=='eed6889861e8d5ca30b90bfe2a2f05a7482f955ccb223e0dfe4955fb3fbe6fa7'
term=subprocess.run(['xcrun','simctl','terminate',ud,'com.oyabu.FrameRelay'],capture_output=True,text=True)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',ud,'com.oyabu.FrameRelay','data'],text=True).strip());p=container/'Library/Application Support/FrameRelayLibrary/capture-preferences.json';after=p.read_bytes();(r/'integration-cf-preferences-after-UI.json').write_bytes(after);assert json.loads(after)==json.loads(before),'Unexpected preference semantic difference; preserved without overwriting'
if after!=before:p.write_bytes(before)
report={'timeUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'container':str(container),'app_terminate_exit':term.returncode,'before':{'sha256':sha(before),'bytes':len(before)},'after_ui':{'sha256':sha(after),'bytes':len(after)},'semantic_equal':True,'restored':after!=before,'final_sha256':sha(p.read_bytes())};(r/'integration-cf-preferences-restored-01.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));assert p.read_bytes()==before
