"""Horror overhaul audio pack (CoD 5/7 + Bodycam v0.9 — Pure Foley & Horror SFX, zero music).

Generates/upgrades physical & horror SFX WAVs in assets/audio/:
  - breath_panic.wav
  - whisper_eerie.wav
  - metal_scrape.wav
  - fluorescent_buzz.wav
  - flashlight_click.wav
  - headshot_crunch.wav
  - boss_blackout.wav
  - gun_suppressed.wav
  - crate_open.wav
  - crate_reveal.wav
  - level_up.wav
  - powerup_spawn.wav
  - second_wind.wav

Run with: python tools/generate_audio_v7_horror.py
"""
import numpy as np

from generate_audio import SR, save_wav, phase_sin, pink_noise, fft_bandpass, convolve_bunker_reverb, modal_ring
from generate_audio_v6 import fft_band, env

rng = np.random.default_rng(7077)


def make_breath_panic() -> np.ndarray:
    """Close-mic ragged panic breathing under a bodycam rig."""
    dur = 2.65
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    # Sharp gasp inhale (0.08..0.85) + trembling exhale (1.05..2.35)
    in_env = np.exp(-((t - 0.42) / 0.24) ** 2) * (1.0 + 0.16 * np.sin(2.0 * np.pi * 11.0 * t))
    ex_env = np.exp(-((t - 1.55) / 0.44) ** 2) * (1.0 + 0.14 * np.sin(2.0 * np.pi * 6.5 * t))

    in_air = fft_band(rng.standard_normal(n), 380, 2600) * in_env * 0.85
    in_throat = fft_band(pink_noise(n, 0.8), 160, 680) * in_env * 0.65
    ex_air = fft_band(rng.standard_normal(n), 220, 1650) * ex_env * 0.75
    # Faint vocal cord tremor on panicked exhale
    cord = phase_sin(np.full(n, 138.0) - 18.0 * (t - 1.0)) * np.exp(-((t - 1.45) / 0.25) ** 2)
    cord = fft_bandpass(cord, 120.0, 520.0) * 0.22
    # Mic capsule wind bump
    mic_thump = fft_bandpass(pink_noise(n, 1.6), 45.0, 160.0) * (in_env * 0.45 + ex_env * 0.35)
    return in_air + in_throat + ex_air + cord + mic_thump


def make_whisper_eerie() -> np.ndarray:
    """Verruckt asylum-style multi-layered unintelligible whispers."""
    dur = 3.2
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    out = np.zeros(n, dtype=np.float64)
    # Three overlapping spectral-sculpted breathy phrases
    for start, length, f1, f2, amp in [
        (0.15, 1.1, 750, 2200, 0.65),
        (0.85, 1.35, 1100, 3400, 0.80),
        (1.65, 1.25, 620, 1850, 0.55),
    ]:
        syll = 0.45 + 0.55 * np.maximum(0.0, np.sin(2.0 * np.pi * 3.8 * (t - start) + rng.uniform(0, 3.0)))
        win = np.exp(-((t - (start + length * 0.5)) / (length * 0.42)) ** 2)
        src = fft_band(rng.standard_normal(n), f1, f2)
        out += src * syll * win * amp
    # Ghostly reversed tail blur
    rev = convolve_bunker_reverb(out, rt60=1.2, wet=0.48, predelay_ms=22.0)
    tail = rev[::-1] * 0.25
    return rev + tail


def make_metal_scrape() -> np.ndarray:
    """Heavy rusted iron drag / pipe groan from down a dark hall."""
    dur = 2.8
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    sweep = np.sin(2.0 * np.pi * 0.55 * t) * 0.04
    bow = fft_bandpass(pink_noise(n, 0.9), 180.0, 2600.0) * env(n, 0.25, 1.1)
    # Inharmonic metallic pipe resonances excited by slip-stick envelope
    slip = 0.5 + 0.5 * np.sin(2.0 * np.pi * 17.0 * t + 3.0 * np.sin(2.0 * np.pi * 2.1 * t))
    modes = np.zeros(n, dtype=np.float64)
    for freq, amp, dec in [(194.0, 0.7, 0.5), (317.0, 0.55, 0.7), (542.0, 0.65, 0.9), (886.0, 0.45, 1.2), (1435.0, 0.30, 1.6)]:
        modes += amp * phase_sin(freq * (1.0 + sweep), rng.uniform(0, 6.28)) * np.exp(-t * dec)
    dry = modes * slip * env(n, 0.18, 1.05) + bow * 0.32
    return convolve_bunker_reverb(dry, rt60=1.1, wet=0.42, predelay_ms=18.0)


