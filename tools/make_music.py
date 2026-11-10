"""게임 안 배경음악 (보드 · 미니게임 설명 화면 · 미니게임 4종). 외부 파일 없이 직접 합성.

    python make_music.py            → ../audio/music/*.ogg
    python make_music.py board      → 한 곡만

곡마다 끊김 없이 반복되도록 끝의 울림을 앞에 더해요. 악기 기본은 make_audio.py 를 같이 씀.
"""
import os
import shutil
import subprocess
import sys

import numpy as np
from scipy.signal import fftconvolve

from make_audio import (SR, MUSIC_DIR, bass, bell, bubble, clap, env_ad, ep, highpass, hz, kalimba, kick,
                        lowpass, bandpass, marimba, pad, shaker, write_wav)

rng = np.random.default_rng(11)


# ── 새 악기 ──────────────────────────────────────────────────
def pluck(m, dur, vel=1.0, bright=1.0, decay=0.25):
    """짧게 튕기는 현 (톱니파 배음이 빨리 어두워짐)"""
    f = hz(m)
    n = int((dur + decay * 1.5) * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(1, 14):
        if f * k > 15000:
            break
        x += np.sin(2 * np.pi * f * k * t) / k * np.exp(-t * k * 6.0 / bright)
    e = env_ad(n, 0.002, decay)
    rel = int(dur * SR)
    if rel < n:
        e[rel:] *= np.exp(-np.arange(n - rel) / SR / 0.04)
    return x * e * vel * 0.8


def pizz(m, vel=1.0):
    """피치카토 (짧고 통통)"""
    return pluck(m, 0.12, vel, 0.6, 0.12)


def lead(m, dur, vel=1.0, vib=1.0):
    """네모파 리드 (홀수 배음) + 비브라토"""
    f = hz(m)
    n = int((dur + 0.08) * SR)
    t = np.arange(n) / SR
    v = 1 + 0.006 * vib * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.15, 0, 1)
    ph = 2 * np.pi * f * np.cumsum(v) / SR
    x = np.zeros(n)
    for k in (1, 3, 5, 7, 9):
        x += np.sin(k * ph) / k
    e = np.ones(n)
    a = int(0.006 * SR)
    e[:a] = np.linspace(0, 1, a)
    e *= 0.75 + 0.25 * np.exp(-t / 0.12)
    rel = int(dur * SR)
    e[rel:] *= np.exp(-np.arange(n - rel) / SR / 0.025)
    return lowpass(x * e, 3800) * vel * 0.6


def stab(ms, dur=0.18, vel=1.0):
    """여러 음 톱니파를 살짝 어긋나게 → 짧은 금관 느낌"""
    n = int((dur + 0.12) * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for m in ms:
        for det in (-0.08, 0.08):
            f = hz(m + det)
            for k in range(1, 9):
                x += np.sin(2 * np.pi * f * k * t) / k
    e = env_ad(n, 0.004, 0.16)
    return lowpass(x * e, 2600) * vel / len(ms) * 0.5


def sub(m, dur, vel=1.0):
    f = hz(m)
    n = int((dur + 0.03) * SR)
    t = np.arange(n) / SR
    x = np.tanh(1.6 * np.sin(2 * np.pi * f * t))
    e = env_ad(n, 0.003, 0.3)
    rel = int(dur * 0.92 * SR)
    e[rel:] *= np.exp(-np.arange(n - rel) / SR / 0.02)
    return x * e * vel


def hat(vel=1.0, open_=False):
    n = int((0.25 if open_ else 0.05) * SR)
    return highpass(rng.standard_normal(n), 7500) * env_ad(n, 0.001, 0.09 if open_ else 0.014) * vel


def snare(vel=1.0):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * t) * env_ad(n, 0.001, 0.05)
    noise = bandpass(rng.standard_normal(n), 1500, 7000) * env_ad(n, 0.001, 0.07)
    return (body * 0.6 + noise * 0.8) * vel


def tom(m, vel=1.0):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = hz(m) * (1 + 0.6 * np.exp(-t / 0.04))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.001, 0.14) * vel


