extends SceneTree
## Builds the terrain lab (docs/godot/TERRAIN_LAB.md): res://game/dev/terrain_lab/terrain_lab.tscn,
## one ground on the converted terrain tile set (res://game/world/terrain_tileset.tres)
## painted with every ground pair and water shore the worlds have. Its `Ground` runs
## terrain_lab_ground.gd, which mounts the water surface and the hand-made terrain edges the way
## WorldService does for a world, in the editor too. Cells use Phaser's sheet-wrap frames.
##
## Run with the Godot 4.7.2 console exe (needs imported art):
##     --headless --path godot -s res://tools/build_terrain_lab.gd
## Safe to re-run: it rewrites the lab scene (paint you added is lost).

const LAB_DIR := "res://game/dev/terrain_lab/"
const SCENE_PATH := LAB_DIR + "terrain_lab.tscn"
const LAB_SCRIPT := LAB_DIR + "terrain_lab.gd"
const GROUND_SCRIPT := LAB_DIR + "terrain_lab_ground.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const TILE_ID_DATA_LAYER := "tile_id"
const CELL := 64
const SHEET_CELLS := 19

## Map key -> terrain tile id.
const KEY := {
	"g": "grass-a", "s": "sanddessert-ground", "w": "water", "d": "deep-water",
	"f": "forest-floor", "m": "forest-moss", "a": "amberleaf-ground", "z": "frozen-ground",
	"c": "cavern-floor", "x": "crystal-floor", "t": "town-cobble", "r": "rock-wall",
}
## A beach lake with a deep middle; moss over forest floor; snow with crystal; a cobble road;
## ponds ringed by moss and fallen leaves; a cavern with crystal, deep water and a rock wall.
const MAP := [
	"gggggggggggggggggggggggggggggggggg",
	"gggsssssgggggggmmmmmmgggggzzzzzggg",
	"ggsswwwssgggggmmffffmmgggzzzzzzzgg",
	"gsswwddwwssggggmffffmmggzzzxxzzzgg",
	"gsswddddwssggggmmffmmgggzzzxxxzzgg",
	"ggswwddwwsgggtttttttttttzzzzzzgggg",
	"ggsswwwwssggtttgggggggtttggggggggg",
	"gggssssssggttgggaaaaggggttggcccccc",
	"ggggggggggtggggaaaaaagggttgcccccrr",
	"gggmmmmgggtgggaaawwaaagggtgcxxccrr",
	"ggmmwwmmggtgggaawwwwaagggtgcxxxccr",
	"ggmmwwmmggtggggaawwaagggggtccddccc",
	"gggmmmmggtgggggggaagggggggtccddxcc",
	"ggggggggggggggggggggggggggtccccccc",
]


func _initialize() -> void:
	quit(0 if _build() else 1)


func _build() -> bool:
	for path: String in [TERRAIN_TILESET, LAB_SCRIPT, GROUND_SCRIPT]:
		if not ResourceLoader.exists(path):
			push_error("build_terrain_lab: %s is missing (not imported yet?)" % path)
			return false
	var tile_set := load(TERRAIN_TILESET) as TileSet
	var source_of := _sources_by_tile_id(tile_set)
	for tile_id: String in KEY.values():
		if not source_of.has(tile_id):
			push_error("build_terrain_lab: the terrain tile set has no '%s'" % tile_id)
			return false

	var root := Node2D.new()
	root.name = "TerrainLab"
	root.set_script(load(LAB_SCRIPT))

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tile_set
	var size := Vector2i(MAP[0].length(), MAP.size())
	ground.set_meta("columns", size.x)
	ground.set_meta("rows", size.y)
	for y in size.y:
		var line: String = MAP[y]
		for x in size.x:
			var tile_id: String = KEY[line[x]]
			ground.set_cell(Vector2i(x, y), source_of[tile_id], Vector2i(posmod(x, SHEET_CELLS), posmod(y, SHEET_CELLS)))
	ground.set_script(load(GROUND_SCRIPT))
	root.add_child(ground)

	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = Vector2(size) * CELL * 0.5
	camera.zoom = Vector2(0.6, 0.6)
	# Physics interpolation is on: the camera would switch itself to physics mode with a warning.
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(camera)

	var ui := CanvasLayer.new()
	ui.name = "Ui"
	root.add_child(ui)
	var status := Label.new()
	status.name = "Status"
	status.position = Vector2(16, 12)
	status.add_theme_font_size_override(&"font_size", 22)
	status.add_theme_color_override(&"font_outline_color", Color.BLACK)
	status.add_theme_constant_override(&"outline_size", 6)
	ui.add_child(status)

	_own(root, root)
	var scene := PackedScene.new()
	var result := scene.pack(root)
	if result == OK:
		result = ResourceSaver.save(scene, SCENE_PATH)
	root.free()
	if result != OK:
		push_error("build_terrain_lab: saving the scene failed (%d)" % result)
		return false
	print("build_terrain_lab: saved %s (%d x %d cells)" % [SCENE_PATH, size.x, size.y])
	return true


## Terrain tile id -> atlas source id (each converted source carries its tile id as custom data).
func _sources_by_tile_id(tile_set: TileSet) -> Dictionary:
	var out := {}
	for i in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(i)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.get_tiles_count() == 0:
			continue
		var data := source.get_tile_data(source.get_tile_id(0), 0)
		var tile_id := str(data.get_custom_data(TILE_ID_DATA_LAYER))
		if not tile_id.is_empty() and not out.has(tile_id):
			out[tile_id] = source_id
	return out


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
