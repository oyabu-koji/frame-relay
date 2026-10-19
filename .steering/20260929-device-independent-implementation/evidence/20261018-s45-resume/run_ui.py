import pathlib,subprocess,json,hashlib,shutil,sys
work=pathlib.Path('/private/tmp/fr-s45-resume-20261018-1tlmtf7y')
root=pathlib.Path('/Users/oyabu/dev/rep/FrameRelay')
evidence=root/'.steering/20260929-device-independent-implementation/evidence/20261018-s45-resume'
simulator='DFE46693-E8DD-4814-8957-4F327699F719';app='com.oyabu.FrameRelay'
subprocess.run(['xcrun','simctl','terminate',simulator,app],capture_output=True)
container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',simulator,app,'data'],text=True).strip())
prefs=container/'Library/Application Support/FrameRelayLibrary/capture-preferences.json'
backup=work/'ui-preferences-before.json';existed=prefs.exists()
record={'preferenceExistedBefore':existed,'beforeSHA256':None,'restored':False}
if existed:
 shutil.copy2(prefs,backup);record['beforeSHA256']=hashlib.sha256(backup.read_bytes()).hexdigest();prefs.unlink()
try:
 result=subprocess.run([sys.executable,str(work/'run_check.py'),'ui-final-01','xcodebuild','-project','FrameRelay.xcodeproj','-scheme','FrameRelay','-configuration','Debug','-destination','platform=iOS Simulator,id='+simulator,'-derivedDataPath',str(work/'vision/DerivedData'),'-resultBundlePath',str(work/'ui-final-01.xcresult'),'-testPlan','FrameRelay','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-disableAutomaticPackageResolution','-only-testing:FrameRelayUITests/ProductCaptureFlowTests','test'],cwd=root)
finally:
 subprocess.run(['xcrun','simctl','terminate',simulator,app],capture_output=True)
 if existed:
  prefs.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(backup,prefs)
  record['restored']=hashlib.sha256(prefs.read_bytes()).hexdigest()==record['beforeSHA256']
 else:
  prefs.unlink(missing_ok=True);record['restored']=not prefs.exists()
 (evidence/'ui-preference-restoration.json').write_text(json.dumps(record,indent=2))
 print(json.dumps(record))
sys.exit(result.returncode)
