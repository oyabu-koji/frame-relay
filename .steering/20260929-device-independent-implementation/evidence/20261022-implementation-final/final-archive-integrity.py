from pathlib import Path
import json,hashlib,datetime,sys
r=Path(__file__).parent
baseline=json.loads((r/'baseline-manifest.json').read_text())
st=Path('.steering/20260929-device-independent-implementation/evidence')
reports=[]
for manifest in sorted(st.glob('*/archive-manifest.json')):
 if str(manifest) in baseline or manifest.parent.name=='20261022-implementation-final':continue
 rows=json.loads(manifest.read_text());assert isinstance(rows,list),str(manifest)
 names=set();bad=[]
 for row in rows:
  rel=Path(row['path']);assert not rel.is_absolute() and '..' not in rel.parts
  assert row['path'] not in names;names.add(row['path'])
  p=manifest.parent/rel
  if not p.is_file() or p.is_symlink():bad.append({'file':str(p),'reason':'missing/symlink'});continue
  data=p.read_bytes()
  if hashlib.sha256(data).hexdigest()!=row['sha256'] or len(data)!=row['size']:bad.append({'file':str(p),'reason':'hash/size'})
 assert not bad,bad
 reports.append({'directory':manifest.parent.name,'files':len(rows),'bytes':sum(x['size'] for x in rows),'hash_or_size_errors':bad})
report={'created_UTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'new_execution_and_document_archives':reports,'archive_directories':len(reports),'archived_files':sum(x['files'] for x in reports),'errors':[],'scope':'all manifests newly created this session; final report archive excluded to avoid self-reference. Initial evidence protected separately by baseline hash comparison.'}
(r/((sys.argv[1] if len(sys.argv)>1 else 'final-archive-integrity-01')+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='new_execution_and_document_archives'},ensure_ascii=False))
