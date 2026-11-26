"""미니게임 시작 · 종료 소리 (합성) → audio/sfx/
  mg_start.wav : "게임 시작!" — 놋쇠 배 종 '땡-땡' 두 번 + 낮은 북 한 방 + 갑판 위 울림
  mg_end.wav   : "게임 종료!" — 뱃고동 같은 낮은 금관 두 음(내려가며 마무리) + 마지막 음에 배 종 한 번 + 북 + 울림"""
import os
import subprocess
import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt

SR = 44100
OUT = "audio/sfx"
rng = np.random.default_rng(41)


def save(name, x, peak_db=-1.0):
    x = x / (np.abs(x).max() + 1e-9) * 10 ** (peak_db / 20)
    fo = int(0.6 * SR)   # 끝은 부드럽게 사그라듦 (뚝 끊기지 않게)
    x[-fo:] *= np.linspace(1, 0, fo) ** 2
    st = np.stack([x, x], axis=1)
    pcm = (np.clip(st, -1, 1) * 32767).astype("<i2")
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    os.path.join(OUT, name + ".wav")], input=pcm.tobytes(), check=True)
    print("  sfx", name, round(len(x) / SR, 2))


def filt(x, kind, hz, order=2):
    sos = butter(order, hz, btype=kind, fs=SR, output="sos")
    return sosfilt(sos, x)


def t_of(sec):
    return np.arange(int(sec * SR)) / SR


def place(buf, x, at):
    i = int(at * SR)
    j = min(len(buf), i + len(x))
    buf[i:j] += x[: j - i]


def bell(strike=560.0, dur=2.6, amp=1.0):
    """놋쇠 배 종: 비화성 부분음(험 · 프라임 · 단3도 · 5도 · 노미널 · 위쪽)이 각자 다르게 사그라듦 + 치는 순간 쇳소리"""
    t = t_of(dur)
    parts = [(0.5, 0.55, 2.2), (1.0, 1.0, 1.3), (1.19, 0.5, 1.0), (1.5, 0.35, 0.8), (2.0, 0.6, 0.7),
             (2.63, 0.3, 0.45), (3.01, 0.22, 0.35), (4.1, 0.12, 0.22), (5.4, 0.08, 0.15)]
    y = np.zeros_like(t)
    for ratio, a, dec in parts:
        f = strike * ratio * (1.0 + rng.uniform(-0.002, 0.002))
        beat = 1.0 + 0.04 * np.sin(2 * np.pi * rng.uniform(1.0, 3.0) * t)   # 살짝 웅웅 맥놀이
        y += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / dec) * beat
    y *= np.clip((dur - t) / 0.5, 0, 1)
    click = filt(rng.normal(0, 1, len(t)), "bandpass", [2500, 9000]) * np.exp(-t / 0.006) * 0.9
    y = y * (1 - np.exp(-t / 0.002)) + click
    return y * amp


def drum(f0=62.0, dur=1.2, amp=1.0):
    """큰 북: 처음엔 음이 조금 높았다 내려앉음 + 가죽 치는 소리"""
    t = t_of(dur)
    f = f0 * (1 + 0.6 * np.exp(-t / 0.05))
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.35) + 0.4 * np.sin(ph * 1.6) * np.exp(-t / 0.18)
    skin = filt(rng.normal(0, 1, len(t)), "bandpass", [120, 1800]) * np.exp(-t / 0.03) * 0.7
    return (body + skin) * amp


def horn(f0, dur, amp=1.0, swell=0.1, rel=0.25):
    """금관 뱃고동: 배음 많은 톱니 소리를 저역으로 걸러 둥글게, 숨결 · 떨림 조금"""
    t = t_of(dur)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.15) / 0.3, 0, 1)
    f = f0 * vib * (1 - 0.012 * np.exp(-t / 0.06))   # 처음 살짝 아래에서 올라붙음
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.zeros_like(t)
    for k in range(1, 24):
        y += np.sin(ph * k) / k ** 1.15
    bright = np.clip(t / swell, 0, 1)   # 불기 시작하면 점점 밝아짐
    y = filt(y, "lowpass", 900) * (0.6 + 0.4 * bright) + filt(y, "lowpass", 2600) * 0.25 * bright
    breath = filt(rng.normal(0, 1, len(t)), "bandpass", [600, 3000]) * 0.03
    env = np.clip(t / swell, 0, 1) ** 1.5 * np.clip((dur - t) / rel, 0, 1)
    return (y + breath) * env * amp


def room(x, sec=1.4, wet=0.28, damp=3500):
    """나무 갑판 · 바다 위 울림: 지수로 사그라드는 잡음 IR"""
    t = t_of(sec)
    ir = rng.normal(0, 1, len(t)) * np.exp(-t / (sec / 5.5))
    ir = filt(ir, "lowpass", damp)
    ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    w = fftconvolve(x, ir)[: len(x)]
    w /= np.abs(w).max() + 1e-9
    return x / (np.abs(x).max() + 1e-9) + w * wet


# 게임 시작: 땡-땡 + 북
n = int(2.6 * SR)
s = np.zeros(n)
place(s, drum(64, 1.2, 0.85), 0.0)
place(s, bell(600, 2.2, 1.0), 0.0)
place(s, bell(600, 2.0, 0.85), 0.2)
s = filt(s, "highpass", 40)
save("mg_start", room(s, 1.3, 0.3))

# 게임 종료: 금관 두 음 (A2+E3 → D2+A2) · 마지막 음에 종 · 북
n = int(3.2 * SR)
e = np.zeros(n)
place(e, horn(110.0, 0.42, 0.8, 0.07, 0.1), 0.0)
place(e, horn(164.8, 0.42, 0.45, 0.07, 0.1), 0.0)
place(e, horn(73.4, 1.9, 1.0, 0.09, 0.9), 0.42)
place(e, horn(110.0, 1.9, 0.55, 0.09, 0.9), 0.42)
place(e, horn(146.8, 1.9, 0.25, 0.12, 0.9), 0.42)
place(e, drum(55, 1.4, 1.0), 0.42)
place(e, bell(470, 2.6, 0.55), 0.44)
e = filt(e, "highpass", 35)
save("mg_end", room(e, 1.8, 0.32))
