extends RefCounted
## Where the player appears in a world and how a world is left (Phaser `WorldScene.transitionTo`,
## `leaveAreaThen`, `getEntryAnchor`, `createPlayer`; WorldScene.ts:1005-1016, 1437-1470,
## 1607-1614). main.gd owns the travel itself (`Main.travel_to`).
##
## Phaser leaves an area by fading the picture and the music out for 320 ms, then reloading the
## page with the run handed over in session storage. The new page puts the player at, in order:
## the arrival child of the door named by the handoff, the world's `player-entry-<edge>` marker,
## the `player-spawn` marker; and always snaps that anchor to the centre of the nearest open tile
## (`findSpawnPoint`), so an arrival lands on a tile centre even when the marker is open.
## The run's saved location wins instead when it belongs to the target map and is valid (a bed
## respawn or a loaded save).
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")

## `AREA_LEAVE_FADE_MS` (WorldScene.ts:128): picture and music fade before travelling.
const LEAVE_FADE_MS := 320.0
## The camera fades to rgb(11, 16, 32) = #0b1020 (WorldScene.ts:1013).
const FADE_COLOR := Color("#0b1020")
## Doors add themselves to this group and answer `door_id` and `arrival_point()`.
const DOOR_GROUP := &"door"
const ENTRY_MARKER_PREFIX := "player-entry-"
const EDGES: PackedStringArray = ["north", "east", "south", "west"]


## The old Phaser (centre) position the player arrives at in the registered world for a
## navigation handoff (`RunState.consume_navigation()`); `fallback` when the handoff is empty.
static func arrival_point(navigation: Dictionary, fallback: Vector2) -> Vector2:
	var world := Services.world()
	if world == null or not is_instance_valid(world.world_root):
		return fallback
	if navigation.is_empty():
		return fallback
	var anchor: Variant = null
	var door_id := str(navigation.get("entry_door", ""))
	if not door_id.is_empty():
		anchor = door_arrival(world.world_root, door_id)
	var edge := str(navigation.get("entry_edge", ""))
	if anchor == null and not edge.is_empty():
		anchor = entry_marker(world.world_root, edge)
	if anchor == null:
		anchor = world.player_spawn_marker()
	return world.find_spawn_point(anchor)


## A loaded save's spot (`WorldScene.isValidSavedPosition`): the saved old Phaser centre when it
## belongs to the registered world and stands on an open tile inside it, else null.
static func saved_location(location: Dictionary) -> Variant:
	var world := Services.world()
	if world == null or location.is_empty() or str(location.get("map_id", "")) != world.map_id():
		return null
	var point := Vector2(float(location.get("x", NAN)), float(location.get("y", NAN)))
	var dims := world.dimensions()
	if not point.is_finite() or dims.is_empty():
		return null
	if point.x < 0.0 or point.y < 0.0 or point.x >= float(dims["width"]) or point.y >= float(dims["height"]):
		return null
	var tile_size := float(dims["tile_size"])
	if world.is_solid_tile(floori(point.x / tile_size), floori(point.y / tile_size)):
		return null
	return point


## "up" / "down" / "left" / "right" as a unit vector (a saved facing); down otherwise.
static func facing_vector(facing: String) -> Vector2:
	match facing:
		"up":
			return Vector2.UP
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
	return Vector2.DOWN


## The arrival point of the door `door_id` in `world_root`, or null when no door has that id.
static func door_arrival(world_root: Node, door_id: String) -> Variant:
	var tree := world_root.get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(DOOR_GROUP):
		if not world_root.is_ancestor_of(node):
			continue
		if str(node.get(&"door_id")) == door_id and node.has_method(&"arrival_point"):
			return node.call(&"arrival_point")
	return null


## The global position of the `player-entry-<edge>` marker, or null when the world has none.
static func entry_marker(world_root: Node, edge: String) -> Variant:
	if not edge in EDGES:
		return null
	var marker := world_root.find_child(ENTRY_MARKER_PREFIX + edge, true, false) as Node2D
	return marker.global_position if marker != null else null


## A full-screen fade on its own CanvasLayer (above the world, below the HUD), from `from_alpha`
## to `to_alpha` over `ms` of real time, ignoring pause. Calls `done` at the end; frees itself
## when `free_at_end`.
static func fade(parent: Node, layer_index: int, from_alpha: float, to_alpha: float, ms: float, done: Callable = Callable(), free_at_end: bool = true) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "TravelFade"
	layer.layer = layer_index
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.name = "Fade"
	rect.color = Color(FADE_COLOR, from_alpha)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	parent.add_child(layer)
	var tween := layer.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(rect, "color:a", to_alpha, ms / 1000.0)
	if done.is_valid():
		tween.tween_callback(done)
	if free_at_end:
		tween.tween_callback(layer.queue_free)
	return layer


## Fades every playing AudioStreamPlayer under `root` named like music ("Music*", "Ambience*")
## to silence over `ms` (UniversalSceneWorldController.fadeOutMusic).
static func fade_out_music(root: Node, ms: float) -> void:
	if root == null:
		return
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		var stream_player := node as AudioStreamPlayer
		if stream_player == null or not stream_player.playing:
			continue
		var node_name := String(stream_player.name)
		if not (node_name.begins_with("Music") or node_name.begins_with("Ambience") or String(stream_player.get_parent().name) == "Music"):
			continue
		var tween := stream_player.create_tween()
		tween.tween_property(stream_player, "volume_db", -80.0, ms / 1000.0)
