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


def border(d, w, h):
    m = w * 0.07
    d.rounded_rectangle([m, m, w - m, h - m], radius=w * 0.08, outline=255, width=int(w * 0.045))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make("pearl", pearl)
    make("urchin", urchin)
    make("star", star)
    make("arrows", arrows)
    make("event", text("?", 200))
    make("start", text("START", 120), 512, 256)
    make("border", border)
    print("icons ->", OUT)
