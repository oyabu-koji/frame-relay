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
import stat
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
PLAYBACK_TEST = "PublicationHTTPFixtureTests/" + METHODS[0]
PLAYBACK_ATTACHMENTS = "playback-attachments"
METADATA_TIMEOUT_SECONDS = 10
METADATA_COMMAND_COUNT = 4
WIRE_OBSERVATIONS = (
    "all_handlers_terminal", "canonical_source_and_read_distributions", "v1_ranges_match_fixed_identity",
    "consumed_ticket_rejected_while_v1_current", "confirmation_receipt_lost_then_exact_lookup",
    "replacement_waited_for_ack", "invalidation_fetched_then_acknowledged", "v2_published_after_ack",
    "unconsumed_v1_ticket_rejected_after_publication", "all_rejected_gets_emit_no_media", "final_manifest_is_v2",
)
REQUIRED_OBSERVATIONS = ("avplayer_progress_before_full_download", *WIRE_OBSERVATIONS)
PROBE_MODES = ("publication", "metadata-only")
METADATA_TEST = "StatusSynchronizationHTTPFixtureTests/metadataOnlyPageAndManifestUseCoordinator()"
METADATA_KEYS = (*KEYS, "FR_S28_METADATA_ONLY")
METADATA_WIRE_OBSERVATIONS = (
    "exactly_two_metadata_requests", "all_metadata_handlers_terminal", "one_complete_empty_invalidation_page",
    "manifest_matches_current_v1", "zero_media_and_distribution_requests", "zero_confirmation_ack_lookup_requests",
    "zero_fixture_control_requests",
)
METADATA_REQUIRED_OBSERVATIONS = ("coordinator_metadata_commit_reopen", *METADATA_WIRE_OBSERVATIONS)
METADATA_SCHEMA = "fr-s28-metadata-observation-v1"
METADATA_SDK_CONTRACT = "PublicationURLSessionRequest awaits task completion and session invalidation"
METADATA_COUNTERS = {"boundedPages": 1, "invalidationsStarted": 1, "invalidationsCompleted": 1,
    "manifestStarted": 1, "manifestCompleted": 1, "confirmationSend": 0, "ackSend": 0,
    "operationLookup": 0, "distribute": 0, "lookupDistribution": 0, "durablePublicationCount": 1, "newConfirmations": 0}


def probe_contract(mode):
    if mode == "publication":
        return {"mode": mode, "test": PLAYBACK_TEST, "environment_keys": list(KEYS),
            "attachment_directory": PLAYBACK_ATTACHMENTS, "attachment_stem": "s27-wire-observation", "attachment_extension": "txt",
            "report_schema": "s27-wire-observation-v1", "required_observations": list(REQUIRED_OBSERVATIONS)}
    if mode == "metadata-only":
        return {"mode": mode, "test": METADATA_TEST, "environment_keys": list(METADATA_KEYS),
            "attachment_directory": "metadata-attachments", "attachment_stem": "s28-metadata-observation", "attachment_extension": "json",
            "report_schema": METADATA_SCHEMA, "required_observations": list(METADATA_REQUIRED_OBSERVATIONS)}
    raise RuntimeError("Unreviewed probe mode")


def probe_mode(config):
    # Historical publication configs keep their original default and contract.
    # Every newly prepared config includes its full fixed contract in its hash.
    mode = config.get("probe_mode", "publication")
    contract = probe_contract(mode)
    if (("probe_mode" in config and config.get("probe_contract") != contract) or
            ("probe_mode" not in config and "probe_contract" in config)):
        raise RuntimeError("Probe mode/contract configuration mismatch")
    return mode


def namespace_prefixes(mode):
    if mode == "publication":
        return "http-preparation-", "http-snapshot-", "runtime-publication-"
    if mode == "metadata-only":
        return "metadata-http-preparation-", "metadata-http-snapshot-", "runtime-metadata-only-"
    raise RuntimeError("Unreviewed probe namespace")


