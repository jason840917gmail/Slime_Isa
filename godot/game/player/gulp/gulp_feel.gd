extends RefCounted
## The Gulp's feel (owner, 2026-10-16: "Remember Zelda: the mechanic of lifting and throwing feels
## natural and enjoyable mostly because of the sounds and the effect it produces"): quick touches on
## the suck, the catch, the throw and the landing. Presentation only; how the Gulp plays (ranges,
## timing, damage) is mouth.gd's and thrown_object.gd's. Every number is in game-constants.json
## `gulp.feel`:
## - **Suck** (`suck`, mouth.gd `begin_suck`): the slime squashes (`squashX` x `squashY`, back over
##   `squashMs`) and `motes` pale specks swirl into its mouth from up to `moteFromPx` ahead along the
##   aim, over `moteMs` each, started over `moteStaggerMs`, turning `swirlTurns` (gulp_motes.gd).
## - **Catch** (`catch`, mouth.gd `_finish_pull`, `take_item`): the slime bulges and bounces once
##   (`bulgeX` x `bulgeY` over `bulgeMs`), and what it now holds drops into place inside it from
##   `settleDropPx` higher and `settlePop` times bigger over `settleMs`, with one small bob.
## - **Throw** (`throw`, mouth.gd `throw`, `_spit_essence`): the slime stretches along the throw
##   (`stretch` more along its axis, 70 % of that less across, over `stretchMs`) and leans `leanPx`
##   into it, easing back over `leanMs`; the thing trails a whoosh streak for its first `streakMs`
##   (`streakLines` lines up to `streakPx` long, `streakWidthPx` wide; thrown_object.gd draws it).
## - **Landing** (`land`, thrown_object.gd `_break`): a puff of dust on the ground where it comes
##   down (`dodge-dust` at `dustScale`, unless its material's break already raises dust there), and
##   for a heavy material (`heavyMaterials`) a small camera nudge along the throw (`heavyKickPx`).
## Reduce motion keeps SquashStretch's share of the squashes, drops the lean, and GameFeel drops the
## nudge.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const GulpMotes := preload("res://game/player/gulp/gulp_motes.gd")

const ROOT := "gulp.feel"
## The motes end at the mouth: this high over the feet (as suction_fx.gd MOUTH_RISE).
const MOUTH_RISE := 22.0
## A stretch takes this share of `stretch` off across the throw.
const CROSS_SHARE := 0.7
const DUST_PRESET := &"dodge-dust"
## A break counts as on the ground when it is this close to the ground point under it.
const GROUND_EPSILON_PX := 4.0
const LEAN_META := &"gulp_lean_tween"


## Q starts a suck: the squash and the motes, from ahead along `aim`.
static func suck(player: Node, aim: Vector2) -> void:
	var numbers := _block("suck")
	if player == null or numbers.is_empty():
		return
	_squash(player, Vector2(_num(numbers, "squashX", 1.0), _num(numbers, "squashY", 1.0)), _num(numbers, "squashMs", 0.0))
	var body := player.get(&"body") as Node2D
	var constants := Services.constants()
	var cone := constants.number("gulp.suckConeDeg") if constants != null else 60.0
	GulpMotes.spawn(body, Vector2(0.0, -MOUTH_RISE), aim, cone, int(_num(numbers, "motes", 0.0)),
		_num(numbers, "moteMs", 0.0), _num(numbers, "moteStaggerMs", 0.0), _num(numbers, "moteFromPx", 0.0),
		_num(numbers, "moteSizePx", 2.0), _num(numbers, "swirlTurns", 0.0))


