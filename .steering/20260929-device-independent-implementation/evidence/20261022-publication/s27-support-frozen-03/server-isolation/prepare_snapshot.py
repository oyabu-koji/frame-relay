"""Read-only external inputs -> a new S20 snapshot. Does not import the backend."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def file_record(path):
    if path.is_symlink():
        return {"kind": "symlink", "target": os.readlink(path), "resolved": str(path.resolve())}
    return {"kind": "file", "size": path.stat().st_size, "sha256": digest(path)}


def tree_manifest(root):
    return {str(path.relative_to(root)): file_record(path)
            for path in sorted(root.rglob("*")) if path.is_file() or path.is_symlink()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    destination = output / "snapshot-001"
    evidence = output / "preparation-001"
    if destination.exists() or evidence.exists():
        raise SystemExit("Refusing to reuse snapshot/evidence; choose a new namespace")
    destination.mkdir()
    evidence.mkdir()
    git = lambda *parts: subprocess.check_output(["git", "--no-optional-locks", "-C", str(source), *parts])
    head = git("rev-parse", "HEAD").decode().strip()
    if head != "c56d4a25a46acfa99dd66c4586621b5261af4d39":
        raise SystemExit("External HEAD changed; review before snapshot")
    tracked = [Path(os.fsdecode(item)) for item in git("ls-files", "-z", "--", "backend").split(b"\0") if item]
    if len(tracked) != 246:
        raise SystemExit("Tracked backend set changed; review before snapshot")
    before = {}
    for relative in tracked:
        if relative.is_absolute() or ".." in relative.parts:
            raise SystemExit("Invalid tracked path")
        original = source / relative
        if original.is_symlink() or not original.is_file():
            raise SystemExit("Only regular tracked files can be snapshotted")
        before[str(relative)] = file_record(original)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        with original.open("rb") as reader, target.open("xb") as writer:
            shutil.copyfileobj(reader, writer)
    after = {str(relative): file_record(source / relative) for relative in tracked}
    copied = {str(relative): file_record(destination / relative) for relative in tracked}
    if before != after or before != copied:
        raise SystemExit("Source changed during snapshot or copy mismatch")
    site = source / "backend/.venv/lib/python3.12/site-packages"
    interpreter = source / "backend/.venv/bin/python"
    provenance = {
        "external_head": head, "external_root": str(source),
        "external_status_porcelain": git("status", "--porcelain").decode(),
        "source_before": before, "source_after_snapshot": after, "snapshot": copied,
        "guidance": {name: file_record(source / name) for name in ("AGENTS.md", "PROJECT_CONTEXT.md")},
        "site_packages_root": str(site), "site_packages_before": tree_manifest(site),
        "interpreter": {"entry": str(interpreter), "record": file_record(interpreter),
                        "resolved_record": file_record(interpreter.resolve(strict=True))},
        "pyvenv_cfg": (source / "backend/.venv/pyvenv.cfg").read_text(),
        "pth": {str(p.relative_to(site)): p.read_text() for p in sorted(site.glob("*.pth"))},
        "excluded": ["external untracked JPEG", "external .venv (read-only dependency input)",
                     "external runtime/media/DB", "old T04 missing snapshot/evidence"],
        "backend_imported": False, "tests_executed": False,
    }
    manifest = evidence / "provenance-before.json"
    manifest.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")
    config = {"snapshot": str(destination), "runtime": str(output / "runtime-pytest-001"),
              "external_root": str(source), "site_packages": str(site),
              "provenance": str(manifest), "interpreter": str(interpreter),
              "allow_missing_ffprobe_version_probe": True}
    (evidence / "run-config.json").write_text(json.dumps(config, indent=2) + "\n")
    print(json.dumps({"snapshot": str(destination), "tracked_files": len(tracked),
                      "source_bytes": sum(v["size"] for v in before.values()),
                      "site_packages_files": len(provenance["site_packages_before"]),
                      "config": str(evidence / "run-config.json"), "provenance_sha256": digest(manifest)}))


if __name__ == "__main__":
    main()
