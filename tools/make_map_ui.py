"""미니게임 소개 화면을 '보물지도' 처럼: 오래된 양피지(태운 가장자리·접힌 자국·얼룩·좀 슨 점),
잉크 나침반, 밀랍 봉인, 붉은 도장 테두리, 낡은 나무 액자(황동 모서리), 붉은 천 리본.
    python3 tools/make_map_ui.py  →  textures/ui/map/*.png"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_shop_ui import fbm, to_img, wood, bevel, scratches  # noqa: E402

OUT = os.path.join(os.path.dirname(HERE), "textures", "ui", "map")
os.makedirs(OUT, exist_ok=True)
FONT = os.path.join(os.path.dirname(HERE), "fonts", "PirataOne-Regular.ttf")


def parchment(w, h, seed, burn=60, folds=True):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    base = np.array([226, 200, 150], np.float32)
    n1 = fbm(h, w, h / 160, w / 160, seed, 5)
    n2 = fbm(h, w, h / 40, w / 40, seed + 3, 4)
    col = base[None, None, :] * (0.82 + 0.3 * n1[..., None]) * (0.95 + 0.08 * n2[..., None])
    # 누렇게 바랜 얼룩 · 커피 자국 고리
    for _ in range(int(w * h / 90000) + 3):
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(30, 140)
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
        warp = fbm(h, w, h / 50, w / 50, int(rng.integers(1000)), 2) * 0.5
        blob = np.exp(-((d + warp) ** 2) * 2.0)
        ring = np.exp(-((d + warp - 1.0) / 0.06) ** 2) * 0.6
        k = rng.uniform(0.05, 0.16)
        col *= (1 - (blob * 0.6 + ring) * k)[..., None]
        col[..., 2] *= (1 - blob * k * 0.6)
    # 섬유 결
    fib = ndimage.gaussian_filter(rng.standard_normal((h, w)), (0.6, 3.0))
    col *= (1 + fib * 0.05)[..., None]
    # 좀 슨 점 (갈색 반점)
    for _ in range(int(w * h / 6000)):
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(0.8, 3.5)
        d = np.sqrt((xx[int(max(cy - 6, 0)):int(cy + 7), int(max(cx - 6, 0)):int(cx + 7)] - cx) ** 2 +
                    (yy[int(max(cy - 6, 0)):int(cy + 7), int(max(cx - 6, 0)):int(cx + 7)] - cy) ** 2)
        m = np.clip(1 - d / r, 0, 1) * rng.uniform(0.2, 0.5)
        sl = col[int(max(cy - 6, 0)):int(cy + 7), int(max(cx - 6, 0)):int(cx + 7)]
        sl *= (1 - m[..., None] * np.array([0.35, 0.5, 0.7]))
    # 접힌 자국
    if folds:
        for fx in [w * 0.5]:
            d = xx - fx - fbm(h, w, h / 80, 2, seed + 8, 2) * 6
            col *= (1 - 0.16 * np.exp(-(d / 2.0) ** 2) + 0.06 * np.exp(-((d - 4) / 3.0) ** 2))[..., None]
        for fy in [h * 0.5]:
            d = yy - fy - fbm(h, w, 2, w / 80, seed + 9, 2) * 6
            col *= (1 - 0.13 * np.exp(-(d / 2.0) ** 2) + 0.05 * np.exp(-((d - 4) / 3.0) ** 2))[..., None]
    # 태운 가장자리: 안쪽으로 갈수록 갈색 → 검게 그을림 → 뜯겨 나감
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float32)
    rough = fbm(h, w, h / 30, w / 30, seed + 21, 4) * burn * 0.9 + fbm(h, w, h / 8, w / 8, seed + 22, 3) * burn * 0.25
    e = edge - rough * 0.55
    alpha = np.clip((e - 2) / 2.5, 0, 1)
    scorch = np.clip(1 - (e - 2) / (burn * 0.45), 0, 1) ** 1.6
    col = col * (1 - scorch[..., None] * 0.85) + np.array([40, 22, 8], np.float32) * scorch[..., None] * 0.85
    brown = np.clip(1 - (e - 2) / (burn * 1.4), 0, 1) ** 2
    col *= (1 - brown * 0.35)[..., None]
    col[..., 2] *= (1 - brown * 0.2)
    return to_img(col, alpha * 255)


def compass(size=520):
    S = size * 3
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    ink = (70, 38, 16, 230)
    red = (140, 32, 20, 230)
    for r, wdt in [(0.47, 6), (0.44, 3), (0.30, 3)]:
        d.ellipse([c - S * r, c - S * r, c + S * r, c + S * r], outline=ink, width=wdt)
    for k in range(64):
        a = k / 64 * math.tau
        r0 = S * (0.44 if k % 4 else 0.41)
        d.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * S * 0.47, c + math.sin(a) * S * 0.47)], fill=ink, width=3)
    def point(a, length, width, fill_a, fill_b):
        tip = (c + math.cos(a) * length, c + math.sin(a) * length)
        l = (c + math.cos(a - math.pi / 2) * width, c + math.sin(a - math.pi / 2) * width)
        r = (c + math.cos(a + math.pi / 2) * width, c + math.sin(a + math.pi / 2) * width)
        d.polygon([tip, l, (c, c)], fill=fill_a, outline=ink)
        d.polygon([tip, r, (c, c)], fill=fill_b, outline=ink)
    for k in range(8):
        a = k / 8 * math.tau + math.pi / 8
        point(a, S * 0.26, S * 0.035, (190, 160, 110, 220), ink)
    for k in range(4):
        a = k / 4 * math.tau + math.pi / 4
        point(a, S * 0.33, S * 0.05, (205, 175, 120, 230), ink)
    for k in range(4):
        a = k / 4 * math.tau - math.pi / 2
        point(a, S * 0.43, S * 0.07, red if k == 0 else (215, 185, 130, 240), ink)
    d.ellipse([c - S * 0.03, c - S * 0.03, c + S * 0.03, c + S * 0.03], fill=ink)
    f = ImageFont.truetype(FONT, int(S * 0.09))
    for txt, a in [("N", -90), ("E", 0), ("S", 90), ("W", 180)]:
        x = c + math.cos(math.radians(a)) * S * 0.375
        y = c + math.sin(math.radians(a)) * S * 0.375
        d.text((x, y), txt, font=f, fill=red if txt == "N" else ink, anchor="mm")
    img = img.resize((size, size), Image.LANCZOS)
    # 바랜 잉크 (군데군데 옅게)
    a = np.asarray(img).astype(np.float32)
    fade = 0.65 + 0.35 * fbm(size, size, 8, 8, 5, 3)
    a[..., 3] *= fade
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def wax_seal(size=200):
    """회색 밀랍 봉인 (게임에서 플레이어 색으로 물들임). 가운데 닻 무늬가 눌려 있음"""
    S = size
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    c = S / 2
    ang = np.arctan2(yy - c, xx - c)
    rad = np.sqrt((xx - c) ** 2 + (yy - c) ** 2)
    rng = np.random.default_rng(4)
    wob = sum(np.sin(ang * k + rng.uniform(0, 6)) * rng.uniform(1, 4) for k in range(3, 9))
    edge = S * 0.42 + wob
    mask = np.clip((edge - rad) / 2.0, 0, 1)
    h = np.clip((edge - rad) / 14.0, 0, 1) ** 0.6           # 가장자리 볼록
    inner = np.clip((S * 0.3 - rad) / 2.0, 0, 1)
    h = h - inner * 0.35 + np.clip((S * 0.3 - rad) / 6, 0, 1) * 0.2
    # 닻 무늬 (눌림)
    em = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(em)
    d.line([(c, c - S * 0.18), (c, c + S * 0.17)], fill=255, width=int(S * 0.045))
    d.line([(c - S * 0.1, c - S * 0.1), (c + S * 0.1, c - S * 0.1)], fill=255, width=int(S * 0.04))
    d.ellipse([c - S * 0.045, c - S * 0.25, c + S * 0.045, c - S * 0.16], outline=255, width=int(S * 0.03))
    d.arc([c - S * 0.18, c - S * 0.05, c + S * 0.18, c + S * 0.2], 20, 160, fill=255, width=int(S * 0.045))
    emb = ndimage.gaussian_filter(np.asarray(em).astype(np.float32) / 255, 1.2)
    h = h - emb * 0.25
    h = ndimage.gaussian_filter(h, 1.0)
    gx = np.gradient(h, axis=1)
    gy = np.gradient(h, axis=0)
    light = np.clip(0.75 - gx * 9 - gy * 9, 0.25, 1.4)
    spec = np.clip(-gx * 10 - gy * 10 - 0.25, 0, 1) ** 2
    v = 0.72 * light + spec * 0.6
    v *= 0.92 + 0.08 * fbm(S, S, 10, 10, 2, 3)
    rgb = np.dstack([v, v, v]) * 255
    return to_img(rgb, mask * 255)


def stamp(w=330, h=120, seed=3):
    """붉은 도장 테두리 (글씨는 게임에서 넣음). 흰색으로 그려서 게임에서 빨갛게 물들임"""
    S = 3
    img = Image.new("L", (w * S, h * S), 0)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([6 * S, 6 * S, (w - 6) * S, (h - 6) * S], radius=18 * S, outline=255, width=7 * S)
    d.rounded_rectangle([16 * S, 16 * S, (w - 16) * S, (h - 16) * S], radius=12 * S, outline=255, width=3 * S)
    img = img.resize((w, h), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32) / 255
    grunge = fbm(h, w, 6, 14, seed, 4)
    speck = np.random.default_rng(seed).random((h, w))
    a = a * np.clip(grunge * 1.8 - 0.25, 0, 1) * (speck > 0.12)
    rgb = np.ones((h, w, 3)) * 255
    return to_img(rgb, a * 255)


def wood_frame(w=520, h=320, t=44):
    """낡은 나무 액자 (9칸으로 늘림). 모서리에 황동 덧쇠"""
    col = np.zeros((h, w, 3), np.float32)
    top = bevel(wood(t, w, 31, vertical=False, tone=0.75), 8, 0.3)
    bot = bevel(wood(t, w, 32, vertical=False, tone=0.7), 8, 0.3)
    lef = bevel(wood(h, t, 33, vertical=True, tone=0.72), 8, 0.3)
    rig = bevel(wood(h, t, 34, vertical=True, tone=0.68), 8, 0.3)
    col[:t] = top
    col[h - t:] = bot
    col[:, :t] = lef
    col[:, w - t:] = rig
    alpha = np.ones((h, w), np.float32) * 255
    alpha[t:h - t, t:w - t] = 0
    # 안쪽 그늘
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    ins = np.minimum(np.minimum(xx - t, w - t - 1 - xx), np.minimum(yy - t, h - t - 1 - yy))
    sh = np.clip(1 - ins / 14.0, 0, 1) * (ins >= 0)
    img = to_img(col)
    scratches(img, 60, 7)
    a = np.asarray(img).astype(np.float32)
    a[..., 3] = alpha
    a[..., 3] = np.maximum(a[..., 3], sh * 150)
    a[..., :3] *= (1 - sh[..., None] * (a[..., 3:4] < 255))
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    # 황동 모서리
    d = ImageDraw.Draw(img)
    for cx, cy in [(0, 0), (w, 0), (0, h), (w, h)]:
        sx = 1 if cx == 0 else -1
        sy = 1 if cy == 0 else -1
        pts = [(cx, cy), (cx + sx * 64, cy), (cx + sx * 64, cy + sy * 16), (cx + sx * 16, cy + sy * 16), (cx + sx * 16, cy + sy * 64), (cx, cy + sy * 64)]
        d.polygon(pts, fill=(178, 132, 60, 255), outline=(90, 60, 20, 255))
        d.line([(cx + sx * 4, cy + sy * 4), (cx + sx * 58, cy + sy * 4)], fill=(235, 200, 120, 255), width=2)
        for px, py in [(cx + sx * 40, cy + sy * 8), (cx + sx * 8, cy + sy * 40), (cx + sx * 9, cy + sy * 9)]:
            d.ellipse([px - 4, py - 4, px + 4, py + 4], fill=(110, 80, 30, 255), outline=(60, 40, 15, 255))
            d.ellipse([px - 2, py - 3, px + 1, py], fill=(230, 200, 130, 255))
    return img


def ribbon(w=420, h=110):
    """붉은 천 리본 배너 (양끝이 갈라짐)"""
    rng = np.random.default_rng(9)
    S = 2
    m = Image.new("L", (w * S, h * S), 0)
    d = ImageDraw.Draw(m)
    notch = 34
    d.polygon([(0, 0), (w * S, 0), ((w - notch) * S, h * S / 2), (w * S, h * S), (0, h * S), (notch * S, h * S / 2)], fill=255)
    m = m.resize((w, h), Image.LANCZOS)
    a = np.asarray(m).astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    weave = 0.94 + 0.06 * np.sin(xx * 2.2) * np.sin(yy * 2.2)
    fold = 0.85 + 0.25 * np.sin(xx / w * math.pi * 3 + 0.4) * 0.5 + 0.15 * (1 - yy / h)
    base = np.array([150, 28, 26], np.float32)
    col = base[None, None, :] * (fold * weave)[..., None] * (0.9 + 0.2 * fbm(h, w, 4, 12, 3, 3))[..., None]
    # 위아래 금실 바느질
    for y in [9, h - 10]:
        col[y - 1:y + 1, 40:w - 40] = [220, 175, 90]
        col[y - 1:y + 1, 40:w - 40][:, ::7] = col[y - 1:y + 1, 40:w - 40][:, ::7] * 0.5
    return to_img(col, a)


parchment(900, 680, 1).save(os.path.join(OUT, "parchment.png"))
parchment(600, 220, 2, burn=34, folds=False).save(os.path.join(OUT, "parchment_card.png"))
compass().save(os.path.join(OUT, "compass.png"))
wax_seal().save(os.path.join(OUT, "wax_seal.png"))
stamp().save(os.path.join(OUT, "stamp.png"))
wood_frame().save(os.path.join(OUT, "frame.png"))
ribbon().save(os.path.join(OUT, "ribbon.png"))
print("ok")
