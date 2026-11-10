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

맵 구조 (Wii 파티 보드처럼):
  - 구불구불한 큰 고리 길이 산호 정원 → 난파 협곡 → 화산 분수 → 진주 석호 → 다시마 숲을 한 바퀴 돎
  - 가운데 START 광장(부서진 기둥들)에서 지름길 3개가 고리로 이어짐
  - 그중 하나는 깊은 협곡 위 돌다리를 건넘
  - 칸은 네모, 길 방향을 따라 돌아가 있고, 색깔별 종류(파랑·빨강·초록 ?·금별·갈림길)
골인 지점 없음.
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
GW, GD = 2400, 2100                # 바닥 크기 (가로, 깊이) — 튜토리얼이라 작게
TOP_PAD = 190                      # 높은 것들이 위로 튀어나올 여유
SW = GW
SH = int(GD * KZ + TOP_PAD + 10)   # 화면(지도 그림) 크기

SPACING = 212                      # 칸 사이 거리
TILE = 150                         # 칸 한 변
START_SIZE = 300
TILE_H = 22.0
START_H = 30.0

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


# ── 맵 구조 ──────────────────────────────────────────────────
F = 0.6                            # 큰 판 설계를 이만큼 줄여서 씀
OLD_C, NEW_C = (1920, 1640), (1200, 1080)


def P(x, z):
    return (round(NEW_C[0] + (x - OLD_C[0]) * F), round(NEW_C[1] + (z - OLD_C[1]) * F))


S = P(1920, 1640)
JN = {
    "S": S,
    "A": P(1180, 1080),   # 산호 정원 갈림길
    "B": P(2700, 1000),   # 난파 협곡 갈림길
    "C": P(2760, 2300),   # 진주 석호 갈림길
    "D": P(1120, 2260),   # 다시마 숲 (꺾임)
}
# (시작, 끝, 지나가는 점들)
EDGES = [
    ("A", "B", [P(1420, 700), P(1800, 860), P(2180, 560), P(2480, 720)]),       # 위: 산호 언덕 물결
    ("B", "C", [P(3080, 1080), P(3330, 1480), P(3170, 1880), P(3260, 2160)]),    # 오른쪽: 화산 옆 S자
    ("C", "D", [P(2500, 2700), P(2100, 2560), P(1700, 2800), P(1380, 2620)]),    # 아래: 석호 물결
    ("D", "A", [P(820, 2080), P(600, 1700), P(820, 1420)]),                    # 왼쪽: 다시마 숲
    ("S", "A", [P(1640, 1520), P(1420, 1300)]),                               # 지름길
    ("S", "B", [P(2180, 1380), P(2440, 1160)]),                               # 지름길
    ("S", "C", [P(2200, 1880), P(2500, 2050)]),                               # 지름길 (협곡 다리)
]
TRENCH = [P(2740, 1460), P(2620, 1650), P(2490, 1850), P(2370, 2040), P(2270, 2220)]
VOLCANO = P(3420, 560)
CLAM = P(1330, 2020)


