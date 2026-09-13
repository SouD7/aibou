"""Remove SAM shelf leakage; restore newly exposed shelf from the revised source."""
from pathlib import Path
import numpy as np,cv2
from PIL import Image,ImageDraw,ImageFilter
B=Path(__file__).resolve().parents[1];S=B.parent/'v3';W,H=1672,941
for theme in ['black','white']:
 src=Image.open(B/f'repairs/{theme}-horizontal-bed-source.png').convert('RGBA').resize((W,H))
 # Traced outer contour includes frame posts and mattress, excludes the shelf panel.
 headright=329 if theme=='black' else 360
 poly=[(16,441),(headright-15,437),(headright,447),(headright+1,522),(381,533),(408,541),(440,551),(472,560),(508,572),(540,580),(555,586),(567,598),(587,590),(602,595),(608,609),(608,690),(597,700),(338,761),(317,766),(300,760),(24,650),(12,640),(9,625),(14,590)]
 mask=Image.new('L',(W,H));ImageDraw.Draw(mask).polygon(poly,fill=255)
 sam=Image.open(B/f'repairs/{theme}-bed-alpha.png');a=np.minimum(np.array(sam),np.array(mask));im=src.copy();im.putalpha(Image.fromarray(a).filter(ImageFilter.GaussianBlur(.35)));im.save(B/f'scenes/{theme}-horizontal/bed.png')
 # The previous shelf mask was cut along the old wider bed silhouette.
 old=np.array(Image.open(S/f'scenes/{theme}-horizontal/bookshelf.png').getchannel('A'));ys,xs=np.nonzero(old>127);hull=cv2.convexHull(np.array([xs,ys]).T.astype(np.int32));m=np.zeros((H,W),np.uint8);cv2.fillPoly(m,[np.array([[365,237],[390,225],[631,266],[643,584],[620,600],[372,575]],np.int32)],255);m[a>0]=0
 shelf=src.copy();shelf.putalpha(Image.fromarray(m).filter(ImageFilter.GaussianBlur(.3)));shelf.save(B/f'scenes/{theme}-horizontal/bookshelf.png')
