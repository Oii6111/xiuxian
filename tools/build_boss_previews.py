"""Export actual Godot captures as local previews; never invent gameplay frames."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "combat-lifecycle" / "boss-polish"
OUT.mkdir(parents=True,exist_ok=True)
for boss, label in [("b06","charge"),("b16","leap")]:
    paths = sorted((ROOT/"work"/"boss-polish"/"frames"/boss).glob("*.png"))
    if len(paths)!=60: raise SystemExit(f"Expected 60 actual frames for {boss}")
    frames=[]
    for path in paths:
        with Image.open(path) as raw:
            frame=raw.convert("RGB").crop((175,75,655,370)).resize((720,442),Image.Resampling.NEAREST)
            frames.append(frame)
    palette = frames[0].quantize(colors=128)
    frames = [frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
    frames[0].save(OUT/(label+"-preview.gif"),save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=1,optimize=True)
font=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",22)
metadata=json.loads((OUT/"mechanics.json").read_text(encoding="utf-8"))
labels={"slash":"扇形扫击","charge":"真实位移冲锋","leap":"腾空 / 落地","volley":"交错弹幕","nova":"环震 / 内圈走位","eruption":"地面连爆 / 余势","beam":"固定方向吐息","cross":"十字阵 / 空隙走位"}
rows=[("mechanic-"+kind,metadata[kind]["boss"]+" · "+label) for kind,label in labels.items()]
canvas=Image.new("RGB",(1000,1392),"#211e26")
draw=ImageDraw.Draw(canvas)
for i,(stem,label) in enumerate(rows):
    x=(i%2)*500+10
    y=(i//2)*348
    draw.text((x+8,y+8),label,font=font,fill="#f6d8a3")
    with Image.open(OUT/(stem+".png")) as screenshot:
        tile=screenshot.convert("RGB").crop((330,150,1310,740)).resize((480,289),Image.Resampling.LANCZOS)
        canvas.paste(tile,(x,y+42))
canvas.save(OUT/"attack-overview.png")
print("Exported charge / leap clips and eight-mechanic overview from verified Godot captures.")