def catmull(pts, n_per=60):
    pts = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = (np.array(p, float) for p in pts[i - 1:i + 3])
        for t in np.linspace(0, 1, n_per, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(np.array(pts[-2], float))
    return np.array(out)


def build_graph():
    nodes = []
    index = {}

    def node_at(p, ang, kind="space"):
        key = (round(p[0]), round(p[1]))
        if key in index:
            return index[key]
        nid = len(nodes)
        nodes.append({"id": nid, "x": float(p[0]), "z": float(p[1]), "ang": float(ang), "links": set(), "kind": kind})
        index[key] = nid
        return nid

    node_at(S, 0.0, "start")
    curves = []
    for a, b, mid in EDGES:
        c = catmull([JN[a]] + mid + [JN[b]])
        curves.append(c)
        seg = np.linalg.norm(np.diff(c, axis=0), axis=1)
        cum = np.concatenate([[0], np.cumsum(seg)])
        total = cum[-1]
        n = max(1, int(round(total / SPACING)))
        ids = []
        for k in range(n + 1):
            d = total * k / n
            x = np.interp(d, cum, c[:, 0])
            z = np.interp(d, cum, c[:, 1])
            i2 = min(len(c) - 2, int(np.searchsorted(cum, d)))
            tx, tz = c[i2 + 1] - c[max(0, i2 - 1)]
            ang = math.atan2(tz, tx)
            if k == 0:
                p, ang = JN[a], 0.0
            elif k == n:
                p, ang = JN[b], 0.0
            else:
                p = (x, z)
                if a == "S" and math.dist(p, S) < 230:
                    continue
            ids.append(node_at(p, ang))
        for u, v in zip(ids, ids[1:]):
            nodes[u]["links"].add(v)
            nodes[v]["links"].add(u)
    for nd in nodes:
        if nd["kind"] != "start" and len(nd["links"]) > 2:
            nd["kind"] = "junction"
    # 칸 종류 (색). 규칙은 나중에 — 지금은 보기 좋게 섞어 둠
    pattern = ["blue", "blue", "red", "blue", "event", "blue", "blue", "red", "blue", "star"]
    k = 0
    for nd in nodes:
        if nd["kind"] == "space":
            nd["kind"] = pattern[k % len(pattern)]
            k += 1
    return nodes, curves


# ── 높이 지도 + 재질 ─────────────────────────────────────────
def build_ground(curves):
    zz, xx = np.mgrid[0:GD, 0:GW].astype(f32)
    h = np.zeros((GD, GW), f32)
    alb = np.zeros((GD, GW, 3), f32)
    spec = np.zeros((GD, GW), f32)
    mat = np.zeros((GD, GW), np.uint8)

    dunes = fbm(GD, GW, 3) * 46.0
    warp = fbm(GD, GW, 9, cells=(300, 120), amps=(0.7, 0.3))
    rip = np.sin((zz * 0.95 + xx * 0.32) * 0.085 + warp * 9.0)
    rip = np.sign(rip) * np.abs(rip) ** 0.8
    h += dunes + rip * 2.4 + fbm(GD, GW, 21, cells=(8, 4), amps=(0.6, 0.4)) * 1.2
    sand_var = fbm(GD, GW, 31)
    sand = np.array([206, 192, 150], f32) / 255
    sand2 = np.array([160, 168, 132], f32) / 255
    alb[:] = sand * (1 - sand_var[..., None] * 0.6) + sand2 * (sand_var[..., None] * 0.6)
    alb *= (0.92 + 0.08 * (rip[..., None] * 0.5 + 0.5))
    grit = (value_noise(GD, GW, 3, 77) > 0.86).astype(f32) * fbm(GD, GW, 78, cells=(64,), amps=(1.0,))
    alb += grit[..., None] * np.array([0.12, 0.1, 0.08], f32)
    h += grit * 1.0

    # 협곡 (깊은 골짜기)
    tm = Image.new("L", (GW, GD), 0)
    td = ImageDraw.Draw(tm)
    tc = catmull(TRENCH, 30)
    td.line([tuple(p) for p in tc], fill=255, width=150, joint="curve")
    for p in (tc[0], tc[-1]):
        td.ellipse([p[0] - 75, p[1] - 75, p[0] + 75, p[1] + 75], fill=255)
    trench = np.asarray(tm.filter(ImageFilter.GaussianBlur(26)), f32) / 255
    rough = fbm(GD, GW, 91, cells=(40, 14), amps=(0.6, 0.4))
    trench = smoothstep(0.25, 0.75, trench + (rough - 0.5) * 0.35)
    h -= trench * 170.0
    wall = np.clip(trench * (1 - trench) * 4, 0, 1)
    rock_c = np.array([0.42, 0.44, 0.42], f32) * (0.8 + 0.4 * rough[..., None])
    alb = alb * (1 - wall[..., None]) + rock_c * wall[..., None]
    alb *= (1 - trench[..., None] * 0.45)

    # 화산 분수 (큰 원뿔 + 분화구)
    vx, vz = VOLCANO
    d = np.sqrt((xx - vx) ** 2 + ((zz - vz) * 1.15) ** 2)
    cone = np.clip(1 - d / 200, 0, 1) ** 1.25 * 140
    crater = np.exp(-(d / 48) ** 2) * 90
    h += cone - crater
    vrock = np.array([0.36, 0.33, 0.32], f32) * (0.75 + 0.5 * rough[..., None])
    vm = smoothstep(200, 145, d)
    alb = alb * (1 - vm[..., None]) + vrock * vm[..., None]
    glow = np.exp(-(d / 38) ** 2)
    alb = alb * (1 - glow[..., None]) + np.array([1.0, 0.55, 0.25], f32) * glow[..., None]   # 안쪽이 따뜻하게

    # 길 (구불구불한 자갈길) — 그림으로 그려서 마스크로
    pm = Image.new("L", (GW, GD), 0)
    pd = ImageDraw.Draw(pm)
    for c in curves:
        pd.line([tuple(p) for p in c], fill=255, width=78, joint="curve")
    path_mask = np.asarray(pm.filter(ImageFilter.GaussianBlur(4)), f32) / 255
    cell = 22
    jx = value_noise(GD, GW, cell, 41) * 8
    jz = value_noise(GD, GW, cell, 42) * 8
    fx = ((xx + jx) % cell) / cell
    fz = ((zz + jz) % cell) / cell
    cob = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fz, 1 - fz))
    cob_h = smoothstep(0.0, 0.18, cob) * 3.0
    cob_shade = 0.85 + 0.3 * value_noise(GD, GW, cell, 43)
    ground_ref = gaussian_filter(dunes, 30)
    deck = ground_ref + 8.0 + cob_h
    h = h * (1 - path_mask) + np.maximum(h, deck) * path_mask
    # 다리: 협곡 위의 길은 난간 기둥
    over = path_mask * trench
    posts = (np.sin(xx * 0.09) * np.sin(zz * 0.09) > 0.92).astype(f32)
    edge_band = smoothstep(0.35, 0.6, path_mask) * smoothstep(0.95, 0.75, path_mask)
    h += posts * edge_band * (over > 0.3) * 26.0
    stone_col = np.array([150, 150, 140], f32) / 255
    pc = stone_col * cob_shade[..., None] * (0.75 + 0.25 * smoothstep(0.0, 0.15, cob)[..., None])
    alb = alb * (1 - path_mask[..., None]) + pc * path_mask[..., None]
    mat[path_mask > 0.5] = 1

    # 판 테두리
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
    h += smoothstep(RIM + 60, RIM + 4, edge) * 8 * (1 - rim_m)

    busy = np.maximum.reduce([np.asarray(pm, f32) / 255, trench, vm, rim_m])
    return h, alb, spec, mat, (xx, zz), busy


