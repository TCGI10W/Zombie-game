extends Node3D
# Living town: a weather cycle (clear -> drizzle -> rain -> downpour with
# lightning) where rain stops on roofs, distance haze and ground fog, burning
# car wrecks, chandeliers and lamps that sway in the wind, and ambient sound
# for each area (wind, a church drone, hospital hum, rain on the warehouse
# roof) with random distant events (crows, bells, horns, creaks).

const STATES := [0.0, 0.3, 0.65, 1.0] # rain intensity per weather state
const INDOOR := ["church", "warehouse", "hospital"]

var arena: Node
var weather: Node
var intensity: float = 0.0
var _target: float = 0.0
var _state: int = 0
var _state_t: float = 30.0
var _event_t: float = 8.0
var _bolt_t: float = 10.0
var _time: float = 0.0
var _indoor: float = 0.0 # 0 outside .. 1 inside (smoothed)
var _rng := RandomNumberGenerator.new()

var _rain: GPUParticles3D
var _rain_out: AudioStreamPlayer
var _rain_in: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _roof: AudioStreamPlayer3D
var _swingers: Array[Dictionary] = []
var _env: Environment


func setup(p_arena: Node, p_weather: Node) -> void:
	arena = p_arena
	weather = p_weather
	_env = arena.world_env
	_rng.seed = GameState.run_id if GameState.run_id != 0 else randi()
	_state = _rng.randi_range(0, 1)
	_target = STATES[_state]
	intensity = _target
	_state_t = _rng.randf_range(50.0, 110.0)
	_build_rain()
	_build_fog()
	_build_fires()
	_build_swinging_lights()
	_build_ambience()


# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_3d()
	# Weather cycle: drift one step up or down every minute or two
	_state_t -= delta
	if _state_t <= 0.0:
		_state = clampi(_state + (1 if _rng.randf() < (0.62 if _state < 2 else 0.35) else -1), 0, STATES.size() - 1)
		_target = STATES[_state]
		_state_t = _rng.randf_range(60.0, 150.0)
	intensity = move_toward(intensity, _target, delta * 0.04)

	var inside := 0.0
	if cam and arena and arena.has_method("zone_at"):
		inside = 1.0 if String(arena.zone_at(cam.global_position)) in INDOOR else 0.0
		_rain.global_position = cam.global_position + Vector3(0, 13.0, 0) + _wind_dir() * 3.0
	_indoor = move_toward(_indoor, inside, delta * 2.5)
	_rain.amount_ratio = intensity
	_rain.emitting = intensity > 0.02

	# Rain and wind sound: muffled indoors
	_set_vol(_rain_out, intensity * (1.0 - _indoor) * 0.9)
	_set_vol(_rain_in, intensity * _indoor * 0.8)
	_set_vol(_wind, (0.25 + 0.55 * intensity) * (1.0 - 0.7 * _indoor))
	if _roof:
		_roof.volume_db = linear_to_db(maxf(0.0001, intensity * 0.9))

	# Haze thickens with the rain
	if _env:
		_env.fog_density = 0.0035 + 0.011 * intensity + _event_fog
	if _moon and _moon.visible and cam:
		_moon.global_position = cam.global_position + Vector3(60.0, 50.0, -122.0)

	# Storm lightning in heavy rain
	if intensity > 0.7 and weather:
		_bolt_t -= delta
		if _bolt_t <= 0.0:
			_bolt_t = _rng.randf_range(7.0, 16.0)
			weather.flash_sky(_rng.randf_range(0.5, 1.0))

	# Swinging lamps: wind pushes them harder; unpowered indoor bulbs stay dark
	var amp := deg_to_rad(2.5 + 8.0 * intensity)
	var pwr_on: bool = arena != null and arena.get("power_on") == true
	for s in _swingers:
		var piv: Node3D = s["pivot"]
		var ph: float = s["phase"]
		piv.rotation.x = amp * sin(_time * 1.35 + ph)
		piv.rotation.z = amp * 0.6 * sin(_time * 1.04 + ph * 1.7)
		var l: OmniLight3D = s["light"]
		var b: MeshInstance3D = s["bulb"]
		if not pwr_on:
			l.light_energy = 0.0
			b.material_override = MaterialLib.get_emissive(Color(0.25, 0.08, 0.06), 0.15)
		else:
			l.light_energy = 1.15
			b.material_override = MaterialLib.get_emissive(s["color"], 2.4)

	_event_t -= delta
	if _event_t <= 0.0 and cam:
		_event_t = _rng.randf_range(7.0, 16.0)
		_ambient_event(cam.global_position)


