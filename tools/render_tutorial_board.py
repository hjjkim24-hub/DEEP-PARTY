"""튜토리얼 보드 만들기.

    python render_tutorial_board.py
    → out/tutorial_board_print.png                 (위에서 본 판 그림 2048x2048)
       ../textures/boards/tutorial_board_scene.png  (모래 위 판, 1920x1080, 위쪽은 투명 → 물 셰이더가 보임)
       ../textures/boards/tutorial_board_marks.json (칸 중심 화면 좌표 + 크기, Godot 이 말을 놓을 때 씀)

칸 16개가 판 가장자리를 한 바퀴 돌아요. 0번이 START, 나머지는 1~15 번호.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "textures", "boards")
FONT = os.path.join(ROOT, "fonts", "Poppins-Bold.ttf")
N = 2048
W, H = 1920, 1080
SS = 2

PEARL = (234, 255, 250)
AQUA = (127, 240, 219)
DEEP = (5, 48, 44)
TILE_COLORS = [(79, 224, 200), (108, 184, 255), (240, 212, 154), (180, 156, 255)]


def font(s):
    return ImageFont.truetype(FONT, int(s))


def rgba(a):
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


# ── 칸 위치 (판 그림 좌표) ────────────────────────────────────
MARGIN = 300
STEP = (N - 2 * MARGIN) / 4


def tile_centers():
    """5x5 격자의 바깥 테두리 16칸. 0번(START)은 왼쪽 아래, 시계 반대 방향... 이 아니라
    화면에서 보기 좋게: 아래쪽 줄 왼→오, 오른쪽 줄 아래→위, 위쪽 줄 오→왼, 왼쪽 줄 위→아래."""
    pts = []
    for i in range(5):                      # 아래 줄
        pts.append((MARGIN + i * STEP, N - MARGIN))
    for i in range(1, 5):                   # 오른쪽 줄
        pts.append((N - MARGIN, N - MARGIN - i * STEP))
    for i in range(1, 5):                   # 위 줄
        pts.append((N - MARGIN - i * STEP, MARGIN))
    for i in range(1, 4):                   # 왼쪽 줄
        pts.append((MARGIN, MARGIN + i * STEP))
    return pts


def board_print():
    y, x = np.mgrid[0:N, 0:N].astype(np.float32) / N
    base = np.array([16, 96, 104], np.float32)
    col = base * (1.0 + 0.12 * np.sin(x * 9 + y * 4))[..., None]
    wav = (np.sin((x + 0.15 * np.sin(y * 9)) * 70) * 0.5 + 0.5) ** 6
    col += wav[..., None] * np.array([10, 30, 26], np.float32)
    img = rgba(np.concatenate([col, np.full((N, N, 1), 255, np.float32)], axis=2))
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.rounded_rectangle([40, 40, N - 41, N - 41], 90, outline=(234, 255, 250, 200), width=14)
    d.rounded_rectangle([78, 78, N - 79, N - 79], 70, outline=(127, 240, 219, 120), width=5)
    img.alpha_composite(lay)

    pts = tile_centers()
    # 길 (칸 사이 점선)
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        for t in np.linspace(0.22, 0.78, 6):
            px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            d.ellipse([px - 12, py - 12, px + 12, py + 12], fill=(234, 255, 250, 150))
    img.alpha_composite(lay)

    d = ImageDraw.Draw(img)
    ts = 170
    for i, (cx, cy) in enumerate(pts):
        if i == 0:
            r = ts * 0.75
            d.rounded_rectangle([cx - r, cy - r, cx + r, cy + r], 44, fill=PEARL, outline=DEEP, width=12)
            f = font(58)
            tw = d.textlength("START", font=f)
            d.text((cx - tw / 2, cy - 38), "START", font=f, fill=DEEP)
            # 화살표
            d.polygon([(cx + r + 30, cy - 40), (cx + r + 90, cy), (cx + r + 30, cy + 40)], fill=PEARL)
            continue
        c = TILE_COLORS[i % len(TILE_COLORS)]
        r = ts * 0.58
        d.rounded_rectangle([cx - r, cy - r + 14, cx + r, cy + r + 14], 40, fill=(4, 34, 32))
        d.rounded_rectangle([cx - r, cy - r, cx + r, cy + r], 40, fill=c, outline=PEARL, width=8)
        f = font(110)
        s = str(i)
        tw = d.textlength(s, font=f)
        d.text((cx - tw / 2, cy - 78), s, font=f, fill=DEEP)

    # 가운데 글씨
    def centered(text, cy, size, fill, stroke=0, sfill=DEEP, spacing=0):
        f = font(size)
        ws = [d.textlength(ch, font=f) for ch in text]
        x = N / 2 - (sum(ws) + spacing * (len(text) - 1)) / 2
        for ch, w in zip(text, ws):
            d.text((x, cy), ch, font=f, fill=fill, stroke_width=stroke, stroke_fill=sfill)
            x += w + spacing
    centered("DEEP PARTY", 690, 72, AQUA, spacing=12)
    centered("TUTORIAL", 800, 230, PEARL, stroke=14, spacing=8)
    centered("PRACTICE BOARD", 1090, 70, AQUA, spacing=10)
    # 조개 무늬
    cx, cy = N / 2, 1360
    for k in range(7):
        a = math.radians(200 + k * 20)
        d.line([(cx, cy + 60), (cx + math.cos(a) * 150, cy + 60 + math.sin(a) * 150)], fill=(234, 255, 250, 255), width=10)
    d.arc([cx - 150, cy - 90, cx + 150, cy + 210], 200, 340, fill=PEARL, width=12)
    return img


# ── 장면 ─────────────────────────────────────────────────────
def homography(src, dst):
    m = []
    for (x, y), (X, Y) in zip(src, dst):
        m.append([x, y, 1, 0, 0, 0, -X * x, -X * y])
        m.append([0, 0, 0, x, y, 1, -Y * x, -Y * y])
    h = np.linalg.solve(np.array(m, np.float64), np.array(dst, np.float64).reshape(8))
    return np.append(h, 1.0).reshape(3, 3)


def apply_h(Hm, p):
    v = Hm @ np.array([p[0], p[1], 1.0])
    return v[0] / v[2], v[1] / v[2]


# 판 네 꼭짓점 (화면 1920x1080, 위에서 비스듬히 내려다본 모양)
QUAD = [(560, 250), (1500, 250), (1700, 900), (360, 900)]   # 왼위, 오위, 오아래, 왼아래
THICK = 34


def scene(prn):
    S = (W * SS, H * SS)
    q = [(x * SS, y * SS) for x, y in QUAD]
    y, x = np.mgrid[0:S[1], 0:S[0]].astype(np.float32)
    yn, xn = y / S[1], x / S[0]
    # 모래 바닥 (위쪽은 물로 사라짐 = 투명)
    sand = np.array([92, 156, 122], np.float32)
    rip = 0.5 + 0.5 * np.sin(yn * 160 + np.sin(xn * 13) * 3.0 + xn * 6)
    col = sand * (0.9 + 0.12 * rip[..., None])
    c = np.clip(np.sin(xn * 60 + np.sin(yn * 37) * 2.0) * np.sin(yn * 66 + np.sin(xn * 29) * 2.4), 0, 1) ** 2.5
    col *= (0.9 + 0.35 * c)[..., None]
    alpha = np.clip((yn - 0.04) / 0.32, 0, 1) ** 1.2 * 255
    img = rgba(np.concatenate([col, alpha[..., None]], axis=2))

    # 판 그림자
    sh = Image.new("RGBA", S, (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(px + 26 * SS, py + (THICK + 30) * SS) for px, py in q], fill=(0, 22, 20, 170))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(30 * SS)))
    # 판 두께 (앞면)
    side = Image.new("RGBA", S, (0, 0, 0, 0))
    d = ImageDraw.Draw(side)
    bl, br = q[3], q[2]
    d.polygon([bl, br, (br[0], br[1] + THICK * SS), (bl[0], bl[1] + THICK * SS)], fill=(10, 52, 60, 255))
    tr = q[1]
    d.polygon([br, tr, (tr[0], tr[1] + THICK * SS * 0.4), (br[0], br[1] + THICK * SS)], fill=(6, 38, 44, 255))
    img.alpha_composite(side)

    # 윗면
    Hm = homography([(0, 0), (N, 0), (N, N), (0, N)], q)
    Hinv = np.linalg.inv(Hm)
    coeffs = (Hinv / Hinv[2, 2]).flatten()[:8].tolist()
    top = prn.transform(S, Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    mask = Image.new("L", S, 0)
    ImageDraw.Draw(mask).polygon(q, fill=255)
    top.putalpha(mask)
    a = np.asarray(top).astype(np.float32)
    a[..., :3] *= (0.86 + 0.35 * c)[..., None]
    a[..., :3] = a[..., :3] * 0.9 + np.array([20, 120, 110], np.float32) * 0.1
    img.alpha_composite(rgba(a))
    edge = Image.new("RGBA", S, (0, 0, 0, 0))
    ImageDraw.Draw(edge).line([q[3], q[2], q[1]], fill=(200, 245, 235, 170), width=3 * SS)
    img.alpha_composite(edge)

    img = img.resize((W, H), Image.LANCZOS)
    # 칸 위치 (화면 좌표) + 크기
    Hs = homography([(0, 0), (N, 0), (N, N), (0, N)], QUAD)
    marks = []
    for i, p in enumerate(tile_centers()):
        cx, cy = apply_h(Hs, p)
        l = apply_h(Hs, (p[0] - STEP * 0.3, p[1]))
        r = apply_h(Hs, (p[0] + STEP * 0.3, p[1]))
        marks.append({"i": i, "x": round(cx, 1), "y": round(cy, 1), "w": round(math.dist(l, r), 1)})
    return img, marks


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    prn = board_print()
    prn.convert("RGB").save(os.path.join(HERE, "out", "tutorial_board_print.png"))
    img, marks = scene(prn)
    img.save(os.path.join(OUT, "tutorial_board_scene.png"))
    with open(os.path.join(OUT, "tutorial_board_marks.json"), "w") as f:
        json.dump({"size": [W, H], "tiles": marks}, f, indent=1)
    print("tiles:", len(marks), "first:", marks[0], "last:", marks[-1])


if __name__ == "__main__":
    main()
