extends Node

signal subtitle(text: String, color: Color)
signal points_changed(new_points: int, delta: int)
signal round_changed(new_round: int)
signal powerups_changed()

const SAVE_PATH := "user://dead_protocol_save.cfg"
const POWERUP_DURATION := 20.0

var selected_character: String = "ravager"
var points: int = 500
var current_round: int = 1
var total_kills: int = 0
var headshots: int = 0
var bosses_slain: int = 0
var commanders_slain: int = 0
var challenges_done: int = 0
var downs: int = 0
var run_time: float = 0.0 # seconds played this run
# Special rounds: now and then a round changes the rules (see ROUND_EVENTS)
var round_event: String = ""
const ROUND_EVENTS := {
	"blood_moon": {"name": "BLOOD MOON", "desc": "ZOMBIES ARE FASTER  •  ALL POINTS x1.5", "color": Color(1.0, 0.25, 0.2)},
	"swarm": {"name": "THE SWARM", "desc": "ALMOST TWICE AS MANY ZOMBIES, EACH ONE WEAKER", "color": Color(1.0, 0.7, 0.25)},
	"dead_fog": {"name": "DEAD FOG", "desc": "YOU CAN BARELY SEE  •  HEADSHOT BONUS x3", "color": Color(0.72, 0.82, 0.88)},
	"cunning": {"name": "NIGHT OF THE CUNNING", "desc": "EVERY ZOMBIE IS A STALKER, LED BY A COMMANDER  •  POINTS x1.25", "color": Color(1.0, 0.85, 0.2)},
	"toxic": {"name": "TOXIC TIDE", "desc": "BLOATERS AND SPITTERS EVERYWHERE  •  POINTS x1.25", "color": Color(0.45, 1.0, 0.35)},
	"relic_drop": {"name": "RELIC DROP", "desc": "A RELIC FELL SOMEWHERE ON THE MAP", "color": Color(0.78, 0.55, 1.0)},
}
# The commander that killed you last: {"name", "tier", "skill", "kills"}.
# It returns in later runs until you kill it.
var nemesis: Dictionary = {}
# Lifetime totals (career page)
var life_kills: int = 0
var life_bosses: int = 0
var life_commanders: int = 0
var life_runs: int = 0
var life_nemesis_slain: int = 0

# Timed power-ups dropped by zombies (seconds remaining)
var powerup_timers: Dictionary = {"insta_kill": 0.0, "double_points": 0.0, "quad_points": 0.0, "fire_sale": 0.0}

# Saved between sessions
var best_round: int = 0
var best_kills: int = 0
var exfils: int = 0
var best_exfil_round: int = 0
var mouse_sens_mult: float = 1.0
var points_mult: float = 1.0 # Fortune stat bonus, set by the player
var master_volume: float = 0.8
var sfx_volume: float = 1.0
var step_volume: float = 1.0 # zombie footsteps, 0..2
var invert_y: bool = false
var fullscreen: bool = false
var resolution: String = "native" # "native" or "WxH"
var key_binds: Dictionary = {} # action -> "k:<physical keycode>" or "m:<mouse button>"
var show_crosshair: bool = false
var damage_numbers: bool = false
var show_minimap: bool = false
var game_mode: String = "casual" # "casual", "infinite", "horror", "overdrive", or "pvp"
var last_pve_mode: String = "casual"
var pvp_mode: String = "tdm" # "tdm", "gungame", "snd", "dom"
var pvp_map: String = "nacht" # "random" or a key in PVP_MAPS
var active_pvp_map: String = "nacht"
var team_preset: int = 2 # 2 (16v16), 4 (4x8), or 6 (6x6)
var pvp_player_cap: int = 32 # 32, 24, 16, or 0 (humans only)
var pvp_loadout_weapon: String = "m4_carbine"
var pvp_selected_team: int = 0
var active_loadout_index: int = 0
var custom_loadouts: Array = []
var pve_use_custom_loadout: bool = false
var pvp_wins: int = 0
var pvp_kills_life: int = 0
var best_round_infinite: int = 0
var best_round_horror: int = 0
var best_round_overdrive: int = 0
var fov_setting: float = 90.0
var post_fx_enabled: bool = true
var graphics_quality: int = 2 # 0 low, 1 medium, 2 high
var vsync_on: bool = true
var show_fps: bool = false
var menu_sound: bool = true # main-menu ambience + UI sounds
var ads_sens_mult: float = 0.85
var sprint_mode: int = 0 # 0=Hold (+double-tap Tac-Sprint), 1=Toggle Sprint, 2=Auto Tac-Sprint
var ads_mode: int = 0 # 0=Hold ADS, 1=Toggle ADS
var crouch_mode: int = 0 # 0=Toggle Crouch, 1=Hold Crouch
var viewmodel_bob: float = 1.0
var screen_shake: float = 1.0
var crosshair_enabled: bool = true
var crosshair_color: int = 0 # 0=White, 1=Cyan, 2=Green, 3=Amber, 4=Crimson
var hitmarker_sfx: bool = true
var msaa_level: int = 1 # 0=Off, 1=2x, 2=4x
var render_scale_setting: float = 1.0
var _best_round_at_start: int = 0
var rebuild_points_round: int = 0 # points earned rebuilding barriers this round
const REBUILD_POINTS_CAP := 500

const CHARACTERS := {
	"ravager": {
		"id": "ravager",
		"name": "VIKTOR 'RAVAGER' KROSS",
		"codename": "SUBJECT-09 // SHAPESHIFTER",
		"accent": Color(0.92, 0.22, 0.16),
		"max_hp": 130.0,
		"move_speed": 6.4,
		"summary": "Cursed bio-soldier who mutates into a ferocious clawed Monster with 2 dedicated beast skills.",
		"skills": [
			"[F] MONSTER TRANSFORMATION: Morph into the Ravager Beast for 18s (60s cooldown). Swaps guns for 2 Monster Skills:",
			"  • MONSTER SKILL 1 [LMB] — SAVAGE REND: Single-target lethal lunge dealing 480 HIGH DAMAGE to 1 target.",
			"  • MONSTER SKILL 2 [RMB / Q] — SEISMIC SLAM: Shockwave dealing 35 damage and a stun of 1s + 0.2s per zombie hit (8s cooldown, bosses immune).",
		]
	},
	"alchemist": {
		"id": "alchemist",
		"name": "DR. ELENA VANCE",
		"codename": "DIVISION-X // BIOCHEMIST",
		"accent": Color(0.16, 0.90, 0.78),
		"max_hp": 110.0,
		"move_speed": 6.7,
		"summary": "Field biochemist who synthesizes Nocicept-X Pain Drugs engineered to pacify and cripple Round Bosses.",
		"skills": [
			"[Q] NOCICEPT-X PAIN DRUG (Up to 3 Doses): Fires a chemical dart. Giving it to a ROUND BOSS inflicts 12s Neural Numbness:",
			"  • Cuts Boss Attack Damage by 55%, slows Boss speed/windups by 45%, and strips Endurance Armor (+60% bonus dmg)!",
			"[F] PAINKILLER OVERDOSE: Instant full heal + 50 Overshield, +35% fire/reload rate (10s), & crafts +1 Pain Drug!",
		]
	},
	"warden": {
		"id": "warden",
		"name": "SGT. MARCUS COLE",
		"codename": "HELLHOUND // HEAVY ORDNANCE",
		"accent": Color(0.95, 0.68, 0.18),
		"max_hp": 125.0,
		"move_speed": 6.3,
		"summary": "Veteran bunker shock-trooper armed with crowd-control arc charges and an arc weapon overcharge.",
		"skills": [
			"[Q] TESLA CONCUSSION CHARGE: Hurls a high-voltage arc charge dealing 150 AoE damage + 2.5s shock stun. The only stun that can hold a BOSS (1s).",
			"[F] ARC OVERCHARGE: Infuses your firearm for 12s with 2.2x plasma damage & bottomless clip!",
		]
	}
}

# Weapon stats. ads_pos = viewmodel position while aiming (y puts the sights on
# the crosshair), muzzle = (up, forward) offset of the barrel tip.
const WEAPONS := WeaponCatalog.WEAPONS
const LETHALS := WeaponCatalog.LETHALS
const TACTICALS := WeaponCatalog.TACTICALS
const FIELD_PERKS := WeaponCatalog.FIELD_PERKS
const WEAPON_CAMOS := WeaponCatalog.WEAPON_CAMOS
const WEAPON_CAMO_ORDER := WeaponCatalog.WEAPON_CAMO_ORDER

