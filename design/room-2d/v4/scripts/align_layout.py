"""Fixed-camera 2D alignment. Shared wall coordinates; no runtime 3D dependency.
Run after extract_beds.py. All transforms start from immutable v3 pixels.
"""
from pathlib import Path
import json,math,importlib.util
import cv2,numpy as np
from PIL import Image,ImageDraw
B=Path(__file__).resolve().parents[1];S=B.parent/'v3';W,H=1672,941
m=json.loads((S/'manifest.json').read_text());fx=json.loads((S/'effects/manifest.json').read_text())
m['version']=4;fx['version']=4;m['revision']='Cross-camera bed, network and wall fan alignment'

def project(view,points):
 q=np.array(points,float);x,y,z=q.T
 if view=='overview':cx,cy,d,a,b,h=836,285,.06,616.6,244.4,250
 else:cx,cy,d,a,b,h=815,580,.368,483.5,44.3,335
 den=1-d*(x+y)
 return np.stack([cx+a*(y-x)/den,cy+(b*(x+y)-h*z)/den],-1).astype(np.float32)

def warp(im,M,size=(W,H)):
 a=np.array(im.convert('RGBA')).astype(np.float32)/255;a[:,:,:3]*=a[:,:,3:4]
 o=cv2.warpPerspective(a,M,size,flags=cv2.INTER_LINEAR);o[:,:,:3]/=np.maximum(o[:,:,3:4],1e-6)
 return Image.fromarray(np.uint8(np.clip(o*255+.5,0,255)))

def transform(points,M):return cv2.perspectiveTransform(np.float32([points]),M)[0].round(3).tolist()
def affine(sx,sy,anchor,dest):return np.float64([[sx,0,dest[0]-sx*anchor[0]],[0,sy,dest[1]-sy*anchor[1]],[0,0,1]])
def layer(s,id):return next(l for l in s['layers'] if l['id']==id)
def save(p,im):p.parent.mkdir(parents=True,exist_ok=True);im.save(p)
def move_layer(s,id,M):
 l=layer(s,id);save(B/l['file'],warp(Image.open(S/l['file']),M));l['alignmentTransform']=M.tolist()
 for slot in s['avatarSlots']:
  if slot['target']==id:
   slot['anchor']=transform([slot['anchor']],M)[0]
   box=transform([[slot['x'],slot['y']],[slot['x']+slot['width'],slot['y']+slot['height']]],M);slot.update(x=round(box[0][0]),y=round(box[0][1]),width=round(box[1][0]-box[0][0]),height=round(box[1][1]-box[0][1]))

