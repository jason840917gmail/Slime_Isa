extends SceneTree
## Creates only the NEW manual-cliff resources. Refuses to overwrite an existing lab.
const LAB := "res://game/scenes/worlds/cliff-manual-tiles-lab.tscn"
const TILESET := "res://game/world/cliffs/manual_prototype/manual_cliff_tileset.tres"
const ART := "res://asset/MAPS/cliffs/manual-prototype/128x128-tile_6x6-cliff-manual.png"
const LabScript := preload("res://game/world/cliffs/manual_prototype/manual_lab.gd")
const ProbeScript := preload("res://game/world/cliffs/manual_prototype/manual_probe.gd")
const OverlayScript := preload("res://game/world/cliffs/manual_prototype/manual_overlay.gd")
const NAMES := [
	["NW top", "North top", "NE top", "NW inner", "NE inner", "Grass A"],
	["West top", "Grass center", "East top", "SW inner", "SE inner", "Grass B"],
	["SW front rim", "Front rim", "SE front rim", "North variant", "West variant", "East variant"],
	["Cap left", "Cap middle", "Cap right", "Short left", "Short middle", "Short right"],
	["Body left", "Body middle", "Body right", "Body left B", "Body middle B", "Body right B"],
	["Foot left", "Foot middle", "Foot right", "Foot left B", "Foot middle B", "Foot right B"]]


func _initialize() -> void:
	_build.call_deferred()


func _polygon(data: TileData, bounds: Rect2) -> void:
	var a := bounds.position - Vector2(64, 64)
	var b := bounds.end - Vector2(64, 64)
	var index := data.get_collision_polygons_count(0)
	data.set_collision_polygons_count(0, index + 1)
	data.set_collision_polygon_points(0, index, PackedVector2Array([
		a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]))


func _physics(data: TileData, c: Vector2i) -> void:
	if c.y >= 3:
		var left: float = 24.0 if c.x % 3 == 0 else 0.0
		var right: float = 104.0 if c.x % 3 == 2 else 128.0
		var bottom: float = 112.0 if c.y == 5 or (c.y == 3 and c.x >= 3) else 128.0
		_polygon(data, Rect2(left, 0, right - left, bottom))
		return
	if c.x < 3:
		if c.x == 0:
			_polygon(data, Rect2(20, 24 if c.y == 0 else 0, 16, 104 if c.y == 0 else 128))
		if c.x == 2:
			_polygon(data, Rect2(92, 24 if c.y == 0 else 0, 16, 104 if c.y == 0 else 128))
		if c.y == 0:
			_polygon(data, Rect2(24 if c.x == 0 else 0, 20, 104 if c.x != 1 else 128, 16))
		if c.y == 2:
			_polygon(data, Rect2(24 if c.x == 0 else 0, 104, 104 if c.x != 1 else 128, 24))
	elif c.x in [3, 4] and c.y < 2:
		var x: float = 0.0 if c.x == 3 else 96.0
		var y: float = 0.0 if c.y == 0 else 96.0
		_polygon(data, Rect2(x, y, 32, 32))
	elif c.y == 2:
		if c.x == 3:
			_polygon(data, Rect2(0, 20, 128, 16))
		elif c.x == 4:
			_polygon(data, Rect2(20, 0, 16, 128))
		else:
			_polygon(data, Rect2(92, 0, 16, 128))


func _put(layer: TileMapLayer, cell: Vector2i, tile: Vector2i) -> void:
	layer.set_cell(cell, 0, tile)


func _top_tile(c: Vector2i, cells: Dictionary) -> Vector2i:
	var north: bool = not cells.has(c + Vector2i.UP)
	var south: bool = not cells.has(c + Vector2i.DOWN)
	var west: bool = not cells.has(c + Vector2i.LEFT)
	var east: bool = not cells.has(c + Vector2i.RIGHT)
	if north:
		return Vector2i(0 if west else (2 if east else 1), 0)
	if south:
		return Vector2i(0 if west else (2 if east else 1), 2)
	if west:
		return Vector2i(0, 1)
	if east:
		return Vector2i(2, 1)
	for i: int in 4:
		var diagonal: Vector2i = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)][i]
		if not cells.has(c + diagonal):
			return Vector2i(3 + i % 2, i / 2)
	return Vector2i(1, 1)