const WEAPON_ATTACHMENTS := {
	"suppressor": {"tag": "SUPP", "slot": "MUZZLE", "name": "MONOLITHIC SUPPRESSOR", "desc": "SILENCED · -20% RECOIL", "sfx": "gun_suppressed", "dmg": 0.96, "spread": 0.84, "recoil": 0.80, "muzzle": 0.22},
	"tac_laser": {"tag": "LASER", "slot": "LASER", "name": "AN/PEQ-15 TAC LASER", "desc": "-48% HIP SPREAD · +15% ADS", "spread": 0.52, "ads_speed": 1.15, "laser": true},
	"ext_mag": {"tag": "EXT-MAG", "slot": "MAG", "name": "45-RD EXTENDED MAG", "desc": "+45% MAG CAPACITY", "mag": 1.45, "reload": 1.08},
	"heavy_barrel": {"tag": "HVY-BRL", "slot": "BARREL", "name": "MATCH HEAVY BARREL", "desc": "+22% DMG · +30% RANGE", "dmg": 1.22, "range": 1.30, "recoil": 1.12},
	"quickdraw": {"tag": "Q-DRAW", "slot": "GRIP", "name": "ANGLED QUICKDRAW GRIP", "desc": "+22% RELOAD · -12% RECOIL", "reload": 0.78, "recoil": 0.88},
	"overpressured": {"tag": "+P", "slot": "LOAD", "name": "+P OVERPRESSURED", "desc": "+16% DMG · +65% STAGGER", "dmg": 1.16, "stagger": 1.65, "recoil": 1.14},
	"red_dot": {"tag": "RDS", "slot": "OPTIC", "name": "REFLEX RED DOT", "desc": "CLEAR REFLEX · +12% ADS", "spread": 0.72, "ads_speed": 1.12},
	"fmj": {"tag": "FMJ", "slot": "AMMO", "name": "FMJ ARMOR-PIERCING", "desc": "+14% DMG · +15% RANGE", "dmg": 1.14, "range": 1.15},
}


static func is_attachment_allowed(w_id: String, aid: String) -> bool:
	if not WEAPON_ATTACHMENTS.has(aid) or not WEAPONS.has(w_id):
		return false
	var w_cls := String(WEAPONS[w_id].get("class", ""))
	if (w_cls == "wonder" or w_cls == "launcher" or w_cls == "special" or w_id == "volt") and (aid == "suppressor" or aid == "overpressured"):
		return false
	if w_id == "revolver" and aid == "suppressor":
		return false
	if w_id == "rpg7" and aid == "red_dot":
		return false
	return true


