"""Main-launched guarded real storage POST/GET listener plus bounded faults.

No import of backend/site-packages before isolation Guard.install(). No process
launch, external network, worker/finalizer, chunk/media, Keychain or Photos use.
"""
import argparse
import asyncio
from contextlib import closing
import dataclasses
import hashlib
import hmac
import importlib.util
import json
import logging
import os
from pathlib import Path
import secrets
import sqlite3
import sys
import threading
import time
from urllib.parse import parse_qsl
from uuid import UUID, uuid4


def common():
    spec = importlib.util.spec_from_file_location('metadata_common', Path(__file__).with_name('metadata_common.py'))
    value = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = value
    spec.loader.exec_module(value)
    return value


helpers = common()
FIELDS = {'destination_id', 'registration_id', 'registration_generation', 'operation_id',
          'capture_id', 'content_generation', 'sha256', 'byte_count'}


def database_observation(settings):
    from app.db.connection import connect
    with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
        tables = ('fr_registrations', 'fr_upload_bindings', 'fr_upload_states', 'fr_upload_chunks',
                  'fr_storage_evidence', 'fr_job_claims', 'jobs', 'assets')
        counts = {name: conn.execute('SELECT COUNT(*) FROM ' + name).fetchone()[0] for name in tables}
        states = {row[0]: row[1] for row in conn.execute('SELECT status,COUNT(*) FROM fr_upload_states GROUP BY status')}
        generation = conn.execute('SELECT last_generation FROM fr_destination WHERE singleton=1').fetchone()[0]
        bindings = [dict(row) for row in conn.execute('SELECT * FROM fr_upload_bindings')]
    # Binding bodies are used only for exact checks in memory, never logged.
    return {'counts': counts, 'states': states, 'last_registration_generation': generation}, bindings


def make_application(settings):
    from fastapi import FastAPI
    from fastapi.exceptions import RequestValidationError
    from fastapi.responses import JSONResponse
    from app.api.frame_relay_storage import router
    from app.repositories.frame_relay_storage import StorageError
    from app.repositories.registrations import RegistrationError

    application = FastAPI(docs_url=None, redoc_url=None, openapi_url=None, redirect_slashes=False)
    # Mount only the actual storage router. Outer ASGI gate permits create and
    # the one real known-session lookup; every other storage route is blocked.
    application.include_router(router)

    @application.exception_handler(StorageError)
    async def storage_error(_request, error):
        return JSONResponse(status_code=409, content={'code': error.code, 'retryable': False}, headers={'Cache-Control': 'no-store'})

    @application.exception_handler(RegistrationError)
    async def registration_error(_request, _error):
        return JSONResponse(status_code=503, content={'code': 'registration_unavailable'}, headers={'Cache-Control': 'no-store'})

    @application.exception_handler(sqlite3.DatabaseError)
    async def database_error(_request, _error):
        return JSONResponse(status_code=503, content={'code': 'storage_unavailable'}, headers={'Cache-Control': 'no-store'})

    @application.exception_handler(RequestValidationError)
    async def validation_error(_request, _error):
        # Do not reflect payload or token-adjacent headers in raw artifacts.
        return JSONResponse(status_code=422, content={'code': 'validation_error'}, headers={'Cache-Control': 'no-store'})

    return application


async def fixed(send, status, body=b'{}', *, mime=b'application/json', extra=()):
    await send({'type': 'http.response.start', 'status': status, 'headers': [
        (b'content-type', mime), (b'content-length', str(len(body)).encode()),
        (b'cache-control', b'no-store'), (b'connection', b'close'), *extra]})
    await send({'type': 'http.response.body', 'body': body})


