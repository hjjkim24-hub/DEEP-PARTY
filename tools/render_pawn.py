# 실사풍 보드게임 말 + 꾸미기 아이템 그림 만들기 (레이마칭, numpy)
# 결과물 (모두 같은 크기·같은 카메라라서 그대로 겹쳐 그리면 맞아요):
#   textures/pawn_diffuse.png        흰색으로 칠한 말의 명암 (플레이어 색을 곱해서 칠함)
#   textures/pawn_spec.png           말의 반짝임 (흰색, 투명도로 세기)
#   textures/cosmetics/pattern_*.png 무늬 (흰색 명암, 무늬 색을 곱해서 칠함)
#   textures/cosmetics/<아이템>.png  모자·장식품·옷 (색까지 칠해진 그림, 말에 가려지는 부분은 빠져 있음)
#   textures/pawn_frame.json         그림 안에서 말 위끝/아래끝 위치
# 사용법: python render_pawn.py            (전부)
#         python render_pawn.py crown coat (일부만)
import math, os, sys, json, time
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "textures")
OUT_C = os.path.join(OUT, "cosmetics")
os.makedirs(OUT_C, exist_ok=True)
W, H, SS = 640, 960, 2
f32 = np.float32
V3 = lambda x, y, z: np.array([x, y, z], f32)

# ================================================================ 말 모양 (회전체, 높이 1)
PROFILE = [(0.0, 0.0), (0.300, 0.0), (0.312, 0.012), (0.315, 0.045), (0.305, 0.070), (0.275, 0.088), (0.245, 0.098),
           (0.215, 0.118), (0.190, 0.150), (0.165, 0.205), (0.143, 0.275), (0.126, 0.355), (0.114, 0.440), (0.106, 0.515),
           (0.104, 0.560), (0.150, 0.575), (0.178, 0.592), (0.182, 0.608), (0.170, 0.624), (0.118, 0.640), (0.096, 0.655)]
for k in range(1, 26):
    a = -1.15 + (math.pi / 2 + 1.15) * k / 25
    PROFILE.append((0.152 * math.cos(a), 0.792 + 0.152 * math.sin(a)))
PROFILE.append((0.0, 0.944))

def _smooth(pts, sub=10):
    out = []
    n = len(pts)
    for i in range(n - 1):
        p0 = pts[max(i - 1, 0)]; p1 = pts[i]; p2 = pts[i + 1]; p3 = pts[min(i + 2, n - 1)]
        for k in range(sub):
            t = k / sub
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in range(2)))
    out.append(pts[-1])
    return out
POLY = np.array([PROFILE[0]] + _smooth(PROFILE[1:]), f32)

def sd_poly2(px, py):
    n = len(POLY)
    d = np.full(px.shape, 1e9, f32); sgn = np.ones(px.shape, f32)
    for i in range(n):
        ax, ay = POLY[i]; bx, by = POLY[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        wx, wy = px - ax, py - ay
        t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey + 1e-12), 0, 1)
        dx, dy = wx - ex * t, wy - ey * t
        d = np.minimum(d, dx * dx + dy * dy)
        c1 = py >= ay; c2 = py < by; c3 = ex * wy > ey * wx
        flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
        sgn = np.where(flip, -sgn, sgn)
    return sgn * np.sqrt(d)

GR0, GR1, GY0, GY1, GS = 0.0, 0.42, -0.06, 1.0, 0.0005
_gr = np.arange(GR0, GR1, GS, dtype=f32); _gy = np.arange(GY0, GY1, GS, dtype=f32)
_RR, _YY = np.meshgrid(_gr, _gy)
GRID = sd_poly2(_RR.ravel(), _YY.ravel()).reshape(_RR.shape).astype(f32)

def sd_lookup(r, y):
    fx = np.clip((r - GR0) / GS, 0, len(_gr) - 1.001); fy = np.clip((y - GY0) / GS, 0, len(_gy) - 1.001)
    x0 = fx.astype(int); y0 = fy.astype(int); tx = fx - x0; ty = fy - y0
    v = (GRID[y0, x0] * (1 - tx) + GRID[y0, x0 + 1] * tx) * (1 - ty) + (GRID[y0 + 1, x0] * (1 - tx) + GRID[y0 + 1, x0 + 1] * tx) * ty
    ox = np.maximum(r - (GR1 - GS), 0); oy = np.maximum(np.maximum(GY0 - y, y - (GY1 - GS)), 0)
    return v + np.sqrt(ox * ox + oy * oy)

