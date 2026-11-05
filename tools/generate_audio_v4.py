"""Fourth batch of sounds, built on the DSP engine in generate_audio.py:
hounds (growl, bark, howl, bite, death), lightning & thunder, bloater pop,
player cough / downed / second wind, helicopter & flare loops, radio
chatter, exfil siren & victory, carpenter, fire sale, hound round sting,
power-up spawn.

Run with: python tools/generate_audio_v4.py
"""
import math
import os
import wave

import numpy as np

from generate_audio import (
    OUT_DIR,
    SR,
    _celesta_note,
    _piano_note,
    convolve_bunker_reverb,
    fft_bandpass,
    glottal_fry_source,
    granular_footstep_grit,
    modal_ring,
    phase_sin,
    pink_noise,
    rng,
    save_wav,
    vocal_tract_stft,
)


def _t(dur):
    n = int(SR * dur)
    return n, np.arange(n) / SR


def make_loop(sig, n_loop, n_x):
    """Crossfade the overhang into the start so the clip loops without a seam."""
    out = sig[:n_loop].copy()
    ramp = np.linspace(0.0, 1.0, n_x)
    out[:n_x] = sig[:n_x] * ramp + sig[n_loop:n_loop + n_x] * (1.0 - ramp)
    return out


def save_loop_wav(name, samples, target_peak=0.85):
    """Like save_wav but without the edge fades, so loops stay seamless."""
    samples = samples - np.mean(samples)
    peak = np.max(np.abs(samples))
    if peak > 1e-6:
        samples = samples / peak
    samples = np.tanh(samples * 1.35) / np.tanh(1.35) * target_peak
    pcm = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(os.path.join(OUT_DIR, f"{name}.wav"), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())


def brass(freq, dur, gain=1.0):
    """Swelling brass-section tone: harmonics bloom in after the attack."""
    n, t = _t(dur)
    env = np.clip(t / 0.16, 0.0, 1.0) * np.clip((dur - t) / 0.45, 0.0, 1.0)
    phase = 2.0 * np.pi * np.cumsum(freq * (1.0 + 0.0045 * np.sin(2 * np.pi * 5.1 * t))) / SR
    out = np.zeros(n)
    for k in range(1, 13):
        out += (1.0 / k) * np.sin(k * phase + 0.3 * k) * env ** (1.0 + 0.16 * k)
    return out * gain


def timpani(freq, dur, gain=1.0):
    n, t = _t(dur)
    body = modal_ring(n, [freq, freq * 1.5, freq * 1.99, freq * 2.44], [3.2, 4.5, 6.0, 8.0], [1.0, 0.5, 0.3, 0.15])
    thump = phase_sin(freq * 0.7 + 60.0 * np.exp(-t * 30.0)) * np.exp(-t * 9.0)
    skin = fft_bandpass(pink_noise(n, 1.0), 120.0, 1800.0) * np.exp(-t * 40.0) * 0.3
    return (body + thump + skin) * gain