func _shape(layer: TileMapLayer, origin: Vector2i, regions: Array[Rect2i], height: int) -> void:
	var cells: Dictionary = {}
	for region: Rect2i in regions:
		for y: int in range(region.position.y, region.end.y):
			for x: int in range(region.position.x, region.end.x):
				cells[Vector2i(x, y)] = true
	for c: Vector2i in cells:
		_put(layer, origin + c, _top_tile(c, cells))
	for c: Vector2i in cells:
		if cells.has(c + Vector2i.DOWN):
			continue
		var left: bool = not cells.has(c + Vector2i.LEFT)
		var right: bool = not cells.has(c + Vector2i.RIGHT)
		var column: int = 0 if left else (2 if right else 1)
		for row: int in height:
			var tile := Vector2i(column + 3, 3) if height == 1 else Vector2i(column, 3 if row == 0 else (5 if row == height - 1 else 4))
			_put(layer, origin + c + Vector2i(0, row + 1), tile)


func _add(root: Node, node: Node, node_name: String) -> void:
	node.name = node_name
	root.add_child(node)
	node.owner = root


func _build() -> void:
	if FileAccess.file_exists(LAB):
		push_error("Refusing to overwrite manual prototype: keep hand-painted changes safe.")
		quit(1)
		return
	var texture := load(ART) as Texture2D
	if texture == null:
		push_error("Import the new atlas in the editor first.")
		quit(1)
		return
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(128, 128)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(128, 128)
	tile_set.add_source(atlas, 0)
	for row: int in 6:
		for col: int in 6:
			var c := Vector2i(col, row)
			atlas.create_tile(c)
			var data := atlas.get_tile_data(c, 0)
			data.set_meta("tile_name", NAMES[row][col])
			_physics(data, c)
	var result := OK
	if FileAccess.file_exists(TILESET):
		tile_set = load(TILESET) as TileSet
	else:
		result = ResourceSaver.save(tile_set, TILESET)
	if result != OK:
		push_error("Could not save tileset: %s" % result)
		quit(1)
		return
	var world := Node2D.new()
	world.name = "CliffManualPrototype"
	world.set_script(LabScript)
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	layer.scale = Vector2(0.5, 0.5)
	_add(world, layer, "Cliffs")
	_shape(layer, Vector2i(2, 3), [Rect2i(0, 0, 8, 5)], 1)
	_shape(layer, Vector2i(14, 3), [Rect2i(0, 0, 8, 5)], 2)
	_shape(layer, Vector2i(26, 3), [Rect2i(0, 0, 8, 5)], 4)
	_shape(layer, Vector2i(24, 15), [Rect2i(0, 0, 10, 4), Rect2i(0, 4, 4, 7)], 2)
	for i: int in 3:
		var terrace := TileMapLayer.new()
		terrace.tile_set = tile_set
		terrace.scale = Vector2(0.5, 0.5)
		_add(world, terrace, "TerraceLevel%d" % (i + 1))
		_shape(terrace, Vector2i(2 + i * 2, 15 + i * 2), [Rect2i(0, 0, 16 - i * 4, 12 - i * 4)], 2)
	var overlay := Node2D.new()
	overlay.set_script(OverlayScript)
	overlay.z_index = 3
	_add(world, overlay, "CollisionOverlay")
	var probe := CharacterBody2D.new()
	probe.set_script(ProbeScript)
	probe.position = Vector2(420, 720)
	probe.collision_layer = 2
	probe.collision_mask = 1
	probe.z_index = 2
	_add(world, probe, "Probe")
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 26)
	collision.shape = rect
	probe.add_child(collision)
	collision.name = "BodyShape"
	collision.owner = world
	var sprite := Sprite2D.new()
	sprite.texture = load("res://asset/characters/authored/npcs/village-elder-plop.webp") as Texture2D
	sprite.hframes = 6
	sprite.vframes = 5
	sprite.scale = Vector2(0.32, 0.32)
	sprite.position = Vector2(0, -22)
	probe.add_child(sprite)
	sprite.owner = world
	var camera := Camera2D.new()
	camera.position = Vector2(1160, 1050)
	camera.zoom = Vector2(0.45, 0.45)
	_add(world, camera, "Camera2D")
	var canvas := CanvasLayer.new()
	_add(world, canvas, "UI")
	var label := Label.new()
	label.position = Vector2(20, 16)
	label.add_theme_font_size_override("font_size", 18)
	label.text = "FIXED-CELL CLIFF TILE PROTOTYPE\nWASD: move slime · C: collision overlay · Ctrl-click: place slime\nWheel: zoom · Right-drag: pan · Home: overview · 1/2/3: close-ups"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	label.owner = world
	var packed := PackedScene.new()
	result = packed.pack(world)
	if result == OK:
		result = ResourceSaver.save(packed, LAB)
	print("Manual cliff prototype saved; cells=", layer.get_used_cells().size(), "; result=", result)
	world.free()
	quit(0 if result == OK else 1)
