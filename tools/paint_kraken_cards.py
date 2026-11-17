"""크라켄 행동 카드 일러스트를 코드로 그림 (게임 화면이 아닌 그림책 같은 삽화).
    python3 tools/paint_kraken_cards.py  →  textures/ui/kraken/art_barrage.png · art_spines.png · art_surge.png · back_eye.png
2 배 크게 그린 뒤 줄여서 매끈하게 (SSAA)."""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "textures", "ui", "kraken")
os.makedirs(OUT, exist_ok=True)
W, H = 1280, 960            # 그리는 크기 (저장은 절반)
rng = np.random.default_rng(7)
YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)


def noise_tex(n=256, sigma=4.0, seed=0):
    g = np.random.default_rng(seed).standard_normal((n, n)).astype(np.float32)
    g = ndimage.gaussian_filter(g, sigma, mode="wrap")
    return (g - g.min()) / (g.max() - g.min())


NZ = [noise_tex(256, s, i) for i, s in enumerate((2.0, 5.0, 12.0))]


def sample(tex, u, v):
    n = tex.shape[0]
    return ndimage.map_coordinates(tex, [(v * n) % n, (u * n) % n], order=1, mode="wrap")


def fbm(u, v):
    return sample(NZ[2], u * 0.5, v * 0.5) * 0.5 + sample(NZ[1], u, v) * 0.3 + sample(NZ[0], u * 2, v * 2) * 0.2


def ridge(u, v):
    a = 1.0 - np.abs(sample(NZ[1], u, v) * 2 - 1)
    b = 1.0 - np.abs(sample(NZ[0], u * 1.7 + 3, v * 1.7) * 2 - 1)
    return a ** 10 + b ** 14 * 0.6


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def over(dst, rgb, alpha):
    a = np.clip(alpha, 0, 1)[..., None]
    dst[:] = dst * (1 - a) + rgb * a


def add(dst, rgb, amt):
    dst[:] = dst + rgb * np.clip(amt, 0, None)[..., None]


def glow(mask, sigma):
    return ndimage.gaussian_filter(mask.astype(np.float32), sigma)


# ── 바다 배경 ──────────────────────────────────────────────
def sea_bg(top=(0.02, 0.16, 0.17), bottom=(0.0, 0.04, 0.05), rays=True):
    t = (YY / H)[..., None]
    img = np.array(top, np.float32) * (1 - t) + np.array(bottom, np.float32) * t
    if rays:
        for k in range(6):
            x0 = rng.uniform(0.05, 0.95) * W
            ang = rng.uniform(-0.35, -0.1)
            d = np.abs((XX - x0) * np.cos(ang) - YY * np.sin(ang))
            wdt = rng.uniform(25, 70)
            ray = np.exp(-(d / wdt) ** 2) * smooth(H * 0.9, 0, YY) * rng.uniform(0.05, 0.11)
            add(img, np.array([0.5, 0.95, 0.85], np.float32), ray)
    caust = ridge(XX / 300.0, YY / 300.0) * smooth(H * 0.6, 0, YY)
    add(img, np.array([0.3, 0.6, 0.55], np.float32), caust * 0.08)
    return img


def bubbles(img, n, ymax=1.0, size=(3, 12)):
    for _ in range(n):
        x, y = rng.uniform(0, W), rng.uniform(0, H * ymax)
        r = rng.uniform(*size)
        d = np.sqrt((XX - x) ** 2 + (YY - y) ** 2)
        ring = np.exp(-((d - r) / (r * 0.25)) ** 2) * 0.5 + np.exp(-((XX - x + r * 0.35) ** 2 + (YY - y + r * 0.35) ** 2) / (r * 0.18) ** 2) * 0.6
        add(img, np.array([0.7, 1.0, 0.95], np.float32), ring * 0.6)


# ── 바닥 · 칸 (원근) ───────────────────────────────────────
HORIZON = 0.36
CAM_H = 5.0
FOC = 900.0


def proj(x, z, y=0.0):
    sx = W * 0.5 + x * FOC / z
    sy = H * HORIZON + (CAM_H - y) * FOC / z
    return sx, sy