# ---------------------------------------------------------------------------
# HOUNDS
# ---------------------------------------------------------------------------
def gen_hounds():
    # Rolling snarl: rough low voice with a fast lip/throat flutter
    n, t = _t(1.3)
    f0 = 82.0 + 10.0 * np.sin(2 * np.pi * 1.7 * t) + 6.0 * rng.normal(0, 1, n).cumsum() / np.sqrt(n) * 0.0
    src = glottal_fry_source(t, f0, fry_amount=0.85, asp_amount=0.9)
    flutter = 0.55 + 0.45 * np.abs(np.sin(2 * np.pi * 14.0 * t + 0.6 * np.sin(2 * np.pi * 3.0 * t)))
    env = np.clip(t / 0.12, 0, 1) * np.clip((1.3 - t) / 0.3, 0, 1)
    growl = vocal_tract_stft(src, lambda u: 520.0 + 60.0 * math.sin(6.0 * u), 1250.0, 2550.0, bw=(110.0, 180.0, 300.0), chest_hz=110.0)
    save_wav("hound_growl", convolve_bunker_reverb(growl * flutter * env, rt60=0.4, wet=0.2), 0.8)

    # Aggressive bark
    n, t = _t(0.42)
    f0 = 360.0 * np.exp(-t * 2.2) + 190.0
    src = glottal_fry_source(t, f0, fry_amount=0.45, asp_amount=0.8)
    env = np.clip(t / 0.012, 0, 1) * np.exp(-t * 9.0)
    bark = vocal_tract_stft(src, lambda u: 700.0 - 220.0 * u, lambda u: 1650.0 - 450.0 * u, 2700.0, bw=(120.0, 200.0, 320.0), chest_hz=180.0)
    burst = fft_bandpass(pink_noise(n, 0.6), 400.0, 3500.0) * np.exp(-t * 40.0) * 0.4
    save_wav("hound_bark", convolve_bunker_reverb(bark * env + burst, rt60=0.5, wet=0.26), 0.86)

    # Eerie howl, with a second distant howl answering
    def howl(dur, base, peak):
        n2, t2 = _t(dur)
        rise = np.clip(t2 / 0.55, 0, 1)
        fall = np.clip((t2 - dur * 0.7) / (dur * 0.3), 0, 1)
        f = base + (peak - base) * (rise ** 0.6) - (peak - base) * 0.75 * fall ** 1.5
        f = f * (1.0 + 0.012 * np.sin(2 * np.pi * 5.5 * t2) * rise)
        s = glottal_fry_source(t2, f, fry_amount=0.12, asp_amount=0.32)
        v = vocal_tract_stft(s, lambda u: 380.0 + 120.0 * min(1.0, u * 3.0), lambda u: 820.0 + 200.0 * min(1.0, u * 2.0), 2400.0, bw=(80.0, 130.0, 220.0), chest_hz=200.0)
        e = np.clip(t2 / 0.25, 0, 1) * np.clip((dur - t2) / 0.6, 0, 1)
        return v * e

    n, t = _t(3.6)
    out = np.zeros(n)
    h1 = howl(2.9, 300.0, 540.0)
    out[: len(h1)] += h1
    h2 = howl(2.4, 260.0, 470.0) * 0.45
    i2 = int(0.9 * SR)
    out[i2 : i2 + len(h2)] += h2[: n - i2]
    save_wav("hound_howl", convolve_bunker_reverb(out, rt60=1.8, wet=0.45, predelay_ms=40.0)[:n], 0.82)

    # Bite: teeth clack + snarl burst
    n, t = _t(0.36)
    clack = modal_ring(n, [2300.0, 3600.0, 5200.0], [70.0, 90.0, 120.0], [0.6, 0.4, 0.25])
    src = glottal_fry_source(t, 120.0 + 40.0 * np.exp(-t * 8.0), fry_amount=0.7, asp_amount=0.9)
    snarl = vocal_tract_stft(src, 600.0, 1500.0, 2700.0, bw=(120.0, 200.0, 320.0), chest_hz=140.0) * np.exp(-t * 7.0) * np.clip(t / 0.02, 0, 1)
    save_wav("hound_bite", convolve_bunker_reverb(clack * 0.8 + snarl, rt60=0.3, wet=0.16), 0.86)

    # Death: yelp, then a fiery burst of embers
    n, t = _t(1.2)
    f0 = 760.0 * np.exp(-t * 6.0) + 330.0
    src = glottal_fry_source(t, f0, fry_amount=0.25, asp_amount=0.6)
    yelp = vocal_tract_stft(src, 800.0, 1800.0, 3000.0, bw=(120.0, 200.0, 320.0), chest_hz=300.0) * np.clip(t / 0.01, 0, 1) * np.exp(-t * 11.0)
    whoomp = fft_bandpass(pink_noise(n, 1.2), 70.0, 900.0) * np.clip((t - 0.08) / 0.03, 0, 1) * np.exp(-np.maximum(0.0, t - 0.1) * 5.0)
    crackle = granular_footstep_grit(n, 70, 1200.0, 7000.0, 0.1, 0.9) * 0.7
    thump = phase_sin(55.0 + 70.0 * np.exp(-t * 25.0)) * np.clip((t - 0.08) / 0.01, 0, 1) * np.exp(-np.maximum(0.0, t - 0.08) * 9.0)
    save_wav("hound_death", convolve_bunker_reverb(yelp * 0.8 + whoomp + crackle + thump, rt60=0.6, wet=0.26), 0.88)


