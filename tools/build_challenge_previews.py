"""Assemble only actual engine captures and deterministic progression measurements."""
from pathlib import Path
import json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"outputs"/"combat-lifecycle"/"animated-combat"
OUT.mkdir(parents=True,exist_ok=True)
paths=sorted((ROOT/"work"/"action-assets"/"frames"/"chain").glob("*.png"))
if len(paths)!=90: raise SystemExit("Expected ninety actual engine frames.")
frames=[]
for path in paths:
    with Image.open(path) as source:
        frame=source.convert("RGB").crop((165,75,655,375)).resize((735,450),Image.Resampling.NEAREST)
        frames.append(frame)
palette=frames[0].quantize(colors=128)
frames=[frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
frames[0].save(OUT/"chain-preview.gif",save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=1,optimize=True)
font=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",23)
rows=[("perfect-dodge","精准闪避 · 返还体力 / 反击机会"),("precision-counter","强化反击 · 必须真正命中"),("poise-break","破势 · 有限输出窗口"),("three-hit-chain","后段第三阶段 · 三段连续进攻")]
canvas=Image.new("RGB",(1000,720),"#211e26")
draw=ImageDraw.Draw(canvas)
for i,(name,label) in enumerate(rows):
    x=i%2*500+10;y=i//2*360
    draw.text((x+8,y+8),label,font=font,fill="#ffe0a5")
    with Image.open(OUT/(name+".png")) as source:
        tile=source.convert("RGB").crop((330,170,1290,750)).resize((480,290),Image.Resampling.LANCZOS)
        canvas.paste(tile,(x,y+45))
canvas.save(OUT/"mechanics-overview.png")
print("Challenge preview: ninety engine frames; real input screenshots; no generated gameplay frames.")