TILE_STYLE = {
    "blue":  {"col": (70, 150, 230), "icon": "pearl", "ink": (232, 244, 255)},
    "red":   {"col": (226, 82, 78), "icon": "urchin", "ink": (255, 232, 226)},
    "event": {"col": (88, 196, 110), "icon": "?", "ink": (240, 255, 236)},
    "star":  {"col": (240, 190, 60), "icon": "star", "ink": (255, 250, 220)},
    "junction": {"col": (236, 238, 230), "icon": "arrows", "ink": (214, 160, 50)},
    "start": {"col": (240, 242, 234), "icon": "START", "ink": (214, 160, 50)},
}


def icon_mask(icon, n):
    im = Image.new("L", (n * 4, n * 4), 0)
    d = ImageDraw.Draw(im)
    c = n * 2
    R = n * 1.5
    if icon == "pearl":
        d.ellipse([c - R * 0.62, c - R * 0.62, c + R * 0.62, c + R * 0.62], fill=255)
        d.ellipse([c - R * 0.42, c - R * 0.42, c + R * 0.42, c + R * 0.42], fill=0)
        d.ellipse([c - R * 0.28, c - R * 0.28, c + R * 0.28, c + R * 0.28], fill=255)
    elif icon == "urchin":
        pts = []
        for k in range(24):
            a = k * math.pi / 12
            rr = R * (0.85 if k % 2 == 0 else 0.45)
            pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
        d.polygon(pts, fill=255)
    elif icon == "star":
        pts = []
        for k in range(10):
            a = -math.pi / 2 + k * math.pi / 5
            rr = R * (0.95 if k % 2 == 0 else 0.42)
            pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
        d.polygon(pts, fill=255)
    elif icon == "arrows":
        for a in range(4):
            ang = a * math.pi / 2
            tip = (c + math.cos(ang) * R, c + math.sin(ang) * R)
            l = (c + math.cos(ang + 0.38) * R * 0.62, c + math.sin(ang + 0.38) * R * 0.62)
            r = (c + math.cos(ang - 0.38) * R * 0.62, c + math.sin(ang - 0.38) * R * 0.62)
            d.polygon([tip, l, r], fill=255)
        d.ellipse([c - R * 0.28, c - R * 0.28, c + R * 0.28, c + R * 0.28], fill=255)
    else:
        f = ImageFont.truetype(FONT, int(n * (2.6 if len(icon) == 1 else 0.95)))
        tw = d.textlength(icon, font=f)
        asc, desc = f.getmetrics()
        d.text((c - tw / 2, c - (asc + desc) * 0.55), icon, font=f, fill=255)
    im = im.resize((n, n), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.7))
    return np.asarray(im, f32) / 255


