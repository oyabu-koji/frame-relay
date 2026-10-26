"""Metadata HTTP harness: stdlib-only input, identity and terminal checks.

No backend/site-package import, network, process launch or mutation at import.
"""
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import stat
import sys
import time
from urllib.parse import urlsplit
from uuid import UUID

OWNED = Path('/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-implementation-20261024-l0p333tn/metadata-http-harness')
NORMAL = 'FrameRelayTests/UploadMetadataRemoteTests/isolatedActualHTTPCreateAndPausedCancelledKnownSessionGETOnly()'
FAULT = 'FrameRelayTests/UploadMetadataRemoteTests/isolatedNativeHTTPRefusalBoundsCancellationAndActualTerminals(fault:)'
MAXIMUM_BYTES = 262144
SOURCE_NAMES = ('metadata_common.py', 'prepare_metadata_http.py', 'metadata_listener.py',
                'run_metadata_client.py', 'stop_metadata_listener.py', 'isolation_guard.py',
                'listener_lifecycle.py', 'run_pytest.py')


def require_runtime():
    if (sys.platform != 'darwin' or sys.version_info[:2] != (3, 12) or
            not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode)):
        raise RuntimeError('Require reviewed macOS Python 3.12 -I -B -S')


def canonical_id(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f-]{36}', value) is not None and str(UUID(value)) == value


def checked_id(value):
    if not canonical_id(value):
        raise RuntimeError('Expected canonical disposable UUID')
    return value


def record(path, *, dependency=False):
    path = Path(path)
    if dependency and path.is_symlink():
        return {'kind': 'symlink', 'target': os.readlink(path), 'resolved': str(path.resolve(strict=True))}
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise RuntimeError('Expected regular reviewed file')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return {'kind': 'file', 'size': info.st_size, 'sha256': digest.hexdigest()}


def tree(root, *, dependency=False):
    return {str(path.relative_to(root)): record(path, dependency=dependency)
            for path in sorted(Path(root).rglob('*')) if path.is_file() or path.is_symlink()}


def write_json(path, value, *, private=False):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600 if private else 0o644)
    with os.fdopen(fd, 'w', encoding='utf-8') as stream:
        json.dump(value, stream, sort_keys=True, indent=2, ensure_ascii=False, allow_nan=False)
        stream.write('\n')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON member')
        result[key] = value
    return result


def reject_constant(_value):
    raise ValueError('Non-finite JSON constant')


def read_json(path, *, private=False):
    path = Path(path)
    record(path)
    info = path.lstat()
    if private and (info.st_nlink != 1 or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600):
        raise RuntimeError('Secret input must be owned regular 0600 single-link file')
    return json.loads(path.read_text(), object_pairs_hook=unique_object, parse_constant=reject_constant)


def module(name, directory=None):
    directory = Path(__file__).parent if directory is None else Path(directory)
    spec = importlib.util.spec_from_file_location(name, directory / (name + '.py'))
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def app_sources(root):
    result = {}
    for name in ('FrameRelay', 'FrameRelayTests', 'FrameRelayUITests', 'FrameRelay.xcodeproj'):
        directory = root / name
        if directory.is_symlink() or not directory.is_dir():
            raise RuntimeError('Require existing immutable Xcode source copy')
        for path in sorted(directory.rglob('*')):
            if path.is_symlink():
                raise RuntimeError('Immutable Xcode source must not contain symlink aliases')
            if path.is_file() and 'xcuserdata' not in path.parts and path.name != '.DS_Store':
                result[str(path.relative_to(root))] = record(path)
    return result


def dependencies(provenance):
    site = Path(provenance['site_packages_root'])
    interpreter = Path(provenance['interpreter']['entry'])
    if (tree(site, dependency=True) != provenance['site_packages_before'] or
            record(interpreter, dependency=True) != provenance['interpreter']['record'] or
            record(interpreter.resolve(strict=True)) != provenance['interpreter']['resolved_record'] or
            (interpreter.parent.parent / 'pyvenv.cfg').read_text() != provenance['pyvenv_cfg'] or
            {str(p.relative_to(site)): p.read_text() for p in sorted(site.glob('*.pth'))} != provenance['pth']):
        raise RuntimeError('Reviewed dependency hashes changed; no install or refresh is allowed')


