"""Prepare two-phase S24 HTTP commands only; no backend import or subprocess."""
import argparse
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
from uuid import uuid4


ROOT = Path("/private/tmp/fr-di-20261001-5ljls2fr/S24")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend-preparation", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    support = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("listener_lifecycle", support / "listener_lifecycle.py")
    life = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(life)
    base = args.backend_preparation
    if (base.parent != ROOT or re.fullmatch(r"preparation-[0-9]{3}", base.name) is None or
            re.fullmatch(r"[0-9]{3}", args.revision) is None):
        raise RuntimeError("Expected reviewed S24 preparation and fresh revision")
    checkpoint = life.read_json(base / "checkpoint-files.json")
    base_config = life.read_json(base / "run-config.json")
    snapshot = Path(base_config["snapshot"])
    if (snapshot.parent != ROOT or life.tree(snapshot) != checkpoint["snapshot"] or
            life.record(base / "run-config.json") != checkpoint["config"] or
            life.record(Path(base_config["provenance"])) != checkpoint["provenance"] or
            life.tree(base / "source-snapshot") != checkpoint["frozen_sources"]):
        raise RuntimeError("S24 backend preparation changed")
    source_before = life.tree(support)
    frozen_isolation = {name.removeprefix("server-isolation/"): value
        for name, value in checkpoint["frozen_sources"].items() if name.startswith("server-isolation/")}
    if source_before != frozen_isolation:
        raise RuntimeError("HTTP support differs from the jointly frozen backend preparation")
    for name in source_before:
        if name.endswith(".py"):
            compile(ast.parse((support / name).read_text(), filename=name), name, "exec")
    preparation = ROOT / ("http-preparation-" + args.revision)
    runtime = ROOT / ("runtime-storage-" + args.revision)
    if any(path.exists() or path.is_symlink() for path in (preparation, runtime)):
        raise RuntimeError("Refuse to reuse HTTP preparation or runtime")
    preparation.mkdir()
    frozen = preparation / "source-snapshot"
    frozen.mkdir()
    for name in source_before:
        target = frozen / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with (support / name).open("rb") as reader, target.open("xb") as writer:
            shutil.copyfileobj(reader, writer)
    if life.tree(support) != source_before or life.tree(frozen) != source_before:
        raise RuntimeError("Support changed during freeze")
    manifest_path = preparation / "source-manifest.json"
    life.write_json(manifest_path, {"files": source_before, "backend_checkpoint": life.record(base / "checkpoint-files.json")})
    phase_paths = {phase: preparation / ("phase-" + str(phase) + "-config.json") for phase in (1, 2)}
    common = {**base_config, "action": "storage-listener", "runtime": str(runtime),
        "allow_reviewed_loopback_listener": True, "listener_deadline_seconds": 240,
        "run_identity": str(uuid4()), "storage_source_manifest": str(manifest_path),
        "storage_source_manifest_sha256": life.record(manifest_path)["sha256"],
        "storage_phase1_config": str(phase_paths[1]), "storage_phase2_config": str(phase_paths[2])}
    commands = {}
    for phase, path in phase_paths.items():
        life.write_json(path, {**common, "storage_phase": phase})
        commands["listener" + str(phase)] = [common["interpreter"], "-I", "-B", "-S",
            str(frozen / "run_pytest.py"), "--config", str(path)]
        commands["client" + str(phase)] = [common["interpreter"], "-I", "-B", "-S",
            str(frozen / "storage_http_probe.py"), "--config", str(path)]
    life.write_json(preparation / "commands.json", commands)
    life.write_json(preparation / "checkpoint.json", {"source_manifest": life.record(manifest_path),
        "phase1_config": life.record(phase_paths[1]), "phase2_config": life.record(phase_paths[2]),
        "commands": life.record(preparation / "commands.json"), "backend_preparation": str(base),
        "backend_checkpoint": life.record(base / "checkpoint-files.json"),
        "backend_imported": False, "runtime_created": False, "executed": False})
    command = [common["interpreter"], "-I", "-B", "-S", str(frozen / "run_storage_integration.py"),
        "--preparation", str(preparation), "--checkpoint-sha256",
        life.record(preparation / "checkpoint.json")["sha256"]]
    life.write_json(preparation / "integration-command.json", {"dry_run": command,
        "execute": command + ["--execute-reviewed-integration"], "executed": False})
    for path in preparation.rglob("*"):
        if path.is_file():
            path.chmod(0o444)
    print(json.dumps({"preparation": str(preparation), "runtime_created": False,
        "source_files": len(source_before), "checkpoint_sha256": life.record(preparation / "checkpoint.json")["sha256"]}))


if __name__ == "__main__":
    main()
