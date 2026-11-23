extends "res://game/enemy/patterned_enemy.gd"
class_name CocoonMimicScript
## Scene script `game.cocoon-mimic` (the bestiary's row 21, a mimic; docs/godot/BESTIARY.md "Cocoon
## Mimic"): a monster that looks just like a silk-wrapped prize (a cocoon with a gold coin showing
## through the silk), but it breathes. Real cocoons never breathe (the clarity rule).
##
## - **Disguised:** it sits still, but swells and sinks slowly (`breathMs`, `breathSwell`): the tell.
## - **Burst** (`burstMs`): the slime's centre within `wakeRangePx` (or a hit) wakes it: it splits
##   into a toothy mouth, silk tatters flying.
## - **Lunge** (`lungeMs`): it springs `lungePx` at where the slime stood; reaching its feet
##   (`grabRangePx`, and the slime not rolling) it grabs.
## - **Hold:** it clamps shut over the slime: the slime is rooted (the `sticky` status, refreshed
##   while held) and hidden in it, and loses `drainPerSecond` energy (once it is empty, `chewDamage`
##   every `chewMs`). Pressing the move keys shakes it (each new press, or a turn to another key,
##   counts): `shakeOffPresses` shakes throw it off, **dazed** (`dazedMs`, open: every old-style hit
##   `dazedDamageTaken` times; rework hits: the profile's `states.dazed`). After `holdMaxMs` it spits
##   the slime out (`spitDamage`, `spitKnockback`). Hits clink while it holds.
## - **Open** (`openMs`): awake, it creeps at the slime (`creepSpeed`) and lunges again within
##   `lungeRangePx` (`lungeCooldownMs` apart); then, or once the slime leaves its arena, it walks home
##   (`homeSpeed`) and wraps itself up again (`wrapMs`).
## - **Right tool:** a Goo Bomb's blast (tag `blast`) next to it bursts it at once, disguised or not.
## - **A swallowed drop** (the Weaver Hollow's B3 Mimic swallowed small key 2; set on a placed enemy's
##   `overrides`, game/enemy/placed_enemy.gd): beaten, it spits out what it swallowed, once. With
##   `swallowed_flag` set and `swallowed_scene_id` (a scene id: the dungeon kit's key pickup, a
##   collectible...), that scene hops out of it onto the ground (`swallowed_settings` set on it
##   first: {"property": value} on its root, {"<child path>": {"property": value}} on a child; a
##   CollectibleScript in it gets the world's map id and the flag as its record unless the settings
##   say otherwise, so it is taken once). The flag is set and the spot is kept (the map's object
##   state "swallowed:<flag>"): a world built again (the room entered again, a load) puts the drop
##   back there while the flag is set, and a pickup that is already taken frees itself by its own
##   record. Or `swallowed_item_id` (`swallowed_count` of an items.json item) falls as loot
##   (EnemyLoot.drop_loot: a pile kept by the map until it is picked up). A Mimic built again with
##   the flag set has swallowed nothing more.
##
## Owner: enemy builder.

const PHASE_DISGUISED := "disguised"
const PHASE_BURST := "burst"
const PHASE_LUNGE := "lunge"
const PHASE_HOLD := "hold"
const PHASE_DAZED := "dazed"
const PHASE_OPEN := "open"
const PHASE_WRAP := "wrap"
const FRAME_DISGUISED := 0
const FRAME_BURST := 1
const FRAME_HOLD := 2
const FRAME_DAZED := 3
const BLAST_TAG := "blast"
const STICKY := &"sticky"
const CUE_BURST := &"BreakSoft"
const CUE_GRAB := &"MimicGrab"
const CUE_SHAKE := &"WebStruggle"
const CUE_FREE := &"WebTear"
const CUE_SPIT := &"MimicSpit"
const CUE_WRAP := &"MimicWrap"
const TATTERS := &"dodge-dust"
const HINT := "Shake it off! (move keys)"
## Presentation: the burst's pop, the hold's squirm and a shake's jolt, the dazed sway, the walk's
## waddle, the slime's look inside it, the hint's rise.
const BURST_POP := Vector2(1.14, 0.9)
## A breath swells it upward more than sideways.
const BREATH_WIDTH_SHARE := 0.6
const SQUIRM := 0.04
const SQUIRM_MS := 90.0
const SHAKE_JOLT := Vector2(1.16, 0.86)
const SHAKE_JOLT_MS := 140.0
const DAZED_SWAY_RAD := 0.06
const DAZED_SWAY_MS := 210.0
const WADDLE_RAD := 0.06
const WADDLE_MS := 120.0
const HIDDEN_ALPHA := 0.0
const HINT_RISE_PX := 70.0
## The mimic sits this far in front of the held slime (y-sorted over it).
const HOLD_IN_FRONT_PX := 2.0
## The swallowed drop: it lands this far below the Mimic's feet (a wall there: on the feet), hopping
## out of its middle over DROP_FLIGHT_S with an arc of DROP_ARC_PX (presentation); its record key.
const DROP_OFFSET := Vector2(0.0, 40.0)
const DROP_FLIGHT_S := 0.34
const DROP_ARC_PX := 34.0
const DROP_STATE_PREFIX := "swallowed:"
const DROP_GROUP := &"swallowed_drops"
const DROP_META := &"swallowed_flag"
const PICKUP_AREA := ^"PickupArea"
const CollectibleScriptType := preload("res://game/scripts/collectible.gd")
const EnemyLootType := preload("res://game/world_objects/enemy_loot.gd")
const MAIN_GROUP := &"world_main"

