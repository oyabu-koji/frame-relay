"""Prepare and run the separately reviewed S28 metadata-only loopback fixture.

Preparation imports stdlib/local metadata helpers only. Backend/site-packages
are imported by --listen after the unchanged guard is installed. Parent main
must observe actual process exit and combine the separate iOS test evidence.
"""
import argparse
import ast
import asyncio
from contextlib import closing, contextmanager
import dataclasses
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import socket
import stat
import sys
import threading
import time
from urllib.parse import parse_qs
from uuid import uuid4


VERSION = "fr-s28-inventory-fixture-v1"
TEST = "FrameRelayTests/RemoteInventoryHTTPFixtureTests/discoverOriginalsAcrossRegistrationsAndReopen"
INVENTORY_PATH = "/frame-relay/v1/uploads/inventory"


def module(name):
    path = Path(__file__).with_name(name + ".py")
    spec = importlib.util.spec_from_file_location("inventory_" + name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = value
    spec.loader.exec_module(value)
    return value


def prepare(base, revision):
    life = module("listener_lifecycle")
    if not base.is_absolute():
        raise RuntimeError("Expected an absolute backend preparation path")
    base = base.resolve(strict=True)
    if (not base.is_absolute() or re.fullmatch(r"preparation-[0-9]{3}", base.name) is None
            or base.parent.name != "S28-inventory" or re.fullmatch(r"[0-9]{3}", revision or "") is None):
        raise RuntimeError("Expected reviewed S28 backend preparation and a fresh HTTP revision")
    checkpoint = life.read_json(base / "checkpoint-files.json")
    backend_config = life.read_json(base / "run-config.json")
    snapshot = Path(backend_config["snapshot"])
    support = Path(__file__).resolve().parent
    sources = life.tree(support)
    inherited_isolation = {name.removeprefix("server-isolation/"): value
        for name, value in checkpoint["frozen_sources"].items() if name.startswith("server-isolation/")}
    if (backend_config.get("action") != "pytest" or snapshot.parent != base.parent
            or life.tree(snapshot) != checkpoint["snapshot"]
            or life.record(base / "run-config.json") != checkpoint["config"]
            or life.record(Path(backend_config["provenance"])) != checkpoint["provenance"]
            or life.tree(base / "source-snapshot") != checkpoint["frozen_sources"]
            or sources != inherited_isolation):
        raise RuntimeError("Backend or jointly frozen HTTP sources changed")
    for name in sources:
        if name.endswith(".py"):
            text = (support / name).read_text()
            ast.parse(text, filename=name)
            compile(text, name, "exec", dont_inherit=True)
    preparation = base.parent / ("http-preparation-" + revision)
    runtime = base.parent / ("runtime-http-inventory-" + revision)
    if any(path.exists() or path.is_symlink() for path in (preparation, runtime)):
        raise RuntimeError("Refusing to reuse HTTP preparation or runtime")
    preparation.mkdir()
    frozen = preparation / "source-snapshot"
    for name in sources:
        target = frozen / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with (support / name).open("rb") as reader, target.open("xb") as writer:
            shutil.copyfileobj(reader, writer)
    if life.tree(support) != sources or life.tree(frozen) != sources:
        raise RuntimeError("HTTP sources changed while freezing")
    manifest = preparation / "source-manifest.json"
    life.write_json(manifest, {"files": sources, "backend_checkpoint": life.record(base / "checkpoint-files.json")})
    config = {**backend_config, "action": "inventory-metadata-listener", "runtime": str(runtime),
        "run_identity": str(uuid4()), "deadline_seconds": 600, "backend_preparation": str(base),
        "backend_checkpoint": life.record(base / "checkpoint-files.json"),
        "http_source_manifest": str(manifest), "http_source_manifest_sha256": life.record(manifest)["sha256"],
        "allow_reviewed_loopback_listener": True, "fixture_schema": VERSION,
        "guard_contract": "unchanged Guard, one 127.0.0.1:0 bind, no outbound network/subprocess"}
    config_path = preparation / "config.json"
    life.write_json(config_path, config)
    checkpoint_path = preparation / "checkpoint.json"
    life.write_json(checkpoint_path, {"config": life.record(config_path), "source_manifest": life.record(manifest),
        "backend_checkpoint": life.record(base / "checkpoint-files.json"), "runtime_created": False, "executed": False})
    digest = life.record(checkpoint_path)["sha256"]
    prefix = [config["interpreter"], "-I", "-B", "-S", str(frozen / "prepare_inventory_probe.py")]
    common = ["--config", str(config_path), "--checkpoint-sha256", digest]
    life.write_json(preparation / "commands.json", {"listen": prefix + ["--listen", *common],
        "stop": prefix + ["--stop", *common], "client_test": TEST,
        "client_environment": {"TEST_RUNNER_FR_S28_INVENTORY_HTTP": "1",
            "TEST_RUNNER_FR_S28_INVENTORY_CONFIG": str(runtime / "inventory-env.json")},
        "attachment": "s28-inventory-observation.json", "actual_execution_and_child_exit": "parent main only"})
    for path in preparation.rglob("*"):
        if path.is_file():
            path.chmod(0o444)
    print(json.dumps({"preparation": str(preparation), "checkpoint_sha256": digest,
        "runtime_created": False, "backend_imported": False, "executed": False}))


def checked_config(path, digest):
    life = module("listener_lifecycle")
    if (not path.is_absolute() or path.name != "config.json"
            or re.fullmatch(r"http-preparation-[0-9]{3}", path.parent.name) is None
            or path.parent.parent.name != "S28-inventory" or re.fullmatch(r"[0-9a-f]{64}", digest or "") is None):
        raise RuntimeError("Expected the exact prepared HTTP configuration and checkpoint hash")
    checkpoint_path = path.parent / "checkpoint.json"
    if life.record(checkpoint_path)["sha256"] != digest:
        raise RuntimeError("HTTP checkpoint differs from parent review")
    checkpoint = life.read_json(checkpoint_path)
    config = life.read_json(path)
    manifest = Path(config["http_source_manifest"])
    support = Path(__file__).resolve().parent
    backend = Path(config["backend_preparation"])
    backend_checkpoint = life.read_json(backend / "checkpoint-files.json")
    snapshot = Path(config["snapshot"])
    runtime = Path(config["runtime"])
    if (life.record(path) != checkpoint["config"] or life.record(manifest) != checkpoint["source_manifest"]
            or life.record(manifest)["sha256"] != config["http_source_manifest_sha256"]
            or life.tree(support) != life.read_json(manifest)["files"]
            or config["backend_checkpoint"] != checkpoint["backend_checkpoint"]
            or life.record(backend / "checkpoint-files.json") != config["backend_checkpoint"]
            or life.tree(snapshot) != backend_checkpoint["snapshot"]
            or runtime.parent != snapshot.parent or runtime.parent != path.parent.parent
            or re.fullmatch(r"runtime-http-inventory-[0-9]{3}", runtime.name) is None
            or runtime.is_symlink() or config.get("fixture_schema") != VERSION
            or config.get("action") != "inventory-metadata-listener"
            or config.get("allow_reviewed_loopback_listener") is not True
            or type(config.get("deadline_seconds")) is not int or config["deadline_seconds"] != 600):
        raise RuntimeError("HTTP configuration/input/root contract changed")
    return life, config


def stop(path, digest):
    life, config = checked_config(path, digest)
    runtime = Path(config["runtime"])
    ready = life.read_json(runtime / "listener-ready.json")
    if ready["run_identity"] != config["run_identity"] or ready["config_sha256"] != life.record(path)["sha256"]:
        raise RuntimeError("Runtime identity differs from prepared listener")
    life.write_json(runtime / "stop-request.json", {"run_identity": config["run_identity"],
        "config_sha256": life.record(path)["sha256"], "checkpoint_sha256": digest})
    print(json.dumps({"stop_requested": True, "runtime": str(runtime), "process_exit_observed": False}))


def logical_database(settings):
    from app.db.connection import connect
    with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
        names = [row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        return {name: sorted(json.dumps(dict(row), sort_keys=True) for row in conn.execute('SELECT * FROM "' + name + '"'))
            for name in names}


def canonical_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()).hexdigest()


def media_inventory(root):
    return {str(path.relative_to(root)): {"bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(root.rglob("*")) if path.is_file()}


def make_fixture(settings, config):
    # Every non-stdlib import in this function occurs after Guard.install().
    from fastapi import FastAPI
    from app.api.frame_relay_storage import router as storage_router
    from app.api.registrations import router as registration_router
    from app.api.registrations import _error as registration_error_response
    from app.db.connection import connect
    from app.db.migrations import run_migrations
    from app.db.frame_relay_migrations import run_frame_relay_migrations
    from app.repositories import registrations
    from app.repositories.frame_relay_storage import StorageError
    from app.repositories.registrations import RegistrationError
    from app.repositories.jobs import claim_next_job
    from app.services import frame_relay_storage as storage
    from app.services import frame_relay_finalize as finalize
    from fastapi.responses import JSONResponse
    import sqlite3

    with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
        run_migrations(conn)
        run_frame_relay_migrations(conn)
        destination = registrations.destination_identity(conn)
        old_secret = secrets.token_hex(32)
        old_registration = registrations.register(conn, destination_id=destination, operation_id=str(uuid4()), secret=old_secret)
    expected = []

    async def body(data):
        yield data

    for index in range(33):
        data = ("inventory-" + str(index).zfill(6)).encode("ascii")
        request = {"destination_id": destination, "registration_id": old_registration["registration_id"],
            "registration_generation": old_registration["generation"], "operation_id": str(uuid4()),
            "capture_id": "  ../Inventory/試験?x=1#原本  " if index == 0 else "inventory-" + config["run_identity"] + "-" + str(index),
            "content_generation": "1", "sha256": hashlib.sha256(data).hexdigest(), "byte_count": str(len(data))}
        value = storage.create(settings, request, old_secret)
        asyncio.run(storage.receive_chunk(settings, value["session_id"], request, old_secret, 0,
            (0, len(data)-1, len(data)), request["sha256"], body(data)))
        storage.finalize(settings, value["session_id"], request, old_secret)
        with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
            job = claim_next_job(conn, settings.job_lease_seconds, ("fr_upload_finalize",))
        if job is None or not finalize.process_finalize(settings=settings, job=job):
            raise RuntimeError("Synthetic original seed failed before inventory fixture")
        expected.append((value["session_id"], {key: request[key] for key in ("capture_id", "content_generation", "sha256", "byte_count")}))
    application = FastAPI(docs_url=None, redoc_url=None, openapi_url=None, redirect_slashes=False)
    application.include_router(registration_router)
    routes = [route for route in storage_router.routes if route.path == INVENTORY_PATH and route.methods == {"GET"}]
    if len(routes) != 1:
        raise RuntimeError("Expected the exact canonical authenticated inventory APIRoute")
    application.router.routes.extend(routes)

    async def storage_error(_request, error):
        return JSONResponse(status_code=409, content={"code": error.code, "retryable": False}, headers={"Cache-Control": "no-store"})

    async def registration_error(_request, error):
        return registration_error_response(error)

    async def database_error(_request, _error):
        return JSONResponse(status_code=503, content={"code": "storage_unavailable", "retryable": True}, headers={"Cache-Control": "no-store"})

    application.add_exception_handler(StorageError, storage_error)
    application.add_exception_handler(RegistrationError, registration_error)
    application.add_exception_handler(sqlite3.DatabaseError, database_error)
    return application, destination, old_registration["registration_id"], [item for _session, item in sorted(expected)]


def serve_fixture(life, runtime, config, path, checkpoint_sha256, settings):
    import uvicorn
    started = time.monotonic()
    deadline = started + config["deadline_seconds"]
    application, destination, old_registration, expected = make_fixture(settings, config)
    before = logical_database(settings)
    before_media = media_inventory(settings.media_root)
    report = {"schema_version": VERSION, "run_identity": config["run_identity"], "fixture_only": True,
        "pid": os.getpid(), "ready": False, "started_monotonic": started, "deadline_monotonic": deadline,
        "deadline_seconds": 600, "signals": [], "stop_reason": None, "requests": [], "active_handlers": 0,
        "metadata_response_bytes": 0, "media_response_bytes": 0, "inventory_db_mutations": 0,
        "request_limit": 128,
        "forbidden_requests": 0, "server_terminated": False, "listener_fd_closed": False,
        "secret_deleted": False, "expected_items": len(expected), "passed": False}
    listening = None
    server = None
    secret_path = runtime / "inventory-env.json"

    class MetadataOnly:
        def __init__(self):
            self.lock = asyncio.Lock()

        async def __call__(self, scope, receive, send):
            if scope["type"] != "http":
                await application(scope, receive, send)
                return
            async with self.lock:
                report["active_handlers"] += 1
                request_path = scope["path"]
                is_inventory = request_path == INVENTORY_PATH and scope["method"] == "GET"
                allowed = (is_inventory or request_path == "/frame-relay/v1/registrations"
                    or request_path.startswith("/frame-relay/v1/registration-intents/")
                    or request_path == "/frame-relay/v1/capabilities")
                allowed = allowed and len(report["requests"]) < report["request_limit"]
                record = {"method": scope["method"], "path": request_path if allowed else "<unrecognized>", "status": None, "response_bytes": 0,
                    "inventory": is_inventory, "terminal": False}
                body_parts = []
                db_before = canonical_digest(logical_database(settings)) if is_inventory else None

                async def measured(message):
                    if message["type"] == "http.response.start":
                        record["status"] = message["status"]
                        content_type = dict(message.get("headers", [])).get(b"content-type", b"").split(b";", 1)[0]
                        record["metadata_json"] = content_type == b"application/json"
                    elif message["type"] == "http.response.body":
                        block = message.get("body", b"")
                        record["response_bytes"] += len(block)
                        if record.get("metadata_json"):
                            report["metadata_response_bytes"] += len(block)
                        else:
                            report["media_response_bytes"] += len(block)
                        if is_inventory and sum(map(len, body_parts)) + len(block) <= 256 * 1024:
                            body_parts.append(block)
                        if not message.get("more_body", False):
                            record["terminal"] = True
                    await send(message)

                try:
                    if allowed:
                        await application(scope, receive, measured)
                    else:
                        report["forbidden_requests"] += 1
                        await measured({"type": "http.response.start", "status": 404, "headers": [(b"content-type", b"application/json")]})
                        await measured({"type": "http.response.body", "body": b'{"code":"fixture_metadata_only"}'})
                    if is_inventory:
                        db_after = canonical_digest(logical_database(settings))
                        record["database_rows_unchanged"] = db_before == db_after
                        report["inventory_db_mutations"] += int(db_before != db_after)
                        params = parse_qs(scope["query_string"].decode("ascii"), strict_parsing=True)
                        record["registration_id"] = params.get("registration_id", [None])[0]
                        record["registration_generation"] = params.get("registration_generation", [None])[0]
                        record["request_cursor_present"] = "cursor" in params
                        result = json.loads(b"".join(body_parts))
                        record["items"] = len(result.get("items", []))
                        record["next_cursor_present"] = result.get("next_cursor") is not None
                finally:
                    report["active_handlers"] -= 1
                    report["requests"].append(record)

    class ObservedServer(uvicorn.Server):
        @contextmanager
        def capture_signals(self):
            def handler(signum, _frame):
                report["signals"].append(signum)
                report["stop_reason"] = "signal"
                self.should_exit = True
            prior = {sig: signal.signal(sig, handler) for sig in (signal.SIGINT, signal.SIGTERM)}
            try:
                yield
            finally:
                for sig, old in prior.items():
                    signal.signal(sig, old)

    async def serve():
        nonlocal listening, server
        listening = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listening.bind(("127.0.0.1", 0))
        listening.setblocking(False)
        address, port = listening.getsockname()
        report["actual_address"], report["actual_port"] = address, port
        server = ObservedServer(uvicorn.Config(MetadataOnly(), host="127.0.0.1", port=0, loop="asyncio", http="h11",
            ws="none", lifespan="off", log_config=None, access_log=False, proxy_headers=False, workers=1, reload=False,
            timeout_keep_alive=1, timeout_graceful_shutdown=5))
        task = asyncio.create_task(server.serve(sockets=[listening]))
        try:
            while not server.started:
                if task.done():
                    await task
                    raise RuntimeError("Inventory listener exited before startup")
                if time.monotonic() - started > 60:
                    raise TimeoutError("Inventory startup deadline exceeded")
                await asyncio.sleep(0.05)
            origin = "http://127.0.0.1:" + str(port)
            life.write_json(secret_path, {"schema_version": VERSION, "run_identity": config["run_identity"],
                "origin": origin, "bearer": settings.api_token, "destination_id": destination,
                "old_registration_id": old_registration, "expected_items": expected}, private=True)
            if stat.S_IMODE(secret_path.stat().st_mode) != 0o600:
                raise RuntimeError("Private fixture config is not 0600")
            life.write_json(runtime / "listener-ready.json", {"pid": os.getpid(), "origin": origin,
                "run_identity": config["run_identity"], "config_sha256": life.record(path)["sha256"],
                "private_config": str(secret_path), "deadline_seconds": 600, "deadline_monotonic": deadline})
            report["ready"] = True
            print(json.dumps({"inventory_listener_ready": True, "runtime": str(runtime), "origin": origin}), flush=True)
            while not task.done():
                stop_path = runtime / "stop-request.json"
                if stop_path.exists():
                    stop_value = life.read_json(stop_path)
                    if stop_value != {"run_identity": config["run_identity"], "config_sha256": life.record(path)["sha256"],
                                      "checkpoint_sha256": checkpoint_sha256}:
                        raise RuntimeError("Unbound stop request")
                    report["stop_reason"] = "reviewed-stop-marker"
                    server.should_exit = True
                elif time.monotonic() >= deadline:
                    report["stop_reason"] = "isolation-deadline"
                    server.should_exit = True
                await asyncio.sleep(0.1)
            await task
            report["server_terminated"] = True
            report["remaining_server_connections"] = len(server.server_state.connections)
            report["remaining_server_tasks"] = len(server.server_state.tasks)
        finally:
            server.should_exit = True
            if not task.done():
                try:
                    await asyncio.wait_for(asyncio.shield(task), timeout=10)
                    report["server_terminated"] = True
                except asyncio.TimeoutError:
                    task.cancel()
                    try:
                        await task
                    except asyncio.CancelledError:
                        pass
                    report["forced_server_task_cancel"] = True

    try:
        asyncio.run(serve())
        after = logical_database(settings)
        mutable = {"fr_registrations", "fr_destination"}
        report["old_and_unrelated_rows_unchanged"] = all(after.get(name) == rows for name, rows in before.items() if name not in mutable)
        report["old_registration_retained"] = set(before["fr_registrations"]).issubset(set(after["fr_registrations"]))
        report["new_registration_count"] = len(after["fr_registrations"]) - len(before["fr_registrations"])
        report["media_hashes_unchanged"] = media_inventory(settings.media_root) == before_media
        report["before_media_sha256"] = canonical_digest(before_media)
        report["after_media_sha256"] = canonical_digest(media_inventory(settings.media_root))
        report["before_retained_rows_sha256"] = canonical_digest({name: rows for name, rows in before.items() if name not in mutable})
        report["after_retained_rows_sha256"] = canonical_digest({name: rows for name, rows in after.items() if name not in mutable})
        inventory = [entry for entry in report["requests"] if entry["inventory"]]
        report["inventory_pages"] = len(inventory)
        report["inventory_items"] = sum(entry.get("items", 0) for entry in inventory)
        report["all_handlers_terminal"] = report["active_handlers"] == 0 and all(entry["terminal"] for entry in report["requests"])
        report["passed"] = (report["ready"] and report["server_terminated"] and report["stop_reason"] == "reviewed-stop-marker"
            and not report["signals"] and not report.get("forced_server_task_cancel", False)
            and report.get("remaining_server_connections") == 0 and report.get("remaining_server_tasks") == 0
            and report["all_handlers_terminal"] and report["forbidden_requests"] == 0 and report["media_response_bytes"] == 0
            and report["inventory_db_mutations"] == 0 and report["old_and_unrelated_rows_unchanged"]
            and report["old_registration_retained"] and report["new_registration_count"] == 1 and report["media_hashes_unchanged"]
            and len(inventory) == 2 and [entry.get("items") for entry in inventory] == [32, 1]
            and all(entry["status"] == 200 and entry.get("database_rows_unchanged")
                and entry.get("registration_id") != old_registration and entry.get("registration_generation") == "2" for entry in inventory)
            and len({entry.get("registration_id") for entry in inventory}) == 1
            and [entry["request_cursor_present"] for entry in inventory] == [False, True]
            and [entry["next_cursor_present"] for entry in inventory] == [True, False])
    finally:
        if listening is not None:
            listening.close()
            report["listener_fd_closed"] = listening.fileno() == -1
        if secret_path.exists():
            secret_path.unlink()
        report["secret_deleted"] = not secret_path.exists()
        report["passed"] = report["passed"] and report["listener_fd_closed"] and report["secret_deleted"]
        life.write_json(runtime / "listener-results.json", report)
    return report


def listen(path, digest):
    if (sys.version_info[:2] != (3, 12) or sys.platform != "darwin"
            or not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode)):
        raise RuntimeError("Require reviewed macOS Python3.12 -I -B -S")
    life, config = checked_config(path, digest)
    runner = module("run_pytest")
    snapshot = Path(config["snapshot"]).resolve(strict=True)
    site = Path(config["site_packages"]).resolve(strict=True)
    external = Path(config["external_root"]).resolve(strict=True)
    runtime = Path(config["runtime"])
    provenance = life.read_json(Path(config["provenance"]))
    executable = Path(sys.executable).resolve(strict=True)
    source_before = {name: runner.file_record(external / name) for name in provenance["source_before"]}
    site_before = runner.tree_manifest(site)
    snapshot_before = runner.tree_manifest(snapshot)
    if (executable != Path(config["interpreter"]).resolve(strict=True)
            or runner.file_record(executable) != provenance["interpreter"]["resolved_record"]
            or source_before != provenance["source_before"] or site_before != provenance["site_packages_before"]
            or snapshot_before != provenance["snapshot"] or runtime.exists() or runtime.is_symlink()):
        raise RuntimeError("Input provenance changed or HTTP runtime already exists")
    runtime.mkdir()
    guard_module = module("isolation_guard")
    guard = guard_module.Guard(runtime, allow_missing_ffprobe_version=True, allow_loopback_listener=True)
    guard.install()
    before_fds = runner.fd_inventory(guard)
    before_threads = set(threading.enumerate())
    inherited_home = os.environ.get("HOME")
    preserved = {key: os.environ[key] for key in ("HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ") if key in os.environ}
    os.environ.clear()
    os.environ.update(preserved)
    explicit = runner.settings_environment(runtime)
    os.environ.update(explicit)
    os.environ.update({"PATH": "/usr/bin:/bin", "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1", "TMPDIR": str(runtime / "tmp"),
        "TMP": str(runtime / "tmp"), "TEMP": str(runtime / "tmp"), "SQLITE_TMPDIR": str(runtime / "sqlite-tmp"),
        "XDG_CACHE_HOME": str(runtime / "cache")})
    for directory in ("tmp", "sqlite-tmp", "cache", "media", "user-lut"):
        (runtime / directory).mkdir()
    shutil.copytree(snapshot / "backend/assets", runtime / "assets")
    os.chdir(runtime)
    os.environ["PWD"] = str(runtime)
    sys.path.extend([str(snapshot / "backend"), str(site)])
    life.write_json(runtime / "preflight.json", {"config_sha256": life.record(path)["sha256"], "checkpoint_sha256": digest,
        "guard_sha256": life.record(Path(__file__).with_name("isolation_guard.py"))["sha256"],
        "runner_sha256": life.record(Path(__file__).with_name("run_pytest.py"))["sha256"],
        "home_inherited_unchanged": os.environ.get("HOME") == inherited_home, "settings_count": len(explicit),
        "before_backend_import_fds": before_fds, "listener": "one 127.0.0.1:0 bind", "outbound_network": False,
        "subprocess": "only the inherited exact nonexistent disabled-ffprobe -version allowance"})
    result, failure, observation = 70, None, None
    try:
        from app.core.settings import load_settings
        settings = load_settings()
        effective = dataclasses.asdict(settings)
        if len(effective) != 22:
            raise RuntimeError("Reviewed Settings shape changed")
        effective["api_token"] = "<redacted ephemeral token>"
        life.write_json(runtime / "effective-settings-redacted.json",
            {key: str(value) if isinstance(value, Path) else value for key, value in effective.items()})
        observation = serve_fixture(life, runtime, config, path, digest, settings)
        result = 0 if observation["passed"] else 1
    except BaseException as error:
        failure = {"type": type(error).__name__}
    finally:
        os.environ.pop("API_TOKEN", None)
        explicit.pop("API_TOKEN", None)
        secret = runtime / "inventory-env.json"
        if secret.exists():
            secret.unlink()
        new_threads = [thread for thread in threading.enumerate() if thread not in before_threads and thread is not threading.current_thread()]
        for thread in new_threads:
            thread.join(timeout=10)
        remaining_threads = [{"name": thread.name, "id": thread.ident} for thread in new_threads if thread.is_alive()]
        before_rescue = runner.fd_inventory(guard)
        guard_result = guard.finish()
        pending = set()
        unclosed_at_gc = []
        for entry in guard_result["sqlite_connection_events"]:
            if entry["event"] == "opened": pending.add(entry["id"])
            elif entry["event"] == "closed": pending.discard(entry["id"])
            elif entry["event"] == "garbage_collected" and entry["id"] in pending: unclosed_at_gc.append(entry["id"])
        origins = []
        allowed_roots = (snapshot, site, Path(__file__).resolve().parent, Path(sys.base_prefix).resolve())
        for name, loaded in sorted(sys.modules.items()):
            filename = getattr(loaded, "__file__", None)
            if filename and not any(Path(filename).resolve().is_relative_to(root) for root in allowed_roots):
                origins.append({"module": name, "path": str(Path(filename).resolve())})
        source_after = {name: runner.file_record(external / name) for name in provenance["source_before"]}
        site_after = runner.tree_manifest(site)
        snapshot_after = runner.tree_manifest(snapshot)
        unchanged = source_before == source_after and site_before == site_after and snapshot_before == snapshot_after
        life.write_json(runtime / "provenance-after.json", {"external_source": source_after, "site_packages": site_after,
            "snapshot": snapshot_after, "all_unchanged": unchanged})
        live_media_db = [entry for entry in before_rescue if entry.get("path") and
            (entry["path"].startswith(str(runtime / "db.sqlite3")) or Path(entry["path"]).is_relative_to(runtime / "media"))]
        if (not unchanged or origins or guard.denials or remaining_threads or pending or unclosed_at_gc or live_media_db
                or guard_result["sqlite_connections_alive_before_explicit_close"] != 0
                or guard_result["sqlite_connections_alive_after_explicit_close"] != 0
                or guard_result["foreign_thread_connections_not_explicitly_closed"]
                or guard_result["sqlite_close_failures"]):
            result = 71
        life.write_json(runtime / "result.json", {"execution_kind": "inventory-metadata-listener", "exit_code": result,
            "failure": failure, "inputs_unchanged": unchanged, "unreviewed_import_origins": origins,
            "guard": guard_result, "all_created_threads_joined": not remaining_threads, "remaining_threads": remaining_threads,
            "pending_sqlite_connections": sorted(pending), "unclosed_sqlite_at_gc": unclosed_at_gc,
            "fd_before_rescue": before_rescue, "db_media_fd_before_rescue": live_media_db,
            "fd_after_rescue": runner.fd_inventory(guard), "secret_deleted": not secret.exists(),
            "listener_passed": observation is not None and observation["passed"],
            "process_exit": "parent must observe actual exit; this is a pre-exit inventory",
            "interpretation": "Synthetic storage metadata/new registration over loopback; no real TLS/Wi-Fi/media/Rec709/device acceptance"})
        guard.log.flush()
    print(json.dumps({"runtime": str(runtime), "exit_code": result, "failure_type": None if failure is None else failure["type"]}), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare", action="store_true")
    mode.add_argument("--listen", action="store_true")
    mode.add_argument("--stop", action="store_true")
    parser.add_argument("--backend-preparation", type=Path)
    parser.add_argument("--revision")
    parser.add_argument("--config", type=Path)
    parser.add_argument("--checkpoint-sha256")
    args = parser.parse_args()
    if args.prepare:
        if args.backend_preparation is None:
            parser.error("--prepare requires --backend-preparation")
        prepare(args.backend_preparation, args.revision)
        return 0
    if args.config is None:
        parser.error("--listen/--stop require --config and --checkpoint-sha256")
    if args.stop:
        stop(args.config, args.checkpoint_sha256)
        return 0
    return listen(args.config, args.checkpoint_sha256)


if __name__ == "__main__":
    raise SystemExit(main())
