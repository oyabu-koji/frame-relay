"""Request normal stop by nonce+own listener PID; never signal/kill any PID.

Main must separately observe the original foreground listener process exit.
This command can stop a failed run too: failed client/listener results remain
failed. Rescue close, signal, deadline or forced cancellation never count pass.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys


def common():
    spec = importlib.util.spec_from_file_location('metadata_common', Path(__file__).with_name('metadata_common.py'))
    value = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = value
    spec.loader.exec_module(value)
    return value


helpers = common()


def main():
    helpers.require_runtime()
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepared', type=Path, required=True)
    parser.add_argument('--listener-pid', type=int, required=True)
    args = parser.parse_args()
    config, _checkpoint, _provenance = helpers.verified(args.prepared)
    if Path(__file__).resolve().parent != Path(config['preparation']) / 'source':
        raise RuntimeError('Use immutable prepared stop helper')
    ready = helpers.checked_ready(config)
    if args.listener_pid != ready['pid']:
        raise RuntimeError('Only this exact newly launched listener may be stopped')
    helpers.write_json(Path(config['runtime']) / 'stop.request', {'nonce': config['nonce'],
        'listener_pid': args.listener_pid, 'requester_pid': os.getpid(), 'reason': 'reviewed-main-stop'}, private=True)
    print(json.dumps({'stop_requested': True, 'listener_pid': args.listener_pid, 'nonce': config['nonce'],
        'signal_sent': False, 'process_exit_observed': False}))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'stop_requested': False, 'failure_type': type(error).__name__}))
        raise SystemExit(70) from None
