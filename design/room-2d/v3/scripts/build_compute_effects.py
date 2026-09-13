"""Keep bulb field off by default; light independent seeds without baked-on bulbs."""
from pathlib import Path
import json,importlib.util
from PIL import Image
import numpy as np,cv2
B=Path(__file__).resolve().parents[1];spec=importlib.util.spec_from_file_location('ef',B.parent/'v1/scripts/export_effects.py');ef=importlib.util.module_from_spec(spec);spec.loader.exec_module(ef)
r=json.loads((B/'cpu-revision.json').read_text())
for view in ['horizontal','overview']:
 black=next(x for x in r['scenes'] if x['id']=='black-'+view);poly=black['compute']['roiPolygon'];roi=ef.polygon_mask((1672,941),poly)
 src=cv2.imread(str(B/'repairs'/f'black-{view}-cpu-source.png'));components=ef.extract_compute_components(src,roi)
 for theme in ['black','white']:
  entry=next(x for x in r['scenes'] if x['id']==theme+'-'+view);cpu=entry['compute'];rgb=np.array(Image.open(B/'repairs'/f'{theme}-{view}-cpu-source.png').convert('RGB'))
  alpha=cv2.GaussianBlur(roi,(3,3),.5);offrgb=np.clip(rgb.astype(float)*.12+np.array([8,13,19]),0,255).astype('uint8');off=np.dstack([offrgb,alpha]);off[alpha==0,:3]=0
  on=np.dstack([rgb,alpha]);on[alpha==0,:3]=0
  ef.save_rgba(B/'effects'/cpu['off'],off);ef.save_rgba(B/'effects'/cpu['on'],on)
  rng=np.random.default_rng(183);frames=[]
  for i,path in enumerate(cpu['frames']):
   active=rng.random(len(components))<.45;mask=np.zeros_like(roi)
   for c,enabled in zip(components,active):
    if enabled:mask=cv2.bitwise_or(mask,c['mask'])
   mask=np.maximum(mask,cv2.GaussianBlur(mask,(0,0),1.2));mask=np.minimum(mask,alpha);light=np.dstack([rgb,mask]);frame=ef.composite(off,light);ef.save_rgba(B/'effects'/path,frame)
  cpu['centers']=[x['center'] for x in components];cpu['offBase']='Entire top bulb field dimmed to remove baked-on lights; seeded independent bulb activation';entry['bulbCount']=len(components)
(B/'cpu-revision.json').write_text(json.dumps(r,indent=2))
print('Rebuilt full off-base CPU fields for4 scenes')
