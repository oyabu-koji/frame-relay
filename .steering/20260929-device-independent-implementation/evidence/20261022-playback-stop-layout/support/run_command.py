import sys,os,pathlib,json,datetime,subprocess,hashlib
RUN=pathlib.Path(__file__).resolve().parent
ROOT=pathlib.Path('/Users/oyabu/dev/rep/FrameRelay')
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(name,value):(RUN/name).write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
def snapshot():
    prior=json.loads((ROOT/'.steering/20260929-device-independent-implementation/evidence/20261022-p2-ax-fixture/source-manifest.json').read_text())['files']
    return {rel:{**meta,'sha256':hashlib.sha256((ROOT/rel).read_bytes()).hexdigest(),'size':(ROOT/rel).stat().st_size} for rel,meta in prior.items()}
def run(name,argv,added_env=None,bind=False):
    added_env=added_env or {}
    if bind:save(name+'-sources-before.json',snapshot())
    save(name+'-command.json',{'command':argv,'cwd':str(ROOT),'started_at':now(),'test_environment':added_env})
    log=RUN/(name+'.log')
    with log.open('wb') as stream:
        result=subprocess.run(argv,cwd=ROOT,env={**os.environ,**added_env},stdout=stream,stderr=subprocess.STDOUT)
    after=snapshot() if bind else None
    if bind:save(name+'-sources-after.json',after)
    save(name+'-exit.json',{'exit_code':result.returncode,'finished_at':now(),'log':str(log),'source_mismatches':[p for p,v in after.items() if v!=json.loads((RUN/(name+'-sources-before.json')).read_text())[p]] if bind else []})
    print(json.dumps({'name':name,'exit_code':result.returncode,'log':str(log)}),flush=True)
    print('\n'.join(log.read_text(errors='replace').splitlines()[-12:]),flush=True)
    return result.returncode
if __name__=='__main__':
    args=sys.argv[1:];name=args.pop(0);added={}
    while args and args[0].startswith('TEST_RUNNER_'):
        k,v=args.pop(0).split('=',1);added[k]=v
    if args[0]=='--':args.pop(0)
    sys.exit(run(name,args,added,bind=args[0]=='xcodebuild' and any(x in args for x in ['build','test','build-for-testing','test-without-building'])))