def tick(high=True, vel=1.0):
    """시계 째깍 (나무 소리)"""
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    f = 2600 if high else 1900
    x = np.sin(2 * np.pi * f * t) * env_ad(n, 0.0005, 0.008)
    x += bandpass(rng.standard_normal(n), 2000, 6000) * env_ad(n, 0.0005, 0.004) * 0.5
    return x * vel


def snap(vel=1.0):
    n = int(0.12 * SR)
    return bandpass(rng.standard_normal(n), 1800, 6500) * env_ad(n, 0.0008, 0.018) * vel


def crash(vel=1.0):
    n = int(1.4 * SR)
    return highpass(rng.standard_normal(n), 5000) * env_ad(n, 0.002, 0.5) * vel


# ── 곡 틀 ────────────────────────────────────────────────────
class Track:
    def __init__(self, bpm, bars, swing=0.0, tail=3.0):
        self.beat = 60.0 / bpm
        self.bar = 4 * self.beat
        self.total = bars * self.bar
        self.swing = swing
        self.N = int((self.total + tail) * SR)
        self.L = np.zeros(self.N)
        self.R = np.zeros(self.N)

    def t(self, bar, beat):
        """마디·박 → 초 (스윙: 8분 엇박을 뒤로 밀기)"""
        frac = beat % 1.0
        if self.swing and abs(frac - 0.5) < 1e-6:
            beat += self.swing
        return bar * self.bar + beat * self.beat

    def put(self, sig, t0, pan=0.0, gain=1.0):
        i = int(t0 * SR)
        if i >= self.N:
            return
        j = min(self.N, i + len(sig))
        self.L[i:j] += sig[:j - i] * gain * np.sqrt(0.5 * (1 - pan))
        self.R[i:j] += sig[:j - i] * gain * np.sqrt(0.5 * (1 + pan))

    def finish(self, wet=0.2, room=0.35, level=0.75):
        ir_n = int(1.6 * SR)
        ti = np.arange(ir_n) / SR
        irs = []
        for _ in range(2):
            ir = rng.standard_normal(ir_n) * np.exp(-ti / room)
            ir = lowpass(ir, 6000)
            irs.append(ir / np.sqrt(np.sum(ir ** 2)))
        L = self.L + wet * fftconvolve(self.L, irs[0])[:self.N]
        R = self.R + wet * fftconvolve(self.R, irs[1])[:self.N]
        n_loop = int(self.total * SR)
        L[:self.N - n_loop] += L[n_loop:]
        R[:self.N - n_loop] += R[n_loop:]
        st = np.stack([L[:n_loop], R[:n_loop]], axis=1)
        st = highpass(st.T, 30).T
        st /= np.max(np.abs(st)) + 1e-9
        return np.tanh(st * 1.5) / np.tanh(1.5) * level


def mel(tr, bar, notes, inst, pan=0.0, gain=1.0, octave=0):
    for b, d, m in notes:
        tr.put(inst(m + octave, d * tr.beat), tr.t(bar, b), pan, gain)


