# 메인화면 바다 밑 장면 렌더러 (레이마칭, numpy)
# 모래 바닥에 가라앉은 보드게임 판, 말, 주사위, 카드, 바위, 산호를 실사풍으로 그립니다.
# 결과물 (Godot에서 사용):
#   textures/seabed_scene.png   색 + 투명도 (투명한 부분 = 열린 물, Godot 물 셰이더가 보임)
#   textures/seabed_caustic_pos.png   빛무늬를 위한 바닥 좌표 (RGB에 12비트씩 압축)
#   textures/seabed_caustic_mask.png  빛무늬가 비치는 세기 (위를 향하고 그림자 아닌 곳)
# 사용법: python render_seabed.py [가로해상도] [슈퍼샘플]
import math, os, sys, time, json
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
W = int(sys.argv[1]) if len(sys.argv) > 1 else 1920
SS = int(sys.argv[2]) if len(sys.argv) > 2 else 2
H = W * 9 // 16
OUTDIR = sys.argv[3] if len(sys.argv) > 3 else os.path.join(ROOT, "textures")
os.makedirs(OUTDIR, exist_ok=True)
f32 = np.float32

def V(x, y, z): return np.array([x, y, z], f32)
def norm(v): return v / np.linalg.norm(v)
def rot_x(a): c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], f32)
def rot_y(a): c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], f32)
def rot_z(a): c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], f32)

# ================================================================ 장면 설정
CAM = V(-0.05, 1.70, 4.05)
TARGET = V(0.88, 0.02, 0.25)
FOV = math.radians(42)
LIGHT = norm(V(-0.45, 1.0, 0.32))

# 보드판
B_HALF = V(1.22, 0.042, 1.22)
B_CENTER = V(1.72, 0.10, 0.12)
B_ROT = rot_y(0.36) @ rot_x(0.085) @ rot_z(-0.07)
B_INV = B_ROT.T
TOP = B_HALF[1]

def on_board(lx, lz, lift=0.0):
    return B_CENTER + B_ROT @ V(lx, TOP + lift, lz)

# 말 (위치, 회전, 색)
PAWN_H = 0.26
PAWNS = [
    (on_board(-0.52, 0.58), B_ROT, (0.62, 0.13, 0.11)),                                # 빨강, 서 있음
    (on_board(0.42, -0.36), B_ROT, (0.13, 0.27, 0.55)),                                 # 파랑, 서 있음
    (on_board(0.18, 0.50, 0.078), B_ROT @ rot_y(0.9) @ rot_z(math.pi / 2), (0.78, 0.58, 0.17)),  # 노랑, 쓰러짐
    (V(0.12, 0.0, 1.55), rot_y(-0.5) @ rot_z(-math.pi / 2 + 0.08), (0.17, 0.42, 0.20)),   # 초록, 모래 위에 쓰러짐
]
# 주사위 (중심, 회전, 반크기)
DICE = [
    (on_board(-0.05, 0.28, 0.065), B_ROT @ rot_y(0.55) @ rot_x(math.pi / 2), 0.065),
    (V(0.55, 0.02, 1.95), rot_y(-0.35) @ rot_z(0.25) @ rot_x(0.2), 0.065),
]
# 카드 (중심, 회전)
CARDS = [
    (on_board(0.62, 0.62, 0.004), B_ROT @ rot_y(0.5)),
    (on_board(0.72, 0.38, 0.008), B_ROT @ rot_y(-0.25)),
    (V(2.55, 0.0, 1.35), rot_y(0.8) @ rot_x(0.12)),
]
# 바위 (중심, 반지름, 납작함, 시드)
ROCKS = [
    (V(3.25, -0.12, -1.05), 0.62, 1.5, 1.0),
    (V(3.95, -0.05, 0.15), 0.38, 1.4, 2.0),
    (V(-1.15, -0.10, -1.65), 0.48, 1.6, 3.0),
    (V(-3.2, -0.25, -5.0), 1.25, 1.3, 4.0),
    (V(5.5, -0.3, -4.0), 1.4, 1.2, 5.0),
    (V(3.25, -0.05, 1.45), 0.26, 1.5, 6.0),
    (V(0.35, -0.2, -2.6), 0.55, 1.7, 7.0),
]
BRAIN = [(V(2.72, 0.02, 0.95), 0.27), (V(-0.55, 0.0, -0.95), 0.2)]
BRANCH_BASE = [V(2.55, 0.0, -0.95)]
TUBES = [(V(3.62, 0.0, -0.45), 0.055, 0.42), (V(3.74, 0.0, -0.36), 0.045, 0.3), (V(3.55, 0.0, -0.3), 0.04, 0.24)]
STAR = (V(1.35, 0.0, 2.05), 0.0)

