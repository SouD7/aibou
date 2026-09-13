"""Extract the generated wall-side CPU and foreground cable, then rebuild bulb effects."""
from pathlib import Path
import json,importlib.util
import numpy as np,cv2,torch
from PIL import Image,ImageDraw,ImageFilter
from segment_anything import SamPredictor,sam_model_registry
B=Path(__file__).resolve().parents[1];W,H=1672,941
torch.set_num_threads(6)
p=SamPredictor(sam_model_registry['vit_b'](checkpoint='/private/tmp/sam_vit_b_01ec64.pth'))
spec=importlib.util.spec_from_file_location('ef',B.parent/'v1/scripts/export_effects.py');ef=importlib.util.module_from_spec(spec);spec.loader.exec_module(ef)
entries=[]
for view in ['horizontal','overview']:
 for ti,theme in enumerate(['black','white']):
  sid=f'{theme}-{view}';a=np.array(Image.open(B/'repairs'/f'{sid}-cpu-source.png').convert('RGB'));a=cv2.resize(a,(W,H));p.set_image(a)
  if view=='horizontal':
   box=[1335,503,1664,783];pts=[[1460,630],[1480,526],[1580,584],[1520,783],[1355,490]];labels=[1,1,1,0,0]
   cbox=[1470,603,1662,823];cpts=[[1609,718],[1518,788],[1480,650]];cl=[1,1,0]
   poly=[[1403,512],[1609,510],[1581,543],[1397,537]]
  else:
   box=[1095,339,1441,605];pts=[[1201,505],[1255,406],[1376,481],[1328,621],[1341,282]];labels=[1,1,1,0,0]
   cbox=[1144,577,1304,694];cpts=[[1190,620],[1238,593],[1181,670],[1190,520]];cl=[1,1,1,0]
   poly=[[1153,400],[1236,354],[1390,415],[1288,465]]
  masks,scores,_=p.predict(box=np.array(box),point_coords=np.array(pts),point_labels=np.array(labels),multimask_output=True)
  raw=masks[np.argmax(scores)].astype('uint8')*255
  cs,_=cv2.findContours(raw,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE);mask=np.zeros_like(raw);cv2.drawContours(mask,[cv2.convexHull(max(cs,key=cv2.contourArea))],-1,255,-1)
  cm,sc,_=p.predict(box=np.array(cbox),point_coords=np.array(cpts),point_labels=np.array(cl),multimask_output=True);cable=cm[np.argmax(sc)].astype('uint8')*255
  # Only use the bounded selected foreground cable, not any connected wall panel.
  gate=np.zeros_like(cable);cv2.rectangle(gate,tuple(cbox[:2]),tuple(cbox[2:]),255,-1);cable=cv2.bitwise_and(cable,gate)
  # Reconstruct the small hidden cabinet area so the separate cable can be toggled.
  inside=cv2.bitwise_and(cv2.dilate(cable,np.ones((3,3),np.uint8)),mask)
  clean=cv2.inpaint(a,inside,4,cv2.INPAINT_TELEA)
  mask=cv2.GaussianBlur(mask,(3,3),.4)
  rgba=np.dstack([clean,mask]);rgba[mask==0,:3]=0
  Image.fromarray(rgba).save(B/'scenes'/sid/'compute.png')
  cable=cv2.GaussianBlur(cable,(3,3),.4);cr=np.dstack([a,cable]);cr[cable==0,:3]=0;Image.fromarray(cr).save(B/'scenes'/sid/'external.png')
  # Visible top only; keep the engraved panel unchanged in every CPU frame.
  roi=ef.polygon_mask((W,H),poly);bgr=cv2.cvtColor(a,cv2.COLOR_RGB2BGR);components=ef.extract_compute_components(bgr,roi)
  off,on,frames=ef.make_compute_layers(bgr,roi,components,theme,83+ti)
  out=B/'effects'/theme/view
  paths={}
  for name,data in [('off',off),('on',on)]:
   namepath=f'{theme}/{view}/compute-{name}.png';ef.save_rgba(B/'effects'/namepath,data);paths[name]=namepath
  paths['frames']=[]
  for i,data in enumerate(frames):
   namepath=f'{theme}/{view}/compute-{i:02}.png';ef.save_rgba(B/'effects'/namepath,data);paths['frames'].append(namepath)
  paths.update({'roiPolygon':poly,'centers':[x['center'] for x in components],'frameDurationMs':100,'placement':'right wall near front; engraved brain side','binaryMeaning':{'0':'off','1':'on'}})
  entries.append({'id':sid,'compute':paths,'bulbCount':len(components),'cpuBox':list(Image.fromarray(mask).getbbox()),'externalBox':list(Image.fromarray(cable).getbbox())})
  print(sid,len(components),'bulbs',flush=True)
(B/'cpu-revision.json').write_text(json.dumps({'scenes':entries,'method':'Built-in imagegen exact-object edits; SAM foreground extraction; cable separation; CPU bulb animation regenerated'},indent=2))
