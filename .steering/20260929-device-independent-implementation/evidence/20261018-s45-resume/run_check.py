import pathlib,subprocess,json,hashlib,datetime,sys,shutil
root=pathlib.Path('/Users/oyabu/dev/rep/FrameRelay')
work=pathlib.Path('/private/tmp/fr-s45-resume-20261018-1tlmtf7y')
evidence=root/'.steering/20260929-device-independent-implementation/evidence/20261018-s45-resume'
name=sys.argv[1]; command=sys.argv[2:]
def sources():
 result={}
 for folder in ['FrameRelay','FrameRelayTests','FrameRelayUITests','FrameRelay.xcodeproj']:
  for p in (root/folder).rglob('*'):
   if p.is_file() and p.suffix in ['.swift','.pbxproj','.xcscheme','.xctestplan','.jpg','.json']:
    result[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
 return result
before=sources(); started=datetime.datetime.now(datetime.timezone.utc).isoformat()
(evidence/(name+'-sources.json')).write_text(json.dumps(before,indent=2))
with (work/(name+'.log')).open('w') as log:
 result=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT)
after=sources()
record={'command':command,'startedAt':started,'finishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exitCode':result.returncode,'sourceCount':len(before),'sourceChanges':[p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)],'log':str(work/(name+'.log'))}
(evidence/(name+'-run.json')).write_text(json.dumps(record,indent=2));shutil.copy2(work/(name+'.log'),evidence/(name+'.log'))
print(json.dumps(record))
for i,x in enumerate(command):
 if x=='-resultBundlePath' and pathlib.Path(command[i+1]).exists():
  for query in [['test-results','summary'],['test-results','tests']]:
   run=subprocess.run(['xcrun','xcresulttool','get']+query+['--path',command[i+1]],capture_output=True,text=True)
   if run.returncode==0:
    (evidence/(name+'-'+query[-1]+'.json')).write_text(run.stdout)
    if query[-1]=='summary': print(run.stdout)
sys.exit(result.returncode)
