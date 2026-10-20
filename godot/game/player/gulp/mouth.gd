extends RefCounted
## The slime's mouth (owner, 2026-10-08; GAME_GUIDELINES "Signature Mechanic: Gulp"). Owned by
## player.gd.
##
## - **Suck** (hold Q): the nearest takeable suckable (game/scripts/essence.gd, liftable.gd) within
##   `gulp.suckNearPx` of the slime's feet (its origin to theirs), or within `gulp.suckRangePx` and a cone of
##   `gulp.suckConeDeg` around the aim, leaves the world and flies into the mouth over
##   `gulp.suckPullMs` of simulation time. Letting go of Q before anything comes stops the suck.
##   Never a live enemy: only essences and liftables (pots, rocks, pumpkins, ...:
##   game/scripts/liftable.gd) are suckable. The suck plays `GulpSuck`, the catch `GulpCatch`.
## - **Vacuum** (`_sweep`, owner 2026-10-19): while it sucks, every walk-over pickup in the same reach
##   (coins, loot piles, goo hearts, energy shards: the `collectible` group) flies in and is picked
##   up as if walked over, never held; one that refuses (a full bag, full health) flies back.
## - **Holding** (`held`: {"kind": "essence", "essence": "stone"|"silk"|"swim"}, or {"kind":
##   <liftable kind>, "essence": "", "variant": 0|1}):
##   the slime cannot attack or use abilities (player.gd drops those presses), only throw (Q) or
##   swallow (the Swallow ability). What it holds shows inside it.
## - **Throw** (Q again): a liftable flies along the aim and breaks (game/player/gulp/thrown_object.gd).
##   An essence is never thrown (owner, 2026-10-09): Q spits it out whole, GulpController.SPIT_PX in
##   front along the aim, where it stays as a released form does, to be sucked back or picked up.
## A hit makes the slime drop what it holds (`drop`): a thing bursts at its feet, an essence
## falls whole and fades after `gulp.dropFadeMs`, a Goo Bomb (game/scripts/goo_bomb.gd, held kind
## "goo-bomb", ticking all along) falls whole and ticks on; death discards a held bomb. Death loses it. A door or a save keeps it
## (player.gd `run_snapshot`, `restore_held`).
##
## Body-shapes rework (docs/godot/BODY_SHAPES.md "Mouth"; body-shapes plan section 5): the Q state
## machine (mouth_hold.gd) starts a **timed burst** instead (`begin_burst`): the same suck, but it
## lasts `duration_ms` of simulation time whether Q is held or not, and ends early on a catch.
## `end_burst` ends it (a pull already in flight finishes). The held suck above is unchanged and is
## the only one the classic game uses. Neither ever pulls a live enemy.
##
## The feel (gulp_feel.gd, game-constants.json `gulp.feel`; 2026-10-16): the suck squashes the slime
## and draws motes into its mouth, the catch bulges it and settles what it holds with a bob, the
## throw stretches and leans it toward the throw. The pulled thing flies in at its PULL_LOOK_PX look,
## shrinking (it flew at its full art size before).
##
## Owner: abilities (the burst: mouth).

const Services := preload("res://game/shared/services.gd")
const HeldLook := preload("res://game/player/gulp/held_look.gd")
const ThrownObject := preload("res://game/player/gulp/thrown_object.gd")
const SuctionFx := preload("res://game/player/gulp/suction_fx.gd")
## The suck's squash and motes, the catch's bulge and settle, the throw's stretch (`gulp.feel`).
const GulpFeel := preload("res://game/player/gulp/gulp_feel.gd")
const EssenceScript := preload("res://game/scripts/essence.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")

