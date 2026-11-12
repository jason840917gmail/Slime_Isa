extends RefCounted
## What a chunk world keeps of a bigger world (docs/godot/WORLD_ATLAS.md "Chunk worlds"): the rules
## tools/split_region_chunks.gd cuts regions by and the atlas's area editor
## (game/dev/area_edit/area_edit.gd) writes joined chunks back by. Each painted layer is kept on its
## own cell size, with a margin past the chunk's edges where its drawing reaches in (`keep_rect`,
## `prop_reaches`); scenery whose picture or collision reaches into a chunk is in that chunk too
## (`overlaps`, `picture_overlaps`); an exit is clipped to the chunk (`exit_part`); a `map_id` naming
## the world names the chunk (`rename_map_id`); doors are listed for travel back from interiors
## (`list_places`).
##
## Owner: world (atlas).

const Elevation := preload("res://game/world/elevation/elevation.gd")
const PropLayerScript := preload("res://game/world/props/prop_layer.gd")
const PropPictures := preload("res://tools/lib/prop_pictures.gd")

const WORLD_EXIT := "res://game/scripts/world_exit.gd"
## How far past a chunk's edge an exit of the region world may lie and still be the chunk's
## (`exit_part`).
const EXIT_PULL := 64.0
## Scenery (scene file names starting so): static props a chunk also gets from its neighbours when
## their picture or collision reaches into it (`overlaps`), so a house or a tree on a chunk border
## shows on both sides; anything else (chests, items, NPCs, doors) lives in one chunk only.
const SCENERY: PackedStringArray = ["tree-", "wall-stone-solid", "rock-world-wall", "decoration-world-",
		"crystal-cluster-wall", "house-world-solid", "water-life"]
## Forest cells a chunk also takes past its edges (left, top, right, bottom), for the trees whose
## canopy reaches into it.
const FOREST_MARGIN := [1, 1, 1, 3]

## Each scenery scene's reach around its origin (`reach`), read once.
static var _reaches := {}
## Each painted prop tile's picture box around its cell's corner (`prop_reaches`), read once.
static var _prop_boxes := {}


## "south-wilds-a6" for chunk A6 of south-wilds.
static func chunk_id(world: String, chunk_name: String) -> String:
	return "%s-%s" % [world, chunk_name.to_lower()]


## The cells of `layer` a chunk `tiles` cells big keeps (the layer's own cells, chunk space): an
## elevation layer also Elevation.MAX_ROWS_ABOVE rows above it (the walls of the tops just north of
## it still hang in), a ForestLayer FOREST_MARGIN past its edges (canopies), a WallLayer one cell past
## every edge (the pieces at the edge still join); any other layer its own cells. A PropLayer also
## keeps the cells whose prop's picture reaches into the chunk (`prop_reaches`).
static func keep_rect(layer: TileMapLayer, tiles: Vector2i) -> Rect2i:
	var path := script_path(layer)
	if path.ends_with("elevation_layer.gd"):
		return Rect2i(0, -Elevation.MAX_ROWS_ABOVE, tiles.x, tiles.y + Elevation.MAX_ROWS_ABOVE)
	if path.ends_with("forest_layer.gd"):
		return forest_keep(tiles)
	if path.ends_with("wall_layer.gd"):
		return Rect2i(-1, -1, tiles.x + 2, tiles.y + 2)
	return Rect2i(Vector2i.ZERO, tiles)


## The forest cells a chunk of `tiles` keeps (chunk tiles): its own and FOREST_MARGIN past its edges.
static func forest_keep(tiles: Vector2i) -> Rect2i:
	return Rect2i(-FOREST_MARGIN[0], -FOREST_MARGIN[1], tiles.x + FOREST_MARGIN[0] + FOREST_MARGIN[2],
			tiles.y + FOREST_MARGIN[1] + FOREST_MARGIN[3])


static func is_prop_layer(layer: TileMapLayer) -> bool:
	return script_path(layer).ends_with("prop_layer.gd")


static func is_wall_layer(layer: TileMapLayer) -> bool:
	return script_path(layer).ends_with("wall_layer.gd")


## The cell size of `layer` (its tile set's, else `tile`).
static func cell_size(layer: TileMapLayer, tile: int) -> Vector2:
	return Vector2(layer.tile_set.tile_size) if layer.tile_set != null else Vector2(tile, tile)


static func script_path(node: Node) -> String:
	var script := node.get_script() as Script if node != null else null
	return script.resource_path if script != null else ""