def body_radius(y):
    """그 높이에서 말 표면의 반지름 (옷 위치 잡을 때 사용)"""
    ys = POLY[:, 1]; rs = POLY[:, 0]
    best = 0
    for i in range(len(POLY) - 1):
        if (ys[i] - y) * (ys[i + 1] - y) <= 0 and ys[i] != ys[i + 1]:
            t = (y - ys[i]) / (ys[i + 1] - ys[i]); best = max(best, rs[i] + (rs[i + 1] - rs[i]) * t)
    return best

def sd_pawn(p):
    r = np.sqrt(p[:, 0] ** 2 + p[:, 2] ** 2)
    return sd_lookup(r, p[:, 1]) * 0.9

# ================================================================ 기본 도형
def length(v): return np.sqrt(np.sum(v * v, axis=1))
def sd_sphere(p, c, r): return length(p - c) - r
def sd_capsule(p, a, b, r):
    pa = p - a; ba = b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0, 1)
    return length(pa - h[:, None] * ba[None]) - r
def sd_torus_y(p, c, R, r):
    q = p - c
    return np.sqrt((np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - R) ** 2 + q[:, 1] ** 2) - r
def sd_round_box(q, b, r):
    d = np.abs(q) - (b - r)
    return length(np.maximum(d, 0)) + np.minimum(np.max(d, axis=1), 0) - r
def sd_cyl_y(p, c, r, h, rr=0.0):
    q = p - c
    dx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - (r - rr); dy = np.abs(q[:, 1]) - (h - rr)
    return np.minimum(np.maximum(dx, dy), 0) + np.sqrt(np.maximum(dx, 0) ** 2 + np.maximum(dy, 0) ** 2) - rr
def smin(a, b, k):
    h = np.maximum(k - np.abs(a - b), 0) / k
    return np.minimum(a, b) - h * h * k * 0.25
def rot_x(a): c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], f32)
def rot_y(a): c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], f32)
def rot_z(a): c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], f32)
def theta(p): return np.arctan2(p[:, 0], p[:, 2])  # 0 = 정면(카메라 쪽)

HEAD_C = V3(0, 0.792, 0); HEAD_R = 0.152
HAT_TILT = rot_z(-0.10) @ rot_x(-0.06)   # 모자는 살짝 비스듬히

def in_hat(p, origin):
    """모자 좌표계: origin 기준, 살짝 기울임"""
    return (p - origin) @ HAT_TILT

# ================================================================ 아이템 (거리 함수 + 재질)
# 재질 함수는 (점, 법선) -> (색, 반짝임 세기, 반짝임 날카로움)

def party_hat_sd(p):
    q = in_hat(p, V3(0, 0.905, 0))
    h = 0.27; r0 = 0.118
    # 원뿔 (밑면 반지름 r0, 높이 h)
    rq = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2)
    k = np.array([h, r0]) / math.hypot(h, r0)
    cone = np.maximum(rq * k[0] - (h - q[:, 1]) * k[1] * 1.0, -q[:, 1])  # 근사
    cone = np.maximum((rq - r0 * (1 - q[:, 1] / h)) * k[0], -q[:, 1])
    cone = np.maximum(cone, q[:, 1] - h)
    pom = sd_sphere(q, V3(0, h + 0.01, 0), 0.042)
    return np.minimum(cone, pom) * 0.85

def party_hat_mat(p, n):
    q = in_hat(p, V3(0, 0.905, 0))
    th = np.arctan2(q[:, 0], q[:, 2])
    s = np.sin(th * 3 + q[:, 1] * 38) > 0
    col = np.where(s[:, None], np.array([0.95, 0.42, 0.40], f32), np.array([0.98, 0.94, 0.86], f32))
    dots = (np.sin(th * 14) * np.sin(q[:, 1] * 120) > 0.85)
    col[dots] = np.array([1.0, 0.85, 0.35], f32)
    pom = q[:, 1] > 0.255
    col[pom] = np.array([0.45, 0.88, 0.80], f32)
    return col, np.full(len(p), 0.25, f32), np.full(len(p), 20, f32)

