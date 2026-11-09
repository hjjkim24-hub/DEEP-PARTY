"""DEEP PARTY 배경음악 + 효과음 만들기 (외부 소리 파일 없이 직접 합성).

    python make_audio.py          → ../audio/music/menu_theme.ogg, ../audio/sfx/*.wav
    (ffmpeg 가 있어야 ogg 로 저장, 없으면 wav)

음악: 116 BPM, F장조, 마림바 멜로디 + 칼림바 대선율 + 통통 튀는 베이스 + 엇박 건반
      + 가벼운 드럼 + 물방울 소리. 32마디가 끊김 없이 반복됩니다.
"""
import os
import shutil
import subprocess
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MUSIC_DIR = os.path.join(ROOT, "audio", "music")
SFX_DIR = os.path.join(ROOT, "audio", "sfx")
rng = np.random.default_rng(7)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def t_arr(dur):
    return np.arange(int(dur * SR)) / SR


def env_ad(n, a, d_tau):
    """빠른 어택 + 지수 감쇠."""
    t = np.arange(n) / SR
    e = np.exp(-t / d_tau)
    na = max(1, int(a * SR))
    e[:na] *= np.linspace(0, 1, na)
    return e


def lowpass(x, f, order=2):
    return sosfilt(butter(order, f, "low", fs=SR, output="sos"), x)


def highpass(x, f, order=2):
    return sosfilt(butter(order, f, "high", fs=SR, output="sos"), x)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


# ── 악기 ─────────────────────────────────────────────────────
def marimba(m, dur, vel=1.0):
    f = hz(m)
    n = int((dur + 0.6) * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) * env_ad(n, 0.002, 0.42)
    x += 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * env_ad(n, 0.001, 0.07)
    x += 0.12 * np.sin(2 * np.pi * f * 9.2 * t) * env_ad(n, 0.0005, 0.02)
    return x * vel


def kalimba(m, dur, vel=1.0):
    f = hz(m)
    n = int((dur + 0.8) * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t + 0.6 * np.sin(2 * np.pi * f * 5.4 * t) * env_ad(n, 0.0, 0.05))
    x *= env_ad(n, 0.002, 0.55)
    x += 0.2 * np.sin(2 * np.pi * f * 6.1 * t) * env_ad(n, 0.0, 0.03)
    return x * vel


def ep(m, dur, vel=1.0):
    """둥근 전자피아노(FM)."""
    f = hz(m)
    n = int((dur + 0.25) * SR)
    t = np.arange(n) / SR
    mod = 1.2 * np.sin(2 * np.pi * f * t) * env_ad(n, 0.0, 0.12)
    x = np.sin(2 * np.pi * f * t + mod)
    e = env_ad(n, 0.004, 0.35)
    rel = int(dur * SR)
    e[rel:] *= np.exp(-np.arange(n - rel) / SR / 0.06)
    return x * e * vel


def bass(m, dur, vel=1.0):
    f = hz(m)
    n = int((dur + 0.05) * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * 2 * f * t) + 0.08 * np.sin(2 * np.pi * 3 * f * t)
    e = env_ad(n, 0.005, 0.5)
    rel = int(dur * 0.9 * SR)
    e[rel:] *= np.exp(-np.arange(n - rel) / SR / 0.03)
    return np.tanh(1.3 * x) * e * vel


def pad(ms, dur, vel=1.0):
    n = int((dur + 0.4) * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for m in ms:
        for det in (-0.12, 0.12):
            f = hz(m + det)
            x += 2 / np.pi * np.arcsin(np.sin(2 * np.pi * f * t))  # 삼각파
    a = int(0.35 * SR)
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    rel = int(dur * SR)
    e[rel:] = np.linspace(1, 0, n - rel)
    return lowpass(x * e, 1400) * vel / len(ms)


def kick(vel=1.0):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t / 0.03)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env_ad(n, 0.001, 0.12) * vel


def clap(vel=1.0):
    n = int(0.25 * SR)
    noise = rng.standard_normal(n)
    e = np.zeros(n)
    for k, off in enumerate((0, 0.011, 0.022)):
        i = int(off * SR)
        e[i:] += np.exp(-np.arange(n - i) / SR / (0.012 if k < 2 else 0.09))
    return bandpass(noise * e, 900, 4500) * 0.5 * vel


