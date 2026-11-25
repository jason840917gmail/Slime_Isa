@tool
extends Node2D
class_name KnockTarget
## The knock target (docs/godot/DUNGEONS.md "Mechanisms: the knock target, the ram, the runaway
## cart"; `object.knock-target`; the rework plan docs/design/2026-11-23-dungeons-2-3-rework.md "The
## bosses"): a round wooden practice target (red and white rings, a straw back) on a short post, a
## rope running from its hook to the mechanism it holds back. It is a trigger, never a lock: it lets
## its mechanism go each time it is knocked, and the mechanism winds back by itself.
##
## - **What knocks it:** a thrown thing (a hit tagged `thrown` through the damage router: a pot, a
##   bone, a stunned enemy), the Bow's arrow (`on_arrow_hit`, group `bow_targets`) and a Goo Bomb's
##   blast (`receive_blast`, group `blast_targets`), as the bell (game/scripts/lash_bell.gd) and the
##   cracked winch post (game/scripts/winch_post.gd) take them. A thrown thing reaches it only from
##   its own elevation level, as every thrown thing does.
## - **Everything else** (the Spear, a Roll, the slime's body pushing on its post) is refused as
##   `immune` with a wooden knock (`KnockTargetTap`) and, once per visit, `refusal_text`: the line
##   comes back once the slime has gone `lineResetPx` away.
## - **Knocked:** it spins and rocks for `spinMs` (`KnockTargetHit`, a puff of straw), emits `knocked`
##   and sets off every node in `targets` through `DungeonState.fire` with the payload
##   {"source": this, "targetId"}: each time, never for good, and nothing is recorded. Then it hangs
##   slack (tilted, the rope sagging) and further hits only rock it, until its mechanism calls
##   `rearm()`: it snaps upright with a clack (`KnockTargetRearm`) and emits `rearmed`. A target none
##   of whose `targets` is a mechanism (group `knock_mechanisms`: the ram, the runaway cart) rearms by
##   itself `rearmMs` later.
## - **The rope** is drawn from its hook down the back of the disc to the floor beside the post (just
##   behind it, so it never crosses the target's face), then along the floor
##   through `rope_points` (from this node) to its end: `rope_to` when set, else the first of
##   `targets` that has `rope_anchor()` (a global point). A hemp rope of two twisted strands (the
##   light strand with the darker one's slanted twist marks, a dark outline, a shine) with a soft
##   shadow on the floor, pinned by small iron eyelets (a plate and a ring it runs through): at the
##   foot, at each of `rope_points`, and along a straight run without corners (two or three in all).
##   Taut (straight) while armed; slack, each run between two pins lies in a loose curve. A knock
##   sends a whip along it from the hook to its end (`WHIP_RUN_MS`), held still at the eyelets; the
##   snap upright a smaller one.
## - A mechanism let go by something else calls `go_slack()`, so the target never shows armed while
##   its mechanism is away.
##
## Looks: armed (upright, the rope taut, a slow sway), knocked (the spin), slack, the snap upright.
## Numbers: `dungeon.knockTarget` in game-constants.json.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PushProbe := preload("res://game/dungeon/push_probe.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const MechanismStrike := preload("res://game/dungeon/mechanism_strike.gd")

