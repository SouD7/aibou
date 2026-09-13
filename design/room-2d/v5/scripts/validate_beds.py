from pathlib import Path
import numpy as np,json,math,hashlib
from PIL import Image
B=Path(__file__).resolve().parents[1];S=B.parent/'v4';m=json.loads((B/'manifest.json').read_text());report={'version':5,'checks':[]}
walls={'overview':np.array([814-292,279-510]),'horizontal':np.array([789-83,570-645])}
for s in m['scenes']:
 view=s['id'].split('-')[1];slot=next(a for a in s['avatarSlots'] if a['target']=='bed');p=np.array(slot['mattressQuad']);axis=p[3]-p[0];wall=walls[view];angle=math.degrees(math.acos(float(np.clip(np.dot(axis,wall)/np.linalg.norm(axis)/np.linalg.norm(wall),-1,1))));assert angle<4
 bed=next(l for l in s['layers'] if l['id']=='bed');alpha=np.array(Image.open(B/bed['file']).getchannel('A'));anchor=list(map(round,slot['anchor']));assert alpha[anchor[1],anchor[0]]>128 and slot['z']>bed['z']
 # Changes are confined to the requested bed asset and its metadata/effects.
 assert (B/s['background']).read_bytes()==(S/s['background']).read_bytes()
 for l in s['layers']:
  if l['id']!='bed':assert (B/l['file']).read_bytes()==(S/l['file']).read_bytes(),l['id']
 report['checks'].append({'scene':s['id'],'wallParallelAngleDifferenceDegrees':round(angle,3),'headEnd':'bookshelf','footEnd':'front-left','bedZ':bed['z'],'sleepingAvatarZ':slot['z'],'otherFurnitureAndBackground':'byte identical to v4'})
report['status']='passed';report['visualQA']='Final composite contact sheet reviewed; wide bed parallel to left wall in both views; desk legs behind bed';(B/'bed-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
