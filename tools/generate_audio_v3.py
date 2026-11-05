"""Third batch of sounds: impacts, gore, casings, gun mechanics, power,
electric trap, easter egg song, ambient music and heartbeat.
Unified into the studio-grade acoustic DSP engine in generate_audio.py.
Run with: python tools/generate_audio.py
"""
from generate_audio import (
    gen_hit_feedback,
    gen_melee_grenade_and_player,
    gen_reload,
    gen_world_and_music,
)

if __name__ == "__main__":
    gen_hit_feedback()
    gen_reload()
    gen_melee_grenade_and_player()
    gen_world_and_music()
    print("Generated studio-grade v3 audio clips")