## What the Bow shoots at, and what a blast reaches (bow_arrow.gd, goo_blast.gd).
const BOW_TARGETS := &"bow_targets"
const BLAST_TARGETS := &"blast_targets"
const RULE := {"priority": 0, "damageMultiplier": 1}
## The hit tag that knocks it: a thrown thing's.
const KNOCKING_TAG := "thrown"
const REASON_IMMUNE := "immune"
const CUE_HIT := &"KnockTargetHit"
const CUE_TAP := &"KnockTargetTap"
const CUE_REARM := &"KnockTargetRearm"
## A hit on a slack target is this much quieter (dB).
const SLACK_HIT_DB := -6.0
const TEXT_RISE := 104.0
## The disc: its pivot on the post's bracket and its middle over the pivot (world units, from the
## node: the post's foot), the hook on its top from its middle.
const PIVOT := Vector2(0.0, -40.0)
const DISC_RISE := 26.0
const HOOK := Vector2(0.0, -33.0)
## Slack, the disc hangs this much lower on its pivot.
const SLACK_DROP := 6.0
## Where the rope meets the floor: beside the post and just behind it (on the side it runs to; right
## when it runs straight up or down the screen). The hanging run from the hook comes down behind the
## disc to it, so it never crosses the target's face.
const ROPE_FOOT := Vector2(18.0, -6.0)
## The rope: a hemp rope of two strands twisted together (the outline, the two strands, a shine
## along its top), its soft shadow on the floor, and where its twist marks fall (units).
const ROPE_DARK := Color("#3e2a19")
const ROPE_LIGHT := Color("#d2ae72")
const ROPE_STRAND := Color("#94703f")
const ROPE_SHINE := Color(1.0, 0.93, 0.76, 0.55)
const ROPE_SHADOW := Color(0.04, 0.03, 0.02, 0.4)
const ROPE_SHADOW_AT := Vector2(3.0, 3.5)
const ROPE_WIDTH := 6.0
const ROPE_CORE := 4.2
const ROPE_SHADOW_WIDTH := 7.0
const TWIST_EVERY := 5.0
const TWIST_SLANT := 2.2
## The slack rope: how far its drop bellies out, and how far each run between two pins swings out
## (a share of the run, at most so many units).
const SAG_DROP := 12.0
const SAG_SHARE := 0.09
const SAG_MAX := 11.0
const ROPE_STEP := 6.0
## The iron eyelets that pin the rope to the floor: the ring's radius and thickness, its plate.
const EYELET_RADIUS := 6.0
const EYELET_RING := 2.4
const EYELET_PLATE := Vector2(16.0, 9.0)
const IRON_DARK := Color("#1d1816")
const IRON := Color("#6d655d")
const IRON_SHINE := Color("#cfc6ba")
## The whip a knock sends along the rope (and a small one when it snaps taut again): its height
## (units), how long it takes to run the rope's length (ms), how long it lasts, its wave's length,
## how far round a pin it is held still.
const WHIP_PX := 7.0
const WHIP_RUN_MS := 260.0
const WHIP_MS := 420.0
const WHIP_WAVE := 34.0
const WHIP_HELD := 16.0
const REARM_WHIP := 0.45
const STRAW_TINT := Color("#e8c25a")
const STRAW_PUFF := &"silk-tuft"
const DUST := &"dodge-dust"

enum State { ARMED, SPIN, SLACK, REARM }

## It was knocked and let its targets go. Payload: {"targetId"}.
signal knocked(payload: Dictionary)
## It snapped upright again. Payload: {"targetId"}.
signal rearmed(payload: Dictionary)

## Its id (the payloads carry it).
@export var target_id: String = ""
## What it lets go: each is set off through DungeonState.fire, every time it is knocked.
@export var targets: Array[NodePath] = []
## Where its rope ends (a Node2D); empty: the first of `targets` with `rope_anchor()`.
@export var rope_to: NodePath
## Points the rope passes on the floor, from this node (world units), before its end.
@export var rope_points: PackedVector2Array = PackedVector2Array():
	set(value):
		rope_points = value
		_redraw_rope()
## Said once per visit when something that cannot knock it touches it.
@export var refusal_text: String = "A good knock from afar would trip it."
## Its post (the body the slime pushes, and what stops an arrow).
@export var body: StaticBody2D
## The shape a thrown thing must hit.
@export var damage_area: Area2D
## The disc on its pivot, the part of it that spins, and its two faces.
@export var disc: Node2D
@export var spinner: Node2D
@export var front: Sprite2D
@export var back: Sprite2D

var _state: State = State.ARMED
## When the state began (the gameplay clock) and, for a target with no mechanism, when it rearms.
var _since_ms := 0.0
var _rearm_at_ms := -1.0
var _waits_for_mechanism := false
## The slack share of the looks (0 armed, 1 slack), and the rocking after a hit on a slack target.
var _slack := 0.0
var _rock_from_ms := -1.0
var _rock_sign := 1.0
var _said := false
var _next_tap_ms := 0.0
var _registered: Area2D
var _rope_top: Node2D
var _rope_floor: Node2D
var _sway_offset := 0.0
## The last whip along the rope: when it began (the gameplay clock; -1: none) and how strong.
var _whip_from_ms := -1.0
var _whip_strength := 1.0