const SUCKABLE_GROUP := &"suckable"
## Walk-over pickups (game/scripts/collectible.gd and its kin: coins, loot piles, the dungeon's goo
## hearts and coins, energy shards), swept in by any suck.
const COLLECTIBLE_GROUP := &"collectible"
## A swept pickup shrinks to this share of its size as it flies in.
const SWEEP_SHRINK := 0.45
const PULL_LOOK_PX := 30.0
## What the slime holds shows inside it: this size, this high over the feet (on the full slime's
## belly, where its art draws a lump), this see-through.
const INSIDE_LOOK_PX := 22.0
const INSIDE_RISE := 15.0
const INSIDE_ALPHA := 0.75
## Where a pulled thing ends up (the mouth, above the feet).
const MOUTH_RISE := 26.0
const LiftableScript := preload("res://game/scripts/liftable.gd")
const BreakBurst := preload("res://game/player/gulp/break_burst.gd")
const GulpController := preload("res://game/player/gulp/gulp_controller.gd")
## The Goo Bomb is a light liftable of its own (not in liftables.json): held whole, ticking.
const GooBomb := preload("res://game/scripts/goo_bomb.gd")
const CUE_SUCK := &"GulpSuck"
const CUE_CATCH := &"GulpCatch"
const CUE_THROW := &"GulpSpit"

## {} or {"kind", "essence"}.
var held: Dictionary = {}
## The slime (player.gd): body, get_centre, on_held_changed.
var _player: Node
var _sucking: bool = false
## A timed burst's end (simulation ms); < 0 for the held suck (or no suck).
var _burst_until_ms: float = -1.0
## The thing flying in: {"info", "look": Node2D, "from": Vector2, "started": float}; {} when none.
var _pull: Dictionary = {}
var _fx: Node2D
var _inside: Node2D
## Pickups flying in (their CollectibleScript's instance id -> true).
var _sweeping: Dictionary = {}
## Pickups that refused the slime during this suck (a full bag, full health): not pulled again
## until the next suck.
var _refused: Dictionary = {}
## Something was swept in during this suck (the burst then ends without the empty puff).
var _swept_any: bool = false
## The pickups lying there when this suck began: only they are swept in. One that appears during
## the suck (what a pot hid, revealed as the pot flies in) waits for the next suck (owner, 2026-10-19).
var _lying: Dictionary = {}


func _init(player: Node) -> void:
	_player = player


func is_holding() -> bool:
	return not held.is_empty()


## True while Q sucks (with or without something flying in).
func is_sucking() -> bool:
	return _sucking


## A Q press with nothing held: the suck starts and lasts while Q is held.
func begin_suck() -> void:
	if is_holding() or _sucking:
		return
	_sucking = true
	_refused.clear()
	_swept_any = false
	_lying.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for node: Node in tree.get_nodes_in_group(COLLECTIBLE_GROUP):
			_lying[node.get_instance_id()] = true
	_show_fx(true)
	_audio(CUE_SUCK)
	var aim := Vector2.DOWN
	if _player != null and _player.has_method(&"get_gulp_aim"):
		aim = _player.call(&"get_gulp_aim")
	GulpFeel.suck(_player, aim)


## Rework mode (mouth_hold.gd): a suck that lasts `duration_ms` from `now_ms`, Q held or not, and
## ends early on a catch. False when the mouth is full or already sucks.
func begin_burst(now_ms: float, duration_ms: float) -> bool:
	if is_holding() or _sucking:
		return false
	begin_suck()
	_burst_until_ms = now_ms + maxf(0.0, duration_ms)
	return true


## Ends a burst now; a pull already in flight finishes first (and then the suck ends).
func end_burst() -> void:
	if not _sucking:
		return
	if _pull.is_empty():
		_stop_suck()
	else:
		_burst_until_ms = 0.0


## True while a timed burst runs (with or without a pull in flight).
func is_burst() -> bool:
	return _sucking and _burst_until_ms >= 0.0


## True while something flies into the mouth.
func is_pulling() -> bool:
	return not _pull.is_empty()


## True when the last suck swept in a pickup.
func swept_loot() -> bool:
	return _swept_any


## Every physics step: `q_held` is whether Q is still down, `aim` where the slime sucks from. A
## timed burst ignores `q_held` and ends at its time.
func update(now_ms: float, q_held: bool, aim: Vector2) -> void:
	if not _sucking:
		return
	_sweep(aim)
	if not _pull.is_empty():
		var progress := (now_ms - float(_pull["started"])) / maxf(1.0, _constant("gulp.suckPullMs"))
		_move_pull_look(clampf(progress, 0.0, 1.0))
		if progress >= 1.0:
			_finish_pull()
		return
	if _burst_until_ms >= 0.0:
		if now_ms >= _burst_until_ms:
			_stop_suck()
			return
	elif not q_held:
		_stop_suck()
		return
	if _fx != null:
		_fx.set(&"direction", aim)
		_fx.set(&"reach", _constant("gulp.suckRangePx"))
		_fx.set(&"cone_deg", _constant("gulp.suckConeDeg"))
	var target := find_target(aim)
	if target != null:
		_start_pull(target, now_ms)