@export_group("Swallowed drop")
## The story flag set when it spits its drop out (empty: it swallowed nothing).
@export var swallowed_flag: String = ""
## The scene it spits out (a scene id in scene_index.json).
@export var swallowed_scene_id: String = ""
## Set on that scene before it enters the tree (see the class notes).
@export var swallowed_settings: Dictionary = {}
## Or an items.json item, dropped as loot.
@export var swallowed_item_id: String = ""
@export var swallowed_count: int = 1
@export_group("")

var _ready_at: float = 0.0
var _lunge_from: Vector2 = Vector2.ZERO
var _lunge_to: Vector2 = Vector2.ZERO
var _held: Node = null
var _held_body: PhysicsBody2D = null
var _shakes: int = 0
var _last_intent: Vector2 = Vector2.ZERO
var _jolt_at: float = -INF
var _chew_at: float = 0.0
var _hinted: bool = false
var _push_dir: Vector2 = Vector2.DOWN


func _ready() -> void:
	super()
	_disguise(Services.now_ms())
	_restore_swallowed.call_deferred()


func _exit_tree() -> void:
	_let_go()
	super()


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	var slime_feet := _slime_feet(target)
	match _phase:
		PHASE_DISGUISED:
			body.velocity = Vector2.ZERO
			_breathe(now)
			if engaged and now >= _ready_at and centre.distance_to(slime) <= pattern("wakeRangePx", 60.0):
				_burst(now)
		PHASE_BURST:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("burstMs", 380.0)), 0.0, 1.0)
			set_look(0.0, Vector2.ONE.lerp(BURST_POP, sin(t * PI)))
			face_x(slime.x - centre.x)
			if t >= 1.0:
				_begin_lunge(now, slime_feet if engaged else Vector2.INF)
		PHASE_LUNGE:
			var lunge_ms := maxf(1.0, pattern("lungeMs", 220.0))
			var t := clampf(elapsed / lunge_ms, 0.0, 1.0)
			body.velocity = (_lunge_to - _lunge_from) / (lunge_ms / 1000.0)
			set_look(sin(t * PI) * pattern("lungeHopPx", 14.0), Vector2(0.92, 1.1))
			if engaged and _can_grab(target) and feet().distance_to(slime_feet) <= pattern("grabRangePx", 30.0):
				_grab(now, target)
			elif t >= 1.0:
				body.velocity = Vector2.ZERO
				_open(now)
				_ready_at = now + pattern("lungeCooldownMs", 1200.0)
		PHASE_HOLD:
			_step_hold(now, delta, target)
		PHASE_DAZED:
			var slide := clampf(1.0 - elapsed / maxf(1.0, pattern("shakeOffSlideMs", 200.0)), 0.0, 1.0)
			body.velocity = -_push_dir * pattern("shakeOffSlide", 160.0) * slide
			set_look(0.0, Vector2.ONE, sin(elapsed / DAZED_SWAY_MS) * DAZED_SWAY_RAD)
			if elapsed >= pattern("dazedMs", 2200.0):
				_open(now)
				_ready_at = now + pattern("lungeCooldownMs", 1200.0)
		PHASE_OPEN:
			var going_home := not engaged or elapsed >= pattern("openMs", 5000.0)
			if going_home:
				body.velocity = _velocity_home(pattern("homeSpeed", 50.0), delta)
				if body.velocity == Vector2.ZERO:
					_transition(PHASE_WRAP, now)
					set_frame(FRAME_HOLD)
					_cue(CUE_WRAP)
			else:
				body.velocity = _velocity_toward(slime, pattern("creepSpeed", 40.0), delta)
				if now >= _ready_at and centre.distance_to(slime) <= pattern("lungeRangePx", 90.0):
					body.velocity = Vector2.ZERO
					_burst(now)
			face_x(body.velocity.x if body.velocity.length() > WALK_SPEED_THRESHOLD else slime.x - centre.x)
			var walking := body.velocity.length() > WALK_SPEED_THRESHOLD
			if _phase == PHASE_OPEN and show_walk(delta, FRAME_BURST):
				set_look(0.0)
			else:
				set_look(0.0, Vector2.ONE, sin(now / WADDLE_MS) * WADDLE_RAD if walking else 0.0)
		PHASE_WRAP:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("wrapMs", 600.0)), 0.0, 1.0)
			set_look(0.0, Vector2(1.0 - 0.08 * sin(t * PI), 1.0 + 0.08 * sin(t * PI)))
			if t >= 1.0:
				_disguise(now)
				_ready_at = now + pattern("rewakeMs", 800.0)


