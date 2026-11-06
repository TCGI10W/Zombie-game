extends Node

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

# Timed power-ups dropped by zombies (seconds remaining)
var powerup_timers: Dictionary = {"insta_kill": 0.0, "double_points": 0.0, "fire_sale": 0.0}

# Saved between sessions
var best_round: int = 0
var best_kills: int = 0
var exfils: int = 0
var best_exfil_round: int = 0
var mouse_sens_mult: float = 1.0
var points_mult: float = 1.0 # Fortune stat bonus, set by the player
var master_volume: float = 0.8
var sfx_volume: float = 1.0
var invert_y: bool = false
var fullscreen: bool = false
var resolution: String = "native" # "native" or "WxH"
var key_binds: Dictionary = {} # action -> "k:<physical keycode>" or "m:<mouse button>"
var show_crosshair: bool = true
var damage_numbers: bool = true
var game_mode: String = "casual" # "casual" (ends at round 20) or "infinite"
var best_round_infinite: int = 0
var fov_setting: float = 80.0
var post_fx_enabled: bool = true
var graphics_quality: int = 2 # 0 low, 1 medium, 2 high
var vsync_on: bool = true
var show_fps: bool = false
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
const WEAPONS := {
	"pistol": {
		"id": "pistol", "name": "M1911 SIDEARM", "class": "pistol",
		"model": "res://assets/models/vm_pistol.glb", "sfx": "gun_pistol",
		"damage": 42.0, "headshot_mult": 2.3, "fire_rate": 0.17, "automatic": false,
		"mag_size": 8, "reserve_max": 80, "reload_time": 1.3, "reload_type": "mag",
		"pellets": 1, "spread_deg": 1.4, "ads_spread_deg": 0.15, "bloom": 0.6,
		"range": 70.0, "recoil_pitch": 1.6, "recoil_yaw": 0.6, "penetration": 0, "move_mult": 1.05,
		"ads_pos": Vector3(0.0, -0.074, -0.34), "ads_fov": 64.0, "ads_time": 0.16, "muzzle": Vector2(0.042, 0.26),
		"box_weight": 0,
	},
	"smg": {
		"id": "smg", "name": "KURZ-9 SMG", "class": "smg",
		"model": "res://assets/models/vm_smg.glb", "sfx": "gun_smg",
		"damage": 34.0, "headshot_mult": 2.2, "fire_rate": 0.07, "automatic": true,
		"mag_size": 32, "reserve_max": 256, "reload_time": 1.9, "reload_type": "mag",
		"pellets": 1, "spread_deg": 2.4, "ads_spread_deg": 0.6, "bloom": 0.35,
		"range": 50.0, "recoil_pitch": 0.75, "recoil_yaw": 0.55, "penetration": 0, "move_mult": 1.03,
		"ads_pos": Vector3(0.0, -0.075, -0.30), "ads_fov": 60.0, "ads_time": 0.17, "muzzle": Vector2(0.035, 0.44),
		"box_weight": 10,
	},
	"rifle": {
		"id": "rifle", "name": "COMMANDO M14A", "class": "rifle",
		"model": "res://assets/models/vm_rifle.glb", "sfx": "gun_rifle",
		"damage": 58.0, "headshot_mult": 2.4, "fire_rate": 0.115, "automatic": true,
		"mag_size": 30, "reserve_max": 210, "reload_time": 2.0, "reload_type": "mag",
		"pellets": 1, "spread_deg": 2.2, "ads_spread_deg": 0.25, "bloom": 0.45,
		"range": 95.0, "recoil_pitch": 1.25, "recoil_yaw": 0.5, "penetration": 1, "move_mult": 0.96,
		"ads_pos": Vector3(0.0, -0.088, -0.30), "ads_fov": 55.0, "ads_time": 0.22, "muzzle": Vector2(0.036, 0.79),
		"box_weight": 10,
	},
	"shotgun": {
		"id": "shotgun", "name": "TRENCH-12 PUMP", "class": "shotgun",
		"model": "res://assets/models/vm_shotgun.glb", "sfx": "gun_shotgun",
		"damage": 34.0, "headshot_mult": 1.85, "fire_rate": 0.72, "automatic": false,
		"mag_size": 6, "reserve_max": 54, "reload_time": 0.45, "reload_type": "shell",
		"pellets": 8, "spread_deg": 5.2, "ads_spread_deg": 3.4, "bloom": 0.0,
		"range": 36.0, "recoil_pitch": 4.2, "recoil_yaw": 1.0, "penetration": 0, "move_mult": 0.97,
		"ads_pos": Vector3(0.0, -0.07, -0.30), "ads_fov": 64.0, "ads_time": 0.2, "muzzle": Vector2(0.048, 0.72),
		"box_weight": 10,
	},
	"lmg": {
		"id": "lmg", "name": "RAZORBACK LMG", "class": "lmg",
		"model": "res://assets/models/vm_lmg.glb", "sfx": "gun_lmg",
		"damage": 64.0, "headshot_mult": 2.0, "fire_rate": 0.085, "automatic": true,
		"mag_size": 100, "reserve_max": 400, "reload_time": 4.2, "reload_type": "mag",
		"pellets": 1, "spread_deg": 3.2, "ads_spread_deg": 0.55, "bloom": 0.3,
		"range": 85.0, "recoil_pitch": 1.05, "recoil_yaw": 0.75, "penetration": 2, "move_mult": 0.86,
		"ads_pos": Vector3(0.0, -0.112, -0.30), "ads_fov": 56.0, "ads_time": 0.32, "muzzle": Vector2(0.04, 0.80),
		"box_weight": 12,
	},
	"sniper": {
		"id": "sniper", "name": "LONGSHOT .50", "class": "sniper",
		"model": "res://assets/models/vm_sniper.glb", "sfx": "gun_sniper",
		"damage": 680.0, "headshot_mult": 3.0, "fire_rate": 1.2, "automatic": false,
		"mag_size": 5, "reserve_max": 40, "reload_time": 3.0, "reload_type": "mag",
		"pellets": 1, "spread_deg": 8.0, "ads_spread_deg": 0.0, "bloom": 0.0,
		"range": 140.0, "recoil_pitch": 6.5, "recoil_yaw": 1.2, "penetration": 5, "move_mult": 0.9,
		"ads_pos": Vector3(0.0, -0.115, -0.25), "ads_fov": 22.0, "ads_time": 0.3, "muzzle": Vector2(0.04, 0.97),
		"scoped": true, "box_weight": 10,
	},
	"revolver": {
		"id": "revolver", "name": ".44 HAND CANNON", "class": "pistol",
		"model": "res://assets/models/vm_revolver.glb", "sfx": "gun_revolver",
		"damage": 185.0, "headshot_mult": 2.5, "fire_rate": 0.36, "automatic": false,
		"mag_size": 6, "reserve_max": 72, "reload_time": 2.4, "reload_type": "mag",
		"pellets": 1, "spread_deg": 1.8, "ads_spread_deg": 0.2, "bloom": 1.4,
		"range": 70.0, "recoil_pitch": 5.0, "recoil_yaw": 1.4, "penetration": 1, "move_mult": 1.04,
		"ads_pos": Vector3(0.0, -0.073, -0.34), "ads_fov": 60.0, "ads_time": 0.17, "muzzle": Vector2(0.045, 0.30),
		"box_weight": 12,
	},
	"volt": {
		"id": "volt", "name": "VOLT CANNON", "class": "wonder",
		"model": "res://assets/models/vm_volt.glb", "sfx": "gun_volt",
		"damage": 1100.0, "headshot_mult": 1.0, "fire_rate": 0.8, "automatic": false,
		"mag_size": 6, "reserve_max": 36, "reload_time": 2.8, "reload_type": "mag",
		"pellets": 1, "spread_deg": 0.8, "ads_spread_deg": 0.1, "bloom": 0.0,
		"range": 70.0, "recoil_pitch": 4.5, "recoil_yaw": 0.8, "penetration": 0, "move_mult": 0.95,
		"ads_pos": Vector3(0.0, -0.14, -0.36), "ads_fov": 62.0, "ads_time": 0.2, "muzzle": Vector2(0.02, 0.45),
		"chain": 5, "box_weight": 4,
	},
}

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

	for bus_name in ["SFX", "Zombies", "Music"]:
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
		invert_y = bool(cfg.get_value("settings", "invert_y", false))
		fullscreen = bool(cfg.get_value("settings", "fullscreen", false))
		resolution = String(cfg.get_value("settings", "resolution", "native"))
		key_binds = cfg.get_value("settings", "key_binds", {})
		_apply_key_binds()
		show_crosshair = bool(cfg.get_value("settings", "show_crosshair", true))
		damage_numbers = bool(cfg.get_value("settings", "damage_numbers", true))
		game_mode = String(cfg.get_value("settings", "game_mode", "casual"))
		best_round_infinite = int(cfg.get_value("records", "best_round_infinite", 0))
		fov_setting = float(cfg.get_value("settings", "fov", 80.0))
		post_fx_enabled = bool(cfg.get_value("settings", "post_fx", true))
		graphics_quality = int(cfg.get_value("settings", "graphics", 2))
		vsync_on = bool(cfg.get_value("settings", "vsync", true))
		show_fps = bool(cfg.get_value("settings", "show_fps", false))
		difficulty = clampi(int(cfg.get_value("settings", "difficulty", 1)), 0, DIFFICULTIES.size() - 1)
		career_xp = int(cfg.get_value("records", "career_xp", 0))
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
	cfg.set_value("settings", "invert_y", invert_y)
	cfg.set_value("settings", "fullscreen", fullscreen)
	cfg.set_value("settings", "resolution", resolution)
	cfg.set_value("settings", "key_binds", key_binds)
	cfg.set_value("settings", "show_crosshair", show_crosshair)
	cfg.set_value("settings", "damage_numbers", damage_numbers)
	cfg.set_value("settings", "game_mode", game_mode)
	cfg.set_value("records", "best_round_infinite", best_round_infinite)
	cfg.set_value("settings", "fov", fov_setting)
	cfg.set_value("settings", "post_fx", post_fx_enabled)
	cfg.set_value("settings", "graphics", graphics_quality)
	cfg.set_value("settings", "vsync", vsync_on)
	cfg.set_value("settings", "show_fps", show_fps)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("records", "career_xp", career_xp)
	cfg.save(SAVE_PATH)


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, master_volume)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	for bus in ["SFX", "Zombies"]:
		var bi := AudioServer.get_bus_index(bus)
		if bi >= 0:
			AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(0.0001, sfx_volume)))
			AudioServer.set_bus_mute(bi, sfx_volume <= 0.001)
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_mute(mb, true) # no music in this game