func _enter_tree() -> void:
	add_to_group(BOW_TARGETS)
	add_to_group(BLAST_TARGETS)


func _ready() -> void:
	_make_rope()
	_show()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_sway_offset = float(get_instance_id() % 1000)
	var router := Services.router()
	if damage_area != null and router != null:
		router.register_area(damage_area, self, RULE, [])
		_registered = damage_area
	_introduce.call_deferred()


func _exit_tree() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


## Tells each mechanism among its targets who holds it back (`set_knock_target`), so a mechanism let
## go by something else can slacken this target and rearm it.
func _introduce() -> void:
	if not is_inside_tree():
		return
	for path: NodePath in targets:
		var node := get_node_or_null(path)
		if node != null and node.has_method(&"set_knock_target"):
			node.call(&"set_knock_target", self)
	_redraw_rope()


# --- what it answers ------------------------------------------------------------------------------

func is_armed() -> bool:
	return _state == State.ARMED


## For the tests and the films: "armed", "spin", "slack" or "rearm".
func state_name() -> String:
	return ["armed", "spin", "slack", "rearm"][_state]


## The level and line tests of a throw and an arrow look at its post.
func get_body() -> Node2D:
	return body


func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": false}


## Only a thrown thing knocks it; anything else is refused with the wooden knock.
func can_receive_damage(input: Dictionary) -> Dictionary:
	var request: Dictionary = input.get("request", {})
	if knocks(request):
		return {"accepted": true}
	tap()
	return {"accepted": false, "reason": REASON_IMMUNE}


## A knocking hit deals no damage (no number over the target). It is committed for the effect it
## carries (every thrown hit's `impact`: a hit with neither damage nor an effect is dropped by the
## resolver, as on the bell).
func mitigate_damage(_input: Dictionary) -> float:
	return 0.0


func commit_damage(_commit: Dictionary) -> void:
	strike()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


## The Bow's arrow. Always true: the arrow is spent on it.
func on_arrow_hit(_hit: Dictionary) -> bool:
	strike()
	return true


## A Goo Bomb's blast whose ellipse holds the disc.
func receive_blast(_hit: Dictionary) -> bool:
	strike()
	return true


func blast_point() -> Vector2:
	return global_position + PIVOT


## True when `request` (a DamageRouter request) is a thrown thing's hit.
static func knocks(request: Dictionary) -> bool:
	var tags: Variant = request.get("weapon_tags", [])
	return tags is Array and (tags as Array).has(KNOCKING_TAG)


# --- the knock ------------------------------------------------------------------------------------

## A knocking hit landed: armed, it is knocked; else it only rocks.
func strike() -> void:
	if _state == State.ARMED:
		_knock()
		return
	_rock_from_ms = Services.now_ms()
	_rock_sign = -_rock_sign
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HIT, {"volume_db": SLACK_HIT_DB})


func _knock() -> void:
	_state = State.SPIN
	_since_ms = Services.now_ms()
	_said = true
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HIT)
		feel.burst(STRAW_PUFF, global_position + PIVOT - Vector2(0.0, DISC_RISE), Vector2.ZERO, STRAW_TINT, 1.0)
		feel.particles(DUST, global_position)
	_whip_from_ms = _since_ms
	_whip_strength = 1.0
	var payload := {"source": self, "targetId": target_id}
	_waits_for_mechanism = false
	for path: NodePath in targets:
		var node := get_node_or_null(path)
		if node == null:
			continue
		if node.is_in_group(MechanismStrike.GROUP_MECHANISMS):
			_waits_for_mechanism = true
		DungeonState.fire(node, payload)
	_rearm_at_ms = -1.0 if _waits_for_mechanism else _since_ms + DungeonState.number("knockTarget.rearmMs", 3000.0)
	knocked.emit({"targetId": target_id})


