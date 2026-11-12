extends SceneTree
## Builds the playground's sky corner (docs/godot/SKY_FLOOR.md "The playground's sky corner"): a sky
## floor on the playground's east side (cells 100-123 x 67-88, x 6400-7936, y 4288-5696, south of the
## Bestiary's east pens and north of the Crossings corner), with three islands, a rope bridge to each and an islet with
## none.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_sky_corner.gd [-- --force]
## Paints the sky on the playground's `elevation` layer (level -2; the islands left at level 0, their
## corners cut, and an islet at level 1 whose walls drop three levels), writes res://game/dev/corners/sky_corner.tscn (the SkyFloor, the bridges, a sign) and
## instances it in the playground. It stops when the area is painted already or the corner exists,
## unless given --force; after that both are edited by hand. Bake the playground's elevation cache
## afterwards (tools/bake_elevation.gd -- --world=playground).
##
## Owner: world (sky).

const SceneSave := preload("res://tools/lib/scene_save.gd")
const SkyFloorScript := preload("res://game/world/sky/sky_floor.gd")
const RopeBridgeScript := preload("res://game/world/sky/rope_bridge.gd")

const CORNER_PATH := "res://game/dev/corners/sky_corner.tscn"
const PLAYGROUND_SCENE := "res://game/scenes/worlds/playground.tscn"
const CORNER_NAME := "sky-corner"

const CELL := 64
## The free ground the corner may use, and the sky painted in it (cells).
const AREA := Rect2i(93, 65, 31, 26)
const SKY := Rect2i(100, 67, 24, 22)
const SKY_LEVEL := -2
## The elevation palette's tile of each level (row 0: -3, -2, -1, 1, 2, 3).
const LEVEL_TILE := {-3: Vector2i(0, 0), -2: Vector2i(1, 0), -1: Vector2i(2, 0), 1: Vector2i(3, 0)}
## The islands (cells, their level), each with its corners cut unless it is three cells or less wide.
const ISLANDS := [[Rect2i(104, 70, 6, 6), 0], [Rect2i(114, 69, 7, 6), 0], [Rect2i(104, 80, 8, 6), 0],
		[Rect2i(115, 79, 6, 4), 1]]
const NOT_ISLAND := -99
## The bridges: name, hinge (world units), the way it runs, cells long.
const BRIDGES := [
	["bridge-west", Vector2(6400, 4640), "east", 4],
	["bridge-east", Vector2(7040, 4640), "east", 4],
	["bridge-south", Vector2(6816, 4864), "south", 4],
]


func _initialize() -> void:
	var force := OS.get_cmdline_user_args().has("--force")
	if FileAccess.file_exists(CORNER_PATH) and not force:
		print("sky corner: %s exists; not rebuilt (add -- --force)" % CORNER_PATH)
		quit(0)
		return
	var err := _save(_corner(), CORNER_PATH, true)
	if err == OK:
		err = _paint_playground(force)
	print("sky corner: ", "ok" if err == OK else "failed (%s)" % error_string(err))
	quit(0 if err == OK else 1)


func _corner() -> Node2D:
	var root := Node2D.new()
	root.name = CORNER_NAME
	root.y_sort_enabled = true
	var sky := SkyFloorScript.new()
	sky.name = "sky-floor"
	sky.position = Vector2(SKY.position) * CELL
	sky.set(&"size", Vector2(SKY.size) * CELL)
	root.add_child(sky)
	for spec: Array in BRIDGES:
		var bridge := RopeBridgeScript.new()
		bridge.name = spec[0]
		bridge.position = spec[1]
		bridge.set(&"toward", spec[2])
		bridge.set(&"length", spec[3])
		bridge.set(&"bridge_id", "playground-sky-" + str(spec[0]))
		root.add_child(bridge)
	root.add_child(_label("sign", Vector2(6024, 4380), Vector2(360, 150),
		"Sky corner (docs/godot/SKY_FLOOR.md).\nThe sky is painted as holes (level -2) on the\nelevation layer; the SkyFloor node draws it.\nCross the rope bridges; push off any edge to\nfall: you come back where you fell."))
	return root


func _label(node_name: String, at: Vector2, size: Vector2, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", 14)
	label.text = text
	return label


## Paints the sky and instances the corner in the playground (once).
func _paint_playground(force: bool) -> Error:
	var before := FileAccess.get_file_as_string(PLAYGROUND_SCENE)
	var root := (load(PLAYGROUND_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var elevation := root.get_node(^"elevation") as TileMapLayer
	var painted := 0
	for cell: Vector2i in elevation.get_used_cells():
		if AREA.has_point(cell):
			painted += 1
	if painted > 0 and not force:
		root.free()
		print("sky corner: the playground paints %d elevation cells in %s already; not painted (add -- --force)" % [painted, AREA])
		return ERR_ALREADY_EXISTS
	for y in range(SKY.position.y, SKY.end.y):
		for x in range(SKY.position.x, SKY.end.x):
			var cell := Vector2i(x, y)
			var island := _island_level(cell)
			if island == 0:
				elevation.erase_cell(cell)
			else:
				elevation.set_cell(cell, 0, LEVEL_TILE[SKY_LEVEL if island == NOT_ISLAND else island])
	if root.get_node_or_null(NodePath(CORNER_NAME)) == null:
		var corner := (ResourceLoader.load(CORNER_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		corner.name = CORNER_NAME
		root.add_child(corner)
		corner.owner = root
	return _save(root, PLAYGROUND_SCENE, false, before)


## The level of the island `cell` is on, NOT_ISLAND in the sky (a cut corner is sky).
static func _island_level(cell: Vector2i) -> int:
	for entry: Array in ISLANDS:
		var island: Rect2i = entry[0]
		if not island.has_point(cell):
			continue
		if island.size.x <= 3 or island.size.y <= 3:
			return int(entry[1])
		var edge_x := cell.x == island.position.x or cell.x == island.end.x - 1
		var edge_y := cell.y == island.position.y or cell.y == island.end.y - 1
		return NOT_ISLAND if edge_x and edge_y else int(entry[1])
	return NOT_ISLAND


func _save(root: Node, path: String, own: bool, before: String = "") -> Error:
	if own:
		for child: Node in root.get_children():
			child.owner = root
	if before.is_empty() and FileAccess.file_exists(path):
		before = FileAccess.get_file_as_string(path)
	var err := SceneSave.save(root, path, before)
	root.free()
	return err
