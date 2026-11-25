@tool
extends Node2D
class_name RamCart
## The runaway cart (docs/godot/DUNGEONS.md "Mechanisms: the knock target, the ram, the runaway
## cart"; `object.ram-cart`; the rework plan docs/design/2026-11-23-dungeons-2-3-rework.md "The
## Crystal Mine"): a cart heaped with ore, held on a slope by a brake (a lever and a chock) that a
## knock target's rope holds. Let go (`trigger()`, the kit's generic hookup), the brake snaps, the
## cart rolls down its line gathering speed and rams what stands on the rails. It is not the mine's
## travel cart (mine_cart.gd), which the slime rides.
##
## **Placing.** The node is the cart's place while held; `points` is its line from there (world
## units from the node, the first point the cart's own place: (0, 0)). Straight lines are what it is
## made for; a line with a bend is followed leg by leg (the cart turns at the corner at once). It
## draws its own rails along the line (`draw_rails`; game/crystal_mine/mine_rails.gd), its brake
## beside the start, a buffer stop past the line's end (`buffer_stop`), and, with `returns`, the
## pulley post and the counterweight that haul it back.
##
## **The cycle** (`dungeon.ramCart` in game-constants.json): held (it rocks a little against its
## chock, the ore glints) -> `trigger()` -> the brake snaps `brakeMs` (120) -> it rolls from
## `startSpeed` up to `maxSpeed` by `accel` (seen from the side the wheels turn and sparks fly
## behind; seen from the front, on a line up or down the screen, the bin jolts as each axle crosses a
## sleeper's joint and rocks side to side, the ore heap jostles in it and two loose stones hop, and
## sparks fly at both wheels; the rattle's pitch rises) ->
## the line's end (the buffer stop: a bump, a shake, ore jumps out) or a node it stops against.
## Then, with `returns`: after `restMs` the counterweight's chain hauls it back over `returnMs`
## (8000, a click every `ratchetEveryMs`; a heavy iron chain from the pulley post, its links drawn
## big enough to read), the chock drops, its knock target is rearmed (`rearm()`)
## and it emits `ready_again`. Without `returns` it stays where it ended, for good (its record,
## `cart_id`): that is how a cart opens a shortcut.
##
## **What it rams** (game/dungeon/mechanism_strike.gd, on its own elevation level, each thing once
## per run): a node in the group `ram_breakable` (the rail gate) gets `on_ram_hit(self)` and the cart
## runs on through; a node with `on_mechanism_hit(kind, source)` is found a little ahead, the cart
## rolls on until its front (`CONTACT_SIDE` or `CONTACT_FRONT` ahead of its place) touches the near
## edge of that node's hurtbox, and stops there: the call (kind `&"cart"`), the bump, the dust and
## the sparks all come at that touch (the ore falls back round the cart); an enemy takes `damage` and is knocked aside, off the rails; the slime
## takes `slimeDamage` and is knocked aside too (its invulnerability and a Roll's i-frames pass it).
## Standing still (held, or at its line's end) the cart is solid.
##
## **Kicked back** (the Crystal Colossus's plate fight, game/scripts/crystal_colossus.gd): a node it
## stopped against may `hold_for_kick()` it there (it waits, solid, instead of its haul back after
## `restMs`) and then `kick_back(ms)` it: it rolls home up its line over `ms`, fast at first and slowing
## to its chock (no chain clicks), and is held again as after a haul back (the brake, its target
## rearmed, `ready_again`). `let_go()` gives a held cart back to its haul back. Only a cart that comes
## back (`returns` or `through`).
##
## **Through** (`through`; the Colossus lab, the owner on 2026-11-24: "the cart [comes] from outside the
## scenes from a tunnel in the walls ... if he is not hit the cart should go through the scene side to
## side like a passing cart in a mine"): its line runs from a tunnel mouth to a tunnel mouth (its first
## and last points inside them; the mouths are the mine gate's open doorway, `mine-gate-leaves.webp`,
## turned and foreshortened as the kit's doors in a side wall, drawn over the cart). Held, it waits in
## its start tunnel, its front showing (no lever, chock, buffer stop or counterweight: the brake is in
## the tunnel, where a target's rope runs). Let go, it rolls the whole line; meeting nothing, it rolls
## on into the far tunnel and is gone (it fades in its last `TUNNEL_FADE` units), and after `restMs`
## the next cart comes out of the start tunnel (`APPEAR_MS`): held again, its target rearmed. Stopped
## against a node with the hook, it waits there to be kicked back (or, let go, rolls home slowly
## over `returnMs`).
##
## **Into the next room** (`rolls_out`, `arrives`; the Crystal Mine's rooms, 2026-11-25: M7's cart
## bursts the rail gate in its west doorway and rolls on into M1): a cart with `rolls_out` has its line
## end in a doorway's passage; at its end it rolls on out of the room (it fades in its last
## `TUNNEL_FADE` units, as into a tunnel) and is gone for good (its record), with no buffer stop. The
## room it rolls into has a cart with `arrives` and the same `cart_id` on a line from that doorway to a
## buffer stop: no brake and no cart until the record is set, then the cart stands at its line's end.
## Neither comes back (`returns` and `through` stay off).
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const MechanismStrike := preload("res://game/dungeon/mechanism_strike.gd")
const MechanismDebris := preload("res://game/dungeon/mechanism_debris.gd")
const MineRails := preload("res://game/crystal_mine/mine_rails.gd")

