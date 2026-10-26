import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote,urlsplit
repo=Path('/Users/oyabu/dev/rep/FrameRelay');root=Path(__file__).resolve().parent
steer=repo/'.steering/20260929-device-independent-implementation'
e=steer/'evidence/20261023-remote-inventory'
files=[repo/'docs'/n for n in ['architecture.md','functional-design.md','development-guidelines.md','repository-structure.md']]
files += [steer/n for n in ['requirements.md','design.md','tasklist.md']]
files += [steer/'evidence'/('20261023-'+n)/'README.md' for n in ['cleanup-composition','photo-release-owner','capture-resume','new-registration','remote-inventory']]
checks={};missing=[]
for p in files:
 text=p.read_text();text=re.sub(r'```.*?```','',text,flags=re.S)
 count=0
 for m in re.finditer(r'(?<!!)\[[^\]]+\]\(([^)]+)\)',text):
  value=m.group(1).strip().strip('<>')
  if value.startswith(('#','http:','https:','mailto:','skill:','plugin:')):continue
  value=unquote(value.split('#')[0]);value=re.sub(r':\d+$','',value)
  if not value:continue
  count+=1
  target=p.parent/value
  if not target.exists():missing.append({'file':str(p.relative_to(repo)),'target':value})
 checks[str(p.relative_to(repo))]=count
def ac_rows(text):
 section=text.split('## PRD 全21要求・79ACの個別台帳')[1].split('## CF／BI条件')[0]
 rows={}
 for line in section.splitlines():
  if re.match(r'^\| (?:FR|NFR)-',line):
   cells=line.split('|');assert len(cells)==15,(len(cells),line)
   key=cells[2].strip();assert key not in rows;rows[key]={'D':cells[11].strip(),'R':cells[12].strip()}
 return rows
before=ac_rows((root/'baseline/.steering/20260929-device-independent-implementation/tasklist.md').read_text())
after=ac_rows((steer/'tasklist.md').read_text())
assert len(before)==len(after)==79 and before==after
assert all(v['D']=='D0' for v in after.values())
assert not missing,missing
critical=['FrameRelay/Features/Playback/OriginalPlaybackView.swift','FrameRelay.xcodeproj/project.pbxproj','.steering/20260929-device-independent-implementation/requirements.md','AGENTS.md','PROJECT_CONTEXT.md']
baseline=json.loads((root/'baseline-manifest.json').read_text())
unchanged={p:hashlib.sha256((repo/p).read_bytes()).hexdigest()==baseline[p]['sha256'] for p in critical}
assert all(unchanged.values()),unchanged
result={'local_links_checked':sum(checks.values()),'files':checks,'missing':missing,'PRD_rows':79,'PRD_ids_and_D_R_unchanged':before==after,'all_D':'D0','critical_unchanged':unchanged,'scope':'main static handoff check, not independent implementation validation'}
(e/'handoff-static-check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False))
