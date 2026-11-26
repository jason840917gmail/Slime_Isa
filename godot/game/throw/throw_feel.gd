extends RefCounted
## The throw's new feel (owner, 2026-11-16: "it was a strong hit and the monster got pushed back with
## nice effects and sounds", his Zelda reference; docs/godot/THROW_COMBAT.md): the switch and the
## numbers of game-constants.json `gulp.throwFeel`. While it is on, a thrown thing is bigger, faster
## and hits harder, breaks ON the enemy with an impact star, a ring and shards that fly on, the Gulp
## key throws on its press, and the hit carries the big-hit fields the enemies' reactions read
## (thrown_object.gd `rework_hit`). While it is off every reader gets the old numbers (`gulp`,
## `gulp.throwHit`, `gulp.throwCombat`, `gulp.feel`), so the throw plays exactly as before.
##
## - **The switch** (`is_on`): `gulp.throwFeel.enabled`, unless the session's dev switch says otherwise
##   (`set_session`, `toggle`: the throw yard's F1, to compare with the old feel).
## - **Numbers**: `base_damage`, `throw_speed`, `throw_range_px`, `look_px(weight)`, `hit_block(weight)`
##   (the weight's `hit` row: hit-stop, trauma, kick, sparks, knockback, launch speed), `streak`, and
##   the plain readers `number`, `flag`, `block`, `cue` for every other key.
## - **The rebound prototype** (`rebound_on`: the feel on and `gulp.throwFeel.rebound.enabled`, or
##   its own session switch, `toggle_rebound`: the throw yard's Shift+F1): sturdy things (stone,
##   metal, bone: a material with `rebound.uses.<material>`) bounce off what they strike instead of
##   shattering, land as the same thing again and can be caught in the air (thrown_object.gd,
##   throw_rebound.gd, mouth.gd `snap_catch`). `uses_of(material)` is how many hits such a thing
##   survives in all, `uses_left(held, material)` what a held one has left (`held.uses`), `wear_tint`
##   its darker look as it wears.
##
## Owner: throw combat (the sender).

const Services := preload("res://game/shared/services.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")

const ROOT := "gulp.throwFeel"

## The session's dev switch: -1 = the constants', 0 off, 1 on.
static var _session: int = -1
## The rebound prototype's own session switch: -1 = the constants', 0 off, 1 on.
static var _rebound_session: int = -1


## True while the new feel plays: the constants' switch or the session's.
static func is_on() -> bool:
	if _session == 0:
		return false
	return _session == 1 or enabled_in_data()


## The constants' switch (`gulp.throwFeel.enabled`).
static func enabled_in_data() -> bool:
	var constants := Services.constants()
	return constants != null and bool(constants.value(ROOT + ".enabled", false))


## The session's dev switch: the new feel on or off whatever the constants say.
static func set_session(on: bool) -> void:
	_session = 1 if on else 0


## Back to the constants' switch.
static func clear_session() -> void:
	_session = -1


## Flips the feel for the session; returns whether it is on now.
static func toggle() -> bool:
	set_session(not is_on())
	return is_on()


## A throw's base damage: `gulp.throwFeel.throwDamage`, or `gulp.throwCombat.throwDamage` while the feel
## is off (the yard's F1).
static func base_damage() -> float:
	return number("throwDamage", ThrowMode.base_damage()) if is_on() else ThrowMode.base_damage()


## A throw's speed (px/s) before its weight's scale: `throwSpeed`, or `gulp.throwSpeed`.
static func throw_speed() -> float:
	var old := _old("gulp.throwSpeed")
	return number("throwSpeed", old) if is_on() else old


## A throw's reach (px) before its weight's scale: `throwRangePx`, or `gulp.throwRangePx`.
static func throw_range_px() -> float:
	var old := _old("gulp.throwRangePx")
	return number("throwRangePx", old) if is_on() else old


## The flying look's size for a thing of `weight` ("" = light): `lookPx.<weight>`, or `fallback`
## while the feel is off.
static func look_px(weight: String, fallback: float) -> float:
	if not is_on():
		return fallback
	var sizes := block("lookPx")
	var value: Variant = sizes.get(weight if sizes.has(weight) else ThrowMode.LIGHT, fallback)
	return float(value) if value is float or value is int else fallback