def carve_tiles(h, alb, spec, mat, nodes, coords):
    xx, zz = coords
    stone_noise = fbm(GD, GW, 61, cells=(60, 20, 6), amps=(0.5, 0.3, 0.2))
    glaze_noise = fbm(GD, GW, 62, cells=(30, 10), amps=(0.6, 0.4))
    tops = {}
    for nd in nodes:
        kind = nd["kind"]
        style = TILE_STYLE[kind]
        size = START_SIZE if kind == "start" else (TILE + 14 if kind == "junction" else TILE)
        height = 30.0 if kind == "start" else TILE_H
        cx, cz, ang = nd["x"], nd["z"], nd["ang"]
        half = size / 2
        pad = int(half * 1.5 + 14)
        z0, x0 = int(cz - pad), int(cx - pad)
        sl = (slice(z0, z0 + 2 * pad), slice(x0, x0 + 2 * pad))
        dx = xx[sl] - cx
        dz = zz[sl] - cz
        ca, sa = math.cos(-ang), math.sin(-ang)
        lx = dx * ca - dz * sa
        lz = dx * sa + dz * ca
        r = 12.0
        qx = np.abs(lx) - (half - r)
        qz = np.abs(lz) - (half - r)
        d = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qz, 0) ** 2) + np.minimum(np.maximum(qx, qz), 0) - r
        bevel = 8.0
        body = smoothstep(0, -bevel, d)
        top = height * (body ** 0.55)
        # 유약 바른 위판 + 테두리 띠
        rim_band = smoothstep(-15, -12, d) * smoothstep(-1, -5, d)
        groove = np.exp(-((d + 17.0) / 2.4) ** 2)
        top += rim_band * 1.6 - groove * 2.4
        # 아이콘 (볼록하게 도드라짐)
        n = int(size * (0.62 if kind != "start" else 0.8))
        im = icon_mask(style["icon"], n)
        icon = np.zeros_like(top)
        # 아이콘도 칸 방향대로 돌림 → 회전한 좌표로 샘플
        u = np.clip((lx / n + 0.5) * (n - 1), 0, n - 1).astype(np.int32)
        v = np.clip((lz / n + 0.5) * (n - 1), 0, n - 1).astype(np.int32)
        inside_icon = (np.abs(lx) < n / 2) & (np.abs(lz) < n / 2)
        icon = np.where(inside_icon, im[v, u], 0.0)
        top += icon * 2.2
        base = float(np.median(h[sl][body > 0.5])) if (body > 0.5).any() else 0.0
        base = max(base, float(np.percentile(h[sl], 70)))
        new_h = base + top
        h[sl] = np.where(body > 0.001, np.maximum(h[sl] * (1 - body) + new_h * body, h[sl]), h[sl])
        # 색
        sn = stone_noise[sl]
        gz = glaze_noise[sl]
        col = np.array(style["col"], f32) / 255
        face = col * (0.9 + 0.16 * gz[..., None])
        # 가운데가 살짝 밝은 유약 느낌
        center_glow = np.exp(-((lx / (half * 0.9)) ** 2 + (lz / (half * 0.9)) ** 2))
        face = face + center_glow[..., None] * 0.08
        # 테두리 띠: 흰 돌
        band_col = np.array([0.93, 0.94, 0.9], f32) * (0.9 + 0.1 * sn[..., None])
        face = face * (1 - rim_band[..., None]) + band_col * rim_band[..., None]
        # 옆면: 돌 색
        side = smoothstep(-2, -bevel, d)
        stone = np.array([0.82, 0.83, 0.8], f32) * (0.85 + 0.2 * sn[..., None])
        face = stone * (1 - side[..., None]) + face * side[..., None]
        ink = np.array(style["ink"], f32) / 255
        face = face * (1 - icon[..., None]) + ink * icon[..., None]
        face -= groove[..., None] * 0.2
        alb[sl] = alb[sl] * (1 - body[..., None]) + face * body[..., None]
        spec[sl] = np.maximum(spec[sl], body * (0.7 if kind not in ("start",) else 0.45))
        mat[sl][body > 0.5] = 2
        tops[nd["id"]] = base + height
    return tops


