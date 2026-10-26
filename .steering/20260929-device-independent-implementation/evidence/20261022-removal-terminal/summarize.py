import collections,json,subprocess,sys
from pathlib import Path
root=Path(__file__).parent
for label in sys.argv[1:]:
    values={}
    for name,args in [('summary',['get','test-results','summary']),('tests',['get','test-results','tests']),('build',['get','build-results'])]:
        command=['xcrun','xcresulttool',*args,'--path',str(root/(label+'.xcresult'))]
        result=subprocess.run(command,capture_output=True,text=True)
        (root/(label+'-'+name+'.json')).write_text(result.stdout)
        (root/(label+'-'+name+'.stderr.log')).write_text(result.stderr)
        if result.returncode==0: values[name]=json.loads(result.stdout)
    expanded=collections.Counter()
    def walk(node):
        children=node.get('children',[])
        if node.get('nodeType')=='Arguments' or (node.get('nodeType')=='Test Case' and not any(c.get('nodeType')=='Arguments' for c in children)):
            if node.get('result'):expanded[node['result']]+=1
        for child in children:walk(child)
    for node in values.get('tests',{}).get('testNodes',[]):walk(node)
    summary=values.get('summary',{});build=values.get('build',{})
    report={'label':label,'declarations':{k:summary.get(k) for k in ('totalTestCount','passedTests','failedTests','skippedTests','expectedFailures')},'expanded':dict(expanded),'runtime_warnings':len(summary.get('runtimeWarnings',[])),'build':{k:build.get(k) for k in ('status','errorCount','warningCount','analyzerWarningCount')},'compiler_errors':[e for e in build.get('errors',[]) if 'Compiler' in e.get('issueType','')],'compiler_warnings':[e for e in build.get('warnings',[]) if 'Compiler' in e.get('issueType','')]}
    (root/(label+'-metrics.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False))
