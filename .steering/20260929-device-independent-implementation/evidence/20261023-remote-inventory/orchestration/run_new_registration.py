import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('name')
parser.add_argument('mode', choices=['seed', 'ui', 'max', 'verify'])
args = parser.parse_args()
c = json.loads((root / 'new-registration-context.json').read_text())
device = c['simulator']
assert device == '5B5BD239-98C0-44E9-9EF3-29EB1B9A4EE5'
category = 'accessibility-extra-extra-extra-large' if args.mode == 'max' else 'large'
subprocess.run(['xcrun','simctl','ui',device,'content_size',category],check=True)
observed = subprocess.check_output(['xcrun','simctl','ui',device,'content_size'],text=True).strip()
assert observed == category
flags = {'FR_NEW_REGISTRATION_SEED_TOKEN': c['token'], 'FR_NEW_REGISTRATION_SEED_NONCE': c['nonce'], 'FR_NEW_REGISTRATION_SIMULATOR_ID':device}
key = {'seed':'SEED','ui':'UI','max':'UI','verify':'VERIFY'}[args.mode]
flags['FR_NEW_REGISTRATION_'+key] = '1'
only = 'FrameRelayUITests/NewRegistrationFlowTests/testExplicitInputCancellationHTTPRejectionDepartureAndRelaunch' if args.mode in ['ui','max'] else 'FrameRelayTests/ProductNewRegistrationSeedTests'
command = [sys.executable,str(root/'run_check.py'),args.name,'--simulator',device,'--only',only]
for k,v in flags.items(): command += ['--env','TEST_RUNNER_'+k+'='+v]
conditions = {'simulator':device,'mode':args.mode,'content_size':observed,'started_at':datetime.now(timezone.utc).isoformat()}
(root/(args.name+'-conditions.json')).write_text(json.dumps(conditions,indent=2)+'\n')
try:
 code = subprocess.call(command)
 container = Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.oyabu.FrameRelay','data'],text=True).strip())
 manifest = container/'Library/Application Support/FrameRelayLibrary/s28-new-registration-seed.json'
 data = manifest.read_bytes()
 movies = sorted(str(p.relative_to(container)) for p in (container/'Library/Application Support').rglob('*.mov'))
 observation = {'container':str(container),'relative_manifest':str(manifest.relative_to(container)),'manifest_sha256':hashlib.sha256(data).hexdigest(),'manifest_bytes':len(data),'movies':movies}
 (root/(args.name+'-fixture.json')).write_text(json.dumps(observation,indent=2)+'\n')
finally:
 subprocess.run(['xcrun','simctl','ui',device,'content_size','large'],check=True)
raise SystemExit(code)
