"""Derive v2 from the preserved v1 assets; identical affine for CPU artwork/effects."""
from pathlib import Path
import json,shutil,io,zipfile,xml.etree.ElementTree as ET
import cv2,numpy as np
from PIL import Image,ImageDraw,ImageFilter
B=Path(__file__).resolve().parents[1];V1=B.parent/'v1';W,H=1672,941
S=1.15;CX,CY=1444,627;DX,DY=-340,125
M=np.float32([[S,0,DX+(1-S)*CX],[0,S,DY+(1-S)*CY]])
for folder in ['scenes','effects','sources','previews']:
    shutil.copytree(V1/folder,B/folder,dirs_exist_ok=True)
for name in ['index.html','production-brief.json','README.md']:
    if not (B/name).exists():shutil.copy2(V1/name,B/name)
m=json.loads((V1/'manifest.json').read_text());fx=json.loads((V1/'effects/manifest.json').read_text());m['version']=2
# True cabinet outline excludes the adjacent radio-tower base included by v1's hull.
poly=[(1320,574),(1423,517),(1553,518),(1572,532),(1578,672),(1542,718),(1522,736),(1318,713)]
gate=Image.new('L',(W,H));ImageDraw.Draw(gate).polygon(poly,fill=255);g=np.array(gate)
def warp(im):
    # Premultiply before resampling to avoid dark fringes on alpha edges.
    a=np.array(im.convert('RGBA')).astype(np.float32)/255; a[:,:,:3]*=a[:,:,3:4]
    a=cv2.warpAffine(a,M,(W,H),flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
    a[:,:,:3]=np.divide(a[:,:,:3],a[:,:,3:4],out=np.zeros_like(a[:,:,:3]),where=a[:,:,3:4]>0)
    return Image.fromarray(np.clip(np.rint(a*255),0,255).astype(np.uint8))
def point(p):return [round(float(S*p[0]+M[0,2]),2),round(float(S*p[1]+M[1,2]),2)]
def update_coords(value,key=''):
    if isinstance(value,dict):return {k:update_coords(v,k) for k,v in value.items()}
    if isinstance(value,list):
        if key in ['centers','roiPolygon']:return [point(p) for p in value]
        if key=='roiPolygons':return [[point(p) for p in poly] for poly in value]
        return [update_coords(x,key) for x in value]
    return value
for scene in m['scenes']:
    sid=scene['id'];view=sid.split('-')[1]
    # Avatar positions are pose anchors, not a reserved empty center rectangle.
    if view=='horizontal':
        slots=[dict(id='sleeping',label='ベッド・寝姿（仮）',x=85,y=482,width=480,height=155,z=25,pose='lying',target='bed',anchor=[308,541]),dict(id='seated',label='椅子・座り姿（仮）',x=737,y=367,width=168,height=247,z=45,pose='sitting',target='chair',anchor=[817,531])]
    else:
        slots=[dict(id='sleeping',label='ベッド・寝姿（仮）',x=234,y=425,width=390,height=235,z=25,pose='lying',target='bed',anchor=[414,534]),dict(id='seated',label='椅子・座り姿（仮）',x=685,y=223,width=145,height=201,z=45,pose='sitting',target='chair',anchor=[753,345])]
    for slot in slots:slot['provisional']=True;slot['requiresPoseSpecificOcclusion']=True
    scene['avatarSlots']=slots
    if view=='horizontal':
        cp=B/'scenes'/sid/'compute.png';old=Image.open(V1/'scenes'/sid/'compute.png').convert('RGBA');arr=np.array(old);original_a=arr[:,:,3].copy()
        arr[:,:,3]=np.minimum(original_a,g);arr[arr[:,:,3]==0,:3]=0
        # Restore the now-exposed tower pedestal from a localized imagegen repair.
        network=Image.open(B/'repairs'/f"{sid.split('-')[0]}-network.png").convert('RGBA')
        network.save(B/'scenes'/sid/'network.png')
        moved=warp(Image.fromarray(arr))
        # Soft contact shadow grounds the cabinet at its new floor position.
        shadow=Image.new('RGBA',(W,H)); shadow_alpha=Image.new('L',(W,H))
        ImageDraw.Draw(shadow_alpha).ellipse((957,843,1247,887),fill=80 if sid.startswith('black') else 42)
        shadow_alpha=shadow_alpha.filter(ImageFilter.GaussianBlur(10));shadow.putalpha(shadow_alpha)
        shadow.alpha_composite(moved);shadow.save(cp)
        e=next(x for x in fx['scenes'] if x['id']==sid)
        files=[e['compute']['off'],e['compute']['on']]+e['compute']['frames']
        for file in files:warp(Image.open(V1/'effects'/file)).save(B/'effects'/file)
        e['compute']=update_coords(e['compute']);e['compute']['revisionTransform']=M.tolist()
        for layer in scene['layers']:
            if layer['id']=='compute':layer['z']=45;layer['revisionTransform']=M.tolist()
            if layer['id'] not in ['compute','network']:continue
            alpha=np.array(Image.open(B/layer['file']).getchannel('A'));hit=(alpha>=128).astype(np.uint8)*255
            Image.fromarray(hit).save(B/layer['hitMask']);contours,_=cv2.findContours(hit,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
            polygons=[cv2.approxPolyDP(c,1.5,True).reshape(-1,2).tolist() for c in contours if cv2.contourArea(c)>30]
            layer['hitPolygons']=polygons;layer['hitPolygon']=max(polygons,key=lambda p:cv2.contourArea(np.array(p)))
    comp=Image.open(B/scene['background']).convert('RGBA')
    for layer in sorted(scene['layers'],key=lambda l:l['z']):comp.alpha_composite(Image.open(B/layer['file']))
    comp.save(B/scene['preview'])
    if view=='horizontal':
        # A derived reference at the new coordinates for contrast checks and future edits.
        ref=f'sources/{sid}-layout-v2.png';comp.save(B/ref);next(e for e in fx['scenes'] if e['id']==sid)['source']=ref
    def pngbytes(im):
        buf=io.BytesIO();im.save(buf,format='PNG');return buf.getvalue()
    root=ET.Element('image',w=str(W),h=str(H),name=sid,version='0.0.3');stack=ET.SubElement(root,'stack')
    with zipfile.ZipFile(B/'scenes'/sid/f'{sid}.ora','w',zipfile.ZIP_DEFLATED) as z:
        z.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
        for i,layer in enumerate(sorted(scene['layers'],key=lambda l:l['z'],reverse=True)):
            src=f'data/layer{i:02}.png';z.write(B/layer['file'],src);ET.SubElement(stack,'layer',name=layer['label'],src=src,opacity='1.0',visibility='visible',x='0',y='0',**{'composite-op':'svg:src-over'})
        z.write(B/scene['background'],'data/background.png');ET.SubElement(stack,'layer',name='部屋背景',src='data/background.png',opacity='1.0',visibility='visible',x='0',y='0',**{'composite-op':'svg:src-over'})
        z.writestr('stack.xml',ET.tostring(root,encoding='UTF-8',xml_declaration=True));z.writestr('mergedimage.png',pngbytes(comp));thumb=comp.copy();thumb.thumbnail((256,256));z.writestr('Thumbnails/thumbnail.png',pngbytes(thumb))
    print('revised',sid,flush=True)
(B/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2));(B/'manifest.js').write_text('window.ROOM_MANIFEST = '+json.dumps(m,ensure_ascii=False)+';\n');(B/'effects/manifest.json').write_text(json.dumps(fx,ensure_ascii=False,indent=2))
(B/'layout-revision.json').write_text(json.dumps(dict(version=2,parent='../v1',priority='Component visibility; no central standing-space requirement',horizontalCompute=dict(scale=S,translation=[DX,DY],anchor=[CX,CY],matrix=M.tolist()),avatarPlacement='Bed lying / chair sitting; provisional anchors only; actual avatar art and occlusion layers deferred',method='Python affine edits of existing CPU RGBA assets; built-in imagegen localized tower pedestal repair'),ensure_ascii=False,indent=2))
