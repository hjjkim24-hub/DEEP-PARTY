"""바다 꾸미기 그림: 부채산호 (흰색 + 투명, 게임에서 색을 입힘).

    python make_decor.py  →  ../textures/decor/sea_fan.png
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "textures", "decor")


def sea_fan():
    W, H, S = 512, 512, 2
    im = Image.new("L", (W * S, H * S), 0)
    d = ImageDraw.Draw(im)
    rnd = random.Random(5)
    base = (W * S / 2, H * S * 0.97)
    ends = []

    def branch(p, ang, ln, wd, depth):
        q = (p[0] + math.cos(ang) * ln, p[1] - math.sin(ang) * ln)
        d.line([p, q], fill=255, width=max(2, int(wd)))
        if depth == 0:
            ends.append(q)
            return
        for da in (-0.32, 0.3):
            branch(q, ang + da + rnd.uniform(-0.12, 0.12), ln * rnd.uniform(0.72, 0.86), wd * 0.72, depth - 1)

    branch(base, math.pi / 2, H * S * 0.2, 16 * S, 6)
    # 그물 무늬: 가까운 끝끼리 잇고, 부채꼴 안쪽에 가는 선
    for _ in range(900):
        a = rnd.uniform(0.25, math.pi - 0.25)
        r0 = rnd.uniform(0.15, 0.9) * H * S * 0.85
        r1 = r0 + rnd.uniform(10, 40) * S
        a1 = a + rnd.uniform(-0.08, 0.08)
        p0 = (base[0] + math.cos(a) * r0, base[1] - math.sin(a) * r0)
        p1 = (base[0] + math.cos(a1) * r1, base[1] - math.sin(a1) * r1)
        d.line([p0, p1], fill=200, width=2 * S)
    for k in range(15):
        r = H * S * (0.22 + 0.042 * k)
        pts = []
        for t in range(60):
            a = 0.3 + (math.pi - 0.6) * t / 59
            rr = r * (1 + 0.02 * math.sin(t * 0.25 + k))
            pts.append((base[0] + math.cos(a) * rr, base[1] - math.sin(a) * rr))
        d.line(pts, fill=150, width=2 * S)
    # 부채 바깥은 잘라냄
    mask = Image.new("L", im.size, 0)
    md = ImageDraw.Draw(mask)
    R = H * S * 0.9
    md.pieslice([base[0] - R, base[1] - R, base[0] + R, base[1] + R], 180 + 14, 360 - 14, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(10 * S))
    im = Image.composite(im, Image.new("L", im.size, 0), mask)
    im = im.resize((W, H), Image.LANCZOS)
    out = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    out.putalpha(im)
    out.save(os.path.join(OUT, "sea_fan.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sea_fan()
    print("decor ->", OUT)
