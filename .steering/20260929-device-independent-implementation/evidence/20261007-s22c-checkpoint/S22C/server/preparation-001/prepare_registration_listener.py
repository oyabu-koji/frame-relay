"""Copy verified S22 to a fresh S22C namespace without importing backend/pytest."""
import argparse
import ast
import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil
from uuid import uuid4


ROOT = Path("/private/tmp/fr-di-20261001-5ljls2fr")
OUTPUT = ROOT / "S22C/server"
SUPPORT = Path("/Users/oyabu/dev/rep/FrameRelay/.steering/20260929-device-independent-implementation/support/server-isolation")
BASE = ROOT / "S22/snapshot-001"
BASE_PREPARATION = ROOT / "S22/preparation-001"


def record(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError("Expected regular source file")
    data = path.read_bytes()
    return {"kind": "file", "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def tree(root):
    return {str(path.relative_to(root)): record(path) for path in sorted(root.rglob("*"))
            if path.is_file() or path.is_symlink()}


def dump(path, value):
    with path.open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def copy(source, destination):
    record(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as reader, destination.open("xb") as writer:
        shutil.copyfileobj(reader, writer)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--revision", required=True)
    parser.add_argument("--test", action="append", required=True)
    args = parser.parse_args()
    if re.fullmatch(r"[0-9]{3}", args.revision) is None:
        raise SystemExit("Expected three-digit fresh revision")
    tests = args.test
    if len(tests) != len(set(tests)) or any(re.fullmatch(
        r"FrameRelayTests/Registration(?:Server|Transport)ProbeTests/test[A-Za-z0-9_]+", item
    ) is None for item in tests):
        raise SystemExit("Expected explicit reviewed registration probe test methods")
    provenance_path = BASE_PREPARATION / "provenance-before.json"
    original = json.loads(provenance_path.read_text())
    base_before = tree(BASE)
    if base_before != original["snapshot"]:
        raise SystemExit("Verified S22 snapshot identity mismatch")
    result_path = ROOT / "S22/runtime-pytest-001/result.json"
    result = json.loads(result_path.read_text())
    if (result["exit_code"] != 0 or result["pytest_exit_code"] != 0 or
            result["pytest_counts"] != {"tests": 46, "failures": 0, "errors": 0, "skipped": 0} or
            result["inputs_unchanged"] is not True or result["unreviewed_import_origins"]):
        raise SystemExit("Expected successful S22 evidence")
    external = Path(original["external_root"])
    source_before = {name: record(external / name) for name in original["source_before"]}
    if source_before != original["source_before"]:
        raise SystemExit("External tracked source changed")
    support_before = tree(SUPPORT)
    guard_before = record(SUPPORT / "isolation_guard.py")
    if guard_before != record(BASE_PREPARATION / "source-snapshot/server-isolation/isolation_guard.py"):
        raise SystemExit("Guard differs from successful S22 version; separate review required")
    for name in support_before:
        if name.endswith(".py"):
            ast.parse((SUPPORT / name).read_text(), filename=name)
    snapshot = OUTPUT / ("snapshot-" + args.revision)
    evidence = OUTPUT / ("preparation-" + args.revision)
    runtime = OUTPUT / ("runtime-listener-" + args.revision)
    if any(path.exists() or path.is_symlink() for path in (snapshot, evidence, runtime)):
        raise SystemExit("Refusing to reuse snapshot/evidence/runtime")
    snapshot.mkdir(parents=True)
    evidence.mkdir()
    for name in base_before:
        copy(BASE / name, snapshot / name)
    frozen = evidence / "source-snapshot"
    for name in support_before:
        copy(SUPPORT / name, frozen / name)
    copy(Path(__file__), evidence / "prepare_registration_listener.py")
    snapshot_manifest = tree(snapshot)
    if snapshot_manifest != base_before or tree(BASE) != base_before or tree(SUPPORT) != support_before:
        raise SystemExit("Source changed during copy")
    source_after = {name: record(external / name) for name in original["source_before"]}
    if source_after != source_before:
        raise SystemExit("External source changed during copy")
    provenance = dict(original)
    provenance.update({"snapshot": snapshot_manifest,
        "s22_parent_provenance": str(provenance_path), "s22_parent_provenance_record": record(provenance_path),
        "s22_verified_snapshot": str(BASE), "s22_verified_result_record": record(result_path),
        "snapshot_is_byte_identical_s22_copy": True, "source_after_snapshot": source_after,
        "backend_imported": False, "tests_executed": False})
    new_provenance = evidence / "provenance-before.json"
    dump(new_provenance, provenance)
    config = {"snapshot": str(snapshot), "runtime": str(runtime),
        "external_root": str(external), "site_packages": original["site_packages_root"],
        "provenance": str(new_provenance), "interpreter": original["interpreter"]["entry"],
        "allow_missing_ffprobe_version_probe": True, "action": "registration-listener",
        "allow_reviewed_loopback_listener": True, "listener_deadline_seconds": 1200,
        "allow_registration_transport_probe_routes": True,
        "transport_probe_oversize_bytes": 16385, "transport_probe_slow_seconds": 5,
        "run_identity": str(uuid4()), "xcode_only_testing": tests}
    config_path = evidence / "run-config.json"
    dump(config_path, config)
    prior_runner = BASE_PREPARATION / "source-snapshot/server-isolation/run_pytest.py"
    runner_diff = "".join(difflib.unified_diff(prior_runner.read_text().splitlines(keepends=True),
        (SUPPORT / "run_pytest.py").read_text().splitlines(keepends=True),
        fromfile="S22-frozen/run_pytest.py", tofile="S22C/run_pytest.py"))
    (evidence / "runner.diff").write_text(runner_diff)
    commands = {"listener": [config["interpreter"], "-I", "-B", "-S", str(frozen / "run_pytest.py"),
                              "--config", str(config_path)],
        "simulator": ["python3", "-I", "-B", "-S", str(frozen / "run_registration_simulator_probe.py"),
                      "--config", str(config_path), "--execute-reviewed-xcode"],
        "stop_request": ["python3", "-I", "-B", "-S", str(frozen / "request_listener_stop.py"),
                         "--config", str(config_path)],
        "env_names": ["FR_REGISTRATION_PROBE", "FR_REGISTRATION_BASE_URL",
                      "FR_REGISTRATION_BOOTSTRAP_TOKEN", "FR_REGISTRATION_DESTINATION_ID"],
        "executed": False, "requires": "main review and permission for this listener and Xcode wrapper"}
    dump(evidence / "commands.json", commands)
    for directory in (snapshot, frozen):
        for path in directory.rglob("*"):
            if path.is_file():
                path.chmod(0o444)
    manifest = {"snapshot": snapshot_manifest, "frozen_sources": tree(frozen),
        "snapshot_is_byte_identical_s22_copy": True, "s22_base_unchanged": True,
        "external_tracked_source_unchanged": True, "guard_unchanged_from_s22": True,
        "base_provenance": record(provenance_path), "s22_result": record(result_path),
        "provenance": record(new_provenance), "run_config": record(config_path),
        "commands": record(evidence / "commands.json"), "runner_diff": record(evidence / "runner.diff"),
        "preparation_script": record(evidence / "prepare_registration_listener.py"),
        "xcode_only_testing": tests, "backend_imported": False, "tests_executed": False,
        "listener_started": False, "runtime_created": False,
        "limits": ["guard is Python audit/SQLite containment, not a complete native OS sandbox",
                   "Xcode wrapper needs separately reviewed ordinary Simulator/Xcode writes",
                   "no real Wi-Fi/TLS/background/physical-device or PRD acceptance claim"]}
    manifest_path = evidence / "checkpoint-files.json"
    dump(manifest_path, manifest)
    print(json.dumps({"evidence": str(evidence), "snapshot_files": len(snapshot_manifest),
        "frozen_source_files": len(support_before), "test_methods": len(tests),
        "checkpoint_sha256": record(manifest_path)["sha256"], "runtime_created": False}))


if __name__ == "__main__":
    main()
