import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
root=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--max',action='store_true');a=p.parse_args()
device=json.loads((root/'regression-simulator.json').read_text())['udid']
assert device=='DB985305-B55C-4694-8307-77E3BFD2E11D'
category='accessibility-extra-extra-extra-large' if a.max else 'large'
subprocess.run(['xcrun','simctl','ui',device,'content_size',category],check=True)
assert subprocess.check_output(['xcrun','simctl','ui',device,'content_size'],text=True).strip()==category
(root/(a.name+'-conditions.json')).write_text(json.dumps({'simulator':device,'content_size':category,'started_at':datetime.now(timezone.utc).isoformat()},indent=2)+'\n')
def fixture():
 container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.oyabu.FrameRelay','data'],text=True).strip())
 manifest=container/'Library/Application Support/FrameRelayLibrary/s16v2-test-seed-evidence.json'
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 movies={str(p.relative_to(container)):{'sha256':sha(p),'bytes':p.stat().st_size} for p in (container/'Library/Application Support').rglob('*.mov')}
 assert sha(manifest)=='ad9267f8343fe8f01a57c7b5c31ac237a4b1b83ddb1b84cce8841f292b9ed201'
 assert any(v=={'sha256':'d12f2dfd375e4cbbf64883e43f697416a6794b6675bba434e3e290b418294751','bytes':485721} for v in movies.values())
 return {'container':str(container),'relative_manifest':str(manifest.relative_to(container)),'manifest_sha256':sha(manifest),'movies':movies}
before=fixture();(root/(a.name+'-fixture-before.json')).write_text(json.dumps(before,indent=2)+'\n')
command=[sys.executable,str(root/'run_check.py'),a.name,'--simulator',device]
for method in ['testListDetailSelectionHistoryAndRetainedStateAfterRelaunch','testOriginalPlaybackProgressStopBackgroundAndRestart']:
 command+=['--only','FrameRelayUITests/LibraryFlowTests/'+method]
try:
 code=subprocess.call(command)
 after=fixture();(root/(a.name+'-fixture-after.json')).write_text(json.dumps(after,indent=2)+'\n')
 assert before['manifest_sha256']==after['manifest_sha256'] and before['movies']==after['movies']
finally:
 subprocess.run(['xcrun','simctl','ui',device,'content_size','large'],check=True)
raise SystemExit(code)
