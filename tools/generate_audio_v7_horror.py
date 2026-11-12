"""Horror overhaul audio pack (CoD 5/7 + Bodycam v0.9).

Generates new horror & tactical WAVs and upgrades stings in assets/audio/:
  New clips:
    - breath_panic.wav
    - whisper_eerie.wav
    - metal_scrape.wav
    - fluorescent_buzz.wav
    - flashlight_click.wav
    - headshot_crunch.wav
    - round_end_sting.wav
    - boss_blackout.wav
    - gun_suppressed.wav
  Upgraded stings:
    - round_sting.wav
    - hound_round_sting.wav

Run with: python tools/generate_audio_v7_horror.py
"""
import numpy as np

from generate_audio import SR, save_wav, phase_sin, pink_noise, fft_bandpass, convolve_bunker_reverb
from generate_audio_v6 import fft_band, env

rng = np.random.default_rng(7077)


def _piano_note(freq_hz: float, dur: float, detune_cents: float = 0.0, hammer: float = 0.35) -> np.ndarray:
    """Detuned haunting felt-piano note with wooden hammer thud and tape wow."""
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    wow = 1.0 + 0.0028 * np.sin(2.0 * np.pi * 0.42 * t + rng.uniform(0, 6.28))
    f0 = freq_hz * (2.0 ** (detune_cents / 1200.0)) * wow
    sig = np.zeros(n, dtype=np.float64)
    partials = [(1.0, 1.0, 0.85), (2.001, 0.42, 1.4), (3.005, 0.16, 2.2), (4.015, 0.06, 3.3), (0.5, 0.18, 0.7)]
    for mult, amp, decay in partials:
        sig += amp * phase_sin(f0 * mult, rng.uniform(0, 6.28)) * np.exp(-t * decay)
    # Soft felt hammer thump
    thud = fft_bandpass(pink_noise(n, 1.2), 70.0, 420.0) * env(n, 0.004, 0.035) * hammer
    attack = np.clip(t / 0.012, 0.0, 1.0)
    return (sig * attack + thud) * np.exp(-t * 0.45)


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


def make_round_end_sting() -> np.ndarray:
    """CoD 5 Nacht/Verruckt mournful detuned piano & hollow sub drone."""
    dur = 5.2
    n = int(dur * SR)
    out = np.zeros(n, dtype=np.float64)
    # Slow haunted descending minor phrase: A3 -> F3 -> E3 -> D3 over low D2 pedal
    notes = [
        (0.05, 73.42, 4.6, -9.0, 0.65),
        (0.08, 220.00, 2.8, -6.0, 0.75),
        (0.95, 174.61, 2.6, 8.0, 0.70),
        (1.85, 164.81, 2.5, -11.0, 0.65),
        (2.75, 146.83, 2.4, 5.0, 0.85),
    ]
    for start_s, hz, ndur, cents, amp in notes:
        i0 = int(start_s * SR)
        sig = _piano_note(hz, ndur, cents, hammer=0.28) * amp
        k = min(len(sig), n - i0)
        out[i0:i0 + k] += sig[:k]
    # Hollow eerie sub-drone & breathy ghost choir
    t = np.arange(n, dtype=np.float64) / SR
    drone = phase_sin(np.full(n, 55.0)) * env(n, 0.6, 2.4) * 0.35
    ghost = fft_bandpass(pink_noise(n, 0.9), 420.0, 1150.0) * env(n, 1.1, 2.1) * 0.22
    return convolve_bunker_reverb(out + drone + ghost, rt60=1.8, wet=0.46, predelay_ms=26.0)


def make_round_sting() -> np.ndarray:
    """CoD 5/7 haunted round-start piano + reversed whisper swell."""
    dur = 5.8
    n = int(dur * SR)
    out = np.zeros(n, dtype=np.float64)
    t = np.arange(n, dtype=np.float64) / SR
    # Classic tense minor piano + dissonant minor-second shadow: D2, D3, F3, C#4, Bb3
    notes = [
        (0.04, 73.42, 5.4, -7.0, 0.85),
        (0.18, 146.83, 3.6, 6.0, 0.72),
        (0.92, 174.61, 3.2, -10.0, 0.70),
        (1.68, 277.18, 2.6, 12.0, 0.58),
        (2.55, 233.08, 3.0, -8.0, 0.74),
    ]
    for start_s, hz, ndur, cents, amp in notes:
        i0 = int(start_s * SR)
        sig = _piano_note(hz, ndur, cents, hammer=0.36) * amp
        k = min(len(sig), n - i0)
        out[i0:i0 + k] += sig[:k]
    # Low ominous scrape & choir dread underneath
    choir = fft_bandpass(pink_noise(n, 0.7), 290.0, 920.0) * env(n, 0.9, 2.4) * 0.30
    sub = phase_sin(48.0 * (1.0 - 0.18 * t / dur)) * env(n, 0.35, 2.8) * 0.48
    return convolve_bunker_reverb(out + choir + sub, rt60=1.9, wet=0.45, predelay_ms=24.0)


def make_hound_round_sting() -> np.ndarray:
    """Demonic Hellhound round dread horn + thunder crack."""
    dur = 5.5
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    # Dissonant tritone sub-brass: 58 Hz + 82 Hz + gritty saw harmonics
    drop = 1.0 - 0.12 * np.clip(t / dur, 0.0, 1.0)
    horn = np.zeros(n, dtype=np.float64)
    for f0 in [58.27, 82.41]:
        for k in range(1, 7):
            horn += (0.7 / k) * phase_sin(f0 * k * drop + rng.uniform(-0.2, 0.2), rng.uniform(0, 6.28))
    horn *= env(n, 0.35, 2.2) * 0.45
    rumble = fft_bandpass(pink_noise(n, 1.5), 35.0, 240.0) * env(n, 0.08, 1.6) * 0.9
    growl = fft_bandpass(pink_noise(n, 0.8), 420.0, 1600.0) * env(n, 0.4, 1.1) * 0.35
    return convolve_bunker_reverb(horn + rumble + growl, rt60=1.8, wet=0.42, predelay_ms=20.0)


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
        "round_end_sting": make_round_end_sting(),
        "round_sting": make_round_sting(),
        "hound_round_sting": make_hound_round_sting(),
        "boss_blackout": make_boss_blackout(),
        "gun_suppressed": make_gun_suppressed(),
    }
    for name, sig in clips.items():
        save_wav(name, sig)
        print(f"generated assets/audio/{name}.wav ({len(sig) / SR:.2f}s)")


if __name__ == "__main__":
    main()