## Something reached the mouth: the bulge, and `inside` (what the slime now holds, drawn inside it,
## resting at `rest`) settles into place.
static func caught(player: Node, inside: Node2D, rest: Vector2) -> void:
	var numbers := _block("catch")
	if player == null or numbers.is_empty():
		return
	_squash(player, Vector2(_num(numbers, "bulgeX", 1.0), _num(numbers, "bulgeY", 1.0)), _num(numbers, "bulgeMs", 0.0))
	var settle_ms := _num(numbers, "settleMs", 0.0)
	if inside == null or not is_instance_valid(inside) or not inside.is_inside_tree() or settle_ms <= 0.0:
		return
	var base_scale := inside.scale
	inside.position = rest - Vector2(0.0, _num(numbers, "settleDropPx", 0.0))
	inside.scale = base_scale * _num(numbers, "settlePop", 1.0)
	var tween := inside.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(inside, "position", rest, settle_ms / 1000.0)
	tween.tween_property(inside, "scale", base_scale, settle_ms / 1000.0)


## A throw (or an essence spat out) along `direction`: the stretch and the lean.
static func thrown(player: Node, direction: Vector2) -> void:
	var numbers := _block("throw")
	if player == null or numbers.is_empty() or direction == Vector2.ZERO:
		return
	var unit := direction.normalized()
	var along_x := absf(unit.x) / maxf(0.001, absf(unit.x) + absf(unit.y))
	var stretch := _num(numbers, "stretch", 0.0)
	var scale := Vector2(1.0 + stretch * along_x - stretch * CROSS_SHARE * (1.0 - along_x),
		1.0 + stretch * (1.0 - along_x) - stretch * CROSS_SHARE * along_x)
	_squash(player, scale, _num(numbers, "stretchMs", 0.0))
	var feel := Services.feel()
	var lean_px := _num(numbers, "leanPx", 0.0)
	var lean_ms := _num(numbers, "leanMs", 0.0)
	var visual := player.get(&"visual") as Node2D
	if (feel != null and feel.reduce_motion) or lean_px <= 0.0 or lean_ms <= 0.0 or visual == null \
			or not visual.is_inside_tree() or not player.has_method(&"set_effect_offset"):
		return
	var previous: Variant = player.get_meta(LEAN_META) if player.has_meta(LEAN_META) else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	var tween := visual.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(Callable(player, &"set_effect_offset"), unit * lean_px, Vector2.ZERO, lean_ms / 1000.0)
	player.set_meta(LEAN_META, tween)


## The whoosh streak behind a thrown thing: {"ms", "px", "width", "lines"} (thrown_object.gd).
static func streak() -> Dictionary:
	var numbers := _block("throw")
	return {"ms": _num(numbers, "streakMs", 0.0), "px": _num(numbers, "streakPx", 0.0),
		"width": _num(numbers, "streakWidthPx", 2.0), "lines": int(_num(numbers, "streakLines", 1.0))}


## A thrown thing of `material` broke at `at` over the ground point `ground`, flying along
## `direction`; `break_particles` are the presets its break already plays at `at`.
static func landed(at: Vector2, ground: Vector2, material: String, direction: Vector2, break_particles: Array) -> void:
	var numbers := _block("land")
	var feel := Services.feel()
	if numbers.is_empty() or feel == null:
		return
	var dust_scale := _num(numbers, "dustScale", 0.0)
	var dusty := break_particles.has(DUST_PRESET) and at.distance_to(ground) <= GROUND_EPSILON_PX
	if dust_scale > 0.0 and not dusty:
		feel.burst(DUST_PRESET, ground, Vector2.ZERO, Color.WHITE, dust_scale)
	var heavy: Variant = numbers.get("heavyMaterials", [])
	if heavy is Array and (heavy as Array).has(material):
		feel.kick(_num(numbers, "heavyKickPx", 0.0), direction)


static func _squash(player: Node, scale: Vector2, ms: float) -> void:
	if ms > 0.0 and player.has_method(&"squash_by"):
		player.call(&"squash_by", scale, ms, Tween.TRANS_BACK, false)


static func _block(name: String) -> Dictionary:
	var constants := Services.constants()
	if constants == null:
		return {}
	var value: Variant = constants.value("%s.%s" % [ROOT, name], {})
	return value if value is Dictionary else {}


static func _num(numbers: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = numbers.get(key, fallback)
	return float(value) if value is float or value is int else fallback
