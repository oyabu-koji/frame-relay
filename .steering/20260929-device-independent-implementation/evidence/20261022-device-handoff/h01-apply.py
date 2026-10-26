from pathlib import Path
import json,re,hashlib,difflib
r=Path(__file__).parent
p=Path('.steering/20260929-device-independent-implementation/tasklist.md')
evidence=p.parent/'evidence/20261022-device-handoff/source-binding.json'
assert evidence.is_file(), 'final binding must exist before application'
before=p.read_text();text=before
assert '### H01 引渡し準備版' not in text
rows=json.loads((r/'h01-branches-draft.json').read_text())
axes=json.loads((r/'h01-axes-draft.json').read_text())
assert rows['row_count']==76 and rows['dv_count']==18 and not rows['missing'] and not rows['unknown']
start=text.index('## PRD 全21要求・79ACの個別台帳')
end=text.index('## CF／BI条件を残す受入対応',start)
section=text[start:end];changed=[]
def update(m):
 line=m.group(0);c=[v.strip() for v in line.strip().strip('|').split('|')]
 assert len(c)==13,(c[:2],len(c))
 if c[1] not in axes:return line
 a=axes[c[1]];assert c[10]=='D0';c[8]=a['I'];c[9]=a['A'];c[11]=a['R'];changed.append(c[1])
 return '| '+' | '.join(c)+' |'
section=re.sub(r'^\| (?:FR-|NFR-)[^\n]+$',update,section,flags=re.M)
assert set(changed)==set(axes) and len(changed)==35
text=text[:start]+section+text[end:]
common=(r/'h01-common-draft.md').read_text().replace('H01-SOURCE-01（最終source-binding.jsonへの実リンクをmainが設定）','[H01-SOURCE-01](evidence/20261022-device-handoff/source-binding.json)')
assert '最終source-binding.jsonへの実リンク' not in common
text=text.replace('### A01 / DV-01 形式・手動設定',common+'\n### A01 / DV-01 形式・手動設定',1)
def cell(value):return str(value).replace('|','&#124;').replace('\n','<br>')
for num in range(18,0,-1):
 dv=f'DV-{num:02d}';a=f'A{num:02d}'
 marker=f'### {a} / {dv} '
 at=text.index(marker)
 following=re.search(r'^### A\d{2} / DV-|^## ',text[at+len(marker):],re.M)
 assert following
 tail=at+len(marker)+following.start()
 table=['\n引渡しcase母行（全パラメータのrun展開は共通規則とQ01に従う）:\n\n','| case／根拠AC・旧条件 | 条件→操作 | 期待結果 | 必要証拠 | 直接依存・必要substatus | 実装状態／実施可否 |\n','| --- | --- | --- | --- | --- | --- |\n']
 group=sorted((x for x in rows['rows'] if x['dv']==dv),key=lambda x:tuple(int(v) for v in x['case'][1:].split('.')));assert group
 for x in group:
  values=[dv+'/'+x['case']+'<br>'+ '、'.join(x['ac'])+'<br>'+x['old'],x['condition']+'<br>→ '+x['action'],x['expected'],x['evidence'],x['dependency'],x['availability']]
  table.append('| '+' | '.join(cell(v) for v in values)+' |\n')
 text=text[:tail]+''.join(table)+'\n'+text[tail:]
# Existing six concrete parent rows must remain byte-identical.
parents=re.findall(r'^\| DV-\d{2}/c\d{2} [^\n]+$',before,re.M)
assert len(parents)==6 and all(line in text for line in parents)
assert len(re.findall(r'^### A\d{2} / DV-\d{2} ',text,re.M))==18
(r/'h01-tasklist-before-01.md').write_text(before)
(r/'h01-applied-diff-01.txt').write_text(''.join(difflib.unified_diff(before.splitlines(True),text.splitlines(True),fromfile='before/tasklist.md',tofile='tasklist.md')))
p.write_text(text)
print(json.dumps({'mother_rows':76,'changed_axis_rows':len(changed),'preserved_parent_rows':len(parents),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}))
