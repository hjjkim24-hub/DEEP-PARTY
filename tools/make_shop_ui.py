"""나무 상점 화면 그림 — 사실적인 버전.
나뭇결(노이즈로 만든 결·옹이·얼룩), 판자 틈 그림자, 녹슨 못, 주름진 천 차양과 바느질, 꼬인 밧줄,
쇠 경첩, 종이 가격표, 황동 등불.

    python make_shop_ui.py  →  ../textures/ui/shop/*.png
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "textures", "ui", "shop")

LIGHT = np.array([182, 128, 80], np.float32)
DARK = np.array([88, 52, 28], np.float32)


# ── 노이즈 ───────────────────────────────────────────────────
def smooth_noise(h, w, cy, cx, seed):
    rng = np.random.default_rng(seed)
    g = rng.random((max(2, int(cy)) + 3, max(2, int(cx)) + 3)).astype(np.float32)
    z = ndimage.zoom(g, ((h + 4) / g.shape[0] * 1.0, (w + 4) / g.shape[1] * 1.0), order=3)
    return z[:h, :w]


def fbm(h, w, cy, cx, seed, octaves=4):
    out = np.zeros((h, w), np.float32)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        out += smooth_noise(h, w, cy * 2 ** o, cx * 2 ** o, seed + o * 17) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def to_img(rgb, alpha=None):
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    if alpha is None:
        alpha = np.full(rgb.shape[:2], 255, np.uint8)
    else:
        alpha = np.clip(alpha, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, alpha]), "RGBA")


# ── 나무 ─────────────────────────────────────────────────────
def wood(h, w, seed, vertical=True, tone=1.0, knots=1):
    """결이 세로(vertical) 또는 가로로 난 판자 한 장 (h x w, RGB float)"""
    if not vertical:
        return wood(w, h, seed, True, tone, knots).transpose(1, 0, 2)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    warp = fbm(h, w, h / 220, w / 60, seed) * 26 + fbm(h, w, h / 60, w / 14, seed + 5) * 4
    rng = np.random.default_rng(seed)
    # 옹이 주변으로 결이 휘어짐
    for k in range(knots):
        if rng.random() < 0.7:
            kx, ky = rng.uniform(w * 0.2, w * 0.8), rng.uniform(h * 0.1, h * 0.9)
            d2 = ((xx - kx) / (w * 0.08 + 6)) ** 2 + ((yy - ky) / (w * 0.22 + 12)) ** 2
            warp += 22 * np.exp(-d2) * np.sign(xx - kx + 0.01)
    u = xx + warp
    rings = 0.5 + 0.5 * np.sin(u * 0.55 + fbm(h, w, h / 300, w / 30, seed + 9) * 6)
    rings = rings ** 3
    fibers = fbm(h, w, h / 260, w / 1.6, seed + 3, 3)
    low = fbm(h, w, h / 260, w / 90, seed + 7, 3)
    t = np.clip(rings * 0.45 + fibers * 0.4 + (1 - low) * 0.3 - 0.1, 0, 1)
    col = LIGHT[None, None, :] * (1 - t[..., None]) + DARK[None, None, :] * t[..., None]
    col *= tone
    # 얼룩 · 바랜 자국
    stain = fbm(h, w, h / 120, w / 40, seed + 11, 3)
    col *= (0.86 + 0.22 * stain)[..., None]
    # 옹이
    for k in range(knots):
        if rng.random() < 0.45:
            kx, ky = rng.uniform(w * 0.25, w * 0.75), rng.uniform(h * 0.15, h * 0.85)
            rx, ry = rng.uniform(4, 8), rng.uniform(7, 13)
            d = np.sqrt(((xx - kx) / rx) ** 2 + ((yy - ky) / ry) ** 2)
            ring = 0.5 + 0.5 * np.cos(d * 5.0)
            m = np.clip(1.3 - d, 0, 1)
            col = col * (1 - m[..., None] * 0.55) + (DARK * 0.55)[None, None, :] * m[..., None] * 0.55 * (0.6 + 0.4 * ring[..., None])
    return col


def bevel(col, edge=10, strength=0.22):
    """판자 가장자리: 왼쪽·위는 밝게, 오른쪽·아래는 어둡게 (빛이 왼쪽 위에서)"""
    h, w = col.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    l = np.clip(1 - xx / edge, 0, 1)
    r = np.clip(1 - (w - 1 - xx) / edge, 0, 1)
    t = np.clip(1 - yy / edge, 0, 1)
    b = np.clip(1 - (h - 1 - yy) / edge, 0, 1)
    f = 1 + strength * (l * 0.8 + t * 0.6) - strength * (r * 1.4 + b * 1.2)
    return col * f[..., None]


def scratches(img, n, seed, light=True):
    rng = np.random.default_rng(seed)
    d = ImageDraw.Draw(img, "RGBA")
    w, h = img.size
    for _ in range(n):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        a = rng.uniform(-0.5, 0.5) + (math.pi / 2 if rng.random() < 0.5 else 0)
        ln = rng.uniform(8, 40)
        c = (255, 230, 190, int(rng.uniform(25, 60))) if light else (30, 15, 5, int(rng.uniform(30, 70)))
        d.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=c, width=1)


def nail(img, x, y, r=6):
    """녹이 살짝 슨 쇠못"""
    w, h = img.size
    halo = Image.new("L", (w, h), 0)
    ImageDraw.Draw(halo).ellipse([x - r * 2.4, y - r * 2.0, x + r * 2.4, y + r * 3.2], fill=110)
    halo = halo.filter(ImageFilter.GaussianBlur(r))
    rust = Image.new("RGBA", (w, h), (92, 46, 18, 255))
    img.paste(rust, (0, 0), halo)
    d = ImageDraw.Draw(img)
    d.ellipse([x - r, y - r + 1.5, x + r, y + r + 1.5], fill=(20, 14, 10))
    for k in range(int(r), 0, -1):
        f = k / r
        c = int(70 + (1 - f) * 120)
        d.ellipse([x - k, y - k, x + k, y + k], fill=(c, c - 6, c - 14))
    d.ellipse([x - r * 0.55, y - r * 0.6, x - r * 0.05, y - r * 0.15], fill=(225, 220, 210))


def plank_wall(w, h, plank_w, seed, vertical=True, tone=1.0, gap=4):
    """판자를 여러 장 이어 붙인 면 (RGBA)"""
    out = np.zeros((h, w, 3), np.float32)
    rng = np.random.default_rng(seed)
    pos = 0
    k = 0
    span = w if vertical else h
    while pos < span:
        pw = int(plank_w * rng.uniform(0.85, 1.15))
        pw = min(pw, span - pos)
        if pw <= gap + 4:
            break
        tn = tone * rng.uniform(0.86, 1.08)
        if vertical:
            p = bevel(wood(h, pw - gap, seed + k * 31, True, tn, 2), 9, 0.2)
            out[:, pos:pos + pw - gap] = p
            out[:, pos + pw - gap:pos + pw] = (18, 9, 4)
        else:
            p = bevel(wood(pw - gap, w, seed + k * 31, False, tn, 2), 9, 0.2)
            out[pos:pos + pw - gap, :] = p
            out[pos + pw - gap:pos + pw, :] = (18, 9, 4)
        pos += pw
        k += 1
    img = to_img(out)
    # 판자 틈 옆 그림자
    sh = np.zeros((h, w), np.float32)
    a = np.asarray(img)[..., :3].mean(axis=2)
    sh[a < 30] = 1
    sh = ndimage.gaussian_filter(sh, 3)
    arr = np.asarray(img).astype(np.float32)
    arr[..., :3] *= (1 - np.clip(sh * 0.8, 0, 0.6))[..., None]
    img = Image.fromarray(arr.astype(np.uint8), "RGBA")
    scratches(img, int(w * h / 9000), seed + 2)
    scratches(img, int(w * h / 18000), seed + 3, False)
    return img


def vignette(img, strength=0.45, top_shadow=0.0, top_px=0):
    w, h = img.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = np.minimum(xx, w - 1 - xx) / (w * 0.18)
    dy = np.minimum(yy, h - 1 - yy) / (h * 0.25)
    f = 1 - strength * (1 - np.clip(np.minimum(dx, dy), 0, 1)) ** 2
    if top_shadow > 0:
        f *= 1 - top_shadow * np.clip(1 - yy / top_px, 0, 1) ** 1.5
    arr = np.asarray(img).astype(np.float32)
    arr[..., :3] *= f[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


# ── 부품 ─────────────────────────────────────────────────────
def wall(w=1650, h=840):
    img = plank_wall(w, h, 140, 100, True, 0.95)
    # 가로 받침목 (진열칸 아래)
    beam = to_img(bevel(wood(54, w, 77, False, 0.8, 1), 8, 0.3))
    img.paste(beam, (0, int(h * 0.62)))
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, int(h * 0.62) + 54, w, int(h * 0.62) + 66], fill=(0, 0, 0, 70))
    for x in range(70, w, 140):
        nail(img, x, 34, 6)
        nail(img, x, int(h * 0.62) + 27, 6)
    return vignette(img, 0.5, 0.55, 150)


def counter(w=1770, h=270):
    top_h = 52
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    front = plank_wall(w - 30, h - top_h - 4, 68, 300, False, 0.82)
    out.paste(front, (15, top_h + 4))
    d = ImageDraw.Draw(out, "RGBA")
    # 상판 아래 그림자
    for k in range(18):
        d.rectangle([15, top_h + 4 + k, w - 15, top_h + 5 + k], fill=(0, 0, 0, int(120 * (1 - k / 18) ** 2)))
    top = to_img(bevel(wood(top_h, w, 333, False, 1.12, 2), 10, 0.35))
    out.paste(top, (0, 0))
    # 상판 윗면 반짝임
    d.rectangle([4, 4, w - 4, 8], fill=(255, 225, 180, 60))
    # 모서리 쇠 장식
    for x0 in (15, w - 15 - 44):
        d.rectangle([x0, top_h + 4, x0 + 44, h - 2], fill=(52, 48, 46, 255))
        d.rectangle([x0 + 3, top_h + 6, x0 + 9, h - 4], fill=(110, 104, 98, 255))
        for yy in range(top_h + 30, h - 10, 52):
            nail(out, x0 + 22, yy, 6)
    return vignette(out, 0.25)


def slot(w=345, h=354):
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    m = 30
    # 안쪽 뒷판 (세로 판자, 어둡게)
    back = plank_wall(w - m * 2, h - m * 2, 70, 500, True, 0.62)
    arr = np.asarray(back).astype(np.float32)
    hh, ww = arr.shape[:2]
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    # 상자 안쪽 그림자 (위·왼쪽 깊게)
    ao = np.clip(np.minimum(np.minimum(xx / 60, (ww - xx) / 40), np.minimum(yy / 80, (hh - yy) / 30)), 0, 1)
    arr[..., :3] *= (0.35 + 0.65 * ao ** 0.8)[..., None]
    out.paste(Image.fromarray(arr.astype(np.uint8), "RGBA"), (m, m))
    # 틀 (네 변)
    frame_t = to_img(bevel(wood(m, w, 510, False, 1.05, 1), 6, 0.35))
    frame_b = to_img(bevel(wood(m, w, 511, False, 1.1, 1), 6, 0.35))
    frame_l = to_img(bevel(wood(h, m, 512, True, 1.0, 1), 6, 0.35))
    frame_r = to_img(bevel(wood(h, m, 513, True, 0.9, 1), 6, 0.35))
    out.paste(frame_l, (0, 0))
    out.paste(frame_r, (w - m, 0))
    out.paste(frame_t, (0, 0))
    out.paste(frame_b, (0, h - m))
    # 바닥 선반 윗면 빛
    d = ImageDraw.Draw(out, "RGBA")
    d.rectangle([m, h - m - 6, w - m, h - m], fill=(255, 220, 170, 50))
    for x, y in ((15, 15), (w - 15, 15), (15, h - 15), (w - 15, h - 15)):
        nail(out, x, y, 5)
    return out


def awning(w=1860, h=330):
    S = 1
    stripes = 11
    sw = w / stripes
    body = int(h * 0.6)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    k = np.floor(xx / sw)
    u = (xx - k * sw) / sw
    red = np.array([168, 40, 46], np.float32)
    cream = np.array([232, 220, 196], np.float32)
    col = np.where((k % 2 == 0)[..., None], red[None, None, :], cream[None, None, :])
    # 천 짜임
    weave = 0.93 + 0.04 * np.sin(xx * 2.1) * np.sin(yy * 2.3) + 0.05 * fbm(h, w, h / 6, w / 6, 900, 2)
    # 주름 (줄마다 둥글게 부풀어 보이게)
    fold = 0.74 + 0.34 * np.sin(np.pi * u) ** 0.7
    # 위쪽은 막대 그림자, 가운데 밝게
    vert = 0.78 + 0.3 * np.clip(yy / (h * 0.35), 0, 1) - 0.12 * np.clip((yy - body) / (h * 0.3), 0, 1)
    dirt = 0.9 + 0.12 * fbm(h, w, h / 50, w / 70, 901, 3)
    col = col * (weave * fold * vert * dirt)[..., None]
    # 물결 모양 아래 끝 (반원)
    cxs = (k + 0.5) * sw
    r = sw * 0.5
    inside = (yy < body) | (((xx - cxs) ** 2 + (yy - body) ** 2) <= r * r)
    dist_edge = np.where(yy < body, 99, r - np.sqrt((xx - cxs) ** 2 + (yy - body) ** 2))
    # 단 (끝단 접은 부분 어둡게) + 바느질
    hem = np.clip(1 - dist_edge / 14, 0, 1)
    col *= (1 - 0.3 * hem)[..., None]
    alpha = inside.astype(np.float32) * 255
    # 가장자리 부드럽게
    alpha = ndimage.gaussian_filter(alpha, 0.8)
    img = to_img(col, alpha)
    d = ImageDraw.Draw(img, "RGBA")
    for i in range(stripes):
        cx = (i + 0.5) * sw
        thread = (240, 225, 200, 170) if i % 2 == 0 else (120, 40, 40, 150)
        for a in range(0, 180, 9):
            a0, a1 = math.radians(a), math.radians(a + 5)
            rr = r - 20
            d.line([(cx + math.cos(a0) * rr, body + math.sin(a0) * rr), (cx + math.cos(a1) * rr, body + math.sin(a1) * rr)], fill=thread, width=2)
        for yv in range(30, body, 18):
            pass
    # 위쪽 나무 막대 (둥근 막대처럼)
    bar_h = 40
    bar = wood(bar_h, w, 950, False, 0.9, 2)
    shade = 0.55 + 0.6 * np.sin(np.linspace(0.15, np.pi - 0.15, bar_h)) ** 0.8
    bar *= shade[:, None, None]
    img.paste(to_img(bar), (0, 0))
    # 쇠 받침
    for x in (60, w // 2, w - 60):
        d.rectangle([x - 16, 0, x + 16, bar_h + 14], fill=(46, 42, 40, 255))
        d.rectangle([x - 12, 2, x - 7, bar_h + 12], fill=(115, 108, 100, 255))
        nail(img, x, bar_h + 4, 5)
    # 아래로 드리운 그림자는 별도로 (벽 위에 깔림)
    return img


def awning_shadow(w=1860, h=180):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    stripes = 11
    sw = w / stripes
    for i in range(stripes):
        cx = (i + 0.5) * sw
        d.ellipse([cx - sw * 0.5, -sw * 0.15, cx + sw * 0.5, sw * 0.62], fill=(0, 0, 0, 150))
    d.rectangle([0, 0, w, 40], fill=(0, 0, 0, 150))
    return img.filter(ImageFilter.GaussianBlur(18))


def rope(d, x, y0, y1, width=9):
    """꼬인 밧줄"""
    d.line([(x, y0), (x, y1)], fill=(150, 118, 70), width=width)
    for yy in range(int(y0), int(y1), 7):
        d.line([(x - width / 2, yy), (x + width / 2, yy + 6)], fill=(98, 72, 38), width=2)
        d.line([(x - width / 2 + 1, yy + 2), (x + width / 2 - 2, yy + 7)], fill=(198, 168, 116), width=1)


def sign(w=660, h=285):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    board_top = int(h * 0.3)
    for x in (w * 0.2, w * 0.8):
        rope(d, x, 0, board_top + 18)
    bh = h - board_top
    board = to_img(bevel(wood(bh, w, 700, False, 0.85, 2), 14, 0.4))
    mask = Image.new("L", (w, bh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, bh - 1], radius=18, fill=255)
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([6, board_top + 10, w - 2, h - 1], radius=18, fill=(0, 0, 0, 120))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(6)))
    img.paste(board, (0, board_top), mask)
    d = ImageDraw.Draw(img, "RGBA")
    # 인두로 지진 테두리
    d.rounded_rectangle([18, board_top + 16, w - 18, h - 16], radius=12, outline=(40, 20, 8, 150), width=4)
    for x in (w * 0.2, w * 0.8):
        d.ellipse([x - 13, board_top + 6, x + 13, board_top + 32], outline=(70, 66, 62), width=5)
        nail(img, x, board_top + 19, 5)
    return img


def tag(w=225, h=96):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    paper = np.ones((h, w, 3), np.float32) * np.array([236, 220, 182], np.float32)
    paper *= (0.9 + 0.12 * fbm(h, w, h / 10, w / 10, 1200, 3))[..., None]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    paper *= (1 - 0.18 * np.clip(1 - np.minimum(xx, w - xx) / 20, 0, 1))[..., None]
    pimg = to_img(paper)
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.polygon([(4, h / 2), (h * 0.36, 6), (w - 4, 6), (w - 4, h - 6), (h * 0.36, h - 6)], fill=255)
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(8, h / 2 + 4), (h * 0.36 + 4, 10), (w, 10), (w, h - 2), (h * 0.36 + 4, h - 2)], fill=(0, 0, 0, 110))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(4)))
    img.paste(pimg, (0, 0), mask)
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([h * 0.24, h / 2 - 8, h * 0.24 + 16, h / 2 + 8], fill=(60, 40, 20, 255), outline=(170, 140, 90), width=3)
    d.line([(h * 0.24 + 8, h / 2), (-2, h / 2 - 30)], fill=(120, 96, 60), width=3)
    return img


def shutter(w=825, h=840):
    img = plank_wall(w, h, 78, 800, False, 0.78)
    img = vignette(img, 0.3)
    d = ImageDraw.Draw(img, "RGBA")
    # Z 받침목
    brace = to_img(bevel(wood(64, w, 810, False, 0.68, 1), 8, 0.35))
    for y in (70, h - 134):
        img.paste(brace, (0, y))
    diag = to_img(bevel(wood(64, int(math.hypot(w, h - 260)), 811, False, 0.68, 1), 8, 0.35))
    ang = math.degrees(math.atan2(h - 260, w))
    rot = diag.rotate(ang, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(rot, (int(w / 2 - rot.width / 2), int(h / 2 - rot.height / 2)))
    # 쇠 경첩 (바깥쪽 = 왼쪽 끝) — 오른쪽 문은 Godot 에서 좌우 뒤집어 씀
    for y in (102, h - 102):
        d.rectangle([0, y - 18, 230, y + 18], fill=(44, 40, 38, 255))
        d.rectangle([4, y - 15, 226, y - 10], fill=(110, 104, 96, 255))
        d.ellipse([218, y - 24, 266, y + 24], fill=(44, 40, 38, 255))
        for x in range(26, 240, 46):
            nail(img, x, y, 6)
    # 손잡이 고리 (가운데 쪽 = 오른쪽 끝)
    d.ellipse([w - 128, h / 2 - 34, w - 60, h / 2 + 34], outline=(60, 56, 52), width=9)
    d.ellipse([w - 126, h / 2 - 32, w - 62, h / 2 + 32], outline=(140, 130, 116), width=3)
    nail(img, w - 94, h / 2 - 34, 7)
    return img


def button(w=420, h=120):
    board = to_img(bevel(wood(h, w, 900, False, 1.08, 2), 12, 0.45))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=24, fill=255)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    img.paste(board, (0, 0), mask)
    d = ImageDraw.Draw(img, "RGBA")
    # 파낸 홈 테두리
    d.rounded_rectangle([14, 14, w - 14, h - 14], radius=14, outline=(40, 20, 8, 140), width=3)
    d.rounded_rectangle([16, 17, w - 12, h - 11], radius=14, outline=(255, 220, 170, 50), width=2)
    for x in (30, w - 30):
        nail(img, x, h / 2, 6)
    return img


def lantern(w=150, h=260):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    cx = w / 2
    # 빛 번짐은 Godot 에서 따로 (glow.png)
    d.line([(cx, 0), (cx, 40)], fill=(40, 36, 34), width=5)
    d.ellipse([cx - 16, 30, cx + 16, 58], outline=(60, 54, 46), width=6)
    # 지붕
    d.polygon([(cx - 52, 92), (cx, 52), (cx + 52, 92)], fill=(70, 52, 30))
    d.polygon([(cx - 48, 92), (cx, 56), (cx - 4, 92)], fill=(150, 110, 50))
    # 유리 (불빛)
    glass = np.zeros((130, 84, 3), np.float32)
    yy, xx = np.mgrid[0:130, 0:84].astype(np.float32)
    dd = np.sqrt(((xx - 42) / 42) ** 2 + ((yy - 70) / 65) ** 2)
    glass[...] = np.array([255, 196, 96], np.float32)
    glass *= np.clip(1.25 - dd * 0.55, 0.5, 1.3)[..., None]
    img.paste(to_img(glass), (int(cx - 42), 94))
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([cx - 12, 140, cx + 12, 184], fill=(255, 250, 220, 255))
    # 황동 틀
    for x in (cx - 44, cx - 2, cx + 40):
        d.rectangle([x, 92, x + 5, 226], fill=(176, 130, 56))
    d.rectangle([cx - 52, 222, cx + 52, 238], fill=(150, 108, 44))
    d.rectangle([cx - 50, 90, cx + 50, 98], fill=(190, 146, 66))
    d.polygon([(cx - 30, 238), (cx + 30, 238), (cx, 256)], fill=(120, 86, 36))
    return img


def glow(n=400):
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.sqrt((xx - n / 2) ** 2 + (yy - n / 2) ** 2) / (n / 2)
    a = np.clip(1 - d, 0, 1) ** 2.2 * 255
    rgb = np.ones((n, n, 3), np.float32) * np.array([255, 190, 110], np.float32)
    return to_img(rgb, a)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    parts = {
        "wall": wall, "counter": counter, "slot": slot, "awning": awning, "awning_shadow": awning_shadow,
        "sign": sign, "tag": tag, "shutter": shutter, "button": button, "lantern": lantern, "glow": glow,
    }
    for name, fn in parts.items():
        fn().save(os.path.join(OUT, name + ".png"))
        print("  ", name)
    print("shop ui ->", OUT)
