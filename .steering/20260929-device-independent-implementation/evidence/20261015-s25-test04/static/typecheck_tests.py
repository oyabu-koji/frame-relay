import json
from pathlib import Path
import subprocess

root = Path('/private/tmp/s25-cache-static')
command = [
    'xcrun', 'swiftc', '-typecheck', '-swift-version', '5', '-D', 'DEBUG',
    '-module-name', 'FrameRelayTests', '-target', 'arm64-apple-ios27.0-simulator',
    '-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.0.sdk',
    '-I', '/private/tmp/fr-di-20261014-s25/DerivedData/Build/Products/Debug-iphonesimulator',
    '-module-cache-path', '/private/tmp/s25-swift-module-cache',
]
command += [str(root / name) for name in ['FixedRenditionHTTPClient.swift', 'FixedRenditionRangeReader.swift',
    'ManagedTemporaryMedia.swift', 'TemporaryRenditionReader.swift', 'UsageValues.swift', 'AVRenditionPlayback.swift']]
command += subprocess.check_output(['rg', '--files', 'FrameRelayTests', '-g', '*.swift'], text=True).splitlines()
result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(root / 'tests-typecheck.log').write_text(result.stdout)
(root / 'tests-typecheck-result.json').write_text(json.dumps({'command': command, 'exit_code': result.returncode,
    'output_path': str(root / 'tests-typecheck.log'), 'scope': 'Static typecheck only; no test execution.'}, indent=2))
print(result.stdout[-18000:])
raise SystemExit(result.returncode)
