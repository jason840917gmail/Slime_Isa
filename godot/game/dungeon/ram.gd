@tool
extends Node2D
class_name Ram
## The ram (docs/godot/DUNGEONS.md "Mechanisms: the knock target, the ram, the runaway cart";
## `object.ram`; the rework plan docs/design/2026-11-23-dungeons-2-3-rework.md "The bosses"): an
## iron-capped log hung by two chains from a timber gantry, held back by a knock target. Let go
## (`trigger()`, the kit's generic hookup: a knock target's `targets`), it swings down its lane,
## strikes what its head sweeps, swings back and winches itself up again.
##
## **Placing.** The node stands at the lane's start: the middle of its rest end. The lane runs
## `toward` (north, south, east or west) for `length` cells, `width` wide (two cells). The log
## rests behind the node (the other way), under its gantry: that bay (the log's length and the
## gantry's feet) is solid, the lane itself is free floor with worn grooves along it (the tell).
##
## **The cycle** (`dungeon.ram` in game-constants.json): held back -> `trigger()` -> the shudder
## `windupMs` (350: it shakes, the chains rattle, dust falls) -> the swing out `swingMs` (420,
## speeding up) -> held at full reach `holdMs` (150) -> the swing back `returnMs` (600: it hangs
## loose, low on slack chains) -> the winch `rewindMs` (8000: a ratchet click every
## `ratchetEveryMs`, the log creeping back and up a tooth at a time, the cog turning) -> ready: it
## calls its knock target's `rearm()` and emits `ready_again`. `trigger()` does nothing until then.
##
## **What the swing does** (game/dungeon/mechanism_strike.gd, on the ram's own elevation level, each
## thing once per swing): a node in the group `ram_breakable` gets `on_ram_hit(self)`; a node with
## `on_mechanism_hit(kind, source)` gets that call (kind `&"ram"`) instead of damage and the log
## swings on through; the slime takes `slimeDamage` and is shoved ACROSS the lane, to the side it
## stands on, clear of the lane before the head reaches it (`MechanismStrike.shove_slime`: its
## invulnerability and a Roll's i-frames pass it, and then the log passes over it); an enemy takes
## `damage` as a true blow and is knocked down the lane through the knock system (walls splat,
## ledges and hazards apply; at least `hit.resistFloor` of the knock however heavy it is).
##
## **Looks:** the gantry (one front view for every way it points), the log (seen from the side for
## east and west, on end for north and south), two drawn chains from the beam to the log that follow
## it, the cog on a post, the log's shadow on the floor, the lane's grooves. `rope_anchor()` is where
## a knock target's rope ends (the foot of the cog's post).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const MechanismStrike := preload("res://game/dungeon/mechanism_strike.gd")

