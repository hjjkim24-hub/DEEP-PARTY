"""크라켄의 배 돛 · 깃발 문양: 크라켄 머리 + 말려 올라간 촉수 (흰 실루엣, 알파만 씀)."""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(img)
cx, cy = S * 0.5, S * 0.36
# 촉수 8 개: 머리 밑에서 뻗어 나와 끝이 말림
for k in range(8):
    side = -1 if k < 4 else 1
    j = k % 4
    a0 = math.radians(90 + side * (12 + j * 22))
    pts = []
    x, y = cx + math.cos(a0) * 120, cy + 140
    ang = a0
    w = 46 - j * 4
    n = 70
    for i in range(n):
        t = i / n
        pts.append((x, y, w * (1 - t) ** 0.9 + 3))
        ang -= side * (0.012 - 0.19 * t ** 3.0) * (1 if j % 2 == 0 else 0.9)
        step = 7.5 - t * 3
        x += math.cos(ang) * step
        y += math.sin(ang) * step
    for (x0, y0, r) in pts:
        d.ellipse([x0 - r, y0 - r, x0 + r, y0 + r], fill=255)
# 머리 (위가 둥근 종 모양)
d.ellipse([cx - 175, cy - 230, cx + 175, cy + 150], fill=255)
d.ellipse([cx - 150, cy + 30, cx + 150, cy + 200], fill=255)
# 두 눈: 비워 두고 세로 동공만 남김
for sx in (-1, 1):
    ex, ey = cx + sx * 78, cy + 60
    d.ellipse([ex - 54, ey - 34, ex + 54, ey + 34], fill=0)
    d.ellipse([ex - 10, ey - 30, ex + 10, ey + 30], fill=255)
    # 찡그린 눈썹: 눈 위를 비스듬히 깎아 냄 (안쪽이 낮게)
    d.polygon([(ex - sx * 70, ey - 6), (ex + sx * 70, ey - 52), (ex + sx * 70, ey - 120), (ex - sx * 70, ey - 120)], fill=255)

img = img.filter(ImageFilter.GaussianBlur(1.2))
out = Image.new("RGBA", (S, S), (255, 255, 255, 0))
out.putalpha(img)
out = out.resize((512, 512), Image.LANCZOS)
out.save("textures/ship/emblem.png")
print("ok")