## Its mechanism was let go by something else: it hangs slack without setting anything off.
func go_slack() -> void:
	if _state != State.ARMED:
		return
	_state = State.SLACK
	_since_ms = Services.now_ms()
	_waits_for_mechanism = true
	_rearm_at_ms = -1.0


## Its mechanism is ready again (or its own time is up): it snaps upright.
func rearm(_payload: Variant = null) -> void:
	if _state == State.ARMED or _state == State.REARM:
		return
	_state = State.REARM
	_since_ms = Services.now_ms()
	_rearm_at_ms = -1.0
	_rock_from_ms = -1.0
	# the rope snaps taut: a small whip runs along it
	_whip_from_ms = _since_ms
	_whip_strength = REARM_WHIP
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_REARM)
	rearmed.emit({"targetId": target_id})


## Something that cannot knock it touched it: the wooden knock, and the line once per visit.
func tap() -> void:
	var now := Services.now_ms()
	if now < _next_tap_ms:
		return
	_next_tap_ms = now + DungeonState.number("knockTarget.tapEveryMs", 700.0)
	_rock_from_ms = now
	var feel := Services.feel()
	if feel == null:
		return
	feel.audio_cue(CUE_TAP)
	if not _said and not refusal_text.is_empty():
		_said = true
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), refusal_text, &"white", false,
			DungeonState.number("knockTarget.lineMs", 2600.0))


func _physics_process(_delta: float) -> void:
	var now := Services.now_ms()
	match _state:
		State.SPIN:
			if now - _since_ms >= DungeonState.number("knockTarget.spinMs", 400.0):
				_state = State.SLACK
				_since_ms = now
		State.SLACK:
			if _rearm_at_ms >= 0.0 and now >= _rearm_at_ms:
				rearm()
		State.REARM:
			if now - _since_ms >= DungeonState.number("knockTarget.rearmSnapMs", 180.0):
				_state = State.ARMED
				_since_ms = now
	# The slime's body on its post: the wooden knock.
	if body != null and PushProbe.push_direction(PushProbe.shapes_box(body), DungeonState.number("knockTarget.reachPx", 8.0)) != Vector2.ZERO:
		tap()
	# The line is said again once the slime has been away.
	if _said and _state == State.ARMED:
		var world := Services.world()
		if world != null and world.player_body != null and is_instance_valid(world.player_body) \
				and world.player_body.global_position.distance_to(global_position) > DungeonState.number("knockTarget.lineResetPx", 480.0):
			_said = false


# --- the looks ------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_show()


## The disc's tilt, spin and the rope for the state and the time in it.
func _show() -> void:
	if disc == null or spinner == null:
		return
	var editor := Engine.is_editor_hint()
	var now := 0.0 if editor else Services.now_ms()
	var age := now - _since_ms
	var slack_tilt := deg_to_rad(_number("slackTiltDeg", 34.0))
	var tilt := 0.0
	var turn := 0.0
	var slack := 0.0
	match _state:
		State.ARMED:
			# a slow sway on its pivot
			var period := maxf(1.0, _number("swayPeriodMs", 2600.0))
			tilt = deg_to_rad(_number("swayDeg", 3.5)) * sin(TAU * (now + _sway_offset) / period)
		State.SPIN:
			var t := clampf(age / maxf(1.0, _number("spinMs", 400.0)), 0.0, 1.0)
			var eased := 1.0 - (1.0 - t) * (1.0 - t)
			turn = TAU * _number("spinTurns", 2.5) * eased
			# it rocks hard at first and comes to rest tilted
			tilt = slack_tilt * eased + deg_to_rad(_number("rockDeg", 16.0)) * sin(t * TAU * 2.0) * (1.0 - t)
			slack = eased
		State.SLACK:
			slack = 1.0
			# it settles with a small swing that dies away
			tilt = slack_tilt + deg_to_rad(5.0) * sin(age / 170.0) * exp(-age / 420.0)
		State.REARM:
			var t := clampf(age / maxf(1.0, _number("rearmSnapMs", 180.0)), 0.0, 1.0)
			# back past upright and home (a snap)
			var back_ease := 1.0 + 2.70158 * pow(t - 1.0, 3.0) + 1.70158 * pow(t - 1.0, 2.0)
			tilt = slack_tilt * (1.0 - back_ease)
			slack = 1.0 - t
	# a hit that does not knock it rocks it
	if _rock_from_ms >= 0.0 and not editor:
		var rock_age := now - _rock_from_ms
		var rock_ms := maxf(1.0, _number("rockMs", 420.0))
		if rock_age < rock_ms:
			tilt += _rock_sign * deg_to_rad(_number("rockDeg", 16.0)) * 0.6 * sin(rock_age / rock_ms * TAU * 1.5) * (1.0 - rock_age / rock_ms)
		else:
			_rock_from_ms = -1.0
	disc.position = PIVOT + Vector2(0.0, SLACK_DROP * slack)
	disc.rotation = tilt
	var facing := cos(turn)
	spinner.scale.x = facing if absf(facing) > 0.06 else 0.06 * (1.0 if facing >= 0.0 else -1.0)
	if front != null:
		front.visible = facing >= 0.0
	if not is_equal_approx(slack, _slack) or _state != State.ARMED or _rock_from_ms >= 0.0 or editor:
		_slack = slack
		_redraw_rope()
	elif _state == State.ARMED:
		# the sway moves the hook a little
		_redraw_rope()


