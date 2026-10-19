"""S27 preparation: immutable backend snapshot plus an explicitly test-owned authority."""
import argparse
import ast
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import time
from urllib.parse import urlsplit
from uuid import uuid4


def module(name):
    path = Path(__file__).with_name(name + ".py")
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


common = module("prepare_rendition_fixture")
record, tree, read_json, write_json = common.record, common.tree, common.read_json, common.write_json
verify_dependencies, app_sources = common.verify_dependencies, common.app_sources
PROJECT = common.PROJECT
ROOT = Path("/private/tmp/fr-di-20261015-s27/S27")
FILES = ("prepare_publication_probe.py", "publication_fixture_listener.py", "run_publication_fixture.py",
         "run_publication_simulator_probe.py", "README-publication.md", "prepare_rendition_fixture.py",
         "isolation_guard.py", "listener_lifecycle.py", "run_pytest.py")
METHODS = ("canonicalPlaybackConfirmationInvalidationAndReplacement()",)
KEYS = ("FR_S27_HTTP_FIXTURE", "FR_S27_ORIGIN", "FR_S27_BEARER", "FR_S27_REGISTRATION_SECRET",
        "FR_S27_FIXTURE_SECRET", "FR_S27_FIXTURE_JSON")
MOVIE_SHA256 = "8a77b6c2cfdedbe850148210eada8851956f10942203aec4eae8f9e552a8b984"
WIRE_SHA256 = "455868ebe8d057ad32471a169396333c03cd1bcf2b4a4986f3147935f2617e0a"
REQUIRED_OBSERVATIONS = (
    "all_handlers_terminal", "canonical_source_and_read_distributions", "v1_ranges_match_fixed_identity",
    "consumed_ticket_rejected_while_v1_current", "confirmation_receipt_lost_then_exact_lookup",
    "replacement_waited_for_ack", "invalidation_fetched_then_acknowledged", "v2_published_after_ack",
    "unconsumed_v1_ticket_rejected_after_publication", "all_rejected_gets_emit_no_media", "final_manifest_is_v2",
)


