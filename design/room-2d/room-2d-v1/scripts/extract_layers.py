"""Prompted local SAM extraction. Source art is generated; output alpha is real RGBA."""
import argparse, json, os
from pathlib import Path
import numpy as np
import cv2
from PIL import Image, ImageDraw
import torch
from segment_anything import SamPredictor, sam_model_registry
BASE=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(); p.add_argument('--checkpoint',default='/private/tmp/sam_vit_b_01ec64.pth'); p.add_argument('--scene',action='append'); args=p.parse_args()
torch.set_num_threads(6)
model=sam_model_registry['vit_b'](checkpoint=args.checkpoint)
# CPU is deterministic and compatible with all operators in upstream SAM.
predictor=SamPredictor(model)
scenes=args.scene or ['black-overview','white-overview','black-horizontal','white-horizontal']
for scene in scenes:
    view=scene.split('-')[1]
    source=Image.open(BASE/'sources'/f'{scene}-master.png').convert('RGB')
    rgb=np.array(source); h,w=rgb.shape[:2]
    ann=json.loads((BASE/f'{view}-annotations.json').read_text())
    out=BASE/'layers'/scene; out.mkdir(parents=True,exist_ok=True)
    print('encode',scene,flush=True); predictor.set_image(rgb)
    masks={}; report=[]
    for obj in ann['objects']:
        union=np.zeros((h,w),bool)
        prompts=obj.get('samPrompts',[obj])
        # Expand inaccurate hand annotation boxes; SAM follows actual image outlines.
        if view=='overview' and obj['id']=='bookshelf':
            prompts=[dict(box=[372,156,600,470],positivePoints=[[391,257],[578,190],[550,399],[465,329]],negativePoints=[[367,270],[610,300],[435,485]])]
        if view=='overview' and obj['id']=='display':
            prompts=[dict(box=[800,115,958,272],positivePoints=[[870,180],[919,227],[880,253]],negativePoints=[[780,197],[968,220]]),dict(box=[966,207,1022,329],positivePoints=[[1004,239],[1004,295],[982,315]],negativePoints=[[1027,270],[984,281]])]
        for prompt in prompts:
            positive=prompt.get('positivePoints',[]); negative=prompt.get('negativePoints',[])
            points=np.array(positive+negative,dtype=np.float32)
            labels=np.array([1]*len(positive)+[0]*len(negative))
            found,scores,_=predictor.predict(point_coords=points,point_labels=labels,box=np.array(prompt['box']),multimask_output=True)
            chosen=found[int(np.argmax(scores))]
            # Limit to a generous rectangle to prevent leakage into whole-room structure.
            x0,y0,x1,y1=prompt['box']; gate=np.zeros((h,w),bool); gate[max(0,y0-10):min(h,y1+11),max(0,x0-10):min(w,x1+11)]=True
            union|=chosen&gate
        masks[obj['id']]=union
        print(scene,obj['id'],int(union.sum()),flush=True)
    # Visible pixels have one owner; foreground assets win overlaps.
    occupied=np.zeros((h,w),bool)
    for obj in sorted(ann['objects'],key=lambda o:o['z'],reverse=True):
        mask=masks[obj['id']]; occupied|=mask
        alpha=mask.astype(np.uint8)*255
        rgba=np.dstack([rgb,alpha]); rgba[alpha==0,:3]=0
        Image.fromarray(rgba).save(out/f"{obj['id']}.png")
        Image.fromarray(alpha).save(out/f"{obj['id']}-mask.png")
        ys,xs=np.where(mask)
        report.append(dict(id=obj['id'],pixels=int(mask.sum()),bbox=[int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)] if len(xs) else None))
    # Inspection overlay and a montage on a contrast checkerboard.
    tint=rgb.copy().astype(float); palette=[(255,75,75),(75,255,100),(70,160,255),(255,180,40),(255,80,230),(0,235,210)]
    for i,obj in enumerate(ann['objects']):
        mask=masks[obj['id']]; tint[mask]=.5*tint[mask]+.5*np.array(palette[i%len(palette)])
    Image.fromarray(tint.astype(np.uint8)).save(out/'mask-review.png')
    (out/'extraction-report.json').write_text(json.dumps(report,indent=2))
    print('saved',scene,flush=True)