def sand_floor(img, col=(0.58, 0.55, 0.42)):
    yh = H * HORIZON
    m = smooth(yh - 4, yh + 30, YY)
    z = CAM_H * FOC / np.maximum(YY - yh, 1.0)
    x = (XX - W * 0.5) * z / FOC
    tex = fbm(x / 6.0, z / 6.0) * 0.6 + sample(NZ[0], x * 1.5, z * 1.5) * 0.4
    fog = smooth(5.0, 60.0, z)
    base = np.array(col, np.float32) * (0.75 + 0.45 * tex)[..., None]
    base = base * (1 - fog[..., None] * 0.85) + np.array([0.02, 0.14, 0.15], np.float32) * fog[..., None] * 0.85
    caust = ridge(x / 3.0, z / 3.0) * (1 - fog)
    base += np.array([0.35, 0.6, 0.5], np.float32) * caust[..., None] * 0.15
    over(img, base, m)


def tile(img, x, z, col, s=1.0, h=0.45, glow_col=None, icon=True, yaw=0.0, layer=None):
    """칸 하나: 받침 + 윗면 + 테두리 + 그림. 반환: 윗면 중심 화면 좌표"""
    c, sn = np.cos(yaw), np.sin(yaw)
    def corner(dx, dz, y):
        rx, rz = dx * c - dz * sn, dx * sn + dz * c
        return proj(x + rx, z + rz, y)
    pil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(pil)
    hs = s * 1.1
    ps = hs + 0.25
    # 받침돌
    plinth = [corner(-ps, -ps, 0.18), corner(ps, -ps, 0.18), corner(ps, ps, 0.18), corner(-ps, ps, 0.18)]
    plinth_lo = [corner(-ps, ps, 0), corner(ps, ps, 0), corner(ps, ps, 0.18), corner(-ps, ps, 0.18)]
    d.polygon(plinth_lo, fill=(120, 116, 100, 255))
    d.polygon(plinth, fill=(176, 170, 150, 255))
    # 몸통 옆면 + 윗면
    side = [corner(-hs, hs, 0.18), corner(hs, hs, 0.18), corner(hs, hs, h), corner(-hs, hs, h)]
    cc = tuple(int(v * 255) for v in col)
    dark = tuple(int(v * 255 * 0.62) for v in col)
    d.polygon(side, fill=dark + (255,))
    top = [corner(-hs, -hs, h), corner(hs, -hs, h), corner(hs, hs, h), corner(-hs, hs, h)]
    d.polygon(top, fill=cc + (255,))
    inset = [corner(-hs * 0.82, -hs * 0.82, h), corner(hs * 0.82, -hs * 0.82, h), corner(hs * 0.82, hs * 0.82, h), corner(-hs * 0.82, hs * 0.82, h)]
    d.polygon(inset, outline=(240, 214, 140, 255), width=max(2, int(3 * FOC / z / 90)))
    cx, cy = proj(x, z, h)
    if icon:
        rr = 0.38 * FOC / z
        d.ellipse([cx - rr, cy - rr * 0.55, cx + rr, cy + rr * 0.55], fill=(255, 255, 255, 220))
    a = np.asarray(pil).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3]
    # 윗면 위쪽은 밝게
    shade = 0.85 + 0.25 * smooth(cy + 40, cy - 40, YY)
    rgb = rgb * shade[..., None]
    target = img if layer is None else layer
    over(target, rgb, al)
    if glow_col is not None:
        rr = 1.7 * FOC / z
        dd = np.sqrt(((XX - cx) / rr) ** 2 + ((YY - cy) / (rr * 0.45)) ** 2)
        add(target, np.array(glow_col, np.float32), np.exp(-dd ** 2 * 2.2) * 0.9 + np.exp(-((dd - 0.7) / 0.08) ** 2) * 0.5)
    return cx, cy


# ── 촉수 (스탬프로 관을 그리고 한꺼번에 음영) ──────────────
def bezier(pts, n):
    pts = np.array(pts, np.float32)
    t = np.linspace(0, 1, n)[:, None]
    out = np.zeros((n, 2), np.float32)
    k = len(pts) - 1
    from math import comb
    for i, p in enumerate(pts):
        out += comb(k, i) * (t ** i) * ((1 - t) ** (k - i)) * p
    return out