func _number(key: String, fallback: float) -> float:
	return DungeonState.number("knockTarget." + key, fallback)


func _make_rope() -> void:
	if _rope_floor != null:
		return
	_rope_floor = Node2D.new()
	_rope_floor.name = "RopeFloor"
	_rope_floor.z_index = -1
	add_child(_rope_floor, false, Node.INTERNAL_MODE_BACK)
	_rope_floor.draw.connect(_draw_rope_floor)
	_rope_top = Node2D.new()
	_rope_top.name = "RopeTop"
	add_child(_rope_top, false, Node.INTERNAL_MODE_BACK)
	_rope_top.draw.connect(_draw_rope_top)


func _redraw_rope() -> void:
	if _rope_floor != null:
		_rope_floor.queue_redraw()
	if _rope_top != null:
		_place_rope_top()
		_rope_top.queue_redraw()


## Where the rope ends on the floor, from this node; INF when it has no end.
func _rope_end() -> Vector2:
	if not is_inside_tree():
		return Vector2.INF
	var node := get_node_or_null(rope_to) as Node2D if not rope_to.is_empty() else null
	if node != null:
		return to_local(node.global_position)
	for path: NodePath in targets:
		var target := get_node_or_null(path)
		if target != null and target.has_method(&"rope_anchor"):
			var point: Variant = target.call(&"rope_anchor")
			if point is Vector2:
				return to_local(point as Vector2)
	return Vector2.INF


## The point the rope reaches the floor at: beside the post and just behind it, on the side of its
## first floor point (right when that lies straight up or down the screen).
func _rope_foot() -> Vector2:
	var toward := rope_points[0] if rope_points.size() > 0 else _rope_end()
	var side := -1.0 if toward.is_finite() and toward.x < -ROPE_FOOT.x else 1.0
	return Vector2(ROPE_FOOT.x * side, ROPE_FOOT.y)


## The hanging run is drawn behind the disc and the post (it comes down their back).
func _place_rope_top() -> void:
	if _rope_top != null:
		_rope_top.z_index = -1


## The hook on the disc's top, from this node (it moves with the tilt and the spin).
func _hook_point() -> Vector2:
	if disc == null:
		return PIVOT + Vector2(0.0, -DISC_RISE) + HOOK
	return disc.position + (Vector2(0.0, -DISC_RISE) + HOOK).rotated(disc.rotation)


## The rope's pins on the floor, from this node: where it reaches the floor beside the post, the
## iron eyelets, its end. `rope_points` are its corners, each an eyelet; with fewer than two, eyelets
## are added along its longest straight runs (two or three in all, the foot's ring counted).
func _floor_pins() -> PackedVector2Array:
	var end := _rope_end()
	var foot := _rope_foot()
	var pins := PackedVector2Array([foot])
	if not end.is_finite():
		return pins
	if rope_points.size() >= 2:
		pins.append_array(rope_points)
	elif rope_points.size() == 1:
		var corner := rope_points[0]
		if foot.distance_to(corner) >= corner.distance_to(end):
			pins.append(foot.lerp(corner, 0.5))
			pins.append(corner)
		else:
			pins.append(corner)
			pins.append(corner.lerp(end, 0.5))
	elif foot.distance_to(end) > 220.0:
		pins.append(foot.lerp(end, 1.0 / 3.0))
		pins.append(foot.lerp(end, 2.0 / 3.0))
	else:
		pins.append(foot.lerp(end, 0.5))
	pins.append(end)
	return pins


