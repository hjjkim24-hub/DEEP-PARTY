"""찬스 카드 실물 같은 앞 · 뒷면 (800 x 1160) → textures/ui/cards/
  chance_back.png : 짙은 남색 리넨 천 질감 + 금박 이중 테두리 · 모서리 장식 · 가운데 나침반 장미 + 물음표 + 닳은 모서리
  chance_front.png: 바랜 양피지 (얼룩 · 여우 반점 · 가장자리 그을음) + 금박 테두리 · 모서리 장식 (글자 · 그림은 게임에서 얹음)
    python3 tools/make_chance_cards.py"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 800, 1160
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "textures", "ui", "cards")
rng = np.random.default_rng(4)
FONT = os.path.join(os.path.dirname(OUT), "..", "..", "fonts", "Poppins-Bold.ttf")


def noise(scale, octaves=4, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros((H, W), np.float32)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        s = max(2, int(scale / (2 ** o)))
        small = r.random((H // s + 2, W // s + 2)).astype(np.float32)
        im = Image.fromarray((small * 255).astype(np.uint8)).resize((W + s * 2, H + s * 2), Image.BICUBIC)
        out += np.asarray(im, np.float32)[:H, :W] / 255.0 * amp
        tot += amp
        amp *= 0.5
    return out / tot


def rounded_mask(r=46):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, W - 1, H - 1], radius=r, fill=255)
    return m


def gold(img_size, mask):
    """금박: 결 따라 밝고 어두움이 바뀌는 금속 그라데이션"""
    w, h = img_size
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    band = 0.5 + 0.5 * np.sin((x * 1.3 + y * 2.2) * math.pi * 2.0)
    n = noise(40, 3, 9)[:h, :w]
    t = np.clip(band * 0.7 + n * 0.5 - 0.1, 0, 1)
    c0 = np.array([110, 72, 22], np.float32)
    c1 = np.array([214, 168, 74], np.float32)
    c2 = np.array([255, 236, 170], np.float32)
    col = np.where(t[..., None] < 0.6, c0 + (c1 - c0) * (t[..., None] / 0.6), c1 + (c2 - c1) * ((t[..., None] - 0.6) / 0.4))
    im = Image.fromarray(col.astype(np.uint8), "RGB").convert("RGBA")
    im.putalpha(mask)
    return im


def ornament_mask():
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([26, 26, W - 27, H - 27], radius=34, outline=255, width=10)
    d.rounded_rectangle([50, 50, W - 51, H - 51], radius=24, outline=255, width=4)
    # 모서리 장식: 소용돌이 + 잎
    for cx, cy, sx, sy in [(50, 50, 1, 1), (W - 51, 50, -1, 1), (50, H - 51, 1, -1), (W - 51, H - 51, -1, -1)]:
        for k in range(140):
            t = k / 139
            a = t * math.pi * 2.2
            r = 10 + 46 * t
            x = cx + sx * (24 + math.cos(a) * r * 0.9)
            y = cy + sy * (24 + math.sin(a) * r * 0.9)
            rr = 4.5 - 2.5 * t
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=255)
        d.polygon([(cx + sx * 8, cy + sy * 110), (cx + sx * 22, cy + sy * 150), (cx + sx * 8, cy + sy * 190), (cx + sx * 0, cy + sy * 150)], fill=255)
        d.polygon([(cx + sx * 110, cy + sy * 8), (cx + sx * 150, cy + sy * 22), (cx + sx * 190, cy + sy * 8), (cx + sx * 150, cy + sy * 0)], fill=255)
    return m


def wear(im, strength=0.5, seed=1):
    """가장자리 닳음 · 긁힘"""
    a = np.asarray(im).astype(np.float32)
    n = noise(6, 2, seed)
    scratch = (n > 0.9).astype(np.float32) * strength * 0.12
    yy, xx = np.mgrid[0:H, 0:W]
    edge = np.minimum.reduce([xx, yy, W - 1 - xx, H - 1 - yy]).astype(np.float32)
    rim = np.clip(1.0 - edge / 40.0, 0, 1) * strength
    a[..., :3] = a[..., :3] * (1 - rim[..., None] * 0.35) + 230 * scratch[..., None] * (1 - rim[..., None])
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), im.mode)


def back():
    # 리넨 천: 가로 · 세로 실결 + 잡음
    base = np.array([20, 34, 58], np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    weave = (np.sin(xx * 1.9) * 0.5 + np.sin(yy * 2.1) * 0.5) * 6
    n = noise(80, 4, 2) * 26 - 13 + noise(3, 1, 3) * 14 - 7
    col = np.clip(base[None, None, :] + (weave + n)[..., None] * np.array([0.8, 0.9, 1.1]), 0, 255)
    vign = 1.0 - 0.35 * (((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    col *= vign[..., None]
    im = Image.fromarray(col.astype(np.uint8), "RGB").convert("RGBA")
    # 금박 장식
    om = ornament_mask()
    # 나침반 장미 + 물음표
    d = ImageDraw.Draw(om)
    cx, cy = W // 2, H // 2
    d.ellipse([cx - 230, cy - 230, cx + 230, cy + 230], outline=255, width=8)
    d.ellipse([cx - 205, cy - 205, cx + 205, cy + 205], outline=255, width=3)
    for k in range(64):
        a = k / 64 * math.tau
        r0 = 205 if k % 4 else 186
        d.line([(cx + math.cos(a) * r0, cy + math.sin(a) * r0), (cx + math.cos(a) * 214, cy + math.sin(a) * 214)], fill=255, width=3)
    for k in range(8):
        a = k / 8 * math.tau - math.pi / 2
        L = 300 if k % 2 == 0 else 190
        wdt = 34 if k % 2 == 0 else 24
        tip = (cx + math.cos(a) * L, cy + math.sin(a) * L)
        l = (cx + math.cos(a + math.pi / 2) * wdt, cy + math.sin(a + math.pi / 2) * wdt)
        r = (cx + math.cos(a - math.pi / 2) * wdt, cy + math.sin(a - math.pi / 2) * wdt)
        d.polygon([tip, l, (cx, cy)], fill=255)
        d.polygon([tip, r, (cx, cy)], fill=170)
    d.ellipse([cx - 92, cy - 92, cx + 92, cy + 92], fill=0)
    d.ellipse([cx - 92, cy - 92, cx + 92, cy + 92], outline=255, width=6)
    f = ImageFont.truetype(FONT, 150)
    d.text((cx, cy + 8), "?", font=f, fill=255, anchor="mm")
    f2 = ImageFont.truetype(FONT, 46)
    d.text((cx, 150), "DEEP PARTY", font=f2, fill=255, anchor="mm")
    d.text((cx, H - 150), "CHANCE", font=f2, fill=255, anchor="mm")
    g = gold((W, H), om)
    # 금박 살짝 볼록하게 (그림자 + 하이라이트)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh.putalpha(om.filter(ImageFilter.GaussianBlur(3)).point(lambda v: int(v * 0.6)))
    im.alpha_composite(sh, (3, 4))
    im.alpha_composite(g)
    im = wear(im, 0.6, 5)
    im.putalpha(rounded_mask())
    im.save(os.path.join(OUT, "chance_back.png"))


def front():
    yy, xx = np.mgrid[0:H, 0:W]
    n1 = noise(160, 4, 11)
    n2 = noise(20, 3, 12)
    base = np.array([236, 220, 182], np.float32)
    col = base[None, None, :] * (0.9 + 0.12 * n1[..., None]) - (n2[..., None] - 0.5) * 14
    # 가장자리 그을음 · 바램
    edge = np.minimum.reduce([xx, yy, W - 1 - xx, H - 1 - yy]).astype(np.float32)
    burn = np.clip(1.0 - edge / 90.0, 0, 1) ** 1.6 * (0.6 + 0.4 * noise(30, 3, 13))
    col = col * (1 - burn[..., None] * np.array([0.45, 0.55, 0.7]))
    # 여우 반점 (갈색 얼룩)
    spots = np.zeros((H, W), np.float32)
    for _ in range(70):
        x, y = rng.integers(0, W), rng.integers(0, H)
        r = rng.uniform(3, 14)
        spots += np.exp(-(((xx - x) ** 2 + (yy - y) ** 2) / (2 * r * r))) * rng.uniform(0.2, 0.6)
    col = col * (1 - np.clip(spots, 0, 0.6)[..., None] * np.array([0.25, 0.35, 0.5]))
    im = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    om = ornament_mask()
    # 제목 아래 · 그림 둘레 가는 장식선
    d = ImageDraw.Draw(om)
    d.line([(150, 250), (W - 150, 250)], fill=255, width=3)
    d.ellipse([W // 2 - 8, 242, W // 2 + 8, 258], fill=255)
    d.line([(150, H - 120), (W - 150, H - 120)], fill=255, width=3)
    g = gold((W, H), om)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh.putalpha(om.filter(ImageFilter.GaussianBlur(2)).point(lambda v: int(v * 0.45)))
    im.alpha_composite(sh, (2, 3))
    im.alpha_composite(g)
    im = wear(im, 0.35, 6)
    im.putalpha(rounded_mask())
    im.save(os.path.join(OUT, "chance_front.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    back()
    front()
    print("ok")