const KIND := &"ram"
const CELL := 64.0
const WAYS := {"north": Vector2.UP, "south": Vector2.DOWN, "east": Vector2.RIGHT, "west": Vector2.LEFT}
const ART := "res://asset/MAPS/objects/mechanisms/"
## The pictures are packed at 2 px a unit.
const ART_SCALE := 0.5
## The log's art (world units): its length, its body's thickness, the rows its rings stand over it,
## its two chained rings from its middle toward its head, how much of its head end strikes.
const LOG_LENGTH := 160.0
const LOG_THICK := 55.5
const LOG_RINGS := 17.5
const RING_REAR := -50.0
const RING_FRONT := 26.0
const HEAD_LENGTH := 46.0
## The gantry's art: its size, its posts' middles from its own, its beam's underside and middle
## over its feet, the cog's and the pawl's places on its right post.
const GANTRY_SIZE := Vector2(161.5, 137.0)
const POST_ASIDE := 59.75
const BEAM_UNDER := 109.0
const BEAM_MIDDLE := 123.0
const COG_AT := Vector2(59.75, -58.0)
const PAWL_AT := Vector2(44.0, -84.0)
const COG_CELL := 44.5
## The solid bay: how far it reaches behind the log's rest, and its half width for a lane across
## the screen and for one up or down it (the gantry's feet stand outside the log there).
const BAY_BEHIND := 16.0
const BAY_HALF_ACROSS := 40.0
const BAY_HALF_ALONG := 80.0
## The gantry's place in the depth order is this far from its feet (in front of a log that points
## up the screen, behind any other): more than the resting log's sway, so the two never swap.
const DEPTH_NUDGE := 6.0
## The swing reaches this far past its lane's end, so a breakable standing on that line is struck.
const REACH_SLACK := 8.0
## The shudder pulls the log this far back, and shakes it this fast (radians per ms).
const WINDUP_PULL := 7.0
const SHUDDER_RATE := 0.085
## The log on end is drawn this far over its floor line besides its height (its round body).
const END_RISE := 14.0
## How long a ratchet tooth's jerk takes (ms).
const TOOTH_MS := 110.0
## The cog turns this much per tooth, and this fast as the chains pay out (radians per unit).
const COG_TOOTH := TAU / 20.0
const COG_PAYOUT := 0.03
const SHADOW_COLOR := Color(0.05, 0.04, 0.03, 0.34)
const GROOVE_DARK := Color(0.12, 0.09, 0.07, 0.34)
const GROOVE_LIGHT := Color(0.95, 0.9, 0.8, 0.13)
const SCUFF := Color(0.14, 0.11, 0.09, 0.1)
const CHAIN_DARK := Color("#2e2421")
const CHAIN_LIGHT := Color("#8a7260")
const LINK_PX := 8.0
const LINK_WIDTH := 2.4
const CUE_WINDUP := &"RamWindup"
const CUE_SWING := &"RamSwing"
const CUE_THUD := &"RamThud"
const CUE_RATCHET := &"RamRatchet"
const DUST := &"dodge-dust"

enum State { READY, WINDUP, SWING, HOLD, RETURN, REWIND }

## It was let go. Payload: {"ramId"}.
signal released(payload: Dictionary)
## Its swing reached its end. Payload: {"ramId", "hits": how many things it struck}.
signal swung(payload: Dictionary)
## It is wound back and ready. Payload: {"ramId"}.
signal ready_again(payload: Dictionary)

## Which way its lane runs from the node.
@export_enum("north", "south", "east", "west") var toward: String = "east":
	set(value):
		toward = value
		_layout()
## Cells its lane spans.
@export var length: int = 4:
	set(value):
		length = maxi(1, value)
		_layout()
## Its lane's width (world units: two cells).
@export var width: float = 128.0:
	set(value):
		width = value
		_layout()
## Its id (the payloads carry it).
@export var ram_id: String = ""
## The solid bay under the gantry.
@export var body: StaticBody2D
## The area its hits are sent from (the damage router wants one; it needs no shape).
@export var attack_area: Area2D

var _state: State = State.READY
var _since_ms := 0.0
## The head's tip along the lane (units from the node; negative: behind it) at the last physics
## step, the things this swing has struck, and how many.
var _swept_tip := 0.0
var _struck: Dictionary = {}
var _hits := 0
var _teeth := 0
var _knock_target: Node
var _lane: Node2D
var _gantry: Sprite2D
var _cog: Sprite2D
var _pawl: Sprite2D
var _log: Node2D
var _log_sprite: Sprite2D
var _chains: Node2D
var _cog_turn := 0.0
var _shown_height := 16.0
var _sway_offset := 0.0


func _enter_tree() -> void:
	add_to_group(MechanismStrike.GROUP_MECHANISMS)


func _ready() -> void:
	y_sort_enabled = true
	_build()
	_layout()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_sway_offset = float(get_instance_id() % 1000)
	_swept_tip = _rest_tip()
	_since_ms = Services.now_ms()


# --- what it answers ------------------------------------------------------------------------------

