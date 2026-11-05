class_name NetBuffer
extends RefCounted
# Snapshot interpolation for a networked body. States are stamped with the
# host clock; the body is drawn a little in the past (Net render time) so
# there are always two states to blend between. Late or lost packets are
# covered by a short, capped extrapolation instead of a visible stop/jump.

const MAX_STATES := 10
const MAX_EXTRAPOLATE := 0.25

var times: PackedFloat64Array = PackedFloat64Array()
var positions: PackedVector3Array = PackedVector3Array()
var yaws: PackedFloat32Array = PackedFloat32Array()
var latest_extra: Dictionary = {}


func push(t: float, pos: Vector3, yaw: float, extra: Dictionary = {}) -> void:
	var n := times.size()
	if n > 0 and t <= times[n - 1]:
		if t < times[n - 1] - 1.0:
			clear() # host clock jumped (rejoin): start over
		else:
			return # out of order / duplicate
	times.append(t)
	positions.append(pos)
	yaws.append(yaw)
	latest_extra = extra
	if times.size() > MAX_STATES:
		times.remove_at(0)
		positions.remove_at(0)
		yaws.remove_at(0)


func clear() -> void:
	times.clear()
	positions.clear()
	yaws.clear()


func has_data() -> bool:
	return times.size() > 0


func latest_pos() -> Vector3:
	return positions[positions.size() - 1]


# Returns [position, yaw, velocity]
func sample(t: float) -> Array:
	var n := times.size()
	if n == 1:
		return [positions[0], yaws[0], Vector3.ZERO]
	if t <= times[0]:
		return [positions[0], yaws[0], Vector3.ZERO]
	for i in range(n - 1):
		if t <= times[i + 1]:
			var span := maxf(0.0001, times[i + 1] - times[i])
			var f := (t - times[i]) / span
			var vel := (positions[i + 1] - positions[i]) / span
			return [positions[i].lerp(positions[i + 1], f), lerp_angle(yaws[i], yaws[i + 1], f), vel]
	# Past the newest state: extrapolate briefly along the last velocity
	var dt := maxf(0.0001, times[n - 1] - times[n - 2])
	var v := (positions[n - 1] - positions[n - 2]) / dt
	if v.length() > 12.0:
		v = Vector3.ZERO # a teleport, not motion
	var ahead := minf(t - times[n - 1], MAX_EXTRAPOLATE)
	return [positions[n - 1] + v * ahead, yaws[n - 1], v if ahead < MAX_EXTRAPOLATE else Vector3.ZERO]