const KIND := &"cart"
const ART := "res://asset/MAPS/objects/mechanisms/"
## The pictures are packed at 2 px a unit.
const ART_SCALE := 0.5
## The cart's art (world units): the side view's and the front view's sizes, the side view's wheels
## from its bottom middle (it faces left) and their radius, the ore's top over the floor.
const SIDE_SIZE := Vector2(84.0, 89.0)
const FRONT_SIZE := Vector2(60.5, 89.5)
const WHEELS: Array[Vector2] = [Vector2(-15.13, -15.82), Vector2(19.35, -15.82)]
const WHEEL_RADIUS := 15.21
const ORE_TOP := 70.0
## What it sweeps: this far ahead of its middle and to each side of the line.
const NOSE := 36.0
const HALF_WIDTH := 30.0
## How far its front reaches ahead of its place, to touch a node it stops against: the side
## picture's bumper (a line across the screen) or its footprint's front edge (up or down it).
const CONTACT_SIDE := 42.0
const CONTACT_FRONT := 8.0
## Its solid box while it stands still (along the line, across it).
const BODY_SIZE := Vector2(64.0, 30.0)
## The brake beside the start: the lever's foot and the chock's place from the node (the chock
## along the line, the lever across it), where the kicked chock ends, the lever's and chock's sizes.
const LEVER_ASIDE := 40.0
const LEVER_SIZE := Vector2(29.5, 46.0)
const LEVER_AHEAD := 26.0
const CHOCK_AHEAD := 36.0
const CHOCK_AHEAD_FRONT := 9.0
const CHOCK_ASIDE_FRONT := 22.0
const CHOCK_KICKED := Vector2(30.0, 10.0)
const CHOCK_SIZE := Vector2(22.0, 21.5)
## The way back: the pulley post behind the start, the counterweight beside it.
const PULLEY_BEHIND := 62.0
const PULLEY_SIZE := Vector2(30.0, 60.0)
const WEIGHT_SIZE := Vector2(21.0, 46.0)
const WEIGHT_ASIDE := 22.0
const WEIGHT_TRAVEL := 26.0
## The buffer stop past the line's end, and its solid box.
const BUFFER_FRONT := Vector2(96.0, 57.0)
const BUFFER_SIDE := Vector2(45.5, 57.0)
const BUFFER_GAP := 40.0
const BUFFER_BODY := Vector2(72.0, 22.0)
const BUFFER_SIDE_DROP := 18.0
const ORE := "res://asset/MAPS/objects/mechanisms/ram-cart-ore-6x1.webp"
const ORE_CELLS := 6
const ORE_CELL_PX := 48.0
## The rails reach this far behind the start.
const RAILS_BEHIND := 78.0
## The bump: how long the cart rocks on its stop (ms), how far it bounces back, how far it tips.
const BUMP_MS := 420.0
const BUMP_BACK := 6.0
const BUMP_TIP := 0.09
## The roll's rattle: the cart hops this much, once every this far.
const RATTLE_PX := 1.6
const RATTLE_EVERY := 21.0
## The rattle's loop: its pitch at the start speed, at the top speed and while hauled back.
const PITCH_SLOW := 0.8
const PITCH_FAST := 1.3
const PITCH_HAUL := 0.6
## Seen from the front (a line up or down the screen) the picture is cut in two at its rim: the ore
## heap (rows above `FRONT_HEAP_PX`) behind the bin (rows from `FRONT_BIN_PX`, the rim's iron band
## and the wheels), so the load can jostle in its bin. Rows in the picture's pixels.
const FRONT_HEAP_PX := 68.0
const FRONT_BIN_PX := 56.0
## Its two wheels in the front picture (from its bottom middle) and the rails' sleepers' spacing and
## first one along the line (game/crystal_mine/mine_rails.gd: its sleepers start half a space past
## the rails' start, RAILS_BEHIND behind the cart's place), the axles' distance from the cart's middle.
const FRONT_WHEELS: Array[Vector2] = [Vector2(-23.5, -3.0), Vector2(23.5, -3.0)]
const SLEEPER_EVERY := 22.0
const AXLE_AT := 16.0
## Each axle over a sleeper's joint jolts the bin up this much (units at the top speed; less while
## slow), the jolt dying away over `JOLT_FADE` units of travel; the bin rocks this far (radians) to
## one side and the other on alternate sleepers; the ore heap lags the bin by `ORE_LAG` units and
## bounces `ORE_JOSTLE` times as high, tilting `ORE_TILT`; the share of the jolt left while slowest.
const JOLT_PX := 2.6
const JOLT_FADE := 5.0
const JOLT_ROCK := 0.035
const ORE_LAG := 4.0
const ORE_JOSTLE := 1.15
const ORE_TILT := 0.03
const JOLT_SLOW := 0.35
## Two loose stones on the heap's top (ore sheet cells), their places and size; they hop on the
## harder jolts.
const LOOSE_ORE: Array[Vector2] = [Vector2(-13.0, -74.0), Vector2(12.0, -71.0)]
const LOOSE_CELLS: Array[int] = [3, 2]
const LOOSE_SCALE := 0.42
const LOOSE_HOP := 3.2
const SHADOW_COLOR := Color(0.05, 0.04, 0.03, 0.34)
const SPARK_TINT := Color("#ffcf6b")
const GLINT := Color(0.85, 0.97, 1.0)
const GLINTS: Array[Vector2] = [Vector2(-12.0, -72.0), Vector2(9.0, -79.0), Vector2(18.0, -64.0)]
const GLINT_PERIOD_MS := 1900.0
## The haul chain: big iron links that read at game size (a face-on oval, then an edge-on bar), its
## outline, iron and shine, and its shadow on the floor.
const CHAIN_OUTLINE := Color("#1b1513")
const CHAIN_IRON := Color("#5f554d")
const CHAIN_SHINE := Color("#b9ada0")
const CHAIN_SHADOW := Color(0.04, 0.03, 0.02, 0.3)
const LINK_PX := 12.0
const LINK_WIDTH := 3.4
const CUE_BRAKE := &"CartBrake"
const CUE_ROLL := &"CartRoll"
const CUE_BUMP := &"CartBump"
const CUE_RATCHET := &"RamRatchet"
const DUST := &"dodge-dust"
const SPARK := &"hit-spark"
## A line through (`through`): the tunnel mouths' picture (the mine gate's open doorway, the leaf
## strip's right half), how deep it is drawn (foreshortened, as a door in a side wall or the south
## wall; a mouth in a north wall, opening down the screen, stands whole, face on), how far each
## mouth stands from its line's end point (the cart waits that far inside), how far the cart fades as
## it rolls into the far tunnel, and how long the next one takes to come out of the start tunnel (ms).
const TUNNEL_ART := "res://asset/MAPS/objects/dungeon/doorways/mine-gate-leaves.webp"
const TUNNEL_REGION := Rect2(256.0, 0.0, 256.0, 256.0)
const TUNNEL_DEPTH := 0.55
const TUNNEL_INSET := 44.0
const TUNNEL_FADE := 90.0
const APPEAR_MS := 450.0

enum State { HELD, BRAKE, ROLL, BUMP, REST, RETURN, SPENT, GONE, APPEAR }

## Its brake was knocked off. Payload: {"cartId"}.
signal released(payload: Dictionary)
## It stopped: at its line's end, or against `by` (a node with `on_mechanism_hit`). Payload:
## {"cartId", "by": Node or null, "hits": how many things it rammed}.
signal bumped(payload: Dictionary)
## It is hauled back and held again. Payload: {"cartId"}.
signal ready_again(payload: Dictionary)

## Its line, from the node (world units): the cart's own place first.
@export var points: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(0, 384)]):
	set(value):
		points = value
		_layout()
## Hauled back to its start after each run; off: it stays where it ends, for good.
@export var returns: bool = false:
	set(value):
		returns = value
		_layout()
## Its id (its record when it does not return; the payloads carry it).
@export var cart_id: String = ""
## Draws its own rails along the line.
@export var draw_rails: bool = true:
	set(value):
		draw_rails = value
		_layout()
