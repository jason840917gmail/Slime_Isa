extends Node2D
## A rock or crystal shaken loose from the cave's roof by the Crystal Colossus's blows, falling onto
## his floor (game/scripts/crystal_colossus.gd `_drop_debris`; docs/godot/DUNGEONS.md "The plate
## fight"): presentation only, at the spot it will land (`origin`). Its shadow grows there (Fatty's
## clod shadow, game/fattys_lair/clod_shadow.gd) while the liftable's own picture (the kind it lands
## as) falls into it from `fall_px` above over `fall_ms`, `delay_ms` after it is made. The boss lands
## it on the gameplay clock (the hit, the liftable left to throw) and frees this then.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const ClodShadow := preload("res://game/fattys_lair/clod_shadow.gd")

const LIFTABLE_SCENE := "res://game/scenes/objects/liftable.tscn"
## The shadow's radius, and the falling picture's place in the depth order (thrown things' 5: over
## everything on the floor).
const SHADOW_RADIUS := 30.0
const PICTURE_Z := 5
const THROW_ARC_PX := 110.0

## Set before it enters the tree: the liftable kind it falls as, where it lands (global), the wait
## before it starts falling, the fall's length and height; `from` (global, else INF): thrown from
## there instead (the Colossus's rock from his wall), flying in an arc of THROW_ARC_PX.
var kind := "ore-rock"
var origin := Vector2.ZERO
var delay_ms := 0.0
var fall_ms := 750.0
var fall_px := 420.0
var from := Vector2.INF

var _started_at := 0.0
var _picture: Sprite2D
var _rest := Vector2.ZERO


func _ready() -> void:
	global_position = origin
	_started_at = Services.now_ms()
	var shadow := ClodShadow.new()
	shadow.set(&"radius", SHADOW_RADIUS)
	shadow.set(&"grow_ms", delay_ms + fall_ms)
	add_child(shadow)
	var packed := load(LIFTABLE_SCENE) as PackedScene
	var root := packed.instantiate() if packed != null else null
	var visual := root.get_node_or_null(^"Visual") as Sprite2D if root != null else null
	if visual != null:
		_picture = visual.duplicate() as Sprite2D
		_picture.frame = LiftableScript.frame_of(kind, 0)
		_picture.z_index = PICTURE_Z
		_picture.z_as_relative = false
		_picture.visible = false
		_rest = _picture.position
		add_child(_picture)
	if root != null:
		root.free()


func _process(_delta: float) -> void:
	if _picture == null:
		return
	var t := clampf((Services.now_ms() - _started_at - delay_ms) / maxf(1.0, fall_ms), 0.0, 1.0)
	_picture.visible = Services.now_ms() - _started_at >= delay_ms
	if from.is_finite():
		# thrown: from his hand to here, over an arc
		var start := _rest + (from - origin)
		_picture.position = start.lerp(_rest, t) - Vector2(0.0, THROW_ARC_PX * sin(t * PI))
		_picture.rotation = t * TAU * 1.5
		return
	_picture.position = _rest - Vector2(0.0, fall_px * (1.0 - t * t))
