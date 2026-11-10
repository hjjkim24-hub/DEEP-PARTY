"""나무 상점 화면 그림 (차양, 나무 벽, 계산대, 진열 칸, 간판, 가격표, 덧문, 나무 버튼).

    python make_shop_ui.py  →  ../textures/ui/shop/*.png
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "textures", "ui", "shop")
rnd = random.Random(3)

WOOD = (150, 96, 56)
WOOD_D = (104, 62, 34)
WOOD_L = (190, 132, 82)


def grain(im, box, base, vertical=True, seed=0):
    """나뭇결 판자 하나"""
    r = random.Random(seed)
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = box
    d.rectangle(box, fill=base)
    ln = (y1 - y0) if vertical else (x1 - x0)
    wd = (x1 - x0) if vertical else (y1 - y0)
    for k in range(int(wd / 3)):
        off = r.uniform(0, wd)
        g = r.uniform(0.82, 1.08)
        col = tuple(max(0, min(255, int(c * g))) for c in base)
        pts = []
        ph = r.uniform(0, 6.28)
        amp = r.uniform(1, 4)
        for t in range(0, int(ln) + 8, 8):
            w = off + math.sin(t * 0.02 + ph) * amp
            pts.append((x0 + w, y0 + t) if vertical else (x0 + t, y0 + w))
        d.line(pts, fill=col, width=r.choice([1, 1, 2]))
    # 옹이
    for k in range(r.randint(0, 2)):
        cx = r.uniform(x0 + 10, x1 - 10)
        cy = r.uniform(y0 + 10, y1 - 10)
        rr = r.uniform(4, 9)
        d.ellipse([cx - rr * (0.6 if vertical else 1.4), cy - rr * (1.4 if vertical else 0.6),
                   cx + rr * (0.6 if vertical else 1.4), cy + rr * (1.4 if vertical else 0.6)], fill=WOOD_D)
    # 테두리 그림자
    d.rectangle(box, outline=tuple(int(c * 0.6) for c in base), width=3)
    d.line([(x0 + 3, y0 + 3), (x0 + 3, y1 - 3)] if vertical else [(x0 + 3, y0 + 3), (x1 - 3, y0 + 3)],
           fill=tuple(min(255, int(c * 1.18)) for c in base), width=2)


def nail(d, x, y):
    d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(70, 62, 58))
    d.ellipse([x - 3, y - 4, x + 1, y], fill=(160, 150, 140))


def wall(w=1100, h=560):
    im = Image.new("RGBA", (w, h), WOOD)
    pw = 92
    x = 0
    k = 0
    while x < w:
        f = rnd.uniform(0.88, 1.08)
        base = tuple(max(0, min(255, int(c * f))) for c in WOOD)
        grain(im, (x, 0, min(w, x + pw), h), base, True, k)
        d = ImageDraw.Draw(im)
        for y in (24, h - 24):
            nail(d, x + pw / 2, y)
        x += pw
        k += 1
    # 가로 받침목
    d = ImageDraw.Draw(im)
    for y in (h * 0.55,):
        grain(im, (0, int(y), w, int(y) + 34), WOOD_D, False, 99)
    # 가장자리 어둡게
    sh = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(sh)
    sd.rectangle([0, 0, w, h], fill=90)
    sd.rectangle([40, 30, w - 40, h - 20], fill=0)
    sh = sh.filter(ImageFilter.GaussianBlur(30))
    im = Image.composite(Image.new("RGBA", (w, h), (40, 22, 10, 255)), im, sh)
    return im


def awning(w=1240, h=210):
    S = 2
    im = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    n = 12
    sw = w * S / n
    body = h * S * 0.62
    for k in range(n):
        col = (240, 108, 140) if k % 2 == 0 else (255, 244, 230)
        x0 = k * sw
        d.rectangle([x0, 0, x0 + sw, body], fill=col)
        d.pieslice([x0, body - sw * 0.5, x0 + sw, body + sw * 0.5], 0, 180, fill=col)
        # 주름 그림자
        d.rectangle([x0 + sw * 0.82, 0, x0 + sw, body], fill=tuple(int(c * 0.88) for c in col))
    # 위쪽 막대
    d.rounded_rectangle([0, 0, w * S, h * S * 0.12], radius=10 * S, fill=(126, 76, 40))
    d.rectangle([0, h * S * 0.09, w * S, h * S * 0.12], fill=(90, 52, 26))
    im = im.resize((w, h), Image.LANCZOS)
    return im


def counter(w=1180, h=180):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    top = 34
    grain(im, (0, 0, w, top), WOOD_L, False, 7)
    y = top
    k = 0
    while y < h:
        hh = min(48, h - y)
        grain(im, (16, y, w - 16, y + hh), tuple(int(c * rnd.uniform(0.86, 0.98)) for c in WOOD), False, 20 + k)
        y += hh
        k += 1
    d = ImageDraw.Draw(im)
    for x in (40, w - 40):
        for yy in range(top + 20, h, 48):
            nail(d, x, yy)
    return im


def slot(w=230, h=250):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    grain(im, (0, 0, w, h), WOOD_L, True, 41)
    d = ImageDraw.Draw(im)
    d.rectangle([18, 18, w - 18, h - 18], fill=(70, 40, 20))
    # 안쪽 그림자
    inner = Image.new("L", (w, h), 0)
    idr = ImageDraw.Draw(inner)
    idr.rectangle([18, 18, w - 18, h - 18], fill=255)
    idr.rectangle([34, 40, w - 30, h - 24], fill=0)
    inner = inner.filter(ImageFilter.GaussianBlur(12))
    im = Image.composite(Image.new("RGBA", (w, h), (40, 22, 10, 255)), im, inner)
    d = ImageDraw.Draw(im)
    for x, y in ((9, 9), (w - 9, 9), (9, h - 9), (w - 9, h - 9)):
        nail(d, x, y)
    return im


def sign(w=440, h=190):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # 밧줄
    for x in (w * 0.24, w * 0.76):
        d.line([(x, 0), (x, h * 0.32)], fill=(200, 170, 110), width=6)
    board = Image.new("RGBA", (w, int(h * 0.72)), (0, 0, 0, 0))
    grain(board, (0, 0, w, board.height), (122, 74, 40), False, 55)
    mask = Image.new("L", board.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, board.height - 1], radius=26, fill=255)
    im.paste(board, (0, int(h * 0.28)), mask)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([10, int(h * 0.28) + 10, w - 10, h - 10], radius=20, outline=(236, 196, 120), width=5)
    for x in (w * 0.24, w * 0.76):
        nail(d, x, h * 0.34)
    return im


def tag(w=150, h=64):
    S = 3
    im = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(0, h * S * 0.5), (h * S * 0.35, 0), (w * S, 0), (w * S, h * S), (h * S * 0.35, h * S)], fill=(255, 241, 206))
    d.ellipse([h * S * 0.22, h * S * 0.38, h * S * 0.42, h * S * 0.62], fill=(150, 110, 60))
    d.line([(h * S * 0.35, 3 * S), (w * S - 3 * S, 3 * S)], fill=(235, 210, 160), width=2 * S)
    return im.resize((w, h), Image.LANCZOS)


def shutter(w=560, h=560):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = 0
    k = 0
    while y < h:
        hh = min(46, h - y)
        grain(im, (0, y, w, y + hh), tuple(int(c * rnd.uniform(0.8, 0.92)) for c in WOOD), False, 70 + k)
        y += hh
        k += 1
    d = ImageDraw.Draw(im)
    # 대각선 받침목 + 손잡이
    grain(im, (0, 0, 40, h), WOOD_D, True, 81)
    grain(im, (w - 40, 0, w, h), WOOD_D, True, 82)
    d.ellipse([w - 90, h / 2 - 22, w - 46, h / 2 + 22], fill=(220, 170, 70))
    d.ellipse([w - 82, h / 2 - 14, w - 54, h / 2 + 14], fill=(170, 120, 40))
    return im


def button(w=280, h=86):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    plank = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    grain(plank, (0, 0, w, h), WOOD_L, False, 91)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=22, fill=255)
    im.paste(plank, (0, 0), mask)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([5, 5, w - 6, h - 6], radius=18, outline=(255, 226, 170), width=3)
    for x in (20, w - 20):
        nail(d, x, h / 2)
    return im


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    wall().save(os.path.join(OUT, "wall.png"))
    awning().save(os.path.join(OUT, "awning.png"))
    counter().save(os.path.join(OUT, "counter.png"))
    slot().save(os.path.join(OUT, "slot.png"))
    sign().save(os.path.join(OUT, "sign.png"))
    tag().save(os.path.join(OUT, "tag.png"))
    shutter().save(os.path.join(OUT, "shutter.png"))
    button().save(os.path.join(OUT, "button.png"))
    print("shop ui ->", OUT)
