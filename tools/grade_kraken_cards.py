"""크라켄 행동 카드 일러스트: 실제 3D 모델로 꾸민 연출 장면(quick_shot illust)을 잘라 가볍게 색 보정.
    godot ... -- --quick-shot=illust --shots-dir=DIR   (장면 촬영)
    python3 tools/grade_kraken_cards.py DIR            → textures/ui/kraken/*.png"""
import os, sys
import numpy as np
import cv2
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ilsrc"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "textures", "ui", "kraken")
W, H = 640, 480

# 원본 · 잘라낼 영역 (원본 1920x1080 기준 x, y, 폭 — 높이는 폭의 3/4) · 색 기울기
JOBS = {
    "art_barrage": ("il_storm_b.png", (400, 0, 1440), (0.92, 1.0, 0.95)),
    "art_spines": ("il_spines_a.png", (150, 0, 1440), (0.95, 0.92, 1.0)),
    "art_surge": ("il_surge_a.png", (420, 40, 1380), (1.0, 0.98, 0.9)),
    "art_ship": ("il_ship_b.png", (360, 0, 1440), (0.96, 0.95, 1.0)),
}


def grade(bgr, tint):
    """가벼운 보정: 렌더 그대로의 사실감을 살리고, 가장자리만 어둡게 · 빛 살짝 번지게"""
    img = bgr.astype(np.float32) / 255.0
    h, w = img.shape[:2]
    bright = np.clip(img - 0.85, 0, 1)
    img = img + cv2.GaussianBlur(bright, (0, 0), w * 0.012) * 0.25
    img *= np.array(tint[::-1], np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.sqrt(((xx / w - 0.5) * 1.5) ** 2 + ((yy / h - 0.5) * 1.5) ** 2)
    img *= (1 - 0.4 * np.clip(r - 0.5, 0, 1) ** 1.3)[..., None]
    img = (img - 0.5) * 1.02 + 0.53
    return np.clip(img, 0, 1)


ONLY = sys.argv[2:]    # 이름을 주면 그 카드만 다시 만듦
for name, (f, (x, y, cw), tint) in JOBS.items():
    if ONLY and name not in ONLY:
        continue
    bgr = cv2.imread(os.path.join(SRC, f))
    ch = cw * 3 // 4
    bgr = bgr[y:y + ch, x:x + cw]
    out = grade(bgr, tint)
    out = cv2.resize((out * 255).astype(np.uint8), (W, H), interpolation=cv2.INTER_AREA)
    out = cv2.addWeighted(out, 1.35, cv2.GaussianBlur(out, (0, 0), 1.2), -0.35, 0)
    cv2.imwrite(os.path.join(OUT, name + ".png"), out)
    print("->", name)
