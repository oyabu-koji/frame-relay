"""Prepare fresh S26J input only; stdlib/AST, no backend import or child processes."""
import argparse
import ast
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil


ROOT = Path("/private/tmp/fr-di-20261001-5ljls2fr")
BASE_ARCHIVE = "20261013-s24-complete"
BASE_ARCHIVE_MANIFEST_SHA256 = "9b7b00c81b68dfb8e480deefd8d8b1ec24f9db421ac4bfd4b29fbbf896d6e247"


def record(path, *, dependency=False):
    if path.is_symlink():
        if dependency:
            return {"kind":"symlink","target":os.readlink(path),"resolved":str(path.resolve(strict=True))}
        raise RuntimeError("Source/snapshot must not contain symlinks")
    if not path.is_file():
        raise RuntimeError("Expected regular source")
    content = path.read_bytes()
    return {"kind":"file","size":len(content),"sha256":hashlib.sha256(content).hexdigest()}


def tree(root, *, dependency=False):
    return {str(path.relative_to(root)):record(path,dependency=dependency) for path in sorted(root.rglob("*"))
            if path.is_file() or path.is_symlink()}


def copy(source, target):
    record(source)
    target.parent.mkdir(parents=True,exist_ok=True)
    with source.open("rb") as reader,target.open("xb") as writer:shutil.copyfileobj(reader,writer)


def dump(path,value):
    with path.open("x") as stream:json.dump(value,stream,indent=2,sort_keys=True);stream.write("\n")


def external_runtime(original):
    site=Path(original["site_packages_root"])
    interpreter=Path(original["interpreter"]["entry"])
    if (tree(site,dependency=True) != original["site_packages_before"] or
            record(interpreter,dependency=True) != original["interpreter"]["record"] or
            record(interpreter.resolve(strict=True)) != original["interpreter"]["resolved_record"] or
            (interpreter.parent.parent/"pyvenv.cfg").read_text() != original["pyvenv_cfg"] or
            {str(p.relative_to(site)):p.read_text() for p in sorted(site.glob("*.pth"))} != original["pth"]):
        raise RuntimeError("External runtime differs from reviewed provenance")


def archived_base(support):
    """Use the reviewed repository archive, never recreate missing tmp inputs."""
    archive=support.parent.parent/"evidence"/BASE_ARCHIVE
    if archive.is_symlink():raise RuntimeError("Base archive must not be a symlink")
    manifest_path=archive/"archive-manifest.json"
    manifest_record=record(manifest_path)
    if manifest_record["sha256"]!=BASE_ARCHIVE_MANIFEST_SHA256:
        raise RuntimeError("Reviewed S24 archive manifest changed")
    manifest=json.loads(manifest_path.read_text())
    entries=manifest["entries"]
    expected={entry["path"]:{"kind":"file","size":entry["bytes"],"sha256":entry["sha256"]}
              for entry in entries}
    if len(entries)!=386 or len(expected)!=386:
        raise RuntimeError("Expected all 386 unique S24 archive entries")
    expected["archive-manifest.json"]=manifest_record
    archive_before=tree(archive)
    if archive_before!=expected:
        raise RuntimeError("S24 archive file set or content differs from its manifest")
    base=archive/"snapshot-001"
    original_path=archive/"preparation-001/provenance-before.json"
    original=json.loads(original_path.read_text())
    checkpoint=json.loads((archive/"preparation-001/checkpoint-files.json").read_text())
    after=json.loads((archive/"runtime-pytest-001/provenance-after.json").read_text())
    before=tree(base)
    if record(original_path)!=checkpoint["provenance"]:
        raise RuntimeError("Archived S24 provenance differs from its checkpoint")
    if (len(before)!=261 or before!=original["snapshot"] or
            before!=checkpoint["snapshot"] or before!=after["snapshot"] or
            after["all_unchanged"] is not True):
        raise RuntimeError("Archived S24 snapshot differs from its preserved provenance")
    return archive,archive_before,base,original_path,original,before