## The whip's sideways push at `walked` units along the rope from the hook (0 when none runs),
## for a rope `total` long whose pins lie at `pins_at` (units from the hook).
func _whip_at(walked: float, total: float, pins_at: PackedFloat32Array) -> float:
	if _whip_from_ms < 0.0 or Engine.is_editor_hint():
		return 0.0
	var age := Services.now_ms() - _whip_from_ms
	if age >= WHIP_MS or age < 0.0:
		return 0.0
	var head := age / WHIP_RUN_MS * total
	var from_head := (walked - head) / WHIP_WAVE
	var held := 1.0
	for pin: float in pins_at:
		held = minf(held, clampf(absf(walked - pin) / WHIP_HELD, 0.0, 1.0))
	return WHIP_PX * _whip_strength * (1.0 - age / WHIP_MS) * exp(-from_head * from_head) * sin(from_head * TAU * 0.5) * held


## The hanging run's length (the hook to the floor), for the whip's timing.
func _top_length() -> float:
	return _hook_point().distance_to(_rope_foot())


## The floor run's length along its pins.
func _floor_length(pins: PackedVector2Array) -> float:
	var total := 0.0
	for i in pins.size() - 1:
		total += pins[i].distance_to(pins[i + 1])
	return total


func _draw_rope_top() -> void:
	var from := _hook_point()
	var to := _rope_foot()
	var pins := _floor_pins()
	var top := from.distance_to(to)
	var total := top + _floor_length(pins)
	var pins_at := PackedFloat32Array([top])
	var span := to - from
	var across := Vector2(-span.y, span.x).normalized() if span.length() > 0.0 else Vector2.RIGHT
	var points := PackedVector2Array()
	var steps := 12
	# taut: a straight line; slack: it bellies out and down
	var belly := Vector2(signf(to.x) * SAG_DROP * 0.7, SAG_DROP) * _slack
	for i in steps + 1:
		var t := float(i) / float(steps)
		points.append(from.lerp(to, t) + belly * 4.0 * t * (1.0 - t) + across * _whip_at(top * t, total, pins_at) * sin(PI * t))
	_stroke(_rope_top, points, false)


func _draw_rope_floor() -> void:
	var pins := _floor_pins()
	if pins.size() < 2:
		return
	var top := _top_length()
	var floor_length := _floor_length(pins)
	if floor_length <= 0.0:
		return
	var total := top + floor_length
	var pins_at := PackedFloat32Array([top])
	var walked := top
	for i in pins.size() - 1:
		walked += pins[i].distance_to(pins[i + 1])
		pins_at.append(walked)
	# the hanging run's shadow, from the post's foot to where the rope meets the floor
	var foot := pins[0]
	_rope_floor.draw_line(Vector2(signf(foot.x) * 5.0, 2.0) + ROPE_SHADOW_AT, foot + ROPE_SHADOW_AT,
		Color(ROPE_SHADOW, ROPE_SHADOW.a * 0.6), ROPE_SHADOW_WIDTH * 0.8, true)
	var points := PackedVector2Array()
	walked = top
	for i in pins.size() - 1:
		var a := pins[i]
		var b := pins[i + 1]
		var length := a.distance_to(b)
		if length <= 0.0:
			continue
		var across := Vector2(-(b - a).y, (b - a).x) / length
		# slack, each run between two pins lies in a loose curve, the next one the other way
		var sag := minf(SAG_MAX, length * SAG_SHARE) * _slack * (1.0 if i % 2 == 0 else -1.0)
		var count := maxi(2, ceili(length / ROPE_STEP))
		for step in count + (1 if i == pins.size() - 2 else 0):
			var t := float(step) / float(count)
			var lie := sag * (sin(PI * t) + 0.22 * sin(3.0 * PI * t))
			points.append(a.lerp(b, t) + across * (lie + _whip_at(walked + length * t, total, pins_at)))
		walked += length
	# under the rope: the eyelets' plates and the far half of each ring; over it: the near half
	var eyelets := pins.slice(0, pins.size() - 1)
	for at: Vector2 in eyelets:
		_draw_eyelet_under(at)
	_stroke(_rope_floor, points, true)
	for at: Vector2 in eyelets:
		_draw_eyelet_over(at)


