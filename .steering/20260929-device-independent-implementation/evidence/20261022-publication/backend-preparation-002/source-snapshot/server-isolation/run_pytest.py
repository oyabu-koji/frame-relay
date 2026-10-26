"""Reviewed S20 checkpoint 1 entry. Run only with external Python -I -B -S.

No backend, pytest, or site-package import occurs before Guard.install().
This file is prepared for main review; preparing it does not execute any tests.
"""
import argparse
import dataclasses
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import sys
import traceback
import xml.etree.ElementTree as ET


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def file_record(path):
    if path.is_symlink():
        return {"kind": "symlink", "target": os.readlink(path), "resolved": str(path.resolve())}
    return {"kind": "file", "size": path.stat().st_size, "sha256": sha256(path)}


def tree_manifest(root, *, excluded=()):
    return {str(path.relative_to(root)): file_record(path)
            for path in sorted(root.rglob("*"))
            if str(path.relative_to(root)) not in excluded and (path.is_file() or path.is_symlink())}


def dump(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def fd_inventory(guard):
    values = []
    for item in sorted(Path("/dev/fd").iterdir(), key=lambda p: int(p.name)):
        number = int(item.name)
        try:
            status = os.fstat(number)
            record = {"fd": number, "mode": status.st_mode, "dev": status.st_dev, "ino": status.st_ino}
            try:
                record["path"] = str(guard.fd_path(number))
            except OSError:
                record["path"] = None  # Pipe/socket or FD closed after enumeration.
            values.append(record)
        except OSError:
            values.append({"fd": number, "closed_during_enumeration": True})
    return values


def settings_environment(runtime):
    # Every Settings field is explicit. Values are isolated test configuration,
    # not accepted product wire, tuning, or conversion settings.
    return {
        "MEDIA_ROOT": str(runtime / "media"),
        "API_TOKEN": "s20-disposable-" + secrets.token_hex(24),
        "DATABASE_PATH": str(runtime / "db.sqlite3"),
        "LUT_PATH": str(runtime / "assets/lut/rec709.cube"),
        "USER_LUT_ROOT": str(runtime / "user-lut"),
        "BUILT_IN_PRESET_ROOT": str(runtime / "assets/lut/presets"),
        "APPLE_LOG_DETECTOR_ROOT": str(runtime / "assets/detectors/apple-log-v2"),
        "FFPROBE_BINARY": str(runtime / "disabled-ffprobe"),
        "DETECTOR_PROBE_TIMEOUT_MS": "15000", "DETECTOR_PROBE_MAX_STDOUT_BYTES": "1048576",
        "DETECTOR_PROBE_MAX_STDERR_BYTES": "1048576", "DETECTOR_EVIDENCE_MAX_BYTES": "4096",
        "PRESET_MANIFEST_MAX_BYTES": "65536", "PRESET_LUT_MAX_BYTES": "16777216",
        "SQLITE_BUSY_TIMEOUT_MS": "5000", "JOB_LEASE_SECONDS": "300",
        "PROCESSED_RESULT_RECOVERY_GRACE_SECONDS": "300",
        "UPLOAD_SESSION_CHUNK_SIZE_BYTES": "8388608", "UPLOAD_SESSION_MAX_SIZE_BYTES": "1099511627776",
        "UPLOAD_SESSION_ACTIVE_LIMIT": "2", "UPLOAD_SESSION_EXPIRY_SECONDS": "604800",
        "UPLOAD_SESSION_RETRY_AFTER_SECONDS": "30",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--restart-checkpoint-sha256")
    args = parser.parse_args()
    if sys.version_info[:2] != (3, 12) or not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
        raise SystemExit("Require reviewed Python 3.12 -I -B -S")
    if sys.platform != "darwin":
        raise SystemExit("Reviewed FD implementation requires macOS")
    support = Path(__file__).resolve().parent
    config = json.loads(args.config.read_text())
    action = config.get("action", "pytest")
    storage_action = action == "storage-listener"
    listener_action = action in {"listener", "registration-listener", "storage-listener"}
    if action not in {"pytest", "range-probe", "listener", "registration-listener", "storage-listener"}:
        raise SystemExit("Unreviewed execution action")
    if args.restart_checkpoint_sha256 and not storage_action:
        raise SystemExit("Restart checkpoint is exclusive to S24 phase two")
    if listener_action and config.get("allow_reviewed_loopback_listener") is not True:
        raise SystemExit("Listener requires explicit reviewed config; preparation is not authorization")
    snapshot = Path(config["snapshot"]).resolve(strict=True)
    backend = snapshot / "backend"
    site_packages = Path(config["site_packages"]).resolve(strict=True)
    external = Path(config["external_root"]).resolve(strict=True)
    runtime = Path(config["runtime"]).resolve()
    provenance = json.loads(Path(config["provenance"]).read_text())
    executable = Path(sys.executable).resolve(strict=True)
    if executable != Path(config["interpreter"]).resolve(strict=True) or file_record(executable) != provenance["interpreter"]["resolved_record"]:
        raise SystemExit("Interpreter differs from prepared dependency provenance")
    # No writes yet. Check all approved external/snapshot inputs before execution.
    source_before = {name: file_record(external / name) for name in provenance["source_before"]}
    snapshot_before = {name: file_record(snapshot / name) for name in provenance["snapshot"]}
    site_before = tree_manifest(site_packages)
    if source_before != provenance["source_before"] or snapshot_before != provenance["snapshot"]:
        raise SystemExit("Source or snapshot changed since preparation; review required")
    if site_before != provenance["site_packages_before"]:
        raise SystemExit("Dependency files changed since preparation; review required")
    case_file = Path(config.get("case_file", support / "cases.json")).resolve(strict=True)
    nodes = json.loads(case_file.read_text())
    expected_nodes = config.get("expected_nodes", 13)
    expected_cases = config.get("expected_cases", 20)
    if (not isinstance(nodes, list) or not nodes or
            any(not isinstance(node, str) or not node.startswith("tests/") or
                "::test_" not in node or ".." in node or "\\" in node for node in nodes) or
            len(set(nodes)) != len(nodes) or type(expected_nodes) is not int or
            expected_nodes != len(nodes) or type(expected_cases) is not int or expected_cases < expected_nodes):
        raise SystemExit("Invalid explicit test set or expected counts")
    if "case_file" in config and sha256(case_file) != config.get("case_file_sha256"):
        raise SystemExit("Explicit test set differs from reviewed configuration")
    evidence = runtime
    if storage_action:
        lifecycle_spec = importlib.util.spec_from_file_location("listener_lifecycle", support / "listener_lifecycle.py")
        lifecycle = importlib.util.module_from_spec(lifecycle_spec)
        sys.modules[lifecycle_spec.name] = lifecycle
        lifecycle_spec.loader.exec_module(lifecycle)
        lifecycle.verify_sources(config, support)
        evidence = lifecycle.phase_directory(runtime, config)
        if runtime.is_symlink() or runtime.parent != snapshot.parent or evidence.exists() or evidence.is_symlink():
            raise SystemExit("S24 requires a fresh phase in its own sibling runtime")
        if config["storage_phase"] == 1:
            if runtime.exists() or args.restart_checkpoint_sha256:
                raise SystemExit("S24 phase one requires a new runtime and no checkpoint")
            runtime.mkdir()
        else:
            lifecycle.verify_restart(runtime, config, args.restart_checkpoint_sha256)
        evidence.mkdir()
    else:
        if runtime.exists() or runtime.is_symlink() or runtime.parent != snapshot.parent:
            raise SystemExit("Runtime must be an uncreated sibling of the prepared snapshot")
        runtime.mkdir()
    # Load the local guard by exact path while sys.path still excludes checkout,
    # site-packages, cwd and .pth processing.
    spec = importlib.util.spec_from_file_location("s20_isolation_guard", support / "isolation_guard.py")
    guard_module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = guard_module
    spec.loader.exec_module(guard_module)
    guard = guard_module.Guard(runtime,
        allow_missing_ffprobe_version=config.get("allow_missing_ffprobe_version_probe") is True,
        allow_loopback_listener=listener_action, evidence_directory=evidence if storage_action else None)
    guard.install()
    initial_fds = fd_inventory(guard)
    inherited_home = os.environ.get("HOME")
    preserved = {key: os.environ[key] for key in ("HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ") if key in os.environ}
    os.environ.clear()
    os.environ.update(preserved)  # HOME is inherited byte-for-byte, never relocated.
    explicit = settings_environment(runtime)
    os.environ.update(explicit)
    os.environ.update({"PATH": "/usr/bin:/bin", "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1",
        "TMPDIR": str(runtime / "tmp"), "TMP": str(runtime / "tmp"), "TEMP": str(runtime / "tmp"),
        "SQLITE_TMPDIR": str(runtime / "sqlite-tmp"), "XDG_CACHE_HOME": str(runtime / "cache")})
    if not storage_action or config["storage_phase"] == 1:
        for directory in ("tmp", "sqlite-tmp", "cache", "media", "user-lut"):
            (runtime / directory).mkdir()
        shutil.copytree(backend / "assets", runtime / "assets")
    os.chdir(runtime)
    os.environ["PWD"] = str(runtime)
    original_sys_path = list(sys.path)
    sys.path.extend([str(backend), str(site_packages)])
    assert len(explicit) == 22
    pytest_args = ["-q", "--noconftest", "--capture=sys", "-c", str(backend / "pyproject.toml"),
        "--rootdir=" + str(backend), "-o", "addopts=", "-o", "cache_dir=" + str(runtime / "pytest-cache"),
        "--basetemp=" + str(runtime / "pytest-tmp"), "--log-file=" + str(runtime / "pytest.log"),
        "--junitxml=" + str(runtime / "pytest.xml"), *[str(backend / node) for node in nodes]]
    dump(evidence / "preflight.json", {"python": sys.version, "executable": sys.executable,
        "base_prefix": sys.base_prefix, "flags": repr(sys.flags), "source": config,
        "sys_path_before_explicit_addition": original_sys_path, "sys_path_after": list(sys.path),
        "environment_keys": sorted(os.environ), "home_inherited_unchanged": os.environ.get("HOME") == inherited_home,
        "settings_environment": {key: "<redacted ephemeral token>" if key == "API_TOKEN" else value for key, value in explicit.items()},
        "execution_kind": action, "pytest_args": pytest_args if action == "pytest" else None,
        "case_file": str(case_file), "case_file_sha256": sha256(case_file),
        "expected_nodes": expected_nodes if action == "pytest" else None,
        "expected_cases_static": expected_cases if action == "pytest" else None,
        "fd_before_backend_import": initial_fds,
        "listener": "one 127.0.0.1:0 bind" if listener_action else "not allowed",
        "subprocess": "only exact nonexistent runtime/disabled-ffprobe -version" if guard.allow_missing_ffprobe_version else "not allowed",
        "guard_sha256": sha256(support / "isolation_guard.py"), "runner_sha256": sha256(Path(__file__))})
    result = 70
    failure = None
    effective_settings = None
    pytest_counts = None
    pytest_exit_code = None
    try:
        from app.core.settings import load_settings
        effective_settings = dataclasses.asdict(load_settings())
        if len(effective_settings) != 22:
            raise RuntimeError("Settings shape changed from reviewed 22 fields")
        effective_settings["api_token"] = "<redacted ephemeral token>"
        effective_settings = {key: str(value) if isinstance(value, Path) else value for key, value in effective_settings.items()}
        dump(evidence / "effective-settings-redacted.json", effective_settings)
        if action == "pytest":
            import pytest
            result = int(pytest.main(pytest_args))
            pytest_exit_code = result
            suites = ET.parse(runtime / "pytest.xml").getroot().findall("testsuite")
            pytest_counts = {key: sum(int(suite.get(key, "0")) for suite in suites)
                             for key in ("tests", "failures", "errors", "skipped")}
            if pytest_counts["tests"] != expected_cases or pytest_counts["skipped"]:
                result = 72  # Wrong collection/skip cannot satisfy the reviewed set.
        elif action == "range-probe":
            probe_spec = importlib.util.spec_from_file_location("s20_range_probe", support / "range_probe.py")
            probe_module = importlib.util.module_from_spec(probe_spec)
            sys.modules[probe_spec.name] = probe_module
            probe_spec.loader.exec_module(probe_module)
            observation = probe_module.run(runtime)
            result = 0 if observation["passed"] and observation["request_thread_terminated"] else 1
        else:
            listener_module = ("storage_listener.py" if storage_action else
                "registration_listener.py" if action == "registration-listener" else "listener_probe.py")
            probe_spec = importlib.util.spec_from_file_location("reviewed_listener_probe", support / listener_module)
            probe_module = importlib.util.module_from_spec(probe_spec)
            sys.modules[probe_spec.name] = probe_module
            probe_spec.loader.exec_module(probe_module)
            observation = probe_module.run(runtime, config)
            result = 0 if observation["passed"] else 1
    except BaseException as error:
        result = 70
        failure = ({"type": type(error).__name__} if storage_action else
            {"type": type(error).__name__, "message": str(error), "traceback": traceback.format_exc()})
    finally:
        if storage_action:
            os.environ.pop("API_TOKEN", None)
            explicit.pop("API_TOKEN", None)
            secret = evidence / "storage-http-env.json"
            if secret.exists():
                secret.unlink()
        origins = {}
        allowed_roots = (snapshot, site_packages, support, Path(sys.base_prefix).resolve())
        unreviewed_origins = []
        for name, module in sorted(sys.modules.items()):
            filename = getattr(module, "__file__", None)
            if filename:
                path = Path(filename).resolve()
                origins[name] = str(path)
                if not any(path.is_relative_to(root) for root in allowed_roots):
                    unreviewed_origins.append({"module": name, "path": str(path)})
        dump(evidence / "import-origins.json", {"modules": origins, "unreviewed": unreviewed_origins})
        fd_before_close = fd_inventory(guard)
        guard_result = guard.finish()
        after_source = {name: file_record(external / name) for name in provenance["source_before"]}
        after_site = tree_manifest(site_packages)
        after_snapshot = {name: file_record(snapshot / name) for name in provenance["snapshot"]}
        unchanged = after_source == source_before and after_site == site_before and after_snapshot == snapshot_before
        dump(evidence / "provenance-after.json", {"external_source": after_source, "site_packages": after_site,
            "snapshot": after_snapshot, "all_unchanged": unchanged})
        excluded = {"simulator-probe-env.json"}
        if storage_action:
            excluded.update({"phase-1/storage-http-env.json", "phase-2/storage-http-env.json",
                             "storage-client-state.json"})
        artifacts = tree_manifest(runtime, excluded=excluded)
        dump(evidence / "artifacts.json", {"files": artifacts,
            "excluded_sensitive_files": sorted(excluded),
            "sqlite_sidecars": [name for name in artifacts if name.endswith(("-wal", "-shm", "-journal"))]})
        if not unchanged or unreviewed_origins or guard.denials:
            result = 71
        report = {"execution_kind": action, "exit_code": result,
            "pytest_exit_code": pytest_exit_code,
            "pytest_counts": pytest_counts,
            "failure": failure, "inputs_unchanged": unchanged,
            "unreviewed_import_origins": unreviewed_origins, "guard": guard_result,
            "fd_before_explicit_sqlite_close": fd_before_close, "fd_after_explicit_sqlite_close": fd_inventory(guard),
            "process_exit": "parent must observe actual exit; this is a pre-exit FD inventory",
            "interpretation": (
                "actual bound HTTP upload/final read and same-disk process restart; synthetic bytes, no conversion or physical-network acceptance"
                if storage_action else
                "actual registration app/SQLite and loopback lifecycle; iOS results are separate; real Wi-Fi/TLS/background remain unverified"
                if action == "registration-listener" else
                "actual loopback listener lifecycle/FD observations; HTTP/AVPlayer results are separate Simulator evidence; "
                "product receipts, Log conversion and real Wi-Fi remain unverified"
                if action == "listener" else
                "synthetic in-process HTTP/SQLite checks, not real network, video playback or conversion")}
        dump(evidence / "result.json", report)
        # Keep the audit stream available for Python/pytest atexit cleanup. The
        # parent records actual process termination; no early FD-close claim.
        guard.log.flush()
    print(json.dumps({"runtime": str(runtime), "execution_kind": action, "exit_code": result,
        "pytest_exit_code": pytest_exit_code,
        "failure_type": None if failure is None else failure["type"]}))
    return result


if __name__ == "__main__":
    raise SystemExit(main())
