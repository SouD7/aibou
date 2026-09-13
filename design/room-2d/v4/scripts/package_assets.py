from pathlib import Path
import json,zipfile
B=Path(__file__).resolve().parents[1]
assert json.loads((B/'validation.json').read_text())['status']=='passed'
assert json.loads((B/'alignment-validation.json').read_text())['status']=='passed'
p=B.parent/'room-2d-v4.zip'
with zipfile.ZipFile(p,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for f in sorted(B.rglob('*')):
  if f.is_file() and not any(part.startswith('.') or part=='__pycache__' for part in f.relative_to(B).parts):z.write(f,f.relative_to(B.parent))
with zipfile.ZipFile(p) as z:
 assert z.testzip() is None
 print(json.dumps({'file':str(p.resolve()),'entries':len(z.namelist()),'MiB':round(p.stat().st_size/1048576,1),'integrity':'passed'}))
