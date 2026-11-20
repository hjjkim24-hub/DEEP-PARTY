"""카드 · 오라 소리 → audio/sfx/
  card_draw.wav : 카드 더미에서 한 장 쓱 빼냄 (Kenney Casino Audio, CC0)
  card_pass.wav : 돌아가는 카드가 한 장씩 스치는 짧은 소리 (돌림판 틱 대신)
  aura.wav      : 오라가 피어오를 때 웅웅 — 낮은 화음이 맥박치듯 울렁이며 커졌다 사라짐 (합성)
쓰는 법: python3 tools/make_card_sfx.py <kenney 폴더>"""
import os
import subprocess
import sys
import numpy as np

SR = 44100
KN = sys.argv[1]
OUT = "audio/sfx"


def load(rel, af=""):
    cmd = ["ffmpeg", "-v", "quiet", "-i", os.path.join(KN, rel)]
    if af:
        cmd += ["-af", af]
    cmd += ["-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32).copy()


def save(name, x, peak_db=-1.0, fout=0.03):
    x = x / (np.abs(x).max() + 1e-9) * 10 ** (peak_db / 20)
    b = int(fout * SR)
    x[-b:] *= np.linspace(1, 0, b)
    st = np.stack([x, x], axis=1)
    pcm = (np.clip(st, -1, 1) * 32767).astype("<i2")
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    os.path.join(OUT, name + ".wav")], input=pcm.tobytes(), check=True)
    print("  sfx", name, round(len(x) / SR, 2))


def mix(parts):
    n = max(int(t * SR) + len(a) for a, t, g in parts)
    out = np.zeros(n, dtype=np.float32)
    for a, t, g in parts:
        s = int(t * SR)
        out[s:s + len(a)] += a * g
    return out


C = "kenney_casinoaudio/Audio/"
save("card_draw", mix([(load(C + "cardTakeOutPackage1.ogg"), 0.0, 0.8), (load(C + "cardSlide1.ogg"), 0.05, 1.0)]), -2)
save("card_pass", load(C + "cardShove1.ogg", "atrim=0:0.13"), -4, 0.04)

# 오라: 2.8 초
n = int(2.8 * SR)
t = np.arange(n) / SR
pulse = 0.62 + 0.38 * np.sin(2 * np.pi * 3.2 * t - np.pi / 2)          # 웅 · 웅 울렁임
tone = (np.sin(2 * np.pi * 62 * t) * 0.9 + np.sin(2 * np.pi * 124.6 * t) * 0.5
        + np.sin(2 * np.pi * 186.5 * t) * 0.28 + np.sin(2 * np.pi * 249 * t + 1.0) * 0.14)
tone += np.sin(2 * np.pi * 63.1 * t) * 0.5                              # 살짝 어긋난 음 → 맥놀이
rng = np.random.default_rng(5)
air = rng.standard_normal(n)
for _ in range(3):                                                       # 낮게 걸러 숨소리 같은 결
    air = np.convolve(air, np.ones(40) / 40, mode="same")
env = np.minimum(1.0, t / 0.35) * np.where(t > 1.7, np.exp(-(t - 1.7) / 0.45), 1.0)
aura = (tone * pulse + air * 6.0 * (0.5 + 0.5 * pulse)) * env
aura = np.tanh(aura * 1.4)
save("aura", aura, -2, 0.2)
