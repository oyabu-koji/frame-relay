import argparse
import json
from pathlib import Path
import shutil
root = Path(__file__).resolve().parent
repo = Path('/Users/oyabu/dev/rep/FrameRelay')
p = argparse.ArgumentParser();p.add_argument('stage',choices=['new-registration','remote-inventory']);p.add_argument('name');a=p.parse_args()
src = root/a.name
result = json.loads((src/'result.json').read_text())
dst = repo/'.steering/20260929-device-independent-implementation/evidence'/('20261023-'+a.stage)/'runs'/a.name
dst.mkdir(parents=True,exist_ok=True)
for f in src.iterdir():
 if f.is_file():shutil.copy2(f,dst/f.name)
for f in root.glob(a.name+'-*.json'):shutil.copy2(f,dst/f.name)
print(json.dumps({'name':a.name,'exit_code':result['exit_code'],'sources_unchanged':result['sources_unchanged'],'source_files':result['source_files'],'declared':result.get('tests',{}).get('totalTestCount'),'passed':result.get('tests',{}).get('passedTests'),'failed':result.get('tests',{}).get('failedTests'),'skipped':result.get('tests',{}).get('skippedTests'),'expanded':result.get('counts',{}).get('expanded'),'diagnostics':{k:result.get('build',{}).get(k) for k in ['errorCount','warningCount','analyzerWarningCount']},'runtimeWarnings':result.get('tests',{}).get('runtimeWarnings')},ensure_ascii=False))
