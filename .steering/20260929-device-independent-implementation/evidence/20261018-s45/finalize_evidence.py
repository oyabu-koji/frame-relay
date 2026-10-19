import pathlib,json,hashlib,subprocess,shutil,difflib,datetime
repo=pathlib.Path('/Users/oyabu/dev/rep/FrameRelay')
r=pathlib.Path('/private/tmp/fr-s45-20261018-ow_sx8bp')
e=repo/'.steering/20260929-device-independent-implementation/evidence/20261018-s45'
baseline={x['path']:x for x in json.loads((r/'baseline-manifest.json').read_text())}
paths=set(x.decode() for x in subprocess.check_output(['git','ls-files','-z','--cached','--others','--exclude-standard'],cwd=repo).split(b'\0') if x)
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
changed=sorted(p for p in baseline if (repo/p).is_file() and digest(repo/p)!=baseline[p]['sha256'])
missing=sorted(p for p in baseline if not (repo/p).is_file())
new=sorted(p for p in paths-set(baseline) if '/evidence/' not in p)
expected=json.loads((r/'pre-final-scope.json').read_text())
violations=sorted((set(changed)-set(expected['changed'])) | (set(new)-set(expected['newOutsideEvidence'])))
old_evidence=[p for p in changed if '/evidence/' in p]
assert not missing and not violations and not old_evidence,(missing,violations,old_evidence)
inputs=json.loads((r/'test-final-05-sources.json').read_text())
input_differences=[p for p,h in inputs.items() if not (repo/p).is_file() or digest(repo/p)!=h]
ios_inputs=json.loads((r/'ios-build-03-sources.json').read_text())
assert not input_differences and inputs==ios_inputs
scope={'createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'baselineCount':len(baseline),'changed':changed,'newOutsideEvidence':new,'missing':missing,'oldEvidenceChanges':old_evidence,'ownershipViolations':violations,'unchangedCount':len(baseline)-len(changed),'testedInputs':len(inputs),'testAndBuildInputsIdentical':inputs==ios_inputs,'currentInputDifferences':input_differences,'status':'S45 blocked: product policy decisions pending and real Vision Simulator identity test failure','independentValidation':False}
(r/'main-scope-review.json').write_text(json.dumps(scope,ensure_ascii=False,indent=2))
patch=[]
for name in changed+new:
    current=repo/name
    before=r/'baseline'/name
    destination=e/'final-source'/name; destination.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(current,destination)
    if name in changed:
        saved=e/'baseline-changed'/name; saved.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(before,saved)
    if current.suffix not in ('.jpg','.png'):
        old=before.read_text().splitlines(True) if before.is_file() else []
        patch.extend(difflib.unified_diff(old,current.read_text().splitlines(True),fromfile='baseline/'+name,tofile='final/'+name))
    else: patch.append('Binary snapshot: '+name+' sha256='+digest(current)+'\n')
(r/'changes.patch').write_text(''.join(patch))
# Keep failed input versions for the exact changed files, not duplicate the old archive.
for name in changed+new:
    saved=r/'test-02-source'/name
    if saved.is_file():
        dest=e/'test-02-source'/name; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(saved,dest)
for p in r.iterdir():
    if p.is_file() and p.suffix in ('.json','.log','.txt','.swift','.py','.patch','.png') and p.name not in ('baseline-tracked.diff',): shutil.copy2(p,e/p.name)
manifest=[{'path':str(p.relative_to(e)),'size':p.stat().st_size,'sha256':digest(p)} for p in sorted(e.rglob('*')) if p.is_file() and p.name!='archive-manifest.json']
(e/'archive-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print(json.dumps({'changed':len(changed),'new':len(new),'unchanged':scope['unchangedCount'],'violations':violations,'archiveFiles':len(manifest),'archiveBytes':sum(x['size'] for x in manifest),'testedInputs':len(inputs)},ensure_ascii=False))
