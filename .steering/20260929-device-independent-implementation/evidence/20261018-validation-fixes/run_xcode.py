import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

root = Path(__file__).parent
repo = Path('/Users/oyabu/dev/rep/FrameRelay')
name, action, *selection = sys.argv[1:]
def sources():
    result = {}
    for directory in ['FrameRelay', 'FrameRelayTests', 'FrameRelayUITests', 'FrameRelay.xcodeproj']:
        for path in (repo / directory).rglob('*'):
            if path.is_file() and 'xcuserdata' not in path.parts:
                result[str(path.relative_to(repo))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result

before = sources()
(root / (name + '-sources.json')).write_text(json.dumps(before, indent=2, sort_keys=True))
destination = 'generic/platform=iOS' if action == 'ios-build' else 'platform=iOS Simulator,id=DFE46693-E8DD-4814-8957-4F327699F719'
cmd = ['xcodebuild', '-project', 'FrameRelay.xcodeproj', '-scheme', 'FrameRelay', '-configuration', 'Debug',
       '-destination', destination, '-derivedDataPath', str(root / (name + '-DerivedData')),
       '-resultBundlePath', str(root / (name + '.xcresult')), '-disableAutomaticPackageResolution']
if action == 'test':
    cmd += ['-testPlan', 'FrameRelay', '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never'] + selection + ['test']
else:
    cmd += selection + (['CODE_SIGNING_ALLOWED=NO'] if action == 'ios-build' else []) + ['build']
env = {k: v for k, v in os.environ.items() if not k.startswith(('FR_', 'SIMCTL_CHILD_FR_', 'TEST_RUNNER_FR_'))}
record = {'command': cmd, 'startedAt': datetime.now(timezone.utc).isoformat()}
(root / (name + '-run.json')).write_text(json.dumps(record, indent=2))
print(name, 'started', flush=True)
with (root / (name + '.log')).open('w') as log:
    run = subprocess.run(cmd, cwd=repo, env=env, stdout=log, stderr=subprocess.STDOUT)
after = sources()
record.update(exitCode=run.returncode, finishedAt=datetime.now(timezone.utc).isoformat(), sourceCount=len(before),
              sourceChanges=[p for p in set(before) | set(after) if before.get(p) != after.get(p)])
(root / (name + '-run.json')).write_text(json.dumps(record, indent=2))
print(json.dumps(record), flush=True)
for kind, args in [('build', ['build-results'])] + ([('summary', ['test-results', 'summary'])] if action == 'test' else []):
    report = subprocess.run(['xcrun', 'xcresulttool', 'get'] + args + ['--path', str(root / (name + '.xcresult')), '--format', 'json'], capture_output=True)
    (root / (name + '-' + kind + '.json')).write_bytes(report.stdout)
    if report.returncode == 0:
        data = json.loads(report.stdout)
        print(kind, {k: data[k] for k in ['status', 'result', 'errorCount', 'warningCount', 'totalTestCount', 'passedTests', 'failedTests', 'skippedTests'] if k in data}, flush=True)
sys.exit(run.returncode)