class ObservedApplication:
    def __init__(self, application, settings, registration, secret, config, report, note):
        self.application, self.settings, self.registration = application, settings, registration
        self.secret, self.config, self.report, self.note = secret, config, report, note
        self.original_binding = None
        self.session = None
        self.origin = None
        self.counts = {'POST': 0, 'GET': 0, 'redirect': 0, 'oversize': 0,
                       'wrong-mime': 0, 'cancel': 0, 'redirect-target': 0}

    def header(self, scope, key):
        values = [value for name, value in scope.get('headers', []) if name.lower() == key]
        return values[0] if len(values) == 1 else None

    def authenticated(self, scope):
        bearer = self.header(scope, b'authorization')
        secret = self.header(scope, b'x-framerelay-registration-secret')
        return (bearer is not None and secret is not None and
                hmac.compare_digest(bearer, ('Bearer ' + self.settings.api_token).encode()) and
                hmac.compare_digest(secret, self.secret.encode()))

    async def blocked(self, send, reason):
        self.report['blocked_requests'] += 1
        self.note('request-blocked', {'reason': reason})
        await fixed(send, 404)

    async def __call__(self, scope, receive, send):
        if scope['type'] == 'lifespan':
            await self.application(scope, receive, send)
            return
        if scope['type'] != 'http':
            raise RuntimeError('Unexpected ASGI scope')
        path, method = scope.get('path', ''), scope.get('method', '')
        prohibited = self.report['forbidden_route_counts']
        if method == 'PUT':
            prohibited['PUT'] += 1
        if method == 'DELETE':
            prohibited['DELETE'] += 1
        if path.endswith('/finalize'):
            prohibited['finalize'] += 1
        if '/media/' in path or path.endswith('/media'):
            prohibited['media'] += 1
        if path.endswith('/inventory'):
            prohibited['inventory'] += 1
        if '/registrations' in path or '/registration-intents' in path or path.endswith('/capabilities'):
            prohibited['registration_HTTP'] += 1
        if path.startswith('/metadata-probe/'):
            await self.fault(scope, receive, send, path.removeprefix('/metadata-probe/'))
            return
        if not self.authenticated(scope):
            await self.blocked(send, 'authorization-not-exact')
            return
        request = None
        if method == 'POST' and path == '/frame-relay/v1/uploads':
            if self.counts['POST'] >= 1 or scope.get('query_string') or self.header(scope, b'content-type') != b'application/json':
                await self.blocked(send, 'post-shape-or-limit')
                return
            body = bytearray()
            while True:
                message = await receive()
                if message['type'] == 'http.disconnect':
                    await self.blocked(send, 'post-disconnected-before-handler')
                    return
                body.extend(message.get('body', b''))
                if len(body) > 8192:
                    await self.blocked(send, 'post-body-bound')
                    return
                if not message.get('more_body', False):
                    break
            try:
                request = json.loads(body.decode('utf-8'), object_pairs_hook=helpers.unique_object,
                                     parse_constant=helpers.reject_constant)
                if not isinstance(request, dict) or set(request) != FIELDS or not all(type(value) is str for value in request.values()):
                    raise ValueError('POST8field contract')
                expected = self.registration
                if (request['destination_id'] != expected['destination_id'] or request['registration_id'] != expected['registration_id'] or
                        request['registration_generation'] != expected['generation']):
                    raise ValueError('Registration scope')
                prefix = 'metadata-http-' + self.config['nonce'] + '-'
                capture = request['capture_id']
                if not capture.startswith(prefix):
                    raise ValueError('Disposable capture nonce')
                suffix = capture[len(prefix):]
                parsed = str(UUID(suffix))
                if suffix not in (parsed, parsed.upper()):
                    raise ValueError('Capture suffix UUID')
                from app.schemas.frame_relay_storage import StorageBindingRequest
                if StorageBindingRequest.model_validate(request).model_dump() != request:
                    raise ValueError('Schema changed')
            except (ValueError, TypeError, KeyError, UnicodeError):
                await self.blocked(send, 'post-eight-fields-scope-or-schema')
                return
            self.counts['POST'] += 1
            delivered = False

            async def replay_receive():
                nonlocal delivered
                if not delivered:
                    delivered = True
                    return {'type': 'http.request', 'body': bytes(body), 'more_body': False}
                return await receive()
            actual_receive = replay_receive
            kind = 'POST'
        elif method == 'GET' and self.session is not None and path == '/frame-relay/v1/uploads/' + self.session:
            if self.counts['GET'] >= 2:
                await self.blocked(send, 'get-limit')
                return
            try:
                pairs = parse_qsl(scope.get('query_string', b'').decode('ascii'), keep_blank_values=True, strict_parsing=True)
                request = helpers.unique_object(pairs)
                if set(request) != FIELDS or request != self.original_binding:
                    raise ValueError('GET original8 binding changed')
            except (ValueError, UnicodeError):
                await self.blocked(send, 'get-binding-not-exact')
                return
            self.counts['GET'] += 1
            actual_receive, kind = receive, 'GET'
        else:
            await self.blocked(send, 'route-not-allowed')
            return
        row = self.row(kind)
        response = bytearray()

        async def measured_send(message):
            if message['type'] == 'http.response.start':
                row['status'] = message['status']
                headers = {key.lower(): value for key, value in message.get('headers', [])}
                row['json_mime'] = headers.get(b'content-type') == b'application/json'
                row['headers_sent'] = True
            if message['type'] == 'http.response.body':
                response.extend(message.get('body', b''))
                if len(response) > helpers.MAXIMUM_BYTES:
                    raise RuntimeError('Actual metadata response bound exceeded')
                row['bytes_offered'] += len(message.get('body', b''))
            await send(message)

        try:
            row['real_storage_handler_entered'] = True
            await self.application(scope, actual_receive, measured_send)
            row['handler_returned'] = True
            if row['status'] != 200:
                raise RuntimeError('Real storage response not successful')
            value = json.loads(response, object_pairs_hook=helpers.unique_object, parse_constant=helpers.reject_constant)
            binding = value['binding']
            if ({key: binding[key] for key in FIELDS} != request or set(binding) != FIELDS | {'session_id', 'chunk_size'} or
                    not helpers.canonical_id(binding['session_id'])):
                raise RuntimeError('Real response binding mismatch')
            if kind == 'POST':
                if set(value) != {'binding'}:
                    raise RuntimeError('POST must not manufacture status')
                self.original_binding, self.session = request, binding['session_id']
                row['created_binding_only'] = True
            else:
                if (set(value) != {'binding', 'status', 'evidence', 'chunk_indexes', 'failure_code'} or
                        value['status'] != 'receiving' or value['evidence'] is not None or
                        value['chunk_indexes'] != [] or value['failure_code'] is not None):
                    raise RuntimeError('Expected real empty receiving state only')
                row['receiving_empty_chunks_no_evidence'] = True
            row['exact_eight_fields_and_nonce'] = True
        except BaseException as error:
            row['failure_type'] = type(error).__name__
            raise
        finally:
            row['terminal_monotonic'] = time.monotonic()
            self.note('request-terminal', row)

    def row(self, kind):
        row = {'sequence': len(self.report['requests']) + 1, 'kind': kind, 'started_monotonic': time.monotonic(),
               'terminal_monotonic': None, 'status': None, 'headers_sent': False, 'bytes_offered': 0,
               'media_bytes_offered': 0, 'handler_returned': False, 'real_storage_handler_entered': False}
        self.report['requests'].append(row)
        return row

    async def fault(self, scope, receive, send, fault):
        nonce = self.header(scope, b'x-framerelay-probe-nonce')
        if (scope.get('method') != 'GET' or scope.get('query_string') or fault not in self.counts or
                fault in ('POST', 'GET') or nonce is None or not hmac.compare_digest(nonce, self.config['nonce'].encode())):
            await self.blocked(send, 'fault-nonce-route-or-method')
            return
        self.counts[fault] += 1
        row = self.row(fault)
        try:
            if self.counts[fault] != 1 or fault == 'redirect-target':
                self.report['unexpected_fault_request'] = True
                await fixed(send, 410)
                row['status'] = 410
            elif fault == 'redirect':
                await fixed(send, 307, b'', extra=[(b'location', (self.origin + '/metadata-probe/redirect-target').encode())])
                row['status'], row['bytes_offered'] = 307, 0
            elif fault == 'oversize':
                payload = b' ' * (helpers.MAXIMUM_BYTES + 1)
                await fixed(send, 200, payload)
                row['status'], row['bytes_offered'] = 200, len(payload)
            elif fault == 'wrong-mime':
                payload = b'{"probe":"unknown-mime"}'
                await fixed(send, 200, payload, mime=b'application/octet-stream')
                row['status'], row['bytes_offered'] = 200, len(payload)
            elif fault == 'cancel':
                # Deliberately withhold headers/body, observing actual disconnect.
                # The client may cancel before Uvicorn creates this scope: zero
                # arrivals is separately reported and never called disconnect.
                async def disconnected():
                    while True:
                        message = await receive()
                        if message['type'] == 'http.disconnect':
                            return
                try:
                    await asyncio.wait_for(disconnected(), timeout=10)
                    row['actual_disconnect_before_response'] = True
                except asyncio.TimeoutError:
                    row['delay_expired_without_disconnect'] = True
                    await fixed(send, 200)
                    row['status'], row['bytes_offered'] = 200, 2
            row['handler_returned'] = True
        except BaseException as error:
            row['failure_type'] = type(error).__name__
            raise
        finally:
            row['terminal_monotonic'] = time.monotonic()
            self.note('fault-terminal', row)


