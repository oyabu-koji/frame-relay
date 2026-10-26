from pathlib import Path
import json,hashlib,shutil
r=Path(__file__).parent
source=r/'h01-source-01'
target=Path('.steering/20260929-device-independent-implementation/evidence/20261022-device-handoff')
assert source.is_dir() and (source/'source-binding.json').is_file()
target.mkdir(parents=True,exist_ok=True)
manifest=target/'archive-manifest.json'
rows=json.loads(manifest.read_text()) if manifest.exists() else []
known={row['path']:row for row in rows}
for p in sorted(source.rglob('*')):
 if not p.is_file():continue
 assert not p.is_symlink()
 rel=str(p.relative_to(source));data=p.read_bytes();sha=hashlib.sha256(data).hexdigest()
 if rel in known:
  assert known[rel]['sha256']==sha
  assert hashlib.sha256((target/rel).read_bytes()).hexdigest()==sha
  continue
 q=target/rel;q.parent.mkdir(parents=True,exist_ok=True);assert not q.exists();shutil.copy2(p,q)
 rows.append({'path':rel,'sha256':sha,'size':len(data),'origin':str(p)})
manifest.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
binding=json.loads((target/'source-binding.json').read_text())
for rel,row in binding['files'].items():
 assert hashlib.sha256((target/'source-snapshot'/rel).read_bytes()).hexdigest()==row['sha256']
 assert hashlib.sha256(Path(rel).read_bytes()).hexdigest()==row['sha256']
print(json.dumps({'bound_source_files':len(binding['files']),'archived_files':len(rows),'bytes':sum(x['size'] for x in rows),'source_manifest_sha256':binding['source_manifest_sha256']},ensure_ascii=False))
