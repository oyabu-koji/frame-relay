from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,time
root=Path(__file__).resolve().parent
repo=Path('/Users/oyabu/dev/rep/FrameRelay')
label=sys.argv[1]
args=sys.argv[2:]
def inputs():
    rows=[]
    for top in ['FrameRelay','FrameRelayTests','FrameRelayUITests','FrameRelay.xcodeproj']:
        for p in sorted((repo/top).rglob('*')):
            if not p.is_file() or '/xcuserdata/' in str(p): continue
            data=p.read_bytes()
            rows.append({'path':str(p.relative_to(repo)),'size':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    return rows
before=inputs()
if label.startswith(('test-', 'photos-', 'ui-', 'ios-build-')):
    for item in before:
        destination=root/'source-snapshots'/label/item['path']
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(repo/item['path'],destination)
(root/(label+'-sources-before.json')).write_text(json.dumps(before,indent=2))
start=time.time()
with (root/(label+'.log')).open('w') as out:
    result=subprocess.run(args,cwd=repo,stdout=out,stderr=subprocess.STDOUT)
after=inputs()
(root/(label+'-sources-after.json')).write_text(json.dumps(after,indent=2))
summary={'environment':{k:os.environ[k] for k in ['TEST_RUNNER_FR_PHOTOS_INTEGRATION'] if k in os.environ},'args':args,'exit':result.returncode,'seconds':round(time.time()-start,3),'inputs':len(before),'unchanged':before==after,'log':str(root/(label+'.log'))}
(root/(label+'-run.json')).write_text(json.dumps(summary,indent=2))
print(json.dumps(summary),flush=True)
sys.exit(result.returncode)