def shaker(vel=1.0):
    n = int(0.08 * SR)
    return highpass(rng.standard_normal(n), 6000) * env_ad(n, 0.008, 0.025) * vel


def bubble(f0=500, dur=0.09, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 2.2 * (t / dur) ** 1.4)
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6 * np.exp(-t / (dur * 0.7))
    return np.sin(ph) * e * vel


# ── 곡 ───────────────────────────────────────────────────────
BPM = 116
BEAT = 60 / BPM
BAR = 4 * BEAT

CH = {
    "F": ([57, 60, 65], 41), "Dm": ([57, 62, 65], 38), "Bb": ([58, 62, 65], 46),
    "C": ([55, 60, 64], 48), "Am": ([57, 60, 64], 45), "Gm": ([55, 58, 62], 43),
    "C7": ([55, 58, 64], 48),
}
PROG_A = ["F", "Dm", "Bb", "C", "F", "Am", "Bb", "C"]
PROG_B = ["Bb", "C", "Am", "Dm", "Gm", "C", "F", "C7"]

MEL_A = [
    [(0, 1, 72), (1, .5, 69), (1.5, .5, 72), (2, 1, 77), (3, .5, 76), (3.5, .5, 74)],
    [(0, 1.5, 74), (1.5, .5, 72), (2, .5, 72), (2.5, .5, 74), (3, 1, 77)],
    [(0, 1, 74), (1, .5, 72), (1.5, .5, 70), (2, 1, 72), (3, 1, 74)],
    [(0, 1.5, 76), (1.5, .5, 74), (2, 2, 72)],
    [(0, 1, 72), (1, .5, 69), (1.5, .5, 72), (2, 1, 77), (3, .5, 76), (3.5, .5, 74)],
    [(0, 1, 76), (1, .5, 77), (1.5, .5, 76), (2, 1, 72), (3, 1, 69)],
    [(0, .5, 70), (.5, .5, 72), (1, .5, 74), (1.5, .5, 77), (2, 1, 79), (3, .5, 77), (3.5, .5, 76)],
    [(0, 1, 79), (1, 1, 76), (2, 2, 72)],
]
MEL_B = [
    [(0, 1.5, 77), (1.5, .5, 74), (2, 1, 70), (3, 1, 74)],
    [(0, 1.5, 76), (1.5, .5, 72), (2, 1, 67), (3, 1, 72)],
    [(0, 1, 72), (1, 1, 76), (2, 1, 81), (3, .5, 79), (3.5, .5, 76)],
    [(0, 2, 77), (2, 1, 74), (3, 1, 69)],
    [(0, 1, 70), (1, .5, 74), (1.5, .5, 77), (2, 1, 79), (3, 1, 74)],
    [(0, 1, 76), (1, .5, 79), (1.5, .5, 76), (2, 1, 72), (3, 1, 70)],
    [(0, 1, 69), (1, 1, 72), (2, 1, 77), (3, .5, 76), (3.5, .5, 77)],
    [(0, 1, 79), (1, 1, 76), (2, 1, 72), (3, 1, 67)],
]
# 칼림바 대선율: 2박마다 화음 음을 위에서 톡톡
SECTIONS = [("A", False), ("A", True), ("B", True), ("A", True)]