def top_hat_sd(p):
    q = in_hat(p, V3(0, 0.915, 0))
    crown = sd_cyl_y(q, V3(0, 0.115, 0), 0.118, 0.115, 0.012)
    brim = sd_cyl_y(q, V3(0, 0.0, 0), 0.205, 0.008, 0.006)
    return smin(crown, brim, 0.012)

def top_hat_mat(p, n):
    q = in_hat(p, V3(0, 0.915, 0))
    col = np.tile(np.array([0.07, 0.07, 0.085], f32), (len(p), 1))
    band = (q[:, 1] > 0.012) & (q[:, 1] < 0.055) & (np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) < 0.135)
    col[band] = np.array([0.80, 0.22, 0.26], f32)
    return col, np.where(band, 0.35, 0.22).astype(f32), np.where(band, 30, 18).astype(f32)

def crown_sd(p):
    q = in_hat(p, V3(0, 0.905, 0))
    th = np.arctan2(q[:, 0], q[:, 2])
    rq = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2)
    top = 0.075 + 0.065 * np.clip(np.cos(th * 5), 0, 1) ** 3
    shell = np.maximum(np.abs(rq - 0.125) - 0.012, np.maximum(q[:, 1] - top, -q[:, 1]))
    d = shell * 0.7
    for k in range(5):
        a = k * 2 * math.pi / 5
        d = np.minimum(d, sd_sphere(q, V3(math.sin(a) * 0.125, 0.145, math.cos(a) * 0.125), 0.017))
    band = sd_torus_y(q, V3(0, 0.012, 0), 0.127, 0.012)
    return np.minimum(d, band)

def crown_mat(p, n):
    q = in_hat(p, V3(0, 0.905, 0))
    th = np.arctan2(q[:, 0], q[:, 2])
    col = np.tile(np.array([1.0, 0.76, 0.28], f32), (len(p), 1))
    gem = (np.abs(q[:, 1] - 0.045) < 0.016) & (np.abs(np.sin(th * 5 / 2 * 2 / 2 * 2)) > 0.0)
    gem = (np.abs(q[:, 1] - 0.045) < 0.017) & (np.cos(th * 5) > 0.93)
    col[gem] = np.where((np.round(th * 5 / (2 * math.pi)) % 2 == 0)[gem][:, None], np.array([0.85, 0.12, 0.2], f32), np.array([0.15, 0.35, 0.9], f32))
    return col, np.full(len(p), 0.9, f32), np.full(len(p), 45, f32)

def beanie_sd(p):
    q = p - V3(0, 0.0, 0)
    cap = np.maximum(sd_sphere(q, HEAD_C + V3(0, 0.008, 0), HEAD_R + 0.026), 0.835 - q[:, 1])
    rim = sd_torus_y(q, V3(0, 0.845, 0), HEAD_R * 0.93 + 0.012, 0.028)
    pom_c = V3(0, 0.985, 0)
    pom = sd_sphere(q, pom_c, 0.055)
    pom = pom + 0.006 * np.sin(q[:, 0] * 160) * np.sin(q[:, 1] * 150) * np.sin(q[:, 2] * 170)
    return np.minimum(np.minimum(cap, rim), pom * 0.8)

def beanie_mat(p, n):
    th = theta(p)
    rib = 0.88 + 0.12 * (np.sin(th * 34) > 0)
    col = np.array([0.90, 0.62, 0.22], f32)[None] * rib[:, None]
    rim = p[:, 1] < 0.875
    col[rim] = (np.array([0.80, 0.52, 0.16], f32)[None] * (0.88 + 0.12 * (np.sin(th[rim] * 50) > 0))[:, None])
    pom = p[:, 1] > 0.935
    col[pom] = np.array([0.97, 0.93, 0.85], f32)
    return col, np.full(len(p), 0.05, f32), np.full(len(p), 8, f32)

def scarf_sd(p):
    ring = sd_torus_y(p, V3(0, 0.662, 0), 0.128, 0.058)
    ring = ring + 0.005 * np.sin(theta(p) * 26)
    tail = sd_round_box((p - V3(0.085, 0.50, 0.175)) @ rot_z(-0.16) @ rot_x(0.22), V3(0.052, 0.15, 0.016), 0.014)
    tail2 = sd_round_box((p - V3(0.035, 0.53, 0.185)) @ rot_z(0.10) @ rot_x(0.20), V3(0.048, 0.12, 0.015), 0.013)
    tail = np.minimum(tail, tail2)
    return np.minimum(ring, tail) * 0.9

