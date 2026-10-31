"""Extract complete alpha components from generated atlases; fixed-scale technical packing."""
from pathlib import Path
import json,hashlib,re,argparse
from PIL import Image
import numpy as np
from scipy import ndimage
ROOT=Path(__file__).resolve().parents[1]
DIR=ROOT/"assets/combat_animations"
CELL=384;PAD=28
sources={}
for path in sorted(DIR.glob("*_actions_v*.png")):
    id,version=re.match(r"(.+)_actions_v(\d+)$",path.stem).groups()
    if id not in sources or int(version)>sources[id][0]:sources[id]=(int(version),path)
parser=argparse.ArgumentParser()
parser.add_argument("--only",nargs="+")
options=parser.parse_args()
manifest_path=ROOT/"data/combat/action_atlases.json"
entries=json.loads(manifest_path.read_text(encoding="utf-8"))["assets"] if options.only else {}
for id,(_,source) in sorted(sources.items()):
    if options.only and id not in options.only:continue
    image=Image.open(source).convert("RGBA");pixels=np.asarray(image)
    mask=pixels[:,:,3]>70
    labels,n=ndimage.label(mask)
    sizes=np.bincount(labels.ravel());slices=ndimage.find_objects(labels)
    groups={i:[] for i in range(16)}
    for component in range(1,n+1):
        if sizes[component]<100:continue
        sy,sx=slices[component-1]
        cx=(sx.start+sx.stop)*.5;cy=(sy.start+sy.stop)*.5
        col=min(3,int(cx/image.width*4));row=min(3,int(cy/image.height*4))
        groups[row*4+col].append(component)
    frames=[];heights=[];source_boxes=[];extents=[];hashes=[]
    for index in range(16):
        components=groups[index]
        if not components:raise ValueError(f"No isolated pose {id}:{index}; revise source atlas")
        main=max(components,key=lambda k:sizes[k])
        sy,sx=slices[main-1]
        if not id.startswith("vfx_") and (sizes[main]<6000 or sx.stop-sx.start>image.width/4*1.8 or sy.stop-sy.start>image.height/4*1.8):
            raise ValueError(f"Ambiguous or merged character pose {id}:{index}; revise generated source")
        # Whole connected pose may cross a nominal grid boundary. Never cut at that boundary.
        keep=labels==main
        for k in components:
            if k!=main and (sizes[k]>max(300,sizes[main]*.08) or id.startswith("vfx_")):keep|=labels==k
        keep=ndimage.binary_dilation(keep,iterations=3)
        rgba=pixels.copy();rgba[:,:,3]=np.where(keep,rgba[:,:,3],0)
        isolated=Image.fromarray(rgba)
        box=isolated.getbbox()
        if not box:raise ValueError(f"Empty pose {id}:{index}")
        frame=isolated.crop(box)
        # Preserve original horizontal registration; normalize only to the foot anchor.
        anchor_x=(index%4+.5)*image.width/4-box[0]
        anchor_y=box[3]-box[1]
        if id.startswith("vfx_"):
            bottom=(id=="vfx_elements" and index//4 in [2,3]) or (id=="vfx_nature" and index//4 in [0,1])
            anchor_x=frame.width*.5
            anchor_y=frame.height if bottom else frame.height*.5
        frames.append((frame,anchor_x,anchor_y));heights.append(frame.height)
        source_boxes.append(list(box))
        extents.append(max(anchor_x,frame.width-anchor_x)*2)
        hashes.append(hashlib.sha256(frame.tobytes()).hexdigest())
    ratio=min((CELL-PAD*2)/max(extents),(CELL-PAD*2)/max(heights))
    output=Image.new("RGBA",(CELL*4,CELL*4));pivots=[]
    for index,(frame,anchor_x,anchor_y) in enumerate(frames):
        packed=frame.resize((round(frame.width*ratio),round(frame.height*ratio)),Image.Resampling.NEAREST)
        target_y=CELL-PAD
        if id.startswith("vfx_"):
            bottom=(id=="vfx_elements" and index//4 in [2,3]) or (id=="vfx_nature" and index//4 in [0,1])
            if not bottom:target_y=CELL*.5
        x=round(CELL*.5-anchor_x*ratio);y=round(target_y-anchor_y*ratio)
        if x<0 or y<0 or x+packed.width>CELL or y+packed.height>CELL:raise ValueError(f"Packing clips {id}:{index}")
        output.alpha_composite(packed,(index%4*CELL+x,index//4*CELL+y))
        pivots.append([CELL/2,target_y])
    path=DIR/(id+"_runtime_v1.png");output.save(path,optimize=True)
    entries[id]={"path":"res://assets/combat_animations/"+path.name,"columns":4,"rows":4,"cell":CELL,"frame_count":16,"reference_height":round(max(heights[:4])*ratio,3),"pivots":pivots,"fixed_scale":True,"distinct_frames":len(set(hashes)),"source":source.name,"source_boxes":source_boxes,"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),"packing":"complete alpha component; no equal-grid clipping"}
manifest={"schema":1,"generator":"built-in imagegen; deterministic technical packing","boss_clips":{"walk":[0,1,2,3],"melee":[4,5,6,7],"cast":[8,9,10,11],"hurt":[12,13],"stagger":[14],"defeat":[15]},"hero_clips":{"walk":[0,1,2,3],"attack":[4,5,6,7],"sword":[8,9,10,11],"dodge":[12,13],"hurt":[14],"idle":[15]},"assets":entries}
(ROOT/"data/combat/action_atlases.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(f"Packed {len(entries)} complete-pose atlases / {len(entries)*16} frames; fixed scale and foot registration.")
