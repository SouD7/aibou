"""Refresh click masks, sprite metadata, static composites and editable ORA."""
from pathlib import Path
from PIL import Image,ImageDraw
import cv2,numpy as np,json,zipfile,io,xml.etree.ElementTree as ET
B=Path(__file__).resolve().parents[1];W,H=1672,941
m=json.loads((B/'manifest.json').read_text());fx=json.loads((B/'effects/manifest.json').read_text())
def pngbytes(im):
 b=io.BytesIO();im.save(b,format='PNG');return b.getvalue()
for s in m['scenes']:
 e=next(x for x in fx['scenes'] if x['id']==s['id']);comp=Image.open(B/s['background']).convert('RGBA');ora_layers=[('部屋背景・配線消灯',s['background'])]
 for l in sorted(s['layers'],key=lambda l:l['z']):
  im=Image.open(B/l['file']).convert('RGBA');a=np.array(im.getchannel('A'));hit=(a>=128).astype('uint8')*255;Image.fromarray(hit).save(B/l['hitMask']);cs,_=cv2.findContours(hit,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
  polys=[cv2.approxPolyDP(c,1,True).reshape(-1,2).tolist() for c in cs if cv2.contourArea(c)>20];l['hitPolygons']=polys;l['hitPolygon']=max(polys,key=lambda p:cv2.contourArea(np.array(p)));l['alphaBBox']=im.getbbox();comp.alpha_composite(im)
  for part in l.get('parts',[{'id':l['id'],'file':l['file']}]):ora_layers.append((l['label']+' / '+part['id'],part['file']))
 comp.save(B/s['preview'])
 root=ET.Element('image',w=str(W),h=str(H),name=s['id'],version='0.0.3');stack=ET.SubElement(root,'stack')
 with zipfile.ZipFile(B/'scenes'/s['id']/f"{s['id']}.ora",'w',zipfile.ZIP_DEFLATED) as z:
  z.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
  for i,(label,file) in enumerate(reversed(ora_layers)):
   path=f'data/layer{i:02}.png';z.write(B/file,path);ET.SubElement(stack,'layer',name=label,src=path,opacity='1.0',visibility='visible',x='0',y='0',**{'composite-op':'svg:src-over'})
  z.writestr('stack.xml',ET.tostring(root,encoding='UTF-8',xml_declaration=True));z.writestr('mergedimage.png',pngbytes(comp));thumb=comp.copy();thumb.thumbnail((256,256));z.writestr('Thumbnails/thumbnail.png',pngbytes(thumb))
 print('integrated',s['id'],flush=True)
(B/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2));(B/'manifest.js').write_text('window.ROOM_MANIFEST = '+json.dumps(m,ensure_ascii=False)+';\n')
