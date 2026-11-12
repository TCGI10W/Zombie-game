"""Generate bespoke 1024x1024 tileable PBR texture sets (_albedo, _normal, _rough)
for the v7 Zombie, Hound, and Boss 3D models:
  - necrotic_flesh : decayed undead skin with dermal pores, lividity bruising, dark veins, scabs
  - bloater_flesh  : distended toxic bile-skin with stretched striae, dark capillaries, wet sheen
  - gorilla_fur    : dense directional coarse ape fur strands with deep strand normal relief
  - panzer_steel   : battle-scarred dieselpunk rolled armor steel with pitting & brushed grain
  - plague_hazmat  : weathered vulcanized bio-suit fabric/rubber with chemical stains & creases
"""
import math
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX_DIR = os.path.join(ROOT, "assets", "textures")
os.makedirs(TEX_DIR, exist_ok=True)

SIZE = 1024


def tileable_fbm(size, base_freq=4, octaves=6, persistence=0.52, seed=42, aniso=(1.0, 1.0)):
    """Fast FFT-based seamlessly tileable multi-octave noise in [0, 1]."""
    rng = np.random.default_rng(seed)
    acc = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    total_amp = 0.0
    ky = np.fft.fftfreq(size) * size
    kx = np.fft.fftfreq(size) * size
    KX, KY = np.meshgrid(kx, ky)

    for o in range(octaves):
        f = base_freq * (2 ** o)
        fx = max(1.0, f * aniso[0])
        fy = max(1.0, f * aniso[1])
        # Band-pass spectral ring around target frequency so it tiles 100% seamlessly
        rad = np.sqrt((KX / fx) ** 2 + (KY / fy) ** 2)
        env = np.exp(-((rad - 1.0) ** 2) / 0.38) * (rad > 0.15)
        phase = rng.uniform(0.0, 2.0 * math.pi, (size, size))
        spec = env * (np.cos(phase) + 1j * np.sin(phase))
        layer = np.fft.ifft2(spec).real.astype(np.float32)
        std = float(layer.std())
        if std > 1e-6:
            layer /= std
        acc += layer * amp
        total_amp += amp
        amp *= persistence

    acc /= max(total_amp, 1e-6)
    lo, hi = np.percentile(acc, 1.0), np.percentile(acc, 99.0)
    return np.clip((acc - lo) / max(hi - lo, 1e-5), 0.0, 1.0)


def ridge_veins(size, freq=5, octaves=4, seed=101, sharpness=3.0):
    """Tileable branching ridged-multifractal vein / crease mask in [0, 1]."""
    n1 = tileable_fbm(size, base_freq=freq, octaves=octaves, persistence=0.55, seed=seed)
    n2 = tileable_fbm(size, base_freq=freq * 2, octaves=octaves, persistence=0.5, seed=seed + 17)
    r1 = 1.0 - np.abs(n1 * 2.0 - 1.0)
    r2 = 1.0 - np.abs(n2 * 2.0 - 1.0)
    veins = (r1 ** sharpness) * 0.72 + (r2 ** (sharpness + 1.0)) * 0.45
    return np.clip(veins, 0.0, 1.0)