def scarf_mat(p, n):
    th = theta(p)
    u = np.where(p[:, 1] > 0.615, th * 6, p[:, 1] * 55)
    stripe = np.sin(u) > 0
    col = np.where(stripe[:, None], np.array([0.78, 0.15, 0.18], f32), np.array([0.96, 0.92, 0.84], f32))
    knit = 0.9 + 0.1 * (np.sin(p[:, 0] * 300 + p[:, 1] * 200) > 0)
    return col * knit[:, None], np.full(len(p), 0.04, f32), np.full(len(p), 8, f32)

def sunglasses_sd(p):
    d = np.full(len(p), 1e3, f32)
    for sx in (-1, 1):
        lens_c = V3(sx * 0.062, 0.792, 0.142)
        q = (p - lens_c) @ rot_y(sx * 0.30).T
        lens = sd_round_box(q, V3(0.052, 0.032, 0.006), 0.016)
        rim = np.maximum(np.abs(sd_round_box(q * V3(1, 1, 0), V3(0.052, 0.032, 1.0), 0.016)) - 0.006, np.abs(q[:, 2]) - 0.009)
        d = np.minimum(d, np.minimum(lens, rim))
        d = np.minimum(d, sd_capsule(p, V3(sx * 0.112, 0.80, 0.112), V3(sx * 0.152, 0.805, -0.02), 0.006))
    d = np.minimum(d, sd_capsule(p, V3(-0.016, 0.805, 0.156), V3(0.016, 0.805, 0.156), 0.006))
    return d

def sunglasses_mat(p, n):
    # 렌즈는 위가 살짝 밝은 짙은 청록 그라데이션, 테는 검정
    g = np.clip((p[:, 1] - 0.76) / 0.06, 0, 1)
    col = (np.array([0.02, 0.05, 0.07], f32)[None] * (1 - g[:, None]) + np.array([0.10, 0.22, 0.26], f32)[None] * g[:, None])
    return col, np.full(len(p), 1.1, f32), np.full(len(p), 90, f32)

PEARL_N = 24
def pearls_sd(p):
    d = np.full(len(p), 1e3, f32)
    for k in range(PEARL_N):
        a = k * 2 * math.pi / PEARL_N
        R = 0.128 + 0.012 * (0.5 + 0.5 * math.cos(a)); y = 0.648 - 0.030 * (0.5 + 0.5 * math.cos(a))  # 앞쪽이 내려옴
        d = np.minimum(d, sd_sphere(p, V3(math.sin(a) * R, y, math.cos(a) * R), 0.023))
    return d

def pearls_mat(p, n):
    irid = 0.03 * np.sin(n[:, 0] * 8 + n[:, 1] * 6)
    col = np.stack([0.95 + irid, 0.93 - irid * 0.5, 0.90 + irid], 1).astype(f32)
    return col, np.full(len(p), 0.9, f32), np.full(len(p), 60, f32)

def cape_rc(y):
    return 0.205 + (0.60 - y) * 0.30

def cape_sd(p):
    y = p[:, 1]; r = np.sqrt(p[:, 0] ** 2 + p[:, 2] ** 2); th = theta(p)
    wave = 0.012 * np.sin(th * 7 + y * 6)
    shell = np.abs(r - cape_rc(y) - wave) - 0.010
    back = np.cos(th) < 0.15  # 정면 쪽은 열려 있음
    d = np.maximum(shell, np.maximum(y - 0.60, 0.10 - y))
    d = np.where(back, d, np.maximum(d, (np.cos(th) - 0.15) * r))
    clasp = sd_sphere(p, V3(0, 0.598, 0.188), 0.022)
    collar = sd_torus_y(p, V3(0, 0.60, 0), 0.19, 0.016)
    return np.minimum(np.minimum(d * 0.8, clasp), collar)

def cape_mat(p, n):
    y = p[:, 1]
    col = np.tile(np.array([0.70, 0.08, 0.11], f32), (len(p), 1))
    trim = (y < 0.13) | (p[:, 1] > 0.585)
    col[trim] = np.array([0.98, 0.76, 0.30], f32)
    inside = n[:, 2] < -0.2
    col[inside & ~trim] = np.array([0.45, 0.04, 0.07], f32)
    return col, np.where(trim, 0.8, 0.18).astype(f32), np.where(trim, 40, 14).astype(f32)