static func roll_crate_attachments(w_id: String) -> Array[String]:
	var pool: Array[String] = []
	for k in WEAPON_ATTACHMENTS.keys():
		if is_attachment_allowed(w_id, String(k)):
			pool.append(String(k))
	for i in range(pool.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var count := 1 if randf() < 0.45 else 2
	var out: Array[String] = []
	for idx in range(mini(count, pool.size())):
		out.append(pool[idx])
	return out


static func format_attachment_tags(mods: Array) -> String:
	if mods.is_empty():
		return ""
	var tags: Array[String] = []
	for m in mods:
		var k := String(m)
		if WEAPON_ATTACHMENTS.has(k):
			tags.append(String(WEAPON_ATTACHMENTS[k]["tag"]))
	return ("[%s]" % " + ".join(tags)) if not tags.is_empty() else ""

# Upgradeable stats bought at the Augment Furnace. Points burned into a stat
# fill its bar; each level costs more than the last.
const STAT_MAX_LEVEL := 30


# Cost of going from level `lv` to `lv + 1`. Cheap early, steeper late.
static func stat_level_cost(lv: int) -> int:
	return 300 + 150 * lv + 12 * lv * lv


# Levels past 10 count for half (speed for a quarter) so maxed stats stay sane.
static func stat_eff(id: String, lv: int) -> float:
	if lv <= 10:
		return float(lv)
	return 10.0 + float(lv - 10) * (0.25 if id == "speed" else 0.5)
const STATS := [
	{"id": "strength", "name": "STRENGTH", "color": Color(1.0, 0.36, 0.28), "per_level": "+8% weapon, knife & grenade damage (½ after LV 10)"},
	{"id": "speed", "name": "SPEED", "color": Color(0.35, 0.85, 1.0), "per_level": "+4% movement speed (¼ after LV 10)"},
	{"id": "endurance", "name": "ENDURANCE", "color": Color(1.0, 0.62, 0.25), "per_level": "+15 max health & +2.5% damage resistance (½ after LV 10)"},
	{"id": "stamina", "name": "STAMINA", "color": Color(1.0, 0.9, 0.35), "per_level": "+20% sprint time & +12% faster recovery (½ after LV 10)"},
	{"id": "dexterity", "name": "DEXTERITY", "color": Color(0.55, 1.0, 0.5), "per_level": "+7% reload, weapon swap & aim speed (½ after LV 10)"},
	{"id": "reflexes", "name": "REFLEXES", "color": Color(0.85, 0.5, 1.0), "per_level": "+4% fire rate (½ after LV 10)"},
	{"id": "vitality", "name": "VITALITY", "color": Color(1.0, 0.4, 0.6), "per_level": "+15% health regen & regen starts sooner (½ after LV 10)"},
	{"id": "fortune", "name": "FORTUNE", "color": Color(1.0, 0.82, 0.3), "per_level": "+6% points earned (½ after LV 10)"},
]


# Returns {level, into, need} for a stat with `burned` points in it.
func stat_progress(burned: int) -> Dictionary:
	var level := 0
	var rem := burned
	while level < STAT_MAX_LEVEL and rem >= stat_level_cost(level):
		rem -= stat_level_cost(level)
		level += 1
	var need: int = 0 if level >= STAT_MAX_LEVEL else stat_level_cost(level)
	return {"level": level, "into": rem if level < STAT_MAX_LEVEL else 0, "need": need}


func stat_total_cost() -> int:
	var total := 0
	for lv in range(STAT_MAX_LEVEL):
		total += stat_level_cost(lv)
	return total


var _sfx_cache: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next_idx: int = 0
var _zombie_roar_cooldown: float = 0.0
var _zombie_roar_slots: Array[float] = []


func _ready() -> void:
	_setup_input_map()
	_setup_audio_buses()
	_preload_audio()
	load_save()
	apply_graphics.call_deferred()


func _process(delta: float) -> void:
	_zombie_roar_cooldown = maxf(0.0, _zombie_roar_cooldown - delta)
	for i in range(_zombie_roar_slots.size() - 1, -1, -1):
		_zombie_roar_slots[i] -= delta
		if _zombie_roar_slots[i] <= 0.0:
			_zombie_roar_slots.remove_at(i)

	var changed := false
	for k in powerup_timers.keys():
		if powerup_timers[k] > 0.0:
			powerup_timers[k] = maxf(0.0, powerup_timers[k] - delta)
			changed = true
	if changed:
		powerups_changed.emit()


func _setup_audio_buses() -> void:
	# Master bus peak protection compressor so overlapping gunfire, slams & explosions never clip
	if AudioServer.get_bus_effect_count(0) == 0:
		var master_comp := AudioEffectCompressor.new()
		master_comp.threshold = -3.5
		master_comp.ratio = 10.0
		master_comp.attack_us = 25.0
		master_comp.release_ms = 90.0
		master_comp.gain = 0.5
		AudioServer.add_bus_effect(0, master_comp)

	for bus_name in ["SFX", "Zombies"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
			if bus_name == "Zombies":
				var z_comp := AudioEffectCompressor.new()
				z_comp.threshold = -8.0
				z_comp.ratio = 4.5
				z_comp.attack_us = 80.0
				z_comp.release_ms = 140.0
				AudioServer.add_bus_effect(idx, z_comp)


func request_zombie_vocal(duration: float = 1.0) -> bool:
	if _zombie_roar_cooldown > 0.0 or _zombie_roar_slots.size() >= 2:
		return false
	_zombie_roar_cooldown = 0.78
	_zombie_roar_slots.append(duration)
	return true


func is_powerup_active(kind: String) -> bool:
	return powerup_timers.get(kind, 0.0) > 0.0


func activate_powerup(kind: String, duration: float = POWERUP_DURATION) -> void:
	powerup_timers[kind] = duration
	powerups_changed.emit()


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_round = int(cfg.get_value("records", "best_round", 0))
		best_kills = int(cfg.get_value("records", "best_kills", 0))
		exfils = int(cfg.get_value("records", "exfils", 0))
		best_exfil_round = int(cfg.get_value("records", "best_exfil_round", 0))
		mouse_sens_mult = float(cfg.get_value("settings", "mouse_sens_mult", 1.0))
		master_volume = float(cfg.get_value("settings", "master_volume", 0.8))
		sfx_volume = float(cfg.get_value("settings", "sfx_volume", 1.0))
		step_volume = float(cfg.get_value("settings", "step_volume", 1.0))
		invert_y = bool(cfg.get_value("settings", "invert_y", false))
		fullscreen = bool(cfg.get_value("settings", "fullscreen", false))
		resolution = String(cfg.get_value("settings", "resolution", "native"))
		key_binds = cfg.get_value("settings", "key_binds", {})
		_apply_key_binds()
		show_crosshair = bool(cfg.get_value("settings", "show_crosshair", false))
		damage_numbers = bool(cfg.get_value("settings", "damage_numbers", false))
		show_minimap = bool(cfg.get_value("settings", "show_minimap", false))
		game_mode = String(cfg.get_value("settings", "game_mode", "casual"))
		if game_mode not in ["casual", "infinite", "horror", "overdrive", "pvp"]:
			game_mode = "casual"
		last_pve_mode = String(cfg.get_value("settings", "last_pve_mode", "casual"))
		if last_pve_mode not in ["casual", "infinite", "horror", "overdrive"]:
			last_pve_mode = "casual"
		pvp_mode = String(cfg.get_value("settings", "pvp_mode", "tdm"))
		if pvp_mode not in ["tdm", "gungame", "snd", "dom"]:
			pvp_mode = "tdm"
		pvp_map = String(cfg.get_value("settings", "pvp_map", "nacht"))
		if pvp_map != "random" and not PVP_MAPS.has(pvp_map):
			pvp_map = "nacht"
		active_pvp_map = pvp_map if PVP_MAPS.has(pvp_map) else "nacht"
		team_preset = int(cfg.get_value("settings", "team_preset", 2))
		if team_preset not in [2, 4, 6]:
			team_preset = 2
		pvp_player_cap = int(cfg.get_value("settings", "pvp_player_cap", 32))
		if pvp_player_cap not in [32, 24, 16, 0]:
			pvp_player_cap = 32
		pvp_loadout_weapon = String(cfg.get_value("settings", "pvp_loadout_weapon", "m4_carbine"))
		if not is_valid_primary(pvp_loadout_weapon):
			pvp_loadout_weapon = "m4_carbine"
		pvp_selected_team = clampi(int(cfg.get_value("settings", "pvp_selected_team", 0)), 0, pvp_team_count() - 1)
		active_loadout_index = clampi(int(cfg.get_value("settings", "active_loadout_index", 0)), 0, WeaponCatalog.DEFAULT_LOADOUTS.size() - 1)
		pve_use_custom_loadout = bool(cfg.get_value("settings", "pve_use_custom_loadout", false))
		var saved_sets = cfg.get_value("settings", "custom_loadouts", [])
		custom_loadouts = []
		if saved_sets is Array:
			for s in saved_sets:
				if s is Dictionary:
					custom_loadouts.append(sanitize_loadout(s))
		_ensure_loadouts()
		pvp_loadout_weapon = String(get_active_loadout().get("primary", "m4_carbine"))
		pvp_wins = int(cfg.get_value("records", "pvp_wins", 0))
		pvp_kills_life = int(cfg.get_value("records", "pvp_kills_life", 0))
		best_round_infinite = int(cfg.get_value("records", "best_round_infinite", 0))
		best_round_horror = int(cfg.get_value("records", "best_round_horror", 0))
		best_round_overdrive = int(cfg.get_value("records", "best_round_overdrive", 0))
		fov_setting = float(cfg.get_value("settings", "fov", 90.0))
		post_fx_enabled = bool(cfg.get_value("settings", "post_fx", true))
		if not bool(cfg.get_value("settings", "horror_v2_migrated", false)):
			post_fx_enabled = true
			show_crosshair = false
			damage_numbers = false
			show_minimap = false
		graphics_quality = int(cfg.get_value("settings", "graphics", 2))
		vsync_on = bool(cfg.get_value("settings", "vsync", true))
		show_fps = bool(cfg.get_value("settings", "show_fps", false))
		menu_sound = bool(cfg.get_value("settings", "menu_sound", true))
		ads_sens_mult = clampf(float(cfg.get_value("settings", "ads_sens_mult", 0.85)), 0.30, 1.50)
		sprint_mode = clampi(int(cfg.get_value("settings", "sprint_mode", 0)), 0, 2)
		ads_mode = clampi(int(cfg.get_value("settings", "ads_mode", 0)), 0, 1)
		crouch_mode = clampi(int(cfg.get_value("settings", "crouch_mode", 0)), 0, 1)
		viewmodel_bob = clampf(float(cfg.get_value("settings", "viewmodel_bob", 1.0)), 0.0, 1.0)
		screen_shake = clampf(float(cfg.get_value("settings", "screen_shake", 1.0)), 0.0, 1.0)
		crosshair_enabled = bool(cfg.get_value("settings", "crosshair_enabled", true))
		crosshair_color = clampi(int(cfg.get_value("settings", "crosshair_color", 0)), 0, 4)
		hitmarker_sfx = bool(cfg.get_value("settings", "hitmarker_sfx", true))
		msaa_level = clampi(int(cfg.get_value("settings", "msaa_level", 1)), 0, 2)
		render_scale_setting = clampf(float(cfg.get_value("settings", "render_scale_setting", 1.0)), 0.70, 1.0)
		difficulty = clampi(int(cfg.get_value("settings", "difficulty", 1)), 0, DIFFICULTIES.size() - 1)
		overdrive_difficulty = clampi(int(cfg.get_value("settings", "overdrive_difficulty", 1)), 0, OVERDRIVE_DIFFICULTIES.size() - 1)
		career_xp = int(cfg.get_value("records", "career_xp", 0))
		nemesis = cfg.get_value("records", "nemesis", {})
		life_kills = int(cfg.get_value("records", "life_kills", 0))
		life_bosses = int(cfg.get_value("records", "life_bosses", 0))
		life_commanders = int(cfg.get_value("records", "life_commanders", 0))
		life_runs = int(cfg.get_value("records", "life_runs", 0))
		life_nemesis_slain = int(cfg.get_value("records", "life_nemesis_slain", 0))
	_ensure_loadouts()
	pvp_loadout_weapon = String(get_active_loadout().get("primary", "m4_carbine"))
	apply_volume()


func write_save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("records", "best_round", best_round)
	cfg.set_value("records", "best_kills", best_kills)
	cfg.set_value("records", "exfils", exfils)
	cfg.set_value("records", "best_exfil_round", best_exfil_round)
	cfg.set_value("settings", "mouse_sens_mult", mouse_sens_mult)
	cfg.set_value("settings", "master_volume", master_volume)
	cfg.set_value("settings", "sfx_volume", sfx_volume)
	cfg.set_value("settings", "step_volume", step_volume)
	cfg.set_value("settings", "invert_y", invert_y)
	cfg.set_value("settings", "fullscreen", fullscreen)
	cfg.set_value("settings", "resolution", resolution)
	cfg.set_value("settings", "key_binds", key_binds)
	cfg.set_value("settings", "show_crosshair", show_crosshair)
	cfg.set_value("settings", "damage_numbers", damage_numbers)
	cfg.set_value("settings", "show_minimap", show_minimap)
	cfg.set_value("settings", "horror_v2_migrated", true)
	cfg.set_value("settings", "game_mode", game_mode)
	cfg.set_value("settings", "last_pve_mode", last_pve_mode)
	cfg.set_value("settings", "pvp_mode", pvp_mode)
	cfg.set_value("settings", "pvp_map", pvp_map)
	cfg.set_value("settings", "team_preset", team_preset)
	cfg.set_value("settings", "pvp_player_cap", pvp_player_cap)
	cfg.set_value("settings", "pvp_loadout_weapon", pvp_loadout_weapon)
	cfg.set_value("settings", "pvp_selected_team", pvp_selected_team)
	cfg.set_value("settings", "active_loadout_index", active_loadout_index)
	cfg.set_value("settings", "pve_use_custom_loadout", pve_use_custom_loadout)
	cfg.set_value("settings", "custom_loadouts", custom_loadouts)
	cfg.set_value("records", "pvp_wins", pvp_wins)
	cfg.set_value("records", "pvp_kills_life", pvp_kills_life)
	cfg.set_value("records", "best_round_infinite", best_round_infinite)
	cfg.set_value("records", "best_round_horror", best_round_horror)
	cfg.set_value("records", "best_round_overdrive", best_round_overdrive)
	cfg.set_value("settings", "fov", fov_setting)
	cfg.set_value("settings", "post_fx", post_fx_enabled)
	cfg.set_value("settings", "graphics", graphics_quality)
	cfg.set_value("settings", "vsync", vsync_on)
	cfg.set_value("settings", "show_fps", show_fps)
	cfg.set_value("settings", "menu_sound", menu_sound)
	cfg.set_value("settings", "ads_sens_mult", ads_sens_mult)
	cfg.set_value("settings", "sprint_mode", sprint_mode)
	cfg.set_value("settings", "ads_mode", ads_mode)
	cfg.set_value("settings", "crouch_mode", crouch_mode)
	cfg.set_value("settings", "viewmodel_bob", viewmodel_bob)
	cfg.set_value("settings", "screen_shake", screen_shake)
	cfg.set_value("settings", "crosshair_enabled", crosshair_enabled)
	cfg.set_value("settings", "crosshair_color", crosshair_color)
	cfg.set_value("settings", "hitmarker_sfx", hitmarker_sfx)
	cfg.set_value("settings", "msaa_level", msaa_level)
	cfg.set_value("settings", "render_scale_setting", render_scale_setting)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("settings", "overdrive_difficulty", overdrive_difficulty)
	cfg.set_value("records", "career_xp", career_xp)
	cfg.set_value("records", "nemesis", nemesis)
	cfg.set_value("records", "life_kills", life_kills)
	cfg.set_value("records", "life_bosses", life_bosses)
	cfg.set_value("records", "life_commanders", life_commanders)
	cfg.set_value("records", "life_runs", life_runs)
	cfg.set_value("records", "life_nemesis_slain", life_nemesis_slain)
	cfg.save(SAVE_PATH)


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, master_volume)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	for bus in ["SFX", "Zombies"]:
		var bi := AudioServer.get_bus_index(bus)
		if bi >= 0:
			AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(0.0001, sfx_volume)))
			AudioServer.set_bus_mute(bi, sfx_volume <= 0.001)


# Saves progress for this run. Returns true if this run beat the best round
# that was on record when the run started.
func record_run() -> bool:
	if game_mode == "overdrive":
		best_round_overdrive = maxi(best_round_overdrive, current_round)
	elif game_mode == "horror":
		best_round_horror = maxi(best_round_horror, current_round)
	elif game_mode == "infinite":
		best_round_infinite = maxi(best_round_infinite, current_round)
	else:
		best_round = maxi(best_round, current_round)
	best_kills = maxi(best_kills, total_kills)
	write_save()
	return current_round > _best_round_at_start


