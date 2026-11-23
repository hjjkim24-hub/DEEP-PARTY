"""물속 바닥에 일렁이는 빛 무늬(코스틱) — 이음매 없는 타일 텍스처
python3 tools/make_caustics.py → textures/models/caustics.png"""
import numpy as np
from PIL import Image, ImageFilter
S = 512
rng = np.random.default_rng(3)
pts = rng.random((60, 2)) * S
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
d1 = np.full((S, S), 1e9, np.float32)
d2 = np.full((S, S), 1e9, np.float32)
for px, py in pts:
    for ox in (-S, 0, S):
        for oy in (-S, 0, S):
            d = np.hypot(xx - px - ox, yy - py - oy)
            m = d < d1
            d2 = np.where(m, d1, np.minimum(d2, d))
            d1 = np.where(m, d, d1)
edge = d2 - d1
c = np.exp(-edge / 5.0)
c = c ** 1.6
img = Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.6))
img.save("textures/models/caustics.png")
print("caustics ok")
