"""Validate v3 image and animation contracts without requiring a browser."""
from pathlib import Path
import json,zipfile,hashlib,xml.etree.ElementTree as ET,io
import numpy as np
from PIL import Image
B=Path(__file__).resolve().parents[1];m=json.loads((B/'manifest.json').read_text());fx=json.loads((B/'effects/manifest.json').read_text());report={'version':3,'canvas':[1672,941],'scenes':[],'browserQA':'Not run: local URL rejected by browser tool policy.'}
def rgba(path):
 im=Image.open(path);assert im.size==(1672,941);assert im.mode=='RGBA';a=np.array(im.getchannel('A'));assert (a.min()==0 or path.name=='off-base.png') and a.max()>0;return im
assert len(m['scenes'])==4
all_effects=set()
for s in m['scenes']:
 assert len(s['layers'])==11
 e=next(x for x in fx['scenes'] if x['id']==s['id']);base=Image.open(B/s['background']).convert('RGBA')
 for l in sorted(s['layers'],key=lambda l:l['z']):
  im=rgba(B/l['file']);base.alpha_composite(im);hit=np.array(Image.open(B/l['hitMask']));assert hit.shape==(941,1672);assert not np.any((hit>0)&(np.array(im)[:,:,3]<128))
  for poly in l['hitPolygons']:assert len(poly)>=3 and all(0<=x<1672 and 0<=y<941 for x,y in poly)
 assert np.array_equal(np.array(base),np.array(Image.open(B/s['preview'])))
 with zipfile.ZipFile(B/'scenes'/s['id']/f"{s['id']}.ora") as z:
  assert z.testzip() is None;layers=ET.fromstring(z.read('stack.xml')).find('stack').findall('layer');assert len(layers)==18
  ora=Image.new('RGBA',(1672,941))
  for l in reversed(layers):ora.alpha_composite(Image.open(io.BytesIO(z.read(l.attrib['src']))))
  ora_delta=int(np.abs(np.array(ora).astype('int16')-np.array(base).astype('int16')).max());assert ora_delta<=1,ora_delta
 motion=Image.open(B/s['motionPreview']);assert motion.n_frames==24;hashes=[]
 for i in range(24):motion.seek(i);hashes.append(hashlib.sha256(motion.convert('RGB').tobytes()).hexdigest())
 assert len(set(hashes))==24
 fan_checks=[]
 for fan in e['fans']:
  assert len(fan['bladeFrames'])==12;housing=rgba(B/'effects'/fan['fixedHousing']);union=np.zeros((941,1672),bool);comps=[];bladehash=[]
  for f in fan['bladeFrames']:
   im=rgba(B/'effects'/f);union|=np.array(im.getchannel('A'))>0;out=housing.copy();out.alpha_composite(im)
   for key in ['fixedGrille','fixedHub']:out.alpha_composite(rgba(B/'effects'/fan[key]))
   comps.append(np.array(out));bladehash.append(hashlib.sha256(im.tobytes()).hexdigest())
  assert len(set(bladehash))==12
  assert all(not np.any((comp!=comps[0])[~union]) for comp in comps[1:])
  fan_checks.append({'id':fan['id'],'uniqueBladeFrames':12,'changedPixelsOutsideBladeUnion':0})
 assert len(e['compute']['frames'])==12
 on=rgba(B/'effects'/e['compute']['on']);off=rgba(B/'effects'/e['compute']['off']);core=np.array(off)[:,:,3]>200
 contrast=float((np.array(on)[:,:,:3].astype(float)-np.array(off)[:,:,:3])[core].mean());assert contrast>40,contrast
 lamp=np.array(Image.open(B/next(l['file'] for l in s['layers'] if l['id']=='compute')))[:,:,3]
 assert all(lamp[round(y),round(x)]>200 for x,y in e['compute']['centers'])
 wire=e['wiring'];assert len(wire['frames'])==24 and wire['baseAlreadyApplied'];wirehash=[];ratios=[]
 for f in wire['frames']:
  im=rgba(B/'effects'/f);wirehash.append(hashlib.sha256(im.tobytes()).hexdigest());ratios.append(float((np.array(im)[:,:,3]>16).mean()))
 assert len(set(wirehash))==24 and max(ratios)<.15
 def walk(v):
  if isinstance(v,dict):
   for k,x in v.items():
    if k not in ['source','inputBackground']:yield from walk(x)
  elif isinstance(v,list):
   for x in v:yield from walk(x)
  elif isinstance(v,str) and v.endswith('.png'):yield v
 for f in set(walk(e)):rgba(B/'effects'/f);all_effects.add(f)
 report['scenes'].append({'id':s['id'],'recomposition':'pixel identical','oraLayers':18,'oraMaximumChannelRoundingDifference':ora_delta,'uniqueMotionFrames':24,'fans':fan_checks,'cpuBulbCount':len(e['compute']['centers']),'cpuOnOffMeanRGBDelta':round(contrast,2),'uniqueWireFrames':24,'maximumWireActiveCanvasFraction':round(max(ratios),4)})
report['furnitureRGBA']=44;report['referencedEffectRGBA']=len(all_effects);report['status']='passed';(B/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