func record_exfil() -> void:
	exfils += 1
	best_exfil_round = maxi(best_exfil_round, current_round)
	record_run()


func _setup_input_map() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("reload", [KEY_R])
	_bind_keys("interact", [KEY_E])
	_bind_keys("skill_1", [KEY_Q])
	_bind_keys("skill_2", [KEY_F])
	_bind_keys("weapon_1", [KEY_1])
	_bind_keys("weapon_2", [KEY_2])
	_bind_keys("pause", [KEY_ESCAPE])
	_bind_keys("crouch", [KEY_C, KEY_CTRL])
	_bind_keys("melee", [KEY_V])
	_bind_keys("grenade", [KEY_G])
	_bind_keys("tactical", [KEY_4])
	_bind_keys("throw_c4", [KEY_T])
	_bind_keys("place_mine", [KEY_B])
	_bind_keys("borrowed_skill", [KEY_X])
	_bind_keys("borrowed_skill_2", [KEY_Z])
	_bind_keys("map", [KEY_M])
	_bind_keys("ready_round", [KEY_N])
	_bind_keys("flashlight", [KEY_L])
	_bind_keys("inspect_weapon", [KEY_I])
	var mmb := InputEventMouseButton.new()
	mmb.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("flashlight", mmb)
	_bind_keys("scoreboard", [KEY_TAB])
	_bind_mouse("fire", MOUSE_BUTTON_LEFT)
	_bind_mouse("aim", MOUSE_BUTTON_RIGHT)


# ---------------------------------------------------------------------------
# KEY BINDINGS: the first binding of each action can be changed in Options
# ---------------------------------------------------------------------------
const REBINDABLE := [
	["move_forward", "MOVE FORWARD"], ["move_back", "MOVE BACK"], ["move_left", "MOVE LEFT"], ["move_right", "MOVE RIGHT"],
	["jump", "JUMP"], ["sprint", "SPRINT"], ["crouch", "CROUCH / SLIDE"], ["fire", "SHOOT"], ["aim", "AIM"],
	["reload", "RELOAD"], ["interact", "INTERACT / BUY"], ["melee", "KNIFE"], ["grenade", "LETHAL GRENADE"], ["tactical", "TACTICAL (FLASH / SMOKE)"],
	["skill_1", "SKILL 1"], ["skill_2", "SKILL 2 (ULTIMATE)"], ["weapon_1", "WEAPON 1"], ["weapon_2", "WEAPON 2"],
	["throw_c4", "C4 (TAP / HOLD)"], ["place_mine", "PLACE MINE"], ["borrowed_skill", "RELIC SKILL 1"], ["borrowed_skill_2", "RELIC SKILL 2"],
	["flashlight", "FLASHLIGHT"], ["inspect_weapon", "INSPECT WEAPON"], ["ready_round", "READY NEXT ROUND"], ["map", "FULL MAP"], ["scoreboard", "SCOREBOARD (HOLD)"],
]
var _default_events: Dictionary = {}


func _event_code(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return "k:%d" % (k.physical_keycode if k.physical_keycode != 0 else k.keycode)
	if ev is InputEventMouseButton:
		return "m:%d" % (ev as InputEventMouseButton).button_index
	return ""


func _event_from_code(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "k":
		var k := InputEventKey.new()
		k.physical_keycode = int(parts[1]) as Key
		return k
	var m := InputEventMouseButton.new()
	m.button_index = int(parts[1]) as MouseButton
	return m


func key_code(action: String) -> String:
	if key_binds.has(action):
		return String(key_binds[action])
	var evs: Array = InputMap.action_get_events(action) if InputMap.has_action(action) else []
	return _event_code(evs[0]) if not evs.is_empty() else ""


func key_label(action: String) -> String:
	var code := key_code(action)
	if code.begins_with("m:"):
		match int(code.substr(2)):
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_XBUTTON1: return "MOUSE 4"
			MOUSE_BUTTON_XBUTTON2: return "MOUSE 5"
		return "MOUSE %s" % code.substr(2)
	if code.begins_with("k:"):
		var phys := int(code.substr(2)) as Key
		var shown := DisplayServer.keyboard_get_keycode_from_physical(phys) if DisplayServer.get_name() != "headless" else phys
		return OS.get_keycode_string(shown).to_upper()
	return "?"


# Puts `code` on `action`. If another action used that input, it gets this
# action's old input (a swap), so nothing is left unbound.
func rebind(action: String, code: String) -> void:
	var old := key_code(action)
	for pair in REBINDABLE:
		var other: String = pair[0]
		if other != action and key_code(other) == code:
			key_binds[other] = old
	key_binds[action] = code
	_apply_key_binds()
	write_save()


func reset_key_binds() -> void:
	key_binds.clear()
	_apply_key_binds()
	write_save()


func _apply_key_binds() -> void:
	for pair in REBINDABLE:
		var action: String = pair[0]
		if not InputMap.has_action(action):
			continue
		if not _default_events.has(action):
			_default_events[action] = InputMap.action_get_events(action)
		InputMap.action_erase_events(action)
		var defaults: Array = _default_events[action]
		if key_binds.has(action):
			var ev := _event_from_code(String(key_binds[action]))
			if ev:
				InputMap.action_add_event(action, ev)
			# keep the alternate default keys (arrow keys, Ctrl) unless taken elsewhere
			for i in range(1, defaults.size()):
				InputMap.action_add_event(action, defaults[i])
		else:
			for d in defaults:
				InputMap.action_add_event(action, d)


# Swaps default key letters like "[E]" in on-screen text for the player's keys.
const _KEY_HINTS := {"E": "interact", "Q": "skill_1", "F": "skill_2", "R": "reload", "G": "grenade", "V": "melee",
	"T": "throw_c4", "B": "place_mine", "X": "borrowed_skill", "Z": "borrowed_skill_2", "N": "ready_round", "I": "inspect_weapon"}


func get_crosshair_color() -> Color:
	const CH_COLS: Array = [
		Color(0.95, 0.95, 0.95, 0.88),
		Color(0.22, 0.92, 1.0, 0.92),
		Color(0.28, 0.96, 0.44, 0.92),
		Color(1.0, 0.78, 0.20, 0.92),
		Color(1.0, 0.24, 0.24, 0.92),
	]
	return CH_COLS[clampi(crosshair_color, 0, CH_COLS.size() - 1)] as Color


func reset_settings_category(cat: String) -> void:
	match cat:
		"display":
			graphics_quality = 2
			msaa_level = 1
			render_scale_setting = 1.0
			resolution = "native"
			fullscreen = false
			vsync_on = true
			fov_setting = 90.0
			post_fx_enabled = true
			show_fps = false
			apply_graphics()
		"gameplay":
			crosshair_enabled = true
			show_crosshair = false
			crosshair_color = 0
			damage_numbers = false
			show_minimap = false
			viewmodel_bob = 1.0
			screen_shake = 1.0
		"controls":
			mouse_sens_mult = 1.0
			ads_sens_mult = 0.85
			invert_y = false
			sprint_mode = 0
			ads_mode = 0
			crouch_mode = 0
		"audio":
			master_volume = 0.8
			sfx_volume = 1.0
			step_volume = 1.0
			hitmarker_sfx = true
			menu_sound = true
			apply_volume()
		"keybinds":
			reset_key_binds()
			return
	write_save()


func keyify(text: String) -> String:
	if key_binds.is_empty() or text.find("[") < 0:
		return text
	# One pass over the text so swapped keys don't undo each other
	var re := RegEx.create_from_string("\\[([A-Z])(?=[\\] /])")
	var out := ""
	var last := 0
	for m in re.search_all(text):
		var letter := m.get_string(1)
		var action: String = _KEY_HINTS.get(letter, "")
		if action != "" and key_binds.has(action):
			out += text.substr(last, m.get_start() - last) + "[" + key_label(action)
			last = m.get_end()
	return out + text.substr(last)


# ---------------------------------------------------------------------------
# RESOLUTION: window size when windowed; 3D render resolution when fullscreen
# ---------------------------------------------------------------------------
const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]


func resolution_options() -> Array:
	var out := ["native"]
	var scr := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1920, 1080)
	for r in RESOLUTIONS:
		var p: PackedStringArray = r.split("x")
		if int(p[0]) <= scr.x and int(p[1]) <= scr.y:
			out.append(r)
	return out


func _resolution_size() -> Vector2i:
	if resolution == "native" or not "x" in resolution:
		return Vector2i.ZERO
	var p := resolution.split("x")
	return Vector2i(int(p[0]), int(p[1]))