## A buffer stop past the line's end.
@export var buffer_stop: bool = true:
	set(value):
		buffer_stop = value
		_layout()
## Its line runs tunnel to tunnel (see above): a cart that meets nothing rolls on into the far tunnel
## and the next comes out of the start one.
@export var through: bool = false:
	set(value):
		through = value
		_layout()
## Its line ends in a doorway's passage: at its end it rolls on out of the room and is gone for good
## (see "Into the next room" above).
@export var rolls_out: bool = false:
	set(value):
		rolls_out = value
		_layout()
## The far end of a line that a cart (`rolls_out`, the same `cart_id`) rolls out on from the next room:
## nothing but its rails and buffer stop until that cart has run, then the cart at its line's end.
@export var arrives: bool = false:
	set(value):
		arrives = value
		_layout()
## The area its hits are sent from (the damage router wants one; it needs no shape).
@export var attack_area: Area2D

var _state: State = State.HELD
var _since_ms := 0.0
var _last_ms := 0.0
## How far along its line it is (units), how fast (units/s), and where the last step left it.
var _travelled := 0.0
var _speed := 0.0
var _swept := 0.0
var _struck: Dictionary = {}
var _hits := 0
## A node with the hook met ahead: where along the line the cart's front touches it (-1: none yet),
## and the node.
var _stop_at := -1.0
var _stop_by: Node
var _sparked := 0.0
var _teeth := 0
var _return_from := 0.0
var _knock_target: Node
var _roll_player: Node
var _rails: Node2D
var _floor: Node2D
var _cart: Node2D
var _look: Sprite2D
## The front view's ore heap (behind `_look`, the bin) and the loose stones on it.
var _heap: Sprite2D
var _loose: Array[Sprite2D] = []
var _wheels: Array[Sprite2D] = []
var _glints: Node2D
var _cart_body: StaticBody2D
var _lever: Sprite2D
var _chock: Sprite2D
var _pulley: Sprite2D
var _weight: Sprite2D
var _buffer: Sprite2D
var _buffer_body: StaticBody2D
var _sway_offset := 0.0
var _side_art: Texture2D
var _front_art: Texture2D
var _returned := false
## Held where it stopped for a kick (`hold_for_kick`), and the kick's roll home (ms; 0: the haul back).
var _held_for_kick := false
var _kick_ms := 0.0
## A line through: its two tunnel mouths.
var _mouths: Array[Sprite2D] = []


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
	_since_ms = Services.now_ms()
	_last_ms = _since_ms
	if arrives:
		# nothing stands here until the cart in the next room has run (`_restore_in_tree`)
		_set_solid(false)
	_restore_in_tree.call_deferred()


func _exit_tree() -> void:
	_stop_roll_sound()


# --- what it answers ------------------------------------------------------------------------------

## The kit's generic hookup: knocks the brake off. Nothing unless it is held. A payload with a
## "source" that can `rearm` (a knock target) is remembered as its knock target.
func trigger(payload: Variant = null) -> void:
	if payload is Dictionary and (payload as Dictionary).get("source") is Node:
		var source: Node = (payload as Dictionary)["source"]
		if source.has_method(&"rearm"):
			_knock_target = source
	if _state != State.HELD or arrives or Engine.is_editor_hint():
		return
	if _knock_target != null and is_instance_valid(_knock_target) and _knock_target.has_method(&"go_slack"):
		_knock_target.call(&"go_slack")
	_enter(State.BRAKE)
	_struck.clear()
	_hits = 0
	_stop_at = -1.0
	_stop_by = null
	_swept = 0.0
	_sparked = 0.0
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_BRAKE)
		feel.particles(DUST, global_position + _direction_at(0.0) * CHOCK_AHEAD)
	released.emit({"cartId": cart_id})


## The knock target that holds its brake (a knock target tells its mechanisms when the world is built).
func set_knock_target(target: Node) -> void:
	_knock_target = target


## The knock target that holds its brake (null when none was set, or it is gone): the Crystal
## Colossus lights it up while he stands hot on this line.
func get_knock_target() -> Node:
	return _knock_target if _knock_target != null and is_instance_valid(_knock_target) else null


func is_held() -> bool:
	return _state == State.HELD


## For the tests and the films: "held", "brake", "roll", "bump", "rest", "return", "spent", "gone"
## (through its far tunnel) or "appear" (the next one coming out of its start tunnel).
func state_name() -> String:
	return ["held", "brake", "roll", "bump", "rest", "return", "spent", "gone", "appear"][_state]


## True for a cart that comes back after a run: hauled back (`returns`) or the next one out of its
## tunnel (`through`).
func _comes_back() -> bool:
	return returns or through


## Where a knock target's rope ends: the brake lever's foot (global); through, the start tunnel's mouth.
func rope_anchor() -> Vector2:
	if through:
		return global_position + _mouth_at(true) + Vector2(0.0, 6.0)
	return global_position + _lever_at() + Vector2(0.0, 2.0)


## Where the cart is now (global, on the floor).
func cart_point() -> Vector2:
	return global_position + _point_at(_travelled)


## Something it stopped against will kick it back (the Crystal Colossus): it waits where it stopped
## instead of being hauled back. Only a cart that returns, at the end of a run.
func hold_for_kick() -> void:
	if _comes_back() and _state in [State.BUMP, State.REST]:
		_held_for_kick = true


## A cart held for a kick is hauled back as ever after all (the kicker fell, went up his wall, left).
func let_go() -> void:
	_held_for_kick = false


## True while it waits to be kicked back.
func is_held_for_kick() -> bool:
	return _held_for_kick


## Kicked back up its line: it rolls home over `ms` (fast at first, slowing to its chock), then it is
## held again (the brake, its target rearmed). False unless it stands at the end of a run.
func kick_back(ms: float) -> bool:
	if not _comes_back() or not _state in [State.BUMP, State.REST]:
		return false
	_held_for_kick = false
	_kick_ms = maxf(1.0, ms)
	_enter(State.RETURN)
	_return_from = _travelled
	_teeth = 0
	_set_solid(false)
	_start_roll_sound()
	_tune_roll_sound(1.0)
	return true


## Its line's length (units).
func line_length() -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total


