extends RefCounted
## The slime's mouth (owner, 2026-10-08; GAME_GUIDELINES "Signature Mechanic: Gulp"). Owned by
## player.gd.
##
## - **Suck** (hold Q): the nearest takeable suckable (game/scripts/essence.gd, liftable.gd) within
##   `gulp.suckNearPx` of the slime's centre, or within `gulp.suckRangePx` and a cone of
##   `gulp.suckConeDeg` around the aim, leaves the world and flies into the mouth over
##   `gulp.suckPullMs` of simulation time. Letting go of Q before anything comes stops the suck.
##   Never a live enemy: only essences and liftables (pots, rocks, pumpkins, ...:
##   game/scripts/liftable.gd) are suckable. The suck plays `GulpSuck`, the catch `GulpCatch`.
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
## Owner: abilities (the burst: mouth).

const Services := preload("res://game/shared/services.gd")
const HeldLook := preload("res://game/player/gulp/held_look.gd")
const ThrownObject := preload("res://game/player/gulp/thrown_object.gd")
const SuctionFx := preload("res://game/player/gulp/suction_fx.gd")
const EssenceScript := preload("res://game/scripts/essence.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")

const SUCKABLE_GROUP := &"suckable"
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
	_show_fx(true)
	_audio(CUE_SUCK)


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


## Every physics step: `q_held` is whether Q is still down, `aim` where the slime sucks from. A
## timed burst ignores `q_held` and ends at its time.
func update(now_ms: float, q_held: bool, aim: Vector2) -> void:
	if not _sucking:
		return
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
	var centre: Vector2 = _player.call(&"get_centre")
	var near := _constant("gulp.suckNearPx")
	var reach := _constant("gulp.suckRangePx")
	var cone := deg_to_rad(_constant("gulp.suckConeDeg")) * 0.5
	var unit := aim.normalized() if aim != Vector2.ZERO else Vector2.DOWN
	var best: Node = null
	var best_distance := INF
	for node: Node in tree.get_nodes_in_group(SUCKABLE_GROUP):
		if not bool(node.call(&"can_take")):
			continue
		var offset: Vector2 = (node.call(&"origin") as Vector2) - centre
		var distance := offset.length()
		var in_cone := distance <= reach and (distance == 0.0 or absf(unit.angle_to(offset)) <= cone)
		if (distance <= near or in_cone) and distance < best_distance:
			best = node
			best_distance = distance
	return best


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
		var material := LiftableScript.material_of(str(held.get("kind", "")))
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
	_pull = {"info": info, "look": look, "from": from - Vector2(0.0, 14.0), "started": now_ms}


func _move_pull_look(progress: float) -> void:
	var look := _pull.get("look") as Node2D
	if look == null or not is_instance_valid(look) or _player == null:
		return
	var body := _player.get(&"body") as Node2D
	var mouth := body.global_position - Vector2(0.0, MOUTH_RISE) if body != null else look.global_position
	var eased := progress * progress
	look.global_position = (_pull["from"] as Vector2).lerp(mouth, eased)
	look.scale = Vector2.ONE * lerpf(1.0, 0.45, eased)


func _finish_pull() -> void:
	var info: Dictionary = _pull["info"]
	_cancel_pull()
	_stop_suck()
	_set_held(info)
	_audio(CUE_CATCH)


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
