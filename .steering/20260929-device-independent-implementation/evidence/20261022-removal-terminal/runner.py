import json,os,subprocess,sys,time,hashlib
from pathlib import Path
root=Path(__file__).parent
label=sys.argv[1]
spec=json.loads((root/(label+'-spec.json')).read_text())
paths=subprocess.check_output(['git','ls-files','-c','-o','--exclude-standard','-z']).split(b'\0')
def inputs():
    out={}
    for raw in paths:
        if not raw:continue
        name=raw.decode();p=Path(name)
        if name.startswith(('FrameRelay/','FrameRelayTests/','FrameRelayUITests/','FrameRelay.xcodeproj/')) and p.is_file():out[name]=hashlib.sha256(p.read_bytes()).hexdigest()
    return out
before=inputs();(root/(label+'-inputs-before.json')).write_text(json.dumps(before,indent=2)+'\n')
command=spec['command'];env=dict(os.environ);env.update(spec.get('environment',{}))
(root/(label+'-command.json')).write_text(json.dumps({'command':command,'added_environment':spec.get('environment',{}),'started_at':time.time()},indent=2)+'\n')
with (root/(label+'.log')).open('w') as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,env=env)
after=inputs();(root/(label+'-inputs-after.json')).write_text(json.dumps(after,indent=2)+'\n')
result={'exit_code':r.returncode,'ended_at':time.time(),'input_count':len(before),'input_changes':[p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)]}
(root/(label+'-result.json')).write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'label':label,**result}),flush=True)
lines=(root/(label+'.log')).read_text(errors='replace').splitlines()
interesting=[l for l in lines if '** BUILD ' in l or '** TEST ' in l or 'Test Case ' in l or '✔ Test run' in l or 'error:' in l or 'warning:' in l]
print('\n'.join(interesting)[-8000:])