# ================================================================ 노이즈 / 지형
def snoise(x, z):
    return (np.sin(1.7 * x + 0.3) * np.sin(2.3 * z + 1.1) * 0.5 + np.sin(3.9 * x + 2.1 * z) * 0.25
            + np.sin(7.3 * x - 5.1 * z + 0.7) * 0.125 + np.sin(13.1 * x + 11.7 * z) * 0.0625)

def height(x, z):
    h = (0.07 * np.sin(0.8 * x + 0.4 * z) + 0.05 * np.sin(0.6 * z - 1.1 * x + 1.3)
         + 0.025 * np.sin(1.9 * x + 1.4 * z + 0.5) + 0.012 * np.sin(4.1 * x - 3.3 * z))
    back = np.clip((-z - 3.0) / 10.0, 0, 1)
    h = h + back * (0.35 * np.sin(0.35 * x + 0.8) + 0.25)
    return h.astype(f32)

# 모래 위에 놓인 물건들은 모래 높이에 맞춰 올려놓기
def _sy(x, z): return float(height(np.array([x], f32), np.array([z], f32))[0])
PAWNS[3] = (V(PAWNS[3][0][0], _sy(PAWNS[3][0][0], PAWNS[3][0][2]) + 0.07, PAWNS[3][0][2]), PAWNS[3][1], PAWNS[3][2])
DICE[1] = (V(DICE[1][0][0], _sy(DICE[1][0][0], DICE[1][0][2]) + 0.035, DICE[1][0][2]), DICE[1][1], DICE[1][2])
CARDS[2] = (V(CARDS[2][0][0], _sy(CARDS[2][0][0], CARDS[2][0][2]) + 0.004, CARDS[2][0][2]), CARDS[2][1])
STAR = (V(STAR[0][0], _sy(STAR[0][0], STAR[0][2]), STAR[0][2]), 0.0)
BRAIN = [(V(c[0], _sy(c[0], c[2]) - 0.03, c[2]), r) for c, r in BRAIN]
BRANCH_BASE = [V(b[0], _sy(b[0], b[2]) - 0.02, b[2]) for b in BRANCH_BASE]
TUBES = [(V(c[0], _sy(c[0], c[2]) - 0.03, c[2]), r, h) for c, r, h in TUBES]

def sd_round_box(q, b, r):
    d = np.abs(q) - (b - r)
    return (np.linalg.norm(np.maximum(d, 0), axis=1) + np.minimum(np.max(d, axis=1), 0) - r).astype(f32)

def smin(a, b, k):
    h = np.maximum(k - np.abs(a - b), 0) / k
    return np.minimum(a, b) - h * h * k * 0.25

def sd_capped_cone(q, h, r1, r2):
    qx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2); qy = q[:, 1]
    k1 = np.array([r2, h], f32); k2 = np.array([r2 - r1, 2 * h], f32)
    cax = qx - np.minimum(qx, np.where(qy < 0, r1, r2)); cay = np.abs(qy) - h
    t = np.clip(((k1[0] - qx) * k2[0] + (k1[1] - qy) * k2[1]) / (k2 @ k2), 0, 1)
    cbx = qx - k1[0] + k2[0] * t; cby = qy - k1[1] + k2[1] * t
    s = np.where((cbx < 0) & (cay < 0), -1.0, 1.0)
    return (s * np.sqrt(np.minimum(cax * cax + cay * cay, cbx * cbx + cby * cby))).astype(f32)

def sd_cyl(q, r, h, round_r=0.0):
    dx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - (r - round_r); dy = np.abs(q[:, 1]) - (h - round_r)
    return (np.minimum(np.maximum(dx, dy), 0) + np.sqrt(np.maximum(dx, 0) ** 2 + np.maximum(dy, 0) ** 2) - round_r).astype(f32)

PS = 1.25  # 말 크기 배율
def sd_pawn(q):
    return _sd_pawn(q / PS) * PS

def _sd_pawn(q):
    base = sd_cyl(q - V(0, 0.022, 0), 0.078, 0.022, 0.008)
    body = sd_capped_cone(q - V(0, 0.11, 0), 0.075, 0.064, 0.027)
    collar = sd_cyl(q - V(0, 0.185, 0), 0.042, 0.007, 0.005)
    head = np.linalg.norm(q - V(0, 0.222, 0), axis=1) - 0.047
    d = smin(base, body, 0.02)
    d = smin(d, collar, 0.012)
    return smin(d, head.astype(f32), 0.012)

def sd_capsule(p, a, b, r):
    pa = p - a; ba = b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0, 1)
    return (np.linalg.norm(pa - h[:, None] * ba[None, :], axis=1) - r).astype(f32)