def run_listener(settings, config, runtime, report):
    from app.db.connection import connect
    from app.db.migrations import run_migrations
    from app.db.frame_relay_migrations import run_frame_relay_migrations
    from app.services.storage import initialize_storage
    from app.services import registrations
    lifecycle = helpers.module('listener_lifecycle')
    initialize_storage(settings.media_root)  # fresh infrastructure-only write probe
    with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
        run_migrations(conn)
        run_frame_relay_migrations(conn)
    report['before_registration'], _ = database_observation(settings)
    destination = registrations.capabilities()['destination_id']
    secret = secrets.token_hex(32)
    receipt = registrations.register(destination_id=destination, operation_id=str(uuid4()), secret=secret)
    if not (helpers.canonical_id(receipt['destination_id']) and helpers.canonical_id(receipt['registration_id']) and receipt['generation'] == '1'):
        raise RuntimeError('Fresh disposable registration not canonical')
    registration = {key: receipt[key] for key in ('destination_id', 'registration_id', 'generation')}
    report['after_registration'], _ = database_observation(settings)
    events = (runtime / 'listener-events.jsonl').open('x')

    def note(event, detail):
        # No payload, credential, Authorization/secret header, or exception text.
        events.write(json.dumps({'event': event, 'detail': detail, 'monotonic': time.monotonic()}, sort_keys=True) + '\n')
        events.flush()

    app = ObservedApplication(make_application(settings), settings, registration, secret, config, report, note)

    def on_ready(origin):
        app.origin = origin
        normal = {'FR_UPLOAD_METADATA_HTTP': '1', 'FR_UPLOAD_METADATA_HTTP_FAULT': '0',
                  'FR_UPLOAD_METADATA_HTTP_NONCE': config['nonce'], 'FR_UPLOAD_METADATA_HTTP_NEW_ISOLATED': '1',
                  'FR_UPLOAD_METADATA_HTTP_ORIGIN': origin, 'FR_UPLOAD_METADATA_HTTP_DESTINATION': receipt['destination_id'],
                  'FR_UPLOAD_METADATA_HTTP_REGISTRATION': receipt['registration_id'], 'FR_UPLOAD_METADATA_HTTP_GENERATION': receipt['generation'],
                  'FR_UPLOAD_METADATA_HTTP_BEARER': settings.api_token, 'FR_UPLOAD_METADATA_HTTP_SECRET': secret}
        fault = {'FR_UPLOAD_METADATA_HTTP': '0', 'FR_UPLOAD_METADATA_HTTP_FAULT': '1',
                 'FR_UPLOAD_METADATA_HTTP_FAULT_NONCE': config['nonce'], 'FR_UPLOAD_METADATA_HTTP_FAULT_NEW_ISOLATED': '1',
                 'FR_UPLOAD_METADATA_HTTP_FAULT_ORIGIN': origin}
        helpers.write_json(runtime / 'client-env.json', {'nonce': config['nonce'], 'listener_pid': os.getpid(),
            'origin': origin, 'normal': normal, 'fault': fault}, private=True)
        helpers.write_json(runtime / 'listener-ready.json', {'nonce': config['nonce'], 'pid': os.getpid(),
            'origin': origin, 'started_monotonic': report['started_monotonic'], 'deadline_monotonic': report['deadline_monotonic']})
        report['ready'] = True

    def should_stop():
        path = runtime / 'stop.request'
        if path.exists():
            value = helpers.read_json(path, private=True)
            if set(value) != {'nonce', 'listener_pid', 'requester_pid', 'reason'} or value['nonce'] != config['nonce'] or value['listener_pid'] != os.getpid():
                raise RuntimeError('Stop request identity mismatch')
            if type(value['requester_pid']) is not int or value['requester_pid'] <= 1 or value['reason'] != 'reviewed-main-stop':
                raise RuntimeError('Invalid stop request')
            return 'reviewed-stop'
        return None

    try:
        asyncio.run(lifecycle.serve_observed(app, report, note, on_ready, should_stop, deadline=report['deadline_monotonic']))
        report['after_http'], bindings = database_observation(settings)
        expected = app.original_binding
        report['database_binding_matches_actual_post'] = (len(bindings) == 1 and expected is not None and
            {key: str(bindings[0][key]) for key in FIELDS} == expected and bindings[0]['session_id'] == app.session)
        report['request_counts'] = app.counts
        report['cancel_arrival'] = ('arrived-and-disconnected' if app.counts['cancel'] == 1 and
            any(row.get('actual_disconnect_before_response') is True for row in report['requests'] if row['kind'] == 'cancel')
            else 'no-server-arrival-observed' if app.counts['cancel'] == 0 else 'arrived-without-disconnect-proof')
        report['media_files'] = helpers.tree(settings.media_root)
        report['client_executions'] = {}
        for mode in ('normal', 'fault'):
            path = runtime / ('client-' + mode + '-result.json')
            value = helpers.read_json(path)
            report['client_executions'][mode] = {
                'passed': (value.get('passed') is True and value.get('inputs_unchanged') is True and
                           value.get('nonce') == config['nonce'] and value.get('listener_pid') == os.getpid() and
                           value.get('mode') == mode and value.get('expected_executions') == (1 if mode == 'normal' else 4)),
                'record': helpers.record(path)}
    finally:
        events.close()


