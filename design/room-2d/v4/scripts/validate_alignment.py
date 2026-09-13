"""Validate final registration, visibility, and effect attachment to revised sprites."""
from pathlib import Path
import json,cv2,numpy as np
from PIL import Image
B=Path(__file__).resolve().parents[1];m=json.loads((B/'manifest.json').read_text());fx=json.loads((B/'effects/manifest.json').read_text());c=json.loads((B/'layout-contract.json').read_text());checks=[]
def alpha(f):return np.array(Image.open(f).convert('RGBA'))[:,:,3]
def projected(view,points):
 q=np.array(points,float);x,y,z=q.T
 if view=='overview':cx,cy,d,a,b,h=836,285,.06,616.6,244.4,250
 else:cx,cy,d,a,b,h=815,580,.368,483.5,44.3,335
 den=1-d*(x+y);return np.stack([cx+a*(y-x)/den,cy+(b*(x+y)-h*z)/den],-1)
for s in m['scenes']:
 e=next(x for x in fx['scenes'] if x['id']==s['id']);r=next(x for x in c['scenes'] if x['id']==s['id']);view=s['id'].split('-')[1]
 for f in e['fans']:
  assert f['bladeCount']==7
  err=float(np.linalg.norm(projected(view,[f['worldCenter']])[0]-f['center']));assert err<.001
  assert np.allclose(r['projected'][f['id']]['quad'],f['wallQuad'])
  H=np.array(f['canonicalToCanvas']);q=cv2.perspectiveTransform(np.float32([[[0,0],[255,0],[255,255],[0,255]]]),H)[0];assert np.max(np.abs(q-f['wallQuad']))<.001
  checks.append({'scene':s['id'],'fan':f['id'],'centerProjectionErrorPx':round(err,6),'bladeCount':7})
 # Tower anchor and height use the same guide in both views, independent of source pixels.
 net=r['projected']['network'];a=c['objects']['network']['anchor'];p=projected(view,[a,[a[0],a[1],c['objects']['network']['heightWallUnits']]])
 assert np.max(np.abs(p[0]-net['base']))<.001 and np.max(np.abs(p[1]-net['tip']))<.001
 l=next(l for l in s['layers'] if l['id']=='network');mask=alpha(B/l['file'])>128;visible=mask.copy()
 for other in s['layers']:
  if other['z']>l['z']:visible&=alpha(B/other['file'])<128
 fraction=float(visible.sum()/mask.sum());assert fraction>.65,(s['id'],fraction)
 checks.append({'scene':s['id'],'networkVisibleAlphaFraction':round(fraction,4),'networkBase':net['base'],'networkTip':net['tip']})
 # Updated battery and monitor maps must paint only their owning sprites.
 for owner,key,filekey in [('bed','battery','indicator'),('display','display','screen'),('display','display','blank')]:
  l=next(l for l in s['layers'] if l['id']==owner);body=alpha(B/l['file']);effect=alpha(B/'effects'/e[key][filekey]);count=int(np.count_nonzero((effect>128)&(body<100)));assert count==0,(s['id'],key,count)
 # Sleep/seated anchors remain provisional but must still lie on visible furniture pixels.
 for slot in s['avatarSlots']:
  l=next(l for l in s['layers'] if l['id']==slot['target']);x,y=map(round,slot['anchor']);assert alpha(B/l['file'])[y,x]>128
# Color variants use identical fan geometry and projected tower anchors.
for view in ['overview','horizontal']:
 a=next(e for e in fx['scenes'] if e['id']=='black-'+view);b=next(e for e in fx['scenes'] if e['id']=='white-'+view)
 for fa,fb in zip(a['fans'],b['fans']):assert fa['wallQuad']==fb['wallQuad'] and fa['center']==fb['center'] and fa['worldCenter']==fb['worldCenter']
report={'version':4,'status':'passed','checks':checks,'themeFanGeometry':'identical','visualReview':'4 final composites reviewed; bed and shelf alpha repaired; overview tower plinth added','limits':'Layout guides plus 2D painted art, not an exact 3D reconstruction. Overview fan plate height has explicit art compensation.'}
(B/'alignment-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