def swim_ring_sd(p):
    R = body_radius(0.29) + 0.070
    return sd_torus_y(p, V3(0, 0.29, 0), R, 0.074)

def swim_ring_mat(p, n):
    th = theta(p)
    seg = (np.floor((th + math.pi / 8) / (math.pi / 4)) % 2) == 0
    col = np.where(seg[:, None], np.array([0.95, 0.38, 0.36], f32), np.array([0.98, 0.96, 0.92], f32))
    return col, np.full(len(p), 0.6, f32), np.full(len(p), 40, f32)

def coat_sd(p):
    y = p[:, 1]
    r = np.sqrt(p[:, 0] ** 2 + p[:, 2] ** 2)
    off = 0.022 + np.clip(0.50 - y, 0, 1) * 0.06
    d = sd_lookup(r, y) * 0.9 - off
    d = np.maximum(d, np.maximum(0.125 - y, y - 0.585))
    collar = sd_torus_y(p, V3(0, 0.585, 0), 0.155, 0.03)
    d = np.minimum(d, collar)
    for k, by in enumerate([0.24, 0.34, 0.44]):
        rr = body_radius(by) + 0.022 + max(0.50 - by, 0) * 0.06
        d = np.minimum(d, sd_sphere(p, V3(0, by, rr + 0.002), 0.016))
    return d

def coat_mat(p, n):
    th = theta(p); y = p[:, 1]
    col = np.tile(np.array([0.66, 0.46, 0.28], f32), (len(p), 1))
    placket = (np.abs(th) < 0.12) & (y < 0.57)
    col[placket] = np.array([0.56, 0.38, 0.22], f32)
    r = np.sqrt(p[:, 0] ** 2 + p[:, 2] ** 2)
    buttons = np.zeros(len(p), bool)
    for by in [0.24, 0.34, 0.44]:
        rr = body_radius(by) + 0.022 + max(0.50 - by, 0) * 0.06
        buttons |= length(p - V3(0, by, rr + 0.002)) < 0.02
    col[buttons] = np.array([0.22, 0.13, 0.07], f32)
    tw = 0.92 + 0.08 * (np.sin(p[:, 0] * 260 + y * 260) > 0)
    col = col * tw[:, None]
    return col, np.where(buttons, 0.8, 0.08).astype(f32), np.where(buttons, 50, 10).astype(f32)

ITEMS = {
    "party_hat": (party_hat_sd, party_hat_mat),
    "top_hat": (top_hat_sd, top_hat_mat),
    "crown": (crown_sd, crown_mat),
    "beanie": (beanie_sd, beanie_mat),
    "scarf": (scarf_sd, scarf_mat),
    "sunglasses": (sunglasses_sd, sunglasses_mat),
    "pearl_necklace": (pearls_sd, pearls_mat),
    "red_cape": (cape_sd, cape_mat),
    "swim_ring": (swim_ring_sd, swim_ring_mat),
    "coat": (coat_sd, coat_mat),
}

# 무늬: 말 표면에서 무늬가 칠해지는 곳 (1 = 칠함)
def pattern_stripes(p):
    y = p[:, 1]
    m = (np.sin(y * 52) > 0.35) & (y < 0.57)
    return m.astype(f32)

def pattern_diamond(p):
    y = p[:, 1]; th = theta(p)
    u = th / (2 * math.pi) * 10; v = y * 9
    fu = np.abs(u - np.floor(u) - 0.5); fv = np.abs(v - np.floor(v) - 0.5)
    m = ((fu + fv) < 0.32) & (y < 0.57) & (y > 0.10)
    return m.astype(f32)

PATTERNS = {"stripes": pattern_stripes, "diamond": pattern_diamond}

# ================================================================ 카메라·조명
elev = math.radians(11)
dist = 9.0
Y_LO, Y_HI = -0.09, 1.30
center = V3(0, (Y_LO + Y_HI) / 2, 0)
cam = center + V3(0, math.sin(elev), math.cos(elev)) * dist
fwd = (center - cam) / np.linalg.norm(center - cam)
right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
up = np.cross(right, fwd)
tanv = (Y_HI - Y_LO) / 2 / dist
RW, RH = W * SS, H * SS
jj, ii = np.meshgrid(np.arange(RH, dtype=f32), np.arange(RW, dtype=f32), indexing="ij")
sx = ((ii + 0.5) / RW * 2 - 1) * tanv * (W / H); sy = (1 - (jj + 0.5) / RH * 2) * tanv
DIRS = fwd[None, None] + sx[..., None] * right + sy[..., None] * up
DIRS = (DIRS / np.linalg.norm(DIRS, axis=2, keepdims=True)).reshape(-1, 3).astype(f32)
KEY = V3(-0.55, 0.75, 0.55); KEY /= np.linalg.norm(KEY)
FILL = V3(0.75, 0.25, 0.45); FILL /= np.linalg.norm(FILL)

