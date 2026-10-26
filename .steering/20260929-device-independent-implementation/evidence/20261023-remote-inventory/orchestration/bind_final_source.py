from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
root=Path(__file__).resolve().parent
repo=Path('/Users/oyabu/dev/rep/FrameRelay')
steer=repo/'.steering/20260929-device-independent-implementation'
e=steer/'evidence/20261023-remote-inventory'
old=json.loads((steer/'evidence/20261023-capture-resume/source-binding.json').read_text())
paths={k:v['group'] for k,v in old['files'].items() if v['group']!='App/Unit/UI/project'}
for directory in ['FrameRelay','FrameRelayTests','FrameRelayUITests','FrameRelay.xcodeproj']:
 for p in sorted((repo/directory).rglob('*')):
  if p.is_file() and 'xcuserdata' not in p.parts and p.name!='.DS_Store':paths[str(p.relative_to(repo))]='App/Unit/UI/project'
for p in json.loads((e/'server-ownership.json').read_text())['allowed']:paths[p]='server support'
files={}
for p,g in sorted(paths.items()):
 b=(repo/p).read_bytes();files[p]={'sha256':hashlib.sha256(b).hexdigest(),'size':len(b),'group':g}
counts=dict(Counter(v['group'] for v in files.values()));counts['total']=len(files)
assert counts=={'steering input':2,'server support':97,'App/Unit/UI/project':309,'stable document':6,'total':414},counts
canonical=json.dumps(files,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
patch=subprocess.check_output(['git','diff','--binary','--',*sorted(paths)],cwd=repo)
(e/'tracked-source.diff').write_bytes(patch)
snapshot=e/'source-snapshot'
snapshot.mkdir(exist_ok=False)
for p in files:
 dst=snapshot/p;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(repo/p,dst)
changed=sorted(p for p in old['files'].keys()&files.keys() if old['files'][p]['sha256']!=files[p]['sha256'])
added=sorted(files.keys()-old['files'].keys())
d={'id':'DI-SOURCE-20261023-02','created_UTC':datetime.now(timezone.utc).isoformat(),'sourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'source_manifest_sha256':hashlib.sha256(canonical).hexdigest(),'hash_definition':old['hash_definition'],'input_counts':counts,'files':files,'tracked_source_patch_sha256':hashlib.sha256(patch).hexdigest(),'governance':{p:hashlib.sha256((repo/p).read_bytes()).hexdigest() for p in ['AGENTS.md','PROJECT_CONTEXT.md']},'previous_binding':{'id':old['id'],'sha256':old['source_manifest_sha256'],'changed':changed,'added':added,'removed':sorted(old['files'].keys()-files.keys())},'prior_H01':old['prior_H01'],'device_execution':old['device_execution'],'limitations':old['limitations']}
(e/'source-binding.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'id':d['id'],'inputs':counts,'hash':d['source_manifest_sha256'],'changed':len(changed),'added':len(added)},ensure_ascii=False))
