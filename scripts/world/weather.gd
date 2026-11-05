class_name Weather
extends Node3D
# Storm effects: lightning strikes (bolt, flash, thunder, scorch mark), sky
# flashes with rolling thunder, and the sickly fog that rolls in during hound
# raids. Distant thunder rumbles now and then even on quiet nights.

var env: Environment
var sky_flash: DirectionalLight3D
var storm: bool = false
var _flash: float = 0.0
var _next_ambient: float = 25.0
var _base_fog_density: float = 0.02
var _base_fog_albedo: Color = Color(0.14, 0.17, 0.23)
var _base_fog_emission: Color = Color(0.02, 0.025, 0.04)
var _base_ambient: float = 1.15
var _bolt_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _sky_mat: ProceduralSkyMaterial
var _cover_base: Color = Color(1, 1, 1, 1)


func setup(p_env: Environment) -> void:
	env = p_env
	if env:
		_base_fog_density = env.volumetric_fog_density
		_base_fog_albedo = env.volumetric_fog_albedo
		_base_fog_emission = env.volumetric_fog_emission
		_base_ambient = env.ambient_light_energy
		if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
			_sky_mat = env.sky.sky_material as ProceduralSkyMaterial
			_cover_base = _sky_mat.sky_cover_modulate
	sky_flash = DirectionalLight3D.new()
	sky_flash.light_color = Color(0.72, 0.8, 1.0)
	sky_flash.light_energy = 0.0
	sky_flash.shadow_enabled = false
	sky_flash.rotation_degrees = Vector3(-62.0, 150.0, 0.0)
	add_child(sky_flash)
	_bolt_mat = MaterialLib.get_emissive(Color(0.85, 0.9, 1.0), 12.0)
	_glow_mat = MaterialLib.get_emissive(Color(0.45, 0.6, 1.0), 2.5, 0.22)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		# Double-flicker like a real strike
		var f := _flash * (0.6 + 0.4 * absf(sin(_flash * 40.0)))
		sky_flash.light_energy = f * 2.6
		if _sky_mat:
			# The clouds light up from inside
			var k := 1.0 + f * 7.0
			_sky_mat.sky_cover_modulate = Color(_cover_base.r * k, _cover_base.g * k, _cover_base.b * k * 1.1, _cover_base.a)
	else:
		sky_flash.light_energy = 0.0
		if _sky_mat and _sky_mat.sky_cover_modulate != _cover_base:
			_sky_mat.sky_cover_modulate = _cover_base
	_next_ambient -= delta
	if _next_ambient <= 0.0:
		if storm:
			_next_ambient = randf_range(6.0, 14.0)
			flash_sky(randf_range(0.5, 1.0))
		else:
			_next_ambient = randf_range(40.0, 90.0)
			flash_sky(randf_range(0.15, 0.35))


# A flash on the horizon followed (after the light-to-sound delay) by thunder.
func flash_sky(strength: float) -> void:
	_flash = maxf(_flash, strength)
	var delay := randf_range(0.6, 2.4)
	get_tree().create_timer(delay).timeout.connect(func():
		GameState.play_sfx("thunder_far", lerpf(-12.0, -2.0, strength), randf_range(0.85, 1.1))
	)


# Lightning hits the ground at `pos`: used when hounds arrive.
func strike(pos: Vector3) -> void:
	_flash = 1.0
	var top := pos + Vector3(randf_range(-3.0, 3.0), 34.0, randf_range(-3.0, 3.0))
	var bolt := Node3D.new()
	get_tree().current_scene.add_child(bolt)
	var prev := top
	var segs := 16
	for i in range(1, segs + 1):
		var f := float(i) / float(segs)
		var nxt := top.lerp(pos, f)
		if i < segs:
			nxt += Vector3(randf_range(-1.4, 1.4), randf_range(-0.6, 0.6), randf_range(-1.4, 1.4)) * (1.0 - f * 0.75)
		_bolt_segment(bolt, prev, nxt, lerpf(0.05, 0.03, f))
		_bolt_segment(bolt, prev, nxt, lerpf(0.22, 0.12, f), true)
		if i > 2 and i < segs - 1 and randf() < 0.45:
			# Forked branch
			var branch_end := nxt + Vector3(randf_range(-3.0, 3.0), randf_range(-5.0, -2.0), randf_range(-3.0, 3.0))
			_bolt_segment(bolt, nxt, branch_end, 0.03)
		prev = nxt
	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.85, 1.0)
	light.light_energy = 14.0
	light.omni_range = 16.0
	bolt.add_child(light)
	light.global_position = pos + Vector3(0, 2.0, 0)
	var tw := bolt.create_tween()
	tw.tween_interval(0.07)
	tw.tween_callback(func(): bolt.visible = false)
	tw.tween_interval(0.05)
	tw.tween_callback(func(): bolt.visible = true)
	tw.tween_property(light, "light_energy", 0.0, 0.3)
	tw.tween_callback(bolt.queue_free)
	FX.scorch(pos + Vector3(0, 0.03, 0), 2.4)
	FX.impact(pos + Vector3(0, 0.05, 0), Vector3.UP)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = GameState.get_sfx_stream("lightning_strike")
	snd.bus = &"SFX"
	snd.unit_size = 14.0
	snd.max_distance = 120.0
	snd.volume_db = 2.0
	get_tree().current_scene.add_child(snd)
	snd.global_position = pos
	snd.play()
	snd.finished.connect(snd.queue_free)
	var player := get_tree().get_first_node_in_group("player")
	if player and player.global_position.distance_to(pos) < 14.0 and player.has_method("add_camera_shake"):
		player.add_camera_shake(0.35)


func _bolt_segment(parent: Node3D, a: Vector3, b: Vector3, radius: float, glow: bool = false) -> void:
	var d := a.distance_to(b)
	if d < 0.05:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = d
	cm.radial_segments = 5
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _glow_mat if glow else _bolt_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)


# Hound raids: thick, sickly fog, darker ambient, more frequent lightning.
func set_storm(on: bool) -> void:
	storm = on
	_next_ambient = 3.0 if on else randf_range(40.0, 90.0)
	if env == null:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(env, "volumetric_fog_density", _base_fog_density * (2.6 if on else 1.0), 4.0)
	tw.tween_property(env, "volumetric_fog_albedo", Color(0.3, 0.22, 0.16) if on else _base_fog_albedo, 4.0)
	tw.tween_property(env, "volumetric_fog_emission", Color(0.06, 0.025, 0.012) if on else _base_fog_emission, 4.0)
	tw.tween_property(env, "ambient_light_energy", _base_ambient * (0.8 if on else 1.0), 4.0)
