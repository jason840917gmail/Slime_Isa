extends RefCounted
## The throw rules (docs/godot/THROW_COMBAT.md; owner, 2026-10-19, the experiment that made them; one
## combat since 2026-11-25: always on, beside the weapon on the attack key, with no switch). What the
## mouth can lift follows the Gulp's level: 1 light things, 2 medium, 3 heavy. A thing's weight sets its
## damage, reach and the hit's class; its material (or its kind) adds an effect: freeze, sleep, stick,
## shatter or pierce. All numbers are in game-constants.json `gulp.throwCombat`.
##
## - **The Gulp's level** (`gulp_level`): 1, 2 once the run learned `gulp-lift-medium`, 3 once it
##   learned `gulp-lift-heavy` (RunState abilities: saved with the run). A dev level (`set_dev_level`:
##   the playground's F6, the launch option `gulp=<1..3>`) overrides it for the session.
## - **Weights** (`weight_of`): `kindWeights` names the medium and heavy kinds; every other held
##   thing (light kinds, bones, seeds, globs) is light. A weight's level is its place in WEIGHTS
##   (light 1, medium 2, heavy 3); `can_lift` asks the Gulp's level for a thing's weight.
## - **Effects** (`effect_of`): `kindEffects`, then `materialEffects`; "" for none.
## - `weight_in` and `effect_in` read a `gulp.throwCombat` Dictionary handed to them, so the editor
##   (liftable_root.gd, which reads the data file itself) picks them the same way.
## - **Aim help** (`assist`): off unless `aimAssist.enabled` or the dev toggle (Shift+F6, launch option
##   `aimhelp`); then a throw within half of `coneDeg` either side of a live enemy within `rangePx`
##   (on the thrower's height level, no wall between their feet) flies straight at the enemy's feet.
##
## Owner: throw combat (experiment).

const Services := preload("res://game/shared/services.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")

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

## The session's dev level (0 = the run's).
static var _dev_level: int = 0
## The session's aim-help toggle: -1 = the constants', 0 off, 1 on.
static var _dev_assist: int = -1


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
	return weight_in(_dict(""), kind)


## A kind's weight in `combat` (a `gulp.throwCombat` Dictionary): its `kindWeights` entry, else light.
static func weight_in(combat: Dictionary, kind: String) -> String:
	var table: Variant = combat.get("kindWeights")
	var weight := str((table as Dictionary).get(kind, LIGHT)) if table is Dictionary else LIGHT
	return weight if WEIGHTS.has(weight) else LIGHT


## A held thing's weight: the one it was lifted with (its liftable's `weight`), else its kind's.
static func weight_of_held(held: Dictionary) -> String:
	var weight := str(held.get("weight", ""))
	return weight if WEIGHTS.has(weight) else weight_of(str(held.get("kind", "")))


## The level a weight needs (1..3): its place in WEIGHTS.
static func level_for(weight: String) -> int:
	return WEIGHTS.find(weight) + 1 if WEIGHTS.has(weight) else 1


## True when the Gulp's level lifts a thing of `weight` (liftable.gd `can_take`, `is_too_heavy`).
static func can_lift(weight: String) -> bool:
	return level_for(weight) <= gulp_level()


## The weight's row: {"damageScale", "rangeScale", "speedScale", "radiusScale", "holdingSpeed",
## "hitClass"}.
static func weight_row(weight: String) -> Dictionary:
	return _dict("weights." + weight)


## A number of the weight's row, `fallback` when missing.
static func weight_number(weight: String, key: String, fallback: float = 1.0) -> float:
	return float(weight_row(weight).get(key, fallback))


## The effect a held thing carries ("" for none): its kind's, else its material's.
static func effect_of(kind: String, material: String) -> String:
	return effect_in(_dict(""), kind, material)


## The effect of `kind` made of `material` in `combat` (a `gulp.throwCombat` Dictionary):
## `kindEffects`, then `materialEffects`; "" for none.
static func effect_in(combat: Dictionary, kind: String, material: String) -> String:
	var by_kind: Variant = combat.get("kindEffects")
	if by_kind is Dictionary and (by_kind as Dictionary).has(kind):
		return str((by_kind as Dictionary)[kind])
	var by_material: Variant = combat.get("materialEffects")
	return str((by_material as Dictionary).get(material, "")) if by_material is Dictionary else ""


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


## `aim` (unit) of a throw by `thrower` (the slime's body: its feet are where the throw's ground
## track starts) bent onto the feet of the nearest live enemy within half of `coneDeg` either side of
## it and `rangePx` of the feet, on the thrower's height level with no wall between (what the throw
## could strike: AbilityWorld.body_level, clear_line), while the aim help is on; else `aim` itself.
static func assist(aim: Vector2, thrower: Node2D) -> Vector2:
	if not assist_on() or aim == Vector2.ZERO or thrower == null or not is_instance_valid(thrower):
		return aim
	var tree := Engine.get_main_loop() as SceneTree
	var constants := Services.constants()
	if tree == null or constants == null:
		return aim
	var cone := deg_to_rad(constants.number(ROOT + ".aimAssist.coneDeg")) * 0.5
	var reach := constants.number(ROOT + ".aimAssist.rangePx")
	var from := thrower.global_position
	var level := AbilityWorld.body_level(thrower)
	var best := aim
	var best_angle := INF
	for node: Node in tree.get_nodes_in_group(ENEMY_GROUP):
		var body := _enemy_body(node)
		if body == null:
			continue
		var offset := body.global_position - from
		var distance := offset.length()
		if distance < 1.0 or distance > reach:
			continue
		var angle := absf(aim.angle_to(offset))
		if angle > cone or angle >= best_angle:
			continue
		if level != AbilityWorld.ANY_LEVEL and AbilityWorld.body_level(body) != level:
			continue
		var exclude: Array[RID] = []
		for each: Node2D in [thrower, body]:
			if each is CollisionObject2D:
				exclude.append((each as CollisionObject2D).get_rid())
		if not AbilityWorld.clear_line(from, body.global_position, exclude):
			continue
		best_angle = angle
		best = offset / distance
	return best


## A live enemy's body (its feet are the body's position; the node itself without one), null when
## it is dead or gone.
static func _enemy_body(node: Node) -> Node2D:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return null
	if node.has_method(&"is_defeated") and bool(node.call(&"is_defeated")):
		return null
	if node.has_method(&"get_body"):
		var body: Variant = node.call(&"get_body")
		if is_instance_valid(body) and body is Node2D:
			return body as Node2D
	return node as Node2D


## `gulp.throwCombat.<path>` ({} when missing); the whole `gulp.throwCombat` for "".
static func _dict(path: String) -> Dictionary:
	var constants := Services.constants()
	if constants == null:
		return {}
	return constants.dictionary(ROOT if path.is_empty() else ROOT + "." + path)