## The kit's generic hookup: lets the ram go. Nothing while it swings or winds back. A payload with
## a "source" that can `rearm` (a knock target) is remembered as its knock target.
func trigger(payload: Variant = null) -> void:
	if payload is Dictionary and (payload as Dictionary).get("source") is Node:
		var source: Node = (payload as Dictionary)["source"]
		if source.has_method(&"rearm"):
			_knock_target = source
	if _state != State.READY or Engine.is_editor_hint():
		return
	if _knock_target != null and is_instance_valid(_knock_target) and _knock_target.has_method(&"go_slack"):
		_knock_target.call(&"go_slack")
	_enter(State.WINDUP)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_WINDUP)
		for foot: Vector2 in _feet():
			feel.particles(DUST, global_position + foot)
	released.emit({"ramId": ram_id})


## The knock target that holds it back (a knock target tells its mechanisms when the world is built).
func set_knock_target(target: Node) -> void:
	_knock_target = target


## The knock target that holds it back (null when none was set, or it is gone).
func get_knock_target() -> Node:
	return _knock_target if _knock_target != null and is_instance_valid(_knock_target) else null


func is_ready() -> bool:
	return _state == State.READY


## For the tests and the films: "ready", "windup", "swing", "hold", "return" or "rewind".
func state_name() -> String:
	return ["ready", "windup", "swing", "hold", "return", "rewind"][_state]


## Where a knock target's rope ends: the foot of the cog's post (global).
func rope_anchor() -> Vector2:
	return global_position + _gantry_at() + Vector2(COG_AT.x, 3.0)


## Its lane (global): the floor its head sweeps.
func lane_rect() -> Rect2:
	return _rect_along(0.0, float(length) * CELL)


## The head's tip now (global, on the floor).
func head_point() -> Vector2:
	return global_position + _along() * _tip(Services.now_ms())


# --- the cycle ------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	var now := Services.now_ms()
	var age := now - _since_ms
	match _state:
		State.WINDUP:
			if age >= _number("windupMs", 350.0):
				_enter(State.SWING)
				_struck.clear()
				_hits = 0
				_swept_tip = _rest_tip()
				var feel := Services.feel()
				if feel != null:
					feel.audio_cue(CUE_SWING)
		State.SWING:
			var done := age >= _number("swingMs", 420.0)
			var tip := _reach() if done else _tip(now)
			_shove(tip, now)
			_sweep(tip + (REACH_SLACK if done else 0.0))
			if done:
				_enter(State.HOLD)
				_arrive()
		State.HOLD:
			if age >= _number("holdMs", 150.0):
				_enter(State.RETURN)
		State.RETURN:
			if age >= _number("returnMs", 600.0):
				_enter(State.REWIND)
				_teeth = 0
		State.REWIND:
			var every := maxf(1.0, _number("ratchetEveryMs", 500.0))
			var teeth := int(age / every)
			if teeth > _teeth and age < _number("rewindMs", 8000.0):
				_teeth = teeth
				var feel := Services.feel()
				if feel != null:
					feel.audio_cue(CUE_RATCHET)
			if age >= _number("rewindMs", 8000.0):
				_enter(State.READY)
				_cog_turn = 0.0
				if _knock_target != null and is_instance_valid(_knock_target) and _knock_target.has_method(&"rearm"):
					_knock_target.call(&"rearm")
				ready_again.emit({"ramId": ram_id})


func _enter(state: State) -> void:
	_state = state
	_since_ms = Services.now_ms()


## What the head passed over since the last step, up to `tip`.
func _sweep(tip: float) -> void:
	var from := minf(_swept_tip, tip) - HEAD_LENGTH
	_swept_tip = maxf(_swept_tip, tip)
	if tip <= 0.0 or attack_area == null:
		return
	var out := MechanismStrike.sweep(self, attack_area, _rect_along(maxf(0.0, from), tip), _along(), KIND,
		_numbers(), _struck)
	_hits += int(out["hits"])


## The slime ahead of the head is shoved across the lane before the head reaches it
## (MechanismStrike.shove_slime), never carried down the lane under the log.
func _shove(tip: float, now: float) -> void:
	if attack_area == null:
		return
	if MechanismStrike.shove_slime(self, attack_area, lane_rect(), global_position + _along() * tip, _along(),
			_tip_speed(now), KIND, _numbers(), _struck):
		_hits += 1