# --- the hold --------------------------------------------------------------------------------------

func _can_grab(target: Dictionary) -> bool:
	var player: Node = target.get("player")
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")):
		return false
	return not bool(player.call(&"is_rolling"))


func _grab(now: float, target: Dictionary) -> void:
	_held = target.get("player")
	_held_body = target.get("body") as PhysicsBody2D
	_shakes = 0
	_last_intent = Vector2.ZERO
	_chew_at = now + pattern("chewMs", 1000.0)
	set_solid(false)
	if _held_body != null and body != null:
		body.add_collision_exception_with(_held_body)
	if _held != null and _held.has_method(&"set_effect_alpha"):
		_held.call(&"set_effect_alpha", HIDDEN_ALPHA)
	if pose != null:
		pose.z_index = 1
	_transition(PHASE_HOLD, now)
	set_frame(FRAME_HOLD)
	_cue(CUE_GRAB)
	_puff(TATTERS, feet())
	if not _hinted:
		_hinted = true
		var feel := Services.feel()
		if feel != null:
			feel.floating_text(get_centre() - Vector2(0.0, HINT_RISE_PX), HINT, &"yellow", false)


func _step_hold(now: float, delta: float, target: Dictionary) -> void:
	var player := _held
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")) \
			or target.get("player") != player:
		_let_go()
		_open(now)
		return
	# It sits over the slime, clamped shut.
	var over := (_held_body.global_position if _held_body != null else feet()) + Vector2(0.0, HOLD_IN_FRONT_PX)
	body.velocity = (over - feet()) / maxf(delta, 0.0001)
	player.call(&"apply_status", STICKY, pattern("holdTickMs", 200.0))
	# It drinks the slime's energy; empty, it chews.
	var energy := float(player.call(&"get_energy"))
	if energy > 0.0:
		player.call(&"spend_energy", minf(energy, pattern("drainPerSecond", 20.0) * delta))
	elif now >= _chew_at:
		_chew_at = now + pattern("chewMs", 1000.0)
		_route_immediate_attack(target, pattern("chewDamage", 6.0), 0.0)
	# The move keys shake it: each new press, or a turn to another key.
	var intent: Vector2 = player.call(&"get_move_intent")
	if intent != Vector2.ZERO and intent.normalized().distance_to(_last_intent.normalized()) > 0.5:
		_shakes += 1
		_jolt_at = now
		_push_dir = intent.normalized()
		_cue(CUE_SHAKE)
		_puff(TATTERS, feet() + _push_dir * 10.0)
	_last_intent = intent
	var jolt := clampf(1.0 - (now - _jolt_at) / SHAKE_JOLT_MS, 0.0, 1.0)
	var squirm := sin(now / SQUIRM_MS) * SQUIRM
	set_look(0.0, Vector2(1.0 + squirm, 1.0 - squirm).lerp(SHAKE_JOLT, jolt), sin(now / SQUIRM_MS * 0.7) * SQUIRM * jolt * 4.0)
	if _shakes >= int(pattern("shakeOffPresses", 6.0)):
		_shaken_off(now)
	elif _elapsed(now) >= pattern("holdMaxMs", 5000.0):
		_spit_out(now, target)


## Shaken off: the slime breaks out the way it pushed; the mimic slides back, dazed.
func _shaken_off(now: float) -> void:
	var player := _held
	_let_go()
	if player != null and is_instance_valid(player) and player.has_method(&"recoil"):
		player.call(&"recoil", _push_dir, pattern("shakeOffPush", 220.0), pattern("shakeOffPushMs", 220.0))
	_transition(PHASE_DAZED, now)
	set_frame(FRAME_DAZED)
	_cue(CUE_FREE)
	_puff(TATTERS, feet())


