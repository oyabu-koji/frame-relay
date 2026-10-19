import sys, subprocess, pathlib, json, datetime, shlex, hashlib
out=pathlib.Path(__file__).parent
name=sys.argv[1]; command=sys.argv[2:]
sources={}
for folder in ('FrameRelay','FrameRelayTests','FrameRelayUITests','FrameRelay.xcodeproj'):
    for p in sorted(pathlib.Path(folder).rglob('*')):
        if p.is_file() and (p.suffix in ('.swift','.pbxproj','.xcscheme','.xctestplan','.plist') or p.name=='Package.resolved'):
            sources[str(p)]=hashlib.sha256(p.read_bytes()).hexdigest()
(out/(name+'-sources.json')).write_text(json.dumps(sources,indent=2)+'\n')
with (out/'commands.txt').open('a') as file:
    file.write('\n# '+name+'\n'+shlex.join(command)+'\n')
start=datetime.datetime.now(datetime.timezone.utc).isoformat()
with (out/(name+'.log')).open('wb') as logfile:
    result=subprocess.run(command,stdout=logfile,stderr=subprocess.STDOUT)
end=datetime.datetime.now(datetime.timezone.utc).isoformat()
report={'name':name,'command':command,'startedAt':start,'finishedAt':end,'exitCode':result.returncode,'log':str(out/(name+'.log')),'sourceCount':len(sources)}
(out/(name+'-run.json')).write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report),flush=True)
sys.exit(result.returncode)
