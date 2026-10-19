"""Guarded S25 fixture ASGI server. No backend, distribution receipt, or real-media input."""
import argparse
import asyncio
import hmac
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import threading
import time


def load_helper():
    spec = importlib.util.spec_from_file_location("prepare_rendition_fixture",
        Path(__file__).with_name("prepare_rendition_fixture.py"))
    value = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = value
    spec.loader.exec_module(value)
    return value


def run_fixture(helper, lifecycle, runtime, config, token, movie):
    started = time.monotonic()
    report = {"run_identity": config["run_identity"], "pid": os.getpid(), "fixture_only": True,
        "started_monotonic": started, "deadline_monotonic": started + 1200,
        "ready": False, "signals": [], "stop_reason": None, "server_terminated": False,
        "requests": [], "request_limit": 4096, "passed": False,
        "malformed_length_interpretation": "short/oversize use honest Content-Length with a mismatched Content-Range; header rejection only, not proof of incomplete/oversize body detection after accepted headers",
        "throttle": {"block_bytes": 4096, "delay_seconds": 0.01, "delayed_mode_seconds": 2,
                     "meaning": "synthetic transport schedule, not product tuning or performance acceptance"}}
    secret_path = runtime / "fixture-env.json"
    events = (runtime / "listener-events.jsonl").open("x")
    before_threads = set(threading.enumerate())

    def note(event, detail):
        events.write(json.dumps({"event": event, "detail": detail, "monotonic": time.monotonic()}) + "\n")
        events.flush()

    class Fixture:
        async def __call__(self, scope, receive, send):
            if scope["type"] == "lifespan":
                while True:
                    value = await receive()
                    if value["type"] == "lifespan.startup":
                        await send({"type": "lifespan.startup.complete"})
                    elif value["type"] == "lifespan.shutdown":
                        await send({"type": "lifespan.shutdown.complete"})
                        return
            if scope["type"] != "http":
                raise RuntimeError("Unexpected fixture scope")
            path = scope.get("path", "")
            mode = path.removeprefix("/media/") if path.startswith("/media/") else "not-allowed"
            observation = {"sequence": len(report["requests"]) + 1,
                "mode": mode if mode in helper.MODES else "not-allowed",
                "arrived_monotonic": time.monotonic(), "status": None,
                "headers_sent_monotonic": None, "first_body_monotonic": None,
                "body_bytes_emitted": 0, "file_bytes_read": 0, "file_opened": False,
                "file_closed": True, "terminal": None, "terminal_monotonic": None}
            if len(report["requests"]) >= 4096:
                report["request_limit_exceeded"] = True
                raise RuntimeError("Bounded fixture request limit exceeded")
            report["requests"].append(observation)
            note("request-arrived", dict(observation))
            disconnected = None
            stream = None

            async def respond(status, headers=(), body=b""):
                observation["status"] = status
                await send({"type": "http.response.start", "status": status, "headers":
                    [(b"cache-control", b"no-store"), (b"connection", b"close"), *headers]})
                observation["headers_sent_monotonic"] = time.monotonic()
                if body:
                    observation["first_body_monotonic"] = time.monotonic()
                await send({"type": "http.response.body", "body": body})
                observation["body_bytes_emitted"] += len(body)

            async def watch_disconnect():
                while True:
                    message = await receive()
                    if message["type"] == "http.disconnect":
                        return

            try:
                auth = [v for k, v in scope.get("headers", []) if k.lower() == b"authorization"]
                if len(auth) != 1 or not hmac.compare_digest(auth[0], ("Bearer " + token).encode()):
                    await respond(401, [(b"content-length", b"0")])
                    observation["terminal"] = "unauthorized-response-completed"
                    return
                if scope.get("method") != "GET" or mode not in helper.MODES or scope.get("query_string"):
                    await respond(404, [(b"content-length", b"0")])
                    observation["terminal"] = "route-refused"
                    return
                scenarios = [v for k, v in scope.get("headers", []) if k.lower() == b"x-fixture-scenario"]
                if scenarios and (scenarios != [b"streaming"] or mode != "normal"):
                    await respond(400, [(b"content-length", b"0")])
                    observation["terminal"] = "scenario-refused"
                    return
                observation["scenario"] = "streaming" if scenarios else None
                if mode == "redirect":
                    await respond(302, [(b"content-length", b"0"), (b"location", b"/media/redirect-target")])
                    observation["terminal"] = "redirect-response-completed"
                    return
                ranges = [v for k, v in scope.get("headers", []) if k.lower() == b"range"]
                match = re.fullmatch(rb"bytes=([0-9]+)-([0-9]+)", ranges[0]) if len(ranges) == 1 else None
                size = config["fixture"]["byteCount"]
                if match is None:
                    await respond(416, [(b"content-length", b"0")])
                    observation["terminal"] = "range-refused"
                    return
                start, end = map(int, match.groups())
                if start > end or end >= size or end - start + 1 > 65536:
                    await respond(416, [(b"content-length", b"0")])
                    observation["terminal"] = "range-refused"
                    return
                wanted = end - start + 1
                actual = wanted - 1 if mode == "short" else wanted + 1 if mode == "oversize" else wanted
                observation.update(range_start=start, range_end=end, range_total=size,
                    range_length=wanted, content_length=actual)
                headers = [(b"content-type", config["fixture"]["mime"].encode()),
                    (b"content-length", str(actual).encode()), (b"accept-ranges", b"bytes"),
                    (b"content-range", f"bytes {start}-{end}/{size}".encode()),
                    (b"x-fixture-rendition", (config["fixture_id"] + ("-wrong" if mode == "wrong-version" else "")).encode()),
                    (b"x-fixture-sha256", ("0" * 64 if mode == "wrong-digest" else config["fixture"]["sha256"]).encode()),
                    (b"x-fixture-size", str(size + 1 if mode == "wrong-size" else size).encode()),
                    (b"cache-control", b"no-store"), (b"connection", b"close")]
                disconnected = asyncio.create_task(watch_disconnect())
                stream = movie.open("rb")
                observation.update(file_opened=True, file_closed=False, status=206)
                stream.seek(start)
                await send({"type": "http.response.start", "status": 206, "headers": headers})
                observation["headers_sent_monotonic"] = time.monotonic()
                remaining = actual
                while remaining:
                    if disconnected.done():
                        observation["terminal"] = "client-disconnected"
                        return
                    count = 1 if mode == "delayed" and remaining == actual else min(4096, remaining)
                    block = stream.read(min(count, size - stream.tell()))
                    observation["file_bytes_read"] += len(block)
                    if len(block) < count:  # Only an oversize EOF extension is synthetic.
                        if mode != "oversize":
                            raise RuntimeError("Fixture file unexpectedly short")
                        block += b"\0" * (count - len(block))
                    if observation["first_body_monotonic"] is None:
                        observation["first_body_monotonic"] = time.monotonic()
                    await send({"type": "http.response.body", "body": block, "more_body": True})
                    observation["body_bytes_emitted"] += len(block)
                    remaining -= len(block)
                    delay = 2 if mode == "delayed" and observation["body_bytes_emitted"] == 1 else 0.01
                    try:
                        await asyncio.wait_for(asyncio.shield(disconnected), timeout=delay)
                        observation["terminal"] = "client-disconnected"
                        return
                    except asyncio.TimeoutError:
                        pass
                await send({"type": "http.response.body", "body": b"", "more_body": False})
                observation["terminal"] = "response-completed"
            except (OSError, asyncio.CancelledError) as error:
                observation["terminal"] = "transport-" + type(error).__name__
            finally:
                if stream is not None:
                    stream.close()
                    observation["file_closed"] = stream.closed
                if disconnected is not None:
                    if not disconnected.done():
                        disconnected.cancel()
                    await asyncio.gather(disconnected, return_exceptions=True)
                observation["terminal"] = observation["terminal"] or "handler-failed"
                observation["terminal_monotonic"] = time.monotonic()
                note("request-terminal", dict(observation))

    def ready(origin):
        url = origin + "/media"
        environment = {"FR_S25_HTTP_FIXTURE": "1", "FR_S25_FIXTURE_URL": url,
            "FR_S25_FIXTURE_TOKEN": token, "FR_S25_FIXTURE_ID": config["fixture_id"],
            "FR_S25_FIXTURE_SHA256": config["fixture"]["sha256"],
            "FR_S25_FIXTURE_BYTE_COUNT": str(config["fixture"]["byteCount"]),
            "FR_S25_FIXTURE_MIME": config["fixture"]["mime"]}
        helper.write_json(secret_path, {"run_identity": config["run_identity"], "listener_pid": os.getpid(),
            "url": url, "environment": environment}, private=True)
        report["ready"] = True
        helper.write_json(runtime / "listener-ready.json", {"pid": os.getpid(), "url": url,
            "run_identity": config["run_identity"], "started_monotonic": started,
            "deadline_monotonic": started + 1200, "deadline_seconds": 1200})
        note("ready", {"pid": os.getpid()})

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
        asyncio.run(lifecycle.serve_observed(Fixture(), report, note, ready, should_stop, deadline=started + 1200))
    except BaseException as error:
        report["failure_type"] = type(error).__name__
    finally:
        new_threads = [thread for thread in threading.enumerate() if thread not in before_threads]
        for thread in new_threads:
            thread.join(timeout=5)
        report["all_created_threads_joined"] = all(not thread.is_alive() for thread in new_threads)
        if secret_path.exists():
            secret_path.unlink()
        report["secret_deleted"] = not secret_path.exists()
        report["passed"] = (all(report.get(key) is True for key in ("ready", "server_terminated",
            "listener_fd_closed", "all_created_threads_joined", "secret_deleted")) and
            report.get("remaining_server_connections") == 0 and report.get("remaining_server_tasks") == 0 and
            report["stop_reason"] == "reviewed-stop" and not report["signals"] and
            not report.get("request_limit_exceeded") and
            not report.get("forced_server_task_cancel") and "failure_type" not in report and
            all(row["file_closed"] and row["terminal_monotonic"] is not None and
                row["terminal"] not in ("handler-failed", "transport-CancelledError") for row in report["requests"]))
        note("listener-end", {"passed": report["passed"], "requests": len(report["requests"])})
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
    support = Path(__file__).resolve().parent
    preparation = Path(config["preparation"])
    if support != preparation / "source-snapshot":
        raise RuntimeError("Use frozen listener sources")
    provenance = helper.read_json(preparation / "dependency-provenance.json")
    helper.verify_dependencies(provenance)
    if helper.record(Path(sys.executable).resolve()) != provenance["interpreter"]["resolved_record"]:
        raise RuntimeError("Unexpected executable")
    source_movie = Path(config["fixture"]["path"])
    if helper.record(source_movie) != config["fixture_record"]:
        raise RuntimeError("Generated fixture changed")
    runtime = Path(config["runtime"])
    if runtime.exists() or runtime.is_symlink():
        raise RuntimeError("Listener requires a fresh runtime")
    runtime.mkdir()
    runner = helper.module("run_pytest")
    guard_module = helper.module("isolation_guard")
    guard = guard_module.Guard(runtime, allow_loopback_listener=True)
    guard.install()
    initial_fds = runner.fd_inventory(guard)
    preserved = {k: os.environ[k] for k in ("HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ") if k in os.environ}
    inherited_home = os.environ.get("HOME")
    os.environ.clear()
    os.environ.update(preserved)
    explicit = runner.settings_environment(runtime)
    os.environ.update(explicit)
    os.environ.update({"PATH": "/usr/bin:/bin", "TMPDIR": str(runtime / "tmp"),
        "TMP": str(runtime / "tmp"), "TEMP": str(runtime / "tmp"), "SQLITE_TMPDIR": str(runtime / "sqlite-tmp"),
        "XDG_CACHE_HOME": str(runtime / "cache"), "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1"})
    for directory in ("tmp", "sqlite-tmp", "cache", "media", "user-lut"):
        (runtime / directory).mkdir()
    os.chdir(runtime)
    os.environ["PWD"] = str(runtime)
    sys.path.append(provenance["site_packages_root"])
    lifecycle = helper.module("listener_lifecycle")
    result = {"run_identity": config["run_identity"], "pid": os.getpid(), "passed": False,
        "backend_imported": False, "fixture_only": True, "initial_fds": initial_fds,
        "settings_environment": {k: "<redacted ephemeral token>" if k == "API_TOKEN" else v for k, v in explicit.items()},
        "effective_settings_kind": "22 explicit isolated environment values; no backend Settings import",
        "home_inherited_unchanged": os.environ.get("HOME") == inherited_home}
    try:
        movie = runtime / "media/fixture.mov"
        with source_movie.open("rb") as reader, movie.open("xb") as writer:
            shutil.copyfileobj(reader, writer)
        if helper.record(movie) != config["fixture_record"]:
            raise RuntimeError("Fixture copy changed content")
        listener = run_fixture(helper, lifecycle, runtime, config, explicit["API_TOKEN"], movie)
        result["listener_passed"] = listener["passed"]
        result["runtime_fixture"] = helper.record(movie)
    except BaseException as error:
        result["failure_type"] = type(error).__name__
    finally:
        secret = runtime / "fixture-env.json"
        if secret.exists():
            secret.unlink()
        os.environ.pop("API_TOKEN", None)
        explicit.pop("API_TOKEN", None)
        result["guard"] = guard.finish()
        result["fd_after_explicit_close"] = runner.fd_inventory(guard)
        result["source_movie_unchanged"] = helper.record(source_movie) == config["fixture_record"]
        helper.verify_dependencies(provenance)
        result["dependencies_unchanged"] = True
        result["sources_unchanged"] = helper.tree(support) == checkpoint["source_files"]
        result["backend_imported"] = any(name == "app" or name.startswith("app.") for name in sys.modules)
        origins = {name: str(Path(m.__file__).resolve()) for name, m in sys.modules.items() if getattr(m, "__file__", None)}
        allowed = (support, Path(provenance["site_packages_root"]).resolve(), Path(sys.base_prefix).resolve())
        unexpected = {name: path for name, path in origins.items() if not any(Path(path).is_relative_to(root) for root in allowed)}
        result["unexpected_import_origins"] = unexpected
        helper.write_json(runtime / "import-origins.json", origins)
        result["media_fds_remaining"] = [fd for fd in result["fd_after_explicit_close"]
            if fd.get("path") and Path(fd["path"]).is_relative_to(runtime / "media")]
        result["passed"] = (result.get("listener_passed") is True and "failure_type" not in result and
            result["source_movie_unchanged"] and result["dependencies_unchanged"] and result["sources_unchanged"] and
            not unexpected and not guard.denials and not result["media_fds_remaining"] and
            not result["guard"]["sqlite_connection_events"] and guard.listener_bind_count == 1 and
            not secret.exists() and not result["backend_imported"])
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
