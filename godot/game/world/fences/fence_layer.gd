@tool
extends TileMapLayer
## The one painted fence layer of a world (docs/godot/FENCES.md): each tile is a fence post whose
## picture chooses its style and the neighbour it joins (an arrow, or every neighbour); the
## fences (fences.gd) draw the posts and rails and give them shadows and collision. They do not
## paint or alter elevation rims.
##
## In the editor the fences follow the paint at once: a stroke rebuilds only the fences (on the
## Elevation's grid and depth map when the world has one, else on flat ground). The layer's own
## squares are only a painting aid: hide the layer (eye icon) to see the result. The game hides it
## and the Elevation (or, in a flat world, Elevation.mount) mounts the fences with their collision.
##
## Divider gates (docs/godot/FENCES.md "Dungeon dividers"): a cell painted with a gate tile
## (`lair-divider-eye`, `lair-divider-pen`) draws no post (the fences join the posts beside it to the
## gate's block); the layer keeps a divider gate object (`object.divider-gate`) on it under the
## scene's `Objects`, at any depth (`sync_gates`, in the editor as you paint, only in the scene being
## edited): an untagged one already standing there (a converted latch door, with its gate id and
## records) is adopted, else one is made with a record of its own (`gate_id` `<room>-gate-<x>-<y>`,
## `map_id` the world's record id), and the gate turns with its line (DividerGate `fit_to_line`). A
## gate whose tile is erased is let go (game/world/painted_objects.gd `retire`): removed when the
## layer made it and nothing of it was changed since, else kept, untagged, with a warning, and
## adopted again when its tile comes back.
##
## Owner: world (fences).

const Elevation := preload("res://game/world/elevation/elevation.gd")
const Fences := preload("res://game/world/fences/fences.gd")
const PaintedObjects := preload("res://game/world/painted_objects.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const GATE_SCENE := "res://game/scenes/objects/dungeon/divider-gate.tscn"
## The metas a gate the layer keeps carries: its cell ("x,y") and its tile's style.
const GATE_CELL_META := &"fence_gate_cell"
const GATE_STYLE_META := &"fence_gate_style"
const GATE_TAGS: Array[StringName] = [GATE_CELL_META, GATE_STYLE_META]
## The gate's record lives on this child (game/scripts/gate.gd).
const GATE_SCRIPT := "GateScript"
## How near (units) an untagged gate must stand to a gate cell's foot to be adopted.
const ADOPT_REACH := 40.0

var _queued := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false
		return
	changed.connect(_queue_rebuild)
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var ground := Elevation.find_ground(self)
	if ground == null:
		return
	var elevation := ground.get_node_or_null(NodePath(Elevation.NODE_NAME)) as Elevation
	if elevation == null or elevation.grid == null:
		# No elevation drawing yet (or a flat world): the full mount builds what there is.
		Elevation.mount(ground, false)
	else:
		elevation.fences = Fences.mount(ground, elevation, elevation.grid, elevation.occlusion, false)
	# only in the scene being edited: a world shown inside another scene (the world atlas) keeps its
	# own gates, and gets none made in that scene
	var edited := get_tree().edited_scene_root
	if edited != null and (edited == self or edited.is_ancestor_of(self)):
		sync_gates()


## Keeps a divider gate on every cell painted with a gate tile (Fences.GATE_STYLES) and lets go of the
## gates whose tile is gone; returns the gates made.
func sync_gates() -> int:
	var room := get_parent()
	if room == null or tile_set == null or not tile_set.has_custom_data_layer_by_name(Fences.STYLE_DATA_LAYER):
		return 0
	var wanted := {}
	for cell: Vector2i in get_used_cells():
		var data := get_cell_tile_data(cell)
		var style := str(data.get_custom_data(Fences.STYLE_DATA_LAYER)) if data != null else ""
		if Fences.GATE_STYLES.has(style):
			wanted["%d,%d" % [cell.x, cell.y]] = [cell, style]
	var objects := room.get_node_or_null(^"Objects") as Node2D
	if objects == null:
		if wanted.is_empty():
			return 0
		objects = Node2D.new()
		objects.name = "Objects"
		objects.y_sort_enabled = true
		room.add_child(objects)
		objects.owner = _owner_node(room)
	# gates anywhere under Objects (moved into a folder of their own too)
	var standing := objects.find_children("*", "Node2D", true, false)
	var tagged := {}
	for node: Node in standing:
		if node.has_meta(GATE_CELL_META):
			tagged[str(node.get_meta(GATE_CELL_META))] = node
	var made := 0
	for key: String in wanted:
		var cell: Vector2i = wanted[key][0]
		var style: String = wanted[key][1]
		var kind := str(Fences.GATE_STYLES[style])
		var foot := to_global(map_to_local(cell))
		var node: Node = tagged.get(key)
		if node == null:
			for candidate: Node in standing:
				if not is_instance_valid(candidate) or candidate.has_meta(GATE_CELL_META) or candidate.scene_file_path != GATE_SCENE:
					continue
				if (candidate as Node2D).global_position.distance_to(foot) <= ADOPT_REACH:
					node = candidate
					break
		var made_now := false
		if node == null:
			var packed := load(GATE_SCENE) as PackedScene
			node = packed.instantiate()
			var base := "divider-gate-%d-%d" % [cell.x, cell.y]
			node.name = base
			var n := 2
			while objects.has_node(NodePath(String(node.name))):
				node.name = "%s-%d" % [base, n]
				n += 1
			objects.add_child(node)
			node.owner = _owner_node(room)
			# a record of its own: two painted gates never open together
			var gate_script := node.get_node_or_null(GATE_SCRIPT)
			if gate_script != null:
				gate_script.set(&"gate_id", "%s-gate-%d-%d" % [room.name, cell.x, cell.y])
				gate_script.set(&"map_id", DungeonState.record_map_id(node))
			made += 1
			made_now = true
		if node == null:
			continue
		# what the layer itself sets (its place, its kind) keeps a gate it made untouched
		var untouched := made_now or PaintedObjects.is_untouched(node)
		node.set_meta(GATE_CELL_META, key)
		node.set_meta(GATE_STYLE_META, style)
		var gate := node as Node2D
		if not gate.global_position.is_equal_approx(foot):
			gate.global_position = foot
		if str(node.get(&"kind")) != kind:
			node.set(&"kind", kind)
		if node.has_method(&"fit_to_line"):
			node.call(&"fit_to_line")
		if untouched:
			PaintedObjects.remember(node)
		tagged.erase(key)
	for key: String in tagged:
		PaintedObjects.retire(tagged[key] as Node, GATE_TAGS, "FenceLayer")
	return made


func _owner_node(room: Node) -> Node:
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
		return get_tree().edited_scene_root
	return room.owner if room.owner != null else room
