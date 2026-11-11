"""바다 밑 모래 디테일 텍스처 (이음새 없이 반복): 색(albedo) + 노멀맵.
모래알, 반짝이는 석영 알갱이, 검은 알갱이, 조개 부스러기, 작은 자갈, 잔물결.
python3 tools/make_sand.py  →  textures/seabed/sand_albedo.png, sand_normal.png"""
import numpy as np
from scipy import ndimage
from PIL import Image
import os

N = 1024
rng = np.random.default_rng(7)


def wrap_noise(sigma, amp=1.0):
    n = rng.standard_normal((N, N))
    n = ndimage.gaussian_filter(n, sigma, mode="wrap")
    n = (n - n.mean()) / (n.std() + 1e-9)
    return n * amp


def stamp(height, col, cx, cy, rx, ry, ang, h, c, soft=1.0):
    """타원 알갱이 하나를 높이·색에 찍기 (가장자리 이어짐)"""
    r = int(max(rx, ry) * 2 + 3)
    ys, xs = np.mgrid[-r:r + 1, -r:r + 1]
    ca, sa = np.cos(ang), np.sin(ang)
    u = (xs * ca + ys * sa) / rx
    v = (-xs * sa + ys * ca) / ry
    d = u * u + v * v
    m = np.clip(1.0 - d, 0, 1)
    dome = np.sqrt(m) * h
    a = np.clip((1.0 - d) * 3.0 / soft, 0, 1)
    yy = (ys + cy) % N
    xx = (xs + cx) % N
    height[yy, xx] = np.maximum(height[yy, xx], dome)
    for k in range(3):
        col[yy, xx, k] = col[yy, xx, k] * (1 - a) + c[k] * a


# 기본 모래 색 (아주 미세한 얼룩 · 결)
base = np.array([0.66, 0.63, 0.53])
col = np.ones((N, N, 3)) * base
blot = wrap_noise(18) * 0.035 + wrap_noise(6) * 0.03 + wrap_noise(2) * 0.03
col *= (1.0 + blot)[..., None]
tint = wrap_noise(30)
col[..., 1] += tint * 0.012
col[..., 2] -= tint * 0.01

height = np.zeros((N, N))
# 잔물결 (텍스처 안에 2.5 번 반복, 살짝 휘게)
yy, xx = np.mgrid[0:N, 0:N] / N
warp = wrap_noise(40) * 0.04
rip = np.sin((yy + warp) * np.pi * 2 * 5 + np.sin(xx * np.pi * 2 * 2) * 0.6)
height += (rip * 0.5 + 0.5) ** 1.6 * 0.35
# 고운 모래알 질감
height += wrap_noise(0.8) * 0.06 + wrap_noise(1.6) * 0.05

# 모래알 (수천 개)
grain_cols = [(0.74, 0.7, 0.6), (0.58, 0.55, 0.46), (0.8, 0.77, 0.68), (0.5, 0.48, 0.42), (0.7, 0.62, 0.5)]
for _ in range(9000):
    c = grain_cols[rng.integers(len(grain_cols))]
    r = rng.uniform(0.8, 2.2)
    stamp(height, col, rng.integers(N), rng.integers(N), r, r * rng.uniform(0.6, 1.0), rng.uniform(0, np.pi), r * 0.12, c)
# 검은 알갱이 · 반짝 석영
for _ in range(1600):
    r = rng.uniform(0.7, 1.6)
    stamp(height, col, rng.integers(N), rng.integers(N), r, r, 0, r * 0.1, (0.22, 0.22, 0.2))
for _ in range(1400):
    r = rng.uniform(0.7, 1.5)
    stamp(height, col, rng.integers(N), rng.integers(N), r, r, 0, r * 0.12, (0.95, 0.93, 0.86))
# 조개 부스러기 (납작한 조각)
shell_cols = [(0.95, 0.88, 0.8), (0.95, 0.75, 0.7), (0.88, 0.84, 0.92), (0.98, 0.95, 0.9)]
for _ in range(260):
    rx = rng.uniform(2.5, 6.0)
    stamp(height, col, rng.integers(N), rng.integers(N), rx, rx * rng.uniform(0.35, 0.7), rng.uniform(0, np.pi), 0.25, shell_cols[rng.integers(4)])
# 작은 자갈
peb_cols = [(0.55, 0.54, 0.5), (0.62, 0.58, 0.5), (0.45, 0.47, 0.45), (0.68, 0.64, 0.58)]
for _ in range(140):
    rx = rng.uniform(4.0, 10.0)
    c = np.array(peb_cols[rng.integers(4)]) * rng.uniform(0.9, 1.1)
    stamp(height, col, rng.integers(N), rng.integers(N), rx, rx * rng.uniform(0.6, 0.95), rng.uniform(0, np.pi), rx * 0.18, tuple(c))

# 자갈 · 알갱이 아래 그늘 (오목한 곳 어둡게)
cav = height - ndimage.gaussian_filter(height, 3, mode="wrap")
col *= (1.0 + np.clip(cav, -0.3, 0.3) * 0.9)[..., None]

albedo = np.clip(col, 0, 1)
Image.fromarray((albedo * 255).astype(np.uint8)).save("textures/seabed/sand_albedo.png")

# 노멀맵 (가장자리 이어짐)
s = 4.0
gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * s
gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * s
n = np.dstack([-gx, -gy, np.ones_like(gx)])
n /= np.linalg.norm(n, axis=2, keepdims=True)
Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save("textures/seabed/sand_normal.png")
print("ok", albedo.mean(axis=(0, 1)))
