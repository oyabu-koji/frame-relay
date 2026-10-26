from pathlib import Path
import json,re,hashlib,subprocess,sys
r=Path(__file__).parent;p=Path('.steering/20260929-device-independent-implementation/tasklist.md');text=p.read_text();before=(r/'h01-tasklist-before-01.md').read_text();rows=json.loads((r/'h01-branches-draft.json').read_text())['rows'];axes=json.loads((r/'h01-axes-draft.json').read_text())
def prd(s):
 a=s.index('## PRD 全21要求・79ACの個別台帳');b=s.index('## CF／BI条件を残す受入対応',a);result={}
 for line in s[a:b].splitlines():
  if re.match(r'^\| (?:FR-|NFR-)',line):
   c=[x.strip() for x in line.strip().strip('|').split('|')];assert len(c)==13;assert c[1] not in result;result[c[1]]=c
 return result
old,new=prd(before),prd(text);assert len(new)==79 and list(old)==list(new)
for ac,c in new.items():
 assert c[10]=='D0'
 for i in range(13):
  if ac in axes and i in [8,9,11]:continue
  assert c[i]==old[ac][i],(ac,i)
assert new['AC-NFR-04-02'][8:10]==old['AC-NFR-04-02'][8:10]
assert set(ac for x in rows for ac in x['ac'])==set(new)
parents=re.findall(r'^\| DV-\d{2}/c\d{2} [^\n]+$',before,re.M);assert len(parents)==6 and all(x in text for x in parents)
found=re.findall(r'^\| (DV-\d{2}/c\d{2}(?:\.\d{2})?)<br>',text,re.M)
assert len(found)==76 and len(set(found))==76 and set(found)=={x['dv']+'/'+x['case'] for x in rows}
a_sections=list(re.finditer(r'^### A(\d{2}) / DV-(\d{2}) ',text,re.M));assert len(a_sections)==18
for i,m in enumerate(a_sections):
 assert int(m[1])==int(m[2])==i+1
 end=a_sections[i+1].start() if i+1<len(a_sections) else text.index('## 検証証跡・レビュー記録',m.end())
 block=text[m.end():end];assert block.count('- [ ] Status: pending')==1
for prefix,count in [('AC-CF-',11),('AC-BI-',34),('AC-DI-',18)]:
 ids=set(re.findall(r'\b'+prefix+r'\d{2}\b',text));assert ids=={prefix+f'{i:02d}' for i in range(1,count+1)},(prefix,ids)
for prefix,count in [('C',19),('B',7),('U',5),('V',16)]:
 # Legacy ranges are explicitly inherited in the common text; actual runs expand all values.
 expected=prefix+('01' if prefix!='B' else '1')+'〜'+prefix+(f'{count:02d}' if prefix!='B' else str(count))
 assert expected in text,expected
broken=[]
for href in re.findall(r'\[[^\]\n]+\]\(([^)]+)\)',text):
 if href.startswith(('http://','https://','#')):continue
 if not (p.parent/href.split('#')[0]).resolve().exists():broken.append(href)
assert not broken,broken
binding_path=p.parent/'evidence/20261022-device-handoff/source-binding.json';binding=json.loads(binding_path.read_text());bad=[]
for rel,row in binding['files'].items():
 if not Path(rel).is_file() or hashlib.sha256(Path(rel).read_bytes()).hexdigest()!=row['sha256']:bad.append(rel)
assert not bad,bad
check=subprocess.run(['git','diff','--check'],capture_output=True,text=True);assert check.returncode==0,check.stdout+check.stderr
report={'PRD_rows':79,'PRD_order_and_non_IAR_columns_preserved':True,'IAR_updated':len(axes),'all_D0':True,'NFR04_02_I_A_unchanged':True,'DV':18,'all_A_pending':True,'mother_rows':76,'unique_mother_ids':len(set(found)),'preserved_parent_rows':len(parents),'CF':11,'BI':34,'DI':18,'legacy_ranges_inherited':['C01-C19','B1-B7','U01-U05','V01-V16'],'missing_local_links':broken,'final_bound_inputs':len(binding['files']),'bound_source_changed':bad,'git_diff_check':check.returncode,'tasklist_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'device_execution':False,'PRD_acceptance':'unassessed'}
(r/((sys.argv[1] if len(sys.argv)>1 else 'h01-static-01')+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
