from pathlib import Path
import subprocess,json
root=Path('/private/tmp/s27-static')
cmd=json.loads((root/'full-product-command.json').read_text())
r=subprocess.run(cmd,capture_output=True,text=True)
(root/'product-06.log').write_text(r.stdout+r.stderr)
(root/'product-06.json').write_text(json.dumps({'command':cmd,'exit':r.returncode},indent=2))
print((r.stdout+r.stderr)[-18000:]);print('exit',r.returncode)
raise SystemExit(r.returncode)
