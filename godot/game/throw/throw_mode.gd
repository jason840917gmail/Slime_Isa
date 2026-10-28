extends RefCounted
## The throw-combat experiment (branch `exp/throw-combat`; docs/godot/THROW_COMBAT.md; owner,
## 2026-10-19): the Gulp is the whole fight. Enemies fall to what the slime throws, the attack key
## does nothing, and the body shapes are energy powers in the Ability Box. What the mouth can lift
## follows the Gulp's level: 1 light things, 2 medium, 3 heavy. A thing's weight sets its damage,
## reach and the hit's class; its material (or its kind) adds an effect: freeze, sleep, stick,
## shatter or pierce. All numbers are in game-constants.json `gulp.throwCombat`.
##
## - **The mode** rides on the body-shapes rework mode: main.gd decides it at every world build
##   (`set_on`): on when the rework mode is on, `gulp.throwCombat.enabled` is true and the launch
##   option `melee` (desktop `-- --melee`) is not given. While it is off every hook does nothing, so
##   the rework game plays exactly as on main.
## - **The Gulp's level** (`gulp_level`): 1, 2 once the run learned `gulp-lift-medium`, 3 once it
##   learned `gulp-lift-heavy` (RunState abilities: saved with the run). A dev level (`set_dev_level`:
##   the playground's F6, the launch option `gulp=<1..3>`) overrides it for the session.
## - **Weights** (`weight_of`): `kindWeights` names the medium and heavy kinds; every other held
##   thing (light kinds, bones, seeds, globs) is light. `can_lift` asks the level.
## - **Effects** (`effect_of`): `kindEffects`, then `materialEffects`; "" for none.
## - **Aim help** (`assist`): off unless `aimAssist.enabled` or the dev toggle (Shift+F6, launch option
##   `aimhelp`); then a throw within `coneDeg` of an enemy within `rangePx` flies straight at it.
## - **Shape powers** (`is_shape_power`): the shapes' ids in the Ability Box (ability_box.gd).
##
## Owner: throw combat (experiment).

const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")

const ROOT := "gulp.throwCombat"
const LIGHT := "light"
const MEDIUM := "medium"
const HEAVY := "heavy"
const WEIGHTS: Array[String] = [LIGHT, MEDIUM, HEAVY]
## The run's lift upgrades (RunState learned abilities), level 2 and level 3.
const LIFT_MEDIUM := "gulp-lift-medium"
const LIFT_HEAVY := "gulp-lift-heavy"
const MAX_LEVEL := 3
## Effects (`gulp.throwCombat.effects`).
const FREEZE := "freeze"
const SLEEP := "sleep"
const STICK := "stick"
const SHATTER := "shatter"
const PIERCE := "pierce"
## Enemies the aim help looks at.
const ENEMY_GROUP := &"enemy"

static var _on: bool = false
## The session's dev level (0 = the run's).
static var _dev_level: int = 0
## The session's aim-help toggle: -1 = the constants', 0 off, 1 on.
static var _dev_assist: int = -1


## True while the experiment runs (the rework mode on, the constants' switch on, no `melee`).
static func is_on() -> bool:
	return _on


## main.gd only, once per world build.
static func set_on(on: bool) -> void:
	_on = on


## The constants' switch (`gulp.throwCombat.enabled`).
static func enabled_in_data() -> bool:
	var constants := Services.constants()
	return constants != null and bool(constants.value(ROOT + ".enabled", false))


# --- the Gulp's level ----------------------------------------------------------------------------

## 1..3: the dev level when set, else what the run learned.
static func gulp_level() -> int:
	if _dev_level > 0:
		return _dev_level
	var run := Services.run()
	if run == null:
		return 1
	if run.has_learned_ability(LIFT_HEAVY):
		return 3
	if run.has_learned_ability(LIFT_MEDIUM):
		return 2
	return 1


## The session's dev level (1..3; 0 gives the run's back).
static func set_dev_level(level: int) -> void:
	_dev_level = clampi(level, 0, MAX_LEVEL)


## True once a dev level is set for the session.
static func has_dev_level() -> bool:
	return _dev_level > 0


## The dev level's next step (1, 2, 3, 1, ...); returns the new level.
static func cycle_dev_level() -> int:
	set_dev_level(gulp_level() % MAX_LEVEL + 1)
	return _dev_level


## The heaviest weight the Gulp lifts now.
static func level_weight(level: int = -1) -> String:
	var at := level if level > 0 else gulp_level()
	return WEIGHTS[clampi(at, 1, MAX_LEVEL) - 1]


# --- weights and effects -------------------------------------------------------------------------

