from pathlib import Path
import sys, os, json, subprocess, time, hashlib, shutil

OUT = Path(__file__).parent
REPO = Path('/Users/oyabu/dev/rep/FrameRelay')
label, action, *extra = sys.argv[1:]
udid = os.environ.get('FR_P2_SIMULATOR_UDID') or (OUT / 'simulator-id.txt').read_text().strip()
destination = 'generic/platform=iOS' if action == 'ios-build' else 'platform=iOS Simulator,id=' + udid
cmd = ['xcodebuild', '-project', 'FrameRelay.xcodeproj', '-scheme', 'FrameRelay', '-configuration', 'Debug',
       '-destination', destination, '-derivedDataPath', str(OUT / ('iOSDerivedData' if action == 'ios-build' else 'DerivedData')),
       '-disableAutomaticPackageResolution']
if action == 'enumerate':
    cmd += ['-parallel-testing-enabled', 'NO', '-enumerate-tests', '-test-enumeration-format', 'json',
            '-test-enumeration-output-path', str(OUT / 'test-enumeration.json'), 'test']
else:
    cmd += ['-resultBundlePath', str(OUT / (label + '.xcresult'))]
    if action == 'ios-build': cmd += ['-jobs', '2', 'CODE_SIGNING_ALLOWED=NO', 'build']
    else: cmd += ['-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never', *extra,
                  'test-without-building' if action == 'test-without-building' else 'test']
inputs = sorted([p for root in ['FrameRelay', 'FrameRelayTests', 'FrameRelayUITests'] for p in (REPO / root).rglob('*') if p.is_file()]
                + [REPO / 'FrameRelay.xcodeproj/project.pbxproj',
                   REPO / 'FrameRelay.xcodeproj/project.xcworkspace/contents.xcworkspacedata'])
manifest = {}
for p in inputs:
    rel = p.relative_to(REPO); data = p.read_bytes()
    manifest[str(rel)] = {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)}
    target = OUT / (label + '-source') / rel
    target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(p, target)
(OUT / (label + '-sources.json')).write_text(json.dumps(manifest, indent=2))
env = dict(os.environ)
for name in ['FR_LIBRARY_SEED', 'FR_LIBRARY_VERIFY', 'FR_REMOVAL_UI', 'FR_REMOVAL_SEED', 'FR_REMOVAL_VERIFY']:
    env.setdefault('TEST_RUNNER_' + name, '0')
added = {k: v for k, v in env.items() if k.startswith('TEST_RUNNER_FR_')}
record = {'command': cmd, 'start': time.time(), 'added_environment': added, 'source_count': len(manifest),
          'scope': 'New dedicated Simulator only; existing Simulator/app roots untouched'}
(OUT / (label + '-command.json')).write_text(json.dumps(record, indent=2))
print(json.dumps({'started': label, 'source_count': len(manifest), 'destination': destination}), flush=True)
with (OUT / (label + '.log')).open('wb') as log:
    result = subprocess.run(cmd, cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT)
after = {str(p.relative_to(REPO)): {'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'size': p.stat().st_size} for p in inputs}
record.update({'exit_code': result.returncode, 'end': time.time(), 'source_changed': [p for p in manifest if manifest[p] != after[p]]})
(OUT / (label + '-exit.json')).write_text(json.dumps(record, indent=2))
if action != 'enumerate':
    for suffix, args in [('summary', ['test-results', 'summary']), ('build', ['build-results']), ('tests', ['test-results', 'tests'])]:
        if action == 'ios-build' and suffix != 'build': continue
        args = ['xcrun', 'xcresulttool', 'get', *args, '--path', str(OUT / (label + '.xcresult')), '--format', 'json']
        r = subprocess.run(args, capture_output=True)
        if r.returncode == 0: (OUT / (label + '-' + suffix + '.json')).write_bytes(r.stdout)
        else: (OUT / (label + '-' + suffix + '-export.log')).write_bytes(r.stdout + r.stderr)
print(json.dumps({'finished': label, 'exit_code': result.returncode, 'source_changed': record['source_changed']}), flush=True)
summary = OUT / (label + ('-build.json' if action == 'ios-build' else '-summary.json'))
if summary.exists():
    data = json.loads(summary.read_text())
    print(json.dumps({k:v for k,v in data.items() if k in ['totalTestCount','passedTests','failedTests','skippedTests','testFailures','status','errorCount','warningCount','analyzerWarningCount']}, ensure_ascii=False))
sys.exit(result.returncode)
