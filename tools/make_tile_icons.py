"""3D 보드 칸 위에 새길 무늬 그림 (흰색 + 투명).

    python make_tile_icons.py  →  ../textures/tiles/icon_*.png
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "textures", "tiles")
FONT = os.path.join(os.path.dirname(HERE), "fonts", "Poppins-Bold.ttf")
N = 256


def make(name, draw_fn, w=N, h=N):
    s = 4
    im = Image.new("L", (w * s, h * s), 0)
    draw_fn(ImageDraw.Draw(im), w * s, h * s)
    im = im.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(im)
    out.save(os.path.join(OUT, f"icon_{name}.png"))


def pearl(d, w, h):
    c, R = w / 2, w * 0.36
    d.ellipse([c - R, c - R, c + R, c + R], fill=255)
    d.ellipse([c - R * 0.72, c - R * 0.72, c + R * 0.72, c + R * 0.72], fill=0)
    d.ellipse([c - R * 0.46, c - R * 0.46, c + R * 0.46, c + R * 0.46], fill=255)


def urchin(d, w, h):
    c, R = w / 2, w * 0.42
    pts = [(c + math.cos(k * math.pi / 12) * R * (1 if k % 2 == 0 else 0.5),
            c + math.sin(k * math.pi / 12) * R * (1 if k % 2 == 0 else 0.5)) for k in range(24)]
    d.polygon(pts, fill=255)


def star(d, w, h):
    c, R = w / 2, w * 0.44
    pts = [(c + math.cos(-math.pi / 2 + k * math.pi / 5) * R * (1 if k % 2 == 0 else 0.44),
            c + 12 + math.sin(-math.pi / 2 + k * math.pi / 5) * R * (1 if k % 2 == 0 else 0.44)) for k in range(10)]
    d.polygon(pts, fill=255)


def arrows(d, w, h):
    c, R = w / 2, w * 0.44
    for k in range(4):
        a = k * math.pi / 2
        d.polygon([(c + math.cos(a) * R, c + math.sin(a) * R),
                   (c + math.cos(a + 0.4) * R * 0.6, c + math.sin(a + 0.4) * R * 0.6),
                   (c + math.cos(a - 0.4) * R * 0.6, c + math.sin(a - 0.4) * R * 0.6)], fill=255)
    d.ellipse([c - R * 0.26, c - R * 0.26, c + R * 0.26, c + R * 0.26], fill=255)


def text(t, size):
    def fn(d, w, h):
        f = ImageFont.truetype(FONT, int(size * 4))
        tw = d.textlength(t, font=f)
        asc, desc = f.getmetrics()
        d.text((w / 2 - tw / 2, h / 2 - (asc + desc) * 0.55), t, font=f, fill=255)
    return fn


def chance(d, w, h):
    # 기울어진 카드 + 가운데 뚫린 물음표
    c = w / 2
    card = Image.new("L", (w, h), 0)
    cd = ImageDraw.Draw(card)
    cw, ch = w * 0.56, h * 0.74
    cd.rounded_rectangle([c - cw / 2, c - ch / 2, c + cw / 2, c + ch / 2], radius=w * 0.07, fill=255)
    f = ImageFont.truetype(FONT, int(h * 0.5))
    tw = cd.textlength("?", font=f)
    asc, desc = f.getmetrics()
    cd.text((c - tw / 2, c - (asc + desc) * 0.52), "?", font=f, fill=0)
    card = card.rotate(-12, resample=Image.BICUBIC, center=(c, c))
    d._image.paste(card, (0, 0))


def minigame(d, w, h):
    # 게임 패드
    c = w / 2
    body = [w * 0.16, h * 0.34, w * 0.84, h * 0.66]
    d.rounded_rectangle(body, radius=h * 0.16, fill=255)
    for sx in (-1, 1):
        gx = c + sx * w * 0.24
        d.ellipse([gx - w * 0.15, h * 0.42, gx + w * 0.15, h * 0.76], fill=255)
    # 십자키 (뚫기)
    dx, dy, a, b = w * 0.31, h * 0.5, w * 0.085, w * 0.03
    d.rectangle([dx - a, dy - b, dx + a, dy + b], fill=0)
    d.rectangle([dx - b, dy - a, dx + b, dy + a], fill=0)
    # 버튼 두 개
    for bx, by in ((w * 0.66, h * 0.45), (w * 0.73, h * 0.55)):
        r = w * 0.04
        d.ellipse([bx - r, by - r, bx + r, by + r], fill=0)


def portal(d, w, h):
    # 소용돌이 (점을 촘촘히 찍어서 굵은 선)
    c = w / 2
    lw = w * 0.04
    for k in range(1400):
        t = k / 1399
        a = t * math.pi * 3.6
        r = w * (0.07 + 0.34 * t)
        x, y = c + math.cos(a) * r, c + math.sin(a) * r
        d.ellipse([x - lw, y - lw, x + lw, y + lw], fill=255)


def shop(d, w, h):
    # 쇼핑백 + 손잡이 + 가운데 뚫린 조개 동전
    c = w / 2
    d.polygon([(w * 0.22, h * 0.36), (w * 0.78, h * 0.36), (w * 0.84, h * 0.86), (w * 0.16, h * 0.86)], fill=255)
    d.arc([w * 0.34, h * 0.13, w * 0.66, h * 0.5], 180, 360, fill=255, width=int(w * 0.06))
    r = w * 0.13
    cy = h * 0.6
    d.ellipse([c - r, cy - r, c + r, cy + r], fill=0)
    r2 = w * 0.075
    d.ellipse([c - r2, cy - r2, c + r2, cy + r2], fill=255)


def blank(d, w, h):
    pass


def chance_card():
    # 공중에 떠서 도는 찬스 카드 그림 (색 있는 RGBA)
    w, h = 320, 440
    s = 3
    im = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w * s - 1, h * s - 1], radius=40 * s, fill=(250, 186, 52, 255))
    d.rounded_rectangle([16 * s, 16 * s, (w - 16) * s, (h - 16) * s], radius=28 * s, outline=(255, 248, 225, 255), width=10 * s)
    f = ImageFont.truetype(FONT, 250 * s)
    tw = d.textlength("?", font=f)
    asc, desc = f.getmetrics()
    d.text((w * s / 2 - tw / 2 + 6 * s, h * s / 2 - (asc + desc) * 0.5 + 8 * s), "?", font=f, fill=(176, 104, 18, 255))
    d.text((w * s / 2 - tw / 2, h * s / 2 - (asc + desc) * 0.5), "?", font=f, fill=(255, 250, 235, 255))
    im = im.resize((w, h), Image.LANCZOS)
    im.save(os.path.join(OUT, "card_chance.png"))


def border(d, w, h):
    m = w * 0.07
    d.rounded_rectangle([m, m, w - m, h - m], radius=w * 0.08, outline=255, width=int(w * 0.045))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make("plain", blank)
    make("chance", chance)
    make("minigame", minigame)
    make("portal", portal)
    make("shop", shop)
    make("arrows", arrows)
    make("start", text("START", 120), 512, 256)
    make("border", border)
    chance_card()
    print("icons ->", OUT)