def make_fluorescent_buzz() -> np.ndarray:
    """Sputtering 60Hz/120Hz ballast hum with violent high-voltage arcs."""
    dur = 1.9
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    hum = sum((1.0 / k) * np.sin(2.0 * np.pi * 60.0 * k * t) for k in [1, 2, 3, 4, 6, 8])
    sputter = np.ones(n, dtype=np.float64)
    for pos_s, w_s, lvl in [(0.25, 0.07, 2.2), (0.62, 0.14, 0.1), (0.85, 0.05, 2.5), (1.28, 0.18, 0.15), (1.52, 0.08, 2.1)]:
        i0, i1 = int(pos_s * SR), min(n, int((pos_s + w_s) * SR))
        sputter[i0:i1] = lvl
    arcs = np.zeros(n, dtype=np.float64)
    for pos_s in [0.26, 0.60, 0.86, 1.27, 1.53]:
        i0 = int(pos_s * SR)
        k = min(2200, n - i0)
        if k > 20:
            arcs[i0:i0 + k] += fft_band(rng.standard_normal(k), 1400, 6800) * env(k, 0.0005, 0.014) * 1.4
    sig = (hum * 0.25 * sputter + arcs) * env(n, 0.03, 1.1)
    return convolve_bunker_reverb(sig, rt60=0.6, wet=0.25, predelay_ms=10.0)


def make_flashlight_click() -> np.ndarray:
    """Crisp tactical weapon-light switch click."""
    dur = 0.14
    n = int(dur * SR)
    out = np.zeros(n, dtype=np.float64)
    for delay_s, amp, f_lo, f_hi in [(0.004, 1.0, 1800, 6500), (0.022, 0.55, 2600, 8200)]:
        i0 = int(delay_s * SR)
        k = min(int(0.035 * SR), n - i0)
        snap = fft_band(rng.standard_normal(k), f_lo, f_hi) * env(k, 0.0002, 0.0035)
        body = np.sin(2.0 * np.pi * np.arange(k) / SR * 1950.0) * np.exp(-np.arange(k) / (0.004 * SR)) * 0.4
        out[i0:i0 + k] += (snap + body) * amp
    return out


def make_headshot_crunch() -> np.ndarray:
    """Visceral skull fracture + wet arterial mist impact (replaces arcade ding)."""
    dur = 0.55
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    # Sub impact thud
    thud = phase_sin(165.0 * np.exp(-t * 28.0) + 48.0) * np.exp(-t * 16.0) * 0.75
    # Crisp cranial bone fracture transients
    crack = np.zeros(n, dtype=np.float64)
    for d, f_lo, f_hi, a in [(0.002, 1100, 5200, 1.1), (0.014, 1800, 7400, 0.9), (0.034, 900, 3600, 0.65), (0.062, 1500, 6200, 0.4)]:
        i0 = int(d * SR)
        k = min(int(0.05 * SR), n - i0)
        crack[i0:i0 + k] += fft_band(rng.standard_normal(k), f_lo, f_hi) * env(k, 0.0003, 0.008) * a
    # Wet gore splash
    wet = fft_bandpass(pink_noise(n, 0.7), 320.0, 2400.0) * env(n, 0.006, 0.095) * 0.85
    return convolve_bunker_reverb(thud + crack + wet, rt60=0.42, wet=0.22, predelay_ms=8.0)


