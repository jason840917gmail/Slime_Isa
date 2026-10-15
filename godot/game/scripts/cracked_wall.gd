@tool
extends Node2D
## Scene script of `object.cracked-wall` (game/scenes/objects/cracked-wall.tscn; bomb-lantern-and-
## secrets design section 3, the Goo Bomb's lock; BODY_SHAPES.md "Goo Bomb"). A weak spot set on a
## real wall that is already there: a cliff face of the world's elevation (any wall style) or a
## built wall. It adds no wall of its own: the wall's own collision blocks the way.
##
## - **Intact:** a crack decal over the wall face (`Crack`: asset/abilities/goo-bomb/
##   crack-overlay.webp, dark cracks on full transparency, drawn as it is). Weapons, throws and the
##   Slam clink off its hurtbox (`DamageArea`) with `refusal_text`.
## - **Blown** (a Goo Bomb blast whose ellipse holds the root, `receive_blast`; group
##   `blast_targets`): the hole decal (`Hole`: hole-overlay.webp, a dark opening with a rim of rocks
##   and rubble at its foot, greyscale, tinted to the rock it sits on) replaces the cracks, and the
##   passage opens: the elevation opens `passage` (relative to the root, world units) for bodies of
##   `passage_level` (Elevation.open_passage: the wall stays drawn, the slime walks into the hole and
##   shows as a ghost behind the rock). On a built wall without elevation, `blocker` (an optional
##   StaticBody2D, e.g. a wall piece) is removed instead. The opening is saved as the story flag
##   `flag_id` (with its own story variant, a nook's chest can appear with it). With a door target
##   (the "Door (once blown)" group) the hole is a door to another world, a cave or a room, as in
##   Zelda: pushing into it travels (a DoorScript of kind "opening" whose trigger is the `passage`
##   rect: the slime walks into the hole and keeps pushing toward the door's side).
##
## Place it in the editor: put the root at the wall's foot (the ground line under the face), the
## middle of where the hole should be, then size and move the two decals (`crack_size`,
## `crack_offset`, `hole_size`, `hole_offset`, in world units) until they sit on the face; the
## `passage` rect is drawn as a green box. `preview_blown` shows the hole in the editor. With
## `hole_tint` at alpha 0 the hole takes the colour of the wall style it sits on (the average of
## its wall art, times `tint_gain`); any other colour is used as it is.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")
const DoorScriptType := preload("res://game/scripts/door.gd")

const BREAK_TEXT := "The wall caves in!"
const WALL_ART := "res://asset/MAPS/elevation/%s-wall.png"
const DEFAULT_STYLE := "meadow-rock"
const DEBRIS_TINT := Color("#8a7a66")
const PASSAGE_PREVIEW := Color(0.3, 1.0, 0.4, 0.35)
## Samples per side of the wall art when its rock colour is read.
const ROCK_SAMPLES := 48

## Story flag set when it is blown (and read at load: blown for good).
@export var flag_id: String = ""
## Said when a weapon, a throw or the Slam hits it.
@export var refusal_text: String = "Too deep for a hammer. It needs a blast."
## The crack decal: its size and its middle from the root (world units).
@export var crack_size: Vector2 = Vector2(96.0, 115.0):
	set(value):
		crack_size = value
		_apply_look()
@export var crack_offset: Vector2 = Vector2(0.0, -62.0):
	set(value):
		crack_offset = value
		_apply_look()
## The hole decal: its size and its middle from the root (world units).
@export var hole_size: Vector2 = Vector2(100.0, 120.0):
	set(value):
		hole_size = value
		_apply_look()
@export var hole_offset: Vector2 = Vector2(0.0, -52.0):
	set(value):
		hole_offset = value
		_apply_look()
## The hole's rock colour; alpha 0 = the wall style's (see the class notes).
@export var hole_tint: Color = Color(0.0, 0.0, 0.0, 0.0):
	set(value):
		hole_tint = value
		_apply_look()
@export var tint_gain: float = 1.1:
	set(value):
		tint_gain = value
		_apply_look()