def publication_observations(report):
    """Derive the same bounded evidence checks in listener and independent parent."""
    result = dict.fromkeys(REQUIRED_OBSERVATIONS, False)
    try:
        rows, controls = report["requests"], report["controls"]
        v1 = report["fixture"]["v1"]
        total = int(v1["delivery_content"]["byte_count"])
        def terminal(row):
            values = (row["started_monotonic"], row["headers_sent_monotonic"], row["terminal_monotonic"])
            return (all(type(value) in (int, float) and math.isfinite(value) and value >= 0 for value in values) and
                values[0] <= values[1] <= values[2] and row["handler_returned"] is True and "failure_type" not in row and
                type(row["status"]) is int and type(row["body_bytes_emitted"]) is int and
                type(row["media_bytes_emitted"]) is int and 0 <= row["media_bytes_emitted"] <= row["body_bytes_emitted"])
        result["all_handlers_terminal"] = bool(rows) and all(terminal(row) for row in rows)
        sources = [row for row in rows if row["endpoint"] == "distributions" and row["status"] == 200 and row.get("purpose") == "source"]
        reads = [row for row in rows if row["endpoint"] == "distributions" and row["status"] == 200 and row.get("purpose") == "read"]
        result["canonical_source_and_read_distributions"] = bool(sources) and bool(reads)
        media = [row for row in rows if row["endpoint"] == "media"]
        accepted = [row for row in media if row["status"] in (200, 206)]
        successful_tickets = {row.get("ticket_sha256") for row in accepted}
        def exact_range(row):
            match = re.fullmatch(r"bytes (0|[1-9][0-9]*)-(0|[1-9][0-9]*)/([1-9][0-9]*)", row.get("content_range") or "")
            if match is None or row["status"] != 206 or row.get("rendition_id") != v1["rendition_id"]:
                return False
            lower, upper, size = map(int, match.groups())
            return (0 <= lower <= upper < size == total and 0 < upper - lower + 1 <= 65536 and
                row.get("content_length") == str(upper - lower + 1) and row.get("content_type") == "video/quicktime" and
                row.get("wire_version") == "fr-publication-v1" and row.get("content_sha256") == v1["delivery_content"]["digest"] and
                row.get("content_bytes") == str(total) and 0 <= row["media_bytes_emitted"] <= upper - lower + 1 and
                row.get("ticket_sha256") is not None and any(
                    read.get("operation_id_sha256") == row["ticket_sha256"] and read["sequence"] < row["sequence"] for read in reads))
        result["v1_ranges_match_fixed_identity"] = bool(accepted) and all(exact_range(row) for row in accepted)
        rejected = [row for row in media if row["status"] not in (200, 206)]
        def rejected_without_media(row):
            return (row["status"] == 409 and row.get("content_type") == "application/json" and
                row["media_bytes_emitted"] == 0 and row["body_bytes_emitted"] > 0 and terminal(row))
        result["all_rejected_gets_emit_no_media"] = bool(rejected) and all(rejected_without_media(row) for row in rejected)
        reused = [row for row in rejected if row["phase"] == "v1-current" and
            row.get("error_code") == "publication_get_consumed" and any(
                old.get("ticket_sha256") == row.get("ticket_sha256") and old["sequence"] < row["sequence"] for old in accepted)]
        result["consumed_ticket_rejected_while_v1_current"] = len(reused) == 1 and rejected_without_media(reused[0])
        stale = [row for row in rejected if row["phase"] == "v2-current" and row.get("rendition_id") == v1["rendition_id"] and
            row.get("error_code") == "publication_stale_rendition" and
            row.get("ticket_sha256") not in successful_tickets and any(
                read.get("operation_id_sha256") == row.get("ticket_sha256") and read["phase"] == "v1-current" for read in reads)]
        result["unconsumed_v1_ticket_rejected_after_publication"] = len(stale) == 1 and rejected_without_media(stale[0])
        lost = [row for row in rows if row["endpoint"] == "confirmations" and row["response_replaced"] is True and
            row["status"] == 503 and row["underlying_status"] == 200]
        lookups = [row for row in rows if row["endpoint"] == "operations/lookup" and row["status"] == 200 and row.get("kind") == "confirmation"]
        result["confirmation_receipt_lost_then_exact_lookup"] = (len(lost) == 1 and report["response_loss_count"] == 1 and any(
            row["sequence"] > lost[0]["sequence"] and row.get("lookup_original_request_sha256") == lost[0].get("request_sha256") and
            row.get("lookup_original_result_sha256") == lost[0].get("result_sha256") for row in lookups))
        invalidations = [row for row in rows if row["endpoint"] == "invalidations" and row["status"] == 200 and
            type(row.get("invalidation_count")) is int and 0 < row["invalidation_count"] <= 8]
        acks = [row for row in rows if row["endpoint"] == "acknowledgements" and row["status"] == 200]
        result["invalidation_fetched_then_acknowledged"] = len(acks) == 1 and any(
            row["sequence"] < acks[0]["sequence"] for row in invalidations)
        begun = [row for row in controls if row["action"] == "begin-replacement" and row["status"] == 200]
        waiting = [row for row in controls if row["action"] == "publish-replacement" and row["status"] == 409 and
            row.get("error_code") == "publication_awaiting_acknowledgements"]
        published = [row for row in controls if row["action"] == "publish-replacement" and row["status"] == 200]
        result["replacement_waited_for_ack"] = (len(begun) == len(waiting) == len(acks) == 1 and
            begun[0]["terminal_monotonic"] <= waiting[0]["started_monotonic"] <= waiting[0]["terminal_monotonic"] < acks[0]["started_monotonic"])
        result["v2_published_after_ack"] = (len(published) == len(acks) == 1 and
            acks[0]["terminal_monotonic"] < published[0]["started_monotonic"])
        final, publication = report.get("final_manifest", {}), report.get("publication") or {}
        v2 = publication.get("rendition") or {}
        result["final_manifest_is_v2"] = (bool(v2) and v2.get("rendition_id") != v1["rendition_id"] and
            v2.get("original") == v1["original"] and final.get("current") == v2 and
            final.get("revision") == publication.get("committed_revision") and final.get("replacement_pending") is False and
            any(row["endpoint"] == "manifest" and row["status"] == 200 and row["phase"] == "v2-current" and
                row.get("current_rendition_id") == v2["rendition_id"] for row in rows))
    except (KeyError, TypeError, ValueError, OverflowError):
        pass
    return result