def tentacle(img, pts, r0, r1, sucker_side=1.0, n=420, glow_amt=1.0, dark=1.0, seed=0):
    path = bezier(pts, n)
    seg = np.diff(path, axis=0)
    seglen = np.linalg.norm(seg, axis=1)
    s = np.concatenate([[0], np.cumsum(seglen)])
    L = s[-1]
    tang = np.vstack([seg, seg[-1:]])
    tang /= np.linalg.norm(tang, axis=1, keepdims=True) + 1e-6
    nrm = np.stack([-tang[:, 1], tang[:, 0]], 1)
    rad = r0 + (r1 - r0) * (s / L) ** 0.9
    mask = np.zeros((H, W), np.float32)
    acr = np.zeros((H, W), np.float32)
    alg = np.zeros((H, W), np.float32)
    nx = np.zeros((H, W), np.float32)
    ny = np.zeros((H, W), np.float32
                  )
    rr_ = np.zeros((H, W), np.float32)
    for i in range(n):
        cx, cy = path[i]
        r = rad[i]
        x0, x1 = int(max(0, cx - r - 2)), int(min(W, cx + r + 3))
        y0, y1 = int(max(0, cy - r - 2)), int(min(H, cy + r + 3))
        if x0 >= x1 or y0 >= y1:
            continue
        dx = XX[y0:y1, x0:x1] - cx
        dy = YY[y0:y1, x0:x1] - cy
        dist = np.sqrt(dx * dx + dy * dy)
        inside = dist < r
        a = (dx * nrm[i, 0] + dy * nrm[i, 1]) / r
        sl = (slice(y0, y1), slice(x0, x1))
        mask[sl] = np.where(inside, 1.0, mask[sl])
        acr[sl] = np.where(inside, np.clip(a, -1, 1), acr[sl])
        alg[sl] = np.where(inside, s[i] / L, alg[sl])
        nx[sl] = np.where(inside, nrm[i, 0], nx[sl])
        ny[sl] = np.where(inside, nrm[i, 1], ny[sl])
        rr_[sl] = np.where(inside, r, rr_[sl])
    # 바깥 빛 번짐 (형광)
    g = glow(mask, 18)
    add(img, np.array([0.3, 0.9, 0.2], np.float32), g * 0.55 * glow_amt * (1 - mask))
    # 음영
    nz = np.sqrt(np.clip(1 - acr ** 2, 0, 1))
    N = np.stack([acr * nx, acr * ny, nz], -1)
    Ld = np.array([-0.45, -0.65, 0.6], np.float32)
    Ld /= np.linalg.norm(Ld)
    lam = np.clip((N * Ld).sum(-1), 0, 1)
    rim = (1 - nz) ** 2.2
    # 무늬 좌표: 촉수 길이 방향(u)은 굵기에 맞춰, 둘레 방향(v)은 넓게 — 잔무늬가 카펫처럼 보이지 않게
    u = alg * L / (rad.mean() * 5.0)
    v = acr * 0.28 + seed * 0.37
    ve = ridge(u * 0.22, v * 0.9)
    sp = smooth(0.8, 0.86, sample(NZ[1], u * 0.35, v * 1.5 + 5))
    base = np.array([0.05, 0.26, 0.08], np.float32) * dark
    neon = np.array([0.45, 1.0, 0.3], np.float32)
    col = base[None, None] * (0.45 + 1.0 * lam[..., None])
    # 속이 비치는 젤리 살: 가운데가 은은하게 밝음
    col = col + neon * (nz * 0.12 + 0.1 * fbm(u * 0.15, v))[..., None]
    col = col + np.array([0.75, 1.0, 0.25], np.float32) * (ve * 0.45 + sp * 0.55)[..., None]
    col = col + neon * rim[..., None] * 0.85
    # 빨판: 한쪽 면에 두 줄
    side = acr * sucker_side
    # 빨판: 한쪽 면에 한 줄 (굵기에 맞춰 간격, 끝으로 갈수록 작아짐)
    suck = np.zeros_like(acr)
    inner = np.zeros_like(acr)
    local_r = np.maximum(rr_, 1.0)
    pos = np.cumsum(np.concatenate([[0], seglen / (rad[:-1] * 1.25)]))   # 굵기 단위 거리
    pos_px = np.interp(alg, s / L, pos)
    ph = pos_px % 1.0 - 0.5
    dv = (side - 0.5) / 0.3
    e = np.sqrt((ph / 0.36) ** 2 + dv ** 2)
    fade = smooth(0.0, 0.06, alg) * smooth(1.0, 0.88, alg)
    suck = smooth(1.0, 0.8, e) * smooth(0.4, 0.62, e) * fade
    inner = smooth(0.62, 0.3, e) * fade
    col = col * (1 - inner[..., None] * 0.4) + np.array([0.62, 0.98, 0.42], np.float32) * suck[..., None] * 0.5
    # 반짝임
    R = 2 * (N * Ld).sum(-1, keepdims=True) * N - Ld
    spec = np.clip(R[..., 2], 0, 1) ** 40
    col = col + spec[..., None] * 0.6
    edge = smooth(0.0, 1.0, mask)
    over(img, col, edge * 0.97)
    return path, rad


