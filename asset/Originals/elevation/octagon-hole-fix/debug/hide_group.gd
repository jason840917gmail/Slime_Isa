extends SceneTree
## Debug: hides the elevation drawing's groups named in HIDE (comma list: Patches, Shade, Sides, ...),
## or, with KIND=<r>, prints the Sides meshes' names.
var _t := 0.0
var _done := false

func _initialize() -> void:
	change_scene_to_file.call_deferred("res://game/dev/playground.tscn")

func _process(delta: float) -> bool:
	_t += delta
	if not _done and _t > 1.5:
		_done = true
		for e: Node in get_root().find_children("Elevation", "", true, false):
			for g: String in OS.get_environment("HIDE").split(",", false):
				var n := e.get_node_or_null(NodePath(g)) as CanvasItem
				if n != null:
					n.visible = false
			var sides := e.get_node_or_null(^"Sides")
			if sides != null and OS.get_environment("LIST") == "1":
				for c: Node in sides.get_children():
					print("SIDES ", c.name)
	return false
