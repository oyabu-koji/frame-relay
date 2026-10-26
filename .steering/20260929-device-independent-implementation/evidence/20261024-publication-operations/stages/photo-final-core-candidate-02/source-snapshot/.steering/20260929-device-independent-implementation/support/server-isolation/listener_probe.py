"""Opt-in real loopback server for the separately reviewed Simulator probe.

Never started by preparation or pytest. Movie is a synthetic non-Log technical
fixture. Legacy seed fields are contract input, not new product receipt evidence.
"""
import asyncio
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import stat
import threading
import time


MOVIE_SHA256 = "0f567596a4bd101d970dc978f38a2bd1095cefb470a66fc2e0c4b6a11f3df725"
PREFIX_SHA256 = "5d32ee3573b79172661c4434dae00e25ade8be29c54f822d47f96dec78f435d8"
MOVIE_BYTES = 485721


def write_json(path, value, *, private=False):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600 if private else 0o644)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def run(runtime, config):
    from app.core.settings import load_settings
    from app.db.connection import connect
    from app.db.migrations import run_migrations
    from app.main import app
    from app.services.storage import initialize_storage
    from app.services import processed_result_stream as stream
    from tests.test_processed_result_streaming_api import _create_deliverable
    import uvicorn

    movie = Path(config["synthetic_movie"]).resolve(strict=True)
    body = movie.read_bytes()
    if len(body) != MOVIE_BYTES or hashlib.sha256(body).hexdigest() != MOVIE_SHA256:
        raise RuntimeError("Preserved synthetic Movie identity mismatch")
    if hashlib.sha256(body[:64]).hexdigest() != PREFIX_SHA256:
        raise RuntimeError("Synthetic Movie prefix mismatch")
    deadline_seconds = config.get("listener_deadline_seconds")
    run_identity = config.get("run_identity")
    if deadline_seconds != 1200 or not isinstance(run_identity, str) or not run_identity:
        raise RuntimeError("Unreviewed listener deadline")
    settings = load_settings()
    initialize_storage(settings.media_root)
    local_movie = runtime / "synthetic-source.mov"
    with local_movie.open("xb") as copy:
        copy.write(body)
    connection = connect(settings.database_path, settings.sqlite_busy_timeout_ms)
    try:
        run_migrations(connection)
        with connection:
            asset, result, _derived, delivered_path = _create_deliverable(
                connection, settings.media_root, ordinal=1, content=body)
    finally:
        connection.close()
    if hashlib.sha256(delivered_path.read_bytes()).hexdigest() != MOVIE_SHA256:
        raise RuntimeError("Actual seeded delivery bytes mismatch")

    secret_path = runtime / "simulator-probe-env.json"
    stop_path = runtime / "stop.request"
    events_path = runtime / "listener-events.jsonl"
    events = events_path.open("x")
    event_lock = threading.Lock()
    report = {"pid": os.getpid(), "run_identity": run_identity,
        "bind": "127.0.0.1:0", "deadline_seconds": deadline_seconds,
        "source_movie": str(movie), "sha256": MOVIE_SHA256, "byte_count": MOVIE_BYTES,
        "prefix_sha256": PREFIX_SHA256, "result_id": result["id"], "asset_id": asset["id"],
        "interpretation": "legacy non-Log synthetic fixture; not actual upload verification, Log conversion or product distribution receipt",
        "stop_reason": None, "signals": [], "descriptors": [], "ready": False,
        "server_terminated": False, "secret_deleted": False, "passed": False}
    original_iterator = stream.iter_open_file
    descriptor_refs = []
    listening = None
    server = None

    def note(event, detail):
        with event_lock:
            events.write(json.dumps({"event": event, "detail": detail, "monotonic": time.monotonic()}) + "\n")
            events.flush()

    def measured_iterator(file, *, start, end):
        record = {"fd": file.fileno(), "start": start, "end": end, "bytes_yielded": 0,
                  "closed_at_acceptance": file.closed, "iterator_terminated": False}
        descriptor_refs.append((file, record))
        report["descriptors"].append(record)
        note("descriptor-accepted", dict(record))

        def consume():
            try:
                for block in original_iterator(file, start=start, end=end):
                    record["bytes_yielded"] += len(block)
                    yield block
            finally:
                record["iterator_terminated"] = True
                record["closed_after_iterator"] = file.closed
                note("descriptor-iterator-terminal", dict(record))
        return consume()

    class ObservedServer(uvicorn.Server):
        @contextmanager
        def capture_signals(self):
            # Uvicorn's default re-raises captured SIGTERM after shutdown. This
            # launcher records the signal and completes evidence/secret cleanup.
            def handler(signum, _frame):
                report["signals"].append(signum)
                report["stop_reason"] = "signal-" + signal.Signals(signum).name
                self.should_exit = True
                note("stop-signal", {"signal": signum})
            old = {sig: signal.signal(sig, handler) for sig in (signal.SIGINT, signal.SIGTERM)}
            try:
                yield
            finally:
                for sig, previous in old.items():
                    signal.signal(sig, previous)

    async def serve():
        nonlocal server, listening
        # Creation/bind is reached only by explicit listener action and allow flag.
        listening = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listening.bind(("127.0.0.1", 0))
        listening.setblocking(False)
        address, port = listening.getsockname()
        report["actual_address"] = address
        report["actual_port"] = port
        server = ObservedServer(uvicorn.Config(app, host="127.0.0.1", port=0, loop="asyncio", http="h11",
            ws="none", lifespan="on", log_config=None, access_log=False, proxy_headers=False,
            workers=1, reload=False, timeout_graceful_shutdown=5))
        task = asyncio.create_task(server.serve(sockets=[listening]))
        started = time.monotonic()
        try:
            while not server.started:
                if task.done():
                    await task
                    raise RuntimeError("Server exited before actual startup")
                if time.monotonic() - started > 30:
                    raise TimeoutError("Actual server startup deadline exceeded")
                await asyncio.sleep(0.05)
            url = f"http://127.0.0.1:{port}/assets/{asset['id']}/results/{result['id']}"
            secret = {"FR_LEGACY_PLAYBACK_PROBE": "1", "FR_LEGACY_PROBE_URL": url,
                "FR_LEGACY_PROBE_RESULT_ID": result["id"], "FR_LEGACY_PROBE_SHA256": MOVIE_SHA256,
                "FR_LEGACY_PROBE_BYTE_COUNT": str(MOVIE_BYTES), "FR_LEGACY_PROBE_PREFIX_SHA256": PREFIX_SHA256,
                "FR_LEGACY_PROBE_TOKEN": settings.api_token}
            active_started = time.monotonic()
            write_json(secret_path, {"run_identity": run_identity, "listener_pid": os.getpid(),
                "started_monotonic": active_started, "environment": secret}, private=True)
            if stat.S_IMODE(secret_path.stat().st_mode) != 0o600:
                raise RuntimeError("Secret environment file is not 0600")
            report["ready"] = True
            report["active_started_monotonic"] = active_started
            ready = {"pid": os.getpid(), "url": url, "secret_environment_file": str(secret_path),
                "run_identity": run_identity, "started_monotonic": active_started,
                "deadline_monotonic": active_started + deadline_seconds,
                "deadline_seconds": deadline_seconds, "result_id": result["id"], "sha256": MOVIE_SHA256,
                "byte_count": MOVIE_BYTES, "prefix_sha256": PREFIX_SHA256}
            write_json(runtime / "listener-ready.json", ready)
            print(json.dumps({"listener_ready": True, "runtime": str(runtime), "pid": os.getpid(), "url": url}), flush=True)
            while not task.done():
                if stop_path.exists():
                    report["stop_reason"] = "reviewed-stop-file"
                    server.should_exit = True
                elif time.monotonic() - active_started >= deadline_seconds:
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
        stream.iter_open_file = measured_iterator
        asyncio.run(serve())
        report["passed"] = report["server_terminated"] and not report.get("forced_server_task_cancel", False)
    finally:
        stream.iter_open_file = original_iterator
        if listening is not None:
            listening.close()
            report["listener_fd_closed"] = listening.fileno() == -1
        if secret_path.exists():
            secret_path.unlink()
        report["secret_deleted"] = not secret_path.exists()
        for file, record in descriptor_refs:
            record["closed_at_server_end"] = file.closed
            if not file.closed:
                report["passed"] = False
                file.close()
                record["emergency_cleanup_close"] = True
        report["source_movie_unchanged"] = hashlib.sha256(movie.read_bytes()).hexdigest() == MOVIE_SHA256
        report["passed"] = report["passed"] and report["source_movie_unchanged"] and report["secret_deleted"]
        note("listener-end", {key: value for key, value in report.items() if key != "descriptors"})
        events.close()
        write_json(runtime / "listener-results.json", report)
    return report
