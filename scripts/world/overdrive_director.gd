class_name OverdriveDirector
extends Node3D

# Coordinates OVERDRIVE exclusive systems:
#   - 8 Wheel-of-Chaos round mutators (1-2 active per round)
#   - Champion Boss traits scaled by difficulty
#   - 3-Pedestal Colosseum Boss Drafts (+ Reroll Pylon) in Town Plaza
#   - Mid-round Overdrive Blitz Drop Pods

const BlitzZoneScript := preload("res://scripts/world/overdrive_blitz_zone.gd")
const RerollPylonScript := preload("res://scripts/world/draft_reroll_pylon.gd")

const MUTATORS := {
	"low_grav": {"name": "MOONWALK", "desc": "High jump, floaty air control & faster sprints"},
	"hyper_mag": {"name": "BOTTOMLESS", "desc": "+65% fire rate & +40% reload speed"},
	"pinata": {"name": "LOOT PINATA", "desc": "Kills detonate concussive AoE shockwaves"},
	"glass_cannon": {"name": "OVERCLOCKED", "desc": "+45% weapon dmg, +25% dmg taken"},
	"vamp_surge": {"name": "SIPHON", "desc": "Every kill restores +4 HP & +3 Overshield"},
	"turbo_cd": {"name": "HYPERCOOLDOWN", "desc": "Dash, grenades & skills recharge 2.2x faster"},
	"swift_horde": {"name": "BLITZ HORDE", "desc": "Zombies move +25% faster, +35% bonus points"},
	"headhunter": {"name": "HEADHUNTER", "desc": "+50% headshot dmg & bursts nearby foes"},
}

const MUTATIONS := [
	{"id": "vampiric", "name": "VAMPIRIC ROUNDS", "desc": "+5 HP on every kill"},
	{"id": "chain_master", "name": "STORM COILS", "desc": "+1 chain target & +35% shock dmg"},
	{"id": "quick_hands", "name": "SLEIGHT OF HAND", "desc": "+20% fire rate & +25% reload speed"},
	{"id": "titan_plated", "name": "TITAN PLATING", "desc": "+35 Max HP & +35 Overshield"},
	{"id": "crit_surge", "name": "HYPERCRIT", "desc": "+30% headshot dmg & +15% weapon dmg"},
	{"id": "magnet_core", "name": "GREED ENGINE", "desc": "+25% points earned & +1.0s combo window"},
	{"id": "explosive_rounds", "name": "EXPLOSIVE PAYLOAD", "desc": "Every 4th bullet hit detonates a fiery blast"},
	{"id": "shock_slide", "name": "VOLT SLIDE", "desc": "Slides unleash a 3.8m electric shockwave"},
	{"id": "turret_overclock", "name": "GRID OVERCLOCK", "desc": "Defense Pads fire +35% faster & hit +35% harder"},
	{"id": "phoenix_core", "name": "PHOENIX CORE", "desc": "+50 Max HP & emergency stun nova below 40% HP"},
]

const BOSS_TRAITS := [
	{"id": "SWIFT", "label": "SWIFT"},
	{"id": "ARMORED", "label": "ARMORED"},
	{"id": "ENRAGED", "label": "ENRAGED"},
	{"id": "COLOSSAL", "label": "COLOSSAL"},
]

var active_mutators: Array[String] = []
var active_draft_pedestals: Array[DraftPedestal] = []
var active_reroll_pylon: Node3D = null
var active_blitz_zone: Node3D = null
var draft_count: int = 0
var draft_rerolls: int = 0
var last_draft_center: Vector3 = Vector3(0.0, 0.0, 5.5)


func _ready() -> void:
	add_to_group("overdrive")


func has_mutator(id: String) -> bool:
	return GameState.is_overdrive() and active_mutators.has(id)


func roll_round_mutators(round_num: int) -> Array[String]:
	active_mutators.clear()
	if not GameState.is_overdrive():
		return active_mutators
	var want: int = maxi(1, int(GameState.diff("mutators")))
	var keys: Array = MUTATORS.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameState.run_id) * 131 + round_num * 41
	var pool: Array = keys.duplicate()
	while active_mutators.size() < want and not pool.is_empty():
		var idx: int = rng.randi_range(0, pool.size() - 1)
		active_mutators.append(String(pool[idx]))
		pool.remove_at(idx)
	return active_mutators