## Held too long: it spits the slime out with a bite and stays awake.
func _spit_out(now: float, target: Dictionary) -> void:
	var player := _held
	_let_go()
	_cue(CUE_SPIT)
	if player != null and is_instance_valid(player):
		_route_immediate_attack(target, pattern("spitDamage", 10.0), pattern("spitKnockback", 260.0))
	_open(now)
	_ready_at = now + pattern("lungeCooldownMs", 1200.0)


## Lets go of the slime: its status, its look and the body's collision back.
func _let_go() -> void:
	if _held != null and is_instance_valid(_held):
		var status: Variant = _held.call(&"get_status") if _held.has_method(&"get_status") else null
		if status is Object and (status as Object).has_method(&"remove"):
			(status as Object).call(&"remove", STICKY)
		if _held.has_method(&"set_effect_alpha"):
			_held.call(&"set_effect_alpha", 1.0)
	if _held_body != null and is_instance_valid(_held_body) and body != null and is_instance_valid(body):
		body.remove_collision_exception_with(_held_body)
	_held = null
	_held_body = null
	if pose != null:
		pose.z_index = 0
	if not is_defeated():
		set_solid(true)


func is_holding() -> bool:
	return _phase == PHASE_HOLD and _held != null


func shake_count() -> int:
	return _shakes


# --- phases ----------------------------------------------------------------------------------------

func _disguise(now: float) -> void:
	_transition(PHASE_DISGUISED, now)
	set_frame(FRAME_DISGUISED)
	set_look(0.0)


## The tell: a slow, visible swell and sink (a real cocoon never moves).
func _breathe(now: float) -> void:
	var breath := (sin(now / maxf(1.0, pattern("breathMs", 2600.0)) * TAU) + 1.0) * 0.5
	var swell := pattern("breathSwell", 0.12) * breath
	set_look(0.0, Vector2(1.0 + swell * BREATH_WIDTH_SHARE, 1.0 + swell))


func _burst(now: float) -> void:
	_transition(PHASE_BURST, now)
	set_frame(FRAME_BURST)
	_cue(CUE_BURST)
	_puff(TATTERS, get_centre())


func _begin_lunge(now: float, at: Vector2) -> void:
	_lunge_from = feet()
	var offset := (at - _lunge_from) if at != Vector2.INF else Vector2.ZERO
	var reach := minf(offset.length(), pattern("lungePx", 90.0))
	_lunge_to = _lunge_from + (offset.normalized() * reach if offset.length() > 0.0 else Vector2.ZERO)
	face_x(offset.x)
	_transition(PHASE_LUNGE, now)
	set_frame(FRAME_BURST)


func _open(now: float) -> void:
	_transition(PHASE_OPEN, now)
	set_frame(FRAME_BURST)
	set_look(0.0)


func _slime_feet(target: Dictionary) -> Vector2:
	var slime_body := target.get("body") as Node2D
	return slime_body.global_position if slime_body != null else Vector2.INF


# --- hits ------------------------------------------------------------------------------------------

## It holds tight: hits clink while it holds, but a Goo Bomb's blast.
func _shields(request: Dictionary) -> bool:
	return _phase == PHASE_HOLD and not has_tag(request, BLAST_TAG)


## A Goo Bomb's blast bursts it at once.
func _kill_hit(request: Dictionary) -> bool:
	return has_tag(request, BLAST_TAG)


## A hit on the disguise wakes it.
func commit_damage(commit: Dictionary) -> void:
	super(commit)
	if not is_defeated() and _phase == PHASE_DISGUISED:
		_burst(Services.now_ms())


## Old-style hits while it is dazed: `dazedDamageTaken` times (rework hits: `states.dazed`).
func mitigate_damage(input: Dictionary) -> float:
	var damage := super(input)
	if _phase == PHASE_DAZED and not ReworkMode.is_rework_request(input.get("request", {})):
		damage *= pattern("dazedDamageTaken", 2.0)
	return damage


## A stun holds the hold where it is (the slime stays in); else it slides as usual.
func _slides_when_stunned() -> bool:
	return _phase != PHASE_HOLD and _phase != PHASE_DISGUISED


func _on_stunned(now: float, delta: float) -> void:
	if _phase == PHASE_HOLD:
		_step_hold(now, delta, _primary_target())
	elif _phase == PHASE_BURST or _phase == PHASE_LUNGE:
		body.velocity = Vector2.ZERO


