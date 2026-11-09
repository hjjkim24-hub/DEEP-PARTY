# 보드판 윗면 인쇄 그림 만들기 (항해 지도 스타일, 오래된 종이 질감)
# 사용법: python make_board_print.py  ->  tools/out/board_print.png (2048x2048)
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out"); os.makedirs(OUT, exist_ok=True)
FONT = os.path.join(HERE, "..", "fonts", "Poppins-Bold.ttf")
N = 4096  # 그린 뒤 2048로 줄여서 매끈하게
rng = np.random.default_rng(7)

def U(v): return v * N

def value_noise(shape, scale, seed):
    r = np.random.default_rng(seed)
    gh, gw = int(shape[0] / scale) + 2, int(shape[1] / scale) + 2
    g = r.random((gh, gw)).astype(np.float32)
    im = Image.fromarray((g * 255).astype(np.uint8)).resize((shape[1], shape[0]), Image.BICUBIC)
    return np.asarray(im).astype(np.float32) / 255

def fbm(shape, base, seed, octaves=4):
    acc = np.zeros(shape, np.float32); amp = 1.0; tot = 0
    for o in range(octaves):
        acc += value_noise(shape, base / (2 ** o), seed + o) * amp; tot += amp; amp *= 0.5
    return acc / tot

# ---------------------------------------------------------------- 바탕: 종이
paper = np.zeros((N, N, 3), np.float32)
paper[:] = np.array([0.86, 0.80, 0.66])
n1 = fbm((N, N), 600, 1)
paper *= (0.92 + 0.12 * n1)[..., None]
img = Image.fromarray((paper.clip(0, 1) * 255).astype(np.uint8))
d = ImageDraw.Draw(img, "RGBA")

# ---------------------------------------------------------------- 바다 영역 (안쪽)
M = 0.075
d.rectangle([U(M), U(M), U(1 - M), U(1 - M)], fill=(40, 86, 122, 255))
# 물결 무늬 (얇은 선)
for k in range(140):
    y = U(M) + (k + 0.5) * (U(1 - 2 * M) / 140)
    pts = []
    for x in np.linspace(U(M), U(1 - M), 200):
        pts.append((x, y + math.sin(x / 90 + k * 0.7) * 10 + math.sin(x / 31 + k) * 3))
    if k % 3 == 0:
        d.line(pts, fill=(28, 64, 98, 160), width=3)

# ---------------------------------------------------------------- 섬
def blob(cx, cy, r, seed, n=90):
    rr = np.random.default_rng(seed); ph = rr.random(4) * 6.28
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        k = 1 + 0.16 * math.sin(3 * a + ph[0]) + 0.09 * math.sin(5 * a + ph[1]) + 0.05 * math.sin(9 * a + ph[2])
        pts.append((U(cx) + math.cos(a) * U(r) * k, U(cy) + math.sin(a) * U(r) * k))
    return pts

islands = [(0.27, 0.27, 0.13, 3), (0.73, 0.26, 0.12, 5), (0.26, 0.74, 0.12, 8), (0.74, 0.73, 0.13, 11), (0.5, 0.5, 0.16, 2)]
for cx, cy, r, s in islands:
    for j, (scale, col) in enumerate([(1.18, (58, 112, 140, 255)), (1.09, (82, 140, 156, 255))]):
        d.polygon(blob(cx, cy, r * scale, s), fill=col)
    d.polygon(blob(cx, cy, r, s), fill=(226, 192, 120, 255))
    d.line(blob(cx, cy, r, s) + [blob(cx, cy, r, s)[0]], fill=(150, 120, 80, 255), width=6)
    d.polygon(blob(cx, cy, r * 0.72, s + 1), fill=(104, 150, 62, 255))
    d.polygon(blob(cx, cy, r * 0.45, s + 2), fill=(76, 120, 46, 255))

# 작은 나무 그림 (지도 기호)
for cx, cy, r, s in islands[:4]:
    rr = np.random.default_rng(s + 50)
    for t in range(7):
        a = rr.random() * 6.28; dd = rr.random() * r * 0.55
        x, y = U(cx + math.cos(a) * dd), U(cy + math.sin(a) * dd)
        d.polygon([(x - 26, y + 18), (x + 26, y + 18), (x, y - 40)], fill=(78, 110, 62, 255))
        d.line([(x, y + 18), (x, y + 32)], fill=(100, 70, 45, 255), width=8)

# ---------------------------------------------------------------- 칸이 있는 길
CP = [(-0.66, 0.68), (-0.2, 0.74), (0.25, 0.58), (0.68, 0.70), (0.74, 0.25), (0.46, -0.02), (0.70, -0.38), (0.58, -0.72),
      (0.12, -0.66), (-0.28, -0.46), (-0.68, -0.68), (-0.76, -0.22), (-0.46, 0.08), (-0.74, 0.38)]
def cubic(p0, p1, p2, p3, t):
    return tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t * t + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t ** 3) for k in range(2))
