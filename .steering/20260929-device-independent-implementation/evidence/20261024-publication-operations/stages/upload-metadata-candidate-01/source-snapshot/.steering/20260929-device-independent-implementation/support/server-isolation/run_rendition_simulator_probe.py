"""S25 exact opt-in Simulator test wrapper. Disposable credentials never enter argv."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time


def helper_module():
    spec = importlib.util.spec_from_file_location("prepare_rendition_fixture", Path(__file__).with_name("prepare_rendition_fixture.py"))
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    return helper


def evaluate(summary, tests, config):
    cases = []
    def visit(node):
        if node.get("nodeType") == "Test Case":
            cases.append(node)
        for child in node.get("children", []):
            visit(child)
    for node in tests.get("testNodes", []):
        visit(node)
    expected = {name.removeprefix("FrameRelayTests/") for name in config["tests"]}
    identifiers = [node.get("nodeIdentifier") for node in cases]
    counts = {k: summary.get(k) for k in ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")}
    expected_counts = {"totalTestCount": 5, "passedTests": 5, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
    expected_device_counts = {"passedTests": 10, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
    devices = summary.get("devicesAndConfigurations", [])
    parameter_cases = [node for node in cases if "rejectsMalformedFixedRangeAndWaitsForTerminal(mode:)" in node.get("nodeIdentifier", "")]
    arguments = [] if len(parameter_cases) != 1 else [node for node in parameter_cases[0].get("children", []) if node.get("nodeType") == "Arguments"]
    parameter_names = [node.get("name", "").strip('"') for node in arguments]
    expected_parameters = {"wrong-version", "wrong-digest", "wrong-size", "short", "oversize", "redirect"}
    execution_count = sum(max(1, len([child for child in node.get("children", []) if child.get("nodeType") == "Arguments"])) for node in cases)
    passed = (summary.get("result") == "Passed" and counts == expected_counts and
        all(type(v) is int for v in counts.values()) and len(devices) == 1 and
        devices[0].get("device", {}).get("deviceId") == config["destination"].split("id=")[1] and
        all(type(devices[0].get(k)) is int and devices[0][k] == v for k, v in expected_device_counts.items()) and
        len(cases) == 5 and set(identifiers) == expected and all(node.get("result") == "Passed" for node in cases) and
        len(arguments) == 6 and set(parameter_names) == expected_parameters and execution_count == 10 and
        all(node.get("result") == "Passed" for node in arguments))
    return {"passed": passed, "summary_counts": counts, "declarations": identifiers,
            "parameter_names": parameter_names, "execution_count": execution_count,
            "device_execution_counts": [{key: device.get(key) for key in expected_device_counts} for device in devices],
            "nonpassing_declarations": [{"identifier": node.get("nodeIdentifier"), "result": node.get("result")}
                for node in cases if node.get("result") != "Passed"]}


def collect_metadata(helper, runtime, bundle, environment, config, token):
    """Collect each document after actual Xcode exit, including failed/interrupted runs."""
    clean_environment = {k: v for k, v in environment.items() if not k.startswith("TEST_RUNNER_")}
    documents, collection = {}, {}

    def retain_stderr(observation, raw):
        raw = raw or b""
        if isinstance(raw, str):
            raw = raw.encode()
        clean = raw if token is None else raw.replace(token.encode(), b"<redacted disposable fixture token>")
        limit = 8192
        truncated = len(clean) > limit
        observation.update(stderr_captured_bytes=len(raw), stderr_byte_limit=limit,
            stderr_truncated=truncated,
            stderr=clean[:limit].decode("utf-8", errors="replace") +
                ("\n[stderr truncated after 8192 bytes]" if truncated else ""))

    for kind, arguments, filename in (
            ("summary", ["test-results", "summary"], "test-summary.json"),
            ("tests", ["test-results", "tests"], "test-tests.json"),
            ("build", ["build-results"], "build-results.json")):
        observation = {"attempted": False, "collected": False, "file": filename}
        collection[kind] = observation
        if not bundle.exists():
            observation["failure_type"] = "MissingResultBundle"
            continue
        try:
            observation["attempted"] = True
            result = subprocess.run(["/usr/bin/xcrun", "xcresulttool", "get", *arguments,
                "--path", str(bundle)], env=clean_environment, stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False)
            observation["tool_exit_code"] = result.returncode
            retain_stderr(observation, result.stderr)
            if result.returncode != 0:
                observation["failure_type"] = "MetadataToolNonzeroExit"
                continue
            if len(result.stdout) > 2 * 1024 * 1024:
                raise RuntimeError("Unexpected xcresult metadata size")
            # Retain the complete tree (all assertion issues), while removing the
            # disposable bearer if an SDK diagnostic unexpectedly reflects it.
            raw = result.stdout if token is None else result.stdout.replace(token.encode(), b"<redacted disposable fixture token>")
            document = json.loads(raw)
            if not isinstance(document, dict):
                raise RuntimeError("Unexpected xcresult metadata document")
            helper.write_json(runtime / filename, document)
            documents[kind] = document
            observation["collected"] = True
        except subprocess.TimeoutExpired as error:
            retain_stderr(observation, error.stderr)
            observation["failure_type"] = type(error).__name__
        except Exception as error:
            observation["failure_type"] = type(error).__name__
    verification = {"passed": False, "evaluation": "metadata_unavailable"}
    if "summary" in documents and "tests" in documents:
        try:
            verification = {**evaluate(documents["summary"], documents["tests"], config), "evaluation": "completed"}
        except Exception as error:
            verification = {"passed": False, "evaluation": "failed", "failure_type": type(error).__name__}
    build = documents.get("build")
    diagnostics = {"available": build is not None}
    if build is not None:
        diagnostics.update({key: build.get(key) for key in ("status", "errorCount", "warningCount", "analyzerWarningCount")})
    summary = documents.get("summary", {})
    return {"metadata_collection": collection, "test_verification": verification,
        "build_diagnostics": diagnostics,
        "observed_test_failures": summary.get("failedTests"),
        "observed_build_failure": None if build is None else build.get("status") != "succeeded" or build.get("errorCount") != 0,
        "metadata_extraction_failed": any(not item["collected"] for item in collection.values())}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--listener-pid", type=int)
    parser.add_argument("--execute-reviewed-xcode", action="store_true")
    args = parser.parse_args()
    helper = helper_module()
    config, checkpoint = helper.verified_config(args.config)
    runtime = Path(config["runtime"])
    bundle = runtime / "rendition-fixture.xcresult"
    command = ["/usr/bin/xcodebuild", "-project", str(helper.PROJECT / "FrameRelay.xcodeproj"),
        "-scheme", "FrameRelay", "-testPlan", "FrameRelay", "-configuration", "Debug",
        "-destination", config["destination"], "-derivedDataPath", config["derived_data"],
        "-disableAutomaticPackageResolution", "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
        "-resultBundlePath", str(bundle), *["-only-testing:" + name for name in config["tests"]], "test", "-quiet"]
    if not args.execute_reviewed_xcode:
        print(json.dumps({"executed": False, "command": command, "declarations": 5, "executions": 10}))
        return 0
    if (args.listener_pid is None or bundle.exists() or (runtime / "wrapper-result.json").exists() or
            helper.app_sources() != checkpoint["app_sources"]):
        raise RuntimeError("Missing live listener, changed app source, or reused result")
    environment = {k: os.environ[k] for k in ("HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ") if k in os.environ}
    environment["PATH"] = "/usr/bin:/bin"
    token, process, output, bound_pid = None, None, b"", None
    started = time.monotonic()
    outcome = {"run_identity": config["run_identity"], "pid": os.getpid(), "passed": False,
        "command": command, "token_in_argv": False, "signals_sent": [], "test_verification": {"passed": False},
        "metadata_collection": {}, "metadata_extraction_failed": None,
        "limitation": "Xcode internal artifacts can retain disposable environment; listener exit revokes its only bearer"}
    def stop_process():
        nonlocal output
        if process is None:
            return
        for signum, seconds in ((signal.SIGINT, 20), (signal.SIGTERM, 5), (signal.SIGKILL, 5)):
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signum)
                    outcome["signals_sent"].append(signum)
                except ProcessLookupError:
                    pass
            try:
                output, _ = process.communicate(timeout=seconds)
                outcome["xcode_actual_exit_observed"] = True
                outcome["xcode_exit_code"] = process.returncode
                return
            except subprocess.TimeoutExpired:
                continue
        outcome["termination_unconfirmed"] = True
    def interrupted(_signum, _frame):
        raise InterruptedError("S25 wrapper interrupted")
    old_handlers = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        ready = helper.checked_ready(runtime, config, pid=args.listener_pid)
        bound_pid = ready["pid"]
        secret_path = runtime / "fixture-env.json"
        if stat.S_IMODE(secret_path.lstat().st_mode) != 0o600:
            raise RuntimeError("Fixture environment must be 0600")
        secret = helper.read_json(secret_path)
        values = secret["environment"]
        if (secret.get("run_identity") != config["run_identity"] or secret.get("listener_pid") != bound_pid or
                secret.get("url") != ready["url"] or set(values) != set(helper.KEYS) or
                values["FR_S25_HTTP_FIXTURE"] != "1" or values["FR_S25_FIXTURE_URL"] != ready["url"] or
                values["FR_S25_FIXTURE_ID"] != config["fixture_id"] or
                values["FR_S25_FIXTURE_SHA256"] != config["fixture"]["sha256"] or
                values["FR_S25_FIXTURE_BYTE_COUNT"] != str(config["fixture"]["byteCount"]) or
                values["FR_S25_FIXTURE_MIME"] != config["fixture"]["mime"]):
            raise RuntimeError("Fixture environment identity mismatch")
        token = values["FR_S25_FIXTURE_TOKEN"]
        if not isinstance(token, str) or not token:
            raise RuntimeError("Missing fixture bearer")
        outcome["xcode_version"] = subprocess.run(["/usr/bin/xcodebuild", "-version"], env=environment,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10, check=True).stdout.decode()
        outcome["developer_directory"] = subprocess.run(["/usr/bin/xcode-select", "-p"], env=environment,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10, check=True).stdout.decode().strip()
        seconds = min(1100, ready["deadline_monotonic"] - time.monotonic() - 60)
        if seconds < 180:
            raise RuntimeError("Insufficient listener lifetime for Simulator run")
        environment.update({"TEST_RUNNER_" + key: value for key, value in values.items()})
        process = subprocess.Popen(command, cwd=helper.PROJECT, env=environment, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            output, _ = process.communicate(timeout=seconds)
            outcome["xcode_actual_exit_observed"] = True
            outcome["xcode_exit_code"] = process.returncode
        except subprocess.TimeoutExpired:
            outcome["timed_out"] = True
            stop_process()
    except BaseException as error:
        outcome["failure_type"] = type(error).__name__
        stop_process()
    finally:
        if bound_pid is not None:
            try:
                helper.stop(runtime, config, bound_pid)
            except Exception as error:
                outcome["stop_failure_type"] = type(error).__name__
        if outcome.get("xcode_actual_exit_observed") is True:
            outcome.update(collect_metadata(helper, runtime, bundle, environment, config, token))
        else:
            outcome["metadata_not_attempted_reason"] = "xcode_actual_exit_not_observed"
        for sig, old in old_handlers.items():
            signal.signal(sig, old)
        for key in tuple(environment):
            if key.startswith("TEST_RUNNER_"):
                del environment[key]
        clean = output if token is None else output.replace(token.encode(), b"<redacted disposable fixture token>")
        with os.fdopen(os.open(runtime / "xcodebuild-redacted.log", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
            stream.write(clean)
        outcome["app_sources_unchanged"] = helper.app_sources() == checkpoint["app_sources"]
        outcome["elapsed_seconds"] = time.monotonic() - started
        outcome["xcode_failed"] = (outcome.get("xcode_exit_code") != 0
            if outcome.get("xcode_actual_exit_observed") is True else None)
        outcome["passed"] = (outcome.get("xcode_actual_exit_observed") is True and outcome.get("xcode_exit_code") == 0 and
            outcome["test_verification"]["passed"] and outcome["app_sources_unchanged"] and
            outcome["metadata_extraction_failed"] is False and outcome.get("observed_build_failure") is False and
            not outcome["signals_sent"] and not any(key.endswith("failure_type") for key in outcome) and not outcome.get("timed_out"))
        helper.write_json(runtime / "wrapper-result.json", outcome, private=True)
    print(json.dumps({"passed": outcome["passed"], "xcode_exit_code": outcome.get("xcode_exit_code")}))
    return 0 if outcome["passed"] else 70


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"passed": False, "failure_type": type(error).__name__}))
        raise SystemExit(70) from None
