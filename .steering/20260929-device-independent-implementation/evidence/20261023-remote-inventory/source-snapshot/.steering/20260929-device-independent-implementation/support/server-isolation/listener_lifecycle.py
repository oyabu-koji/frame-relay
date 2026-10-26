"""S24 metadata/checkpoint helpers. No backend imports or execution at import time."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat


HTTP_CASES = {
    1: ("capabilities_exact_destination", "registration_exact_replay", "upload_exact_replay",
        "operation_content_conflict_rejected", "authorization_mismatches_rejected",
        "binding_mismatch_destination_id_rejected", "binding_mismatch_registration_id_rejected",
        "binding_mismatch_registration_generation_rejected", "binding_mismatch_operation_id_rejected",
        "binding_mismatch_capture_id_rejected", "binding_mismatch_content_generation_rejected",
        "binding_mismatch_sha256_rejected", "binding_mismatch_byte_count_rejected",
        "chunk_content_mismatch_rejected", "chunk_exact_replay", "partial_upload_no_evidence",
        "three_chunks_transport_only", "final_readback_evidence", "finalize_exact_replay",
        "completed_original_cancel_rejected"),
    2: ("capabilities_exact_destination", "restart_same_registration", "restart_same_session_and_evidence",
        "restart_upload_exact_replay", "restart_finalize_exact_replay"),
}


def record(path):
    path = Path(path)
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise RuntimeError("Expected a regular reviewed file")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return {"kind": "file", "size": info.st_size, "sha256": digest.hexdigest()}


def tree(root):
    return {str(path.relative_to(root)): record(path) for path in sorted(root.rglob("*"))
            if path.is_file() or path.is_symlink()}


def read_json(path):
    record(path)
    return json.loads(Path(path).read_text())


def write_json(path, value, *, private=False):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600 if private else 0o644)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def phase_directory(runtime, config):
    phase = config.get("storage_phase")
    if phase not in (1, 2) or type(phase) is not int:
        raise RuntimeError("Only the two reviewed storage phases are permitted")
    if (re.fullmatch(r"runtime-storage-[0-9]{3}", runtime.name) is None or
            runtime.parent.name != "S24" or config.get("action") != "storage-listener"):
        raise RuntimeError("Expected the fresh S24 storage namespace")
    return runtime / ("phase-" + str(phase))


def verify_sources(config, support):
    manifest_path = Path(config["storage_source_manifest"])
    if record(manifest_path)["sha256"] != config["storage_source_manifest_sha256"]:
        raise RuntimeError("Reviewed storage source manifest changed")
    manifest = read_json(manifest_path)
    if tree(support) != manifest["files"]:
        raise RuntimeError("Frozen storage support sources changed")
    return manifest


def disk_inventory(runtime):
    """Same files, including inode identity; never copy/rebuild the live database."""
    paths = [runtime / "db.sqlite3"]
    paths.extend(path for path in runtime.glob("db.sqlite3-*") if path.exists())
    paths.extend(path for path in (runtime / "media").rglob("*") if path.is_file() or path.is_symlink())
    result = {}
    for path in sorted(paths):
        value = record(path)
        info = path.stat()
        result[str(path.relative_to(runtime))] = {**value, "device": info.st_dev, "inode": info.st_ino}
    return result


def termination_evidence(runtime, phase):
    directory = runtime / ("phase-" + str(phase))
    runner = read_json(directory / "result.json")
    listener = read_json(directory / "listener-results.json")
    audit = [json.loads(line) for line in (directory / "audit.jsonl").read_text().splitlines()]
    guard = runner["guard"]
    if (runner.get("exit_code") != 0 or runner.get("inputs_unchanged") is not True or
            runner.get("unreviewed_import_origins") or guard.get("denials") or
            any(item["event"].startswith("denied:") for item in audit) or
            guard.get("sqlite_connections_alive_after_explicit_close") != 0 or
            guard.get("foreign_thread_connections_not_explicitly_closed") or guard.get("sqlite_close_failures") or
            listener.get("passed") is not True or listener.get("storage_phase") != phase or
            not all(listener.get(key) is True for key in ("server_terminated", "listener_fd_closed",
                "worker_joined", "all_created_threads_joined", "secret_deleted")) or
            listener.get("remaining_server_connections") != 0 or listener.get("remaining_server_tasks") != 0):
        raise RuntimeError("Listener/worker/SQLite termination was not fully observed")
    # Explicit close must pair with every open; GC/process exit is not a substitute.
    pending = set()
    unclosed_at_gc = []
    for event in guard["sqlite_connection_events"]:
        if event["event"] == "opened":
            pending.add(event["id"])
        elif event["event"] == "closed":
            pending.discard(event["id"])
        elif event["event"] == "garbage_collected" and event["id"] in pending:
            unclosed_at_gc.append(event["id"])
    if pending or unclosed_at_gc:
        raise RuntimeError("A SQLite connection lacked owner-thread explicit close")
    for fd in runner["fd_after_explicit_sqlite_close"]:
        path = fd.get("path")
        if path and (path.startswith(str(runtime / "db.sqlite3")) or
                     Path(path).is_relative_to(runtime / "media")):
            raise RuntimeError("Database/media descriptor remained before process exit")
    return {name: record(directory / name) for name in (
        "result.json", "listener-results.json", "audit.jsonl", "provenance-after.json")}


def verify_restart(runtime, config, checkpoint_sha256):
    if config.get("storage_phase") != 2 or not re.fullmatch(r"[0-9a-f]{64}", checkpoint_sha256 or ""):
        raise RuntimeError("Phase two requires the parent's exact post-exit checkpoint hash")
    checkpoint_path = runtime / "restart-checkpoint.json"
    if record(checkpoint_path)["sha256"] != checkpoint_sha256:
        raise RuntimeError("Restart checkpoint changed")
    checkpoint = read_json(checkpoint_path)
    if (checkpoint.get("run_identity") != config["run_identity"] or
            checkpoint.get("parent_pid") != os.getppid() or
            checkpoint.get("phase1_actual_exit_observed") is not True or
            checkpoint.get("phase1_exit_code") != 0 or
            checkpoint.get("phase2_config") != record(Path(config["storage_phase2_config"])) or
            checkpoint.get("source_manifest") != record(Path(config["storage_source_manifest"])) or
            checkpoint.get("phase1_config") != record(Path(config["storage_phase1_config"])) or
            checkpoint.get("phase1_evidence") != termination_evidence(runtime, 1) or
            checkpoint.get("phase1_http") != record(runtime / "phase-1/http-results.json") or
            checkpoint.get("disk_inventory") != disk_inventory(runtime)):
        raise RuntimeError("Restart does not match the parent's fully terminated same-disk run")
    pid = checkpoint.get("phase1_pid")
    if type(pid) is not int or pid <= 1 or pid == os.getpid():
        raise RuntimeError("Invalid previous process identity")
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        pass
    else:
        raise RuntimeError("Previous PID exists/reused; refuse restart")
    return checkpoint


def synthetic_bytes(offset, count):
    pattern = bytes(range(256))
    start = offset % 256
    return (pattern * ((start + count + 255) // 256))[start:start + count]


def checked_ready(path, config, pid=None, launched=None):
    import math
    import time
    from urllib.parse import urlsplit
    ready = read_json(path)
    start, deadline = ready.get("started_monotonic"), ready.get("deadline_monotonic")
    url = urlsplit(ready.get("url", ""))
    if (ready.get("run_identity") != config["run_identity"] or
            ready.get("storage_phase") != config["storage_phase"] or
            type(ready.get("pid")) is not int or ready["pid"] <= 1 or
            (pid is not None and ready["pid"] != pid) or
            type(start) not in (int, float) or not math.isfinite(start) or
            type(deadline) not in (int, float) or not math.isfinite(deadline) or
            deadline - start != config["listener_deadline_seconds"] or
            (launched is not None and not launched <= start <= time.monotonic()) or
            time.monotonic() >= deadline or url.scheme != "http" or url.hostname != "127.0.0.1" or
            url.username or url.password or url.path or url.query or url.fragment or
            url.port is None or not 1 <= url.port <= 65535 or
            ready["url"] != "http://127.0.0.1:" + str(url.port)):
        raise RuntimeError("Listener readiness identity or origin mismatch")
    os.kill(ready["pid"], 0)
    return ready


def request_phase_stop(directory, config, pid):
    value = {"run_identity": config["run_identity"], "storage_phase": config["storage_phase"],
             "listener_pid": pid, "requester_pid": os.getpid(), "reason": "reviewed-parent-stop"}
    path = directory / "stop.request"
    if path.exists():
        existing = read_json(path)
        if any(existing.get(key) != value[key] for key in ("run_identity", "storage_phase", "listener_pid")):
            raise RuntimeError("Stop request identity mismatch")
    else:
        write_json(path, value)


async def serve_observed(application, report, note, on_ready, should_stop, *, deadline):
    """Shared real Uvicorn lifecycle, one OS-selected loopback bind, no subprocess."""
    import asyncio
    from contextlib import contextmanager
    import signal
    import socket
    import time
    import uvicorn

    class ObservedServer(uvicorn.Server):
        @contextmanager
        def capture_signals(self):
            def handler(signum, _frame):
                report["signals"].append(signum)
                report["stop_reason"] = "signal-" + signal.Signals(signum).name
                self.should_exit = True
                note("stop-signal", {"signal": signum})
            previous = {sig: signal.signal(sig, handler) for sig in (signal.SIGINT, signal.SIGTERM)}
            try:
                yield
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)

    listening = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    task = server = None
    try:
        listening.bind(("127.0.0.1", 0))
        listening.setblocking(False)
        address, port = listening.getsockname()
        report.update(actual_address=address, actual_port=port)
        server = ObservedServer(uvicorn.Config(application, host="127.0.0.1", port=0,
            loop="asyncio", http="h11", ws="none", lifespan="on", log_config=None,
            access_log=False, proxy_headers=False, workers=1, reload=False,
            timeout_graceful_shutdown=5))
        task = asyncio.create_task(server.serve(sockets=[listening]))
        while not server.started:
            if task.done():
                await task
                raise RuntimeError("Listener exited before actual startup")
            if time.monotonic() - report["started_monotonic"] > 30:
                raise TimeoutError("Listener startup deadline exceeded")
            await asyncio.sleep(0.05)
        on_ready("http://127.0.0.1:" + str(port))
        while not task.done():
            reason = should_stop()
            if reason or time.monotonic() >= deadline:
                report["stop_reason"] = report["stop_reason"] or reason or "isolation-deadline"
                server.should_exit = True
            await asyncio.sleep(0.05)
        await task
        report["server_terminated"] = True
    finally:
        if server is not None:
            server.should_exit = True
        if task is not None and not task.done():
            try:
                await asyncio.wait_for(asyncio.shield(task), timeout=10)
                report["server_terminated"] = True
            except asyncio.TimeoutError:
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
                report["forced_server_task_cancel"] = True
        if server is not None:
            report["remaining_server_connections"] = len(server.server_state.connections)
            report["remaining_server_tasks"] = len(server.server_state.tasks)
        listening.close()
        report["listener_fd_closed"] = listening.fileno() == -1
