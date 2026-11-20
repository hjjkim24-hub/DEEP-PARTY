#!/usr/bin/env python3
"""DEEP PARTY 소리 만들기 — 무료(CC0 / 퍼블릭 도메인) 소리를 섞고 다듬어서 audio/ 에 넣음.

원본 (모두 상업적 사용 가능, 출처 표기 의무 없음 — audio/CREDITS.md 에 정리):
  • Kenney (kenney.nl) 오디오 팩 — CC0           : github.com/ETdoFresh/kenney.nl
  • 여러 CC0 효과음 팩 (rubberduck · Ben Burnes 등) : github.com/lavenderdotpet/CC0-Public-Domain-Sounds
  • FreePD.com 음악 — 퍼블릭 도메인                : github.com/SoundSafari/CC0-1.0-Music

쓰는 법:  python3 tools/build_audio.py <kenney 폴더> <lavender 폴더> <freepd 폴더>
"""
import os
import subprocess
import sys

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_OUT = os.path.join(ROOT, "audio", "sfx")
MUS_OUT = os.path.join(ROOT, "audio", "music")

KN, LV, FP = sys.argv[1], sys.argv[2], sys.argv[3]


def src(tag: str, rel: str) -> str:
    base = {"kn": KN, "lv": LV}[tag]
    return os.path.join(base, rel)


def load(path: str, pitch: float = 1.0, af: str = "") -> np.ndarray:
    """스테레오 float (n, 2). pitch < 1 이면 낮고 느리게 (테이프 늦추듯)."""
    filt = []
    if pitch != 1.0:
        filt.append(f"asetrate={int(SR * pitch)},aresample={SR}")
    if af:
        filt.append(af)
    cmd = ["ffmpeg", "-v", "quiet", "-i", path]
    if filt:
        cmd += ["-af", ",".join(filt)]
    cmd += ["-ac", "2", "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()
    return x


def mix(parts, length: float = 0.0) -> np.ndarray:
    """parts = [(소리, 시작 초, 음량배)]"""
    end = max(int(t * SR) + len(a) for a, t, g in parts)
    n = max(end, int(length * SR))
    out = np.zeros((n, 2), dtype=np.float32)
    for a, t, g in parts:
        s = int(t * SR)
        out[s:s + len(a)] += a * g
    return out


def trim(x: np.ndarray, thr: float = 0.004) -> np.ndarray:
    """앞뒤 무음 자르기"""
    amp = np.abs(x).max(axis=1)
    idx = np.where(amp > thr)[0]
    if len(idx) == 0:
        return x
    return x[max(0, idx[0] - 32): idx[-1] + 1]


def fade(x: np.ndarray, fin: float = 0.003, fout: float = 0.05) -> np.ndarray:
    x = x.copy()
    a = int(fin * SR)
    b = int(fout * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)[:, None]
    if b > 0 and b < len(x):
        x[-b:] *= np.linspace(1, 0, b)[:, None] ** 1.5
    return x


def norm(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    p = np.abs(x).max()
    if p < 1e-6:
        return x
    return x * (10 ** (peak_db / 20) / p)


def soft_clip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def save(name: str, x: np.ndarray, peak_db: float = -1.0, fout: float = 0.05, mono: bool = False) -> None:
    x = fade(trim(x), 0.002, fout)
    x = norm(x, peak_db)
    if mono:
        x = x.mean(axis=1, keepdims=True).repeat(2, axis=1)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    path = os.path.join(SFX_OUT, name + ".wav")
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-", path],
                   input=pcm.tobytes(), check=True)
    print(f"  sfx {name:16s} {len(x) / SR:5.2f}s")


def lowpass(x: np.ndarray, hz: float) -> np.ndarray:
    return _filt(x, f"lowpass=f={hz}")


def _filt(x: np.ndarray, af: str) -> np.ndarray:
    pcm = x.astype("<f4").tobytes()
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                          "-af", af, "-f", "f32le", "-"], input=pcm, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def reverb(x: np.ndarray, size: str = "big") -> np.ndarray:
    """간단한 잔향 (동굴 · 물속 느낌)"""
    if size == "big":
        af = "apad=pad_dur=1.6,aecho=0.8:0.7:60|130|260|420:0.45|0.35|0.25|0.18"
    elif size == "mid":
        af = "apad=pad_dur=0.6,aecho=0.8:0.6:40|90|170:0.35|0.25|0.15"
    else:
        af = "apad=pad_dur=0.3,aecho=0.8:0.5:25|55:0.25|0.12"
    return _filt(x, af)


