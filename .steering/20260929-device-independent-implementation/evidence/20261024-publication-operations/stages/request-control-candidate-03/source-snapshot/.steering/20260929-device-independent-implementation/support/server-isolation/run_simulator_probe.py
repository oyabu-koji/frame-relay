"""Main-owned opt-in Xcode execution; no token in argv or emitted logs.

This wrapper runs outside the backend guard because Xcode/Simulator need their
normal authorized output directories. Its command, runtime and output are fixed.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import time
from urllib.parse import urlsplit


ROOT = Path("/Users/oyabu/dev/rep/FrameRelay")
EVIDENCE = Path("/private/tmp/fr-di-20261001-5ljls2fr")
DESTINATION = "platform=iOS Simulator,id=DFE46693-E8DD-4814-8957-4F327699F719"
EXPECTED_KEYS = {"FR_LEGACY_PLAYBACK_PROBE", "FR_LEGACY_PROBE_URL", "FR_LEGACY_PROBE_RESULT_ID",
                 "FR_LEGACY_PROBE_SHA256", "FR_LEGACY_PROBE_BYTE_COUNT", "FR_LEGACY_PROBE_PREFIX_SHA256",
                 "FR_LEGACY_PROBE_TOKEN"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--execute-reviewed-xcode", action="store_true")
    args = parser.parse_args()
    support = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("s20_stop_helper", support / "request_listener_stop.py")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    runtime = helper.paths(args.config)
    bundle = runtime / "simulator-probe.xcresult"
    command = ["/usr/bin/xcodebuild", "-project", str(ROOT / "FrameRelay.xcodeproj"), "-scheme", "FrameRelay",
        "-configuration", "Debug", "-destination", DESTINATION, "-derivedDataPath", str(EVIDENCE / "DerivedData"),
        "-disableAutomaticPackageResolution", "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
        "-resultBundlePath", str(bundle), "-only-testing:FrameRelayTests/LegacyServerPlaybackProbeTests", "test", "-quiet"]
    if not args.execute_reviewed_xcode:
        print(json.dumps({"command": command, "executed": False, "requires": "main explicit reviewed execution"}))
        return
    if bundle.exists() or (runtime / "simulator-wrapper-result.json").exists():
        raise SystemExit("Refuse to overwrite prior Xcode evidence")
    secret_path = runtime / "simulator-probe-env.json"
    if secret_path.is_symlink() or not stat.S_ISREG(secret_path.stat().st_mode) or stat.S_IMODE(secret_path.stat().st_mode) != 0o600:
        raise SystemExit("Expected regular runtime-only 0600 secret environment file")
    secret_record = json.loads(secret_path.read_text())
    secret = secret_record["environment"]
    if set(secret) != EXPECTED_KEYS or any(not isinstance(value, str) or not value for value in secret.values()):
        raise SystemExit("Unreviewed probe environment shape")
    address = urlsplit(secret["FR_LEGACY_PROBE_URL"])
    ready = json.loads((runtime / "listener-ready.json").read_text())
    config = json.loads(args.config.read_text())
    if (ready["run_identity"] != config["run_identity"] or secret_record["run_identity"] != ready["run_identity"]
            or secret_record["listener_pid"] != ready["pid"]
            or secret_record["started_monotonic"] != ready["started_monotonic"]
            or ready["secret_environment_file"] != str(secret_path)
            or ready["deadline_monotonic"] != ready["started_monotonic"] + 1200):
        raise SystemExit("Ready/secret/config run identity or lifetime mismatch")
    pid = ready["pid"]
    if not isinstance(pid, int) or pid <= 1:
        raise SystemExit("Invalid listener PID")
    try:
        os.kill(pid, 0)
    except (ProcessLookupError, PermissionError):
        raise SystemExit("Listener PID is absent or unobservable")
    listener_command = subprocess.check_output(["/bin/ps", "-ww", "-p", str(pid), "-o", "command="], text=True).strip()
    if str(support / "run_pytest.py") not in listener_command or str(args.config.resolve()) not in listener_command:
        raise SystemExit("Recorded PID does not identify this reviewed listener command")
    def remaining_budget():
        remaining = ready["deadline_monotonic"] - time.monotonic()
        budget = min(1100, int(remaining) - 60)
        if budget < 180:
            raise SystemExit("Listener has insufficient remaining lifetime; stop it and prepare a fresh runtime")
        return budget
    execution_budget = remaining_budget()
    if address.scheme != "http" or address.hostname != "127.0.0.1" or not address.port or secret["FR_LEGACY_PROBE_URL"] != ready["url"]:
        raise SystemExit("Expected exact ready loopback endpoint")
    token = secret["FR_LEGACY_PROBE_TOKEN"]
    inherited_keys = ("HOME", "USER", "LOGNAME", "TMPDIR", "PATH", "LANG", "LC_ALL", "LC_CTYPE", "TZ", "DEVELOPER_DIR", "SDKROOT")
    environment = {key: os.environ[key] for key in inherited_keys if key in os.environ}
    environment.update({"TEST_RUNNER_" + key: value for key, value in secret.items()})
    started = time.monotonic()
    outcome = {"command": command, "environment_keys_added": sorted("TEST_RUNNER_" + key for key in secret),
        "token_in_argv": False, "xcodebuild": "/usr/bin/xcodebuild", "xcodebuild_sha256": hashlib.sha256(Path("/usr/bin/xcodebuild").read_bytes()).hexdigest(),
        "inherited_environment_keys": sorted(key for key in inherited_keys if key in environment),
        "home_inherited_unchanged": environment.get("HOME") == os.environ.get("HOME"),
        "sdk_environment": {key: environment[key] for key in ("DEVELOPER_DIR", "SDKROOT") if key in environment},
        "run_identity": ready["run_identity"], "listener_pid": pid, "listener_process_command": listener_command,
        "deadline_seconds": execution_budget, "listener_stop_margin_seconds": 60,
        "exit_code": None, "stop_requested": False,
        "limitation": "Xcode internal diagnostics may retain disposable test environment; listener exit revokes token"}
    output = b""
    process = None
    def stop_own_process():
        nonlocal output
        if process is None:
            return
        for sig, wait in ((signal.SIGINT, 20), (signal.SIGTERM, 5), (signal.SIGKILL, 5)):
            if process.poll() is not None:
                break
            os.killpg(process.pid, sig)
            try:
                output, _ = process.communicate(timeout=wait)
                break
            except subprocess.TimeoutExpired:
                continue
    try:
        outcome["selected_developer_directory"] = subprocess.check_output(
            ["/usr/bin/xcode-select", "-p"], env=environment, text=True).strip()
        outcome["xcode_version"] = subprocess.check_output(
            ["/usr/bin/xcodebuild", "-version"], env=environment, text=True).strip()
        execution_budget = remaining_budget()
        outcome["deadline_seconds"] = execution_budget
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        outcome["xcode_pid"] = process.pid
        try:
            output, _ = process.communicate(timeout=execution_budget)
        except subprocess.TimeoutExpired:
            outcome["timed_out"] = True
            stop_own_process()
        outcome["exit_code"] = process.poll()
    except BaseException as error:
        outcome["interrupted_by"] = type(error).__name__
        stop_own_process()
        outcome["exit_code"] = None if process is None else process.poll()
        raise
    finally:
        clean = output.replace(token.encode(), b"<redacted disposable token>")
        with (runtime / "simulator-xcodebuild.log").open("xb") as log:
            log.write(clean)
        helper.request_stop(runtime, "simulator-wrapper-finished")
        outcome["stop_requested"] = True
        outcome["elapsed_seconds"] = time.monotonic() - started
        with (runtime / "simulator-wrapper-result.json").open("x") as record:
            json.dump(outcome, record, indent=2)
        print(json.dumps({"runtime": str(runtime), "exit_code": outcome["exit_code"], "stop_requested": True}))
    return outcome["exit_code"] if outcome["exit_code"] is not None else 70


if __name__ == "__main__":
    raise SystemExit(main())
