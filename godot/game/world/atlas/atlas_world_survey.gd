extends RefCounted
## What the world atlas (world_atlas.gd) checks about a world scene, read from the saved file
## without instancing it (PackedScene.get_state()): its size from the `world-definition` node, its
## exits (each `world_exit.gd` node with its Area2D's shapes), the names of its nodes (arrival
## markers) and the layout hash a placeholder world records on its root
## (`metadata/world_map_layout_hash`, written by godot/tools/build_region_worlds.gd).
##
## Only the scene's own nodes count: an exit inside an instanced sub-scene is not seen.
##
## Owner: world (atlas).

const SCENE_INDEX := "res://game/scenes/scene_index.json"
const WORLDS_DIR := "res://game/scenes/worlds/"
const WORLD_PREFIX := "world."
const EXIT_SCRIPT := "res://game/scripts/world_exit.gd"
const DEFINITION_SCRIPT := "res://game/scripts/world_definition.gd"
const HASH_META := "metadata/world_map_layout_hash"
const EDGES: PackedStringArray = ["north", "east", "south", "west"]
## Each edge's step outward, in EDGES order.
const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## An exit closer than this to an edge of its world sits on that edge (world units).
const EDGE_SLACK := 1.0


## The scene index (scene id -> path), {} when it cannot be read.
static func scene_index() -> Dictionary:
	if not FileAccess.file_exists(SCENE_INDEX):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENE_INDEX))
	return parsed if parsed is Dictionary else {}


## The scene of world `map_id`: its scene index entry `world.<id>`, else the usual place
## (game/scenes/worlds/<id>.tscn); "" when neither exists.
static func scene_path(map_id: String, index: Dictionary) -> String:
	if map_id == "":
		return ""
	var indexed := str(index.get(WORLD_PREFIX + map_id, ""))
	if indexed != "" and ResourceLoader.exists(indexed):
		return indexed
	var usual := WORLDS_DIR + map_id + ".tscn"
	return usual if ResourceLoader.exists(usual) else ""


## The opposite of an edge name ("" for anything else).
static func opposite(edge: String) -> String:
	var at := EDGES.find(edge)
	return EDGES[(at + 2) % 4] if at >= 0 else ""


static func edge_step(edge: String) -> Vector2i:
	var at := EDGES.find(edge)
	return STEPS[at] if at >= 0 else Vector2i.ZERO


## {map_id, columns, rows, tile_size, size (world units), hash (int, or null when the root has
## none), names ({node name: true}), exits: [{name, rect (world units), edge ("" when on no edge),
## target, entry, entry_marker, gate (requiredItemId, "" when open)}]}.
static func read(packed: PackedScene) -> Dictionary:
	var state := packed.get_state()
	var nodes := {}
	var names := {}
	for i in state.get_node_count():
		var props := {}
		for p in state.get_node_property_count(i):
			props[state.get_node_property_name(i, p)] = state.get_node_property_value(i, p)
		var path := str(state.get_node_path(i))
		nodes[path] = {"parent": str(state.get_node_path(i, true)) if i > 0 else "", "props": props}
		names[str(state.get_node_name(i))] = true
	var out := {
		"map_id": "", "columns": 0, "rows": 0, "tile_size": 0, "size": Vector2.ZERO,
		"hash": null, "names": names, "exits": [],
	}
	var root_props: Dictionary = nodes.get(".", {}).get("props", {})
	if root_props.has(HASH_META):
		out["hash"] = int(root_props[HASH_META])
	var exit_nodes: Array[String] = []
	for path: String in nodes:
		var props: Dictionary = nodes[path]["props"]
		var script := _script_path(props)
		if script == DEFINITION_SCRIPT:
			out["map_id"] = str(props.get("map_id", ""))
			out["columns"] = int(props.get("columns", 0))
			out["rows"] = int(props.get("rows", 0))
			out["tile_size"] = int(props.get("tile_size", 0))
		elif script == EXIT_SCRIPT:
			exit_nodes.append(path)
	if int(out["columns"]) <= 0 or int(out["tile_size"]) <= 0:
		_size_from_ground(nodes, out)
	out["size"] = Vector2(int(out["columns"]), int(out["rows"])) * int(out["tile_size"])
	for path in exit_nodes:
		out["exits"].append(_exit(nodes, path, out["size"]))
	return out