def build_sfx() -> None:
    os.makedirs(SFX_OUT, exist_ok=True)
    K = lambda p, **k: load(src("kn", p), **k)
    L = lambda p, **k: load(src("lv", p), **k)

    # ── UI ──────────────────────────────────────────────
    save("hover", K("kenney_uiaudio/Audio/rollover2.ogg"), -6, 0.02)
    save("click", K("kenney_interfacesounds/Audio/click_002.ogg"), -2, 0.02)
    save("back", K("kenney_interfacesounds/Audio/back_002.ogg"), -2, 0.03)
    save("toggle_on", K("kenney_interfacesounds/Audio/toggle_002.ogg"), -2, 0.02)
    save("toggle_off", K("kenney_interfacesounds/Audio/toggle_001.ogg"), -2, 0.02)
    save("tick", K("kenney_interfacesounds/Audio/tick_002.ogg"), -3, 0.02)
    save("tab", K("kenney_interfacesounds/Audio/select_002.ogg"), -2, 0.03)
    save("color", K("kenney_interfacesounds/Audio/select_005.ogg"), -2, 0.03)
    save("equip", mix([(K("kenney_rpgaudio/Audio/clothBelt.ogg"), 0, 1.0),
                       (K("kenney_interfacesounds/Audio/confirmation_001.ogg"), 0.05, 0.5)]), -1, 0.05)
    save("unequip", K("kenney_rpgaudio/Audio/cloth2.ogg"), -2, 0.04)
    save("toast", K("kenney_interfacesounds/Audio/confirmation_002.ogg"), -2, 0.05)
    # 동전 얻음 / 잃음
    save("add", mix([(K("kenney_rpgaudio/Audio/handleCoins.ogg"), 0, 1.0),
                     (K("kenney_interfacesounds/Audio/confirmation_003.ogg"), 0.02, 0.35)]), -1, 0.05)
    save("remove", mix([(K("kenney_rpgaudio/Audio/handleCoins2.ogg", pitch=0.8), 0, 0.9),
                        (K("kenney_interfacesounds/Audio/error_004.ogg"), 0.0, 0.45)]), -1, 0.05)
    save("coins", soft_clip(norm(mix([(K("kenney_casinoaudio/Audio/chipsStack3.ogg"), 0, 0.8),
                       (K("kenney_rpgaudio/Audio/handleCoins2.ogg"), 0.08, 1.0),
                       (K("kenney_casinoaudio/Audio/chipsCollide2.ogg"), 0.22, 0.7)]), 0), 3.0), -1, 0.08)
    # 중요한 순간 (시작 · 결과 · 차례): 스틸드럼 짧은 징글 = 남쪽 바다 느낌
    save("start", K("kenney_musicjingles/Audio/Steel jingles/jingles_STEEL00.ogg"), -2, 0.15)

    # ── 주사위 · 카드 ──────────────────────────────────
    save("dice_shake", K("kenney_casinoaudio/Audio/dieShuffle2.ogg"), -3, 0.05)
    save("dice_land", mix([(K("kenney_casinoaudio/Audio/dieThrow2.ogg"), 0, 1.0),
                           (K("kenney_interfacesounds/Audio/confirmation_004.ogg"), 0.18, 0.12)]), -1, 0.08)
    save("card_spin", K("kenney_casinoaudio/Audio/cardFan1.ogg"), -3, 0.06)
    save("card_flip", mix([(K("kenney_casinoaudio/Audio/cardPlace2.ogg"), 0, 1.0),
                           (K("kenney_casinoaudio/Audio/cardSlide3.ogg"), 0.0, 0.5)]), -1, 0.05)

    # ── 상자 열기 (꾸미기) ─────────────────────────────
    save("box_rumble", mix([(K("kenney_impactsounds/Audio/impactWood_light_000.ogg"), 0.0, 0.8),
                            (K("kenney_impactsounds/Audio/impactWood_light_002.ogg"), 0.12, 0.7),
                            (K("kenney_impactsounds/Audio/impactWood_light_003.ogg"), 0.23, 0.8),
                            (K("kenney_impactsounds/Audio/impactWood_light_001.ogg"), 0.31, 0.6),
                            (K("kenney_impactsounds/Audio/impactWood_light_004.ogg"), 0.40, 0.9),
                            (K("kenney_rpgaudio/Audio/creak2.ogg"), 0.05, 0.5)]), -2, 0.1)
    save("box_burst", mix([(K("kenney_rpgaudio/Audio/doorOpen_1.ogg"), 0, 0.7),
                           (K("kenney_musicjingles/Audio/Pizzicato jingles/jingles_PIZZI10.ogg"), 0.05, 0.8),
                           (K("kenney_interfacesounds/Audio/glass_002.ogg"), 0.1, 0.5)]), -1, 0.2)
    save("box_whoosh", L("Micro Pack - Organic Wooshes/Swish 3.wav"), -2, 0.06)

    # ── 물 · 거품 ───────────────────────────────────────
    save("bubbles", mix([(L("40-cc0-water-splash-slime-sfx/bubble_01.ogg"), 0, 1.0),
                         (L("40-cc0-water-splash-slime-sfx/bubble_02.ogg"), 0.12, 0.7)]), -4, 0.08)
    save("splash", L("40-cc0-water-splash-slime-sfx/splash_04.ogg"), -2, 0.1)
    save("whoosh", L("Micro Pack - Organic Wooshes/Swish 1.wav"), -2, 0.06)

    # ── 배 · 대포 ───────────────────────────────────────
    cannon = mix([(L("25-CC0-bang-sfx/cannon_02.ogg"), 0, 1.0),
                  (L("25-CC0-bang-sfx/bang_03.ogg", pitch=0.7), 0, 0.8)])
    save("cannon", soft_clip(reverb(cannon, "mid"), 1.4), -0.5, 0.4)
    boom = mix([(L("100-CC0-SFX/explosion.ogg"), 0, 1.0),
                (L("25-CC0-bang-sfx/bang_10.ogg", pitch=0.75), 0, 0.8),
                (L("75-cc0-breaking-falling-hit-sfx/bfh1_wood_breaking_01.ogg"), 0.05, 0.7)])
    save("explode", soft_clip(norm(reverb(boom, "mid"), 0), 2.5), -0.5, 0.4)
    save("creak", K("kenney_rpgaudio/Audio/creak1.ogg"), -3, 0.08)
    save("thud", mix([(K("kenney_impactsounds/Audio/impactSoft_heavy_001.ogg"), 0, 1.0),
                      (K("kenney_impactsounds/Audio/impactPlank_medium_002.ogg"), 0, 0.5)]), -1, 0.06)
    save("portal", mix([(K("kenney_digitalaudio/Audio/phaserDown2.ogg", pitch=0.6), 0, 0.5),
                        (L("40-cc0-water-splash-slime-sfx/loop_bubbles_1.ogg", af="atrim=0:1.4"), 0, 0.9),
                        (L("Micro Pack - Organic Wooshes/Twirl 2.wav", pitch=0.8), 0.1, 0.8)]), -2, 0.4)

    # ── 크라켄 ──────────────────────────────────────────
    # 포효: 짐승 울음 여러 개를 아주 낮게 늘어뜨려 겹치고, 물속 동굴처럼 울리게
    roar = mix([(L("80-CC0-creature-sfx-2/roar_05.ogg", pitch=0.48), 0.0, 1.0),
                (L("80-CC0-creature-sfx-2/roar_04.ogg", pitch=0.42), 0.35, 0.9),
                (L("80-CC0-creature-SFX/monster_07.ogg", pitch=0.5), 0.15, 0.7),
                (L("80-CC0-creature-sfx-2/grunt_07.ogg", pitch=0.4), 0.0, 0.8),
                (L("80-CC0-creature-SFX/monster_04.ogg", pitch=0.55), 0.9, 0.7)])
    roar = lowpass(roar, 1800)
    roar = soft_clip(reverb(roar, "big"), 1.6)
    save("roar", roar, -0.5, 0.9)
    build_kraken()   # 포효는 여기서 더 무섭게 다시 만듦
    # 우르릉: 깊은 곳에서 땅이 울림 (폭발음을 아주 낮게 + 거품)
    rum = mix([(L("25-CC0-bang-sfx/bang_03.ogg", pitch=0.3), 0.0, 1.0),
               (L("25-CC0-bang-sfx/bang_10.ogg", pitch=0.28), 0.25, 0.9),
               (L("25-CC0-bang-sfx/cannon_02.ogg", pitch=0.25), 0.5, 0.7),
               (L("40-cc0-water-splash-slime-sfx/loop_bubbles_02.ogg", pitch=0.6, af="atrim=0:2.5"), 0.2, 0.35)])
    rum = lowpass(rum, 600)
    save("kraken_rumble", soft_clip(reverb(rum, "big"), 1.8)[: int(3.6 * SR)], -1.0, 1.2)
    # 촉수 내려침: 무거운 충격 + 물 튀김 + 돌 깨짐
    slam = mix([(L("25-CC0-bang-sfx/bang_03.ogg", pitch=0.55), 0.0, 1.0),
                (K("kenney_impactsounds/Audio/impactPunch_heavy_002.ogg", pitch=0.6), 0.0, 0.9),
                (L("40-cc0-water-splash-slime-sfx/splash_11.ogg", pitch=0.75), 0.02, 0.8),
                (L("75-cc0-breaking-falling-hit-sfx/bfh1_rock_breaking_02.ogg"), 0.04, 0.6)])
    save("kraken_slam", soft_clip(reverb(slam, "mid"), 1.5), -0.5, 0.5)
    # 촉수 솟구침: 물을 가르는 쉭
    rise = mix([(L("Micro Pack - Organic Wooshes/Swish 5.wav", pitch=0.6), 0.0, 1.0),
                (L("Micro Pack - Organic Wooshes/Swish 2.wav", pitch=0.5), 0.05, 0.8),
                (L("40-cc0-water-splash-slime-sfx/splash_07.ogg", pitch=0.7, af="atrim=0:0.6"), 0.0, 0.35)])
    rise = soft_clip(norm(trim(rise), -1), 2.0)[: int(1.0 * SR)]
    save("kraken_rise", rise, -1, 0.25)