## The eyelet's iron plate (two rivets) and shadow, and the far half of its ring.
func _draw_eyelet_under(at: Vector2) -> void:
	var half := EYELET_PLATE * 0.5
	_rope_floor.draw_rect(Rect2(at - half + Vector2(1.5, 2.0), EYELET_PLATE), Color(ROPE_SHADOW, 0.35))
	_rope_floor.draw_rect(Rect2(at - half, EYELET_PLATE), IRON_DARK)
	_rope_floor.draw_rect(Rect2(at - half + Vector2(0.8, 0.8), EYELET_PLATE - Vector2(1.6, 1.6)), IRON)
	for side: float in [-1.0, 1.0]:
		_rope_floor.draw_circle(at + Vector2(side * (half.x - 1.8), 0.0), 1.0, IRON_SHINE)
	_draw_ring(at, PI, TAU)


## The near half of the eyelet's ring, over the rope that runs through it.
func _draw_eyelet_over(at: Vector2) -> void:
	_draw_ring(at, 0.0, PI)
	_rope_floor.draw_arc(at + Vector2(0.0, -0.6), EYELET_RADIUS, PI * 0.15, PI * 0.45, 5, IRON_SHINE, 1.0, true)


## An arc of an eyelet's ring (an upright loop seen from above and in front: a flattened circle).
func _draw_ring(at: Vector2, from: float, to: float) -> void:
	_rope_floor.draw_set_transform(at, 0.0, Vector2(1.0, 0.72))
	_rope_floor.draw_arc(Vector2(0.0, -2.0), EYELET_RADIUS, from, to, 10, IRON_DARK, EYELET_RING + 1.4, true)
	_rope_floor.draw_arc(Vector2(0.0, -2.0), EYELET_RADIUS, from, to, 10, IRON, EYELET_RING, true)
	_rope_floor.draw_set_transform(Vector2.ZERO)


## A run of rope: its shadow on the floor (`shadow`), the dark outline, the light strand, the darker
## strand's twist marks across it and a shine along its upper edge.
func _stroke(canvas: Node2D, points: PackedVector2Array, shadow: bool) -> void:
	if points.size() < 2:
		return
	if shadow:
		var shade := PackedVector2Array()
		for point: Vector2 in points:
			shade.append(point + ROPE_SHADOW_AT)
		canvas.draw_polyline(shade, ROPE_SHADOW, ROPE_SHADOW_WIDTH, true)
	canvas.draw_polyline(points, ROPE_DARK, ROPE_WIDTH, true)
	canvas.draw_polyline(points, ROPE_LIGHT, ROPE_CORE, true)
	# the twist: a slanted mark of the darker strand every TWIST_EVERY units
	var shine := PackedVector2Array()
	var next := TWIST_EVERY * 0.5
	var walked := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length <= 0.0:
			continue
		var along := (b - a) / length
		var normal := Vector2(-along.y, along.x)
		if normal.y > 0.0 or (is_zero_approx(normal.y) and normal.x > 0.0):
			normal = -normal
		shine.append(a + normal * 0.8)
		while next <= walked + length:
			var at := a + along * (next - walked)
			var half := ROPE_CORE * 0.5
			canvas.draw_line(at - normal * half - along * TWIST_SLANT * 0.5, at + normal * half + along * TWIST_SLANT * 0.5,
				ROPE_STRAND, 1.3, true)
			next += TWIST_EVERY
		walked += length
	shine.append(points[points.size() - 1])
	canvas.draw_polyline(shine, ROPE_SHINE, 0.8, true)