## The nearest suckable the slime can take now, aiming `aim`; null when none.
func find_target(aim: Vector2) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or _player == null:
		return null
	# Measured feet to feet: every suckable's origin is its feet, and from the slime's centre
	# (27 px higher) a thing touching its side came out beyond suckNearPx and below the cone.
	var body := _player.get(&"body") as Node2D
	var centre: Vector2 = body.global_position if body != null else _player.call(&"get_centre")
	var best: Node = null
	var best_distance := INF
	for node: Node in tree.get_nodes_in_group(SUCKABLE_GROUP):
		if not bool(node.call(&"can_take")):
			continue
		var offset: Vector2 = (node.call(&"origin") as Vector2) - centre
		var distance := offset.length()
		if _in_reach(offset, aim) and distance < best_distance:
			best = node
			best_distance = distance
	return best


## Throw combat (docs/godot/THROW_COMBAT.md): the nearest liftable in reach that the Gulp's level is
## too low for (`is_too_heavy`), so the mouth can say why nothing came; null when none.
func find_too_heavy(aim: Vector2) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var body := _player.get(&"body") as Node2D if _player != null else null
	if tree == null or body == null:
		return null
	var best: Node = null
	var best_distance := INF
	for node: Node in tree.get_nodes_in_group(SUCKABLE_GROUP):
		if not node.has_method(&"is_too_heavy") or not bool(node.call(&"is_too_heavy")):
			continue
		var offset: Vector2 = (node.call(&"origin") as Vector2) - body.global_position
		if _in_reach(offset, aim) and offset.length() < best_distance:
			best = node
			best_distance = offset.length()
	return best


## `offset` (from the slime's feet) is within `gulp.suckNearPx`, or within `gulp.suckRangePx` and
## the `gulp.suckConeDeg` cone around `aim`.
static func _in_reach(offset: Vector2, aim: Vector2) -> bool:
	var distance := offset.length()
	if distance <= _constant("gulp.suckNearPx"):
		return true
	var unit := aim.normalized() if aim != Vector2.ZERO else Vector2.DOWN
	var cone := deg_to_rad(_constant("gulp.suckConeDeg")) * 0.5
	return distance <= _constant("gulp.suckRangePx") and absf(unit.angle_to(offset)) <= cone