func mutator_summary_lines() -> Array[String]:
	var out: Array[String] = []
	for id in active_mutators:
		var m: Dictionary = MUTATORS.get(id, {})
		if not m.is_empty():
			out.append("%s — %s" % [String(m["name"]), String(m["desc"])])
	return out


func mutator_short_label() -> String:
	if active_mutators.is_empty():
		return "NONE"
	var names: Array[String] = []
	for id in active_mutators:
		var m: Dictionary = MUTATORS.get(id, {})
		if not m.is_empty():
			names.append(String(m["name"]))
	return "  +  ".join(names)


func decorate_boss(boss: ZombieEnemy, round_num: int) -> Array[String]:
	var chosen: Array[String] = []
	if boss == null or not GameState.is_overdrive():
		return chosen
	var count: int = clampi(int(GameState.diff("boss_traits")), 0, BOSS_TRAITS.size())
	if count <= 0:
		return chosen
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameState.run_id) * 197 + round_num * 53 + int(boss.get_instance_id() % 97)
	var pool := BOSS_TRAITS.duplicate()
	for _i in range(count):
		if pool.is_empty():
			break
		var idx: int = rng.randi_range(0, pool.size() - 1)
		var tr: Dictionary = pool[idx]
		pool.remove_at(idx)
		var tid: String = String(tr["id"])
		chosen.append(tid)
		match tid:
			"SWIFT":
				boss.base_speed *= 1.28
			"ARMORED":
				boss.endurance *= 1.28
			"ENRAGED":
				boss.base_damage *= 1.24
				boss.point_reward += 250
			"COLOSSAL":
				boss.max_hp *= 1.30
				boss.hp = boss.max_hp
				boss.scale *= 1.12
	if not chosen.is_empty():
		boss.display_name = "[%s] %s" % ["/".join(chosen), boss.display_name]
	return chosen


func clear_draft() -> void:
	for ped in active_draft_pedestals:
		if is_instance_valid(ped):
			ped.queue_free()
	active_draft_pedestals.clear()
	if active_reroll_pylon != null and is_instance_valid(active_reroll_pylon):
		active_reroll_pylon.queue_free()
	active_reroll_pylon = null


func get_reroll_cost() -> int:
	return 500 * (draft_rerolls + 1)


func reroll_boss_draft(player: Node3D) -> void:
	var cost: int = get_reroll_cost()
	if not GameState.spend_points(cost):
		GameState.play_sfx("dry_fire", -2.0, 0.7)
		if player != null and is_instance_valid(player) and player.has_signal("status_banner_requested"):
			player.status_banner_requested.emit("NEED %d PTS TO REROLL BOSS DRAFT" % cost, Color(1.0, 0.35, 0.30))
		return
	draft_rerolls += 1
	GameState.play_sfx("buy_ching", -2.0, 1.22)
	spawn_boss_draft(last_draft_center, player, true)