def render_music():
    bars = [(PROG_A if s == "A" else PROG_B, MEL_A if s == "A" else MEL_B, counter)
            for s, counter in SECTIONS]
    n_bars = 8 * len(bars)
    total = n_bars * BAR
    tail = 3.0
    N = int((total + tail) * SR)
    L = np.zeros(N)
    R = np.zeros(N)

    def put(sig, t0, pan=0.0, gain=1.0):
        i = int(t0 * SR)
        j = min(N, i + len(sig))
        g_l = gain * np.sqrt(0.5 * (1 - pan))
        g_r = gain * np.sqrt(0.5 * (1 + pan))
        L[i:j] += sig[:j - i] * g_l
        R[i:j] += sig[:j - i] * g_r

    bar_i = 0
    for prog, mel, counter in bars:
        for k in range(8):
            t0 = bar_i * BAR
            chord, root = CH[prog[k]]
            # 패드
            put(pad(chord, BAR), t0, 0.0, 0.16)
            # 엇박 건반
            for b in (0.5, 1.5, 2.5, 3.5):
                for m in chord:
                    put(ep(m, BEAT * 0.3, 0.9 if b in (1.5, 3.5) else 0.7), t0 + b * BEAT, -0.25, 0.07)
            # 베이스 (통통)
            fifth = root + 7 if root + 7 <= 52 else root - 5
            for b, m, d, v in ((0, root, 0.9, 1.0), (1.5, root, 0.4, 0.7), (2, fifth, 0.9, 0.9),
                               (3, root + 12, 0.4, 0.6), (3.5, root, 0.45, 0.75)):
                put(bass(m, d * BEAT, v), t0 + b * BEAT, 0.0, 0.32)
            # 드럼
            put(kick(), t0, 0, 0.55)
            put(kick(0.8), t0 + 2 * BEAT, 0, 0.55)
            if k % 2 == 1:
                put(kick(0.5), t0 + 3.5 * BEAT, 0, 0.5)
            put(clap(), t0 + 1 * BEAT, 0.1, 0.22)
            put(clap(), t0 + 3 * BEAT, 0.1, 0.22)
            for s in range(8):
                put(shaker(1.0 if s % 2 else 0.55), t0 + s * 0.5 * BEAT, 0.45, 0.10)
            # 멜로디 (마림바)
            for b, d, m in mel[k]:
                put(marimba(m, d * BEAT, 1.0), t0 + b * BEAT, 0.08, 0.30)
            # 대선율 (칼림바)
            if counter:
                ups = sorted(chord)
                for b, idx in ((0.75, 2), (1.75, 1), (2.75, 2), (3.75, 0)):
                    put(kalimba(ups[idx] + 12, 0.4 * BEAT, 0.8), t0 + b * BEAT, -0.5, 0.11)
            # 물방울
            if k % 2 == 0:
                for _ in range(2):
                    tb = t0 + rng.uniform(0, BAR)
                    put(bubble(rng.uniform(420, 900), rng.uniform(0.06, 0.12)), tb,
                        rng.uniform(-0.8, 0.8), 0.08)
            bar_i += 1

    # 리버브 (짧은 물속 울림, 좌우 다르게)
    ir_n = int(1.4 * SR)
    ti = np.arange(ir_n) / SR
    irL = rng.standard_normal(ir_n) * np.exp(-ti / 0.35)
    irR = rng.standard_normal(ir_n) * np.exp(-ti / 0.35)
    irL = lowpass(irL, 5000)
    irR = lowpass(irR, 5000)
    irL /= np.sqrt(np.sum(irL ** 2))
    irR /= np.sqrt(np.sum(irR ** 2))
    wetL = fftconvolve(L, irL)[:N]
    wetR = fftconvolve(R, irR)[:N]
    L = L + 0.22 * wetL
    R = R + 0.22 * wetR

    # 끊김 없는 반복: 끝에 남은 울림을 처음에 더함
    n_loop = int(total * SR)
    L[:N - n_loop] += L[n_loop:]
    R[:N - n_loop] += R[n_loop:]
    L, R = L[:n_loop], R[:n_loop]

    st = np.stack([L, R], axis=1)
    st = highpass(st.T, 30).T
    st /= np.max(np.abs(st)) + 1e-9
    st = np.tanh(st * 1.2) / np.tanh(1.2) * 0.6      # 약한 리미터 + 메뉴 음악이라 조금 작게
    return st, total


# ── 효과음 ───────────────────────────────────────────────────
def chirp(f0, f1, dur, shape=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 + (f1 - f0) * (t / dur) ** shape
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def bell(m, dur=0.5, bright=1.0):
    f = hz(m)
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t + bright * 1.5 * np.sin(2 * np.pi * f * 3.5 * t) * env_ad(n, 0, 0.06))
    return x * env_ad(n, 0.002, dur * 0.35)


