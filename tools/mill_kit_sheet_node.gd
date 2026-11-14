extends Node
# Dev helper: lays out every mill kit piece on a stub wall and saves user://mill_kit_<n>.png
const PIECES := ["mk_win_brick", "mk_door_brick", "mk_pier_brick", "mk_coping_4m", "mk_plinth_4m", "mk_band_4m",
	"mk_gutter_4m", "mk_downpipe", "mk_clad_4m", "mk_column_steel", "mk_win_metal", "mk_door_metal",
	"mk_roof_corr", "mk_truss_12m", "mk_chimney", "mk_porch_6m", "mk_dock_6m"]
var _t := 0.0
var _shot := 0
var _cam: Camera3D
func _ready() -> void:
	GameState.retro_enabled = true
	var w := Node3D.new()
	add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.15)
	env.environment.ambient_light_color = Color(0.5, 0.52, 0.56)
	env.environment.ambient_light_energy = 0.6
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	w.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = MillKit.material("screed")
	w.add_child(floor_mi)
	for i in PIECES.size():
		var x := float(i) * 9.0
		var p: String = PIECES[i]
		# stub greybox wall behind wall-hugging pieces (openings cut where the piece frames one)
		if not p in ["mk_roof_corr", "mk_chimney", "mk_truss_12m"]:
			var brick: bool = not (p.contains("clad") or p.contains("metal") or p.contains("column"))
			var gap := 2.0 if p.contains("win") else (3.0 if p.contains("door") else 0.0)
			var gh := 2.4 if p.contains("win") else 3.2
			for side in ([-1.0, 1.0] if gap > 0.0 else [0.0]):
				var wl := (7.0 - gap) * 0.5 if gap > 0.0 else 7.0
				var b := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(wl, 4.2, 0.6)
				b.mesh = bm
				b.material_override = MillKit.material("brick" if brick else "corrugated")
				b.position = Vector3(x + side * (gap * 0.5 + wl * 0.5), 2.1, 0)
				w.add_child(b)
			if gap > 0.0:
				var top := MeshInstance3D.new()
				var tm := BoxMesh.new()
				tm.size = Vector3(gap, 4.2 - gh, 0.6)
				top.mesh = tm
				top.material_override = MillKit.material("brick" if brick else "corrugated")
				top.position = Vector3(x, gh + (4.2 - gh) * 0.5, 0)
				w.add_child(top)
		var k := MillKit.make(p)
		k.position = Vector3(x, 0.0 if p != "mk_roof_corr" else 2.0, 0)
		k.rotation_degrees.y = 180.0  # kit outside (+Y Blender = -Z Godot) turned to face the camera
		w.add_child(k)
	_cam = Camera3D.new()
	_cam.fov = 55
	w.add_child(_cam)

func _process(delta: float) -> void:
	_t += delta
	if _t < 1.5:
		return
	if _shot > 0:
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mill_kit_%d.png" % (_shot - 1))
	if _shot >= 6:
		print("KIT SHEET DONE")
		get_tree().quit()
		return
	var x0 := float(_shot) * 27.0 + 9.0
	_cam.position = Vector3(x0 - 4.0, 4.5, 15.0)
	_cam.look_at(Vector3(x0, 2.6, 0))
	_shot += 1
	_t = 0.0
