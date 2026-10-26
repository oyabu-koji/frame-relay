"""S24 guarded actual app/worker listener. Imported only after Guard.install()."""
import asyncio
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import threading
import time

# run_pytest has already loaded this exact sibling before installing its guard.
from listener_lifecycle import (phase_directory, read_json, serve_observed,
                                synthetic_bytes, write_json)


def final_observation(runtime, settings):
    from app.db.connection import connect
    from app.repositories.registrations import destination_identity
    from app.services.frame_relay_storage import evidence, public_binding
    with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
        bindings = [dict(row) for row in conn.execute("SELECT * FROM fr_upload_bindings ORDER BY session_id")]
        if len(bindings) != 1:
            raise RuntimeError("Expected exactly one HTTP upload binding")
        value = bindings[0]
        proof = evidence(conn, value)
        if proof is None:
            raise RuntimeError("Final evidence absent")
        jobs = [dict(row) for row in conn.execute(
            "SELECT id,job_type,status,dedup_key,payload_json,asset_id FROM jobs ORDER BY id")]
        if (len(jobs) != 2 or sorted((j["job_type"], j["status"]) for j in jobs) !=
                [("fr_conversion", "queued"), ("fr_upload_finalize", "done")] or
                conn.execute("SELECT COUNT(*) FROM fr_storage_evidence").fetchone()[0] != 1 or
                conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0] != 1):
            raise RuntimeError("Evidence/registration/job uniqueness mismatch")
        destination = destination_identity(conn)
        generation = conn.execute("SELECT last_generation FROM fr_destination").fetchone()[0]
    # Independent verification is outside every SQLite writer, with a new FD.
    expected = "originals/frame-relay/" + value["session_id"] + ".mov"
    if value["final_path"] != expected:
        raise RuntimeError("Unexpected final path")
    path = runtime / "media" / expected
    if path.is_symlink() or not path.resolve(strict=True).is_relative_to(runtime / "media"):
        raise RuntimeError("Final file escaped isolated media")
    before = path.stat()
    total, digest = 0, hashlib.sha256()
    with path.open("rb") as stream:
        opened = os.fstat(stream.fileno())
        while block := stream.read(1024 * 1024):
            if block != synthetic_bytes(total, len(block)):
                raise RuntimeError("Independent final bytes differ from HTTP source")
            total += len(block)
            digest.update(block)
        after_fd = os.fstat(stream.fileno())
    after = path.stat()
    fingerprint = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    if (not stat.S_ISREG(before.st_mode) or
            not fingerprint(before) == fingerprint(opened) == fingerprint(after_fd) == fingerprint(after) or
            total != value["byte_count"] or digest.hexdigest() != value["sha256"] or
            proof["byte_count"] != str(total) or proof["sha256"] != digest.hexdigest()):
        raise RuntimeError("Independent final file identity or content mismatch")
    return {"binding": public_binding(value), "evidence": proof, "jobs": jobs,
        "destination_id": destination, "last_generation": generation,
        "independent_final_read": {"byte_count": total, "sha256": digest.hexdigest(),
            "fingerprint": list(fingerprint(after)), "full_bytes_equal": True,
            "new_fd_closed": stream.closed, "outside_sqlite_connection": True}}