def make_crate_open() -> np.ndarray:
    """Heavy rusty iron padlock clack + creaking wooden lid hinge + metallic weapon-rack rattle."""
    dur = 1.6
    n = int(dur * SR)
    out = np.zeros(n, dtype=np.float64)
    # 0.00s: heavy iron hasp / padlock snap + wood knock
    k0 = min(int(0.18 * SR), n)
    t0 = np.arange(k0, dtype=np.float64) / SR
    hasp = modal_ring(k0, [1420.0, 2680.0, 4150.0], [55.0, 75.0, 95.0], [0.55, 0.35, 0.2])
    thud = phase_sin(75.0 + 90.0 * np.exp(-t0 * 40.0)) * np.exp(-t0 * 24.0) * 0.8
    out[:k0] += hasp + thud
    # 0.16s..1.05s: creaking stiff wooden lid hinge
    c_start = int(0.16 * SR)
    c_len = int(0.88 * SR)
    tc = np.arange(c_len, dtype=np.float64) / SR
    stutter = 0.55 + 0.45 * np.sin(2.0 * np.pi * 11.5 * tc)
    creak_f = 290.0 + 75.0 * np.sin(2.0 * np.pi * 2.4 * tc)
    creak = (phase_sin(creak_f) * 0.55 + phase_sin(creak_f * 2.02) * 0.25) * stutter * np.hanning(c_len) * 0.48
    wood_rub = fft_bandpass(pink_noise(c_len, 1.1), 220.0, 1450.0) * np.hanning(c_len) * 0.35
    out[c_start:c_start + c_len] += creak + wood_rub
    # 0.95s..1.48s: internal iron weapon-rack latches clattering
    for dt_s, f_base in [(0.96, 980.0), (1.12, 1340.0), (1.27, 1780.0)]:
        i0 = int(dt_s * SR)
        k = min(int(0.16 * SR), n - i0)
        out[i0:i0 + k] += modal_ring(k, [f_base, f_base * 1.68], [45.0, 68.0], [0.42, 0.28])
    return convolve_bunker_reverb(out, rt60=0.62, wet=0.26, predelay_ms=12.0)


def make_crate_reveal() -> np.ndarray:
    """Crisp steel gun-receiver bolt lock click + solid oak crate thud."""
    dur = 0.55
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    out = np.zeros(n, dtype=np.float64)
    # 0.00s: heavy oak wood seat thud
    out += phase_sin(110.0 * np.exp(-t * 32.0) + 46.0) * np.exp(-t * 18.0) * 0.85
    out += modal_ring(n, [145.0, 295.0], [28.0, 40.0], [0.5, 0.3])
    # 0.07s: double steel bolt lock snap
    for s, f1, f2 in [(0.07, 1850.0, 3420.0), (0.14, 2450.0, 4880.0)]:
        i0 = int(s * SR)
        k = min(int(0.14 * SR), n - i0)
        out[i0:i0 + k] += modal_ring(k, [f1, f2], [65.0, 90.0], [0.55, 0.38])
        out[i0:i0 + k] += fft_band(rng.standard_normal(k), 1800, 6800) * env(k, 0.0003, 0.009) * 0.65
    return convolve_bunker_reverb(out, rt60=0.45, wet=0.22, predelay_ms=8.0)


def make_level_up() -> np.ndarray:
    """Heavy mechanical gear latch click + pressurized forge steam hiss."""
    dur = 0.65
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    out = np.zeros(n, dtype=np.float64)
    # Mechanical ratchet latch clicks
    for s, f0 in [(0.01, 1180.0), (0.09, 1520.0), (0.18, 2100.0)]:
        i0 = int(s * SR)
        k = min(int(0.12 * SR), n - i0)
        out[i0:i0 + k] += modal_ring(k, [f0, f0 * 1.72], [58.0, 82.0], [0.55, 0.35])
    # Lock-in anvil clunk
    i_lock = int(0.18 * SR)
    k_lock = n - i_lock
    tl = np.arange(k_lock, dtype=np.float64) / SR
    out[i_lock:] += phase_sin(130.0 * np.exp(-tl * 25.0) + 52.0) * np.exp(-tl * 16.0) * 0.9
    # Pressurized pneumatic steam hiss
    hiss_env = np.clip((t - 0.16) / 0.04, 0.0, 1.0) * np.exp(-np.maximum(0.0, t - 0.18) * 6.5) * (t >= 0.16)
    out += fft_bandpass(pink_noise(n, 0.9), 1400.0, 7200.0) * hiss_env * 0.68
    return convolve_bunker_reverb(out, rt60=0.48, wet=0.24, predelay_ms=10.0)


def make_powerup_spawn() -> np.ndarray:
    """Metallic supply-canister floor drop thud + brief electrical arc crackle."""
    dur = 0.55
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    out = np.zeros(n, dtype=np.float64)
    # Canister impact on stone
    out += phase_sin(145.0 * np.exp(-t * 30.0) + 50.0) * np.exp(-t * 15.0) * 0.95
    out += modal_ring(n, [480.0, 1120.0, 2340.0], [32.0, 52.0, 80.0], [0.48, 0.34, 0.22])
    # Brief spark crackle bursts
    for s in [0.04, 0.11, 0.21]:
        i0 = int(s * SR)
        k = min(int(0.09 * SR), n - i0)
        out[i0:i0 + k] += fft_band(rng.standard_normal(k), 1900, 7600) * env(k, 0.0004, 0.016) * 0.62
    return convolve_bunker_reverb(out, rt60=0.50, wet=0.25, predelay_ms=9.0)


