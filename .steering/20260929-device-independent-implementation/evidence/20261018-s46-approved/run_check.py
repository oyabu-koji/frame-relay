import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import shutil

root = Path('/Users/oyabu/dev/rep/FrameRelay')
work = Path(__file__).parent
name, *command = sys.argv[1:]

def sources():
    result = {}
    for folder in ('FrameRelay', 'FrameRelayTests', 'FrameRelayUITests', 'FrameRelay.xcodeproj'):
        for path in (root / folder).rglob('*'):
            if path.is_file() and 'xcuserdata' not in path.parts:
                result[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result

before = sources()
(work / (name + '-sources.json')).write_text(json.dumps(before, indent=2))
for rel in before:
    snapshot = work / (name + '-source') / rel
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / rel, snapshot)
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
with (work / (name + '.log')).open('w') as log:
    run = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
after = sources()
record = {'command': command, 'startedAt': started,
          'finishedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'exitCode': run.returncode, 'sourceCount': len(before),
          'sourceChanges': [p for p in before.keys() | after.keys() if before.get(p) != after.get(p)]}
(work / (name + '-run.json')).write_text(json.dumps(record, indent=2))
print(json.dumps(record))
if '-resultBundlePath' in command:
    bundle = command[command.index('-resultBundlePath') + 1]
    if Path(bundle).exists():
        for query in (['test-results', 'summary'], ['test-results', 'tests'], ['build-results']):
            result = subprocess.run(['xcrun', 'xcresulttool', 'get', *query, '--path', bundle],
                                    capture_output=True, text=True)
            suffix = query[-1] if result.returncode == 0 else query[-1] + '-error'
            (work / (name + '-' + suffix + '.json')).write_text(result.stdout if result.returncode == 0 else result.stderr)
            if query == ['test-results', 'summary'] and result.returncode == 0:
                print(result.stdout)
sys.exit(run.returncode)