# ── 1. 보드: 긴박하고 재밌게 (D단조 132) ─────────────────────
def song_board():
    tr = Track(132, 32)
    CH = {"Dm": ([62, 65, 69], 38), "Bb": ([58, 62, 65], 46), "F": ([60, 65, 69], 41), "C": ([60, 64, 67], 36),
          "Gm": ([58, 62, 67], 43), "A": ([61, 64, 69], 45), "A7": ([61, 67, 69], 45), "E": ([59, 64, 68], 40)}
    A = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"]
    B = ["Gm", "Dm", "Bb", "A", "Gm", "Dm", "Bb", "A7"]
    MA = [
        [(0, .5, 74), (.75, .25, 74), (1, .5, 77), (1.5, .5, 76), (2, .5, 74), (2.5, .5, 72), (3, 1, 69)],
        [(0, .5, 70), (.5, .5, 74), (1, .5, 77), (1.5, .5, 74), (2, 1, 79), (3, .5, 77), (3.5, .5, 74)],
        [(0, .5, 72), (.75, .25, 72), (1, .5, 77), (1.5, .5, 76), (2, .5, 77), (2.5, .5, 79), (3, 1, 81)],
        [(0, .5, 79), (.5, .5, 77), (1, .5, 76), (1.5, .5, 72), (2, 2, 76)],
        [(0, .5, 74), (.75, .25, 74), (1, .5, 77), (1.5, .5, 76), (2, .5, 74), (2.5, .5, 72), (3, 1, 69)],
        [(0, .5, 70), (.5, .5, 74), (1, .5, 77), (1.5, .5, 81), (2, 1, 82), (3, .5, 81), (3.5, .5, 79)],
        [(0, .5, 79), (.5, .5, 77), (1, .5, 74), (1.5, .5, 70), (2, .5, 74), (2.5, .5, 77), (3, 1, 79)],
        [(0, 1, 81), (1, .5, 79), (1.5, .5, 77), (2, .5, 76), (2.5, .5, 73), (3, 1, 76)],
    ]
    MB = [
        [(0, 1.5, 79), (1.5, .5, 77), (2, 1, 74), (3, 1, 70)],
        [(0, 1.5, 77), (1.5, .5, 76), (2, 1, 74), (3, 1, 69)],
        [(0, .5, 70), (.5, .5, 72), (1, .5, 74), (1.5, .5, 77), (2, 1, 82), (3, 1, 81)],
        [(0, 1, 79), (1, 1, 76), (2, 2, 73)],
        [(0, .5, 79), (.5, .5, 79), (1, .5, 82), (1.5, .5, 81), (2, .5, 79), (2.5, .5, 77), (3, 1, 74)],
        [(0, .5, 77), (.5, .5, 77), (1, .5, 81), (1.5, .5, 79), (2, .5, 77), (2.5, .5, 76), (3, 1, 74)],
        [(0, 1, 74), (1, 1, 77), (2, 1, 82), (3, .5, 81), (3.5, .5, 79)],
        [(0, 1, 81), (1, .5, 79), (1.5, .5, 76), (2, 1, 73), (3, 1, 69)],
    ]
    sections = [(A, MA, False), (A, MA, True), (B, MB, True), (A, MA, True)]
    bar = 0
    for prog, melody, full in sections:
        for k in range(8):
            chord, root = CH[prog[k]]
            # 베이스: 8분음표로 쿵쿵 (옥타브 왔다 갔다)
            for s in range(8):
                m = root + (12 if s in (3, 6) else 0)
                tr.put(pluck(m, 0.45 * tr.beat, 1.0, 0.7, 0.18), tr.t(bar, s * 0.5), 0.0, 0.42)
            # 현 스타카토: 16분음표 화음 오르내림
            arp = chord + [chord[1] + 12]
            for s in range(16):
                m = arp[[0, 1, 2, 3, 2, 1, 2, 3][s % 8]]
                tr.put(pluck(m, 0.18 * tr.beat, 0.9 if s % 4 == 0 else 0.6, 1.3, 0.12), tr.t(bar, s * 0.25), -0.35, 0.12)
            tr.put(pad(chord, tr.bar), tr.t(bar, 0), 0.25, 0.08)
            # 드럼
            for b in (0, 2):
                tr.put(kick(), tr.t(bar, b), 0, 0.6)
            tr.put(kick(0.7), tr.t(bar, 2.75), 0, 0.5)
            for b in (1, 3):
                tr.put(snare(), tr.t(bar, b), 0.05, 0.32)
            for s in range(16):
                tr.put(hat(1.0 if s % 2 == 0 else 0.55), tr.t(bar, s * 0.25), 0.4, 0.1)
            if k == 7:
                for i, m in enumerate((50, 47, 45, 43)):
                    tr.put(tom(m), tr.t(bar, 3 + i * 0.25), -0.3 + i * 0.2, 0.35)
            if k == 0:
                tr.put(crash(), tr.t(bar, 0), 0.3, 0.12)
                tr.put(stab([c + 12 for c in chord]), tr.t(bar, 0), 0.0, 0.25)
            # 멜로디: 처음 8마디는 마림바만, 그 뒤는 리드 + 마림바
            mel(tr, bar, melody[k], lambda m, d: marimba(m, d, 1.0), 0.1, 0.32)
            if full:
                mel(tr, bar, melody[k], lambda m, d: lead(m, d * 0.9, 1.0), -0.1, 0.16)
            bar += 1
    return tr.finish(0.18, 0.3, 0.72)


