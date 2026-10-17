@tool
extends Node2D
## Scene script of `object.cracked-floor` (game/scenes/objects/cracked-floor.tscn; the Weaver
## Hollow's first cracked floor, room T4, docs/design/2026-10-16-dungeon-weaver-hollow.md; roadmap
## 7.10). A patch of floor carrying the bomb's crack mark (asset/abilities/goo-bomb/
## crack-overlay.webp, the cracked wall's decal, laid flat on whatever floor is painted under it).
## Its CrackedGroundScript child breaks it: a Goo Bomb blast whose ellipse holds the root, a Heavy
## slam on it or a Clod Stomper's slam beside it ("The ground gives way!", the shake, the secret
## jingle, the creak hint naming a blast once the bomb is learned). Broken, a hole into the dark
## (floor-hole.webp, broken flagstones round a black shaft, no ladder) replaces the cracks, and the
## hole is a door of kind `fall`: walking into it the slime spins and shrinks into it, the iris
## closes, and it lands in `target_area_id` on the Node2D named `target_marker` there (or at
## `target_door_id`'s arrival). Nothing needs to lead back: a one-way way down (the Well Room's
## floor into the Roots).
##
## Everything is set on this root in the Inspector: at load it hands `flag_id` and `radius` to the
## CrackedGroundScript, `flag_id` to the StoryVariantScript (which keeps the hole once the flag is
## set, for good) and the target to the hole's DoorScript (`Broken/Door`, its trigger `hole_trigger`
## around the root). The editor shows the cracks, or the hole with `preview_broken`, and the trigger
## as a green box. While intact, dust puffs from the cracks every `DUST_EVERY_S` (the tell;
## presentation, real time).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")

const TRIGGER_PREVIEW := Color(0.3, 1.0, 0.4, 0.35)
## The tell: a few dust puffs from a random point of the cracks, every so often (seconds, real time).
const DUST_EVERY_S := Vector2(2.4, 4.2)
const DUST_TINT := Color("#b9ab92")
const DUST_PUFFS := 3
const DUST_SQUASH := 0.5
## Dust rises from within this share of the crack's half size.
const DUST_SPREAD := 0.55

## Story flag set when it breaks (read at load: broken for good).
@export var flag_id: String = ""
## How near its middle a Heavy slam must land, and where the slime stands to hear it creak.
@export var radius: float = 52.0
@export_group("Hole (once broken)")
## The world the hole drops into, and where in it: the Node2D named `target_marker` (any depth), or
## with `target_door_id` that door's arrival.
@export var target_area_id: String = ""
@export var target_marker: String = ""
@export var target_door_id: String = ""
## The hole's own door id (only needed if a door elsewhere should arrive at it).
@export var door_id: String = ""
## "fall": the slime spins into the dark; "ladder_down": a hole with a ladder (the art has none).
@export_enum("fall", "ladder_down") var kind: String = "fall"
## The hole's doorway around the root (world units): the slime's body touching it while it walks in.
@export var hole_trigger: Rect2 = Rect2(-30.0, -26.0, 60.0, 52.0):
	set(value):
		hole_trigger = value
		queue_redraw()
@export_group("Look")
## The crack decal and the hole picture: their size and their middle from the root (world units).
@export var crack_size: Vector2 = Vector2(124.0, 86.0):
	set(value):
		crack_size = value
		_apply_look()
@export var crack_offset: Vector2 = Vector2.ZERO:
	set(value):
		crack_offset = value
		_apply_look()
@export var hole_size: Vector2 = Vector2(140.0, 105.5):
	set(value):
		hole_size = value
		_apply_look()
@export var hole_offset: Vector2 = Vector2(0.6, 1.5):
	set(value):
		hole_offset = value
		_apply_look()
## The dust puffs while intact.
@export var dust_puffs: bool = true
@export_group("")
## Editor only: show the hole.
@export var preview_broken: bool = false:
	set(value):
		preview_broken = value
		_apply_look()

var _next_dust_s: float = 0.0
var _clock_s: float = 0.0
## The hole's DoorScript, kept: the story variant takes `Broken` out of the tree until the floor
## breaks, where a path no longer finds it.
var _door: Node


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	# Children enter the tree after this root: they read what is handed to them here.
	var ground := get_node_or_null(^"CrackedGroundScript")
	if ground != null:
		ground.set(&"flag_id", flag_id)
		ground.set(&"radius", radius)
	var variant := get_node_or_null(^"StoryVariantScript")
	if variant != null:
		variant.set(&"flag_id", flag_id)
	var door := get_node_or_null(^"Broken/Door/DoorScript")
	if door != null:
		_door = door
		door.set(&"door_id", door_id)
		door.set(&"target_area_id", target_area_id)
		door.set(&"target_door_id", target_door_id)
		door.set(&"target_marker", target_marker)
		door.set(&"kind", kind)
		door.set(&"side", "none")
		door.set(&"trigger_rect", hole_trigger)


func _ready() -> void:
	_apply_look()
	_next_dust_s = randf_range(DUST_EVERY_S.x, DUST_EVERY_S.y)
	set_process(not Engine.is_editor_hint() and dust_puffs)


## The CrackedGroundScript's state: true once it gave way.
func is_broken() -> bool:
	var ground := get_node_or_null(^"CrackedGroundScript")
	return ground != null and bool(ground.call(&"is_broken"))


## The hole's door (DoorScript), whether or not the hole shows yet.
func get_door() -> Node:
	if _door != null and is_instance_valid(_door):
		return _door
	return get_node_or_null(^"Broken/Door/DoorScript")


func _process(delta: float) -> void:
	if is_broken():
		set_process(false)
		return
	_clock_s += delta
	if _clock_s < _next_dust_s:
		return
	_clock_s = 0.0
	_next_dust_s = randf_range(DUST_EVERY_S.x, DUST_EVERY_S.y)
	var half := crack_size * 0.5 * DUST_SPREAD
	var angle := randf() * TAU
	var at := global_position + crack_offset + Vector2(cos(angle) * half.x, sin(angle) * half.y) * sqrt(randf())
	AbilityFx.debris(at, DUST_TINT, 0, DUST_PUFFS, DUST_SQUASH)


# --- the look ------------------------------------------------------------------------------------

func _apply_look() -> void:
	if not is_inside_tree():
		return
	var crack := get_node_or_null(^"Intact/Crack") as Sprite2D
	var hole := get_node_or_null(^"Broken/Hole") as Sprite2D
	if Engine.is_editor_hint():
		var intact_root := get_node_or_null(^"Intact") as CanvasItem
		var broken_root := get_node_or_null(^"Broken") as CanvasItem
		if intact_root != null:
			intact_root.visible = not preview_broken
		if broken_root != null:
			broken_root.visible = preview_broken
	if crack != null:
		_fit(crack, crack_size, crack_offset)
	if hole != null:
		_fit(hole, hole_size, hole_offset)
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
		draw_rect(hole_trigger, TRIGGER_PREVIEW, false, 2.0)