def owned(path, *, strict=False):
    value = Path(path)
    canonical = value.resolve(strict=strict)
    if value.is_symlink() or not canonical.is_relative_to(OWNED.resolve(strict=True)):
        raise RuntimeError('Output must remain in this new harness namespace')
    return canonical


def verified(config_path, *, dependencies_too=True):
    config_path = owned(config_path, strict=True)
    config = read_json(config_path)
    checked_id(config['nonce'])
    preparation = owned(config['preparation'], strict=True)
    if config_path != preparation / 'config.json' or preparation.name != 'prepared-' + config['nonce']:
        raise RuntimeError('Preparation identity mismatch')
    checkpoint = read_json(preparation / 'checkpoint.json')
    if (record(config_path) != checkpoint['config'] or
            tree(preparation / 'source') != checkpoint['source'] or
            tree(preparation / 'backend') != checkpoint['backend'] or
            record(preparation / 'dependencies.json') != checkpoint['dependencies'] or
            record(preparation / 'input-provenance.json') != checkpoint['input_provenance'] or
            record(Path(config['run_check'])) != checkpoint['run_check'] or
            app_sources(Path(config['repository'])) != checkpoint['app_sources']):
        raise RuntimeError('Reviewed immutable input changed')
    provenance = read_json(preparation / 'dependencies.json')
    if (Path(config['interpreter']).resolve(strict=True) != Path(sys.executable).resolve(strict=True) or
            record(Path(sys.executable).resolve()) != provenance['interpreter']['resolved_record'] or
            config['site_packages'] != provenance['site_packages_root']):
        raise RuntimeError('Interpreter or dependency origin mismatch')
    if dependencies_too:
        dependencies(provenance)
    runtime = owned(config['runtime'])
    if runtime != preparation.parent / ('runtime-' + config['nonce']):
        raise RuntimeError('Runtime identity mismatch')
    return config, checkpoint, provenance


def checked_ready(config):
    runtime = Path(config['runtime'])
    ready = read_json(runtime / 'listener-ready.json')
    url = urlsplit(ready.get('origin', ''))
    if (ready.get('nonce') != config['nonce'] or type(ready.get('pid')) is not int or ready['pid'] <= 1 or
            ready['pid'] == os.getpid() or url.scheme != 'http' or url.hostname != '127.0.0.1' or
            url.username or url.password or url.path or url.query or url.fragment or
            url.port is None or not 1 <= url.port <= 65535 or ready['origin'] != 'http://127.0.0.1:' + str(url.port) or
            not all(type(ready.get(key)) in (int, float) and math.isfinite(ready[key])
                    for key in ('started_monotonic', 'deadline_monotonic')) or
            ready['deadline_monotonic'] - ready['started_monotonic'] != config['deadline_seconds'] or
            time.monotonic() >= ready['deadline_monotonic']):
        raise RuntimeError('Listener identity or deadline mismatch')
    os.kill(ready['pid'], 0)  # Observation only. No signal is sent.
    return ready


def owner_close_observation(events, tracked, inventory, initial, runtime):
    pending, unclosed_gc, malformed = set(), [], False
    for event in events:
        identifier = event.get('id')
        if type(identifier) is not int:
            malformed = True
        elif event.get('event') == 'opened':
            if identifier in pending:
                malformed = True
            pending.add(identifier)
        elif event.get('event') == 'closed':
            if identifier not in pending:
                malformed = True
            pending.discard(identifier)
        elif event.get('event') == 'garbage_collected':
            if identifier in pending:
                unclosed_gc.append(identifier)
        else:
            malformed = True
    identities = {(fd.get('dev'), fd.get('ino')) for fd in initial if 'mode' in fd}
    database_media, unknown = [], []
    for fd in inventory:
        path = fd.get('path')
        if path and (path.startswith(str(runtime / 'db.sqlite3')) or Path(path).is_relative_to(runtime / 'media')):
            database_media.append(fd)
        elif not path and stat.S_ISREG(fd.get('mode', 0)) and (fd.get('dev'), fd.get('ino')) not in identities:
            unknown.append(fd)
    closed = not malformed and not pending and not unclosed_gc and not tracked
    return {'passed': closed and not database_media and not unknown,
            'sqlite_owner_explicit_close_complete': closed, 'pending_connection_ids': sorted(pending),
            'unclosed_garbage_collected_ids': unclosed_gc, 'malformed_connection_events': malformed,
            'tracked_connection_count': len(tracked), 'database_media_fds_remaining': database_media,
            'unresolved_new_regular_fds': unknown}
