"""크라켄 행동 카드 뒷면: SUNKEN ISLAND 판 그림(위에서 본 판 + 판을 움켜쥔 크라켄)을 가운데 둥근 창에 넣고,
놋쇠 테두리 · 모서리 장식 · DEEP PARTY / SUNKEN ISLAND 글씨로 꾸밈.
    godot ... -- --quick-shot=backmap --shots-dir=DIR
    python3 tools/make_card_back.py DIR/back_map.png  →  textures/ui/kraken/back_board.png"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ilsrc/back_map.png"
OUT = os.path.join(ROOT, "textures", "ui", "kraken", "back_board.png")
W, H = 712, 1072          # 카드 안쪽 창 (게임에서 356 x 536 의 2 배)
GOLD = (246, 200, 104)
GOLD_D = (150, 104, 42)
INK = (6, 26, 24)
rng = np.random.default_rng(3)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

# 1) 바탕: 짙은 청록 + 마름모 격자 + 결
base = np.zeros((H, W, 3), np.float32)
t = yy / H
base[:] = (np.array([0.03, 0.15, 0.14]) * (1 - t)[..., None] + np.array([0.01, 0.06, 0.06]) * t[..., None])
lat = (np.abs(((xx + yy) / 46.0) % 1.0 - 0.5) < 0.03) | (np.abs(((xx - yy) / 46.0) % 1.0 - 0.5) < 0.03)
base += lat[..., None] * np.array([0.05, 0.12, 0.1]) * 0.6
base *= (0.92 + 0.16 * rng.random((H, W)))[..., None] ** 0.3
r = np.sqrt(((xx / W - 0.5) * 1.4) ** 2 + ((yy / H - 0.5) * 1.1) ** 2)
base *= (1 - 0.55 * np.clip(r - 0.3, 0, 1))[..., None]
img = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8)).convert("RGBA")

# 2) 가운데 둥근 창: 판 그림
mp = Image.open(SRC).convert("RGB")
mw, mh = mp.size
cw = int(mh * 1.06)
mp = mp.crop(((mw - cw) // 2, 0, (mw + cw) // 2, mh))
win_w, win_h = 600, 640
win_x, win_y = (W - win_w) // 2, 196
mp = mp.resize((win_w, int(win_w * mp.height / mp.width)), Image.LANCZOS)
mp = mp.crop((0, (mp.height - win_h) // 2, win_w, (mp.height - win_h) // 2 + win_h))
a = np.asarray(mp).astype(np.float32) / 255.0
wy, wx = np.mgrid[0:win_h, 0:win_w].astype(np.float32)
wr = np.sqrt(((wx / win_w - 0.5) * 2) ** 2 + ((wy / win_h - 0.5) * 2) ** 2)
a *= (1 - 0.6 * np.clip(wr - 0.55, 0, 1) ** 1.2)[..., None]     # 창 안쪽 그늘
a = np.clip((a - 0.5) * 1.08 + 0.52, 0, 1)
mp = Image.fromarray((a * 255).astype(np.uint8))
mask = Image.new("L", (win_w, win_h), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, win_w - 1, win_h - 1], 300 // 2 * 2 // 2 + 120, fill=255)
# 위쪽은 아치 (반원), 아래쪽은 둥근 모서리
md = ImageDraw.Draw(mask)
mask = Image.new("L", (win_w, win_h), 0)
md = ImageDraw.Draw(mask)
md.ellipse([0, 0, win_w - 1, win_w - 1], fill=255)
md.rounded_rectangle([0, win_w // 2, win_w - 1, win_h - 1], 40, fill=255)
img.paste(mp, (win_x, win_y), mask)

d = ImageDraw.Draw(img)
# 3) 창 테두리: 놋쇠 두 줄 + 그림자
def window_outline(off, width, col):
    x0, y0, x1, y1 = win_x - off, win_y - off, win_x + win_w + off, win_y + win_h + off
    w2 = x1 - x0
    d.arc([x0, y0, x1, y0 + w2], 180, 360, fill=col, width=width)
    d.line([x0, y0 + w2 // 2, x0, y1 - 40 - off], fill=col, width=width)
    d.line([x1, y0 + w2 // 2, x1, y1 - 40 - off], fill=col, width=width)
    d.arc([x0, y1 - 80 - off * 2, x0 + 80 + off * 2, y1], 90, 180, fill=col, width=width)
    d.arc([x1 - 80 - off * 2, y1 - 80 - off * 2, x1, y1], 0, 90, fill=col, width=width)
    d.line([x0 + 40 + off, y1, x1 - 40 - off, y1], fill=col, width=width)
window_outline(9, 6, GOLD_D)
window_outline(6, 4, GOLD)
window_outline(18, 2, GOLD_D)

# 4) 바깥 테두리 (두 줄) + 모서리 장식 (소용돌이)
d.rounded_rectangle([16, 16, W - 17, H - 17], 26, outline=GOLD_D, width=4)
d.rounded_rectangle([26, 26, W - 27, H - 27], 20, outline=GOLD, width=2)
for cx, cy, sx, sy in [(26, 26, 1, 1), (W - 27, 26, -1, 1), (26, H - 27, 1, -1), (W - 27, H - 27, -1, -1)]:
    pts = []
    for k in range(60):
        th = k / 59 * 4.2
        rr = 6 + th * 9
        pts.append((cx + sx * (36 + np.cos(th) * rr), cy + sy * (36 + np.sin(th) * rr)))
    d.line(pts, fill=GOLD, width=3)
    d.ellipse([cx + sx * 36 - 6, cy + sy * 36 - 6, cx + sx * 36 + 6, cy + sy * 36 + 6], fill=GOLD)

# 5) 글씨
font_t = ImageFont.truetype(os.path.join(ROOT, "fonts", "PirataOne-Regular.ttf"), 96)
font_s = ImageFont.truetype(os.path.join(ROOT, "fonts", "PirataOne-Regular.ttf"), 44)

def text_c(y, s, font, fill, stroke=6, spacing=0):
    if spacing:
        widths = [d.textlength(ch, font=font) for ch in s]
        tw = sum(widths) + spacing * (len(s) - 1)
        x = (W - tw) / 2
        for ch, wch in zip(s, widths):
            d.text((x, y), ch, font=font, fill=fill, stroke_width=stroke, stroke_fill=INK)
            x += wch + spacing
    else:
        tw = d.textlength(s, font=font)
        d.text(((W - tw) / 2, y), s, font=font, fill=fill, stroke_width=stroke, stroke_fill=INK)

text_c(70, "DEEP PARTY", font_s, GOLD, 4, spacing=8)
d.line([W / 2 - 170, 140, W / 2 - 40, 140], fill=GOLD_D, width=2)
d.line([W / 2 + 40, 140, W / 2 + 170, 140], fill=GOLD_D, width=2)
d.polygon([(W / 2, 130), (W / 2 + 10, 140), (W / 2, 150), (W / 2 - 10, 140)], fill=GOLD)
# 아래 리본
ry = 880
d.polygon([(60, ry), (W - 60, ry), (W - 30, ry + 60), (W - 60, ry + 120), (60, ry + 120), (30, ry + 60)], fill=(10, 52, 46), outline=GOLD, width=4)
text_c(ry + 4, "SUNKEN ISLAND", font_t, GOLD, 6)
text_c(1012, "KRAKEN SURVIVAL", ImageFont.truetype(os.path.join(ROOT, "fonts", "PirataOne-Regular.ttf"), 30), (190, 225, 205), 3, spacing=4)

# 6) 금박 광택 (위에서 비스듬히 빛)
arr = np.asarray(img).astype(np.float32) / 255.0
sheen = np.exp(-(((xx - yy * 0.6) - W * 0.1) / 120.0) ** 2) * 0.07
arr[..., :3] += sheen[..., None]
img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
img.save(OUT)
print("->", OUT, img.size)
