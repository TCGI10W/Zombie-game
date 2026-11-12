extends SceneTree
## Dev tool: loads the game scene, waits, saves a screenshot.
## godot --path . -s res://tools/capture_game.gd -- <out.png> [frames]

var _out := "user://capture.png"
var _frames := 300
var _n := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_frames = int(args[1])
	print("CAPTURE START")
	change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _process(_delta: float) -> bool:
	_n += 1
	if _n == _frames:
		root.get_texture().get_image().save_png(_out)
		print("CAPTURED ", _out)
		return true
	return false