# ---------------------------------------------------------------------------
# WEATHER
# ---------------------------------------------------------------------------
def gen_weather():
    n, t = _t(3.4)
    crack = rng.normal(0, 1, n) * np.exp(-t * 160.0) * 1.4
    tear = granular_footstep_grit(n, 140, 900.0, 9000.0, 0.0, 0.32) * 1.1
    boom = phase_sin(38.0 + 60.0 * np.exp(-t * 12.0)) * np.clip(t / 0.01, 0, 1) * np.exp(-t * 2.6) * 1.2
    slow = np.cumsum(rng.normal(0, 1, n))
    slow = fft_bandpass(slow, 0.5, 6.0)
    slow = (slow - slow.min()) / (slow.max() - slow.min() + 1e-9)
    rumble = fft_bandpass(pink_noise(n, 2.0), 25.0, 320.0) * (0.35 + 0.65 * slow) * np.exp(-t * 0.9) * 1.3
    save_wav("lightning_strike", convolve_bunker_reverb(crack + tear + boom + rumble, rt60=1.8, wet=0.4, predelay_ms=30.0)[:n], 0.94)

    n, t = _t(5.0)
    slow = fft_bandpass(np.cumsum(rng.normal(0, 1, n)), 0.3, 4.0)
    slow = (slow - slow.min()) / (slow.max() - slow.min() + 1e-9)
    env = np.clip(t / 0.6, 0, 1) * np.exp(-np.maximum(0.0, t - 1.0) * 0.8)
    far = fft_bandpass(pink_noise(n, 2.0), 20.0, 260.0) * (0.25 + 0.75 * slow) * env
    save_wav("thunder_far", convolve_bunker_reverb(far, rt60=2.2, wet=0.45)[:n], 0.7)


# ---------------------------------------------------------------------------
# BLOATER, PLAYER VITALS
# ---------------------------------------------------------------------------
def gen_bloater_and_player():
    n, t = _t(1.5)
    thump = phase_sin(70.0 * np.exp(-t * 3.0) + 28.0) * np.exp(-t * 7.0) * 1.3
    splat = granular_footstep_grit(n, 90, 250.0, 3200.0, 0.0, 0.35) * 1.3
    wet = fft_bandpass(pink_noise(n, 1.0), 300.0, 2400.0) * np.exp(-t * 12.0) * 0.6
    hiss = fft_bandpass(pink_noise(n, 0.4), 2200.0, 9000.0) * np.clip((t - 0.05) / 0.1, 0, 1) * np.exp(-np.maximum(0.0, t - 0.15) * 2.0) * 0.45
    src = glottal_fry_source(t, 48.0 + 10.0 * np.sin(2 * np.pi * 3.0 * t), fry_amount=0.9, asp_amount=0.6)
    gurgle = vocal_tract_stft(src, 420.0, 900.0, 2100.0, chest_hz=90.0) * np.exp(-t * 4.0) * 0.5
    save_wav("bloater_pop", convolve_bunker_reverb(thump + splat + wet + hiss + gurgle, rt60=0.55, wet=0.24), 0.92)

    # Coughing fit in the gas
    n, t = _t(0.9)
    out = np.zeros(n)
    for start, g in ((0.0, 1.0), (0.26, 0.8), (0.5, 0.65)):
        ln = int(0.22 * SR)
        i = int(start * SR)
        tt = np.arange(ln) / SR
        src = glottal_fry_source(tt, 150.0 + 30.0 * np.exp(-tt * 20.0), fry_amount=0.5, asp_amount=1.4)
        c = vocal_tract_stft(src, 620.0, 1400.0, 2600.0, chest_hz=160.0) * np.clip(tt / 0.008, 0, 1) * np.exp(-tt * 16.0) * g
        out[i : i + ln] += c[: n - i]
    save_wav("player_cough", convolve_bunker_reverb(out, rt60=0.3, wet=0.14), 0.8)

    # Going down: body thud, muffled ringing ears
    n, t = _t(2.4)
    thud = phase_sin(48.0 + 50.0 * np.exp(-t * 18.0)) * np.exp(-t * 8.0) * 1.2
    gear = granular_footstep_grit(n, 30, 300.0, 3000.0, 0.0, 0.12) * 0.6
    ring = (np.sin(2 * np.pi * 3950.0 * t) * 0.25 + np.sin(2 * np.pi * 4120.0 * t) * 0.12) * np.clip((t - 0.1) / 0.4, 0, 1) * np.exp(-np.maximum(0.0, t - 0.6) * 1.1)
    beat = np.zeros(n)
    for b in (0.5, 0.78, 1.5, 1.78):
        i = int(b * SR)
        ln = int(0.18 * SR)
        tt = np.arange(ln) / SR
        beat[i : i + ln] += phase_sin(45.0 + 20.0 * np.exp(-tt * 25.0)) * np.exp(-tt * 22.0) * 0.8
    save_wav("player_downed", convolve_bunker_reverb(thud + gear + ring + beat, rt60=0.9, wet=0.3)[:n], 0.86)

    # Second wind: sharp inhale, heartbeat, rising swell into a bright chord
    n, t = _t(1.9)
    inhale_env = np.clip(t / 0.4, 0, 1) * np.clip((0.55 - t) / 0.1, 0, 1)
    inhale = np.zeros(n)
    noise = pink_noise(n, 0.7)
    for lo, hi in ((700.0, 1800.0), (1600.0, 3600.0)):
        inhale += fft_bandpass(noise, lo, hi)
    inhale *= inhale_env * 0.9
    beat = np.zeros(n)
    for b in (0.6, 0.82):
        i = int(b * SR)
        ln = int(0.2 * SR)
        tt = np.arange(ln) / SR
        beat[i : i + ln] += phase_sin(52.0 + 40.0 * np.exp(-tt * 25.0)) * np.exp(-tt * 18.0)
    swell_env = np.clip((t - 0.7) / 0.7, 0, 1) ** 2 * np.clip((1.9 - t) / 0.2, 0, 1)
    swell = fft_bandpass(pink_noise(n, 1.0), 300.0, 5000.0) * swell_env * 0.6
    chord = np.zeros(n)
    for f in (293.66, 369.99, 440.0, 587.33):
        chord += np.sin(2 * np.pi * f * t) * swell_env * 0.22
    save_wav("second_wind", convolve_bunker_reverb(inhale + beat + swell + chord, rt60=0.8, wet=0.3)[:n], 0.88)


