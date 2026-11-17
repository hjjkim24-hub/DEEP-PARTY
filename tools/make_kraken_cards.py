"""크라켄 행동 카드 그림: 게임 화면에서 찍은 장면(quick_shot cardart)을 잘라 색을 다듬어 카드용 그림으로.
    python3 tools/make_kraken_cards.py 원본폴더
→ textures/ui/kraken/art_barrage.png · art_spines.png · art_surge.png · back_eye.png"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/cardart"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "textures", "ui", "kraken")
os.makedirs(OUT, exist_ok=True)
W, H = 640, 480

def grade(im, tint=(0.85, 1.0, 0.95), vign=0.55, contrast=1.15, sat=1.12):
    im = ImageEnhance.Contrast(im).enhance(contrast)
    im = ImageEnhance.Color(im).enhance(sat)
    a = np.asarray(im).astype(np.float32) / 255.0
    a *= np.array(tint, np.float32)
    # 가장자리를 어둡게 (심해 느낌)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    r = np.sqrt(((xx / a.shape[1] - 0.5) * 1.6) ** 2 + ((yy / a.shape[0] - 0.5) * 1.6) ** 2)
    a *= (1.0 - vign * np.clip(r - 0.35, 0, 1) ** 1.4)[..., None]
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))

jobs = {
    "art_barrage": ("art_storm_1.png", (200, 40, 1440, 970), (0.95, 1.0, 0.92)),
    "art_spines": ("art_spines_0.png", (300, 140, 1340, 920), (0.92, 0.9, 1.0)),
    "art_surge": ("art_shop_hit_1.png", (560, 0, 1600, 780), (0.95, 1.0, 0.92)),
    "back_eye": ("art_eye.png", (180, 0, 1380, 900), (0.9, 1.0, 0.9)),
}
for name, (f, box, tint) in jobs.items():
    im = Image.open(os.path.join(SRC, f)).convert("RGB").crop(box).resize((W, H), Image.LANCZOS)
    im = grade(im, tint)
    im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    im.save(os.path.join(OUT, name + ".png"))
    print(name, im.size)