func spawn_boss_draft(center: Vector3 = Vector3(0.0, 0.0, 5.5), player: Node3D = null, is_reroll: bool = false) -> void:
	if not GameState.is_overdrive():
		return
	clear_draft()
	if not is_reroll:
		draft_count += 1
		draft_rerolls = 0
	last_draft_center = center
	var host := get_parent()
	if host == null:
		return

	# Offer 1: Modded (or Pre-Forged MK-II on draft 3+) Weapon
	var w_candidates: Array[String] = []
	for wid in GameState.WEAPONS.keys():
		if String(wid) != "pistol":
			w_candidates.append(String(wid))
	w_candidates.shuffle()
	var picked_w: String = w_candidates[0] if not w_candidates.is_empty() else "rifle"
	var w_data: Dictionary = GameState.WEAPONS.get(picked_w, {})
	var mods: Array[String] = GameState.roll_crate_attachments(picked_w)
	if draft_count >= 2 and mods.size() < 2:
		var extra_pool: Array[String] = GameState.roll_crate_attachments(picked_w)
		for em in extra_pool:
			if not mods.has(em):
				mods.append(em)
				if mods.size() >= 2:
					break
	var is_forged: bool = draft_count >= 3
	var offer_weapon := {"kind": "weapon", "weapon_id": picked_w, "mods": mods, "forged": is_forged}
	var w_title: String = String(w_data.get("name", picked_w)).to_upper() + (" MK-II" if is_forged else "")
	var w_detail: String = ("PRE-FORGED MK-II • %d MODS" if is_forged else "MODDED WEAPON (%d MODS)") % mods.size()

	# Offer 2: Stat Surge (scales with draft count)
	var s_pool: Array = GameState.STATS.duplicate()
	s_pool.shuffle()
	var s_info: Dictionary = s_pool[0] if not s_pool.is_empty() else {"id": "strength", "name": "STRENGTH"}
	var s_id: String = String(s_info.get("id", "strength"))
	var s_name: String = String(s_info.get("name", s_id))
	var surge_lv: int = 2 + mini(2, (draft_count - 1) / 2)
	var surge_pts: int = 600 + 200 * (draft_count - 1)
	var offer_perk := {"kind": "perk", "stat_id": s_id, "stat_name": s_name, "levels": surge_lv, "bonus_pts": surge_pts}

	# Offer 3: Stackable Operator Mutation
	var mut_pool := MUTATIONS.duplicate()
	mut_pool.shuffle()
	var mut: Dictionary = mut_pool[0]
	var offer_mut := {"kind": "mutation", "mut_id": String(mut["id"]), "name": String(mut["name"]), "desc": String(mut["desc"])}

	var specs := [
		{
			"offset": Vector3(-3.0, 0.0, 0.0),
			"cat": "weapon",
			"title": w_title,
			"detail": w_detail,
			"data": offer_weapon,
			"col": Color(0.35, 0.95, 1.0),
		},
		{
			"offset": Vector3(0.0, 0.0, 0.0),
			"cat": "perk",
			"title": "%s SURGE +%d" % [s_name.to_upper(), surge_lv],
			"detail": "+%d STAT LEVELS & +%d PTS" % [surge_lv, surge_pts],
			"data": offer_perk,
			"col": Color(1.0, 0.85, 0.22),
		},
		{
			"offset": Vector3(3.0, 0.0, 0.0),
			"cat": "mutation",
			"title": String(mut["name"]),
			"detail": String(mut["desc"]),
			"data": offer_mut,
			"col": Color(1.0, 0.42, 0.88),
		},
	]

	for i in range(specs.size()):
		var spec: Dictionary = specs[i]
		var ped := DraftPedestal.new()
		host.add_child(ped)
		ped.global_position = center + (spec["offset"] as Vector3)
		ped.configure(i, String(spec["cat"]), String(spec["title"]), String(spec["detail"]), spec["data"], spec["col"], self)
		active_draft_pedestals.append(ped)

	var pylon := RerollPylonScript.new()
	pylon.director = self
	host.add_child(pylon)
	pylon.global_position = center + Vector3(-4.3, 0.0, -0.8)
	if pylon.has_method("refresh_label"):
		pylon.refresh_label()
	active_reroll_pylon = pylon

	GameState.play_sfx("crate_open", -2.0, 1.25)
	if player != null and is_instance_valid(player) and player.has_signal("status_banner_requested"):
		var bmsg: String = "DRAFT REROLLED — PICK 1 OF 3 PEDESTALS!" if is_reroll else "BOSS DRAFT READY — PICK 1 OF 3 PEDESTALS IN TOWN PLAZA!"
		player.status_banner_requested.emit(bmsg, Color(1.0, 0.88, 0.28))


