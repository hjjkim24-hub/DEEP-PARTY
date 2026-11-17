"""크라켄 · 크라켄의 배 효과음 (모두 합성):
  cannon   대포 쾅 (낮은 폭발 + 공기 터짐 + 꼬리 울림)       explode  포탄이 터짐 (파편 · 나무 부서짐)
  whoosh   휙 (떨어질 때 · 포탄이 날아감)                  portal   포탈 열림 (빙글 도는 낮은 울림 + 반짝)
  card_spin 카드들이 돌아가는 사각사각                     card_flip 카드 뒤집힘 (탁 + 반짝)
  coins    동전 쏟아짐 (짤랑짤랑)                         roar     크라켄 으르렁 (낮게 끓는 울림)
  thud     말이 갑판에 쿵 내려앉음                          creak    나무 삐걱 (바퀴 · 배)
  wind     배 위 바람 (반복되는 배경 소리, 8초)
python3 tools/make_ship_sfx.py"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 44100
rng = np.random.default_rng(11)


def lp(x, f, order=2):
    b, a = butter(order, f / (SR / 2), "low")
    return lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = butter(order, f / (SR / 2), "high")
    return lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return lfilter(b, a, x)


def t_(dur):
    return np.arange(int(SR * dur)) / SR


def env(t, a, d):
    return np.clip(t / max(a, 1e-4), 0, 1) * np.exp(-np.maximum(t - a, 0) / d)


def noise(n):
    return rng.standard_normal(n)


def save(name, x, peak=0.9):
    x = x / (np.abs(x).max() + 1e-9) * peak
    fade = min(len(x), int(0.01 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    wavfile.write(f"audio/sfx/{name}.wav", SR, (x * 32767).astype(np.int16))


def cannon():
    t = t_(2.2)
    n = len(t)
    boom = lp(noise(n), 160, 3) * env(t, 0.004, 0.35) * 6
    body = np.sin(2 * np.pi * (55 * t - 18 * t * t)) * env(t, 0.002, 0.28) * 1.4
    crack = hp(noise(n), 1800) * env(t, 0.0005, 0.03) * 1.6
    blast = bp(noise(n), 300, 2500) * env(t, 0.002, 0.12) * 1.2
    tail = lp(noise(n), 400) * env(t, 0.05, 0.8) * 0.5
    return np.tanh((boom + body + crack + blast + tail) * 1.4)


def explode():
    t = t_(1.6)
    n = len(t)
    x = lp(noise(n), 260, 3) * env(t, 0.003, 0.3) * 4
    x += bp(noise(n), 600, 4000) * env(t, 0.001, 0.08) * 1.5
    # 나무 파편 따닥따닥
    for k in range(18):
        t0 = rng.uniform(0.04, 0.7)
        i = int(t0 * SR)
        m = int(0.03 * SR)
        f = rng.uniform(900, 2600)
        tk = np.arange(m) / SR
        x[i:i + m] += np.sin(2 * np.pi * f * tk) * np.exp(-tk / 0.008) * rng.uniform(0.2, 0.6)
    return np.tanh(x * 1.3)


def whoosh(dur=0.9):
    t = t_(dur)
    n = len(t)
    sweep = np.zeros(n)
    x = noise(n)
    # 가운데 주파수가 위로 쓸려 올라갔다 내려옴
    seg = 400
    for i in range(0, n, seg):
        f = i / n
        fc = 300 + 2200 * np.sin(np.pi * f) ** 1.5
        sweep[i:i + seg] = bp(x[max(0, i - 2000):i + seg], fc * 0.6, fc * 1.4)[-len(sweep[i:i + seg]):]
    return sweep * np.sin(np.pi * t / dur) ** 1.2


def portal():
    t = t_(1.6)
    n = len(t)
    lfo = np.sin(2 * np.pi * 3.0 * t)
    drone = np.sin(2 * np.pi * (70 + 15 * lfo) * t) + 0.5 * np.sin(2 * np.pi * (140 + 30 * lfo) * t)
    swirl = bp(noise(n), 500, 1800) * (0.5 + 0.5 * np.sin(2 * np.pi * 6 * t))
    sparkle = np.zeros(n)
    for k in range(14):
        i = int(rng.uniform(0.1, 1.2) * SR)
        m = int(0.25 * SR)
        f = rng.uniform(1800, 3600)
        tk = np.arange(m) / SR
        sparkle[i:i + m] += np.sin(2 * np.pi * f * tk) * np.exp(-tk / 0.06) * 0.25
    e = env(t, 0.25, 0.9)
    return (drone * 0.8 + swirl * 0.6) * e + sparkle


def card_spin():
    t = t_(1.0)
    n = len(t)
    x = np.zeros(n)
    k = 0
    tt = 0.0
    while tt < 0.95:
        i = int(tt * SR)
        m = int(0.03 * SR)
        x[i:i + m] += hp(noise(m), 2500) * np.exp(-np.arange(m) / SR / 0.006)
        tt += 0.045 + 0.02 * k / 20
        k += 1
    return x + whoosh(1.0) * 0.4


def card_flip():
    t = t_(0.7)
    n = len(t)
    snap = hp(noise(n), 1500) * env(t, 0.0005, 0.02) * 1.4
    thump = lp(noise(n), 300) * env(t, 0.001, 0.04)
    shine = sum(np.sin(2 * np.pi * f * t) * env(t, 0.01 + j * 0.03, 0.25) for j, f in enumerate((1568, 2093, 2637))) * 0.25
    return snap + thump + shine


def coins():
    t = t_(1.4)
    n = len(t)
    x = np.zeros(n)
    for k in range(40):
        t0 = abs(rng.normal(0.15, 0.25))
        i = int(t0 * SR)
        if i >= n - 100:
            continue
        m = min(int(0.2 * SR), n - i)
        tk = np.arange(m) / SR
        f = rng.uniform(2800, 5200)
        ring = (np.sin(2 * np.pi * f * tk) + 0.6 * np.sin(2 * np.pi * f * 1.52 * tk)) * np.exp(-tk / 0.04)
        x[i:i + m] += ring * rng.uniform(0.15, 0.5)
    return x


def roar():
    t = t_(2.4)
    n = len(t)
    f0 = 48 + 10 * np.sin(2 * np.pi * 0.6 * t)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    growl = np.sign(np.sin(ph)) * 0.6 + np.sin(ph * 2) * 0.4
    growl *= 0.6 + 0.4 * (lp(noise(n), 30) * 8)
    growl = lp(growl, 700)
    breath = bp(noise(n), 200, 1200) * 0.5
    return (growl + breath) * env(t, 0.4, 1.2)


def thud():
    t = t_(0.5)
    n = len(t)
    x = np.sin(2 * np.pi * (90 * t - 40 * t * t)) * env(t, 0.002, 0.08) * 1.2
    x += lp(noise(n), 500) * env(t, 0.001, 0.05)
    x += bp(noise(n), 800, 2000) * env(t, 0.001, 0.015) * 0.6   # 나무 갑판
    return x


def creak():
    t = t_(0.9)
    n = len(t)
    f = 160 + 60 * np.sin(2 * np.pi * 1.1 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    # 끼이익: 빠르게 붙었다 떨어지는 마찰 (펄스열)
    pulses = (np.sin(ph) > 0.92).astype(float)
    x = bp(lfilter([1], [1, -0.97], pulses), 300, 2200)
    return x * np.sin(np.pi * t / 0.9) ** 0.8


def wind():
    dur = 8.0
    t = t_(dur)
    n = len(t)
    x = noise(n)
    # 천천히 일렁이는 바람 + 가끔 휘익 (반복해도 이음매 없게 앞뒤를 겹침)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / dur * 2) * np.sin(2 * np.pi * t / dur * 3 + 1.0)
    low = lp(x, 500) * 1.2
    high = bp(x, 900, 2400) * 0.35 * gust ** 2
    y = (low + high) * gust
    # 밧줄이 웅웅 (약하게)
    y += np.sin(2 * np.pi * 220 * t + 2 * np.sin(2 * np.pi * 0.3 * t)) * 0.02 * gust
    xf = int(0.5 * SR)
    y[:xf] = y[:xf] * np.linspace(0, 1, xf) + y[-xf:] * np.linspace(1, 0, xf)
    return y[:-xf]


for name, fn in [("cannon", cannon), ("explode", explode), ("whoosh", whoosh), ("portal", portal), ("card_spin", card_spin),
                 ("card_flip", card_flip), ("coins", coins), ("roar", roar), ("thud", thud), ("creak", creak)]:
    save(name, fn())
w = wind()
w = w / (np.abs(w).max() + 1e-9) * 0.8
wavfile.write("audio/sfx/wind.wav", SR, (w * 32767).astype(np.int16))
print("ok")