## How fast the head moves down the lane now (units/ms; the swing speeds up as it goes).
func _tip_speed(now: float) -> float:
	if _state != State.SWING:
		return 0.0
	var swing := maxf(1.0, _number("swingMs", 420.0))
	var t := clampf((now - _since_ms) / swing, 0.0, 1.0)
	return (_reach() - (_rest_tip() - WINDUP_PULL)) * 2.0 * t / swing


## The end of the swing: the thud, the shake, dust where the head stops.
func _arrive() -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_THUD)
		feel.shake(_number("shakeMs", 220.0), _number("shakeIntensity", 0.007))
		var head := global_position + _along() * _reach()
		for aside: float in [-34.0, 0.0, 34.0]:
			feel.particles(DUST, head + _across() * aside)
	swung.emit({"ramId": ram_id, "hits": _hits})


# --- where the log is -----------------------------------------------------------------------------

func _along() -> Vector2:
	return WAYS.get(toward, Vector2.RIGHT)


func _across() -> Vector2:
	var along := _along()
	return Vector2(-along.y, along.x)


## True for a lane across the screen (east or west).
func _sideways() -> bool:
	return absf(_along().x) > 0.5


func _rest_tip() -> float:
	return -_number("cockPx", 44.0)


func _reach() -> float:
	return float(length) * CELL


## The head's tip along the lane at `now` (units from the node).
func _tip(now: float) -> float:
	var age := now - _since_ms
	var rest := _rest_tip()
	match _state:
		State.WINDUP:
			var t := clampf(age / maxf(1.0, _number("windupMs", 350.0)), 0.0, 1.0)
			return rest - WINDUP_PULL * (1.0 - (1.0 - t) * (1.0 - t)) + sin(age * SHUDDER_RATE * TAU * 0.16) * _number("shudderPx", 2.5)
		State.SWING:
			var t := clampf(age / maxf(1.0, _number("swingMs", 420.0)), 0.0, 1.0)
			return lerpf(rest - WINDUP_PULL, _reach(), t * t)
		State.HOLD:
			var t := clampf(age / maxf(1.0, _number("holdMs", 150.0)), 0.0, 1.0)
			# a short rebound off its chains
			return _reach() - 7.0 * sin(PI * t)
		State.RETURN:
			var t := clampf(age / maxf(1.0, _number("returnMs", 600.0)), 0.0, 1.0)
			return lerpf(_reach(), 0.0, t * t * (3.0 - 2.0 * t))
		State.REWIND:
			# it swings a little on its slack chains at first, then creeps back a tooth at a time
			return lerpf(0.0, rest, _wound(age)) + 5.0 * sin(age / 150.0) * exp(-age / 380.0)
	# at rest it sways a little on its chains
	return rest + 1.8 * sin((now + _sway_offset) / 700.0)


## The log's height over the floor at `now` (units under its underside).
func _height(now: float) -> float:
	var age := now - _since_ms
	var hang := _number("hangPx", 16.0)
	var loose := _number("loosePx", 3.0)
	match _state:
		State.READY:
			return hang
		State.WINDUP:
			return hang + absf(sin(age * SHUDDER_RATE * TAU * 0.16)) * 1.5
		State.SWING:
			var t := clampf(age / maxf(1.0, _number("swingMs", 420.0)), 0.0, 1.0)
			return hang - (hang - _number("dipPx", 5.0)) * sin(PI * t * t)
		State.HOLD:
			return hang
		State.RETURN:
			var t := clampf(age / maxf(1.0, _number("returnMs", 600.0)), 0.0, 1.0)
			return lerpf(hang, loose, t * t * (3.0 - 2.0 * t))
		State.REWIND:
			return lerpf(loose, hang, _wound(age))
	return hang


