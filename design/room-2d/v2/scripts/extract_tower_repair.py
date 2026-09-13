from pathlib import Path
import numpy as np,cv2,torch
from PIL import Image
from segment_anything import SamPredictor,sam_model_registry
B=Path(__file__).resolve().parents[1];torch.set_num_threads(6)
p=SamPredictor(sam_model_registry['vit_b'](checkpoint='/private/tmp/sam_vit_b_01ec64.pth'))
for theme in ['black','white']:
    a=np.array(Image.open(B/'repairs'/f'{theme}-horizontal-tower-source.png').convert('RGB'));p.set_image(a)
    masks,scores,_=p.predict(box=np.array([1295,292,1438,638]),point_coords=np.array([[1364,460],[1360,581],[1393,384]]),point_labels=np.array([1,1,1]),multimask_output=True)
    mask=masks[np.argmax(scores)].astype(np.uint8)*255
    # Keep the original style of a fixed-position patch including the tower's interior.
    cs,_=cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    for c in cs:
        if cv2.contourArea(c)>30:cv2.drawContours(mask,[cv2.convexHull(c)],-1,255,-1)
    mask=cv2.GaussianBlur(mask,(3,3),0.4);rgba=np.dstack([a,mask]);rgba[mask==0,:3]=0
    Image.fromarray(rgba).save(B/'repairs'/f'{theme}-network.png');print(theme,'repaired',flush=True)
