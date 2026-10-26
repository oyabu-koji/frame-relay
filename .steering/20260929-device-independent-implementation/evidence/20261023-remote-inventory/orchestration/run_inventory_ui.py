import argparse
from datetime import datetime, timezone
import errno
import json
from pathlib import Path
import re
import socket
import subprocess
import sys
from urllib.parse import urlsplit

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('name')
parser.add_argument('--content-size', choices=['large', 'accessibility-extra-extra-extra-large'], default='large')
args = parser.parse_args()
assert re.fullmatch(r'[a-z][a-z0-9-]+', args.name)
context = json.loads((root / 'inventory-context.json').read_text())
origin = urlsplit(context['refused_origin'])
assert origin.scheme == 'https' and origin.hostname == '127.0.0.1' and origin.port is not None
device = context['simulator']
assert device == 'FCEE8D70-F5E1-4566-91CE-2BFE917582DE'

def dump(name, value):
    (root / name).write_text(json.dumps(value, indent=2) + '\n')

def refused(phase):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(2)
        result = probe.connect_ex((origin.hostname, origin.port))
    dump(args.name + '-refusal-' + phase + '.json',
         {'origin': context['refused_origin'], 'checked_at': datetime.now(timezone.utc).isoformat(),
          'connect_ex': result, 'errno_name': errno.errorcode.get(result)})
    return result == errno.ECONNREFUSED

subprocess.run(['xcrun', 'simctl', 'ui', device, 'content_size', args.content_size], check=True)
observed = subprocess.check_output(['xcrun', 'simctl', 'ui', device, 'content_size'], text=True).strip()
assert observed == args.content_size
dump(args.name + '-conditions.json', {'content_size': observed, 'simulator': device, 'refused_origin': context['refused_origin']})
assert refused('before')
command = [sys.executable, str(root / 'run_check.py'), args.name, '--simulator', device,
           '--only', 'FrameRelayUITests/RemoteInventoryFlowTests/testRemoteCatalogConflictFailedMetadataRefreshAndRelaunch']
flags = {'FR_S28_INVENTORY_UI': '1', 'FR_S28_INVENTORY_NONCE': context['nonce'],
         'FR_S28_INVENTORY_SIMULATOR_UDID': device}
for key, value in flags.items():
    command += ['--env', 'TEST_RUNNER_' + key + '=' + value]
try:
    code = subprocess.call(command)
    after_refused = refused('after')
finally:
    subprocess.run(['xcrun', 'simctl', 'ui', device, 'content_size', 'large'], check=True)
raise SystemExit(code or (0 if after_refused else 1))