## The hit numbers of a thing of `weight` ("" = light): `hit.<weight>` ({"hitStopMs", "trauma",
## "kickPx", "sparks", "knockbackPx", "knockbackSpeedScale", "launchSpeed"}); {} when missing.
static func hit_block(weight: String) -> Dictionary:
	var rows := block("hit")
	var row: Variant = rows.get(weight if rows.has(weight) else ThrowMode.LIGHT, {})
	return row if row is Dictionary else {}


## The whoosh streak behind the flying thing, as GulpFeel.streak: {"ms", "px", "width", "lines"}.
static func streak() -> Dictionary:
	var numbers := block("streak")
	return {"ms": float(numbers.get("ms", 0.0)), "px": float(numbers.get("px", 0.0)),
		"width": float(numbers.get("widthPx", 2.0)), "lines": int(numbers.get("lines", 1))}


## `gulp.throwFeel.<key>` as a number (`key` may be a dotted path), `fallback` when it is missing.
## Not switched: ask `is_on` first.
static func number(key: String, fallback: float = 0.0) -> float:
	var constants := Services.constants()
	var value: Variant = constants.value("%s.%s" % [ROOT, key], fallback) if constants != null else fallback
	return float(value) if value is float or value is int else fallback


## `gulp.throwFeel.<key>` as a switch; false while the feel is off.
static func flag(key: String) -> bool:
	if not is_on():
		return false
	var constants := Services.constants()
	return constants != null and bool(constants.value("%s.%s" % [ROOT, key], false))


## `gulp.throwFeel.<key>` as a Dictionary ({} when missing). Not switched.
static func block(key: String) -> Dictionary:
	var constants := Services.constants()
	var value: Variant = constants.value("%s.%s" % [ROOT, key], {}) if constants != null else {}
	return value if value is Dictionary else {}


## The global cue `cues.<name>` ("toss": the throw, "kill": a throw that kills); &"" when missing.
static func cue(name: String) -> StringName:
	return StringName(str(block("cues").get(name, "")))


# --- the rebound prototype ------------------------------------------------------------------------

## True while sturdy things rebound: the feel on, and `rebound.enabled` or the session's switch.
static func rebound_on() -> bool:
	if not is_on() or _rebound_session == 0:
		return false
	var constants := Services.constants()
	return _rebound_session == 1 or (constants != null and bool(constants.value(ROOT + ".rebound.enabled", false)))


## Flips the rebound for the session; returns whether it is on now.
static func toggle_rebound() -> bool:
	_rebound_session = 0 if rebound_on() else 1
	return rebound_on()


## `gulp.throwFeel.rebound.<key>` as a number, `fallback` when missing.
static func rebound_number(key: String, fallback: float = 0.0) -> float:
	return number("rebound." + key, fallback)


## How many hits on enemies a thing of `material` survives in all (`rebound.uses.<material>`); 0 for
## a material that shatters at once, and while the rebound is off.
static func uses_of(material: String) -> int:
	return int(number("rebound.uses." + material, 0.0)) if rebound_on() and not material.is_empty() else 0


## The hits a `held` thing of `material` has left: its own count (`held.uses`, carried from throw to
## throw and on the thing lying on the ground), else all of its material's.
static func uses_left(held: Dictionary, material: String) -> int:
	var own: Variant = held.get("uses")
	return int(own) if own is int or own is float else uses_of(material)


## A sturdy `held` thing's look as it wears: white when whole, toward `rebound.wearTint` (a grey
## level) on its last use. WHITE for anything else.
static func wear_tint(held: Dictionary, material: String) -> Color:
	var total := uses_of(material)
	if total <= 1:
		return Color.WHITE
	var worn := 1.0 - clampf(float(uses_left(held, material) - 1) / float(total - 1), 0.0, 1.0)
	var dark := rebound_number("wearTint", 1.0)
	return Color.WHITE.lerp(Color(dark, dark, dark, 1.0), worn)


static func _old(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0
