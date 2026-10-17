extends Node2D
class_name CrystalVeil
## The Crystal Veil (docs/godot/DUNGEONS.md "The Crystal Mine (built)"; the design's dark room 5:
## "a brazier holds the Colossus's dark crystal back, but only while it burns"): a wall of the
## Colossus's smoky black crystal with a cold violet sheen across a passage, a Lantern lock unlike
## the Caverns' blue scenery crystal. It shrinks back from fire light:
##
## - **Open while a brazier burns:** while any brazier of `braziers` is lit (a candle.gd, burning its
##   `burn_ms`), the crystal sinks into a low ring of stubs and the way is open; when the last one
##   goes out it grows back over `grow_ms`, from both ends toward the middle.
## - **Never traps:** a slime standing in the veil as it grows is pushed out to the nearer side.
## - **The wrong tools clink:** a weapon, a throw or a Roll on it is refused with `refusal_text`
##   (its hurtbox, `DamageArea`, is a damage receiver that takes nothing).
##
## The veil is `size` wide (along x, world units) and stands on this node's y (its foot line); its
## art (`asset/MAPS/props/mine/256x256-tile_2x1-crystal-veil.webp`: grown, receded) is laid along it.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

const ART := "res://asset/MAPS/props/mine/256x256-tile_2x1-crystal-veil.webp"
const ART_SCALE := 0.42
## One picture covers this much of the veil's width (world units).
const PIECE_WIDTH := 96.0
const FRAME_GROWN := 0
const FRAME_LOW := 1
const RULE := {"priority": 0, "damageMultiplier": 1}
const CUE_CLINK := &"HitBlocked"
const CUE_SHRINK := &"GulpWearOff"
const CUE_GROW := &"BreakGlass"
const TEXT_RISE := 110.0
const TEXT_MS := 2400.0
const HINT_EVERY_MS := 2500.0
## The barrier's depth (along y, world units) and how far past it a trapped slime is pushed.
const DEPTH := 40.0
const PUSH_OUT_PX := 36.0

@export var size: float = 384.0
@export var braziers: Array[NodePath] = []
@export var grow_ms: float = 700.0
@export var refusal_text: String = "Cold, dark crystal. It shrinks from fire."

var _open: bool = false
var _pieces: Array[Sprite2D] = []
var _barrier: StaticBody2D
var _shape: CollisionShape2D
var _area: Area2D
var _grow_started_ms: float = -1.0
var _next_hint_ms: float = 0.0


func _ready() -> void:
	_build()
	_apply(false, true)
	var router := Services.router()
	if router != null and _area != null:
		router.register_area(_area, self, RULE, [])


func _exit_tree() -> void:
	var router := Services.router()
	if router != null and _area != null:
		router.unregister_area(_area)


func is_open() -> bool:
	return _open


## The barrier's rect in world coordinates.
func barrier_rect() -> Rect2:
	return Rect2(global_position + Vector2(-size * 0.5, -DEPTH), Vector2(size, DEPTH))


func _physics_process(_delta: float) -> void:
	var lit := _any_lit()
	if lit != _open:
		_apply(lit, false)
	if _grow_started_ms >= 0.0:
		var t := clampf((Services.now_ms() - _grow_started_ms) / maxf(grow_ms, 1.0), 0.0, 1.0)
		_show_growth(t)
		if t >= 1.0:
			_grow_started_ms = -1.0


func _any_lit() -> bool:
	for path in braziers:
		var node := get_node_or_null(path)
		if node != null and node.has_method(&"is_lit") and bool(node.call(&"is_lit")):
			return true
	return false


func _apply(open_now: bool, at_once: bool) -> void:
	_open = open_now
	if _shape != null:
		_shape.set_deferred(&"disabled", open_now)
	var feel := Services.feel()
	if open_now:
		_grow_started_ms = -1.0
		for piece in _pieces:
			piece.frame = FRAME_LOW
			piece.scale = Vector2.ONE * ART_SCALE
		if feel != null and not at_once:
			feel.audio_cue(CUE_SHRINK)
	else:
		if at_once:
			_show_growth(1.0)
		else:
			_grow_started_ms = Services.now_ms()
			_push_out()
			if feel != null:
				feel.audio_cue(CUE_GROW)


## Growing back from both ends toward the middle: piece i is grown once `t` passes its share.
func _show_growth(t: float) -> void:
	var count := _pieces.size()
	for i in count:
		var from_edge := minf(float(i), float(count - 1 - i)) / maxf(1.0, float(count - 1) * 0.5)
		var grown := t >= from_edge * 0.85
		_pieces[i].frame = FRAME_GROWN if grown else FRAME_LOW


## A slime standing in the veil as it grows goes to the nearer side.
func _push_out() -> void:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	var body := player.get(&"body") as Node2D
	if body == null:
		return
	var rect := barrier_rect().grow(10.0)
	var feet := body.global_position
	if not rect.has_point(feet):
		return
	var middle := rect.get_center().y
	var to_y := rect.position.y - PUSH_OUT_PX if feet.y < middle else rect.end.y + PUSH_OUT_PX
	var centre: Vector2 = player.call(&"get_centre")
	player.call(&"teleport", centre + Vector2(0.0, to_y - feet.y))


func _build() -> void:
	_barrier = StaticBody2D.new()
	_barrier.name = "Barrier"
	_barrier.collision_layer = 1
	_barrier.collision_mask = 0
	add_child(_barrier)
	_shape = CollisionShape2D.new()
	_shape.name = "BarrierShape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size, DEPTH)
	_shape.shape = rect
	_shape.position = Vector2(0.0, -DEPTH * 0.5)
	_barrier.add_child(_shape)
	_area = Area2D.new()
	_area.name = "DamageArea"
	_area.collision_layer = 8
	_area.collision_mask = 16
	_area.position = Vector2(0.0, -48.0)
	add_child(_area)
	var area_shape := CollisionShape2D.new()
	var hurt := RectangleShape2D.new()
	hurt.size = Vector2(size, 80.0)
	area_shape.shape = hurt
	_area.add_child(area_shape)
	var count := maxi(1, ceili(size / PIECE_WIDTH))
	var step := size / float(count)
	for i in count:
		var piece := Sprite2D.new()
		piece.name = "Piece%d" % i
		piece.set_script(SheetSprite)
		piece.set(&"sheet_path", ART)
		piece.centered = false
		piece.hframes = 2
		piece.offset = Vector2(-128, -250)
		piece.scale = Vector2.ONE * ART_SCALE
		piece.position = Vector2(-size * 0.5 + step * (float(i) + 0.5), 0.0)
		piece.flip_h = i % 2 == 1
		add_child(piece)
		_pieces.append(piece)


# --- damage receiver: it takes nothing -------------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": false}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	if not _open:
		_hint()
	return {"accepted": false, "reason": "immune"}


func commit_damage(_commit: Dictionary) -> void:
	pass


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


func _hint() -> void:
	var now := float(Time.get_ticks_msec())
	if now < _next_hint_ms:
		return
	_next_hint_ms = now + HINT_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_CLINK)
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), refusal_text, &"white", false, TEXT_MS)