func _bind_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _bind_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _preload_audio() -> void:
	var names := [
		"gun_pistol", "gun_rifle", "gun_shotgun", "enemy_gunshot", "reload",
		"monster_roar", "monster_rend", "monster_slam", "pain_drug",
		"gorilla_slam", "zombie_groan", "zombie_step_1", "zombie_step_2",
		"boss_step", "zombie_roar_1", "zombie_roar_2", "zombie_attack_roar",
		"boss_roar", "buy_ching",
		"gun_smg", "gun_lmg", "gun_sniper", "gun_revolver", "gun_volt",
		"knife_swing", "knife_hit", "grenade_explode", "grenade_pin",
		"crate_open", "crate_reveal", "furnace_burn", "level_up", "dry_fire",
		"board_repair", "board_tear", "door_open", "player_hurt", "weapon_swap",
		"slide", "player_step_1", "player_step_2", "shell_insert",
		"flesh_hit", "hit_flesh", "ricochet", "gore_splat", "shell_tink", "zombie_death", "pump_rack", "bolt_cycle",
		"mag_out", "mag_in", "power_on", "trap_zap", "electrocute", "skull_shatter",
		"heartbeat", "hit_tick", "kill_confirm", "low_ammo_tick",
		"rain_loop", "rain_indoor_loop", "roof_rain_loop", "wind_loop", "fire_loop", "hum_loop",
		"creak", "drip", "crow", "bell_far", "train_horn", "scream_far",
		"hound_growl", "hound_bark", "hound_howl", "hound_bite", "hound_death",
		"lightning_strike", "thunder_far", "bloater_pop", "player_cough", "player_downed", "second_wind",
		"heli_loop", "flare_ignite", "flare_burn", "radio_call", "radio_beep", "exfil_siren",
		"carpenter", "powerup_spawn",
		"breath_panic", "whisper_eerie", "metal_scrape", "fluorescent_buzz",
		"flashlight_click", "headshot_crunch", "boss_blackout", "gun_suppressed"
	]
	for n in names:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_sfx_cache[n] = load(path)
	for i in range(36):
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_players.append(p)


func get_sfx_stream(sfx_name: String) -> AudioStream:
	return _sfx_cache.get(sfx_name, null)


func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not _sfx_cache.has(sfx_name):
		return
	for p in _sfx_players:
		if not p.playing:
			p.stream = _sfx_cache[sfx_name]
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale
			p.play()
			return
	# Fallback round-robin so long stings on slot 0 aren't repeatedly cut off
	var p_rr := _sfx_players[_sfx_next_idx % _sfx_players.size()]
	_sfx_next_idx = (_sfx_next_idx + 1) % _sfx_players.size()
	p_rr.stream = _sfx_cache[sfx_name]
	p_rr.volume_db = volume_db
	p_rr.pitch_scale = pitch_scale
	p_rr.play()


func reset_run() -> void:
	_zombie_roar_cooldown = 0.0
	_zombie_roar_slots.clear()
	if game_mode == "overdrive":
		_best_round_at_start = best_round_overdrive
	elif game_mode == "horror":
		_best_round_at_start = best_round_horror
	elif game_mode == "infinite":
		_best_round_at_start = best_round_infinite
	else:
		_best_round_at_start = best_round
	points_mult = 1.0
	points = start_points()
	_run_finished = false
	current_round = 1
	total_kills = 0
	headshots = 0
	bosses_slain = 0
	commanders_slain = 0
	challenges_done = 0
	downs = 0
	run_time = 0.0
	round_event = ""
	for k in powerup_timers.keys():
		powerup_timers[k] = 0.0
	powerups_changed.emit()
	points_changed.emit(points, 0)
	round_changed.emit(current_round)


func event_points_mult() -> float:
	match round_event:
		"blood_moon":
			return 1.5
		"cunning", "toxic":
			return 1.25
	return 1.0


func add_points(amount: int) -> void:
	if amount > 0:
		amount = int(round(float(amount) * points_mult * diff("points") * event_points_mult()))
		if is_powerup_active("quad_points"):
			amount *= 4
		elif is_powerup_active("double_points"):
			amount *= 2
	points += amount
	points_changed.emit(points, amount)


# Spends points for a purchase, or tells the player they can't afford it.
func try_pay(player: Node, amount: int) -> bool:
	if spend_points(amount):
		return true
	if player and player.has_signal("status_banner_requested"):
		player.status_banner_requested.emit("NOT ENOUGH POINTS — NEED %d" % amount, Color(1.0, 0.35, 0.30))
	play_sfx("dry_fire", -2.0, 0.7)
	return false


func spend_points(cost: int) -> bool:
	if points < cost:
		return false
	points -= cost
	points_changed.emit(points, -cost)
	play_sfx("buy_ching", -3.0, 1.0)
	return true


func get_boss_config(round_num: int) -> Dictionary:
	if round_num == FINAL_ROUND and game_mode == "casual":
		var c: Dictionary = _boss_config(4 + 15).duplicate()
		c["name"] = "THE PROGENITOR — FINAL BOSS"
		c["subtitle"] = "PATIENT ZERO OF NACHT-7 // KILL IT TO END THE OUTBREAK"
		c["max_hp"] = roundf(float(c["max_hp"]) * 2.2)
		c["damage"] = roundf(float(c["damage"]) * 1.2)
		c["scale"] = float(c.get("scale", 1.2)) * 1.25
		c["color"] = Color(1.0, 0.82, 0.25)
		c["final"] = true
		return c
	return _boss_config(round_num)


func _boss_config(round_num: int) -> Dictionary:
	var tier: int = max(0, (round_num - 1) / 5)
	var slot: int = ((round_num - 1) % 5) + 1
	var hp_mult: float = pow(1.45, float(tier))
	var dmg_mult: float = pow(1.22, float(tier))
	var prefix: String = "" if tier == 0 else ("APEX " if tier == 1 else "OMEGA ")

	match slot:
		1:
			return {
				"type": "gun_zombie",
				"name": prefix + "CORP. VEX — ARMED REMNANT",
				"subtitle": "TACTICAL MARKSMAN ZOMBIE // LOCKS LASER & SHOOTS PLAYER",
				"model": "res://assets/models/boss_gun_zombie.glb",
				"max_hp": roundf(620.0 * hp_mult),
				"endurance": 0.15,
				"speed": 3.8,
				"damage": roundf(16.0 * dmg_mult),
				"scale": 1.15,
				"reward": 500 + round_num * 100,
				"color": Color(1.0, 0.24, 0.18),
			}
		2:
			return {
				"type": "gorilla",
				"name": prefix + "SUBJECT GOLIATH — TITAN GORILLA",
				"subtitle": "HIGH ENDURANCE & MASSIVE DAMAGE // SLOW TELEGRAPHED SLAMS",
				"model": "res://assets/models/boss_gorilla.glb",
				"max_hp": roundf(1850.0 * hp_mult),
				"endurance": 0.45, # 45% innate damage reduction unless Pain-Drugged!
				"speed": 3.4,
				"damage": roundf(64.0 * dmg_mult),
				"scale": 1.32,
				"reward": 750 + round_num * 120,
				"color": Color(1.0, 0.48, 0.12),
			}
		3:
			return {
				"type": "necromancer",
				"name": prefix + "PATIENT ZERO-9 — BLIGHT SPITTER",
				"subtitle": "TOXIC MORTAR ARTILLERY & CRAWLER SUMMONER",
				"model": "res://assets/models/boss_necromancer.glb",
				"max_hp": roundf(1350.0 * hp_mult),
				"endurance": 0.25,
				"speed": 3.6,
				"damage": roundf(28.0 * dmg_mult),
				"scale": 1.22,
				"reward": 900 + round_num * 130,
				"color": Color(0.32, 1.0, 0.25),
			}
		4:
			return {
				"type": "juggernaut",
				"name": prefix + "PANZER-KRIEG — IRON JUGGERNAUT",
				"subtitle": "HEAVY ARMORED FLAMETHROWER MECH // AIM FOR POWER CORE OR DRUG",
				"model": "res://assets/models/boss_juggernaut.glb",
				"max_hp": roundf(2400.0 * hp_mult),
				"endurance": 0.55,
				"speed": 2.9,
				"damage": roundf(42.0 * dmg_mult),
				"scale": 1.30,
				"reward": 1100 + round_num * 150,
				"color": Color(1.0, 0.75, 0.15),
			}
		_:
			return {
				"type": "phantom",
				"name": prefix + "WRAITH-11 — VOLT REAPER",
				"subtitle": "PHASE-BLINKING ASSASSIN // TELEPORTS WITH SHOCK BLADES",
				"model": "res://assets/models/boss_phantom.glb",
				"max_hp": roundf(1550.0 * hp_mult),
				"endurance": 0.20,
				"speed": 5.6,
				"damage": roundf(38.0 * dmg_mult),
				"scale": 1.18,
				"reward": 1300 + round_num * 160,
				"color": Color(0.45, 0.72, 1.0),
			}


func to_roman(n: int) -> String:
	var vals := [100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var res := ""
	var rem := maxi(1, n)
	for i in range(vals.size()):
		while rem >= vals[i]:
			res += syms[i]
			rem -= vals[i]
	return res


# Graphics presets for weaker PCs. Low frame rates are what make aiming feel
# laggy, so Low drops the expensive screen effects and renders 3D at 75%.
func apply_graphics() -> void:
	var want_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want_mode and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(want_mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	if vp == null:
		return
	var q := graphics_quality
	var msaa_modes: Array = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
	vp.msaa_3d = msaa_modes[clampi(msaa_level, 0, 2)] as Viewport.MSAA
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var res := _resolution_size()
	var render_scale := 1.0
	if DisplayServer.get_name() != "headless":
		var scr := DisplayServer.screen_get_size()
		if res != Vector2i.ZERO and not fullscreen:
			# Windowed: the window itself is that size, centred on the screen
			if DisplayServer.window_get_size() != res:
				DisplayServer.window_set_size(res)
				DisplayServer.window_set_position(DisplayServer.screen_get_position() + (scr - res) / 2)
		elif res != Vector2i.ZERO and fullscreen and scr.y > 0:
			# Fullscreen: the game renders at that resolution and is scaled to the screen
			render_scale = clampf(float(res.y) / float(scr.y), 0.25, 1.0)
	var eff_scale: float = clampf(render_scale * render_scale_setting * (0.82 if q == 0 and render_scale_setting >= 0.99 else 1.0), 0.5, 1.0)
	vp.scaling_3d_scale = eff_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if eff_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.positional_shadow_atlas_size = [1024, 2048, 4096][q]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][q], true)
	var scene := get_tree().current_scene
	if scene == null:
		return
	for we in scene.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (we as WorldEnvironment).environment
		if env:
			env.ssr_enabled = q == 2
			env.ssao_enabled = q >= 1
			env.volumetric_fog_enabled = (q >= 1) and not (is_overdrive() or is_pvp())


