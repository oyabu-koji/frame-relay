"""Prepare a new immutable backend/source copy. Does not import/run backend.

Main executes this only after reviewing the template and harness source.
Never reads external repository source, .env, DB or media. The only external
inputs are the explicitly pinned read-only Python interpreter/dependency tree.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys


def common():
    spec = importlib.util.spec_from_file_location('metadata_common', Path(__file__).with_name('metadata_common.py'))
    value = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = value
    spec.loader.exec_module(value)
    return value


def safe_copy(source, destination):
    before = helpers.record(source)
    data = Path(source).read_bytes()
    fd = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o444)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data)
    if helpers.record(destination) != before or helpers.record(source) != before:
        raise RuntimeError('Copy source changed')


def main():
    helpers.require_runtime()
    parser = argparse.ArgumentParser()
    parser.add_argument('--template', type=Path, required=True)
    args = parser.parse_args()
    template = helpers.owned(args.template, strict=True)
    config = helpers.read_json(template)
    if set(config) != {'nonce', 'backend_config', 'dependency_provenance', 'base_backend', 'overlay',
                       'repository', 'simulator', 'run_check', 'derived_directory', 'deadline_seconds'}:
        raise RuntimeError('Unreviewed template shape')
    nonce = helpers.checked_id(config['nonce'])
    simulator = config['simulator']
    if not isinstance(simulator, str) or re.fullmatch(r'[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}', simulator) is None:
        raise RuntimeError('Require exact main-owned dedicated simulator UUID')
    if not simulator.startswith('0B'):
        raise RuntimeError('This preparation is allocated only to the new metadata 0B simulator')
    if config['derived_directory'] != 'DerivedData-metadata-app' or config['deadline_seconds'] != 1800:
        raise RuntimeError('Unexpected reviewed DerivedData or listener deadline')
    root = helpers.OWNED.resolve(strict=True)
    preparation, runtime = root / ('prepared-' + nonce), root / ('runtime-' + nonce)
    if preparation.exists() or runtime.exists() or preparation.is_symlink() or runtime.is_symlink():
        raise RuntimeError('No reuse, repair, reseed or restart of an old harness root')
    base, overlay = Path(config['base_backend']).resolve(strict=True), Path(config['overlay']).resolve(strict=True)
    repository = Path(config['repository']).resolve(strict=True)
    # Paths are reviewed repository evidence/support, not latest_template source.
    project = Path('/Users/oyabu/dev/rep/FrameRelay').resolve(strict=True)
    evidence = project / '.steering/20260929-device-independent-implementation/evidence/20261024-publication-operations/http-003'
    expected_overlay = project / '.steering/20260929-device-independent-implementation/support/server-implementation/backend-overlay'
    if base != evidence / 'backend-snapshot-003/backend' or overlay != expected_overlay:
        raise RuntimeError('Require reviewed archived backend plus current committed overlay paths')
    if Path(config['backend_config']).resolve(strict=True) != evidence / 'preparation/backend-config.json':
        raise RuntimeError('Unexpected dependency path config')
    if Path(config['dependency_provenance']).resolve(strict=True) != evidence / 'preparation/dependency-provenance.json':
        raise RuntimeError('Unexpected archived dependency provenance')
    backend_config = helpers.read_json(config['backend_config'])
    # Ignore every old runtime/external_root/provenance/source path in that file.
    interpreter, site = backend_config['interpreter'], backend_config['site_packages']
    if (interpreter != '/Users/oyabu/dev/rep/latest_template/backend/.venv/bin/python' or
            site != '/Users/oyabu/dev/rep/latest_template/backend/.venv/lib/python3.12/site-packages'):
        raise RuntimeError('Unreviewed interpreter/dependency paths')
    old = helpers.read_json(config['dependency_provenance'])
    dependency_keys = ('site_packages_root', 'site_packages_before', 'interpreter', 'pyvenv_cfg', 'pth')
    provenance = {key: old[key] for key in dependency_keys}
    if (provenance['site_packages_root'] != site or provenance['interpreter']['entry'] != interpreter or
            Path(sys.executable).resolve(strict=True) != Path(interpreter).resolve(strict=True)):
        raise RuntimeError('Pinned Python origin mismatch')
    helpers.dependencies(provenance)
    if (repository == project or not (repository.is_relative_to(root.parent) or repository ==
            project / '.steering/20260929-device-independent-implementation/evidence/20261024-publication-operations/stages/upload-metadata-candidate-03/source-snapshot') or
            not (repository / 'FrameRelay.xcodeproj/project.pbxproj').is_file()):
        raise RuntimeError('Use main-reviewed immutable app candidate copy in this raw session, never live workspace')
    run_check = Path(config['run_check']).resolve(strict=True)
    if run_check != root.parent / 'run_check.py':
        raise RuntimeError('Use this session reviewed existing run_check.py')
    app = helpers.app_sources(repository)
    wire_source = repository / 'FrameRelayTests/Integration/Remote/UploadMetadataRemoteTests.swift'
    source = wire_source.read_text()
    for expression in ('func isolatedActualHTTPCreateAndPausedCancelledKnownSessionGETOnly()',
                       'func isolatedNativeHTTPRefusalBoundsCancellationAndActualTerminals(fault: String)',
                       'metadata-http-', 'FR_UPLOAD_METADATA_HTTP_FAULT_',
                       'X-FrameRelay-Probe-Nonce'):
        if expression not in source:
            raise RuntimeError('Actual Swift HTTP test contract changed')
    source_root = Path(__file__).resolve().parent
    source_before = {name: helpers.record(source_root / name) for name in helpers.SOURCE_NAMES}
    base_before, overlay_before = helpers.tree(base), helpers.tree(overlay)
    # No source symlinks, hidden secret/cache/db files, or nested interpreter trees.
    for relative in base_before.keys() | overlay_before.keys():
        parts = Path(relative).parts
        if (any(part in {'.venv', '__pycache__', '.git'} for part in parts) or
                Path(relative).name == '.env' or Path(relative).suffix in {'.pyc', '.sqlite', '.sqlite3', '.db'}):
            raise RuntimeError('Unexpected cache/secret/database in source-only snapshot')
    preparation.mkdir(mode=0o700)
    (preparation / 'source').mkdir(mode=0o700)
    (preparation / 'backend').mkdir(mode=0o700)
    for name in helpers.SOURCE_NAMES:
        safe_copy(source_root / name, preparation / 'source' / name)
    mapping = {}
    # Merge into fresh leaves directly; no old or even fresh file is overwritten.
    for relative in sorted(base_before.keys() | overlay_before.keys()):
        src = overlay / relative if relative in overlay_before else base / relative
        dst = preparation / 'backend' / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        safe_copy(src, dst)
        mapping[relative] = {'input': 'overlay' if relative in overlay_before else 'archived-backend', 'record': helpers.record(src)}
    prepared = {'schema': 'fr-upload-metadata-http-harness-v1', 'nonce': nonce,
                'preparation': str(preparation), 'runtime': str(runtime),
                'interpreter': interpreter, 'site_packages': site, 'repository': str(repository),
                'simulator': simulator, 'run_check': str(run_check),
                'derived_directory': config['derived_directory'], 'deadline_seconds': config['deadline_seconds'],
                'normal_selector': helpers.NORMAL, 'fault_selector': helpers.FAULT,
                'normal_expected': {'POST': 1, 'GET': 2, 'sessions': 1, 'media_bytes': 0},
                'fault_expected': {'redirect': 1, 'oversize': 1, 'wrong-mime': 1, 'cancel': [0, 1], 'redirect-target': 0}}
    helpers.write_json(preparation / 'config.json', prepared)
    helpers.write_json(preparation / 'dependencies.json', provenance)
    helpers.write_json(preparation / 'input-provenance.json', {
        'template': helpers.record(template), 'backend_config': helpers.record(config['backend_config']),
        'dependency_provenance': helpers.record(config['dependency_provenance']),
        'base_backend': base_before, 'overlay': overlay_before, 'merged_mapping': mapping,
        'meaning': 'Only read-only pinned interpreter/deps from latest_template; all backend input from archived repository snapshot plus current overlay. No backend import or execution.'})
    helpers.dependencies(provenance)
    if (helpers.tree(base) != base_before or helpers.tree(overlay) != overlay_before or
            helpers.app_sources(repository) != app or
            {name: helpers.record(source_root / name) for name in helpers.SOURCE_NAMES} != source_before):
        raise RuntimeError('Input changed during preparation; retain failed new root without repair')
    helpers.write_json(preparation / 'checkpoint.json', {'config': helpers.record(preparation / 'config.json'),
        'source': helpers.tree(preparation / 'source'), 'backend': helpers.tree(preparation / 'backend'),
        'dependencies': helpers.record(preparation / 'dependencies.json'), 'app_sources': app,
        'run_check': helpers.record(run_check), 'input_provenance': helpers.record(preparation / 'input-provenance.json')})
    # Enforce accidental-write resistance in addition to the pre-import guard.
    for path in sorted(preparation.rglob('*'), key=lambda item: len(item.parts), reverse=True):
        path.chmod(0o555 if path.is_dir() else 0o444)
    preparation.chmod(0o555)
    print(json.dumps({'prepared': str(preparation), 'runtime_uncreated': not runtime.exists(),
                      'backend_files': len(mapping), 'backend_imported': False, 'sdk_started': False}))
    return 0


helpers = common()
if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'prepared': False, 'failure_type': type(error).__name__}))
        raise SystemExit(70) from None