def add_rocks(h, alb, spec, mat, coords, busy):
    xx, zz = coords
    rock_noise = fbm(GD, GW, 71, cells=(30, 10, 4), amps=(0.5, 0.3, 0.2))
    placed = []
    regions = [(P(560, 520), 7), (P(3300, 520), 5), (P(520, 2900), 5), (P(3400, 2900), 5), (P(1920, 2150), 2),
               (P(3560, 1050), 3), (P(1650, 1150), 2), (P(300, 1700), 3)]
    for (rx, rz), n in regions:
        for _ in range(n):
            for _t in range(40):
                x = rx + rng.normal(0, 180)
                z = rz + rng.normal(0, 150)
                r = rng.uniform(26, 80) if rng.random() < 0.8 else rng.uniform(90, 150)
                if not (RIM + r + 30 < x < GW - RIM - r - 30 and RIM + r + 30 < z < GD - RIM - r - 30):
                    continue
                zi, xi = int(z), int(x)
                rr = int(r) + 60
                if busy[max(0, zi - rr):zi + rr, max(0, xi - rr):xi + rr].max() > 0.05:
                    continue
                if any((x - px) ** 2 + (z - pz) ** 2 < (r + pr) ** 2 * 0.5 for px, pz, pr in placed):
                    continue
                placed.append((x, z, r))
                break
    for x, z, r in placed:
        sz = int(r * 1.6)
        sl = (slice(int(z - sz), int(z + sz)), slice(int(x - sz), int(x + sz)))
        lx = (xx[sl] - x) / r
        lz = (zz[sl] - z) / (r * rng.uniform(0.75, 1.0))
        rn = rock_noise[sl]
        d2 = lx ** 2 + lz ** 2 + (rn - 0.5) * 0.28
        dome = np.sqrt(np.clip(1 - d2, 0, 1))
        hh = dome * r * rng.uniform(0.75, 1.05) + dome * rn * r * 0.22
        m = hh > 0.5
        h[sl] = np.where(m, np.maximum(h[sl], h[sl] * 0.2 + hh + 2), h[sl])
        base = np.array(rng.choice([[128, 126, 116], [140, 132, 118], [116, 122, 118]]), f32) / 255
        col = base * (0.75 + 0.4 * rn[..., None])
        moss = smoothstep(0.7, 0.95, dome) * smoothstep(0.55, 0.75, rn)
        col = col * (1 - moss[..., None] * 0.4) + np.array([0.32, 0.5, 0.34], f32) * moss[..., None] * 0.4
        a = smoothstep(0.0, 0.08, dome)
        alb[sl] = alb[sl] * (1 - a[..., None]) + col * a[..., None]
        spec[sl] = np.where(m, 0.08, spec[sl])
        mat[sl][m] = 3
        busy[sl] = np.maximum(busy[sl], m.astype(f32))
    return placed