## Keeps `layer`'s cells in `area` (world units), moved to the chunk's corner, each layer on its own
## cell size (`keep_rect`, `prop_reaches`), a WallLayer with `shown_cells` the chunk's own (the
## margin only shapes the joins at the edge).
static func clip_layer(layer: TileMapLayer, area: Rect2, tile: int) -> void:
	var size := cell_size(layer, tile)
	var origin := Vector2i((area.position / size).round())
	var tiles := Vector2i((area.size / size).round())
	var keep := keep_rect(layer, tiles)
	var props := is_prop_layer(layer)
	var cells := []
	for cell in layer.get_used_cells():
		var at := cell - origin
		if keep.has_point(at) or (props and prop_reaches(layer, cell, area)):
			cells.append([at, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)])
	layer.clear()
	for cell: Array in cells:
		layer.set_cell(cell[0], cell[1], cell[2], cell[3])
	if is_wall_layer(layer):
		layer.set(&"shown_cells", Rect2i(Vector2i.ZERO, tiles))


## True when the prop painted at `cell` of PropLayer `layer` shows inside `area` (layer space).
static func prop_reaches(layer: TileMapLayer, cell: Vector2i, area: Rect2) -> bool:
	var corner := Vector2(cell) * Vector2(layer.tile_set.tile_size)
	var key := [layer.tile_set.resource_path, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell),
			layer.get_cell_alternative_tile(cell), cell.x % 2]
	if not _prop_boxes.has(key):
		var box := Rect2()
		var prop: Dictionary = layer.call(&"prop_at", cell)
		if not prop.is_empty():
			var node := PropLayerScript.make_prop(prop)
			if node != null:
				box = PropPictures.bounds(node, Transform2D.IDENTITY)
				box.position -= corner
				node.free()
		_prop_boxes[key] = box
	var reach: Rect2 = _prop_boxes[key]
	return reach.has_area() and Rect2(reach.position + corner, reach.size).intersects(area)


# --- exits --------------------------------------------------------------------------------------

## The part of the exit over `rect` (world units) that chunk `area` gets: the generator puts an exit
## just past the region's border, so one lying within EXIT_PULL outside an edge of `area` is moved in
## against that edge; then what of it lies in `area` (an opening across two chunks is split between
## them). Empty when none.
static func exit_part(rect: Rect2, area: Rect2) -> Rect2:
	var moved := rect
	if rect.position.y >= area.end.y and rect.position.y - area.end.y <= EXIT_PULL:
		moved.position.y = area.end.y - rect.size.y
	elif rect.end.y <= area.position.y and area.position.y - rect.end.y <= EXIT_PULL:
		moved.position.y = area.position.y
	if rect.position.x >= area.end.x and rect.position.x - area.end.x <= EXIT_PULL:
		moved.position.x = area.end.x - rect.size.x
	elif rect.end.x <= area.position.x and area.position.x - rect.end.x <= EXIT_PULL:
		moved.position.x = area.position.x
	return moved.intersection(area)


## The world_exit.gd node of an exit Area2D, null for anything else.
static func exit_script(node: Node) -> Node:
	if not node is Area2D:
		return null
	for child: Node in node.get_children():
		if script_path(child) == WORLD_EXIT:
			return child
	return null


## Clips the exit Area2D `area_node` (at `at` in the world) to the chunk `area` (`exit_part`), or
## frees it when none of it is the chunk's.
static func clip_exit(area_node: Area2D, at: Vector2, area: Rect2) -> void:
	var shape_node: CollisionShape2D = null
	for child: Node in area_node.get_children():
		if child is CollisionShape2D:
			shape_node = child
	var box := shape_node.shape as RectangleShape2D if shape_node != null else null
	if box == null:
		if not area.has_point(at):
			area_node.free()
		return
	var rect := Rect2(at + shape_node.position - box.size / 2.0, box.size)
	var part := exit_part(rect, area)
	if not part.has_area():
		area_node.free()
		return
	var clipped := RectangleShape2D.new()
	clipped.size = part.size
	shape_node.shape = clipped
	shape_node.position = Vector2.ZERO
	area_node.position += part.get_center() - at


# --- nodes ----------------------------------------------------------------------------------------

## A group: a plain Node2D of this scene (not an instance, no script) holding nodes.
static func is_group(node: Node) -> bool:
	return node.scene_file_path.is_empty() and node.get_script() == null and node.get_child_count() > 0 \
			and node.get_class() == "Node2D"


## The places (world units) of the nodes in group `node` (at `at`): its Node2D children and their
## groups' nodes; an instance or a scripted node is one place.
static func spots(node: Node, at: Vector2, out: PackedVector2Array) -> void:
	for child: Node in node.get_children():
		if not child is Node2D:
			continue
		var place := at + (child as Node2D).position
		if is_group(child):
			spots(child, place, out)
		else:
			out.append(place)


## `node`'s place in the world (its and its parents' positions up to the root, or up to `top` when
## given), INF when it is null.
static func place_in_world(node: Node, top: Node = null) -> Vector2:
	if node == null:
		return Vector2.INF
	var at := Vector2.ZERO
	var current := node
	while current != null and current != top and current.get_parent() != null:
		if current is Node2D:
			at += (current as Node2D).position
		current = current.get_parent()
	return at


