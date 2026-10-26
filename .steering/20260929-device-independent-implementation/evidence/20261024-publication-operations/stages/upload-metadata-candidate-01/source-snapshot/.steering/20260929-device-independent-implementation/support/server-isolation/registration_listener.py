"""Opt-in S22C registration listener and bounded metadata-only transport probes.

Loaded after guard.install; uses the verified S22 app lifespan and database. No media fixture,
legacy seeding, fabricated receipt, or outward HTTP connection is involved.
"""
import asyncio
from contextlib import closing, contextmanager
import hmac
import json
import os
import re
import signal
import socket
import stat
import threading
import time


def write_json(path, value, *, private=False):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                         0o600 if private else 0o644)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def run(runtime, config):
    from app.core.settings import load_settings
    from app.db.connection import connect
    from app.main import app
    from app.repositories.registrations import destination_identity
    import uvicorn

    if config.get("listener_deadline_seconds") != 1200:
        raise RuntimeError("Unreviewed registration listener lifetime")
    run_identity = config.get("run_identity")
    if not isinstance(run_identity, str) or re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", run_identity
    ) is None:
        raise RuntimeError("Invalid registration listener run identity")
    settings = load_settings()
    transport_probes = config.get("allow_registration_transport_probe_routes") is True
    if transport_probes and (config.get("transport_probe_oversize_bytes") != 16385 or
                             config.get("transport_probe_slow_seconds") != 5):
        raise RuntimeError("Unreviewed registration transport probe bounds")
    secret_path = runtime / "simulator-probe-env.json"
    stop_path = runtime / "stop.request"
    events = (runtime / "listener-events.jsonl").open("x")
    event_lock = threading.Lock()
    started = time.monotonic()
    deadline = started + 1200
    report = {"pid": os.getpid(), "run_identity": run_identity,
        "bind": "127.0.0.1:0", "deadline_seconds": 1200,
        "started_monotonic": started, "deadline_monotonic": deadline,
        "ready": False, "signals": [], "stop_reason": None,
        "response_counts": {}, "server_terminated": False,
        "transport_probes_enabled": transport_probes,
        "transport_probe_requests": {"redirect": 0, "redirect-target": 0, "oversize": 0, "slow": 0},
        "slow_requests": [],
        "secret_deleted": False, "passed": False,
        "interpretation": "actual registration app/SQLite and listener lifecycle; iOS results are separate; no real Wi-Fi, TLS, background or physical-device claim"}
    listening = None
    server = None

    def note(event, detail):
        with event_lock:
            events.write(json.dumps({"event": event, "detail": detail,
                                     "monotonic": time.monotonic()}) + "\n")
            events.flush()

    class RegistrationOnly:
        async def fixed_response(self, send, status, body, extra_headers=()):
            await send({"type": "http.response.start", "status": status,
                "headers": [(b"content-type", b"application/json"),
                            (b"content-length", str(len(body)).encode("ascii")),
                            (b"cache-control", b"no-store"), *extra_headers]})
            await send({"type": "http.response.body", "body": body})

        async def slow_response(self, receive, send):
            observation = {"sequence": len(report["slow_requests"]) + 1,
                "arrived_monotonic": time.monotonic(), "response_started_monotonic": None,
                "terminal": None, "terminal_monotonic": None, "maximum_delay_seconds": 5}
            report["slow_requests"].append(observation)
            note("slow-request-arrived", dict(observation))
            body = b'{"probe":"slow"}'
            delay = None
            disconnected = None

            async def wait_for_disconnect():
                while True:
                    message = await receive()
                    if message["type"] == "http.disconnect":
                        return

            try:
                await send({"type": "http.response.start", "status": 200,
                    "headers": [(b"content-type", b"application/json"),
                                (b"content-length", str(len(body)).encode("ascii")),
                                (b"cache-control", b"no-store")]})
                await send({"type": "http.response.body", "body": body[:9], "more_body": True})
                observation["response_started_monotonic"] = time.monotonic()
                note("slow-response-started", dict(observation))
                delay = asyncio.create_task(asyncio.sleep(5))
                disconnected = asyncio.create_task(wait_for_disconnect())
                completed, _pending = await asyncio.wait((delay, disconnected),
                                                         return_when=asyncio.FIRST_COMPLETED)
                if disconnected in completed:
                    await disconnected
                    observation["terminal"] = "disconnect"
                else:
                    await send({"type": "http.response.body", "body": body[9:]})
                    observation["terminal"] = "response-completed"
            finally:
                pending = [task for task in (delay, disconnected) if task is not None]
                for task in pending:
                    if not task.done():
                        task.cancel()
                if pending:
                    await asyncio.gather(*pending, return_exceptions=True)
                observation["terminal"] = observation["terminal"] or "handler-interrupted"
                observation["terminal_monotonic"] = time.monotonic()
                note("slow-request-terminal", dict(observation))

        async def transport_probe(self, endpoint, scope, receive, send):
            report["transport_probe_requests"][endpoint] += 1
            authorization = [value for key, value in scope.get("headers", []) if key.lower() == b"authorization"]
            if len(authorization) != 1 or not hmac.compare_digest(
                authorization[0], b"Bearer " + settings.api_token.encode("ascii")
            ):
                await self.fixed_response(send, 401, b'{"code":"probe_unauthorized"}')
                note("transport-probe-response", {"endpoint": endpoint, "status": 401})
                return
            if endpoint == "redirect":
                await self.fixed_response(send, 302, b'{"probe":"redirect"}',
                    [(b"location", b"/__s22c_probe__/redirect-target")])
            elif endpoint == "redirect-target":
                await self.fixed_response(send, 200, b'{"probe":"redirect-target"}')
            elif endpoint == "oversize":
                prefix, suffix = b'{"probe":"', b'"}'
                body = prefix + b"x" * (16385 - len(prefix) - len(suffix)) + suffix
                await self.fixed_response(send, 200, body)
            else:
                await self.slow_response(receive, send)
            note("transport-probe-response", {"endpoint": endpoint, "status": 302 if endpoint == "redirect" else 200})

        async def __call__(self, scope, receive, send):
            if scope["type"] == "lifespan":
                await app(scope, receive, send)
                return
            path = scope.get("path", "")
            method = scope.get("method", "")
            probe_paths = {"/__s22c_probe__/" + name: name for name in report["transport_probe_requests"]}
            if transport_probes and scope["type"] == "http" and method == "GET" and path in probe_paths:
                await self.transport_probe(probe_paths[path], scope, receive, send)
                return
            endpoint = None
            if method == "GET" and path == "/frame-relay/v1/capabilities":
                endpoint = "capabilities"
            elif method == "POST" and path == "/frame-relay/v1/registrations":
                endpoint = "registrations"
            elif method == "GET" and re.fullmatch(
                r"/frame-relay/v1/registration-intents/[0-9a-f-]{36}", path
            ):
                endpoint = "registration-intent"
            if scope["type"] != "http" or endpoint is None:
                # Do not expose old media/worker endpoints on the probe listener.
                await send({"type": "http.response.start", "status": 404,
                            "headers": [(b"content-type", b"application/json"),
                                        (b"cache-control", b"no-store")]})
                await send({"type": "http.response.body", "body": b'{"code":"probe_route_not_allowed"}'})
                note("blocked-route", {"status": 404})
                return

            async def measured_send(message):
                if message["type"] == "http.response.start":
                    key = endpoint + ":" + str(message["status"])
                    report["response_counts"][key] = report["response_counts"].get(key, 0) + 1
                    # Never log URL/query/body, token, or registration secret.
                    note("registration-response", {"endpoint": endpoint, "status": message["status"]})
                await send(message)
            await app(scope, receive, measured_send)

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

    async def serve():
        nonlocal server, listening
        listening = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listening.bind(("127.0.0.1", 0))
        listening.setblocking(False)
        address, port = listening.getsockname()
        report["actual_address"] = address
        report["actual_port"] = port
        server = ObservedServer(uvicorn.Config(RegistrationOnly(), host="127.0.0.1", port=0,
            loop="asyncio", http="h11", ws="none", lifespan="on", log_config=None,
            access_log=False, proxy_headers=False, workers=1, reload=False,
            timeout_graceful_shutdown=5))
        task = asyncio.create_task(server.serve(sockets=[listening]))
        try:
            while not server.started:
                if task.done():
                    await task
                    raise RuntimeError("Registration server exited before actual startup")
                if time.monotonic() - started > 30:
                    raise TimeoutError("Registration server startup deadline exceeded")
                await asyncio.sleep(0.05)
            # This query runs only after the real app's migration/lifespan startup.
            with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
                destination = destination_identity(conn)
                initial_count = conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0]
            if initial_count != 0:
                raise RuntimeError("Fresh listener database already contains registrations")
            url = f"http://127.0.0.1:{port}"
            environment = {"FR_REGISTRATION_PROBE": "1", "FR_REGISTRATION_BASE_URL": url,
                "FR_REGISTRATION_BOOTSTRAP_TOKEN": settings.api_token,
                "FR_REGISTRATION_DESTINATION_ID": destination}
            write_json(secret_path, {"run_identity": run_identity, "listener_pid": os.getpid(),
                "started_monotonic": started, "deadline_monotonic": deadline,
                "environment": environment}, private=True)
            if stat.S_IMODE(secret_path.stat().st_mode) != 0o600:
                raise RuntimeError("Registration secret environment is not 0600")
            report["ready"] = True
            report["destination_id"] = destination
            write_json(runtime / "listener-ready.json", {"pid": os.getpid(), "url": url,
                "secret_environment_file": str(secret_path), "run_identity": run_identity,
                "started_monotonic": started, "deadline_monotonic": deadline,
                "deadline_seconds": 1200, "destination_id": destination})
            print(json.dumps({"registration_listener_ready": True, "runtime": str(runtime),
                              "pid": os.getpid(), "url": url}), flush=True)
            while not task.done():
                if stop_path.exists():
                    report["stop_reason"] = report["stop_reason"] or "reviewed-stop-file"
                    server.should_exit = True
                elif time.monotonic() >= deadline:
                    report["stop_reason"] = report["stop_reason"] or "isolation-deadline"
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
        with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
            report["final_destination_id"] = destination_identity(conn)
            report["registration_count"] = conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0]
            report["last_generation"] = conn.execute("SELECT last_generation FROM fr_destination").fetchone()[0]
        report["passed"] = (report["ready"] and report["server_terminated"] and
            report["stop_reason"] is not None and not report.get("forced_server_task_cancel", False) and
            report.get("remaining_server_connections") == 0 and report.get("remaining_server_tasks") == 0 and
            report["destination_id"] == report["final_destination_id"])
    finally:
        if listening is not None:
            listening.close()
            report["listener_fd_closed"] = listening.fileno() == -1
        if secret_path.exists():
            secret_path.unlink()
        report["secret_deleted"] = not secret_path.exists()
        report["passed"] = report["passed"] and report["secret_deleted"] and report.get("listener_fd_closed", False)
        note("listener-end", report)
        events.close()
        write_json(runtime / "listener-results.json", report)
    return report
