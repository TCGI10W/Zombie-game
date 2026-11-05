"""Fifth batch: combat feedback UI sounds.
hit_tick (crisp hitmarker click), kill_confirm (punchy kill thump),
low_ammo_tick (dry mechanical click when the mag runs low),
streak_sting (short rising chime for multi-kills).

Run with: python tools/generate_audio_v5.py
"""
import numpy as np

from generate_audio import SR, save_wav

rng = np.random.default_rng(77)


def env(n, attack, decay):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / decay)


def hit_tick():
    n = int(0.07 * SR)
    t = np.arange(n) / SR
    click = np.sin(2 * np.pi * 3100 * t) * env(n, 0.0005, 0.010)
    body = np.sin(2 * np.pi * 1650 * t) * env(n, 0.0008, 0.018) * 0.6
    noise = rng.standard_normal(n) * env(n, 0.0002, 0.004) * 0.35
    return click + body + noise


def kill_confirm():
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    f = 150 * np.exp(-t * 9) + 55
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.09)
    snap = np.sin(2 * np.pi * 2400 * t) * env(n, 0.0005, 0.012) * 0.5
    ring = np.sin(2 * np.pi * 880 * t) * env(n, 0.002, 0.06) * 0.25
    return thump + snap + ring


def low_ammo_tick():
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    # crude resonant click: noise through a fast-decaying 2.2 kHz ring
    ring = np.sin(2 * np.pi * 2200 * t) * env(n, 0.0003, 0.008)
    return ring * 0.8 + noise * env(n, 0.0001, 0.003) * 0.4


def streak_sting():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for i, fr in enumerate([660, 880, 1320]):
        start = int(i * 0.06 * SR)
        m = n - start
        tt = t[:m]
        tone = (np.sin(2 * np.pi * fr * tt) + 0.3 * np.sin(2 * np.pi * fr * 2 * tt)) * env(m, 0.003, 0.14)
        out[start:] += tone * (0.6 + 0.2 * i)
    return out


if __name__ == "__main__":
    save_wav("hit_tick", hit_tick(), 0.7)
    save_wav("kill_confirm", kill_confirm(), 0.85)
    save_wav("low_ammo_tick", low_ammo_tick(), 0.6)
    save_wav("streak_sting", streak_sting(), 0.7)
    print("ok")
