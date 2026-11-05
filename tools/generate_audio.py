import os
import wave
import math
import numpy as np

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "audio")
os.makedirs(OUT_DIR, exist_ok=True)
SR = 44100
rng = np.random.default_rng(2026)


# ===========================================================================
# STUDIO DSP CORE HELPERS (Phase-Integrated Oscillators, Pink Noise, STFT
# Formant Tract Filter, Modal Resonators, & Bunker Convolution Reverb)
# ===========================================================================
def save_wav(name: str, samples: np.ndarray, target_peak: float = 0.88):
    # Remove DC offset
    samples = samples - np.mean(samples)
    # Gentle soft-knee mastering limiter
    peak = np.max(np.abs(samples))
    if peak > 1e-6:
        samples = samples / peak
    samples = np.tanh(samples * 1.35) / np.tanh(1.35) * target_peak
    # Tiny 3ms fade-in/out to guarantee zero boundary clicks
    fade_n = min(int(0.003 * SR), len(samples) // 8)
    if fade_n > 1:
        samples[:fade_n] *= np.linspace(0.0, 1.0, fade_n)
        samples[-fade_n:] *= np.linspace(1.0, 0.0, fade_n)
    pcm = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    path = os.path.join(OUT_DIR, f"{name}.wav")
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())


def phase_sin(freq_curve: np.ndarray, phase0: float = 0.0) -> np.ndarray:
    """True instantaneous phase integration: phi(t) = 2*pi * integral(f(t) dt)."""
    phi = phase0 + 2.0 * np.pi * np.cumsum(freq_curve) / SR
    return np.sin(phi)


def pink_noise(n: int, alpha: float = 1.0) -> np.ndarray:
    """Generate 1/f^(alpha/2) colored noise via FFT (alpha=1 -> pink, alpha=2 -> brown)."""
    white = rng.normal(0.0, 1.0, n)
    spec = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    scale = 1.0 / np.maximum(freqs, 20.0) ** (alpha * 0.5)
    scale[0] = 0.0
    out = np.fft.irfft(spec * scale, n=n)
    mx = np.max(np.abs(out))
    return out / mx if mx > 1e-6 else out


def fft_bandpass(sig: np.ndarray, f_lo: float, f_hi: float, order: float = 3.0) -> np.ndarray:
    """Smooth zero-phase Butterworth-like bandpass in frequency domain."""
    n = len(sig)
    spec = np.fft.rfft(sig)
    freqs = np.maximum(np.fft.rfftfreq(n, 1.0 / SR), 1e-3)
    hp = 1.0 / np.sqrt(1.0 + (f_lo / freqs) ** (2.0 * order)) if f_lo > 1.0 else 1.0
    lp = 1.0 / np.sqrt(1.0 + (freqs / f_hi) ** (2.0 * order)) if f_hi < SR * 0.49 else 1.0
    return np.fft.irfft(spec * hp * lp, n=n)


def modal_ring(n: int, freqs_hz, decays, amps=None) -> np.ndarray:
    """Sum of damped metallic/glass/wood modal resonances."""
    t = np.arange(n, dtype=np.float64) / SR
    out = np.zeros(n, dtype=np.float64)
    if amps is None:
        amps = [1.0] * len(freqs_hz)
    for f, d, a in zip(freqs_hz, decays, amps):
        out += a * np.sin(2.0 * np.pi * f * t + rng.uniform(0, 2 * np.pi)) * np.exp(-t * d)
    return out


def convolve_bunker_reverb(sig: np.ndarray, rt60: float = 0.55, wet: float = 0.20, predelay_ms: float = 14.0) -> np.ndarray:
    """Realistic concrete courtyard early reflections + diffuse exponential pink tail."""
    ir_len = int(SR * rt60)
    ir = np.zeros(ir_len, dtype=np.float64)
    # Discrete concrete wall early reflections
    early_taps = [
        (predelay_ms, 0.55),
        (predelay_ms + 11.0, -0.40),
        (predelay_ms + 23.0, 0.32),
        (predelay_ms + 39.0, -0.24),
        (predelay_ms + 58.0, 0.18),
    ]
    for ms, gain in early_taps:
        idx = int(ms * 0.001 * SR)
        if idx < ir_len:
            ir[idx] += gain
    # Diffuse tail
    t = np.arange(ir_len, dtype=np.float64) / SR
    tail = pink_noise(ir_len, alpha=1.25) * np.exp(-t * (6.91 / max(rt60, 0.08)))
    tail = fft_bandpass(tail, 120.0, 4200.0, order=2.0)
    predelay_idx = int(predelay_ms * 0.001 * SR)
    tail[:predelay_idx] *= np.linspace(0.0, 1.0, predelay_idx)
    ir += tail * 0.28

    total_n = len(sig) + ir_len - 1
    fft_n = 1 << (total_n - 1).bit_length()
    wet_sig = np.fft.irfft(np.fft.rfft(sig, fft_n) * np.fft.rfft(ir, fft_n), fft_n)[:total_n]
    mx_w = np.max(np.abs(wet_sig))
    mx_d = np.max(np.abs(sig))
    if mx_w > 1e-6 and mx_d > 1e-6:
        wet_sig = wet_sig * (mx_d / mx_w)
    dry_padded = np.zeros(total_n, dtype=np.float64)
    dry_padded[: len(sig)] = sig
    return dry_padded * (1.0 - wet) + wet_sig * wet


def glottal_fry_source(t: np.ndarray, f0_curve: np.ndarray, fry_amount: float = 0.45, asp_amount: float = 0.55) -> np.ndarray:
    """
    Organic creature vocal cord source:
    - Jittered Rosenberg-like asymmetric glottal pulse with rich harmonics
    - Subharmonic f0/2 & f0/3 diplophonia ('death rattle' vocal fry!)
    - Pharyngeal turbulent breath modulated by glottal opening
    """
    n = len(t)
    # Organic micro-jitter & flutter on pitch
    jitter = 1.0 + 0.035 * fft_bandpass(rng.normal(0, 1, n), 4.0, 35.0)
    f_inst = np.maximum(24.0, f0_curve * jitter)
    phi = np.mod(np.cumsum(f_inst) / SR, 1.0)

    # Asymmetric glottal pulse (fast closing edge creates realistic brassy/raspy harmonics, NOT sine/square!)
    open_q = 0.62
    pulse = np.where(
        phi < open_q,
        0.5 * (1.0 - np.cos(np.pi * phi / open_q)),
        np.cos(0.5 * np.pi * (phi - open_q) / (1.0 - open_q)),
    )
    # Differentiate glottal flow -> glottal flow derivative (lip radiation!)
    glottal = np.gradient(pulse) * 18.0

    # Subharmonic f0/2 + f0/3 vocal fry / monster throat rattle
    phi_sub = np.mod(np.cumsum(f_inst * 0.5) / SR, 1.0)
    sub_pulse = np.gradient(np.exp(-((phi_sub - 0.3) ** 2) / 0.008)) * 6.0

    # Wet throat gargle amplitude modulation (18-29 Hz irregular)
    gargle = 0.68 + 0.32 * np.sin(2 * np.pi * np.cumsum(22.0 + 6.0 * np.sin(2 * np.pi * 2.5 * t)) / SR)

    # Turbulent aspiration noise gated by glottal opening
    air = pink_noise(n, alpha=0.85) * (0.45 + 0.55 * pulse)

    return (glottal * (1.0 - fry_amount * 0.4) + sub_pulse * fry_amount) * gargle + air * asp_amount