## Every `map_id` under `node` (instances' insides too) that names `world` names `chunk` instead; a
## node inside an instance (a boss camp's script) has its instances made editable in `root` so the
## chunk scene saves the new value.
static func rename_map_id(node: Node, world: String, chunk: String, root: Node = null) -> void:
	if root == null:
		root = node
	var value: Variant = node.get(&"map_id")
	if value is String and value == world:
		node.set(&"map_id", chunk)
		var instance := node.owner
		while instance != null and instance != root:
			root.set_editable_instance(instance, true)
			instance = instance.owner
	for child: Node in node.get_children():
		rename_map_id(child, world, chunk, root)


## The old arrival markers' names (a neighbour's `arrive-from-<world>-<n>`, an edge's
## `player-entry-<edge>`): no scene has one since 2026-10-31 (border crossings arrive by coordinates:
## game/world/crossings/border_crossing.gd); a scene that still has one is read as before.
static func is_arrival(node_name: String) -> bool:
	return node_name.begins_with("arrive-from-") or node_name.begins_with("player-entry-")


## The places travel arrives at in chunk world `root` (`id`): its arrival markers and its doors.
static func list_places(root: Node, id: String, arrivals: Dictionary, doors: Dictionary) -> void:
	for node: Node in root.find_children("*", "", true, false):
		if node is Node2D and is_arrival(str(node.name)):
			arrivals[str(node.name)] = id
		var door_id: Variant = node.get(&"door_id")
		if door_id is String and door_id != "" and script_path(node).ends_with("/door.gd"):
			doors[door_id] = id


## Frees the script nodes under `root` (outside instances) whose node references point at nodes
## the cut took away (a story variant whose villagers live in another chunk); returns their names.
static func drop_broken_scripts(root: Node) -> PackedStringArray:
	var dropped := PackedStringArray()
	for node: Node in root.find_children("*", "", true, true):
		if node is Node2D or node.get_script() == null or not is_instance_valid(node):
			continue
		for property: Dictionary in node.get_property_list():
			if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var value: Variant = node.get(property["name"])
			var broken: bool = (value is NodePath and not (value as NodePath).is_empty() and not node.has_node(value)) \
					or (typeof(value) == TYPE_OBJECT and not is_instance_valid(value))
			if broken:
				dropped.append(str(node.name))
				node.free()
				break
	return dropped


# --- scenery across chunk edges ----------------------------------------------------------------

## True when `node` is scenery (SCENERY: its scene file's name starts so).
static func is_scenery(node: Node) -> bool:
	if node == null or node.scene_file_path.is_empty():
		return false
	var file := node.scene_file_path.get_file()
	for prefix in SCENERY:
		if file.begins_with(prefix):
			return true
	return false


## True when `node` (at `at` in the world) is scenery (SCENERY) whose picture or collision reaches
## into `area`.
static func overlaps(node: Node2D, at: Vector2, area: Rect2) -> bool:
	if not is_scenery(node):
		return false
	var box := reach(node.scene_file_path)
	if not box.has_area():
		return false
	return (Transform2D(node.rotation, node.scale, node.skew, at) * box).intersects(area)


## The box around its origin that scene `path` draws or collides in: its sprites and collision
## shapes (read once).
static func reach(path: String) -> Rect2:
	if _reaches.has(path):
		return _reaches[path]
	var box := Rect2()
	var packed := load(path) as PackedScene
	if packed != null:
		var instance := packed.instantiate()
		box = bounds(instance, Transform2D.IDENTITY, Rect2())
		instance.free()
	_reaches[path] = box
	return box


static func bounds(node: Node, transform: Transform2D, box: Rect2) -> Rect2:
	var here := transform
	if node is Node2D:
		here = transform * (node as Node2D).transform
	var rect := Rect2()
	if node is Sprite2D:
		rect = (node as Sprite2D).get_rect()
	elif node is CollisionShape2D and (node as CollisionShape2D).shape != null:
		rect = (node as CollisionShape2D).shape.get_rect()
	elif node is CollisionPolygon2D and not (node as CollisionPolygon2D).polygon.is_empty():
		var polygon := (node as CollisionPolygon2D).polygon
		rect = Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			rect = rect.expand(point)
	if rect.has_area():
		var placed := here * rect
		box = placed if not box.has_area() else box.merge(placed)
	for child: Node in node.get_children():
		box = bounds(child, here, box)
	return box


## True when `node` (a prop dragged in from the Scenery dock, at `at` in the world) draws inside
## `area`.
static func picture_overlaps(node: Node2D, at: Vector2, area: Rect2) -> bool:
	if node.scene_file_path.is_empty():
		return false
	var box := PropPictures.bounds(node, Transform2D(node.rotation, node.scale, node.skew, at) * node.transform.affine_inverse())
	return box.intersects(area)