## How far the winch has wound it back (0 .. 1) `age` ms into the rewind: a tooth at a time, each a
## short jerk and then a wait.
func _wound(age: float) -> float:
	var every := maxf(1.0, _number("ratchetEveryMs", 500.0))
	var total := maxf(1.0, _number("rewindMs", 8000.0) / every)
	var tooth := floorf(age / every)
	var into := clampf((age - tooth * every) / TOOTH_MS, 0.0, 1.0)
	return clampf((maxf(0.0, tooth - 1.0) + (into * into * (3.0 - 2.0 * into) if tooth >= 1.0 else 0.0)) / maxf(1.0, total - 1.0), 0.0, 1.0)


## A rectangle of the lane (global) from `from` to `to` along it, its whole width.
func _rect_along(from: float, to: float) -> Rect2:
	var along := _along()
	var across := _across() * width * 0.5
	var a := global_position + along * from
	var b := global_position + along * to
	return Rect2(a - across, Vector2.ZERO).expand(a + across).expand(b - across).expand(b + across)


## The gantry's feet (the middle between them), from the node: over the resting log's middle.
func _gantry_at() -> Vector2:
	return _along() * (_rest_tip() - LOG_LENGTH * 0.5)


## Its two posts' feet, from the node (the gantry is always drawn from the front: its posts stand
## left and right of its middle).
func _feet() -> Array[Vector2]:
	var at := _gantry_at()
	return [at - Vector2(POST_ASIDE, 0.0), at + Vector2(POST_ASIDE, 0.0)]


func _number(key: String, fallback: float) -> float:
	return DungeonState.number("ram." + key, fallback)


func _numbers() -> Dictionary:
	var constants := Services.constants()
	return constants.dictionary("dungeon.ram") if constants != null else {}


# --- the looks ------------------------------------------------------------------------------------

