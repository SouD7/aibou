from pathlib import Path
import torch,cv2,numpy as np
from PIL import Image
from segment_anything import sam_model_registry,SamPredictor
B=Path(__file__).resolve().parents[1];torch.set_num_threads(6)
predictor=SamPredictor(sam_model_registry['vit_b'](checkpoint='/private/tmp/sam_vit_b_01ec64.pth'))
for theme in ['black','white']:
 im=Image.open(B/f'repairs/{theme}-horizontal-bed-source.png').convert('RGB').resize((1672,941));a=np.array(im);predictor.set_image(a)
 masks,_,_=predictor.predict(point_coords=np.array([[180,480],[340,580],[450,690],[40,580],[280,720]]),point_labels=np.ones(5),box=np.array([12,437,609,768]),multimask_output=False)
 mask=masks[0].astype('uint8')*255
 n,lab,stats,cen=cv2.connectedComponentsWithStats(mask);i=1+np.argmax(stats[1:,cv2.CC_STAT_AREA]);mask=(lab==i).astype('uint8')*255
 mask=cv2.morphologyEx(mask,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8));rgba=np.dstack([a,mask]);Image.fromarray(rgba).save(B/f'scenes/{theme}-horizontal/bed.png');Image.fromarray(mask).save(B/f'repairs/{theme}-bed-alpha.png');print(theme,stats[i].tolist(),flush=True)
