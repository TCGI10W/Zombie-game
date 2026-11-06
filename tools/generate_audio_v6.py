"""Sixth batch: ambience for the open town map.
Loops (seamless): rain_loop, rain_indoor_loop, roof_rain_loop, wind_loop,
fire_loop, hum_loop, drone_loop.
One-shots: creak, drip, crow, bell_far, train_horn, scream_far.

Run with: python tools/generate_audio_v6.py
"""
import numpy as np

from generate_audio import SR, save_wav

rng = np.random.default_rng(606)


def lowpass(x, cutoff):
    # one-pole low-pass, run forward and back for a gentle slope
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    acc = 0.0
    for i in range(len(x) - 1, -1, -1):
        acc = (1 - a) * y[i] + a * acc
        y[i] = acc
    return y


def fft_band(x, lo, hi):
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    mask = (freqs >= lo) & (freqs <= hi)
    soft = np.exp(-((freqs - np.clip(freqs, lo, hi)) / (0.25 * (hi - lo) + 1)) ** 2)
    return np.fft.irfft(f * np.where(mask, 1.0, soft), len(x))


def loopify(x, fade_s=0.6):
    """Crossfade the tail into the head so the sound loops without a click."""
    f = int(fade_s * SR)
    body = x[:-f].copy()
    ramp = np.linspace(0, 1, f)
    body[:f] = body[:f] * ramp + x[-f:] * (1 - ramp)
    return body


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.clip(t / max(attack, 1e-4), 0, 1) * np.exp(-t / decay)


def rain(seconds=7.0):
    n = int(seconds * SR)
    hiss = fft_band(rng.standard_normal(n), 1200, 9000) * 0.5
    body = fft_band(rng.standard_normal(n), 250, 1600) * 0.35
    drops = np.zeros(n)
    for _ in range(int(seconds * 180)):
        p = rng.integers(0, n - 800)
        k = int(rng.uniform(80, 400))
        drops[p:p + k] += rng.standard_normal(k) * env(k, 0.0002, 0.002) * rng.uniform(0.2, 0.9)
    drops = fft_band(drops, 1500, 8000)
    return hiss + body + drops * 0.6


def roof_rain(seconds=6.0):
    n = int(seconds * SR)
    out = fft_band(rng.standard_normal(n), 400, 3000) * 0.2
    t = np.arange(600) / SR
    for _ in range(int(seconds * 260)):
        p = rng.integers(0, n - 700)
        fr = rng.uniform(1800, 4200)
        out[p:p + 600] += np.sin(2 * np.pi * fr * t) * np.exp(-t / 0.004) * rng.uniform(0.15, 0.6)
    return out


def wind(seconds=9.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    base = fft_band(rng.standard_normal(n), 80, 900)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / seconds * 2 + 1.3) * np.sin(2 * np.pi * t / seconds * 3)
    howl = fft_band(rng.standard_normal(n), 380, 520) * (0.4 + 0.6 * np.clip(gust, 0, 1) ** 3) * 0.8
    return base * gust + howl


def fire(seconds=5.0):
    n = int(seconds * SR)
    roar = fft_band(rng.standard_normal(n), 60, 700) * 0.6
    crack = np.zeros(n)
    for _ in range(int(seconds * 40)):
        p = rng.integers(0, n - 2000)
        k = int(rng.uniform(150, 1500))
        crack[p:p + k] += rng.standard_normal(k) * env(k, 0.0001, rng.uniform(0.001, 0.008)) * rng.uniform(0.3, 1.2)
    return roar + fft_band(crack, 900, 7000)


def hum(seconds=4.0):
    t = np.arange(int(seconds * SR)) / SR
    x = sum(np.sin(2 * np.pi * 60 * k * t) / k ** 1.3 for k in range(1, 12))
    buzz = np.sign(np.sin(2 * np.pi * 120 * t)) * 0.08
    flick = 1.0 + 0.08 * np.sin(2 * np.pi * 0.5 * t)
    return (x * 0.3 + buzz) * flick + rng.standard_normal(len(t)) * 0.01