path = []
for i in range(len(CP)):
    for s in range(60):
        q = cubic(CP[i - 1], CP[i], CP[(i + 1) % len(CP)], CP[(i + 2) % len(CP)], s / 60)
        path.append((0.5 + q[0] * 0.5 * 0.86, 0.5 + q[1] * 0.5 * 0.86))
# 길 바탕 점선
d.line([(U(x), U(y)) for x, y in path + [path[0]]], fill=(120, 90, 60, 160), width=90, joint="curve")
d.line([(U(x), U(y)) for x, y in path + [path[0]]], fill=(236, 224, 196, 255), width=78, joint="curve")

L = [0.0]
for i in range(len(path)):
    L.append(L[-1] + math.dist(path[i], path[(i + 1) % len(path)]))
COUNT = 40
KINDS = [5, 0, 0, 1, 0, 3, 0, 2, 0, 0, 4, 0, 1, 0, 3, 0, 0, 2, 0, 1, 0, 0, 3, 0, 4, 0, 1, 0, 2, 0, 0, 3, 0, 1, 0, 2, 0, 0, 3, 0]
COLS = [(47, 95, 143), (163, 71, 61), (79, 127, 69), (106, 79, 134), (199, 154, 53), (31, 47, 79)]
font_icon = ImageFont.truetype(FONT, 78)
font_start = ImageFont.truetype(FONT, 44)
seg = 0
for k in range(COUNT):
    tg = L[-1] * k / COUNT
    while seg < len(path) - 1 and L[seg + 1] < tg: seg += 1
    a, b = path[seg], path[(seg + 1) % len(path)]
    f = (tg - L[seg]) / max(1e-9, L[seg + 1] - L[seg])
    x, y = U(a[0] + (b[0] - a[0]) * f), U(a[1] + (b[1] - a[1]) * f)
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    kind = KINDS[k]
    size = 64 if kind != 5 else 86
    tile = Image.new("RGBA", (300, 300), (0, 0, 0, 0)); td = ImageDraw.Draw(tile)
    td.rounded_rectangle([150 - size - 6, 150 - size - 6 + 8, 150 + size + 6, 150 + size + 6 + 8], radius=26, fill=(60, 45, 30, 110))
    td.rounded_rectangle([150 - size - 6, 150 - size - 6, 150 + size + 6, 150 + size + 6], radius=26, fill=(40, 34, 28, 255))
    td.rounded_rectangle([150 - size, 150 - size, 150 + size, 150 + size], radius=20, fill=COLS[kind] + (255,))
    td.rounded_rectangle([150 - size + 10, 150 - size + 10, 150 + size - 10, 150 + size - 10], radius=14, outline=(255, 245, 220, 140), width=4)
    ic = (247, 238, 214, 255)
    if kind == 0:
        td.rectangle([150 - 26, 150 - 7, 150 + 26, 150 + 7], fill=ic); td.rectangle([150 - 7, 150 - 26, 150 + 7, 150 + 26], fill=ic)
    elif kind == 1:
        td.rectangle([150 - 26, 150 - 7, 150 + 26, 150 + 7], fill=ic)
    elif kind == 2:
        td.text((150, 152), "!", font=font_icon, anchor="mm", fill=ic)
    elif kind == 3:
        td.text((150, 152), "?", font=font_icon, anchor="mm", fill=ic)
    elif kind == 4:
        st = [(150 + math.cos(-math.pi / 2 + math.pi * i / 5) * (36 if i % 2 == 0 else 15), 150 + math.sin(-math.pi / 2 + math.pi * i / 5) * (36 if i % 2 == 0 else 15)) for i in range(10)]
        td.polygon(st, fill=ic)
    elif kind == 5:
        td.text((150, 152), "START", font=font_start, anchor="mm", fill=(230, 196, 110, 255))
    if math.cos(ang) < 0:  # 글자가 거꾸로 보이지 않게
        ang += math.pi
    tile = tile.rotate(-math.degrees(ang), resample=Image.BICUBIC)
    img.paste(tile, (int(x - 150), int(y - 150)), tile)

# ---------------------------------------------------------------- 가운데 나침반 + 제목 리본
d = ImageDraw.Draw(img, "RGBA")
cx, cy = U(0.5), U(0.5)
for r, col in [(330, (40, 34, 28, 255)), (318, (226, 211, 170, 255)), (285, (31, 47, 79, 255)), (272, (226, 211, 170, 255))]:
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
for i in range(32):
    a = 2 * math.pi * i / 32
    r0, r1 = (240, 272) if i % 4 == 0 else (256, 272)
    d.line([(cx + math.cos(a) * r0, cy + math.sin(a) * r0), (cx + math.cos(a) * r1, cy + math.sin(a) * r1)], fill=(31, 47, 79, 255), width=6)
