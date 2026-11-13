"""협동 원정 칸 무늬 (흰색 + 투명) + 팀 HUD 아이콘 (색 있음).
    python3 tools/make_coop_icons.py
칸 무늬 → textures/tiles/icon_{treasure,supply,urchin,whirlpool,heal,boss}.png
HUD    → textures/ui/coop/{heart,heart_empty,potion,shield,compass,crate}.png"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_tile_icons import make, urchin  # noqa: E402

UI = os.path.join(os.path.dirname(HERE), "textures", "ui", "coop")


def treasure(d, w, h):
    # 보물 상자 (뚜껑 둥글게) + 열쇠 구멍 뚫기
    d.rounded_rectangle([w * 0.18, h * 0.46, w * 0.82, h * 0.82], radius=w * 0.03, fill=255)
    d.chord([w * 0.18, h * 0.22, w * 0.82, h * 0.68], 180, 360, fill=255)
    d.rectangle([w * 0.18, h * 0.44, w * 0.82, h * 0.5], fill=0)
    d.rectangle([w * 0.44, h * 0.4, w * 0.56, h * 0.6], fill=0)
    d.ellipse([w * 0.47, h * 0.47, w * 0.53, h * 0.53], fill=255)


def supply(d, w, h):
    # 나무 상자: 테두리 + X 받침
    m0, m1 = w * 0.2, w * 0.8
    lw = int(w * 0.07)
    d.rectangle([m0, m0, m1, m1], fill=255)
    d.rectangle([m0 + lw, m0 + lw, m1 - lw, m1 - lw], fill=0)
    d.line([(m0 + lw, m0 + lw), (m1 - lw, m1 - lw)], fill=255, width=lw)
    d.line([(m0 + lw, m1 - lw), (m1 - lw, m0 + lw)], fill=255, width=lw)


def whirlpool(d, w, h):
    # 두 갈래로 말려 들어가는 소용돌이
    c = w / 2
    lw = w * 0.035
    for arm in range(2):
        for k in range(900):
            t = k / 899
            a = t * math.pi * 2.6 + arm * math.pi
            r = w * (0.05 + 0.35 * t)
            x, y = c + math.cos(a) * r, c + math.sin(a) * r
            rr = lw * (0.5 + t)
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=255)


def heal(d, w, h):
    # 공기 방울 + 가운데 뚫린 하트
    c = w / 2
    R = w * 0.36
    d.ellipse([c - R, c - R, c + R, c + R], fill=255)
    s = w * 0.17
    cy = c + s * 0.15
    d.ellipse([c - s * 1.05, cy - s * 0.95, c + s * 0.05, cy + s * 0.15], fill=0)
    d.ellipse([c - s * 0.05, cy - s * 0.95, c + s * 1.05, cy + s * 0.15], fill=0)
    d.polygon([(c - s * 1.0, cy - s * 0.3), (c + s * 1.0, cy - s * 0.3), (c, cy + s * 1.05)], fill=0)
    d.ellipse([c - R * 0.62, c - R * 0.7, c - R * 0.38, c - R * 0.46], fill=0)


def boss(d, w, h):
    # 크라켄 눈: 아몬드 모양 눈 + 세로로 찢어진 동공 + 아래로 늘어진 촉수 두 개
    c = w / 2
    d.ellipse([w * 0.12, h * 0.3, w * 0.88, h * 0.62], fill=255)
    d.ellipse([c - w * 0.15, h * 0.32, c + w * 0.15, h * 0.6], fill=0)
    d.ellipse([c - w * 0.04, h * 0.34, c + w * 0.04, h * 0.58], fill=255)
    lw = w * 0.04
    for sx in (-1, 1):
        for k in range(300):
            t = k / 299
            x = c + sx * (w * 0.16 + math.sin(t * 5) * w * 0.07)
            y = h * 0.6 + t * h * 0.3
            r = lw * (1.2 - t * 0.8)
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)


# ── HUD 아이콘 (색) ─────────────────────────────────────────
def save(im, name):
    im = im.resize((128, 128), Image.LANCZOS)
    im.save(os.path.join(UI, name + ".png"))


def heart(fill, edge, empty=False):
    S = 512
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def shape(dd, inset, col):
        s = S * 0.26 - inset
        c = S / 2
        cy = S * 0.45
        dd.ellipse([c - s * 1.85, cy - s * 0.95, c + s * 0.05, cy + s * 0.95], fill=col)
        dd.ellipse([c - s * 0.05, cy - s * 0.95, c + s * 1.85, cy + s * 0.95], fill=col)
        dd.polygon([(c - s * 1.8, cy + s * 0.25), (c + s * 1.8, cy + s * 0.25), (c, cy + s * 2.15)], fill=col)
    shape(d, 0, edge)
    shape(d, 22, fill)
    if not empty:
        # 반짝이
        d.ellipse([S * 0.27, S * 0.3, S * 0.38, S * 0.42], fill=(255, 255, 255, 170))
    save(im, "heart_empty" if empty else "heart")


def potion():
    S = 512
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([S * 0.18, S * 0.32, S * 0.82, S * 0.94], fill=(60, 30, 20, 255))
    d.ellipse([S * 0.21, S * 0.35, S * 0.79, S * 0.91], fill=(200, 230, 235, 255))
    d.chord([S * 0.21, S * 0.35, S * 0.79, S * 0.91], 10, 170, fill=(230, 60, 90, 255))
    d.rectangle([S * 0.4, S * 0.12, S * 0.6, S * 0.38], fill=(60, 30, 20, 255))
    d.rectangle([S * 0.43, S * 0.15, S * 0.57, S * 0.38], fill=(200, 230, 235, 255))
    d.rounded_rectangle([S * 0.36, S * 0.05, S * 0.64, S * 0.17], radius=14, fill=(150, 95, 50, 255))
    d.ellipse([S * 0.3, S * 0.45, S * 0.4, S * 0.58], fill=(255, 255, 255, 190))
    save(im, "potion")


def shield():
    S = 512
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def sh(inset, col):
        d.polygon([(S * 0.5, S * 0.06 + inset), (S * 0.88 - inset, S * 0.2 + inset * 0.5), (S * 0.84 - inset, S * 0.55),
                   (S * 0.5, S * 0.95 - inset), (S * 0.16 + inset, S * 0.55), (S * 0.12 + inset, S * 0.2 + inset * 0.5)], fill=col)
    sh(0, (70, 45, 20, 255))
    sh(20, (205, 160, 70, 255))
    sh(48, (40, 120, 140, 255))
    d.line([(S * 0.5, S * 0.18), (S * 0.5, S * 0.82)], fill=(205, 160, 70, 255), width=26)
    d.line([(S * 0.24, S * 0.42), (S * 0.76, S * 0.42)], fill=(205, 160, 70, 255), width=26)
    save(im, "shield")


def compass():
    S = 512
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([S * 0.06, S * 0.06, S * 0.94, S * 0.94], fill=(120, 80, 30, 255))
    d.ellipse([S * 0.12, S * 0.12, S * 0.88, S * 0.88], fill=(215, 175, 90, 255))
    d.ellipse([S * 0.17, S * 0.17, S * 0.83, S * 0.83], fill=(245, 232, 200, 255))
    c = S / 2
    d.polygon([(c, S * 0.2), (c + S * 0.07, c), (c - S * 0.07, c)], fill=(190, 40, 30, 255))
    d.polygon([(c, S * 0.8), (c + S * 0.07, c), (c - S * 0.07, c)], fill=(60, 50, 40, 255))
    d.ellipse([c - 16, c - 16, c + 16, c + 16], fill=(120, 80, 30, 255))
    save(im, "compass")


if __name__ == "__main__":
    os.makedirs(UI, exist_ok=True)
    make("treasure", treasure)
    make("supply", supply)
    make("urchin", urchin)
    make("whirlpool", whirlpool)
    make("heal", heal)
    make("boss", boss)
    heart((225, 50, 70, 255), (70, 15, 20, 255))
    heart((40, 30, 35, 160), (70, 15, 20, 220), empty=True)
    potion()
    shield()
    compass()
    print("ok")
