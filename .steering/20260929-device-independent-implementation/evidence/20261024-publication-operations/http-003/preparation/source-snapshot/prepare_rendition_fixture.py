"""S25 test-only fixture preparation and shared stdlib metadata checks."""
import argparse
import ast
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import time
from urllib.parse import urlsplit
from uuid import uuid4

PROJECT = Path("/Users/oyabu/dev/rep/FrameRelay")
ROOT = Path("/private/tmp/fr-di-20261014-s25/S25")
ARCHIVE = PROJECT / ".steering/20260929-device-independent-implementation/evidence/20261014-s26j-complete"
FILES = ("prepare_rendition_fixture.py", "rendition_fixture_listener.py", "run_rendition_fixture.py",
         "run_rendition_simulator_probe.py", "README-rendition.md", "isolation_guard.py",
         "listener_lifecycle.py", "run_pytest.py")
METHODS = (
    "authenticatedStreamingAdvancesBeforeFullFileAndActuallyTerminates()",
    "rejectsMalformedFixedRangeAndWaitsForTerminal(mode:)",
    "exactRangeGateChangeAndStopDuringResponse()",
    "authenticationFailureAndGateLossDuringResponseDoNotDeliverBytes()",
    "httpRetrievalVerifiesWholeFileBeforePhotoUse()",
)
MODES = ("normal", "wrong-version", "wrong-digest", "wrong-size", "short", "oversize", "redirect", "delayed")
KEYS = ("FR_S25_HTTP_FIXTURE", "FR_S25_FIXTURE_URL", "FR_S25_FIXTURE_TOKEN", "FR_S25_FIXTURE_ID",
        "FR_S25_FIXTURE_SHA256", "FR_S25_FIXTURE_BYTE_COUNT", "FR_S25_FIXTURE_MIME")


def record(path, *, dependency=False):
    path = Path(path)
    if path.is_symlink() and dependency:
        return {"kind": "symlink", "target": os.readlink(path), "resolved": str(path.resolve(strict=True))}
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise RuntimeError("Expected regular reviewed input")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return {"kind": "file", "size": info.st_size, "sha256": digest.hexdigest()}


def tree(root, *, dependency=False):
    return {str(p.relative_to(root)): record(p, dependency=dependency)
        for p in sorted(root.rglob("*")) if p.is_file() or p.is_symlink()}


def read_json(path):
    record(path)
    return json.loads(Path(path).read_text())


def write_json(path, value, *, private=False):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600 if private else 0o644)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def module(name, directory=None):
    path = (Path(__file__).parent if directory is None else directory) / (name + ".py")
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def verify_dependencies(provenance):
    site = Path(provenance["site_packages_root"])
    interpreter = Path(provenance["interpreter"]["entry"])
    if (tree(site, dependency=True) != provenance["site_packages_before"] or
            record(interpreter, dependency=True) != provenance["interpreter"]["record"] or
            record(interpreter.resolve(strict=True)) != provenance["interpreter"]["resolved_record"] or
            (interpreter.parent.parent / "pyvenv.cfg").read_text() != provenance["pyvenv_cfg"] or
            {str(p.relative_to(site)): p.read_text() for p in sorted(site.glob("*.pth"))} != provenance["pth"]):
        raise RuntimeError("Reviewed interpreter/dependencies changed")


def app_sources():
    result = {}
    for name in ("FrameRelay", "FrameRelayTests", "FrameRelayUITests", "FrameRelay.xcodeproj"):
        for p in sorted((PROJECT / name).rglob("*")):
            if "xcuserdata" in p.parts or p.name == ".DS_Store":
                continue
            if p.is_file() or p.is_symlink():
                result[str(p.relative_to(PROJECT))] = record(p)
    return result


