@tool
extends Node2D
class_name HazardDeck
## Floor that holds the slime over a hazard (docs/godot/DUNGEONS.md "The void, slabs and spikes"):
## a landing in a slab bridge, a ledge. The base of falling_slab.gd, drawbridge.gd and
## shadow_path.gd. A deck is the rectangle `size` from its position, at the elevation `level` of the
## rim around its hazard. HazardWatch (hazard_watch.gd) asks every deck in the group `hazard_deck`:
## `deck_rects()` (global), `holds_at(point)` (a standing slab, a lowered bridge), `is_safe_ground()`
## (a place a fall may put the slime back on: not a slab) and `touch()` (the slime's body is on it).
##
## Over an elevation hole a deck opens a passage at its `level` (Elevation.open_passage) while it
## holds (hazard_watch.gd `_sync_passages`, from when its world is built; a drawbridge once lowered),
## so the slime walks onto it from the rim; a slab that falls closes it again until it is back, and
## the floor's rim beside the gap holds the slime (a push drops it, the ledge drop). The passage's
## sides where no floor of its level goes on hold the slime as a rim (docs/godot/ELEVATION.md
## "Painting collision", automatic or painted). Its `z_index` (DECK_Z, set in `_ready`) is not stored
## in the scene (`_validate_property`).
## While it holds, its rectangles are ground of its `level` in the terrain's depth map
## (ElevationOcclusion.add_occluder, as the fences' silhouettes): a body of a lower level under it
## hides behind it (its ghost shows) as behind higher ground; a fallen slab or a raised drawbridge
## hides nothing. In the editor it draws its outline.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const ElevationOcclusion := preload("res://game/world/elevation/elevation_occlusion.gd")

const GROUP := &"hazard_deck"
const EDITOR_EDGE := Color(0.4, 0.9, 1.0, 0.9)
const DECK_Z := -1
## A landing's flagstone (`draw_floor`): the slab sheet's whole slab, a cell at a time; these
## colours without the picture.
const FLOOR_ART := "res://asset/MAPS/objects/dungeon/slab-2x1.webp"
const FLOOR := Color("#7d766b")
const FLOOR_EDGE := Color("#4b443c")

## The deck (world units from its position).
@export var size: Vector2 = Vector2(64, 64):
	set(value):
		size = value
		queue_redraw()
## The elevation level it holds bodies at (the rim's; 0 without elevation).
@export var level: int = 0
## A fall may put the slime back here.
@export var safe: bool = true
## Draws a plain flagstone over its rectangle (a landing); off for decks that draw their own look.
@export var draw_floor: bool = true:
	set(value):
		draw_floor = value
		queue_redraw()

var _floor_picture: Texture2D
## Its picture in the depth map while it holds (`_sync_depth`), and the map it is in.
var _depth: MeshInstance2D
var _depth_map: ElevationOcclusion


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func _ready() -> void:
	z_index = DECK_Z
	if Engine.is_editor_hint():
		return
	var watch_script := load("res://game/dungeon/hazard_watch.gd") as GDScript
	watch_script.call(&"ensure", self)
	if opens_passage_at_build():
		watch_script.call(&"open_passages_for", self)
	# every frame (the subclasses keep `_process` for their own): the depth map may be built after
	# this deck, and built again; a slab falls and comes back
	get_tree().process_frame.connect(_sync_depth)


## `z_index` is DECK_Z, set in `_ready`: not stored, so opening a world in the editor never writes it.
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "z_index":
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE


## Puts its rectangles in the world's depth map while it holds, takes them out when it does not.
func _sync_depth() -> void:
	var world := Services.world()
	var elevation: Node2D = world.elevation if world != null and world.elevation != null and is_instance_valid(world.elevation) else null
	var occlusion: ElevationOcclusion = elevation.get(&"occlusion") if elevation != null else null
	var shown := _depth != null and is_instance_valid(_depth) and _depth.is_inside_tree() and _depth_map == occlusion
	var wanted := is_inside_tree() and holds() and occlusion != null and is_instance_valid(occlusion) and occlusion.texture != null
	if shown == wanted:
		return
	if shown:
		_depth_map.remove_occluder(_depth)
		_depth = null
		return
	# ground of its level (no wall above it): a body below whose feet lie behind its edge hides
	var colour := ElevationOcclusion.encode(deck_level(), 0.0)
	var vertices := PackedVector2Array()
	var colours := PackedColorArray()
	for rect: Rect2 in deck_rects():
		var a := elevation.to_local(rect.position)
		var b := elevation.to_local(Vector2(rect.end.x, rect.position.y))
		var c := elevation.to_local(rect.end)
		var d := elevation.to_local(Vector2(rect.position.x, rect.end.y))
		vertices.append_array(PackedVector2Array([a, b, c, a, c, d]))
		for i in 6:
			colours.append(colour)
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_depth = occlusion.add_occluder(mesh, null)
	_depth_map = occlusion


## Its rectangles (global).
func deck_rects() -> Array[Rect2]:
	return [Rect2(global_position, size)]


## True when it holds a body whose feet are at `point` (global).
func holds_at(point: Vector2) -> bool:
	if not holds():
		return false
	for rect: Rect2 in deck_rects():
		if rect.has_point(point):
			return true
	return false


## True while it holds (a standing slab, a lowered bridge).
func holds() -> bool:
	return true


func is_safe_ground() -> bool:
	return safe


func deck_level() -> int:
	return level


## The slime's body is on it (a slab starts to give).
func touch() -> void:
	pass


## True when its passage over an elevation hole opens with the world (not a raised drawbridge).
func opens_passage_at_build() -> bool:
	return true


func _draw() -> void:
	if draw_floor:
		var area := Rect2(Vector2.ZERO, size)
		if _floor_picture == null:
			_floor_picture = SheetSprite.load_picture(FLOOR_ART)
		if _floor_picture != null:
			# The whole flagstone (the slab sheet's frame 0), a cell at a time.
			var cell := Vector2(_floor_picture.get_width() * 0.5, _floor_picture.get_height())
			var x := 0.0
			while x < size.x - 0.5:
				var y := 0.0
				while y < size.y - 0.5:
					var piece := Rect2(Vector2(x, y), Vector2(minf(64.0, size.x - x), minf(64.0, size.y - y)))
					draw_texture_rect_region(_floor_picture, piece, Rect2(Vector2.ZERO, cell * piece.size / 64.0))
					y += 64.0
				x += 64.0
		else:
			draw_rect(area, FLOOR)
			draw_rect(area.grow(-2.0), FLOOR_EDGE, false, 2.0)
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, size), EDITOR_EDGE, false, 2.0)