func _defeat() -> void:
	if is_defeated():
		return
	_let_go()
	super()
	_spit_swallowed()


# --- the swallowed drop ----------------------------------------------------------------------------

## True when it has a drop and has not spat it out yet.
func has_swallowed() -> bool:
	var run := Services.run()
	return not swallowed_flag.is_empty() and (not swallowed_scene_id.is_empty() or not swallowed_item_id.is_empty()) \
		and run != null and not run.has_flag(swallowed_flag)


## Beaten: the drop hops out of it (once: the flag).
func _spit_swallowed() -> void:
	var world := Services.world()
	if not has_swallowed() or world == null:
		return
	var run := Services.run()
	run.set_flag(swallowed_flag)
	var from := get_centre()
	var at := feet() + DROP_OFFSET
	var tile := float(world.dimensions().get("tile_size", 64))
	if world.is_solid_tile(floori(at.x / tile), floori(at.y / tile)):
		at = feet()
	_cue(CUE_SPIT)
	if not swallowed_scene_id.is_empty():
		run.set_object_state(world.map_id(), DROP_STATE_PREFIX + swallowed_flag, {"x": at.x, "y": at.y})
		var drop := _place_swallowed(at)
		if drop != null:
			_fly(drop, from, at)
		return
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	var loot: Variant = main.get(&"loot") if main != null else null
	var items := [{"item_id": swallowed_item_id, "count": maxi(1, swallowed_count)}]
	if loot is EnemyLootType:
		(loot as EnemyLootType).drop_loot(world.map_id(), from, items)
	else:
		run.add_item(swallowed_item_id, maxi(1, swallowed_count))


## A world built again after it spat its scene out: the drop lies where it landed (a taken pickup
## frees itself), unless it is still in the world.
func _restore_swallowed() -> void:
	var run := Services.run()
	var world := Services.world()
	if swallowed_flag.is_empty() or swallowed_scene_id.is_empty() or run == null or world == null \
			or not run.has_flag(swallowed_flag) or not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(DROP_GROUP):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and str(node.get_meta(DROP_META, "")) == swallowed_flag:
			return
	var spot: Variant = run.object_state(world.map_id(), DROP_STATE_PREFIX + swallowed_flag)
	if spot is Dictionary:
		_place_swallowed(Vector2(float((spot as Dictionary).get("x", 0.0)), float((spot as Dictionary).get("y", 0.0))))


## The drop scene at `at` in the world (null when it does not load).
func _place_swallowed(at: Vector2) -> Node2D:
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null:
		return null
	var root := world.instantiate_scene(swallowed_scene_id) as Node2D
	if root == null:
		return null
	for child: Node in root.get_children():
		if child.get_script() == CollectibleScriptType:
			child.set(&"map_id", world.map_id())
			child.set(&"instance_id", swallowed_flag)
	for key: Variant in swallowed_settings:
		var value: Variant = swallowed_settings[key]
		var node := root.get_node_or_null(NodePath(str(key))) if value is Dictionary else null
		if node != null:
			for property: Variant in value:
				node.set(StringName(str(property)), (value as Dictionary)[property])
		else:
			root.set(StringName(str(key)), value)
	root.set_meta(DROP_META, swallowed_flag)
	root.add_to_group(DROP_GROUP)
	root.position = parent.to_local(at)
	parent.add_child(root)
	root.reset_physics_interpolation()
	return root


## The drop hops out of the Mimic's middle `from` to `at` (no pickup until it lands).
func _fly(drop: Node2D, from: Vector2, at: Vector2) -> void:
	var area := drop.get_node_or_null(PICKUP_AREA) as Area2D
	if area != null:
		area.set_deferred(&"monitorable", false)
	var tween := drop.create_tween()
	tween.tween_method(_drop_step.bind(drop, from, at), 0.0, 1.0, DROP_FLIGHT_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_drop_landed.bind(drop, at, area))


static func _drop_step(t: float, drop: Node2D, from: Vector2, at: Vector2) -> void:
	if is_instance_valid(drop):
		drop.global_position = from.lerp(at, t) + Vector2(0.0, -DROP_ARC_PX * 4.0 * t * (1.0 - t))


static func _drop_landed(drop: Node2D, at: Vector2, area: Area2D) -> void:
	if is_instance_valid(drop):
		drop.global_position = at
		drop.reset_physics_interpolation()
	if area != null and is_instance_valid(area):
		area.monitorable = true