def run(runtime, config):
    from app.core.settings import load_settings
    from app.db.connection import connect
    from app.main import app
    from app.repositories.registrations import destination_identity
    from app.workers.worker import run_once

    directory = phase_directory(runtime, config)
    phase = config["storage_phase"]
    if config.get("listener_deadline_seconds") != 240 or not re.fullmatch(
            r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
            config.get("run_identity", "")):
        raise RuntimeError("Unreviewed storage lifetime or run identity")
    settings = load_settings()
    secret_path = directory / "storage-http-env.json"
    started = time.monotonic()
    report = {"pid": os.getpid(), "run_identity": config["run_identity"], "storage_phase": phase,
        "started_monotonic": started, "deadline_monotonic": started + 240,
        "deadline_seconds": 240, "ready": False, "signals": [], "stop_reason": None,
        "server_terminated": False, "worker_joined": False, "secret_deleted": False,
        "passed": False, "response_counts": {}, "worker_calls": []}
    threads_before = set(threading.enumerate())
    stop_worker, wake_worker = threading.Event(), threading.Event()
    worker_error = []
    events = (directory / "listener-events.jsonl").open("x")
    lock = threading.Lock()
    worker = None

    def note(event, detail):
        with lock:
            events.write(json.dumps({"event": event, "detail": detail, "monotonic": time.monotonic()}) + "\n")
            events.flush()

    def work():
        try:
            while not stop_worker.is_set():
                if not wake_worker.wait(0.1):
                    continue
                wake_worker.clear()
                if stop_worker.is_set():
                    break
                # Use the product entry. A second call confirms queued conversion
                # is not claimed; no probe-specific claim/worker implementation.
                for _ in range(2):
                    result = run_once()
                    report["worker_calls"].append(bool(result))
        except BaseException as error:
            worker_error.append(type(error).__name__)
            note("worker-failure", {"type": type(error).__name__})
        finally:
            # Every connection inside run_once belongs to this thread and is
            # explicitly closed by product finally/closing paths, never guard.finish.
            report["worker_function_returned"] = True

    class AllowedRoutes:
        async def __call__(self, scope, receive, send):
            if scope["type"] == "lifespan":
                await app(scope, receive, send)
                return
            path, method = scope.get("path", ""), scope.get("method", "")
            endpoint = None
            if method == "GET" and path == "/frame-relay/v1/capabilities":
                endpoint = "capabilities"
            elif method == "POST" and path == "/frame-relay/v1/registrations" and phase == 1:
                endpoint = "registration"
            elif method == "GET" and re.fullmatch(r"/frame-relay/v1/registration-intents/[0-9a-f-]{36}", path):
                endpoint = "registration-lookup"
            elif method == "POST" and path == "/frame-relay/v1/uploads":
                endpoint = "upload-create"
            elif re.fullmatch(r"/frame-relay/v1/uploads/[0-9a-f-]{36}", path) and method in {"GET", "DELETE"}:
                endpoint = "upload-" + method.lower()
            elif method == "PUT" and re.fullmatch(r"/frame-relay/v1/uploads/[0-9a-f-]{36}/chunks/[0-9]+", path):
                endpoint = "chunk"
            elif method == "POST" and re.fullmatch(r"/frame-relay/v1/uploads/[0-9a-f-]{36}/finalize", path):
                endpoint = "finalize"
            if scope["type"] != "http" or endpoint is None:
                await send({"type": "http.response.start", "status": 404, "headers": []})
                await send({"type": "http.response.body", "body": b'{"code":"probe_route_not_allowed"}'})
                note("blocked-route", {"status": 404})
                return
            success = False

            async def measured_send(message):
                nonlocal success
                if message["type"] == "http.response.start":
                    status = message["status"]
                    success = status == 200
                    key = endpoint + ":" + str(status)
                    report["response_counts"][key] = report["response_counts"].get(key, 0) + 1
                    note("http-response", {"endpoint": endpoint, "status": status})
                await send(message)
            await app(scope, receive, measured_send)
            if endpoint == "finalize" and success:
                wake_worker.set()

    def ready(url):
        nonlocal worker
        with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
            destination = destination_identity(conn)
            count = conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0]
        if count != (0 if phase == 1 else 1):
            raise RuntimeError("Registration count differs from phase contract")
        worker = threading.Thread(target=work, name="s24-product-worker", daemon=False)
        worker.start()
        if phase == 2:
            wake_worker.set()
        write_json(secret_path, {"run_identity": config["run_identity"], "storage_phase": phase,
            "listener_pid": os.getpid(), "url": url, "bootstrap_token": settings.api_token}, private=True)
        if stat.S_IMODE(secret_path.stat().st_mode) != 0o600:
            raise RuntimeError("HTTP credential mode mismatch")
        report.update(ready=True, destination_id=destination)
        write_json(directory / "listener-ready.json", {key: report[key] for key in (
            "pid", "run_identity", "storage_phase", "started_monotonic", "deadline_monotonic",
            "deadline_seconds", "destination_id")} | {"url": url})
        note("ready", {"pid": os.getpid(), "storage_phase": phase})

    def should_stop():
        if worker_error:
            return "worker-failure"
        path = directory / "stop.request"
        if path.exists():
            try:
                value = read_json(path)
            except json.JSONDecodeError:
                return None
            if any(value.get(key) != expected for key, expected in (
                    ("run_identity", config["run_identity"]), ("storage_phase", phase),
                    ("listener_pid", os.getpid()))):
                raise RuntimeError("Stop request identity mismatch")
            return "reviewed-parent-stop"
        return None

    try:
        asyncio.run(serve_observed(AllowedRoutes(), report, note, ready, should_stop, deadline=started + 240))
    except BaseException as error:
        report["failure_type"] = type(error).__name__
    finally:
        stop_worker.set()
        wake_worker.set()
        if worker is not None:
            worker.join(timeout=30)
        report["worker_joined"] = worker is not None and not worker.is_alive()
        # AnyIO endpoint pool threads are stopped by their root asyncio task;
        # observe and join them after asyncio.run's executor/task shutdown.
        created = [thread for thread in threading.enumerate() if thread not in threads_before]
        for thread in created:
            thread.join(timeout=5)
        report["all_created_threads_joined"] = all(not thread.is_alive() for thread in created)
        report["remaining_created_thread_names"] = [thread.name for thread in created if thread.is_alive()]
        report["worker_failure_types"] = worker_error
        report["worker_contract_observed"] = (False in report["worker_calls"] and
            (True in report["worker_calls"] if phase == 1 else True not in report["worker_calls"]))
        if report["server_terminated"] and report["worker_joined"] and not worker_error:
            try:
                report["final_observation"] = final_observation(runtime, settings)
                if phase == 2 and report["final_observation"] != read_json(
                        runtime / "phase-1/listener-results.json")["final_observation"]:
                    raise RuntimeError("Same-disk restart changed final evidence or job identity")
            except BaseException as error:
                report["final_observation_failure_type"] = type(error).__name__
        if secret_path.exists():
            secret_path.unlink()
        report["secret_deleted"] = not secret_path.exists()
        report["passed"] = (all(report.get(key) is True for key in (
            "ready", "server_terminated", "listener_fd_closed", "worker_joined",
            "all_created_threads_joined", "secret_deleted", "worker_contract_observed")) and
            report["stop_reason"] == "reviewed-parent-stop" and not report["signals"] and
            not worker_error and "failure_type" not in report and
            "final_observation" in report and "final_observation_failure_type" not in report and
            not report.get("forced_server_task_cancel", False) and
            report.get("remaining_server_connections") == 0 and report.get("remaining_server_tasks") == 0)
        note("listener-end", report)
        events.close()
        write_json(directory / "listener-results.json", report)
    return report
