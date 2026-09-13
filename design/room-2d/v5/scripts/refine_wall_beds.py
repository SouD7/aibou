"""Close segmentation pinholes and place foreground bed before overlapping desk legs."""
from pathlib import Path
import json,cv2,numpy as np
from PIL import Image,ImageFilter
B=Path(__file__).resolve().parents[1];m=json.loads((B/'manifest.json').read_text())
for s in m['scenes']:
 l=next(l for l in s['layers'] if l['id']=='bed');im=Image.open(B/l['file']).convert('RGBA');rgb=Image.open(B/f"repairs/{s['id']}-wall-bed-source.png").convert('RGB').resize((1672,941));a=(np.array(im.getchannel('A'))>127).astype('uint8')*255
 a=cv2.morphologyEx(a,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(5,5)));f=a.copy();cv2.floodFill(f,None,(0,0),255);a|=255-f
 # Solid post and side panel. These are traced inside the opaque furniture surface.
 if s['id'].endswith('overview'):
  for p in [[[679,368],[698,371],[700,485],[687,493],[678,466]],[[390,596],[680,459],[680,491],[391,633]]]:cv2.fillPoly(a,[np.array(p,np.int32)],255)
 im=rgb.convert('RGBA');im.putalpha(Image.fromarray(a).filter(ImageFilter.GaussianBlur(.35)));im.save(B/l['file']);l['z']=42
 for slot in s['avatarSlots']:
  if slot['target']=='bed':slot['z']=43
(B/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2))
