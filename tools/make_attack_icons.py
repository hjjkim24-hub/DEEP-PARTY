"""칸 · 카드 그림 (흰 실루엣, 256x256 알파) → textures/tiles/
  icon_eel.png  : 몸을 S 자로 꼰 전기뱀장어 + 번개
  icon_trap.png : 이빨이 맞물리는 곰덫
  icon_jelly.png: 갓 + 늘어진 촉수의 해파리"""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 1024


def save(im, name):
    im = im.filter(ImageFilter.GaussianBlur(1.5)).resize((256, 256), Image.LANCZOS)
    out = Image.new("RGBA", (256, 256), (255, 255, 255, 0))
    out.putalpha(im)
    out.save("textures/tiles/" + name)


# 전기뱀장어: 굵기가 줄어드는 S 자 몸 + 머리 + 번개 두 줄기
im = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(im)
pts = []
for k in range(120):
    t = k / 119
    x = 170 + 640 * t
    y = 560 + 170 * math.sin(t * 2.2 * math.pi + 0.4)
    pts.append((x, y, 70 * (1 - t) + 16))
for x, y, r in pts:
    d.ellipse([x - r, y - r, x + r, y + r], fill=255)
hx, hy, _ = pts[0]
d.ellipse([hx - 105, hy - 82, hx + 60, hy + 82], fill=255)
d.ellipse([hx - 62, hy - 42, hx - 30, hy - 10], fill=0)      # 눈
d.polygon([(hx - 108, hy + 12), (hx - 40, hy + 28), (hx - 104, hy + 38)], fill=0)   # 입
for bx, by, sc in [(560, 170, 1.0), (790, 760, 0.8)]:
    bolt = [(0, 0), (60, 0), (20, 110), (80, 110), (-30, 290), (5, 150), (-50, 150)]
    d.polygon([(bx + px * sc, by + py * sc) for px, py in bolt], fill=255)
save(im, "icon_eel.png")

# 곰덫: 받침 고리 + 위아래 턱 (톱니) + 가운데 발판 + 사슬
im = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(im)
cx, cy = 512, 520
d.ellipse([cx - 360, cy - 140, cx + 360, cy + 140], outline=255, width=40)
for sgn in (-1, 1):
    # 턱: 반원 테 + 안쪽으로 난 이빨
    box = [cx - 320, cy - 300, cx + 320, cy + 300]
    a0, a1 = (200, 340) if sgn < 0 else (20, 160)
    d.arc(box, a0, a1, fill=255, width=46)
    for k in range(9):
        a = math.radians(a0 + (a1 - a0) * (k + 0.5) / 9)
        r0, r1 = 300, 215
        x0, y0 = cx + r0 * math.cos(a), cy + r0 * math.sin(a)
        x1, y1 = cx + r1 * math.cos(a), cy + r1 * math.sin(a)
        nx, ny = -math.sin(a) * 30, math.cos(a) * 30
        d.polygon([(x0 + nx, y0 + ny), (x0 - nx, y0 - ny), (x1, y1)], fill=255)
d.ellipse([cx - 80, cy - 45, cx + 80, cy + 45], fill=255)
for k in range(2):
    x = cx + 375 + k * 55
    d.ellipse([x - 32, cy + 40 + k * 40 - 22, x + 32, cy + 40 + k * 40 + 22], outline=255, width=16)
save(im, "icon_trap.png")

# 해파리: 둥근 갓 + 갓 테두리 물결 + 구불구불 촉수
im = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(im)
cx, cy = 512, 400
d.pieslice([cx - 300, cy - 280, cx + 300, cy + 280], 180, 360, fill=255)
for k in range(8):
    x = cx - 262 + k * 75
    d.ellipse([x - 40, cy - 30, x + 40, cy + 40], fill=255)
for k in range(6):
    x0 = cx - 210 + k * 84
    pts = [(x0 + 34 * math.sin(t / 60.0 * 3.0 + k), cy + 40 + t * 8) for t in range(60)]
    d.line(pts, fill=255, width=26 if k % 2 == 0 else 18, joint="curve")
save(im, "icon_jelly.png")
print("ok")
