"""튜토리얼 월드 지도 (실사풍) — 말이 직접 들어가 걸어 다니는 '보드게임 속 세상'.

    python render_world.py
    → ../textures/worlds/tutorial_map.png     (비스듬히 내려다본 바다 밑, 3840 x 약 2560)
       ../textures/worlds/tutorial_world.json  (칸 위치·연결, 시작 칸, 움직이는 장식 위치)
       out/tutorial_map_small.png              (상자 그림용)

만드는 방법
  1) 바닥을 '높이 지도'로 만듦: 모래 물결, 바위, 분수 구멍, 판 테두리, 돌길, 네모 돌 칸(조각·상감 포함)
  2) 높이에서 면 방향을 구해 햇빛·부드러운 그림자·틈새 그늘(AO)·반짝임·물빛 무늬를 계산
  3) 50도 위에서 비스듬히 내려다본 모양으로 투영 (앞쪽부터 그려 가려짐 처리)
  4) 산호·해면은 작은 3D 모형을 따로 레이마칭으로 그려 같은 각도로 붙임

칸 구조: 가로 11 x 세로 7 격자의 바깥 테두리 + 가운데 십자 ('田' 모양). 45칸, 골인 없음.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy.ndimage import gaussian_filter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "textures", "worlds")
FONT = os.path.join(ROOT, "fonts", "Poppins-Bold.ttf")
f32 = np.float32
rng = np.random.default_rng(5)

# ── 카메라 / 크기 ────────────────────────────────────────────
ELEV = math.radians(50)            # 내려다보는 각도
KZ = math.sin(ELEV)                # 바닥 깊이 방향 줄어드는 비율
KH = math.cos(ELEV)                # 높이가 화면 위로 올라가는 비율
GW, GD = 3840, 3200                # 바닥 크기 (가로, 깊이)
TOP_PAD = 150                      # 높은 것들이 위로 튀어나올 여유
SW = GW
SH = int(GD * KZ + TOP_PAD + 10)   # 화면(지도 그림) 크기

U = 262                            # 칸 사이 거리
TILE = 160                         # 칸 한 변
TILE_H = 22.0
START_SIZE = 330
START_H = 30.0
CX, CZ = GW / 2, GD / 2 + 40
NI, NJ = 5, 3                      # 가운데에서 가로 ±5, 세로 ±3 칸

RIM = 70                           # 판 테두리 폭

LIGHT = np.array([-0.45, 0.78, -0.43], f32)
LIGHT /= np.linalg.norm(LIGHT)
VIEW = np.array([0.0, math.sin(ELEV), math.cos(ELEV)], f32)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def value_noise(h, w, cell, seed):
    r = np.random.default_rng(seed)
    g = r.random((h // cell + 3, w // cell + 3)).astype(f32)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize(((w // cell + 3) * cell, (h // cell + 3) * cell), Image.BICUBIC)
    return np.asarray(img, f32)[:h, :w] / 255.0


def fbm(h, w, seed, cells=(256, 96, 36, 12), amps=(0.55, 0.25, 0.13, 0.07)):
    out = np.zeros((h, w), f32)
    for i, (c, a) in enumerate(zip(cells, amps)):
        out += a * value_noise(h, w, c, seed + i * 17)
    return out


# ── 칸 구조 ──────────────────────────────────────────────────
def grid_nodes():
    pts = []
    for j in range(-NJ, NJ + 1):
        for i in range(-NI, NI + 1):
            if abs(i) == NI or abs(j) == NJ or i == 0 or j == 0:
                pts.append((i, j))
    ids = {p: k for k, p in enumerate(pts)}
    links = {k: [] for k in range(len(pts))}
    for (i, j), k in ids.items():
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (i + di, j + dj)
            if q in ids:
                links[k].append(ids[q])
    return pts, ids, links


def gpos(i, j):
    return CX + i * U, CZ + j * U


# ── 높이 지도 + 재질 ─────────────────────────────────────────
def build_ground():
    zz, xx = np.mgrid[0:GD, 0:GW].astype(f32)
    h = np.zeros((GD, GW), f32)
    alb = np.zeros((GD, GW, 3), f32)
    spec = np.zeros((GD, GW), f32)        # 반짝임 세기
    mat = np.zeros((GD, GW), np.uint8)    # 0 모래, 1 돌길, 2 칸, 3 바위, 4 테두리, 5 상감

    # 모래: 큰 언덕 + 물결
    dunes = fbm(GD, GW, 3) * 40.0
    warp = fbm(GD, GW, 9, cells=(300, 120), amps=(0.7, 0.3))
    rip = np.sin((zz * 0.95 + xx * 0.32) * 0.085 + warp * 9.0)
    rip = np.sign(rip) * np.abs(rip) ** 0.8
    h += dunes + rip * 2.4 + fbm(GD, GW, 21, cells=(8, 4), amps=(0.6, 0.4)) * 1.2
    sand_var = fbm(GD, GW, 31)
    sand = np.array([176, 168, 140], f32) / 255
    sand2 = np.array([132, 142, 122], f32) / 255
    alb[:] = sand * (1 - sand_var[..., None] * 0.6) + sand2 * (sand_var[..., None] * 0.6)
    alb *= (0.92 + 0.08 * (rip[..., None] * 0.5 + 0.5))
    # 군데군데 조개 가루·자갈
    grit = (value_noise(GD, GW, 3, 77) > 0.86).astype(f32) * fbm(GD, GW, 78, cells=(64,), amps=(1.0,))
    alb += grit[..., None] * np.array([0.12, 0.1, 0.08], f32)
    h += grit * 1.0

    pts, ids, links = grid_nodes()

    # 돌길 (칸 사이)
    path_mask = np.zeros((GD, GW), f32)
    pw = 70
    for (i, j), k in ids.items():
        for q in links[k]:
            i2, j2 = pts[q]
            if (i2, j2) < (i, j):
                continue
            x0, z0 = gpos(i, j)
            x1, z1 = gpos(i2, j2)
            xa, xb = min(x0, x1) - pw / 2, max(x0, x1) + pw / 2
            za, zb = min(z0, z1) - pw / 2, max(z0, z1) + pw / 2
            sl = (slice(int(za) - 8, int(zb) + 8), slice(int(xa) - 8, int(xb) + 8))
            dx = np.maximum(np.maximum(xa - xx[sl], xx[sl] - xb), 0)
            dz = np.maximum(np.maximum(za - zz[sl], zz[sl] - zb), 0)
            d = np.sqrt(dx * dx + dz * dz)
            path_mask[sl] = np.maximum(path_mask[sl], smoothstep(5, 0, d))
    # 자갈돌 무늬 (격자 + 흔들림)
    cell = 22
    jx = value_noise(GD, GW, cell, 41) * 8
    jz = value_noise(GD, GW, cell, 42) * 8
    fx = ((xx + jx) % cell) / cell
    fz = ((zz + jz) % cell) / cell
    cob = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fz, 1 - fz))
    cob_h = smoothstep(0.0, 0.18, cob) * 3.0
    cob_shade = 0.85 + 0.3 * value_noise(GD, GW, cell, 43)
    path_top = 7.0 + cob_h
    h = h * (1 - path_mask) + np.maximum(h, h * 0.3 + path_top) * path_mask
    stone_col = np.array([118, 126, 122], f32) / 255
    pc = stone_col * cob_shade[..., None] * (0.75 + 0.25 * smoothstep(0.0, 0.15, cob)[..., None])
    alb = alb * (1 - path_mask[..., None]) + pc * path_mask[..., None]
    mat[path_mask > 0.5] = 1

    # 판 테두리 (멀리서 보면 보드게임 판)
    edge = np.minimum.reduce([xx, GW - 1 - xx, zz, GD - 1 - zz])
    rim_m = smoothstep(RIM + 6, RIM - 6, edge)
    rim_h = 46.0 + 4.0 * smoothstep(RIM - 18, RIM - 26, edge)
    h = h * (1 - rim_m) + rim_h * rim_m
    rim_col = np.array([18, 74, 78], f32) / 255
    inlay = np.exp(-((edge - (RIM - 22)) / 3.0) ** 2)
    rc = rim_col[None, None, :] * (0.9 + 0.1 * fbm(GD, GW, 51, cells=(40, 8), amps=(0.5, 0.5))[..., None])
    rc = rc * (1 - inlay[..., None]) + np.array([0.86, 0.95, 0.9], f32) * inlay[..., None]
    alb = alb * (1 - rim_m[..., None]) + rc * rim_m[..., None]
    spec = np.maximum(spec, rim_m * 0.55)
    mat[rim_m > 0.5] = 4
    # 테두리 안쪽으로 모래가 살짝 쌓인 느낌
    h += smoothstep(RIM + 60, RIM + 4, edge) * 8 * (1 - rim_m)

    return h, alb, spec, mat, (pts, ids, links), (xx, zz)


def carve_tiles(h, alb, spec, mat, graph, coords):
    pts, ids, links = graph
    xx, zz = coords
    stone_noise = fbm(GD, GW, 61, cells=(60, 20, 6), amps=(0.5, 0.3, 0.2))
    vein_warp = fbm(GD, GW, 62, cells=(120, 40), amps=(0.7, 0.3))
    font_big = ImageFont.truetype(FONT, 96)

    def text_mask(text, size_px):
        f = ImageFont.truetype(FONT, size_px)
        tw = int(ImageDraw.Draw(Image.new("L", (1, 1))).textlength(text, font=f))
        im = Image.new("L", (tw + 40, size_px + 40), 0)
        ImageDraw.Draw(im).text((20, 10), text, font=f, fill=255)
        return np.asarray(im.filter(ImageFilter.GaussianBlur(1.6)), f32) / 255

    def emblem_mask(kind, n):
        """칸 가운데 새김 무늬 (n x n)."""
        im = Image.new("L", (n * 4, n * 4), 0)
        d = ImageDraw.Draw(im)
        c = n * 2
        if kind == "junction":
            # 네 방향 화살표 (갈림길)
            for a in range(4):
                ang = a * math.pi / 2
                tip = (c + math.cos(ang) * n * 1.45, c + math.sin(ang) * n * 1.45)
                l = (c + math.cos(ang + 0.35) * n * 0.95, c + math.sin(ang + 0.35) * n * 0.95)
                r = (c + math.cos(ang - 0.35) * n * 0.95, c + math.sin(ang - 0.35) * n * 0.95)
                d.polygon([tip, l, r], fill=255)
            d.ellipse([c - n * 0.42, c - n * 0.42, c + n * 0.42, c + n * 0.42], outline=255, width=int(n * 0.16))
        else:
            # 조개 (부채꼴 + 골)
            r = n * 1.35
            d.pieslice([c - r, c - r * 0.95, c + r, c + r * 1.05], 200, 340, fill=255)
            for k in range(6):
                a = math.radians(205 + k * 26)
                d.line([(c, c + r * 0.05), (c + math.cos(a) * r, c + r * 0.05 + math.sin(a) * r)], fill=0, width=int(n * 0.1))
            d.rectangle([c - n * 0.32, c + n * 0.0, c + n * 0.32, c + n * 0.36], fill=255)
        im = im.resize((n, n), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8))
        return np.asarray(im, f32) / 255

    def place(cx, cz, size, height, kind, label=None):
        half = size / 2
        bevel = 9.0
        pad = 12
        z0, z1 = int(cz - half - pad), int(cz + half + pad)
        x0, x1 = int(cx - half - pad), int(cx + half + pad)
        sl = (slice(z0, z1), slice(x0, x1))
        lx = xx[sl] - cx
        lz = zz[sl] - cz
        # 둥근 모서리 네모 거리
        r = 10.0
        qx = np.abs(lx) - (half - r)
        qz = np.abs(lz) - (half - r)
        d = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qz, 0) ** 2) + np.minimum(np.maximum(qx, qz), 0) - r
        body = smoothstep(0, -bevel, d)                 # 모서리 둥글게 깎임
        top = height * (body ** 0.6)
        # 가장자리 안쪽 홈 (테두리)
        groove = np.exp(-((d + 16.0) / 2.6) ** 2)
        top -= groove * 2.6
        # 테두리 띠는 살짝 높게
        band = smoothstep(-16, -13, d) * smoothstep(-2, -6, d)
        top += band * 1.2
        # 새김 무늬
        inner = np.zeros_like(top)
        inlay_m = np.zeros_like(top)
        if kind in ("space", "junction"):
            n = int(size * 0.5)
            em = emblem_mask(kind, n)
            ez0 = int(cz - n / 2) - z0
            ex0 = int(cx - n / 2) - x0
            inner[ez0:ez0 + n, ex0:ex0 + n] = em
            inlay_m = inner
            top -= inner * 3.0
        elif kind == "start":
            # 모자이크 격자 + START 글씨
            inner_d = -d - 40
            mos = (inner_d > 0).astype(f32)
            g = 36
            mx = ((lx + 1000) % g) / g
            mz = ((lz + 1000) % g) / g
            line = np.maximum(np.exp(-((mx - 0.5) / 0.04) ** 2), np.exp(-((mz - 0.5) / 0.04) ** 2))
            top -= line * mos * 1.5
            tm = text_mask(label, 92)
            th, tw = tm.shape
            tz0 = int(cz - th / 2) - z0
            tx0 = int(cx - tw / 2) - x0
            tm_full = np.zeros_like(top)
            tm_full[tz0:tz0 + th, tx0:tx0 + tw] = tm
            # 글씨 뒤 원판
            disk = smoothstep(150, 140, np.sqrt(lx ** 2 + (lz * 1.0) ** 2))
            top -= disk * 0.0
            inlay_m = np.maximum(tm_full, np.exp(-((np.sqrt(lx ** 2 + lz ** 2) - 150) / 4.0) ** 2) * 0.9)
            top -= tm_full * 3.5
            groove2 = np.exp(-((d + 40.0) / 2.6) ** 2)
            top -= groove2 * 2.0
        # 바닥에 얹기 (주변 모래보다 위로)
        base = np.median(h[sl])
        new_h = base + top
        m = body > 0.001
        h[sl] = np.where(m, np.maximum(h[sl] * (1 - body) + new_h * body, h[sl]), h[sl])
        # 재질 색
        sn = stone_noise[sl]
        vw = vein_warp[sl]
        veins = np.abs(np.sin((lx * 0.03 + lz * 0.017) + vw * 10.0)) ** 30
        if kind == "start":
            base_c = np.array([240, 242, 234], f32) / 255
        elif kind == "junction":
            base_c = np.array([226, 238, 232], f32) / 255
        else:
            base_c = np.array([232, 234, 224], f32) / 255
        col = base_c * (0.88 + 0.14 * sn[..., None]) - veins[..., None] * 0.07
        # 테두리 띠는 청록 유리 상감
        col = col * (1 - band[..., None] * 0.8) + np.array([0.25, 0.68, 0.64], f32) * band[..., None] * 0.8
        # 모서리 쪽은 살짝 닳고 이끼·모래
        wear = smoothstep(-22, -2, d)
        col = col * (1 - wear[..., None] * 0.18) + np.array([0.55, 0.6, 0.45], f32) * wear[..., None] * 0.12
        col -= groove[..., None] * 0.25
        # 상감 (진주빛 / 금빛)
        inlay_col = np.array([0.95, 0.76, 0.36], f32) if kind != "space" else np.array([0.2, 0.62, 0.6], f32)
        col = col * (1 - inlay_m[..., None]) + inlay_col * inlay_m[..., None]
        alb[sl] = alb[sl] * (1 - body[..., None]) + col * body[..., None]
        spec[sl] = np.maximum(spec[sl], body * (0.35 + 0.5 * inlay_m))
        mat[sl][body > 0.5] = 2

    tops = {}
    for (i, j), k in ids.items():
        x, z = gpos(i, j)
        if (i, j) == (0, 0):
            place(x, z, START_SIZE, START_H, "start", "START")
            tops[k] = START_H
        else:
            kind = "junction" if len(links[k]) > 2 else "space"
            place(x, z, TILE, TILE_H, kind)
            tops[k] = TILE_H
    return tops


def add_rocks(h, alb, spec, mat, coords, keep_out):
    xx, zz = coords
    rock_noise = fbm(GD, GW, 71, cells=(30, 10, 4), amps=(0.5, 0.3, 0.2))
    placed = []
    regions = [((700, 700), 40), ((3200, 650), 26), ((650, 2650), 18), ((3250, 2650), 22), ((1920, 400), 10), ((1920, 2900), 10)]
    for (rx, rz), n in regions:
        for _ in range(n):
            for _t in range(30):
                x = rx + rng.normal(0, 380)
                z = rz + rng.normal(0, 300)
                r = rng.uniform(26, 90) if rng.random() < 0.8 else rng.uniform(100, 170)
                if not (RIM + r + 30 < x < GW - RIM - r - 30 and RIM + r + 30 < z < GD - RIM - r - 30):
                    continue
                if any(abs(x - kx) < kw + r + 40 and abs(z - kz) < kd + r + 40 for kx, kz, kw, kd in keep_out):
                    continue
                if any((x - px) ** 2 + (z - pz) ** 2 < (r + pr) ** 2 * 0.5 for px, pz, pr in placed):
                    continue
                placed.append((x, z, r))
                break
    for x, z, r in placed:
        s = int(r * 1.6)
        sl = (slice(int(z - s), int(z + s)), slice(int(x - s), int(x + s)))
        lx = (xx[sl] - x) / r
        lz = (zz[sl] - z) / (r * rng.uniform(0.75, 1.0))
        rn = rock_noise[sl]
        d2 = lx ** 2 + lz ** 2 + (rn - 0.5) * 0.28
        dome = np.sqrt(np.clip(1 - d2, 0, 1))
        hh = dome * r * rng.uniform(0.75, 1.05) + dome * rn * r * 0.22
        m = hh > 0.5
        h[sl] = np.where(m, np.maximum(h[sl], h[sl] * 0.2 + hh + 2), h[sl])
        base = np.array(rng.choice([[120, 120, 112], [132, 126, 114], [108, 114, 112]]), f32) / 255
        col = base * (0.75 + 0.4 * rn[..., None])
        moss = smoothstep(0.7, 0.95, dome) * smoothstep(0.55, 0.75, rn)
        col = col * (1 - moss[..., None] * 0.4) + np.array([0.32, 0.48, 0.34], f32) * moss[..., None] * 0.4
        a = smoothstep(0.0, 0.08, dome)
        alb[sl] = alb[sl] * (1 - a[..., None]) + col * a[..., None]
        spec[sl] = np.where(m, 0.08, spec[sl])
        mat[sl][m] = 3
    return placed


def add_vents(h, alb, coords, centers):
    xx, zz = coords
    fbm_cache = fbm(GD, GW, 88, cells=(24, 8), amps=(0.6, 0.4))
    for x, z in centers:
        r = rng.uniform(46, 64)
        s = int(r * 2.4)
        sl = (slice(int(z - s), int(z + s)), slice(int(x - s), int(x + s)))
        d = np.sqrt((xx[sl] - x) ** 2 + (zz[sl] - z) ** 2) / r
        cone = np.clip(1 - d / 2.2, 0, 1) ** 1.2 * 70
        crater = np.exp(-(d / 0.35) ** 2) * 30
        h[sl] = np.maximum(h[sl], h[sl] + cone - crater)
        col = np.array([0.58, 0.56, 0.5], f32) * (0.8 + 0.4 * fbm_cache[sl][..., None]) * (1 - np.exp(-(d / 0.38) ** 2)[..., None] * 0.85)
        a = smoothstep(2.2, 1.2, d)
        alb[sl] = alb[sl] * (1 - a[..., None]) + col * a[..., None]


def add_small(h, alb, coords, keep_out):
    """불가사리·조개·성게 (작은 것들)."""
    xx, zz = coords
    items = []
    for _ in range(140):
        x = rng.uniform(RIM + 60, GW - RIM - 60)
        z = rng.uniform(RIM + 60, GD - RIM - 60)
        if any(abs(x - kx) < kw + 30 and abs(z - kz) < kd + 30 for kx, kz, kw, kd in keep_out):
            continue
        kind = rng.choice(["star", "shell", "shell", "urchin"])
        items.append((x, z, kind))
        s = 40
        sl = (slice(int(z - s), int(z + s)), slice(int(x - s), int(x + s)))
        lx, lz = xx[sl] - x, zz[sl] - z
        rr = np.sqrt(lx ** 2 + lz ** 2)
        ang = np.arctan2(lz, lx) + rng.uniform(0, 6.28)
        if kind == "star":
            R = rng.uniform(16, 26)
            arm = R * (0.45 + 0.55 * np.abs(np.cos(ang * 2.5)) ** 3)
            m = smoothstep(arm, arm - 3, rr)
            h[sl] += m * 4.0 * (1 - rr / (R + 1)).clip(0, 1)
            col = np.array(rng.choice([[0.93, 0.5, 0.32], [0.96, 0.72, 0.36], [0.8, 0.3, 0.35]]), f32)
            dots = (np.sin(lx * 1.4) * np.sin(lz * 1.4) > 0.6).astype(f32) * 0.15
            alb[sl] = alb[sl] * (1 - m[..., None]) + (col + dots[..., None]) * m[..., None]
        elif kind == "shell":
            R = rng.uniform(9, 16)
            m = smoothstep(R, R - 2, rr) * (np.sin(ang) > -0.2)
            h[sl] += m * 3.5 * np.sqrt(np.clip(1 - rr / R, 0, 1))
            ridges = 0.85 + 0.15 * np.cos(ang * 9)
            col = np.array(rng.choice([[0.97, 0.9, 0.84], [0.95, 0.8, 0.75], [0.9, 0.86, 0.95]]), f32) * ridges[..., None]
            alb[sl] = alb[sl] * (1 - m[..., None]) + col * m[..., None]
        else:
            R = rng.uniform(8, 13)
            spikes = 0.6 + 0.4 * np.abs(np.sin(ang * 11))
            m = smoothstep(R * 1.6 * spikes, R * 1.6 * spikes - 2, rr)
            h[sl] += m * 7 * np.sqrt(np.clip(1 - rr / (R * 1.6), 0, 1))
            alb[sl] = alb[sl] * (1 - m[..., None]) + np.array([0.2, 0.12, 0.25], f32) * m[..., None]
    return items


# ── 빛 ───────────────────────────────────────────────────────
def shade(h, alb, spec, mat):
    print("  normals")
    hs = gaussian_filter(h, 0.7)
    gx = np.gradient(hs, axis=1)
    gz = np.gradient(hs, axis=0)
    n = np.stack([-gx, np.ones_like(gx), -gz], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    ndl = n @ LIGHT
    diff = np.clip(ndl * 0.85 + 0.15, 0, 1)

    print("  shadows")
    # 빛 방향으로 높이를 따라가며 가려지는지 (부드럽게)
    lxz = np.array([LIGHT[0], LIGHT[2]], f32)
    lxz_len = np.linalg.norm(lxz)
    dirx, dirz = lxz / lxz_len
    tan_e = LIGHT[1] / lxz_len
    sh = np.ones_like(h)
    for k in range(1, 70):
        dist = k * 3.0
        ox, oz = dirx * dist, dirz * dist
        hx = _shift(hs, ox, oz)
        occ = (hx - hs - dist * tan_e)
        sh = np.minimum(sh, np.clip(1 - occ / (4.0 + dist * 0.06), 0, 1))
    sh = gaussian_filter(sh, 1.2)

    print("  ambient occlusion")
    ao = np.ones_like(h)
    for s, w in ((3, 0.5), (10, 0.35), (30, 0.25)):
        blur = gaussian_filter(hs, s)
        ao -= np.clip((blur - hs) / (s * 1.6), 0, 1) * w
    ao = np.clip(ao, 0.25, 1)

    print("  specular / caustics")
    hv = LIGHT + VIEW
    hv /= np.linalg.norm(hv)
    sp = np.clip(n @ hv, 0, 1) ** 40 * spec * 1.4
    zz, xx = np.mgrid[0:GD, 0:GW].astype(f32)
    p1 = xx / 180.0
    p2 = zz / 180.0
    ca = np.sin(p1 * 3.1 + np.sin(p2 * 2.3) * 1.7) * np.sin(p2 * 3.7 + np.sin(p1 * 1.9) * 1.5)
    ca = np.clip(ca, 0, 1) ** 2.5
    cb = np.sin(p1 * 5.3 + 1.1 + np.sin(p2 * 4.1) * 1.4) * np.sin(p2 * 5.9 + np.sin(p1 * 3.3) * 1.3)
    cb = np.clip(cb, 0, 1) ** 2.5
    caus = (ca + 0.6 * cb) * sh * np.clip(n[..., 1], 0, 1)

    sun = np.array([1.0, 0.97, 0.88], f32)
    amb_top = np.array([0.3, 0.5, 0.52], f32)
    amb_bot = np.array([0.1, 0.2, 0.22], f32)
    amb = amb_bot + (amb_top - amb_bot) * (n[..., 1:2] * 0.5 + 0.5)
    light = sun * (diff * sh)[..., None] * 1.12 + amb * ao[..., None] * 0.6
    col = alb * light + sp[..., None] * sh[..., None] * np.array([1.0, 1.0, 0.95], f32) + caus[..., None] * np.array([0.16, 0.26, 0.22], f32)
    col *= ao[..., None] ** 0.5
    return col


def _shift(a, ox, oz):
    """a 를 (ox, oz) 만큼 옮겨 읽기 (정수 + 선형보간)."""
    ix, iz = int(math.floor(ox)), int(math.floor(oz))
    fx, fz = ox - ix, oz - iz

    def roll(arr, dx, dz):
        out = np.empty_like(arr)
        # dz
        if dz >= 0:
            out[:GD - dz] = arr[dz:]
            out[GD - dz:] = arr[-1:]
        else:
            out[-dz:] = arr[:GD + dz]
            out[:-dz] = arr[:1]
        res = np.empty_like(out)
        if dx >= 0:
            res[:, :GW - dx] = out[:, dx:]
            res[:, GW - dx:] = out[:, -1:]
        else:
            res[:, -dx:] = out[:, :GW + dx]
            res[:, :-dx] = out[:, :1]
        return res
    a00 = roll(a, ix, iz)
    a10 = roll(a, ix + 1, iz)
    a01 = roll(a, ix, iz + 1)
    a11 = roll(a, ix + 1, iz + 1)
    return (a00 * (1 - fx) + a10 * fx) * (1 - fz) + (a01 * (1 - fx) + a11 * fx) * fz


# ── 비스듬히 투영 ────────────────────────────────────────────
def screen_y(z, hgt):
    return TOP_PAD + z * KZ - hgt * KH


def project(col, h):
    print("  projecting")
    img = np.zeros((SH, GW, 3), f32)
    ybuf = np.full(GW, SH, np.int32)
    xs = np.arange(GW)
    for z in range(GD - 1, -1, -1):          # 앞(아래)부터 뒤로
        sy = screen_y(z, h[z])
        y = np.floor(sy).astype(np.int32)
        for k in range(5):
            yy = y + k
            m = yy < ybuf
            m &= yy >= 0
            if not m.any():
                break
            img[yy[m], xs[m]] = col[z, m]
        np.minimum(ybuf, np.maximum(y, 0), out=ybuf)
    # 위쪽 빈 곳 (판 너머) = 물 색
    empty = (img.sum(axis=2) == 0)
    img[empty] = np.array([0.04, 0.2, 0.2], f32)
    return img


def water_grade(img):
    """물속 느낌: 멀수록(위쪽) 물빛, 전체 청록 톤."""
    yy = np.linspace(0, 1, SH, dtype=f32)[:, None, None]
    fog = np.clip(0.3 - yy * 0.34, 0, 1)
    water = np.array([0.1, 0.45, 0.42], f32)
    img = img * (1 - fog) + water * fog
    img = img * np.array([0.72, 0.92, 0.9], f32) + np.array([0.0, 0.02, 0.025], f32)
    img = np.clip((img - 0.45) * 1.15 + 0.45, 0, 1)
    # 화면 가장자리 살짝 어둡게
    xx = np.linspace(-1, 1, GW, dtype=f32)[None, :, None]
    img *= (1 - 0.16 * xx ** 2)
    yv = np.linspace(-1, 1, SH, dtype=f32)[:, None, None]
    img *= (1 - 0.12 * yv ** 2)
    return img


# ── 산호·해면 (작은 3D 모형을 레이마칭) ──────────────────────
def sd_capsule(p, a, b, r):
    pa = p - a
    ba = b - a
    t = np.clip((pa @ ba) / (ba @ ba), 0, 1)
    return np.linalg.norm(pa - t[..., None] * ba, axis=-1) - r


def coral_sdf_parts(seed, kind):
    r = np.random.default_rng(seed)
    parts = []
    if kind == "branch":
        def grow(p, d, ln, rad, depth):
            q = p + d * ln
            parts.append((p, q, rad))
            if depth > 0:
                for s in (-1, 1):
                    nd = d + np.array([s * r.uniform(0.35, 0.7), r.uniform(0.1, 0.3), r.uniform(-0.4, 0.4)], f32)
                    nd /= np.linalg.norm(nd)
                    grow(q, nd, ln * 0.74, rad * 0.75, depth - 1)
        for k in range(3):
            d0 = np.array([r.uniform(-0.3, 0.3), 1.0, r.uniform(-0.3, 0.3)], f32)
            grow(np.array([r.uniform(-0.15, 0.15), 0, r.uniform(-0.15, 0.15)], f32), d0 / np.linalg.norm(d0), 0.42, 0.075, 3)
    else:  # tube sponge
        for k in range(r.integers(3, 6)):
            base = np.array([r.uniform(-0.3, 0.3), 0, r.uniform(-0.3, 0.3)], f32)
            top = base + np.array([r.uniform(-0.1, 0.1), r.uniform(0.6, 1.2), r.uniform(-0.1, 0.1)], f32)
            parts.append((base, top, r.uniform(0.09, 0.14)))
    return parts


def render_sprite(kind, seed, color, px=260):
    px = int(px * 1.5)
    parts = coral_sdf_parts(seed, kind)
    # 정사영 카메라: 50도 위에서
    n = px * 2
    ext = 1.25
    us = np.linspace(-ext, ext, n, dtype=f32)
    vs = np.linspace(ext * 1.15, -ext * 0.45, n, dtype=f32)
    U_, V_ = np.meshgrid(us, vs)
    fwd = np.array([0, -math.sin(ELEV), -math.cos(ELEV)], f32)
    up = np.array([0, math.cos(ELEV), -math.sin(ELEV)], f32)
    right = np.array([1, 0, 0], f32)
    orig = (U_[..., None] * right + V_[..., None] * up) - fwd * 4.0
    orig = orig.reshape(-1, 3)
    t = np.zeros(len(orig), f32)
    hit = np.zeros(len(orig), bool)

    def sdf(p):
        d = np.full(len(p), 1e9, f32)
        for a, b, rad in parts:
            d = np.minimum(d, sd_capsule(p, a, b, rad))
        if kind == "tube":
            pass
        return d
    for _ in range(90):
        p = orig + fwd * t[:, None]
        d = sdf(p)
        hit |= d < 0.002
        t = np.where(hit, t, t + np.maximum(d, 0.004))
        if (t > 9).all():
            break
    p = orig + fwd * t[:, None]
    e = 0.004
    nx = sdf(p + [e, 0, 0]) - sdf(p - [e, 0, 0])
    ny = sdf(p + [0, e, 0]) - sdf(p - [0, e, 0])
    nz = sdf(p + [0, 0, e]) - sdf(p - [0, 0, e])
    nrm = np.stack([nx, ny, nz], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True) + 1e-9
    L3 = LIGHT
    diff = np.clip(nrm @ L3 * 0.8 + 0.2, 0, 1)
    ao = np.clip(0.4 + p[:, 1] * 0.6, 0.4, 1.0)
    col = np.array(color, f32) / 255
    tip = np.clip(p[:, 1] - 0.5, 0, 1)
    c = col[None, :] * (0.35 + 0.8 * diff[:, None]) * ao[:, None] + tip[:, None] * 0.18
    if kind == "tube":
        # 구멍 (위쪽 끝 안쪽 어둡게)
        for a, b, rad in parts:
            dtop = np.linalg.norm(p - b, axis=1)
            c *= np.where(dtop < rad * 0.75, 0.35, 1.0)[:, None]
    img = np.zeros((len(orig), 4), f32)
    img[:, :3] = np.clip(c, 0, 1) * 255
    img[:, 3] = hit * 255
    im = Image.fromarray(img.reshape(n, n, 4).astype(np.uint8), "RGBA").resize((px, px), Image.LANCZOS)
    # 바닥 기준점: 원점(0,0,0)의 화면 위치
    base_v = (0 - (-ext * 0.45)) / (ext * 1.15 + ext * 0.45)
    return im, (px / 2, px * (1 - base_v))


# ── 조립 ─────────────────────────────────────────────────────
def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    print("ground")
    h, alb, spec, mat, graph, coords = build_ground()
    pts, ids, links = graph
    print("tiles")
    tops = carve_tiles(h, alb, spec, mat, graph, coords)
    # 길·칸 주변은 장식 금지 구역
    keep = []
    for (i, j) in pts:
        x, z = gpos(i, j)
        keep.append((x, z, 120, 120))
    keep.append((CX, CZ, 260, 260))
    vents = [(3000, 420), (3420, 520), (3220, 880), (2700, 640)]
    vents = [(x, z) for x, z in vents if not any(abs(x - kx) < kw + 70 and abs(z - kz) < kd + 70 for kx, kz, kw, kd in keep)]
    for x, z in vents:
        keep.append((x, z, 80, 80))
    print("rocks / vents / small")
    rocks = add_rocks(h, alb, spec, mat, coords, keep)
    for x, z, r in rocks:
        keep.append((x, z, r, r))
    add_vents(h, alb, coords, vents)
    add_small(h, alb, coords, keep)
    print("shade")
    col = shade(h, alb, spec, mat)
    img = project(col, h)
    img = water_grade(img)
    out = Image.fromarray(np.clip(img * 255, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    # 산호·해면 붙이기 (뒤에서 앞 순서)
    print("coral sprites")
    palette = [(255, 120, 110), (250, 160, 90), (190, 120, 230), (255, 110, 160), (240, 220, 120)]
    sprites = []
    for k in range(10):
        kind = "branch" if k % 3 != 2 else "tube"
        sprites.append(render_sprite(kind, 100 + k, palette[k % len(palette)], px=220 if kind == "branch" else 180))
    decor = []
    coral_regions = [((620, 560), 16), ((3300, 2700), 10), ((560, 2700), 6), ((1920, 2950), 6), ((1920, 330), 4), ((3500, 1600), 4), ((350, 1600), 4)]
    for (rx, rz), n in coral_regions:
        for _ in range(n):
            for _t in range(40):
                x = rx + rng.normal(0, 260)
                z = rz + rng.normal(0, 200)
                if not (RIM + 80 < x < GW - RIM - 80 and RIM + 140 < z < GD - RIM - 40):
                    continue
                if any(abs(x - kx) < kw + 60 and abs(z - kz) < kd + 60 for kx, kz, kw, kd in keep):
                    continue
                decor.append((x, z, rng.integers(len(sprites)), rng.uniform(0.7, 1.2)))
                keep.append((x, z, 50, 50))
                break
    for x, z, si, sc in sorted(decor, key=lambda t: t[1]):
        im, (bx, by) = sprites[si]
        if sc != 1.0:
            im = im.resize((int(im.width * sc), int(im.height * sc)), Image.LANCZOS)
            bx, by = bx * sc, by * sc
        gh = h[int(z), int(x)]
        sx, sy = x, screen_y(z, gh)
        # 그림자
        shl = Image.new("RGBA", (int(im.width * 1.2), int(im.height * 0.5)), (0, 0, 0, 0))
        ImageDraw.Draw(shl).ellipse([shl.width * 0.25, shl.height * 0.35, shl.width * 0.95, shl.height * 0.75], fill=(0, 20, 18, 120))
        shl = shl.filter(ImageFilter.GaussianBlur(8))
        out.alpha_composite(shl, (int(sx - shl.width * 0.45), int(sy - shl.height * 0.55)))
        out.alpha_composite(im, (int(sx - bx), int(sy - by)))

    out.save(os.path.join(OUT, "tutorial_map.png"))
    out.resize((1200, int(1200 * SH / SW)), Image.LANCZOS).save(os.path.join(HERE, "out", "tutorial_map_small.png"))

    # JSON (화면 = 지도 그림 좌표)
    spaces = []
    for (i, j), k in ids.items():
        x, z = gpos(i, j)
        kind = "start" if (i, j) == (0, 0) else ("junction" if len(links[k]) > 2 else "space")
        sy = screen_y(z, h[int(z), int(x)])
        spaces.append({"id": k, "x": round(x, 1), "y": round(float(sy), 1), "kind": kind, "links": links[k],
                       "grid": [i, j]})
    start = ids[(0, 0)]
    kelp = []
    for _ in range(80):
        x = 600 + rng.normal(0, 380)
        z = 2600 + rng.normal(0, 280)
        if RIM + 100 < x < GW - RIM - 60 and RIM + 200 < z < GD - RIM - 40 and \
                not any(abs(x - kx) < kw + 50 and abs(z - kz) < kd + 50 for kx, kz, kw, kd in keep):
            kelp.append([round(x), round(float(screen_y(z, h[int(z), int(x)]))), round(float(rng.uniform(260, 520))),
                         round(float(rng.uniform(0, 6.28)), 2)])
    for _ in range(30):
        x = rng.uniform(RIM + 100, GW - RIM - 100)
        z = rng.uniform(RIM + 300, GD - RIM - 60)
        if not any(abs(x - kx) < kw + 60 and abs(z - kz) < kd + 60 for kx, kz, kw, kd in keep):
            kelp.append([round(x), round(float(screen_y(z, h[int(z), int(x)]))), round(float(rng.uniform(180, 340))),
                         round(float(rng.uniform(0, 6.28)), 2)])
    data = {
        "size": [SW, SH],
        "start": start,
        "spaces": spaces,
        "kelp": kelp,
        "vents": [[round(x), round(float(screen_y(z, h[int(z), int(x)])) - 10)] for x, z in vents],
    }
    with open(os.path.join(OUT, "tutorial_world.json"), "w") as f:
        json.dump(data, f)
    print("spaces", len(spaces), "size", SW, SH)


if __name__ == "__main__":
    main()
