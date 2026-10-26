import difflib
import hashlib
import json
from pathlib import Path
import subprocess
repo=Path('/Users/oyabu/dev/rep/FrameRelay');root=Path(__file__).resolve().parent
e=repo/'.steering/20260929-device-independent-implementation/evidence/20261023-remote-inventory'
subprocess.run(['python3',str(root/'audit_scope.py')],check=True,stdout=subprocess.DEVNULL)
audit=json.loads((root/'scope-audit.json').read_text());baseline=json.loads((root/'baseline-manifest.json').read_text())
assert not any(audit[k] for k in ['missing','unexpected','ignored_file_changes'])
assert audit['head_unchanged'] and audit['staged_unchanged']
prefix='.steering/20260929-device-independent-implementation/evidence/'
new=[p for p in audit['added'] if not p.startswith(prefix)]
patch=[];manifest={}
for relative in sorted(audit['changed']+new):
 current=(repo/relative).read_bytes();before=b''
 if relative in baseline:
  saved=root/'baseline'/relative
  before=saved.read_bytes() if saved.is_file() else subprocess.check_output(['git','show','HEAD:'+relative],cwd=repo)
  assert hashlib.sha256(before).hexdigest()==baseline[relative]['sha256'],relative
  dest=e/'session-baseline'/relative;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(before)
 manifest[relative]={'before_sha256':hashlib.sha256(before).hexdigest() if relative in baseline else None,'after_sha256':hashlib.sha256(current).hexdigest(),'new':relative not in baseline}
 patch.extend(difflib.unified_diff(before.decode().splitlines(True),current.decode().splitlines(True),fromfile='session-start/'+relative,tofile='session-final/'+relative))
content=''.join(patch).encode();(e/'session-changes.diff').write_bytes(content)
result={'baseline_files':len(baseline),'changed_existing':len(audit['changed']),'new_non_evidence':len(new),'files':manifest,'patch_sha256':hashlib.sha256(content).hexdigest(),'scope':'actual session-start dirty/untracked bytes, not HEAD; existing-before source copies retained','baseline_root':str(root/'baseline')}
(e/'session-delta.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='files'},ensure_ascii=False))
