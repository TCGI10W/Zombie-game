"""Third batch of textures: cloth materials for the new zombies and arms,
plus decals (blood, bullet holes, scorch) and effect sprites (muzzle flash).
Run with: python tools/generate_textures_v2.py
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_textures import OUT_DIR, save_pbr_set, tileable_noise  # noqa: E402

rng = np.random.default_rng(7)


def build_fabric():
    size = 256
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    weave = (np.sin(xx * np.pi / 2.0) * np.sin(yy * np.pi / 2.0)) * 0.5 + 0.5
    n = tileable_noise(size, 8, 70)
    grime = np.clip((tileable_noise(size, 4, 71) - 0.45) * 2.5, 0, 1)
    height = np.clip(0.5 + weave * 0.3 + n * 0.2, 0, 1)
    v = 0.62 + n * 0.18 + weave * 0.08 - grime * 0.35
    albedo = np.stack([v, v, v], axis=-1)
    rough = np.clip(0.85 + n * 0.1, 0, 1)
    save_pbr_set("fabric", albedo, height, rough, normal_strength=2.5)


def build_denim():
    size = 256
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    twill = (np.sin((xx + yy) * np.pi / 3.0) * 0.5 + 0.5)
    n = tileable_noise(size, 16, 72)
    fade = tileable_noise(size, 4, 73)
    height = np.clip(0.5 + twill * 0.35 + n * 0.15, 0, 1)
    r = 0.16 + n * 0.08 + fade * 0.12
    g = 0.22 + n * 0.08 + fade * 0.13
    b = 0.36 + n * 0.1 + fade * 0.14
    albedo = np.stack([r, g, b], axis=-1) * (0.85 + twill[..., None] * 0.2)
    rough = np.clip(0.88 + n * 0.08, 0, 1)
    save_pbr_set("denim", albedo, height, rough, normal_strength=2.8)


def build_camo():
    size = 256
    a = tileable_noise(size, 4, 74)
    b = tileable_noise(size, 6, 75)
    c = tileable_noise(size, 8, 76)
    weave = tileable_noise(size, 64, 77)
    col = np.zeros((size, size, 3), np.float32)
    col[:] = (0.30, 0.32, 0.20)
    col[a > 0.55] = (0.20, 0.22, 0.13)
    col[b > 0.6] = (0.40, 0.36, 0.25)
    col[c > 0.65] = (0.12, 0.12, 0.09)
    col *= (0.9 + weave[..., None] * 0.2)
    height = np.clip(0.5 + weave * 0.4, 0, 1)
    rough = np.full((size, size), 0.9, np.float32)
    save_pbr_set("camo", col, height, rough, normal_strength=2.0)


def build_leather():
    size = 256
    n = tileable_noise(size, 32, 78)
    creases = np.clip(1.0 - np.abs(tileable_noise(size, 8, 79) - 0.5) * 9.0, 0, 1)
    height = np.clip(0.6 + n * 0.3 - creases * 0.4, 0, 1)
    v = 0.09 + n * 0.05 - creases * 0.03
    albedo = np.stack([v * 1.1, v, v * 0.9], axis=-1)
    rough = np.clip(0.55 + n * 0.2 + creases * 0.2, 0, 1)
    save_pbr_set("leather", albedo, height, rough, normal_strength=3.0)


def _save_rgba(name, rgba):
    Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), mode="RGBA").save(os.path.join(OUT_DIR, name + ".png"))


def build_blood_decals():
    for k in range(3):
        size = 256
        img = Image.new("L", (size, size), 0)
        d = ImageDraw.Draw(img)
        local = np.random.default_rng(90 + k)
        c = size / 2
        d.ellipse([c - 50, c - 45, c + 50, c + 45], fill=255)
        for _ in range(28):
            ang = local.random() * np.pi * 2
            dist = local.uniform(30, 115)
            r = local.uniform(3, 16) * (1.2 - dist / 140)
            x, y = c + np.cos(ang) * dist, c + np.sin(ang) * dist
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
            # streak back toward the center
            d.line([c + np.cos(ang) * 40, c + np.sin(ang) * 40, x, y], fill=255, width=max(1, int(r * 0.8)))
        img = img.filter(ImageFilter.GaussianBlur(1.5))
        a = np.asarray(img, np.float32) / 255.0
        n = tileable_noise(size, 16, 95 + k)
        alpha = np.clip(a * 1.4 - 0.2, 0, 1) * (0.75 + n * 0.25)
        rgba = np.zeros((size, size, 4), np.float32)
        rgba[..., 0] = 70 + n * 45
        rgba[..., 1] = 4 + n * 6
        rgba[..., 2] = 4 + n * 6
        rgba[..., 3] = alpha * 240
        _save_rgba("decal_blood_%d" % (k + 1), rgba)


def build_bullet_hole():
    size = 64
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size / 2 - 0.5
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2)
    ang = np.arctan2(yy - c, xx - c)
    cracks = np.clip(1.0 - np.abs(np.sin(ang * 5.0 + 0.7)) * 6.0, 0, 1) * np.clip(1.0 - r / 26.0, 0, 1)
    hole = np.clip(1.0 - (r - 4.0) / 3.0, 0, 1)
    ring = np.clip(1.0 - np.abs(r - 8.0) / 5.0, 0, 1) * 0.6
    alpha = np.clip(hole + ring + cracks * 0.7, 0, 1)
    v = np.clip(20 + (1 - hole) * 40, 0, 255)
    rgba = np.stack([v, v * 0.95, v * 0.9, alpha * 255], axis=-1)
    _save_rgba("decal_bullet_hole", rgba)


def build_scorch():
    size = 128
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size / 2
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / c
    n = tileable_noise(size, 8, 99)
    alpha = np.clip(1.1 - r - (n - 0.5) * 0.6, 0, 1) ** 1.3
    rgba = np.stack([np.full_like(r, 18), np.full_like(r, 14), np.full_like(r, 12), alpha * 230], axis=-1)
    _save_rgba("decal_scorch", rgba)


def build_muzzle_flash():
    size = 128
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size / 2 - 0.5
    dx, dy = (xx - c) / c, (yy - c) / c
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    spikes = np.clip(np.cos(ang * 4.0) ** 8, 0, 1) * 0.7 + np.clip(np.cos(ang * 4.0 + np.pi / 4) ** 16, 0, 1) * 0.35
    core = np.clip(1.0 - r * 3.0, 0, 1)
    star = np.clip((spikes + 0.15) * np.clip(1.0 - r, 0, 1) ** 1.5, 0, 1)
    a = np.clip(core + star, 0, 1)
    rgba = np.stack([np.full_like(a, 255), 200 + core * 55, 120 + core * 135, a * 255], axis=-1)
    _save_rgba("fx_muzzle_flash", rgba)
    # Side view (cone-shaped flash for crossed quads)
    sx = np.clip(1.0 - np.abs(dy) / (0.15 + (xx / size) * 0.55), 0, 1) * np.clip(1.0 - xx / size, 0, 1) ** 0.6
    sx *= 0.8 + 0.2 * np.sin(xx * 0.7)
    rgba2 = np.stack([np.full_like(sx, 255), 190 + sx * 65, 110 + sx * 145, np.clip(sx, 0, 1) * 255], axis=-1)
    _save_rgba("fx_muzzle_side", rgba2)


if __name__ == "__main__":
    build_fabric()
    build_denim()
    build_camo()
    build_leather()
    build_blood_decals()
    build_bullet_hole()
    build_scorch()
    build_muzzle_flash()
    print("Generated v2 textures")
