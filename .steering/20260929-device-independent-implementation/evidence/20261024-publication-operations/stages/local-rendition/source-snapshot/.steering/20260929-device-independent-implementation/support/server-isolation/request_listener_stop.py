"""Stop-file request; emergency secret cleanup only after the recorded PID is absent."""
import argparse
import json
import os
from pathlib import Path


def paths(config_path):
    config = json.loads(config_path.read_text())
    snapshot = Path(config["snapshot"]).resolve(strict=True)
    runtime = Path(config["runtime"]).resolve(strict=True)
    if runtime.parent != snapshot.parent or not runtime.name.startswith("runtime-listener-"):
        raise SystemExit("Refuse a runtime outside reviewed S20 listener namespace")
    return runtime


def request_stop(runtime, reason):
    path = runtime / "stop.request"
    try:
        with path.open("x") as stream:
            json.dump({"reason": reason, "requester_pid": os.getpid()}, stream)
            stream.write("\n")
    except FileExistsError:
        pass
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--cleanup-secret-after-exit", action="store_true")
    args = parser.parse_args()
    runtime = paths(args.config)
    if not args.cleanup_secret_after_exit:
        request_stop(runtime, "main-reviewed-stop")
        print(json.dumps({"stop_requested": True, "runtime": str(runtime), "actual_stop": "not yet observed"}))
        return
    ready = json.loads((runtime / "listener-ready.json").read_text())
    config = json.loads(args.config.read_text())
    if ready["run_identity"] != config["run_identity"]:
        raise SystemExit("Ready/config run identity mismatch")
    pid = ready["pid"]
    if not isinstance(pid, int) or pid <= 1:
        raise SystemExit("Invalid recorded PID")
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        pass
    except PermissionError:
        raise SystemExit("Recorded PID state is unknown; do not claim cleanup")
    else:
        raise SystemExit("Recorded PID exists or was reused; verify identity/actual exit before cleanup")
    secret = runtime / "simulator-probe-env.json"
    if secret.is_symlink():
        raise SystemExit("Refuse symlink secret")
    if secret.exists():
        secret.unlink()
    record = {"recorded_pid": pid, "pid_observed_absent": True, "secret_absent": not secret.exists(),
              "meaning": "post-exit cleanup only, not evidence of graceful SDK/server teardown"}
    with (runtime / "secret-cleanup-after-exit.json").open("x") as stream:
        json.dump(record, stream, indent=2)
    print(json.dumps(record))


if __name__ == "__main__":
    main()