func claim_pedestal(player: Node3D, ped: DraftPedestal) -> void:
	if player == null or not is_instance_valid(player) or ped == null or not is_instance_valid(ped):
		return
	var data: Dictionary = ped.offer
	var kind: String = String(data.get("kind", ""))
	var banner: String = ""
	match kind:
		"weapon":
			var wid: String = String(data.get("weapon_id", "rifle"))
			var mods: Array = data.get("mods", [])
			var forged: bool = bool(data.get("forged", false))
			if player.has_method("grant_or_refill_weapon"):
				player.grant_or_refill_weapon(wid, mods)
			if forged and "upgraded" in player and player.has_method("get_weapon_cfg"):
				player.upgraded[wid] = true
				var cfg: Dictionary = player.get_weapon_cfg(wid)
				player.mag_ammo[wid] = cfg["mag_size"]
				player.reserve_ammo[wid] = cfg["reserve_max"]
				if player.has_method("_equip_weapon_model"):
					player._equip_weapon_model(wid)
				if player.has_method("_emit_ammo"):
					player._emit_ammo()
			banner = "DRAFT CLAIMED: %s%s" % [String(GameState.WEAPONS.get(wid, {}).get("name", wid)).to_upper(), " MK-II" if forged else ""]
		"perk":
			var sid: String = String(data.get("stat_id", "strength"))
			var sname: String = String(data.get("stat_name", sid))
			var lv: int = int(data.get("levels", 2))
			var bonus_pts: int = int(data.get("bonus_pts", 600))
			if player.has_method("grant_stat_levels"):
				player.grant_stat_levels(sid, lv)
			GameState.points += bonus_pts
			GameState.points_changed.emit(GameState.points, bonus_pts)
			banner = "DRAFT CLAIMED: +%d %s & +%d PTS" % [lv, sname.to_upper(), bonus_pts]
		"mutation":
			var mid: String = String(data.get("mut_id", ""))
			if "od_mutations" in player:
				var muts: Dictionary = player.od_mutations
				muts[mid] = int(muts.get(mid, 0)) + 1
				if player.has_method("_apply_stats"):
					player._apply_stats()
				if mid == "titan_plated":
					player.hp = minf(float(player.max_hp), float(player.hp) + 35.0)
					player.overshield = minf(100.0, float(player.overshield) + 35.0)
					player.hp_changed.emit(player.hp, player.max_hp, player.overshield)
				elif mid == "phoenix_core":
					player.hp = minf(float(player.max_hp), float(player.hp) + 50.0)
					player.overshield = minf(100.0, float(player.overshield) + 35.0)
					player.hp_changed.emit(player.hp, player.max_hp, player.overshield)
			banner = "MUTATION ACQUIRED: %s" % String(data.get("name", mid))

	GameState.play_sfx("level_up", -1.0, 1.12)
	GameState.play_sfx("buy_ching", -3.0, 1.25)
	if player.has_signal("status_banner_requested") and banner != "":
		player.status_banner_requested.emit(banner, Color(1.0, 0.88, 0.25))
	clear_draft()


func clear_blitz_zone() -> void:
	if active_blitz_zone != null and is_instance_valid(active_blitz_zone):
		active_blitz_zone.queue_free()
	active_blitz_zone = null


func spawn_blitz_zone(arena: Node3D, player: Node3D) -> void:
	if not GameState.is_overdrive() or (active_blitz_zone != null and is_instance_valid(active_blitz_zone)):
		return
	var host := get_parent()
	if host == null:
		return
	var candidates: Array[Vector3] = [
		Vector3(0.0, 0.0, 6.2),
		Vector3(-11.5, 0.0, 2.5),
		Vector3(11.5, 0.0, -2.5),
		Vector3(-5.5, 0.0, -9.5),
		Vector3(8.5, 0.0, 8.5),
	]
	if arena != null and "boss_points" in arena and arena.has_method("is_zone_open"):
		for zid in arena.boss_points:
			if zid == "plaza" or not arena.is_zone_open(String(zid)):
				continue
			for bp in arena.boss_points[zid]:
				var v := bp as Vector3
				candidates.append(Vector3(v.x, 0.0, v.z))
	var chosen: Vector3 = candidates[0]
	var ppos: Vector3 = player.global_position if (player != null and is_instance_valid(player)) else Vector3.ZERO
	candidates.shuffle()
	for c in candidates:
		if c.distance_to(ppos) >= 5.0:
			chosen = c
			break
	if arena != null and arena.has_method("find_clear_ground_point"):
		chosen = arena.find_clear_ground_point(chosen, "", 0.55)
	var bz := BlitzZoneScript.new()
	bz.director = self
	host.add_child(bz)
	bz.global_position = chosen
	active_blitz_zone = bz
	GameState.play_sfx("crate_open", -1.5, 0.92)
	if player != null and is_instance_valid(player) and player.has_signal("status_banner_requested"):
		player.status_banner_requested.emit("OVERDRIVE BLITZ POD LANDED — HOLD THE GOLD RING!", Color(1.0, 0.86, 0.24))


func notify_enemy_killed(enemy_pos: Vector3, killer: Node3D) -> void:
	if active_blitz_zone != null and is_instance_valid(active_blitz_zone) and active_blitz_zone.has_method("on_enemy_killed"):
		active_blitz_zone.on_enemy_killed(enemy_pos, killer)
