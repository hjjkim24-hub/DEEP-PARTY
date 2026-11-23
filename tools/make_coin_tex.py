"""금화 앞면(양각) 텍스처: 높이맵 → 노멀맵 + 금 · 녹슨 동전 색 (오목한 곳은 어둡게 때가 낌)
python3 tools/make_coin_tex.py  → textures/models/coin_*.png"""
import math, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
import numpy as np

S = 1024
C = S / 2
OUT = "textures/models/"
font = ImageFont.truetype("fonts/Almendra-Bold.ttf", 74)

h = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(h)
# 바깥 테 (가장 높음)
d.ellipse([8, 8, S - 8, S - 8], fill=235)
d.ellipse([58, 58, S - 58, S - 58], fill=70)
# 구슬 테
for k in range(72):
    a = 2 * math.pi * k / 72
    x, y = C + math.cos(a) * 410, C + math.sin(a) * 410
    d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=200)
d.ellipse([C - 388, C - 388, C + 388, C + 388], outline=190, width=6)
# 둘레 글자: 원을 따라 한 글자씩
def ring_text(txt, radius, start_deg, span_deg, flip=False):
    n = len(txt)
    for i, ch in enumerate(txt):
        t = (i + 0.5) / n
        ang = math.radians(start_deg + span_deg * t)
        g = Image.new("L", (110, 110), 0)
        ImageDraw.Draw(g).text((55, 55), ch, font=font, fill=215, anchor="mm")
        rot = -math.degrees(ang) - 90 if not flip else -math.degrees(ang) + 90
        g = g.rotate(rot, resample=Image.BICUBIC)
        x = C + math.cos(ang) * radius
        y = C + math.sin(ang) * radius
        h.paste(ImageChops.lighter(h.crop((int(x) - 55, int(y) - 55, int(x) + 55, int(y) + 55)), g), (int(x) - 55, int(y) - 55))
ring_text("DEEP PARTY", 330, 200, 140)
ring_text("SUNKEN ISLAND", 330, 145, -110, flip=True)
for a in (182, 358):
    r = math.radians(a)
    x, y = C + math.cos(r) * 330, C + math.sin(r) * 330
    d.regular_polygon((x, y, 16), 4, fill=210)
# 가운데 닻 (두껍게 그린 뒤 흐려서 둥근 양각)
an = Image.new("L", (S, S), 0)
ad = ImageDraw.Draw(an)
W = 34
ad.line([(C, C - 205), (C, C + 175)], fill=255, width=W)            # 기둥
ad.ellipse([C - 52, C - 280, C + 52, C - 176], outline=255, width=26)  # 고리
ad.line([(C - 120, C - 140), (C + 120, C - 140)], fill=255, width=28)  # 가로대
for sx in (-1, 1):
    ad.ellipse([C + sx * 120 - 20, C - 160, C + sx * 120 + 20, C - 120], fill=255)
ad.arc([C - 190, C - 60, C + 190, C + 205], 20, 160, fill=255, width=W)   # 팔
for sx in (-1, 1):  # 갈고리 끝
    x = C + sx * 180
    y = C + 100
    ad.polygon([(x - sx * 10, y - 70), (x + sx * 44, y - 70), (x - sx * 8, y + 14)], fill=255)
ad.polygon([(C - 30, C + 170), (C + 30, C + 170), (C, C + 215)], fill=255)
an = an.filter(ImageFilter.GaussianBlur(5))
h = ImageChops.lighter(h, an.point(lambda v: int(v * 0.9)))
# 밧줄 감김
ro = Image.new("L", (S, S), 0)
rd = ImageDraw.Draw(ro)
pts = []
for k in range(120):
    t = k / 119
    y = C - 170 + t * 330
    x = C + math.sin(t * math.pi * 3.2) * (60 + 60 * t)
    pts.append((x, y))
