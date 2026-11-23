"""찬스 카드 그림 마무리: 렌더(art/<id>_raw.png) → 색감 · 비네트 · 필름 입자 · 살짝 바랜 인쇄 느낌 → art/<id>.png
python3 tools/finish_card_art.py"""
import glob, os
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance

OUT_W, OUT_H = 624, 416
for raw in sorted(glob.glob("textures/ui/cards/art/*_raw.png")):
    cid = os.path.basename(raw)[:-8]
    im = Image.open(raw).convert("RGB")
    im = im.resize((OUT_W, OUT_H), Image.LANCZOS)
    a = np.asarray(im, np.float32) / 255.0
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = (xx - w / 2) / (w / 2)
    dy = (yy - h / 2) / (h / 2)
    r = np.sqrt(dx * dx * 0.8 + dy * dy)
    vig = np.clip(1.0 - (r - 0.55) * 0.55, 0.55, 1.0)
    a = a * vig[..., None]
    # 살짝 따뜻하게 (양피지 카드에 어울리게) + 어두운 곳 청록 유지
    lum = a.mean(-1, keepdims=True)
    warm = np.array([1.04, 1.0, 0.92], np.float32)
    a = a * (warm * lum + (1 - lum))
    a = np.clip((a - 0.5) * 1.06 + 0.5, 0, 1)
    rng = np.random.default_rng(abs(hash(cid)) % 2**32)
    a += (rng.standard_normal((h, w, 1)).astype(np.float32)) * 0.012
    out = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    out = ImageEnhance.Sharpness(out).enhance(1.25)
    out.save("textures/ui/cards/art/%s.png" % cid)
    os.remove(raw)
    print("finished", cid)
