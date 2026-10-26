"""Disposable stdlib-only guard checks, each case in a separate main-launched process.

Preparation/--show-commands does not run a check or launch subprocesses.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import posix
import re
import sys
import threading


CASES = ("inside", "posix_inside", "outside_fd", "parent_escape", "symlink_escape",
         "absolute_inside", "absolute_outside", "reserved", "thread_inside", "thread_outside",
         "read_only_fd", "invalid_fd")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--trial", type=Path, required=True)
    parser.add_argument("--case", choices=CASES)
    parser.add_argument("--guard-sha256", required=True)
    parser.add_argument("--show-commands", action="store_true")
    args = parser.parse_args()
    source = Path(__file__).with_name("isolation_guard.py")
    if hashlib.sha256(source.read_bytes()).hexdigest() != args.guard_sha256:
        raise RuntimeError("Guard source differs from reviewed hash")
    if (args.trial.parent != Path("/private/tmp") or
            re.fullmatch(r"fr-s24-guard-[a-zA-Z0-9-]+", args.trial.name) is None or args.trial.is_symlink()):
        raise RuntimeError("Expected new private-tmp guard trial namespace")
    if args.show_commands:
        print(json.dumps({"executed": False, "commands": [[sys.executable, "-I", "-B", "-S",
            str(Path(__file__).resolve()), "--trial", str(args.trial), "--case", case,
            "--guard-sha256", args.guard_sha256] for case in CASES]}, indent=2))
        return 0
    if args.case is None or not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
        raise RuntimeError("Require an explicit case under -I -B -S")
    # All outside targets are disposable siblings created by this one case.
    case_root = args.trial / args.case
    case_root.mkdir(parents=True, exist_ok=False)
    runtime, outside = case_root / "runtime", case_root / "outside"
    runtime.mkdir()
    outside.mkdir()
    inside = runtime / "nested"
    inside.mkdir()
    sentinel = outside / "sentinel"
    sentinel.write_bytes(b"outside-must-remain-unchanged")
    (runtime / "escape").symlink_to(outside, target_is_directory=True)
    original = sentinel.read_bytes()
    inside_fd, outside_fd = os.open(inside, os.O_RDONLY), os.open(outside, os.O_RDONLY)
    spec = importlib.util.spec_from_file_location("guard_check", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    guard = module.Guard(runtime)
    guard.install()
    os.chdir(runtime)
    observed = {"case": args.case, "guard_sha256": args.guard_sha256,
                "backend_imported": False, "subprocess_launched": False}
    negative = args.case in {"outside_fd", "parent_escape", "symlink_escape", "absolute_outside",
                             "reserved", "thread_outside"}
    outcomes = []

    def operation():
        path, directory = "created", inside_fd
        opener, flags = os.open, os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if args.case == "posix_inside":
            opener = posix.open
        elif args.case in {"outside_fd", "thread_outside"}:
            directory = outside_fd
        elif args.case == "parent_escape":
            path = "../../outside/created"
        elif args.case == "symlink_escape":
            path, directory = "escape/created", None
        elif args.case == "absolute_inside":
            path, directory = str(inside / "created"), outside_fd
        elif args.case == "absolute_outside":
            path = str(outside / "created")
        elif args.case == "reserved":
            path = str(runtime / "disabled-ffprobe")
        elif args.case == "read_only_fd":
            path, directory, flags = "sentinel", outside_fd, os.O_RDONLY
        elif args.case == "invalid_fd":
            directory, flags = -999, os.O_RDONLY
        descriptor = None
        try:
            descriptor = opener(path, flags, 0o600, dir_fd=directory)
            if flags == os.O_RDONLY:
                if os.read(descriptor, len(original) + 1) != original:
                    raise RuntimeError("Read-only FD changed behavior")
            else:
                os.write(descriptor, b"inside")
            outcomes.append("allowed")
        except module.IsolationViolation:
            outcomes.append("denied")
        except OSError as error:
            outcomes.append("errno-" + str(error.errno))
        finally:
            if descriptor is not None:
                os.close(descriptor)

    try:
        if args.case.startswith("thread_"):
            thread = threading.Thread(target=operation)
            thread.start()
            thread.join(timeout=5)
            if thread.is_alive():
                raise RuntimeError("Guard check thread did not terminate")
        else:
            operation()
    finally:
        os.close(inside_fd)
        os.close(outside_fd)
    result = guard.finish()
    entries = [json.loads(line) for line in (runtime / "audit.jsonl").read_text().splitlines()]
    expected = ["denied"] if negative else ["errno-9"] if args.case == "invalid_fd" else ["allowed"]
    correct_path = True
    if not negative and args.case not in {"read_only_fd", "invalid_fd"}:
        writes = [entry["detail"]["path"] for entry in entries if entry["event"] == "open"]
        correct_path = str(inside / "created") in writes and (inside / "created").read_bytes() == b"inside"
    unchanged = (sentinel.read_bytes() == original and sorted(p.name for p in outside.iterdir()) == ["sentinel"]
                 and not (runtime / "disabled-ffprobe").exists())
    observed.update(outcomes=outcomes, expected=expected, outside_unchanged=unchanged,
        correct_resolved_write_path=correct_path, expected_denials=1 if negative else 0,
        actual_denials=len(result["denials"]), guard=result)
    observed["passed"] = (outcomes == expected and unchanged and correct_path and
                          len(result["denials"]) == (1 if negative else 0))
    with (runtime / "check-result.json").open("x") as stream:
        json.dump(observed, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps({"case": args.case, "passed": observed["passed"], "evidence": str(runtime)}))
    return 0 if observed["passed"] else 70


if __name__ == "__main__":
    raise SystemExit(main())