def add_small(h, alb, coords, busy):
    xx, zz = coords
    for _ in range(80):
        x = rng.uniform(RIM + 60, GW - RIM - 60)
        z = rng.uniform(RIM + 60, GD - RIM - 60)
        if busy[int(z), int(x)] > 0.05:
            continue
        kind = rng.choice(["star", "shell", "shell", "urchin"])
        sz = 40
        sl = (slice(int(z - sz), int(z + sz)), slice(int(x - sz), int(x + sz)))
        lx, lz = xx[sl] - x, zz[sl] - z
        rr = np.sqrt(lx ** 2 + lz ** 2)
        ang = np.arctan2(lz, lx) + rng.uniform(0, 6.28)
        if kind == "star":
            R = rng.uniform(16, 26)
            arm = R * (0.45 + 0.55 * np.abs(np.cos(ang * 2.5)) ** 3)
            m = smoothstep(arm, arm - 3, rr)
            h[sl] += m * 4.0 * (1 - rr / (R + 1)).clip(0, 1)
            col = np.array(rng.choice([[0.93, 0.5, 0.32], [0.96, 0.72, 0.36], [0.8, 0.3, 0.35]]), f32)
            alb[sl] = alb[sl] * (1 - m[..., None]) + col * m[..., None]
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
    for k in range(1, 46):
        dist = k * 4.5
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




def _ortho_raymarch(sdf_fn, color_fn, ext, px, steps=110):
    n = px * 2
    us = np.linspace(-ext, ext, n, dtype=f32)
    vs = np.linspace(ext * 1.15, -ext * 0.45, n, dtype=f32)
    U_, V_ = np.meshgrid(us, vs)
    fwd = np.array([0, -math.sin(ELEV), -math.cos(ELEV)], f32)
    up = np.array([0, math.cos(ELEV), -math.sin(ELEV)], f32)
    right = np.array([1, 0, 0], f32)
    orig = ((U_[..., None] * right + V_[..., None] * up) - fwd * 6.0).reshape(-1, 3)
    t = np.zeros(len(orig), f32)
    hit = np.zeros(len(orig), bool)
    for _ in range(steps):
        p = orig + fwd * t[:, None]
        d = sdf_fn(p)
        hit |= d < 0.002
        t = np.where(hit, t, t + np.maximum(d, 0.004))
    p = orig + fwd * t[:, None]
    e = 0.003
    nrm = np.stack([sdf_fn(p + [e, 0, 0]) - sdf_fn(p - [e, 0, 0]), sdf_fn(p + [0, e, 0]) - sdf_fn(p - [0, e, 0]),
                    sdf_fn(p + [0, 0, e]) - sdf_fn(p - [0, 0, e])], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True) + 1e-9
    diff = np.clip(nrm @ LIGHT * 0.85 + 0.15, 0, 1)
    hv = LIGHT + VIEW
    hv /= np.linalg.norm(hv)
    alb, spc = color_fn(p, nrm)
    c = alb * (0.32 + 0.85 * diff[:, None]) + (np.clip(nrm @ hv, 0, 1) ** 30 * spc)[:, None]
    ao = np.clip(0.55 + p[:, 1] * 0.5, 0.55, 1.0)
    c *= ao[:, None]
    img = np.zeros((len(orig), 4), f32)
    img[:, :3] = np.clip(c, 0, 1) * 255
    img[:, 3] = hit * 255
    im = Image.fromarray(img.reshape(n, n, 4).astype(np.uint8), "RGBA").resize((px, px), Image.LANCZOS)
    base_v = (0 - (-ext * 0.45)) / (ext * 1.15 + ext * 0.45)
    return im, (px / 2, px * (1 - base_v))


