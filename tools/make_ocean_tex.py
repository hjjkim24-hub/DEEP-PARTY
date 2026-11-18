#!/usr/bin/env python3
"""바다 텍스처 굽기 (이어 붙여도 이음새 없는 타일).

  textures/ocean/water_normal_a.png  큰 잔물결 (바람 방향으로 길쭉)
  textures/ocean/water_normal_b.png  작은 잔물결 (다른 방향)
  textures/ocean/foam.png            거품 무늬 (회색조: 밝을수록 거품)

실제 바다 물결 스펙트럼(필립스 스펙트럼)으로 무작위 물결을 만들고 역 FFT 로 높이장을 얻음 →
주파수가 격자 위 정수라서 저절로 이음새 없는 타일이 됨. 노멀은 높이장 기울기로.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures", "ocean")
N = 512


def phillips_height(seed: int, wind: tuple, wind_speed: float, size_m: float, damp_small: float) -> np.ndarray:
    rng = np.random.default_rng(seed)
    k = np.fft.fftfreq(N, d=size_m / N) * 2 * np.pi
    kx, ky = np.meshgrid(k, k)
    kk = np.sqrt(kx ** 2 + ky ** 2)
    kk[0, 0] = 1e-6
    w = np.array(wind, dtype=float)
    w /= np.linalg.norm(w)
    L = wind_speed ** 2 / 9.81
    kdotw = (kx * w[0] + ky * w[1]) / kk
    ph = np.exp(-1.0 / (kk * L) ** 2) / kk ** 4 * kdotw ** 2
    ph *= np.exp(-(kk * damp_small) ** 2)          # 너무 작은 물결은 줄임
    ph[kdotw < 0] *= 0.15                            # 바람 반대 방향 물결은 약하게
    ph[0, 0] = 0.0
    spec = (rng.normal(size=(N, N)) + 1j * rng.normal(size=(N, N))) * np.sqrt(ph / 2.0)
    h = np.real(np.fft.ifft2(spec))
    # 기울기 (스펙트럼 미분 = 이음새 없음)
    dx = np.real(np.fft.ifft2(spec * 1j * kx))
    dy = np.real(np.fft.ifft2(spec * 1j * ky))
    return h, dx, dy


def save_normal(name: str, dx: np.ndarray, dy: np.ndarray, strength: float) -> None:
    s = strength / (np.percentile(np.abs(np.concatenate([dx.ravel(), dy.ravel()])), 98) + 1e-9)
    nx, ny = -dx * s, -dy * s
    nz = np.ones_like(nx)
    ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    rgb = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name))
    print("  ", name)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    _, dxa, dya = phillips_height(1, (1.0, 0.35), 9.0, 24.0, 0.16)
    save_normal("water_normal_a.png", dxa, dya, 0.9)
    _, dxb, dyb = phillips_height(2, (-0.4, 1.0), 5.0, 9.0, 0.07)
    save_normal("water_normal_b.png", dxb, dyb, 0.9)
    # 거품: 레이스처럼 얽힌 가는 줄 + 드문드문 뭉친 덩어리 (띠 주파수 잡음 두 겹)
    lace1 = 1.0 - np.abs(band_noise(5, 9.0))
    lace2 = 1.0 - np.abs(band_noise(6, 21.0))
    blob = band_noise(7, 5.0)
    lace = np.clip((lace1 - 0.72) / 0.28, 0, 1) ** 1.6 * 0.8 + np.clip((lace2 - 0.78) / 0.22, 0, 1) ** 1.5 * 0.55
    clump = np.clip((blob - 0.25) / 0.6, 0, 1) ** 1.2
    foam = np.clip(lace * (0.45 + 0.55 * clump) + clump * 0.35, 0, 1)
    Image.fromarray((foam * 255).astype(np.uint8), "L").save(os.path.join(OUT, "foam.png"))
    print("   foam.png")


def band_noise(seed: int, k0: float) -> np.ndarray:
    """주파수 크기가 k0(타일당 물결 수) 근처인 잡음 (-1..1)"""
    rng = np.random.default_rng(seed)
    k = np.fft.fftfreq(N, d=1.0 / N)
    kx, ky = np.meshgrid(k, k)
    kk = np.sqrt(kx ** 2 + ky ** 2)
    wgt = np.exp(-((kk - k0) / (k0 * 0.35)) ** 2)
    spec = (rng.normal(size=(N, N)) + 1j * rng.normal(size=(N, N))) * wgt
    n = np.real(np.fft.ifft2(spec))
    return n / np.abs(n).max()


if __name__ == "__main__":
    main()
