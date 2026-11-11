"""보드 상자 열리는 연출 효과음: rumble(덜덜), burst(팡 열림 + 반짝), whoosh(빨려 들어감)
python3 tools/make_portal_sfx.py"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 44100
rng = np.random.default_rng(5)


def lp(x, f, order=2):
    b, a = butter(order, f / (SR / 2), "low")
    return lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = butter(order, f / (SR / 2), "high")
    return lfilter(b, a, x)


def save(name, x):
    x = x / (np.abs(x).max() + 1e-9) * 0.9
    wavfile.write(f"audio/sfx/{name}.wav", SR, (x * 32767).astype(np.int16))


# 덜덜 (1.4초, 점점 세짐): 낮은 덜컹 + 나무 상자 달그락
T = 1.4
t = np.arange(int(SR * T)) / SR
grow = (t / T) ** 1.4
rum = lp(rng.standard_normal(len(t)), 120) * 3.0
rum *= 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * (14 + 10 * t / T) * t))   # 덜덜 끊김
rattle = np.zeros(len(t))
k = 0.0
while k < T - 0.05:
    i = int(k * SR)
    n = int(SR * 0.03)
    click = hp(rng.standard_normal(n), 900) * np.exp(-np.linspace(0, 9, n))
    rattle[i:i + n] += click * rng.uniform(0.4, 1.0)
    k += rng.uniform(0.04, 0.09) * (1.2 - 0.6 * k / T)
hum = np.sin(2 * np.pi * 220 * t + 3 * np.sin(2 * np.pi * 5 * t)) * 0.15 * (t / T) ** 3    # 새어 나오는 빛 소리
save("box_rumble", (rum * 0.8 + rattle * 0.6 + hum) * grow)

# 팡 (1.6초): 쿵 + 공기 터짐 + 반짝이는 화음
T = 1.6
t = np.arange(int(SR * T)) / SR
thump = np.sin(2 * np.pi * (90 * np.exp(-t * 6) + 40) * t) * np.exp(-t * 7)
air = lp(rng.standard_normal(len(t)), 3000) * np.exp(-t * 5)
chime = np.zeros(len(t))
for f, d in [(784, 0.0), (988, 0.03), (1175, 0.06), (1568, 0.09), (1976, 0.13)]:
    env = np.clip((t - d) * 40, 0, 1) * np.exp(-np.clip(t - d, 0, None) * 2.6)
    chime += np.sin(2 * np.pi * f * t) * env * 0.35 + np.sin(2 * np.pi * f * 2.01 * t) * env * 0.08
shimmer = hp(rng.standard_normal(len(t)), 6000) * np.exp(-t * 2.5) * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * t))
save("box_burst", thump * 1.2 + air * 0.5 + chime + shimmer * 0.25)

# 빨려 들어감 (1.3초): 올라가는 쉬익 + 깊은 웅
T = 1.3
t = np.arange(int(SR * T)) / SR
noise = rng.standard_normal(len(t))
out = np.zeros(len(t))
seg = 1024
for i in range(0, len(t), seg):
    f = 300 + 5000 * (i / len(t)) ** 2
    out[i:i + seg] = lp(noise[i:i + seg], min(f, 15000))[:len(out[i:i + seg])]
env = np.clip(t / 0.15, 0, 1) * np.clip((T - t) / 0.12, 0, 1) * (0.4 + 0.6 * t / T)
deep = np.sin(2 * np.pi * (60 + 140 * (t / T) ** 2) * t) * 0.6 * env
riser = np.sin(2 * np.pi * (300 * 2 ** (t / T * 2.0)) * t) * 0.12 * (t / T) ** 2
save("box_whoosh", out * env * 1.5 + deep + riser)
print("ok")
