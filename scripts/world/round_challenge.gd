extends Node
# ROUND CHALLENGE: every round each player gets one optional goal (headshots,
# knife kills, a kill streak...). Finishing it pays points; every 4th one in a
# run also gives a free stat level. Runs on each player's own machine, so in
# co-op everyone has their own challenge.

signal changed()

const POOL := [
	{"id": "headshots", "name": "HEADHUNTER", "text": "%d HEADSHOT KILLS", "base": 5.0, "grow": 0.5, "cap": 16, "min_round": 1},
	{"id": "melee", "name": "KNIFE WORK", "text": "%d MELEE KILLS", "base": 2.0, "grow": 0.12, "cap": 5, "min_round": 1},
	{"id": "explosive", "name": "DEMOLITION", "text": "%d EXPLOSIVE KILLS", "base": 3.0, "grow": 0.2, "cap": 8, "min_round": 2},
	{"id": "streak", "name": "RAMPAGE", "text": "A %d-KILL STREAK", "base": 4.0, "grow": 0.15, "cap": 7, "min_round": 2},
	{"id": "untouched", "name": "UNTOUCHABLE", "text": "%d KILLS IN A ROW WITHOUT BEING HIT", "base": 8.0, "grow": 0.5, "cap": 20, "min_round": 1},
	{"id": "close", "name": "POINT BLANK", "text": "%d KILLS FROM UNDER 4 METRES", "base": 5.0, "grow": 0.35, "cap": 14, "min_round": 1},
	{"id": "far", "name": "MARKSMAN", "text": "%d KILLS FROM OVER 15 METRES", "base": 4.0, "grow": 0.3, "cap": 12, "min_round": 3},
	{"id": "hunter", "name": "HEAD OF THE SNAKE", "text": "KILL %d STALKERS OR COMMANDERS", "base": 3.0, "grow": 0.25, "cap": 9, "min_round": 4},
	{"id": "acrobat", "name": "ACROBAT", "text": "%d KILLS WHILE JUMPING OR SLIDING", "base": 3.0, "grow": 0.2, "cap": 8, "min_round": 2},
]
const DONE_COLOR := Color(0.45, 1.0, 0.55)
const OPEN_COLOR := Color(0.95, 0.82, 0.45)

var player: Node
var current: Dictionary = {}
var target: int = 0
var progress: int = 0
var reward: int = 0
var done: bool = false
var _last_id: String = ""


func setup(p_player: Node, wave_mgr: Node) -> void:
	player = p_player
	wave_mgr.round_started.connect(_on_round)
	player.enemy_killed.connect(_on_kill)
	player.damaged.connect(_on_hurt)
	player.kill_streak.connect(_on_streak)


func _on_round(round_num: int, _boss_cfg: Dictionary) -> void:
	var options: Array = []
	for c in POOL:
		if round_num >= int(c["min_round"]) and c["id"] != _last_id:
			options.append(c)
	current = options[randi() % options.size()]
	_last_id = current["id"]
	target = mini(int(current["cap"]), int(round(float(current["base"]) + float(current["grow"]) * float(round_num))))
	progress = 0
	done = false
	reward = 300 + 60 * round_num
	changed.emit()


func _on_kill(z: Node, headshot: bool) -> void:
	if done or current.is_empty() or not is_instance_valid(z):
		return
	var dist: float = z.global_position.distance_to(player.global_position)
	var kind: String = z.last_damage_kind
	var hit := false
	match String(current["id"]):
		"headshots":
			hit = headshot
		"melee":
			hit = kind == "melee"
		"explosive":
			hit = kind == "explosive"
		"untouched":
			hit = true
		"close":
			hit = dist < 4.0
		"far":
			hit = dist > 15.0
		"hunter":
			hit = int(z.tier) >= 2
		"acrobat":
			hit = player.is_sliding or not player.is_on_floor()
	if hit:
		_advance(progress + 1)


func _on_hurt(_from: Vector3) -> void:
	if not done and not current.is_empty() and current["id"] == "untouched" and progress > 0:
		progress = 0
		changed.emit()


func _on_streak(count: int) -> void:
	if not done and not current.is_empty() and current["id"] == "streak":
		_advance(maxi(progress, count))


func _advance(value: int) -> void:
	progress = mini(target, value)
	if progress >= target:
		done = true
		GameState.challenges_done += 1
		GameState.add_points(reward)
		GameState.play_sfx("level_up", -2.0, 1.15)
		var extra := ""
		if GameState.challenges_done % 4 == 0 and player.has_method("grant_stat_levels"):
			var stat: Dictionary = GameState.STATS[randi() % GameState.STATS.size()]
			if int(player.grant_stat_levels(stat["id"], 1)) > 0:
				extra = "  •  BONUS: +1 %s" % stat["name"]
		player.status_banner_requested.emit("CHALLENGE COMPLETE: %s  +%d%s" % [current["name"], reward, extra], DONE_COLOR)
	changed.emit()


func hud_text() -> String:
	if current.is_empty():
		return ""
	if done:
		return "✔ %s — COMPLETE" % current["name"]
	return "◆ %s: %s  [%d/%d]  +%d" % [current["name"], String(current["text"]) % target, progress, target, reward]


func hud_color() -> Color:
	return DONE_COLOR if done else OPEN_COLOR
