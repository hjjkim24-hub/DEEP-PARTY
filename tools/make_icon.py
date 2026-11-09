"""DEEP PARTY 게임 아이콘 만들기.

바닷속 에메랄드 물 + 가라앉은 보드판 + 실사풍 말 + 물방울.
결과: ../icon.png (1024, Godot 프로젝트/창 아이콘), ../icon.ico (16~256, exe 아이콘)

    python make_icon.py          (먼저 make_board_print.py 로 out/board_print.png 가 있어야 함)
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SS = 2                      # 슈퍼샘플링
S = 1024 * SS
RADIUS = 210 * SS           # 둥근 사각형 모서리
PAWN_TINT = (255, 122, 107)  # Coral (GameState.PALETTE[0])


def u(v):
    return int(round(v * SS))


def lerp(a, b, t):
    return a + (b - a) * t


def rgba(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


# ── 1. 물 배경 ───────────────────────────────────────────────
def water():
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    top = np.array([46, 196, 170], np.float32)      # 수면 쪽 밝은 에메랄드
    mid = np.array([12, 110, 98], np.float32)
    bot = np.array([4, 44, 40], np.float32)         # deep 05302c 근처
    t = y[..., None]
    col = np.where(t < 0.45, lerp(top, mid, t / 0.45), lerp(mid, bot, (t - 0.45) / 0.55))

    # 수면 빛무늬 (위쪽에만)
    c = (np.sin(x * 31 + np.sin(y * 17) * 2.2) * np.sin(y * 27 + np.sin(x * 13) * 2.5))
    c = np.clip(c, 0, 1) ** 3
    col += (c * np.clip(1 - y * 2.2, 0, 1))[..., None] * np.array([90, 140, 120], np.float32)

    # 빛줄기 (왼쪽 위에서 비스듬히)
    ang = np.arctan2(x - 0.22, y + 0.35)
    rays = 0.0
    for k, w, a in ((0.10, 0.035, 1.0), (0.32, 0.05, 0.8), (0.55, 0.03, 0.7), (0.78, 0.045, 0.6)):
        rays = rays + a * np.exp(-((ang - (k - 0.15)) / w) ** 2)
    rays *= np.clip(1.1 - y * 1.2, 0, 1)
    col += rays[..., None] * np.array([60, 110, 95], np.float32)

    # 모래 바닥 (아래쪽, 멀수록 물빛에 묻힘)
    sand = np.array([88, 150, 118], np.float32)
    rip = 0.5 + 0.5 * np.sin(y * 120 + np.sin(x * 9) * 3.0)
    sand_col = sand * (0.92 + 0.1 * rip[..., None])
    k = np.clip((y - 0.56) / 0.22, 0, 1) ** 1.4
    col = lerp(col, sand_col, (k * 0.85)[..., None])

    # 가장자리 어둡게
    d = np.sqrt((x - 0.5) ** 2 + (y - 0.45) ** 2)
    col *= np.clip(1.15 - d * 0.75, 0.55, 1)[..., None]
    a = np.full((S, S, 1), 255, np.float32)
    return rgba(np.concatenate([col, a], axis=2))


# ── 2. 보드판 (원근 변환) ─────────────────────────────────────
def perspective_coeffs(dst, src):
    """dst 사각형의 점 → src 이미지 좌표 로 가는 PIL PERSPECTIVE 계수."""
    m = []
    for (x, y), (X, Y) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -X * x, -X * y])
        m.append([0, 0, 0, x, y, 1, -Y * x, -Y * y])
    b = np.array(src, np.float64).reshape(8)
    return np.linalg.solve(np.array(m, np.float64), b).tolist()


BOARD = [(u(512), u(500)), (u(930), u(668)), (u(512), u(850)), (u(94), u(668))]  # 위, 오른쪽, 아래, 왼쪽
THICK = u(46)


def board_layers():
    prn = Image.open(os.path.join(HERE, "out", "board_print.png")).convert("RGBA")
    n = prn.width
    # 판 그림의 왼쪽 위 모서리를 화면 위쪽 꼭짓점에 맞춤 (45° 돌린 모양)
    src = [(0, 0), (n, 0), (n, n), (0, n)]
    coeffs = perspective_coeffs(BOARD, src)
    top = prn.transform((S, S), Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(BOARD, fill=255)
    top.putalpha(mask)

    # 윗면 위 빛무늬 + 물속 흡수(먼 쪽은 물빛으로)
    arr = np.asarray(top).astype(np.float32)
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    c = np.sin(x * 46 + np.sin(y * 31) * 2.0) * np.sin(y * 52 + np.sin(x * 23) * 2.4)
    c = np.clip(c, 0, 1) ** 2.5
    arr[..., :3] = arr[..., :3] * (0.82 + 0.5 * c[..., None])
    fog = np.clip((0.66 - y) / 0.2, 0, 1)[..., None] * 0.35
    arr[..., :3] = lerp(arr[..., :3], np.array([20, 120, 108], np.float32), fog)
    arr[..., :3] = lerp(arr[..., :3], np.array([30, 140, 125], np.float32), 0.12)
    top = rgba(arr)

    # 옆면 두께
    side = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(side)
    l, b, r = BOARD[3], BOARD[2], BOARD[1]
    d.polygon([l, b, (b[0], b[1] + THICK), (l[0], l[1] + THICK)], fill=(18, 52, 92, 255))
    d.polygon([b, r, (r[0], r[1] + THICK), (b[0], b[1] + THICK)], fill=(10, 34, 66, 255))
    d.line([l, b, r], fill=(160, 220, 210, 160), width=u(3))      # 모서리 하이라이트
    return top, side


# ── 3. 말 ────────────────────────────────────────────────────
def pawn(height_px):
    dif = Image.open(os.path.join(ROOT, "textures", "pawn_diffuse.png")).convert("RGBA")
    spc = Image.open(os.path.join(ROOT, "textures", "pawn_spec.png")).convert("RGBA")
    box = (104, 247, 536, 939)
    dif, spc = dif.crop(box), spc.crop(box)
    a = np.asarray(dif).astype(np.float32)
    a[..., :3] = a[..., :3] * np.array(PAWN_TINT, np.float32) / 255.0
    dif = rgba(a)
    dif.alpha_composite(spc)
    w = int(dif.width * height_px / dif.height)
    return dif.resize((w, height_px), Image.LANCZOS)


# ── 4. 주사위 ────────────────────────────────────────────────
def die(cx, cy, s):
    cx, cy, s = u(cx), u(cy), u(s)
    h = s * 1.1
    N, E, So, W = (cx, cy - 0.4 * s), (cx + s, cy), (cx, cy + 0.4 * s), (cx - s, cy)
    dn = lambda p: (p[0], p[1] + h)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - s * 1.3, cy + h - s * 0.1, cx + s * 1.5, cy + h + s * 0.75], fill=(0, 20, 24, 120))
    layer = layer.filter(ImageFilter.GaussianBlur(u(10)))
    d = ImageDraw.Draw(layer)
    d.polygon([W, So, dn(So), dn(W)], fill=(176, 206, 196, 255))
    d.polygon([So, E, dn(E), dn(So)], fill=(126, 160, 152, 255))
    d.polygon([N, E, So, W], fill=(212, 238, 228, 255))

    def pip(o, e1, e2, a, b, r):
        pts = []
        for i in range(20):
            t = i / 20 * math.tau
            uu, vv = a + r * math.cos(t), b + r * math.sin(t)
            pts.append((o[0] + uu * e1[0] + vv * e2[0], o[1] + uu * e1[1] + vv * e2[1]))
        d.polygon(pts, fill=(18, 44, 44, 255))
    top_o, top_e1, top_e2 = W, (N[0] - W[0], N[1] - W[1]), (So[0] - W[0], So[1] - W[1])
    pip(top_o, top_e1, top_e2, 0.5, 0.5, 0.15)                       # 윗면 1
    lf_e1, lf_e2 = (So[0] - W[0], So[1] - W[1]), (0, h)
    for a, b in ((0.3, 0.3), (0.7, 0.7)):                              # 왼쪽 2
        pip(W, lf_e1, lf_e2, a, b, 0.11)
    rf_e1, rf_e2 = (E[0] - So[0], E[1] - So[1]), (0, h)
    for a, b in ((0.27, 0.27), (0.5, 0.5), (0.73, 0.73)):            # 오른쪽 3
        pip(So, rf_e1, rf_e2, a, b, 0.1)
    d.line([W, So, E], fill=(255, 255, 255, 200), width=u(2))
    return layer


# ── 5. 물방울 ────────────────────────────────────────────────
def bubbles():
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for cx, cy, r in ((735, 400, 34), (790, 300, 24), (752, 215, 17), (812, 150, 12), (680, 300, 10),
                      (300, 330, 14), (262, 250, 9)):
        cx, cy, r = u(cx), u(cy), u(r)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(200, 255, 240, 40),
                  outline=(225, 255, 248, 210), width=max(2, r // 7))
        hr = r * 0.32
        hx, hy = cx - r * 0.38, cy - r * 0.38
        d.ellipse([hx - hr, hy - hr * 0.7, hx + hr, hy + hr * 0.7], fill=(255, 255, 255, 230))
    return layer


def main():
    img = water()

    # 판 아래 그림자
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(x, y + THICK + u(18)) for x, y in BOARD], fill=(0, 20, 18, 150))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(u(26))))

    top, side = board_layers()
    img.alpha_composite(side)
    img.alpha_composite(top)

    img.alpha_composite(die(792, 652, 44))

    # 말 + 발밑 그림자
    p = pawn(u(560))
    foot = (u(505), u(700))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([foot[0] - u(150), foot[1] - u(40), foot[0] + u(190), foot[1] + u(46)],
                                   fill=(0, 18, 24, 170))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(u(18))))
    img.alpha_composite(p, (foot[0] - p.width // 2, foot[1] - p.height + u(14)))

    # 위에서 내려오는 물빛 한 겹 (말도 물에 잠긴 느낌)
    y = np.linspace(0, 1, S, dtype=np.float32)[:, None]
    haze = np.zeros((S, S, 4), np.float32)
    haze[..., 0], haze[..., 1], haze[..., 2] = 40, 190, 165
    haze[..., 3] = np.clip(0.6 - y, 0, 1) * 70
    img.alpha_composite(rgba(haze))

    img.alpha_composite(bubbles())

    # 둥근 사각형으로 자르기 + 안쪽 테두리
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], RADIUS, fill=255)
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([u(6), u(6), S - u(7), S - u(7)], RADIUS - u(6),
                                          outline=(127, 240, 219, 150), width=u(5))
    img.alpha_composite(rim)
    img.putalpha(mask)

    out = img.resize((1024, 1024), Image.LANCZOS)
    out.save(os.path.join(ROOT, "icon.png"))
    out.save(os.path.join(ROOT, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                                                    (64, 64), (128, 128), (256, 256)])
    print("icon.png, icon.ico 저장")


if __name__ == "__main__":
    main()