def march(sdf, dirs):
    t = np.full(len(dirs), dist - 1.5, f32)
    hit = np.zeros(len(dirs), bool); act = np.arange(len(dirs))
    for step in range(200):
        if len(act) == 0: break
        p = cam + dirs[act] * t[act, None]
        d = sdf(p)
        h = d < 0.0004
        hit[act[h]] = True
        far = t[act] > dist + 1.5
        t[act] += np.where(h, 0, d)
        act = act[~(h | far)]
    return hit, t

def normals(sdf, P):
    e = 0.0007; n = np.zeros_like(P)
    for k in [V3(1, -1, -1), V3(-1, -1, 1), V3(-1, 1, -1), V3(1, 1, 1)]:
        n += k[None] * sdf(P + k * e)[:, None]
    return n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-9)

def soft_shadow(sdf, org, L):
    res = np.ones(len(org), f32); st = np.full(len(org), 0.01, f32); a = np.arange(len(org))
    for s in range(80):
        if len(a) == 0: break
        dd = sdf(org[a] + L * st[a, None])
        res[a] = np.minimum(res[a], 6 * dd / st[a])
        st[a] += np.clip(dd, 0.004, 0.06)
        keep = (dd > 0.0002) & (st[a] < 1.5)
        res[a[dd <= 0.0002]] = 0
        a = a[keep]
    return np.clip(res, 0, 1)

def ambient_occ(sdf, P, n):
    occ = np.zeros(len(P), f32)
    for k in range(1, 6):
        hh = 0.018 * k
        occ += (hh - sdf(P + n * hh)) / (2 ** k)
    return np.clip(1 - 3.0 * occ, 0.2, 1)

def light(P, n, dirs, sh, ao):
    ndk = n @ KEY
    wrap = np.clip((ndk + 0.35) / 1.35, 0, 1) ** 1.4
    df = np.clip(n @ FILL, 0, 1)
    amb = (0.20 + 0.18 * (n[:, 1] * 0.5 + 0.5)) * ao
    diff = amb + 0.92 * wrap * (0.35 + 0.65 * sh) + 0.25 * df * ao
    V = -dirs
    hv = KEY[None] + V; hv /= np.linalg.norm(hv, axis=1, keepdims=True)
    nh = np.clip(np.sum(n * hv, 1), 0, 1)
    nv = np.clip(np.sum(n * V, 1), 0, 1)
    rim = 0.22 * (1 - nv) ** 3.5 * np.clip(n[:, 1] + 0.6, 0, 1) * ao
    return diff, nh, rim

def downs(a):
    return a.reshape(H, SS, W, SS, *a.shape[2:]).mean(axis=(1, 3))

def save_rgba(rgb, a, path):
    rgba = np.concatenate([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]], 2)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(path)

# ================================================================ 렌더
def render_base():
    t0 = time.time()
    hit, t = march(sd_pawn, DIRS)
    hi = np.where(hit)[0]
    P = cam + DIRS[hi] * t[hi, None]
    n = normals(sd_pawn, P)
    sh = soft_shadow(sd_pawn, P + n * 0.002, KEY)
    ao = ambient_occ(sd_pawn, P, n)
    diff, nh, rim = light(P, n, DIRS[hi], sh, ao)
    spec = np.clip((0.55 * nh ** 90 + 0.12 * nh ** 14) * sh + rim, 0, 1)
    N = len(DIRS)
    cov = np.zeros(N, f32); cov[hi] = 1
    dv = np.zeros(N, f32); dv[hi] = np.clip(0.9 * diff, 0, 1)
    sv = np.zeros(N, f32); sv[hi] = spec
    A = downs(cov.reshape(RH, RW)); D = downs(dv.reshape(RH, RW)) / np.maximum(A, 1e-4); Sp = downs(sv.reshape(RH, RW))
    save_rgba(np.stack([D, D, D], 2), A, os.path.join(OUT, "pawn_diffuse.png"))
    save_rgba(np.ones((H, W, 3), f32), Sp, os.path.join(OUT, "pawn_spec.png"))
    rows = np.where(A.max(axis=1) > 0.5)[0]
    json.dump({"top": float(rows.min() / H), "bottom": float((rows.max() + 1) / H), "width": W, "height": H},
              open(os.path.join(OUT, "pawn_frame.json"), "w"))
    # 무늬
    for name, fn in PATTERNS.items():
        m = fn(P)
        pv = np.zeros(N, f32); pv[hi] = m
        PA = downs(pv.reshape(RH, RW))
        save_rgba(np.stack([D, D, D], 2), PA, os.path.join(OUT_C, f"pattern_{name}.png"))
    print(f"base + patterns {time.time() - t0:.0f}s  frame rows {rows.min() / H:.4f} {(rows.max() + 1) / H:.4f}")

