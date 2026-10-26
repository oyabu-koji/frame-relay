"""Freeze S28 original-inventory input; stdlib/AST only, no backend import or execution."""
import argparse
import ast
import difflib
import importlib.util
import json
from pathlib import Path


PRESERVED_TEST_SHA256 = {
    # Current S27-era tests, frozen in DI-SOURCE-20261023-01. The older S26J
    # base archive predates existing storage/conversion acceptance additions.
    "test_frame_relay_registrations.py": "fa0ce426c3b3b3ca684c846a62b466556b9e27af9a299d0c92a31a264f8a224a",
    "test_frame_relay_storage.py": "a7cd9760a85bae25e1e87932eacbe6686d15955123b3a276a882a2166a3adb8c",
    "test_frame_relay_conversion.py": "3789d575c7b2333221be07e3b14c5238b37907f1ab18be3926ba2be07be37939",
    "test_frame_relay_publication.py": "1abe9811ab970e39f63a7dd30cc81364797ad107eff34cd768316c0cee78a2e9",
}


def reviewed_helpers(support):
    path = support / "prepare_publication_snapshot.py"
    spec = importlib.util.spec_from_file_location("inventory_reviewed_preparation", path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def case_inventory(support, base, inherited_helper):
    inherited = json.loads((support / "cases-publication.json").read_text())
    inherited_cases, _publication_nodes, inherited_counts = inherited_helper.verify_cases(inherited, support, base)
    if len(inherited) != 170 or inherited_cases != 230:
        raise RuntimeError("Expected the reviewed 170/230 S27 case inventory")
    name = "tests/test_frame_relay_inventory.py"
    module = ast.parse((support / "backend-overlay" / name).read_text())
    declarations = [node for node in module.body if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")]
    required = [name + "::" + node.name for node in declarations]
    nodes = json.loads((support / "cases-inventory.json").read_text())
    if nodes != inherited + required or len(nodes) != len(set(nodes)):
        raise RuntimeError("Inventory cases must preserve all inherited nodes and add every new declaration in AST order")
    counts = dict(inherited_counts)
    for node in declarations:
        count = 1
        for decorator in node.decorator_list:
            if not (isinstance(decorator, ast.Call) and isinstance(decorator.func, ast.Attribute)
                    and decorator.func.attr == "parametrize" and isinstance(decorator.func.value, ast.Attribute)
                    and decorator.func.value.attr == "mark" and isinstance(decorator.func.value.value, ast.Name)
                    and decorator.func.value.value.id == "pytest" and len(decorator.args) >= 2
                    and isinstance(decorator.args[1], (ast.List, ast.Tuple)) and decorator.args[1].elts):
                raise RuntimeError("Only literal, nonempty parametrization is reviewed; no skip/xfail")
            if any(isinstance(value, ast.keyword) and value.arg == "marks" for value in ast.walk(decorator.args[1])):
                raise RuntimeError("Parameterized marks require separate review")
            count *= len(decorator.args[1].elts)
        counts[name + "::" + node.name] = count
    selected = sum(counts[node] for node in required)
    if len(required) != 16 or selected != 49 or len(nodes) != 186 or sum(counts.values()) != 279:
        raise RuntimeError("Expected inherited 170/230 plus inventory 16/49, total 186/279")
    return nodes, counts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    if len(args.revision) != 3 or not args.revision.isascii() or not args.revision.isdigit():
        raise SystemExit("Expected a fresh three-digit revision")
    if not args.output_root.is_absolute():
        raise SystemExit("The reviewed output parent must be an absolute existing directory")
    output_parent = args.output_root.resolve(strict=True)
    if not output_parent.is_dir():
        raise SystemExit("Output parent is not a directory")
    support = Path(__file__).resolve().parent
    isolation = support.parent / "server-isolation"
    helper = reviewed_helpers(support)
    record, tree, copy, dump = helper.record, helper.tree, helper.copy, helper.dump
    archive, archive_before, base, original_path, original, before = helper.archived_base(support)
    external = Path(original["external_root"])
    source_before = {name: record(external / name) for name in original["source_before"]}
    if source_before != original["source_before"]:
        raise RuntimeError("External checkout differs from the preserved read-only provenance")
    helper.external_runtime(original)
    overlay = support / "backend-overlay"
    overlay_before = tree(overlay)
    # These are existing acceptance cases and migration identities, never new
    # inventory inputs to modify or rebrand as current successful execution.
    for name, expected in PRESERVED_TEST_SHA256.items():
        if record(overlay / "tests" / name)["sha256"] != expected:
            raise RuntimeError("Preserved current test changed: " + name)
    for relative in ("app/db/frame_relay_schema/001_registrations.sql",
                     "app/db/frame_relay_schema/002_storage.sql", "app/db/frame_relay_schema/003_conversion_candidates.sql"):
        if record(overlay / relative) != record(base / "backend" / relative):
            raise RuntimeError("Preserved tests or SQL migration changed: " + relative)
    nodes, counts = case_inventory(support, base, helper)
    sources = {directory.name: tree(directory) for directory in (support, isolation)}
    parsed = []
    for directory in (support, isolation):
        for name in sources[directory.name]:
            if name.endswith(".py"):
                text = (directory / name).read_text()
                ast.parse(text, filename=name)
                compile(text, name, "exec", dont_inherit=True)
                parsed.append(directory.name + "/" + name)
    output = output_parent / "S28-inventory"
    snapshot = output / ("snapshot-" + args.revision)
    preparation = output / ("preparation-" + args.revision)
    runtime = output / ("runtime-pytest-" + args.revision)
    if output.is_symlink() or any(path.exists() or path.is_symlink() for path in (snapshot, preparation, runtime)):
        raise RuntimeError("Refusing to reuse snapshot, preparation, or runtime")
    snapshot.mkdir(parents=True)
    preparation.mkdir()
    for name in before:
        if not name.startswith("backend/"):
            raise RuntimeError("Unexpected base source path")
        replacement = overlay / name.removeprefix("backend/")
        copy(replacement if replacement.is_file() else base / name, snapshot / name)
    for name in overlay_before:
        if not (snapshot / "backend" / name).exists():
            copy(overlay / name, snapshot / "backend" / name)
    frozen = preparation / "source-snapshot"
    for directory in (support, isolation):
        for name in sources[directory.name]:
            copy(directory / name, frozen / directory.name / name)
    if (tree(archive) != archive_before or any(tree(directory) != sources[directory.name] for directory in (support, isolation))
            or {name: record(external / name) for name in source_before} != source_before):
        raise RuntimeError("Inputs changed during preparation; do not execute this incomplete revision")
    helper.external_runtime(original)
    snapshot_manifest = tree(snapshot)
    provenance = {**original, "snapshot": snapshot_manifest, "source_after_snapshot": source_before,
        "base_snapshot": before, "base_provenance": str(original_path), "base_provenance_sha256": record(original_path)["sha256"],
        "base_input_kind": "repository_archive", "base_archive": str(archive),
        "base_archive_manifest": archive_before["archive-manifest.json"], "s26j_tmp_input_reverified": False,
        "overlay": overlay_before, "backend_imported": False, "tests_executed": False}
    provenance_path = preparation / "provenance-before.json"
    dump(provenance_path, provenance)
    cases = frozen / "server-implementation/cases-inventory.json"
    config = {"snapshot": str(snapshot), "runtime": str(runtime), "external_root": str(external),
        "site_packages": original["site_packages_root"], "interpreter": original["interpreter"]["entry"],
        "provenance": str(provenance_path), "allow_missing_ffprobe_version_probe": True, "action": "pytest",
        "case_file": str(cases), "case_file_sha256": record(cases)["sha256"],
        "expected_nodes": len(nodes), "expected_cases": sum(counts.values())}
    config_path = preparation / "run-config.json"
    dump(config_path, config)
    command = [config["interpreter"], "-I", "-B", "-S", str(frozen / "server-isolation/run_pytest.py"), "--config", str(config_path)]
    dump(preparation / "command.json", {"command": command, "executed": False})
    differences = []
    for name in overlay_before:
        old = base / "backend" / name
        differences.extend(difflib.unified_diff(old.read_text().splitlines(keepends=True) if old.exists() else [],
            (overlay / name).read_text().splitlines(keepends=True), fromfile="a/backend/" + name if old.exists() else "/dev/null",
            tofile="b/backend/" + name))
    with (preparation / "overlay.diff").open("x") as stream:
        stream.write("".join(differences))
    checkpoint = {"snapshot": snapshot_manifest, "frozen_sources": tree(frozen), "config": record(config_path),
        "provenance": record(provenance_path), "command": record(preparation / "command.json"),
        "overlay_diff": record(preparation / "overlay.diff"), "base_unchanged": True, "base_archive_unchanged": True,
        "base_identity": "Archived S26J snapshot-001: evidence/" + helper.BASE_ARCHIVE,
        "base_archive_manifest": archive_before["archive-manifest.json"], "base_archive_entry_count": 345,
        "s26j_tmp_input_reverified": False, "s20_original_copy_complete": False,
        "external_source_and_runtime_unchanged": True, "preserved_tests_and_001_002_003_sql_unchanged": True,
        "expected_nodes": len(nodes), "expected_cases": sum(counts.values()), "inherited_nodes": 170, "inherited_cases": 230,
        "selected_inventory_nodes": 16, "selected_inventory_cases": 49, "case_expansion": counts,
        "python_ast_files": parsed, "python_compile_files": parsed,
        "backend_imported": False, "tests_executed": False, "runtime_created": False}
    dump(preparation / "checkpoint-files.json", checkpoint)
    for root in (snapshot, preparation):
        for path in root.rglob("*"):
            if path.is_file():
                path.chmod(0o444)
    print(json.dumps({"preparation": str(preparation), "snapshot_files": len(snapshot_manifest),
        "expected_nodes": len(nodes), "expected_cases": sum(counts.values()), "selected_inventory_nodes": 16,
        "selected_inventory_cases": 49, "runtime_created": False,
        "checkpoint_sha256": record(preparation / "checkpoint-files.json")["sha256"]}))


if __name__ == "__main__":
    main()