def dust(img, cx, cy, size, n=40, col=(0.75, 0.72, 0.6)):
    for _ in range(n):
        x = cx + rng.normal(0, size * 0.6)
        y = cy + rng.normal(0, size * 0.18) - abs(rng.normal(0, size * 0.25))
        r = rng.uniform(size * 0.08, size * 0.25)
        d = ((XX - x) ** 2 + ((YY - y) * 1.3) ** 2) / r ** 2
        over(img, np.array(col, np.float32) * rng.uniform(0.75, 1.05), np.exp(-d * 1.6) * 0.38)


def impact(img, cx, cy, size):
    """내려친 자리: 납작한 충격파 고리 + 사방으로 튀는 빛줄기 + 바닥 금"""
    d = np.sqrt(((XX - cx) / size) ** 2 + ((YY - cy) / (size * 0.32)) ** 2)
    add(img, np.array([1.0, 0.95, 0.75], np.float32), np.exp(-((d - 1.0) / 0.08) ** 2) * 0.7 + np.exp(-((d - 0.62) / 0.06) ** 2) * 0.4)
    ang = np.arctan2((YY - cy) * 3.0, XX - cx)
    streak = np.clip(np.sin(ang * 9.0 + 1.3), 0, 1) ** 18 * np.exp(-d * 1.2) * smooth(0.25, 0.5, d)
    add(img, np.array([1.0, 0.9, 0.6], np.float32), streak * 0.8)
    pil = Image.new("L", (W, H), 0)
    dr = ImageDraw.Draw(pil)
    for k in range(7):
        a = rng.uniform(0, 6.28)
        x, y = cx, cy
        for _ in range(5):
            nx2 = x + np.cos(a) * size * rng.uniform(0.12, 0.22)
            ny2 = y + np.sin(a) * size * 0.32 * rng.uniform(0.12, 0.22)
            dr.line([x, y, nx2, ny2], fill=255, width=4)
            x, y = nx2, ny2
            a += rng.normal(0, 0.4)
    cr = np.asarray(pil).astype(np.float32) / 255
    over(img, np.array([0.12, 0.1, 0.07], np.float32), cr * 0.75)


def rocks(img, cx, cy, size, n=14):
    pil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(pil)
    for _ in range(n):
        x = cx + rng.normal(0, size * 0.7)
        y = cy - abs(rng.normal(0, size * 0.6))
        r = rng.uniform(size * 0.03, size * 0.09)
        pts = [(x + r * np.cos(a) * rng.uniform(0.6, 1.2), y + r * np.sin(a) * rng.uniform(0.6, 1.2)) for a in np.linspace(0, 6.28, 7)[:-1]]
        g = int(rng.uniform(80, 140))
        d.polygon(pts, fill=(g, g - 8, g - 25, 255))
    a = np.asarray(pil).astype(np.float32) / 255
    over(img, a[..., :3], a[..., 3])


def vignette(img, amt=0.6):
    r = np.sqrt(((XX / W - 0.5) * 1.5) ** 2 + ((YY / H - 0.5) * 1.5) ** 2)
    img *= (1 - amt * np.clip(r - 0.4, 0, 1) ** 1.3)[..., None]


