from pathlib import Path
import hashlib,json,plistlib,subprocess
from datetime import datetime,timezone
r=Path(__file__).resolve().parent
repo=Path('/Users/oyabu/dev/rep/FrameRelay');e=repo/'.steering/20260929-device-independent-implementation/evidence/20261023-remote-inventory'
ours={'cleanup':'FC6EF960-EEC5-4592-BC4B-DD4FFD767B93','regression':'DB985305-B55C-4694-8307-77E3BFD2E11D','new_registration':'5B5BD239-98C0-44E9-9EF3-29EB1B9A4EE5','inventory':'FCEE8D70-F5E1-4566-91CE-2BFE917582DE','initial':'9E28C477-2751-4F60-85CC-BD3529B0BE34'}
def devices():
 d=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','--json'],text=True));return {x['udid']:x for group in d['devices'].values() for x in group}
current=devices();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
expected={'cleanup':{'relative_manifest':'Library/Application Support/FrameRelayLibrary/s34-cleanup-seed.json','manifest_sha256':'da073409c87e284888cc8335a10772d77321c124f8d5d2259e1d767b8744fba6','movies':json.loads((r/'cleanup-fixture-preservation.json').read_text())['after_managed_movies']},'regression':json.loads((r/'regression-max-64-fixture-after.json').read_text()),'new_registration':json.loads((r/'new-registration-post-60-fixture.json').read_text()),'inventory':json.loads((r/'inventory-fixture-before.json').read_text())}
result={}
for role,u in ours.items():
 probe=subprocess.run(['xcrun','simctl','get_app_container',u,'com.oyabu.FrameRelay','data'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 if probe.returncode==0:container=Path(probe.stdout.strip());method='simctl'
 else:
  matches=[f.parent for f in (Path(current[u]['dataPath'])/'Containers/Data/Application').glob('*/.com.apple.mobile_container_manager.metadata.plist') if plistlib.loads(f.read_bytes()).get('MCMMetadataIdentifier')=='com.oyabu.FrameRelay'];assert len(matches)==1,(role,matches);container=matches[0];method='read-only own-device MCM metadata'
 movies={str(p.relative_to(container)):{'sha256':sha(p),'bytes':p.stat().st_size} for p in (container/'Library/Application Support').rglob('*.mov')}
 item={'simulator':u,'container':str(container),'lookup':method,'managed_movies':movies,'scope':'Application Support only; disposable Unit tmp excluded'}
 if role=='initial':assert not movies
 else:
  exp=expected[role];p=container/exp['relative_manifest'];item.update({'relative_manifest':exp['relative_manifest'],'manifest_sha256':sha(p),'manifest_unchanged':sha(p)==exp['manifest_sha256']});exp_movies=exp['movies'] or {};assert movies==exp_movies,(role,movies,exp_movies);assert item['manifest_unchanged'];item['managed_movies_unchanged']=True
 result[role]=item
 if current[u]['state']=='Booted':
  subprocess.run(['xcrun','simctl','ui',u,'content_size','large'],check=True);assert subprocess.check_output(['xcrun','simctl','ui',u,'content_size'],text=True).strip()=='large';subprocess.run(['xcrun','simctl','shutdown',u],check=True)
now=devices();d=json.loads((r/'devices.txt').read_text());old={x['udid']:x for group in d['devices'].values() for x in group};changed={k:{'before':v['state'],'after':now.get(k,{}).get('state')} for k,v in old.items() if now.get(k,{}).get('state')!=v['state']};assert not changed,changed;assert all(now[u]['state']=='Shutdown' for u in ours.values())
size={}
for role,u in ours.items():
 q=subprocess.run(['xcrun','simctl','ui',u,'content_size'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 if q.returncode==0 and q.stdout.strip()!='unknown':assert q.stdout.strip()=='large';size[role]={'observed_after_shutdown':q.stdout.strip()}
 else:size[role]={'after_shutdown_query':q.stdout.strip() or 'unavailable','last_successful_large_restore':'recorded in final harness/explicit simctl command before shutdown; unknown on shutdown is not a category measurement'}
output={'created_UTC':datetime.now(timezone.utc).isoformat(),'fixtures':result,'owned_devices':ours,'owned_states':{k:now[u]['state'] for k,u in ours.items()},'content_size':size,'preexisting_devices':len(old),'preexisting_state_changes':changed,'logical_and_Keychain_verification':{'cleanup':'66 passed1/seedSkip1','regression':'65 passed2/seedSkip1','new_registration':'60 passed1/seedSkip1','inventory':'51 passed1/seedSkip1'},'limits':'synthetic own roots; no device/quality acceptance; no old root repair/reseed or Photos asset deletion'}
(e/'final-fixture-simulator-preservation.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n');(r/'final-fixture-simulator-preservation-67.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'owned_shutdown':len(ours),'preexisting_state_changes':changed,'managed_movie_counts':{k:len(v['managed_movies']) for k,v in result.items()},'all_manifest_and_movies_preserved':True,'content_size':size},ensure_ascii=False))
