"""Small headboard perspective correction, preserving the mattress and legs."""
from pathlib import Path
import numpy as np,cv2,json
from PIL import Image,ImageDraw
B=Path(__file__).resolve().parents[1];W,H=1672,941
# The width alignment is confined to white headboard/pillow and fades at mattress.
def points(ps,theme):
 q=np.array(ps,float);w=np.clip((550-q[:,1])/70,0,1)
 # Preserve straight headboard posts; color variants retain their painted silhouette.
 q[:,1]=q[:,1]-.065*(q[:,0]-170)*np.clip((550-q[:,1])/90,0,1)
 return q
fx=json.loads((B/'effects/manifest.json').read_text())
for theme in ['black','white']:
 im=Image.open(B/f'scenes/{theme}-horizontal/bed.png').convert('RGBA');rgba=np.array(im,dtype=np.float32)/255;rgba[:,:,:3]*=rgba[:,:,3:4]
 yy,xx=np.indices((H,W),dtype=np.float32);sx=xx.copy();sy=yy.copy()
 for _ in range(8):
  q=points(np.stack([sx.ravel(),sy.ravel()],1),theme);sx+=(xx-q[:,0].reshape(H,W)).astype('float32');sy+=(yy-q[:,1].reshape(H,W)).astype('float32')
 out=cv2.remap(rgba,sx,sy,cv2.INTER_LINEAR);out[:,:,:3]/=np.maximum(out[:,:,3:4],1e-6);im=Image.fromarray(np.uint8(np.clip(out*255+.5,0,255)));im.save(B/f'scenes/{theme}-horizontal/bed.png')
 pp=points([[148,452],[236,452],[240,480],[147,484]],theme).round(2).tolist();mask=Image.new('L',(W,H));ImageDraw.Draw(mask).polygon([tuple(p) for p in pp],fill=255)
 ef=next(e for e in fx['scenes'] if e['id']==f'{theme}-horizontal');bat=im.copy();bat.putalpha(Image.fromarray(np.minimum(np.array(mask),np.array(im.getchannel('A')))));bat.save(B/'effects'/ef['battery']['indicator']);ef['battery']['polygon']=pp
(B/'effects/manifest.json').write_text(json.dumps(fx,ensure_ascii=False,indent=2))
