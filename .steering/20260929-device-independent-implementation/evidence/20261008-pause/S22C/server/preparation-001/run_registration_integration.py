"""One reviewed invocation: frozen listener -> ready -> Xcode wrapper -> reaping.

Never reads the secret environment. Only the three exact commands already frozen
in commands.json may be launched. Dry-run performs read-only hash checks only.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import stat
import subprocess
import time
from urllib.parse import urlsplit


PREPARATION = Path("/private/tmp/fr-di-20261001-5ljls2fr/S22C/server/preparation-001")
CHECKPOINT_SHA256 = "81046378b07ffee00ebfafe6d302cd538858b832aa9bdad8f98cfd957374bda5"
PROJECT = Path("/Users/oyabu/dev/rep/FrameRelay")
READY_SECONDS = 30
OVERALL_SECONDS = 1260


def file_record(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise RuntimeError("Expected a regular frozen input")
    content = path.read_bytes()
    return {"kind": "file", "size": len(content), "sha256": hashlib.sha256(content).hexdigest()}


def read_json(path):
    file_record(path)
    return json.loads(path.read_text())


def private_output(path):
    return os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb")


def verify_inputs():
    checkpoint_path = PREPARATION / "checkpoint-files.json"
    if file_record(checkpoint_path)["sha256"] != CHECKPOINT_SHA256:
        raise RuntimeError("Frozen S22C checkpoint changed")
    checkpoint = read_json(checkpoint_path)
    for name, key in (("commands.json", "commands"), ("run-config.json", "run_config"),
                      ("provenance-before.json", "provenance")):
        if file_record(PREPARATION / name) != checkpoint[key]:
            raise RuntimeError("Frozen S22C command/config/provenance changed")
    source = PREPARATION / "source-snapshot"
    actual = {str(path.relative_to(source)): file_record(path) for path in source.rglob("*")
              if path.is_file() or path.is_symlink()}
    if actual != checkpoint["frozen_sources"] or len(actual) != 11:
        raise RuntimeError("Frozen S22C source set changed")
    config = read_json(PREPARATION / "run-config.json")
    commands = read_json(PREPARATION / "commands.json")
    runtime = Path(config["runtime"])
    if runtime != PREPARATION.parent / "runtime-listener-001":
        raise RuntimeError("Unexpected runtime namespace")
    if runtime.exists() or runtime.is_symlink():
        raise RuntimeError("Refusing to reuse the listener runtime")
    config_arguments = ["--config", str(PREPARATION / "run-config.json")]
    exact = {
        "listener": [config["interpreter"], "-I", "-B", "-S", str(source / "run_pytest.py"), *config_arguments],
        "simulator": ["python3", "-I", "-B", "-S", str(source / "run_registration_simulator_probe.py"),
                      *config_arguments, "--execute-reviewed-xcode"],
        "stop_request": ["python3", "-I", "-B", "-S", str(source / "request_listener_stop.py"), *config_arguments],
    }
    if any(commands[key] != command for key, command in exact.items()):
        raise RuntimeError("Commands differ from the exact reviewed child commands")
    return config, exact, runtime


def ready_record(runtime, listener, config, launched):
    path = runtime / "listener-ready.json"
    if not path.exists():
        return None
    try:
        ready = read_json(path)
    except json.JSONDecodeError:
        return None  # The child may still be finishing its exclusive write.
    started = ready.get("started_monotonic")
    deadline = ready.get("deadline_monotonic")
    if (ready.get("pid") != listener.pid or type(ready.get("pid")) is not int or
            ready.get("run_identity") != config["run_identity"] or
            ready.get("deadline_seconds") != 1200 or type(started) not in (int, float) or
            not math.isfinite(started) or not launched <= started <= time.monotonic() or
            deadline != started + 1200 or
            ready.get("secret_environment_file") != str(runtime / "simulator-probe-env.json")):
        raise RuntimeError("Listener ready identity/lifetime does not match the owned child")
    address = urlsplit(ready["url"])
    if (address.scheme != "http" or address.hostname != "127.0.0.1" or not address.port or
            address.username is not None or address.password is not None or
            address.path or address.query or address.fragment):
        raise RuntimeError("Listener ready endpoint is not the reviewed loopback origin")
    return ready


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute-reviewed-integration", action="store_true")
    args = parser.parse_args()
    config, commands, runtime = verify_inputs()
    evidence = PREPARATION / "integration-execution-001"
    if evidence.exists() or evidence.is_symlink():
        raise SystemExit("Refusing to overwrite prior integration execution evidence")
    if not args.execute_reviewed_integration:
        print(json.dumps({"commands": commands, "ready_deadline_seconds": READY_SECONDS,
            "overall_deadline_seconds": OVERALL_SECONDS, "evidence": str(evidence),
            "secret_environment_read": False, "executed": False}))
        return 0

    evidence.mkdir(mode=0o700)
    inherited = ("HOME", "USER", "LOGNAME", "TMPDIR", "PATH", "LANG", "LC_ALL", "LC_CTYPE",
                 "TZ", "DEVELOPER_DIR", "SDKROOT")
    environment = {key: os.environ[key] for key in inherited if key in os.environ}
    started = time.monotonic()
    # Reserve at most five seconds per owned child for final post-kill reaping.
    deadline = started + OVERALL_SECONDS - 15
    children = {}
    logs = {}
    observed_signal = None
    outcome = {"run_identity": config["run_identity"], "commands": commands,
        "started_monotonic": started, "overall_deadline_seconds": OVERALL_SECONDS,
        "ready_deadline_seconds": READY_SECONDS, "secret_environment_read": False,
        "environment_keys_inherited": sorted(environment), "children": {}, "signals_sent": [],
        "ready_observed": False, "stop_helper_attempted": False, "passed": False,
        "output_policy": "0600 logs contain frozen listener metadata and wrapper summaries; supervisor does not read credentials or echo child output",
        "interpretation": "process lifecycle result only; main must separately inspect the six XCTest results and transport/DB evidence"}

    def capture_signal(signum, _frame):
        nonlocal observed_signal
        observed_signal = signum

    previous = {sig: signal.signal(sig, capture_signal) for sig in (signal.SIGINT, signal.SIGTERM)}

    def launch(name):
        log = private_output(evidence / (name + ".log"))
        logs[name] = log
        child = subprocess.Popen(commands[name], cwd=PROJECT, env=environment, stdin=subprocess.DEVNULL,
                                 stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        children[name] = child
        outcome["children"][name] = {"pid": child.pid, "exit_code": None, "actual_exit_observed": False}
        return child

    def collect(name, timeout):
        child = children[name]
        try:
            code = child.wait(timeout=max(0, min(timeout, deadline - time.monotonic())))
        except subprocess.TimeoutExpired:
            return False
        outcome["children"][name].update({"exit_code": code, "actual_exit_observed": True})
        return True

    def stop_owned(name):
        if name not in children or collect(name, 0):
            return
        child = children[name]
        # Signal only Popen children. The wrapper handles its own Xcode session.
        interrupt_grace = 40 if name == "simulator" else 20
        for signum, seconds in ((signal.SIGINT, interrupt_grace), (signal.SIGTERM, 5), (signal.SIGKILL, 5)):
            if child.poll() is not None:
                collect(name, 0)
                return
            child.send_signal(signum)
            outcome["signals_sent"].append({"child": name, "pid": child.pid, "signal": signum})
            if collect(name, seconds):
                return
        # Kernel exit is still observed explicitly even at the overall deadline.
        try:
            code = child.wait(timeout=5)
            outcome["children"][name].update({"exit_code": code, "actual_exit_observed": True})
        except subprocess.TimeoutExpired:
            outcome["children"][name]["termination_unconfirmed"] = True

    try:
        listener_launch = time.monotonic()
        listener = launch("listener")
        ready = None
        while time.monotonic() < listener_launch + READY_SECONDS:
            if observed_signal is not None:
                raise InterruptedError("Supervisor interrupted")
            if listener.poll() is not None:
                collect("listener", 0)
                raise RuntimeError("Listener exited before readiness")
            ready = ready_record(runtime, listener, config, listener_launch)
            if ready is not None:
                break
            time.sleep(0.05)
        if ready is None:
            raise TimeoutError("Listener did not become ready within 30 seconds")
        outcome["ready_observed"] = True
        outcome["ready"] = ready  # Public metadata only; no environment/token read.
        wrapper = launch("simulator")
        wrapper_deadline = min(time.monotonic() + 1140, deadline - 90, ready["deadline_monotonic"] - 30)
        while wrapper.poll() is None:
            if observed_signal is not None:
                raise InterruptedError("Supervisor interrupted")
            if listener.poll() is not None:
                collect("listener", 0)
                # The wrapper requests listener stop in its finally block, just
                # before persisting its own result and exiting. Reap that short
                # tail before interpreting an early listener exit as a failure.
                if collect("simulator", 5):
                    break
                raise RuntimeError("Listener exited while Simulator wrapper was running")
            if time.monotonic() >= wrapper_deadline:
                raise TimeoutError("Simulator wrapper exceeded its bounded integration budget")
            time.sleep(0.1)
        collect("simulator", 0)
    except BaseException as error:
        outcome["failure_type"] = type(error).__name__
    finally:
        # Always request the frozen helper first, including partial startup.
        outcome["stop_helper_attempted"] = True
        try:
            launch("stop_request")
            if not collect("stop_request", 10):
                stop_owned("stop_request")
        except BaseException as error:
            outcome["stop_helper_failure_type"] = type(error).__name__
        stop_owned("simulator")
        if "listener" in children and not collect("listener", 45):
            stop_owned("listener")
        for name in children:
            collect(name, 0)
        for sig, old_handler in previous.items():
            signal.signal(sig, old_handler)
        for log in logs.values():
            log.close()
        outcome["received_signal"] = observed_signal
        outcome["elapsed_seconds"] = time.monotonic() - started
        outcome["secret_file_absent_after_child_exit"] = not (runtime / "simulator-probe-env.json").exists()
        for name, filename in (("runner", "result.json"), ("listener", "listener-results.json"),
                               ("wrapper", "registration-wrapper-result.json")):
            path = runtime / filename
            if path.is_file() and not path.is_symlink():
                outcome[name + "_result_file"] = file_record(path)
        exits = outcome["children"]
        outcome["passed"] = (outcome["ready_observed"] and "failure_type" not in outcome and
            "stop_helper_failure_type" not in outcome and observed_signal is None and
            set(exits) == set(commands) and all(value["actual_exit_observed"] and value["exit_code"] == 0
                                               for value in exits.values()) and
            outcome["secret_file_absent_after_child_exit"] and
            all(name + "_result_file" in outcome for name in ("runner", "listener", "wrapper")))
        with private_output(evidence / "result.json") as stream:
            stream.write((json.dumps(outcome, indent=2, sort_keys=True) + "\n").encode())
        print(json.dumps({"evidence": str(evidence), "passed": outcome["passed"],
            "child_exits": {name: value["exit_code"] for name, value in exits.items()},
            "secret_environment_read": False}))
    return 0 if outcome["passed"] else 70


if __name__ == "__main__":
    raise SystemExit(main())
