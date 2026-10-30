# -*- coding: utf-8 -*-
"""生成两张模拟输入图，用于测试视觉识别效果：
  1) 手写既往病史便签  sample_handwritten_history.png
  2) 几种药盒摆在一起  sample_medicine_boxes.png
再直接调用本地服务 /api/v1/records/parse 看识别 + 属性换算结果。
"""
import base64
import json
import random

from PIL import Image, ImageDraw, ImageFont

FONT_DIR = "C:/Windows/Fonts/"
KAI = FONT_DIR + "simkai.ttf"       # 楷体，近似手写
XING = FONT_DIR + "STXINGKA.TTF"    # 华文行楷
HEI = FONT_DIR + "simhei.ttf"       # 黑体
YH = FONT_DIR + "msyh.ttc"          # 微软雅黑


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


# ---------------------------------------------------------------- 手写便签
def make_history_note(path):
    rnd = random.Random(7)
    W, H = 1024, 720
    img = Image.new("RGB", (W, H), (250, 247, 240))
    d = ImageDraw.Draw(img)

    # 横线本纸纹
    for y in range(120, H, 66):
        d.line([(40, y), (W - 40, y)], fill=(210, 214, 222), width=1)

    title_font = font(XING, 72)
    body_font = font(KAI, 46)

    # 标题
    d.text((W // 2 - 150, 40), "既往病史", font=title_font, fill=(35, 45, 80))

    lines = [
        "高血压 15 年，控制尚可",
        "2 型糖尿病 10 年",
        "冠心病 5 年，偶有胸闷",
        "前列腺增生 3 年",
        "胆囊切除术后 8 年",
        "",
        "目前长期服药（见药盒照片）",
    ]

    def handwritten(x, y, text, fnt, ink=(25, 32, 70)):
        for ch in text:
            bbox = d.textbbox((0, 0), ch, font=fnt)
            w = bbox[2] - bbox[0]
            h = bbox[3] - bbox[1]
            pad = fnt.size
            tile = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
            td = ImageDraw.Draw(tile)
            td.text((pad - bbox[0], pad - bbox[1]), ch, font=fnt, fill=ink + (255,))
            ang = rnd.uniform(-3.5, 3.5)
            tile = tile.rotate(ang, expand=True, resample=Image.BICUBIC)
            dx = int(x + rnd.uniform(-1.5, 1.5))
            dy = int(y + rnd.uniform(-2, 2))
            img.paste(tile, (dx, dy), tile)
            x += w + rnd.uniform(-1, 2)

    y = 150
    for line in lines:
        if line == "":
            y += 66
            continue
        handwritten(80, y, line, body_font)
        y += 66

    img.save(path)
    print("saved", path)


# ---------------------------------------------------------------- 药盒
def make_medicine_boxes(path):
    rnd = random.Random(11)
    W, H = 1240, 820
    img = Image.new("RGB", (W, H), (222, 224, 220))
    d = ImageDraw.Draw(img)

    # 桌面轻微渐变
    for i in range(H):
        v = int(222 - i * 0.012)
        d.line([(0, i), (W, i)], fill=(v, v + 2, v - 2))

    boxes = [
        ("络活喜", "苯磺酸氨氯地平片", "5mg × 7 片", "每日 1 次", "【降压】用于高血压", (176, 40, 44)),
        ("格华止", "盐酸二甲双胍片", "0.5g × 20 片", "每日 2 次", "【降糖】用于 2 型糖尿病", (196, 120, 36)),
        ("拜阿司匹灵", "阿司匹林肠溶片", "100mg × 30 片", "每日 1 次", "【抗血小板】防血栓", (44, 92, 156)),
        ("立普妥", "阿托伐他汀钙片", "20mg × 7 片", "每日 1 次", "【降脂】用于高血脂", (44, 120, 76)),
    ]

    bw, bh = 260, 340
    gap = 30
    total = len(boxes) * bw + (len(boxes) - 1) * gap
    x0 = (W - total) // 2
    y0 = (H - bh) // 2

    brand_font = font(YH, 34)
    gen_font = font(YH, 26)
    small_font = font(YH, 20)
    tag_font = font(HEI, 24)

    for i, (brand, generic, spec, usage, tag, color) in enumerate(boxes):
        box_img = Image.new("RGBA", (bw, bh), (255, 255, 255, 255))
        bd = ImageDraw.Draw(box_img)

        # 药盒主体
        bd.rounded_rectangle([(0, 0), (bw - 1, bh - 1)], radius=14, fill=(255, 255, 255), outline=(200, 200, 200), width=2)
        # 顶部色带
        bd.rounded_rectangle([(10, 10), (bw - 10, 92)], radius=10, fill=color)
        bd.text((18, 26), brand, font=brand_font, fill=(255, 255, 255))
        # 通用名
        bd.text((18, 120), generic, font=gen_font, fill=(30, 30, 30))
        # 规格
        bd.text((18, 168), spec, font=small_font, fill=(90, 90, 90))
        # 用法
        bd.text((18, 208), usage, font=gen_font, fill=(40, 40, 40))
        # 适应症标签
        bd.rounded_rectangle([(18, 262), (bw - 18, 304)], radius=8, fill=(240, 240, 240))
        bd.text((30, 272), tag, font=tag_font, fill=(20, 20, 20))
        # 底部公司名
        bd.text((18, bh - 40), "XX 制药", font=small_font, fill=(150, 150, 150))

        # 轻微旋转 + 阴影，摆出“随手放在桌上”的感觉
        ang = rnd.uniform(-3, 3)
        box_img = box_img.rotate(ang, expand=True, resample=Image.BICUBIC)
        shadow = Image.new("RGBA", box_img.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        sd.rectangle([(6, 10), (box_img.size[0] - 6, box_img.size[1] + 6)], fill=(0, 0, 0, 60))
        shadow = shadow.rotate(ang, expand=True, resample=Image.BICUBIC)

        px = x0 + i * (bw + gap)
        py = y0 + rnd.uniform(-8, 8)
        img.paste(shadow, (int(px) + 6, int(py) + 10), shadow)
        img.paste(box_img, (int(px), int(py)), box_img)

    img.save(path)
    print("saved", path)


def test_via_server():
    import requests

    paths = ["sample_handwritten_history.png", "sample_medicine_boxes.png"]
    data_urls = []
    for p in paths:
        with open(p, "rb") as f:
            data_urls.append("data:image/png;base64," + base64.b64encode(f.read()).decode())

    payload = {
        "data_urls": data_urls,
        "profile": {"relation": "爸爸", "name": "张建国", "age": 72, "sex": "男"},
    }
    r = requests.post("http://127.0.0.1:8000/api/v1/records/parse", json=payload, timeout=180)
    print("\nHTTP", r.status_code)
    data = r.json()
    if r.status_code != 200:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return

    doc = data["document"]
    print("\n==== 识别到的 person ====")
    print(json.dumps(doc.get("person"), ensure_ascii=False, indent=2))
    print("\n==== 识别到的 history ====")
    print(json.dumps(doc.get("history"), ensure_ascii=False, indent=2))
    print("\n==== 识别到的 medications ====")
    print(json.dumps(doc.get("medications"), ensure_ascii=False, indent=2))
    print("\n==== 识别到的 groups（指标） ====")
    print(json.dumps(doc.get("groups"), ensure_ascii=False, indent=2))
    print("\n==== 一句话结论 summary ====")
    print(doc.get("summary"))

    proj = data["game_projection"]
    print("\n==== 换算出的角色属性 character_state ====")
    print(json.dumps(proj.get("character_state"), ensure_ascii=False, indent=2))
    print("\n==== 属性由哪些数据算出 attribute_notes ====")
    print(json.dumps(proj.get("attribute_notes"), ensure_ascii=False, indent=2))
    print("\nreadiness =", proj.get("readiness"))


if __name__ == "__main__":
    make_history_note("sample_handwritten_history.png")
    make_medicine_boxes("sample_medicine_boxes.png")
    test_via_server()