func _wind_dir() -> Vector3:
	return Vector3(0.55, 0, 0.3)


func _set_vol(p: AudioStreamPlayer, lin: float) -> void:
	if p:
		p.volume_db = linear_to_db(maxf(0.0001, lin))


# ---------------------------------------------------------------------------
# RAIN: GPU streaks around the camera; a heightfield from above hides drops
# that hit a roof, so it never rains indoors.
# ---------------------------------------------------------------------------
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 3500 if GameState.graphics_quality == 0 else 7000
	_rain.lifetime = 1.1
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 45, 60))
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 0.5, 24)
	pm.direction = Vector3(-0.12, -1, -0.07)
	pm.spread = 2.0
	pm.initial_velocity_min = 19.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0, -6, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.022, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.72, 0.78, 0.88, 0.32)
	q.material = m
	_rain.draw_pass_1 = q
	add_child(_rain)
	var hf := GPUParticlesCollisionHeightField3D.new()
	hf.size = Vector3(64, 40, 64)
	hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	hf.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	hf.follow_camera_enabled = true
	add_child(hf)


# ---------------------------------------------------------------------------
# FOG: distance haze for the open map, and thick ground fog in low spots
# ---------------------------------------------------------------------------
func _build_fog() -> void:
	if _env:
		_env.fog_enabled = true
		_env.fog_light_color = Color(0.07, 0.085, 0.12)
		_env.fog_light_energy = 1.0
		_env.fog_sky_affect = 0.35
		_env.fog_density = 0.0035
	for f in [[Vector3(38, 0.4, -40), Vector3(34, 3.0, 30), 0.32, Color(0.5, 0.58, 0.56)],
			[Vector3(-20, 0.3, 25), Vector3(54, 2.4, 18), 0.3, Color(0.6, 0.62, 0.7)],
			[Vector3(0, 0.2, 0), Vector3(42, 1.6, 32), 0.14, Color(0.6, 0.64, 0.72)]]:
		var v := FogVolume.new()
		v.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		v.size = f[1]
		v.position = f[0]
		var fm := FogMaterial.new()
		fm.density = f[2]
		fm.albedo = f[3]
		fm.height_falloff = 0.8
		fm.edge_fade = 0.7
		v.material = fm
		add_child(v)


# ---------------------------------------------------------------------------
# BURNING WRECKS
# ---------------------------------------------------------------------------
func _build_fires() -> void:
	for f in [[Vector3(-30, 0.7, 9), 1.0], [Vector3(58, 0.7, -12), 1.1], [Vector3(-38, 0.7, 21.5), 0.8], [Vector3(-12, 0.8, -4), 0.35]]:
		_fire(f[0], f[1])


func _soft_tex() -> Texture2D:
	return load("res://assets/textures/soft_particle.png") if ResourceLoader.exists("res://assets/textures/soft_particle.png") else null


func _fire(pos: Vector3, size: float) -> void:
	var flames := GPUParticles3D.new()
	flames.amount = int(70 * size) + 10
	flames.lifetime = 0.9
	flames.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.2, 1.6) * size
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0.4, 2.5, 0.2)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	grad.set_color(1, Color(0.6, 0.08, 0.02, 0.0))
	grad.add_point(0.4, Color(1.0, 0.45, 0.1, 0.9))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	flames.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9) * maxf(size, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	q.material = m
	flames.draw_pass_1 = q
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)

	var smoke := GPUParticles3D.new()
	smoke.amount = int(26 * size) + 6
	smoke.lifetime = 5.0
	smoke.position = pos + Vector3(0, 1.2 * size, 0)
	smoke.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(20, 22, 20))
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spm.emission_sphere_radius = 0.6 * size
	spm.direction = Vector3.UP
	spm.spread = 15.0
	spm.initial_velocity_min = 1.2
	spm.initial_velocity_max = 2.2
	spm.gravity = Vector3(0.7, 0.5, 0.35)
	spm.scale_min = 1.0
	spm.scale_max = 1.6
	var ssc := Curve.new()
	ssc.add_point(Vector2(0, 0.4))
	ssc.add_point(Vector2(1, 2.6))
	var ssct := CurveTexture.new()
	ssct.curve = ssc
	spm.scale_curve = ssct
	var sg := Gradient.new()
	sg.set_color(0, Color(0.12, 0.1, 0.09, 0.0))
	sg.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
	sg.add_point(0.15, Color(0.13, 0.11, 0.1, 0.55))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	spm.color_ramp = sgt
	smoke.process_material = spm
	var sq := QuadMesh.new()
	sq.size = Vector2(1.6, 1.6) * size
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = _soft_tex()
	sq.material = smat
	smoke.draw_pass_1 = sq
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)

	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.16)
	l.light_energy = 2.6 * size + 0.6
	l.omni_range = 9.0 + 6.0 * size
	l.position = pos + Vector3(0, 1.4, 0)
	add_child(l)
	if arena and "fire_lights" in arena:
		arena.fire_lights.append(l)
	_loop3d("fire_loop", pos, -4.0 + 4.0 * size, 3.0, 26.0)