def render_item(name):
    t0 = time.time()
    isd, imat = ITEMS[name]
    def combo(p): return np.minimum(sd_pawn(p), isd(p))
    hit, t = march(combo, DIRS)
    hi = np.where(hit)[0]
    P = cam + DIRS[hi] * t[hi, None]
    is_item = isd(P) <= sd_pawn(P) + 1e-5
    hi2 = hi[is_item]; P2 = P[is_item]
    n = normals(isd, P2)
    sh = soft_shadow(combo, P2 + n * 0.003, KEY)
    ao = ambient_occ(combo, P2, n)
    diff, nh, rim = light(P2, n, DIRS[hi2], sh, ao)
    alb, ks, shin = imat(P2, n)
    col = alb * diff[:, None] + ((ks * nh ** shin) * sh + rim * 0.6)[:, None]
    N = len(DIRS)
    cov = np.zeros(N, f32); cov[hi2] = 1
    cv = np.zeros((N, 3), f32); cv[hi2] = col
    A = downs(cov.reshape(RH, RW)); C = downs(cv.reshape(RH, RW, 3)) / np.maximum(A, 1e-4)[..., None]
    save_rgba(C, A, os.path.join(OUT_C, f"{name}.png"))
    print(f"  {name}: {time.time() - t0:.0f}s")

# ================================================================ 아이콘 (꾸미기 화면 아이템 칸용, 아이템만 단독으로)
OUT_I = os.path.join(OUT_C, "icons")
ICON = 256

def icon_rays(u0, u1, v0, v1, res, elev_deg):
    el = math.radians(elev_deg)
    c = V3(0, 0.6, 0)
    cm = c + V3(0, math.sin(el), math.cos(el)) * dist
    fw = (c - cm) / np.linalg.norm(c - cm)
    rt = np.cross(fw, [0, 1, 0]); rt /= np.linalg.norm(rt)
    upv = np.cross(rt, fw)
    tv = 0.75 / dist
    j, i = np.meshgrid(np.arange(res, dtype=f32), np.arange(res, dtype=f32), indexing="ij")
    su = u0 + (i + 0.5) / res * (u1 - u0); sv = v1 - (j + 0.5) / res * (v1 - v0)
    dirs = fw[None, None] + (su * tv)[..., None] * rt + (sv * tv)[..., None] * upv
    dirs = (dirs / np.linalg.norm(dirs, axis=2, keepdims=True)).reshape(-1, 3).astype(f32)
    return cm, dirs

def march_from(origin, sdf, dirs):
    t = np.full(len(dirs), dist - 1.5, f32)
    hit = np.zeros(len(dirs), bool); act = np.arange(len(dirs))
    for step in range(220):
        if len(act) == 0: break
        p = origin + dirs[act] * t[act, None]
        d = sdf(p)
        h = d < 0.0003
        hit[act[h]] = True
        far = t[act] > dist + 1.5
        t[act] += np.where(h, 0, d)
        act = act[~(h | far)]
    return hit, t

def shade_icon(origin, dirs, sdf, matfn, res, ss):
    hit, t = march_from(origin, sdf, dirs)
    hi = np.where(hit)[0]
    P = origin + dirs[hi] * t[hi, None]
    n = normals(sdf, P)
    sh = soft_shadow(sdf, P + n * 0.003, KEY)
    ao = ambient_occ(sdf, P, n)
    diff, nh, rim = light(P, n, dirs[hi], sh, ao)
    return hit, hi, P, n, sh, diff, nh, rim

