extends "res://scripts/world/atmosphere.gd"
# Atmosphere for the open-world OUTBREAK map. The weather cycle, rain, moon,
# lightning and special-round skies are the classic ones; only the parts the
# classic script places at fixed spots on the closed Nacht map are replaced:
#   - no chandeliers / work lamps hanging where the old church and warehouse
#     stood (on the County that is empty sky)
#   - no fog banks, wreck fires or room hums at old-map coordinates
#   - ambient one-shots follow the player around the county (crows, distant
#     screams, a far-off car alarm), never a bell or train at a fixed point


func _build_fog() -> void:
	pass  # the open map uses the environment's volumetric haze


func _build_fires() -> void:
	# a few burning wrecks / barrels at real County spots, on the ground
	var spots: Array = arena.get("fire_spots") if "fire_spots" in arena else [[Vector3(-2, 0.5, 18), 0.6], [Vector3(-150, 0.4, 59), 0.5],
			[Vector3(122, 0.4, -106), 0.5], [Vector3(102, 0.5, 88), 0.6], [Vector3(286, 0.5, -239), 0.9], [Vector3(-304, 0.7, 154), 0.6]]
	for f in spots:
		_fire(f[0], f[1])


func _build_swinging_lights() -> void:
	pass


func _build_ambience() -> void:
	_rain_out = _loop2d("rain_loop")
	_rain_in = _loop2d("rain_indoor_loop")
	_wind = _loop2d("wind_loop")


func _ambient_event(cam_pos: Vector3) -> void:
	var ring := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	var far := cam_pos + ring * _rng.randf_range(30.0, 60.0) + Vector3(0, 4, 0)
	var near := cam_pos + ring * _rng.randf_range(4.0, 9.0) + Vector3(0, 2, 0)
	var r := _rng.randf()
	var outdoor: Array = arena.get("outdoor_zones") if "outdoor_zones" in arena else ["wilds"]
	var indoors := not (String(arena.zone_at(cam_pos)) in outdoor)
	if indoors:
		_one_shot("creak" if r < 0.6 else "drip", near, -12.0, _rng.randf_range(0.8, 1.2))
	elif r < 0.5:
		_one_shot("crow", far, -8.0, _rng.randf_range(0.9, 1.1))
	else:
		_one_shot("scream_far", far, -12.0, _rng.randf_range(0.85, 1.15))
