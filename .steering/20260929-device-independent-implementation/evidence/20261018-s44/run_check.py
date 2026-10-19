import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent
repo = pathlib.Path('/Users/oyabu/dev/rep/FrameRelay')
label, *command = sys.argv[1:]

def snapshot():
    paths = [repo / 'FrameRelay.xcodeproj/project.pbxproj',
             repo / 'FrameRelay.xcodeproj/xcuserdata/oyabu.xcuserdatad/xcschemes/xcschememanagement.plist']
    for directory in ['FrameRelay', 'FrameRelayTests', 'FrameRelayUITests']:
        paths.extend(sorted((repo / directory).rglob('*.swift')))
    return {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in paths if path.is_file()}

before = snapshot()
(root / f'{label}-sources.json').write_text(json.dumps(before, indent=2))
start = datetime.datetime.now(datetime.timezone.utc).isoformat()
with (root / f'{label}.log').open('w') as log:
    result = subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
after = snapshot()
metadata = dict(command=command, startedAt=start,
                finishedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                exitCode=result.returncode, sourceCount=len(before),
                sourceChanges=[p for p in before.keys() | after.keys() if before.get(p) != after.get(p)],
                log=str(root / f'{label}.log'))
(root / f'{label}-run.json').write_text(json.dumps(metadata, indent=2))
print(json.dumps(metadata), flush=True)
sys.exit(result.returncode)
