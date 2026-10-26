import json,subprocess,sys
from pathlib import Path
r=Path(__file__).parent
sim="DFE46693-E8DD-4814-8957-4F327699F719"
label="s34-actual-ax5-11"
def size():return subprocess.check_output(["xcrun","simctl","ui",sim,"content_size"],text=True).strip()
before=size()
try:
 subprocess.run(["xcrun","simctl","ui",sim,"content_size","accessibility-extra-extra-extra-large"],check=True)
 (r/(label+"-content-size.json")).write_text(json.dumps({"before":before,"requested":"accessibility-extra-extra-extra-large","actual":size()},indent=2)+"\n")
 subprocess.run([sys.executable,str(r/"runner.py"),label],check=True)
finally:
 subprocess.run(["xcrun","simctl","ui",sim,"content_size",before],check=True)
 (r/(label+"-settings-restored.json")).write_text(json.dumps({"before":before,"actual":size(),"restored":size()==before},indent=2)+"\n")
