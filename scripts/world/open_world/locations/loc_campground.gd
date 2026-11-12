extends OWLocation
# BLACKWATER CAMPGROUND, at the end of a dirt spur east of the depot: tents
# pitched in a clearing ringed by pines, fire pits, picnic tables and the
# ranger's cabin (furnished, with a rifle rack).
#   pad x 104..152, z -136..-88.

const O := Vector2(128, -112)


func _init() -> void:
	id = "campground"
	title = "BLACKWATER CAMP"
	center = O
	pad = Rect2(104, -136, 48, 48)
	views = [[Vector3(100, 5, -104), Vector3(126, 1, -108)], [Vector3(142, 1.7, -126), Vector3(140, 1.4, -122)]]


func build() -> void:
	var cabin := Rect2(O.x + 8, O.y - 20, 8, 12)
	w.zone_names["ranger_cabin"] = "RANGER CABIN"
	house(cabin, "siding_red", "ranger_cabin", ["s", 0, 0], [["e", 1], ["w", 1]], "gable", "wood")
	porch(cabin, "s", 0)
	furnish_house(cabin, "s")
	buy(cabin, "n", 0, "weapon", "rifle", "COMMANDO M14A", 1200, 600)
	for i in range(6):
		var a := float(i) / 6.0 * TAU
		k("ext_tent", O.x - 6 + cos(a) * 10.0, O.y + 6 + sin(a) * 8.0, rad_to_deg(-a) + 90.0)
	k("ext_campfire", O.x - 6, O.y + 6)
	for p in [Vector2(-16, -6), Vector2(4, 16), Vector2(-18, 16)]:
		k("ext_picnic_table", O.x + p.x, O.y + p.y, p.x * 7.0)
	wreck(O.x - 18, O.y - 16, 30.0)
	k("ext_trash_can", O.x - 10, O.y - 10)
	for i in range(14):
		var a := float(i) / 14.0 * TAU
		k("ext_pine", O.x + cos(a) * 22.0, O.y + sin(a) * 22.0, float(i) * 37.0, 0.9 + float(i % 3) * 0.2)
	light(O.x - 2, O.y - 4, Color(1.0, 0.78, 0.45), 1.6)
