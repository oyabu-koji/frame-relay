import sys,pathlib,subprocess,json,collections
RUN=pathlib.Path(__file__).resolve().parent
for name in sys.argv[1:]:
    bundle=RUN/(name+'.xcresult')
    kinds=[['build-results']] if name.startswith('build-ios') else [['test-results','summary'],['build-results'],['test-results','tests']]
    for kind in kinds:
        result=subprocess.run(['xcrun','xcresulttool','get',*kind,'--path',str(bundle)],capture_output=True,text=True)
        if result.returncode:raise SystemExit(result.stderr)
        parsed=json.loads(result.stdout)
        (RUN/(name+'-'+'-'.join(kind)+'.json')).write_text(json.dumps(parsed,ensure_ascii=False,indent=2)+'\n')
        if kind[-1]=='tests':
            leaves=[]
            def walk(n):
                if n.get('nodeType')=='Test Case':
                    args=[c for c in n.get('children',[]) if c.get('nodeType')=='Arguments']
                    leaves.extend(args or [n]);return
                for c in n.get('children',[]):walk(c)
            for n in parsed['testNodes']:walk(n)
            metrics={'expanded':dict(collections.Counter(n['result'] for n in leaves)),'leaves':leaves}
            (RUN/(name+'-metrics.json')).write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+'\n')
            print(name,'expanded',metrics['expanded'])
        else:print(name,'-'.join(kind),{k:parsed[k] for k in ['result','totalTestCount','passedTests','failedTests','skippedTests','status','errorCount','warningCount','analyzerWarningCount','runtimeWarnings'] if k in parsed})