def frame_window(sdf, elev):
    # 대충 그려서 아이템이 차지하는 범위를 찾고, 정사각형으로 여유 있게 잡기
    u0, u1, v0, v1 = -1.0, 1.0, -1.0, 1.0
    cm, dirs = icon_rays(u0, u1, v0, v1, 200, elev)
    hit, _ = march_from(cm, sdf, dirs)
    m = hit.reshape(200, 200)
    ys, xs = np.where(m)
    uu0 = u0 + xs.min() / 200 * 2; uu1 = u0 + (xs.max() + 1) / 200 * 2
    vv1 = v1 - ys.min() / 200 * 2; vv0 = v1 - (ys.max() + 1) / 200 * 2
    cu, cv = (uu0 + uu1) / 2, (vv0 + vv1) / 2
    half = max(uu1 - uu0, vv1 - vv0) / 2 * 1.18
    return cu - half, cu + half, cv - half, cv + half

def render_icon(name, elev=20):
    isd, imat = ITEMS[name]
    u0, u1, v0, v1 = frame_window(isd, elev)
    res = ICON * 2
    cm, dirs = icon_rays(u0, u1, v0, v1, res, elev)
    hit, hi, P, n, sh, diff, nh, rim = shade_icon(cm, dirs, isd, imat, res, 2)
    alb, ks, shin = imat(P, n)
    col = alb * diff[:, None] + ((ks * nh ** shin) * sh + rim * 0.6)[:, None]
    cov = np.zeros(res * res, f32); cov[hi] = 1
    cv = np.zeros((res * res, 3), f32); cv[hi] = col
    A = cov.reshape(ICON, 2, ICON, 2).mean(axis=(1, 3))
    C = cv.reshape(ICON, 2, ICON, 2, 3).mean(axis=(1, 3)) / np.maximum(A, 1e-4)[..., None]
    save_rgba(C, A, os.path.join(OUT_I, f"{name}.png"))

def render_pattern_icons():
    # 무늬는 구슬 위에 칠해서 보여줌: 구슬 명암(흰색) + 반짝임 + 무늬별 칠할 곳
    c = V3(0, 0.335, 0); r = 0.215
    sph = lambda p: sd_sphere(p, c, r)
    u0, u1, v0, v1 = frame_window(sph, 12)
    res = ICON * 2
    cm, dirs = icon_rays(u0, u1, v0, v1, res, 12)
    hit, hi, P, n, sh, diff, nh, rim = shade_icon(cm, dirs, sph, None, res, 2)
    def down(v):
        full = np.zeros(res * res, f32); full[hi] = v
        return full.reshape(ICON, 2, ICON, 2).mean(axis=(1, 3))
    A = down(np.ones(len(hi), f32))
    D = down(np.clip(0.9 * diff, 0, 1)) / np.maximum(A, 1e-4)
    Sp = down(np.clip((0.55 * nh ** 90 + 0.12 * nh ** 14) * sh + rim, 0, 1))
    save_rgba(np.stack([D, D, D], 2), A, os.path.join(OUT_I, "sphere_diffuse.png"))
    save_rgba(np.ones((ICON, ICON, 3), f32), Sp, os.path.join(OUT_I, "sphere_spec.png"))
    # 구슬 좌표를 말 몸통 높이로 옮겨서 같은 무늬 함수 사용
    Q = P.copy()
    Q[:, 1] = 0.12 + (P[:, 1] - (c[1] - r)) / (2 * r) * 0.44
    for name, fn in PATTERNS.items():
        M = down(fn(Q))
        save_rgba(np.stack([D, D, D], 2), M, os.path.join(OUT_I, f"pattern_{name}.png"))

if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "icons":
    os.makedirs(OUT_I, exist_ok=True)
    t0 = time.time()
    for name in ITEMS:
        render_icon(name, 28 if name in ("swim_ring", "pearl_necklace", "scarf", "crown") else 18)
        print(f"  icon {name} {time.time() - t0:.0f}s", flush=True)
    render_pattern_icons()
    print("icons done")
    sys.exit(0)

if __name__ == "__main__":
    want = sys.argv[1:]
    if not want or "base" in want:
        render_base()
    for name in ITEMS:
        if not want or name in want:
            render_item(name)
