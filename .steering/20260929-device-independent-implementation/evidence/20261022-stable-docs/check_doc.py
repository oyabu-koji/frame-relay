from pathlib import Path
import hashlib,json,re,shutil,subprocess,sys,time,difflib
root=Path(__file__).parent
label,name=sys.argv[1:3]
p=Path('docs')/name;before=root/'m02-m06-before'/name
missing=[]
for href in re.findall(r'\[[^\]\n]+\]\(([^)]+)\)',p.read_text()):
 if href.startswith(('http://','https://','#')):continue
 if not (p.parent/href.split('#')[0]).resolve().exists():missing.append(href)
diff=''.join(difflib.unified_diff(before.read_text().splitlines(True),p.read_text().splitlines(True),fromfile='before/'+name,tofile='docs/'+name))
(root/(label+'-diff.txt')).write_text(diff)
shutil.copy2(p,root/(label+'-'+name))
report={'label':label,'file':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'before_sha256':hashlib.sha256(before.read_bytes()).hexdigest(),'missing_local_links':missing,'T_ids':sorted(set(re.findall(r'\bT\d{2}\b',p.read_text()))),'time':time.time()}
(root/(label+'-static.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
if missing:raise SystemExit(1)
