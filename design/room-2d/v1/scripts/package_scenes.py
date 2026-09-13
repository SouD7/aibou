"""Package fixed-position scene patches with actual alpha and restored background.
These are scene-aligned layers including local lighting context, not movable stickers.
"""
from pathlib import Path
import json, io, zipfile, xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import cv2
B=Path(__file__).resolve().parents[1]; W,H=1672,941
OV={
'bed': [[163,443],[377,367],[403,378],[403,432],[444,455],[491,486],[660,564],[679,582],[681,676],[492,761],[457,744],[198,613],[163,571]],
'bookshelf':[[368,235],[575,153],[602,162],[602,416],[587,435],[418,477],[393,450],[367,410]],
'desk':[[604,244],[745,184],[800,199],[814,216],[962,246],[980,257],[980,372],[948,386],[931,370],[916,398],[881,423],[849,411],[836,372],[793,336],[755,339],[702,343],[650,388],[604,379]],
'chair':[[687,248],[713,243],[741,252],[761,305],[784,311],[814,304],[825,319],[807,348],[777,372],[772,391],[817,407],[817,437],[783,440],[760,422],[753,448],[728,448],[720,422],[701,430],[680,422],[680,402],[714,383],[699,357],[686,319]],
'compute':[[1108,427],[1228,382],[1483,490],[1487,541],[1347,593],[1120,537]],
'network':[[1340,154],[1359,154],[1370,215],[1384,268],[1390,288],[1411,393],[1411,441],[1364,465],[1295,443],[1291,410],[1313,387],[1335,283],[1300,290],[1283,276],[1280,243],[1291,221],[1313,221],[1333,238]],
'fan-1':[[945,103],[1018,124],[1019,202],[943,177]],
'fan-2':[[1020,134],[1095,157],[1095,237],[1019,212]],
'display':[[802,115],[946,161],[958,169],[958,270],[885,272],[799,251]],
'external':[[1280,550],[1323,558],[1335,578],[1330,610],[1250,602],[1229,606],[1223,629],[1236,650],[1230,684],[1203,701],[1172,692],[1148,677],[1149,640],[1165,617],[1174,585],[1194,567],[1231,552]]}
# Cable is a separate island inside the display layer.
OV_CABLE=[[992,207],[1018,214],[1023,267],[1018,306],[1007,321],[989,328],[967,319],[970,301],[989,303],[993,289]]

def hull_mask(scene, obj):
    view=scene.split('-')[1]; oid=obj['id']
    mask=np.array(Image.open(B/'layers'/scene/f'{oid}-mask.png'))
    contours,_=cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    for contour in contours:
        if cv2.contourArea(contour)>40:cv2.drawContours(mask,[cv2.convexHull(contour)],-1,255,-1)
    if view=='overview' and oid in OV:
        guide=Image.new('L',(W,H)); d=ImageDraw.Draw(guide); d.polygon([tuple(p) for p in OV[oid]],fill=255)
        if oid=='display':
            d.polygon([tuple(p) for p in OV_CABLE],fill=255)
        gate=np.array(guide)>0
        mask[~gate]=0
        if oid.startswith('fan-'):mask=np.array(guide)
        if oid=='display':
            mask[:,965:]=0
            d=ImageDraw.Draw(Image.fromarray(mask))
            tmp=Image.fromarray(mask); d=ImageDraw.Draw(tmp)
            d.polygon([(994,210),(1013,217),(1013,266),(994,262)],fill=255)
            d.line([(1005,264),(1004,287),(1000,303),(992,313),(982,315),(970,310)],fill=255,width=10,joint='curve')
            mask=np.array(tmp)
    if view=='horizontal' and oid=='bed':
        mask[:435,:]=0
    if view=='horizontal' and oid=='display':
        tmp=Image.new('L',(W,H)); d=ImageDraw.Draw(tmp)
        d.polygon([(867,381),(1099,365),(1101,455),(990,457),(1000,469),(1047,470),(1047,481),(934,481),(934,472),(959,468),(962,456),(866,455)],fill=255)
        d.polygon([(1188,356),(1222,351),(1225,423),(1188,427)],fill=255)
        d.line([(1203,423),(1201,450),(1192,473),(1175,487),(1137,489)],fill=255,width=11,joint='curve')
        mask=np.array(tmp)
    if view=='horizontal' and oid=='external':
        cv2.rectangle(mask,(1598,530),(1649,605),255,-1)
    # Remove stray disconnected specks; retain thin functional cables.
    n,labels,stats,_=cv2.connectedComponentsWithStats((mask>0).astype(np.uint8),8)
    for i in range(1,n):
        if stats[i,cv2.CC_STAT_AREA]<12:mask[labels==i]=0
    return mask>0

