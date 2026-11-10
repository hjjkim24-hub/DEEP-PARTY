"""규칙 아이콘: 동전, 트로피 (UI용 컬러), +5/-5 동전 칸 무늬 (흰색+투명).

    python make_game_icons.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT = os.path.join(ROOT, "fonts", "Poppins-Bold.ttf")
S = 4


def coin(n=128):
    im = Image.new("RGBA", (n * S, n * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    w = n * S
    d.ellipse([w * 0.04, w * 0.08, w * 0.96, w * 1.0 - w * 0.0], fill=(176, 112, 20, 255))
    d.ellipse([w * 0.04, w * 0.02, w * 0.96, w * 0.94], fill=(255, 196, 58, 255))
    d.ellipse([w * 0.16, w * 0.14, w * 0.84, w * 0.82], fill=(242, 168, 34, 255))
    d.ellipse([w * 0.2, w * 0.18, w * 0.8, w * 0.78], fill=(255, 206, 76, 255))
    # 가운데 조개 모양 대신 별 하나
    c = (w / 2, w * 0.48)
    pts = [(c[0] + math.cos(-math.pi / 2 + k * math.pi / 5) * w * (0.2 if k % 2 == 0 else 0.09),
            c[1] + math.sin(-math.pi / 2 + k * math.pi / 5) * w * (0.2 if k % 2 == 0 else 0.09)) for k in range(10)]
    d.polygon(pts, fill=(214, 140, 22, 255))
    d.ellipse([w * 0.26, w * 0.2, w * 0.4, w * 0.3], fill=(255, 240, 190, 200))
    return im.resize((n, n), Image.LANCZOS)


def trophy(n=128):
    im = Image.new("RGBA", (n * S, n * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    w = n * S
    gold, dark, light = (255, 198, 60, 255), (196, 128, 24, 255), (255, 236, 160, 255)
    # 손잡이
    for sx in (-1, 1):
        cx = w / 2 + sx * w * 0.3
        d.ellipse([cx - w * 0.14, w * 0.14, cx + w * 0.14, w * 0.44], outline=dark, width=int(w * 0.055))
    # 컵
    d.pieslice([w * 0.2, -w * 0.18, w * 0.8, w * 0.62], 0, 180, fill=gold)
    d.rectangle([w * 0.2, w * 0.08, w * 0.8, w * 0.22], fill=gold)
    d.rectangle([w * 0.2, w * 0.06, w * 0.8, w * 0.12], fill=light)
    d.rectangle([w * 0.45, w * 0.58, w * 0.55, w * 0.74], fill=dark)
    d.rounded_rectangle([w * 0.3, w * 0.72, w * 0.7, w * 0.8], radius=w * 0.02, fill=gold)
    d.rounded_rectangle([w * 0.24, w * 0.8, w * 0.76, w * 0.92], radius=w * 0.03, fill=dark)
    # 별
    c = (w / 2, w * 0.3)
    pts = [(c[0] + math.cos(-math.pi / 2 + k * math.pi / 5) * w * (0.11 if k % 2 == 0 else 0.05),
            c[1] + math.sin(-math.pi / 2 + k * math.pi / 5) * w * (0.11 if k % 2 == 0 else 0.05)) for k in range(10)]
    d.polygon(pts, fill=light)
    d.ellipse([w * 0.27, w * 0.14, w * 0.34, w * 0.36], fill=(255, 245, 210, 150))
    return im.resize((n, n), Image.LANCZOS)


def tile_coin(sign, n=256):
    im = Image.new("L", (n * S, n * S), 0)
    d = ImageDraw.Draw(im)
    w = n * S
    d.ellipse([w * 0.14, w * 0.14, w * 0.86, w * 0.86], fill=255)
    d.ellipse([w * 0.22, w * 0.22, w * 0.78, w * 0.78], fill=0)
    f = ImageFont.truetype(FONT, int(w * 0.3))
    t = sign + "5"
    tw = d.textlength(t, font=f)
    asc, desc = f.getmetrics()
    d.text((w / 2 - tw / 2, w / 2 - (asc + desc) * 0.52), t, font=f, fill=255)
    im = im.resize((n, n), Image.LANCZOS)
    out = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    out.putalpha(im)
    return out


if __name__ == "__main__":
    coin().save(os.path.join(ROOT, "textures", "ui", "coin.png"))
    trophy().save(os.path.join(ROOT, "textures", "ui", "trophy.png"))
    tile_coin("+").save(os.path.join(ROOT, "textures", "tiles", "icon_coin_plus.png"))
    tile_coin("-").save(os.path.join(ROOT, "textures", "tiles", "icon_coin_minus.png"))
    print("ok")