def verified_config(path):
    config = read_json(path)
    preparation = Path(config["preparation"])
    runtime = Path(config["runtime"])
    if (path != preparation / "config.json" or preparation.parent != ROOT or
            re.fullmatch(r"preparation-[0-9]{3}", preparation.name) is None or
            runtime != ROOT / ("runtime-fixture-" + preparation.name.removeprefix("preparation-")) or
            config.get("action") != "rendition-fixture-only" or config.get("listener_deadline_seconds") != 1200 or
            config.get("tests") != ["FrameRelayTests/RenditionHTTPFixtureTests/" + name for name in METHODS]):
        raise RuntimeError("Unreviewed fixture configuration")
    checkpoint = read_json(preparation / "checkpoint.json")
    if record(path) != checkpoint["config"]:
        raise RuntimeError("Fixture configuration changed")
    source = preparation / "source-snapshot"
    if tree(source) != checkpoint["source_files"]:
        raise RuntimeError("Frozen fixture sources changed")
    if record(preparation / "dependency-provenance.json") != checkpoint["dependency_provenance"]:
        raise RuntimeError("Dependency provenance changed")
    return config, checkpoint


def checked_ready(runtime, config, *, pid=None, launched=None):
    ready = read_json(runtime / "listener-ready.json")
    url = urlsplit(ready.get("url", ""))
    start, deadline = ready.get("started_monotonic"), ready.get("deadline_monotonic")
    if (ready.get("run_identity") != config["run_identity"] or type(ready.get("pid")) is not int or
            ready["pid"] <= 1 or (pid is not None and ready["pid"] != pid) or
            type(start) not in (int, float) or type(deadline) not in (int, float) or
            not math.isfinite(start) or not math.isfinite(deadline) or deadline - start != 1200 or
            (launched is not None and not launched <= start <= time.monotonic()) or time.monotonic() >= deadline or
            url.scheme != "http" or url.hostname != "127.0.0.1" or url.path != "/media" or
            url.username or url.password or url.query or url.fragment or url.port is None or
            not 1 <= url.port <= 65535 or ready["url"] != "http://127.0.0.1:" + str(url.port) + "/media"):
        raise RuntimeError("Fixture ready identity/origin mismatch")
    os.kill(ready["pid"], 0)
    return ready