# --- the cycle ------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	var now := Services.now_ms()
	var step := maxf(0.0, now - _last_ms) / 1000.0
	_last_ms = now
	var age := now - _since_ms
	match _state:
		State.BRAKE:
			if age >= _number("brakeMs", 120.0):
				_enter(State.ROLL)
				_speed = _number("startSpeed", 140.0)
				_set_solid(false)
				_start_roll_sound()
		State.ROLL:
			_speed = minf(_number("maxSpeed", 560.0), _speed + _number("accel", 520.0) * step)
			var total := line_length()
			var before := _travelled
			_travelled = minf(total, _travelled + _speed * step)
			# closing on a hooked node met ahead: it stops with its front against it
			if _stop_at >= 0.0 and _travelled >= _stop_at:
				_travelled = _stop_at
				_bump(_stop_by)
				return
			_tune_roll_sound(clampf((_speed - _number("startSpeed", 140.0)) / maxf(1.0, _number("maxSpeed", 560.0) - _number("startSpeed", 140.0)), 0.0, 1.0))
			_sparks()
			var met := _ram()
			var hooked := met.get("stopped_by") as Node
			if hooked != null and _stop_at < 0.0:
				var contact := clampf(_contact_at(met.get("stopped_area") as Area2D), before, total)
				if contact <= _travelled:
					_travelled = contact
					_bump(hooked)
					return
				_stop_at = contact
				_stop_by = hooked
			if _travelled >= total:
				if through:
					_vanish()
				elif rolls_out:
					_roll_out()
				else:
					_bump(null)
		State.BUMP:
			if age >= BUMP_MS:
				_enter(State.REST if _comes_back() else State.SPENT)
		State.REST:
			if age >= _number("restMs", 1500.0) and not _held_for_kick:
				_enter(State.RETURN)
				_return_from = _travelled
				_teeth = 0
				_kick_ms = 0.0
				_set_solid(false)
				_start_roll_sound()
				_tune_roll_sound(-1.0)
		State.RETURN:
			var kicked := _kick_ms > 0.0
			var t := clampf(age / (_kick_ms if kicked else maxf(1.0, _number("returnMs", 8000.0))), 0.0, 1.0)
			# kicked: fast at first, slowing to its chock; hauled: the counterweight's slow ease
			var home := 1.0 - (1.0 - t) * (1.0 - t) if kicked else t * t * (3.0 - 2.0 * t)
			_travelled = _return_from * (1.0 - home)
			var teeth := int(age / maxf(1.0, _number("ratchetEveryMs", 400.0)))
			if teeth > _teeth and t < 1.0 and not kicked:
				_teeth = teeth
				var feel := Services.feel()
				if feel != null:
					feel.audio_cue(CUE_RATCHET)
			if t >= 1.0:
				_travelled = 0.0
				_kick_ms = 0.0
				_stop_roll_sound()
				_home_again()
		State.GONE:
			if age >= _number("restMs", 1500.0):
				_travelled = 0.0
				_enter(State.APPEAR)
		State.APPEAR:
			if age >= APPEAR_MS:
				_home_again()


## Held again at its start (hauled or kicked home, or the next one out of its tunnel): the brake, its
## target rearmed.
func _home_again() -> void:
	_returned = true
	_enter(State.HELD)
	_set_solid(true)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_BRAKE, {"pitch": 0.8})
		if not through:
			feel.particles(DUST, global_position + _direction_at(0.0) * CHOCK_AHEAD)
	if _knock_target != null and is_instance_valid(_knock_target) and _knock_target.has_method(&"rearm"):
		_knock_target.call(&"rearm")
	ready_again.emit({"cartId": cart_id})


## Through: it rolled the whole line into the far tunnel and is gone.
func _vanish() -> void:
	_speed = 0.0
	_stop_roll_sound()
	bumped.emit({"cartId": cart_id, "by": null, "hits": _hits})
	_enter(State.GONE)


## Into the next room (`rolls_out`): it rolled on out through the doorway, gone for good.
func _roll_out() -> void:
	_speed = 0.0
	_stop_roll_sound()
	_set_solid(false)
	DungeonState.mark_done(get_tree(), _record_key())
	bumped.emit({"cartId": cart_id, "by": null, "hits": _hits})
	_enter(State.SPENT)


func _enter(state: State) -> void:
	_state = state
	_since_ms = Services.now_ms()


## What the cart passed over since the last step (ahead of it as far as its nose, or its front where
## that reaches further). Returns the sweep's answer (`MechanismStrike.sweep`): a node with the hook
## is only found here ("stopped_by", "stopped_area"); it is called when the cart's front touches it.
func _ram() -> Dictionary:
	if attack_area == null:
		return {}
	var along := _direction_at(_travelled)
	var across := Vector2(-along.y, along.x) * HALF_WIDTH
	var from := global_position + _point_at(maxf(0.0, _swept - NOSE * 0.5))
	var to := global_position + _point_at(_travelled) + along * maxf(NOSE, _contact_reach(along))
	_swept = _travelled
	var rect := Rect2(from - across, Vector2.ZERO).expand(from + across).expand(to - across).expand(to + across)
	var out := MechanismStrike.sweep(self, attack_area, rect, along, KIND, _numbers(), _struck, true, true)
	_hits += int(out["hits"])
	return out


## How far its front reaches ahead of its place, the way it runs.
func _contact_reach(along: Vector2) -> float:
	return CONTACT_SIDE if _sideways(along) else CONTACT_FRONT


## Where along its line the cart stands with its front against `area`'s near edge (the hurtbox's
## rectangle, `MechanismStrike.area_rect`); where it is now when there is no area.
func _contact_at(area: Area2D) -> float:
	if area == null or not is_instance_valid(area):
		return _travelled
	var along := _direction_at(_travelled)
	var place := cart_point()
	var rect := MechanismStrike.area_rect(area)
	var near := INF
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		near = minf(near, (corner - place).dot(along))
	return _travelled + near - _contact_reach(along)


## It stops: at its line's end, or against `by`.
func _bump(by: Node) -> void:
	_enter(State.BUMP)
	_set_solid(true)
	_speed = 0.0
	_stop_roll_sound()
	var at := cart_point()
	var along := _direction_at(_travelled)
	# against a node with the hook, it is struck now, at the touch (the sweep only found it)
	if by != null:
		MechanismStrike.call_hook(by, KIND, self)
	# the bump where its front is: at the buffer, or against the node
	var front := at + along * (_contact_reach(along) if by != null else NOSE)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_BUMP)
		feel.shake(_number("bumpShakeMs", 200.0), _number("bumpShakeIntensity", 0.006))
		feel.particles(DUST, front)
		feel.burst(SPARK, front - Vector2(0.0, 14.0), -along, SPARK_TINT, 1.0)
	# the ore jumps: a few pieces fly on over the stop and out of the cart (against a node they fall
	# back round the cart instead of onto it)
	var ore_way := along if by == null else -along
	var ore_spread := 110.0 if by == null else 170.0
	MechanismDebris.throw(get_parent(), at + along * 10.0, {"sheet": ORE, "cells": ORE_CELLS, "cell_px": ORE_CELL_PX,
		"pieces": [0, 1, 2, 3, 4, 5], "direction": ore_way, "spread_deg": ore_spread, "speed_min": 50.0, "speed_max": 150.0,
		"rise_min": 16.0, "rise_max": 34.0, "air_ms": 520.0, "lie_ms": 1700.0, "fade_ms": 600.0,
		"seed": 11 + get_instance_id() % 71, "from_px": 16.0, "start_rise": ORE_TOP})
	if not _comes_back():
		DungeonState.mark_done(get_tree(), _record_key())
	bumped.emit({"cartId": cart_id, "by": by, "hits": _hits})


