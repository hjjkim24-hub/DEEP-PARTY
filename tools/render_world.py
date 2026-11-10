"""튜토리얼 월드 지도 만들기 — 말이 직접 들어가서 걸어 다니는 '보드게임 속 세상'.

    python render_world.py
    → ../textures/worlds/tutorial_map.png    (4800x3200, 비스듬히 내려다본 바다 밑 세상)
       ../textures/worlds/tutorial_world.json (칸 위치·연결, 시작 칸, 움직이는 장식 위치)
       out/tutorial_map_small.png             (상자 그림용 작은 지도)

골인 지점은 없고, 길이 여러 갈래로 갈라졌다 다시 만나며 세상 전체를 이어요.
지역: 가운데 START 광장 / 산호 정원 / 다시마 숲 / 난파선 / 조개 해변 / 거품 분수 / 진주 석호
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "textures", "worlds")
FONT = os.path.join(ROOT, "fonts", "Poppins-Bold.ttf")
W, H = 4800, 3200
RIM = 90            # 판 가장자리 (멀리서 보면 보드게임 판처럼 보이게)
SPACING = 175       # 칸 사이 거리
rng = np.random.default_rng(11)

PEARL = (234, 255, 250)
AQUA = (127, 240, 219)
DEEP = (5, 48, 44)

REGIONS = {
    "start":   {"pos": (2350, 1750), "tint": (96, 168, 140)},
    "coral":   {"pos": (1150, 820), "tint": (156, 150, 128)},
    "kelp":    {"pos": (900, 2350), "tint": (66, 126, 94)},
    "wreck":   {"pos": (3780, 950), "tint": (84, 118, 116)},
    "beach":   {"pos": (3950, 2480), "tint": (180, 188, 150)},
    "vents":   {"pos": (2550, 520), "tint": (62, 96, 100)},
    "lagoon":  {"pos": (2250, 2850), "tint": (80, 170, 168)},
}
R = {k: v["pos"] for k, v in REGIONS.items()}
S = R["start"]
J = {
    "S": S, "C": R["coral"], "K": R["kelp"], "W": R["wreck"], "B": R["beach"], "V": R["vents"], "L": R["lagoon"],
    "J1": (1700, 1450), "J2": (2950, 1430), "J3": (2200, 2300), "J4": (3300, 2330),
}
# 갈림길(J)끼리 잇는 길. 가운데 숫자들은 길이 구불구불 지나가는 점
EDGES = [
    ("S", "J1", [(2050, 1660)]),
    ("S", "J2", [(2640, 1560)]),
    ("S", "J3", [(2300, 2040)]),
    ("J1", "C", [(1500, 1210), (1300, 1010)]),
    ("J1", "K", [(1420, 1720), (1160, 2010)]),
    ("J1", "V", [(1860, 1110), (2160, 820)]),
    ("J2", "V", [(2870, 1100), (2720, 760)]),
    ("J2", "W", [(3260, 1300), (3560, 1140)]),
    ("C", "V", [(1560, 600), (2020, 450)]),
    ("V", "W", [(3020, 410), (3460, 590)]),
    ("C", "K", [(820, 1240), (660, 1800)]),
    ("W", "B", [(4170, 1360), (4260, 1960)]),
    ("J3", "L", [(2120, 2600)]),
    ("J3", "J4", [(2720, 2360), (3010, 2270)]),
    ("J4", "B", [(3620, 2520)]),
    ("J2", "J4", [(3200, 1800), (3360, 2100)]),
    ("K", "L", [(1300, 2720), (1800, 2960)]),
    ("L", "B", [(2900, 3010), (3500, 2860)]),
]
ROUTES = [[J[a]] + mid + [J[b]] for a, b, mid in EDGES]


def font(s):
    return ImageFont.truetype(FONT, int(s))


def catmull(pts, n_per=40):
    pts = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = (np.array(p, float) for p in pts[i - 1:i + 3])
        for t in np.linspace(0, 1, n_per, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(np.array(pts[-2], float))
    return np.array(out)


def resample(curve, spacing):
    seg = np.linalg.norm(np.diff(curve, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    total = cum[-1]
    n = max(1, int(round(total / spacing)))
    ds = np.linspace(0, total, n + 1)
    xs = np.interp(ds, cum, curve[:, 0])
    ys = np.interp(ds, cum, curve[:, 1])
    return list(zip(xs, ys))


def build_graph():
    nodes = []          # {"id","x","y","links":set,"kind"}
    index = {}

    def node_at(p, kind="space"):
        key = (round(p[0]), round(p[1]))
        if key in index:
            return index[key]
        nid = len(nodes)
        nodes.append({"id": nid, "x": float(p[0]), "y": float(p[1]), "links": set(), "kind": kind})
        index[key] = nid
        return nid

    node_at(S, "start")
    curves = []
    for route in ROUTES:
        c = catmull(route)
        curves.append(c)
        pts = resample(c, SPACING)
        pts[0], pts[-1] = route[0], route[-1]
        # START 광장은 크니까 바로 옆 칸은 조금 떨어뜨림
        pts = [p for k, p in enumerate(pts) if k in (0, len(pts) - 1) or math.dist(p, S) > 250]
        ids = [node_at(p) for p in pts]
        for a, b in zip(ids, ids[1:]):
            nodes[a]["links"].add(b)
            nodes[b]["links"].add(a)
    for n in nodes:
        if n["kind"] != "start" and len(n["links"]) > 2:
            n["kind"] = "junction"
    return nodes, curves


# ── 바닥 ─────────────────────────────────────────────────────
def value_noise(h, w, cell, seed):
    r = np.random.default_rng(seed)
    gh, gw = h // cell + 2, w // cell + 2
    g = r.random((gh, gw)).astype(np.float32)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((gw * cell, gh * cell), Image.BICUBIC)
    return np.asarray(img, np.float32)[:h, :w] / 255.0


def ground():
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    col = np.zeros((H, W, 3), np.float32)
    wsum = np.zeros((H, W), np.float32)
    for reg in REGIONS.values():
        px, py = reg["pos"]
        wgt = np.exp(-(((x - px) / 900) ** 2 + ((y - py) / 700) ** 2))
        col += wgt[..., None] * np.array(reg["tint"], np.float32)
        wsum += wgt
    base = np.array([88, 140, 118], np.float32)
    col = (col + base * 0.15) / (wsum + 0.15)[..., None]
    n1 = value_noise(H, W, 160, 1)
    n2 = value_noise(H, W, 40, 2)
    n3 = value_noise(H, W, 9, 3)
    col *= (0.82 + 0.25 * n1 + 0.08 * n2 + 0.05 * n3)[..., None]
    rip = np.sin(y * 0.09 + np.sin(x * 0.004) * 6 + n1 * 5) * 0.5 + 0.5
    col *= (0.95 + 0.07 * rip)[..., None]
    # 판 가장자리
    m = np.minimum.reduce([x - RIM, W - RIM - x, y - RIM, H - RIM - y])
    inside = np.clip(m / 40.0, 0, 1)
    rim_col = np.array([10, 52, 58], np.float32)
    col = col * inside[..., None] + rim_col * (1 - inside[..., None])
    edge_glow = np.exp(-((m) / 14.0) ** 2)
    col += edge_glow[..., None] * np.array([120, 200, 185], np.float32) * 0.55
    vign = np.clip(m / 500.0, 0, 1) ** 0.5
    col *= (0.82 + 0.18 * vign)[..., None]
    a = np.full((H, W, 1), 255, np.float32)
    return Image.fromarray(np.clip(np.concatenate([col, a], 2), 0, 255).astype(np.uint8), "RGBA")


# ── 작게 그려서 깔끔하게 붙이기 (안티에일리어싱) ─────────────
def stamp(img, cx, cy, w, h, draw_fn, ss=3):
    patch = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(patch), ss, patch)
    patch = patch.resize((w, h), Image.LANCZOS)
    img.alpha_composite(patch, (int(cx - w / 2), int(cy - h / 2)))


def soft_shadow(img, cx, cy, rx, ry, alpha=120, blur=14):
    pad = blur * 3
    w, h = int(rx * 2 + pad * 2), int(ry * 2 + pad * 2)
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([pad, pad, pad + rx * 2, pad + ry * 2], fill=(0, 20, 18, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(sh, (int(cx - w / 2), int(cy - h / 2)))


def paths(img, curves):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for c in curves:
        pts = [tuple(p) for p in c]
        d.line(pts, fill=(214, 226, 190, 150), width=86, joint="curve")
    lay = lay.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(lay)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for c in curves:
        d.line([tuple(p) for p in c], fill=(236, 240, 214, 110), width=40, joint="curve")
    img.alpha_composite(lay.filter(ImageFilter.GaussianBlur(6)))
    # 조약돌
    d = ImageDraw.Draw(img)
    for c in curves:
        for p in c[::3]:
            for _ in range(2):
                ox, oy = rng.normal(0, 26, 2)
                r = rng.uniform(3, 7)
                g = int(rng.uniform(150, 215))
                d.ellipse([p[0] + ox - r, p[1] + oy - r * 0.6, p[0] + ox + r, p[1] + oy + r * 0.6], fill=(g, g + 10, g - 10, 255))


def stone(img, x, y, kind):
    """칸: 납작한 원기둥 돌판."""
    if kind == "start":
        rx, ry, th = 190, 110, 26
    elif kind == "junction":
        rx, ry, th = 74, 44, 16
    else:
        rx, ry, th = 62, 37, 15
    soft_shadow(img, x + 10, y + th + 8, rx * 1.05, ry * 1.0, 130, 12)
    w, h = int(rx * 2 + 20), int(ry * 2 + th + 20)

    def draw(d, s, patch):
        cx, cy = w * s / 2, (ry + 10) * s
        side = (24, 92, 96, 255) if kind != "start" else (26, 70, 80, 255)
        d.rectangle([cx - rx * s, cy, cx + rx * s, cy + th * s], fill=side)
        d.ellipse([cx - rx * s, cy + th * s - ry * s, cx + rx * s, cy + th * s + ry * s], fill=side)
        if kind == "start":
            top, ring = (234, 255, 250, 255), (5, 48, 44, 255)
        elif kind == "junction":
            top, ring = (190, 250, 236, 255), (127, 240, 219, 255)
        else:
            top, ring = (127, 228, 210, 255), (234, 255, 250, 255)
        d.ellipse([cx - rx * s, cy - ry * s, cx + rx * s, cy + ry * s], fill=top)
        # 윗면 빛 (왼쪽 위가 밝게, 불투명하게 여러 겹)
        for k in range(6):
            t = (k + 1) / 7
            col = tuple(min(255, int(top[i] + (255 - top[i]) * t * 0.55)) for i in range(3)) + (255,)
            fx = 1 - t * 0.55
            ox, oy = -rx * 0.18 * t, -ry * 0.2 * t
            d.ellipse([cx + ox * s - rx * fx * s, cy + oy * s - ry * fx * s, cx + ox * s + rx * fx * s, cy + oy * s + ry * fx * s], fill=col)
        d.ellipse([cx - rx * s, cy - ry * s, cx + rx * s, cy + ry * s], outline=ring, width=int(5 * s))
        if kind == "start":
            d.ellipse([cx - rx * 0.78 * s, cy - ry * 0.78 * s, cx + rx * 0.78 * s, cy + ry * 0.78 * s],
                      outline=(127, 240, 219, 255), width=int(4 * s))
            f = font(64 * s)
            tw = d.textlength("START", font=f)
            # 납작하게 보이도록 글자를 따로 그려 세로로 눌러 붙임
            txt = Image.new("RGBA", (int(tw + 20), int(100 * s)), (0, 0, 0, 0))
            ImageDraw.Draw(txt).text((10, 0), "START", font=f, fill=(5, 48, 44, 255))
            txt = txt.resize((txt.width, int(txt.height * 0.62)), Image.LANCZOS)
            patch.alpha_composite(txt, (int(cx - txt.width / 2), int(cy - txt.height / 2 + 4 * s)))
        elif kind == "junction":
            for k in range(4):
                a = k * math.pi / 2 + math.pi / 4
                px, py = cx + math.cos(a) * rx * 0.45 * s, cy + math.sin(a) * ry * 0.45 * s
                d.ellipse([px - 6 * s, py - 4 * s, px + 6 * s, py + 4 * s], fill=(5, 48, 44, 200))
    stamp(img, x, y + th / 2, w, h, draw)


# ── 장식 ─────────────────────────────────────────────────────
def rock(img, x, y, r, col=(110, 126, 118)):
    soft_shadow(img, x + r * 0.2, y + r * 0.35, r * 1.1, r * 0.45, 140, 10)
    w, h = int(r * 2.4), int(r * 2.0)
    patch = np.zeros((h * 2, w * 2, 4), np.float32)
    yy, xx = np.mgrid[0:h * 2, 0:w * 2].astype(np.float32) / 2
    nx = (xx - w / 2) / r
    ny = (yy - h * 0.62) / (r * 0.62)
    d2 = nx ** 2 + ny ** 2
    inside = d2 < 1
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    light = np.clip(-0.5 * nx - 0.6 * ny + 0.62 * nz, 0, 1)
    shade = 0.35 + 0.75 * light
    c = np.array(col, np.float32) * shade[..., None]
    nz_ = np.asarray(Image.fromarray((rng.random((h // 4 + 2, w // 4 + 2)) * 255).astype(np.uint8)).resize((w * 2, h * 2), Image.BICUBIC), np.float32) / 255
    c *= (0.85 + 0.3 * nz_)[..., None]
    moss = np.clip((nz_ - 0.6) * 4, 0, 1) * np.clip(-ny, 0, 1)
    c = c * (1 - moss[..., None] * 0.5) + np.array([70, 130, 80], np.float32) * moss[..., None] * 0.5
    patch[..., :3] = c
    patch[..., 3] = np.clip((1 - d2) * 30, 0, 1) * 255 * inside
    p = Image.fromarray(np.clip(patch, 0, 255).astype(np.uint8), "RGBA").resize((w, h), Image.LANCZOS)
    img.alpha_composite(p, (int(x - w / 2), int(y - h * 0.62)))


def coral(img, x, y, size, col):
    soft_shadow(img, x + 4, y - 2, size * 0.32, size * 0.1, 110, 6)
    w, h = int(size * 1.6), int(size * 1.4)

    def draw(d, s, patch):
        def branch(px, py, ang, ln, wd, depth):
            ex, ey = px + math.cos(ang) * ln, py + math.sin(ang) * ln
            dark = tuple(int(c * 0.7) for c in col) + (255,)
            d.line([(px, py), (ex, ey)], fill=dark, width=int(wd))
            d.line([(px - wd * 0.15, py), (ex - wd * 0.15, ey)], fill=col + (255,), width=int(wd * 0.6))
            d.ellipse([ex - wd / 2, ey - wd / 2, ex + wd / 2, ey + wd / 2], fill=col + (255,))
            if depth > 0:
                for da in (-0.5, 0.45):
                    branch(ex, ey, ang + da + rng.uniform(-0.15, 0.15), ln * 0.72, wd * 0.72, depth - 1)
        bx, by = w * s / 2, h * s * 0.92
        for a in (-1.9, -1.57, -1.25):
            branch(bx, by, a + rng.uniform(-0.1, 0.1), size * 0.36 * s, size * 0.11 * s, 3)
    stamp(img, x, y - h * 0.42, w, h, draw)


def sponge(img, x, y, size, col):
    soft_shadow(img, x + 4, y - 2, size * 0.36, size * 0.11, 110, 6)
    w, h = int(size * 1.2), int(size * 1.3)

    def draw(d, s, patch):
        for i, (ox, hh) in enumerate(((-0.25, 0.7), (0.0, 0.95), (0.25, 0.6))):
            cx = w * s / 2 + ox * size * s
            top = h * s * (1 - hh)
            r = size * 0.13 * s
            dark = tuple(int(c * 0.65) for c in col) + (255,)
            d.rounded_rectangle([cx - r, top, cx + r, h * s * 0.95], radius=r, fill=col + (255,), outline=dark, width=int(2 * s))
            d.ellipse([cx - r * 0.75, top + r * 0.1, cx + r * 0.75, top + r * 0.7], fill=dark)
    stamp(img, x, y - h * 0.45, w, h, draw)


def starfish(img, x, y, r, col=(240, 150, 100)):
    w = int(r * 2.4)

    def draw(d, s, patch):
        c = w * s / 2
        pts = []
        for k in range(10):
            a = -math.pi / 2 + k * math.pi / 5
            rr = r * s if k % 2 == 0 else r * 0.42 * s
            pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr * 0.6))
        d.polygon(pts, fill=col + (255,), outline=tuple(int(v * 0.7) for v in col) + (255,))
    stamp(img, x, y, w, w, draw)


def shell(img, x, y, r, col=(246, 222, 200)):
    w = int(r * 2.6)

    def draw(d, s, patch):
        cx, cy = w * s / 2, w * s * 0.6
        d.pieslice([cx - r * s, cy - r * s, cx + r * s, cy + r * s], 180, 360, fill=col + (255,),
                   outline=tuple(int(v * 0.75) for v in col) + (255,), width=int(2 * s))
        for k in range(1, 6):
            a = math.pi + k * math.pi / 6
            d.line([(cx, cy), (cx + math.cos(a) * r * s, cy + math.sin(a) * r * s)], fill=tuple(int(v * 0.8) for v in col) + (255,), width=int(2 * s))
    stamp(img, x, y, w, w, draw)


def vent(img, x, y, r):
    soft_shadow(img, x, y + 6, r * 1.6, r * 0.7, 120, 10)
    w, h = int(r * 3.4), int(r * 2.2)

    def draw(d, s, patch):
        cx, cy = w * s / 2, h * s * 0.55
        d.ellipse([cx - r * 1.5 * s, cy - r * 0.7 * s, cx + r * 1.5 * s, cy + r * 0.8 * s], fill=(70, 80, 78, 255))
        d.ellipse([cx - r * 1.1 * s, cy - r * 0.45 * s, cx + r * 1.1 * s, cy + r * 0.45 * s], fill=(110, 122, 118, 255))
        d.ellipse([cx - r * 0.6 * s, cy - r * 0.25 * s, cx + r * 0.6 * s, cy + r * 0.25 * s], fill=(18, 26, 26, 255))
    stamp(img, x, y, w, h, draw)


def wreck(img, x, y):
    soft_shadow(img, x + 30, y + 40, 360, 90, 150, 24)
    w, h = 900, 520

    def draw(d, s, patch):
        cx, cy = w * s / 2, h * s * 0.7
        hull = [(cx - 380 * s, cy - 40 * s), (cx + 300 * s, cy - 90 * s), (cx + 400 * s, cy - 150 * s),
                (cx + 330 * s, cy + 20 * s), (cx - 330 * s, cy + 70 * s)]
        d.polygon(hull, fill=(92, 66, 48, 255), outline=(48, 34, 26, 255))
        for k in range(1, 6):
            t = k / 6
            d.line([(cx - 380 * s + t * 60 * s, cy - 40 * s + t * 100 * s), (cx + 310 * s + t * 20 * s, cy - 90 * s + t * 110 * s)],
                   fill=(60, 44, 32, 255), width=int(4 * s))
        d.polygon([(cx - 340 * s, cy - 40 * s), (cx + 300 * s, cy - 90 * s), (cx + 290 * s, cy - 110 * s), (cx - 330 * s, cy - 60 * s)],
                  fill=(120, 92, 66, 255))
        # 부러진 돛대
        d.line([(cx - 40 * s, cy - 70 * s), (cx + 40 * s, cy - 400 * s)], fill=(70, 52, 38, 255), width=int(22 * s))
        d.line([(cx - 10 * s, cy - 300 * s), (cx + 170 * s, cy - 270 * s)], fill=(70, 52, 38, 255), width=int(12 * s))
        d.polygon([(cx + 20 * s, cy - 330 * s), (cx + 150 * s, cy - 300 * s), (cx + 90 * s, cy - 180 * s)], fill=(200, 196, 170, 210))
        # 구멍
        d.ellipse([cx + 80 * s, cy - 60 * s, cx + 170 * s, cy + 0 * s], fill=(24, 18, 14, 255))
    stamp(img, x, y - 170, w, h, draw, ss=2)


def chest(img, x, y):
    soft_shadow(img, x + 8, y + 10, 70, 22, 140, 8)
    w, h = 180, 150

    def draw(d, s, patch):
        cx, cy = w * s / 2, h * s * 0.65
        d.rectangle([cx - 60 * s, cy - 40 * s, cx + 60 * s, cy + 30 * s], fill=(120, 74, 40, 255), outline=(60, 36, 20, 255), width=int(3 * s))
        d.pieslice([cx - 60 * s, cy - 90 * s, cx + 60 * s, cy + 10 * s], 180, 360, fill=(140, 88, 46, 255), outline=(60, 36, 20, 255), width=int(3 * s))
        d.rectangle([cx - 60 * s, cy - 44 * s, cx + 60 * s, cy - 34 * s], fill=(214, 176, 80, 255))
        d.rectangle([cx - 10 * s, cy - 50 * s, cx + 10 * s, cy - 20 * s], fill=(240, 200, 90, 255))
        for k in range(5):
            px = cx - 40 * s + k * 20 * s
            d.ellipse([px - 7 * s, cy - 60 * s, px + 7 * s, cy - 46 * s], fill=(250, 220, 110, 255))
    stamp(img, x, y - 40, w, h, draw)


def clam(img, x, y):
    soft_shadow(img, x + 10, y + 16, 150, 40, 140, 14)
    w, h = 360, 260

    def draw(d, s, patch):
        cx, cy = w * s / 2, h * s * 0.65
        d.pieslice([cx - 150 * s, cy - 40 * s, cx + 150 * s, cy + 80 * s], 0, 180, fill=(170, 196, 214, 255), outline=(90, 110, 130, 255), width=int(4 * s))
        d.pieslice([cx - 150 * s, cy - 170 * s, cx + 150 * s, cy + 40 * s], 180, 340, fill=(190, 214, 230, 255), outline=(90, 110, 130, 255), width=int(4 * s))
        d.ellipse([cx - 34 * s, cy - 30 * s, cx + 34 * s, cy + 30 * s], fill=(250, 246, 255, 255))
        d.ellipse([cx - 22 * s, cy - 22 * s, cx - 4 * s, cy - 6 * s], fill=(255, 255, 255, 255))
    stamp(img, x, y - 60, w, h, draw)


def too_close(x, y, nodes, d=120):
    return any((n["x"] - x) ** 2 + (n["y"] - y) ** 2 < d * d for n in nodes)


def scatter(region, n, spread, fn, nodes, min_d=120):
    cx, cy = R[region]
    placed = 0
    tries = 0
    while placed < n and tries < n * 30:
        tries += 1
        x = cx + rng.normal(0, spread)
        y = cy + rng.normal(0, spread * 0.7)
        if not (RIM + 80 < x < W - RIM - 80 and RIM + 120 < y < H - RIM - 60):
            continue
        if too_close(x, y, nodes, min_d):
            continue
        fn(x, y)
        placed += 1


def main():
    os.makedirs(OUT, exist_ok=True)
    nodes, curves = build_graph()
    print("spaces:", len(nodes), "junctions:", sum(1 for n in nodes if n["kind"] == "junction"))
    img = ground()
    paths(img, curves)

    # 장식은 위에서 아래 순서로 (앞에 있는 게 나중에)
    decor = []
    corals = [(255, 130, 120), (250, 170, 110), (200, 140, 230), (255, 120, 170)]
    def add(y, f):
        decor.append((y, f))
    for reg, n, spread in (("coral", 26, 330), ("start", 6, 600), ("lagoon", 6, 380), ("beach", 5, 360)):
        for _ in range(n):
            x = R[reg][0] + rng.normal(0, spread)
            y = R[reg][1] + rng.normal(0, spread * 0.7)
            if RIM + 100 < x < W - RIM - 100 and RIM + 200 < y < H - RIM - 60 and not too_close(x, y, nodes, 115):
                kind = rng.random()
                if kind < 0.6:
                    add(y, lambda x=x, y=y, c=corals[rng.integers(4)], s=rng.uniform(90, 170): coral(img, x, y, s, c))
                else:
                    add(y, lambda x=x, y=y, c=corals[rng.integers(4)], s=rng.uniform(70, 120): sponge(img, x, y, s, c))
    for reg, n, spread, base in (("vents", 14, 420, (96, 106, 108)), ("wreck", 10, 420, (108, 118, 112)), ("kelp", 9, 380, (100, 122, 106)),
                                 ("start", 8, 900, (116, 130, 120)), ("beach", 6, 420, (170, 164, 144))):
        for _ in range(n):
            x = R[reg][0] + rng.normal(0, spread)
            y = R[reg][1] + rng.normal(0, spread * 0.7)
            if RIM + 100 < x < W - RIM - 100 and RIM + 150 < y < H - RIM - 60 and not too_close(x, y, nodes, 120):
                add(y, lambda x=x, y=y, r=rng.uniform(30, 80), c=base: rock(img, x, y, r, c))
    for _ in range(40):
        x, y = rng.uniform(RIM + 60, W - RIM - 60), rng.uniform(RIM + 60, H - RIM - 60)
        if not too_close(x, y, nodes, 90):
            if rng.random() < 0.5:
                add(y, lambda x=x, y=y, r=rng.uniform(14, 24): starfish(img, x, y, r, (240, 150, 100) if rng.random() < 0.6 else (250, 200, 110)))
            else:
                add(y, lambda x=x, y=y, r=rng.uniform(14, 22): shell(img, x, y, r))
    vents = []
    for _ in range(5):
        for _t in range(40):
            x = R["vents"][0] + rng.normal(0, 420)
            y = R["vents"][1] + rng.normal(0, 200)
            if RIM + 150 < y and not too_close(x, y, nodes, 140):
                vents.append((x, y))
                add(y, lambda x=x, y=y: vent(img, x, y, rng.uniform(22, 34)))
                break
    add(R["wreck"][1] - 160, lambda: wreck(img, R["wreck"][0] + 120, R["wreck"][1] - 160))
    add(R["wreck"][1] + 260, lambda: chest(img, R["wreck"][0] - 330, R["wreck"][1] + 250))
    add(R["lagoon"][1] + 120, lambda: clam(img, R["lagoon"][0] + 330, R["lagoon"][1] + 110))

    # 칸은 장식과 같은 줄 세우기에 끼워 넣어 앞뒤가 자연스럽게
    for n in nodes:
        add(n["y"], lambda n=n: stone(img, n["x"], n["y"], n["kind"]))
    for _, f in sorted(decor, key=lambda t: t[0]):
        f()

    # 다시마 위치 (Godot 에서 흔들리게 그림)
    kelp = []
    for _ in range(60):
        x = R["kelp"][0] + rng.normal(0, 420)
        y = R["kelp"][1] + rng.normal(0, 300)
        if RIM + 200 < x < W - RIM - 60 and RIM + 300 < y < H - RIM - 30 and not too_close(x, y, nodes, 100):
            kelp.append([round(x), round(y), round(float(rng.uniform(220, 480))), round(float(rng.uniform(0, 6.28)), 2)])
    for reg in ("coral", "lagoon", "beach", "start"):
        for _ in range(5):
            x = R[reg][0] + rng.normal(0, 500)
            y = R[reg][1] + rng.normal(0, 340)
            if RIM + 200 < x < W - RIM - 60 and RIM + 300 < y < H - RIM - 30 and not too_close(x, y, nodes, 110):
                kelp.append([round(x), round(y), round(float(rng.uniform(160, 300))), round(float(rng.uniform(0, 6.28)), 2)])

    img.save(os.path.join(OUT, "tutorial_map.png"))
    small = img.resize((1200, 800), Image.LANCZOS)
    small.save(os.path.join(HERE, "out", "tutorial_map_small.png"))
    data = {
        "size": [W, H],
        "rim": RIM,
        "start": 0,
        "spaces": [{"id": n["id"], "x": round(n["x"], 1), "y": round(n["y"], 1), "kind": n["kind"], "links": sorted(n["links"])} for n in nodes],
        "kelp": kelp,
        "vents": [[round(x), round(y)] for x, y in vents],
        "regions": {k: list(v) for k, v in R.items()},
    }
    with open(os.path.join(OUT, "tutorial_world.json"), "w") as f:
        json.dump(data, f)
    print("saved", OUT)


if __name__ == "__main__":
    main()