def evaluate(report):
    counts = report.get('request_counts', {})
    after = report.get('after_http', {})
    tables = after.get('counts', {})
    rows = report['requests']
    normal = [row for row in rows if row['kind'] in ('POST', 'GET')]
    required_faults = all(counts.get(key) == 1 for key in ('redirect', 'oversize', 'wrong-mime'))
    return {'exact_post_one_get_two': counts.get('POST') == 1 and counts.get('GET') == 2,
            'actual_native_client_one_plus_four_passed': all(report.get('client_executions', {}).get(mode, {}).get('passed') is True for mode in ('normal', 'fault')),
            'real_handler_three_exact_terminal': len(normal) == 3 and all(
                row['real_storage_handler_entered'] and row['handler_returned'] and row['status'] == 200 and
                row.get('json_mime') is True and row.get('exact_eight_fields_and_nonce') is True and 'failure_type' not in row for row in normal),
            'all_handlers_terminal': bool(rows) and all(row['handler_returned'] and row['terminal_monotonic'] is not None and 'failure_type' not in row for row in rows),
            'one_registration_one_receiving_session': report.get('before_registration', {}).get('counts', {}).get('fr_registrations') == 0 and
                report.get('after_registration', {}).get('counts', {}).get('fr_registrations') == 1 and
                report.get('after_registration', {}).get('counts', {}).get('fr_upload_bindings') == 0 and
                tables.get('fr_registrations') == 1 and tables.get('fr_upload_bindings') == 1 and
                tables.get('fr_upload_states') == 1 and after.get('states') == {'receiving': 1} and after.get('last_registration_generation') == 1,
            'actual_binding_matches_post': report.get('database_binding_matches_actual_post') is True,
            'no_chunk_finalize_delete_media_jobs_assets_evidence': all(tables.get(key) == 0 for key in
                ('fr_upload_chunks', 'fr_storage_evidence', 'fr_job_claims', 'jobs', 'assets')) and
                report.get('media_files') == {} and all(row['media_bytes_offered'] == 0 for row in rows),
            'fault_three_plus_optional_cancel_and_no_redirect_target': required_faults and counts.get('cancel') in (0, 1) and
                counts.get('redirect-target') == 0 and report.get('cancel_arrival') in ('arrived-and-disconnected', 'no-server-arrival-observed'),
            'no_unreviewed_requests': report['blocked_requests'] == 0 and not report.get('unexpected_fault_request') and
                all(value == 0 for value in report['forbidden_route_counts'].values())}


