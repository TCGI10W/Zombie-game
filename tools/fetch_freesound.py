"""Replace the game's sounds with real recordings from Freesound (CC0 only).

For every sound: search Freesound (CC0 licence, sensible length), take the
most downloaded match, decode the HQ preview, trim silence, cap the length,
match the loudness of the old sound (in-game volumes were tuned to it), make
loops seamless, and write assets/audio/<name>.wav. Picks are cached in
tools/freesound_cache/picks.json so re-runs are stable; delete an entry (or
pass names on the command line) to re-pick. Credits go to SOUND_CREDITS.md.

Needs: tools/.freesound_key (your API key, git-ignored), numpy, miniaudio.
Run:   python tools/fetch_freesound.py            (all sounds)
       python tools/fetch_freesound.py gun_rifle  (just these, re-picked)
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import wave

import miniaudio
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "assets", "audio")
CACHE = os.path.join(ROOT, "tools", "freesound_cache")
SR = 44100
KEY = open(os.path.join(ROOT, "tools", ".freesound_key")).read().strip()

# name: (query, min_s, max_s, kind, result_index)   kind: shot / loop
S = {
    "ambient_loop": ("night ambience crickets", 10, 300, "loop", 0),
    "bell_far": ("church bell toll", 3, 20, "shot", 0),
    "bloater_pop": ("gore squelch splat", 0.3, 3, "shot", 0),
    "board_repair": ("hammer nail wood", 0.3, 3, "shot", 0),
    "board_tear": ("wood break crack", 0.3, 3, "shot", 0),
    "bolt_cycle": ("rifle bolt action", 0.3, 2.5, "shot", 0),
    "boss_roar": ("monster growl", 1, 6, "shot", 0),
    "boss_step": ("heavy footstep stomp", 0.2, 2.5, "shot", 0),
    "buy_ching": ("cash register", 0.3, 3, "shot", 0),
    "carpenter": ("hammering nails", 1, 8, "shot", 0),
    "crate_open": ("chest open", 0.5, 4, "shot", 0),
    "crate_reveal": ("magic reveal", 0.5, 4, "shot", 0),
    "creak": ("metal creak", 0.5, 4, "shot", 0),
    "crow": ("crow caw", 0.5, 5, "shot", 0),
    "door_open": ("metal door open", 0.8, 5, "shot", 0),
    "drip": ("water drop drip", 0.1, 2, "shot", 0),
    "drone_loop": ("dark ambient drone", 10, 300, "loop", 0),
    "dry_fire": ("gun dry fire click", 0.05, 1.5, "shot", 0),
    "electrocute": ("electric shock zap", 0.3, 3, "shot", 0),
    "enemy_gunshot": ("pistol gunshot", 0.3, 3, "shot", 1),
    "exfil_siren": ("siren", 3, 30, "shot", 0),
    "exfil_success": ("victory fanfare", 1.5, 8, "shot", 0),
    "fire_loop": ("fire crackling", 10, 300, "loop", 0),
    "fire_sale": ("jingle", 1, 6, "shot", 0),
    "flare_burn": ("flare burning", 3, 60, "loop", 0),
    "flare_ignite": ("match strike", 0.3, 4, "shot", 0),
    "flesh_hit": ("flesh impact", 0.1, 1.5, "shot", 0),
    "furnace_burn": ("fire burst", 0.5, 4, "shot", 0),
    "gore_splat": ("gore splat", 0.2, 2.5, "shot", 0),
    "gorilla_slam": ("heavy impact slam", 0.5, 3, "shot", 0),
    "grenade_explode": ("explosion large", 1, 8, "shot", 0),
    "grenade_pin": ("metal clink", 0.1, 1.5, "shot", 0),
    "gun_lmg": ("machine gun shot", 0.2, 2.5, "shot", 0),
    "gun_pistol": ("pistol shot", 0.3, 3, "shot", 0),
    "gun_revolver": ("magnum revolver shot", 0.3, 4, "shot", 0),
    "gun_rifle": ("rifle shot", 0.3, 4, "shot", 0),
    "gun_shotgun": ("shotgun blast", 0.4, 3.5, "shot", 0),
    "gun_smg": ("submachine gun shot", 0.15, 2.5, "shot", 0),
    "gun_sniper": ("sniper rifle shot", 0.5, 4.5, "shot", 0),
    "gun_volt": ("laser blaster", 0.2, 2.5, "shot", 0),
    "headshot_ding": ("metal ding", 0.2, 2.5, "shot", 0),
    "heartbeat": ("heartbeat", 0.5, 4, "shot", 0),
    "heli_loop": ("helicopter flying", 8, 300, "loop", 0),
    "hit_flesh": ("flesh hit", 0.1, 1.5, "shot", 0),
    "hit_tick": ("ui click short", 0.03, 0.6, "shot", 0),
    "hum_loop": ("fluorescent hum", 3, 300, "loop", 0),
    "kill_confirm": ("punch thud", 0.1, 1.2, "shot", 1),
    "knife_hit": ("knife stab", 0.1, 1.5, "shot", 0),
    "knife_swing": ("whoosh swing", 0.1, 1.2, "shot", 0),
    "level_up": ("level up", 0.5, 3.5, "shot", 0),
    "lightning_strike": ("thunder clap", 1, 8, "shot", 0),
    "low_ammo_tick": ("gun click", 0.02, 0.6, "shot", 1),
    "mag_in": ("magazine insert", 0.1, 1.2, "shot", 0),
    "mag_out": ("magazine release", 0.1, 1.2, "shot", 0),
    "monster_rend": ("slash", 0.15, 2, "shot", 0),
    "monster_roar": ("beast roar", 1, 5, "shot", 0),
    "monster_slam": ("ground impact", 0.4, 4, "shot", 0),
    "pain_drug": ("syringe", 0.2, 4, "shot", 0),
    "player_cough": ("cough", 0.4, 3, "shot", 0),
    "player_downed": ("male pain groan", 0.5, 3.5, "shot", 0),
    "player_hurt": ("male grunt pain", 0.15, 1.5, "shot", 0),
    "player_step_1": ("footstep concrete", 0.1, 1.0, "shot", 0),
    "player_step_2": ("footstep concrete", 0.1, 1.0, "shot", 1),
    "power_on": ("power up generator start", 1, 6, "shot", 0),
    "powerup_spawn": ("magic sparkle", 0.5, 3, "shot", 0),
    "pump_rack": ("shotgun pump action", 0.2, 2.5, "shot", 0),
    "radio_beep": ("radio beep", 0.1, 2, "shot", 0),
    "radio_call": ("radio chatter static", 1, 7, "shot", 0),
    "rain_loop": ("heavy rain", 10, 900, "loop", 0),
    "reload": ("gun reload", 0.5, 3.5, "shot", 0),
    "ricochet": ("bullet ricochet", 0.2, 3, "shot", 0),
    "roof_rain_loop": ("rain roof", 10, 600, "loop", 0),
    "round_sting": ("horror stinger", 1, 7, "shot", 0),
    "scream_far": ("distant scream", 1, 6, "shot", 0),
    "second_wind": ("deep breath gasp", 0.5, 3.5, "shot", 0),
    "shell_insert": ("shotgun shell load", 0.1, 1.5, "shot", 0),
    "shell_tink": ("bullet casing drop", 0.1, 2, "shot", 0),
    "skull_shatter": ("bone crack crunch", 0.2, 2.5, "shot", 0),
    "slide": ("sliding gravel", 0.3, 2.5, "shot", 0),
    "streak_sting": ("chime", 0.3, 3, "shot", 0),
    "thunder_far": ("distant thunder", 3, 20, "shot", 0),
    "train_horn": ("train horn", 1.5, 15, "shot", 1),
    "trap_zap": ("electric zap", 0.2, 2.5, "shot", 0),
    "weapon_swap": ("gun handling", 0.2, 2, "shot", 0),
    "wind_loop": ("wind howling", 10, 300, "loop", 0),
    "zombie_attack_roar": ("zombie attack growl", 0.4, 3, "shot", 0),
    "zombie_death": ("zombie death", 0.5, 4, "shot", 0),
    "zombie_groan": ("zombie moan", 1, 6, "shot", 0),
    "zombie_roar_1": ("zombie roar", 0.8, 4, "shot", 0),
    "zombie_roar_2": ("zombie scream", 0.8, 4, "shot", 0),
    "zombie_step_1": ("footstep drag", 0.2, 1.5, "shot", 0),
    "zombie_step_2": ("footstep drag", 0.2, 1.5, "shot", 1),
}
# Max kept length for one-shots (seconds); loops keep LOOP_LEN
CAP = {"zombie_step_1": 0.32, "zombie_step_2": 0.32, "player_step_1": 0.35, "player_step_2": 0.35, "boss_step": 0.6, "exfil_siren": 6.0, "bell_far": 6.0, "thunder_far": 7.0, "train_horn": 4.0, "lightning_strike": 4.0, "grenade_explode": 3.0,
       "exfil_success": 6.0, "radio_call": 4.0, "boss_roar": 3.5, "monster_roar": 3.0}
# Extra loudness on top of the old level (old synthesized steps were very quiet)
GAIN = {"zombie_step_1": 2.2, "zombie_step_2": 2.2, "boss_step": 1.6}
LOOP_LEN = {"heli_loop": 4.0, "hum_loop": 4.0, "flare_burn": 4.0}
DEFAULT_SHOT_CAP = 2.5


def api(path, params):
    params = dict(params, token=KEY)
    url = "https://freesound.org/apiv2/" + path + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "DeadProtocolSoundFetcher/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def search(query, lo, hi):
    flt = 'license:"Creative Commons 0" duration:[%s TO %s]' % (lo, hi)
    res = api("search/text/", {"query": query, "filter": flt, "sort": os.environ.get("FS_SORT", "downloads_desc"), "page_size": 8,
                               "fields": "id,name,username,license,duration,previews,url,num_downloads,avg_rating"})
    return res.get("results", [])


def download(url, path):
    req = urllib.request.Request(url, headers={"User-Agent": "DeadProtocolSoundFetcher/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r, open(path, "wb") as f:
        f.write(r.read())


def decode(path):
    d = miniaudio.decode_file(path, output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1, sample_rate=SR)
    return np.frombuffer(d.samples, dtype=np.float32).astype(np.float64)


def old_rms(name):
    p = os.path.join(AUDIO, name + ".wav")
    if not os.path.exists(p):
        return None
    with wave.open(p) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
    return active_rms(x)


def active_rms(x):
    if len(x) == 0:
        return 0.0
    frame = 1024
    n = len(x) // frame
    if n == 0:
        return float(np.sqrt(np.mean(x ** 2)))
    f = x[: n * frame].reshape(n, frame)
    r = np.sqrt(np.mean(f ** 2, axis=1))
    loud = r[r > r.max() * 0.1]
    return float(np.sqrt(np.mean(loud ** 2))) if len(loud) else float(r.max())


def trim(x, thresh_db=-42.0):
    peak = np.max(np.abs(x)) + 1e-9
    th = peak * 10 ** (thresh_db / 20.0)
    idx = np.where(np.abs(x) > th)[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] - int(0.004 * SR))
    b = min(len(x), idx[-1] + int(0.05 * SR))
    return x[a:b]


def fade(x, fin=0.003, fout=0.08):
    x = x.copy()
    a, b = int(fin * SR), min(len(x) // 3, int(fout * SR))
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def loopify(x, length, xfade=0.8):
    n, f = int(length * SR), int(xfade * SR)
    if len(x) < n + f:
        reps = int(np.ceil((n + f) / max(1, len(x)))) + 1
        x = np.tile(x, reps)
    start = (len(x) - n - f) // 3  # skip the start of the recording
    seg = x[start:start + n + f].copy()
    body = seg[:n].copy()
    ramp = np.linspace(0, 1, f)
    body[:f] = body[:f] * np.sqrt(ramp) + seg[n:n + f] * np.sqrt(1 - ramp)
    return body


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def write(name, x, target_rms):
    r = active_rms(x)
    if r > 0 and target_rms:
        x = x * (target_rms / r)
    peak = np.max(np.abs(x))
    if peak > 0.97:  # gentle limiter instead of clipping
        x = np.tanh(x / peak * 1.6) / np.tanh(1.6) * 0.97
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(AUDIO, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    os.makedirs(CACHE, exist_ok=True)
    picks_path = os.path.join(CACHE, "picks.json")
    picks = json.load(open(picks_path)) if os.path.exists(picks_path) else {}
    only = sys.argv[1:]
    names = only if only else list(S.keys())
    for name in names:
        query, lo, hi, kind, idx = S[name]
        try:
            if name not in picks or name in only:
                results = search(query, lo, hi)
                time.sleep(1.1)
                if not results:
                    print("NO RESULT", name, query)
                    continue
                r = results[min(idx, len(results) - 1)]
                picks[name] = {"id": r["id"], "name": r["name"], "user": r["username"], "license": r["license"],
                               "url": r["url"], "preview": r["previews"]["preview-hq-mp3"], "duration": r["duration"]}
                json.dump(picks, open(picks_path, "w"), indent=1)
            p = picks[name]
            mp3 = os.path.join(CACHE, "%s_%d.mp3" % (name, p["id"]))
            if not os.path.exists(mp3):
                download(p["preview"], mp3)
                time.sleep(0.5)
            target = old_rms(name)
            x = decode(mp3)
            if kind == "loop":
                x = loopify(trim(x, -60.0), LOOP_LEN.get(name, 8.0))
            else:
                x = trim(x)
                x = x[: int(CAP.get(name, DEFAULT_SHOT_CAP) * SR)]
                x = fade(x)
            write(name, x, (target if target else 0.18) * GAIN.get(name, 1.0))
            if name == "rain_loop":  # indoor version: muffled
                write("rain_indoor_loop", lowpass(x, 600.0), old_rms("rain_indoor_loop") or 0.12)
            print("ok %-20s <- #%d %s (%s)" % (name, p["id"], p["name"][:50], p["user"]))
        except Exception as e:  # keep going; report at the end
            print("FAIL", name, repr(e)[:160])
    with open(os.path.join(ROOT, "SOUND_CREDITS.md"), "w", encoding="utf-8") as f:
        f.write("# Sound credits\n\nAll sound effects come from [Freesound](https://freesound.org) under the "
                "**Creative Commons 0** licence (public domain). Credit is not required, but thank you to the creators:\n\n")
        f.write("| In game | Freesound sound | Creator |\n|---|---|---|\n")
        for name in sorted(picks):
            p = picks[name]
            f.write("| %s | [%s](%s) | %s |\n" % (name, p["name"].replace("|", "/"), p["url"], p["user"]))


if __name__ == "__main__":
    main()
