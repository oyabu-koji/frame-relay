"""Main-only client runner: secrets inherited via TEST_RUNNER_ environment.

No bearer/secret in argv or run_check --env/environment_overrides. Xcode may
still retain disposable runner environment in its raw artifacts; see README.
This script does not launch or kill the server. It invokes only reviewed
run_check.py, which owns actual xcodebuild and result extraction.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def common():
    spec = importlib.util.spec_from_file_location('metadata_common', Path(__file__).with_name('metadata_common.py'))
    value = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = value
    spec.loader.exec_module(value)
    return value


helpers = common()


def evaluate(run, config, mode, exit_code):
    result = helpers.read_json(run / 'result.json')
    summary = helpers.read_json(run / 'tests.json')
    tree = helpers.read_json(run / 'tree.json')
    build = helpers.read_json(run / 'build.json')
    command = helpers.read_json(run / 'command.json')
    cases = []

    def visit(node):
        if node.get('nodeType') == 'Test Case':
            cases.append(node)
        for child in node.get('children', []):
            visit(child)
    for node in tree.get('testNodes', []):
        visit(node)
    selector = config['normal_selector' if mode == 'normal' else 'fault_selector']
    identifier = selector.removeprefix('FrameRelayTests/')
    arguments = [child for case in cases for child in case.get('children', []) if child.get('nodeType') == 'Arguments']
    expected_args = {'"redirect"', '"oversize"', '"wrong-mime"', '"cancel"'}
    executions = 1 if mode == 'normal' else 4
    devices = summary.get('devicesAndConfigurations', [])
    expected_summary = {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
    command_args = command.get('command', [])
    return {'passed': (exit_code == 0 and result.get('exit_code') == 0 and result.get('sources_unchanged') is True and
        result.get('environment_overrides') == {} and command.get('environment_overrides') == {} and
        command.get('cwd') == config['repository'] and '-only-testing:' + selector in command_args and
        len([arg for arg in command_args if arg.startswith('-only-testing:')]) == 1 and
        summary.get('result') == 'Passed' and all(type(summary.get(key)) is int and summary[key] == value for key, value in expected_summary.items()) and
        len(cases) == 1 and cases[0].get('nodeIdentifier') == identifier and cases[0].get('result') == 'Passed' and
        ((mode == 'normal' and not arguments) or (mode == 'fault' and len(arguments) == 4 and
            {arg.get('name') for arg in arguments} == expected_args and all(arg.get('result') == 'Passed' for arg in arguments))) and
        len(devices) == 1 and devices[0].get('device', {}).get('deviceId') == config['simulator'] and
        devices[0].get('passedTests') == executions and devices[0].get('failedTests') == 0 and devices[0].get('skippedTests') == 0 and
        not summary.get('runtimeWarnings') and not summary.get('testFailures') and
        build.get('status') == 'succeeded' and all(build.get(key) == 0 for key in ('errorCount', 'warningCount', 'analyzerWarningCount'))),
        'declarations': [case.get('nodeIdentifier') for case in cases], 'argument_names': [arg.get('name') for arg in arguments],
        'expected_executions': executions, 'run_check_exit_code': exit_code,
        'source_fingerprint': result.get('source_fingerprint'), 'sources_unchanged': result.get('sources_unchanged'),
        'result_record': helpers.record(run / 'result.json'), 'command_record': helpers.record(run / 'command.json'),
        'meaning': 'Raw xcresult Passed plus exact selector/arguments, native client assertions, immutable inputs and zero diagnostics; server separately verifies request counts/DB/terminal state.'}


def main():
    helpers.require_runtime()
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepared', type=Path, required=True)
    parser.add_argument('--mode', choices=('normal', 'fault'), required=True)
    parser.add_argument('--name', required=True)
    args = parser.parse_args()
    config, _checkpoint, _provenance = helpers.verified(args.prepared)
    if Path(__file__).resolve().parent != Path(config['preparation']) / 'source':
        raise RuntimeError('Use immutable prepared runner')
    if re.fullmatch(r'upload-metadata-http-(normal|fault)-[0-9]{3}', args.name) is None or not args.name.startswith('upload-metadata-http-' + args.mode + '-'):
        raise RuntimeError('Use fresh explicit metadata HTTP run name')
    runtime = Path(config['runtime'])
    ready = helpers.checked_ready(config)
    secret_path = runtime / 'client-env.json'
    private = helpers.read_json(secret_path, private=True)
    if (set(private) != {'nonce', 'listener_pid', 'origin', 'normal', 'fault'} or private['nonce'] != config['nonce'] or
            private['listener_pid'] != ready['pid'] or private['origin'] != ready['origin']):
        raise RuntimeError('Disposable client environment identity mismatch')
    values = private[args.mode]
    common_keys = {'FR_UPLOAD_METADATA_HTTP', 'FR_UPLOAD_METADATA_HTTP_FAULT'}
    required = common_keys | ({'FR_UPLOAD_METADATA_HTTP_' + key for key in ('NONCE', 'NEW_ISOLATED', 'ORIGIN', 'DESTINATION',
        'REGISTRATION', 'GENERATION', 'BEARER', 'SECRET')} if args.mode == 'normal' else
        {'FR_UPLOAD_METADATA_HTTP_FAULT_' + key for key in ('NONCE', 'NEW_ISOLATED', 'ORIGIN')})
    prefix = 'FR_UPLOAD_METADATA_HTTP_' if args.mode == 'normal' else 'FR_UPLOAD_METADATA_HTTP_FAULT_'
    if (set(values) != required or not all(isinstance(value, str) and value for value in values.values()) or
            values[prefix + 'NONCE'] != config['nonce'] or values[prefix + 'ORIGIN'] != ready['origin'] or
            values[prefix + 'NEW_ISOLATED'] != '1' or values['FR_UPLOAD_METADATA_HTTP'] != ('1' if args.mode == 'normal' else '0') or
            values['FR_UPLOAD_METADATA_HTTP_FAULT'] != ('1' if args.mode == 'fault' else '0')):
        raise RuntimeError('Unreviewed client environment shape')
    if args.mode == 'normal' and (not helpers.canonical_id(values[prefix + 'DESTINATION']) or
            not helpers.canonical_id(values[prefix + 'REGISTRATION']) or values[prefix + 'GENERATION'] != '1' or
            re.fullmatch(r'[0-9a-f]{64}', values[prefix + 'SECRET']) is None):
        raise RuntimeError('Unreviewed disposable registration/secret shape')
    run = Path(config['run_check']).parent / args.name
    if run.exists() or run.is_symlink():
        raise RuntimeError('Never overwrite an existing run')
    # Single launch per mode/root. A failure is retained, never repaired/reseeded.
    helpers.write_json(runtime / ('client-' + args.mode + '.claimed.json'), {'nonce': config['nonce'], 'mode': args.mode,
        'run': str(run), 'listener_pid': ready['pid'], 'runner_pid': os.getpid()})
    environment = {key: value for key, value in os.environ.items() if not (
        key.startswith('TEST_RUNNER_FR_UPLOAD_METADATA_HTTP') or key.startswith('FR_UPLOAD_METADATA_HTTP'))}
    environment.update({'TEST_RUNNER_' + key: value for key, value in values.items()})
    home_before = os.environ.get('HOME')
    if environment.get('HOME') != home_before:
        raise RuntimeError('HOME must be inherited unchanged')
    selector = config['normal_selector' if args.mode == 'normal' else 'fault_selector']
    command = [config['interpreter'], '-I', '-B', '-S', config['run_check'], args.name,
        '--repository-directory', config['repository'], '--simulator', config['simulator'],
        '--derived-directory', config['derived_directory'], '--only', selector]
    # Environment is deliberately not serialized here or passed as --env args.
    process = subprocess.run(command, env=environment, check=False)
    values.clear()
    private.clear()
    environment.clear()
    evaluation = {'passed': False, 'run_check_exit_code': process.returncode}
    try:
        evaluation = evaluate(run, config, args.mode, process.returncode)
        helpers.verified(args.prepared)
        evaluation['inputs_unchanged'] = True
    except BaseException as error:
        evaluation['failure_type'] = type(error).__name__
        evaluation['passed'] = False
    evaluation.update({'nonce': config['nonce'], 'mode': args.mode, 'run': str(run), 'listener_pid': ready['pid'],
        'secret_transport': 'inherited TEST_RUNNER_ environment only; no --env or argv secret',
        'security_limit': 'Xcode raw artifacts may contain disposable environment; listener termination invalidates token. No user Keychain access.'})
    helpers.write_json(runtime / ('client-' + args.mode + '-result.json'), evaluation)
    print(json.dumps({'mode': args.mode, 'passed': evaluation['passed'], 'run': str(run),
        'run_check_exit_code': process.returncode, 'secrets_printed': False}))
    return 0 if evaluation['passed'] else 70


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'passed': False, 'failure_type': type(error).__name__}))
        raise SystemExit(70) from None