rd.line(pts, fill=255, width=14, joint="curve")
ro = ro.filter(ImageFilter.GaussianBlur(3))
h = ImageChops.lighter(h, ro.point(lambda v: int(v * 0.98)))
h = h.filter(ImageFilter.GaussianBlur(2.2))
# 바닥면 미세한 긁힘 · 마모
rng = random.Random(7)
sc = Image.new("L", (S, S), 0)
sd = ImageDraw.Draw(sc)
for k in range(260):
    x, y = rng.uniform(80, S - 80), rng.uniform(80, S - 80)
    a = rng.uniform(0, math.pi)
    L = rng.uniform(10, 70)
    sd.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], fill=rng.randint(10, 30), width=1)
H = np.asarray(h, dtype=np.float32) / 255.0 - np.asarray(sc, dtype=np.float32) / 255.0 * 0.6
H += np.asarray(Image.effect_noise((S, S), 40).filter(ImageFilter.GaussianBlur(1.5)), dtype=np.float32) / 255.0 * 0.03
# 노멀맵
gy, gx = np.gradient(H)
k = 9.0
nx, ny, nz = -gx * k, -gy * k, np.ones_like(H)
L = np.sqrt(nx * nx + ny * ny + nz * nz)
nrm = np.stack([(nx / L) * 0.5 + 0.5, (-ny / L) * 0.5 + 0.5, (nz / L) * 0.5 + 0.5], -1)  # OpenGL(+Y) 방식
Image.fromarray((nrm * 255).astype(np.uint8)).save(OUT + "coin_normal.png")
# 오목한 곳(캐비티) = 주변보다 낮은 곳 → 때 · 그을음
blur = np.asarray(Image.fromarray((np.clip(H, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10)), dtype=np.float32) / 255.0
cav = np.clip((blur - H) * 6.0, 0, 1)
top = np.clip((H - blur) * 5.0, 0, 1)   # 볼록한 곳은 닳아 반짝
mott = np.asarray(Image.effect_noise((S, S), 60).filter(ImageFilter.GaussianBlur(8)), dtype=np.float32) / 255.0


def paint(base, dirt, shine, name, rough_base, extra=None):
    col = np.ones((S, S, 3), np.float32) * np.array(base, np.float32)
    col *= (0.88 + 0.24 * mott)[..., None]
    col = col * (1 - cav[..., None] * 0.75) + np.array(dirt, np.float32) * cav[..., None] * 0.75
    col = col * (1 - top[..., None] * 0.5) + np.array(shine, np.float32) * top[..., None] * 0.5
    if extra is not None:
        col = extra(col)
    Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(OUT + "coin_%s_albedo.png" % name)
    rough = np.clip(rough_base + cav * 0.45 - top * 0.15 + (mott - 0.5) * 0.12, 0.05, 1)
    Image.fromarray((rough * 255).astype(np.uint8)).save(OUT + "coin_%s_rough.png" % name)


paint((1.0, 0.76, 0.33), (0.32, 0.2, 0.07), (1.0, 0.92, 0.62), "gold", 0.22)
# 저주받은 동전: 검게 그을린 쇠 + 붉은 녹 · 푸른 녹청이 오목한 곳에
rn = np.asarray(Image.effect_noise((S, S), 90).filter(ImageFilter.GaussianBlur(14)), dtype=np.float32) / 255.0
def cursed(col):
    rust = np.clip((rn - 0.5) * 4, 0, 1)[..., None]
    col = col * (1 - rust * 0.7) + np.array([0.42, 0.17, 0.07]) * rust * 0.7
    ver = np.clip(cav * 1.4, 0, 1)[..., None] * np.clip((0.55 - rn) * 3, 0, 1)[..., None]
    return col * (1 - ver * 0.6) + np.array([0.22, 0.42, 0.36]) * ver * 0.6
paint((0.2, 0.19, 0.18), (0.05, 0.04, 0.035), (0.42, 0.4, 0.37), "bad", 0.6, cursed)
print("coin textures ok")
