extends RefCounted
class_name MapMarkers
## The markers the minimap and the world map draw (docs/godot/specs/map.md 3.3), shared by both:
## `MapUi` owns one store and hands it to `Minimap` and `WorldMapWindow`, so a marker set through
## any of the three shows on both views.
##
## A marker is {"point": Vector2, "kind": StringName, "map_id": String}. `point` is in world pixels
## of the old Phaser space (the space of WorldService areas, spawn points, `primary_target().centre`
## and `player.get_centre()`; a plain Node2D's `global_position`, `FeetAnchor.phaser_position(root)`
## for a re-anchored character). `map_id` is the world the marker belongs to (default: the current
## world); markers outlive travel and the minimap draws only the current world's.
##
## Owner: map (game/ui/map).

const Services := preload("res://game/shared/services.gd")

## Phaser's quest waypoint pin (MinimapSurfacePort.ts:84-99).
const KIND_WAYPOINT := &"waypoint"
## Extra kinds (no Phaser counterpart): dark-rimmed dots.
const KIND_NPC := &"npc"
const KIND_EXIT := &"exit"
const KIND_BOSS := &"boss"
const KIND_POINT := &"point"
## Dot kinds: {kind: [radius, colour]}; an unknown kind draws as `point`.
const DOT_STYLES := {
	&"npc": [3.0, Color("#ffb347")],
	&"exit": [3.0, Color("#86f0c3")],
	&"boss": [4.0, Color("#ff6f88")],
	&"point": [3.0, Color("#f5f7ff")],
}
## The waypoint pin's gold (`#ffd277`) and the dark rim every marker gets (`#081022`).
const WAYPOINT_COLOR := Color("#ffd277")
const RIM_COLOR := Color(0.0314, 0.0627, 0.1333, 0.88)
const PIN_RIM_COLOR := Color(0.0314, 0.0627, 0.1333, 0.9)

## A marker was set, moved or cleared.
signal changed

## id -> {"point", "kind", "map_id"}, in insertion order.
var _markers: Dictionary = {}


## Adds or moves marker `id`. `map_id` empty = the current world (WorldService.map_id()).
func set_marker(id: StringName, world_point: Vector2, kind: StringName = KIND_WAYPOINT, map_id: String = "") -> void:
	if id == &"" or not world_point.is_finite():
		return
	var world_id := map_id
	if world_id.is_empty():
		var world := Services.world()
		world_id = world.map_id() if world != null else ""
	var record := {"point": world_point, "kind": kind, "map_id": world_id}
	if _markers.get(id, {}) == record:
		return
	_markers[id] = record
	changed.emit()


func clear_marker(id: StringName) -> void:
	if _markers.erase(id):
		changed.emit()


func clear_markers() -> void:
	if _markers.is_empty():
		return
	_markers.clear()
	changed.emit()


func has_marker(id: StringName) -> bool:
	return _markers.has(id)


## A copy of marker `id` ({"point", "kind", "map_id"}), {} when there is none.
func marker(id: StringName) -> Dictionary:
	return (_markers.get(id, {}) as Dictionary).duplicate()


func marker_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _markers:
		ids.append(id)
	return ids


## The markers of world `map_id`, insertion order: [{"id", "point", "kind", "map_id"}].
func markers_in(map_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in _markers:
		var record: Dictionary = _markers[id]
		if record["map_id"] == map_id:
			var entry := record.duplicate()
			entry["id"] = id
			out.append(entry)
	return out


## Radius and colour of a dot kind (`point` for an unknown one).
static func dot_style(kind: StringName) -> Array:
	return DOT_STYLES.get(kind, DOT_STYLES[KIND_POINT])


## Draws a marker of `kind` at `at` on `canvas` (during its draw): the waypoint pin
## (MinimapSurfacePort.ts:84-99) or a dark-rimmed dot.
static func draw_marker(canvas: CanvasItem, at: Vector2, kind: StringName) -> void:
	if kind == KIND_WAYPOINT:
		draw_pin(canvas, at)
		return
	var style := dot_style(kind)
	var radius: float = style[0]
	canvas.draw_circle(at, radius + 1.25, RIM_COLOR, true, -1.0, true)
	canvas.draw_circle(at, radius, style[1], true, -1.0, true)


## The gold quest pin pointing at `tip`: a dark teardrop from `tip + (0, 1)` around a circle r 5 at
## `tip - (0, 8)` (arc 0.8π -> 0.2π clockwise, over the top), then a gold disc r 3.4. (Phaser's
## extra corner at `tip + (-5, -6)` sits 0.4 px off the arc and would fold the polygon; left out.)
## `rim` replaces the dark teardrop colour (the world map draws it on a dark panel).
static func draw_pin(canvas: CanvasItem, tip: Vector2, rim: Color = PIN_RIM_COLOR) -> void:
	var head := tip + Vector2(0.0, -8.0)
	var points := PackedVector2Array([tip + Vector2(0.0, 1.0)])
	var steps := 18
	for i in steps + 1:
		var angle := PI * 0.8 + (PI * 1.4) * float(i) / float(steps)
		points.append(head + Vector2(cos(angle), sin(angle)) * 5.0)
	canvas.draw_colored_polygon(points, rim)
	canvas.draw_circle(head, 3.4, WAYPOINT_COLOR, true, -1.0, true)