def verify_swift_playback_contract(sources):
    """Bind raw Passed + attachment to the reviewed real-player assertion."""
    relative = "FrameRelayTests/Integration/Remote/PublicationHTTPFixtureTests.swift"
    path = PROJECT / relative
    if record(path) != sources.get(relative):
        raise RuntimeError("Reviewed publication Swift source changed")
    source = path.read_text()
    for expression in (
        "@MainActor struct PublicationHTTPFixtureTests",
        "@Test func " + METHODS[0] + " async throws",
        "let advanced = await renditionEventually(seconds: 30) { player.elapsedSeconds > 0.1 && player.decodedFrames > 0 }",
        "let bytesAtProgress = client.receivedBytes",
        "#expect(advanced && bytesAtProgress > 0 && bytesAtProgress < config.v1.deliveryContent.byteCount)",
        r'Attachment.record("fixtureOnly=true bytesAtProgress=\(bytesAtProgress) total=\(config.v1.deliveryContent.byteCount) decoded=\(player.decodedFrames) httpStarted=\(client.started) httpCompleted=\(client.completed) cacheAfter=\(state.cachePayloadBytes) acknowledgements=\(acknowledgements.count)", named: "s27-wire-observation.txt")',
    ):
        if source.count(expression) != 1:
            raise RuntimeError("Publication Swift progress assertion/attachment contract changed")


def verify_swift_metadata_contract(sources):
    relative = "FrameRelayTests/Integration/Composition/ProductStatusSynchronizationTests.swift"
    path = PROJECT / relative
    if record(path) != sources.get(relative):
        raise RuntimeError("Reviewed metadata-only Swift source changed")
    source = path.read_text()
    start = "@MainActor struct StatusSynchronizationHTTPFixtureTests {"
    end = "\n@MainActor private final class StatusObservedHTTPRemote:"
    gate = ('@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FR_S27_HTTP_FIXTURE"] == "1"\n'
        '    && ProcessInfo.processInfo.environment["FR_S28_METADATA_ONLY"] == "1"))')
    if any(source.count(expression) != 1 for expression in (start, end, gate)):
        raise RuntimeError("Metadata-only Swift suite/gate contract changed")
    test_source = source.split(start, 1)[1].split(end, 1)[0]
    for expression in ("@Test func metadataOnlyPageAndManifestUseCoordinator() async throws",
            "let result = await coordinator.synchronize()", "let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)",
            "let replay = try await mediaSnapshot(reopened)", "let matches = saved == replay",
            '"report_schema": "' + METADATA_SCHEMA + '", "probe_mode": "metadata-only", "fixtureOnly": true',
            '"runIdentity": config.runIdentity, "boundedPages": remote.invalidationsStarted',
            '"durablePublicationCount": saved.publications.count, "newConfirmations": saved.confirmations.count - before.confirmations.count',
            '"reopenMatches": matches, "coordinatorAwaitCompleted": true, "sdkTerminalCountsObserved": false',
            '"sdkTerminalContract": "' + METADATA_SDK_CONTRACT + '"',
            'Attachment.record(String(decoding: data, as: UTF8.self), named: "s28-metadata-observation.json")',
            "#expect(result.phase == .checked && !result.hasMore && result.unresolvedInvalidations == 0)",
            "#expect(remote.invalidationsStarted == 1 && remote.invalidationsCompleted == 1)",
            "#expect(remote.manifestStarted == 1 && remote.manifestCompleted == 1)",
            "#expect(remote.confirmationSend == 0 && remote.ackSend == 0 && remote.operationLookup == 0)",
            "#expect(remote.distributeCount == 0 && remote.lookupDistributionCount == 0)",
            "#expect(before.publications.isEmpty && saved.publications.count == 1)",
            "#expect(saved.publications.first?.observation.rendition == config.rendition)",
            "#expect(matches && replay.storeIdentity == identity)"):
        if test_source.count(expression) != 1:
            raise RuntimeError("Metadata-only Swift assertion/attachment contract changed")
    relative = "FrameRelay/Platform/Remote/URLSessionPublicationRemote.swift"
    remote = PROJECT / relative
    if record(remote) != sources.get(relative):
        raise RuntimeError("Reviewed real publication SDK source changed")
    sdk_source = remote.read_text()
    for expression in ("let response = try await PublicationURLSessionRequest.perform(http)",
            "didCompleteWithError error: Error?", "completed = true", "session.finishTasksAndInvalidate()",
            "didBecomeInvalidWithError error: Error?", "else if error != nil || !completed",
            "continuation.resume(returning: .init(status: response.statusCode, data: data))"):
        if sdk_source.count(expression) != 1:
            raise RuntimeError("Publication SDK terminal-await source contract changed")