def build_kraken() -> None:
    """크라켄 등장: 귀엽지 않게 — 더 낮고 거대한 포효 + 웅장하고 어두운 등장 음악"""
    L = lambda p, **k: load(src("lv", p), **k)
    # 포효: 짐승 울음을 훨씬 낮게 + 몸통이 울리는 저음 그르렁(직접 합성). 짧고 귀여운 grunt 는 뺌
    n = int(4.2 * SR)
    t = np.arange(n) / SR
    f0 = 44.0 - 8.0 * (t / t[-1])
    ph = 2 * np.pi * np.cumsum(f0) / SR
    growl = sum(np.sin(ph * h + h * 0.7) / h for h in range(1, 14))
    rough = 0.65 + 0.35 * np.sin(2 * np.pi * 9.0 * t + 1.5 * np.sin(2 * np.pi * 2.3 * t))
    env = np.minimum(1.0, t / 0.45) * np.where(t > 2.4, np.exp(-(t - 2.4) / 0.6), 1.0)
    rng = np.random.default_rng(3)
    noise = np.cumsum(rng.standard_normal(n)) * 0.002
    noise -= np.convolve(noise, np.ones(2205) / 2205, mode="same")
    body = (growl * rough * 0.5 + noise * 4.0) * env
    body = np.stack([body, body * 0.96], axis=1).astype(np.float32)
    body = lowpass(body, 320)
    roar = mix([(L("80-CC0-creature-sfx-2/roar_05.ogg", pitch=0.34), 0.05, 1.0),
                (L("80-CC0-creature-sfx-2/roar_04.ogg", pitch=0.30), 0.3, 0.85),
                (L("80-CC0-creature-SFX/monster_07.ogg", pitch=0.36), 0.15, 0.6),
                (body, 0.0, 1.1)])
    roar = lowpass(roar, 1100)
    roar = soft_clip(reverb(roar, "big"), 1.8)
    save("roar", roar, -0.5, 1.2)

    # 등장 음악: 웅장한 보스곡 앞부분. 처음엔 물속처럼 먹먹하다가(저역만) 포효·내려침에 맞춰 활짝 열림
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", os.path.join(FP, "Epic Boss Battle.mp3"), "-t", "26",
                          "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()
    m = len(x)
    tt = np.arange(m) / SR
    cut = np.where(tt < 0.4, 180.0, np.where(tt > 5.4, 16000.0, 180.0 * (16000.0 / 180.0) ** ((tt - 0.4) / 5.0)))
    a = 1.0 - np.exp(-2 * np.pi * cut / SR)
    y = np.zeros_like(x)
    z1 = np.zeros(2, dtype=np.float32)
    z2 = np.zeros(2, dtype=np.float32)
    for i in range(m):   # 2단 단극 저역 통과 (주파수가 시간에 따라 올라감)
        z1 += a[i] * (x[i] - z1)
        z2 += a[i] * (z1 - z2)
        y[i] = z2
    gain = np.clip(0.55 + 0.45 * (tt - 0.4) / 5.0, 0.55, 1.0)
    y *= gain[:, None]
    fo = int(5.0 * SR)
    y[-fo:] *= (np.linspace(1, 0, fo) ** 1.6)[:, None]
    y[: int(0.3 * SR)] *= np.linspace(0, 1, int(0.3 * SR))[:, None]
    tmp = os.path.join(MUS_OUT, "_kw.f32")
    y.astype("<f4").tofile(tmp)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", tmp,
                    "-af", "loudnorm=I=-14:TP=-1.0:LRA=11", "-ar", str(SR), "-c:a", "libvorbis", "-q:a", "5",
                    os.path.join(MUS_OUT, "kraken_wake.ogg")], check=True)
    os.remove(tmp)
    print("  music kraken_wake  ← Epic Boss Battle (26s, filter sweep)")