# ---------------------------------------------------------------------------
# DIFFICULTY, RUN SCORE AND CAREER PROGRESSION
# ---------------------------------------------------------------------------
const DIFFICULTY_NAMES := ["EASY", "NORMAL", "HARD", "VETERAN", "NIGHTMARE", "APOCALYPSE", "EXTINCTION"]
# Every rule a difficulty changes, as multipliers (1.0 = Normal).
#  hp/dmg/speed: zombies   crowd: zombies per round   special: how often special
#  zombies appear   boss: extra boss health   regen: your health regen
#  horror: 0 = a normal zombie shooter .. 1 = dark, lights fail, things stalk you
#  points: points you earn   score: run score at the end
const DIFFICULTIES := [
	{"hp": 0.75, "dmg": 0.7, "speed": 1.0, "crowd": 1.0, "special": 1.0, "boss": 1.0, "regen": 1.0, "points": 1.0, "score": 0.75, "horror": 0.65},
	{"hp": 1.0, "dmg": 1.0, "speed": 1.0, "crowd": 1.0, "special": 1.0, "boss": 1.0, "regen": 1.0, "points": 1.0, "score": 1.0, "horror": 0.78},
	{"hp": 1.2, "dmg": 1.15, "speed": 1.0, "crowd": 1.0, "special": 1.0, "boss": 1.0, "regen": 1.0, "points": 1.0, "score": 1.5, "horror": 0.85},
	{"hp": 1.4, "dmg": 1.3, "speed": 1.04, "crowd": 1.1, "special": 1.2, "boss": 1.05, "regen": 1.0, "points": 1.0, "score": 2.0, "horror": 0.90},
	{"hp": 1.65, "dmg": 1.45, "speed": 1.08, "crowd": 1.2, "special": 1.4, "boss": 1.15, "regen": 0.9, "points": 1.0, "score": 2.75, "horror": 0.95},
	{"hp": 1.95, "dmg": 1.65, "speed": 1.12, "crowd": 1.3, "special": 1.7, "boss": 1.25, "regen": 0.8, "points": 0.95, "score": 3.5, "horror": 1.0},
	{"hp": 2.3, "dmg": 1.9, "speed": 1.16, "crowd": 1.4, "special": 2.0, "boss": 1.35, "regen": 0.7, "points": 0.9, "score": 4.5, "horror": 1.0},
]
const OVERDRIVE_DIFFICULTY_NAMES := ["ROOKIE", "TURBO", "MAYHEM", "CARNAGE", "OVERKILL"]
const OVERDRIVE_DIFFICULTIES := [
	{"hp": 0.70, "dmg": 0.65, "speed": 1.05, "crowd": 1.15, "special": 1.15, "boss": 0.85, "regen": 1.50, "points": 1.25, "score": 0.85, "horror": 0.0, "mutators": 1, "boss_traits": 0, "twin_every": 0, "combo_window": 6.5},
	{"hp": 0.90, "dmg": 0.90, "speed": 1.12, "crowd": 1.30, "special": 1.40, "boss": 1.00, "regen": 1.30, "points": 1.25, "score": 1.20, "horror": 0.0, "mutators": 1, "boss_traits": 1, "twin_every": 0, "combo_window": 5.5},
	{"hp": 1.15, "dmg": 1.15, "speed": 1.20, "crowd": 1.50, "special": 1.75, "boss": 1.20, "regen": 1.15, "points": 1.35, "score": 1.75, "horror": 0.0, "mutators": 2, "boss_traits": 1, "twin_every": 0, "combo_window": 4.8},
	{"hp": 1.45, "dmg": 1.40, "speed": 1.28, "crowd": 1.75, "special": 2.15, "boss": 1.40, "regen": 1.00, "points": 1.45, "score": 2.50, "horror": 0.0, "mutators": 2, "boss_traits": 2, "twin_every": 5, "combo_window": 4.2},
	{"hp": 1.80, "dmg": 1.70, "speed": 1.36, "crowd": 2.00, "special": 2.60, "boss": 1.65, "regen": 0.85, "points": 1.60, "score": 3.50, "horror": 0.0, "mutators": 2, "boss_traits": 2, "twin_every": 3, "combo_window": 3.6},
]
const FINAL_ROUND := 20
const META_UNLOCKS := [
	{"level": 2, "id": "points_250", "text": "+250 STARTING POINTS"},
	{"level": 3, "id": "grenade", "text": "+1 STARTING GRENADE"},
	{"level": 4, "id": "skill_slot", "text": "SECOND RELIC SKILL SLOT [Z]"},
	{"level": 5, "id": "points_500", "text": "+500 MORE STARTING POINTS"},
	{"level": 6, "id": "relic_luck", "text": "RELIC LUCK: STAT RELICS MAY UPGRADE A RARITY"},
	{"level": 8, "id": "start_smg", "text": "START WITH THE KURZ-9 SMG"},
	{"level": 10, "id": "damage", "text": "+6% WEAPON DAMAGE"},
	{"level": 12, "id": "challenge_pay", "text": "ROUND CHALLENGES PAY +50%"},
	{"level": 14, "id": "second_wind", "text": "START EVERY RUN WITH 1 SECOND WIND"},
	{"level": 16, "id": "armor", "text": "25 OVERSHIELD AT THE START OF EVERY ROUND"},
	{"level": 18, "id": "points_1250", "text": "+750 MORE STARTING POINTS"},
	{"level": 20, "id": "reload", "text": "+10% RELOAD & WEAPON SWAP SPEED"},
]
const MAX_PVP_PLAYERS := 32
const PVP_MODES := {
	"tdm": {"name": "TEAM DEATHMATCH", "short": "TDM", "tag": "75 / 50 KILLS", "icon": "skull", "desc": "Fast-paced squad combat across all arena sectors. First team to score cap wins."},
	"gungame": {"name": "GUN GAME", "short": "GUN GAME", "tag": "12 TIERS", "icon": "rifle", "desc": "Advance 12 weapons ending with RPG-7V2 & Knife. Knife kills demote victims!"},
	"snd": {"name": "SEARCH & DESTROY", "short": "S&D", "tag": "NO RESPAWN", "icon": "bolt", "desc": "1 life per round. Plant or defuse C4 at Site A or B across 2, 4, or 6 squads."},
	"dom": {"name": "DOMINATION", "short": "DOMINATION", "tag": "3 FLAGS", "icon": "flag", "desc": "Capture & hold Objectives A, B, and C to earn +1 pt per flag every 2s to 150."},
}
const PVP_MAP_ORDER: Array[String] = ["nacht", "dockyard", "black_site", "quarry", "substation"]
const PVP_MAPS := {
	"nacht": {
		"id": "nacht", "name": "OUTPOST NACHT-7", "short": "NACHT-7", "tag": "LARGE · 6 SECTORS",
		"icon": "compass", "accent": Color(0.95, 0.42, 0.28),
		"desc": "Fortified 6-sector town around a central memorial plaza.",
	},
	"dockyard": {
		"id": "dockyard", "name": "IRONCLAD DOCKYARD", "short": "DOCKYARD", "tag": "FAST · CQC PORT",
		"icon": "chopper", "accent": Color(0.28, 0.78, 1.00),
		"desc": "Symmetric 3-lane container terminal, crane hub & coastal helipad.",
	},
	"black_site": {
		"id": "black_site", "name": "SUB-ZERO BLACK SITE", "short": "BLACK SITE", "tag": "MEDIUM · ARCTIC LAB",
		"icon": "snow", "accent": Color(0.48, 0.94, 1.00),
		"desc": "Polar cryo-facility & raised missile silo rotunda with 4 breach lanes.",
	},
	"quarry": {
		"id": "quarry", "name": "SUNSCORCH REFINERY", "short": "REFINERY", "tag": "OPEN · DESERT BASIN",
		"icon": "flame", "accent": Color(1.00, 0.68, 0.22),
		"desc": "Canyon oil refinery with long sightlines, trenches & cracking towers.",
	},
	"substation": {
		"id": "substation", "name": "GRIDLOCK SUBSTATION", "short": "SUBSTATION", "tag": "MEDIUM · 3-LANE NIGHT",
		"icon": "bolt", "accent": Color(1.00, 0.48, 0.10),
		"desc": "Rain-soaked power substation: sunken cargo pit & sniper catwalk, server bunker, fuel depot.",
	},
}
const PVP_TEAMS := [
	{"id": 0, "name": "ALPHA", "code": "ALP", "zone": "rail", "color": Color(0.96, 0.26, 0.22)},
	{"id": 1, "name": "BRAVO", "code": "BRV", "zone": "church", "color": Color(0.24, 0.64, 1.00)},
	{"id": 2, "name": "CHARLIE", "code": "CHL", "zone": "warehouse", "color": Color(0.26, 0.92, 0.50)},
	{"id": 3, "name": "DELTA", "code": "DLT", "zone": "hospital", "color": Color(1.00, 0.82, 0.20)},
	{"id": 4, "name": "ECHO", "code": "ECH", "zone": "plaza", "color": Color(0.76, 0.40, 1.00)},
	{"id": 5, "name": "FOXTROT", "code": "FOX", "zone": "cemetery", "color": Color(1.00, 0.50, 0.16)},
]
const PVP_TEAM_PRESETS := {
	2: {"teams": 2, "max_per_team": 16, "max_players": 32, "label": "2 TEAMS (16v16)"},
	4: {"teams": 4, "max_per_team": 8, "max_players": 32, "label": "4 TEAMS (4x8)"},
	6: {"teams": 6, "max_per_team": 6, "max_players": 32, "label": "6 TEAMS (6x6)"},
}
const GUN_GAME_LADDER: Array[String] = ["pistol", "deagle_50", "spas12", "vector_45", "m4_carbine", "scar_h", "mk14_ebr", "m249_saw", "awm_magnum", "volt", "rpg7", "knife"]
const PVP_WEAPON_DAMAGE := WeaponCatalog.PVP_DAMAGE

