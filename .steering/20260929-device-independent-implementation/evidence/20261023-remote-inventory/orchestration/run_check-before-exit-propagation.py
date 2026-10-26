import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parent
REPO = Path('/Users/oyabu/dev/rep/FrameRelay')

def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def sources():
    result = {}
    for directory in ('FrameRelay', 'FrameRelayTests', 'FrameRelayUITests', 'FrameRelay.xcodeproj'):
        for path in sorted((REPO / directory).rglob('*')):
            if path.is_file() and 'xcuserdata' not in path.parts and '.DS_Store' != path.name:
                data = path.read_bytes()
                result[str(path.relative_to(REPO))] = {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
    return result

def extract(bundle, command, destination):
    value = subprocess.run(['xcrun', 'xcresulttool', 'get', *command, '--path', str(bundle)],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (destination.with_suffix('.stderr.txt')).write_bytes(value.stderr)
    if value.returncode == 0:
        destination.write_bytes(value.stdout)
        try:
            return json.loads(value.stdout)
        except json.JSONDecodeError:
            return None
    return None

parser = argparse.ArgumentParser()
parser.add_argument('name')
parser.add_argument('--kind', choices=['test', 'build'], default='test')
parser.add_argument('--only', action='append', default=[])
parser.add_argument('--env', action='append', default=[])
parser.add_argument('--simulator')
args = parser.parse_args()
run = ROOT / args.name
run.mkdir(exist_ok=False)
before = sources()
fingerprint = hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()
snapshot = ROOT / 'sources' / fingerprint
if not snapshot.exists():
    snapshot.mkdir(parents=True)
    for relative in before:
        destination = snapshot / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO / relative, destination)
    dump(snapshot / 'manifest.json', before)
dump(run / 'sources-before.json', before)
simulator = args.simulator or json.loads((ROOT / 'simulator.json').read_text())['udid']
destination = 'generic/platform=iOS' if args.kind == 'build' else 'platform=iOS Simulator,id=' + simulator
bundle = run / 'result.xcresult'
command = ['xcodebuild', '-project', 'FrameRelay.xcodeproj', '-scheme', 'FrameRelay',
           '-configuration', 'Debug', '-destination', destination,
           '-derivedDataPath', str(ROOT / ('DerivedData-iOS' if args.kind == 'build' else 'DerivedData')),
           '-resultBundlePath', str(bundle), '-disableAutomaticPackageResolution']
if args.kind == 'build':
    command += ['CODE_SIGNING_ALLOWED=NO', 'build']
else:
    command += ['-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never']
    command += ['-only-testing:' + value for value in args.only]
    command += ['test']
environment = os.environ.copy()
overrides = dict(value.split('=', 1) for value in args.env)
environment.update(overrides)
metadata = {'name': args.name, 'command': command, 'environment_overrides': overrides,
            'cwd': str(REPO), 'started_at': datetime.now(timezone.utc).isoformat(),
            'source_fingerprint': fingerprint, 'source_files': len(before), 'snapshot': str(snapshot)}
dump(run / 'command.json', metadata)
print(json.dumps({'started': args.name, 'source_files': len(before), 'log': str(run / 'stdout.log')}, ensure_ascii=False), flush=True)
started = time.monotonic()
with (run / 'stdout.log').open('wb') as output:
    process = subprocess.run(command, cwd=REPO, env=environment, stdout=output, stderr=subprocess.STDOUT)
after = sources()
dump(run / 'sources-after.json', after)
metadata.update({'exit_code': process.returncode, 'seconds': time.monotonic() - started,
                 'finished_at': datetime.now(timezone.utc).isoformat(), 'sources_unchanged': before == after,
                 'changed_inputs': sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))})
if bundle.exists():
    build = extract(bundle, ['build-results'], run / 'build.json')
    metadata['build'] = build
    if args.kind == 'test':
        summary = extract(bundle, ['test-results', 'summary'], run / 'tests.json')
        tree = extract(bundle, ['test-results', 'tests'], run / 'tree.json')
        metadata['tests'] = summary
        if tree:
            counts = Counter()
            expanded = Counter()
            skipped = []
            def visit(node):
                counts[(node.get('nodeType', ''), node.get('result', ''))] += 1
                children = node.get('children', [])
                if node.get('nodeType') == 'Arguments' or (node.get('nodeType') == 'Test Case' and not any(c.get('nodeType') == 'Arguments' for c in children)):
                    expanded[node.get('result', '')] += 1
                if node.get('nodeType') == 'Test Case' and node.get('result') == 'Skipped':
                    skipped.append(node.get('nodeIdentifier', node.get('name')))
                for child in children:
                    visit(child)
            for node in tree.get('testNodes', []):
                visit(node)
            metadata['counts'] = {'nodes': {str(k): v for k, v in counts.items()},
                                  'expanded': dict(expanded), 'skipped': skipped}
dump(run / 'result.json', metadata)
print(json.dumps({'finished': args.name, 'exit': process.returncode, 'sources_unchanged': before == after,
                  'tests': metadata.get('tests'), 'counts': metadata.get('counts'),
                  'build': metadata.get('build')}, ensure_ascii=False), flush=True)
