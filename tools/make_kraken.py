"""거대 크라켄 몸통(외투막 + 머리 + 눈두덩 + 팔 뿌리)을 하나로 매끈하게 이어진 메쉬로 조각.
부호 거리장(SDF)을 부드럽게 합치고(smooth union) 마칭 큐브로 표면을 뽑아 OBJ 로 저장.
    python3 tools/make_kraken.py  →  models/kraken_body.obj
좌표: +Y 위, +Z 앞(얼굴), 단위 1 = 게임에서 KRAKEN_SCALE 배"""
import os
import numpy as np
from scipy import ndimage
from skimage import measure

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "models", "kraken_body.obj")
STEP = 0.062
lo = np.array([-4.6, -3.6, -4.8])
hi = np.array([4.6, 5.4, 3.6])
xs = np.arange(lo[0], hi[0], STEP, dtype=np.float32)
ys = np.arange(lo[1], hi[1], STEP, dtype=np.float32)
zs = np.arange(lo[2], hi[2], STEP, dtype=np.float32)
X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
rng = np.random.default_rng(3)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def ellipsoid(cx, cy, cz, rx, ry, rz, tilt=0.0):
    x, y, z = X - cx, Y - cy, Z - cz
    c, s = np.cos(tilt), np.sin(tilt)
    y, z = y * c - z * s, y * s + z * c
    k0 = np.sqrt((x / rx) ** 2 + (y / ry) ** 2 + (z / rz) ** 2)
    k1 = np.sqrt((x / rx ** 2) ** 2 + (y / ry ** 2) ** 2 + (z / rz ** 2) ** 2)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def capsule(a, b, ra, rb):
    a = np.array(a, np.float32)
    b = np.array(b, np.float32)
    pa = np.stack([X - a[0], Y - a[1], Z - a[2]], -1)
    ba = b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0, 1)
    d = np.linalg.norm(pa - h[..., None] * ba, axis=-1)
    return d - (ra + (rb - ra) * h)


def noise3(scale, amp, seed):
    g = np.random.default_rng(seed).standard_normal((24, 24, 24)).astype(np.float32)
    g = ndimage.gaussian_filter(g, 1.2, mode="wrap")
    g /= g.std()
    idx = [((A - lo[i]) / (hi[i] - lo[i]) * scale) % 24 for i, A in enumerate((X, Y, Z))]
    return ndimage.map_coordinates(g, idx, order=1, mode="wrap").astype(np.float32) * amp


# 외투막: 뒤로 젖혀진 커다란 주머니
d = ellipsoid(0, 2.0, -1.9, 1.75, 2.75, 1.8, tilt=-0.62)
# 머리 (눈이 붙은 넓적한 부분)
d = smin(d, ellipsoid(0, 0.15, 0.35, 2.05, 1.15, 1.6), 0.7)
# 눈두덩 (양옆으로 불룩)
for sx in (-1, 1):
    d = smin(d, ellipsoid(sx * 1.25, 0.62, 1.05, 0.72, 0.62, 0.66), 0.35)
# 눈 구멍 (눈알이 들어갈 자리, 위쪽은 눈꺼풀처럼 덮임)
for sx in (-1, 1):
    d = smax(d, -ellipsoid(sx * 1.42, 0.6, 1.5, 0.42, 0.3, 0.36), 0.08)
# 팔 뿌리 8개: 머리 아래에서 바깥으로 퍼졌다가 심연 아래로
for k in range(8):
    a = (k + 0.5) / 8 * np.pi * 2
    ca, sa = np.cos(a), np.sin(a)
    p0 = (ca * 0.6, -0.55, 0.3 + sa * 0.6)
    p1 = (ca * 2.2, -1.2, 0.3 + sa * 2.0)
    p2 = (ca * 3.4, -3.4, 0.3 + sa * 3.0)
    d = smin(d, capsule(p0, p1, 0.72, 0.6), 0.5)
    d = smin(d, capsule(p1, p2, 0.6, 0.48), 0.25)
# 깔때기 (옆구리 숨구멍)
d = smin(d, capsule((1.5, -0.2, -0.6), (2.0, -0.45, -0.1), 0.32, 0.22), 0.25)
# 주름 · 혹: 외투막 쪽에 큰 굴곡, 전체에 잔 주름
wr = np.sin((Y * 7.0 + noise3(2.0, 1.6, 5)) * 1.0) * 0.012
d = d + noise3(3.0, 0.06, 1) + noise3(7.0, 0.018, 2) + wr
d[:, :, :] = np.where(Y < -3.45, np.maximum(d, -(Y + 3.45)), d)   # 바닥 자르기

verts, faces, normals, _ = measure.marching_cubes(d, 0.0, spacing=(STEP, STEP, STEP), allow_degenerate=False)
verts += lo
# 마칭 큐브 노멀은 바깥쪽 = 거리 증가 방향 (부호 맞추기)
normals = -normals
# 매끈하게 (라플라시안 2회)
nbr = [[] for _ in range(len(verts))]
for f in faces:
    for i in range(3):
        nbr[f[i]].append(f[(i + 1) % 3])
        nbr[f[i]].append(f[(i + 2) % 3])
for _ in range(2):
    nv = verts.copy()
    for i, n in enumerate(nbr):
        if n:
            nv[i] = verts[i] * 0.5 + verts[n].mean(axis=0) * 0.5
    verts = nv
print("verts", len(verts), "faces", len(faces))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as fo:
    fo.write("# kraken body (tools/make_kraken.py)\n")
    fo.write("".join("v %.3f %.3f %.3f\n" % tuple(v) for v in verts))
    fo.write("".join("vn %.2f %.2f %.2f\n" % tuple(n) for n in normals))
    # 표준 OBJ (바깥에서 볼 때 반시계) — Godot 가져오기가 알아서 뒤집음
    fo.write("".join("f %d//%d %d//%d %d//%d\n" % (f[0] + 1, f[0] + 1, f[1] + 1, f[1] + 1, f[2] + 1, f[2] + 1) for f in faces))
print("->", OUT, os.path.getsize(OUT) // 1024, "KB")