## "light", "medium" or "heavy" for a liftable kind (or a held Dictionary's kind).
static func weight_of(kind: String) -> String:
	var table := _dict("kindWeights")
	var weight := str(table.get(kind, LIGHT))
	return weight if WEIGHTS.has(weight) else LIGHT


## A held thing's weight: the one it was lifted with (its liftable's `weight`), else its kind's.
static func weight_of_held(held: Dictionary) -> String:
	var weight := str(held.get("weight", ""))
	return weight if WEIGHTS.has(weight) else weight_of(str(held.get("kind", "")))


## The level a weight needs (1..3).
static func level_for(weight: String) -> int:
	return WEIGHTS.find(weight) + 1 if WEIGHTS.has(weight) else 1


## True when the Gulp's level lifts `kind`.
static func can_lift(kind: String) -> bool:
	return level_for(weight_of(kind)) <= gulp_level()


## The weight's row: {"level", "damageScale", "rangeScale", "speedScale", "radiusScale",
## "holdingSpeed", "hitClass"}.
static func weight_row(weight: String) -> Dictionary:
	return _dict("weights." + weight)


## A number of the weight's row, `fallback` when missing.
static func weight_number(weight: String, key: String, fallback: float = 1.0) -> float:
	return float(weight_row(weight).get(key, fallback))


## The effect a held thing carries ("" for none): its kind's, else its material's.
static func effect_of(kind: String, material: String) -> String:
	var by_kind := _dict("kindEffects")
	if by_kind.has(kind):
		return str(by_kind[kind])
	return str(_dict("materialEffects").get(material, ""))


## The effect's row (`gulp.throwCombat.effects.<id>`), {} for none.
static func effect_row(effect: String) -> Dictionary:
	return _dict("effects." + effect) if not effect.is_empty() else {}


## The hit class a throw carries: the effect's when it has one, else the weight's.
static func hit_class(weight: String, effect: String) -> String:
	var from_effect := str(effect_row(effect).get("hitClass", ""))
	if not from_effect.is_empty():
		return from_effect
	return str(weight_row(weight).get("hitClass", "thrown"))


## Base damage in the mode (`gulp.throwCombat.throwDamage`).
static func base_damage() -> float:
	var constants := Services.constants()
	return constants.number(ROOT + ".throwDamage") if constants != null else 0.0


# --- aim help -------------------------------------------------------------------------------------

static func assist_on() -> bool:
	if _dev_assist >= 0:
		return _dev_assist == 1
	var constants := Services.constants()
	return constants != null and bool(constants.value(ROOT + ".aimAssist.enabled", false))


## The dev toggle; returns the new state.
static func toggle_assist() -> bool:
	_dev_assist = 0 if assist_on() else 1
	return _dev_assist == 1


static func set_assist(on: bool) -> void:
	_dev_assist = 1 if on else 0


## `aim` (unit) bent onto the nearest live enemy within `coneDeg` of it and `rangePx` of `from`
## while the aim help is on; else `aim` itself.
static func assist(aim: Vector2, from: Vector2) -> Vector2:
	if not assist_on() or aim == Vector2.ZERO:
		return aim
	var tree := Engine.get_main_loop() as SceneTree
	var constants := Services.constants()
	if tree == null or constants == null:
		return aim
	var cone := deg_to_rad(constants.number(ROOT + ".aimAssist.coneDeg")) * 0.5
	var reach := constants.number(ROOT + ".aimAssist.rangePx")
	var best := aim
	var best_angle := INF
	for node: Node in tree.get_nodes_in_group(ENEMY_GROUP):
		var target := _enemy_point(node)
		if target == Vector2.INF:
			continue
		var offset := target - from
		var distance := offset.length()
		if distance < 1.0 or distance > reach:
			continue
		var angle := absf(aim.angle_to(offset))
		if angle <= cone and angle < best_angle:
			best_angle = angle
			best = offset / distance
	return best


## An enemy's centre (or its body's position), INF when it is dead or gone.
static func _enemy_point(node: Node) -> Vector2:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return Vector2.INF
	if node.has_method(&"is_defeated") and bool(node.call(&"is_defeated")):
		return Vector2.INF
	if node.has_method(&"get_centre"):
		var centre: Variant = node.call(&"get_centre")
		if centre is Vector2:
			return centre
	if node is Node2D:
		return (node as Node2D).global_position
	return Vector2.INF


# --- shape powers ---------------------------------------------------------------------------------

## True when `id` is a body shape standing in the Ability Box as a power (the mode on).
static func is_shape_power(id: StringName) -> bool:
	return _on and ShapeDefs.is_shape(id)


static func _dict(path: String) -> Dictionary:
	var constants := Services.constants()
	return constants.dictionary(ROOT + "." + path) if constants != null else {}