contract={'version':4,'canvas':[W,H],'method':'2D art correction plus shared wall/floor projection guides; not a reconstructed 3D model','roomGuideMeters':[4,4,2.5],'scenes':[],'objects':{'bed':{'nominalWidthMeters':1.04,'nominalLengthMeters':2.08,'orientation':'headboard west wall; foot into room','method':'overview identity reference; horizontal bed redrawn, visual rather than metric reconstruction'},'network':{'anchor':[.16,.55,0],'heightWallUnits':.58,'widthFloorUnits':.12,'relation':'right wall between desk and CPU; separate from CPU plinth'},'fans':{'wall':'right','centers':[[0,.23,.72],[0,.38,.72]],'nominalWidthMeters':.55,'nominalHeightMeters':.55,'overviewPlateVerticalExtensionPx':16,'bladeCount':7,'method':'same normalized housing and rotor; shared wall centers, art-adjusted wall plate projection'},'desk':{'relation':'rear corner, left of tower','horizontalWidthScale':.82},'display':{'relation':'above desk; cable to right wall','horizontalWidthScale':.82}},'audit':[]}
spec=importlib.util.spec_from_file_location('fan_source',S/'scripts/build_fans.py');fanmod=importlib.util.module_from_spec(spec);spec.loader.exec_module(fanmod)
# One rectified physical housing per theme, reused by BOTH cameras and BOTH fans.
source_quad=np.float32([[1082,250],[1163,234],[1167,323],[1082,338]])
canon_quad=np.float32([[0,0],[255,0],[255,255],[0,255]])
canonical={}
for theme in ['black','white']:
 src=Image.open(S/f'effects/{theme}/horizontal/fan-1/fixed-housing.png')
 c=np.array(warp(src,cv2.getPerspectiveTransform(source_quad,canon_quad),(256,256)))
 # Cover old rotor and rim completely, preserving only square housing/corner bolts.
 cv2.circle(c,(128,128),111,(17,26,32,255) if theme=='black' else (40,50,56,255),-1,cv2.LINE_AA)
 cv2.circle(c,(128,128),110,(91,112,124,255) if theme=='black' else (160,174,182,255),4,cv2.LINE_AA)
 cv2.circle(c,(128,128),105,(35,49,58,255),2,cv2.LINE_AA)
 hub=np.zeros_like(c);cv2.circle(hub,(128,128),29,(62,77,85,255),-1,cv2.LINE_AA);cv2.circle(hub,(128,128),24,(58,225,251,255),3,cv2.LINE_AA);cv2.circle(hub,(128,128),18,(81,94,103,255),-1,cv2.LINE_AA)
 grille=np.zeros_like(c)
 for angle in [45,135,225,315]:
  t=math.radians(angle);p1=(round(128+29*math.cos(t)),round(128+29*math.sin(t)));p2=(round(128+103*math.cos(t)),round(128+103*math.sin(t)));cv2.line(grille,p1,p2,(101,114,123,255),3,cv2.LINE_AA)
 frames=[]
 for n in range(12):
  disc=fanmod.blade_disc(theme,n*30,7);cv2.circle(disc,(128,128),31,(0,0,0,0),-1,cv2.LINE_AA);frames.append(Image.fromarray(disc))
 canonical[theme]=(Image.fromarray(c),Image.fromarray(grille),Image.fromarray(hub),frames)
 for key,im in zip(['housing','grille','hub'],canonical[theme][:3]):save(B/f'repairs/{theme}-fan-canonical-{key}.png',im)