def make_branches(base, seed):
    rr = np.random.default_rng(int(seed * 100))
    segs = []
    def grow(p, d, l, r, depth):
        e = p + d * l
        segs.append((p, e, r))
        if depth < 3:
            for k in range(2):
                nd = norm(d + V(*(rr.normal(0, 0.55, 3))) + V(0, 0.4, 0))
                grow(e, nd, l * 0.72, r * 0.75, depth + 1)
    for k in range(3):
        d0 = norm(V(rr.normal(0, 0.5), 1.0, rr.normal(0, 0.5)))
        grow(base, d0, 0.16, 0.026, 0)
    return segs
BRANCHES = [make_branches(b, i + 1) for i, b in enumerate(BRANCH_BASE)]

def bounded(p, center, radius, fn, thresh=0.12):
    db = (np.linalg.norm(p - center, axis=1) - radius).astype(f32)
    m = db < thresh
    if np.any(m):
        db[m] = fn(p[m])
    return db

# ================================================================ 장면 거리 함수
COMP = ["sand", "board", "pawn", "dice", "card", "rock", "coral", "star"]

def components(p):
    out = {}
    sand = (p[:, 1] - height(p[:, 0], p[:, 2])) * 0.8
    out["sand"] = sand.astype(f32)
    out["board"] = bounded(p, B_CENTER, 1.7, lambda pp: sd_round_box((pp - B_CENTER) @ B_INV.T, B_HALF, 0.012))
    d = np.full(len(p), 1e3, f32)
    for base, R, _ in PAWNS:
        d = np.minimum(d, bounded(p, base + R @ V(0, 0.16, 0), 0.22, lambda pp, base=base, R=R: sd_pawn((pp - base) @ R)))
    out["pawn"] = d
    d = np.full(len(p), 1e3, f32)
    for c, R, hs in DICE:
        d = np.minimum(d, bounded(p, c, hs * 1.8, lambda pp, c=c, R=R, hs=hs: sd_round_box((pp - c) @ R, V(hs, hs, hs), 0.014)))
    out["dice"] = d
    d = np.full(len(p), 1e3, f32)
    for c, R in CARDS:
        d = np.minimum(d, bounded(p, c, 0.13, lambda pp, c=c, R=R: sd_round_box((pp - c) @ R, V(0.062, 0.0025, 0.09), 0.002)))
    out["card"] = d
    d = np.full(len(p), 1e3, f32)
    for c, r, flat, sd in ROCKS:
        def rock(pp, c=c, r=r, flat=flat, sd=sd):
            q = pp - c; q2 = q * V(1, flat, 1)
            o1 = V(math.sin(sd * 3.1) * 0.45, 0.1, math.cos(sd * 2.3) * 0.4) * r
            o2 = V(math.cos(sd * 1.7) * 0.5, -0.05, math.sin(sd * 4.1) * 0.35) * r
            lump = smin(np.linalg.norm((q - o1) * V(1, flat, 1), axis=1) - r * 0.7, np.linalg.norm((q - o2) * V(1, flat, 1), axis=1) - r * 0.65, 0.3 * r)
            disp = (0.10 * np.sin(4.1 * q[:, 0] / r + sd) * np.sin(3.7 * q[:, 1] / r + sd * 2) * np.sin(4.3 * q[:, 2] / r + sd * 0.5)
                    + 0.045 * np.sin(11 * q[:, 0] / r + sd) * np.sin(9 * q[:, 2] / r - sd) * np.sin(7 * q[:, 1] / r)
                    + 0.006 * np.abs(np.sin(23 * q[:, 1] / r + 3 * np.sin(5 * q[:, 0] / r)))
                    + 0.012 * np.sin(41 * q[:, 0] / r) * np.sin(37 * q[:, 2] / r + sd)) * r
            return ((smin(np.linalg.norm(q2, axis=1) - r, lump, 0.35 * r) + disp) * 0.55).astype(f32)
        d = np.minimum(d, bounded(p, c, r * 1.3, rock, 0.2))
    out["rock"] = d
    d = np.full(len(p), 1e3, f32)
    for c, r in BRAIN:
        def brain(pp, c=c, r=r):
            q = pp - c; q2 = q * V(1, 1.35, 1)
            g = 0.012 * np.sin(38 * q[:, 0] + 9 * np.sin(14 * q[:, 2])) * np.sin(36 * q[:, 2] + 7 * np.sin(13 * q[:, 0]))
            return ((np.linalg.norm(q2, axis=1) - r + g) * 0.7).astype(f32)
        d = np.minimum(d, bounded(p, c, r * 1.2, brain))
    for i, segs in enumerate(BRANCHES):
        def branch(pp, segs=segs):
            dd = np.full(len(pp), 1e3, f32)
            for a, b, r in segs:
                dd = smin(dd, sd_capsule(pp, a, b, r), 0.03)
            return dd
        d = np.minimum(d, bounded(p, BRANCH_BASE[i] + V(0, 0.32, 0), 0.5, branch))
    for c, r, h in TUBES:
        d = np.minimum(d, bounded(p, c + V(0, h * 0.5, 0), h * 0.6 + r, lambda pp, c=c, r=r, h=h: sd_cyl(pp - c - V(0, h * 0.5, 0), r, h * 0.5, 0.01)))
    out["coral"] = d
    def starfish(pp):
        q = pp - STAR[0]
        a = np.arctan2(q[:, 2], q[:, 0]); rr = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2)
        k = 0.5 + 0.5 * np.cos(5 * a)
        lim = 0.035 + 0.1 * k ** 2.2
        th = 0.022 * (1 - np.clip(rr / 0.14, 0, 1)) + 0.008
        dx = rr - lim; dy = np.abs(q[:, 1] - 0.008) - th
        return ((np.minimum(np.maximum(dx, dy), 0) + np.sqrt(np.maximum(dx, 0) ** 2 + np.maximum(dy, 0) ** 2)) * 0.6).astype(f32)
    out["star"] = bounded(p, STAR[0], 0.17, starfish)
    return out

