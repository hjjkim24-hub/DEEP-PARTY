"""모래사장 보물찾기 효과음: 금속탐지기 삑 (낮은 · 높은) + 삽으로 모래 푸는 소리 (CC0, 직접 합성)
python3 tools/make_beach_sfx.py → audio/sfx/det_beep.wav, det_ping.wav, dig_sand.wav
"""
import numpy as np
from scipy.signal import butter, sosfilt
import wave
import os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "sfx")


def save(name, x, peak=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def env(n, a, r):
    e = np.ones(n)
    na = int(a * SR)
    nr = int(r * SR)
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] = np.linspace(1, 0, nr) ** 1.5
    return e


def beep(freq, dur):
    t = np.arange(int(dur * SR)) / SR
    # 작은 스피커에서 나는 전자음: 사인 + 약한 홀수 배음, 살짝 떨림
    x = np.sin(2 * np.pi * freq * t) + 0.18 * np.sin(2 * np.pi * freq * 3 * t) + 0.05 * np.sin(2 * np.pi * freq * 5 * t)
    x *= 1.0 + 0.04 * np.sin(2 * np.pi * 38 * t)
    x *= env(len(t), 0.004, dur * 0.45)
    sos = butter(2, [500, 7000], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def dig():
    # 삽이 모래에 박히는 둔탁한 소리 + 모래가 흩어지는 사각사각
    n = int(0.55 * SR)
    rng = np.random.default_rng(3)
    noise = rng.standard_normal(n)
    t = np.arange(n) / SR
    thud = np.sin(2 * np.pi * 95 * t) * np.exp(-t * 28)
    sos = butter(2, [900, 5200], btype="band", fs=SR, output="sos")
    grit = sosfilt(sos, noise) * (np.exp(-np.maximum(t - 0.06, 0) * 7) * (t > 0.02))
    # 알갱이 톡톡
    grains = np.zeros(n)
    for k in range(160):
        i = int(rng.uniform(0.05, 0.5) * SR)
        grains[i:i + 60] += rng.uniform(0.2, 1.0) * np.hanning(60) * rng.choice([-1, 1])
    sos2 = butter(2, 2500, btype="high", fs=SR, output="sos")
    grains = sosfilt(sos2, grains)
    x = thud * 0.9 + grit * 0.55 + grains * 0.35
    x *= env(n, 0.003, 0.12)
    return x


if __name__ == "__main__":
    save("det_beep", beep(1750, 0.075), 0.55)
    save("det_ping", beep(2500, 0.06), 0.6)
    save("dig_sand", dig(), 0.75)
    print("ok")