def render_clam():
    """거대 조개 + 진주."""
    def sdf(p):
        x, y, z = p[:, 0], p[:, 1], p[:, 2]
        # 아래 껍데기: 납작한 반구 + 골
        r = np.sqrt(x * x + z * z)
        ang = np.arctan2(z, x)
        ridge = 0.025 * np.cos(ang * 14)
        low = np.sqrt(x * x + (y * 2.6) ** 2 + z * z) - (0.9 + ridge)
        low = np.maximum(low, y - 0.05)
        # 위 껍데기: 뒤쪽으로 열린 채 비스듬히
        c, s = math.cos(-0.9), math.sin(-0.9)
        y2 = (y - 0.05) * c - (z + 0.75) * s
        z2 = (y - 0.05) * s + (z + 0.75) * c - 0.75
        up = np.sqrt(x * x + (y2 * 2.6) ** 2 + z2 * z2) - (0.9 + 0.025 * np.cos(np.arctan2(z2, x) * 14))
        up = np.maximum(up, -y2 - 0.02)
        pearl = np.sqrt(x * x + (y - 0.22) ** 2 + (z - 0.05) ** 2) - 0.24
        return np.minimum(np.minimum(low, up), pearl)

    def col(p, n):
        x, y, z = p[:, 0], p[:, 1], p[:, 2]
        pearl = np.sqrt(x * x + (y - 0.22) ** 2 + (z - 0.05) ** 2) < 0.26
        shell = np.array([0.78, 0.7, 0.86], f32) * (0.85 + 0.15 * np.cos(np.arctan2(z, x) * 14))[:, None]
        inner = np.array([0.95, 0.82, 0.88], f32)
        a = np.where((n[:, 1] > 0.3)[:, None] & (y < 0.12)[:, None], inner, shell)
        a = np.where(pearl[:, None], np.array([0.98, 0.97, 0.95], f32), a)
        spc = np.where(pearl, 1.4, 0.35)
        return a, spc
    return _ortho_raymarch(sdf, col, 1.7, 520)


def render_pillar(seed):
    """부서진 돌기둥."""
    r = np.random.default_rng(seed)
    hgt = r.uniform(0.9, 1.6)
    cut_a, cut_b = r.uniform(-0.5, 0.5), r.uniform(-0.5, 0.5)

    def sdf(p):
        x, y, z = p[:, 0], p[:, 1], p[:, 2]
        rr = np.sqrt(x * x + z * z)
        ang = np.arctan2(z, x)
        flute = 0.012 * np.cos(ang * 16)
        col_ = rr - (0.2 + flute)
        col_ = np.maximum(col_, y - (hgt + cut_a * x + cut_b * z) * 1.0)
        col_ = np.maximum(col_, -y)
        base = np.maximum(np.maximum(np.abs(x) - 0.3, np.abs(z) - 0.3), np.abs(y - 0.06) - 0.06)
        cap = np.maximum(rr - 0.26, np.abs(y - 0.2) - 0.05)
        return np.minimum(np.minimum(col_, base), cap)

    def col(p, n):
        a = np.array([0.86, 0.85, 0.8], f32) * (0.85 + 0.15 * np.sin(p[:, 1] * 40 + p[:, 0] * 10))[:, None]
        moss = (n[:, 1] > 0.6) & (p[:, 1] > 0.3)
        a = np.where(moss[:, None], np.array([0.4, 0.6, 0.4], f32), a)
        return a, np.full(len(p), 0.2, f32)
    return _ortho_raymarch(sdf, col, 1.0, 230)


