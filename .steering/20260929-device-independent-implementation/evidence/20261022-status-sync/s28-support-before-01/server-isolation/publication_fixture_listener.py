"""Guarded S27 canonical wire with explicit tests-owned publication authority."""
import argparse
import asyncio
import base64
from contextlib import closing
import dataclasses
import hashlib
import hmac
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import sys
import threading
import time
from uuid import uuid4


def load_helper():
    spec = importlib.util.spec_from_file_location("prepare_publication_probe",
        Path(__file__).with_name("prepare_publication_probe.py"))
    helper = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = helper
    spec.loader.exec_module(helper)
    return helper


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
        ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def make_fixture(helper, config, settings, movie, registration_secret):
    # All imports below occur after Guard.install. Production router defaults remain untouched.
    from fastapi import FastAPI
    from app.api.frame_relay_publication import create_router
    from app.db.connection import connect
    from app.db.migrations import run_migrations
    from app.db.frame_relay_migrations import run_frame_relay_migrations
    from app.services.storage import initialize_storage
    from app.services import registrations
    factory_path = Path(config["snapshot"]) / "backend/tests/frame_relay_publication_fixture.py"
    spec = importlib.util.spec_from_file_location("s27_tests_publication_fixture", factory_path)
    fixture = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = fixture
    spec.loader.exec_module(fixture)
    fixture_service, seed_candidate = fixture.fixture_service, fixture.seed_candidate

    initialize_storage(settings.media_root)
    with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
        run_migrations(conn)
        run_frame_relay_migrations(conn)
    destination = registrations.capabilities()["destination_id"]
    receipt = registrations.register(destination_id=destination, operation_id=str(uuid4()), secret=registration_secret)
    registration = {key: receipt[key] for key in ("destination_id", "registration_id", "generation")}
    data = movie.read_bytes()
    capture = "s27-technical-fixture-" + config["run_identity"]
    v1 = seed_candidate(settings, registration, registration_secret, data, capture, str(uuid4()))
    v2 = seed_candidate(settings, registration, registration_secret, data, capture, str(uuid4()), source_bytes=data)
    if v1["original"] != v2["original"] or v1["candidate_id"] == v2["candidate_id"]:
        raise RuntimeError("Fixture candidates must be distinct versions of one original")
    service = fixture_service(settings)
    initial = service.publish_initial(operation_id=str(uuid4()), candidate_id=v1["candidate_id"], expected_revision=0)
    factory_source = helper.record(factory_path)
    metadata = {"schema_version": "fr-publication-fixture-v1", "run_identity": config["run_identity"],
        "fixture_only": True, "wire_sha256": helper.WIRE_SHA256, "source_sha256": config["fixture"]["sha256"],
        "media_type": "video/quicktime", "registration_receipt": receipt,
        "original": v1["original"], "v1": initial["rendition"], "v2": None,
        "provenance": {"authority": "tests.frame_relay_publication_fixture.FixturePublicationAuthority",
            "factory_source": {**factory_source, "size": str(factory_source["size"])},
            "candidate_v1_id": v1["candidate_id"], "candidate_v2_id": v2["candidate_id"],
            "meaning": "technical copy only; no Rec.709 proof or product quality acceptance"}}
    application = FastAPI(docs_url=None, redoc_url=None, openapi_url=None, redirect_slashes=False)
    application.include_router(create_router(lambda: service))
    return application, service, registration, v2["candidate_id"], metadata


