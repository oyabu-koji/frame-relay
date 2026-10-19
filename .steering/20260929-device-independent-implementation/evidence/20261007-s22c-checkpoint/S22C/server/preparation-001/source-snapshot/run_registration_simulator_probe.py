"""Reviewed opt-in Xcode wrapper for registration probes; secrets stay off argv.

This executes outside the backend guard using main's Xcode/Simulator permission.
The config contains only non-secret source/run identity and explicit test names.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shlex
import signal
import stat
import subprocess
import time
from urllib.parse import urlsplit


ROOT = Path("/Users/oyabu/dev/rep/FrameRelay")
EVIDENCE = Path("/private/tmp/fr-di-20261001-5ljls2fr")
SERVER_ROOT = EVIDENCE / "S22C/server"
DESTINATION = "platform=iOS Simulator,id=DFE46693-E8DD-4814-8957-4F327699F719"
EXPECTED_KEYS = {"FR_REGISTRATION_PROBE", "FR_REGISTRATION_BASE_URL",
                 "FR_REGISTRATION_BOOTSTRAP_TOKEN", "FR_REGISTRATION_DESTINATION_ID"}


def read_regular_json(path, *, private=False):
    if path.is_symlink() or not stat.S_ISREG(path.stat().st_mode):
        raise RuntimeError("Expected regular reviewed input file")
    if private and stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise RuntimeError("Secret environment must be 0600")
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--execute-reviewed-xcode", action="store_true")
    args = parser.parse_args()
    support = Path(__file__).resolve().parent
    config_path = args.config.resolve(strict=True)
    config = read_regular_json(config_path)
    snapshot = Path(config["snapshot"]).resolve(strict=True)
    runtime = Path(config["runtime"]).resolve()
    if (runtime.parent != SERVER_ROOT or snapshot.parent != SERVER_ROOT or
            not runtime.name.startswith("runtime-listener-") or
            config.get("action") != "registration-listener" or
            config.get("listener_deadline_seconds") != 1200 or
            config.get("allow_reviewed_loopback_listener") is not True):
        raise SystemExit("Unreviewed registration listener namespace/config")
    tests = config.get("xcode_only_testing")
    if (not isinstance(tests, list) or not tests or len(tests) != len(set(tests)) or
            any(not isinstance(test, str) or re.fullmatch(
                r"FrameRelayTests/Registration(?:Server|Transport)ProbeTests/test[A-Za-z0-9_]+", test
            ) is None for test in tests)):
        raise SystemExit("Expected explicit reviewed registration probe methods")
    if any("/RegistrationTransportProbeTests/" in test for test in tests) and (
            config.get("allow_registration_transport_probe_routes") is not True or
            config.get("transport_probe_oversize_bytes") != 16385 or
            config.get("transport_probe_slow_seconds") != 5):
        raise SystemExit("Transport methods require the exact reviewed bounded probe configuration")
    bundle = runtime / "registration-probe.xcresult"
    command = ["/usr/bin/xcodebuild", "-project", str(ROOT / "FrameRelay.xcodeproj"),
        "-scheme", "FrameRelay", "-configuration", "Debug", "-destination", DESTINATION,
        "-derivedDataPath", str(EVIDENCE / "DerivedData"), "-disableAutomaticPackageResolution",
        "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
        "-resultBundlePath", str(bundle), *["-only-testing:" + test for test in tests], "test", "-quiet"]
    if not args.execute_reviewed_xcode:
        print(json.dumps({"command": command, "executed": False,
                          "requires": "main review and permission for this fresh run"}))
        return 0
    if not runtime.is_dir() or bundle.exists() or (runtime / "registration-wrapper-result.json").exists():
        raise SystemExit("Runtime must be live and Xcode evidence must be fresh")
    spec = importlib.util.spec_from_file_location("s22c_stop_helper", support / "request_listener_stop.py")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    output = b""
    token = None
    process = None
    started = time.monotonic()
    outcome = {"command": command, "run_identity": config["run_identity"],
        "token_in_argv": False, "exit_code": None, "stop_requested": False,
        "listener_stop_margin_seconds": 60,
        "limitation": "Xcode internal diagnostics may retain disposable test environment; listener exit revokes bootstrap token"}

    def stop_own_process():
        nonlocal output
        if process is None:
            return
        for signum, seconds in ((signal.SIGINT, 20), (signal.SIGTERM, 5), (signal.SIGKILL, 5)):
            if process.poll() is not None:
                break
            try:
                os.killpg(process.pid, signum)  # Only the session this wrapper created.
            except ProcessLookupError:
                pass
            try:
                output, _ = process.communicate(timeout=seconds)
                break
            except subprocess.TimeoutExpired:
                continue

    def interrupted(signum, _frame):
        outcome["wrapper_signal"] = signum
        raise KeyboardInterrupt

    previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        secret_path = runtime / "simulator-probe-env.json"
        secret_record = read_regular_json(secret_path, private=True)
        secret = secret_record["environment"]
        if set(secret) != EXPECTED_KEYS or any(type(value) is not str or not value for value in secret.values()):
            raise RuntimeError("Unreviewed registration probe environment shape")
        token = secret["FR_REGISTRATION_BOOTSTRAP_TOKEN"]
        ready = read_regular_json(runtime / "listener-ready.json")
        if (ready["run_identity"] != config["run_identity"] or
                secret_record["run_identity"] != ready["run_identity"] or
                secret_record["listener_pid"] != ready["pid"] or
                secret_record["started_monotonic"] != ready["started_monotonic"] or
                secret_record["deadline_monotonic"] != ready["deadline_monotonic"] or
                ready["secret_environment_file"] != str(secret_path) or
                ready["deadline_seconds"] != 1200 or
                type(ready["started_monotonic"]) not in (int, float) or
                not math.isfinite(ready["started_monotonic"]) or
                ready["deadline_monotonic"] != ready["started_monotonic"] + 1200):
            raise RuntimeError("Ready/secret/config run identity or lifetime mismatch")
        pid = ready["pid"]
        if type(pid) is not int or pid <= 1:
            raise RuntimeError("Invalid listener PID")
        os.kill(pid, 0)
        process_command = subprocess.check_output(
            ["/bin/ps", "-ww", "-p", str(pid), "-o", "command="], text=True).strip()
        words = shlex.split(process_command)
        if words[-3:] != [str(support / "run_pytest.py"), "--config", str(config_path)]:
            raise RuntimeError("Recorded PID is not this reviewed listener command")
        if not {"-I", "-B", "-S"}.issubset(words):
            raise RuntimeError("Listener does not use the reviewed isolated interpreter flags")
        address = urlsplit(secret["FR_REGISTRATION_BASE_URL"])
        if (secret["FR_REGISTRATION_PROBE"] != "1" or address.scheme != "http" or
                address.hostname != "127.0.0.1" or address.port is None or
                address.username is not None or address.password is not None or
                address.path or address.query or address.fragment or
                secret["FR_REGISTRATION_BASE_URL"] != ready["url"] or
                secret["FR_REGISTRATION_DESTINATION_ID"] != ready["destination_id"] or
                re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
                             ready["destination_id"]) is None):
            raise RuntimeError("Expected exact ready loopback destination")

        def remaining_budget():
            now = time.monotonic()
            if not ready["started_monotonic"] <= now < ready["deadline_monotonic"]:
                raise RuntimeError("Listener lifetime is not currently valid")
            budget = min(1100, int(ready["deadline_monotonic"] - now) - 60)
            if budget < 180:
                raise RuntimeError("Listener lifetime insufficient; prepare a fresh runtime")
            return budget

        remaining_budget()
        inherited = ("HOME", "USER", "LOGNAME", "TMPDIR", "PATH", "LANG", "LC_ALL", "LC_CTYPE",
                     "TZ", "DEVELOPER_DIR", "SDKROOT")
        environment = {key: os.environ[key] for key in inherited if key in os.environ}
        environment.update({"TEST_RUNNER_" + key: value for key, value in secret.items()})
        outcome.update({"environment_keys_added": sorted("TEST_RUNNER_" + key for key in secret),
            "xcodebuild_sha256": hashlib.sha256(Path("/usr/bin/xcodebuild").read_bytes()).hexdigest(),
            "inherited_environment_keys": sorted(key for key in inherited if key in environment),
            "home_inherited_unchanged": environment.get("HOME") == os.environ.get("HOME"),
            "sdk_environment": {key: environment[key] for key in ("DEVELOPER_DIR", "SDKROOT") if key in environment},
            "listener_pid": pid, "listener_process_command": process_command,
            "selected_developer_directory": subprocess.check_output(
                ["/usr/bin/xcode-select", "-p"], env=environment, text=True).strip(),
            "xcode_version": subprocess.check_output(
                ["/usr/bin/xcodebuild", "-version"], env=environment, text=True).strip()})
        budget = remaining_budget()
        outcome["deadline_seconds"] = budget
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        outcome["xcode_pid"] = process.pid
        try:
            output, _ = process.communicate(timeout=budget)
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
        for sig, previous_handler in previous.items():
            signal.signal(sig, previous_handler)
        # Stop is requested even if log persistence itself later fails.
        helper.request_stop(runtime, "registration-simulator-wrapper-finished")
        outcome["stop_requested"] = True
        clean = output if token is None else output.replace(token.encode(), b"<redacted disposable token>")
        with (runtime / "registration-xcodebuild.log").open("xb") as log:
            log.write(clean)
        outcome["elapsed_seconds"] = time.monotonic() - started
        with (runtime / "registration-wrapper-result.json").open("x") as record:
            json.dump(outcome, record, indent=2)
        print(json.dumps({"runtime": str(runtime), "exit_code": outcome["exit_code"], "stop_requested": True}))
    return outcome["exit_code"] if outcome["exit_code"] is not None else 70


if __name__ == "__main__":
    raise SystemExit(main())
