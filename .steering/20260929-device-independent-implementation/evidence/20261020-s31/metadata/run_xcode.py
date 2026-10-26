import argparse, hashlib, json, os, shutil, subprocess, sys, time
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('run')
parser.add_argument('--action', choices=['test','build'], default='test')
parser.add_argument('--only', action='append', default=[])
parser.add_argument('--photos', choices=['authorized','denied','compatibility'])
parser.add_argument('--ios', action='store_true')
args=parser.parse_args()
root=Path(__file__).resolve().parent
repo=Path('/Users/oyabu/dev/rep/FrameRelay')
def snapshot():
    # Split using a real NUL; source roots include test fixtures and project assets.
    paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=repo).decode().split(chr(0))
    result=[]
    for rel in sorted(set(p for p in paths if p)):
        if not rel.startswith(('FrameRelay/','FrameRelayTests/','FrameRelayUITests/','FrameRelay.xcodeproj/')): continue
        if 'xcuserdata/' in rel: continue
        path=repo/rel
        if path.is_file():
            data=path.read_bytes()
            result.append({'path':rel,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)})
    return result
prefix=root/args.run
if prefix.with_suffix('.command.json').exists(): raise SystemExit('run id exists')
destination='generic/platform=iOS' if args.ios else 'platform=iOS Simulator,id=7FD88306-1CFD-4181-83E6-ED765F8830B0'
command=['xcodebuild','-project','FrameRelay.xcodeproj','-scheme','FrameRelay','-configuration','Debug','-destination',destination,'-derivedDataPath',str(root/('DerivedData-ios' if args.ios else 'DerivedData-simulator')),'-resultBundlePath',str(prefix.with_suffix('.xcresult')),'-disableAutomaticPackageResolution']
if args.action=='test':
    command+=['-parallel-testing-enabled','NO','-collect-test-diagnostics','never']
    command+=['-only-testing:'+item for item in args.only]
if args.ios: command+=['CODE_SIGNING_ALLOWED=NO']
command+=[args.action]
env=os.environ.copy()
if args.photos: env['TEST_RUNNER_FR_PHOTOS_INTEGRATION']=args.photos
else: env.pop('TEST_RUNNER_FR_PHOTOS_INTEGRATION',None)
record={'command':command,'cwd':str(repo),'extraEnvironment':({'TEST_RUNNER_FR_PHOTOS_INTEGRATION':args.photos} if args.photos else {}),'startedAt':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
before=snapshot()
for entry in before:
    dest=root/(args.run+'-source')/entry['path']
    dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(repo/entry['path'],dest)
prefix.with_suffix('.sources-before.json').write_text(json.dumps(before,indent=2)+'\n')
prefix.with_suffix('.command.json').write_text(json.dumps(record,indent=2)+'\n')
with prefix.with_suffix('.log').open('wb') as log:
    result=subprocess.run(command,cwd=repo,env=env,stdout=log,stderr=subprocess.STDOUT)
after=snapshot()
prefix.with_suffix('.sources-after.json').write_text(json.dumps(after,indent=2)+'\n')
record.update({'exitCode':result.returncode,'finishedAt':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'sourcesUnchanged':before==after,'sourceCount':len(before)})
prefix.with_suffix('.result.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({'run':args.run,'exitCode':result.returncode,'sourcesUnchanged':before==after,'sourceCount':len(before),'log':str(prefix.with_suffix('.log'))}),flush=True)
raise SystemExit(result.returncode)