def build_music() -> None:
    """FreePD 곡을 ogg 로: 앞 무음 자르고 음량 고르게 (-16 LUFS)"""
    os.makedirs(MUS_OUT, exist_ok=True)
    tracks = {
        "menu_theme": "Land of Pirates",
        "board_theme": "Aquatic City Vanished",
        "ship_theme": "Evil Incoming",
        "mg_intro": "Busybody",
        "mg_a": "Going Bananas",
        "mg_c": "Wakka Wakka",
        "mg_d": "Gotta Keep On Movin",
        "mg_e": "Funshine",
        "mg_f": "Adventures of Flying Jack",
        "results": "Fanfare X",
        "mg_hall": "Lucky Break",
        # 미니게임마다 고유한 곡 (분위기에 맞춰)
        "mg_tentacle_dodge": "Action Strike",
        "mg_cannon_volley": "Heroic Adventure",
        "mg_treasure_dive": "The Lagoon",
        "mg_chest_shuffle": "Managing Mischief",
        "mg_tentacle_tug": "Hit n Smash",
        "mg_powder_keg": "Night Attack",
        "mg_anchor_drop": "Windy Old Weather",
        "mg_ink_paint": "Funky Energy Loop",
        "mg_clam_snatch": "Neptunian Princess",
    }
    only = os.environ.get("ONLY", "")
    if only:
        tracks = {k: v for k, v in tracks.items() if k.startswith(only)}
    for out, name in tracks.items():
        path = os.path.join(MUS_OUT, out + ".ogg")
        subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-i", os.path.join(FP, name + ".mp3"),
                        "-af", "silenceremove=start_periods=1:start_threshold=-50dB,loudnorm=I=-16:TP=-1.5:LRA=11",
                        "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", path], check=True)
        print(f"  music {out:12s} ← {name}")


if __name__ == "__main__":
    if os.environ.get("KRAKEN_ONLY"):
        build_kraken()
        sys.exit(0)
    build_sfx()
    build_music()
