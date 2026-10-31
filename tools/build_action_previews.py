"""Compose generated frames at fixed roots; separately package actual Godot captures."""
from pathlib import Path
import json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"outputs"/"combat-lifecycle"/"animated-combat"
OUT.mkdir(parents=True,exist_ok=True)
M=json.loads((ROOT/"data/combat/action_atlases.json").read_text(encoding="utf-8"))["assets"]
FONT=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",23)
SMALL=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",17)
def pose(id,index,height):
    entry=M[id];cell=entry["cell"]
    with Image.open(ROOT/entry["path"].removeprefix("res://")) as atlas:
        x=index%4*cell;y=index//4*cell
        frame=atlas.crop((x,y,x+cell,y+cell)).convert("RGBA")
    scale=height/entry["reference_height"]
    return frame.resize((round(cell*scale),round(cell*scale)),Image.Resampling.NEAREST),[round(v*scale) for v in entry["pivots"][index]]
def stamp(canvas,id,index,foot,height):
    frame,pivot=pose(id,index,height)
    canvas.paste(frame,(round(foot[0]-pivot[0]),round(foot[1]-pivot[1])),frame)
def gif(frames,path,duration):
    sheet=Image.new("RGB",(160*len(frames),100))
    for i,frame in enumerate(frames):sheet.paste(frame.resize((160,100)),(160*i,0))
    palette=sheet.quantize(colors=256)
    encoded=[frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
    encoded[0].save(path,save_all=True,append_images=encoded[1:],duration=duration,loop=0,disposal=1,optimize=True)
for id,title in [("b06","赤棘 · 四肢迈步 / 抬爪重击"),("b18","晦鳞 · 爬行 / 龙爪横扫"),("hero_male","男角色 · 行走 / 挥剑"),("hero_female","女角色 · 行走 / 挥剑")]:
    frames=[]
    for i in range(16):
        canvas=Image.new("RGB",(800,360),"#171d28");draw=ImageDraw.Draw(canvas)
        draw.text((20,14),title,font=FONT,fill="#fce1b1")
        draw.text((36,58),"固定根位置 · 行走四帧",font=SMALL,fill="#9ec8cc")
        draw.text((430,58),"蓄力 → 抬肢 → 命中 → 收招",font=SMALL,fill="#9ec8cc")
        for x in [190,590]:
            draw.line((x-140,305,x+140,305),fill="#35434b",width=2)
            draw.line((x,298,x,313),fill="#6bb7ab",width=2)
        stamp(canvas,id,i%4,(190,305),205)
        sequence=[4,4,5,5,5,6,6,6,7,7,7,7,4,4,4,4]
        stamp(canvas,id,sequence[i],(590,305),205)
        frames.append(canvas)
    gif(frames,OUT/(id+"-limb-preview.gif"),125)
# Contact sheet uses only existing generated frame pixels and captions.
canvas=Image.new("RGB",(1200,1600),"#171d28");draw=ImageDraw.Draw(canvas)
config=json.loads((ROOT/"data/combat/pr4_boss_moves.json").read_text(encoding="utf-8"))["bosses"]
for i,(id,entry) in enumerate(config.items()):
    x=i%4*300;y=i//4*320
    draw.text((x+8,y+8),f"{entry['rank']:02} {entry['name']}",font=FONT,fill="#fce1b1")
    stamp(canvas,id,1,(x+80,y+173),110)
    stamp(canvas,id,6,(x+215,y+173),110)
    stamp(canvas,id,5,(x+80,y+308),110)
    stamp(canvas,id,10,(x+215,y+308),110)
canvas.save(OUT/"twenty-boss-action-assets.png")
# Capture sequence is a separate real-engine preview, never mixed with atlas demo.
paths=sorted((ROOT/"work/action-assets/frames/chain").glob("*.png"))
if len(paths)==90:
    frames=[]
    for path in paths:
        with Image.open(path) as raw:frames.append(raw.convert("RGB").crop((150,85,650,375)).resize((800,464),Image.Resampling.NEAREST))
    gif(frames,OUT/"battle-animation-preview.gif",100)
print("Composed four fixed-root limb demos, twenty-boss asset sheet, and actual-engine preview when available.")
