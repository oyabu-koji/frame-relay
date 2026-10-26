from pathlib import Path
import hashlib,json,subprocess,shutil,datetime
r=Path(__file__).parent;repo=Path.cwd();st=Path('.steering/20260929-device-independent-implementation');out=r/'h01-source-01'
assert not out.exists(),'immutable source binding already exists'
latest=json.loads((r/'latest-tested-source.json').read_text());app=json.loads((r/latest['app_manifest']).read_text());support=json.loads((r/latest['support_manifest']).read_text())['support_files']
manifest={}
def add(rel,group,want=None):
 p=repo/rel;data=p.read_bytes();sha=hashlib.sha256(data).hexdigest();assert want is None or sha==want,rel
 manifest[rel]={'sha256':sha,'size':len(data),'group':group}
for rel,want in app.items():add(rel,'App/Unit/UI/project',want)
for rel,want in support.items():add(str(st/'support'/rel),'server support',want)
for name in ['product-requirements','functional-design','architecture','repository-structure','development-guidelines','glossary']:add('docs/'+name+'.md','stable document')
for name in ['requirements','design']:add(str(st/(name+'.md')),'steering input')
assert len(manifest)==len(app)+len(support)+8
head=subprocess.run(['git','rev-parse','HEAD'],capture_output=True,text=True,check=True).stdout.strip()
paths=sorted(manifest)
tracked=set(subprocess.run(['git','ls-files','-z','--',*paths],capture_output=True,check=True).stdout.decode().split('\0'))
untracked={p:manifest[p]['sha256'] for p in paths if p not in tracked}
patch=subprocess.run(['git','diff','--binary','HEAD','--',*paths],capture_output=True,check=True).stdout
canonical=json.dumps(manifest,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
dirty={'tracked_patch_sha256':hashlib.sha256(patch).hexdigest(),'untracked_sources':untracked}
dirty_sha=hashlib.sha256(json.dumps(dirty,sort_keys=True,separators=(',',':')).encode()).hexdigest()
sha=lambda p:hashlib.sha256((repo/p).read_bytes()).hexdigest()
# Verify implementation outputs consumed by the actual backend snapshot and actual HTTP preparation.
backend_rel='support/server-implementation/backend-overlay'
backend=repo/st/backend_rel; tested=Path('/private/tmp/fr-di-20261015-s27/S27/snapshot-002/backend')
backend_compare=[]
for p in sorted(backend.rglob('*')):
 if p.is_file():
  rel=p.relative_to(backend);q=tested/rel
  if not q.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=hashlib.sha256(q.read_bytes()).hexdigest():backend_compare.append(str(rel))
assert not backend_compare,backend_compare
http=Path(json.loads((r/'final-execution-binding.json').read_text())['metadata_HTTP']['preparation_source_snapshot'])
http_compare=[]
for p in sorted(http.rglob('*')):
 if p.is_file():
  q=repo/st/'support/server-isolation'/p.relative_to(http)
  if not q.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=hashlib.sha256(q.read_bytes()).hexdigest():http_compare.append(str(p.relative_to(http)))
assert http_compare==['README-publication.md'],http_compare
readme_before=r/'s2v-support-README-before-01.md'
assert hashlib.sha256((http/'README-publication.md').read_bytes()).hexdigest()==hashlib.sha256(readme_before.read_bytes()).hexdigest()
assert hashlib.sha256((repo/st/'support/server-isolation/README-publication.md').read_bytes()).hexdigest()==support['server-isolation/README-publication.md']
catalog=json.loads((r/'final-execution-binding.json').read_text())
binding={'id':'H01-SOURCE-01','created_UTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'sourceRevision':head,'dirty_difference_sha256':dirty_sha,'source_manifest_sha256':hashlib.sha256(canonical).hexdigest(),
 'hash_definition':'SHA256 of sorted canonical manifest JSON; dirty hash binds the tracked patch and each untracked source. Every exact source byte is in source-snapshot/. tasklist/evidence excluded to avoid self-reference.',
 'input_counts':{'App_Unit_UI_project':len(app),'server_support':len(support),'stable_docs':6,'steering_inputs':2,'total':len(manifest)},
 'files':manifest,'dirty_delta':dirty,'execution_binding':catalog,
 'device_execution':{'all_A01_A18':'pending','D':'D0','PRD_acceptance':'unassessed','Q01':'actual environment, buildID, media, network, quality, permissions, counts and repetitions unbound'},
 'limitations':['Formal Log/Rec709 assets and production proof absent','Normal strict network start/resume and all media producer integration incomplete','Known four strict accessibility failures unresolved','Source binding does not establish device quality or whole-product completion']}

out.mkdir()
for rel,entry in manifest.items():
 target=out/'source-snapshot'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(repo/rel,target);assert hashlib.sha256(target.read_bytes()).hexdigest()==entry['sha256']
(out/'tracked-source.diff').write_bytes(patch)
(out/'source-binding.json').write_text(json.dumps(binding,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'source_manifest_sha256':binding['source_manifest_sha256'],'dirty_difference_sha256':dirty_sha,'sourceRevision':head,'counts':binding['input_counts'],'backend_overlay_mismatches':backend_compare,'HTTP_documentation_only_differences':http_compare},ensure_ascii=False))