# ---------------------------------------------------------------------------
# HELICOPTER, FLARE, RADIO
# ---------------------------------------------------------------------------
def gen_exfil():
    # Helicopter: 11 Hz blade slap, turbine whine, rotor wash. Loops seamlessly.
    loop_s, x_s = 2.0, 0.25
    n_loop, n_x = int(SR * loop_s), int(SR * x_s)
    n, t = _t(loop_s + x_s)
    blade = np.zeros(n)
    period = int(SR / 11.0)
    pulse_t = np.arange(int(0.07 * SR)) / SR
    pulse = (fft_bandpass(rng.normal(0, 1, len(pulse_t)), 70.0, 600.0) * 0.6 + np.sin(2 * np.pi * 95.0 * pulse_t)) * np.exp(-pulse_t * 55.0)
    for i in range(0, n - len(pulse), period):
        blade[i : i + len(pulse)] += pulse * rng.uniform(0.85, 1.0)
    whine = (np.sin(2 * np.pi * 1350.0 * t + 0.4 * np.sin(2 * np.pi * 0.5 * t)) * 0.12 + np.sin(2 * np.pi * 2700.0 * t) * 0.05)
    wash = fft_bandpass(pink_noise(n, 1.0), 200.0, 3000.0) * (0.55 + 0.45 * np.sin(2 * np.pi * 11.0 * t) ** 2) * 0.5
    rumble = fft_bandpass(pink_noise(n, 2.0), 25.0, 140.0) * 0.8
    heli = blade * 1.4 + whine + wash + rumble
    save_loop_wav("heli_loop", make_loop(heli, n_loop, n_x), 0.85)

    # Signal flare: ignite pop, then a sizzling burn loop
    n, t = _t(0.8)
    scratch = granular_footstep_grit(n, 40, 1500.0, 8000.0, 0.0, 0.12)
    pop = phase_sin(160.0 + 400.0 * np.exp(-t * 40.0)) * np.clip((t - 0.1) / 0.005, 0, 1) * np.exp(-np.maximum(0.0, t - 0.1) * 25.0)
    hiss = fft_bandpass(pink_noise(n, 0.5), 1500.0, 9000.0) * np.clip((t - 0.1) / 0.1, 0, 1) * 0.6
    save_wav("flare_ignite", scratch + pop + hiss, 0.8)

    loop_s, x_s = 1.5, 0.2
    n_loop, n_x = int(SR * loop_s), int(SR * x_s)
    n, t = _t(loop_s + x_s)
    burn = fft_bandpass(pink_noise(n, 0.5), 1200.0, 8500.0) * (0.8 + 0.2 * np.sin(2 * np.pi * 6.0 * t)) * 0.6
    burn += granular_footstep_grit(n, 120, 2000.0, 9000.0, 0.0, loop_s + x_s - 0.02) * 0.5
    save_loop_wav("flare_burn", make_loop(burn, n_loop, n_x), 0.6)

    # Radio: squelch, garbled voice through a small speaker, squelch out
    vowels = [(730.0, 1090.0, 2440.0), (270.0, 2290.0, 3010.0), (300.0, 870.0, 2240.0), (530.0, 1840.0, 2480.0), (570.0, 840.0, 2410.0)]
    n, t = _t(3.0)
    frames = 400
    f1 = np.zeros(frames)
    f2 = np.zeros(frames)
    f3 = np.zeros(frames)
    amp = np.zeros(n)
    pos = 0.18
    fi = 0
    while pos < 2.65:
        syl = rng.uniform(0.08, 0.16)
        v = vowels[rng.integers(0, len(vowels))]
        a = int(pos / 3.0 * frames)
        b = min(frames, int((pos + syl) / 3.0 * frames) + 1)
        f1[a:b], f2[a:b], f3[a:b] = v
        i0, i1 = int(pos * SR), int((pos + syl) * SR)
        seg_t = np.arange(i1 - i0) / SR
        amp[i0:i1] = np.sin(np.pi * seg_t / syl) ** 0.6 * rng.uniform(0.6, 1.0)
        pos += syl + (rng.uniform(0.15, 0.3) if rng.random() < 0.18 else rng.uniform(0.01, 0.04))
        fi += 1
    f1[f1 == 0] = 500.0
    f2[f2 == 0] = 1500.0
    f3[f3 == 0] = 2500.0
    f0 = 135.0 + 18.0 * np.sin(2 * np.pi * 0.9 * t) + 10.0 * np.sin(2 * np.pi * 3.3 * t)
    src = glottal_fry_source(t, f0, fry_amount=0.1, asp_amount=0.35)
    voice = vocal_tract_stft(src, lambda u: f1[min(frames - 1, int(u * frames))], lambda u: f2[min(frames - 1, int(u * frames))], lambda u: f3[min(frames - 1, int(u * frames))]) * amp
    voice = np.tanh(fft_bandpass(voice, 380.0, 2800.0) * 6.0)
    static = fft_bandpass(pink_noise(n, 0.3), 500.0, 5000.0) * 0.12 * np.clip(t / 0.05, 0, 1) * np.clip((2.95 - t) / 0.05, 0, 1)
    sq = np.zeros(n)
    for c in (0.0, 2.82):
        i = int(c * SR)
        ln = int(0.15 * SR)
        tt = np.arange(ln) / SR
        sq[i : i + ln] += fft_bandpass(rng.normal(0, 1, ln), 800.0, 6000.0) * np.exp(-tt * 30.0) * 0.6
    save_wav("radio_call", voice * 0.8 + static + sq, 0.8)

    n, t = _t(0.42)
    beep = np.zeros(n)
    for start, f in ((0.0, 1000.0), (0.16, 1500.0)):
        i = int(start * SR)
        ln = int(0.13 * SR)
        tt = np.arange(ln) / SR
        beep[i : i + ln] += np.sin(2 * np.pi * f * tt) * np.clip(tt / 0.004, 0, 1) * np.clip((0.13 - tt) / 0.01, 0, 1)
    save_wav("radio_beep", np.tanh(fft_bandpass(beep, 400.0, 3000.0) * 2.0), 0.6)

    # Air-raid siren when the extraction is called
    n, t = _t(3.4)
    sweep = np.clip(t / 1.2, 0, 1) ** 0.7 * np.clip((3.4 - t) / 1.1, 0, 1) ** 0.8
    f = 240.0 + 420.0 * sweep
    ph = 2 * np.pi * np.cumsum(f) / SR
    siren = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph) + 0.15 * np.sin(4 * ph)
    siren *= (0.75 + 0.25 * np.sin(2 * np.pi * 18.0 * t)) * np.clip(t / 0.2, 0, 1) * np.clip((3.4 - t) / 0.9, 0, 1)
    save_wav("exfil_siren", convolve_bunker_reverb(siren * 0.6, rt60=1.9, wet=0.5, predelay_ms=60.0)[:n], 0.8)

    # Victory: brass swell over timpani, resolving to D major
    n, t = _t(5.2)
    out = np.zeros(n)
    chords = [(0.0, (146.83, 220.0, 293.66, 349.23), 1.3), (1.2, (116.54, 233.08, 293.66, 349.23), 1.3),
              (2.4, (130.81, 261.63, 329.63, 392.0), 1.2), (3.4, (146.83, 293.66, 369.99, 440.0), 1.8)]
    for start, notes, dur in chords:
        i = int(start * SR)
        for fq in notes:
            b = brass(fq, dur, 0.28)
            out[i : i + len(b)] += b[: n - i]
        tp = timpani(notes[0] * 0.5, 1.2, 0.5)
        out[i : i + len(tp)] += tp[: n - i]
    save_wav("exfil_success", convolve_bunker_reverb(out, rt60=1.6, wet=0.38, predelay_ms=24.0)[:n], 0.88)


