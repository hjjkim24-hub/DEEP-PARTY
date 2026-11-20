"""상점 아이템 그림 (색 있는 평면 그림, 128x128) → textures/ui/items/
  dice.png    : 추가 주사위 (1~3 눈만 있는 작은 주사위 + 더하기)
  scroll.png  : 순간이동서 (돌돌 말린 양피지 + 소용돌이 문양)
  conch.png   : 덫 탐지 소라 (나선 소라껍데기)
  oxygen.png  : 산소통 (노란 잠수용 통 + 밸브 · 압력계)
  net.png     : 그물 (둥근 그물 뭉치 + 찌)
    python3 tools/make_item_icons.py"""
import math
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "textures", "ui", "items")
S = 512
EDGE = (60, 35, 18, 255)


def new():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def save(im, name):
    im.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


def dice():
    im, d = new()
    d.rounded_rectangle([S * 0.12, S * 0.2, S * 0.72, S * 0.8], radius=60, fill=EDGE)
    d.rounded_rectangle([S * 0.15, S * 0.23, S * 0.69, S * 0.77], radius=50, fill=(250, 246, 236, 255))
    for x, y in [(0.27, 0.35), (0.42, 0.5), (0.57, 0.65)]:
        d.ellipse([S * x - 30, S * y - 30, S * x + 30, S * y + 30], fill=(200, 40, 50, 255))
    d.ellipse([S * 0.6, S * 0.06, S * 0.94, S * 0.4], fill=EDGE)
    d.ellipse([S * 0.63, S * 0.09, S * 0.91, S * 0.37], fill=(80, 170, 90, 255))
    d.rectangle([S * 0.75, S * 0.14, S * 0.79, S * 0.32], fill=(255, 255, 255, 255))
    d.rectangle([S * 0.68, S * 0.21, S * 0.86, S * 0.25], fill=(255, 255, 255, 255))
    save(im, "dice")


def scroll():
    im, d = new()
    d.rounded_rectangle([S * 0.16, S * 0.22, S * 0.84, S * 0.78], radius=20, fill=EDGE)
    d.rectangle([S * 0.2, S * 0.26, S * 0.8, S * 0.74], fill=(236, 214, 165, 255))
    for x in (0.12, 0.88):     # 양쪽 말린 부분
        d.ellipse([S * (x - 0.08), S * 0.16, S * (x + 0.08), S * 0.84], fill=EDGE)
        d.ellipse([S * (x - 0.06), S * 0.18, S * (x + 0.06), S * 0.82], fill=(214, 186, 128, 255))
        d.ellipse([S * (x - 0.025), S * 0.44, S * (x + 0.025), S * 0.56], fill=(150, 110, 60, 255))
    c = S / 2                  # 보랏빛 소용돌이
    for k in range(700):
        t = k / 699
        a = t * math.pi * 3.2
        r = S * (0.02 + 0.17 * t)
        x, y = c + math.cos(a) * r, c + math.sin(a) * r * 0.85
        rr = 7 + 9 * t
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(120, 70, 200, 255))
    save(im, "scroll")


def conch():
    im, d = new()
    # 나선 몸통: 커지는 원들을 겹쳐 그리고 줄무늬
    pts = []
    for k in range(60):
        t = k / 59
        a = -t * math.pi * 1.6 + 0.6
        r = S * (0.03 + 0.2 * t)
        x = S * 0.38 + math.cos(a) * r * 0.9 + t * S * 0.08
        y = S * 0.34 + math.sin(a) * r * 0.6 + t * S * 0.22
        pts.append((x, y, S * (0.04 + 0.2 * t)))
    for x, y, r in pts:
        d.ellipse([x - r - 10, y - r - 10, x + r + 10, y + r + 10], fill=EDGE)
    for i, (x, y, r) in enumerate(pts):
        col = (245, 205, 160, 255) if (i // 6) % 2 == 0 else (230, 160, 110, 255)
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)
    x, y, r = pts[-1]          # 입구: 분홍빛 안쪽
    d.ellipse([x - r * 0.75, y - r * 0.45, x + r * 0.75, y + r * 0.7], fill=(240, 130, 140, 255))
    d.ellipse([x - r * 0.45, y - r * 0.2, x + r * 0.45, y + r * 0.45], fill=(200, 80, 100, 255))
    # 뾰족한 끝
    d.polygon([(S * 0.3, S * 0.3), (S * 0.12, S * 0.12), (S * 0.36, S * 0.22)], fill=EDGE)
    d.polygon([(S * 0.31, S * 0.29), (S * 0.16, S * 0.15), (S * 0.35, S * 0.24)], fill=(245, 215, 175, 255))
    save(im, "conch")