def save(img, name):
    a = np.clip(img, 0, 1)
    a = a ** (1 / 1.05)
    im = Image.fromarray((a * 255).astype(np.uint8)).resize((W // 2, H // 2), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=1.0, percent=40, threshold=2))
    im.save(os.path.join(OUT, name + ".png"))
    print("->", name)


# ── 1) 촉수 폭풍 ──────────────────────────────────────────
def paint_barrage():
    img = sea_bg()
    # 저 멀리 크라켄 그림자와 눈
    sil = np.exp(-(((XX - W * 0.5) / (W * 0.33)) ** 2 + ((YY - H * 0.2) / (H * 0.24)) ** 2) * 1.5)
    over(img, np.array([0.01, 0.07, 0.06], np.float32), sil * 0.75)
    for ex in (0.41, 0.59):
        d = np.sqrt(((XX - W * ex) / 26) ** 2 + ((YY - H * 0.22) / 14) ** 2)
        add(img, np.array([1.0, 0.85, 0.2], np.float32), np.exp(-d ** 2 * 1.5) * 1.2)
        add(img, np.array([0.6, 1.0, 0.3], np.float32), np.exp(-d ** 2 * 0.12) * 0.25)
    sand_floor(img)
    bubbles(img, 30, 0.5)
    red = (1.0, 0.18, 0.08)
    tiles = [(-4.6, 15.0, (0.36, 0.66, 0.92), True), (-1.4, 12.5, (0.95, 0.94, 0.86), False), (1.9, 13.4, (0.98, 0.8, 0.3), True),
             (4.9, 15.5, (0.36, 0.66, 0.92), False), (-3.0, 8.6, (0.98, 0.8, 0.3), False), (0.6, 7.6, (0.36, 0.66, 0.92), True),
             (3.8, 8.8, (0.95, 0.94, 0.86), True), (-6.0, 10.4, (0.95, 0.94, 0.86), False)]
    tiles.sort(key=lambda t: -t[1])
    centers = {}
    for x, z, c, hot in tiles:
        centers[(x, z)] = tile(img, x, z, c, glow_col=red if hot else None)
    # 뒤쪽 촉수 둘: 크게 솟아 칸 위로 내려꽂힘
    tentacle(img, [(W * 0.05, H * 0.62), (W * 0.0, H * 0.05), (W * 0.32, -H * 0.08), centers[(-4.6, 15.0)]], 52, 9, -1, seed=1)
    tentacle(img, [(W * 1.0, H * 0.6), (W * 1.04, H * 0.02), (W * 0.62, -H * 0.05), centers[(1.9, 13.4)]], 50, 9, 1, seed=2)
    for key in [(-4.6, 15.0), (1.9, 13.4)]:
        cx, cy = centers[key]
        impact(img, cx, cy, 150)
        dust(img, cx, cy, 120, 18)
    # 앞쪽: 칸을 막 내려친 촉수 (흙먼지 · 돌 조각)
    tx, ty = centers[(0.6, 7.6)]
    impact(img, tx, ty, 330)
    dust(img, tx, ty + 10, 260, 50)
    rocks(img, tx, ty, 330, 18)
    tentacle(img, [(W * 0.62, H * 1.15), (W * 0.95, H * 0.42), (W * 0.42, H * 0.3), (tx - 30, ty - 10)], 112, 22, 1, seed=3)
    tile(img, -3.0, 8.6, (0.98, 0.8, 0.3), glow_col=None)  # 앞 칸이 촉수 뒤로 가려지지 않게 다시
    # 오른쪽 뜨거운 칸에도 촉수 끝이 솟는 중
    hx, hy = centers[(3.8, 8.8)]
    tentacle(img, [(hx + 120, hy + 40), (hx + 150, hy - 220), (hx + 30, hy - 330), (hx - 30, hy - 230)], 46, 12, -1, seed=4)
    dust(img, hx + 110, hy + 30, 110, 14)
    bubbles(img, 25, 1.0, (4, 16))
    vignette(img, 0.7)
    save(img, "art_barrage")


# ── 2) 독 가시 ────────────────────────────────────────────
def spine(img, base, tip, w, col=(0.55, 0.25, 0.75)):
    bx, by = base
    tx, ty = tip
    dvec = np.array([tx - bx, ty - by], np.float32)
    L = np.linalg.norm(dvec)
    t = dvec / L
    nrm = np.array([-t[1], t[0]])
    px, py = XX - bx, YY - by
    along = (px * t[0] + py * t[1]) / L
    acr = (px * nrm[0] + py * nrm[1])
    half = w * (1 - np.clip(along, 0, 1)) ** 1.15
    m = (along > 0) & (along < 1) & (np.abs(acr) < half + 1)
    a = np.where(m, np.clip(acr / np.maximum(half, 0.5), -1, 1), 0)
    edge = smooth(half + 1.2, half - 0.8, np.abs(acr)) * (along > 0) * (along < 1)
    lit = 0.45 + 0.55 * np.clip(-a * 0.8 + 0.4, 0, 1)
    c = np.array(col, np.float32)[None, None] * lit[..., None]
    c = c * (0.55 + 0.45 * along)[..., None]
    c = c + np.array([0.9, 0.6, 1.0], np.float32) * (smooth(0.75, 1.0, along) * 0.5)[..., None]
    c = c + np.array([1, 1, 1], np.float32) * (np.exp(-((a + 0.45) / 0.12) ** 2) * 0.35 * along)[..., None]
    over(img, c, edge)


def paint_spines():
    img = sea_bg((0.04, 0.12, 0.14), (0.0, 0.03, 0.04))
    sand_floor(img, (0.52, 0.5, 0.42))
    bubbles(img, 20, 0.45)
    # 주변 칸 (흐릿하게 멀리)
    for x, z, c in [(-5.5, 15.0, (0.36, 0.66, 0.92)), (5.2, 14.5, (0.98, 0.8, 0.3)), (-5.6, 7.6, (0.95, 0.94, 0.86)), (5.4, 7.4, (0.36, 0.66, 0.92))]:
        tile(img, x, z, c)
    # 가운데: 독 가시 칸 (보라색) — 칸 위로 가시가 폭발하듯 솟음
    cx, cy = tile(img, 0.0, 9.5, (0.55, 0.3, 0.75), s=1.5, icon=False, glow_col=(0.7, 0.2, 1.0))
    # 칸 위 독 웅덩이
    pd = np.sqrt(((XX - cx) / 230) ** 2 + ((YY - cy) / 85) ** 2)
    add(img, np.array([0.45, 1.0, 0.25], np.float32), np.exp(-pd ** 2 * 3) * 0.55)
    order = []
    for k in range(34):
        ang = rng.uniform(-np.pi, 0) if k < 30 else rng.uniform(-2.4, -0.7)
        spread = rng.uniform(0.0, 1.0) ** 0.7
        a0 = rng.uniform(0, 6.28)
        bx = cx + np.cos(a0) * 190 * spread
        by = cy + np.sin(a0) * 70 * spread
        lean = (bx - cx) / 190.0
        Lh = rng.uniform(200, 460) * (1.15 - spread * 0.55)
        tip = (bx + lean * Lh * 0.55 + rng.normal(0, 30), by - Lh)
        order.append((by, (bx, by), tip, rng.uniform(13, 26)))
    order.sort(key=lambda o: o[0])
    for _, b, t, w in order:
        spine(img, b, t, w, col=(rng.uniform(0.45, 0.62), rng.uniform(0.18, 0.3), rng.uniform(0.65, 0.85)))
    # 독 방울 · 연기
    for _ in range(26):
        x = cx + rng.normal(0, 210)
        y = cy - rng.uniform(40, 520)
        r = rng.uniform(10, 46)
        d = ((XX - x) ** 2 + (YY - y) ** 2) / r ** 2
        add(img, np.array([0.4, 1.0, 0.25], np.float32), np.exp(-d * 1.2) * rng.uniform(0.15, 0.4))
    for _ in range(14):
        x = cx + rng.normal(0, 160)
        y = cy - rng.uniform(80, 380)
        r = rng.uniform(6, 13)
        d = np.sqrt((XX - x) ** 2 + ((YY - y) / 1.35) ** 2)
        over(img, np.array([0.55, 1.0, 0.35], np.float32), smooth(r + 1, r - 1, d) * 0.85)
        add(img, np.array([1, 1, 1], np.float32), np.exp(-((XX - x + r * 0.3) ** 2 + (YY - y + r * 0.4) ** 2) / (r * 0.3) ** 2) * 0.7)
    bubbles(img, 20, 1.0, (4, 14))
    vignette(img, 0.75)
    save(img, "art_spines")


# ── 3) 상점 대혼란 ────────────────────────────────────────
def paint_surge():
    img = sea_bg((0.03, 0.15, 0.15), (0.0, 0.04, 0.05))
    sand_floor(img, (0.56, 0.53, 0.42))
    bubbles(img, 20, 0.45)
    # 노점: 나무 기둥 · 계산대 · 분홍 줄무늬 차양
    pil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(pil)
    sx, sy = W * 0.47, H * 0.83
    # 그림자
    d.ellipse([sx - 330, sy - 30, sx + 330, sy + 40], fill=(0, 0, 0, 90))
    wood, wood_d = (132, 86, 50, 255), (92, 58, 34, 255)
    for px in (-250, 230):
        d.rectangle([sx + px, sy - 560, sx + px + 34, sy], fill=wood)
        d.rectangle([sx + px + 24, sy - 560, sx + px + 34, sy], fill=wood_d)
    d.rectangle([sx - 280, sy - 230, sx + 290, sy], fill=wood)
    for k in range(7):
        d.line([sx - 280, sy - 230 + k * 33, sx + 290, sy - 230 + k * 33], fill=wood_d, width=4)
    d.rectangle([sx - 300, sy - 260, sx + 310, sy - 225], fill=(160, 108, 64, 255))
    # 차양 (기울어짐 — 크라켄이 흔들어서)
    aw = [(sx - 340, sy - 590), (sx + 360, sy - 640), (sx + 380, sy - 500), (sx - 330, sy - 450)]
    d.polygon(aw, fill=(250, 240, 236, 255))
    for k in range(8):
        f0, f1 = k / 8, (k + 0.5) / 8
        def lerp(a, b, f):
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        d.polygon([lerp(aw[0], aw[1], f0), lerp(aw[0], aw[1], f1), lerp(aw[3], aw[2], f1), lerp(aw[3], aw[2], f0)], fill=(236, 120, 150, 255))
    for k in range(9):
        f = k / 8
        x = aw[3][0] + (aw[2][0] - aw[3][0]) * f
        y = aw[3][1] + (aw[2][1] - aw[3][1]) * f
        d.pieslice([x - 40, y - 30, x + 40, y + 30], 0, 180, fill=(236, 120, 150, 255) if k % 2 == 0 else (250, 240, 236, 255))
    # 진열된 물약 · 방패
    for k, (cx2, colr) in enumerate([(-170, (230, 70, 80)), (-40, (120, 190, 240)), (90, (230, 70, 80))]):
        d.ellipse([sx + cx2 - 34, sy - 330, sx + cx2 + 34, sy - 262], fill=colr + (255,))
        d.rectangle([sx + cx2 - 10, sy - 362, sx + cx2 + 10, sy - 328], fill=colr + (255,))
        d.ellipse([sx + cx2 - 18, sy - 320, sx + cx2 - 4, sy - 306], fill=(255, 255, 255, 200))
    a = np.asarray(pil).astype(np.float32) / 255
    over(img, a[..., :3], a[..., 3])
    # 촉수: 노점 뒤에서 솟아 차양을 휘감고 앞으로 내려옴
    tentacle(img, [(W * 0.98, H * 1.05), (W * 1.02, H * 0.15), (W * 0.62, -H * 0.12), (W * 0.36, H * 0.12), (W * 0.24, H * 0.36)], 98, 18, 1, seed=5)
    # 날아가는 동전
    pil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(pil)
    for _ in range(16):
        x, y = rng.uniform(W * 0.1, W * 0.9), rng.uniform(H * 0.25, H * 0.75)
        r = rng.uniform(18, 34)
        sq = rng.uniform(0.25, 1.0)
        d.ellipse([x - r, y - r * sq, x + r, y + r * sq], fill=(250, 196, 60, 255), outline=(180, 120, 20, 255), width=4)
        d.ellipse([x - r * 0.55, y - r * sq * 0.55, x + r * 0.55, y + r * sq * 0.55], outline=(255, 232, 140, 255), width=3)
    a = np.asarray(pil).astype(np.float32) / 255
    over(img, a[..., :3], a[..., 3])
    # 가격표 x2 (빨간 글씨)
    pil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(pil)
    tx, ty = sx - 60, sy - 170
    d.polygon([(tx - 150, ty - 60), (tx + 110, ty - 60), (tx + 160, ty), (tx + 110, ty + 60), (tx - 150, ty + 60)], fill=(240, 220, 170, 255), outline=(120, 80, 40, 255))
    d.ellipse([tx + 92, ty - 14, tx + 120, ty + 14], fill=(120, 80, 40, 255))
    from PIL import ImageFont
    fnt = None
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/home/claude/deep_party/fonts/GowunBatang-Bold.ttf"]:
        if os.path.exists(p):
            fnt = ImageFont.truetype(p, 100)
            break
    d.text((tx - 110, ty - 62), "×2", font=fnt, fill=(200, 20, 20, 255))
    pt = pil.rotate(-12, center=(tx, ty), resample=Image.BICUBIC)
    a = np.asarray(pt).astype(np.float32) / 255
    over(img, a[..., :3], a[..., 3])
    bubbles(img, 25, 1.0, (4, 14))
    vignette(img, 0.7)
    save(img, "art_surge")


# ── 카드 뒷면: 크라켄 눈 ──────────────────────────────────
def paint_back():
    img = np.zeros((H, W, 3), np.float32)
    u, v = XX / 900.0, YY / 900.0
    skin = np.array([0.03, 0.2, 0.07], np.float32) * (0.6 + 0.7 * fbm(u, v))[..., None]
    skin += np.array([0.7, 1.0, 0.25], np.float32) * (ridge(u * 1.0, v * 1.0) * 0.7)[..., None]
    sp = smooth(0.8, 0.86, sample(NZ[1], u * 1.5, v * 1.5))
    skin += np.array([0.6, 1.0, 0.3], np.float32) * sp[..., None] * 0.6
    img[:] = skin
    cx, cy = W * 0.5, H * 0.5
    # 눈두덩 (불룩한 살 + 어두운 홈)
    ed = np.sqrt(((XX - cx) / 470) ** 2 + ((YY - cy) / 330) ** 2)
    img *= (1 - 0.65 * np.exp(-((ed - 1.0) / 0.12) ** 2))[..., None]
    add(img, np.array([0.45, 1.0, 0.3], np.float32), np.exp(-((ed - 1.12) / 0.07) ** 2) * 0.5)
    # 눈알
    r = np.sqrt(((XX - cx) / 400) ** 2 + ((YY - cy) / 290) ** 2)
    ang = np.arctan2(YY - cy, XX - cx)
    fib = sample(NZ[0], ang * 6.0, r * 2.0) * 0.6 + sample(NZ[1], ang * 2.0, r)
    iris = np.array([0.55, 0.36, 0.06], np.float32) * (1 - fib[..., None]) + np.array([0.98, 0.82, 0.3], np.float32) * fib[..., None]
    iris *= (1 - 0.7 * smooth(0.7, 1.0, r))[..., None]
    # 가로로 긴 동공
    px, py = (XX - cx) / 300, (YY - cy) / 70
    pup = smooth(1.05, 0.95, np.sqrt(px ** 2 + py ** 2 * (1 + 0.3 * px ** 2)))
    iris = iris * (1 - pup[..., None]) + np.array([0.01, 0.01, 0.0], np.float32) * pup[..., None]
    m = smooth(1.0, 0.97, r)
    over(img, iris, m)
    # 촉촉한 반사
    for (hx, hy, hr, ha) in [(cx - 150, cy - 120, 55, 0.9), (cx + 120, cy + 110, 22, 0.5)]:
        d = ((XX - hx) ** 2 + (YY - hy) ** 2) / hr ** 2
        add(img, np.array([1, 1, 1], np.float32), np.exp(-d * 2.0) * ha * m)
    add(img, np.array([0.8, 1.0, 0.7], np.float32), np.exp(-((r - 0.98) / 0.03) ** 2) * 0.3)
    vignette(img, 0.8)
    save(img, "back_eye")


if __name__ == "__main__":
    import sys
    which = sys.argv[1:] or ["barrage", "spines", "surge", "back"]
    for w in which:
        {"barrage": paint_barrage, "spines": paint_spines, "surge": paint_surge, "back": paint_back}[w]()
