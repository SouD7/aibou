"""Integrate CPU, split fans and dark-base wiring into fixed-camera deliverables."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
import json,shutil,zipfile,io,xml.etree.ElementTree as ET
import cv2,numpy as np
B=Path(__file__).resolve().parents[1];V2=B.parent/'v2';W,H=1672,941
m=json.loads((V2/'manifest.json').read_text());fx=json.loads((V2/'effects/manifest.json').read_text());cpu=json.loads((B/'cpu-revision.json').read_text());fans=json.loads((B/'fan-revision.json').read_text());wiring=json.loads((B/'wiring-revision.json').read_text());m['version']=3;fx['version']=3
m['revision']='Split fan blades, enlarged wall-side brain CPU, intermittent dark-base wiring'
def pngbytes(im):
 b=io.BytesIO();im.save(b,format='PNG');return b.getvalue()
for s in m['scenes']:
 sid=s['id'];ef=next(x for x in fx['scenes'] if x['id']==sid);cp=next(x for x in cpu['scenes'] if x['id']==sid);fs=next(x for x in fans['scenes'] if x['id']==sid);wire=next(x for x in wiring['scenes'] if x['id']==sid)
 ef['compute']=cp['compute'];ef['fans']=fs['fans'];ef['wiring']={**wire,'offBase':wire['offBase'].removeprefix('effects/'),'frames':[p.removeprefix('effects/') for p in wire['frames']],'frameDurationMs':100,'baseAlreadyApplied':True,'z':1};ef['source']=f'repairs/{sid}-cpu-source.png'
 bg=Image.open(V2/s['background']).convert('RGBA');bg.alpha_composite(Image.open(B/wire['offBase']));bg.save(B/s['background'])
 s['backgroundEffects']={'wiring':ef['wiring']};s['motionFrameCount']=24;s['motionFrameDurationMs']=100
 for l in s['layers']:
  if l['id'].startswith('fan-'):
   fan=next(x for x in fs['fans'] if x['id']==l['id']);out=Image.open(B/'effects'/fan['fixedHousing']).convert('RGBA')
   for key in ['bladesStatic','fixedGrille','fixedHub']:out.alpha_composite(Image.open(B/'effects'/fan[key]))
   out.save(B/l['file']);l['parts']=[{'id':key,'file':'effects/'+fan[key],'animated':key=='bladesStatic'} for key in ['fixedHousing','bladesStatic','fixedGrille','fixedHub']]
  if l['id']=='compute':l['z']=45;l.pop('revisionTransform',None);l['design']='Larger wall-side cabinet with recessed brain engraving'
  if l['id']=='external':l['z']=50
  if l['id'] in ['compute','external','network'] or l['id'].startswith('fan-'):
   alpha=np.array(Image.open(B/l['file']).getchannel('A'));hit=(alpha>=128).astype('uint8')*255;Image.fromarray(hit).save(B/l['hitMask']);cs,_=cv2.findContours(hit,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE);polys=[cv2.approxPolyDP(c,1.0,True).reshape(-1,2).tolist() for c in cs if cv2.contourArea(c)>20];l['hitPolygons']=polys;l['hitPolygon']=max(polys,key=lambda p:cv2.contourArea(np.array(p)))
 comp=bg.copy()
 for l in sorted(s['layers'],key=lambda l:l['z']):comp.alpha_composite(Image.open(B/l['file']))
 comp.save(B/s['preview'])
 ora_layers=[]
 for l in sorted(s['layers'],key=lambda l:l['z']):
  for part in l.get('parts',[{'id':l['id'],'file':l['file']}]):ora_layers.append((l['label']+' / '+part['id'],part['file']))
 ora_layers.insert(0,('部屋背景・配線消灯',s['background']))
 root=ET.Element('image',w=str(W),h=str(H),name=sid,version='0.0.3');stack=ET.SubElement(root,'stack')
 with zipfile.ZipFile(B/'scenes'/sid/f'{sid}.ora','w',zipfile.ZIP_DEFLATED) as z:
  z.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
  for i,(label,file) in enumerate(reversed(ora_layers)):
   path=f'data/layer{i:02}.png';z.write(B/file,path);ET.SubElement(stack,'layer',name=label,src=path,opacity='1.0',visibility='visible',x='0',y='0',**{'composite-op':'svg:src-over'})
  z.writestr('stack.xml',ET.tostring(root,encoding='UTF-8',xml_declaration=True));z.writestr('mergedimage.png',pngbytes(comp));thumb=comp.copy();thumb.thumbnail((256,256));z.writestr('Thumbnails/thumbnail.png',pngbytes(thumb))
 print('integrated',sid,flush=True)
(B/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2));(B/'manifest.js').write_text('window.ROOM_MANIFEST = '+json.dumps(m,ensure_ascii=False)+';\n');(B/'effects/manifest.json').write_text(json.dumps(fx,ensure_ascii=False,indent=2))