def seq(parts, length):
    out = np.zeros(int(length * SR))
    for t0, sig, g in parts:
        i = int(t0 * SR)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[:j - i] * g
    return out


def pop(f0, f1, dur, vel=1.0):
    n = int(dur * SR)
    x = chirp(f0, f1, dur, 0.7) * env_ad(n, 0.002, dur * 0.35)
    return x * vel


SFX = {
    "hover": lambda: pop(1500, 2100, 0.05, 0.35),
    "click": lambda: seq([(0, pop(520, 1500, 0.075), 1.0), (0.02, bell(96, 0.15, 0.4), 0.18)], 0.2),
    "back": lambda: seq([(0, pop(1100, 420, 0.09), 1.0)], 0.14),
    "toggle_on": lambda: seq([(0, bell(84, 0.18, 0.5), 0.7), (0.06, bell(91, 0.25, 0.5), 0.7)], 0.35),
    "toggle_off": lambda: seq([(0, bell(91, 0.18, 0.5), 0.6), (0.06, bell(84, 0.25, 0.5), 0.6)], 0.35),
    "tick": lambda: pop(1900, 2300, 0.025, 0.5),
    "tab": lambda: seq([(0, kalimba(88, 0.15, 1.0)[:int(0.3 * SR)], 0.8)], 0.3),
    "color": lambda: seq([(0, bell(88, 0.35, 0.3), 0.7), (0.0, pop(700, 1300, 0.05), 0.4)], 0.4),
    "equip": lambda: seq([(0, pop(600, 1600, 0.07), 0.8)]
                         + [(0.05 + i * 0.055, bell(m, 0.3, 0.8), 0.45) for i, m in enumerate((89, 93, 96, 101))],
                         0.6),
    "unequip": lambda: seq([(0, pop(1300, 500, 0.1), 0.9), (0.06, bell(81, 0.2, 0.3), 0.3)], 0.3),
    "add": lambda: seq([(0, pop(380, 1200, 0.1), 1.0), (0.08, bell(84, 0.3, 0.5), 0.5),
                        (0.14, bell(91, 0.35, 0.5), 0.5)], 0.55),
    "remove": lambda: seq([(0, pop(1200, 330, 0.14), 1.0), (0.05, bubble(700, 0.07), 0.4)], 0.25),
    "start": lambda: seq([(i * 0.075, marimba(m, 0.2, 1.0), 0.6) for i, m in enumerate((72, 76, 79, 84))]
                         + [(0.3, bell(96, 0.6, 0.8), 0.35), (0.34, bell(103, 0.6, 0.8), 0.25)], 1.0),
    "toast": lambda: seq([(0, bell(88, 0.4, 0.4), 0.55), (0.1, bell(93, 0.5, 0.4), 0.55)], 0.65),
    "bubbles": lambda: seq([(i * 0.06 + rng.uniform(0, 0.03), bubble(rng.uniform(450, 900), 0.08), 0.6)
                            for i in range(6)], 0.5),
}


def write_wav(path, data, channels):
    data = np.clip(data, -1, 1)
    pcm = (data * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    os.makedirs(MUSIC_DIR, exist_ok=True)
    os.makedirs(SFX_DIR, exist_ok=True)

    music, length = render_music()
    wav_path = os.path.join(MUSIC_DIR, "menu_theme.wav")
    write_wav(wav_path, music, 2)
    if shutil.which("ffmpeg"):
        ogg = os.path.join(MUSIC_DIR, "menu_theme.ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "6", ogg],
                       check=True)
        os.remove(wav_path)
    print(f"music: {length:.1f}s loop")

    for name, fn in SFX.items():
        x = fn()
        x = highpass(x, 120)
        x = x / (np.max(np.abs(x)) + 1e-9) * 0.8
        fade = min(len(x), int(0.01 * SR))
        x[-fade:] *= np.linspace(1, 0, fade)
        write_wav(os.path.join(SFX_DIR, name + ".wav"), x, 1)
    print("sfx:", ", ".join(SFX))


if __name__ == "__main__":
    main()
