@tool
extends Node2D
## A candle, sconce or brazier the Lantern lights (bomb-lantern-and-secrets design section 2;
## docs/godot/DARKNESS.md): a fire target (group `fire_targets`, game/world/fire/fire_targets.gd)
## that shows one of two existing interior props, `unlit_scene` or `lit_scene` (e.g.
## `interior-decor-candlestick-unlit.tscn` / `-lit.tscn`, the sconces, the toadstool candles; both
## are made as children, the hidden one's collision off).
##
## - A flame lights it (`receive_fire`: true, the flame stops; a lit candle lets the flame fly on).
## - Lit, it is a light source (`light_circle`: `abilities.lantern.candle.lightRadiusPx`, 110 px,
##   flickering, at `flame_offset`), with a warm glow on its flame.
## - It burns for `burn_ms` of gameplay time (60000 by default; owner, 2026-10-14: candles do not
##   stay lit forever) and goes out; in its last `abilities.lantern.candle.gutterMs` it gutters (the
##   flame flickers harder and dims, its light shrinks). Nothing is saved. `burn_ms` 0: it stays lit
##   for good (the story flag `candle-lit.<key>`).
## - `group`: when every candle of the same group burns at once, every gate with `gate_id` opens
##   (GateScript.open, as pressure plates do).
## - A dark room listing it is lit while all its candles burn (dark_room.gd); a room set to light
##   for good then keeps it lit (`keep_lit`).
##
## Owner: world (fire and darkness).

const Services := preload("res://game/shared/services.gd")
const FireTargets := preload("res://game/world/fire/fire_targets.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")

const GROUP := &"candles"
const GATE_GROUP := &"gate"
const FLAG_PREFIX := "candle-lit."
const PERSISTENCE_KEY_META := &"persistence_key"
const INSTANCE_ID_META := &"instance_id"
const CUE_LIGHT := &"GulpSpit"
const GLOW_PX := 64.0
const GLOW_COLOR := Color(1.0, 0.65, 0.25, 0.55)
## The fire target's width, and its height over the flame point (px).
const FIRE_BOX := Vector2(36.0, 44.0)
## Guttering: the light shrinks to GUTTER_LIGHT and the flame dims to GUTTER_DIM of itself, and the
## flicker grows to GUTTER_FLICKER of the radius (from FireTargets.FLICKER_SHARE).
const GUTTER_LIGHT := 0.45
const GUTTER_DIM := 0.5
const GUTTER_FLICKER := 0.3

## The prop shown while unlit / lit.
@export var unlit_scene: PackedScene:
	set(value):
		unlit_scene = value
		_rebuild()
@export var lit_scene: PackedScene:
	set(value):
		lit_scene = value
		_rebuild()
## Where its flame burns, from its feet (the light's centre and the fire target).
@export var flame_offset: Vector2 = Vector2(0, -56)
## Lit when the world loads.
@export var lit_at_start: bool = false:
	set(value):
		lit_at_start = value
		_rebuild()
## It goes out after this many ms of burning; 0: lit for good (saved).
@export var burn_ms: float = 60000.0
## Candles of one group open the gates with `gate_id` when they all burn ("" = no group).
@export var group: String = ""
@export var gate_id: String = ""
## The light's radius (0 = `abilities.lantern.candle.lightRadiusPx`).
@export var light_radius: float = 0.0

var _unlit: Node2D
var _lit_look: Node2D
var _glow: Sprite2D
var _lit: bool = false
var _out_at_ms: float = -1.0
var _for_good: bool = false
var _seed: float = 0.0


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(FireTargets.FIRE_GROUP)
	add_to_group(FireTargets.LIGHT_GROUP)
	add_to_group(GROUP)


func _ready() -> void:
	_seed = randf() * 100.0
	_rebuild()
	if Engine.is_editor_hint():
		return
	var run := Services.run()
	if lit_at_start or (burn_ms <= 0.0 and run != null and run.has_flag(candle_flag())):
		_set_lit(true)
		_for_good = burn_ms <= 0.0 or _for_good


func is_lit() -> bool:
	return _lit


## Fire target: a flame lights an unlit candle (and stops there).
func receive_fire(_hit: Dictionary) -> bool:
	if _lit:
		return false
	light()
	return true


## The box a flame must touch: from its feet up to just over its flame, FIRE_BOX wide.
func fire_rect() -> Rect2:
	var top := flame_offset.y - FIRE_BOX.y * 0.5
	return Rect2(global_position + Vector2(-FIRE_BOX.x * 0.5, top), Vector2(FIRE_BOX.x, -top + 4.0))


## Lights it (a flame, a script): for good, or for `burn_ms`.
func light() -> void:
	if _lit:
		return
	_set_lit(true)
	if burn_ms > 0.0 and not _for_good:
		_out_at_ms = Services.now_ms() + burn_ms
	else:
		var run := Services.run()
		if run != null:
			run.set_flag(candle_flag())
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_LIGHT)
	FireFx.embers(global_position + flame_offset, 6)
	_check_group()


