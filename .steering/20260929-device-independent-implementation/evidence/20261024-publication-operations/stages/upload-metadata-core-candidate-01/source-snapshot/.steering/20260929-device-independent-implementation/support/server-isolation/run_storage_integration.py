"""Parent-observed S24 two-process restart. Dry-run only unless explicitly enabled."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


ROOT = Path("/private/tmp/fr-di-20261001-5ljls2fr/S24")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preparation", type=Path, required=True)
    parser.add_argument("--checkpoint-sha256", required=True)
    parser.add_argument("--execute-reviewed-integration", action="store_true")
    args = parser.parse_args()
    if not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
        raise RuntimeError("Require -I -B -S")
    preparation = args.preparation
    support = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("listener_lifecycle", support / "listener_lifecycle.py")
    life = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(life)
    if (preparation.parent != ROOT or re.fullmatch(r"http-preparation-[0-9]{3}", preparation.name) is None or
            life.record(preparation / "checkpoint.json")["sha256"] != args.checkpoint_sha256):
        raise RuntimeError("Unreviewed HTTP preparation/checkpoint")
    checkpoint = life.read_json(preparation / "checkpoint.json")
    for name, key in (("source-manifest.json", "source_manifest"), ("phase-1-config.json", "phase1_config"),
                      ("phase-2-config.json", "phase2_config"), ("commands.json", "commands")):
        if life.record(preparation / name) != checkpoint[key]:
            raise RuntimeError("Frozen HTTP preparation changed")
    base = Path(checkpoint["backend_preparation"])
    if base.parent != ROOT or life.record(base / "checkpoint-files.json") != checkpoint["backend_checkpoint"]:
        raise RuntimeError("Backend preparation changed")
    configs = {phase: life.read_json(preparation / ("phase-" + str(phase) + "-config.json")) for phase in (1, 2)}
    config1, config2 = configs[1], configs[2]
    if ({**config1, "storage_phase": 2} != config2 or config1["storage_phase"] != 1 or
            support != preparation / "source-snapshot"):
        raise RuntimeError("Phase configs do not describe one same-disk run")
    life.verify_sources(config1, support)
    runtime = Path(config1["runtime"])
    if (runtime != ROOT / ("runtime-storage-" + preparation.name.removeprefix("http-preparation-")) or
            runtime.exists() or runtime.is_symlink()):
        raise RuntimeError("HTTP run requires a new runtime")
    commands = life.read_json(preparation / "commands.json")
    exact = {}
    for phase in (1, 2):
        suffix = str(phase)
        tail = ["--config", str(preparation / ("phase-" + suffix + "-config.json"))]
        prefix = [config1["interpreter"], "-I", "-B", "-S"]
        exact["listener" + suffix] = prefix + [str(support / "run_pytest.py")] + tail
        exact["client" + suffix] = prefix + [str(support / "storage_http_probe.py")] + tail
    if commands != exact:
        raise RuntimeError("Unexpected child command")
    if not args.execute_reviewed_integration:
        print(json.dumps({"executed": False, "commands": exact,
            "dynamic_arguments": {"listener2": "parent-verified post-exit checkpoint sha256",
                                  "clients": "their own observed listener PID"},
            "runtime": str(runtime)}, indent=2))
        return 0
    evidence = preparation / "supervisor"
    evidence.mkdir(exist_ok=False)
    environment = {key: os.environ[key] for key in ("HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ") if key in os.environ}
    environment["PATH"] = "/usr/bin:/bin"
    children, logs = {}, {}
    started = time.monotonic()
    deadline = started + 600
    received_signal = None
    outcome = {"run_identity": config1["run_identity"], "parent_pid": os.getpid(),
        "checkpoint_sha256": args.checkpoint_sha256, "children": {}, "phases": {},
        "signals_sent": [], "passed": False, "secret_environment_read": False,
        "interpretation": "synthetic real HTTP upload/final read and actual same-disk process restart; no conversion, physical network, or crash fault acceptance"}

    def capture(signum, _frame):
        nonlocal received_signal
        received_signal = signum
    previous = {sig: signal.signal(sig, capture) for sig in (signal.SIGINT, signal.SIGTERM)}

    def launch(name, extra=()):
        stream = os.fdopen(os.open(evidence / (name + ".log"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb")
        logs[name] = stream
        child = subprocess.Popen(commands[name] + list(extra), cwd=preparation, env=environment,
            stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        children[name] = child
        outcome["children"][name] = {"pid": child.pid, "actual_exit_observed": False, "exit_code": None}
        return child

    def collect(name, seconds):
        child = children[name]
        try:
            code = child.wait(timeout=max(0, seconds))
        except subprocess.TimeoutExpired:
            return False
        outcome["children"][name].update(actual_exit_observed=True, exit_code=code)
        return True

    def stop_owned(name):
        if name not in children or collect(name, 0):
            return
        child = children[name]
        for signum, seconds in ((signal.SIGINT, 15), (signal.SIGTERM, 5), (signal.SIGKILL, 5)):
            if child.poll() is not None:
                collect(name, 0)
                return
            child.send_signal(signum)
            outcome["signals_sent"].append({"child": name, "pid": child.pid, "signal": signum})
            if collect(name, seconds):
                return
        outcome["children"][name]["termination_unconfirmed"] = True

    def healthy():
        if received_signal is not None:
            raise InterruptedError("Supervisor interrupted")
        if time.monotonic() >= deadline:
            raise TimeoutError("Supervisor deadline exceeded")

    def run_phase(phase, restart_hash=None):
        config = configs[phase]
        directory = life.phase_directory(runtime, config)
        listener_name, client_name = "listener" + str(phase), "client" + str(phase)
        extra = () if phase == 1 else ("--restart-checkpoint-sha256", restart_hash)
        launched = time.monotonic()
        listener = launch(listener_name, extra)
        ready = None
        try:
            while time.monotonic() < launched + 45:
                healthy()
                if listener.poll() is not None:
                    collect(listener_name, 0)
                    raise RuntimeError("Listener exited before ready")
                ready_path = directory / "listener-ready.json"
                if ready_path.exists():
                    try:
                        ready = life.checked_ready(ready_path, config, listener.pid, launched)
                    except json.JSONDecodeError:
                        pass
                    if ready is not None:
                        break
                time.sleep(0.05)
            if ready is None:
                raise TimeoutError("Listener readiness deadline exceeded")
            client = launch(client_name, ("--listener-pid", str(listener.pid)))
            client_deadline = min(time.monotonic() + 160, ready["deadline_monotonic"] - 20)
            while client.poll() is None:
                healthy()
                if listener.poll() is not None or time.monotonic() >= client_deadline:
                    raise RuntimeError("Client/listener did not finish within phase budget")
                time.sleep(0.05)
            collect(client_name, 0)
            if outcome["children"][client_name]["exit_code"] != 0:
                raise RuntimeError("HTTP client failed")
        finally:
            if directory.is_dir():
                life.request_phase_stop(directory, config, listener.pid)
            stop_owned(client_name)
            if not collect(listener_name, 45):
                stop_owned(listener_name)
        if outcome["children"][listener_name]["exit_code"] != 0:
            raise RuntimeError("Listener process failed")
        # These checks occur only after real Popen.wait, not after a stop flag.
        terminal = life.termination_evidence(runtime, phase)
        listener_result = life.read_json(directory / "listener-results.json")
        client_result = life.read_json(directory / "http-results.json")
        if (listener_result.get("pid") != listener.pid or
                listener_result.get("run_identity") != config["run_identity"] or
                client_result.get("client_pid") != children[client_name].pid or
                client_result.get("listener_pid") != listener.pid or
                client_result.get("run_identity") != config["run_identity"] or
                client_result.get("storage_phase") != phase or client_result.get("passed") is not True or
                tuple(client_result.get("cases", ())) != life.HTTP_CASES[phase] or
                client_result.get("all_connections_closed") is not True or
                client_result["completed"]["binding"] != listener_result["final_observation"]["binding"] or
                client_result["completed"]["evidence"] != listener_result["final_observation"]["evidence"]):
            raise RuntimeError("Exact HTTP cases and DB/final observation differ")
        outcome["phases"][str(phase)] = {"ready": ready, "terminal_evidence": terminal,
            "http_result": life.record(directory / "http-results.json"),
            "exact_case_count": len(life.HTTP_CASES[phase]), "passed": True}
        return listener.pid

    try:
        first_pid = run_phase(1)
        restart = {"run_identity": config1["run_identity"], "parent_pid": os.getpid(),
            "phase1_pid": first_pid, "phase1_actual_exit_observed": True, "phase1_exit_code": 0,
            "phase1_config": life.record(preparation / "phase-1-config.json"),
            "phase2_config": life.record(preparation / "phase-2-config.json"),
            "source_manifest": life.record(preparation / "source-manifest.json"),
            "phase1_evidence": life.termination_evidence(runtime, 1),
            "phase1_http": life.record(runtime / "phase-1/http-results.json"),
            "disk_inventory": life.disk_inventory(runtime)}
        life.write_json(runtime / "restart-checkpoint.json", restart)
        restart_hash = life.record(runtime / "restart-checkpoint.json")["sha256"]
        outcome["restart_checkpoint_sha256"] = restart_hash
        second_pid = run_phase(2, restart_hash)
        if first_pid == second_pid:
            raise RuntimeError("Different actual process identity was not observed")
        outcome["passed"] = True
    except BaseException as error:
        outcome["failure_type"] = type(error).__name__
    finally:
        # Emergency paths still stop only owned Popen children and never use a
        # guessed process name. A forced exit remains a failed run.
        for phase in (2, 1):
            listener_name = "listener" + str(phase)
            if listener_name in children:
                directory = runtime / ("phase-" + str(phase))
                if directory.is_dir():
                    try:
                        life.request_phase_stop(directory, configs[phase], children[listener_name].pid)
                    except BaseException as error:
                        outcome["stop_failure_type"] = type(error).__name__
            stop_owned("client" + str(phase))
            stop_owned(listener_name)
        exits_confirmed = all(value["actual_exit_observed"] for value in outcome["children"].values())
        cleanup = []
        if exits_confirmed:
            for path in (runtime / "storage-client-state.json", runtime / "phase-1/storage-http-env.json",
                         runtime / "phase-2/storage-http-env.json"):
                if path.is_symlink():
                    outcome["cleanup_failure_type"] = "SymlinkRefused"
                    continue
                if path.exists():
                    path.unlink()
                    cleanup.append(str(path.relative_to(runtime)))
        outcome["parent_deleted_sensitive_files"] = cleanup
        outcome["all_sensitive_files_absent"] = all(not path.exists() and not path.is_symlink() for path in (
            runtime / "storage-client-state.json", runtime / "phase-1/storage-http-env.json",
            runtime / "phase-2/storage-http-env.json"))
        outcome["all_actual_exits_observed"] = exits_confirmed
        outcome["received_signal"] = received_signal
        outcome["elapsed_seconds"] = time.monotonic() - started
        outcome["passed"] = (outcome["passed"] and set(children) == set(commands) and exits_confirmed and
            all(value["exit_code"] == 0 for value in outcome["children"].values()) and not outcome["signals_sent"] and
            received_signal is None and outcome["all_sensitive_files_absent"] and
            not any(key.endswith("failure_type") for key in outcome))
        for stream in logs.values():
            stream.close()
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        life.write_json(evidence / "result.json", outcome, private=True)
    print(json.dumps({"passed": outcome["passed"], "evidence": str(evidence),
        "child_exits": {name: value["exit_code"] for name, value in outcome["children"].items()}}))
    return 0 if outcome["passed"] else 70


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"passed": False, "failure_type": type(error).__name__}))
        raise SystemExit(70) from None