# ---------------------------------------------------------------------------
# SWINGING LIGHTS: chandeliers in the church, work lamps in the warehouse
# ---------------------------------------------------------------------------
func _build_swinging_lights() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.18, 0.17, 0.16)
	metal.metallic = 0.7
	metal.roughness = 0.5
	for s in [[Vector3(1, 8.0, -24), 2.6, Color(1.0, 0.72, 0.42), true, true], [Vector3(1, 8.0, -36), 2.6, Color(1.0, 0.72, 0.42), false, true],
			[Vector3(27, 7.0, 4), 2.2, Color(1.0, 0.92, 0.75), true, false], [Vector3(43, 7.0, -6), 2.2, Color(1.0, 0.92, 0.75), false, false],
			[Vector3(42, 7.0, 22), 2.2, Color(1.0, 0.92, 0.75), false, false]]:
		var pivot := Node3D.new()
		pivot.position = s[0]
		add_child(pivot)
		var length: float = s[1]
		var cable := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.03, length, 0.03)
		cable.mesh = cm
		cable.material_override = metal
		cable.position.y = -length * 0.5
		pivot.add_child(cable)
		var shade := MeshInstance3D.new()
		if s[4]:
			var tm := TorusMesh.new() # chandelier ring
			tm.inner_radius = 0.5
			tm.outer_radius = 0.62
			shade.mesh = tm
		else:
			var cyl := CylinderMesh.new() # lamp shade
			cyl.top_radius = 0.12
			cyl.bottom_radius = 0.45
			cyl.height = 0.35
			shade.mesh = cyl
		shade.material_override = metal
		shade.position.y = -length
		pivot.add_child(shade)
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.1
		bm.height = 0.2
		bulb.mesh = bm
		bulb.material_override = MaterialLib.get_emissive(Color(0.25, 0.08, 0.06), 0.15)
		bulb.position.y = -length - 0.15
		pivot.add_child(bulb)
		var l := OmniLight3D.new()
		l.light_color = s[2]
		l.light_energy = 0.0
		l.omni_range = 10.5
		l.shadow_enabled = s[3] and GameState.graphics_quality >= 1
		l.position.y = -length - 0.3
		pivot.add_child(l)
		_swingers.append({"pivot": pivot, "phase": _rng.randf_range(0.0, TAU), "light": l, "bulb": bulb, "color": s[2]})


# ---------------------------------------------------------------------------
# AMBIENT SOUND
# ---------------------------------------------------------------------------
func _build_ambience() -> void:
	_rain_out = _loop2d("rain_loop")
	_rain_in = _loop2d("rain_indoor_loop")
	_wind = _loop2d("wind_loop")
	_roof = _loop3d("roof_rain_loop", Vector3(36, 6.5, 6), -80.0, 14.0, 40.0)
	_loop3d("drone_loop", Vector3(1, 4.0, -38), -9.0, 8.0, 34.0)
	_loop3d("hum_loop", Vector3(-28, 3.5, -3), -16.0, 4.0, 18.0)
	_loop3d("hum_loop", Vector3(-38, 3.5, -21), -18.0, 4.0, 16.0)


func _looped(name: String) -> AudioStream:
	var st := GameState.get_sfx_stream(name)
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * float(w.mix_rate))
	return st


