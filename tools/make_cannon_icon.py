"""칸 그림: 대포 (흰 실루엣, 256x256 알파) → textures/tiles/icon_cannon.png"""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 1024
im = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(im)
# 포신 (오른쪽 위로 비스듬히): 뒤가 굵고 앞이 가는 통 + 포구 테 + 뒤쪽 둥근 꼭지
ang = math.radians(-24)
ca, sa = math.cos(ang), math.sin(ang)
def P(x, y, ox=430, oy=520):
    return (ox + x * ca - y * sa, oy + x * sa + y * ca)
body = [P(-250, -105), P(300, -72), P(300, 72), P(-250, 105)]
d.polygon(body, fill=255)
for x, r in [(300, 92), (-120, 118), (90, 98)]:
    d.polygon([P(x - 22, -r), P(x + 22, -r), P(x + 22, r), P(x - 22, r)], fill=255)
cx, cy = P(-262, 0)
d.ellipse([cx - 105, cy - 105, cx + 105, cy + 105], fill=255)
cx, cy = P(-372, 0)
d.ellipse([cx - 50, cy - 50, cx + 50, cy + 50], fill=255)
# 포구 구멍
mx, my = P(322, 0)
d.ellipse([mx - 40, my - 52, mx + 40, my + 52], fill=0)
# 바퀴 달린 받침
d.polygon([(250, 640), (640, 640), (590, 520), (300, 520)], fill=255)
for wx in (330, 570):
    d.ellipse([wx - 120, 600, wx + 120, 840], fill=255)
    d.ellipse([wx - 50, 670, wx + 50, 770], fill=0)
    d.ellipse([wx - 18, 702, wx + 18, 738], fill=255)
# 포탄 세 개
for bx, by, r in [(760, 800, 62), (880, 800, 62), (820, 700, 62)]:
    d.ellipse([bx - r, by - r, bx + r, by + r], fill=255)
im = im.filter(ImageFilter.GaussianBlur(1.5)).resize((256, 256), Image.LANCZOS)
out = Image.new("RGBA", (256, 256), (255, 255, 255, 0))
out.putalpha(im)
out.save("textures/tiles/icon_cannon.png")
print("ok")
