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
lo = np.array([-5.6, -3.6, -5.2])
hi = np.array([5.6, 5.6, 5.4])
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


# ── 문어 모양: 커다란 외투막(머리 주머니)이 뒤로 처지고, 그 아래 눈 달린 머리, 머리 밑에서 물갈퀴로 이어진 팔 8개
# 외투막: 몸에서 가장 큰 부분. 뒤로 젖혀지며 끝이 살짝 뾰족
d = ellipsoid(0, 2.25, -1.25, 2.3, 2.65, 2.55, tilt=-0.55)
d = smin(d, ellipsoid(0, 4.0, -2.75, 1.25, 1.35, 1.4, tilt=-0.7), 1.1)
# 머리: 외투막과 목 없이 매끈하게
d = smin(d, ellipsoid(0, 0.25, 0.65, 1.85, 1.2, 1.65), 1.2)
# 눈두덩 (양옆으로 불룩) + 눈 위 주름진 눈썹
for sx in (-1, 1):
    d = smin(d, ellipsoid(sx * 1.45, 0.75, 1.0, 0.82, 0.78, 0.78), 0.45)
    d = smin(d, capsule((sx * 1.0, 1.32, 1.25), (sx * 1.85, 1.2, 0.95), 0.2, 0.14), 0.2)
# 눈 구멍 (옆 · 앞을 봄)
for sx in (-1, 1):
    d = smax(d, -ellipsoid(sx * 1.66, 0.74, 1.4, 0.44, 0.33, 0.4), 0.08)
# 물갈퀴: 머리 밑에 넓게 퍼져 팔 뿌리를 잇는 막
d = smin(d, ellipsoid(0, -0.85, 0.45, 2.75, 0.5, 2.55), 0.7)
# 팔 뿌리 8개: 머리 밑에서 바닥을 따라 바깥으로 뻗다가 심연 아래로 (앞쪽 두 개는 피함 — 얼굴 가리지 않게)
for k in range(8):
    a = (k + 0.5) / 8 * np.pi * 2
    ca, sa = np.cos(a), np.sin(a)
    tw = 0.25 * (1 if k % 2 else -1)
    p0 = (ca * 0.8, -0.8, 0.45 + sa * 0.8)
    p1 = (ca * 2.7, -1.25, 0.45 + sa * 2.5)
    p2 = (np.cos(a + tw) * 4.2, -2.1, 0.45 + np.sin(a + tw) * 3.9)
    p3 = (np.cos(a + tw * 2) * 4.9, -3.5, 0.45 + np.sin(a + tw * 2) * 4.5)
    d = smin(d, capsule(p0, p1, 0.8, 0.66), 0.55)
    d = smin(d, capsule(p1, p2, 0.66, 0.55), 0.3)
    d = smin(d, capsule(p2, p3, 0.55, 0.46), 0.25)
# 깔때기 (옆구리 숨구멍)
d = smin(d, capsule((1.55, -0.1, -0.5), (2.1, -0.35, 0.0), 0.34, 0.24), 0.25)
d = smax(d, -capsule((2.05, -0.33, -0.05), (2.3, -0.4, 0.2), 0.14, 0.14), 0.05)
# 외투막의 혹 (크고 작은 돌기)
r2 = np.random.default_rng(11)
for _ in range(70):
    u, v = r2.uniform(0, 2 * np.pi), r2.uniform(-0.2, 1.0)
    cx, cy, cz = 2.2 * np.cos(u) * np.sqrt(1 - v * v), 2.25 + 2.5 * v, -1.25 + 2.45 * np.sin(u) * np.sqrt(1 - v * v)
    if cz > 0.6 and cy < 1.8:
        continue
    rr = r2.uniform(0.07, 0.17)
    d = smin(d, np.sqrt((X - cx) ** 2 + (Y - cy) ** 2 + (Z - cz) ** 2) - rr, 0.12)
# 주름 · 결: 외투막 둘레로 굵은 주름, 전체에 잔 주름
wr = np.sin(Y * 5.5 + noise3(2.0, 1.8, 5)) * 0.018 * np.clip((Y - 0.8) / 2.0, 0, 1)
d = d + noise3(3.0, 0.05, 1) + noise3(7.0, 0.016, 2) + wr
d[:, :, :] = np.where(Y < -3.45, np.maximum(d, -(Y + 3.45)), d)   # 바닥 자르기

if os.environ.get("PREVIEW"):
    from PIL import Image
    occ = d < 0
    ims = []
    for axis, flip, name in ((2, True, "front"), (0, True, "side"), (1, True, "top")):
        o = np.flip(occ, axis) if flip else occ
        hit = o.any(axis)
        depth = np.argmax(o, axis).astype(np.float32)
        gy, gx = np.gradient(depth)
        shade = np.clip(0.75 - gx * 0.25 - gy * 0.25, 0.2, 1.0) * (1 - depth / depth.max() * 0.5)
        img = np.where(hit, shade, 0.0)
        img = np.rot90(img) if axis != 1 else img.T
        ims.append(Image.fromarray((img * 255).astype(np.uint8)).resize((img.shape[1] * 2, img.shape[0] * 2)))
    W = sum(i.width for i in ims)
    S = Image.new("L", (W, max(i.height for i in ims)))
    x = 0
    for i in ims:
        S.paste(i, (x, 0))
        x += i.width
    S.save("/tmp/kraken_preview.png")
    raise SystemExit
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
