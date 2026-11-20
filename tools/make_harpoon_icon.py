"""칸 그림: 작살 (흰 실루엣, 256x256 알파) → textures/tiles/icon_harpoon.png
비스듬한 작살대 + 뒤로 젖혀진 미늘 촉 + 꼬리 고리에서 늘어진 밧줄 타래"""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 1024
im = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(im)
ang = math.radians(-45)          # 왼쪽 아래 → 오른쪽 위
ca, sa = math.cos(ang), math.sin(ang)
def P(x, y, ox=512, oy=512):
    return (ox + x * ca - y * sa, oy + x * sa + y * ca)
# 작살대
d.polygon([P(-420, -26), P(250, -26), P(250, 26), P(-420, 26)], fill=255)
# 촉 (긴 세모) + 양쪽 미늘
d.polygon([P(230, -70), P(470, 0), P(230, 70)], fill=255)
d.polygon([P(250, -60), P(150, -150), P(195, -60)], fill=255)
d.polygon([P(250, 60), P(150, 150), P(195, 60)], fill=255)
# 촉 아래 쇠 고리
d.polygon([P(205, -46), P(235, -46), P(235, 46), P(205, 46)], fill=255)
# 꼬리 끝 밧줄 고리
ex, ey = P(-440, 0)
d.ellipse([ex - 48, ey - 48, ex + 48, ey + 48], outline=255, width=26)
# 밧줄: 작살대에서 늘어져 둥글게 감긴 고리
cx, cy = 690, 800
for r, w in [(150, 34), (105, 30)]:
    d.ellipse([cx - r, cy - r * 0.62, cx + r, cy + r * 0.62], outline=255, width=w)
d.line([(ex + 20, ey + 40), (330, 880), (cx - 140, cy + 20)], fill=255, width=26, joint="curve")
im = im.filter(ImageFilter.GaussianBlur(1.5)).resize((256, 256), Image.LANCZOS)
out = Image.new("RGBA", (256, 256), (255, 255, 255, 0))
out.putalpha(im)
out.save("textures/tiles/icon_harpoon.png")
print("ok")