func _build() -> void:
	if _lane != null:
		return
	_lane = Node2D.new()
	_lane.name = "Lane"
	_lane.z_index = -1
	add_child(_lane, false, Node.INTERNAL_MODE_BACK)
	_lane.draw.connect(_draw_lane)
	_gantry = _sprite("ram-gantry-front.webp")
	_gantry.name = "Gantry"
	_gantry.centered = false
	_gantry.offset = Vector2(-GANTRY_SIZE.x, -GANTRY_SIZE.y * 2.0)
	add_child(_gantry, false, Node.INTERNAL_MODE_BACK)
	_cog = _sprite("ram-cog.webp")
	_cog.position = COG_AT / ART_SCALE
	_cog.scale = Vector2.ONE
	_gantry.add_child(_cog)
	_pawl = _sprite("ram-pawl.webp")
	_pawl.position = PAWL_AT / ART_SCALE
	_pawl.scale = Vector2.ONE * 0.8
	_gantry.add_child(_pawl)
	_log = Node2D.new()
	_log.name = "Log"
	add_child(_log, false, Node.INTERNAL_MODE_BACK)
	_log_sprite = Sprite2D.new()
	_log_sprite.scale = Vector2.ONE * ART_SCALE
	_log.add_child(_log_sprite)
	_chains = Node2D.new()
	_chains.name = "Chains"
	_log.add_child(_chains)
	_chains.draw.connect(_draw_chains)
	# Moved every frame from the gameplay clock: no physics interpolation on top.
	for node: Node in [_lane, _gantry, _log]:
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _sprite(file: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = SheetSprite.load_picture(ART + file)
	sprite.scale = Vector2.ONE * ART_SCALE
	return sprite


## The pictures and the body for `toward`, `length` and `width`.
func _layout() -> void:
	if _lane == null:
		return
	var along := _along()
	var file := "ram-log.webp"
	if not _sideways():
		file = "ram-log-north.webp" if along.y < 0.0 else "ram-log-south.webp"
	_log_sprite.texture = SheetSprite.load_picture(ART + file)
	_log_sprite.flip_h = along.x < 0.0
	# The gantry stands a hair behind the log in the depth order, but in front of a log that points
	# up the screen (the log passes under its beam there).
	var gantry_at := _gantry_at()
	var nudge := DEPTH_NUDGE if along.y < 0.0 else -DEPTH_NUDGE
	_gantry.position = gantry_at + Vector2(0.0, nudge)
	_gantry.offset = Vector2(-GANTRY_SIZE.x, (-GANTRY_SIZE.y - nudge) / ART_SCALE)
	if body != null:
		var shape := body.get_node_or_null(^"Shape") as CollisionShape2D
		if shape != null:
			var behind := -_rest_tip() + LOG_LENGTH + BAY_BEHIND
			var half_across := BAY_HALF_ACROSS if _sideways() else BAY_HALF_ALONG
			var box := RectangleShape2D.new()
			box.size = Vector2(behind, half_across * 2.0) if _sideways() else Vector2(half_across * 2.0, behind)
			shape.shape = box
			shape.position = -along * behind * 0.5
	_lane.queue_redraw()
	_place()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_place()


## The log, its chains, its shadow and the cog, for now.
func _place() -> void:
	if _log == null:
		return
	var editor := Engine.is_editor_hint()
	var now := 0.0 if editor else Services.now_ms()
	var tip := _rest_tip() if editor else _tip(now)
	var height := _number("hangPx", 16.0) if editor else _height(now)
	var along := _along()
	_log.position = along * (tip - LOG_LENGTH * 0.5)
	if _sideways():
		# seen from the side: its underside `height` over the floor line
		_log_sprite.position = Vector2(0.0, -height - (LOG_THICK + LOG_RINGS) * 0.5)
		_log_sprite.offset = Vector2.ZERO
	else:
		_log_sprite.position = Vector2(0.0, -height - END_RISE)
	# The cog pays the chains out as the log goes and turns a tooth at a time as it winds back.
	if not editor:
		match _state:
			State.SWING, State.HOLD, State.RETURN:
				_cog_turn = (tip - _rest_tip()) * COG_PAYOUT
			State.REWIND:
				_cog_turn = -_wound(now - _since_ms) * COG_TOOTH * 16.0
			_:
				_cog_turn = 0.0
	_cog.rotation = _cog_turn
	_pawl.rotation = deg_to_rad(-14.0) if _state in [State.SWING, State.HOLD, State.RETURN] else 0.0
	_shown_height = height
	_chains.queue_redraw()
	_lane.set_meta(&"log_at", _log.position)
	_lane.set_meta(&"log_height", height)
	_lane.queue_redraw()


## The two rings on the log the chains hold, from the log's node.
func _rings() -> Array[Vector2]:
	var along := _along()
	if _sideways():
		var top := _log_sprite.position.y - (LOG_THICK + LOG_RINGS) * 0.5 + 4.0
		return [Vector2(along.x * RING_REAR, top), Vector2(along.x * RING_FRONT, top)]
	var rise := _log_sprite.position.y
	return [along * RING_REAR + Vector2(0.0, rise), along * RING_FRONT + Vector2(0.0, rise)]


## The two hooks under the gantry's beam, from the log's node.
func _hooks() -> Array[Vector2]:
	var gantry := _gantry_at() - _log.position
	if _sideways():
		var along := _along()
		return [gantry + Vector2(along.x * RING_REAR, -BEAM_UNDER), gantry + Vector2(along.x * RING_FRONT, -BEAM_UNDER)]
	return [gantry + Vector2(-13.0, -BEAM_MIDDLE + 6.0), gantry + Vector2(13.0, -BEAM_MIDDLE + 6.0)]


func _draw_chains() -> void:
	var rings := _rings()
	var hooks := _hooks()
	# slack chains sag: the lower the log hangs, the more
	var hang := _number("hangPx", 16.0)
	var slack := clampf((hang - _shown_height) / maxf(1.0, hang - _number("loosePx", 3.0)), 0.0, 1.0)
	for i in 2:
		_draw_chain(hooks[i], rings[i], 0.04 + 0.1 * slack)


## A run of links from `from` to `to`, sagging by `sag` of its span: alternately seen face on (an
## oval) and edge on (a bar), as the cracked winch post's chain is drawn.
func _draw_chain(from: Vector2, to: Vector2, sag: float) -> void:
	var span := from.distance_to(to)
	var count := maxi(2, int(span / LINK_PX))
	var drop := span * sag
	var points := PackedVector2Array()
	for i in count + 1:
		var t := float(i) / float(count)
		points.append(from.lerp(to, t) + Vector2(0.0, drop * 4.0 * t * (1.0 - t)))
	for i in count:
		var a := points[i]
		var b := points[i + 1]
		if i % 2 == 0:
			_chains.draw_set_transform((a + b) * 0.5, (b - a).angle(), Vector2(1.0, 0.6))
			_chains.draw_arc(Vector2.ZERO, LINK_PX * 0.56, 0.0, TAU, 12, CHAIN_DARK, LINK_WIDTH)
			_chains.draw_arc(Vector2(0.0, -0.5), LINK_PX * 0.56, PI * 1.1, PI * 1.9, 6, CHAIN_LIGHT, 0.9)
			_chains.draw_set_transform(Vector2.ZERO)
		else:
			_chains.draw_line(a.lerp(b, 0.08), a.lerp(b, 0.92), CHAIN_DARK, LINK_WIDTH + 0.8)
			_chains.draw_line(a.lerp(b, 0.2) + Vector2(0.0, -0.7), a.lerp(b, 0.8) + Vector2(0.0, -0.7), CHAIN_LIGHT, 0.8)


## The lane's worn grooves and the log's shadow, on the floor.
func _draw_lane() -> void:
	var along := _along()
	var across := _across()
	var reach := _reach()
	var half := width * 0.5
	# a faint scuffed band, then long scratches the log's hoops have left, the same every time
	_lane.draw_colored_polygon(PackedVector2Array([along * 4.0 - across * half * 0.72, along * reach - across * half * 0.72,
		along * reach + across * half * 0.72, along * 4.0 + across * half * 0.72]), SCUFF)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + length * 13 + int(width)
	for i in 26:
		var side := rng.randf_range(-0.62, 0.62) * half
		var from := rng.randf_range(0.0, reach * 0.7)
		var run := rng.randf_range(reach * 0.12, reach * 0.5)
		var to := minf(reach - 4.0, from + run)
		var thick := rng.randf_range(1.0, 2.6)
		_lane.draw_line(along * from + across * side, along * to + across * side, GROOVE_DARK, thick, true)
		_lane.draw_line(along * from + across * (side + 1.2), along * to + across * (side + 1.2), GROOVE_LIGHT, 1.0, true)
	for side: float in [-0.34, 0.34]:
		_lane.draw_line(along * 2.0 + across * side * half, along * (reach - 6.0) + across * side * half, GROOVE_DARK, 3.4, true)
		_lane.draw_line(along * 2.0 + across * (side * half + 1.8), along * (reach - 6.0) + across * (side * half + 1.8), GROOVE_LIGHT, 1.2, true)
	# the shadow: under the log, smaller and fainter the higher it hangs
	var at: Vector2 = _lane.get_meta(&"log_at", along * (_rest_tip() - LOG_LENGTH * 0.5))
	var height := float(_lane.get_meta(&"log_height", 16.0))
	var fade := clampf(1.0 - height / 70.0, 0.4, 1.0)
	var radii := Vector2(LOG_LENGTH * 0.5, LOG_THICK * 0.3) if _sideways() else Vector2(LOG_THICK * 0.52, LOG_LENGTH * 0.5)
	_lane.draw_set_transform(at + Vector2(4.0, 5.0), 0.0, Vector2(radii.x * fade, radii.y * fade) / 32.0)
	_lane.draw_circle(Vector2.ZERO, 32.0, Color(SHADOW_COLOR, SHADOW_COLOR.a * fade))
	_lane.draw_set_transform(Vector2.ZERO)