def main():
    helpers.require_runtime()
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepared', type=Path, required=True)
    args = parser.parse_args()
    config, checkpoint, _provenance = helpers.verified(args.prepared)
    preparation, runtime = Path(config['preparation']), Path(config['runtime'])
    if Path(__file__).resolve().parent != preparation / 'source':
        raise RuntimeError('Run immutable prepared source only')
    if runtime.exists() or runtime.is_symlink():
        raise RuntimeError('Fresh uncreated runtime only; never repair/reseed/restart')
    runtime.mkdir(mode=0o700)
    guard_module = helpers.module('isolation_guard')
    guard = guard_module.Guard(runtime, allow_missing_ffprobe_version=False, allow_loopback_listener=True)
    guard.install()  # Before site-packages, settings, router, DB or backend imports.
    runner = helpers.module('run_pytest')
    initial_fds = runner.fd_inventory(guard)
    baseline_threads = set(threading.enumerate())
    home_before = os.environ.get('HOME')
    preserved = {key: os.environ[key] for key in ('HOME', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TZ') if key in os.environ}
    # Retain HOME continuously and byte-for-byte, rather than clearing/rebinding.
    for key in tuple(os.environ):
        if key not in preserved:
            os.environ.pop(key)
    explicit = runner.settings_environment(runtime)
    os.environ.update(explicit)
    os.environ.update({'PATH': '/usr/bin:/bin', 'TMPDIR': str(runtime / 'tmp'), 'TMP': str(runtime / 'tmp'),
        'TEMP': str(runtime / 'tmp'), 'SQLITE_TMPDIR': str(runtime / 'sqlite-tmp'), 'XDG_CACHE_HOME': str(runtime / 'cache'),
        'PYTEST_DISABLE_PLUGIN_AUTOLOAD': '1'})
    for name in ('tmp', 'sqlite-tmp', 'cache', 'media', 'user-lut', 'assets/lut/presets', 'assets/detectors/apple-log-v2'):
        (runtime / name).mkdir(parents=True, exist_ok=True)
    # LUT/detector paths are explicit and private; metadata does not load assets.
    os.chdir(runtime)
    os.environ['PWD'] = str(runtime)
    sys.path.extend((str(preparation / 'backend'), config['site_packages']))
    logging.disable(logging.CRITICAL)  # Uvicorn/backend traceback cannot render credentials.
    started = time.monotonic()
    report = {'schema': 'fr-upload-metadata-http-harness-v1', 'nonce': config['nonce'], 'pid': os.getpid(),
        'started_monotonic': started, 'deadline_monotonic': started + config['deadline_seconds'],
        'ready': False, 'signals': [], 'stop_reason': None, 'server_terminated': False,
        'blocked_requests': 0, 'forbidden_route_counts': {key: 0 for key in ('PUT', 'DELETE', 'finalize', 'media', 'inventory', 'registration_HTTP')},
        'requests': [], 'passed': False, 'initial_fds': initial_fds,
        'home_inherited_unchanged': os.environ.get('HOME') == home_before,
        'unverified': ['strict sender/native URLSession resume', 'media transfer/final read/conversion', 'production network/quality'],
        'security_limit': 'Trusted-code Python audit guard is not an OS/native sandbox. Xcode raw artifacts may retain disposable environment. Token lifetime ends with this listener; only new client-env.json is removed.'}
    try:
        from app.core.settings import load_settings
        settings = load_settings()
        effective = dataclasses.asdict(settings)
        if len(effective) != 22 or len(explicit) != 22:
            raise RuntimeError('Settings shape changed')
        for key, value in effective.items():
            env_key = 'APPLE_LOG_DETECTOR_ROOT' if key == 'detector_root' else key.upper()
            if str(value) != explicit[env_key]:
                raise RuntimeError('Effective settings differ from explicit private paths')
        redacted = {key: '<disposable-redacted>' if key == 'API_TOKEN' else value for key, value in explicit.items()}
        helpers.write_json(runtime / 'effective-settings-redacted.json', redacted)
        run_listener(settings, config, runtime, report)
    except BaseException as error:
        report['failure_type'] = type(error).__name__
    finally:
        created = [thread for thread in threading.enumerate() if thread not in baseline_threads]
        report['created_threads'] = []
        for thread in created:
            row = {'id': thread.ident, 'name': thread.name, 'daemon': thread.daemon}
            try:
                thread.join(timeout=5)
                row['join_returned'] = True
            except BaseException as error:
                row['failure_type'] = type(error).__name__
            row['alive_after_join'] = thread.is_alive()
            report['created_threads'].append(row)
        report['all_created_threads_joined'] = all(row.get('join_returned') is True and not row['alive_after_join'] and 'failure_type' not in row for row in report['created_threads'])
        secret_path = runtime / 'client-env.json'
        if secret_path.exists():
            secret_path.unlink()  # Only this newly generated disposable secret file.
        report['secret_deleted'] = not secret_path.exists()
        report['token_invalidated_by_listener_termination'] = report.get('server_terminated') is True and report.get('listener_fd_closed') is True
        os.environ.pop('API_TOKEN', None)
        explicit.pop('API_TOKEN', None)
        owner = {'passed': False}
        try:
            survivors = tuple(guard.connections)  # Keep GC from hiding live owners.
            events = [dict(event) for event in guard.connection_events]
            tracked = [{'id': id(conn), 'owner_thread': conn._s20_thread} for conn in survivors]
            before_finish = runner.fd_inventory(guard)
            owner = helpers.owner_close_observation(events, tracked, before_finish, initial_fds, runtime)
            report['owner_close_before_guard_finish'] = {'events': events, 'tracked': tracked,
                'fd_inventory': before_finish, 'observation': owner}
        except BaseException as error:
            report['owner_audit_failure_type'] = type(error).__name__
        report['guard'] = guard.finish()  # Rescue close cannot turn owner failure into success.
        report['fd_after_guard_finish'] = runner.fd_inventory(guard)
        report['remaining_created_threads'] = [{'id': thread.ident, 'name': thread.name}
            for thread in threading.enumerate() if thread not in baseline_threads]
        try:
            helpers.verified(args.prepared)
            report['inputs_unchanged'] = True
        except BaseException as error:
            report['inputs_unchanged'] = False
            report['input_audit_failure_type'] = type(error).__name__
        origins = {name: str(Path(value.__file__).resolve()) for name, value in sys.modules.items() if getattr(value, '__file__', None)}
        allowed = (preparation / 'source', preparation / 'backend', Path(config['site_packages']).resolve(), Path(sys.base_prefix).resolve())
        unexpected = {name: path for name, path in origins.items() if not any(Path(path).is_relative_to(root) for root in allowed)}
        helpers.write_json(runtime / 'import-origins.json', origins)
        report['unexpected_import_origins'] = unexpected
        report['observations'] = evaluate(report)
        report['passed'] = (all(report['observations'].values()) and owner.get('passed') is True and
            all(report.get(key) is True for key in ('ready', 'server_terminated', 'listener_fd_closed', 'all_created_threads_joined',
                'secret_deleted', 'token_invalidated_by_listener_termination', 'home_inherited_unchanged', 'inputs_unchanged')) and
            report['stop_reason'] == 'reviewed-stop' and not report['signals'] and not report.get('forced_server_task_cancel') and
            report.get('remaining_server_connections') == 0 and report.get('remaining_server_tasks') == 0 and
            not report['remaining_created_threads'] and not unexpected and not guard.denials and
            report['guard']['sqlite_connections_alive_before_explicit_close'] == 0 and
            report['guard']['sqlite_connections_alive_after_explicit_close'] == 0 and
            not report['guard']['foreign_thread_connections_not_explicitly_closed'] and not report['guard']['sqlite_close_failures'] and
            guard.listener_bind_count == 1 and 'failure_type' not in report)
        helpers.write_json(runtime / 'listener-result.json', report)
        guard.log.close()
    print(json.dumps({'runtime': str(runtime), 'passed': report['passed'], 'request_counts': report.get('request_counts'),
                      'secret_deleted': report['secret_deleted'], 'real_metadata_only': True}))
    return 0 if report['passed'] else 70


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'passed': False, 'failure_type': type(error).__name__}))
        raise SystemExit(70) from None
