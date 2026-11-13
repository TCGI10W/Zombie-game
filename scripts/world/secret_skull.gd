extends StaticBody3D
# A glowing skull hidden somewhere on the map. Shoot all three to unlock the
# secret cache reward (handled by the arena).

var _found: bool = false
var _light: OmniLight3D
var _visual: Node3D
var _t: float = 0.0


func _ready() -> void:
	collision_layer = 1 | HitboxRig.BALLISTIC_WORLD_LAYER
	collision_mask = 0
	set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.2
	cs.shape = sp
	cs.position.y = 0.14
	add_child(cs)
	if ResourceLoader.exists("res://assets/models/prop_skull.glb"):
		_visual = (load("res://assets/models/prop_skull.glb") as PackedScene).instantiate()
		_visual.scale = Vector3.ONE * 1.3
		add_child(_visual)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.35, 1.0, 0.5)
	_light.light_energy = 0.8
	_light.omni_range = 2.0
	_light.position.y = 0.2
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	if not _found:
		_light.light_energy = 0.6 + sin(_t * 2.0) * 0.3


func on_shot(_player: Node) -> void:
	if _found:
		return
	_found = true
	collision_layer = 0
	GameState.play_sfx("skull_shatter", 0.0, 1.0)
	FX.gore_burst(global_position + Vector3(0, 0.15, 0), 4, 2.5)
	if _visual:
		var tw := _visual.create_tween()
		tw.set_parallel(true)
		tw.tween_property(_visual, "scale", Vector3.ONE * 1.9, 0.12)
		tw.chain().tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.15)
	var ltw := _light.create_tween()
	ltw.tween_property(_light, "light_energy", 4.0, 0.1)
	ltw.tween_property(_light, "light_energy", 0.0, 0.5)
	get_tree().call_group("arena", "skull_found")