# ── 조립 ─────────────────────────────────────────────────────
def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    nodes, curves = build_graph()
    print("spaces", len(nodes))
    print("ground")
    h, alb, spec, mat, coords, busy = build_ground(curves)
    print("tiles")
    carve_tiles(h, alb, spec, mat, nodes, coords)
    print("rocks / small")
    add_rocks(h, alb, spec, mat, coords, busy)
    add_small(h, alb, coords, busy)
    print("shade")
    col = shade(h, alb, spec, mat)
    img = project(col, h)
    img = water_grade(img)
    out = Image.fromarray(np.clip(img * 255, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    print("sprites")
    palette = [(255, 110, 100), (250, 160, 80), (190, 110, 235), (255, 100, 160), (250, 220, 110)]
    sprites = []
    for k in range(10):
        kind = "branch" if k % 3 != 2 else "tube"
        sprites.append(render_sprite(kind, 100 + k, palette[k % len(palette)], px=220 if kind == "branch" else 180))
    decor = []
    # 큰 볼거리: START 둘레 부서진 기둥
    placed_p = 0
    for a in np.linspace(0, 2 * math.pi, 24, endpoint=False):
        if placed_p >= 4:
            break
        x, z = S[0] + math.cos(a) * 250, S[1] + math.sin(a) * 215
        zi, xi = int(z), int(x)
        if busy[zi - 60:zi + 40, xi - 50:xi + 50].max() > 0.05:
            continue
        decor.append((x, z, ("pillar", int(rng.integers(3))), rng.uniform(0.9, 1.1)))
        busy[zi - 120:zi + 120, xi - 120:xi + 120] = 1
        placed_p += 1
    zones = [(P(700, 560), 9), (P(1300, 420), 3), (P(520, 2900), 3), (P(3400, 2850), 4), (P(1500, 3000), 2),
             (P(2500, 3000), 2), (P(300, 1300), 2), (P(3650, 2250), 2), (P(1100, 1650), 2), (P(2800, 1650), 2)]
    for (rx, rz), n in zones:
        for _ in range(n):
            for _t in range(50):
                x = rx + rng.normal(0, 150)
                z = rz + rng.normal(0, 115)
                if not (RIM + 80 < x < GW - RIM - 80 and RIM + 140 < z < GD - RIM - 40):
                    continue
                zi, xi = int(z), int(x)
                if busy[max(0, zi - 300):zi + 40, max(0, xi - 70):xi + 70].max() > 0.05:
                    continue
                decor.append((x, z, ("coral", int(rng.integers(len(sprites)))), rng.uniform(0.75, 1.25)))
                busy[max(0, zi - 50):zi + 50, max(0, xi - 50):xi + 50] = 1
                break
    clam_sprite = None
    pillar_sprites = [render_pillar(s) for s in range(3)]
    for x, z, (kind, si), sc in sorted(decor, key=lambda t: t[1]):
        if kind == "coral":
            im, (bx, by) = sprites[si]
        elif kind == "clam":
            im, (bx, by) = clam_sprite
        else:
            im, (bx, by) = pillar_sprites[si]
        if sc != 1.0:
            im = im.resize((int(im.width * sc), int(im.height * sc)), Image.LANCZOS)
            bx, by = bx * sc, by * sc
        gh = h[int(z), int(x)]
        sx, sy = x, screen_y(z, gh)
        shl = Image.new("RGBA", (int(im.width * 1.2), int(im.height * 0.5)), (0, 0, 0, 0))
        ImageDraw.Draw(shl).ellipse([shl.width * 0.25, shl.height * 0.35, shl.width * 0.95, shl.height * 0.75], fill=(0, 20, 18, 120))
        shl = shl.filter(ImageFilter.GaussianBlur(8))
        out.alpha_composite(shl, (int(sx - shl.width * 0.45), int(sy - shl.height * 0.55)))
        out.alpha_composite(im, (int(sx - bx), int(sy - by)))

    out.save(os.path.join(OUT, "tutorial_map.png"))
    out.resize((1200, int(1200 * SH / SW)), Image.LANCZOS).save(os.path.join(HERE, "out", "tutorial_map_small.png"))

    spaces = []
    for nd in nodes:
        x, z = nd["x"], nd["z"]
        sy = screen_y(z, h[int(z), int(x)])
        spaces.append({"id": nd["id"], "x": round(x, 1), "y": round(float(sy), 1), "kind": nd["kind"], "links": sorted(nd["links"])})
    kelp = []
    for _ in range(140):
        x, z = P(700 + rng.normal(0, 330), 1900 + rng.normal(0, 420))
        if RIM + 100 < x < GW - RIM - 60 and RIM + 200 < z < GD - RIM - 40 and \
                busy[max(0, int(z) - 420):int(z) + 30, int(x) - 50:int(x) + 50].max() < 0.05:
            kelp.append([round(x), round(float(screen_y(z, h[int(z), int(x)]))), round(float(rng.uniform(260, 520))),
                         round(float(rng.uniform(0, 6.28)), 2)])
            busy[int(z) - 20:int(z) + 20, int(x) - 20:int(x) + 20] = 1
    vx, vz = VOLCANO
    vents = [[vx, round(float(screen_y(vz, h[int(vz), int(vx)]))) - 10]]
    for ox, oz in ((-170, 80), (160, 110)):
        x, z = vx + ox, vz + oz
        vents.append([x, round(float(screen_y(z, h[int(z), int(x)])))])
    data = {"size": [SW, SH], "start": 0, "spaces": spaces, "kelp": kelp, "vents": vents}
    with open(os.path.join(OUT, "tutorial_world.json"), "w") as f:
        json.dump(data, f)
    print("done", SW, SH)


if __name__ == "__main__":
    main()