def drone(seconds=10.0):
    t = np.arange(int(seconds * SR)) / SR
    x = np.zeros_like(t)
    # Detuned low organ cluster, slowly breathing (whole periods so it loops)
    for f, a in [(55.0, 1.0), (55.3, 0.8), (82.5, 0.6), (110.4, 0.35), (164.8, 0.2), (116.5, 0.18)]:
        x += a * np.sin(2 * np.pi * f * t)
    breath = 0.7 + 0.3 * np.sin(2 * np.pi * t / seconds)
    air = fft_band(rng.standard_normal(len(t)), 200, 1200) * 0.08
    return x * breath * 0.4 + air


def creak():
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    f = 140 + 60 * np.sin(2 * np.pi * 0.9 * t) + 30 * t
    phase = 2 * np.pi * np.cumsum(f) / SR
    grain = (np.sin(phase) > 0.6).astype(float) * rng.uniform(0.5, 1.0, n)
    x = fft_band(grain - grain.mean(), 150, 2500)
    return x * np.clip(np.sin(np.pi * t / t[-1]), 0, 1) ** 0.7


def drip():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 900 + 1400 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.0005, 0.04)


def crow():
    out = np.zeros(int(1.6 * SR))
    for k in range(3):
        n = int(0.32 * SR)
        t = np.arange(n) / SR
        f0 = rng.uniform(650, 760)
        src = np.sign(np.sin(2 * np.pi * f0 * (1 - 0.25 * t / t[-1]) * t)) + 0.5 * rng.standard_normal(n)
        x = fft_band(src, 600, 3200) * np.clip(np.sin(np.pi * t / t[-1]), 0, 1) ** 0.5
        p = int(k * 0.45 * SR)
        out[p:p + n] += x
    return out


def bell_far():
    n = int(6.0 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for ratio, a, d in [(0.5, 0.7, 3.0), (1.0, 1.0, 2.2), (1.19, 0.5, 1.6), (1.5, 0.35, 1.2), (2.0, 0.3, 0.9), (2.74, 0.15, 0.6)]:
        x += a * np.sin(2 * np.pi * 220 * ratio * t) * np.exp(-t / d)
    return lowpass(x * env(n, 0.003, 9.0), 1800)


def train_horn():
    n = int(3.2 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f in [277.0, 349.0, 415.0]:
        x += np.sign(np.sin(2 * np.pi * f * t)) * 0.3 + np.sin(2 * np.pi * f * t)
    shape = np.clip(t / 0.25, 0, 1) * np.clip((t[-1] - t) / 0.6, 0, 1)
    return lowpass(x * shape, 1300)


def scream_far():
    n = int(1.8 * SR)
    t = np.arange(n) / SR
    f = 520 + 260 * np.sin(np.pi * t / t[-1]) + 25 * np.sin(2 * np.pi * 6 * t)
    src = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * rng.standard_normal(n)
    x = fft_band(src, 400, 2600) * np.clip(np.sin(np.pi * t / t[-1]), 0, 1) ** 0.8
    return lowpass(x, 2200)


if __name__ == "__main__":
    r = rain()
    save_wav("rain_loop", loopify(r), 0.6)
    save_wav("rain_indoor_loop", loopify(lowpass(r, 500)), 0.5)
    save_wav("roof_rain_loop", loopify(roof_rain()), 0.55)
    save_wav("wind_loop", loopify(wind(), 1.2), 0.6)
    save_wav("fire_loop", loopify(fire()), 0.6)
    save_wav("hum_loop", hum(), 0.4)
    save_wav("drone_loop", drone(), 0.55)
    save_wav("creak", creak(), 0.6)
    save_wav("drip", drip(), 0.5)
    save_wav("crow", crow(), 0.6)
    save_wav("bell_far", bell_far(), 0.6)
    save_wav("train_horn", train_horn(), 0.6)
    save_wav("scream_far", scream_far(), 0.5)
    print("ok")