def vocal_tract_stft(excitation: np.ndarray, f1_curve, f2_curve, f3_curve, bw=(95.0, 150.0, 260.0), chest_hz: float = 130.0) -> np.ndarray:
    """
    Time-varying resonant vocal tract filter using 75%-overlap STFT Lorentzian formants.
    Produces authentic organic vowels, snarls, roars, and throat resonances!
    """
    n = len(excitation)
    win_len = 512
    hop = 128
    win = np.hanning(win_len)
    freqs = np.fft.rfftfreq(win_len, 1.0 / SR)

    pad = win_len
    padded = np.pad(excitation, (pad, pad))
    out = np.zeros_like(padded)
    norm = np.zeros_like(padded)

    num_frames = (len(padded) - win_len) // hop + 1
    for fi in range(num_frames):
        start = fi * hop
        center_orig = np.clip(start + win_len // 2 - pad, 0, n - 1)
        u = center_orig / max(1, n - 1)

        f1 = f1_curve(u) if callable(f1_curve) else f1_curve
        f2 = f2_curve(u) if callable(f2_curve) else f2_curve
        f3 = f3_curve(u) if callable(f3_curve) else f3_curve

        # Sum of 3 vocal tract formant resonances + chest resonance
        h_chest = 0.55 / np.sqrt(1.0 + ((freqs - chest_hz) / 85.0) ** 2)
        h1 = 1.00 / np.sqrt(1.0 + ((freqs - f1) / bw[0]) ** 2)
        h2 = 0.72 / np.sqrt(1.0 + ((freqs - f2) / bw[1]) ** 2)
        h3 = 0.42 / np.sqrt(1.0 + ((freqs - f3) / bw[2]) ** 2)
        # Gentle high-frequency rolloff above 4.8 kHz so it never sounds fizzy
        rolloff = 1.0 / (1.0 + (freqs / 4800.0) ** 4)
        transfer = (h_chest + h1 + h2 + h3) * rolloff

        frame = padded[start : start + win_len] * win
        filtered = np.fft.irfft(np.fft.rfft(frame) * transfer, n=win_len)
        out[start : start + win_len] += filtered * win
        norm[start : start + win_len] += win * win

    out = out / np.maximum(norm, 1e-6)
    return out[pad : pad + n]


def granular_footstep_grit(n: int, num_grains: int, f_lo: float, f_hi: float, window_start: float, window_len: float) -> np.ndarray:
    """Procedural foley gravel/wet-asphalt crunch via Poisson micro-impacts."""
    sig = np.zeros(n, dtype=np.float64)
    s_idx = int(window_start * SR)
    e_idx = min(n - int(0.012 * SR), int((window_start + window_len) * SR))
    if e_idx <= s_idx:
        return sig
    for _ in range(num_grains):
        pos = rng.integers(s_idx, e_idx)
        glen = rng.integers(int(0.002 * SR), int(0.009 * SR))
        gt = np.linspace(0.0, 1.0, glen)
        grain = rng.normal(0, 1, glen) * np.exp(-gt * rng.uniform(4.0, 9.0))
        sig[pos : pos + glen] += grain * rng.uniform(0.35, 1.0)
    return fft_bandpass(sig, f_lo, f_hi, order=2.0)


# ===========================================================================
# 1. FIREARMS & TACTICAL FOLEY
# ===========================================================================
def gen_pistol():
    dur = 0.34
    n = int(SR * dur)
    t = np.arange(n) / SR

    # Supersonic muzzle snap + chamber thump + powder blast + slide metal clink
    crack = fft_bandpass(pink_noise(n, 0.4), 1200.0, 6800.0) * np.exp(-t * 95.0) * 1.15
    thump = phase_sin(48.0 + 165.0 * np.exp(-t * 48.0)) * np.exp(-t * 28.0) * 1.10
    blast = fft_bandpass(pink_noise(n, 0.9), 180.0, 2600.0) * np.exp(-t * 22.0) * 0.95

    mech = np.zeros(n)
    s_idx = int(0.036 * SR)
    mech[s_idx:] += modal_ring(n - s_idx, [2450, 3820, 5610], [85, 110, 140], [0.16, 0.12, 0.08])

    raw = np.tanh((crack + thump + blast + mech) * 1.6)
    out = convolve_bunker_reverb(raw, rt60=0.42, wet=0.22, predelay_ms=16.0)
    save_wav("gun_pistol", out, 0.92)


def gen_rifle():
    dur = 0.40
    n = int(SR * dur)
    t = np.arange(n) / SR

    # High-velocity 7.62mm supersonic bark + tight chest punch + bolt carrier ring
    bark = fft_bandpass(pink_noise(n, 0.35), 1400.0, 7800.0) * np.exp(-t * 115.0) * 1.35
    punch = phase_sin(54.0 + 195.0 * np.exp(-t * 55.0)) * np.exp(-t * 30.0) * 1.15
    body = fft_bandpass(pink_noise(n, 0.85), 220.0, 3100.0) * np.exp(-t * 20.0) * 1.05

    bolt = np.zeros(n)
    b_idx = int(0.042 * SR)
    bolt[b_idx:] += modal_ring(n - b_idx, [2180, 3290, 4950], [70, 95, 120], [0.18, 0.14, 0.09])

    raw = np.tanh((bark + punch + body + bolt) * 1.75)
    out = convolve_bunker_reverb(raw, rt60=0.52, wet=0.25, predelay_ms=18.0)
    save_wav("gun_rifle", out, 0.94)


def gen_shotgun():
    dur = 0.56
    n = int(SR * dur)
    t = np.arange(n) / SR

    # Massive 12-gauge sub-cannon + wide low-mid buckshot roar (pump rack plays synced via pump_rack.wav)
    sub_boom = phase_sin(36.0 + 115.0 * np.exp(-t * 28.0)) * np.exp(-t * 14.0) * 1.45
    pellet_crack = fft_bandpass(pink_noise(n, 0.45), 900.0, 6200.0) * np.exp(-t * 68.0) * 1.25
    cannon_body = fft_bandpass(pink_noise(n, 1.1), 95.0, 2100.0) * np.exp(-t * 11.5) * 1.30

    raw = np.tanh((sub_boom + pellet_crack + cannon_body) * 1.8)
    out = convolve_bunker_reverb(raw, rt60=0.62, wet=0.28, predelay_ms=15.0)
    save_wav("gun_shotgun", out, 0.95)


def gen_extra_weapons():
    # 1. SMG (KURZ-9): Tight, crisp 9mm submachine gun bark — super clean for high fire-rate
    dur_smg = 0.20
    ns = int(SR * dur_smg)
    ts = np.arange(ns) / SR
    s_crack = fft_bandpass(pink_noise(ns, 0.35), 1500.0, 7400.0) * np.exp(-ts * 125.0) * 1.15
    s_punch = phase_sin(68.0 + 175.0 * np.exp(-ts * 62.0)) * np.exp(-ts * 38.0) * 1.05
    s_body = fft_bandpass(pink_noise(ns, 0.8), 260.0, 3200.0) * np.exp(-ts * 30.0) * 0.85
    s_bolt = np.zeros(ns)
    bi = int(0.028 * SR)
    s_bolt[bi:] += modal_ring(ns - bi, [2650.0, 4120.0], [110.0, 140.0], [0.15, 0.10])
    save_wav("gun_smg", convolve_bunker_reverb(np.tanh((s_crack + s_punch + s_body + s_bolt) * 1.6), rt60=0.30, wet=0.18), 0.88)

    # 2. LMG (RAZORBACK): Heavy belt-fed 7.62mm thump + brass belt-link clatter
    dur_lmg = 0.34
    nl = int(SR * dur_lmg)
    tl = np.arange(nl) / SR
    l_crack = fft_bandpass(pink_noise(nl, 0.4), 1100.0, 6800.0) * np.exp(-tl * 95.0) * 1.25
    l_thump = phase_sin(46.0 + 155.0 * np.exp(-tl * 45.0)) * np.exp(-tl * 24.0) * 1.30
    l_body = fft_bandpass(pink_noise(nl, 0.95), 150.0, 2700.0) * np.exp(-tl * 18.0) * 1.10
    l_links = np.zeros(nl)
    li = int(0.035 * SR)
    l_links[li:] += modal_ring(nl - li, [3150.0, 4880.0, 6720.0], [85.0, 105.0, 130.0], [0.18, 0.14, 0.10])
    save_wav("gun_lmg", convolve_bunker_reverb(np.tanh((l_crack + l_thump + l_body + l_links) * 1.7), rt60=0.46, wet=0.22), 0.92)

    # 3. SNIPER (LONGSHOT .50 BMG): Supersonic whip-crack + seismic cannon boom + long courtyard echo
    dur_snp = 0.92
    nn = int(SR * dur_snp)
    tn = np.arange(nn) / SR
    n_whip = fft_bandpass(pink_noise(nn, 0.25), 1800.0, 9200.0) * np.exp(-tn * 90.0) * 1.45
    n_boom = phase_sin(32.0 + 130.0 * np.exp(-tn * 32.0)) * np.exp(-tn * 10.5) * 1.55
    n_roar = fft_bandpass(pink_noise(nn, 1.15), 80.0, 2400.0) * np.exp(-tn * 8.5) * 1.35
    save_wav("gun_sniper", convolve_bunker_reverb(np.tanh((n_whip + n_boom + n_roar) * 1.85), rt60=0.85, wet=0.34, predelay_ms=20.0), 0.96)

    # 4. REVOLVER (.44 HAND CANNON): High-pressure magnum bark + heavy cylinder steel ring
    dur_rev = 0.48
    nr = int(SR * dur_rev)
    tr = np.arange(nr) / SR
    r_crack = fft_bandpass(pink_noise(nr, 0.35), 1300.0, 7600.0) * np.exp(-tr * 82.0) * 1.35
    r_punch = phase_sin(52.0 + 185.0 * np.exp(-tr * 42.0)) * np.exp(-tr * 20.0) * 1.35
    r_body = fft_bandpass(pink_noise(nr, 0.9), 160.0, 2800.0) * np.exp(-tr * 15.0) * 1.10
    r_ring = modal_ring(nr, [1890.0, 3420.0, 5140.0], [28.0, 36.0, 48.0], [0.14, 0.10, 0.06])
    save_wav("gun_revolver", convolve_bunker_reverb(np.tanh((r_crack + r_punch + r_body + r_ring) * 1.75), rt60=0.56, wet=0.26), 0.94)

    # 5. VOLT CANNON (Wonder Weapon): Capacitor discharge THOOM + stochastic plasma arc crackle + coil hum
    dur_v = 0.68
    nv = int(SR * dur_v)
    tv = np.arange(nv) / SR
    v_thoom = phase_sin(42.0 + 380.0 * np.exp(-tv * 24.0)) * np.exp(-tv * 11.0) * 1.25
    v_coil = (
        np.sin(2 * np.pi * 120.0 * tv) * 0.35
        + phase_sin(920.0 - 480.0 * (tv / dur_v)) * 0.28
    ) * np.exp(-tv * 6.5)
    v_arcs = granular_footstep_grit(nv, 42, 1800.0, 9600.0, 0.001, 0.42) * 1.25
    v_sizzle = fft_bandpass(pink_noise(nv, 0.45), 2200.0, 8800.0) * np.exp(-tv * 8.0) * 0.55
    save_wav("gun_volt", convolve_bunker_reverb(np.tanh((v_thoom + v_coil + v_arcs + v_sizzle) * 1.5), rt60=0.58, wet=0.26), 0.93)


def gen_enemy_shot():
    dur = 0.30
    n = int(SR * dur)
    t = np.arange(n) / SR
    # Distinct snappy carbine crack + supersonic bullet whiz so player immediately recognizes enemy gunfire!
    crack = fft_bandpass(pink_noise(n, 0.4), 1600.0, 6500.0) * np.exp(-t * 85.0) * 1.0
    thump = phase_sin(75.0 + 180.0 * np.exp(-t * 42.0)) * np.exp(-t * 25.0) * 0.85
    whiz = phase_sin(1650.0 - 950.0 * (t / dur)) * np.exp(-((t - 0.045) ** 2) / 0.0012) * 0.32
    raw = np.tanh((crack + thump + whiz) * 1.5)
    save_wav("enemy_gunshot", convolve_bunker_reverb(raw, rt60=0.38, wet=0.20), 0.86)


def gen_reload():
    # Initial tactical weapon cant & pouch cloth grab (synced mag_out / mag_in play at 15% & 68% of reload!)
    dur_r = 0.28
    nr = int(SR * dur_r)
    tr = np.arange(nr) / SR
    cloth = fft_bandpass(pink_noise(nr, 0.9), 260.0, 2200.0) * np.sin(np.pi * tr / dur_r) ** 0.8 * 0.55
    latch = modal_ring(nr, [1480.0, 2620.0], [65.0, 90.0], [0.35, 0.22])
    save_wav("reload", cloth + latch, 0.68)

    # Mag out: metallic catch click + polymer/steel magazine sliding free
    dur_mo = 0.24
    nmo = int(SR * dur_mo)
    s_mo = np.zeros(nmo)
    s_mo += modal_ring(nmo, [1780.0, 3050.0, 4420.0], [75.0, 95.0, 125.0], [0.50, 0.36, 0.22])
    i_slide = int(0.025 * SR)
    l_slide = int(0.16 * SR)
    s_mo[i_slide : i_slide + l_slide] += fft_bandpass(pink_noise(l_slide, 0.7), 650.0, 3600.0) * np.hanning(l_slide) * 0.45
    save_wav("mag_out", s_mo, 0.78)

    # Mag in: solid heavy magazine-well THUNK + crisp locking pawl click!
    dur_mi = 0.26
    nmi = int(SR * dur_mi)
    tmi = np.arange(nmi) / SR
    thunk = phase_sin(88.0 + 135.0 * np.exp(-tmi * 58.0)) * np.exp(-tmi * 42.0) * 0.95
    click_lock = np.zeros(nmi)
    il = int(0.048 * SR)
    click_lock[il:] += modal_ring(nmi - il, [1540.0, 2890.0, 4560.0], [70.0, 92.0, 120.0], [0.58, 0.44, 0.28])
    save_wav("mag_in", thunk + click_lock, 0.84)

    # Pump rack: authentic 2-stroke steel shotgun slide CHAK-CHUK (0.0s & 0.16s)
    dur_pr = 0.36
    npr = int(SR * dur_pr)
    s_pr = np.zeros(npr)
    for p_time, freqs in [(0.005, [1420.0, 2640.0, 4080.0]), (0.165, [1740.0, 3180.0, 4760.0])]:
        idx = int(p_time * SR)
        ln = min(int(0.11 * SR), npr - idx)
        fric = fft_bandpass(pink_noise(ln, 0.65), 850.0, 4800.0) * np.hanning(ln) * 0.38
        clack = modal_ring(ln, freqs, [72.0, 92.0, 118.0], [0.48, 0.36, 0.24])
        s_pr[idx : idx + ln] += fric + clack
    save_wav("pump_rack", s_pr, 0.82)

    # Bolt cycle: 4-stage precision sniper steel bolt lift -> pull -> push -> lock
    dur_bc = 0.60
    nbc = int(SR * dur_bc)
    s_bc = np.zeros(nbc)
    stages = [
        (0.01, [1680.0, 2950.0], 0.06, 0.42),
        (0.11, [1350.0, 2480.0, 3920.0], 0.14, 0.50),
        (0.34, [1520.0, 2760.0, 4180.0], 0.13, 0.52),
        (0.49, [1920.0, 3420.0, 5120.0], 0.07, 0.58),
    ]
    for st_t, f_set, st_len, gain in stages:
        idx = int(st_t * SR)
        ln = min(int(st_len * SR), nbc - idx)
        fric = fft_bandpass(pink_noise(ln, 0.6), 950.0, 5200.0) * np.hanning(ln) * 0.32 * gain
        ring = modal_ring(ln, f_set, [75.0] * len(f_set), [0.45 * gain] * len(f_set))
        s_bc[idx : idx + ln] += fric + ring
    save_wav("bolt_cycle", s_bc, 0.82)

    # Shotgun shell insert: brass rim past steel shell-latch + hull slide
    dur_sh = 0.19
    nsh = int(SR * dur_sh)
    tsh = np.arange(nsh) / SR
    hull = fft_bandpass(pink_noise(nsh, 0.75), 550.0, 3400.0) * np.exp(-((tsh - 0.04) ** 2) / 0.0012) * 0.55
    latch_sh = np.zeros(nsh)
    ish = int(0.055 * SR)
    latch_sh[ish:] += modal_ring(nsh - ish, [1650.0, 3120.0, 4850.0], [85.0, 110.0, 140.0], [0.52, 0.38, 0.24])
    latch_sh[ish:] += phase_sin(125.0 + 110.0 * np.exp(-np.arange(nsh - ish) / SR * 65.0)) * np.exp(-np.arange(nsh - ish) / SR * 50.0) * 0.50
    save_wav("shell_insert", hull + latch_sh, 0.78)

    # Dry fire: crisp metallic firing-pin snap on empty chamber
    dur_df = 0.085
    ndf = int(SR * dur_df)
    s_df = modal_ring(ndf, [2150.0, 3680.0, 5840.0], [95.0, 125.0, 165.0], [0.55, 0.42, 0.28])
    s_df += fft_bandpass(pink_noise(ndf, 0.4), 1800.0, 7500.0) * np.exp(-np.linspace(0, 12, ndf)) * 0.35
    save_wav("dry_fire", s_df, 0.72)

    # Weapon swap: tactical sling/cloth brush + receiver catch
    dur_ws = 0.22
    nws = int(SR * dur_ws)
    tws = np.arange(nws) / SR
    s_ws = fft_bandpass(pink_noise(nws, 0.85), 320.0, 2600.0) * np.sin(np.pi * tws / dur_ws) * 0.55
    iws = int(0.09 * SR)
    s_ws[iws:] += modal_ring(nws - iws, [1320.0, 2450.0], [75.0, 95.0], [0.35, 0.24])
    save_wav("weapon_swap", s_ws, 0.70)


def gen_hit_feedback():
    # Meaty bullet impact thwack on zombie flesh (both flesh_hit and hit_flesh)
    dur = 0.15
    n = int(SR * dur)
    t = np.arange(n) / SR
    thud = phase_sin(62.0 + 140.0 * np.exp(-t * 55.0)) * np.exp(-t * 36.0) * 0.95
    splat = granular_footstep_grit(n, 16, 650.0, 3800.0, 0.002, 0.060) * 0.80
    save_wav("hit_flesh", thud + splat, 0.80)
    save_wav("flesh_hit", thud + splat, 0.80)

    # Visceral COD Zombies Headshot Kill crunch + subtle helmet ring!
    dur_h = 0.24
    nh = int(SR * dur_h)
    th = np.arange(nh) / SR
    skull_crunch = granular_footstep_grit(nh, 26, 950.0, 5600.0, 0.001, 0.075) * 1.1
    punch = phase_sin(78.0 + 160.0 * np.exp(-th * 50.0)) * np.exp(-th * 32.0) * 0.85
    ping = modal_ring(nh, [1960.0, 2945.0, 4420.0], [22.0, 28.0, 36.0], [0.28, 0.20, 0.12])
    save_wav("headshot_ding", skull_crunch + punch + ping, 0.88)

    # Gore splat: wet organic burst for headshots & explosive gibs
    dur_g = 0.42
    ng = int(SR * dur_g)
    tg = np.arange(ng) / SR
    g_thud = phase_sin(52.0 + 115.0 * np.exp(-tg * 38.0)) * np.exp(-tg * 20.0) * 1.05
    g_wet = granular_footstep_grit(ng, 38, 450.0, 4200.0, 0.002, 0.24) * 1.05
    save_wav("gore_splat", convolve_bunker_reverb(g_thud + g_wet, rt60=0.28, wet=0.16), 0.86)

    # Bullet ricochet: concrete chip impact + smooth supersonic lead whine
    dur_rc = 0.34
    nrc = int(SR * dur_rc)
    trc = np.arange(nrc) / SR
    chip = granular_footstep_grit(nrc, 12, 1400.0, 6800.0, 0.001, 0.035) * 0.90
    whine = phase_sin(2850.0 - 1650.0 * np.sqrt(trc / dur_rc)) * np.exp(-trc * 13.0) * np.clip(trc / 0.012, 0.0, 1.0) * 0.32
    save_wav("ricochet", convolve_bunker_reverb(chip + whine, rt60=0.35, wet=0.22), 0.78)

    # Brass shell casing tink: high-Q hollow brass cylinder bounces on concrete
    dur_st = 0.32
    nst = int(SR * dur_st)
    s_st = np.zeros(nst)
    for b_t, amp in [(0.002, 1.0), (0.095, 0.62), (0.175, 0.38), (0.235, 0.20)]:
        ib = int(b_t * SR)
        lb = nst - ib
        s_st[ib:] += modal_ring(
            lb,
            [4180.0, 5860.0, 7640.0, 9820.0],
            [52.0, 64.0, 78.0, 95.0],
            [0.45 * amp, 0.35 * amp, 0.25 * amp, 0.15 * amp],
        )
    save_wav("shell_tink", s_st, 0.74)


# ===========================================================================
# 2. REALISTIC WET-ASPHALT & GRAVEL FOOTSTEPS (Zombies, Bosses, & Player)
# ===========================================================================
def _make_boot_step(sole_hz: float, grit_grains: int, scuff_len: float, weight: float = 1.0) -> np.ndarray:
    dur = 0.22
    n = int(SR * dur)
    t = np.arange(n) / SR
    # Heel thud (low damped impact, zero sine tone ring!)
    heel = phase_sin(sole_hz * 0.45 + sole_hz * np.exp(-t * 68.0)) * np.exp(-t * 48.0) * 0.85 * weight
    # Leather/rubber sole slap
    slap = fft_bandpass(pink_noise(n, 0.8), 280.0, 1500.0) * np.exp(-((t - 0.014) ** 2) / 0.00018) * 0.70
    # Wet gravel & water droplet micro-crunch
    grit = granular_footstep_grit(n, grit_grains, 1300.0, 5800.0, 0.008, scuff_len) * 0.85
    return heel + slap + grit


def gen_footsteps():
    save_wav("zombie_step_1", _make_boot_step(115.0, 18, 0.075, 1.0), 0.76)
    # Step 2 has a slightly longer dragging undead boot scuff
    s2 = _make_boot_step(98.0, 24, 0.115, 0.92)
    save_wav("zombie_step_2", s2, 0.74)

    # Player crisp tactical combat boot steps
    save_wav("player_step_1", _make_boot_step(128.0, 14, 0.055, 0.85), 0.62)
    save_wav("player_step_2", _make_boot_step(120.0, 15, 0.060, 0.85), 0.62)

    # Colossal Boss Stomp (Gorilla / Panzer Juggernaut)
    dur_b = 0.38
    nb = int(SR * dur_b)
    tb = np.arange(nb) / SR
    quake = phase_sin(30.0 + 78.0 * np.exp(-tb * 26.0)) * np.exp(-tb * 14.0) * 1.35
    impact = fft_bandpass(pink_noise(nb, 1.2), 65.0, 950.0) * np.exp(-tb * 18.0) * 1.10
    rubble = granular_footstep_grit(nb, 34, 650.0, 4200.0, 0.005, 0.16) * 0.85
    clank = modal_ring(nb, [420.0, 690.0, 1180.0], [26.0, 32.0, 42.0], [0.22, 0.15, 0.10])
    save_wav("boss_step", convolve_bunker_reverb(quake + impact + rubble + clank, rt60=0.35, wet=0.18), 0.88)


# ===========================================================================
# 3. ORGANIC VOCAL-TRACT ZOMBIE, MONSTER & BOSS ROARS (Source-Filter STFT)
# ===========================================================================
def gen_zombie_vocals():
    # 1. Zombie Groan: Creepy hollow vocal-fry exhale ('UUUHHH...')
    dur_g = 0.92
    ng = int(SR * dur_g)
    tg = np.arange(ng) / SR
    env_g = np.clip(tg / 0.12, 0.0, 1.0) * np.exp(-np.maximum(0.0, tg - 0.22) * 2.8) * np.sin(np.pi * tg / dur_g) ** 0.4
    f0_g = 74.0 - 16.0 * (tg / dur_g) + 3.5 * np.sin(2 * np.pi * 4.5 * tg)
    src_g = glottal_fry_source(tg, f0_g, fry_amount=0.65, asp_amount=0.75)
    groan = vocal_tract_stft(
        src_g,
        lambda u: 360.0 - 70.0 * u,
        lambda u: 860.0 - 180.0 * u,
        lambda u: 2150.0,
        bw=(85.0, 140.0, 240.0),
        chest_hz=115.0,
    ) * env_g
    save_wav("zombie_groan", convolve_bunker_reverb(groan, rt60=0.45, wet=0.22), 0.78)

    # 2. Zombie Roar 1: Guttural snarling throat growl ('GRRRAAAHH!')
    dur_r1 = 1.05
    nr1 = int(SR * dur_r1)
    tr1 = np.arange(nr1) / SR
    env_r1 = np.clip(tr1 / 0.08, 0.0, 1.0) * np.exp(-np.maximum(0.0, tr1 - 0.28) * 2.7)
    f0_r1 = 84.0 + 18.0 * np.sin(np.pi * tr1 / 0.55) * np.exp(-tr1 * 1.5) - 18.0 * (tr1 / dur_r1)
    src_r1 = glottal_fry_source(tr1, f0_r1, fry_amount=0.72, asp_amount=0.68)
    roar1 = vocal_tract_stft(
        src_r1,
        lambda u: 410.0 + 290.0 * math.sin(math.pi * min(1.0, u * 1.3)),
        lambda u: 920.0 + 420.0 * math.sin(math.pi * min(1.0, u * 1.2)),
        lambda u: 2250.0 + 250.0 * (1.0 - u),
        bw=(95.0, 165.0, 280.0),
        chest_hz=125.0,
    ) * env_r1
    save_wav("zombie_roar_1", convolve_bunker_reverb(roar1, rt60=0.48, wet=0.24), 0.82)

    # 3. Zombie Roar 2: Iconic COD-Zombies raspy feral sprinter shriek!
    dur_r2 = 0.95
    nr2 = int(SR * dur_r2)
    tr2 = np.arange(nr2) / SR
    env_r2 = np.clip(tr2 / 0.05, 0.0, 1.0) * np.exp(-np.maximum(0.0, tr2 - 0.22) * 2.9)
    f0_r2 = 165.0 + 58.0 * np.exp(-((tr2 - 0.20) ** 2) / 0.04) - 35.0 * (tr2 / dur_r2)
    src_r2 = glottal_fry_source(tr2, f0_r2, fry_amount=0.55, asp_amount=0.95)
    roar2 = vocal_tract_stft(
        src_r2,
        lambda u: 680.0 - 180.0 * u,
        lambda u: 1680.0 - 340.0 * u,
        lambda u: 2950.0 - 300.0 * u,
        bw=(120.0, 210.0, 340.0),
        chest_hz=185.0,
    ) * env_r2
    save_wav("zombie_roar_2", convolve_bunker_reverb(roar2, rt60=0.52, wet=0.26), 0.82)

    # 4. Zombie Attack Roar: Fast vicious close-range bite snarl!
    dur_a = 0.44
    na = int(SR * dur_a)
    ta = np.arange(na) / SR
    env_a = np.clip(ta / 0.025, 0.0, 1.0) * np.exp(-ta * 5.2)
    f0_a = 132.0 - 45.0 * (ta / dur_a)
    src_a = glottal_fry_source(ta, f0_a, fry_amount=0.65, asp_amount=0.85)
    atk = vocal_tract_stft(
        src_a,
        lambda u: 640.0 - 280.0 * u,
        lambda u: 1420.0 - 520.0 * u,
        lambda u: 2550.0,
        bw=(110.0, 180.0, 290.0),
        chest_hz=140.0,
    ) * env_a
    save_wav("zombie_attack_roar", convolve_bunker_reverb(atk, rt60=0.30, wet=0.16), 0.86)

    # 5. Colossal Boss Roar (Gorilla / Boss Entrance): Deep chest bellow
    dur_b = 1.45
    nb = int(SR * dur_b)
    tb = np.arange(nb) / SR
    env_b = np.clip(tb / 0.10, 0.0, 1.0) * np.exp(-np.maximum(0.0, tb - 0.42) * 2.2)
    f0_b = 54.0 + 14.0 * np.exp(-((tb - 0.28) ** 2) / 0.08) - 10.0 * (tb / dur_b)
    src_b = glottal_fry_source(tb, f0_b, fry_amount=0.80, asp_amount=0.65)
    boss_v = vocal_tract_stft(
        src_b,
        lambda u: 310.0 + 180.0 * math.sin(math.pi * min(1.0, u * 1.2)),
        lambda u: 690.0 + 260.0 * math.sin(math.pi * min(1.0, u * 1.1)),
        lambda u: 1680.0,
        bw=(80.0, 130.0, 220.0),
        chest_hz=78.0,
    ) * env_b
    sub_chest = phase_sin(f0_b) * env_b * 0.45
    save_wav("boss_roar", convolve_bunker_reverb(boss_v + sub_chest, rt60=0.72, wet=0.30), 0.92)

    # 6. Viktor Monster Transformation Roar: Layered Beast Bellow + Predatory Snarl
    dur_m = 1.15
    nm = int(SR * dur_m)
    tm = np.arange(nm) / SR
    env_m = np.clip(tm / 0.06, 0.0, 1.0) * np.exp(-np.maximum(0.0, tm - 0.30) * 2.6)
    f0_m1 = 62.0 + 22.0 * np.exp(-((tm - 0.20) ** 2) / 0.05) - 14.0 * (tm / dur_m)
    f0_m2 = 138.0 + 35.0 * np.exp(-((tm - 0.18) ** 2) / 0.04) - 28.0 * (tm / dur_m)
    low_layer = vocal_tract_stft(
        glottal_fry_source(tm, f0_m1, 0.75, 0.6),
        lambda u: 380.0 + 220.0 * (1.0 - u),
        lambda u: 880.0 + 340.0 * (1.0 - u),
        lambda u: 1950.0,
        chest_hz=85.0,
    )
    high_layer = vocal_tract_stft(
        glottal_fry_source(tm, f0_m2, 0.55, 0.85),
        lambda u: 620.0 - 180.0 * u,
        lambda u: 1480.0 - 380.0 * u,
        lambda u: 2750.0,
        chest_hz=150.0,
    )
    save_wav("monster_roar", convolve_bunker_reverb((low_layer * 0.75 + high_layer * 0.55) * env_m, rt60=0.62, wet=0.26), 0.92)


# ===========================================================================
# 4. HERO ABILITIES, HEAVY SLAMS & COD ZOMBIES ATMOSPHERIC ROUND STING
# ===========================================================================
def gen_abilities_and_slams():
    # Monster Skill 1: Savage Rend (Heavy aerodynamic claw swipe + flesh rip)
    dur_r = 0.38
    nr = int(SR * dur_r)
    tr = np.arange(nr) / SR
    whoosh = fft_bandpass(pink_noise(nr, 0.9), 220.0, 2400.0) * np.exp(-((tr - 0.075) ** 2) / 0.0028) * 1.15
    blade_air = phase_sin(520.0 - 340.0 * (tr / dur_r)) * np.exp(-((tr - 0.07) ** 2) / 0.0020) * 0.35
    rip = granular_footstep_grit(nr, 28, 850.0, 5200.0, 0.055, 0.12) * 0.95
    thud = phase_sin(55.0 + 135.0 * np.exp(-np.maximum(0.0, tr - 0.05) * 45.0)) * np.exp(-np.maximum(0.0, tr - 0.05) * 26.0) * (tr >= 0.05) * 0.9
    save_wav("monster_rend", convolve_bunker_reverb(whoosh + blade_air + rip + thud, rt60=0.32, wet=0.18), 0.90)

    # Monster Skill 2: Seismic 4s Stun Slam (Earthquake sub drop + stone shatter + electric stun arc)
    dur_s = 0.95
    ns = int(SR * dur_s)
    ts = np.arange(ns) / SR
    sub_drop = phase_sin(32.0 + 95.0 * np.exp(-ts * 14.0)) * np.exp(-ts * 6.5) * 1.40
    blast = fft_bandpass(pink_noise(ns, 1.15), 55.0, 1400.0) * np.exp(-ts * 7.2) * 1.15
    debris = granular_footstep_grit(ns, 45, 700.0, 4800.0, 0.01, 0.35) * 0.80
    stun_hum = modal_ring(ns, [440.0, 885.0, 1330.0, 2640.0], [5.5, 6.5, 8.0, 11.0], [0.22, 0.18, 0.14, 0.10])
    save_wav("monster_slam", convolve_bunker_reverb(sub_drop + blast + debris + stun_hum, rt60=0.65, wet=0.28), 0.94)

    # Gorilla Slam: Colossal physical ground smash
    dur_g = 1.0
    ng = int(SR * dur_g)
    tg = np.arange(ng) / SR
    g_sub = phase_sin(28.0 + 88.0 * np.exp(-tg * 12.0)) * np.exp(-tg * 5.5) * 1.50
    g_boom = fft_bandpass(pink_noise(ng, 1.3), 48.0, 1100.0) * np.exp(-tg * 6.0) * 1.25
    g_rocks = granular_footstep_grit(ng, 52, 500.0, 3900.0, 0.008, 0.42) * 0.90
    save_wav("gorilla_slam", convolve_bunker_reverb(g_sub + g_boom + g_rocks, rt60=0.72, wet=0.30), 0.95)

    # Elena's Nocicept-X Pain Drug Dart: Pneumatic air rifle THWIP + glass ampoule shatter + sedative gas hiss!
    dur_p = 0.56
    np_len = int(SR * dur_p)
    tp = np.arange(np_len) / SR
    pneumatic = phase_sin(95.0 + 260.0 * np.exp(-tp * 55.0)) * np.exp(-tp * 38.0) * 0.85
    air_burst = fft_bandpass(pink_noise(np_len, 0.5), 1800.0, 7500.0) * np.exp(-tp * 45.0) * 0.75
    # Crystalline ampoule chime + gas release at 0.07s
    ampoule = np.zeros(np_len)
    ia = int(0.065 * SR)
    la = np_len - ia
    ampoule[ia:] += modal_ring(la, [3120.0, 4680.0, 6240.0, 7950.0], [16.0, 20.0, 26.0, 32.0], [0.28, 0.24, 0.18, 0.14])
    ampoule[ia:] += granular_footstep_grit(la, 18, 3200.0, 9500.0, 0.0, 0.06) * 0.55
    hiss_env = np.clip((tp - 0.065) / 0.03, 0.0, 1.0) * np.exp(-np.maximum(0.0, tp - 0.09) * 8.5) * (tp >= 0.065)
    gas_hiss = fft_bandpass(pink_noise(np_len, 0.4), 2400.0, 8800.0) * hiss_env * 0.50
    save_wav("pain_drug", convolve_bunker_reverb(pneumatic + air_burst + ampoule + gas_hiss, rt60=0.38, wet=0.20), 0.88)


def gen_buy_ching():
    # Authentic mechanical register bell + heavy steel weapon latch!
    dur = 0.62
    n = int(SR * dur)
    sig = np.zeros(n, dtype=np.float64)
    # Mechanical latch click at 0.0s
    l0 = int(0.06 * SR)
    sig[:l0] += modal_ring(l0, [1350.0, 2480.0], [65.0, 85.0], [0.45, 0.35])
    # Warm brass bell ring at 0.05s (B5 + F#6 + B6)
    ib = int(0.05 * SR)
    lb = n - ib
    sig[ib:] += modal_ring(
        lb,
        [987.77, 1479.98, 1975.53, 2963.0],
        [6.5, 8.0, 9.5, 13.0],
        [0.55, 0.42, 0.34, 0.18],
    )
    save_wav("buy_ching", convolve_bunker_reverb(sig, rt60=0.40, wet=0.18), 0.84)


def _piano_note(freq: float, dur: float) -> np.ndarray:
    """Dark felt-hammer upright piano tone with slight horror detune & inharmonicity."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    attack = np.clip(t / 0.008, 0.0, 1.0)
    out = np.zeros(n, dtype=np.float64)
    harmonics = [(1, 1.0, 1.3), (2, 0.52, 1.9), (3, 0.28, 2.5), (4, 0.14, 3.2), (5, 0.07, 4.1)]
    for k, amp, dec in harmonics:
        # Realistic piano string stiffness inharmonicity + subtle eerie chorus detune
        fk = freq * k * math.sqrt(1.0 + 0.00018 * k * k)
        s1 = np.sin(2.0 * np.pi * fk * t)
        s2 = np.sin(2.0 * np.pi * (fk * 1.0028) * t + 0.7)
        out += amp * 0.5 * (s1 + s2) * np.exp(-t * dec)
    # Soft felt hammer thud
    hammer = fft_bandpass(pink_noise(n, 1.0), 180.0, 1400.0) * np.exp(-t * 85.0) * 0.18
    return (out + hammer) * attack


def gen_round_sting():
    # Iconic COD-Zombies ('Damned' / Nacht) style haunting minor piano + sub-bass swell + eerie choir pad!
    dur = 4.2
    n = int(SR * dur)
    t = np.arange(n) / SR
    sig = np.zeros(n, dtype=np.float64)

    # Haunting D-minor piano motif: D4 -> A4 -> Bb4 -> A4 -> F4 -> D3
    melody = [
        (0.05, 293.66, 2.2, 0.58),  # D4
        (0.46, 440.00, 2.0, 0.52),  # A4
        (0.88, 466.16, 2.1, 0.60),  # Bb4 (tense minor b6!)
        (1.36, 440.00, 1.9, 0.50),  # A4
        (1.82, 349.23, 2.1, 0.48),  # F4
        (0.02, 73.42, 3.8, 0.65),   # Deep D2 piano bass octave
        (0.02, 146.83, 3.6, 0.45),  # D3
    ]
    for start_s, f_hz, n_dur, gain in melody:
        idx = int(start_s * SR)
        note = _piano_note(f_hz, min(n_dur, dur - start_s)) * gain
        sig[idx : idx + len(note)] += note

    # Dark cinematic sub-bass swell + ghostly choral whisper pad
    pad_env = np.sin(np.pi * np.clip(t / dur, 0.0, 1.0)) ** 1.3
    choir_src = pink_noise(n, alpha=0.9) * 0.35 + (
        np.sin(2 * np.pi * 146.83 * t) + np.sin(2 * np.pi * 220.0 * t) + np.sin(2 * np.pi * 174.61 * t)
    ) * 0.12
    choir = vocal_tract_stft(choir_src, 520.0, 1180.0, 2450.0, bw=(70.0, 110.0, 190.0), chest_hz=146.0) * pad_env * 0.28

    out = convolve_bunker_reverb(sig + choir, rt60=1.35, wet=0.44, predelay_ms=26.0)
    save_wav("round_sting", out[:n], 0.88)


# ===========================================================================
# 5. MELEE, GRENADES, PLAYER VITALS, ZOMBIE DEATH & SLIDE FOLEY
# ===========================================================================
def gen_melee_grenade_and_player():
    # Knife swing: fast aerodynamic steel blade air slice
    dur_ks = 0.24
    nks = int(SR * dur_ks)
    tks = np.arange(nks) / SR
    whoosh = fft_bandpass(pink_noise(nks, 0.7), 380.0, 4200.0) * np.exp(-((tks - 0.085) ** 2) / 0.0022) * 1.0
    edge = phase_sin(780.0 - 460.0 * (tks / dur_ks)) * np.exp(-((tks - 0.08) ** 2) / 0.0016) * 0.22
    save_wav("knife_swing", whoosh + edge, 0.78)

    # Knife hit: steel blade stab + bone/flesh rip
    dur_kh = 0.26
    nkh = int(SR * dur_kh)
    tkh = np.arange(nkh) / SR
    stab_thud = phase_sin(72.0 + 150.0 * np.exp(-tkh * 52.0)) * np.exp(-tkh * 34.0) * 0.95
    stab_rip = granular_footstep_grit(nkh, 24, 800.0, 5400.0, 0.002, 0.11) * 0.95
    blade_ring = modal_ring(nkh, [2420.0, 4180.0], [45.0, 62.0], [0.16, 0.10])
    save_wav("knife_hit", stab_thud + stab_rip + blade_ring, 0.86)

    # Grenade pin: crisp steel cotter-pin pull + spoon spring ping
    dur_gp = 0.18
    ngp = int(SR * dur_gp)
    s_gp = modal_ring(ngp, [2480.0, 3920.0, 5860.0], [55.0, 72.0, 95.0], [0.50, 0.38, 0.26])
    s_gp += fft_bandpass(pink_noise(ngp, 0.5), 1600.0, 6800.0) * np.exp(-np.linspace(0, 9, ngp)) * 0.35
    save_wav("grenade_pin", s_gp, 0.76)

    # Frag grenade explosion: massive concussion sub-wave + compressed blast + falling concrete debris
    dur_ge = 1.45
    nge = int(SR * dur_ge)
    tge = np.arange(nge) / SR
    g_sub = phase_sin(26.0 + 98.0 * np.exp(-tge * 16.0)) * np.exp(-tge * 4.8) * 1.55
    g_crack = fft_bandpass(pink_noise(nge, 0.4), 900.0, 6800.0) * np.exp(-tge * 32.0) * 1.35
    g_roar = fft_bandpass(pink_noise(nge, 1.25), 45.0, 1650.0) * np.exp(-tge * 4.2) * 1.40
    g_debris = granular_footstep_grit(nge, 65, 650.0, 4600.0, 0.06, 0.85) * 0.75
    raw_ge = np.tanh((g_sub + g_crack + g_roar) * 1.85) + g_debris
    save_wav("grenade_explode", convolve_bunker_reverb(raw_ge, rt60=0.95, wet=0.36, predelay_ms=18.0), 0.96)

    # Zombie death: collapsing undead vocal-fry exhale & throat rattle
    dur_zd = 0.82
    nzd = int(SR * dur_zd)
    tzd = np.arange(nzd) / SR
    env_zd = np.clip(tzd / 0.04, 0.0, 1.0) * np.exp(-tzd * 3.6)
    f0_zd = 108.0 - 54.0 * (tzd / dur_zd)
    src_zd = glottal_fry_source(tzd, f0_zd, fry_amount=0.82, asp_amount=0.88)
    zd_voc = vocal_tract_stft(
        src_zd,
        lambda u: 520.0 - 240.0 * u,
        lambda u: 1180.0 - 480.0 * u,
        lambda u: 2250.0,
        bw=(105.0, 175.0, 280.0),
        chest_hz=110.0,
    ) * env_zd
    save_wav("zombie_death", convolve_bunker_reverb(zd_voc, rt60=0.38, wet=0.20), 0.80)

    # Player hurt: physical punch impact thud + short tight human breath grunt
    dur_ph = 0.30
    nph = int(SR * dur_ph)
    tph = np.arange(nph) / SR
    env_ph = np.clip(tph / 0.02, 0.0, 1.0) * np.exp(-tph * 8.5)
    src_ph = glottal_fry_source(tph, 128.0 - 34.0 * (tph / dur_ph), fry_amount=0.30, asp_amount=0.65)
    grunt = vocal_tract_stft(src_ph, 560.0, 1240.0, 2480.0, bw=(95.0, 150.0, 240.0), chest_hz=135.0) * env_ph * 0.75
    blow = phase_sin(58.0 + 110.0 * np.exp(-tph * 48.0)) * np.exp(-tph * 32.0) * 0.85
    save_wav("player_hurt", grunt + blow, 0.84)

    # Heartbeat: deep realistic cardiac LUB-DUB (zero negative-frequency sweep!)
    dur_hb = 0.85
    nhb = int(SR * dur_hb)
    s_hb = np.zeros(nhb)
    for t0, f_peak, gain in [(0.02, 62.0, 1.0), (0.25, 52.0, 0.74)]:
        idx = int(t0 * SR)
        ln = int(0.18 * SR)
        th = np.arange(ln) / SR
        beat = phase_sin(36.0 + f_peak * np.exp(-th * 28.0)) * np.exp(-th * 20.0) * np.sin(np.pi * np.clip(th / 0.16, 0, 1)) ** 0.5
        s_hb[idx : idx + ln] += beat * gain
    save_wav("heartbeat", s_hb, 0.82)

    # Tactical combat slide: heavy cordura fabric + knee-pad grit friction across concrete
    dur_sl = 0.68
    nsl = int(SR * dur_sl)
    tsl = np.arange(nsl) / SR
    sl_env = np.clip(tsl / 0.035, 0.0, 1.0) * np.exp(-tsl * 3.4)
    sl_cloth = fft_bandpass(pink_noise(nsl, 0.85), 240.0, 2800.0) * sl_env * 0.75
    sl_grit = granular_footstep_grit(nsl, 42, 1100.0, 5600.0, 0.01, 0.48) * 0.65
    sl_thud = phase_sin(55.0 + 85.0 * np.exp(-tsl * 35.0)) * np.exp(-tsl * 24.0) * 0.65
    save_wav("slide", sl_cloth + sl_grit + sl_thud, 0.78)


# ===========================================================================
# 6. WORLD INTERACTIONS, MYSTERY CRATE, POWER, TRAPS & ATMOSPHERIC MUSIC
# ===========================================================================
def _celesta_note(freq: float, dur: float) -> np.ndarray:
    """Haunting COD Mystery Box music-box / celesta bell tine."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    atk = np.clip(t / 0.004, 0.0, 1.0)
    tone = (
        np.sin(2 * np.pi * freq * t) * np.exp(-t * 4.2)
        + 0.35 * np.sin(2 * np.pi * freq * 2.0 * t) * np.exp(-t * 6.5)
        + 0.18 * np.sin(2 * np.pi * freq * 5.42 * t) * np.exp(-t * 18.0)
    )
    mallet = modal_ring(n, [freq * 3.0, 3600.0], [65.0, 95.0], [0.12, 0.08])
    return (tone + mallet) * atk


def gen_world_and_music():
    # Barricade board repair: solid wooden plank THWACK + hammer nail ring
    dur_br = 0.30
    nbr = int(SR * dur_br)
    s_br = np.zeros(nbr)
    for t0, w_f in [(0.005, 165.0), (0.125, 210.0)]:
        idx = int(t0 * SR)
        ln = min(int(0.14 * SR), nbr - idx)
        tb = np.arange(ln) / SR
        wood = modal_ring(ln, [w_f, w_f * 1.62, w_f * 2.45], [38.0, 48.0, 62.0], [0.65, 0.45, 0.28])
        thud = phase_sin(68.0 + 95.0 * np.exp(-tb * 55.0)) * np.exp(-tb * 40.0) * 0.70
        nail = modal_ring(ln, [2850.0, 4320.0], [55.0, 75.0], [0.22, 0.15])
        s_br[idx : idx + ln] += wood + thud + nail
    save_wav("board_repair", convolve_bunker_reverb(s_br, rt60=0.26, wet=0.16), 0.82)

    # Barricade board tear: splintering timber crack + nails wrenching free
    dur_bt = 0.45
    nbt = int(SR * dur_bt)
    tbt = np.arange(nbt) / SR
    splinters = granular_footstep_grit(nbt, 36, 550.0, 4800.0, 0.01, 0.34) * 1.05
    wood_snap = modal_ring(nbt, [145.0, 265.0, 430.0], [18.0, 24.0, 32.0], [0.55, 0.42, 0.30])
    nail_screech = phase_sin(1450.0 - 520.0 * (tbt / dur_bt)) * np.exp(-((tbt - 0.16) ** 2) / 0.012) * 0.18
    save_wav("board_tear", convolve_bunker_reverb(splinters + wood_snap + nail_screech, rt60=0.32, wet=0.18), 0.84)

    # Bunker zone door open: heavy steel latch release + stone/iron grinding slide
    dur_do = 1.55
    ndo = int(SR * dur_do)
    tdo = np.arange(ndo) / SR
    clunk = phase_sin(45.0 + 85.0 * np.exp(-tdo * 28.0)) * np.exp(-tdo * 14.0) * 1.15
    latch_do = modal_ring(ndo, [320.0, 580.0, 1140.0], [16.0, 22.0, 30.0], [0.45, 0.32, 0.20])
    grind_env = np.clip((tdo - 0.12) / 0.15, 0.0, 1.0) * np.exp(-np.maximum(0.0, tdo - 0.35) * 1.6) * (tdo >= 0.12)
    grind = fft_bandpass(pink_noise(ndo, 1.15), 75.0, 880.0) * grind_env * (0.75 + 0.25 * np.sin(2 * np.pi * 13.0 * tdo)) * 0.95
    grit_do = granular_footstep_grit(ndo, 55, 450.0, 2800.0, 0.15, 1.15) * 0.55
    save_wav("door_open", convolve_bunker_reverb(clunk + latch_do + grind + grit_do, rt60=0.65, wet=0.28), 0.88)

    # Mystery Crate open: creaky wooden lid + eerie COD Mystery Box music-box melody!
    dur_co = 4.2
    nco = int(SR * dur_co)
    s_co = np.zeros(nco)
    l_hinge = int(0.45 * SR)
    th_c = np.arange(l_hinge) / SR
    hinge = phase_sin(310.0 + 85.0 * np.sin(2 * np.pi * 6.5 * th_c)) * np.hanning(l_hinge) * 0.22
    hinge += modal_ring(l_hinge, [185.0, 340.0], [12.0, 16.0], [0.35, 0.25])
    s_co[:l_hinge] += hinge
    box_notes = [659.25, 783.99, 987.77, 880.00, 783.99, 659.25, 587.33, 659.25, 783.99, 1046.50, 987.77, 880.00]
    for i, f_n in enumerate(box_notes):
        idx = int((0.32 + i * 0.30) * SR)
        cn = _celesta_note(f_n, min(0.65, dur_co - (0.32 + i * 0.30))) * 0.52
        s_co[idx : idx + len(cn)] += cn
    save_wav("crate_open", convolve_bunker_reverb(s_co, rt60=0.75, wet=0.32)[:nco], 0.82)

    # Crate reveal: shimmering E-minor / B5 celesta chord
    dur_cr = 0.85
    ncr = int(SR * dur_cr)
    s_cr = _celesta_note(659.25, dur_cr) * 0.45 + _celesta_note(987.77, dur_cr) * 0.42 + _celesta_note(1318.51, dur_cr) * 0.38
    save_wav("crate_reveal", convolve_bunker_reverb(s_cr, rt60=0.60, wet=0.30)[:ncr], 0.82)

    # Augment Furnace burn: deep forge fire roar + crackling embers
    dur_fb = 1.05
    nfb = int(SR * dur_fb)
    tfb = np.arange(nfb) / SR
    f_env = np.sin(np.pi * tfb / dur_fb) ** 0.65
    f_whoosh = fft_bandpass(pink_noise(nfb, 1.25), 55.0, 920.0) * f_env * 1.15
    f_embers = granular_footstep_grit(nfb, 38, 1600.0, 7800.0, 0.05, 0.85) * 0.65
    save_wav("furnace_burn", convolve_bunker_reverb(f_whoosh + f_embers, rt60=0.42, wet=0.22), 0.84)

    # Stat Level Up: dark resonant D-major/fifth heroic piano + brass swell
    dur_lu = 1.25
    nlu = int(SR * dur_lu)
    s_lu = np.zeros(nlu)
    for i, f_l in enumerate([293.66, 440.00, 587.33, 880.00]):
        idx = int(i * 0.09 * SR)
        pn = _piano_note(f_l, dur_lu - i * 0.09) * 0.55
        s_lu[idx : idx + len(pn)] += pn
    save_wav("level_up", convolve_bunker_reverb(s_lu, rt60=0.65, wet=0.28)[:nlu], 0.84)

    # Power Generator On: heavy steel breaker CLUNK + smooth turbine spin-up + 60Hz hum
    dur_pw = 2.8
    npw = int(SR * dur_pw)
    tpw = np.arange(npw) / SR
    breaker = phase_sin(42.0 + 95.0 * np.exp(-tpw * 30.0)) * np.exp(-tpw * 16.0) * 1.15
    breaker += modal_ring(npw, [380.0, 740.0, 1480.0], [18.0, 24.0, 34.0], [0.45, 0.35, 0.22])
    # Phase-integrated smooth turbine frequency rise (45 Hz -> 180 Hz)!
    turb_f = 45.0 + 135.0 * np.clip(tpw / 2.2, 0.0, 1.0) ** 1.4
    turbine = (phase_sin(turb_f) * 0.45 + phase_sin(turb_f * 2.0) * 0.25) * np.sin(np.pi * tpw / dur_pw) ** 0.5
    hum_pw = (np.sin(2 * np.pi * 60.0 * tpw) * 0.30 + np.sin(2 * np.pi * 120.0 * tpw) * 0.20) * np.clip((tpw - 0.8) / 0.6, 0.0, 1.0) * np.exp(-np.maximum(0.0, tpw - 2.1) * 3.0)
    sparks = granular_footstep_grit(npw, 28, 2200.0, 8800.0, 0.02, 2.2) * 0.55
    save_wav("power_on", convolve_bunker_reverb(breaker + turbine + hum_pw + sparks, rt60=0.70, wet=0.28)[:npw], 0.88)

    # Electric Trap Zap & Electrocute: transformer hum + authentic corona plasma arcs (NO 1-bit square buzz!)
    dur_tz = 0.95
    ntz = int(SR * dur_tz)
    ttz = np.arange(ntz) / SR
    hum_tz = (
        np.sin(2 * np.pi * 120.0 * ttz) * 0.35
        + np.sin(2 * np.pi * 240.0 * ttz) * 0.25
        + np.sin(2 * np.pi * 360.0 * ttz) * 0.15
    ) * (0.75 + 0.25 * np.sin(2 * np.pi * 8.0 * ttz)) * np.sin(np.pi * ttz / dur_tz) ** 0.3
    arcs_tz = granular_footstep_grit(ntz, 58, 1800.0, 9500.0, 0.01, 0.90) * 1.10
    save_wav("trap_zap", convolve_bunker_reverb(hum_tz + arcs_tz, rt60=0.35, wet=0.20)[:ntz], 0.82)

    dur_el = 0.65
    nel = int(SR * dur_el)
    tel = np.arange(nel) / SR
    el_snap = phase_sin(95.0 + 320.0 * np.exp(-tel * 28.0)) * np.exp(-tel * 16.0) * 0.85
    el_arcs = granular_footstep_grit(nel, 44, 1600.0, 9200.0, 0.002, 0.50) * 1.15
    el_sizz = fft_bandpass(pink_noise(nel, 0.5), 2000.0, 8200.0) * np.exp(-tel * 5.5) * 0.50
    save_wav("electrocute", convolve_bunker_reverb(el_snap + el_arcs + el_sizz, rt60=0.32, wet=0.18), 0.84)

    # Secret Skull shatter: bone/stone fracture + eerie ghostly harmonic chime
    dur_sk = 0.85
    nsk = int(SR * dur_sk)
    s_sk = granular_footstep_grit(nsk, 34, 900.0, 6800.0, 0.002, 0.14) * 1.05
    s_sk += modal_ring(nsk, [587.33, 880.0, 1396.91, 1760.0], [3.5, 4.2, 5.0, 6.5], [0.28, 0.24, 0.18, 0.14])
    save_wav("skull_shatter", convolve_bunker_reverb(s_sk, rt60=0.65, wet=0.32), 0.84)

    # Ambient Loop (32s seamless dark bunker atmosphere — warm low drone, NO harsh wind static, sparse lonely piano)
    dur_amb = 32.0
    namb = int(SR * dur_amb)
    tamb = np.arange(namb) / SR
    # Integer-cycle frequencies over 32.0s guarantee 100% seamless zero-click looping!
    drone_a = (
        0.28 * np.sin(2 * np.pi * (55.0) * tamb)
        + 0.18 * np.sin(2 * np.pi * (82.5) * tamb)
        + 0.12 * np.sin(2 * np.pi * (110.0) * tamb)
    ) * (0.72 + 0.28 * np.sin(2 * np.pi * (2.0 / dur_amb) * tamb))
    # Deep subterranean air draft (strictly low-passed below 340 Hz so zero white-noise hiss!)
    air_draft = fft_bandpass(pink_noise(namb, 1.35), 42.0, 320.0, order=3.0) * 0.22 * (
        0.65 + 0.35 * np.sin(2 * np.pi * (3.0 / dur_amb) * tamb + 1.2)
    )
    amb_sig = drone_a + air_draft
    # Sparse haunting D-minor / A-minor felt piano echoes in the distance
    sparse_notes = [(3.2, 220.0), (8.8, 261.63), (14.5, 233.08), (20.4, 220.0), (26.2, 164.81)]
    for t0, fn in sparse_notes:
        idx = int(t0 * SR)
        pn = convolve_bunker_reverb(_piano_note(fn, 3.6) * 0.24, rt60=1.6, wet=0.65)
        ln = min(len(pn), namb - idx)
        amb_sig[idx : idx + ln] += pn[:ln]
    # Smooth 0.6s loop-boundary taper for click-free wrap
    edge_n = int(0.6 * SR)
    amb_sig[:edge_n] *= np.linspace(0.0, 1.0, edge_n)
    amb_sig[-edge_n:] *= np.linspace(1.0, 0.0, edge_n)
    save_wav("ambient_loop", amb_sig, 0.38)

    # Easter Egg Song (20s dark COD-Zombies inspired driving D-minor instrumental!)
    bpm = 136.0
    beat = 60.0 / bpm
    riff_midi = [
        62, 65, 69, 70, 69, 65, 62, 60,
        62, 65, 69, 72, 70, 69, 65, 67,
        62, 65, 69, 70, 69, 65, 74, 72,
        70, 69, 67, 65, 64, 65, 61, 62,
    ]
    dur_es = beat * len(riff_midi) + 1.8
    nes = int(SR * dur_es)
    s_es = np.zeros(nes)
    for i, m_note in enumerate(riff_midi):
        t0 = i * beat
        idx = int(t0 * SR)
        f_lead = 440.0 * (2.0 ** ((m_note - 69.0) / 12.0))
        # Dark felt piano + warm overdriven guitar harmonic lead (NO harsh sign() square wave!)
        lead = _piano_note(f_lead, beat * 1.35)
        lead_drive = np.tanh(lead * 2.4) * 0.42
        s_es[idx : idx + len(lead_drive)] += lead_drive
        # Driving octave sub-bass pulse
        f_bass = f_lead * 0.25
        nb_len = int(beat * 0.92 * SR)
        tb_e = np.arange(nb_len) / SR
        bass = np.tanh((np.sin(2 * np.pi * f_bass * tb_e) + 0.5 * np.sin(4 * np.pi * f_bass * tb_e)) * 1.8) * np.exp(-tb_e * 4.5) * 0.45
        s_es[idx : idx + nb_len] += bass
        # Tight phase-integrated rock kick on every beat, crisp snare on odd beats
        nk_len = int(0.20 * SR)
        tk_e = np.arange(nk_len) / SR
        kick = phase_sin(46.0 + 115.0 * np.exp(-tk_e * 38.0)) * np.exp(-tk_e * 18.0) * 0.65
        s_es[idx : idx + nk_len] += kick
        if i % 2 == 1:
            snare = (
                fft_bandpass(pink_noise(nk_len, 0.55), 350.0, 5800.0) * np.exp(-tk_e * 24.0) * 0.48
                + phase_sin(165.0 + 90.0 * np.exp(-tk_e * 45.0)) * np.exp(-tk_e * 32.0) * 0.35
            )
            s_es[idx : idx + nk_len] += snare
    save_wav("easter_song", convolve_bunker_reverb(s_es, rt60=0.65, wet=0.26)[:nes], 0.86)


if __name__ == "__main__":
    gen_pistol()
    gen_rifle()
    gen_shotgun()
    gen_extra_weapons()
    gen_enemy_shot()
    gen_reload()
    gen_hit_feedback()
    gen_footsteps()
    gen_zombie_vocals()
    gen_abilities_and_slams()
    gen_buy_ching()
    gen_round_sting()
    gen_melee_grenade_and_player()
    gen_world_and_music()
    print("Generated complete 61-clip studio-grade acoustic SFX library in:", OUT_DIR)