def copy(source, target):
    record(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as reader, target.open("xb") as writer:
        shutil.copyfileobj(reader, writer)


def verified_config(path):
    config = read_json(path)
    preparation, runtime = Path(config["preparation"]), Path(config["runtime"])
    revision = preparation.name.removeprefix("http-preparation-")
    if (path != preparation / "config.json" or preparation.parent != ROOT or
            preparation != ROOT / ("http-preparation-" + revision) or not re.fullmatch(r"[0-9]{3}", revision) or
            runtime != ROOT / ("runtime-publication-" + revision) or
            Path(config["snapshot"]) != ROOT / ("http-snapshot-" + revision) or
            config.get("action") != "publication-fixture-only" or config.get("listener_deadline_seconds") != 1200 or
            not METHODS or config.get("tests") != ["FrameRelayTests/PublicationHTTPFixtureTests/" + name for name in METHODS]):
        raise RuntimeError("Unreviewed publication fixture configuration")
    checkpoint = read_json(preparation / "checkpoint.json")
    if (record(path) != checkpoint["config"] or tree(preparation / "source-snapshot") != checkpoint["source_files"] or
            tree(Path(config["snapshot"])) != checkpoint["backend_snapshot"] or
            record(preparation / "dependency-provenance.json") != checkpoint["dependency_provenance"] or
            record(preparation / "wire-contract.json")["sha256"] != WIRE_SHA256):
        raise RuntimeError("Frozen publication inputs changed")
    return config, checkpoint


def verify_inputs(config, checkpoint):
    preparation = Path(config["preparation"])
    provenance = read_json(preparation / "dependency-provenance.json")
    verify_dependencies(provenance)
    if ({name: record(Path(provenance["external_root"]) / name) for name in provenance["source_before"]}
            != provenance["source_before"] or record(Path(config["fixture"]["path"])) != config["fixture_record"] or
            app_sources() != checkpoint["app_sources"]):
        raise RuntimeError("Reviewed external source, movie or App source changed")
    return provenance


def checked_ready(runtime, config, *, pid=None, launched=None):
    ready = read_json(runtime / "listener-ready.json")
    url = urlsplit(ready.get("url", ""))
    start, deadline = ready.get("started_monotonic"), ready.get("deadline_monotonic")
    if (ready.get("run_identity") != config["run_identity"] or type(ready.get("pid")) is not int or ready["pid"] <= 1 or
            (pid is not None and ready["pid"] != pid) or
            any(type(v) not in (int, float) or not math.isfinite(v) for v in (start, deadline)) or
            deadline - start != 1200 or (launched is not None and not launched <= start <= time.monotonic()) or
            time.monotonic() >= deadline or url.scheme != "http" or url.hostname != "127.0.0.1" or
            url.path or url.query or url.fragment or url.username or url.password or url.port is None or
            not 1 <= url.port <= 65535 or ready["url"] != "http://127.0.0.1:" + str(url.port)):
        raise RuntimeError("Publication listener identity/origin mismatch")
    os.kill(ready["pid"], 0)
    return ready


def stop(runtime, config, pid):
    common.stop(runtime, config, pid)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--revision", required=True)
    parser.add_argument("--backend-config", type=Path, required=True)
    parser.add_argument("--backend-checkpoint-sha256", required=True)
    parser.add_argument("--fixture-movie", type=Path, required=True)
    parser.add_argument("--enumeration", type=Path, required=True)
    parser.add_argument("--xcode-list", type=Path, required=True)
    parser.add_argument("--destinations", type=Path, required=True)
    parser.add_argument("--destination-udid", required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]{3}", args.revision) or not METHODS:
        raise RuntimeError("Require fresh revision and frozen exact test declarations")
    source_config = read_json(args.backend_config)
    source_preparation = args.backend_config.parent
    source_checkpoint_path = source_preparation / "checkpoint-files.json"
    source_checkpoint = read_json(source_checkpoint_path)
    source_snapshot = Path(source_config["snapshot"])
    source_provenance_path = Path(source_config["provenance"])
    provenance = read_json(source_provenance_path)
    if (not source_preparation.is_relative_to(ROOT) or source_preparation.is_symlink() or
            args.backend_config != source_preparation / "run-config.json" or source_config.get("action") != "pytest" or
            source_checkpoint["config"] != record(args.backend_config) or
            record(source_checkpoint_path)["sha256"] != args.backend_checkpoint_sha256 or
            source_provenance_path != source_preparation / "provenance-before.json" or
            source_checkpoint["provenance"] != record(source_provenance_path) or
            source_snapshot.parent != ROOT or source_snapshot.is_symlink() or
            tree(source_snapshot) != source_checkpoint["snapshot"] or provenance["snapshot"] != source_checkpoint["snapshot"]):
        raise RuntimeError("Require the reviewed S27 backend preparation/checkpoint")
    verify_dependencies(provenance)
    external_before = {name: record(Path(provenance["external_root"]) / name) for name in provenance["source_before"]}
    if external_before != provenance["source_before"]:
        raise RuntimeError("External backend source changed")
    movie = args.fixture_movie.resolve(strict=True)
    movie_record = record(movie)
    with movie.open("rb") as stream:
        prefix = stream.read(16)
    if movie_record["size"] != 969998 or movie_record["sha256"] != MOVIE_SHA256 or prefix[4:12] != b"ftypqt  ":
        raise RuntimeError("Require the unchanged S25 synthetic QuickTime fixture")
    expected = ["FrameRelayTests/PublicationHTTPFixtureTests/" + name for name in METHODS]
    enumeration = read_json(args.enumeration)
    plans = enumeration.get("values", [])
    if (enumeration.get("errors") != [] or len(plans) != 1 or plans[0].get("testPlan") != "FrameRelay" or
            sorted(item["identifier"] for item in plans[0].get("enabledTests", [])) != sorted(expected)):
        raise RuntimeError("SDK enumeration differs from reviewed publication cases")
    if (not re.fullmatch(r"[0-9A-F-]{36}", args.destination_udid) or
            args.destination_udid not in args.destinations.read_text() or "FrameRelay" not in args.xcode_list.read_text() or
            not args.derived_data.is_absolute() or not args.derived_data.is_relative_to(ROOT.parent)):
        raise RuntimeError("Unverified Xcode configuration or DerivedData boundary")
    support = Path(__file__).resolve().parent
    wire = source_preparation / "source-snapshot/server-implementation/s27-wire-contract.json"
    if record(wire)["sha256"] != WIRE_SHA256:
        raise RuntimeError("Canonical publication wire changed")
    sources = {name: record(support / name) for name in FILES}
    for name in FILES:
        if name.endswith(".py"):
            compile(ast.parse((support / name).read_bytes(), filename=name), name, "exec")
    preparation = ROOT / ("http-preparation-" + args.revision)
    snapshot = ROOT / ("http-snapshot-" + args.revision)
    runtime = ROOT / ("runtime-publication-" + args.revision)
    if any(p.exists() or p.is_symlink() for p in (preparation, snapshot, runtime)):
        raise RuntimeError("Refuse reused publication namespace")
    preparation.mkdir(parents=True)
    snapshot.mkdir()
    for name in source_checkpoint["snapshot"]:
        copy(source_snapshot / name, snapshot / name)
    for name in FILES:
        copy(support / name, preparation / "source-snapshot" / name)
    observations = {}
    for name, path in (("enumeration.json", args.enumeration), ("xcode-list.txt", args.xcode_list),
            ("destinations.txt", args.destinations), ("wire-contract.json", wire),
            ("backend-config.json", args.backend_config), ("backend-checkpoint.json", source_checkpoint_path)):
        copy(path, preparation / name)
        observations[name] = record(preparation / name)
    write_json(preparation / "dependency-provenance.json", provenance)
    config = {"action": "publication-fixture-only", "preparation": str(preparation), "snapshot": str(snapshot),
        "runtime": str(runtime), "run_identity": str(uuid4()), "interpreter": provenance["interpreter"]["entry"],
        "listener_deadline_seconds": 1200, "fixture": {"path": str(movie), "byteCount": 969998,
            "sha256": MOVIE_SHA256, "mime": "video/quicktime", "fixtureOnly": True},
        "fixture_record": movie_record, "tests": expected,
        "destination": "platform=iOS Simulator,id=" + args.destination_udid, "derived_data": str(args.derived_data)}
    write_json(preparation / "config.json", config)
    checkpoint = {"config": record(preparation / "config.json"), "source_files": sources,
        "backend_snapshot": source_checkpoint["snapshot"], "dependency_provenance": record(preparation / "dependency-provenance.json"),
        "app_sources": app_sources(), "observations": observations, "runtime_created": False, "executed": False}
    write_json(preparation / "checkpoint.json", checkpoint)
    verified_config(preparation / "config.json")
    verify_inputs(config, checkpoint)
    if tree(source_snapshot) != checkpoint["backend_snapshot"] or {n: record(support / n) for n in FILES} != sources:
        raise RuntimeError("Source changed while preparing")
    command = [config["interpreter"], "-I", "-B", "-S", str(preparation / "source-snapshot/run_publication_fixture.py"),
        "--config", str(preparation / "config.json"), "--checkpoint-sha256", record(preparation / "checkpoint.json")["sha256"]]
    write_json(preparation / "commands.json", {"dry_run": command, "execute": command + ["--execute-reviewed-integration"]})
    for root in (preparation, snapshot):
        for path in root.rglob("*"):
            if path.is_file():
                path.chmod(0o444)
    print(json.dumps({"preparation": str(preparation), "runtime_created": False, "executed": False}))


if __name__ == "__main__":
    main()