def scene(p):
    c = components(p)
    d = smin(c["sand"], c["board"], 0.10)
    d = smin(d, c["pawn"], 0.025)
    d = smin(d, c["dice"], 0.03)
    d = np.minimum(d, c["card"])
    d = smin(d, c["rock"], 0.12)
    d = smin(d, c["coral"], 0.05)
    d = smin(d, c["star"], 0.02)
    return d.astype(f32)

def scene_mat(p):
    c = components(p)
    stack = np.stack([c[k] for k in COMP], axis=1)
    return np.argmin(stack, axis=1)

# ================================================================ 재질
BOARD_TEX = np.asarray(Image.open(os.path.join(HERE, "out", "board_print.png")).convert("RGB").resize((1024, 1024), Image.LANCZOS)).astype(f32) / 255

def sample_tex(tex, u, v):
    hh, ww = tex.shape[:2]
    x = np.clip(u * (ww - 1), 0, ww - 1.001); y = np.clip(v * (hh - 1), 0, hh - 1.001)
    x0 = x.astype(int); y0 = y.astype(int); fx = (x - x0)[:, None]; fy = (y - y0)[:, None]
    a = tex[y0, x0]; b = tex[y0, x0 + 1]; c = tex[y0 + 1, x0]; d = tex[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

SAND = np.array([0.60, 0.54, 0.41], f32)
# 고해상도 모래 디테일 (tools/make_sand.py 가 만든 이음새 없는 텍스처)
SAND_TEX = np.asarray(Image.open(os.path.join(ROOT, "textures", "seabed", "sand_albedo.png")).convert("RGB")).astype(f32) / 255
SAND_TEX /= SAND_TEX.reshape(-1, 3).mean(axis=0)
SAND_NRM = np.asarray(Image.open(os.path.join(ROOT, "textures", "seabed", "sand_normal.png")).convert("RGB")).astype(f32) / 255 * 2 - 1

ROCK_TEX = np.asarray(Image.open(os.path.join(ROOT, "textures", "seabed", "rock_albedo.png")).convert("RGB")).astype(f32) / 255
ROCK_TEX /= ROCK_TEX.reshape(-1, 3).mean(axis=0)
ROCK_NRM = np.asarray(Image.open(os.path.join(ROOT, "textures", "seabed", "rock_normal.png")).convert("RGB")).astype(f32) / 255 * 2 - 1

def rock_tri(tex, p, n, scale=0.9):
    """세 방향에서 바위 결을 입힘"""
    w = np.abs(n) ** 4; w /= w.sum(axis=1, keepdims=True)
    q = p / scale
    a = sample_tex(tex, np.mod(q[:, 2], 1), np.mod(q[:, 1], 1))
    b = sample_tex(tex, np.mod(q[:, 0] + 0.31, 1), np.mod(q[:, 2], 1))
    c = sample_tex(tex, np.mod(q[:, 0] + 0.67, 1), np.mod(q[:, 1], 1))
    return a * w[:, 0:1] + b * w[:, 1:2] + c * w[:, 2:3]

def sand_detail(tex, x, z):
    """두 가지 크기로 겹쳐서 반복이 티 나지 않게"""
    a = sample_tex(tex, np.mod(x / 1.1, 1.0), np.mod(z / 1.1, 1.0))
    xr = 0.8 * x - 0.6 * z; zr = 0.6 * x + 0.8 * z
    b = sample_tex(tex, np.mod(xr / 2.9 + 0.37, 1.0), np.mod(zr / 2.9 + 0.11, 1.0))
    k = np.clip(snoise(x * 0.9, z * 0.9) * 0.5 + 0.5, 0, 1)[:, None]
    return a * (1 - k) + b * k

def ripple(x, z):
    return np.sin(16 * (0.82 * x + 0.57 * z) + 2.5 * snoise(x * 0.7, z * 0.7))

def albedo_and_extra(p, n, mat):
    N = len(p)
    alb = np.zeros((N, 3), f32); spec = np.zeros(N, f32); shin = np.full(N, 20, f32)
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    nz = snoise(x * 2.0, z * 2.0)
    # 모래
    m = mat == 0
    if np.any(m):
        r = ripple(x[m], z[m])
        speck = (snoise(x[m] * 31, z[m] * 31) > 0.62).astype(f32) * 0.5
        det = sand_detail(SAND_TEX, x[m], z[m])
        alb[m] = SAND * (0.86 + 0.08 * r[:, None] * 0.5 + 0.08 * nz[m][:, None]) * (det * 0.9 + 0.1)
    # 보드
    m = mat == 1
    if np.any(m):
        q = (p[m] - B_CENTER) @ B_INV.T
        nl = n[m] @ B_INV.T
        top = nl[:, 1] > 0.7
        col = np.zeros((m.sum(), 3), f32)
        u = 0.5 + q[:, 0] / (2 * B_HALF[0]); v = 0.5 + q[:, 2] / (2 * B_HALF[2])
        col[top] = sample_tex(BOARD_TEX, u[top], v[top])
        side = ~top
        grain = 0.5 + 0.5 * np.sin(q[side][:, 1] * 900 + snoise(q[side][:, 0] * 8, q[side][:, 2] * 8) * 3)
        col[side] = np.array([0.12, 0.15, 0.23], f32) * (0.85 + 0.25 * grain[:, None])
        # 모래 쌓임 (낮은 쪽일수록 많이) + 얇게 덮인 먼지
        lowness = np.clip((0.16 - y[m]) / 0.14, 0, 1)
        sn = snoise(q[:, 0] * 3.1 + 4, q[:, 2] * 3.1) * 0.5 + 0.5
        sandy = np.clip(lowness * 1.3 * sn + 0.02 + 0.07 * (snoise(q[:, 0] * 9, q[:, 2] * 9) * 0.5 + 0.5), 0, 0.92)
        col = col * (1 - sandy[:, None]) + SAND * sandy[:, None]
        # 가장자리 이끼
        edge = np.minimum(B_HALF[0] - np.abs(q[:, 0]), B_HALF[2] - np.abs(q[:, 2]))
        alg = np.clip(1 - edge / 0.16, 0, 1) * np.clip(snoise(q[:, 0] * 5 + 1, q[:, 2] * 5) * 0.7 + 0.5, 0, 1) * 0.55
        col = col * (1 - alg[:, None]) + np.array([0.30, 0.38, 0.20], f32) * alg[:, None]
        alb[m] = col; spec[m] = 0.06; shin[m] = 12
    # 말 (칠한 나무)
    m = mat == 2
    if np.any(m):
        pm = p[m]; col = np.zeros((m.sum(), 3), f32)
        best = np.full(m.sum(), 1e9, f32)
        for base, R, c in PAWNS:
            dd = np.linalg.norm(pm - (base + R @ V(0, 0.12, 0)), axis=1)
            sel = dd < best; best[sel] = dd[sel]; col[sel] = np.array(c, f32)
        wear = np.clip(snoise(pm[:, 0] * 25, pm[:, 2] * 25 + pm[:, 1] * 25) * 0.5 + 0.3, 0, 1) * 0.25
        col = col * (1 - wear[:, None]) + np.array([0.55, 0.42, 0.28], f32) * wear[:, None]
        alb[m] = col; spec[m] = 0.45; shin[m] = 40
    # 주사위 (상아색 + 파인 눈)
    m = mat == 3
    if np.any(m):
        pm = p[m]; col = np.tile(np.array([0.90, 0.86, 0.76], f32), (m.sum(), 1))
        for c, R, hs in DICE:
            q = (pm - c) @ R
            inside = np.max(np.abs(q), axis=1) < hs * 1.3
            if not np.any(inside): continue
            qi = q[inside]; ax = np.argmax(np.abs(qi), axis=1)
            sgn = np.sign(qi[np.arange(len(qi)), ax])
            val = np.where(ax == 1, np.where(sgn > 0, 2, 5), np.where(ax == 0, np.where(sgn > 0, 3, 4), np.where(sgn > 0, 1, 6)))
            uu = np.where(ax == 0, qi[:, 2], qi[:, 0]) / hs; vv = np.where(ax == 1, qi[:, 2], qi[:, 1]) / hs
            pip = np.zeros(len(qi), bool)
            layouts = {1: [(0, 0)], 2: [(-1, -1), (1, 1)], 3: [(-1, -1), (0, 0), (1, 1)], 4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
                       5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)], 6: [(-1, -1), (-1, 0), (-1, 1), (1, -1), (1, 0), (1, 1)]}
            for vnum, lay in layouts.items():
                sel = val == vnum
                for a, b in lay:
                    pip |= sel & ((uu - a * 0.5) ** 2 + (vv - b * 0.5) ** 2 < 0.19 ** 2)
            sub = col[inside]; sub[pip] = np.array([0.08, 0.07, 0.06], f32); col[inside] = sub
        alb[m] = col; spec[m] = 0.5; shin[m] = 50
    # 카드
    m = mat == 4
    if np.any(m):
        pm = p[m]; col = np.tile(np.array([0.14, 0.20, 0.36], f32), (m.sum(), 1))
        for c, R in CARDS:
            q = (pm - c) @ R
            inside = (np.abs(q[:, 0]) < 0.07) & (np.abs(q[:, 2]) < 0.1) & (np.abs(q[:, 1]) < 0.01)
            border = inside & ((np.abs(np.abs(q[:, 0]) - 0.05) < 0.004) | (np.abs(np.abs(q[:, 2]) - 0.078) < 0.004))
            diamond = inside & (np.abs(q[:, 0]) / 0.03 + np.abs(q[:, 2]) / 0.05 < 1)
            col[border | diamond] = np.array([0.75, 0.60, 0.28], f32)
        alb[m] = col; spec[m] = 0.15
    # 바위 (위쪽은 이끼)
    m = mat == 5
    if np.any(m):
        tex = rock_tri(ROCK_TEX, p[m], n[m])
        big = np.clip(snoise(x[m] * 1.3 + y[m], z[m] * 1.3) * 0.5 + 0.5, 0, 1)
        col = np.array([0.36, 0.35, 0.32], f32) * (0.85 + 0.25 * big[:, None]) * tex
        moss = np.clip((n[m][:, 1] - 0.72) * 4.0, 0, 1) * np.clip(tex.mean(axis=1) * 1.4 - 0.6, 0, 1) * 0.85
        col = col * (1 - moss[:, None]) + np.array([0.22, 0.33, 0.17], f32) * tex * moss[:, None]
        alb[m] = col
    # 산호
    m = mat == 6
    if np.any(m):
        pm = p[m]; col = np.tile(np.array([0.78, 0.42, 0.30], f32), (m.sum(), 1))
        for c, r in BRAIN:
            sel = np.linalg.norm(pm - c, axis=1) < r * 1.3
            col[sel] = np.array([0.70, 0.60, 0.38], f32) * (0.85 + 0.15 * np.sin(38 * pm[sel][:, 0] + 9 * np.sin(14 * pm[sel][:, 2])))[:, None]
        for c, r, h in TUBES:
            sel = np.linalg.norm((pm - c)[:, [0, 2]], axis=1) < r * 1.6
            col[sel] = np.array([0.52, 0.36, 0.58], f32)
            topsel = sel & (pm[:, 1] > c[1] + h - 0.012) & (np.linalg.norm((pm - c)[:, [0, 2]], axis=1) < r * 0.6)
            col[topsel] = np.array([0.12, 0.08, 0.12], f32)
        for b in BRANCH_BASE:
            sel = np.linalg.norm((pm - b)[:, [0, 2]], axis=1) < 0.55
            sel &= ~np.zeros(len(pm), bool)
        alb[m] = col
    # 불가사리
    m = mat == 7
    if np.any(m):
        dots = (np.sin(140 * x[m]) * np.sin(140 * z[m]) > 0.6).astype(f32)
        alb[m] = np.array([0.85, 0.42, 0.20], f32) * (1 - 0.25 * dots[:, None])
    return alb, spec, shin

