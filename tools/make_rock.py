"""바위 디테일 텍스처 (이음새 없이 반복): 색 + 노멀맵.
갈라진 틈, 층층이 결, 광물 알갱이, 작은 구멍. python3 tools/make_rock.py"""
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from PIL import Image

N = 1024
rng = np.random.default_rng(3)


def wrap_noise(sigma):
    n = ndimage.gaussian_filter(rng.standard_normal((N, N)), sigma, mode="wrap")
    return (n - n.mean()) / (n.std() + 1e-9)


yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
# 보로노이 틈 (가장자리 이어지도록 9 칸 복제)
def cracks(count, warp_amp):
    pts = rng.uniform(0, N, (count, 2))
    tiled = np.concatenate([pts + np.array([dx, dy]) * N for dx in (-1, 0, 1) for dy in (-1, 0, 1)])
    tree = cKDTree(tiled)
    wx = xx + wrap_noise(25) * warp_amp
    wy = yy + wrap_noise(25) * warp_amp
    d, _ = tree.query(np.stack([wx.ravel() % N, wy.ravel() % N], 1), k=2)
    edge = (d[:, 1] - d[:, 0]).reshape(N, N)
    return edge

e_big = cracks(34, 9)
e_small = cracks(160, 4)
height = np.zeros((N, N))
width = 2.0 + np.clip(wrap_noise(20), -1, 2) * 1.6
height -= np.exp(-e_big / width) * 1.0          # 깊은 틈 (굵기 들쭉날쭉)
height -= np.exp(-e_small / 1.2) * 0.3 * (wrap_noise(30) > -0.3)       # 잔금 (군데군데)
# 판마다 살짝 기울고 울퉁불퉁
height += wrap_noise(60) * 0.35 + wrap_noise(14) * 0.18 + wrap_noise(3) * 0.06 + wrap_noise(1) * 0.03
# 층 결 (가로 줄무늬)
height += np.sin((yy / N) * np.pi * 2 * 9 + wrap_noise(50) * 1.2) * 0.07
# 작은 구멍
for _ in range(220):
    cx, cy = rng.integers(N, size=2)
    r = rng.uniform(1.5, 5)
    ys, xs = np.mgrid[-8:9, -8:9]
    m = np.clip(1 - (xs ** 2 + ys ** 2) / r ** 2, 0, 1)
    height[(ys + cy) % N, (xs + cx) % N] -= m * 0.25

col = np.ones((N, N, 3)) * np.array([0.5, 0.49, 0.46])
col *= (1 + wrap_noise(40)[..., None] * 0.07 + wrap_noise(8)[..., None] * 0.05)
warm = wrap_noise(70)
col[..., 0] += warm * 0.025
col[..., 2] -= warm * 0.02
# 광물 알갱이
spk = ndimage.gaussian_filter(rng.random((N, N)), 0.8, mode="wrap")
spk = (spk - spk.mean()) / spk.std()
col *= (1 + np.clip(spk, -3, 3)[..., None] * 0.06)
# 틈은 어둡게, 튀어나온 곳은 밝게
cav = height - ndimage.gaussian_filter(height, 6, mode="wrap")
col *= (1 + np.clip(cav, -0.6, 0.4) * 0.9)[..., None]
col *= (0.5 + 0.5 * (1 - np.exp(-e_big / width)))[..., None]
alb = np.clip(col, 0, 1)
Image.fromarray((alb * 255).astype(np.uint8)).save("textures/seabed/rock_albedo.png")

s = 3.0
gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * s
gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * s
n = np.dstack([-gx, -gy, np.ones_like(gx)])
n /= np.linalg.norm(n, axis=2, keepdims=True)
Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save("textures/seabed/rock_normal.png")
print("ok", alb.mean(axis=(0, 1)))