def evaluate_publication_tests(summary, tests, config, *, required_test=PLAYBACK_TEST):
    """Re-evaluated from raw xcresult summary/tree by wrapper AND parent."""
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
    counts = {key: summary.get(key) for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")}
    expected_counts = {"totalTestCount": len(expected), "passedTests": len(expected),
        "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
    devices = summary.get("devicesAndConfigurations", [])
    executions = sum(max(1, len([child for child in node.get("children", []) if child.get("nodeType") == "Arguments"])) for node in cases)
    passed = (expected == {required_test} and summary.get("result") == "Passed" and counts == expected_counts and
        all(type(value) is int for value in counts.values()) and len(devices) == 1 and
        devices[0].get("device", {}).get("deviceId") == config["destination"].split("id=")[1] and
        all(type(devices[0].get(key)) is int and devices[0][key] == value
            for key, value in expected_counts.items() if key != "totalTestCount") and
        len(cases) == len(expected) and set(identifiers) == expected and executions == len(expected) and
        all(node.get("result") == "Passed" for node in cases) and
        not any(child.get("nodeType") == "Arguments" for node in cases for child in node.get("children", [])))
    return {"passed": passed, "summary_counts": counts, "declarations": identifiers,
        "execution_count": executions, "test_urls": [node.get("nodeIdentifierURL") for node in cases],
        "nonpassing_declarations": [{"identifier": node.get("nodeIdentifier"), "result": node.get("result")}
            for node in cases if node.get("result") != "Passed"]}


def evaluate_probe_tests(summary, tests, config):
    return evaluate_publication_tests(summary, tests, config,
        required_test=probe_contract(probe_mode(config))["test"])


def playback_evidence(runtime, config, summary, tests, fixture):
    """Read the SDK-exported manifest and exact raw text; accept no invented values."""
    verification = evaluate_publication_tests(summary, tests, config)
    directory = runtime / PLAYBACK_ATTACHMENTS
    if (directory.is_symlink() or not directory.is_dir() or
            stat.S_IMODE(directory.lstat().st_mode) != 0o700):
        raise RuntimeError("Missing private SDK attachment export")
    manifest_path = directory / "manifest.json"
    if manifest_path.lstat().st_size > 65536:
        raise RuntimeError("Unexpected attachment manifest size")
    manifest = read_json(manifest_path)
    if (not isinstance(manifest, list) or len(manifest) != 1 or manifest[0].get("testIdentifier") != PLAYBACK_TEST or
            not isinstance(manifest[0].get("testIdentifierURL"), str) or
            not manifest[0]["testIdentifierURL"].startswith("test://") or
            not manifest[0]["testIdentifierURL"].endswith("/FrameRelayTests/" + PLAYBACK_TEST) or
            manifest[0].get("testIdentifierURL") not in verification["test_urls"] or
            not isinstance(manifest[0].get("attachments"), list) or len(manifest[0]["attachments"]) != 1):
        raise RuntimeError("SDK attachment test identity differs from raw test tree")
    attachment = manifest[0]["attachments"][0]
    name, suggested = attachment.get("exportedFileName"), attachment.get("suggestedHumanReadableName")
    timestamp = attachment.get("timestamp")
    if (not isinstance(name, str) or re.fullmatch(r"[0-9A-Fa-f-]{36}\.txt", name) is None or
            not isinstance(suggested, str) or
            re.fullmatch(r"s27-wire-observation(?:_[0-9]+_[0-9A-Fa-f-]{36})?\.txt", suggested) is None or
            attachment.get("deviceId") != config["destination"].split("id=")[1] or
            attachment.get("isAssociatedWithFailure") is not False or
            type(timestamp) not in (int, float) or not math.isfinite(timestamp) or timestamp <= 0 or
            {path.name for path in directory.iterdir()} != {"manifest.json", name}):
        raise RuntimeError("Unexpected SDK progress attachment identity")
    path = directory / name
    for exported in (manifest_path, path):
        info = exported.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
            raise RuntimeError("SDK attachment must be a private regular file")
    if path.stat().st_size > 4096:
        raise RuntimeError("Unexpected progress attachment size")
    raw = path.read_bytes()
    match = re.fullmatch(r"fixtureOnly=true bytesAtProgress=([0-9]+) total=([0-9]+) decoded=([0-9]+) "
        r"httpStarted=([0-9]+) httpCompleted=([0-9]+) cacheAfter=([0-9]+) acknowledgements=([0-9]+)\n?", raw.decode("ascii"))
    if match is None:
        raise RuntimeError("SDK progress attachment is not the reviewed numeric observation")
    values = dict(zip(("bytes_at_progress", "total", "decoded", "http_started", "http_completed", "cache_after", "acknowledgements"),
        map(int, match.groups())))
    total = int(fixture["v1"]["delivery_content"]["byte_count"])
    passed = (verification["passed"] is True and total == config["fixture"]["byteCount"] == values["total"] and
        fixture["v1"]["delivery_content"]["digest"] == config["fixture"]["sha256"] and
        0 < values["bytes_at_progress"] < total and values["decoded"] > 0 and
        values["http_started"] > 0 and values["http_started"] == values["http_completed"] and
        values["cache_after"] == 0 and values["acknowledgements"] == 1)
    return {"passed": passed, "test_verification": verification, "values": values,
        "manifest_record": record(manifest_path), "attachment_file": name, "attachment_record": record(path),
        "meaning": "raw xcresult Passed plus exact real-player Swift assertion and SDK-exported text; not listener inference"}


def metadata_evidence(runtime, config, summary, tests, fixture):
    if probe_mode(config) != "metadata-only":
        raise RuntimeError("Metadata report used for another probe mode")
    contract = probe_contract("metadata-only")
    verification = evaluate_probe_tests(summary, tests, config)
    directory = runtime / contract["attachment_directory"]
    if (directory.is_symlink() or not directory.is_dir() or
            stat.S_IMODE(directory.lstat().st_mode) != 0o700):
        raise RuntimeError("Missing private SDK metadata-only export")
    manifest_path = directory / "manifest.json"
    if manifest_path.lstat().st_size > 65536:
        raise RuntimeError("Unexpected metadata-only attachment manifest size")
    manifest = read_json(manifest_path)
    if (not isinstance(manifest, list) or len(manifest) != 1 or manifest[0].get("testIdentifier") != METADATA_TEST or
            not isinstance(manifest[0].get("testIdentifierURL"), str) or
            not manifest[0]["testIdentifierURL"].startswith("test://") or
            not manifest[0]["testIdentifierURL"].endswith("/FrameRelayTests/" + METADATA_TEST) or
            manifest[0].get("testIdentifierURL") not in verification["test_urls"] or
            not isinstance(manifest[0].get("attachments"), list) or len(manifest[0]["attachments"]) != 1):
        raise RuntimeError("SDK metadata-only attachment test identity mismatch")
    attachment = manifest[0]["attachments"][0]
    name, suggested, timestamp = (attachment.get(key) for key in ("exportedFileName", "suggestedHumanReadableName", "timestamp"))
    if (not isinstance(name, str) or re.fullmatch(r"[0-9A-Fa-f-]{36}\.json", name) is None or
            not isinstance(suggested, str) or
            re.fullmatch(r"s28-metadata-observation(?:_[0-9]+_[0-9A-Fa-f-]{36})?\.json", suggested) is None or
            attachment.get("deviceId") != config["destination"].split("id=")[1] or
            attachment.get("isAssociatedWithFailure") is not False or
            type(timestamp) not in (int, float) or not math.isfinite(timestamp) or timestamp <= 0 or
            {path.name for path in directory.iterdir()} != {"manifest.json", name}):
        raise RuntimeError("Unexpected SDK metadata-only attachment")
    path = directory / name
    for exported in (manifest_path, path):
        info = exported.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
            raise RuntimeError("Metadata-only SDK report must be a private regular file")
    if path.stat().st_size > 4096:
        raise RuntimeError("Unexpected metadata-only SDK report size")
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise RuntimeError("Duplicate SDK metadata report field")
            result[key] = value
        return result
    def invalid_constant(_value):
        raise RuntimeError("Non-finite SDK metadata report value")
    values = json.loads(path.read_bytes(), object_pairs_hook=unique_object, parse_constant=invalid_constant)
    expected_keys = {"report_schema", "probe_mode", "fixtureOnly", "runIdentity", *METADATA_COUNTERS,
        "reopenMatches", "coordinatorAwaitCompleted", "sdkTerminalCountsObserved", "sdkTerminalContract"}
    if (not isinstance(values, dict) or set(values) != expected_keys or
            values["report_schema"] != METADATA_SCHEMA or values["probe_mode"] != "metadata-only" or
            values["fixtureOnly"] is not True or values["runIdentity"] != config["run_identity"] or
            fixture.get("run_identity") != config["run_identity"] or fixture.get("fixture_only") is not True or
            fixture.get("wire_sha256") != WIRE_SHA256 or fixture.get("source_sha256") != config["fixture"]["sha256"] or
            any(type(values[key]) is not int for key in METADATA_COUNTERS) or
            type(values["reopenMatches"]) is not bool or type(values["coordinatorAwaitCompleted"]) is not bool or
            values["sdkTerminalCountsObserved"] is not False or values["sdkTerminalContract"] != METADATA_SDK_CONTRACT):
        raise RuntimeError("SDK metadata-only schema/mode/run identity/type mismatch")
    passed = (verification["passed"] is True and all(values[key] == expected for key, expected in METADATA_COUNTERS.items()) and
        values["reopenMatches"] is True and values["coordinatorAwaitCompleted"] is True)
    return {"passed": passed, "test_verification": verification, "values": values,
        "manifest_record": record(manifest_path), "attachment_file": name, "attachment_record": record(path),
        "sdk_terminal_source_contract": {"remote_source_record": record(PROJECT / "FrameRelay/Platform/Remote/URLSessionPublicationRemote.swift"),
            "contract": METADATA_SDK_CONTRACT, "actual_task_session_counts_observed": False},
        "meaning": "raw SDK Passed and exact coordinator-await/SQLite-reopen report; actual SDK terminal counts unobserved"}


def probe_evidence(runtime, config, summary, tests, fixture):
    if probe_mode(config) == "publication":
        return playback_evidence(runtime, config, summary, tests, fixture)
    return metadata_evidence(runtime, config, summary, tests, fixture)


def evidence_field(config):
    return "playback_evidence" if probe_mode(config) == "publication" else "metadata_evidence"


def metadata_only_observations(report):
    result = dict.fromkeys(METADATA_WIRE_OBSERVATIONS, False)
    try:
        rows, controls, fixture = report["requests"], report["controls"], report["fixture"]
        result["exactly_two_metadata_requests"] = (report["probe_mode"] == "metadata-only" and len(rows) == 2 and
            [row["endpoint"] for row in rows] == ["invalidations", "manifest"] and
            [row["sequence"] for row in rows] == [1, 2] and all(row["method"] == "POST" for row in rows))
        def terminal(row):
            clocks = [row[key] for key in ("started_monotonic", "headers_sent_monotonic", "terminal_monotonic")]
            return (all(type(value) in (int, float) and math.isfinite(value) and value >= 0 for value in clocks) and
                clocks[0] <= clocks[1] <= clocks[2] and row["handler_returned"] is True and "failure_type" not in row and
                row["status"] == row["underlying_status"] == 200 and row["response_replaced"] is False and
                row["content_type"] == "application/json" and type(row["body_bytes_emitted"]) is int and row["body_bytes_emitted"] > 0 and
                type(row["media_bytes_emitted"]) is int and row["media_bytes_emitted"] == 0)
        result["all_metadata_handlers_terminal"] = len(rows) == 2 and all(terminal(row) for row in rows)
        registration = {key: fixture["registration_receipt"][key] for key in ("destination_id", "registration_id", "generation")}
        invalidations = [row for row in rows if row["endpoint"] == "invalidations"]
        expected_invalidation = {"schema_version": "fr-publication-v1", "registration": registration,
            "after_invalidation_id": None, "limit": "8"}
        request_digest = digest_json(expected_invalidation)
        result["one_complete_empty_invalidation_page"] = (len(invalidations) == 1 and invalidations[0].get("invalidation_count") == 0 and
            invalidations[0].get("next_after_is_null") is True and invalidations[0].get("request_sha256") == request_digest and
            invalidations[0].get("result_sha256") == digest_json({"invalidations": [], "next_after": None}))
        manifests = [row for row in rows if row["endpoint"] == "manifest"]
        expected_manifest = {"schema_version": "fr-publication-v1", "registration": registration, "original": fixture["original"]}
        final = report["final_manifest"]
        result["manifest_matches_current_v1"] = (len(manifests) == 1 and manifests[0].get("request_sha256") == digest_json(expected_manifest) and
            manifests[0].get("current_rendition_id") == fixture["v1"]["rendition_id"] and
            manifests[0].get("result_sha256") == digest_json(final) and final.get("current") == fixture["v1"] and
            final.get("replacement_pending") is False and report.get("replacement") is None and report.get("publication") is None)
        result["zero_media_and_distribution_requests"] = (bool(rows) and not report.get("blocked_route_count") and
            all(row["endpoint"] not in ("media", "distributions") and row["media_bytes_emitted"] == 0 for row in rows))
        result["zero_confirmation_ack_lookup_requests"] = bool(rows) and all(
            row["endpoint"] not in ("confirmations", "acknowledgements", "operations/lookup") for row in rows)
        result["zero_fixture_control_requests"] = not controls and not report.get("blocked_route_count")
    except (KeyError, TypeError, ValueError, OverflowError):
        pass
    return result


def digest_json(value):
    import hashlib
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
        ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def wire_observations(report, config):
    return publication_observations(report) if probe_mode(config) == "publication" else metadata_only_observations(report)


def owner_close_observation(events, tracked_connections, inventory, initial_inventory, runtime):
    """Evaluate only owner state captured BEFORE guard.finish rescue cleanup."""
    pending, unclosed_gc, malformed = set(), [], False
    for event in events:
        if type(event.get("id")) is not int:
            malformed = True
        elif event.get("event") == "opened":
            if event["id"] in pending:
                malformed = True
            pending.add(event["id"])
        elif event.get("event") == "closed":
            pending.discard(event["id"])
        elif event.get("event") == "garbage_collected":
            if event["id"] in pending:
                unclosed_gc.append(event["id"])
        else:
            malformed = True
    database_media, unknown_regular = [], []
    initial_identities = {(fd.get("dev"), fd.get("ino")) for fd in initial_inventory if "mode" in fd}
    for fd in inventory:
        path = fd.get("path")
        if path and (path.startswith(str(runtime / "db.sqlite3")) or Path(path).is_relative_to(runtime / "media")):
            database_media.append(fd)
        elif (not path and stat.S_ISREG(fd.get("mode", 0)) and
                (fd.get("dev"), fd.get("ino")) not in initial_identities):
            # A new regular descriptor with unresolved F_GETPATH cannot be
            # silently classified as a non-media FD, including unlinked files.
            unknown_regular.append(fd)
    sqlite_closed = not malformed and not pending and not unclosed_gc and not tracked_connections
    return {"passed": sqlite_closed and not database_media and not unknown_regular,
        "sqlite_owner_explicit_close_complete": sqlite_closed, "pending_connection_ids": sorted(pending),
        "unclosed_garbage_collected_ids": unclosed_gc, "malformed_connection_events": malformed,
        "tracked_connection_count": len(tracked_connections), "database_media_fds_remaining": database_media,
        "unresolved_new_regular_fds": unknown_regular}


def publication_observations(report):
    """Derive the same bounded evidence checks in listener and independent parent."""
    result = dict.fromkeys(WIRE_OBSERVATIONS, False)
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
    mode = probe_mode(config)
    contract = probe_contract(mode)
    preparation, runtime = Path(config["preparation"]), Path(config["runtime"])
    preparation_prefix, snapshot_prefix, runtime_prefix = namespace_prefixes(mode)
    revision = preparation.name.removeprefix(preparation_prefix)
    if (path != preparation / "config.json" or preparation.parent != ROOT or
            preparation != ROOT / (preparation_prefix + revision) or not re.fullmatch(r"[0-9]{3}", revision) or
            runtime != ROOT / (runtime_prefix + revision) or Path(config["snapshot"]) != ROOT / (snapshot_prefix + revision) or
            config.get("action") != ("publication-fixture-only" if mode == "publication" else "publication-metadata-only-fixture") or
            config.get("listener_deadline_seconds") != 1200 or not METHODS or
            config.get("tests") != ["FrameRelayTests/" + contract["test"]]):
        raise RuntimeError("Unreviewed publication fixture configuration")
    checkpoint = read_json(preparation / "checkpoint.json")
    if (record(path) != checkpoint["config"] or tree(preparation / "source-snapshot") != checkpoint["source_files"] or
            tree(Path(config["snapshot"])) != checkpoint["backend_snapshot"] or
            record(preparation / "dependency-provenance.json") != checkpoint["dependency_provenance"] or
            record(preparation / "wire-contract.json")["sha256"] != WIRE_SHA256):
        raise RuntimeError("Frozen publication inputs changed")
    if "probe_mode" in config and checkpoint.get("probe_mode") != mode:
        raise RuntimeError("Checkpoint probe mode mismatch")
    return config, checkpoint


def verify_inputs(config, checkpoint):
    preparation = Path(config["preparation"])
    provenance = read_json(preparation / "dependency-provenance.json")
    verify_dependencies(provenance)
    if ({name: record(Path(provenance["external_root"]) / name) for name in provenance["source_before"]}
            != provenance["source_before"] or record(Path(config["fixture"]["path"])) != config["fixture_record"] or
            app_sources() != checkpoint["app_sources"]):
        raise RuntimeError("Reviewed external source, movie or App source changed")
    if probe_mode(config) == "publication":
        verify_swift_playback_contract(checkpoint["app_sources"])
    else:
        verify_swift_metadata_contract(checkpoint["app_sources"])
    return provenance


def checked_ready(runtime, config, *, pid=None, launched=None):
    ready = read_json(runtime / "listener-ready.json")
    url = urlsplit(ready.get("url", ""))
    start, deadline = ready.get("started_monotonic"), ready.get("deadline_monotonic")
    if (ready.get("run_identity") != config["run_identity"] or type(ready.get("pid")) is not int or ready["pid"] <= 1 or
            ready.get("probe_mode", "publication") != probe_mode(config) or
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
    parser.add_argument("--probe-mode", choices=PROBE_MODES, default="publication")
    parser.add_argument("--backend-config", type=Path, required=True)
    parser.add_argument("--backend-checkpoint-sha256", required=True)
    parser.add_argument("--fixture-movie", type=Path, required=True)
    parser.add_argument("--enumeration", type=Path, required=True)
    parser.add_argument("--xcode-list", type=Path, required=True)
    parser.add_argument("--destinations", type=Path, required=True)
    parser.add_argument("--destination-udid", required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    args = parser.parse_args()
    mode, contract = args.probe_mode, probe_contract(args.probe_mode)
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
    expected = ["FrameRelayTests/" + contract["test"]]
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
    preparation_prefix, snapshot_prefix, runtime_prefix = namespace_prefixes(mode)
    preparation = ROOT / (preparation_prefix + args.revision)
    snapshot = ROOT / (snapshot_prefix + args.revision)
    runtime = ROOT / (runtime_prefix + args.revision)
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
    config = {"action": "publication-fixture-only" if mode == "publication" else "publication-metadata-only-fixture",
        "probe_mode": mode, "probe_contract": contract, "preparation": str(preparation), "snapshot": str(snapshot),
        "runtime": str(runtime), "run_identity": str(uuid4()), "interpreter": provenance["interpreter"]["entry"],
        "listener_deadline_seconds": 1200, "fixture": {"path": str(movie), "byteCount": 969998,
            "sha256": MOVIE_SHA256, "mime": "video/quicktime", "fixtureOnly": True},
        "fixture_record": movie_record, "tests": expected,
        "destination": "platform=iOS Simulator,id=" + args.destination_udid, "derived_data": str(args.derived_data)}
    write_json(preparation / "config.json", config)
    checkpoint = {"probe_mode": mode, "config": record(preparation / "config.json"), "source_files": sources,
        "backend_snapshot": source_checkpoint["snapshot"], "dependency_provenance": record(preparation / "dependency-provenance.json"),
        "app_sources": app_sources(), "observations": observations, "runtime_created": False, "executed": False}
    write_json(preparation / "checkpoint.json", checkpoint)
    verified_config(preparation / "config.json")
    verify_inputs(config, checkpoint)
    if tree(source_snapshot) != checkpoint["backend_snapshot"] or {n: record(support / n) for n in FILES} != sources:
        raise RuntimeError("Source changed while preparing")
    command = [config["interpreter"], "-I", "-B", "-S", str(preparation / "source-snapshot/run_publication_fixture.py"),
        "--config", str(preparation / "config.json"), "--checkpoint-sha256", record(preparation / "checkpoint.json")["sha256"],
        "--probe-mode", mode]
    write_json(preparation / "commands.json", {"dry_run": command, "execute": command + ["--execute-reviewed-integration"]})
    for root in (preparation, snapshot):
        for path in root.rglob("*"):
            if path.is_file():
                path.chmod(0o444)
    print(json.dumps({"preparation": str(preparation), "runtime_created": False, "executed": False}))


if __name__ == "__main__":
    main()
