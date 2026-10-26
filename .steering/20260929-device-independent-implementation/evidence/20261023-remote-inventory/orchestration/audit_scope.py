from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parent
repo = Path('/Users/oyabu/dev/rep/FrameRelay')
evidence = repo / '.steering/20260929-device-independent-implementation/evidence/20261023-cleanup-composition'
baseline = json.loads((root / 'baseline-manifest.json').read_text())
ignored = json.loads((root / 'ignored-baseline-manifest.json').read_text())
ownership = json.loads((evidence / 'ownership.json').read_text())
allowed = set(ownership['code_allowed'] + ownership['tests_allowed'])
allowed |= {'.steering/20260929-device-independent-implementation/' + f for f in ['tasklist.md', 'design.md']}
allowed |= {'docs/' + f for f in ['architecture.md', 'functional-design.md', 'development-guidelines.md', 'repository-structure.md']}
allowed |= set(ownership.get('additional_allowed', []))
current = {}
for raw in subprocess.check_output(['git', 'ls-files', '-c', '-o', '--exclude-standard', '-z'], cwd=repo).split(b'\0'):
    if not raw:
        continue
    relative = raw.decode()
    path = repo / relative
    if path.is_file():
        current[relative] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size}
changed = sorted(k for k in baseline.keys() & current.keys() if baseline[k]['sha256'] != current[k]['sha256'])
missing = sorted(baseline.keys() - current.keys())
added = sorted(current.keys() - baseline.keys())
prefixes = ['.steering/20260929-device-independent-implementation/evidence/20261023-cleanup-composition/']
prefixes += ownership.get('additional_prefixes', [])
def permitted(path):
    return path in allowed or any(path.startswith(prefix) for prefix in prefixes)
ignored_changes = []
for path, value in ignored.items():
    actual = repo / path
    if not actual.is_file() or hashlib.sha256(actual.read_bytes()).hexdigest() != value['sha256']:
        ignored_changes.append(path)
result = {'initial_files': len(baseline), 'current_files': len(current), 'changed': changed,
          'missing': missing, 'added': added, 'unexpected': [p for p in changed + missing + added if not permitted(p)],
          'ignored_file_changes': ignored_changes,
          'head_unchanged': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo) == (root / 'head.txt').read_bytes(),
          'staged_unchanged': subprocess.check_output(['git', 'diff', '--cached', '--binary'], cwd=repo) == (root / 'staged.diff').read_bytes()}
(root / 'scope-audit.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({**{k: v for k, v in result.items() if k not in ['changed', 'added']},
                  'changed_files': len(changed), 'added_files': len(added), 'changed_paths': changed,
                  'added_non_evidence': [p for p in added if not any(p.startswith(prefix) for prefix in prefixes)]}, ensure_ascii=False))
