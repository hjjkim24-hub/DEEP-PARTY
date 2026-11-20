"""전기뱀장어 · 곰덫 소리 (합성 + CC0 소리 섞기) → audio/sfx/
  zap.wav  : 물속 방전 — 찌지직 터지는 잡음 + 낮은 웅 소리 + 물거품
  snap.wav : 쇠 이빨이 철컥 맞물림 — 날카로운 금속 충격 + 짧은 울림"""
import os
import subprocess
import numpy as np

SR = 44100
OUT = "audio/sfx"
rng = np.random.default_rng(11)


def save(name, x, peak_db=-1.0):
    x = x / (np.abs(x).max() + 1e-9) * 10 ** (peak_db / 20)
    st = np.stack([x, x], axis=1)
    pcm = (np.clip(st, -1, 1) * 32767).astype("<i2")
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    os.path.join(OUT, name + ".wav")], input=pcm.tobytes(), check=True)
    print("  sfx", name, len(x) / SR)


def onepole_hp(x, hz):
    a = np.exp(-2 * np.pi * hz / SR)
    y = np.zeros_like(x)
    prev_x = prev_y = 0.0
    for i in range(len(x)):
        y[i] = a * (prev_y + x[i] - prev_x)
        prev_x, prev_y = x[i], y[i]
    return y


# zap: 1.1 초
n = int(1.1 * SR)
t = np.arange(n) / SR
env = np.minimum(1, t / 0.01) * np.exp(-t / 0.35)
crackle = rng.standard_normal(n) * (rng.random(n) < 0.08) * 3.0          # 튀는 잡음 알갱이
burst = np.zeros(n)
for k in range(14):                                                       # 찌지직 덩어리들
    s = int(rng.uniform(0, 0.7) * SR)
    L = int(rng.uniform(0.01, 0.05) * SR)
    burst[s:s + L] += rng.standard_normal(min(L, n - s)) * rng.uniform(0.4, 1.0)
hum = np.sign(np.sin(2 * np.pi * 110 * t)) * 0.25 + np.sin(2 * np.pi * 55 * t) * 0.35   # 웅 (전기 험)
hum *= 0.6 + 0.4 * np.sin(2 * np.pi * 23 * t)
zap = onepole_hp((crackle + burst) * env, 900) * 1.2 + hum * env
zap = np.tanh(zap * 2.2)
save("zap", zap, -1.0)

# snap: 0.6 초
n = int(0.6 * SR)
t = np.arange(n) / SR
click = rng.standard_normal(n) * np.exp(-t / 0.006)
ring = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * a * np.exp(-t / d)
           for f, a, d in [(1870, 0.5, 0.12), (2930, 0.35, 0.08), (4410, 0.25, 0.05), (960, 0.4, 0.18)])
thud = np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.05) * 0.9
snap = onepole_hp(click, 1500) * 1.4 + ring + thud
snap = np.tanh(snap * 1.6)
save("snap", snap, -1.0)