## What opens (relative to the root, world units) and for which height level.
@export var passage: Rect2 = Rect2(-30.0, -60.0, 60.0, 60.0):
	set(value):
		passage = value
		queue_redraw()
@export var passage_level: int = 0
## A built wall's piece to remove when it is blown (optional; the elevation's walls need none).
@export var blocker: Node
@export_group("Door (once blown)")
## With a target the blown hole is a door (DoorScript): the slime in the hole (its body touching the
## `passage` rect) pushing toward `door_side` for `worldNavigation.doorPushMs` travels to
## `target_area_id`'s door `target_door_id`; coming back, the slime arrives at `arrival_offset` in
## front of it (this wall's `door_id`). Without a target it is a plain opening.
@export var door_id: String = ""
@export var target_area_id: String = ""
@export var target_door_id: String = ""
@export var arrival_offset: Vector2 = Vector2(0.0, 52.0)
## The door's side (door.gd pairing rule): a hole in a wall the slime walks up into is a north door,
## so its target door is the cave's south door, and the slime comes back out facing down.
@export_enum("none", "north", "south", "east", "west") var door_side: String = "north"
@export_group("")
## Editor only: show the blown look.
@export var preview_blown: bool = false:
	set(value):
		preview_blown = value
		_apply_look()

var _broken: bool = false
var _passage_open: bool = false
var _tint_cache: Dictionary = {}
var _wait_frames: int = 0
var _door: DoorScriptType
## Physics frames a blown wall waits for the world's elevation before it gives up on it.
const ELEVATION_WAIT_FRAMES := 120


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(BlastBarrier.GROUP)
	var run := Services.run()
	_broken = not flag_id.is_empty() and run != null and run.has_flag(flag_id)


