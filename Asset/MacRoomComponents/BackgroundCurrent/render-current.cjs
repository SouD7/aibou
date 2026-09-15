const fs=require('fs'),path=require('path');
const sharp=require(process.env.SHARP_MODULE||'C:/Users/namba/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=__dirname,W=1672,H=941,N=96,FPS=24;
const routes=[
 ['#26deee',[[112,124],[780,253]]],
 ['#2855ef',[[835,255],[1565,108]]],
 ['#ae66ed',[[328,0],[272,63],[815,211],[1270,78]]],
 ['#ee74b7',[[113,192],[113,340],[145,388],[145,495],[177,531],[177,581]]],
 ['#27d9d3',[[178,194],[178,348],[161,374],[161,485],[198,529],[198,581]]],
 ['#f1bd50',[[729,277],[729,402],[699,447],[699,551]]],
 ['#ac70ef',[[851,284],[851,411],[883,458],[883,550]]],
 ['#2855ef',[[1439,154],[1439,326],[1481,373],[1481,474],[1462,499],[1462,577]]],
 ['#20dbed',[[1525,150],[1525,335],[1508,370],[1508,483],[1526,517],[1526,586]]],
 ['#2855ef',[[114,637],[774,561]]],
 ['#b779ed',[[840,562],[1556,645]]],
 ['#26e0e5',[[110,669],[32,718],[250,941]]],
 ['#a66eef',[[206,672],[178,686],[371,756],[240,941]]],
 ['#ec74bb',[[283,941],[336,827],[223,768],[176,730],[129,677],[171,665]]],
 ['#2855ef',[[1532,667],[1563,691],[1505,755],[1484,796],[1575,893],[1545,941]]],
 ['#f2be58',[[1357,716],[1420,732],[1483,802],[1416,941]]]
];
const prepared=routes.map(([color,p],j)=>{let lengths=[0];for(let i=1;i<p.length;i++)lengths.push(lengths[i-1]+Math.hypot(p[i][0]-p[i-1][0],p[i][1]-p[i-1][1]));return{color,p,lengths,length:lengths.at(-1),phase:j*43.17};});
function at(r,d){for(let i=1;i<r.p.length;i++)if(d<=r.lengths[i]){const t=(d-r.lengths[i-1])/(r.lengths[i]-r.lengths[i-1]);return[r.p[i-1][0]+(r.p[i][0]-r.p[i-1][0])*t,r.p[i-1][1]+(r.p[i][1]-r.p[i-1][1])*t];}return r.p.at(-1);}
function svg(frame){let strokes='';for(const r of prepared){const phase=(frame/N*360+r.phase)%360;for(let head=phase;head<r.length+80;head+=360){for(let k=0;k<16;k++){const d=head-k*4,a=d-4;if(a<0||d>r.length)continue;const p=at(r,a),q=at(r,d),alpha=Math.pow(1-k/16,1.6)*Math.min(1,a/16,(r.length-d)/16);strokes+=`<path d="M${p} L${q}" stroke="${r.color}" opacity="${Math.max(0,alpha).toFixed(3)}"/>`;}}}return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><defs><filter id="g" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="4"/></filter></defs><g fill="none" stroke-linecap="round" stroke-width="8" filter="url(#g)" opacity=".6">${strokes}</g><g fill="none" stroke-linecap="round" stroke-width="3">${strokes}</g></svg>`);}
(async()=>{for(const d of ['Frames','LightFrames'])fs.mkdirSync(path.join(root,d),{recursive:true});const stats=await sharp(path.join(root,'background-base.png')).stats();if(!stats.isOpaque)throw Error('Background must be opaque');const base=await sharp(path.join(root,'background-base.png')).resize(W,H).png().toBuffer();const frames=[],overlays=[];for(let i=0;i<N;i++){const name=String(i).padStart(3,'0'),light=await sharp(svg(i)).png().toBuffer();fs.writeFileSync(path.join(root,'LightFrames','light-'+name+'.png'),light);await sharp(base).composite([{input:light}]).png().toFile(path.join(root,'Frames','frame-'+name+'.png'));frames.push('Frames/frame-'+name+'.png');overlays.push('LightFrames/light-'+name+'.png');}fs.writeFileSync(path.join(root,'sequence.json'),JSON.stringify({canvas:[W,H],fps:FPS,frameCount:N,durationSeconds:N/FPS,loop:true,background:'background-base.png',frames,overlays,reducedMotionFrame:frames[0]},null,2));fs.writeFileSync(path.join(root,'routes.json'),JSON.stringify(routes,null,2));const samples=[];for(let i=0;i<6;i++)samples.push({input:await sharp(path.join(root,frames[i*16])).resize(557,314).toBuffer(),left:(i%2)*557,top:Math.floor(i/2)*314});await sharp({create:{width:1114,height:942,channels:3,background:'white'}}).composite(samples).png().toFile(path.join(root,'contact-sheet.png'));console.log('96 background PNGs + 96 alpha overlays; 24 fps, 4s seamless phase loop');})();
