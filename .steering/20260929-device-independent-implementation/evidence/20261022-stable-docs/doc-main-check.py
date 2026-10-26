from pathlib import Path
import json,hashlib,re,subprocess,sys
r=Path(__file__).parent; name,label,sha=sys.argv[1:4];p=Path('docs')/name
actual=hashlib.sha256(p.read_bytes()).hexdigest();assert actual==sha
app=json.loads((r/'s49-candidate-03.json').read_text());support=json.loads((r/'s27-http-main-review-05.json').read_text())['source_files']
bad=[]
for rel,want in app.items():
 q=Path(rel)
 if not q.is_file() or hashlib.sha256(q.read_bytes()).hexdigest()!=want:bad.append(rel)
for rel,want in support.items():
 q=Path('.steering/20260929-device-independent-implementation/support')/rel
 if not q.is_file() or hashlib.sha256(q.read_bytes()).hexdigest()!=want:bad.append(str(q))
assert not bad,bad
links=re.findall(r'\[[^\]\n]+\]\(([^)]+)\)',p.read_text());broken=[href for href in links if not href.startswith(('http:','https:','#')) and not (p.parent/href.split('#')[0]).resolve().exists()];assert not broken
check=subprocess.run(['git','diff','--check','--',str(p)],capture_output=True,text=True);assert check.returncode==0,check.stdout+check.stderr
out={'task':label.upper(),'file':str(p),'sha256':actual,'main_review':'full diff plus any corrected candidate delta read by main; authority and current implementation limits checked','source_inputs':{'app':len(app),'support':len(support),'changed_or_missing':bad},'local_links':len([x for x in links if not x.startswith(('http:','https:','#'))]),'broken_links':broken,'diff_check':check.returncode,'build_test_added':False,'device_or_PRD_acceptance':False}
if name=='functional-design.md':
 def table(s):return s[s.index('| PRD要件'):s.index('## 利用者フロー')]
 before=(r/'m02-m06-before'/name).read_text();out['PRD_mapping_table_unchanged']=table(before)==table(p.read_text());assert out['PRD_mapping_table_unchanged']
 out['T01_T21_present']=all(f'T{x:02d}' in p.read_text() for x in range(1,22));assert out['T01_T21_present']
(r/(label+'-main-review-01.json')).write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(out,ensure_ascii=False))