for i in range(8):
    a = -math.pi / 2 + i * math.pi / 4
    ln = 230 if i % 2 == 0 else 150
    w = 44 if i % 2 == 0 else 30
    tip = (cx + math.cos(a) * ln, cy + math.sin(a) * ln)
    l = (cx + math.cos(a + math.pi / 2) * w, cy + math.sin(a + math.pi / 2) * w)
    r_ = (cx + math.cos(a - math.pi / 2) * w, cy + math.sin(a - math.pi / 2) * w)
    d.polygon([tip, l, (cx, cy)], fill=(31, 47, 79, 255) if i % 2 == 0 else (163, 71, 61, 255))
    d.polygon([tip, r_, (cx, cy)], fill=(199, 154, 53, 255) if i % 2 == 0 else (120, 52, 45, 255))
d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], fill=(226, 211, 170, 255), outline=(31, 47, 79, 255), width=6)
fN = ImageFont.truetype(FONT, 70)
d.text((cx, cy - 290), "N", font=fN, anchor="mm", fill=(31, 47, 79, 255))
# 리본
rb_y = cy + 400
d.polygon([(cx - 560, rb_y - 70), (cx - 470, rb_y - 70), (cx - 470, rb_y + 70), (cx - 560, rb_y + 70), (cx - 520, rb_y)], fill=(120, 52, 45, 255))
d.polygon([(cx + 560, rb_y - 70), (cx + 470, rb_y - 70), (cx + 470, rb_y + 70), (cx + 560, rb_y + 70), (cx + 520, rb_y)], fill=(120, 52, 45, 255))
d.rounded_rectangle([cx - 480, rb_y - 88, cx + 480, rb_y + 88], radius=18, fill=(163, 71, 61, 255), outline=(40, 34, 28, 255), width=8)
d.line([(cx - 450, rb_y - 62), (cx + 450, rb_y - 62)], fill=(230, 196, 110, 255), width=5)
d.line([(cx - 450, rb_y + 62), (cx + 450, rb_y + 62)], fill=(230, 196, 110, 255), width=5)
fT = ImageFont.truetype(FONT, 118)
d.text((cx, rb_y + 6), "DEEP PARTY", font=fT, anchor="mm", fill=(246, 232, 196, 255))

# ---------------------------------------------------------------- 테두리 (남색 띠 + 금색 선 + 모서리 장식)
d.rectangle([0, 0, N, U(0.06)], fill=(31, 47, 79, 255)); d.rectangle([0, U(0.94), N, N], fill=(31, 47, 79, 255))
d.rectangle([0, 0, U(0.06), N], fill=(31, 47, 79, 255)); d.rectangle([U(0.94), 0, N, N], fill=(31, 47, 79, 255))
for inset, w in [(0.045, 10), (0.055, 4), (0.066, 6)]:
    d.rectangle([U(inset), U(inset), U(1 - inset), U(1 - inset)], outline=(199, 160, 72, 255), width=w)
for sx in (0, 1):
    for sy in (0, 1):
        x = U(0.03) if sx == 0 else U(0.97); y = U(0.03) if sy == 0 else U(0.97)
        st = [(x + math.cos(-math.pi / 2 + math.pi * i / 5) * (70 if i % 2 == 0 else 28), y + math.sin(-math.pi / 2 + math.pi * i / 5) * (70 if i % 2 == 0 else 28)) for i in range(10)]
        d.polygon(st, fill=(199, 160, 72, 255))
fB = ImageFont.truetype(FONT, 92)
d.text((U(0.5), U(0.97) + 4), "DEEP PARTY  •  A MINIGAME BOARD GAME FOR 1-4 PLAYERS", font=fB, anchor="mm", fill=(199, 160, 72, 255))

# ---------------------------------------------------------------- 낡은 느낌 (얼룩, 긁힘, 가장자리 바램)
arr = np.asarray(img).astype(np.float32) / 255
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) / N
grain = fbm((N, N), 30, 21, 2)
arr *= (0.94 + 0.08 * grain)[..., None]
stain = fbm((N, N), 900, 33, 3)
arr *= (1 - 0.18 * np.clip((stain - 0.55) * 4, 0, 1))[..., None]
edge = np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy))
arr *= (0.82 + 0.18 * np.clip(edge / 0.08, 0, 1))[..., None]
fade = fbm((N, N), 300, 44, 3)
arr = arr * (1 - 0.06 * fade[..., None]) + np.array([0.85, 0.80, 0.68]) * 0.06 * fade[..., None]
img = Image.fromarray((arr.clip(0, 1) * 255).astype(np.uint8))
d = ImageDraw.Draw(img, "RGBA")
for i in range(260):
    x, y = rng.random() * N, rng.random() * N; a = rng.random() * 6.28; l = rng.random() * 160 + 30
    d.line([(x, y), (x + math.cos(a) * l, y + math.sin(a) * l)], fill=(255, 250, 235, int(rng.random() * 60 + 20)), width=2)
for i in range(5):
    x, y, r = rng.random() * N, rng.random() * N, rng.random() * 220 + 120
    d.ellipse([x - r, y - r, x + r, y + r], outline=(110, 85, 50, 45), width=10)

img = img.resize((2048, 2048), Image.LANCZOS)
img.save(os.path.join(OUT, "board_print.png"))
print("saved")