func _loop2d(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _looped(name)
	p.bus = &"SFX"
	p.volume_db = -80.0
	add_child(p)
	if p.stream:
		p.play()
	return p


func _loop3d(name: String, pos: Vector3, vol: float, unit: float, max_d: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _looped(name)
	p.bus = &"SFX"
	p.volume_db = vol
	p.unit_size = unit
	p.max_distance = max_d
	p.position = pos
	add_child(p)
	if p.stream:
		p.play(randf() * 2.0)
	return p


func _one_shot(name: String, pos: Vector3, vol: float, pitch: float) -> void:
	var st := GameState.get_sfx_stream(name)
	if st == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = &"SFX"
	p.volume_db = vol
	p.pitch_scale = pitch
	p.unit_size = 18.0
	p.max_distance = 140.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _ambient_event(cam_pos: Vector3) -> void:
	var zone := String(arena.zone_at(cam_pos)) if arena else ""
	var ring := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	var far := cam_pos + ring * _rng.randf_range(25.0, 45.0) + Vector3(0, 4, 0)
	var near := cam_pos + ring * _rng.randf_range(4.0, 9.0) + Vector3(0, 3, 0)
	var r := _rng.randf()
	match zone:
		"warehouse":
			if r < 0.38:
				_one_shot("metal_scrape", near, -8.0, _rng.randf_range(0.85, 1.15))
			elif r < 0.68:
				_one_shot("fluorescent_buzz", near, -11.0, _rng.randf_range(0.9, 1.1))
			elif r < 0.85:
				_one_shot("creak", near, -10.0, _rng.randf_range(0.7, 1.0))
			else:
				_one_shot("drip", near, -14.0, _rng.randf_range(0.9, 1.2))
		"hospital":
			if r < 0.32:
				_one_shot("whisper_eerie", near, -9.0, _rng.randf_range(0.9, 1.1))
			elif r < 0.56:
				_one_shot("fluorescent_buzz", near, -11.0, _rng.randf_range(0.9, 1.1))
			elif r < 0.78:
				_one_shot("drip", near, -14.0, _rng.randf_range(0.9, 1.3))
			elif r < 0.90:
				_one_shot("metal_scrape", near, -12.0, _rng.randf_range(0.95, 1.25))
			else:
				_one_shot("scream_far", far, -10.0, _rng.randf_range(0.85, 1.1))
		"church":
			if r < 0.38:
				_one_shot("whisper_eerie", near, -8.0, _rng.randf_range(0.82, 1.05))
			elif r < 0.72:
				_one_shot("creak", near + Vector3(0, 4, 0), -11.0, _rng.randf_range(0.55, 0.75))
			else:
				_one_shot("bell_far", Vector3(1, 12, -50), -9.0, 1.0)
		_:
			if r < 0.25:
				_one_shot("crow", far, -8.0, _rng.randf_range(0.9, 1.1))
			elif r < 0.45:
				_one_shot("whisper_eerie", near, -11.0, _rng.randf_range(0.9, 1.15))
			elif r < 0.65:
				_one_shot("metal_scrape", near, -12.0, _rng.randf_range(0.85, 1.15))
			elif r < 0.80:
				_one_shot("scream_far", far, -11.0, _rng.randf_range(0.85, 1.15))
			elif r < 0.90:
				_one_shot("bell_far", Vector3(1, 12, -50), -6.0, 1.0)
			else:
				_one_shot("train_horn", Vector3(-90, 4, 30), -4.0, _rng.randf_range(0.95, 1.05))


# ---------------------------------------------------------------------------
# SPECIAL ROUNDS: the sky and the air change with the round's event
# ---------------------------------------------------------------------------
var _event_fog: float = 0.0
var _event_tw: Tween
var _moon: MeshInstance3D
var _base_amb: Color = Color(-1, 0, 0)
var _base_fogc: Color


func set_event(kind: String) -> void:
	if _env == null:
		return
	if _base_amb.r < 0.0:
		_base_amb = _env.ambient_light_color
		_base_fogc = _env.fog_light_color
	var amb := _base_amb
	var fogc := _base_fogc
	var fog := 0.0
	match kind:
		"blood_moon":
			amb = Color(0.44, 0.1, 0.08)
			fogc = Color(0.32, 0.05, 0.04)
			fog = 0.004
		"dead_fog":
			fog = 0.06
			fogc = Color(0.3, 0.33, 0.36)
		"toxic":
			amb = Color(0.12, 0.23, 0.11)
			fogc = Color(0.06, 0.14, 0.05)
			fog = 0.008
		"cunning":
			amb = Color(0.22, 0.19, 0.1)
	if _event_tw:
		_event_tw.kill()
	_event_tw = create_tween().set_parallel(true)
	_event_tw.tween_property(_env, "ambient_light_color", amb, 3.0)
	_event_tw.tween_property(_env, "fog_light_color", fogc, 3.0)
	_event_tw.tween_property(self, "_event_fog", fog, 3.0)
	if kind == "blood_moon" and _moon == null:
		_moon = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 9.0
		sm.height = 18.0
		_moon.mesh = sm
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = Color(1.5, 0.13, 0.08) # a little brighter than white so it glows
		mm.disable_fog = true
		_moon.material_override = mm
		_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_moon.top_level = true
		add_child(_moon)
	if _moon:
		_moon.visible = kind == "blood_moon"