def height_to_normal(height, strength=2.5):
    """Convert [0,1] tileable height map to OpenGL (Y+) tangent-space RGB normal map."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    nx = -dx
    ny = dy  # OpenGL Y+ convention
    nz = np.ones_like(height)
    inv_len = 1.0 / np.maximum(np.sqrt(nx * nx + ny * ny + nz * nz), 1e-6)
    rgb = np.stack([(nx * inv_len) * 0.5 + 0.5, (ny * inv_len) * 0.5 + 0.5, (nz * inv_len) * 0.5 + 0.5], axis=-1)
    return np.clip(rgb, 0.0, 1.0)


def save_pbr(prefix, albedo, height, rough, normal_strength=2.6):
    albedo_u8 = (np.clip(albedo, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    rough_u8 = (np.clip(rough, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    height_u8 = (np.clip(height, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    norm_rgb = height_to_normal(height, strength=normal_strength)
    norm_u8 = (norm_rgb * 255.0 + 0.5).astype(np.uint8)

    Image.fromarray(albedo_u8, "RGB").save(os.path.join(TEX_DIR, f"{prefix}_albedo.png"), optimize=True)
    Image.fromarray(norm_u8, "RGB").save(os.path.join(TEX_DIR, f"{prefix}_normal.png"), optimize=True)
    Image.fromarray(rough_u8, "L").save(os.path.join(TEX_DIR, f"{prefix}_rough.png"), optimize=True)
    Image.fromarray(height_u8, "L").save(os.path.join(TEX_DIR, f"{prefix}_height.png"), optimize=True)
    print(f"Generated PBR set: {prefix}")


def build_necrotic_flesh():
    macro = tileable_fbm(SIZE, base_freq=3, octaves=5, seed=11)
    bruise = tileable_fbm(SIZE, base_freq=5, octaves=5, seed=23)
    pores = tileable_fbm(SIZE, base_freq=42, octaves=3, seed=37)
    wrinkle = tileable_fbm(SIZE, base_freq=16, octaves=4, seed=49, aniso=(1.8, 0.7))
    veins = ridge_veins(SIZE, freq=4, octaves=4, seed=61, sharpness=9.5)
    scabs = np.clip((tileable_fbm(SIZE, base_freq=8, octaves=5, seed=79) - 0.79) * 4.8, 0.0, 1.0)

    # Pallid corpse grey-olive base with purple-blue livor mortis bruising & dark crimson scabs
    pale = np.array([0.60, 0.62, 0.53], np.float32)
    sallow = np.array([0.46, 0.48, 0.39], np.float32)
    livid = np.array([0.34, 0.27, 0.35], np.float32)
    vein_col = np.array([0.20, 0.16, 0.24], np.float32)
    scab_col = np.array([0.24, 0.04, 0.035], np.float32)

    albedo = pale[None, None, :] * (1.0 - macro[..., None]) + sallow[None, None, :] * macro[..., None]
    b_mask = np.clip((bruise - 0.50) * 1.9, 0.0, 1.0)[..., None]
    albedo = albedo * (1.0 - b_mask * 0.52) + livid[None, None, :] * (b_mask * 0.52)
    v_mask = np.clip(veins * macro * 1.1, 0.0, 1.0)[..., None]
    albedo = albedo * (1.0 - v_mask * 0.48) + vein_col[None, None, :] * (v_mask * 0.48)
    albedo *= (0.91 + 0.16 * pores[..., None])
    s_mask = (scabs ** 1.5)[..., None]
    albedo = albedo * (1.0 - s_mask * 0.82) + scab_col[None, None, :] * (s_mask * 0.82)

    height = 0.52 + 0.20 * (wrinkle - 0.5) - 0.14 * (1.0 - pores) + 0.10 * veins - 0.20 * scabs
    rough = 0.68 + 0.18 * (1.0 - macro) - 0.34 * scabs - 0.10 * veins
    save_pbr("necrotic_flesh", albedo, np.clip(height, 0, 1), np.clip(rough, 0.18, 0.92), normal_strength=3.2)


def build_bloater_flesh():
    macro = tileable_fbm(SIZE, base_freq=3, octaves=5, seed=112)
    striae = tileable_fbm(SIZE, base_freq=14, octaves=4, seed=128, aniso=(2.4, 0.55))
    veins = ridge_veins(SIZE, freq=5, octaves=4, seed=145, sharpness=4.8)
    blisters = np.clip((tileable_fbm(SIZE, base_freq=11, octaves=4, seed=163) - 0.68) * 3.6, 0.0, 1.0)

    putrid = np.array([0.58, 0.60, 0.38], np.float32)
    bile = np.array([0.66, 0.68, 0.32], np.float32)
    toxic_vein = np.array([0.18, 0.24, 0.11], np.float32)
    pus_tint = np.array([0.74, 0.84, 0.30], np.float32)

    albedo = putrid[None, None, :] * (1.0 - macro[..., None]) + bile[None, None, :] * macro[..., None]
    v_mask = np.clip(veins * 1.2, 0.0, 1.0)[..., None]
    albedo = albedo * (1.0 - v_mask * 0.72) + toxic_vein[None, None, :] * (v_mask * 0.72)
    bl_mask = (blisters ** 1.3)[..., None]
    albedo = albedo * (1.0 - bl_mask * 0.65) + pus_tint[None, None, :] * (bl_mask * 0.65)

    height = 0.48 + 0.18 * (striae - 0.5) + 0.22 * veins + 0.30 * blisters
    rough = 0.44 + 0.22 * (1.0 - striae) - 0.24 * blisters
    save_pbr("bloater_flesh", albedo, np.clip(height, 0, 1), np.clip(rough, 0.14, 0.80), normal_strength=3.4)


def build_gorilla_fur():
    # Vertical V-aligned coarse hair strands with clumping & wave!
    y = np.linspace(0, 2 * math.pi, SIZE, endpoint=False)[:, None]
    x = np.linspace(0, 2 * math.pi, SIZE, endpoint=False)[None, :]
    wave = tileable_fbm(SIZE, base_freq=6, octaves=4, seed=205) * 0.35
    fine_strands = tileable_fbm(SIZE, base_freq=28, octaves=4, seed=219, aniso=(3.8, 0.32))
    clumps = tileable_fbm(SIZE, base_freq=11, octaves=4, seed=233, aniso=(2.5, 0.45))
    macro = tileable_fbm(SIZE, base_freq=3, octaves=4, seed=251)
    comb = 0.5 + 0.5 * np.sin((x + wave * 1.4) * 52.0 + np.sin(y * 6.0) * 1.8)

    fur_val = fine_strands * 0.52 + clumps * 0.33 + comb * 0.15
    root_col = np.array([0.11, 0.10, 0.10], np.float32)
    tip_col = np.array([0.36, 0.35, 0.34], np.float32)
    warm_col = np.array([0.24, 0.20, 0.18], np.float32)

    albedo = root_col[None, None, :] * (1.0 - fur_val[..., None]) + tip_col[None, None, :] * fur_val[..., None]
    albedo = albedo * (0.82 + 0.32 * macro[..., None]) + warm_col[None, None, :] * 0.06
    height = np.clip(fur_val * 0.78 + clumps * 0.22, 0.0, 1.0)
    rough = np.clip(0.84 - 0.26 * fur_val + 0.08 * (1.0 - macro), 0.42, 0.95)
    save_pbr("gorilla_fur", albedo, height, rough, normal_strength=4.2)


def build_panzer_steel():
    # Rolled industrial armor steel: moderate metallic charcoal-olive-grey with subtle rust & scratches
    grain = tileable_fbm(SIZE, base_freq=22, octaves=4, seed=307, aniso=(2.6, 0.6))
    pits = tileable_fbm(SIZE, base_freq=32, octaves=4, seed=319)
    macro = tileable_fbm(SIZE, base_freq=4, octaves=5, seed=331)
    scratches = ridge_veins(SIZE, freq=14, octaves=3, seed=347, sharpness=7.0)
    rust = np.clip((tileable_fbm(SIZE, base_freq=7, octaves=5, seed=359) - 0.64) * 2.8, 0.0, 1.0)

    steel_dark = np.array([0.34, 0.36, 0.38], np.float32)
    steel_bright = np.array([0.58, 0.60, 0.63], np.float32)
    rust_col = np.array([0.42, 0.22, 0.12], np.float32)

    albedo = steel_dark[None, None, :] * (1.0 - macro[..., None]) + steel_bright[None, None, :] * macro[..., None]
    albedo *= (0.88 + 0.22 * grain[..., None])
    albedo = np.clip(albedo + scratches[..., None] * 0.22, 0.0, 1.0)
    r_mask = (rust ** 1.3)[..., None]
    albedo = albedo * (1.0 - r_mask * 0.70) + rust_col[None, None, :] * (r_mask * 0.70)

    height = np.clip(0.55 + 0.16 * (grain - 0.5) - 0.22 * (pits < 0.22).astype(np.float32) * (0.22 - pits) * 4.0 - 0.18 * scratches - 0.12 * rust, 0.0, 1.0)
    rough = np.clip(0.36 + 0.18 * (1.0 - grain) - 0.14 * scratches + 0.42 * rust, 0.18, 0.90)
    save_pbr("panzer_steel", albedo, height, rough, normal_strength=2.8)


def build_plague_hazmat():
    weave = tileable_fbm(SIZE, base_freq=44, octaves=2, seed=401)
    folds = tileable_fbm(SIZE, base_freq=8, octaves=4, seed=419, aniso=(1.8, 0.75))
    grime = tileable_fbm(SIZE, base_freq=5, octaves=5, seed=433)
    chem = np.clip((tileable_fbm(SIZE, base_freq=9, octaves=4, seed=449) - 0.66) * 3.0, 0.0, 1.0)

    base = np.array([0.56, 0.52, 0.30], np.float32)
    dirty = np.array([0.28, 0.26, 0.17], np.float32)
    acid_stain = np.array([0.34, 0.48, 0.20], np.float32)

    albedo = dirty[None, None, :] * (1.0 - grime[..., None]) + base[None, None, :] * grime[..., None]
    albedo *= (0.90 + 0.18 * folds[..., None]) * (0.94 + 0.12 * weave[..., None])
    c_mask = (chem ** 1.2)[..., None]
    albedo = albedo * (1.0 - c_mask * 0.55) + acid_stain[None, None, :] * (c_mask * 0.55)

    height = np.clip(0.50 + 0.28 * (folds - 0.5) + 0.10 * (weave - 0.5) - 0.12 * chem, 0.0, 1.0)
    rough = np.clip(0.52 + 0.26 * (1.0 - grime) - 0.22 * chem, 0.22, 0.88)
    save_pbr("plague_hazmat", albedo, height, rough, normal_strength=2.8)


if __name__ == "__main__":
    build_necrotic_flesh()
    build_bloater_flesh()
    build_gorilla_fur()
    build_panzer_steel()
    build_plague_hazmat()
    print("ALL V7 PBR TEXTURE SETS GENERATED!")