var difficulty: int = 1 # 0 easy, 1 normal, 2 hard (the host's choice in co-op)
var overdrive_difficulty: int = 1 # 0..4 index into OVERDRIVE_DIFFICULTIES
var career_xp: int = 0
var _run_finished: bool = false


func is_overdrive() -> bool:
	return game_mode == "overdrive"


func is_horror_mode() -> bool:
	return game_mode == "horror"


func is_pvp() -> bool:
	return game_mode == "pvp"


func pvp_team_count() -> int:
	return int(PVP_TEAM_PRESETS.get(team_preset, PVP_TEAM_PRESETS[2])["teams"])


func pvp_max_per_team() -> int:
	return int(PVP_TEAM_PRESETS.get(team_preset, PVP_TEAM_PRESETS[2])["max_per_team"])


func pvp_team_color(tid: int) -> Color:
	return PVP_TEAMS[clampi(tid, 0, PVP_TEAMS.size() - 1)]["color"]


func pvp_team_name(tid: int) -> String:
	return String(PVP_TEAMS[clampi(tid, 0, PVP_TEAMS.size() - 1)]["name"])


func pvp_team_code(tid: int) -> String:
	return String(PVP_TEAMS[clampi(tid, 0, PVP_TEAMS.size() - 1)]["code"])


func pvp_weapon_damage(w_id: String) -> float:
	return float(PVP_WEAPON_DAMAGE.get(w_id, 28.0))


func resolve_pvp_map() -> String:
	if pvp_map == "random":
		var pool: Array[String] = []
		for mid in PVP_MAP_ORDER:
			pool.append(mid)
		if PVP_MAPS.has(active_pvp_map) and pool.size() > 1 and randf() < 0.75:
			pool.erase(active_pvp_map)
		active_pvp_map = pool[randi() % pool.size()]
		return active_pvp_map
	if PVP_MAPS.has(pvp_map):
		active_pvp_map = pvp_map
		return active_pvp_map
	pvp_map = "nacht"
	active_pvp_map = "nacht"
	return "nacht"


func pvp_map_info(map_key: String = "") -> Dictionary:
	var k: String = map_key if map_key != "" else active_pvp_map
	return PVP_MAPS.get(k, PVP_MAPS["nacht"])


func mode_label() -> String:
	if is_pvp():
		var m: Dictionary = PVP_MODES.get(pvp_mode, PVP_MODES["tdm"])
		return "%s (%dT)" % [String(m["short"]), pvp_team_count()]
	if game_mode == "overdrive":
		return "OVERDRIVE"
	if game_mode == "horror":
		return "HORROR"
	return "CASUAL" if game_mode == "casual" else "INFINITE"


func active_diff_index() -> int:
	if is_overdrive():
		return clampi(overdrive_difficulty, 0, OVERDRIVE_DIFFICULTIES.size() - 1)
	return clampi(difficulty, 0, DIFFICULTIES.size() - 1)


func active_diff_name() -> String:
	if is_overdrive():
		return OVERDRIVE_DIFFICULTY_NAMES[active_diff_index()]
	return DIFFICULTY_NAMES[active_diff_index()]


func diff_name_for(m: String, idx: int) -> String:
	if m == "overdrive":
		return OVERDRIVE_DIFFICULTY_NAMES[clampi(idx, 0, OVERDRIVE_DIFFICULTY_NAMES.size() - 1)]
	return DIFFICULTY_NAMES[clampi(idx, 0, DIFFICULTY_NAMES.size() - 1)]


func diff(key: String) -> float:
	if is_overdrive():
		return float(OVERDRIVE_DIFFICULTIES[clampi(overdrive_difficulty, 0, OVERDRIVE_DIFFICULTIES.size() - 1)].get(key, 1.0))
	return float(DIFFICULTIES[clampi(difficulty, 0, DIFFICULTIES.size() - 1)].get(key, 1.0))


# How frightening the game is on this mode & difficulty (0..1)
# Horror blackout / sensory infected / carrion crows are exclusive to HORROR mode.
func horror() -> float:
	if not is_horror_mode():
		return 0.0
	var raw := diff("horror") if DIFFICULTIES[clampi(difficulty, 0, DIFFICULTIES.size() - 1)].has("horror") else 0.85
	return clampf(raw, 0.80, 1.0)


func diff_hp_mult() -> float:
	return diff("hp")


func diff_dmg_mult() -> float:
	return diff("dmg")


func diff_score_mult() -> float:
	return diff("score")


# Plain lines describing what a difficulty changes compared to Normal.
func diff_lines(i: int) -> Array[String]:
	var d: Dictionary = DIFFICULTIES[i]
	var out: Array[String] = []
	var pct := func(label: String, key: String) -> void:
		var v := float(d.get(key, 1.0))
		if absf(v - 1.0) > 0.001:
			out.append("%s %s%d%%" % [label, "+" if v > 1.0 else "-", roundi(absf(v - 1.0) * 100.0)])
	pct.call("Zombie health", "hp")
	pct.call("Zombie damage", "dmg")
	pct.call("Zombie speed", "speed")
	pct.call("Zombies per round", "crowd")
	if absf(float(d["special"]) - 1.0) > 0.001:
		out.append("Special zombies x%s as often" % str(snappedf(float(d["special"]), 0.01)))
	pct.call("Boss health", "boss")
	pct.call("Your health regen", "regen")
	pct.call("Points earned", "points")
	if is_horror_mode():
		var hr := clampf(float(d.get("horror", 0.85)), 0.80, 1.0)
		var bits: Array[String] = ["pitch-black blackout", "tactical flashlight", "LOS & sound infected", "carrion crows & 6s corpse mutations"]
		if hr >= 0.92:
			bits.append("hidden zombie count")
		out.append("Survival Horror %d%%: %s" % [roundi(hr * 100.0), ", ".join(bits)])
	else:
		out.append("Night Outpost: lit streetlamps & interior lights ON")
	if out.is_empty():
		out.append("The standard experience")
	out.append("Score x%s" % str(snappedf(float(d["score"]), 0.01)))
	return out


func overdrive_diff_lines(i: int) -> Array[String]:
	var d: Dictionary = OVERDRIVE_DIFFICULTIES[clampi(i, 0, OVERDRIVE_DIFFICULTIES.size() - 1)]
	var out: Array[String] = []
	var pct := func(label: String, key: String) -> void:
		var v := float(d.get(key, 1.0))
		if absf(v - 1.0) > 0.001:
			out.append("%s %s%d%%" % [label, "+" if v > 1.0 else "-", roundi(absf(v - 1.0) * 100.0)])
	pct.call("Zombie speed", "speed")
	pct.call("Zombies per round", "crowd")
	pct.call("Zombie health", "hp")
	pct.call("Zombie damage", "dmg")
	out.append("Specials x%s" % str(snappedf(float(d["special"]), 0.01)))
	var mut_n: int = int(d.get("mutators", 1))
	out.append("%d Chaos Mutator%s / round" % [mut_n, "s" if mut_n > 1 else ""])
	var tr_n: int = int(d.get("boss_traits", 0))
	if tr_n > 0:
		out.append("Champion Bosses (%d trait%s)" % [tr_n, "s" if tr_n > 1 else ""])
	var tw_n: int = int(d.get("twin_every", 0))
	if tw_n > 0:
		out.append("Twin Bosses every %d rounds" % tw_n)
	out.append("Combo window %.1fs" % float(d.get("combo_window", 5.0)))
	out.append("Zero horror: golden daylight, pre-lit arena & tactical HUD")
	out.append("Score x%s" % str(snappedf(float(d["score"]), 0.01)))
	return out


static func xp_for_level(level: int) -> int:
	return 300 * level * (level - 1)


func career_level() -> int:
	var lvl := 1
	while career_xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl


func has_unlock(id: String) -> bool:
	var lvl := career_level()
	for u in META_UNLOCKS:
		if u["id"] == id:
			return lvl >= int(u["level"])
	return false


