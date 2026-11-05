extends Area3D
# Boss loot: a glowing relic in its rarity colour (white common, blue rare,
# purple epic, gold legendary) under a column of light. `kind` encodes the
# reward: "relic:<rarity>:stat:<stat_id>:<levels>" or
# "relic:<rarity>:skill:<skill_id>:<cooldown % of normal>".
# Walk into it to take it; it fades after two minutes.

signal collected(kind: String)

const RARITY_NAMES := ["COMMON", "RARE", "EPIC", "LEGENDARY"]
const RARITY_COLORS := [Color(0.92, 0.94, 1.0), Color(0.25, 0.55, 1.0), Color(0.72, 0.3, 1.0), Color(1.0, 0.74, 0.18)]
const LIFETIME := 120.0

var kind: String = ""
var _taken: bool = false
var _t: float = 0.0
var _gem: MeshInstance3D
var _light: OmniLight3D


static func rarity_of(k: String) -> int:
	return clampi(int(k.get_slice(":", 1)), 0, 3)


static func describe(k: String) -> String:
	var parts := k.split(":")
	if parts.size() < 5:
		return "RELIC"
	if parts[2] == "stat":
		for s in GameState.STATS:
			if s["id"] == parts[3]:
				return "+%s %s" % [parts[4], s["name"]]
		return "+%s %s" % [parts[4], parts[3].to_upper()]
	var skill: Dictionary = PlayerController.BORROWED_SKILLS.get(parts[3], {})
	var txt := "SKILL: %s" % String(skill.get("name", parts[3].to_upper()))
	if int(parts[4]) < 100:
		txt += "  (FAST RECHARGE)"
	return txt


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	cs.shape = sph
	cs.position.y = 0.8
	add_child(cs)

	var r := rarity_of(kind)
	var col: Color = RARITY_COLORS[r]

	_gem = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.32, 0.42, 0.32)
	_gem.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = col
	gm.metallic = 0.6
	gm.roughness = 0.15
	gm.emission_enabled = true
	gm.emission = col
	gm.emission_energy_multiplier = 2.5 + float(r)
	_gem.material_override = gm
	_gem.position.y = 1.0
	add_child(_gem)
	var bottom := MeshInstance3D.new()
	var pm2 := PrismMesh.new()
	pm2.size = Vector3(0.32, 0.28, 0.32)
	bottom.mesh = pm2
	bottom.material_override = gm
	bottom.rotation.x = PI
	bottom.position.y = -0.35
	_gem.add_child(bottom)

	# Loot beam: taller and brighter for better rarities
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.015 + 0.006 * float(r)
	cm.bottom_radius = 0.05 + 0.012 * float(r)
	cm.height = 5.0 + 2.5 * float(r)
	beam.mesh = cm
	beam.material_override = MaterialLib.get_emissive(col, 0.9 + 0.4 * float(r), 0.08)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = cm.height * 0.5
	add_child(beam)

	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 1.5 + 0.6 * float(r)
	_light.omni_range = 4.0 + float(r)
	_light.position.y = 1.0
	add_child(_light)

	var lbl := Label3D.new()
	lbl.text = "%s RELIC\n%s" % [RARITY_NAMES[r], describe(kind)]
	lbl.font_size = 30
	lbl.outline_size = 10
	lbl.pixel_size = 0.004
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = col
	lbl.position.y = 1.75
	lbl.no_depth_test = true
	lbl.render_priority = 2
	add_child(lbl)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	_gem.rotation.y += delta * 1.6
	_gem.position.y = 1.0 + sin(_t * 2.2) * 0.12
	if _t > LIFETIME - 5.0:
		visible = fmod(_t, 0.3) < 0.18
	if _t > LIFETIME:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player") or body.get("is_dead"):
		return
	_taken = true
	collected.emit(kind)
	queue_free()