# ── 2. 미니게임 설명 화면: 궁금궁금 (C 리디안 96) ─────────────
def song_mg_intro():
    tr = Track(96, 16)
    prog = [([60, 64, 67, 71], 36), ([62, 66, 69, 72], 38), ([64, 67, 71, 74], 40), ([57, 60, 64, 67], 45)] * 4
    motif = [(0, .5, 79), (.5, .5, 83), (1, 1, 81), (2.5, .5, 78), (3, 1, 76)]
    for bar, (chord, root) in enumerate(prog):
        tr.put(pad(chord, tr.bar), tr.t(bar, 0), 0.0, 0.14)
        tr.put(bass(root, 1.6 * tr.beat, 0.8), tr.t(bar, 0), 0, 0.3)
        tr.put(bass(root + 7, 0.8 * tr.beat, 0.6), tr.t(bar, 2.5), 0, 0.22)
        for s in range(8):
            m = chord[[0, 2, 1, 3, 2, 0, 3, 1][s]] + 12
            tr.put(kalimba(m, 0.4 * tr.beat, 0.8 if s % 2 == 0 else 0.55), tr.t(bar, s * 0.5), -0.4 + 0.1 * s, 0.14)
        for s in range(8):
            tr.put(shaker(1.0 if s % 2 else 0.5), tr.t(bar, s * 0.5), 0.5, 0.07)
        if bar % 2 == 0:
            tr.put(kick(0.6), tr.t(bar, 0), 0, 0.35)
        tr.put(snap(0.8), tr.t(bar, 1), 0.2, 0.18)
        tr.put(snap(0.8), tr.t(bar, 3), 0.2, 0.18)
        if bar % 4 in (1, 3):
            mel(tr, bar, motif, lambda m, d: bell(m, d + 0.6, 0.7), 0.3, 0.18)
        if bar % 4 == 2:
            for i in range(3):
                tr.put(bubble(rng.uniform(500, 900), 0.09), tr.t(bar, rng.uniform(0, 4)), rng.uniform(-0.7, 0.7), 0.1)
    return tr.finish(0.3, 0.45, 0.62)


# ── 3. 진주 팡팡: 통통 신나게 (G장조 150) ─────────────────────
def song_pearl_pop():
    tr = Track(150, 32)
    CH = [([67, 71, 74], 43), ([64, 67, 71], 40), ([60, 64, 67], 36), ([62, 66, 69], 38)]
    M = [
        [(0, .5, 79), (.5, .5, 83), (1, .5, 86), (1.5, .5, 83), (2, .5, 81), (2.5, .5, 79), (3, 1, 76)],
        [(0, .5, 76), (.5, .5, 79), (1, .5, 83), (1.5, .5, 79), (2, 1, 81), (3, 1, 79)],
        [(0, .5, 76), (.5, .5, 79), (1, .5, 84), (1.5, .5, 83), (2, .5, 81), (2.5, .5, 79), (3, 1, 76)],
        [(0, .5, 78), (.5, .5, 81), (1, .5, 86), (1.5, .5, 84), (2, 1, 83), (3, .5, 81), (3.5, .5, 78)],
    ]
    for bar in range(32):
        chord, root = CH[bar % 4]
        sec = bar // 8
        for b in range(4):
            tr.put(kick(), tr.t(bar, b), 0, 0.55)
            tr.put(bass(root + (12 if b % 2 else 0), 0.4 * tr.beat, 0.9), tr.t(bar, b + 0.5), 0, 0.3)
        tr.put(clap(), tr.t(bar, 1), 0.1, 0.25)
        tr.put(clap(), tr.t(bar, 3), 0.1, 0.25)
        for s in range(8):
            tr.put(hat(0.8 if s % 2 else 0.4), tr.t(bar, s * 0.5), 0.4, 0.09)
        for b in (0.5, 1.5, 2.5, 3.5):
            for m in chord:
                tr.put(ep(m, 0.25 * tr.beat, 0.8), tr.t(bar, b), -0.3, 0.06)
        if sec >= 1:
            mel(tr, bar, M[bar % 4], lambda m, d: marimba(m, d, 1.0), 0.1, 0.32, 12 if sec == 3 else 0)
        if sec >= 2:
            mel(tr, bar, M[bar % 4], lambda m, d: kalimba(m - 12, d, 0.8), -0.4, 0.12)
        for i in range(2):
            tr.put(bubble(rng.uniform(450, 1000), 0.08), tr.t(bar, rng.integers(0, 8) * 0.5 + 0.25), rng.uniform(-0.8, 0.8), 0.14)
    return tr.finish(0.15, 0.3, 0.72)


