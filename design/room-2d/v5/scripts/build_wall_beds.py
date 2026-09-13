"""Extract the wide, wall-parallel bed; retain v4 components and animations."""
from pathlib import Path
import torch,cv2,numpy as np,json
from PIL import Image,ImageDraw,ImageFilter
from segment_anything import sam_model_registry,SamPredictor
B=Path(__file__).resolve().parents[1];W,H=1672,941;torch.set_num_threads(6)
predictor=SamPredictor(sam_model_registry['vit_b'](checkpoint='/private/tmp/sam_vit_b_01ec64.pth'))
m=json.loads((B/'manifest.json').read_text());fx=json.loads((B/'effects/manifest.json').read_text());c=json.loads((B/'layout-contract.json').read_text())
m['version']=5;fx['version']=5;c['version']=5;m['revision']='Wide bed with long side against left wall, head at bookshelf end'
polys={
'overview':[(166,492),(192,481),(374,394),(472,352),(516,335),(520,292),(537,292),(690,350),(709,366),(711,489),(692,501),(398,648),(391,679),(365,685),(170,579),(163,560)],
'horizontal':[(20,546),(43,539),(74,547),(341,524),(410,520),(468,497),(469,454),(485,449),(636,450),(655,456),(660,604),(644,615),(186,696),(164,702),(28,644),(17,629)]}
heads={'overview':[[566,320],[629,341],[630,374],[565,351]],'horizontal':[[516,461],[577,463],[581,490],[515,489]]}
planes={'overview':[[213,496],[372,579],[676,436],[520,356]],'horizontal':[[58,552],[173,589],[622,538],[502,505]]}
for s in m['scenes']:
 sid=s['id'];view=sid.split('-')[1];im=Image.open(B/f'repairs/{sid}-wall-bed-source.png').convert('RGB').resize((W,H));rgb=np.array(im);predictor.set_image(rgb)
 if view=='overview':box=[164,290,714,687];points=[[450,470],[260,545],[591,339],[693,461],[383,615]]
 else:box=[17,446,662,705];points=[[300,563],[91,597],[550,477],[646,579],[407,619]]
 masks,_,_=predictor.predict(point_coords=np.array(points),point_labels=np.ones(len(points)),box=np.array(box),multimask_output=False)
 mask=Image.new('L',(W,H));ImageDraw.Draw(mask).polygon(polys[view],fill=255)
 alpha=np.minimum(masks[0].astype('uint8')*255,np.array(mask));alpha=cv2.morphologyEx(alpha,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
 bed=Image.fromarray(np.dstack([rgb,alpha]));bed.putalpha(bed.getchannel('A').filter(ImageFilter.GaussianBlur(.35)))
 l=next(l for l in s['layers'] if l['id']=='bed');bed.save(B/l['file']);l['design']='Wide mattress; long side flush with west wall; pillow at bookshelf end';l.pop('alignmentTransform',None)
 slot=next(a for a in s['avatarSlots'] if a['target']=='bed')
 if view=='overview':slot.update(x=217,y=351,width=460,height=239,anchor=[450,470])
 else:slot.update(x=70,y=496,width=550,height=104,anchor=[345,550])
 slot['mattressQuad']=planes[view];slot['headEnd']='bookshelf';slot['longSideWall']='west';slot['provisional']=True
 ef=next(e for e in fx['scenes'] if e['id']==sid);pp=heads[view];a=Image.new('L',(W,H));ImageDraw.Draw(a).polygon([tuple(p) for p in pp],fill=255);bat=bed.copy();bat.putalpha(Image.fromarray(np.minimum(np.array(a),np.array(bed.getchannel('A')))));bat.save(B/'effects'/ef['battery']['indicator']);ef['battery']['polygon']=pp
 print(sid,bed.getbbox(),flush=True)
c['objects']['bed']={'nominalWidthMeters':1.4,'nominalLengthMeters':2.1,'widthIntent':'comfortable reclining avatar; wide pre-v4 character','orientation':'LONG side flush to west/left tall wall; head toward bookshelf; foot toward front-left corner','method':'both camera paintings generated from corrected overview identity; no runtime 3D','mattressQuads':planes}
c['audit']=[x for x in c['audit'] if x['component']!='bed']+[{'component':'bed','finding':'v4 bed long axis projected into room, not along wall; narrowing unnecessary for reclining avatar','action':'quarter-turn onto west wall and wide mattress in both cameras and themes'}]
(B/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2));(B/'effects/manifest.json').write_text(json.dumps(fx,ensure_ascii=False,indent=2));(B/'layout-contract.json').write_text(json.dumps(c,ensure_ascii=False,indent=2))
