from pathlib import Path
import json,sqlite3,hashlib,base64,sys
r=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent
folder=r/'photos-auxiliary-readonly-copies'
def normalize(x):
 if x is None:return ['null']
 if isinstance(x,bytes):return ['blob',base64.b64encode(x).decode()]
 if isinstance(x,float):return ['float',x.hex()]
 if isinstance(x,int):return ['int',x]
 return ['text',x]
def inspect(path):
 c=sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True);c.execute('PRAGMA query_only=ON');result={}
 try:
  for name,root,sql in c.execute("SELECT name,rootpage,sql FROM sqlite_master WHERE type='table' ORDER BY name").fetchall():
   rows=c.execute('SELECT * FROM "'+name.replace('"','""')+'"').fetchall();v=sorted(json.dumps([normalize(x) for x in row],ensure_ascii=False,separators=(',',':')) for row in rows);result[name]={'rootpage':root,'rows':len(rows),'digest':hashlib.sha256(('\n'.join(v)).encode()).hexdigest(),'schema_sha256':hashlib.sha256((sql or '').encode()).hexdigest()}
 finally:c.close()
 return result
before=inspect(folder/'baseline/Photos.sqlite');after=inspect(folder/'observed/Photos.sqlite');x={'method':'SHA256 sorted typed JSON rows, BLOB base64 and float.hex; original Photos file never opened by SQLite; read-only private copies only','baseline':before,'observed':after,'changed_tables':[k for k in before.keys()|after.keys() if before.get(k)!=after.get(k)],'private_values_included':False};(r/'photos-table-fingerprints.json').write_text(json.dumps(x,indent=2));print(json.dumps({'tables':len(before),'changed_tables':x['changed_tables'],'asset_rows_unchanged':before.get('ZASSET')==after.get('ZASSET')}))