for s in m['scenes']:
 sid=s['id'];theme,view=sid.split('-');e=next(x for x in fx['scenes'] if x['id']==sid);record={'id':sid,'projected':{}}
 # Narrower desk and screen in low view: keep chair reachable and expose network base.
 if view=='horizontal':
  move_layer(s,'desk',affine(.82,1,[649,620],[590,620]))
  Md=affine(.82,1,[860,501],[710,501]);move_layer(s,'display',Md)
  for key in ['screen','blank']:save(B/'effects'/e['display'][key],warp(Image.open(S/'effects'/e['display'][key]),Md))
  e['display']['quad']=transform(e['display']['quad'],Md)
  # Fresh battery indicator from generated bed source, in matching new geometry.
  pp=[[151,453],[234,452],[240,478],[148,483]]
  mask=Image.new('L',(W,H));ImageDraw.Draw(mask).polygon([tuple(p) for p in pp],fill=255)
  im=Image.open(B/layer(s,'bed')['file']).convert('RGBA');im.putalpha(Image.fromarray(np.minimum(np.array(im.getchannel('A')),np.array(mask))));save(B/'effects'/e['battery']['indicator'],im);e['battery']['polygon']=pp
  slot=next(x for x in s['avatarSlots'] if x['target']=='bed');slot.update(x=90,y=484,width=460,height=165,anchor=[330,560])
  layer(s,'bed')['design']='Single bed matching overview: narrow footboard and longer visible side'
 # Network grounded at identical floor position, with identical projected height.
 anchor=contract['objects']['network']['anchor'];base,tip=project(view,[anchor,[anchor[0],anchor[1],contract['objects']['network']['heightWallUnits']]])
 oldbase=[1342,438] if view=='overview' else [1364,631];oldtop=160 if view=='overview' else 301
 sy=float((base[1]-tip[1])/(oldbase[1]-oldtop));sx=.78 if view=='overview' else .85
 M=affine(sx,sy,oldbase,base);move_layer(s,'network',M)
 record['projected']['network']={'base':base.tolist(),'tip':tip.tolist(),'sourceBase':oldbase,'matrix':M.tolist()}
 # New fan dimensions originate in one physical wall plane, not screen-space guesses.
 e['fans']=[]
 for index,center in enumerate(contract['objects']['fans']['centers']):
  _,u,z=center;du=.55/4/2;dz=.55/2.5/2
  world=[[0,u-du,z+dz],[0,u+du,z+dz],[0,u+du,z-dz],[0,u-du,z-dz]]
  quad=project(view,world)
  # Painted room backgrounds have different wall-height compression. Keep the
  # common center but match the observed vertical edge proportions of the artwork.
  if view=='overview':
   quad[:,1]+=np.float32([-16,-16,16,16])
  M=cv2.getPerspectiveTransform(canon_quad,quad);fid=f'fan-{index+1}';folder=f'{theme}/{view}/{fid}'
  fixed,grille,hub,frames=canonical[theme];f={'id':fid,'center':project(view,[center])[0].tolist(),'worldCenter':center,'wallQuad':quad.tolist(),'worldQuad':world,'canonicalToCanvas':M.tolist(),'bladeCount':7,'frameDurationMs':100,'blend':'source-over','bladeFrames':[]}
  for key,name,im in [('fixedHousing','fixed-housing',fixed),('fixedGrille','fixed-grille',grille),('fixedHub','fixed-hub',hub),('bladesStatic','blades-static',frames[0])]:
   path=f'{folder}/{name}.png';save(B/'effects'/path,warp(im,M));f[key]=path
  for n,im in enumerate(frames):
   path=f'{folder}/blades-frame-{n:02}.png';save(B/'effects'/path,warp(im,M));f['bladeFrames'].append(path)
  comp=Image.new('RGBA',(W,H))
  for key in ['fixedHousing','bladesStatic','fixedGrille','fixedHub']:comp.alpha_composite(Image.open(B/'effects'/f[key]))
  path=f'{folder}/composite-static.png';save(B/'effects'/path,comp);f['compositeStatic']=path;save(B/layer(s,fid)['file'],comp)
  layer(s,fid)['parts']=[{'id':k,'file':'effects/'+f[k],'animated':k=='bladesStatic'} for k in ['fixedHousing','bladesStatic','fixedGrille','fixedHub']]
  e['fans'].append(f);record['projected'][fid]={'center':f['center'],'quad':f['wallQuad'],'worldQuad':world}
 contract['scenes'].append(record)
 print(sid,record['projected']['network']['base'],flush=True)
contract['audit']=[{'component':'bed','finding':'horizontal double-width appearance and short side face','action':'redraw horizontal from overview single-bed identity; refresh alpha and battery'},{'component':'network','finding':'overview tower base too high, oversized tower and different wall position','action':'shared floor anchor and wall-relative height; bring between desk and CPU'},{'component':'fans','finding':'different wall positions, apparent sizes, 7 vs 11 blades, grille differences','action':'same 0.55m housing, 7 blades, 4 fixed supports; project shared wall coordinates'},{'component':'desk/display','finding':'horizontal desk much wider; tower would be obscured','action':'reduce horizontal desk/screen width and move display left with all screen effects'},{'component':'bookshelf/clock/chair','finding':'same semantic location and component identity; perspective differences remain in painted detail','action':'preserve; do not assert exact metric reconstruction'},{'component':'compute/external','finding':'right-wall front relation, engraved brain, visible bulb plane preserved','action':'preserve v3 animation and foreground cable'}]
(B/'layout-contract.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2));(B/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2));(B/'effects/manifest.json').write_text(json.dumps(fx,ensure_ascii=False,indent=2))