def stop(runtime, config, pid):
    value = {"run_identity": config["run_identity"], "listener_pid": pid,
             "requester_pid": os.getpid(), "reason": "reviewed-stop"}
    path = runtime / "stop.request"
    if path.exists():
        previous = read_json(path)
        if any(previous.get(k) != value[k] for k in ("run_identity", "listener_pid")):
            raise RuntimeError("Stop request identity mismatch")
    else:
        write_json(path, value)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--revision", required=True)
    parser.add_argument("--fixture-manifest", type=Path, required=True)
    parser.add_argument("--enumeration", type=Path, required=True)
    parser.add_argument("--xcode-list", type=Path, required=True)
    parser.add_argument("--destinations", type=Path, required=True)
    parser.add_argument("--destination-udid", required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    args = parser.parse_args()
    if re.fullmatch(r"[0-9]{3}", args.revision) is None:
        raise RuntimeError("Require a fresh three-digit revision")
    fixture = read_json(args.fixture_manifest)
    movie = Path(fixture["path"]).resolve(strict=True)
    movie_record = record(movie)
    if (fixture.get("fixtureOnly") is not True or fixture.get("duration") != 60 or
            fixture.get("mime") not in ("video/quicktime", "video/mp4") or
            fixture.get("byteCount") != movie_record["size"] or fixture.get("sha256") != movie_record["sha256"] or
            movie_record["size"] <= 65536):
        raise RuntimeError("Fixture differs from generated 60-second synthetic movie")
    enumeration = read_json(args.enumeration)
    plans = enumeration.get("values", [])
    expected = ["FrameRelayTests/RenditionHTTPFixtureTests/" + name for name in METHODS]
    if (enumeration.get("errors") != [] or len(plans) != 1 or plans[0].get("testPlan") != "FrameRelay" or
            sorted(item["identifier"] for item in plans[0].get("enabledTests", [])) != sorted(expected)):
        raise RuntimeError("SDK enumeration differs from exact five declarations")
    if (re.fullmatch(r"[0-9A-F-]{36}", args.destination_udid) is None or
            args.destination_udid not in args.destinations.read_text() or
            "FrameRelay" not in args.xcode_list.read_text() or
            not args.derived_data.is_absolute() or not args.derived_data.is_relative_to(Path("/private/tmp"))):
        raise RuntimeError("Unverified Xcode configuration/destination/derived data")
    provenance_path = ARCHIVE / "preparation-001/provenance-before.json"
    checkpoint_path = ARCHIVE / "preparation-001/checkpoint-files.json"
    archived = read_json(ARCHIVE / "archive-manifest.json")
    archive_entries = {entry["path"]: entry for entry in archived["entries"]}
    if len(archive_entries) != len(archived["entries"]):
        raise RuntimeError("Duplicate archive entries")
    for relative in ("preparation-001/provenance-before.json", "preparation-001/checkpoint-files.json"):
        actual = record(ARCHIVE / relative)
        entry = archive_entries[relative]
        if actual["size"] != entry["bytes"] or actual["sha256"] != entry["sha256"]:
            raise RuntimeError("Archived dependency provenance changed")
    if record(provenance_path) != read_json(checkpoint_path)["provenance"]:
        raise RuntimeError("Dependency provenance checkpoint mismatch")
    provenance = read_json(provenance_path)
    verify_dependencies(provenance)
    support = Path(__file__).resolve().parent
    sources = {name: record(support / name) for name in FILES}
    for name in FILES:
        if name.endswith(".py"):
            compile(ast.parse((support / name).read_text(), filename=name), name, "exec")
    preparation = ROOT / ("preparation-" + args.revision)
    runtime = ROOT / ("runtime-fixture-" + args.revision)
    if any(path.exists() or path.is_symlink() for path in (preparation, runtime)):
        raise RuntimeError("Refuse reused fixture namespace")
    preparation.mkdir(parents=True)
    frozen = preparation / "source-snapshot"
    frozen.mkdir()
    for name in FILES:
        with (support / name).open("rb") as reader, (frozen / name).open("xb") as writer:
            shutil.copyfileobj(reader, writer)
    write_json(preparation / "dependency-provenance.json", provenance)
    observations = {}
    for name, path in (("enumeration.json", args.enumeration), ("xcode-list.txt", args.xcode_list),
                       ("destinations.txt", args.destinations), ("fixture-manifest.json", args.fixture_manifest)):
        with path.open("rb") as reader, (preparation / name).open("xb") as writer:
            shutil.copyfileobj(reader, writer)
        observations[name] = record(preparation / name)
    config = {"action": "rendition-fixture-only", "preparation": str(preparation), "runtime": str(runtime),
        "run_identity": str(uuid4()), "interpreter": provenance["interpreter"]["entry"],
        "listener_deadline_seconds": 1200, "fixture": {**fixture, "path": str(movie)},
        "fixture_record": movie_record, "fixture_id": "s25-fixture-" + str(uuid4()), "tests": expected,
        "destination": "platform=iOS Simulator,id=" + args.destination_udid, "derived_data": str(args.derived_data)}
    write_json(preparation / "config.json", config)
    write_json(preparation / "checkpoint.json", {"config": record(preparation / "config.json"),
        "source_files": sources, "dependency_provenance": record(preparation / "dependency-provenance.json"),
        "archive_provenance": record(provenance_path), "archive_checkpoint": record(checkpoint_path),
        "archive_manifest": record(ARCHIVE / "archive-manifest.json"),
        "app_sources": app_sources(), "observations": observations, "backend_imported": False,
        "runtime_created": False, "executed": False})
    if tree(frozen) != sources or {n: record(support / n) for n in FILES} != sources or record(movie) != movie_record:
        raise RuntimeError("Inputs changed during preparation")
    command = [config["interpreter"], "-I", "-B", "-S", str(frozen / "run_rendition_fixture.py"),
        "--config", str(preparation / "config.json"), "--checkpoint-sha256",
        record(preparation / "checkpoint.json")["sha256"]]
    write_json(preparation / "commands.json", {"dry_run": command, "execute": command + ["--execute-reviewed-integration"]})
    for path in preparation.rglob("*"):
        if path.is_file():
            path.chmod(0o444)
    print(json.dumps({"preparation": str(preparation), "runtime_created": False, "tests": 5, "executions": 10}))


if __name__ == "__main__":
    main()
