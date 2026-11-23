"""보드게임 상자 그림 만들기 (보드 고르기 화면용).

    python render_boardbox.py
    → ../textures/boards/sunken_island_box.png   (상자 3/4 시점, 투명 배경)
       ../textures/boards/locked_box.png         (아직 없는 보드: 물음표 상자)
       ../textures/boards/box_shadow.png         (상자 밑 그림자, 따로 움직이도록)
       out/sunken_island_lid.png                  (뚜껑 그림 원본)

먼저 make_board_print.py 로 out/board_print.png 가 있어야 해요.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "textures", "boards")
FONT = os.path.join(ROOT, "fonts", "Poppins-Bold.ttf")

PEARL = (234, 255, 250)
AQUA = (127, 240, 219)
DEEP = (5, 48, 44)
PALETTE = {"coral": (255, 122, 107), "sand": (240, 212, 154), "mint": (79, 224, 200),
           "lavender": (180, 156, 255), "sky": (108, 184, 255)}

L = 2048  # 뚜껑 그림 크기


def lerp(a, b, t):
    return a + (b - a) * t


def rgba(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def font(size):
    return ImageFont.truetype(FONT, size)


def perspective_coeffs(dst, src):
    m = []
    for (x, y), (X, Y) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -X * x, -X * y])
        m.append([0, 0, 0, x, y, 1, -Y * x, -Y * y])
    return np.linalg.solve(np.array(m, np.float64), np.array(src, np.float64).reshape(8)).tolist()


def warp_onto(canvas_size, tex, quad):
    """tex 전체를 canvas 위 4점(quad: 왼위, 오위, 오아래, 왼아래)에 붙임."""
    w, h = tex.size
    coeffs = perspective_coeffs(quad, [(0, 0), (w, 0), (w, h), (0, h)])
    out = tex.transform(canvas_size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    mask = Image.new("L", canvas_size, 0)
    ImageDraw.Draw(mask).polygon([tuple(p) for p in quad], fill=255)
    a = np.minimum(np.asarray(out)[..., 3], np.asarray(mask))
    out.putalpha(Image.fromarray(a))
    return out


# ── 물속 배경 ────────────────────────────────────────────────
def water(size, sand_from=0.62):
    S = size
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    top = np.array([52, 200, 172], np.float32)
    mid = np.array([12, 112, 100], np.float32)
    bot = np.array([5, 50, 46], np.float32)
    t = y[..., None]
    col = np.where(t < 0.5, lerp(top, mid, t / 0.5), lerp(mid, bot, (t - 0.5) / 0.5))
    # 수면에서 일렁이는 빛 무늬: 부드럽고 옅게 (딱딱한 줄무늬처럼 보이지 않게 흐림)
    c = np.sin(x * 33 + np.sin(y * 19) * 2.2) * np.sin(y * 29 + np.sin(x * 14) * 2.5)
    c = np.clip(c, 0, 1) ** 2
    c = np.asarray(Image.fromarray((c * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(S * 0.006)), np.float32) / 255.0
    col += (c * np.clip(1 - y * 2.0, 0, 1))[..., None] * np.array([40, 66, 56], np.float32)
    # 빛줄기: 넓고 은은하게, 끝으로 갈수록 자연스럽게 사라짐 (경계가 칼같이 끊기지 않게)
    ang = np.arctan2(x - 0.3, y + 0.4)
    rays = 0.0
    for k, w, a in ((0.02, 0.07, 0.8), (0.2, 0.09, 0.6), (0.4, 0.07, 0.5), (0.6, 0.1, 0.45)):
        rays = rays + a * np.exp(-((ang - k) / w) ** 2)
    rays *= np.clip(1.0 - y * 1.3, 0, 1) ** 1.5
    col += rays[..., None] * np.array([30, 60, 52], np.float32)
    sand = np.array([86, 150, 116], np.float32)
    rip = 0.5 + 0.5 * np.sin(y * 140 + np.sin(x * 11) * 3.0)
    k = np.clip((y - sand_from) / 0.2, 0, 1) ** 1.4
    col = lerp(col, sand * (0.92 + 0.1 * rip[..., None]), (k * 0.85)[..., None])
    d = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2)
    col *= np.clip(1.2 - d * 0.8, 0.5, 1)[..., None]
    return rgba(np.concatenate([col, np.full((S, S, 1), 255, np.float32)], axis=2))


def pawn(tint, height_px):
    dif = Image.open(os.path.join(ROOT, "textures", "pawn_diffuse.png")).convert("RGBA")
    spc = Image.open(os.path.join(ROOT, "textures", "pawn_spec.png")).convert("RGBA")
    box = (104, 247, 536, 939)
    dif, spc = dif.crop(box), spc.crop(box)
    a = np.asarray(dif).astype(np.float32)
    a[..., :3] = a[..., :3] * np.array(tint, np.float32) / 255.0
    dif = rgba(a)
    dif.alpha_composite(spc)
    w = int(dif.width * height_px / dif.height)
    return dif.resize((w, height_px), Image.LANCZOS)


def place_pawn(img, tint, foot, h):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    w = h * 0.36
    ImageDraw.Draw(sh).ellipse([foot[0] - w * 0.9, foot[1] - w * 0.25, foot[0] + w * 1.15, foot[1] + w * 0.3],
                               fill=(0, 18, 24, 160))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(h * 0.035)))
    p = pawn(tint, int(h))
    img.alpha_composite(p, (int(foot[0] - p.width / 2), int(foot[1] - p.height + h * 0.025)))


def die(img, cx, cy, s, rot=0.0):
    d = ImageDraw.Draw(img)
    h = s * 1.1
    N, E, So, W = (cx, cy - 0.42 * s), (cx + s, cy), (cx, cy + 0.42 * s), (cx - s, cy)
    dn = lambda p: (p[0], p[1] + h)
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([cx - s * 1.3, cy + h - s * 0.15, cx + s * 1.6, cy + h + s * 0.7], fill=(0, 18, 24, 130))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(s * 0.2)))
    d = ImageDraw.Draw(img)
    d.polygon([W, So, dn(So), dn(W)], fill=(178, 208, 198, 255))
    d.polygon([So, E, dn(E), dn(So)], fill=(128, 162, 154, 255))
    d.polygon([N, E, So, W], fill=(214, 240, 230, 255))

    def pip(o, e1, e2, a, b, r):
        pts = [(o[0] + (a + r * math.cos(t)) * e1[0] + (b + r * math.sin(t)) * e2[0],
                o[1] + (a + r * math.cos(t)) * e1[1] + (b + r * math.sin(t)) * e2[1])
               for t in np.linspace(0, math.tau, 20, endpoint=False)]
        d.polygon(pts, fill=(18, 44, 44, 255))
    pip(W, (N[0] - W[0], N[1] - W[1]), (So[0] - W[0], So[1] - W[1]), 0.5, 0.5, 0.14)
    for a, b in ((0.3, 0.3), (0.7, 0.7)):
        pip(W, (So[0] - W[0], So[1] - W[1]), (0, h), a, b, 0.1)
    for a in (0.25, 0.5, 0.75):
        pip(So, (E[0] - So[0], E[1] - So[1]), (0, h), a, a, 0.09)
    d.line([W, So, E], fill=(255, 255, 255, 190), width=max(2, int(s * 0.05)))


def bubbles(img, items):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for cx, cy, r in items:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(200, 255, 240, 38), outline=(225, 255, 248, 200),
                  width=max(2, int(r / 7)))
        hr = r * 0.3
        d.ellipse([cx - r * 0.4 - hr, cy - r * 0.4 - hr * 0.7, cx - r * 0.4 + hr, cy - r * 0.4 + hr * 0.7],
                  fill=(255, 255, 255, 220))
    img.alpha_composite(layer)


def kelp(img, x0, y0, height, sway, width, color):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts_l, pts_r = [], []
    n = 30
    for i in range(n + 1):
        t = i / n
        x = x0 + math.sin(t * 3.0 + sway) * width * 1.6 * t
        y = y0 - height * t
        w = width * (1 - t * 0.85)
        pts_l.append((x - w, y))
        pts_r.append((x + w, y))
    d.polygon(pts_l + pts_r[::-1], fill=color)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(2)))


def text_block(img, text, center, size, fill=PEARL, outline=DEEP, stroke=None, rim=AQUA, shadow=True, spacing=0):
    f = font(size)
    stroke = stroke if stroke is not None else max(4, size // 9)
    d = ImageDraw.Draw(img)
    # 글자 사이 간격
    widths = [d.textlength(ch, font=f) for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = center[0] - total / 2
    asc, desc = f.getmetrics()
    y = center[1] - (asc + desc) / 2
    if shadow:
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        xx = x
        for ch, w in zip(text, widths):
            sd.text((xx, y + size * 0.07), ch, font=f, fill=(0, 20, 18, 170), stroke_width=stroke,
                    stroke_fill=(0, 20, 18, 170))
            xx += w + spacing
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(size * 0.05)))
        d = ImageDraw.Draw(img)
    xx = x
    for ch, w in zip(text, widths):
        d.text((xx, y), ch, font=f, fill=outline, stroke_width=stroke, stroke_fill=outline)
        if rim:
            d.text((xx, y - size * 0.035), ch, font=f, fill=rim)
        d.text((xx, y), ch, font=f, fill=fill)
        xx += w + spacing


def pill(img, text, center, size, bg=(5, 48, 44, 220), fg=PEARL, border=(127, 240, 219, 160), spacing=6):
    f = font(size)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    widths = [d.textlength(ch, font=f) for ch in text]
    tw = sum(widths) + spacing * (len(text) - 1)
    pad_x, pad_y = size * 0.9, size * 0.45
    asc, desc = f.getmetrics()
    th = asc + desc * 0.3
    box = [center[0] - tw / 2 - pad_x, center[1] - th / 2 - pad_y, center[0] + tw / 2 + pad_x, center[1] + th / 2 + pad_y]
    d.rounded_rectangle(box, radius=(box[3] - box[1]) / 2, fill=bg, outline=border, width=max(2, size // 12))
    x = center[0] - tw / 2
    for ch, w in zip(text, widths):
        d.text((x, center[1] - th / 2 - desc * 0.15), ch, font=f, fill=fg)
        x += w + spacing
    img.alpha_composite(layer)


# ── 뚜껑 그림 ────────────────────────────────────────────────
BOARD = [(1024, 1020), (1890, 1372), (1024, 1760), (158, 1372)]


def lid_art():
    img = water(L, sand_from=0.58)
    kelp(img, 120, 2048, 1100, 0.3, 34, (16, 92, 70, 200))
    kelp(img, 230, 2048, 800, 1.6, 26, (20, 110, 82, 190))
    kelp(img, 1930, 2048, 1000, 2.4, 30, (16, 92, 70, 200))

    # 보드판
    prn = Image.open(os.path.join(HERE, "out", "board_print.png")).convert("RGBA")
    thick = 70
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(x, y + thick + 30) for x, y in BOARD], fill=(0, 20, 18, 160))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(40)))
    side = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(side)
    l, b, r = BOARD[3], BOARD[2], BOARD[1]
    d.polygon([l, b, (b[0], b[1] + thick), (l[0], l[1] + thick)], fill=(18, 52, 92, 255))
    d.polygon([b, r, (r[0], r[1] + thick), (b[0], b[1] + thick)], fill=(10, 34, 66, 255))
    img.alpha_composite(side)
    top = warp_onto(img.size, prn, BOARD)
    arr = np.asarray(top).astype(np.float32)
    yy, xx = np.mgrid[0:L, 0:L].astype(np.float32) / L
    c = np.clip(np.sin(xx * 50 + np.sin(yy * 33) * 2.0) * np.sin(yy * 55 + np.sin(xx * 24) * 2.4), 0, 1) ** 2.5
    arr[..., :3] = arr[..., :3] * (0.84 + 0.45 * c[..., None])
    arr[..., :3] = lerp(arr[..., :3], np.array([30, 140, 125], np.float32), 0.12)
    img.alpha_composite(rgba(arr))
    edge = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).line([l, b, r], fill=(160, 225, 212, 170), width=5)
    img.alpha_composite(edge)

    # 말 4개 + 주사위
    place_pawn(img, PALETTE["mint"], (1330, 1265), 430)
    place_pawn(img, PALETTE["lavender"], (640, 1330), 410)
    die(img, 1470, 1440, 70)
    place_pawn(img, PALETTE["coral"], (1010, 1420), 560)
    place_pawn(img, PALETTE["sand"], (1530, 1600), 470)

    # 물빛 한 겹 + 물방울
    y = np.linspace(0, 1, L, dtype=np.float32)[:, None]
    haze = np.zeros((L, L, 4), np.float32)
    haze[..., 0], haze[..., 1], haze[..., 2] = 40, 190, 165
    haze[..., 3] = np.clip(0.55 - y, 0, 1) * 80
    img.alpha_composite(rgba(haze))
    bubbles(img, [(1660, 980, 46), (1730, 860, 32), (1690, 760, 22), (1760, 690, 15),
                  (380, 1080, 30), (330, 980, 20), (1240, 900, 18), (1200, 830, 12)])

    # 제목
    pill(img, "DEEP PARTY", (1024, 205), 62, spacing=10)
    text_block(img, "SUNKEN", (1024, 420), 250, spacing=10)
    text_block(img, "ISLAND", (1024, 655), 250, spacing=10)
    pill(img, "BOARD 01", (300, 1905), 46, spacing=6)
    pill(img, "1-4 PLAYERS", (1700, 1905), 46, spacing=6)

    # 테두리
    frame = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle([46, 46, L - 47, L - 47], radius=60, outline=(234, 255, 250, 120), width=6)
    d.rounded_rectangle([64, 64, L - 65, L - 65], radius=48, outline=(127, 240, 219, 70), width=3)
    img.alpha_composite(frame)
    return img


def tutorial_lid():
    """튜토리얼 월드 지도를 비스듬히 깔고, 말 하나가 그 안으로 뛰어드는 그림."""
    img = water(L, sand_from=0.5)
    world = Image.open(os.path.join(HERE, "out", "tutorial_map_small.png")).convert("RGBA")
    quad = [(330, 900), (1720, 900), (1960, 1820), (90, 1820)]
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(x + 16, y + 50) for x, y in quad], fill=(0, 20, 18, 170))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(36)))
    side = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(side).polygon([quad[3], quad[2], (quad[2][0], quad[2][1] + 40), (quad[3][0], quad[3][1] + 40)],
                                 fill=(10, 52, 60, 255))
    img.alpha_composite(side)
    img.alpha_composite(warp_onto(img.size, world, quad))
    # 지도 위로 뛰어드는 말 + 물방울 꼬리
    bubbles(img, [(1040, 1180, 34), (1080, 1080, 24), (1010, 990, 18), (1060, 910, 13), (1030, 850, 9)])
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([900, 1560, 1180, 1640], fill=(0, 18, 24, 140))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)))
    p = pawn(PALETTE["coral"], 430)
    img.alpha_composite(p, (int(1040 - p.width / 2), 1050))
    bubbles(img, [(1600, 980, 40), (1680, 870, 26), (1630, 780, 17), (420, 1040, 26), (380, 950, 16)])
    pill(img, "DEEP PARTY", (1024, 205), 62, spacing=10)
    text_block(img, "TUTORIAL", (1024, 470), 250, spacing=10)
    pill(img, "JUMP INTO THE BOARD", (1024, 720), 54, spacing=8)
    pill(img, "LEARN THE BASICS", (1024, 1915), 46, spacing=6)
    frame = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle([46, 46, L - 47, L - 47], radius=60, outline=(234, 255, 250, 120), width=6)
    d.rounded_rectangle([64, 64, L - 65, L - 65], radius=48, outline=(127, 240, 219, 70), width=3)
    img.alpha_composite(frame)
    return img


def locked_lid():
    img = water(L, sand_from=0.75)
    arr = np.asarray(img).astype(np.float32)
    arr[..., :3] *= 0.55
    img = rgba(arr)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # 물결 무늬
    for i in range(14):
        pts = [(x, 300 + i * 120 + 26 * math.sin(x / 120 + i)) for x in range(0, L + 20, 20)]
        d.line(pts, fill=(127, 240, 219, 28), width=6)
    d.ellipse([624, 524, 1424, 1324], fill=(5, 48, 44, 200), outline=(127, 240, 219, 150), width=10)
    img.alpha_composite(layer)
    text_block(img, "?", (1024, 940), 560, rim=AQUA)
    bubbles(img, [(1500, 600, 40), (1570, 490, 26), (520, 1400, 30), (470, 1310, 18)])
    frame = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle([46, 46, L - 47, L - 47], radius=60, outline=(234, 255, 250, 80), width=6)
    img.alpha_composite(frame)
    return img


def side_band(w, h, title, sub, dark=False):
    """상자 옆면 인쇄."""
    base = np.array([8, 78, 70] if not dark else [6, 46, 42], np.float32)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    col = base * (1.0 + 0.18 * (1 - y / h))[..., None]
    col += (np.sin(x / 38 + np.sin(y / 30) * 1.5) * 0.5 + 0.5)[..., None] * 6
    img = rgba(np.concatenate([col, np.full((h, w, 1), 255, np.float32)], axis=2))
    lines = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    ld.rectangle([0, int(h * 0.1), w, int(h * 0.1) + 5], fill=(127, 240, 219, 120))
    ld.rectangle([0, int(h * 0.86), w, int(h * 0.86) + 5], fill=(127, 240, 219, 120))
    img.alpha_composite(lines)
    d = ImageDraw.Draw(img)
    if title:
        f = font(int(h * 0.34))
        d.text((w * 0.05, h * 0.27), title, font=f, fill=PEARL, stroke_width=4, stroke_fill=DEEP)
    if sub:
        f2 = font(int(h * 0.19))
        tw = d.textlength(sub, font=f2)
        d.text((w * 0.95 - tw, h * 0.39), sub, font=f2, fill=AQUA)
    return img


# ── 상자 3D ──────────────────────────────────────────────────
W_OUT, H_OUT = 1200, 1100
SS = 2
BOX_H = 0.2          # 상자 높이 (가로세로 1 기준)
YAW = math.radians(30)
ELEV = math.radians(36)
DIST = 3.6
FOV = math.radians(30)


def project(p):
    x, y, z = p
    cx, sx = math.cos(YAW), math.sin(YAW)
    x, z = x * cx - z * sx, x * sx + z * cx            # 상자 돌리기
    ce, se = math.cos(ELEV), math.sin(ELEV)
    # 카메라: 앞(+z)쪽 위에서 내려다봄
    yc = y * ce - z * se
    zc = y * se + z * ce
    depth = DIST - zc
    f = (H_OUT * SS * 0.5) / math.tan(FOV / 2)
    return (W_OUT * SS / 2 + x * f / depth, H_OUT * SS * 0.56 - (yc - 0.1) * f / depth)


def shade(img, factor, grad=None):
    a = np.asarray(img).astype(np.float32)
    g = factor if grad is None else factor * grad[..., None]
    a[..., :3] *= g
    return rgba(a)


def render_box(lid, front_tex, right_tex, name):
    size = (W_OUT * SS, H_OUT * SS)
    h = BOX_H
    P = {k: project(v) for k, v in {
        "tlb": (-0.5, h, -0.5), "trb": (0.5, h, -0.5), "trf": (0.5, h, 0.5), "tlf": (-0.5, h, 0.5),
        "blf": (-0.5, 0, 0.5), "brf": (0.5, 0, 0.5), "brb": (0.5, 0, -0.5),
    }.items()}
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))

    # 앞면 / 오른쪽 면
    yy, xx = np.mgrid[0:size[1], 0:size[0]].astype(np.float32)
    front = warp_onto(size, front_tex, [P["tlf"], P["trf"], P["brf"], P["blf"]])
    right = warp_onto(size, right_tex, [P["trf"], P["trb"], P["brb"], P["brf"]])
    gy = np.clip(1.0 - (yy - P["tlf"][1]) / (P["blf"][1] - P["tlf"][1] + 1) * 0.25, 0.7, 1.0)
    canvas.alpha_composite(shade(front, 0.86, gy))
    canvas.alpha_composite(shade(right, 0.6, gy))

    # 뚜껑
    top = warp_onto(size, lid, [P["tlb"], P["trb"], P["trf"], P["tlf"]])
    # 빛: 왼쪽 뒤가 밝고 오른쪽 앞이 살짝 어둡게 + 대각선 반사
    lx = (xx - P["tlf"][0]) / (P["trb"][0] - P["tlf"][0] + 1)
    grad = 1.04 - 0.12 * np.clip(lx, 0, 1)
    top = shade(top, 1.0, grad)
    sheen = np.zeros((size[1], size[0], 4), np.float32)
    band = np.exp(-(((xx - P["tlb"][0]) * 0.7 + (yy - P["tlb"][1]) * 1.0 - 900) / 260) ** 2)
    sheen[..., :3] = 255
    sheen[..., 3] = band * 34
    top_a = np.asarray(top)[..., 3].astype(np.float32) / 255
    sheen[..., 3] *= top_a
    canvas.alpha_composite(top)
    canvas.alpha_composite(rgba(sheen))

    d = ImageDraw.Draw(canvas)
    # 뚜껑 이음선 (불투명) (아래쪽에 상자 몸통이 살짝)
    seam = 0.03
    a1, a2, a3 = project((-0.5, seam, 0.5)), project((0.5, seam, 0.5)), project((0.5, seam, -0.5))
    d.polygon([a1, a2, P["brf"], P["blf"]], fill=(4, 34, 32, 255))
    d.polygon([a2, a3, P["brb"], P["brf"]], fill=(3, 24, 22, 255))
    d.line([a1, a2, a3], fill=(0, 14, 12, 255), width=4)
    # 모서리 하이라이트 + 닳은 자국 (반투명이라 따로 그려 겹치기)
    hl = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(hl)
    d.line([P["tlf"], P["trf"]], fill=(234, 255, 250, 210), width=6)
    d.line([P["trf"], P["trb"]], fill=(234, 255, 250, 140), width=5)
    d.line([P["tlb"], P["tlf"]], fill=(234, 255, 250, 110), width=4)
    d.line([P["tlf"], P["blf"]], fill=(234, 255, 250, 90), width=4)
    d.line([P["trf"], P["brf"]], fill=(234, 255, 250, 150), width=5)
    rng = np.random.default_rng(3)
    for e0, e1 in ((P["tlf"], P["trf"]), (P["trf"], P["trb"]), (P["trf"], P["brf"])):
        for _ in range(8):
            t = rng.uniform(0.05, 0.95)
            px, py = e0[0] + (e1[0] - e0[0]) * t, e0[1] + (e1[1] - e0[1]) * t
            r = rng.uniform(2.0, 4.0)
            d.ellipse([px - r, py - r, px + r, py + r], fill=(234, 255, 250, int(rng.uniform(40, 90))))
    canvas.alpha_composite(hl)

    # 아주 약한 종이 결
    noise = rng.normal(0, 4, (size[1], size[0], 1)).astype(np.float32)
    arr = np.asarray(canvas).astype(np.float32)
    arr[..., :3] += noise
    canvas = rgba(arr)

    return canvas.resize((W_OUT, H_OUT), Image.LANCZOS)


def render_shadow():
    size = (W_OUT * SS, H_OUT * SS)
    pts = [project(p) for p in ((-0.55, 0, -0.55), (0.55, 0, -0.55), (0.55, 0, 0.55), (-0.55, 0, 0.55))]
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(img).polygon(pts, fill=(0, 16, 14, 200))
    return img.filter(ImageFilter.GaussianBlur(50)).resize((W_OUT, H_OUT), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    lid = lid_art()
    lid.convert("RGB").save(os.path.join(HERE, "out", "sunken_island_lid.png"))
    side_w, side_h = 2048, int(2048 * BOX_H)
    box = render_box(lid, side_band(side_w, side_h, "SUNKEN ISLAND", "BOARD 01"),
                     side_band(side_w, side_h, "DEEP PARTY", "1-4 PLAYERS", dark=True), "sunken_island_box.png")
    locked = render_box(locked_lid(), side_band(side_w, side_h, "", "", dark=True),
                        side_band(side_w, side_h, "", "", dark=True), "locked_box.png")
    tut = render_box(tutorial_lid(), side_band(side_w, side_h, "TUTORIAL", "PRACTICE WORLD"),
                     side_band(side_w, side_h, "DEEP PARTY", "LEARN THE BASICS", dark=True), "tutorial_box.png")
    shadow = render_shadow()
    # 셋 다 같은 영역으로 잘라서 Godot 에서 같은 자리에 겹쳐 그리면 딱 맞게
    union = Image.new("RGBA", box.size)
    for im in (box, shadow):
        union.alpha_composite(im)
    bb = union.getbbox()
    box.crop(bb).save(os.path.join(OUT, "sunken_island_box.png"))
    locked.crop(bb).save(os.path.join(OUT, "locked_box.png"))
    tut.crop(bb).save(os.path.join(OUT, "tutorial_box.png"))
    shadow.crop(bb).save(os.path.join(OUT, "box_shadow.png"))
    print("saved to", OUT)


if __name__ == "__main__":
    main()
