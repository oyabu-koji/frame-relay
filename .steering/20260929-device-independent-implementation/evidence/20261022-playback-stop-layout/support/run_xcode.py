import sys
from run_command import RUN,run
name=sys.argv[1]
kind=name.removesuffix('-04').removesuffix('-03').removesuffix('-final')
sim='664DEF26-9030-4889-9715-FED5B9E0D675'
base=['xcodebuild','-project','FrameRelay.xcodeproj','-scheme','FrameRelay','-configuration','Debug','-destination','platform=iOS Simulator,id='+sim,'-derivedDataPath',str(RUN/'DerivedData'),'-disableAutomaticPackageResolution']
env={'TEST_RUNNER_FR_LIBRARY_SEED':'0','TEST_RUNNER_FR_LIBRARY_VERIFY':'0'}
if kind=='enumeration':
    argv=base+['test','-enumerate-tests','-test-enumeration-style','hierarchical','-test-enumeration-format','json','-test-enumeration-output-path',str(RUN/'enumeration.json')]
elif kind=='build-ios':
    argv=['xcodebuild','-project','FrameRelay.xcodeproj','-scheme','FrameRelay','-configuration','Debug','-destination','generic/platform=iOS','-derivedDataPath',str(RUN/'DerivedDataIOS'),'-disableAutomaticPackageResolution','-resultBundlePath',str(RUN/(name+'.xcresult')),'CODE_SIGNING_ALLOWED=NO','build']
else:
    tests=[]
    if name=='fresh-seed':
        tests=['FrameRelayTests/ProductLibrarySeedTests'];env['TEST_RUNNER_FR_LIBRARY_SEED']='1'
    elif kind=='unit':
        tests=['FrameRelayTests/OriginalPlaybackTests','FrameRelayTests/ProductCompositionTests','FrameRelayTests/ProductCaptureSavePlaybackTests']
    elif name in ['ui-max-audit-03','ui-max-audit-04']:tests=['FrameRelayUITests/LibraryFlowTests/testAccessibilityStoppedPlayer']
    elif name in ['ui-max-flow-03','ui-max-flow-04']:tests=['FrameRelayUITests/LibraryFlowTests/testOriginalPlaybackProgressStopBackgroundAndRestart']
    elif name in ['ui-normal-03','ui-normal-04']:tests=['FrameRelayUITests/LibraryFlowTests/testAccessibilityStoppedPlayer','FrameRelayUITests/LibraryFlowTests/testOriginalPlaybackProgressStopBackgroundAndRestart','FrameRelayUITests/LibraryFlowTests/testAccessibilityHistoryAfterPlaybackHandoff']
    elif name=='ui-normal-final':tests=['FrameRelayUITests/LibraryFlowTests/testOriginalPlaybackProgressStopBackgroundAndRestart','FrameRelayUITests/LibraryFlowTests/testAccessibilityStoppedPlayer']
    elif name=='ui-normal':tests=['FrameRelayUITests/LibraryFlowTests']
    elif name=='ui-max':
        tests=['FrameRelayUITests/LibraryFlowTests/'+x for x in ['testOriginalPlaybackProgressStopBackgroundAndRestart','testAccessibilityStoppedPlayer','testHistoryAndSubmissionTextLayoutAtCurrentContentSize','testListDetailSelectionHistoryAndRetainedStateAfterRelaunch','testVoiceOverReadsHistoryAndPlaybackSubmission']]
    elif name=='post-ui':
        tests=['FrameRelayTests/ProductLibrarySeedTests'];env['TEST_RUNNER_FR_LIBRARY_VERIFY']='1'
    else:raise SystemExit('unknown run')
    argv=base+['-resultBundlePath',str(RUN/(name+'.xcresult')),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never']+['-only-testing:'+x for x in tests]+['test']
sys.exit(run(name,argv,env,bind=True))