def run_fixture(helper, lifecycle, runtime, config, settings, movie):
    # Seed/import-created workers belong to this run too. A baseline taken after
    # make_fixture would silently exempt finalize/conversion seed threads.
    before_threads = set(threading.enumerate())
    from starlette.concurrency import run_in_threadpool
    from app.repositories.frame_relay_publication import PublicationError

    registration_secret, control_secret = secrets.token_hex(32), secrets.token_hex(32)
    application, service, registration, candidate_v2, metadata = make_fixture(
        helper, config, settings, movie, registration_secret)
    started = time.monotonic()
    report = {"run_identity": config["run_identity"], "pid": os.getpid(), "fixture_only": True,
        "started_monotonic": started, "deadline_monotonic": started + 1200,
        "ready": False, "signals": [], "stop_reason": None, "server_terminated": False,
        "requests": [], "controls": [], "request_limit": 4096, "passed": False,
        "fixture": metadata, "response_loss_count": 0,
        "throttle": {"block_bytes": 4096, "delay_seconds": 0.01,
            "meaning": "fixture ASGI scheduling only; canonical body/headers unchanged; not product performance tuning"},
        "response_loss_meaning": "successful committed confirmation receipt replaced with fixture 503; not TCP loss",
        "thread_baseline_before_seed": [{"id": thread.ident, "name": thread.name}
            for thread in sorted(before_threads, key=lambda value: (value.name, value.ident or 0))],
        "unverified": ["production Rec.709 authority", "real network loss", "production external owners",
            "re-registration and old ACK races on this HTTP path"]}
    state = {"phase": "v1-current", "loss_armed": False, "replacement": None, "publication": None}
    secret_path = runtime / "fixture-env.json"
    events = (runtime / "listener-events.jsonl").open("x")

    def note(event, detail):
        events.write(json.dumps({"event": event, "detail": detail, "monotonic": time.monotonic()}) + "\n")
        events.flush()

    async def fixed(send, status, value):
        body = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
        await send({"type": "http.response.start", "status": status, "headers": [
            (b"content-type", b"application/json"), (b"content-length", str(len(body)).encode()),
            (b"cache-control", b"no-store"), (b"connection", b"close")]})
        await send({"type": "http.response.body", "body": body})

    def manifest():
        return service.manifest({"schema_version": "fr-publication-v1", "registration": registration,
            "original": metadata["original"]}, registration_secret)["result"]

    async def control(scope, receive, send):
        credentials = [value for key, value in scope.get("headers", []) if key.lower() == b"x-framerelay-fixture-secret"]
        if len(credentials) != 1 or not hmac.compare_digest(credentials[0], control_secret.encode()):
            await fixed(send, 401, {"code": "fixture_control_unauthorized"})
            return
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            body.extend(message.get("body", b""))
            if len(body) > 1024:
                await fixed(send, 422, {"code": "fixture_control_too_large"})
                return
            if not message.get("more_body", False):
                break
        try:
            from app.api.frame_relay_publication import unique_object
            request = json.loads(body.decode("utf-8"), object_pairs_hook=unique_object)
            if set(request) != {"run_identity", "action"} or request["run_identity"] != config["run_identity"]:
                raise ValueError("Control identity mismatch")
            action = request["action"]
            observation = {"action": action, "started_monotonic": time.monotonic(),
                "phase_before": state["phase"], "status": None, "terminal_monotonic": None}
            report["controls"].append(observation)
            if action == "arm-confirmation-response-loss" and not state["loss_armed"] and report["response_loss_count"] == 0:
                state["loss_armed"] = True
                result = {"armed": True}
            elif action == "begin-replacement" and state["phase"] == "v1-current":
                current = await run_in_threadpool(manifest)
                result = await run_in_threadpool(service.begin_replacement, operation_id=str(uuid4()),
                    candidate_id=candidate_v2, invalidation_id=str(uuid4()), expected_revision=int(current["revision"]))
                state["replacement"], state["phase"] = result, "replacement-pending"
            elif action == "publish-replacement" and state["phase"] == "replacement-pending":
                current = await run_in_threadpool(manifest)
                result = await run_in_threadpool(service.publish_replacement, operation_id=str(uuid4()),
                    replacement_id=state["replacement"]["replacement_id"], expected_revision=int(current["revision"]))
                state["publication"], state["phase"] = result, "v2-current"
            else:
                raise ValueError("Unreviewed control action/state")
            observation.update(status=200, result=result, phase_after=state["phase"])
            await fixed(send, 200, {"run_identity": config["run_identity"], "action": action, "result": result})
        except PublicationError as error:
            observation.update(status=error.status, error_code=error.code, phase_after=state["phase"])
            await fixed(send, error.status, {"code": error.code})
        except (ValueError, TypeError, KeyError, UnicodeError):
            await fixed(send, 422, {"code": "fixture_control_invalid"})
        finally:
            if "observation" in locals():
                observation["terminal_monotonic"] = time.monotonic()
                note("control-terminal", observation)

    class ObservedApplication:
        async def __call__(self, scope, receive, send):
            if scope["type"] == "lifespan":
                await application(scope, receive, send)
                return
            if scope["type"] != "http":
                raise RuntimeError("Unexpected fixture scope")
            path, method = scope.get("path", ""), scope.get("method", "")
            if path == "/__s27_fixture__/control" and method == "POST":
                await control(scope, receive, send)
                return
            prefix = "/frame-relay/v1/publication/"
            endpoint = path.removeprefix(prefix) if path.startswith(prefix) else "not-allowed"
            if endpoint.startswith("media/") and re.fullmatch(r"media/[0-9a-f-]{36}", endpoint):
                endpoint = "media"
            allowed = ((method == "GET" and endpoint == "media") or (method == "POST" and endpoint in
                ("manifest", "distributions", "operations/lookup", "confirmations", "invalidations", "acknowledgements")))
            if not allowed:
                report["blocked_route_count"] = report.get("blocked_route_count", 0) + 1
                await fixed(send, 404, {"code": "fixture_route_not_allowed"})
                return
            if len(report["requests"]) >= 4096:
                report["request_limit_exceeded"] = True
                await fixed(send, 503, {"code": "fixture_request_limit"})
                return
            row = {"sequence": len(report["requests"]) + 1, "endpoint": endpoint, "phase": state["phase"],
                "started_monotonic": time.monotonic(), "status": None, "underlying_status": None,
                "content_type": None, "body_bytes_emitted": 0, "media_bytes_emitted": 0,
                "first_body_monotonic": None, "headers_sent_monotonic": None,
                "handler_returned": False, "terminal_monotonic": None, "response_replaced": False}
            if endpoint == "media":
                row["rendition_id"] = path.rsplit("/", 1)[1]
                values = [v for k, v in scope.get("headers", []) if k.lower() == b"x-framerelay-distribution-id"]
                if len(values) == 1:
                    try:
                        decoded = base64.urlsafe_b64decode(values[0] + b"=" * (-len(values[0]) % 4))
                        row["ticket_sha256"] = hashlib.sha256(decoded).hexdigest()
                    except ValueError:
                        pass
            report["requests"].append(row)
            request_body, response_body = bytearray(), bytearray()
            lose_receipt = endpoint == "confirmations" and state["loss_armed"]

            async def measured_receive():
                message = await receive()
                if message["type"] == "http.request":
                    request_body.extend(message.get("body", b""))
                    if len(request_body) > 262144:
                        raise RuntimeError("Fixture request observation bound exceeded")
                return message

            async def public_send(message):
                if message["type"] == "http.response.start":
                    row["status"] = message["status"]
                    headers = {key.lower(): value.decode("ascii") for key, value in message.get("headers", [])}
                    row["content_type"] = headers.get(b"content-type")
                    row["content_length"] = headers.get(b"content-length")
                    row["content_range"] = headers.get(b"content-range")
                    row["wire_version"] = headers.get(b"x-framerelay-wire-version")
                    row["content_sha256"] = headers.get(b"x-framerelay-content-sha256")
                    row["content_bytes"] = headers.get(b"x-framerelay-content-bytes")
                if (message["type"] == "http.response.body" and message.get("body") and
                        row["content_type"] in ("video/quicktime", "video/mp4")):
                    body = message["body"]
                    if len(body) > 65536:
                        raise RuntimeError("Unexpected canonical stream block size")
                    for offset in range(0, len(body), 4096):
                        block = body[offset:offset + 4096]
                        await send({"type": "http.response.body", "body": block,
                            "more_body": offset + len(block) < len(body) or message.get("more_body", False)})
                        row["body_bytes_emitted"] += len(block)
                        row["media_bytes_emitted"] += len(block)
                        if row["first_body_monotonic"] is None:
                            row["first_body_monotonic"] = time.monotonic()
                        await asyncio.sleep(0.01)
                    return
                await send(message)
                if message["type"] == "http.response.start":
                    row["headers_sent_monotonic"] = time.monotonic()
                elif message["type"] == "http.response.body":
                    count = len(message.get("body", b""))
                    row["body_bytes_emitted"] += count
                    if count and row["first_body_monotonic"] is None:
                        row["first_body_monotonic"] = time.monotonic()
                    if row["content_type"] in ("video/quicktime", "video/mp4"):
                        row["media_bytes_emitted"] += count

            async def measured_send(message):
                if message["type"] == "http.response.start":
                    row["underlying_status"] = message["status"]
                elif message["type"] == "http.response.body" and (endpoint != "media" or row["underlying_status"] not in (200, 206)):
                    response_body.extend(message.get("body", b""))
                    if len(response_body) > 262144:
                        raise RuntimeError("Fixture response observation bound exceeded")
                if not (lose_receipt and row["underlying_status"] == 200):
                    await public_send(message)

            try:
                await application(scope, measured_receive, measured_send)
                row["handler_returned"] = True  # PinnedResponse finally already closed its accepted read FD.
                if request_body:
                    request = json.loads(request_body)
                    row["request_sha256"] = digest(request)
                    for key in ("purpose", "kind", "range", "source_operation_id"):
                        if key in request:
                            row[key] = request[key]
                    if "operation_id" in request:
                        row["operation_id_sha256"] = hashlib.sha256(request["operation_id"].encode()).hexdigest()
                if response_body:
                    response = json.loads(response_body)
                    if row["underlying_status"] == 200:
                        row["result_sha256"] = digest(response["result"])
                        if endpoint == "operations/lookup":
                            row["lookup_original_request_sha256"] = digest(response["result"]["original_request"])
                            row["lookup_original_result_sha256"] = digest(response["result"]["original_result"])
                        if endpoint == "manifest":
                            row["current_rendition_id"] = (response["result"]["current"] or {}).get("rendition_id")
                        if endpoint == "invalidations":
                            row["invalidation_count"] = len(response["result"]["invalidations"])
                    else:
                        row["error_code"] = response.get("code")
                if lose_receipt and row["underlying_status"] == 200:
                    state["loss_armed"] = False
                    report["response_loss_count"] += 1
                    row["response_replaced"] = True
                    await fixed(public_send, 503, {"schema_version": "fr-publication-v1",
                        "code": "publication_result_unknown", "retryable": True})
            except BaseException as error:
                row["failure_type"] = type(error).__name__
                if row["status"] is None:
                    await fixed(public_send, 503, {"code": "fixture_handler_failed"})
            finally:
                row["terminal_monotonic"] = time.monotonic()
                note("request-terminal", row)

    def ready(origin):
        fixture_json = json.dumps(metadata, sort_keys=True, separators=(",", ":"))
        if len(fixture_json.encode()) > 16384:
            raise RuntimeError("Fixture metadata exceeds reviewed environment bound")
        environment = {"FR_S27_HTTP_FIXTURE": "1", "FR_S27_ORIGIN": origin,
            "FR_S27_BEARER": settings.api_token, "FR_S27_REGISTRATION_SECRET": registration_secret,
            "FR_S27_FIXTURE_SECRET": control_secret, "FR_S27_FIXTURE_JSON": fixture_json}
        helper.write_json(secret_path, {"run_identity": config["run_identity"], "listener_pid": os.getpid(),
            "url": origin, "environment": environment}, private=True)
        report["ready"] = True
        helper.write_json(runtime / "listener-ready.json", {"pid": os.getpid(), "url": origin,
            "run_identity": config["run_identity"], "started_monotonic": started,
            "deadline_monotonic": started + 1200, "deadline_seconds": 1200})

    def should_stop():
        path = runtime / "stop.request"
        if path.exists():
            try:
                value = helper.read_json(path)
            except json.JSONDecodeError:
                return None
            if value.get("run_identity") != config["run_identity"] or value.get("listener_pid") != os.getpid():
                raise RuntimeError("Stop identity mismatch")
            return "reviewed-stop"
        return None

    try:
        asyncio.run(lifecycle.serve_observed(ObservedApplication(), report, note, ready, should_stop, deadline=started + 1200))
        report["final_manifest"] = manifest()
        report["replacement"] = state["replacement"]
        report["publication"] = state["publication"]
    except BaseException as error:
        report["failure_type"] = type(error).__name__
    finally:
        created_threads = [thread for thread in threading.enumerate() if thread not in before_threads]
        report["created_threads"], report["thread_join_failures"] = [], []
        for thread in created_threads:
            row = {"id": thread.ident, "name": thread.name, "daemon": thread.daemon, "join_returned": False}
            try:
                thread.join(timeout=5)
                row["join_returned"] = True
            except BaseException as error:
                row["failure_type"] = type(error).__name__
                report["thread_join_failures"].append(dict(row))
            row["alive_after_join"] = thread.is_alive()
            report["created_threads"].append(row)
        report["all_created_threads_joined"] = (not report["thread_join_failures"] and
            all(row["join_returned"] and not row["alive_after_join"] for row in report["created_threads"]))
        if secret_path.exists():
            secret_path.unlink()
        report["secret_deleted"] = not secret_path.exists()
        report["wire_observation"] = helper.publication_observations(report)
        report["passed"] = (all(report.get(key) is True for key in ("ready", "server_terminated", "listener_fd_closed",
            "all_created_threads_joined", "secret_deleted")) and report.get("remaining_server_connections") == 0 and
            report.get("remaining_server_tasks") == 0 and report["stop_reason"] == "reviewed-stop" and not report["signals"] and
            not report.get("forced_server_task_cancel") and not report.get("request_limit_exceeded") and
            not report.get("blocked_route_count") and "failure_type" not in report and
            all(value is True for value in report["wire_observation"].values()))
        events.close()
        helper.write_json(runtime / "listener-results.json", report)
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    if sys.version_info[:2] != (3, 12) or sys.platform != "darwin" or not (
            sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
        raise RuntimeError("Require reviewed macOS Python 3.12 -I -B -S")
    helper = load_helper()
    config, checkpoint = helper.verified_config(args.config)
    support, preparation = Path(__file__).resolve().parent, Path(config["preparation"])
    if support != preparation / "source-snapshot":
        raise RuntimeError("Use frozen publication listener sources")
    provenance = helper.verify_inputs(config, checkpoint)
    if helper.record(Path(sys.executable).resolve()) != provenance["interpreter"]["resolved_record"]:
        raise RuntimeError("Unexpected executable")
    runtime, backend = Path(config["runtime"]), Path(config["snapshot"]) / "backend"
    if runtime.exists() or runtime.is_symlink():
        raise RuntimeError("Require fresh publication runtime")
    runtime.mkdir()
    runner, guard_module = helper.module("run_pytest"), helper.module("isolation_guard")
    guard = guard_module.Guard(runtime, allow_loopback_listener=True)
    guard.install()
    initial_fds = runner.fd_inventory(guard)
    inherited_home = os.environ.get("HOME")
    preserved = {k: os.environ[k] for k in ("HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ") if k in os.environ}
    os.environ.clear()
    os.environ.update(preserved)
    explicit = runner.settings_environment(runtime)
    os.environ.update(explicit)
    os.environ.update({"PATH": "/usr/bin:/bin", "TMPDIR": str(runtime / "tmp"), "TMP": str(runtime / "tmp"),
        "TEMP": str(runtime / "tmp"), "SQLITE_TMPDIR": str(runtime / "sqlite-tmp"),
        "XDG_CACHE_HOME": str(runtime / "cache"), "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1"})
    for directory in ("tmp", "sqlite-tmp", "cache", "media", "user-lut"):
        (runtime / directory).mkdir()
    shutil.copytree(backend / "assets", runtime / "assets")
    os.chdir(runtime)
    os.environ["PWD"] = str(runtime)
    sys.path.extend((str(backend), provenance["site_packages_root"]))
    result = {"run_identity": config["run_identity"], "pid": os.getpid(), "passed": False, "fixture_only": True,
        "initial_fds": initial_fds, "settings_environment": {
            key: "<redacted ephemeral token>" if key == "API_TOKEN" else value for key, value in explicit.items()},
        "home_inherited_unchanged": os.environ.get("HOME") == inherited_home}
    threads_before_backend = set(threading.enumerate())
    try:
        from app.core.settings import load_settings
        settings = load_settings()
        effective = dataclasses.asdict(settings)
        if len(explicit) != 22 or len(effective) != 22:
            raise RuntimeError("Settings shape changed")
        for key, value in effective.items():
            environment_key = "APPLE_LOG_DETECTOR_ROOT" if key == "detector_root" else key.upper()
            if str(value) != explicit[environment_key]:
                raise RuntimeError("Effective setting differs from explicit configuration")
        effective["api_token"] = "<redacted ephemeral token>"
        helper.write_json(runtime / "effective-settings-redacted.json", {
            key: str(value) if isinstance(value, Path) else value for key, value in effective.items()})
        movie = runtime / "media/fixture-input.mov"
        helper.copy(Path(config["fixture"]["path"]), movie)
        if helper.record(movie) != config["fixture_record"]:
            raise RuntimeError("Fixture copy changed")
        listener = run_fixture(helper, helper.module("listener_lifecycle"), runtime, config, settings, movie)
        result["listener_passed"] = listener["passed"]
    except BaseException as error:
        result["failure_type"] = type(error).__name__
    finally:
        secret = runtime / "fixture-env.json"
        if secret.exists():
            secret.unlink()
        os.environ.pop("API_TOKEN", None)
        explicit.pop("API_TOKEN", None)
        # Preserve owner evidence BEFORE Guard.finish attempts rescue-close of
        # main-thread survivors. Keep weak-set survivors strongly referenced
        # during this snapshot; GC cannot make a live connection look closed.
        owner_observation = {"passed": False, "sqlite_owner_explicit_close_complete": False,
            "database_media_fds_remaining": None}
        result["fd_before_guard_finish"] = None
        result["remaining_created_threads_before_guard_finish"] = [{"id": thread.ident, "name": thread.name}
            for thread in threading.enumerate() if thread not in threads_before_backend]
        try:
            owner_survivors = tuple(guard.connections)
            owner_events = [dict(event) for event in guard.connection_events]
            owner_tracked = [{"id": id(connection), "owner_thread": connection._s20_thread}
                for connection in owner_survivors]
            result["fd_before_guard_finish"] = runner.fd_inventory(guard)
            owner_observation = helper.owner_close_observation(owner_events, owner_tracked,
                result["fd_before_guard_finish"], initial_fds, runtime)
            result["owner_close_before_guard_finish"] = {"connection_events": owner_events,
                "tracked_connections": owner_tracked, "observation": owner_observation}
        except BaseException as error:
            result["owner_close_audit_failure_type"] = type(error).__name__
            result["owner_close_before_guard_finish"] = {"observation": owner_observation, "incomplete": True}
        finally:
            result["guard"] = guard.finish()
        result["fd_after_guard_finish"] = runner.fd_inventory(guard)
        result["sqlite_explicit_close_complete"] = owner_observation["sqlite_owner_explicit_close_complete"]
        helper.verify_inputs(config, checkpoint)
        result["inputs_unchanged"] = True
        result["sources_unchanged"] = helper.tree(support) == checkpoint["source_files"]
        result["snapshot_unchanged"] = helper.tree(Path(config["snapshot"])) == checkpoint["backend_snapshot"]
        origins = {name: str(Path(value.__file__).resolve()) for name, value in sys.modules.items() if getattr(value, "__file__", None)}
        allowed = (support, Path(config["snapshot"]), Path(provenance["site_packages_root"]).resolve(), Path(sys.base_prefix).resolve())
        unexpected = {name: path for name, path in origins.items() if not any(Path(path).is_relative_to(root) for root in allowed)}
        result["unexpected_import_origins"] = unexpected
        helper.write_json(runtime / "import-origins.json", origins)
        result["database_media_fds_remaining"] = owner_observation["database_media_fds_remaining"]
        post_rescue_fds = helper.owner_close_observation([], [], result["fd_after_guard_finish"], initial_fds, runtime)
        result["database_media_fds_after_guard_finish"] = post_rescue_fds["database_media_fds_remaining"]
        result["unresolved_new_regular_fds_after_guard_finish"] = post_rescue_fds["unresolved_new_regular_fds"]
        result["passed"] = (result.get("listener_passed") is True and "failure_type" not in result and
            result["inputs_unchanged"] and result["sources_unchanged"] and result["snapshot_unchanged"] and
            owner_observation["passed"] is True and result["sqlite_explicit_close_complete"] and
            not result["remaining_created_threads_before_guard_finish"] and
            result["guard"]["sqlite_connections_alive_before_explicit_close"] == 0 and
            not result["guard"]["foreign_thread_connections_not_explicitly_closed"] and
            not result["guard"]["sqlite_close_failures"] and result["guard"]["sqlite_connections_alive_after_explicit_close"] == 0 and
            post_rescue_fds["passed"] is True and
            not unexpected and not guard.denials and not result["database_media_fds_remaining"] and
            guard.listener_bind_count == 1 and not secret.exists())
        helper.write_json(runtime / "result.json", result)
        guard.log.flush()
    print(json.dumps({"runtime": str(runtime), "passed": result["passed"], "fixture_only": True}))
    return 0 if result["passed"] else 70


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"passed": False, "failure_type": type(error).__name__}))
        raise SystemExit(70) from None