static func _script_path(props: Dictionary) -> String:
	var script := props.get("script") as Script
	return script.resource_path if script != null else ""


## Worlds without a definition size: the ground layer's `columns` / `rows` metadata, 64 px tiles.
static func _size_from_ground(nodes: Dictionary, out: Dictionary) -> void:
	for path: String in nodes:
		var props: Dictionary = nodes[path]["props"]
		if props.has("metadata/columns") and props.has("metadata/rows"):
			out["columns"] = int(props["metadata/columns"])
			out["rows"] = int(props["metadata/rows"])
			out["tile_size"] = 64 if int(out["tile_size"]) <= 0 else out["tile_size"]
			return


static func _exit(nodes: Dictionary, path: String, size: Vector2) -> Dictionary:
	var props: Dictionary = nodes[path]["props"]
	var area := str(nodes[path]["parent"])
	var area_path: Variant = props.get("area")
	if area_path is NodePath and str(area_path) != "" and str(area_path) != "..":
		area = _resolve(path, str(area_path))
	var origin := _position_in_world(nodes, area)
	var rect := Rect2()
	for child: String in nodes:
		var child_props: Dictionary = nodes[child]["props"]
		if str(nodes[child]["parent"]) != area or not child_props.get("shape") is Shape2D:
			continue
		var shape_rect := (child_props["shape"] as Shape2D).get_rect()
		shape_rect.position += origin + (child_props.get("position", Vector2.ZERO) as Vector2)
		rect = shape_rect if not rect.has_area() else rect.merge(shape_rect)
	if not rect.has_area():
		rect = Rect2(origin - Vector2(32, 32), Vector2(64, 64))
	var gate: Variant = props.get("gate", {})
	return {
		"name": area.get_file(),
		"rect": rect,
		"edge": edge_of(rect, size),
		"target": str(props.get("target_area_id", "")),
		"entry": str(props.get("entry", "")),
		"entry_marker": str(props.get("entry_marker", "")),
		"gate": str((gate as Dictionary).get("requiredItemId", "")) if gate is Dictionary else "",
	}


## The edge of a world of `size` that `rect` lies along (no thicker across than along it; the
## thinnest way for a strip along a whole side, which also touches two others), "" when none.
static func edge_of(rect: Rect2, size: Vector2) -> String:
	var best := ""
	var thinnest := INF
	var touches := [
		rect.position.y <= EDGE_SLACK, rect.end.x >= size.x - EDGE_SLACK,
		rect.end.y >= size.y - EDGE_SLACK, rect.position.x <= EDGE_SLACK,
	]
	for i in EDGES.size():
		var thickness := rect.size.y if i % 2 == 0 else rect.size.x
		var length := rect.size.x if i % 2 == 0 else rect.size.y
		if touches[i] and thickness <= length and thickness < thinnest:
			thinnest = thickness
			best = EDGES[i]
	return best


## A node's position in its world: the positions of it and its parents added up (exits are never
## rotated or scaled).
static func _position_in_world(nodes: Dictionary, path: String) -> Vector2:
	var at := Vector2.ZERO
	var current := path
	while current != "" and current != "." and nodes.has(current):
		at += nodes[current]["props"].get("position", Vector2.ZERO) as Vector2
		current = str(nodes[current]["parent"])
	return at


## `relative` (a NodePath from the node at `from`) as a scene path.
static func _resolve(from: String, relative: String) -> String:
	var parts := PackedStringArray() if from == "." else from.split("/")
	for part in relative.split("/"):
		if part == "..":
			if not parts.is_empty():
				parts.remove_at(parts.size() - 1)
		elif part != ".":
			parts.append(part)
	return "." if parts.is_empty() else "/".join(parts)
