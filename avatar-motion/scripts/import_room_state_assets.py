"""Crop existing v3 component layers into compact runtime textures; no source assets changed."""
from pathlib import Path
import json
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'design/room-2d/v3'
OUT = ROOT / 'avatar-motion/Assets/RoomStates'
OUT.mkdir(parents=True, exist_ok=True)
fx = next(s for s in json.loads((SOURCE/'effects/manifest.json').read_text())['scenes'] if s['id']=='white-horizontal')
base = Image.open(ROOT/'avatar-motion/Assets/RoomAnimation/frame-000.png').convert('RGBA')
entries = {}
def save(name, image, bounds):
    image.crop(bounds).save(OUT/(name+'.png'))
    entries[name] = list(bounds)
for fan in fx['fans']:
    fixed = Image.open(SOURCE/'effects'/fan['fixedHousing']).convert('RGBA')
    bounds = fixed.getbbox()
    for i, blade in enumerate(fan['bladeFrames']):
        # Start from the delivered still room inside the housing bounds to fully erase baked motion.
        image = base.copy()
        image.alpha_composite(fixed)
        image.alpha_composite(Image.open(SOURCE/'effects'/blade))
        for name in ['fixedGrille','fixedHub']: image.alpha_composite(Image.open(SOURCE/'effects'/fan[name]))
        save(f"{fan['id']}-{i:02d}", image, bounds)
    # Camera-like blade blur makes high speed visibly distinct even at aliased frame rates.
    for i in range(12):
        images = [Image.open(OUT/f"{fan['id']}-{(i+j)%12:02d}.png") for j in range(4)]
        blur = images[0]
        for n, im in enumerate(images[1:],2): blur = Image.blend(blur,im,1/n)
        name=f"{fan['id']}-fast-{i:02d}";blur.save(OUT/(name+'.png'));entries[name]=list(bounds)
for i, path in enumerate(fx['compute']['frames']):
    im=Image.open(SOURCE/'effects'/path).convert('RGBA')
    save(f'compute-{i:02d}',im,im.getbbox())
save('network-lamp',base,(1354,295,1382,347))
# Chair occludes paper placed on the desk behind it.
chair=Image.open(SOURCE/'scenes/white-horizontal/chair.png').convert('RGBA')
save('chair',chair,chair.getbbox())
# Preserve the exact painted spines and native widths from the normal room.
book_regions = {
    'book-tall': [(416,269),(434,271),(434,346),(416,344)],
    'book-white': [(446,273),(457,274),(457,348),(446,347)],
    'book-short': [(515,304),(527,305),(527,353),(515,352)],
    'book-small': [(528,309),(535,311),(535,353),(528,353)],
    'book-middle': [(443,376),(458,378),(458,445),(443,445)],
    'book-middle-white': [(465,379),(477,380),(477,445),(465,445)],
    'book-middle-short': [(530,397),(544,398),(544,444),(530,445)],
    'book-lower': [(455,479),(473,482),(473,533),(455,531)],
    'book-lower-white': [(432,469),(445,470),(445,531),(432,528)],
    'book-lower-right': [(569,469),(586,470),(586,523),(569,525)],
    'book-horizontal': [(478,494),(531,490),(532,505),(478,510)],
}
for name, polygon in book_regions.items():
    mask = Image.new('L', base.size)
    ImageDraw.Draw(mask).polygon(polygon, fill=255)
    image = base.copy(); image.putalpha(mask)
    save(name,image,mask.getbbox())
(OUT/'manifest.json').write_text(json.dumps({'source':'design/room-2d/v3','bounds':entries},indent=2)+'\n')
print(f'Exported {len(entries)} cropped textures')
