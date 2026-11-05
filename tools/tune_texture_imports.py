"""Godot import settings for the PBR texture maps: GPU (VRAM) compression,
mipmaps, and normal maps flagged as normal maps.

The map materials are built by scripts at runtime, so Godot's "used in 3D"
detection never kicks in and these maps would otherwise import uncompressed
with no mipmaps: distant floors and walls shimmer and VRAM use balloons.

Covers assets/textures/<set>_{albedo,normal,rough,height}.png and every
texture extracted from the models in assets/models. Run it after new
textures or models have been imported once, then re-import:

    python tools/tune_texture_imports.py
    godot --headless --path . --import
"""
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_SUFFIXES = ("_albedo", "_normal", "_rough", "_height")


def targets():
    for p in sorted(glob.glob(os.path.join(ROOT, "assets", "textures", "*.png.import"))):
        stem = os.path.basename(p)[: -len(".png.import")]
        if stem.endswith(MAP_SUFFIXES):
            yield p, stem, True
    for ext in ("webp", "png", "jpg"):
        for p in sorted(glob.glob(os.path.join(ROOT, "assets", "models", "*.%s.import" % ext))):
            yield p, os.path.basename(p)[: -len(".%s.import" % ext)], False


def wanted_params(stem, world):
    normal = "_normal" in stem
    single = stem.endswith(("_rough", "_height")) or "_rough" in stem
    return {
        "compress/mode": "2",
        # BC7 for the large map textures, BC1/BC5 for the many model textures
        "compress/high_quality": "true" if world and not single else "false",
        "compress/normal_map": "1" if normal else "2",
        "compress/channel_pack": "1" if single else "0",
        "mipmaps/generate": "true",
    }


def main():
    changed = 0
    for path, stem, world in targets():
        text = open(path, encoding="utf-8").read()
        new = text
        for key, val in wanted_params(stem, world).items():
            pat = re.compile(r"^%s=.*$" % re.escape(key), re.M)
            if pat.search(new):
                new = pat.sub("%s=%s" % (key, val), new)
            else:
                new = new.replace("[params]\n", "[params]\n\n%s=%s\n" % (key, val), 1)
        if new == text:
            continue
        open(path, "w", encoding="utf-8", newline="\n").write(new)
        changed += 1
        # Drop the import checksum so Godot re-imports with the new settings
        m = re.search(r'path(?:\.\w+)?="res://\.godot/imported/([^"]+?-[0-9a-f]{32})', text)
        if m:
            md5 = os.path.join(ROOT, ".godot", "imported", m.group(1) + ".md5")
            if os.path.exists(md5):
                os.remove(md5)
    print("updated %d import files" % changed)


if __name__ == "__main__":
    main()
