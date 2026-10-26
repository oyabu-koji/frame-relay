from pathlib import Path
import sys, subprocess, json, collections
out = Path(__file__).parent
label = sys.argv[1]
dest = out / (label + '-attachments')
cmd = ['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(out / (label + '.xcresult')), '--output-path', str(dest)]
r = subprocess.run(cmd, capture_output=True)
(out / (label + '-attachments-export.log')).write_bytes(r.stdout + r.stderr)
if r.returncode: sys.exit(r.returncode)
manifest = json.loads((dest / 'manifest.json').read_text())
issues = []
for test in manifest:
    for item in test.get('attachments', []):
        name = item.get('suggestedHumanReadableName', '')
        if 'unhandled-issue' not in name: continue
        file = dest / item['exportedFileName']
        content = file.read_text()
        lines = content.splitlines()
        issues.append({'test': {k: v for k, v in test.items() if k != 'attachments'}, 'name': name,
                       'path': str(file), 'issue': lines[0] if lines else '',
                       'element': next((s for s in lines if s.startswith('identifier=')), None), 'details': content})
(out / (label + '-issues.json')).write_text(json.dumps(issues, ensure_ascii=False, indent=2))
index = [{k: v for k, v in i.items() if k != 'details'} for i in issues]
(out / (label + '-issue-index.json')).write_text(json.dumps(index, ensure_ascii=False, indent=2))
print(json.dumps({'label': label, 'issues': len(issues), 'counts': dict(collections.Counter(i['issue'] for i in issues))}, ensure_ascii=False))
