extends SceneTree
# Dev helper: renders the mill kit sheet (tools/mill_kit_sheet_node.gd) to user://mill_kit_<n>.png
func _initialize() -> void:
	var n: Node = (load("res://tools/mill_kit_sheet_node.gd") as GDScript).new()
	root.add_child.call_deferred(n)