func _sparks() -> void:
	if _speed < _number("sparkSpeed", 260.0) or _travelled - _sparked < _number("sparkEveryPx", 46.0):
		return
	_sparked = _travelled
	var feel := Services.feel()
	if feel == null:
		return
	var along := _direction_at(_travelled)
	if _sideways(along):
		feel.burst(SPARK, cart_point() - along * 16.0 - Vector2(0.0, 2.0), -along, SPARK_TINT, 0.45)
		return
	# seen from the front: at both wheels, flying back and out
	for wheel: Vector2 in FRONT_WHEELS:
		var out := (-along + Vector2(signf(wheel.x) * 0.6, 0.0)).normalized()
		feel.burst(SPARK, cart_point() + wheel, out, SPARK_TINT, 0.38)


func _record_key() -> String:
	return DungeonState.object_key(self, "ram-cart:" + (cart_id if not cart_id.is_empty() else String(name)))


## Built again after a run that did not return: it stands at its line's end.
func _restore_in_tree() -> void:
	if not is_inside_tree() or _comes_back() or _state != State.HELD:
		return
	if DungeonState.is_done(get_tree(), _record_key()):
		_state = State.SPENT
		_travelled = line_length()
		# gone on into the next room, it leaves nothing to bump into; arrived, it stands at the stop
		_set_solid(not rolls_out)
		if _knock_target != null and is_instance_valid(_knock_target) and _knock_target.has_method(&"go_slack"):
			_knock_target.call(&"go_slack")
		_place()


func _number(key: String, fallback: float) -> float:
	return DungeonState.number("ramCart." + key, fallback)


func _numbers() -> Dictionary:
	var constants := Services.constants()
	return constants.dictionary("dungeon.ramCart") if constants != null else {}


# --- its line -------------------------------------------------------------------------------------

## The point `distance` along the line, from the node.
func _point_at(distance: float) -> Vector2:
	if points.size() == 0:
		return Vector2.ZERO
	var left := distance
	for i in points.size() - 1:
		var leg := points[i].distance_to(points[i + 1])
		if left <= leg or i == points.size() - 2:
			return points[i].lerp(points[i + 1], clampf(left / maxf(0.001, leg), 0.0, 1.0)) if leg > 0.0 else points[i]
		left -= leg
	return points[0]


## The way the line runs `distance` along it (unit).
func _direction_at(distance: float) -> Vector2:
	var left := distance
	for i in points.size() - 1:
		var leg := points[i].distance_to(points[i + 1])
		if leg <= 0.0:
			continue
		if left < leg or i == points.size() - 2:
			return (points[i + 1] - points[i]) / leg
		left -= leg
	return Vector2.DOWN


## True where the line runs across the screen (the cart shows its side).
func _sideways(direction: Vector2) -> bool:
	return absf(direction.x) >= absf(direction.y)


## The side of the line the brake stands on: toward the screen's bottom for a line across the
## screen (in front of the cart, where it shows), to the right for a line up or down it.
func _brake_side() -> Vector2:
	return Vector2.DOWN if _sideways(_direction_at(0.0)) else Vector2.RIGHT


func _lever_at() -> Vector2:
	return _brake_side() * LEVER_ASIDE + _direction_at(0.0) * LEVER_AHEAD


## The chock's place while it holds: under the leading wheel.
func _chock_at() -> Vector2:
	var along := _direction_at(0.0)
	if _sideways(along):
		return along * CHOCK_AHEAD
	return along * CHOCK_AHEAD_FRONT + _brake_side() * CHOCK_ASIDE_FRONT


func _pulley_at() -> Vector2:
	return -_direction_at(0.0) * PULLEY_BEHIND


func _buffer_at() -> Vector2:
	var total := line_length()
	return _point_at(total) + _direction_at(total) * (NOSE + BUFFER_GAP * 0.5)


# --- the looks ------------------------------------------------------------------------------------

func _build() -> void:
	if _cart != null:
		return
	_rails = Node2D.new()
	_rails.name = "Rails"
	_rails.set_script(MineRails)
	add_child(_rails, false, Node.INTERNAL_MODE_BACK)
	_floor = Node2D.new()
	_floor.name = "Floor"
	_floor.z_index = -1
	add_child(_floor, false, Node.INTERNAL_MODE_BACK)
	_floor.draw.connect(_draw_floor)
	_pulley = _sprite("ram-cart-pulley.webp", PULLEY_SIZE)
	add_child(_pulley, false, Node.INTERNAL_MODE_BACK)
	_weight = _sprite("ram-cart-counterweight.webp", WEIGHT_SIZE)
	_pulley.add_child(_weight)
	_lever = _sprite("ram-cart-brake-lever.webp", LEVER_SIZE)
	add_child(_lever, false, Node.INTERNAL_MODE_BACK)
	_buffer = Sprite2D.new()
	_buffer.scale = Vector2.ONE * ART_SCALE
	_buffer.centered = false
	add_child(_buffer, false, Node.INTERNAL_MODE_BACK)
	_buffer_body = _box_body(BUFFER_BODY)
	add_child(_buffer_body, false, Node.INTERNAL_MODE_BACK)
	_cart = Node2D.new()
	_cart.name = "Cart"
	add_child(_cart, false, Node.INTERNAL_MODE_BACK)
	_side_art = SheetSprite.load_picture(ART + "ram-cart-side.webp")
	_front_art = SheetSprite.load_picture(ART + "ram-cart-front.webp")
	# the front view's heap, drawn before (behind) the bin
	_heap = Sprite2D.new()
	_heap.name = "Heap"
	_heap.texture = _front_art
	_heap.scale = Vector2.ONE * ART_SCALE
	_heap.centered = false
	_heap.region_enabled = true
	_heap.region_rect = Rect2(0.0, 0.0, FRONT_SIZE.x * 2.0, FRONT_HEAP_PX)
	_heap.offset = Vector2(-FRONT_SIZE.x, -FRONT_SIZE.y * 2.0)
	_cart.add_child(_heap)
	var ore_sheet := SheetSprite.load_picture(ORE)
	for i in LOOSE_ORE.size():
		var stone := Sprite2D.new()
		stone.texture = ore_sheet
		stone.hframes = ORE_CELLS
		stone.frame = LOOSE_CELLS[i]
		# under the heap (drawn at ART_SCALE): its places are in the picture's pixels
		stone.scale = Vector2.ONE * LOOSE_SCALE
		stone.position = LOOSE_ORE[i] / ART_SCALE
		stone.offset = Vector2(0.0, -ORE_CELL_PX * 0.35)
		_heap.add_child(stone)
		_loose.append(stone)
	_look = Sprite2D.new()
	_look.scale = Vector2.ONE * ART_SCALE
	_look.centered = false
	_cart.add_child(_look)
	for i in WHEELS.size():
		var wheel := Sprite2D.new()
		wheel.texture = SheetSprite.load_picture(ART + "ram-cart-wheel.webp")
		wheel.scale = Vector2.ONE * ART_SCALE
		_cart.add_child(wheel)
		_wheels.append(wheel)
	_glints = Node2D.new()
	_glints.name = "Glints"
	_cart.add_child(_glints)
	_glints.draw.connect(_draw_glints)
	_cart_body = _box_body(BODY_SIZE)
	_cart.add_child(_cart_body)
	# after the cart: on the same floor line the chock is drawn over the wheel it wedges
	_chock = _sprite("ram-cart-chock.webp", CHOCK_SIZE)
	add_child(_chock, false, Node.INTERNAL_MODE_BACK)
	# Moved every frame from the gameplay clock: no physics interpolation on top.
	for node: Node in [_cart, _floor, _chock, _lever, _pulley]:
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Through: where a tunnel's mouth stands (from the node): `start`'s inside the line's first point
## along it, else the far one's.
func _mouth_at(start: bool) -> Vector2:
	if start:
		return _point_at(0.0) + _direction_at(0.0) * TUNNEL_INSET
	var total := line_length()
	return _point_at(total) - _direction_at(total) * TUNNEL_INSET


