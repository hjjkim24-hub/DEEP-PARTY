"""새 미니게임 소리 (합성) → audio/sfx/
  gull.wav  : 갈매기 울음 "끼룩 끼룩" — 쉰 듯한 높은 소리가 위로 꺾였다 내려옴, 두 번
  pump.wav  : 손펌프 한 번 — 쇠 피스톤 끼익 + 꿀렁 물 밀려드는 소리
  spray.wav : 물대포 물줄기 — 쏴아 (센 물줄기 잡음 + 물방울 튐)"""
import os
import subprocess
import numpy as np

SR = 44100
OUT = "audio/sfx"
rng = np.random.default_rng(23)


def save(name, x, peak_db=-1.0):
    x = x / (np.abs(x).max() + 1e-9) * 10 ** (peak_db / 20)
    st = np.stack([x, x], axis=1)
    pcm = (np.clip(st, -1, 1) * 32767).astype("<i2")
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    os.path.join(OUT, name + ".wav")], input=pcm.tobytes(), check=True)
    print("  sfx", name, round(len(x) / SR, 2))


def lp(x, hz):
    a = 1.0 - np.exp(-2 * np.pi * hz / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def bp(x, lo, hi):
    return lp(x, hi) - lp(x, lo)


# 갈매기: 0.95 초, 울음 두 번
n = int(0.95 * SR)
out = np.zeros(n)
for start, L, f0, f1 in ((0.0, 0.38, 1350, 2150), (0.45, 0.42, 1300, 2050)):
    m = int(L * SR)
    t = np.arange(m) / SR
    u = t / L
    # 처음엔 위로 꺾여 올라가다 끝에서 뚝 떨어지는 음
    f = f0 + (f1 - f0) * np.sin(np.pi * np.minimum(u * 1.4, 1.0)) - 500 * np.maximum(u - 0.7, 0) / 0.3
    f = f * (1 + 0.02 * np.sin(2 * np.pi * 31 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.55 * np.sin(2 * ph + 0.3) + 0.3 * np.sin(3 * ph) + 0.15 * np.sin(4 * ph)
    rasp = bp(rng.standard_normal(m), 1500, 4500) * 0.9
    env = np.minimum(1, u / 0.06) * np.minimum(1, (1 - u) / 0.15) ** 1.4
    s = (tone * (0.75 + 0.25 * np.sin(2 * np.pi * 70 * t)) + rasp) * env
    i0 = int(start * SR)
    out[i0:i0 + m] += s[: n - i0]
save("gull", out, -4.0)

# 펌프: 0.42 초
n = int(0.42 * SR)
t = np.arange(n) / SR
sq_f = 900 + 700 * np.sin(np.pi * np.minimum(t / 0.16, 1.0))
squeak = np.sin(2 * np.pi * np.cumsum(sq_f) / SR) * np.exp(-((t - 0.07) / 0.06) ** 2) * 0.35
thunk = np.sin(2 * np.pi * 90 * t) * np.exp(-t / 0.05) * np.minimum(1, t / 0.003)
gush = bp(rng.standard_normal(n), 200, 1400) * np.exp(-((t - 0.2) / 0.09) ** 2) * 1.2
glug = np.sin(2 * np.pi * (180 + 120 * np.sin(2 * np.pi * 9 * t)) * t) * np.exp(-((t - 0.22) / 0.07) ** 2) * 0.5
save("pump", squeak + thunk + gush + glug, -3.0)

# 물줄기: 0.6 초 (계속 쏠 땐 이어서 반복 재생)
n = int(0.6 * SR)
t = np.arange(n) / SR
hiss = bp(rng.standard_normal(n), 1800, 7500)
body = bp(rng.standard_normal(n), 300, 1500) * 0.6
drops = np.zeros(n)
for k in range(30):
    s = int(rng.uniform(0, 0.55) * SR)
    L = int(0.02 * SR)
    tt = np.arange(L) / SR
    fr = rng.uniform(1200, 2600)
    drops[s:s + L] += np.sin(2 * np.pi * fr * tt * (1 + tt * 30)) * np.exp(-tt / 0.006) * 0.4
env = np.minimum(1, t / 0.03) * np.minimum(1, (0.6 - t) / 0.08) * (0.85 + 0.15 * np.sin(2 * np.pi * 13 * t))
save("spray", (hiss + body + drops) * env, -5.0)
