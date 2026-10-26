import errno
import json
from pathlib import Path
import socket
import time
from uuid import uuid4

root = Path(__file__).resolve().parent
output = root / 'refused-port-reservation-001'
output.mkdir(exist_ok=False)
identity = str(uuid4())
started = time.monotonic()
reservation_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    reservation_socket.bind(('127.0.0.1', 0))
    address, port = reservation_socket.getsockname()
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as check_socket:
        check_socket.settimeout(1)
        outcome = check_socket.connect_ex((address, port))
    if outcome != errno.ECONNREFUSED:
        raise RuntimeError('The bound but non-listening endpoint was not refused')
    context = {'run_identity': identity, 'origin': f'https://127.0.0.1:{port}',
               'address': address, 'port': port, 'listening': False,
               'connect_ex': outcome, 'expected_errno': errno.ECONNREFUSED,
               'deadline_seconds': 1200, 'deadline_monotonic': started + 1200}
    (output / 'ready.json').write_text(json.dumps(context, indent=2) + '\n')
    print(json.dumps({'ready': True, 'origin': context['origin'], 'listening': False}), flush=True)
    reason = 'deadline'
    while time.monotonic() < started + 1200:
        stop = output / 'stop.json'
        if stop.exists():
            if json.loads(stop.read_text()) != {'run_identity': identity}:
                raise RuntimeError('Unbound stop request')
            reason = 'reviewed-stop'
            break
        time.sleep(0.2)
finally:
    reservation_socket.close()
result = {'run_identity': identity, 'stop_reason': reason,
          'fd_closed': reservation_socket.fileno() == -1,
          'elapsed_seconds': time.monotonic() - started,
          'passed': reason == 'reviewed-stop' and reservation_socket.fileno() == -1}
(output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result), flush=True)
raise SystemExit(0 if result['passed'] else 1)