## Through: the two tunnel mouths, each its opening toward the room (the picture turned so its front
## faces along the line, foreshortened), drawn over the cart; hidden otherwise.
func _lay_mouths() -> void:
	if through and _mouths.is_empty():
		var art := SheetSprite.load_picture(TUNNEL_ART)
		for i in 2:
			var mouth := Sprite2D.new()
			mouth.name = "Tunnel%d" % i
			mouth.texture = art
			mouth.region_enabled = true
			mouth.region_rect = TUNNEL_REGION
			mouth.z_index = 2
			mouth.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(mouth, false, Node.INTERNAL_MODE_BACK)
			_mouths.append(mouth)
	for i in _mouths.size():
		var mouth := _mouths[i]
		mouth.visible = through and points.size() >= 2
		if not mouth.visible:
			continue
		var start := i == 0
		# the opening faces into the room: along the line out of the start, back along it at the end
		var facing := _direction_at(0.0) if start else -_direction_at(line_length())
		mouth.rotation = atan2(-facing.x, facing.y)
		# in a north wall the doorway stands face on, whole; elsewhere it is seen at a slant
		var north := facing.y > 0.7
		var depth := 1.0 if north else TUNNEL_DEPTH
		mouth.scale = Vector2(ART_SCALE, ART_SCALE * depth)
		# its front edge on the mouth, the rest of it in the wall: the node stands on the mouth (where
		# the doorway meets the floor), the picture behind it
		mouth.position = _mouth_at(start)
		mouth.offset = Vector2(0.0, -TUNNEL_REGION.size.y * 0.5)
		# A doorway in a north wall is sorted by where it meets the floor, as the wall is (this node
		# sorts its children): what stands on the floor before it is drawn over it, a cart inside the
		# tunnel behind it (2026-11-24: the Crystal Colossus was drawn behind the top tunnels). In a
		# side or south wall it stays drawn over everything: a cart leaves there at its own height.
		mouth.z_index = 0 if north else 2