## The vacuum (owner, 2026-10-19): while the mouth sucks, every walk-over pickup in reach that can
## be taken (its pickup area on: not still flying from a drop) flies into the mouth over
## `gulp.suckPullMs` and is picked up there as if walked over: coins paid, the bag filled, health
## or energy restored. It is never held, so the suck goes on (and a pot can still be caught). One
## that refuses the slime (a full bag, full health) flies back to where it lay and is left alone
## until the next suck. Only what was lying there when the suck began (`_lying`): what appears
## during it (a heart under a pot just sucked up) is left for the next suck.
func _sweep(aim: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var body := _player.get(&"body") as Node2D if _player != null else null
	if tree == null or body == null:
		return
	for node: Node in tree.get_nodes_in_group(COLLECTIBLE_GROUP):
		var id := node.get_instance_id()
		if _sweeping.has(id) or _refused.has(id) or not _lying.has(id):
			continue
		var root := node.get_parent() as Node2D
		var area := node.get(&"pickup_area") as Area2D
		if root == null or area == null or not area.monitorable or root.is_queued_for_deletion():
			continue
		if _in_reach(root.global_position - body.global_position, aim):
			_sweep_in(node, root, body)


func _sweep_in(script: Node, root: Node2D, body: Node2D) -> void:
	var id := script.get_instance_id()
	_sweeping[id] = true
	_swept_any = true
	var from := root.global_position
	var size := root.scale
	var seconds := maxf(0.01, _constant("gulp.suckPullMs") / 1000.0)
	var mouth := body.global_position - Vector2(0.0, MOUTH_RISE)
	var tween := root.create_tween()
	tween.tween_property(root, ^"global_position", mouth, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(root, ^"scale", size * SWEEP_SHRINK, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _swept(id, script, root, from, size, seconds))


## A swept pickup reached the mouth: it is picked up; what is left of it (a full bag, full health)
## flies back to `from`.
func _swept(id: int, script: Node, root: Node2D, from: Vector2, size: Vector2, seconds: float) -> void:
	_sweeping.erase(id)
	if not is_instance_valid(script) or _player == null or not is_instance_valid(_player):
		return
	var result: Dictionary = script.call(&"request_pickup", _player.call(&"get_pickup_area"))
	if int(result.get("remaining", 0)) <= 0 or not is_instance_valid(root) or root.is_queued_for_deletion():
		return
	_refused[id] = true
	var back := root.create_tween()
	back.tween_property(root, ^"global_position", from, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	back.parallel().tween_property(root, ^"scale", size, seconds)


## Q with something held: throws a liftable from the slime's feet along `direction`, or spits an
## essence out whole in front. False when nothing held.
func throw(direction: Vector2) -> bool:
	if not is_holding() or _player == null:
		return false
	if str(held.get("kind", "")) == "essence":
		return _spit_essence(direction)
	var world := Services.world()
	var parent := world.entities_root() if world != null else null
	var body := _player.get(&"body") as Node2D
	if parent == null or body == null:
		return false
	var thrown := ThrownObject.new()
	thrown.name = "Thrown"
	parent.add_child(thrown)
	thrown.launch(_player, held, body.global_position, direction)
	_audio(CUE_THROW)
	GulpFeel.thrown(_player, direction)
	_set_held({})
	return true


## The essence held lands whole GulpController.SPIT_PX in front along `direction` and stays (no
## fade), as a form spat out with Swallow does.
func _spit_essence(direction: Vector2) -> bool:
	var body := _player.get(&"body") as Node2D
	if body == null:
		return false
	var unit := direction.normalized() if direction != Vector2.ZERO else Vector2.DOWN
	EssenceScript.spawn(str(held.get("essence", "")), body.global_position + unit * GulpController.SPIT_PX,
		_player.call(&"get_centre"), 0.0)
	_audio(CUE_THROW)
	GulpFeel.thrown(_player, unit)
	_set_held({})
	return true


## The bag's "Use" on an essence: it goes into the mouth. False when the mouth is busy or the item
## is no essence.
func take_item(item_id: String) -> bool:
	var form := GulpForms.for_item(item_id)
	if form.is_empty() or is_holding() or not _pull.is_empty():
		return false
	_set_held({"kind": "essence", "essence": str(form["essence"])})
	_audio(CUE_CATCH)
	GulpFeel.caught(_player, _inside, Vector2(0.0, -INSIDE_RISE))
	return true


## Swallowed (the Swallow ability): the mouth is empty again.
func clear_held() -> void:
	_set_held({})


## A hit: what the slime holds falls. A liftable bursts at its feet; an essence lands whole
## beside it and fades after `gulp.dropFadeMs`. A suck in progress stops.
func drop() -> void:
	_cancel_pull()
	_stop_suck()
	if not is_holding() or _player == null:
		return
	var body := _player.get(&"body") as Node2D
	var feet := body.global_position if body != null else Vector2.ZERO
	if str(held.get("kind", "")) == "essence":
		var facing: Vector2 = _player.call(&"get_facing")
		EssenceScript.spawn(str(held["essence"]), feet - facing * 28.0, _player.call(&"get_centre"), _constant("gulp.dropFadeMs"))
	elif GooBomb.from_held(held) != null:
		# A Goo Bomb falls out whole and keeps ticking (game/scripts/goo_bomb.gd).
		var facing: Vector2 = _player.call(&"get_facing")
		GooBomb.from_held(held).call(&"land", feet - facing * 28.0)
	else:
		# It breaks at the slime's feet as a thrown one breaks where it lands.
		var material := HeldLook.material_of(held)
		var world := Services.world()
		var look := HeldLook.make(held, ThrownObject.LOOK_SIZE_PX)
		if world != null and look is Sprite2D:
			BreakBurst.burst(world.entities_root(), feet - Vector2(0.0, MOUTH_RISE * 0.5), look as Sprite2D)
		look.free()
		var feel := Services.feel()
		if feel != null:
			for preset: StringName in ThrownObject.BREAK_PARTICLES.get(material, [&"dodge-dust"]):
				feel.particles(preset, feet)
			feel.audio_cue(ThrownObject.BREAK_CUES.get(material, ThrownObject.CUE_FALLBACK))
	_set_held({})


## Death: the held thing and any suck are gone without a trace.
func clear() -> void:
	# A Goo Bomb held or flying in is gone with it (no blast).
	for info: Variant in [held, _pull.get("info", {})]:
		var bomb := GooBomb.from_held(info as Dictionary) if info is Dictionary else null
		if bomb != null:
			bomb.call(&"discard")
	_cancel_pull()
	_stop_suck()
	_set_held({})


## A door or a load: the slime holds `state` again, quietly.
func restore(state: Dictionary) -> void:
	var kind := str(state.get("kind", ""))
	if kind == "essence":
		_set_held({"kind": kind, "essence": str(state.get("essence", ""))})
	elif not LiftableScript.entry(kind).is_empty():
		_set_held({"kind": kind, "essence": "", "variant": int(state.get("variant", 0))})


func _start_pull(target: Node, now_ms: float) -> void:
	var info: Dictionary = target.call(&"suck_info")
	var from: Vector2 = target.call(&"origin")
	target.call(&"take")
	var look := HeldLook.make(info, PULL_LOOK_PX)
	var world := Services.world()
	var parent := world.entities_root() if world != null else null
	if parent != null:
		look.z_index = 5
		parent.add_child(look)
		look.global_position = from - Vector2(0.0, 14.0)
	else:
		look.free()
		look = null
	_pull = {"info": info, "look": look, "from": from - Vector2(0.0, 14.0), "started": now_ms,
		"scale": look.scale if look != null else Vector2.ONE}


func _move_pull_look(progress: float) -> void:
	var look := _pull.get("look") as Node2D
	if look == null or not is_instance_valid(look) or _player == null:
		return
	var body := _player.get(&"body") as Node2D
	var mouth := body.global_position - Vector2(0.0, MOUTH_RISE) if body != null else look.global_position
	var eased := progress * progress
	look.global_position = (_pull["from"] as Vector2).lerp(mouth, eased)
	# It shrinks from its PULL_LOOK_PX look (HeldLook's scale) as it goes in.
	look.scale = (_pull.get("scale", Vector2.ONE) as Vector2) * lerpf(1.0, 0.45, eased)


func _finish_pull() -> void:
	var info: Dictionary = _pull["info"]
	_cancel_pull()
	_stop_suck()
	_set_held(info)
	_audio(CUE_CATCH)
	GulpFeel.caught(_player, _inside, Vector2(0.0, -INSIDE_RISE))


func _cancel_pull() -> void:
	var look := _pull.get("look") as Node2D
	if look != null and is_instance_valid(look):
		look.queue_free()
	_pull = {}


func _stop_suck() -> void:
	_sucking = false
	_burst_until_ms = -1.0
	_show_fx(false)


func _set_held(next: Dictionary) -> void:
	held = next
	_show_inside()
	if _player != null:
		_player.call(&"on_held_changed", held)


func _show_fx(on: bool) -> void:
	var body := _player.get(&"body") as Node2D if _player != null else null
	if on and body != null:
		if _fx == null or not is_instance_valid(_fx):
			_fx = SuctionFx.new()
			_fx.name = "SuctionFx"
			_fx.z_index = 2
			body.add_child(_fx)
		_fx.visible = true
	elif _fx != null and is_instance_valid(_fx):
		_fx.visible = false


## What the slime holds, inside it.
func _show_inside() -> void:
	if _inside != null and is_instance_valid(_inside):
		_inside.queue_free()
		_inside = null
	var body := _player.get(&"body") as Node2D if _player != null else null
	if held.is_empty() or body == null:
		return
	_inside = HeldLook.make(held, INSIDE_LOOK_PX)
	_inside.name = "HeldInside"
	_inside.position = Vector2(0.0, -INSIDE_RISE)
	_inside.modulate = Color(1.0, 1.0, 1.0, INSIDE_ALPHA)
	_inside.z_index = 1
	body.add_child(_inside)


func _audio(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


static func _constant(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0
