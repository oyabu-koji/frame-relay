"""Prepare an additive S22 snapshot; no backend/pytest import or listener launch.

Run with Python -I -B -S. External checkout, dependencies and S20 stay read-only.
"""
import argparse
import ast
import difflib
import hashlib
import json
from pathlib import Path
import shutil


def record(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError("Snapshot inputs must be regular files")
    data = path.read_bytes()
    return {"kind": "file", "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def tree(root):
    return {str(p.relative_to(root)): record(p) for p in sorted(root.rglob("*"))
            if p.is_file() or p.is_symlink()}


def dump(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def copy_regular(source, target):
    record(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as reader, target.open("xb") as writer:
        shutil.copyfileobj(reader, writer)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--provenance", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", default="001")
    args = parser.parse_args()
    if len(args.revision) != 3 or not args.revision.isascii() or not args.revision.isdigit():
        raise SystemExit("Revision must be a three-digit fresh namespace")
    support = Path(__file__).resolve().parent
    overlay = support / "backend-overlay"
    isolation = support.parent / "server-isolation"
    base = args.base.resolve(strict=True)
    original = json.loads(args.provenance.read_text())
    external = Path(original["external_root"])
    before = tree(base)
    if before != original["snapshot"]:
        raise SystemExit("S20 base differs from its recorded immutable snapshot")
    source_before = {name: record(external / name) for name in original["source_before"]}
    if source_before != original["source_before"]:
        raise SystemExit("External source differs from S20 provenance")
    overlay_before = tree(overlay)
    if not overlay_before:
        raise SystemExit("Empty overlay")
    for name in overlay_before:
        if name.endswith(".py"):
            ast.parse((overlay / name).read_text(), filename=name)
    output = args.output.resolve()
    if output != Path("/private/tmp/fr-di-20261001-5ljls2fr/S22"):
        raise SystemExit("Output must be the authorized disposable S22 namespace")
    snapshot = output / ("snapshot-" + args.revision)
    evidence = output / ("preparation-" + args.revision)
    runtime = output / ("runtime-pytest-" + args.revision)
    if any(p.exists() or p.is_symlink() for p in (snapshot, evidence, runtime)):
        raise SystemExit("Refusing to reuse a snapshot/evidence/runtime namespace")
    snapshot.mkdir(parents=True)
    evidence.mkdir()
    # All files are copied, never hardlinked, and every overlay path is explicit.
    for name in before:
        if not name.startswith("backend/"):
            raise SystemExit("Unexpected base path")
        source = overlay / name.removeprefix("backend/")
        copy_regular(source if source.is_file() else base / name, snapshot / name)
    for name in overlay_before:
        target = snapshot / "backend" / name
        if not target.exists():
            copy_regular(overlay / name, target)
    frozen = evidence / "source-snapshot"
    for directory in (isolation, support):
        for name in tree(directory):
            copy_regular(directory / name, frozen / directory.name / name)
    differences = []
    for name in overlay_before:
        old = base / "backend" / name
        differences.extend(difflib.unified_diff(
            old.read_text().splitlines(keepends=True) if old.exists() else [],
            (overlay / name).read_text().splitlines(keepends=True),
            fromfile="a/backend/" + name if old.exists() else "/dev/null",
            tofile="b/backend/" + name))
    diff = "".join(differences)
    if (support / "backend-overlay.diff").read_text() != diff:
        raise SystemExit("Saved review diff is stale")
    (evidence / "backend-overlay.diff").write_text(diff)
    source_after = {name: record(external / name) for name in original["source_before"]}
    if source_after != source_before or tree(base) != before or tree(overlay) != overlay_before:
        raise SystemExit("An input changed during preparation")
    snapshot_manifest = tree(snapshot)
    provenance = dict(original)
    provenance.update({"snapshot": snapshot_manifest, "source_after_snapshot": source_after,
        "base_snapshot": before, "base_provenance": str(args.provenance.resolve()),
        "base_provenance_sha256": record(args.provenance)["sha256"],
        "overlay": overlay_before, "backend_imported": False, "tests_executed": False})
    provenance_path = evidence / "provenance-before.json"
    dump(provenance_path, provenance)
    cases = frozen / "server-implementation/cases.json"
    nodes = json.loads(cases.read_text())
    # New test nodes are individually named, have no fixture parameter expansion,
    # and the inherited S20 13 nodes expand to 20 cases.
    new_tests = ast.parse((overlay / "tests/test_frame_relay_registrations.py").read_text())
    functions = [node for node in new_tests.body if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")]
    if any(node.decorator_list for node in functions):
        raise SystemExit("Explicit expected count needs review for decorated tests")
    old_nodes = json.loads((isolation / "cases.json").read_text())
    expected = old_nodes + ["tests/test_frame_relay_registrations.py::" + node.name for node in functions]
    if nodes != expected:
        raise SystemExit("Explicit case list differs from the reviewed old/new functions")
    config = {"snapshot": str(snapshot), "runtime": str(runtime),
        "external_root": str(external), "site_packages": original["site_packages_root"],
        "provenance": str(provenance_path), "interpreter": original["interpreter"]["entry"],
        "allow_missing_ffprobe_version_probe": True, "action": "pytest",
        "case_file": str(cases), "case_file_sha256": record(cases)["sha256"],
        "expected_nodes": len(nodes), "expected_cases": 20 + len(functions)}
    dump(evidence / "run-config.json", config)
    for p in snapshot.rglob("*"):
        if p.is_file():
            p.chmod(0o444)
    for p in frozen.rglob("*"):
        if p.is_file():
            p.chmod(0o444)
    manifest = {"base_unchanged": True, "external_tracked_source_unchanged": True,
        "snapshot": snapshot_manifest, "frozen_sources": tree(frozen),
        "overlay": overlay_before, "review_diff": record(evidence / "backend-overlay.diff"),
        "provenance": record(provenance_path), "config": record(evidence / "run-config.json"),
        "python_ast_files": [name for name in overlay_before if name.endswith(".py")],
        "expected_nodes": len(nodes), "expected_cases": config["expected_cases"],
        "backend_imported": False, "tests_executed": False, "runtime_created": False}
    dump(evidence / "checkpoint-files.json", manifest)
    print(json.dumps({"evidence": str(evidence), "snapshot_files": len(snapshot_manifest),
        "overlay_files": len(overlay_before), "expected_nodes": len(nodes),
        "expected_cases": config["expected_cases"],
        "checkpoint_sha256": record(evidence / "checkpoint-files.json")["sha256"]}))


if __name__ == "__main__":
    main()
