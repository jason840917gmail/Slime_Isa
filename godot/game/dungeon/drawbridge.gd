@tool
extends "res://game/dungeon/hazard_deck.gd"
class_name Drawbridge
## A drawbridge over the void (docs/godot/DUNGEONS.md "Doors and room logic"; `object.drawbridge`):
## raised, it stands upright on the far rim; `trigger()` lowers it across the gap for good (a winch,
## a crank, a bomb on its post, an arrow in a lens: anything can call `trigger`, or have a signal
## connected to it; `lower()` is the same). Lowered, it is a deck (safe ground) over the hazard and
## opens its passage over the elevation hole under it; its record (`bridge_id`) keeps it down.
##
## The node stands at the hinge: the middle of the bridge's end on the rim it is fixed to. It
## lowers toward `toward` (south: the deck runs down the screen from the hinge) over `length`
## cells, `width` units wide. Looks: `raised_look` (the upright bridge, its bottom at the hinge) and
## `deck_look` (the lowered planks, top at the hinge), both turned with `toward`.
##
## Owner: dungeon kit.

const TURNS := {"south": 0.0, "west": PI * 0.5, "north": PI, "east": -PI * 0.5}
const CUE_LOWER := &"GateOpen"
const CUE_THUD := &"StomperSlam"
const DUST := &"dodge-dust"
const CELL := 64.0

## It came down. Payload: {"bridgeId"}.
signal lowered(payload: Dictionary)

## Which way it lowers from its hinge.
@export_enum("south", "north", "east", "west") var toward: String = "south":
	set(value):
		toward = value
		_layout()
## Cells it spans.
@export var length: int = 3:
	set(value):
		length = maxi(1, value)
		_layout()
## Its width (world units).
@export var width: float = 128.0:
	set(value):
		width = value
		_layout()
## Its id in the record.
@export var bridge_id: String = ""
## Starts down (a bridge that is simply there).
@export var starts_lowered: bool = false
## The upright bridge (Sprite2D; centered off, bottom middle at the hinge).
@export var raised_look: Sprite2D
## The lowered planks (Sprite2D; stretched to the deck).
@export var deck_look: Sprite2D

var _down := false
var _lowering := false
var _started_ms := 0.0


func _init() -> void:
	draw_floor = false


func _ready() -> void:
	_layout()
	if Engine.is_editor_hint():
		_show(1.0 if starts_lowered else 0.0)
		return
	_down = starts_lowered
	_show(1.0 if _down else 0.0)
	super()
	_restore_in_tree.call_deferred()


func holds() -> bool:
	return _down and not _lowering


func is_lowered() -> bool:
	return _down


func opens_passage_at_build() -> bool:
	return starts_lowered


## Its deck, global (the hinge end at its position).
func deck_rects() -> Array[Rect2]:
	var along := Vector2(0.0, length * CELL).rotated(float(TURNS.get(toward, 0.0)))
	var across := Vector2(width, 0.0).rotated(float(TURNS.get(toward, 0.0)))
	var a := global_position - across * 0.5
	var rect := Rect2(a, Vector2.ZERO).expand(a + across).expand(a + along).expand(a + across + along)
	return [rect]


## The kit's generic hookup: lowers it for good.
func trigger(_payload: Variant = null) -> void:
	lower()


## Lowers it across the gap, for good.
func lower(_payload: Variant = null) -> void:
	if _down:
		return
	_down = true
	_lowering = true
	_started_ms = float(Time.get_ticks_msec())
	DungeonState.mark_done(get_tree(), _record_key())
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_LOWER)
	set_process(true)


## `_restore`, deferred from `_ready`, only while still in the tree: a world run on its own (F6)
## is the current scene for a moment before it swaps itself for main.tscn, and this piece of that
## copy has left the tree by then.
func _restore_in_tree() -> void:
	if is_inside_tree():
		_restore()


func _restore() -> void:
	if not _down and DungeonState.is_done(get_tree(), _record_key()):
		_down = true
		_show(1.0)
		_open_passage()


func _record_key() -> String:
	return DungeonState.object_key(self, "bridge:" + (bridge_id if not bridge_id.is_empty() else String(name)))


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _lowering:
		set_process(false)
		return
	var t := clampf((float(Time.get_ticks_msec()) - _started_ms) / maxf(1.0, DungeonState.number("drawbridge.lowerMs", 650.0)), 0.0, 1.0)
	_show(t * t)
	if t >= 1.0:
		_lowering = false
		set_process(false)
		_open_passage()
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_THUD)
			feel.shake(DungeonState.number("drawbridge.shakeMs", 240.0), DungeonState.number("drawbridge.shakeIntensity", 0.006))
			var rect: Rect2 = deck_rects()[0]
			feel.particles(DUST, rect.get_center())
			feel.particles(DUST, rect.position + rect.size * Vector2(0.2, 0.8))
			feel.particles(DUST, rect.position + rect.size * Vector2(0.8, 0.2))
		lowered.emit({"bridgeId": bridge_id})


func _open_passage() -> void:
	var watch_script := load("res://game/dungeon/hazard_watch.gd") as GDScript
	watch_script.call(&"open_passages_for", self)


## Lowered by `share` (0: upright, 1: down): the upright look folds toward the gap, the deck grows.
func _show(share: float) -> void:
	if raised_look != null:
		raised_look.visible = share < 0.999
		raised_look.scale.y = absf(raised_look.scale.x) * maxf(0.0, 1.0 - share)
	if deck_look != null:
		deck_look.visible = share > 0.001
		deck_look.scale.y = _deck_scale().y * share


func _deck_scale() -> Vector2:
	if deck_look == null or deck_look.texture == null:
		return Vector2.ONE
	var art := deck_look.texture.get_size()
	return Vector2(width / maxf(1.0, art.x), length * CELL / maxf(1.0, art.y))


func _layout() -> void:
	rotation = float(TURNS.get(toward, 0.0))
	if deck_look != null and deck_look.texture != null:
		var art := deck_look.texture.get_size()
		deck_look.centered = false
		deck_look.offset = Vector2(-art.x * 0.5, 0.0)
		deck_look.scale = _deck_scale()
	queue_redraw()