# ================================================================ 렌더
def render():
    t0 = time.time()
    RW, RH = W * SS, H * SS
    fwd = norm(TARGET - CAM); right = norm(np.cross(fwd, V(0, 1, 0))); up = np.cross(right, fwd)
    tan = math.tan(FOV / 2); asp = RW / RH
    js, is_ = np.meshgrid(np.arange(RH, dtype=f32), np.arange(RW, dtype=f32), indexing="ij")
    sx = ((is_ + 0.5) / RW * 2 - 1) * tan * asp; sy = (1 - (js + 0.5) / RH * 2) * tan
    dirs = (fwd[None, None, :] + sx[..., None] * right + sy[..., None] * up).reshape(-1, 3)
    dirs = (dirs / np.linalg.norm(dirs, axis=1, keepdims=True)).astype(f32)
    NPIX = len(dirs)
    out_col = np.zeros((NPIX, 3), f32); out_a = np.zeros(NPIX, f32)
    out_cpos = np.zeros((NPIX, 2), f32); out_mask = np.zeros(NPIX, f32)

    sigma = np.array([0.12, 0.034, 0.044], f32)
    TMAX = 45.0
    CH = 300000
    down = np.where(dirs[:, 1] < -1e-4)[0]
    for ci in range(0, len(down), CH):
        idx = down[ci:ci + CH]
        rd = dirs[idx]
        t = ((CAM[1] - 1.05) / -rd[:, 1]).astype(f32)
        hit = np.zeros(len(idx), bool); done = np.zeros(len(idx), bool)
        active = np.arange(len(idx))
        for step in range(260):
            if len(active) == 0: break
            pp = CAM + rd[active] * t[active, None]
            dd = scene(pp)
            h_ = dd < 0.0006 * t[active]
            far = t[active] > TMAX
            hit[active[h_]] = True
            done[active[h_ | far]] = True
            t[active] += np.where(h_, 0, dd * 0.9)
            active = active[~(h_ | far)]
        t = np.minimum(t, TMAX)
        P = CAM + rd * t[:, None]
        # 법선
        e = 0.0012
        ks = [V(1, -1, -1), V(-1, -1, 1), V(-1, 1, -1), V(1, 1, 1)]
        n = np.zeros_like(P)
        hi = np.where(hit)[0]
        for k in ks:
            n[hi] += k[None, :] * scene(P[hi] + k * e)[:, None]
        n[hi] /= np.linalg.norm(n[hi], axis=1, keepdims=True) + 1e-9
        n[~hit] = V(0, 1, 0)
        mat = np.zeros(len(idx), int)
        mat[hi] = scene_mat(P[hi])
        mat[~hit] = 0
        # 모래 물결 법선 흔들기
        ms = hit & (mat == 0)
        if np.any(ms):
            xs, zs = P[ms, 0], P[ms, 2]
            g = np.cos(16 * (0.82 * xs + 0.57 * zs) + 2.5 * snoise(xs * 0.7, zs * 0.7)) * 0.18
            n[ms] += np.stack([g * 0.82, np.zeros_like(g), g * 0.57], 1)
            dn = sand_detail(SAND_NRM, xs, zs)
            n[ms] += np.stack([dn[:, 0] * 0.55, np.zeros_like(g), -dn[:, 1] * 0.55], 1)
            n[ms] /= np.linalg.norm(n[ms], axis=1, keepdims=True)
        # 바위 표면 울퉁불퉁
        mr = hit & (mat == 5)
        if np.any(mr):
            xr_, yr_, zr_ = P[mr, 0], P[mr, 1], P[mr, 2]
            nn = n[mr]
            w = np.abs(nn) ** 4; w /= w.sum(axis=1, keepdims=True)
            q = P[mr] / 0.9
            na = sample_tex(ROCK_NRM, np.mod(q[:, 2], 1), np.mod(q[:, 1], 1))
            nb = sample_tex(ROCK_NRM, np.mod(q[:, 0] + 0.31, 1), np.mod(q[:, 2], 1))
            nc = sample_tex(ROCK_NRM, np.mod(q[:, 0] + 0.67, 1), np.mod(q[:, 1], 1))
            pert = (np.stack([np.zeros(len(nn)), na[:, 1], na[:, 0]], 1) * w[:, 0:1] * np.sign(nn[:, 0:1])
                    + np.stack([nb[:, 0], np.zeros(len(nn)), nb[:, 1]], 1) * w[:, 1:2]
                    + np.stack([nc[:, 0], nc[:, 1], np.zeros(len(nn))], 1) * w[:, 2:3] * np.sign(nn[:, 2:3]))
            n[mr] += pert.astype(f32) * 0.9
            n[mr] /= np.linalg.norm(n[mr], axis=1, keepdims=True)
        # 그림자 (부드럽게)
        sh = np.ones(len(idx), f32)
        st = np.full(len(hi), 0.02, f32); res = np.ones(len(hi), f32)
        org = P[hi] + n[hi] * 0.004
        act = np.arange(len(hi))
        for s in range(48):
            if len(act) == 0: break
            dd = scene(org[act] + LIGHT * st[act, None])
            res[act] = np.minimum(res[act], 9.0 * dd / st[act])
            st[act] += np.clip(dd, 0.01, 0.25)
            keep = (dd > 0.0005) & (st[act] < 4.0)
            res[act[dd <= 0.0005]] = 0
            act = act[keep]
        sh[hi] = np.clip(res, 0, 1) ** 1.3
        # AO
        ao = np.ones(len(idx), f32)
        occ = np.zeros(len(hi), f32)
        for k in range(1, 6):
            hh = 0.035 * k
            occ += (hh - scene(P[hi] + n[hi] * hh)) / (2 ** k)
        ao[hi] = np.clip(1 - 2.2 * occ, 0.15, 1)
        # 색
        alb, spec, shin = albedo_and_extra(P, n, mat)
        diff = np.clip(n @ LIGHT, 0, 1)
        sun = np.array([1.12, 1.22, 1.10], f32)
        amb = (np.array([0.05, 0.11, 0.11], f32) * (1 - (n[:, 1:2] * 0.5 + 0.5)) + np.array([0.20, 0.38, 0.36], f32) * (n[:, 1:2] * 0.5 + 0.5)) * ao[:, None]
        hv = LIGHT[None, :] - rd; hv /= np.linalg.norm(hv, axis=1, keepdims=True)
        sp = spec * np.clip(np.sum(n * hv, axis=1), 0, 1) ** shin
        col = alb * (amb + sun * (diff * sh)[:, None]) + (sun * (sp * sh)[:, None])
        Tr = np.exp(-sigma[None, :] * t[:, None]) * np.exp(-np.maximum(t - 7.0, 0) * 0.16)[:, None]
        a = Tr[:, 1]
        rgb = col * Tr / np.maximum(a[:, None], 1e-4)
        out_col[idx] = np.clip(rgb, 0, 1); out_a[idx] = a
        Ly = LIGHT[1]
        out_cpos[idx, 0] = P[:, 0] - P[:, 1] * LIGHT[0] / Ly
        out_cpos[idx, 1] = P[:, 2] - P[:, 1] * LIGHT[2] / Ly
        out_mask[idx] = np.clip(diff * sh * a * (0.4 + 0.6 * np.clip(n[:, 1], 0, 1)), 0, 1)
        print(f"  chunk {ci // CH + 1}/{(len(down) + CH - 1) // CH}  {time.time() - t0:.0f}s", flush=True)

    def down_s(arr):
        c = arr.reshape(RH // SS, SS, RW // SS, SS, -1).mean(axis=(1, 3)) if SS > 1 else arr.reshape(RH, RW, -1)
        return c
    col = down_s(out_col * out_a[:, None])          # 미리 곱한 뒤 평균
    a = down_s(out_a[:, None])[..., 0]
    col = col / np.maximum(a[..., None], 1e-4)
    rgba = np.concatenate([np.clip(col, 0, 1), a[..., None]], axis=2)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUTDIR, "seabed_scene.png"))
    # 빛무늬 좌표: x -8~12, z -40~8 를 12비트로
    cp = out_cpos.reshape(RH, RW, 2)[SS // 2::SS, SS // 2::SS]
    xq = np.clip((cp[..., 0] + 8) / 20, 0, 1) * 4095
    zq = np.clip((cp[..., 1] + 40) / 48, 0, 1) * 4095
    xq = xq.astype(np.uint16); zq = zq.astype(np.uint16)
    R = (xq >> 4).astype(np.uint8); G = (((xq & 15) << 4) | (zq >> 8)).astype(np.uint8); B = (zq & 255).astype(np.uint8)
    Image.fromarray(np.stack([R, G, B], 2), "RGB").save(os.path.join(OUTDIR, "seabed_caustic_pos.png"))
    mk = down_s(out_mask[:, None])[..., 0]
    Image.fromarray((np.clip(mk, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUTDIR, "seabed_caustic_mask.png"))
    print(f"done {time.time() - t0:.0f}s")

def project(pw):
    fwd = norm(TARGET - CAM); right = norm(np.cross(fwd, V(0, 1, 0))); up = np.cross(right, fwd)
    d = pw - CAM; z = d @ fwd; tan = math.tan(FOV / 2)
    sx = (d @ right) / z / (tan * W / H); sy = (d @ up) / z / tan
    return [round(float((sx + 1) / 2 * 1920), 1), round(float((1 - sy) / 2 * 1080), 1)]

if __name__ == "__main__":
    render()
    marks = {
        "board_low_corner": project(B_CENTER + B_ROT @ V(-1.15, 0, 1.15)),
        "board_high_corner": project(B_CENTER + B_ROT @ V(1.15, 0, -1.15)),
        "under_board_right": project(B_CENTER + B_ROT @ V(1.15, -0.04, 0.6)),
        "under_board_back": project(B_CENTER + B_ROT @ V(0.2, -0.04, -1.15)),
        "rock_back": project(V(3.25, 0.25, -1.05)),
        "coral_branch": project(BRANCH_BASE[0]),
        "sand_left_far": project(V(-2.5, height(np.array([-2.5]), np.array([-3.0]))[0], -3.0)),
        "sand_left_mid": project(V(-1.6, 0.0, -0.8)),
        "sand_right_front": project(V(4.2, 0.0, 1.8)),
    }
    json.dump(marks, open(os.path.join(OUTDIR, "seabed_marks.json"), "w"), indent=1)
    print(marks)
