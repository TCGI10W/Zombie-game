"""Second batch of synthesized sound effects: new guns, knife, grenades,
mystery crate, augment furnace, barricades, doors and player movement.
Unified into the studio-grade acoustic DSP engine in generate_audio.py.
Run with: python tools/generate_audio.py
"""
from generate_audio import (
    gen_extra_weapons,
    gen_footsteps,
    gen_melee_grenade_and_player,
    gen_reload,
    gen_world_and_music,
)

if __name__ == "__main__":
    gen_extra_weapons()
    gen_reload()
    gen_footsteps()
    gen_melee_grenade_and_player()
    gen_world_and_music()
    print("Generated studio-grade v2 audio clips")