def make_second_wind() -> np.ndarray:
    """Sharp ragged adrenaline gasp inhale + double low heartbeat thump."""
    dur = 1.2
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    # Double strong pulse heartbeat (0.04s and 0.28s)
    beat = np.zeros(n, dtype=np.float64)
    for bp, amp in [(0.04, 1.0), (0.28, 0.72), (0.68, 0.85), (0.90, 0.60)]:
        i0 = int(bp * SR)
        k = min(int(0.18 * SR), n - i0)
        tk = np.arange(k, dtype=np.float64) / SR
        beat[i0:i0 + k] += phase_sin(95.0 * np.exp(-tk * 24.0) + 38.0) * np.exp(-tk * 17.0) * amp
    # Urgent chest gasp inhale
    gasp_env = np.exp(-((t - 0.36) ** 2) / (2.0 * 0.14 ** 2))
    gasp = fft_bandpass(pink_noise(n, 0.8), 320.0, 2300.0) * gasp_env * 0.85
    throat = fft_bandpass(pink_noise(n, 1.0), 140.0, 520.0) * gasp_env * 0.55
    return convolve_bunker_reverb(beat + gasp + throat, rt60=0.40, wet=0.20, predelay_ms=6.0)


def make_boss_blackout() -> np.ndarray:
    """Transformer short-circuit arc + breaker clunk + sub-bass blackout drop."""
    dur = 2.7
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    # Breaker arc sparks
    arcs = np.zeros(n, dtype=np.float64)
    for s in [0.02, 0.14, 0.28, 0.55]:
        i0 = int(s * SR)
        k = min(int(0.18 * SR), n - i0)
        arcs[i0:i0 + k] += fft_band(rng.standard_normal(k), 900, 6200) * env(k, 0.0005, 0.032) * 0.85
    # Heavy mechanical breaker throw at 0.32s
    b0 = int(0.32 * SR)
    bk = min(int(0.22 * SR), n - b0)
    arcs[b0:b0 + bk] += phase_sin(np.linspace(210.0, 52.0, bk)) * np.exp(-np.arange(bk) / (0.04 * SR)) * 1.1
    # Power-down turbine whine falling + 38 Hz horror dread sub drop
    whine = phase_sin(420.0 * np.exp(-t * 2.2) + 28.0) * env(n, 0.05, 1.1) * 0.45
    sub = phase_sin(np.maximum(34.0, 92.0 * np.exp(-t * 1.9))) * env(n, 0.22, 1.3) * 0.85
    return convolve_bunker_reverb(arcs + whine + sub, rt60=1.25, wet=0.34, predelay_ms=15.0)


def make_gun_suppressed() -> np.ndarray:
    """Baffled subsonic suppressed shot + crisp mechanical bolt cycle."""
    dur = 0.34
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    # Baffled gas thump (tight low punch, minimal crack)
    punch = phase_sin(210.0 * np.exp(-t * 42.0) + 65.0) * np.exp(-t * 26.0) * 0.95
    puff = fft_bandpass(pink_noise(n, 0.9), 240.0, 1950.0) * env(n, 0.001, 0.028) * 0.75
    # Crisp metallic bolt snap at +18ms
    b0 = int(0.018 * SR)
    bk = min(int(0.045 * SR), n - b0)
    bolt = fft_band(rng.standard_normal(bk), 2200, 7200) * env(bk, 0.0003, 0.007) * 0.6
    out = punch + puff
    out[b0:b0 + bk] += bolt
    return convolve_bunker_reverb(out, rt60=0.45, wet=0.22, predelay_ms=8.0)


def main():
    clips = {
        "breath_panic": make_breath_panic(),
        "whisper_eerie": make_whisper_eerie(),
        "metal_scrape": make_metal_scrape(),
        "fluorescent_buzz": make_fluorescent_buzz(),
        "flashlight_click": make_flashlight_click(),
        "headshot_crunch": make_headshot_crunch(),
        "boss_blackout": make_boss_blackout(),
        "gun_suppressed": make_gun_suppressed(),
        "crate_open": make_crate_open(),
        "crate_reveal": make_crate_reveal(),
        "level_up": make_level_up(),
        "powerup_spawn": make_powerup_spawn(),
        "second_wind": make_second_wind(),
    }
    for name, sig in clips.items():
        save_wav(name, sig)
        print(f"generated assets/audio/{name}.wav ({len(sig) / SR:.2f}s)")


if __name__ == "__main__":
    main()
