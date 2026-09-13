from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
B=Path(__file__).resolve().parents[1];S=B.parent/'v4';m=json.loads((B/'manifest.json').read_text());fx=json.loads((B/'effects/manifest.json').read_text());p=B/'previews'
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',24)
# Same displayed scale for camera-to-camera comparison.
o=Image.new('RGB',(1672,1030),(20,26,36));d=ImageDraw.Draw(o)
for i,s in enumerate(m['scenes']):
 im=Image.open(B/s['preview']).convert('RGB').resize((820,462));x=(i%2)*836+8;y=(i//2)*515+43;o.paste(im,(x,y));d.text((x+8,y-33),s['id'].upper()+' / v5',font=font,fill=(210,234,248))
o.save(p/'cross-camera-v5.jpg',quality=94)
# Compare the changed silhouette and arrangement.
o=Image.new('RGB',(1672,515),(20,26,36));d=ImageDraw.Draw(o)
for i,(base,title) in enumerate([(S,'BEFORE / v4'),(B,'AFTER / v5')]):
 im=Image.open(base/'scenes/black-horizontal/composite.png').convert('RGB').resize((820,462));x=i*836+8;o.paste(im,(x,43));d.text((x+8,8),title,font=font,fill=(210,234,248))
o.save(p/'horizontal-before-after.jpg',quality=94)
# Fan animated close-up uses the delivered layers at their FINAL coordinates.
frames=[]
for n in range(12):
 tile=Image.new('RGB',(1040,580),(36,44,55));d=ImageDraw.Draw(tile)
 for i,e in enumerate(fx['scenes']):
  im=Image.new('RGBA',(1672,941))
  for f in e['fans']:
   for path in [f['fixedHousing'],f['bladeFrames'][n],f['fixedGrille'],f['fixedHub']]:im.alpha_composite(Image.open(B/'effects'/path))
  box=im.getbbox();im=im.crop(box);im.thumbnail((500,230));x=(i%2)*520;y=(i//2)*290+40;bg=Image.new('RGBA',(500,240),(56,65,77,255));bg.alpha_composite(im,((500-im.width)//2,(240-im.height)//2));tile.paste(bg.convert('RGB'),(x+10,y));d.text((x+15,y-30),e['id'],font=font,fill='white')
 frames.append(tile)
frames[0].save(p/'fan-blades-motion.webp',save_all=True,append_images=frames[1:],duration=100,loop=0,lossless=True);frames[0].save(p/'fan-components.jpg',quality=93)
# Remove superseded v3 QA sheet; replacement uses final layer atlases.
old=p/'network-alpha-review.jpg'
if old.exists():old.unlink()
print('alignment and fan reviews exported')