func _ready() -> void:
	_apply_look()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	var area := get_node_or_null(^"DamageArea") as Area2D
	if _broken:
		_remove_blocker()
		_make_door()
		if area != null:
			area.queue_free()
	else:
		BlastBarrier.register(area, self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		BlastBarrier.unregister(get_node_or_null(^"DamageArea") as Area2D)


## A blown wall opens its passage once the world's elevation is there (it mounts after the world's
## nodes are ready); the tint follows the wall style once it can be read.
func _physics_process(_delta: float) -> void:
	if not _broken:
		set_physics_process(false)
		return
	var world := Services.world()
	if world == null:
		return
	if not _passage_open:
		if world.elevation != null:
			world.elevation.open_passage(Rect2(global_position + passage.position, passage.size), passage_level)
			_passage_open = true
			_apply_look()
		else:
			# No elevation (yet): a world without one has only the blocker to shut the way.
			_wait_frames += 1
			if _wait_frames >= ELEVATION_WAIT_FRAMES:
				_passage_open = true
	if _passage_open:
		set_physics_process(false)


## The door in the hole (DoorScript, with its "arrival" point in front of the wall), when the wall
## has a target and is blown.
func _make_door() -> void:
	if target_area_id.is_empty() or _door != null:
		return
	var holder := Node2D.new()
	holder.name = "Door"
	add_child(holder)
	var arrival := Node2D.new()
	arrival.name = "arrival"
	arrival.position = arrival_offset
	holder.add_child(arrival)
	_door = DoorScriptType.new()
	_door.name = "DoorScript"
	_door.door_id = door_id
	_door.target_area_id = target_area_id
	_door.target_door_id = target_door_id
	_door.side = door_side
	_door.kind = "opening"
	_door.trigger_rect = passage
	var world := Services.world()
	if world != null:
		_door.map_id = world.map_id()
	holder.add_child(_door)


func is_broken() -> bool:
	return _broken


func blast_point() -> Vector2:
	return global_position


## A Goo Bomb blast (game/player/abilities/goo_blast.gd) reached it: it gives way for good.
func receive_blast(_hit: Dictionary) -> bool:
	if _broken:
		return false
	_broken = true
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	BlastBarrier.unregister(get_node_or_null(^"DamageArea") as Area2D)
	var area := get_node_or_null(^"DamageArea")
	if area != null:
		area.queue_free()
	_remove_blocker()
	_make_door()
	_apply_look()
	BlastBarrier.give_way(global_position - Vector2(0.0, 8.0), BREAK_TEXT, _rock_tint(), 16, 10)
	set_physics_process(true)
	return true


# --- the damage contract (only refusals: blasts come through receive_blast) ----------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _broken}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	return BlastBarrier.refuse(global_position + crack_offset, refusal_text)


# --- the look ------------------------------------------------------------------------------------

func _apply_look() -> void:
	if not is_inside_tree():
		return
	var blown := _broken or (Engine.is_editor_hint() and preview_blown)
	var crack := get_node_or_null(^"Crack") as Sprite2D
	var hole := get_node_or_null(^"Hole") as Sprite2D
	if crack != null:
		crack.visible = not blown
		_fit(crack, crack_size, crack_offset)
	if hole != null:
		hole.visible = blown
		_fit(hole, hole_size, hole_offset)
		hole.modulate = _rock_tint() if hole_tint.a <= 0.0 else hole_tint
	queue_redraw()


## Scales `sprite` (centred) to `size` world units, its middle at `offset`.
static func _fit(sprite: Sprite2D, size: Vector2, offset: Vector2) -> void:
	sprite.centered = true
	sprite.position = offset
	if sprite.texture != null:
		var art := sprite.texture.get_size()
		if art.x > 0.0 and art.y > 0.0:
			sprite.scale = size / art


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(passage, PASSAGE_PREVIEW, false, 2.0)


## The colour of the wall style under the hole (its wall art's average, times `tint_gain`).
func _rock_tint() -> Color:
	var style := _wall_style()
	if not _tint_cache.has(style):
		var path := WALL_ART % style
		var colour := DEBRIS_TINT
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			var image := texture.get_image() if texture != null else null
			if image != null:
				if image.is_compressed():
					image.decompress()
				colour = _rock_colour(image)
		_tint_cache[style] = colour
	var base: Color = _tint_cache[style]
	return Color(minf(1.0, base.r * tint_gain), minf(1.0, base.g * tint_gain), minf(1.0, base.b * tint_gain), 1.0)


## The colour of a wall art's stones: the mean of the brighter half of its opaque pixels (sampled
## on a grid), so the dark joints do not drag it down.
static func _rock_colour(image: Image) -> Color:
	var size := image.get_size()
	var step := maxi(1, mini(size.x, size.y) / ROCK_SAMPLES)
	var samples: Array[Color] = []
	for y in range(0, size.y, step):
		for x in range(0, size.x, step):
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				samples.append(c)
	if samples.is_empty():
		return DEBRIS_TINT
	samples.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() > b.get_luminance())
	var keep := maxi(1, samples.size() / 2)
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	for i in keep:
		sum += samples[i]
	return Color(sum.r / keep, sum.g / keep, sum.b / keep, 1.0)


## The wall style of the elevation wall just above the root (its band's), else meadow rock.
func _wall_style() -> String:
	var elevation := _elevation()
	if elevation == null:
		return DEFAULT_STYLE
	var grid: Variant = elevation.get(&"grid")
	var styles: Variant = elevation.get(&"band_styles")
	if grid == null or not (styles is PackedStringArray):
		return DEFAULT_STYLE
	var local := (global_position + Vector2(0.0, -20.0) - (elevation as Node2D).global_position) / float(elevation.get(&"cell"))
	var tri := int(grid.call(&"tri_at", local))
	if tri < 0:
		return DEFAULT_STYLE
	var band := int((grid.get(&"tri_band") as PackedInt32Array)[tri])
	var list: PackedStringArray = styles
	return list[band] if band >= 0 and band < list.size() and not list[band].is_empty() else DEFAULT_STYLE


func _elevation() -> Node:
	if not Engine.is_editor_hint():
		var world := Services.world()
		return world.elevation if world != null else null
	var root := get_tree().edited_scene_root if get_tree() != null else null
	if root == null:
		return null
	var found := root.find_child("Elevation", true, false)
	return found


func _remove_blocker() -> void:
	if blocker != null and is_instance_valid(blocker):
		blocker.queue_free()
		blocker = null