# ── 4. 딱 멈춰!: 째깍째깍 긴장감 (A단조 120) ───────────────────
def song_timing_stop():
    tr = Track(120, 16)
    CH = [([57, 60, 64], 33), ([53, 57, 60], 41), ([50, 53, 57], 38), ([52, 56, 59], 40)]
    for bar in range(16):
        chord, root = CH[bar % 4]
        for s in range(8):
            tr.put(tick(s % 2 == 0, 1.0), tr.t(bar, s * 0.5), -0.2 if s % 2 else 0.2, 0.2)
            tr.put(sub(root, 0.42 * tr.beat, 1.0), tr.t(bar, s * 0.5), 0, 0.26)
        tr.put(pad([c + 12 for c in chord], tr.bar), tr.t(bar, 0), 0, 0.1)
        # 오르는 아르페지오 (마디가 갈수록 높이)
        up = chord + [c + 12 for c in chord] + [c + 24 for c in chord]
        for s in range(16):
            tr.put(pluck(up[min(s // 2 + (bar % 4), len(up) - 1)] + 12, 0.2 * tr.beat, 0.7, 1.4, 0.1), tr.t(bar, s * 0.25), 0.35, 0.09)
        tr.put(kick(0.9), tr.t(bar, 0), 0, 0.5)
        tr.put(kick(0.7), tr.t(bar, 2), 0, 0.45)
        if bar % 4 == 3:
            for s in range(8):
                tr.put(snare(0.4 + 0.08 * s), tr.t(bar, 2 + s * 0.25), 0, 0.25)
        else:
            tr.put(snare(0.8), tr.t(bar, 3), 0, 0.22)
        if bar % 2 == 1:
            tr.put(bell(chord[2] + 24, 0.9, 0.9), tr.t(bar, 0.5), 0.3, 0.12)
    return tr.finish(0.22, 0.4, 0.66)


# ── 5. 조개 섞기: 살금살금 스윙 (E단조 108) ────────────────────
def song_shell_game():
    tr = Track(108, 16, swing=0.17)
    walk = [40, 43, 45, 46, 47, 45, 43, 42]   # E G A Bb B A G F# (반음으로 살금살금)
    CH = [([64, 67, 71], 40), ([64, 67, 71], 40), ([60, 64, 67], 36), ([59, 63, 66], 35)]
    M = [
        [(0, .5, 76), (.5, .5, 77), (1, 1, 79), (2.5, .5, 82), (3, .5, 83), (3.5, .5, 79)],
        [(0, 1, 76), (1.5, .5, 74), (2, .5, 75), (2.5, .5, 76), (3, 1, 71)],
        [(0, .5, 72), (.5, .5, 76), (1, .5, 79), (1.5, .5, 84), (2, 1, 83), (3, 1, 79)],
        [(0, .5, 75), (.5, .5, 78), (1, 1, 81), (2, .5, 78), (2.5, .5, 75), (3, 1, 71)],
    ]
    for bar in range(16):
        chord, root = CH[bar % 4]
        for s in range(8):
            m = walk[s] + (0 if bar % 4 < 2 else (-4 if bar % 4 == 2 else -5))
            tr.put(pizz(m, 1.0), tr.t(bar, s * 0.5), -0.1, 0.42)
        for b in (0.5, 1.5, 2.5, 3.5):
            for m in chord:
                tr.put(pizz(m, 0.6), tr.t(bar, b), 0.35, 0.08)
        tr.put(snap(), tr.t(bar, 1), 0.3, 0.26)
        tr.put(snap(), tr.t(bar, 3), 0.3, 0.26)
        for s in range(8):
            tr.put(hat(0.5 if s % 2 else 0.25), tr.t(bar, s * 0.5), 0.5, 0.08)
        if bar >= 4:
            mel(tr, bar, M[bar % 4], lambda m, d: marimba(m, d, 0.9), 0.1, 0.3)
        if bar >= 8:
            mel(tr, bar, M[bar % 4], lambda m, d: lead(m - 12, d * 0.6, 0.7, 0.3), -0.3, 0.07)
    return tr.finish(0.2, 0.35, 0.68)


# ── 6. 해파리 피하기: 빠른 액션 (F#단조 164) ───────────────────
def song_jelly_dodge():
    tr = Track(164, 32)
    CH = [([66, 69, 73], 42), ([62, 66, 69], 38), ([61, 64, 69], 45), ([64, 68, 71], 40)]
    M = [
        [(0, .5, 78), (.5, .5, 81), (1, .5, 85), (1.5, .5, 81), (2, .25, 83), (2.25, .25, 85), (2.5, .5, 83), (3, 1, 81)],
        [(0, .5, 78), (.5, .5, 81), (1, .5, 86), (1.5, .5, 85), (2, 1, 83), (3, .5, 81), (3.5, .5, 78)],
        [(0, .5, 76), (.5, .5, 81), (1, .5, 85), (1.5, .5, 88), (2, 1, 85), (3, 1, 81)],
        [(0, .5, 80), (.5, .5, 83), (1, .5, 88), (1.5, .5, 86), (2, .5, 85), (2.5, .5, 83), (3, 1, 80)],
    ]
    for bar in range(32):
        chord, root = CH[bar % 4]
        sec = bar // 8
        for s in range(16):
            m = root + (12 if s % 4 == 2 else 0)
            tr.put(pluck(m, 0.2 * tr.beat, 1.0, 0.8, 0.1), tr.t(bar, s * 0.25), 0, 0.3)
        for b in range(4):
            tr.put(kick(), tr.t(bar, b), 0, 0.55)
        tr.put(snare(), tr.t(bar, 1), 0, 0.3)
        tr.put(snare(), tr.t(bar, 3), 0, 0.3)
        for s in range(16):
            tr.put(hat(1.0 if s % 4 == 2 else 0.45), tr.t(bar, s * 0.25), 0.4, 0.08)
        if bar % 8 == 0:
            tr.put(crash(), tr.t(bar, 0), -0.3, 0.14)
            tr.put(stab([c + 12 for c in chord]), tr.t(bar, 0), 0, 0.25)
        if bar % 4 == 3 and bar % 8 == 7:
            for i, m in enumerate((55, 52, 50, 47)):
                tr.put(tom(m), tr.t(bar, 3 + i * 0.25), -0.3 + i * 0.2, 0.35)
        tr.put(pad(chord, tr.bar), tr.t(bar, 0), 0.2, 0.07)
        if sec >= 1:
            mel(tr, bar, M[bar % 4], lambda m, d: lead(m, d * 0.85, 1.0), 0.1, 0.18)
        if sec >= 2:
            arp = chord + [c + 12 for c in chord]
            for s in range(8):
                tr.put(pluck(arp[s % 6] + 12, 0.15 * tr.beat, 0.6, 1.4, 0.08), tr.t(bar, s * 0.5 + 0.25), -0.45, 0.1)
    return tr.finish(0.14, 0.28, 0.74)


SONGS = {
    "board_theme": song_board,
    "mg_intro": song_mg_intro,
    "mg_pearl_pop": song_pearl_pop,
    "mg_timing_stop": song_timing_stop,
    "mg_shell_game": song_shell_game,
    "mg_jelly_dodge": song_jelly_dodge,
}


def main():
    os.makedirs(MUSIC_DIR, exist_ok=True)
    pick = sys.argv[1:] or list(SONGS)
    for name in pick:
        key = name if name in SONGS else ("mg_" + name if "mg_" + name in SONGS else name + "_theme")
        st = SONGS[key]()
        wav = os.path.join(MUSIC_DIR, key + ".wav")
        write_wav(wav, st, 2)
        if shutil.which("ffmpeg"):
            ogg = os.path.join(MUSIC_DIR, key + ".ogg")
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
            os.remove(wav)
        print(f"  {key}: {len(st) / SR:.1f}s")


if __name__ == "__main__":
    main()
