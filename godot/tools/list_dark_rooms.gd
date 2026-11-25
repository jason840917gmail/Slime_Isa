extends SceneTree
## Lists every dark room (game/world/darkness/dark_room.gd) of the scenes given, with the candles it
## lists and the candles (candle.gd: candles, sconces, braziers) that stand inside its rectangle, each
## with its light: what docs/godot/DARKNESS.md "A share of the room per candle" lights. Headless:
##     "<Godot console exe>" --headless --path godot -s res://tools/list_dark_rooms.gd -- res://a.tscn res://b.tscn ...
## One line per dark room: scene, node, rect, listed, inside (lit for good / burn_ms per candle).

const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const CANDLE := "res://game/world/fire/candle.gd"


func _initialize() -> void:
	for path: String in OS.get_cmdline_user_args():
		var scene := load(path) as PackedScene
		if scene == null:
			print("%s: cannot load" % path)
			continue
		var root := scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		var rooms: Array[Node] = []
		var candles: Array[Node] = []
		_collect(root, rooms, candles)
		for room: Node in rooms:
			var at := _global(room)
			var size: Vector2 = room.get(&"size")
			var rect := Rect2(at, size)
			var listed: Array = room.get(&"candles")
			var inside: Array[String] = []
			for candle: Node in candles:
				if rect.has_point(_global(candle)):
					inside.append("%s(r%.0f,burn%.0f)" % [candle.name, float(candle.get(&"light_radius")), float(candle.get(&"burn_ms"))])
			print("%s | %s | rect %s | listed %d | inside %d: %s | for_good %s | override %.2f" % [path.get_file(), room.name,
				rect, listed.size(), inside.size(), ", ".join(inside), room.get(&"lit_for_good_when_all_lit"), float(room.get(&"darkness_override"))])
		root.free()
	quit(0)


func _collect(node: Node, rooms: Array[Node], candles: Array[Node]) -> void:
	var script := node.get_script() as Script
	if script != null:
		if script.resource_path == DARK_ROOM:
			rooms.append(node)
		elif script.resource_path == CANDLE:
			candles.append(node)
	for child: Node in node.get_children():
		_collect(child, rooms, candles)


## The node's position in its scene (positions added up its Node2D parents; nothing here rotates).
func _global(node: Node) -> Vector2:
	var at := Vector2.ZERO
	var n := node
	while n != null:
		if n is Node2D:
			at += (n as Node2D).position
		n = n.get_parent()
	return at
