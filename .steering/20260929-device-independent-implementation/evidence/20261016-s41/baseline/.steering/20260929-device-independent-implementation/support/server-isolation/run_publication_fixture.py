"""S27 supervisor: frozen fixture listener -> real Simulator tests -> actual child exit."""
import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--checkpoint-sha256", required=True)
    parser.add_argument("--execute-reviewed-integration", action="store_true")
    args = parser.parse_args()
    support = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("prepare_publication_probe", support / "prepare_publication_probe.py")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    config, checkpoint = helper.verified_config(args.config)
    preparation = Path(config["preparation"])
    runtime = Path(config["runtime"])
    if (helper.record(preparation / "checkpoint.json")["sha256"] != args.checkpoint_sha256 or
            support != preparation / "source-snapshot" or runtime.exists() or runtime.is_symlink() or
            helper.app_sources() != checkpoint["app_sources"] or
            helper.record(Path(config["fixture"]["path"])) != config["fixture_record"]):
        raise RuntimeError("Changed input or reused fixture execution")
    helper.verify_inputs(config, checkpoint)
    commands = {name: [config["interpreter"], "-I", "-B", "-S", str(support / filename),
                       "--config", str(args.config)] for name, filename in (
                           ("listener", "publication_fixture_listener.py"), ("simulator", "run_publication_simulator_probe.py"))}
    if not args.execute_reviewed_integration:
        print(json.dumps({"executed": False, "commands": commands,
            "simulator_execute_suffix": ["--listener-pid", "<actual owned PID>", "--execute-reviewed-xcode"],
            "fixture_only": True, "runtime": str(runtime)}, indent=2))
        return 0
    evidence = preparation / "supervisor"
    evidence.mkdir(exist_ok=False)
    environment = {k: os.environ[k] for k in ("HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ") if k in os.environ}
    environment["PATH"] = "/usr/bin:/bin"
    logs, children = {}, {}
    started, received_signal = time.monotonic(), None
    outcome = {"run_identity": config["run_identity"], "parent_pid": os.getpid(), "children": {},
        "signals_sent": [], "passed": False, "secret_environment_read": False, "fixture_only": True}
    def interrupted(signum, _frame):
        nonlocal received_signal
        received_signal = signum
    previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGINT, signal.SIGTERM)}

    def launch(name, extra=()):
        stream = os.fdopen(os.open(evidence / (name + ".log"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb")
        logs[name] = stream
        child = subprocess.Popen(commands[name] + list(extra), cwd=preparation, env=environment,
            stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        children[name] = child
        outcome["children"][name] = {"pid": child.pid, "actual_exit_observed": False, "exit_code": None}
        return child

    def collect(name, seconds):
        try:
            code = children[name].wait(timeout=max(0, seconds))
        except subprocess.TimeoutExpired:
            return False
        outcome["children"][name].update(actual_exit_observed=True, exit_code=code)
        return True

    def stop_owned(name):
        if name not in children or collect(name, 0):
            return
        child = children[name]
        for sig, seconds in ((signal.SIGINT, 40 if name == "simulator" else 15),
                             (signal.SIGTERM, 10), (signal.SIGKILL, 5)):
            if child.poll() is None:
                child.send_signal(sig)
                outcome["signals_sent"].append({"child": name, "pid": child.pid, "signal": sig})
            if collect(name, seconds):
                return
        outcome["children"][name]["termination_unconfirmed"] = True

    try:
        launched = time.monotonic()
        listener = launch("listener")
        ready = None
        while time.monotonic() < launched + 45:
            if received_signal is not None:
                raise InterruptedError("Supervisor interrupted")
            if listener.poll() is not None:
                collect("listener", 0)
                raise RuntimeError("Listener exited before ready")
            if (runtime / "listener-ready.json").exists():
                try:
                    ready = helper.checked_ready(runtime, config, pid=listener.pid, launched=launched)
                except json.JSONDecodeError:
                    pass
                if ready is not None:
                    break
            time.sleep(0.05)
        if ready is None:
            raise TimeoutError("Fixture startup deadline exceeded")
        outcome["ready"] = ready
        wrapper = launch("simulator", ("--listener-pid", str(listener.pid), "--execute-reviewed-xcode"))
        while wrapper.poll() is None:
            if received_signal is not None:
                raise InterruptedError("Supervisor interrupted")
            if time.monotonic() >= min(started + 1200, ready["deadline_monotonic"] - 20):
                raise TimeoutError("Simulator deadline exceeded")
            if listener.poll() is not None:
                collect("listener", 0)
                if collect("simulator", 35):  # wrapper requests stop before 3 metadata queries, each bounded to 10s
                    break
                raise RuntimeError("Listener exited during Simulator execution")
            time.sleep(0.1)
        collect("simulator", 0)
    except BaseException as error:
        outcome["failure_type"] = type(error).__name__
    finally:
        if "listener" in children and runtime.is_dir():
            try:
                helper.stop(runtime, config, children["listener"].pid)
            except BaseException as error:
                outcome["stop_failure_type"] = type(error).__name__
        stop_owned("simulator")
        if "listener" in children and not collect("listener", 45):
            stop_owned("listener")
        for sig, old in previous.items():
            signal.signal(sig, old)
        for stream in logs.values():
            stream.close()
        exits = outcome["children"]
        all_exited = all(value["actual_exit_observed"] for value in exits.values())
        outcome["all_actual_exits_observed"] = all_exited
        outcome["parent_deleted_secret_after_exit"] = False
        secret = runtime / "fixture-env.json"
        if all_exited and secret.exists() and not secret.is_symlink():
            secret.unlink()
            outcome["parent_deleted_secret_after_exit"] = True
        outcome["secret_absent_after_exit"] = not secret.exists() and not secret.is_symlink()
        outcome["result_hashes"], outcome["artifact_status"] = {}, {}
        documents = {}
        required_artifacts = ("result.json", "listener-results.json", "wrapper-result.json", "audit.jsonl",
                              "import-origins.json", "test-summary.json", "test-tests.json", "build-results.json")
        for name in required_artifacts:
            try:
                outcome["result_hashes"][name] = helper.record(runtime / name)
                if name in ("result.json", "listener-results.json", "wrapper-result.json"):
                    document = helper.read_json(runtime / name)
                    if not isinstance(document, dict):
                        raise RuntimeError("Unexpected child result document")
                    documents[name] = document
                outcome["artifact_status"][name] = {"available": True}
            except Exception as error:
                outcome["artifact_status"][name] = {"available": False, "failure_type": type(error).__name__}
        wrapper_summary = documents.get("wrapper-result.json", {})
        outcome["child_result_summary"] = {
            "runner_passed": documents.get("result.json", {}).get("passed"),
            "listener_passed": documents.get("listener-results.json", {}).get("passed"),
            "wrapper_passed": wrapper_summary.get("passed"),
            "xcode_actual_exit_observed": wrapper_summary.get("xcode_actual_exit_observed"),
            "xcode_exit_code": wrapper_summary.get("xcode_exit_code"),
            "test_verification": wrapper_summary.get("test_verification"),
            "build_diagnostics": wrapper_summary.get("build_diagnostics"),
            "observed_test_failures": wrapper_summary.get("observed_test_failures"),
            "observed_build_failure": wrapper_summary.get("observed_build_failure"),
            "metadata_collection": wrapper_summary.get("metadata_collection"),
            "metadata_extraction_failed": wrapper_summary.get("metadata_extraction_failed"),
            "wrapper_failure_type": wrapper_summary.get("failure_type")}
        outcome["nonzero_child_exits"] = {name: value["exit_code"] for name, value in exits.items()
            if value["actual_exit_observed"] and value["exit_code"] != 0}
        try:
            runner = documents["result.json"]
            listener_result = documents["listener-results.json"]
            wrapper_result = documents["wrapper-result.json"]
            observation = helper.publication_observations(listener_result)
            if observation != listener_result.get("wire_observation"):
                raise RuntimeError("Publication wire observations changed")
            outcome["http_observation"] = observation
            audit = [json.loads(line) for line in (runtime / "audit.jsonl").read_text().splitlines()]
            outcome["passed"] = (set(exits) == set(commands) and all_exited and
                all(item["available"] for item in outcome["artifact_status"].values()) and
                all(value["exit_code"] == 0 for value in exits.values()) and
                runner.get("passed") is True and listener_result.get("passed") is True and wrapper_result.get("passed") is True and
                runner.get("run_identity") == listener_result.get("run_identity") == wrapper_result.get("run_identity") == config["run_identity"] and
                runner.get("pid") == listener_result.get("pid") == exits["listener"]["pid"] and wrapper_result.get("pid") == exits["simulator"]["pid"] and
                not any(row["event"].startswith("denied:") for row in audit) and all(value is True for value in observation.values()) and
                outcome["secret_absent_after_exit"] and not outcome["parent_deleted_secret_after_exit"] and
                not outcome["signals_sent"] and received_signal is None and
                not any(key.endswith("failure_type") for key in outcome))
        except BaseException as error:
            outcome["evidence_failure_type"] = type(error).__name__
        outcome["received_signal"] = received_signal
        outcome["elapsed_seconds"] = time.monotonic() - started
        helper.write_json(evidence / "result.json", outcome, private=True)
    print(json.dumps({"passed": outcome["passed"], "evidence": str(evidence),
                     "child_exits": {name: value["exit_code"] for name, value in outcome["children"].items()}}))
    return 0 if outcome["passed"] else 70


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"passed": False, "failure_type": type(error).__name__}))
        raise SystemExit(70) from None