func start_points() -> int:
	return 500 + (750 if is_overdrive() else 0) + (250 if has_unlock("points_250") else 0) + (500 if has_unlock("points_500") else 0) + (750 if has_unlock("points_1250") else 0)


func run_score(outcome: String) -> int:
	var s := total_kills * 10 + headshots * 5 + bosses_slain * 500 + commanders_slain * 300 + challenges_done * 150 + current_round * 250
	if outcome == "exfil":
		s += 3000
	elif outcome == "victory":
		s += 10000
	return int(float(s) * diff_score_mult())


# Ends the run once: score -> career XP (1 XP per 10 score). Returns the
# lines for the end screen.
func finish_run(outcome: String) -> String:
	var score := run_score(outcome)
	var before := career_level()
	var gained := 0
	var nemesis_note := ""
	if not _run_finished:
		_run_finished = true
		clear_run_save()
		gained = score / 10
		career_xp += gained
		life_kills += total_kills
		life_bosses += bosses_slain
		life_commanders += commanders_slain
		life_runs += 1
		if outcome == "death":
			nemesis_note = _update_nemesis()
		record_run()
		write_save()
	var after := career_level()
	var lines := mode_label() + " MODE\nSCORE: %d   (%s)\n+%d XP   •   CAREER LEVEL %d   (%d / %d XP)" % [score, active_diff_name(), gained, after, career_xp, xp_for_level(after + 1)]
	for u in META_UNLOCKS:
		if int(u["level"]) > before and int(u["level"]) <= after:
			lines += "\n★ UNLOCKED: %s" % u["text"]
	if nemesis_note != "":
		lines += "\n" + nemesis_note
	return lines


# You died: the strongest commander still standing remembers you and comes
# back in later runs. If it already was your nemesis, it grows a tier.
func _update_nemesis() -> String:
	var best: Node = null
	for c in get_tree().get_nodes_in_group("commanders"):
		if not is_instance_valid(c) or c.is_dead:
			continue
		if c.is_nemesis:
			best = c
			break
		if best == null or c.tier > best.tier:
			best = c
	if best == null:
		return ""
	if best.is_nemesis:
		nemesis["tier"] = mini(5, int(nemesis.get("tier", 3)) + 1)
		nemesis["kills"] = int(nemesis.get("kills", 1)) + 1
		return "YOUR NEMESIS %s KILLED YOU AGAIN AND GROWS STRONGER" % String(nemesis.get("name", ""))
	if nemesis.is_empty() or best.tier >= int(nemesis.get("tier", 3)):
		nemesis = {"name": best.commander_name, "tier": best.tier, "skill": best.stolen_skill, "kills": 1}
		return "%s WILL REMEMBER YOU — IT IS NOW YOUR NEMESIS" % best.commander_name
	return ""


# ---------------------------------------------------------------------------
# RUN SAVE (resume after a host drop / quit, rejoin with your loadout)
# ---------------------------------------------------------------------------
const RUN_SAVE_PATH := "user://run_save.cfg"
var run_id: int = 0
var pending_resume: bool = false # this run continues a saved one
var late_join: bool = false # joined a co-op game already in progress


func new_run_id() -> int:
	return randi() % 2000000000 + 1


func save_world(data: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(RUN_SAVE_PATH)
	cfg.set_value("world", "data", data)
	cfg.save(RUN_SAVE_PATH)


func load_world() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_SAVE_PATH) != OK:
		return {}
	return cfg.get_value("world", "data", {})


func save_player_state(data: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(RUN_SAVE_PATH)
	cfg.set_value("player", "data", data)
	cfg.save(RUN_SAVE_PATH)


func load_player_state(for_run: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_SAVE_PATH) != OK:
		return {}
	var d: Dictionary = cfg.get_value("player", "data", {})
	return d if int(d.get("run_id", -1)) == for_run else {}


func clear_run_save() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_SAVE_PATH))


# ---------------------------------------------------------------------------
# CUSTOM LOADOUT SETS (5 CoD / Battlefield-style Weapon + Equipment Classes)
# ---------------------------------------------------------------------------
static func is_valid_primary(w_id: String) -> bool:
	if not WEAPONS.has(w_id):
		return false
	var slot := String(WEAPONS[w_id].get("slot", "primary"))
	return slot == "primary" or slot == "both"


static func is_valid_secondary(w_id: String) -> bool:
	if not WEAPONS.has(w_id):
		return false
	var slot := String(WEAPONS[w_id].get("slot", "secondary"))
	return slot == "secondary" or slot == "both"


func sanitize_loadout(raw: Dictionary, fallback_idx: int = 0) -> Dictionary:
	var def_arr := WeaponCatalog.DEFAULT_LOADOUTS
	var def: Dictionary = def_arr[clampi(fallback_idx, 0, def_arr.size() - 1)]
	var name_str := String(raw.get("name", def.get("name", "CUSTOM CLASS"))).strip_edges().to_upper()
	if name_str.is_empty():
		name_str = String(def.get("name", "CUSTOM CLASS"))
	var pri := String(raw.get("primary", def.get("primary", "m4_carbine")))
	if not is_valid_primary(pri):
		pri = String(def.get("primary", "m4_carbine"))
	var sec := String(raw.get("secondary", def.get("secondary", "rpg7")))
	if not is_valid_secondary(sec):
		sec = String(def.get("secondary", "rpg7"))
	var atts: Array[String] = []
	var raw_atts = raw.get("attachments", def.get("attachments", []))
	if raw_atts is Array:
		for a in raw_atts:
			var aid := String(a)
			if is_attachment_allowed(pri, aid) and aid not in atts:
				atts.append(aid)
				if atts.size() >= 3:
					break
	var sec_atts: Array[String] = []
	var raw_sec_atts = raw.get("sec_attachments", def.get("sec_attachments", []))
	if raw_sec_atts is Array:
		for a in raw_sec_atts:
			var aid := String(a)
			if is_attachment_allowed(sec, aid) and aid not in sec_atts:
				sec_atts.append(aid)
				if sec_atts.size() >= 2:
					break
	var pri_camo := String(raw.get("pri_camo", def.get("pri_camo", "factory")))
	if not WEAPON_CAMOS.has(pri_camo):
		pri_camo = "factory"
	var sec_camo := String(raw.get("sec_camo", def.get("sec_camo", "factory")))
	if not WEAPON_CAMOS.has(sec_camo):
		sec_camo = "factory"
	var let_id := String(raw.get("lethal", def.get("lethal", "frag")))
	if not LETHALS.has(let_id):
		let_id = String(def.get("lethal", "frag"))
	var tac_id := String(raw.get("tactical", def.get("tactical", "flashbang")))
	if not TACTICALS.has(tac_id):
		tac_id = String(def.get("tactical", "flashbang"))
	var perk_id := String(raw.get("perk", def.get("perk", "fast_hands")))
	if not FIELD_PERKS.has(perk_id):
		perk_id = String(def.get("perk", "fast_hands"))
	return {
		"name": name_str.substr(0, 24),
		"primary": pri,
		"attachments": atts,
		"pri_camo": pri_camo,
		"secondary": sec,
		"sec_attachments": sec_atts,
		"sec_camo": sec_camo,
		"lethal": let_id,
		"tactical": tac_id,
		"perk": perk_id,
	}


func _ensure_loadouts() -> void:
	var target_count := WeaponCatalog.DEFAULT_LOADOUTS.size()
	while custom_loadouts.size() < target_count:
		var idx := custom_loadouts.size()
		custom_loadouts.append(sanitize_loadout(WeaponCatalog.DEFAULT_LOADOUTS[idx], idx))
	if custom_loadouts.size() > target_count:
		custom_loadouts.resize(target_count)
	for i in range(custom_loadouts.size()):
		custom_loadouts[i] = sanitize_loadout(custom_loadouts[i], i)
	active_loadout_index = clampi(active_loadout_index, 0, target_count - 1)


func get_loadout(idx: int) -> Dictionary:
	_ensure_loadouts()
	return custom_loadouts[clampi(idx, 0, custom_loadouts.size() - 1)]


func get_active_loadout() -> Dictionary:
	_ensure_loadouts()
	return custom_loadouts[active_loadout_index]


func set_active_loadout(idx: int, save_now: bool = true) -> void:
	_ensure_loadouts()
	active_loadout_index = clampi(idx, 0, custom_loadouts.size() - 1)
	pvp_loadout_weapon = String(custom_loadouts[active_loadout_index].get("primary", "m4_carbine"))
	if save_now:
		write_save()


func update_loadout(idx: int, data: Dictionary, save_now: bool = true) -> void:
	_ensure_loadouts()
	var i := clampi(idx, 0, custom_loadouts.size() - 1)
	custom_loadouts[i] = sanitize_loadout(data, i)
	if i == active_loadout_index:
		pvp_loadout_weapon = String(custom_loadouts[i].get("primary", "m4_carbine"))
	if save_now:
		write_save()


func reset_loadout_slot(idx: int, save_now: bool = true) -> void:
	_ensure_loadouts()
	var i := clampi(idx, 0, custom_loadouts.size() - 1)
	custom_loadouts[i] = sanitize_loadout(WeaponCatalog.DEFAULT_LOADOUTS[i], i)
	if i == active_loadout_index:
		pvp_loadout_weapon = String(custom_loadouts[i].get("primary", "m4_carbine"))
	if save_now:
		write_save()
