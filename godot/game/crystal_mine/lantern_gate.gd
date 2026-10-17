extends StaticBody2D
class_name LanternGate
## A mine gate the Lantern opens (docs/godot/DUNGEONS.md "The Crystal Mine (built)"; the look book:
## the Lantern owns braziers, candles and the dark): two timber posts with a cold iron lamp cup on
## each and a gate of planks between them. It is a `gate` (group `gate`, `gate_id`): the candles of
## its group (candle.gd `group` + `gate_id`) open it when they all burn at once: the Dark Maze's four
## corner candles, the camp's gate brazier. It opens for good: the planks rise, flames burn in the
## lamp cups, and it no longer collides (the kit's object state, DungeonState.mark_done).
##
## Pushing into it while shut says `shut_text`, at most every SHUT_EVERY_MS.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")

const GATE_GROUP := &"gate"
const FRAME_SHUT := 0
const FRAME_OPEN := 1
const CUE_OPEN := &"GateOpen"
const SHUT_EVERY_MS := 2600.0
const TEXT_RISE := 140.0
const TEXT_MS := 2400.0
## How near the slime's centre must push against it to hear the line.
const PUSH_RADIUS := 90.0
## The lamp cups' flames, from the root (world units), lit once open.
const CUPS: Array[Vector2] = [Vector2(-58, -150), Vector2(58, -150)]

## Payload {"gate_id": String}.
signal opened(payload: Dictionary)

@export var gate_id: String = ""
@export var shut_text: String = "The gate is shut. Its lamps are cold."
@export var visual: Sprite2D

var _open := false
var _next_text_ms := 0.0
var _glows: Array[Sprite2D] = []


func _enter_tree() -> void:
	add_to_group(GATE_GROUP)
	add_to_group(&"light_sources")


func _ready() -> void:
	_open = DungeonState.is_done(get_tree(), _key())
	_apply()


func is_open() -> bool:
	return _open


## Opens it for good (its candles, a script).
func open(_payload: Variant = null) -> void:
	if _open:
		return
	_open = true
	DungeonState.mark_done(get_tree(), _key())
	_apply()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_OPEN)
		feel.shake(220.0, 0.004)
	for cup in CUPS:
		FireFx.embers(global_position + cup, 6)
	opened.emit({"gate_id": gate_id})


func open_for_good(payload: Variant = null) -> void:
	open(payload)


## Gates of the `gate` group can be closed by plates; this one stays open.
func close(_payload: Variant = null) -> void:
	pass


func _apply() -> void:
	if visual != null:
		visual.frame = FRAME_OPEN if _open else FRAME_SHUT
	for child: Node in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred(&"disabled", _open)
	if _open and _glows.is_empty():
		for cup in CUPS:
			var glow := Sprite2D.new()
			glow.texture = FireFx.glow_texture()
			glow.material = FireFx.additive()
			glow.modulate = Color(1.0, 0.65, 0.25, 0.55)
			glow.scale = Vector2.ONE * 0.6
			glow.position = cup
			add_child(glow)
			_glows.append(glow)


func _physics_process(_delta: float) -> void:
	if _open:
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	var centre: Vector2 = player.call(&"get_centre")
	if centre.distance_to(global_position) > PUSH_RADIUS:
		return
	var intent: Vector2 = player.call(&"get_move_intent") if player.has_method(&"get_move_intent") else Vector2.ZERO
	if intent == Vector2.ZERO or intent.dot(global_position - centre) <= 0.0:
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_text_ms:
		return
	_next_text_ms = now + SHUT_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), shut_text, &"white", false, TEXT_MS)


## Its lamp cups are light sources while open (a lit gate shows in the dark).
func light_circle() -> Vector3:
	if not _open:
		return Vector3.ZERO
	return Vector3(global_position.x, global_position.y - 150.0, 130.0)


func _key() -> String:
	return DungeonState.object_key(self, "lantern-gate:" + (gate_id if not gate_id.is_empty() else str(name)))
