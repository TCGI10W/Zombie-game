import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "textures")
os.makedirs(OUT_DIR, exist_ok=True)

rng = np.random.default_rng(42)


def tileable_noise(size: int, scale: int, seed_offset: int = 0) -> np.ndarray:
    """Generate smooth tileable multi-octave value noise in [0, 1]."""
    local_rng = np.random.default_rng(100 + seed_offset)
    result = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    total_amp = 0.0
    freq = scale
    while freq <= size // 2:
        grid = local_rng.random((freq, freq), dtype=np.float32)
        # Tile pad by wrapping 1 pixel then resizing with bicubic
        padded = np.pad(grid, ((0, 1), (0, 1)), mode="wrap")
        img = Image.fromarray((padded * 255).astype(np.uint8), mode="L")
        up = img.resize((size + size // freq, size + size // freq), Image.Resampling.BICUBIC)
        arr = np.asarray(up, dtype=np.float32)[:size, :size] / 255.0
        result += arr * amp
        total_amp += amp
        amp *= 0.5
        freq *= 2
    return np.clip(result / max(total_amp, 1e-5), 0.0, 1.0)


def height_to_normal(height: np.ndarray, strength: float = 3.0) -> Image.Image:
    """Convert a [0, 1] heightfield into an OpenGL tangent-space normal map."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    dz = np.ones_like(height)
    norm = np.sqrt(dx * dx + dy * dy + dz * dz)
    nx = (-dx / norm * 0.5 + 0.5) * 255.0
    ny = (-dy / norm * 0.5 + 0.5) * 255.0
    nz = (dz / norm * 0.5 + 0.5) * 255.0
    rgb = np.stack([nx, ny, nz], axis=-1).astype(np.uint8)
    return Image.fromarray(rgb, mode="RGB")


def save_pbr_set(name: str, albedo: np.ndarray, height: np.ndarray, rough: np.ndarray, normal_strength: float = 3.5):
    Image.fromarray(np.clip(albedo * 255, 0, 255).astype(np.uint8), mode="RGB").save(
        os.path.join(OUT_DIR, f"{name}_albedo.png")
    )
    height_to_normal(height, normal_strength).save(os.path.join(OUT_DIR, f"{name}_normal.png"))
    Image.fromarray(np.clip(rough * 255, 0, 255).astype(np.uint8), mode="L").save(
        os.path.join(OUT_DIR, f"{name}_rough.png")
    )


def build_asphalt_wet():
    size = 512
    n1 = tileable_noise(size, 8, 1)
    n2 = tileable_noise(size, 32, 2)
    pebbles = rng.random((size, size), dtype=np.float32) * 0.18
    puddles = np.clip((tileable_noise(size, 4, 3) - 0.56) * 4.5, 0.0, 1.0)

    height = np.clip(n1 * 0.5 + n2 * 0.35 + pebbles, 0.0, 1.0) * (1.0 - puddles * 0.85)
    base = 0.09 + n1 * 0.07 + n2 * 0.04 + pebbles * 0.12
    base = base * (1.0 - puddles * 0.45)
    albedo = np.stack([base * 0.96, base * 0.98, base * 1.06], axis=-1)
    rough = np.clip(0.84 - puddles * 0.68 + n2 * 0.1, 0.10, 0.95)
    save_pbr_set("asphalt", albedo, height, rough, normal_strength=4.0)


def build_bunker_concrete():
    size = 512
    n1 = tileable_noise(size, 6, 10)
    n2 = tileable_noise(size, 24, 11)
    y_coords = np.linspace(0, 1, size, dtype=np.float32)[:, None]
    # Formwork horizontal seams & grime at bottom
    seams = np.where((np.mod(y_coords * 4.0, 1.0) < 0.025), -0.25, 0.0)
    grime = np.clip((y_coords - 0.55) * 1.4, 0.0, 0.55) * n1

    height = np.clip(0.5 + (n1 - 0.5) * 0.4 + (n2 - 0.5) * 0.28 + seams, 0.0, 1.0)
    val = 0.24 + n1 * 0.11 + n2 * 0.06 - grime * 0.16 + seams * 0.12
    # Subtle dried blood/rust stains
    stain = np.clip((tileable_noise(size, 5, 12) - 0.68) * 3.0, 0.0, 1.0)
    r = val * 1.02 + stain * 0.04
    g = val * 0.99 - stain * 0.04
    b = val * 0.95 - stain * 0.05
    albedo = np.stack([r, g, b], axis=-1)
    rough = np.clip(0.82 + n2 * 0.12 - stain * 0.15, 0.35, 0.98)
    save_pbr_set("concrete", albedo, height, rough, normal_strength=4.5)


def build_rusted_metal():
    size = 512
    n1 = tileable_noise(size, 8, 20)
    n2 = tileable_noise(size, 32, 21)
    x_coords = np.linspace(0, 1, size, dtype=np.float32)[None, :]
    ribs = np.sin(x_coords * math.pi * 16.0) * 0.25
    rust = np.clip((n1 * 0.7 + n2 * 0.3 - 0.50) * 3.5, 0.0, 1.0)

    height = np.clip(0.5 + ribs + n2 * 0.15 - rust * 0.12, 0.0, 1.0)
    steel = 0.22 + n2 * 0.09
    r = steel * (1.0 - rust) + (0.36 + n2 * 0.1) * rust
    g = steel * (1.0 - rust) + (0.16 + n2 * 0.05) * rust
    b = steel * 1.05 * (1.0 - rust) + 0.08 * rust
    albedo = np.stack([r, g, b], axis=-1)
    rough = np.clip(0.36 * (1.0 - rust) + 0.88 * rust + n2 * 0.08, 0.22, 0.96)
    save_pbr_set("rusted_metal", albedo, height, rough, normal_strength=5.0)


def build_wood_planks():
    size = 512
    n1 = tileable_noise(size, 8, 30)
    grain = tileable_noise(size, 64, 31)
    y_coords = np.linspace(0, 1, size, dtype=np.float32)[:, None]
    gaps = np.where(np.mod(y_coords * 6.0, 1.0) < 0.035, 0.0, 1.0)

    height = np.clip((0.45 + grain * 0.3 + n1 * 0.2) * gaps, 0.0, 1.0)
    base = (0.22 + n1 * 0.09 + grain * 0.06) * (0.25 + 0.75 * gaps)
    albedo = np.stack([base * 1.25, base * 0.88, base * 0.56], axis=-1)
    rough = np.clip(0.78 + grain * 0.14, 0.5, 0.97)
    save_pbr_set("wood_planks", albedo, height, rough, normal_strength=4.0)


def build_zombie_flesh():
    size = 256
    n1 = tileable_noise(size, 8, 40)
    veins = np.abs(tileable_noise(size, 16, 41) - 0.5) * 2.0
    vein_mask = np.clip(1.0 - veins * 4.5, 0.0, 1.0)
    rot = np.clip((tileable_noise(size, 6, 42) - 0.55) * 3.0, 0.0, 1.0)

    height = np.clip(0.5 + n1 * 0.3 - rot * 0.25 + vein_mask * 0.15, 0.0, 1.0)
    r = 0.28 + n1 * 0.10 + rot * 0.14 + vein_mask * 0.12
    g = 0.31 + n1 * 0.11 - rot * 0.12 - vein_mask * 0.08
    b = 0.23 + n1 * 0.07 - rot * 0.08 - vein_mask * 0.05
    albedo = np.stack([r, g, b], axis=-1)
    rough = np.clip(0.68 - rot * 0.25 + n1 * 0.15, 0.28, 0.92)
    save_pbr_set("zombie_skin", albedo, height, rough, normal_strength=3.5)


def build_gorilla_hide():
    size = 256
    n1 = tileable_noise(size, 8, 50)
    fur = tileable_noise(size, 48, 51)
    silver = np.clip((tileable_noise(size, 4, 52) - 0.48) * 2.2, 0.0, 1.0)

    height = np.clip(0.4 + fur * 0.42 + n1 * 0.18, 0.0, 1.0)
    val = 0.10 + fur * 0.08 + silver * 0.26
    albedo = np.stack([val * 1.02, val * 1.0, val * 1.05], axis=-1)
    rough = np.clip(0.80 + fur * 0.12 - silver * 0.1, 0.55, 0.96)
    save_pbr_set("gorilla_hide", albedo, height, rough, normal_strength=4.2)


def build_monster_scales():
    size = 256
    n1 = tileable_noise(size, 12, 60)
    cracks = np.clip(1.0 - np.abs(tileable_noise(size, 16, 61) - 0.5) * 7.0, 0.0, 1.0)

    height = np.clip(0.6 + n1 * 0.35 - cracks * 0.45, 0.0, 1.0)
    r = 0.11 + n1 * 0.06 + cracks * 0.65
    g = 0.06 + n1 * 0.03 + cracks * 0.10
    b = 0.08 + n1 * 0.04 + cracks * 0.06
    albedo = np.stack([r, g, b], axis=-1)
    rough = np.clip(0.48 + n1 * 0.22 - cracks * 0.2, 0.2, 0.85)
    save_pbr_set("monster_scales", albedo, height, rough, normal_strength=5.0)


def build_ui_overlays():
    # Blood splatter screen vignette for COD Zombies low-HP feedback
    w, h = 1024, 576
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx / w) * 2.0 - 1.0
    ny = (yy / h) * 2.0 - 1.0
    dist = np.sqrt(nx * nx * 0.85 + ny * ny * 1.15)

    n = np.asarray(
        Image.fromarray((rng.random((64, 114)) * 255).astype(np.uint8), mode="L").resize(
            (w, h), Image.Resampling.BICUBIC
        ),
        dtype=np.float32,
    ) / 255.0

    alpha = np.clip((dist - 0.62 + (n - 0.5) * 0.38) * 2.4, 0.0, 1.0) ** 1.4
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[..., 0] = np.clip((125 + n * 75), 0, 255).astype(np.uint8)
    rgba[..., 1] = np.clip((8 + n * 15), 0, 255).astype(np.uint8)
    rgba[..., 2] = np.clip((10 + n * 12), 0, 255).astype(np.uint8)
    rgba[..., 3] = np.clip(alpha * 235, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, mode="RGBA").save(os.path.join(OUT_DIR, "blood_vignette.png"))

    # Monster / Rage crimson-amber edge vignette (clean subtle outer rim)
    rgba_m = np.zeros((h, w, 4), dtype=np.uint8)
    alpha_m = np.clip((dist - 0.82 + (n - 0.5) * 0.12) * 2.4, 0.0, 1.0) ** 1.7
    rgba_m[..., 0] = 225
    rgba_m[..., 1] = 42
    rgba_m[..., 2] = 14
    rgba_m[..., 3] = np.clip(alpha_m * 130, 0, 255).astype(np.uint8)
    Image.fromarray(rgba_m, mode="RGBA").save(os.path.join(OUT_DIR, "monster_vignette.png"))

    # Soft radial particle glow sprite (for fire, muzzle flash, stun stars, pain drug mist)
    ps = 128
    py, px = np.mgrid[0:ps, 0:ps].astype(np.float32)
    pr = np.sqrt(((px - ps / 2) / (ps / 2)) ** 2 + ((py - ps / 2) / (ps / 2)) ** 2)
    pa = np.clip(1.0 - pr, 0.0, 1.0) ** 2.2
    p_rgba = np.full((ps, ps, 4), 255, dtype=np.uint8)
    p_rgba[..., 3] = (pa * 255).astype(np.uint8)
    Image.fromarray(p_rgba, mode="RGBA").save(os.path.join(OUT_DIR, "soft_particle.png"))


if __name__ == "__main__":
    build_asphalt_wet()
    build_bunker_concrete()
    build_rusted_metal()
    build_wood_planks()
    build_zombie_flesh()
    build_gorilla_hide()
    build_monster_scales()
    build_ui_overlays()
    print("Generated all PBR texture sets and UI overlays in:", OUT_DIR)
