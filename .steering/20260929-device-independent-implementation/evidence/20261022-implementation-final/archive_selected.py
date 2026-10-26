import hashlib,json,shutil,sys
from pathlib import Path
root=Path(__file__).parent
archive=Path('/Users/oyabu/dev/rep/FrameRelay/.steering/20260929-device-independent-implementation/evidence')/sys.argv[1]
archive.mkdir(parents=True,exist_ok=True);manifest=archive/'archive-manifest.json'
rows=json.loads(manifest.read_text()) if manifest.is_file() else []
known={row['path']:row for row in rows}
for pattern in sys.argv[2:]:
    for match in root.glob(pattern):
        if match.suffix=='.xcresult' or match.name.endswith('DerivedData'):continue
        for path in ([match] if match.is_file() else match.rglob('*')):
            if not path.is_file():continue
            if path.suffix not in ('.swift','.json','.txt','.log','.py','.png','.jpg','.jpeg','.md','.diff','.sql','.pbxproj','.xcscheme','.xcworkspacedata','.xctestplan','.plist','.jsonl','.xml'):continue
            rel=str(path.relative_to(root));data=path.read_bytes()
            row={'path':rel,'sha256':hashlib.sha256(data).hexdigest(),'size':len(data),'origin':str(path)}
            if rel in known:
                if known[rel]['sha256']!=row['sha256']:raise RuntimeError('immutable evidence conflict '+rel)
                continue
            target=archive/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
            rows.append(row);known[rel]=row
manifest.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'files':len(rows),'bytes':sum(x['size'] for x in rows)}))