def verify_cases(nodes,support,base):
    inherited=json.loads((support/"cases-storage.json").read_text())
    inherited=[entry.replace("test_worker_routes_fr_finalize_but_never_claims_conversion",
        "test_worker_routes_fr_finalize_then_marks_unimplemented_conversion_failed") for entry in inherited]
    if len(inherited) != 118 or nodes[:118] != inherited or len(nodes) != len(set(nodes)):
        raise RuntimeError("S24 case list must be retained with the explicit worker-stage rename")
    counts={}
    for entry in nodes:
        name,function=entry.split("::")
        path=support/"backend-overlay"/name
        if not path.is_file():path=base/"backend"/name
        module=ast.parse(path.read_text())
        candidates=[n for n in module.body if isinstance(n,ast.FunctionDef) and n.name==function]
        if len(candidates)!=1:raise RuntimeError("Unknown explicit case")
        count=1
        for decorator in candidates[0].decorator_list:
            if not (isinstance(decorator,ast.Call) and isinstance(decorator.func,ast.Attribute)
                    and decorator.func.attr=="parametrize" and len(decorator.args)>=2):
                raise RuntimeError("Unexpected skip/decorator: explicit count needs review")
            values=decorator.args[1]
            if isinstance(values,ast.Call):
                # The immutable S22 authentication matrix is a literal return
                # list containing three pytest.param entries. Inspect its AST;
                # never evaluate a backend helper to discover tests.
                if not (entry==inherited[0] and isinstance(values.func,ast.Name) and
                        values.func.id=="_auth_cases" and not values.args and not values.keywords):
                    raise RuntimeError("Dynamic parametrization requires review")
                helpers=[n for n in module.body if isinstance(n,ast.FunctionDef) and n.name=="_auth_cases"]
                if len(helpers)!=1 or len(helpers[0].body)!=1 or not isinstance(helpers[0].body[0],ast.Return):
                    raise RuntimeError("Unexpected S22 authentication matrix")
                values=helpers[0].body[0].value
            if not isinstance(values,(ast.List,ast.Tuple)) or not values.elts:
                raise RuntimeError("Expected nonempty explicit parametrization")
            if any(isinstance(n,ast.keyword) and n.arg=="marks" for n in ast.walk(values)):
                raise RuntimeError("Parameterized skip/xfail requires review")
            count*=len(values.elts)
        counts[entry]=count
    if sum(counts[entry] for entry in inherited)!=126:
        raise RuntimeError("S24 parameter expansion changed")
    new=ast.parse((support/"backend-overlay/tests/test_frame_relay_conversion.py").read_text())
    required={"tests/test_frame_relay_conversion.py::"+n.name for n in new.body
              if isinstance(n,ast.FunctionDef) and n.name.startswith("test_")}
    if not required.issubset(nodes):raise RuntimeError("New conversion cases omitted")
    return sum(counts.values()),len(required),counts


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--revision",required=True)
    args=parser.parse_args()
    if len(args.revision)!=3 or not args.revision.isascii() or not args.revision.isdigit():
        raise SystemExit("Expected fresh three-digit revision")
    support=Path(__file__).resolve().parent
    isolation=support.parent/"server-isolation"
    archive,archive_before,base,original_path,original,before=archived_base(support)
    external=Path(original["external_root"])
    source_before={name:record(external/name) for name in original["source_before"]}
    if source_before!=original["source_before"]:raise RuntimeError("External source changed")
    external_runtime(original)
    overlay=support/"backend-overlay"
    overlay_before=tree(overlay)
    # Keep the old 26 declarations and every assertion byte-for-byte.
    old_test=base/"backend/tests/test_frame_relay_registrations.py"
    if record(overlay/"tests/test_frame_relay_registrations.py")!=record(old_test):
        raise RuntimeError("S22 registration tests changed")
    if record(overlay/"app/db/frame_relay_schema/001_registrations.sql")!=record(
            base/"backend/app/db/frame_relay_schema/001_registrations.sql"):
        raise RuntimeError("S22 migration 001 changed")
    if record(overlay/"app/db/frame_relay_schema/002_storage.sql")!=record(
            base/"backend/app/db/frame_relay_schema/002_storage.sql"):
        raise RuntimeError("S24 migration 002 changed")
    sources={directory.name:tree(directory) for directory in (support,isolation)}
    parsed=[]
    for directory in (support,isolation):
        for name in sources[directory.name]:
            if name.endswith(".py"):
                source=(directory/name).read_text()
                ast.parse(source,filename=name)
                # AST parsing does not reject a misplaced __future__ import.
                # Compile without importing/executing or writing bytecode.
                compile(source,name,"exec",dont_inherit=True)
                parsed.append(directory.name+"/"+name)
    differences=[]
    for name in overlay_before:
        old=base/"backend"/name
        differences.extend(difflib.unified_diff(old.read_text().splitlines(keepends=True) if old.exists() else [],
            (overlay/name).read_text().splitlines(keepends=True),
            fromfile="a/backend/"+name if old.exists() else "/dev/null",tofile="b/backend/"+name))
    difference="".join(differences)
    if (support/"backend-conversion-overlay.diff").read_text()!=difference:
        raise RuntimeError("Conversion review diff is stale")
    nodes=json.loads((support/"cases-conversion.json").read_text())
    expected_cases,new_cases,case_counts=verify_cases(nodes,support,base)
    output=ROOT/"S26J"
    snapshot=output/("snapshot-"+args.revision)
    preparation=output/("preparation-"+args.revision)
    runtime=output/("runtime-pytest-"+args.revision)
    if any(p.exists() or p.is_symlink() for p in (snapshot,preparation,runtime)):
        raise SystemExit("Refusing to reuse snapshot, preparation or runtime")
    snapshot.mkdir(parents=True)
    preparation.mkdir()
    for name in before:
        if not name.startswith("backend/"):raise RuntimeError("Unexpected base path")
        replacement=overlay/name.removeprefix("backend/")
        copy(replacement if replacement.is_file() else base/name,snapshot/name)
    for name in overlay_before:
        if not (snapshot/"backend"/name).exists():copy(overlay/name,snapshot/"backend"/name)
    frozen=preparation/"source-snapshot"
    for directory in (support,isolation):
        for name in sources[directory.name]:copy(directory/name,frozen/directory.name/name)
    if (tree(archive)!=archive_before or any(tree(directory)!=sources[directory.name] for directory in (support,isolation)) or
            {name:record(external/name) for name in source_before}!=source_before):
        raise RuntimeError("Source changed while preparing; do not execute this incomplete revision")
    external_runtime(original)
    snapshot_manifest=tree(snapshot)
    provenance={**original,"snapshot":snapshot_manifest,"source_after_snapshot":source_before,
        "s24_base_snapshot":before,
        "s24_base_provenance_sha256":record(original_path)["sha256"],
        "base_snapshot":before,"base_provenance":str(original_path),"base_provenance_sha256":record(original_path)["sha256"],
        "base_input_kind":"repository_archive","base_archive":str(archive),
        "base_archive_manifest":archive_before["archive-manifest.json"],
        "s24_tmp_input_reverified":False,
        "overlay":overlay_before,"backend_imported":False,"tests_executed":False}
    provenance_path=preparation/"provenance-before.json";dump(provenance_path,provenance)
    cases=frozen/"server-implementation/cases-conversion.json"
    config={"snapshot":str(snapshot),"runtime":str(runtime),"external_root":str(external),
        "site_packages":original["site_packages_root"],"interpreter":original["interpreter"]["entry"],
        "provenance":str(provenance_path),"allow_missing_ffprobe_version_probe":True,"action":"pytest",
        "case_file":str(cases),"case_file_sha256":record(cases)["sha256"],
        "expected_nodes":len(nodes),"expected_cases":expected_cases}
    config_path=preparation/"run-config.json";dump(config_path,config)
    command=[config["interpreter"],"-I","-B","-S",str(frozen/"server-isolation/run_pytest.py"),"--config",str(config_path)]
    dump(preparation/"command.json",{"command":command,"executed":False})
    manifest={"snapshot":snapshot_manifest,"frozen_sources":tree(frozen),"config":record(config_path),
        "provenance":record(provenance_path),"command":record(preparation/"command.json"),
        "base_unchanged":True,"base_archive_unchanged":True,
        "base_identity":"Archived S24 snapshot-001: evidence/"+BASE_ARCHIVE,
        "base_archive_manifest":archive_before["archive-manifest.json"],"base_archive_entry_count":386,
        "s24_tmp_input_reverified":False,
        "s20_original_copy_complete":False,"external_source_and_runtime_unchanged":True,"s22_tests_and_001_002_sql_unchanged":True,
        "expected_nodes":len(nodes),"expected_cases":expected_cases,"new_conversion_tests":new_cases,
        "case_expansion":case_counts,
        "python_ast_files":parsed,"python_compile_files":parsed,
        "backend_imported":False,"tests_executed":False,"runtime_created":False}
    dump(preparation/"checkpoint-files.json",manifest)
    for root in (snapshot,preparation):
        for path in root.rglob("*"):
            if path.is_file():path.chmod(0o444)
    print(json.dumps({"preparation":str(preparation),"snapshot_files":len(snapshot_manifest),
        "expected_nodes":len(nodes),"expected_cases":expected_cases,"runtime_created":False,
        "checkpoint_sha256":record(preparation/"checkpoint-files.json")["sha256"]}))


if __name__=="__main__":main()
