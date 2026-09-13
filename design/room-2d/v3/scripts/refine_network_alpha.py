#!/usr/bin/env python3
"""Remove convex-hull wall patches from v3 network tower cutouts."""
from __future__ import annotations
import json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOM_2D = Path(__file__).resolve().parents[2]
V2, V3 = ROOM_2D / "v2", ROOM_2D / "v3"
CONFIG = {
 "horizontal": {"antenna":[[1356,299],[1377,356]],"top":[1366,350],"leftBottom":[1319,542],"rightBottom":[1402,542],"centerBottom":[1363,542],"levels":[358,408,454,495,538],"railWidth":6,"braceWidth":3,"dishes":[([1391,386],[21,25]),([1397,441],[13,17])],"baseBox":[1294,536,1440,638],"holeSamples":[[1342,477],[1381,477],[1342,515],[1382,515]]},
 "overview": {"antenna":[[1343,157],[1362,220]],"top":[1353,195],"leftBottom":[1305,398],"rightBottom":[1383,398],"centerBottom":[1353,398],"levels":[208,247,286,326,365,397],"railWidth":6,"braceWidth":3,"dishes":[([1309,253],[27,33]),([1377,296],[21,26])],"basePolygon":[[1287,397],[1387,390],[1390,414],[1370,437],[1313,433],[1285,414]],"baseBox":[1283,390,1412,463],"holeSamples":[[1338,315],[1368,337],[1334,368],[1372,372]]},
}

def at_y(top, bottom, y):
 t=(y-top[1])/max(1,bottom[1]-top[1]); return (round(top[0]+(bottom[0]-top[0])*t),y)

def geometry_mask(shape, view):
 h,w=shape; c=CONFIG[view]; m=np.zeros((h,w),np.uint8)
 top=tuple(c["top"]); left=tuple(c["leftBottom"]); right=tuple(c["rightBottom"]); center=tuple(c["centerBottom"])
 (x1,y1),(x2,y2)=c["antenna"]; cv2.rectangle(m,(x1,y1),(x2,y2),255,-1)
 for bottom in (left,right,center): cv2.line(m,top,bottom,255,c["railWidth"],cv2.LINE_AA)
 levels=c["levels"]
 for y in levels: cv2.line(m,at_y(top,left,y),at_y(top,right,y),255,c["braceWidth"],cv2.LINE_AA)
 for uy,ly in zip(levels[:-1],levels[1:]):
  cv2.line(m,at_y(top,left,uy),at_y(top,right,ly),255,c["braceWidth"],cv2.LINE_AA)
  cv2.line(m,at_y(top,right,uy),at_y(top,left,ly),255,c["braceWidth"],cv2.LINE_AA)
 for dish,axes in c["dishes"]:
  cv2.ellipse(m,tuple(dish),tuple(axes),0,0,360,255,-1,cv2.LINE_AA)
  mount=at_y(top,center,dish[1]); cv2.line(m,mount,tuple(dish),255,4,cv2.LINE_AA)
 if view=="overview": cv2.rectangle(m,(1387,320),(1415,389),0,-1)
 if "basePolygon" in c: cv2.fillPoly(m,[np.asarray(c["basePolygon"],np.int32)],255)
 else:
  bx1,by1,bx2,by2=c["baseBox"]; cv2.rectangle(m,(bx1,by1),(bx2,by2),255,-1)
 return cv2.GaussianBlur(m,(3,3),0.45)

def main():
 report={"version":3,"method":"deterministic truss geometry intersected with v2 alpha","scenes":[],"qa":{}}
 total=0; all_ok=True
 for sid in ("black-horizontal","white-horizontal","black-overview","white-overview"):
  view="horizontal" if sid.endswith("horizontal") else "overview"; c=CONFIG[view]
  base=np.asarray(Image.open(V2/"scenes"/sid/"network.png").convert("RGBA")); old=base[:,:,3]
  new=np.minimum(old,geometry_mask(old.shape,view)); out=base.copy(); out[:,:,3]=new; out[new==0,:3]=0
  dest=V3/"scenes"/sid/"network.png"; Image.fromarray(out,"RGBA").save(dest,optimize=True)
  before=int(np.count_nonzero(old)); after=int(np.count_nonzero(new)); removed=before-after; total+=removed
  bx1,by1,bx2,by2=c["baseBox"]; retention=float(np.count_nonzero(new[by1:by2,bx1:bx2]))/max(1,np.count_nonzero(old[by1:by2,bx1:bx2]))
  holes=float(np.mean([new[y,x]==0 for x,y in c["holeSamples"]])); rgb=bool(np.array_equal(out[new>0,:3],base[new>0,:3]))
  minimum_retention=.65 if view=="overview" else .9; minimum_holes=.25 if view=="overview" else .5
  ok=bool(removed>3000 and after>before*.3 and retention>minimum_retention and holes>=minimum_holes and rgb); all_ok=all_ok and ok
  report["scenes"].append({"id":sid,"file":f"scenes/{sid}/network.png","beforeAlphaPixels":before,"afterAlphaPixels":after,"removedBackgroundPixels":removed,"baseAlphaRetention":round(retention,4),"holeSampleClearance":round(holes,4),"visibleRgbUnchanged":rgb,"passed":ok})
 report["qa"]={"passed":all_ok,"totalRemovedBackgroundPixels":total}; (V3/"network-alpha-revision.json").write_text(json.dumps(report,indent=2)+"\n")
 print(json.dumps(report["qa"],indent=2))
 if not all_ok: raise SystemExit("network alpha QA failed")

if __name__=="__main__": main()
