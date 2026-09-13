"""Verify usable alpha, all references, lossless reassembly, ORA and motion frames."""
from pathlib import Path
from PIL import Image
import json, zipfile, hashlib, xml.etree.ElementTree as ET
import numpy as np
B=Path(__file__).resolve().parents[1];m=json.loads((B/'manifest.json').read_text());e=json.loads((B/'effects/manifest.json').read_text())
report={'canvas':[1672,941],'sceneCount':len(m['scenes']),'furnitureRGBA':0,'effectRGBA':0,'scenes':[], 'browserQA':'Not run: local file URL rejected by browser tool policy.'}
def rgba(p, opaque_required=True):
    im=Image.open(p);assert im.size==(1672,941),(p,im.size);assert im.mode=='RGBA',(p,im.mode)
    a=np.array(im.getchannel('A'));assert a.min()==0 and (a.max()==255 if opaque_required else a.max()>0),(p,a.min(),a.max());return im
assert len(m['scenes'])==4
for s in m['scenes']:
    assert len(s['layers'])==11
    im=Image.open(B/s['background']).convert('RGBA')
    for l in sorted(s['layers'],key=lambda o:o['z']):
        layer=rgba(B/l['file']);report['furnitureRGBA']+=1;im.alpha_composite(layer)
        mask=Image.open(B/l['hitMask']);assert mask.mode=='L' and mask.size==im.size
        a=np.array(layer.getchannel('A'));hit=np.array(mask)>0;assert not np.any(hit&(a<128))
        for poly in l['hitPolygons']:
            assert len(poly)>=3
            assert all(0<=x<1672 and 0<=y<941 for x,y in poly)
    expected=Image.open(B/s['preview']);assert np.array_equal(np.array(im),np.array(expected)),s['id']
    ora=B/'scenes'/s['id']/f"{s['id']}.ora"
    with zipfile.ZipFile(ora) as z:
        assert z.read('mimetype')==b'image/openraster';root=ET.fromstring(z.read('stack.xml'));layers=root.find('stack').findall('layer');assert len(layers)==12
        for l in layers:assert l.attrib['src'] in z.namelist()
        assert z.testzip() is None
    motion=Image.open(B/s['motionPreview']);assert motion.n_frames==12
    hashes=[]
    for i in range(motion.n_frames):motion.seek(i);hashes.append(hashlib.sha256(motion.convert('RGB').tobytes()).hexdigest())
    assert len(set(hashes))==12
    report['scenes'].append({'id':s['id'],'recomposition':'pixel-identical to delivered composite','oraLayers':12,'motionFrames':12,'uniqueMotionFrames':12})
for s in e['scenes']:
    def walk(value):
        if isinstance(value,dict):
            for v in value.values():yield from walk(v)
        elif isinstance(value,list):
            for v in value:yield from walk(v)
        elif isinstance(value,str) and value.endswith('.png') and not value.startswith('sources/'):
            yield value
    for path in set(walk(s)):rgba(B/'effects'/path, opaque_required=False);report['effectRGBA']+=1
    original=Image.open(B/s['source']).convert('RGBA')
    on=original.copy();on.alpha_composite(Image.open(B/'effects'/s['compute']['on']))
    off=original.copy();off.alpha_composite(Image.open(B/'effects'/s['compute']['off']))
    active=np.array(Image.open(B/'effects'/s['compute']['off']).getchannel('A'))>200
    delta=(np.array(on)[:,:,:3].astype(float)-np.array(off)[:,:,:3].astype(float))[active].mean()
    assert delta>40,(s['id'],'insufficient on/off contrast',delta)
assert report['furnitureRGBA']==44
assert report['effectRGBA']==184,report['effectRGBA']
report['status']='passed'
(B/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