## A lit dark room keeps its candles lit for good (no timer).
func keep_lit() -> void:
	_for_good = true
	_out_at_ms = -1.0
	if not _lit:
		_set_lit(true)


## Light source: its flame and a flickering light while lit.
func light_circle() -> Vector3:
	if not _lit:
		return Vector3.ZERO
	var radius := light_radius if light_radius > 0.0 else FireTargets.lantern_number("candle.lightRadiusPx", 110.0)
	var at := global_position + flame_offset
	var life := _life()
	var share := lerpf(GUTTER_FLICKER, FireTargets.FLICKER_SHARE, life)
	return Vector3(at.x, at.y, FireTargets.flicker(radius * lerpf(GUTTER_LIGHT, 1.0, life), _seed, share))


## 1 while it burns steadily, falling to 0 over its last `candle.gutterMs` (always 1 for good).
func _life() -> float:
	if not _lit or _out_at_ms < 0.0:
		return 1.0
	var gutter := maxf(1.0, FireTargets.lantern_number("candle.gutterMs", 5000.0))
	return clampf((_out_at_ms - Services.now_ms()) / gutter, 0.0, 1.0)


## `candle-lit.<key>`: the placement's persistence key, else its instance id, else its path.
func candle_flag() -> String:
	var node: Node = self
	while node != null:
		var key: Variant = node.get_meta(PERSISTENCE_KEY_META, "")
		if key is String and not (key as String).is_empty():
			return FLAG_PREFIX + key
		var instance_id: Variant = node.get_meta(INSTANCE_ID_META, "")
		if instance_id is String and not (instance_id as String).is_empty():
			return FLAG_PREFIX + instance_id
		node = node.get_parent()
	return FLAG_PREFIX + str(get_path())


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _lit and _out_at_ms >= 0.0 and Services.now_ms() >= _out_at_ms:
		_out_at_ms = -1.0
		_set_lit(false)
		FireFx.smoke(global_position + flame_offset, 4)
	if _glow != null and _glow.visible:
		var life := _life()
		var share := lerpf(GUTTER_FLICKER, FireTargets.FLICKER_SHARE, life)
		var wave := FireTargets.flicker(1.0, _seed, share)
		_glow.scale = Vector2.ONE * (GLOW_PX / 128.0) * lerpf(GUTTER_LIGHT, 1.0, life) * wave
		_glow.modulate.a = GLOW_COLOR.a * lerpf(GUTTER_DIM, 1.0, life) * wave
		if _lit_look != null:
			var dim := clampf(lerpf(GUTTER_DIM, 1.0, life) * (1.0 + (wave - 1.0) * 1.5), 0.0, 1.0)
			_lit_look.modulate = Color(1.0, 1.0, 1.0).lerp(Color(0.55, 0.5, 0.5), 1.0 - dim)


func _set_lit(on: bool) -> void:
	_lit = on
	if _lit_look != null:
		_lit_look.modulate = Color.WHITE
	_show()


func _check_group() -> void:
	if group.is_empty() or gate_id.is_empty():
		return
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if str(node.get(&"group")) == group and not bool(node.call(&"is_lit")):
			return
	for gate: Node in get_tree().get_nodes_in_group(GATE_GROUP):
		if str(gate.get(&"gate_id")) == gate_id:
			gate.call(&"open")


## Makes the two looks (children with no owner, never saved) and shows the right one.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	for look: Node2D in [_unlit, _lit_look]:
		if look != null and is_instance_valid(look):
			look.queue_free()
	_unlit = _make(unlit_scene)
	_lit_look = _make(lit_scene)
	if _glow == null:
		_glow = Sprite2D.new()
		_glow.texture = FireFx.glow_texture()
		_glow.material = FireFx.additive()
		_glow.modulate = GLOW_COLOR
		_glow.scale = Vector2.ONE * (GLOW_PX / 128.0)
		add_child(_glow)
	_glow.position = flame_offset
	if Engine.is_editor_hint():
		_lit = lit_at_start
	_show()


func _make(scene: PackedScene) -> Node2D:
	if scene == null:
		return null
	var look := scene.instantiate() as Node2D
	if look == null:
		return null
	add_child(look)
	return look


func _show() -> void:
	_toggle(_unlit, not _lit)
	_toggle(_lit_look, _lit)
	if _glow != null:
		_glow.visible = _lit
		move_child(_glow, get_child_count() - 1)


## Shows or hides a look, and its collision with it.
static func _toggle(look: Node2D, on: bool) -> void:
	if look == null or not is_instance_valid(look):
		return
	look.visible = on
	for child: Node in look.find_children("*", "CollisionShape2D", true, false):
		(child as CollisionShape2D).set_deferred(&"disabled", not on)
	if look is CollisionObject2D:
		for child: Node in look.get_children():
			if child is CollisionShape2D:
				(child as CollisionShape2D).set_deferred(&"disabled", not on)