## A picture standing on its bottom middle.
func _sprite(file: String, size: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = SheetSprite.load_picture(ART + file)
	sprite.scale = Vector2.ONE * ART_SCALE
	sprite.centered = false
	sprite.offset = Vector2(-size.x, -size.y * 2.0)
	return sprite


func _box_body(size: Vector2) -> StaticBody2D:
	var made := StaticBody2D.new()
	made.collision_layer = 1
	made.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	made.add_child(shape)
	return made


## The fixed pieces for `points`, `returns`, `draw_rails` and `buffer_stop`.
func _layout() -> void:
	if _cart == null:
		return
	var along := _direction_at(0.0)
	_rails.visible = draw_rails
	if points.size() >= 2:
		var line := PackedVector2Array([points[0] - along * RAILS_BEHIND])
		for i in range(1, points.size()):
			line.append(points[i])
		var last := _direction_at(line_length())
		line[line.size() - 1] = points[points.size() - 1] + last * (NOSE + BUFFER_GAP)
		_rails.set(&"points", line)
	_lever.position = _lever_at()
	_chock.position = _chock_at()
	# through: the brake is in the tunnel, and nothing stops the cart at the far end
	_lever.visible = not through and not arrives
	_chock.visible = not through and not arrives
	_pulley.visible = returns and not through
	_pulley.position = _pulley_at()
	_weight.position = Vector2(WEIGHT_ASIDE, 0.0) / ART_SCALE
	_weight.scale = Vector2.ONE
	_lay_mouths()
	var end := _direction_at(line_length())
	var stop := buffer_stop and not through and not rolls_out
	_buffer.visible = stop
	var buffer_shape := _buffer_body.get_node(^"Shape") as CollisionShape2D
	buffer_shape.set_deferred(&"disabled", not stop)
	if _sideways(end):
		# seen from the side it spans the rails: its foot lies below the line, its box across it
		_buffer.texture = SheetSprite.load_picture(ART + "rail-buffer-side.webp")
		_buffer.offset = Vector2(-BUFFER_SIDE.x, -BUFFER_SIDE.y * 2.0)
		# the picture's bumper faces left: toward a cart coming from the left
		_buffer.flip_h = end.x < 0.0
		_buffer.position = _buffer_at() + Vector2(0.0, BUFFER_SIDE_DROP)
		(buffer_shape.shape as RectangleShape2D).size = Vector2(BUFFER_BODY.y, BUFFER_BODY.x * 0.8)
		_buffer_body.position = _buffer_at()
	else:
		_buffer.texture = SheetSprite.load_picture(ART + "rail-buffer-front.webp")
		_buffer.offset = Vector2(-BUFFER_FRONT.x, -BUFFER_FRONT.y * 2.0)
		_buffer.flip_h = false
		_buffer.position = _buffer_at()
		(buffer_shape.shape as RectangleShape2D).size = BUFFER_BODY
		_buffer_body.position = _buffer_at() - Vector2(0.0, BUFFER_BODY.y * 0.5)
	_place()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_place()


## The cart, its wheels, the brake and the way back, for now.
func _place() -> void:
	if _cart == null:
		return
	var editor := Engine.is_editor_hint()
	var now := 0.0 if editor else Services.now_ms()
	var age := now - _since_ms
	var along := _direction_at(_travelled)
	var side := _sideways(along)
	var at := _point_at(_travelled)
	var hop := 0.0
	var tip := 0.0
	var shift := Vector2.ZERO
	match _state:
		State.HELD:
			# it strains against its chock
			tip = 0.014 * sin((now + _sway_offset) / 300.0) if not editor else 0.0
			shift = along * 0.7 * sin((now + _sway_offset) / 300.0) if not editor else Vector2.ZERO
		State.BRAKE:
			shift = along * 2.0 * clampf(age / maxf(1.0, _number("brakeMs", 120.0)), 0.0, 1.0)
		State.ROLL, State.RETURN:
			hop = RATTLE_PX * absf(sin(_travelled / RATTLE_EVERY * PI)) * (1.0 if _state == State.ROLL else 0.4)
			tip = 0.018 * sin(_travelled / RATTLE_EVERY * PI * 0.7) * (1.0 if _state == State.ROLL else 0.3)
		State.BUMP:
			var t := clampf(age / BUMP_MS, 0.0, 1.0)
			# it tips over its stop, bounces back and settles
			var ring := sin(t * PI * 3.0) * (1.0 - t) * (1.0 - t)
			tip = BUMP_TIP * ring
			shift = -along * BUMP_BACK * sin(t * PI) * (1.0 - t)
			hop = 3.0 * absf(ring)
	_cart.position = at + shift
	_cart.modulate.a = _shown_share(age)
	_cart_body.position = Vector2(0.0, -BODY_SIZE.y * 0.5 if side else -BODY_SIZE.x * 0.35)
	var shape := _cart_body.get_node(^"Shape") as CollisionShape2D
	(shape.shape as RectangleShape2D).size = BODY_SIZE if side else Vector2(BODY_SIZE.y + 16.0, BODY_SIZE.x * 0.7)
	# Seen from the front no wheel turns: the bin jolts on the sleepers' joints and rocks, the ore
	# jostles in it.
	var jolt := Vector3.ZERO
	if not side and not editor and (_state == State.ROLL or _state == State.RETURN):
		jolt = _front_jolt()
	if side:
		_look.texture = _side_art
		_look.region_enabled = false
		_look.offset = Vector2(-SIDE_SIZE.x, -SIDE_SIZE.y * 2.0)
		# the picture faces left
		_look.flip_h = along.x > 0.0
		_look.rotation = tip * (1.0 if along.x > 0.0 else -1.0)
	else:
		_look.texture = _front_art
		_look.region_enabled = true
		_look.region_rect = Rect2(0.0, FRONT_BIN_PX, FRONT_SIZE.x * 2.0, FRONT_SIZE.y * 2.0 - FRONT_BIN_PX)
		_look.offset = Vector2(-FRONT_SIZE.x, -FRONT_SIZE.y * 2.0 + FRONT_BIN_PX)
		_look.flip_h = false
		_look.rotation = tip * 0.6 + JOLT_ROCK * jolt.y
	_look.position = Vector2(0.0, -hop - JOLT_PX * jolt.x)
	_heap.visible = not side
	if not side:
		_heap.position = _look.position - Vector2(0.0, JOLT_PX * ORE_JOSTLE * jolt.z)
		_heap.rotation = _look.rotation + ORE_TILT * jolt.y * jolt.z
		for i in _loose.size():
			# each stone hops on the harder jolts, a little after the heap
			var kick := maxf(0.0, jolt.z - 0.45) * (1.0 if i == 0 else 0.7)
			_loose[i].position = (LOOSE_ORE[i] - Vector2(0.0, LOOSE_HOP * kick * 2.0)) / ART_SCALE
			_loose[i].rotation = 0.25 * kick * (1.0 if i == 0 else -1.0)
	var facing := -1.0 if along.x > 0.0 else 1.0
	for i in _wheels.size():
		var wheel := _wheels[i]
		wheel.visible = side
		var spot := WHEELS[i]
		wheel.position = Vector2(spot.x * facing, spot.y - hop).rotated(_look.rotation)
		# rolling: a turn per circumference, the way it goes
		wheel.rotation = _travelled / WHEEL_RADIUS * (1.0 if along.x > 0.0 else -1.0)
	_glints.position = _heap.position if not side else _look.position
	_glints.queue_redraw()
	# The brake: set while held, knocked off from the snap on, back as the cart comes home.
	var off := 0.0
	match _state:
		State.HELD:
			# hauled home: the chock drops back and the lever is thrown over again
			off = clampf(1.0 - age / 160.0, 0.0, 1.0) if _returned and not editor else 0.0
		State.BRAKE:
			off = clampf(age / maxf(1.0, _number("brakeMs", 120.0)), 0.0, 1.0)
		_:
			off = 1.0
	_show_brake(off)
	# The counterweight rises as the cart runs out and sinks as it hauls the cart home.
	if returns:
		var share := clampf(_travelled / maxf(1.0, line_length()), 0.0, 1.0)
		_weight.position = Vector2(WEIGHT_ASIDE, -WEIGHT_TRAVEL * share) / ART_SCALE
	_floor.queue_redraw()


## How much of the cart shows (0 .. 1): all of it but through a tunnel line, where it fades into the
## far tunnel, is gone, and fades in as the next one comes out of the start tunnel.
func _shown_share(age: float) -> float:
	if Engine.is_editor_hint():
		return 1.0
	if arrives:
		return 1.0 if _state == State.SPENT else 0.0
	if rolls_out:
		match _state:
			State.SPENT:
				return 0.0
			State.ROLL:
				return clampf((line_length() - _travelled) / TUNNEL_FADE, 0.0, 1.0)
		return 1.0
	if not through:
		return 1.0
	match _state:
		State.GONE:
			return 0.0
		State.APPEAR:
			return clampf(age / APPEAR_MS, 0.0, 1.0)
		State.ROLL:
			return clampf((line_length() - _travelled) / TUNNEL_FADE, 0.0, 1.0)
	return 1.0


## The front view's rattle now: x the bin's jolt (0 .. 1: both axles just over a sleeper's joint at
## the top speed), y its rock (-1 .. 1, the side alternating sleeper by sleeper), z the ore's jolt (as
## x, a few units later). Hauled back slowly, a share `JOLT_SLOW` of it.
func _front_jolt() -> Vector3:
	var share := JOLT_SLOW
	if _state == State.ROLL:
		var start := _number("startSpeed", 140.0)
		share = lerpf(JOLT_SLOW, 1.0, clampf((_speed - start) / maxf(1.0, _number("maxSpeed", 560.0) - start), 0.0, 1.0))
	var first := -RAILS_BEHIND + SLEEPER_EVERY * 0.5
	var out := Vector3.ZERO
	for axle: float in [-AXLE_AT, AXLE_AT]:
		var over := _travelled + axle - first
		var kick := exp(-fposmod(over, SLEEPER_EVERY) / JOLT_FADE)
		out.x += kick * 0.5
		out.y += kick * 0.5 * (1.0 if posmod(floori(over / SLEEPER_EVERY), 2) == 0 else -1.0)
		out.z += exp(-fposmod(over - ORE_LAG, SLEEPER_EVERY) / JOLT_FADE) * 0.5
	return out * share


## The lever and the chock, `off` from set (0) to knocked off (1).
func _show_brake(off: float) -> void:
	var along := _direction_at(0.0)
	var eased := off * off * (3.0 - 2.0 * off)
	# the lever is thrown over (its picture leans one way: it swings through upright to the other)
	_lever.scale = Vector2(ART_SCALE * lerpf(1.0, -1.0, eased), ART_SCALE)
	_lever.offset = Vector2(-LEVER_SIZE.x, -LEVER_SIZE.y * 2.0)
	# the chock is kicked out from under the wheel, with a hop, and lies beside the rails
	var kicked := _chock_at() + _brake_side() * CHOCK_KICKED.x + along * CHOCK_KICKED.y
	_chock.position = _chock_at().lerp(kicked, eased) - Vector2(0.0, 12.0 * sin(PI * off))
	_chock.rotation = eased * 1.9


func _draw_glints() -> void:
	if Engine.is_editor_hint():
		return
	var now := Services.now_ms()
	for i in GLINTS.size():
		var phase := fmod((now + _sway_offset * 3.0) / GLINT_PERIOD_MS + float(i) * 0.37, 1.0)
		# a short twinkle once per period
		var glow := clampf(1.0 - absf(phase - 0.5) * 9.0, 0.0, 1.0)
		if glow <= 0.0:
			continue
		var at := GLINTS[i]
		var along := _direction_at(_travelled)
		if not _sideways(along):
			at.x *= 0.7
		elif along.x > 0.0:
			at.x = -at.x
		var size := 2.0 + 5.0 * glow
		var colour := Color(GLINT, glow)
		_glints.draw_line(at - Vector2(size, 0.0), at + Vector2(size, 0.0), colour, 1.4, true)
		_glints.draw_line(at - Vector2(0.0, size), at + Vector2(0.0, size), colour, 1.4, true)
		_glints.draw_circle(at, 1.2 + glow, colour)


## On the floor: the cart's shadow and, for a cart that returns, the chain that hauls it.
func _draw_floor() -> void:
	var along := _direction_at(_travelled)
	var at := _cart.position if _cart != null else Vector2.ZERO
	var radii := Vector2(38.0, 9.0) if _sideways(along) else Vector2(27.0, 10.0)
	var shown := _cart.modulate.a if _cart != null else 1.0
	_floor.draw_set_transform(at + Vector2(3.0, 1.0), 0.0, radii / 32.0)
	_floor.draw_circle(Vector2.ZERO, 32.0, Color(SHADOW_COLOR, SHADOW_COLOR.a * shown))
	_floor.draw_set_transform(Vector2.ZERO)
	if not returns:
		return
	var from := _pulley_at() + Vector2(0.0, -6.0)
	var to := at - along * 30.0 + Vector2(0.0, -8.0)
	var span := from.distance_to(to)
	if span <= 1.0:
		return
	var count := maxi(2, int(span / LINK_PX))
	_floor.draw_line(from + Vector2(2.5, 3.5), to + Vector2(2.5, 3.5), CHAIN_SHADOW, LINK_WIDTH * 2.0, true)
	# the edge-on links first, the face-on ovals over their ends (each oval holds the bars beside it)
	for i in count:
		if i % 2 == 0:
			continue
		var a := from.lerp(to, float(i) / float(count))
		var b := from.lerp(to, float(i + 1) / float(count))
		var start := a.lerp(b, -0.18)
		var end := a.lerp(b, 1.18)
		_floor.draw_line(start, end, CHAIN_OUTLINE, LINK_WIDTH + 2.2, true)
		_floor.draw_line(start, end, CHAIN_IRON, LINK_WIDTH, true)
		_floor.draw_line(start.lerp(end, 0.2) + Vector2(0.0, -0.8), start.lerp(end, 0.8) + Vector2(0.0, -0.8), CHAIN_SHINE, 1.0, true)
	for i in count:
		if i % 2 == 1:
			continue
		var a := from.lerp(to, float(i) / float(count))
		var b := from.lerp(to, float(i + 1) / float(count))
		_floor.draw_set_transform((a + b) * 0.5, (b - a).angle(), Vector2(1.0, 0.62))
		var radius := LINK_PX * 0.6
		_floor.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 14, CHAIN_OUTLINE, LINK_WIDTH + 2.0, true)
		_floor.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 14, CHAIN_IRON, LINK_WIDTH, true)
		_floor.draw_arc(Vector2(0.0, -0.6), radius, PI * 1.15, PI * 1.85, 6, CHAIN_SHINE, 1.1, true)
		_floor.draw_set_transform(Vector2.ZERO)


# --- solid while it stands, and its rattle ----------------------------------------------------------

func _set_solid(solid: bool) -> void:
	if _cart_body == null:
		return
	(_cart_body.get_node(^"Shape") as CollisionShape2D).set_deferred(&"disabled", not solid)


func _start_roll_sound() -> void:
	var feel := Services.feel()
	if feel == null:
		return
	feel.audio_cue(CUE_ROLL)
	var root: Node = feel.global_audio()
	_roll_player = root.find_child(String(CUE_ROLL), true, false) if root != null else null


## The rattle's pitch for `share` of the way from the start speed to the top speed (-1: hauled back).
func _tune_roll_sound(share: float) -> void:
	if _roll_player == null or not is_instance_valid(_roll_player):
		return
	_roll_player.set(&"pitch_scale", PITCH_HAUL if share < 0.0 else lerpf(PITCH_SLOW, PITCH_FAST, share))


func _stop_roll_sound() -> void:
	if _roll_player == null or not is_instance_valid(_roll_player):
		return
	_roll_player.set(&"pitch_scale", 1.0)
	_roll_player = null
	var feel := Services.feel()
	if feel != null:
		feel.stop_audio_cue(CUE_ROLL)
