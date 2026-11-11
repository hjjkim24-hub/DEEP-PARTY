"""주사위 그림판 — 오래된 상아(뼈) 주사위: 살짝 누렇게 바랜 결, 미세한 긁힘·작은 이 빠짐,
드릴로 판 오목한 눈에 검은 잉크(1 은 붉은 잉크), 모서리 손때.
    python3 tools/make_dice.py  →  textures/dice/dice_atlas.png (색), dice_normal.png, dice_rough.png
칸 순서: 1 2 3 / 4 5 6  (scripts/world3d/mesh_kit.gd 의 rounded_box(atlas=true) 와 맞춤)
"""
import os
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "textures", "dice")
C = 512
SPOTS = {
    1: [(0.5, 0.5)],
    2: [(0.3, 0.3), (0.7, 0.7)],
    3: [(0.28, 0.28), (0.5, 0.5), (0.72, 0.72)],
    4: [(0.3, 0.3), (0.7, 0.3), (0.3, 0.7), (0.7, 0.7)],
    5: [(0.28, 0.28), (0.72, 0.28), (0.5, 0.5), (0.28, 0.72), (0.72, 0.72)],
    6: [(0.3, 0.26), (0.7, 0.26), (0.3, 0.5), (0.7, 0.5), (0.3, 0.74), (0.7, 0.74)],
}


def noise(shape, sigma, rng):
    n = ndimage.gaussian_filter(rng.standard_normal(shape), sigma)
    return (n - n.mean()) / (n.std() + 1e-9)


def face(n, seed):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:C, 0:C].astype(np.float32) / C
    # 상아 색 + 결 (가는 세로 줄무늬가 살짝 휘어짐)
    ivory = np.array([0.93, 0.88, 0.76])
    warp = noise((C, C), 40, rng) * 0.03
    grain = np.sin((xx + warp) * 140 + noise((C, C), 25, rng) * 2.0) * 0.5 + 0.5
    streak = ndimage.gaussian_filter(rng.standard_normal((C, C)), (14, 0.7))
    tone = 1 + noise((C, C), 60, rng) * 0.035 + grain * 0.01 + streak * 0.025
    col = ivory[None, None, :] * tone[..., None]
    yellow = np.clip(noise((C, C), 50, rng) * 0.5 + 0.3, 0, 1)
    col = col * (1 - yellow[..., None] * 0.08) + np.array([0.85, 0.72, 0.48]) * yellow[..., None] * 0.08
    # 모서리 손때 (가장자리 어둡고 누렇게)
    e = np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy))
    grime = np.clip(1 - e / 0.12, 0, 1) ** 2 * (0.6 + 0.4 * np.clip(noise((C, C), 8, rng) + 0.5, 0, 1))
    col *= (1 - grime[..., None] * np.array([0.22, 0.26, 0.34]))
    height = np.zeros((C, C))
    rough = np.full((C, C), 0.42) + noise((C, C), 20, rng) * 0.04
    # 긁힘
    for _ in range(28):
        x0, y0 = rng.uniform(0, 1, 2)
        a = rng.uniform(0, np.pi)
        ln = rng.uniform(0.04, 0.22)
        t = np.linspace(0, 1, 200)
        px = ((x0 + np.cos(a) * ln * t) * C).astype(int)
        py = ((y0 + np.sin(a) * ln * t) * C).astype(int)
        ok = (px >= 0) & (px < C) & (py >= 0) & (py < C)
        height[py[ok], px[ok]] -= rng.uniform(0.15, 0.4)
        col[py[ok], px[ok]] *= 0.96
        rough[py[ok], px[ok]] += 0.15
    height = ndimage.gaussian_filter(height, 0.7)
    # 작은 이 빠짐 (모서리 근처)
    for _ in range(3):
        side = rng.integers(4)
        u = rng.uniform(0.15, 0.85)
        cx, cy = [(u, 0.02), (u, 0.98), (0.02, u), (0.98, u)][side]
        r = rng.uniform(0.01, 0.025)
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
        m = np.clip(1 - d, 0, 1)
        height -= m * 0.8
        col *= (1 - m[..., None] * 0.18)
    # 드릴로 판 눈: 오목한 그릇 + 잉크 + 가장자리 살짝 깨짐
    ink = np.array([0.55, 0.08, 0.07]) if n == 1 else np.array([0.07, 0.05, 0.04])
    r = 0.12 if n == 1 else 0.078
    for (sx, sy) in SPOTS[n]:
        jitter = noise((C, C), 6, rng) * 0.0012
        d = np.sqrt((xx - sx) ** 2 + (yy - sy) ** 2) + jitter
        bowl = np.clip(1 - (d / r) ** 2, 0, 1)
        height -= bowl * 6.0
        inside = np.clip((r - d) / 0.004, 0, 1)
        ring = np.exp(-((d - r) / 0.006) ** 2)
        # 잉크: 가운데 진하고 가장자리 살짝 바램, 잉크 위는 번들
        ink_amt = inside * (0.85 + 0.15 * np.clip(1 - d / r, 0, 1))
        shade = 0.55 + 0.45 * np.clip((yy - sy) / r * 0.5 + 0.5, 0, 1)    # 그릇 안 그늘 (위쪽이 어두움)
        col = col * (1 - ink_amt[..., None]) + (ink * shade[..., None]) * ink_amt[..., None]
        col *= (1 - ring[..., None] * 0.25)
        rough = rough * (1 - inside) + 0.18 * inside
    return np.clip(col, 0, 1), height, np.clip(rough, 0.05, 1)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    col = np.zeros((C * 2, C * 3, 3))
    hgt = np.zeros((C * 2, C * 3))
    rgh = np.zeros((C * 2, C * 3))
    for n in range(1, 7):
        k = n - 1
        c, h, r = face(n, 10 + n)
        y0, x0 = (k // 3) * C, (k % 3) * C
        col[y0:y0 + C, x0:x0 + C] = c
        hgt[y0:y0 + C, x0:x0 + C] = h
        rgh[y0:y0 + C, x0:x0 + C] = r
    Image.fromarray((col * 255).astype(np.uint8)).save(os.path.join(OUT, "dice_atlas.png"))
    s = 0.35
    gx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * s
    gy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * s
    nrm = np.dstack([-gx, gy, np.ones_like(gx)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    Image.fromarray(((nrm * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(OUT, "dice_normal.png"))
    Image.fromarray((rgh * 255).astype(np.uint8)).save(os.path.join(OUT, "dice_rough.png"))
    print("dice ->", OUT)