# Saves progress for this run. Returns true if this run beat the best round
# that was on record when the run started.
func record_run() -> bool:
	if game_mode == "infinite":
		best_round_infinite = maxi(best_round_infinite, current_round)
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
	_bind_keys("throw_c4", [KEY_T])
	_bind_keys("place_mine", [KEY_B])
	_bind_keys("borrowed_skill", [KEY_X])
	_bind_keys("borrowed_skill_2", [KEY_Z])
	_bind_mouse("fire", MOUSE_BUTTON_LEFT)
	_bind_mouse("aim", MOUSE_BUTTON_RIGHT)


# ---------------------------------------------------------------------------
# KEY BINDINGS: the first binding of each action can be changed in Options
# ---------------------------------------------------------------------------
const REBINDABLE := [
	["move_forward", "MOVE FORWARD"], ["move_back", "MOVE BACK"], ["move_left", "MOVE LEFT"], ["move_right", "MOVE RIGHT"],
	["jump", "JUMP"], ["sprint", "SPRINT"], ["crouch", "CROUCH / SLIDE"], ["fire", "SHOOT"], ["aim", "AIM"],
	["reload", "RELOAD"], ["interact", "INTERACT / BUY"], ["melee", "KNIFE"], ["grenade", "GRENADE"],
	["skill_1", "SKILL 1"], ["skill_2", "SKILL 2 (ULTIMATE)"], ["weapon_1", "WEAPON 1"], ["weapon_2", "WEAPON 2"],
	["throw_c4", "C4 (TAP / HOLD)"], ["place_mine", "PLACE MINE"], ["borrowed_skill", "RELIC SKILL 1"], ["borrowed_skill_2", "RELIC SKILL 2"],
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
	"T": "throw_c4", "B": "place_mine", "X": "borrowed_skill", "Z": "borrowed_skill_2"}


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
		"boss_roar", "round_sting", "buy_ching",
		"gun_smg", "gun_lmg", "gun_sniper", "gun_revolver", "gun_volt",
		"knife_swing", "knife_hit", "grenade_explode", "grenade_pin",
		"crate_open", "crate_reveal", "furnace_burn", "level_up", "dry_fire",
		"board_repair", "board_tear", "door_open", "player_hurt", "weapon_swap",
		"slide", "player_step_1", "player_step_2", "shell_insert",
		"flesh_hit", "hit_flesh", "headshot_ding", "ricochet", "gore_splat", "shell_tink", "zombie_death", "pump_rack", "bolt_cycle",
		"mag_out", "mag_in", "power_on", "trap_zap", "electrocute", "skull_shatter",
		"heartbeat", "hit_tick", "kill_confirm", "low_ammo_tick", "streak_sting",
		"rain_loop", "rain_indoor_loop", "roof_rain_loop", "wind_loop", "fire_loop", "hum_loop", "drone_loop",
		"creak", "drip", "crow", "bell_far", "train_horn", "scream_far",
		"hound_growl", "hound_bark", "hound_howl", "hound_bite", "hound_death", "hound_round_sting",
		"lightning_strike", "thunder_far", "bloater_pop", "player_cough", "player_downed", "second_wind",
		"heli_loop", "flare_ignite", "flare_burn", "radio_call", "radio_beep", "exfil_siren", "exfil_success",
		"carpenter", "fire_sale", "powerup_spawn"
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
	_best_round_at_start = best_round
	points_mult = 1.0
	points = start_points()
	_run_finished = false
	current_round = 1
	total_kills = 0
	headshots = 0
	bosses_slain = 0
	for k in powerup_timers.keys():
		powerup_timers[k] = 0.0
	powerups_changed.emit()
	points_changed.emit(points, 0)
	round_changed.emit(current_round)