def oxygen():
    im, d = new()
    d.rounded_rectangle([S * 0.28, S * 0.2, S * 0.72, S * 0.94], radius=90, fill=EDGE)
    d.rounded_rectangle([S * 0.31, S * 0.23, S * 0.69, S * 0.91], radius=80, fill=(245, 190, 40, 255))
    d.rectangle([S * 0.31, S * 0.55, S * 0.69, S * 0.6], fill=(60, 60, 65, 255))      # 띠
    d.rectangle([S * 0.36, S * 0.3, S * 0.42, S * 0.85], fill=(255, 225, 120, 255))   # 반짝
    d.rectangle([S * 0.44, S * 0.08, S * 0.56, S * 0.24], fill=EDGE)                  # 밸브
    d.rectangle([S * 0.47, S * 0.1, S * 0.53, S * 0.24], fill=(170, 175, 180, 255))
    d.rounded_rectangle([S * 0.36, S * 0.04, S * 0.64, S * 0.11], radius=12, fill=(200, 50, 40, 255))
    d.ellipse([S * 0.58, S * 0.1, S * 0.82, S * 0.34], fill=EDGE)                     # 압력계
    d.ellipse([S * 0.61, S * 0.13, S * 0.79, S * 0.31], fill=(245, 245, 240, 255))
    d.line([(S * 0.7, S * 0.22), (S * 0.75, S * 0.16)], fill=(200, 40, 40, 255), width=10)
    save(im, "oxygen")


def net():
    im, d = new()
    c = S / 2
    R = S * 0.36
    d.ellipse([c - R - 14, c - R - 14, c + R + 14, c + R + 14], fill=(30, 60, 70, 110))
    rope = (205, 175, 115, 255)
    # 그물코: 둥근 테 안에 비스듬한 줄 두 방향
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([c - R, c - R, c + R, c + R], fill=255)
    grid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    g = ImageDraw.Draw(grid)
    for k in range(-8, 9):
        o = k * S * 0.075
        g.line([(c + o - S, c - S), (c + o + S, c + S)], fill=rope, width=12)
        g.line([(c + o + S, c - S), (c + o - S, c + S)], fill=rope, width=12)
    im.paste(grid, (0, 0), Image.composite(grid, Image.new("RGBA", (S, S)), mask).split()[3])
    d.ellipse([c - R, c - R, c + R, c + R], outline=EDGE, width=22)
    d.ellipse([c - R + 6, c - R + 6, c + R - 6, c + R - 6], outline=(150, 115, 60, 255), width=10)
    for a in (0.6, 2.3, 4.1):      # 빨간 찌
        x, y = c + math.cos(a) * R, c + math.sin(a) * R
        d.ellipse([x - 34, y - 34, x + 34, y + 34], fill=EDGE)
        d.ellipse([x - 27, y - 27, x + 27, y + 27], fill=(220, 60, 45, 255))
        d.ellipse([x - 27, y - 4, x + 27, y + 27], fill=(250, 245, 235, 255))
    save(im, "net")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    dice()
    scroll()
    conch()
    oxygen()
    net()
    print("ok")
