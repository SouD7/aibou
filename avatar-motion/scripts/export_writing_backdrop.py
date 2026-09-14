"""Rebuild the existing layered scene behind the chair, preserving its 24-frame clock."""
from pathlib import Path
import json
from PIL import Image

root = Path(__file__).resolve().parents[2]
source = root / 'design/room-2d/v3'
out = root / 'avatar-motion/Assets/WritingBackdrop'
out.mkdir(parents=True, exist_ok=True)
scene = next(s for s in json.loads((source / 'manifest.json').read_text())['scenes']
             if s['id'] == 'white-horizontal')
effects = next(s for s in json.loads((source / 'effects/manifest.json').read_text())['scenes']
               if s['id'] == scene['id'])
chair = Image.open(source / 'scenes/white-horizontal/chair.png').convert('RGBA')
bounds = chair.getbbox()
frames = []
for index in range(24):
    frame = Image.open(source / scene['background']).convert('RGBA')
    frame.alpha_composite(Image.open(source / 'effects' / effects['wiring']['frames'][index]))
    for layer in sorted(scene['layers'], key=lambda item: item['z']):
        if layer['id'] == 'chair':
            continue
        if layer['id'].startswith('fan-'):
            fan = next(f for f in effects['fans'] if f['id'] == layer['id'])
            for path in [fan['fixedHousing'], fan['bladeFrames'][index % 12], fan['fixedGrille'], fan['fixedHub']]:
                frame.alpha_composite(Image.open(source / 'effects' / path))
        else:
            frame.alpha_composite(Image.open(source / layer['file']))
            if layer['id'] == 'compute':
                frame.alpha_composite(Image.open(source / 'effects' / effects['compute']['frames'][index % 12]))
    name = f'frame-{index:03}.png'
    frame.crop(bounds).save(out / name)
    frames.append(name)
(out / 'manifest.json').write_text(json.dumps({'bounds': bounds, 'frames': frames, 'duration': 2.4}, indent=2) + '\n')
print(f'Exported {len(frames)} chair-free backdrop patches at {bounds}')