# ---------------------------------------------------------------------------
# POWER-UPS & STINGS
# ---------------------------------------------------------------------------
def gen_powerups_and_stings():
    # Carpenter: rapid hammering, then a bright bell
    n, t = _t(1.7)
    out = np.zeros(n)
    for k, start in enumerate((0.0, 0.16, 0.32, 0.5, 0.66, 0.82, 1.0)):
        i = int(start * SR)
        ln = int(0.14 * SR)
        tt = np.arange(ln) / SR
        wood = modal_ring(ln, [180.0 + 15.0 * k, 300.0, 460.0], [40.0, 50.0, 70.0], [0.6, 0.4, 0.25])
        nail = modal_ring(ln, [2900.0, 4300.0], [60.0, 80.0], [0.25, 0.15])
        thud = phase_sin(70.0 + 90.0 * np.exp(-tt * 50.0)) * np.exp(-tt * 40.0) * 0.6
        out[i : i + ln] += (wood + nail + thud)[: n - i]
    i = int(1.15 * SR)
    bell = modal_ring(n - i, [1318.5, 1975.5, 2637.0], [5.0, 6.5, 9.0], [0.5, 0.35, 0.2])
    out[i:] += bell
    save_wav("carpenter", convolve_bunker_reverb(out, rt60=0.5, wet=0.2)[:n], 0.85)

    # Fire sale: bouncy music-box jingle
    n, t = _t(3.4)
    out = np.zeros(n)
    melody = [(0.0, 523.25), (0.15, 659.25), (0.3, 783.99), (0.45, 1046.5), (0.6, 783.99), (0.75, 659.25),
              (0.9, 698.46), (1.05, 880.0), (1.2, 1046.5), (1.35, 1396.9), (1.5, 1174.7), (1.65, 987.77),
              (1.8, 1046.5), (2.1, 783.99), (2.25, 1046.5)]
    for start, f in melody:
        i = int(start * SR)
        note = _celesta_note(f, 0.9) * 0.5
        out[i : i + len(note)] += note[: n - i]
    for start, f in ((0.0, 130.81), (0.6, 196.0), (1.2, 174.61), (1.8, 196.0), (2.25, 130.81)):
        i = int(start * SR)
        note = _piano_note(f, 0.7) * 0.35
        out[i : i + len(note)] += note[: n - i]
    save_wav("fire_sale", convolve_bunker_reverb(out, rt60=0.6, wet=0.24)[:n], 0.82)

    # Power-up spawn shimmer
    n, t = _t(1.0)
    out = np.zeros(n)
    for k, f in enumerate((1318.5, 1567.98, 1975.53, 2637.0)):
        i = int(k * 0.06 * SR)
        note = _celesta_note(f, 0.8) * 0.4
        out[i : i + len(note)] += note[: n - i]
    out += fft_bandpass(pink_noise(n, 0.3), 4000.0, 12000.0) * np.exp(-t * 4.0) * 0.15
    save_wav("powerup_spawn", convolve_bunker_reverb(out, rt60=0.7, wet=0.3)[:n], 0.7)

    # Hound round: low brass cluster swelling under a distant howl and thunder
    n, t = _t(4.6)
    out = np.zeros(n)
    for f, g in ((73.42, 0.4), (110.0, 0.3), (155.56, 0.25), (146.83, 0.2)):
        b = brass(f, 4.2, g)
        out[: len(b)] += b
    tp = timpani(73.42, 2.0, 0.8)
    out[: len(tp)] += tp
    i = int(2.2 * SR)
    tp2 = timpani(69.3, 2.0, 0.6)
    out[i : i + len(tp2)] += tp2[: n - i]
    save_wav("hound_round_sting", convolve_bunker_reverb(out, rt60=1.7, wet=0.42, predelay_ms=30.0)[:n], 0.9)


if __name__ == "__main__":
    gen_hounds()
    gen_weather()
    gen_bloater_and_player()
    gen_exfil()
    gen_powerups_and_stings()
    print("Generated v4 audio clips")