manifest={'version':1,'canvas':{'width':W,'height':H},'assetType':'fixed-position-2d-scene-layers','scenes':[]}
for theme in ['black','white']:
 for view in ['overview','horizontal']:
    sid=f'{theme}-{view}'; out=B/'scenes'/sid; out.mkdir(parents=True,exist_ok=True)
    ann=json.loads((B/f'{view}-annotations.json').read_text()); src=Image.open(B/'sources'/f'{sid}-master.png').convert('RGB'); rgb=np.array(src)
    empty=Image.open(B/'background-candidates'/f'{sid}.png').convert('RGB')
    ordered=sorted(ann['objects'],key=lambda o:o['z'])
    cores={o['id']:hull_mask(sid,o) for o in ordered}
    masks={k:cv2.GaussianBlur(cv2.dilate(v.astype(np.uint8)*255,np.ones((5,5),np.uint8)),(9,9),1.3) for k,v in cores.items()}
    # One pixel owner prevents another furniture layer retaining a duplicate object.
    occupied=np.zeros((H,W),bool)
    for o in reversed(ordered):
        m=masks[o['id']].copy(); m[occupied]=0; occupied|=cores[o['id']]; masks[o['id']]=m
    bg=np.array(empty).copy()
    background=Image.fromarray(bg).convert('RGBA'); background.save(out/'background.png')
    layers=[]; composite=background.copy()
    for o in ordered:
        mask=masks[o['id']]; rgba=np.dstack([rgb,mask]); rgba[mask==0,:3]=0
        im=Image.fromarray(rgba); im.save(out/f"{o['id']}.png"); composite.alpha_composite(im)
        # Alpha masks are authoritative for exact picking; polygon is broad phase.
        contours,_=cv2.findContours(mask.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
        polys=[cv2.approxPolyDP(c,2,True).reshape(-1,2).tolist() for c in contours if cv2.contourArea(c)>40]
        Image.fromarray((mask>127).astype(np.uint8)*255).save(out/f"{o['id']}-hit-mask.png")
        layer=dict(id=o['id'],label=o['label'],file=f'scenes/{sid}/{o["id"]}.png',x=0,y=0,width=W,height=H,z=o['z'],hitPolygon=max(polys,key=len) if polys else [],hitPolygons=polys,hitMask=f'scenes/{sid}/{o["id"]}-hit-mask.png',lockedPosition=True,localLightingIncluded=True)
        layers.append(layer)
    composite.save(out/'composite.png')
    # composite.png is rendered from the actual layers, not copied from generated art.
    slot=dict(id='idle',label='アバター配置予定',x=760 if view=='overview' else 720,y=440 if view=='overview' else 490,width=240,height=300 if view=='overview' else 350,z=50)
    entry=dict(id=sid,label=f"{'黒' if theme=='black' else '白'}・{'俯瞰' if view=='overview' else '水平'}",preview=f'scenes/{sid}/composite.png',background=f'scenes/{sid}/background.png',layers=layers,avatarSlots=[slot])
    manifest['scenes'].append(entry)
    # Editable OpenRaster, top-first layer stack, standard PNG entries.
    root=ET.Element('image',w=str(W),h=str(H),name=sid,version='0.0.3'); stack=ET.SubElement(root,'stack')
    def pngbytes(im):
        b=io.BytesIO(); im.save(b,format='PNG'); return b.getvalue()
    with zipfile.ZipFile(out/f'{sid}.ora','w') as z:
        z.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
        for i,o in enumerate(reversed(ordered)):
            name=f'data/layer{i:02}.png'; z.write(out/f"{o['id']}.png",name,compress_type=zipfile.ZIP_DEFLATED)
            ET.SubElement(stack,'layer',name=o['label'],src=name,opacity='1.0',visibility='visible',x='0',y='0',**{'composite-op':'svg:src-over'})
        z.writestr('data/background.png',pngbytes(background)); ET.SubElement(stack,'layer',name='部屋背景（元の空室素材）',src='data/background.png',opacity='1.0',visibility='visible',x='0',y='0',**{'composite-op':'svg:src-over'})
        z.writestr('stack.xml',ET.tostring(root,encoding='UTF-8',xml_declaration=True)); z.writestr('mergedimage.png',pngbytes(composite))
        thumb=composite.copy(); thumb.thumbnail((256,256)); z.writestr('Thumbnails/thumbnail.png',pngbytes(thumb))
    print('packaged',sid,flush=True)
(B/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
(B/'manifest.js').write_text('window.ROOM_MANIFEST = '+json.dumps(manifest,ensure_ascii=False)+';\n')