func add_points(amount: int) -> void:
	if amount > 0:
		amount = int(round(float(amount) * points_mult * diff("points")))
		if is_powerup_active("double_points"):
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
				"model": "res://assets/models/boss_necromancer.glb",
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
	vp.msaa_3d = Viewport.MSAA_2X if q == 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q == 0 else Viewport.SCALING_3D_MODE_BILINEAR
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
	vp.scaling_3d_scale = render_scale * (0.75 if q == 0 else 1.0)
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
			env.volumetric_fog_enabled = q >= 1


# ---------------------------------------------------------------------------
# DIFFICULTY, RUN SCORE AND CAREER PROGRESSION
# ---------------------------------------------------------------------------
const DIFFICULTY_NAMES := ["EASY", "NORMAL", "HARD", "VETERAN", "NIGHTMARE", "APOCALYPSE", "EXTINCTION"]
# Every rule a difficulty changes, as multipliers (1.0 = Normal).
#  hp/dmg/speed: zombies   crowd: zombies per round   special: how often special
#  zombies appear   boss: extra boss health   regen: your health regen
#  points: points you earn   score: run score at the end
const DIFFICULTIES := [
	{"hp": 0.75, "dmg": 0.7, "speed": 1.0, "crowd": 1.0, "special": 1.0, "boss": 1.0, "regen": 1.0, "points": 1.0, "score": 0.75},
	{"hp": 1.0, "dmg": 1.0, "speed": 1.0, "crowd": 1.0, "special": 1.0, "boss": 1.0, "regen": 1.0, "points": 1.0, "score": 1.0},
	{"hp": 1.35, "dmg": 1.3, "speed": 1.0, "crowd": 1.0, "special": 1.0, "boss": 1.0, "regen": 1.0, "points": 1.0, "score": 1.5},
	{"hp": 1.7, "dmg": 1.55, "speed": 1.08, "crowd": 1.2, "special": 1.25, "boss": 1.1, "regen": 1.0, "points": 1.0, "score": 2.0},
	{"hp": 2.2, "dmg": 1.85, "speed": 1.15, "crowd": 1.4, "special": 1.5, "boss": 1.25, "regen": 0.8, "points": 1.0, "score": 2.75},
	{"hp": 2.8, "dmg": 2.2, "speed": 1.22, "crowd": 1.6, "special": 2.0, "boss": 1.4, "regen": 0.65, "points": 0.9, "score": 3.5},
	{"hp": 3.6, "dmg": 2.6, "speed": 1.3, "crowd": 1.8, "special": 2.5, "boss": 1.6, "regen": 0.5, "points": 0.8, "score": 4.5},
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
]
var difficulty: int = 1 # 0 easy, 1 normal, 2 hard (the host's choice in co-op)
var career_xp: int = 0
var _run_finished: bool = false


func diff(key: String) -> float:
	return float(DIFFICULTIES[clampi(difficulty, 0, DIFFICULTIES.size() - 1)].get(key, 1.0))


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
	if out.is_empty():
		out.append("The standard experience")
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
	return 500 + (250 if has_unlock("points_250") else 0) + (500 if has_unlock("points_500") else 0)


func run_score(outcome: String) -> int:
	var s := total_kills * 10 + headshots * 5 + bosses_slain * 500 + current_round * 250
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
	if not _run_finished:
		_run_finished = true
		clear_run_save()
		gained = score / 10
		career_xp += gained
		record_run()
		write_save()
	var after := career_level()
	var lines := ("CASUAL" if game_mode == "casual" else "INFINITE") + " MODE\nSCORE: %d   (%s)\n+%d XP   •   CAREER LEVEL %d   (%d / %d XP)" % [score, DIFFICULTY_NAMES[difficulty], gained, after, career_xp, xp_for_level(after + 1)]
	for u in META_UNLOCKS:
		if int(u["level"]) > before and int(u["level"]) <= after:
			lines += "\n★ UNLOCKED: %s" % u["text"]
	return lines


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
