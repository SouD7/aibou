"""Give overview tower the same electronics plinth as horizontal tower."""
from pathlib import Path
import json,cv2,numpy as np
from PIL import Image,ImageDraw
B=Path(__file__).resolve().parents[1];S=B.parent/'v3';W,H=1672,941
# Import only helpers, avoiding align_layout's export side effects.
ns={'__file__':str(B/'scripts/align_layout.py')};code=(B/'scripts/align_layout.py').read_text();exec(code[:code.index("contract={'version'")],ns)
project,warp,affine=ns['project'],ns['warp'],ns['affine']
c=json.loads((B/'layout-contract.json').read_text());a=c['objects']['network']['anchor'];height=c['objects']['network']['heightWallUnits'];base,tip,seat=project('overview',[a,[a[0],a[1],height],[a[0],a[1],.18]])
# Top back, right, front and left corners of a 0.48m square plinth.
x,y,_=a
world=[[x-.045,y-.045,.18],[x-.045,y+.045,.18],[x+.045,y+.045,.18],[x+.045,y-.045,.18]]
top=project('overview',world);bottom=project('overview',[[p[0],p[1],0] for p in world])
source_front=np.float32([[1301,546],[1390,555],[1390,629],[1301,616]])
source_side=np.float32([[1390,555],[1423,540],[1423,614],[1390,629]])
for theme in ['black','white']:
 old=Image.open(S/f'scenes/{theme}-overview/network.png').convert('RGBA');sy=(seat[1]-tip[1])/(438-160);M=affine(.78,sy,[1342,438],seat);mast=warp(old,M)
 src=Image.open(S/f'scenes/{theme}-horizontal/network.png').convert('RGBA');out=Image.new('RGBA',(W,H))
 # Top panel without the old camera's protruding mast.
 d=ImageDraw.Draw(out);col=(47,58,67,255) if theme=='black' else (192,201,211,255);d.polygon([tuple(p) for p in top],fill=col)
 for sq,tq in [(source_front,np.float32([top[3],top[2],bottom[2],bottom[3]])),(source_side,np.float32([top[2],top[1],bottom[1],bottom[2]]))]:
  mask=Image.new('L',(W,H));ImageDraw.Draw(mask).polygon([tuple(p) for p in sq],fill=255);im=src.copy();im.putalpha(mask);out.alpha_composite(warp(im,cv2.getPerspectiveTransform(sq,tq)))
 out.alpha_composite(mast);out.save(B/f'scenes/{theme}-overview/network.png')
 r=next(s for s in c['scenes'] if s['id']==f'{theme}-overview')['projected']['network'];r['mastSeat']=seat.tolist();r['mastMatrix']=M.tolist();r['plinthTopQuad']=top.tolist();r['plinthBottomQuad']=bottom.tolist()
c['objects']['network']['plinth']='Same square electronics plinth; overview uses horizontal front/side textures';(B/'layout-contract.json').write_text(json.dumps(c,ensure_ascii=False,indent=2))
