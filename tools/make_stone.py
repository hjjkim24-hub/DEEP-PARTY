"""구조물(기둥 · 집 · 받침돌 등)에 입히는 밝은 돌 표면 디테일 (이음새 없이 반복): 색 + 노멀맵.
색은 거의 흰색이라 재질 색에 곱해도 원래 색이 유지됨. 잔 구멍, 얼룩, 가는 금, 물때.
python3 tools/make_stone.py  →  textures/seabed/stone_albedo.png, stone_normal.png"""
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from PIL import Image

N = 1024
rng = np.random.default_rng(11)


def wn(sigma):
    n = ndimage.gaussian_filter(rng.standard_normal((N, N)), sigma, mode="wrap")
    return (n - n.mean()) / (n.std() + 1e-9)


yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
# 가는 금 (보로노이 경계, 일부만 남김)
pts = rng.uniform(0, N, (26, 2))
tiled = np.concatenate([pts + np.array([dx, dy]) * N for dx in (-1, 0, 1) for dy in (-1, 0, 1)])
wx = (xx + wn(22) * 10) % N
wy = (yy + wn(22) * 10) % N
d, _ = cKDTree(tiled).query(np.stack([wx.ravel(), wy.ravel()], 1), k=2)
edge = (d[:, 1] - d[:, 0]).reshape(N, N)
crack = np.clip(1.0 - edge / 2.2, 0, 1) * np.clip(wn(50) * 0.8 + 0.1, 0, 1)

height = wn(40) * 0.25 + wn(14) * 0.18 + wn(5) * 0.12 + wn(1.5) * 0.1 + wn(0.7) * 0.06
# 잔 구멍 (풍화)
pit = np.clip(wn(2.2) - 1.7, 0, None)
height -= pit * 0.9
height -= crack * 0.8

col = np.ones((N, N, 3)) * 0.92
col *= (1.0 + wn(45) * 0.035 + wn(12) * 0.03 + wn(3) * 0.025 + wn(0.8) * 0.02)[..., None]
# 물때 · 얼룩 (살짝 초록 · 갈색)
stain = np.clip(wn(35), 0, 2.5) / 2.5
col[..., 0] -= stain * 0.07
col[..., 2] -= stain * 0.06
rust = np.clip(wn(28) - 0.8, 0, 2) / 2
col[..., 1] -= rust * 0.05
col[..., 2] -= rust * 0.09
col *= (1.0 - np.clip(pit, 0, 1) * 0.35 - crack * 0.4)[..., None]
cav = height - ndimage.gaussian_filter(height, 4, mode="wrap")
col *= (1.0 + np.clip(cav, -0.3, 0.3) * 0.25)[..., None]
Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save("textures/seabed/stone_albedo.png")

s = 3.0
gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * s
gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * s
n = np.dstack([-gx, -gy, np.ones_like(gx)])
n /= np.linalg.norm(n, axis=2, keepdims=True)
Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save("textures/seabed/stone_normal.png")
print("ok", col.mean())
