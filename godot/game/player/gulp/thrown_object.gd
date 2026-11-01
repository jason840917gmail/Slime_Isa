extends Node2D
## Something the slime throws with Q (owner, 2026-10-08; GAME_GUIDELINES "Signature Mechanic:
## Gulp"): a liftable (a pot, a rock, a pumpkin, ... game/scripts/liftable.gd) flies from the
## slime's mouth along the aim at `gulp.throwSpeed` for up to `gulp.throwRangePx`, falling in a low
## arc, and breaks at the first hurtbox it meets, at a wall, or where it lands. The break strikes
## every hurtbox in `gulp.throwHitRadiusPx` for `gulp.throwDamage` times its material's
## `gulp.throwDamageByMaterial` (AbilityWorld.strike_area, as the slam does) with
## `gulp.throwKnockback`. Essences are never thrown: the mouth spits them out whole (owner,
## 2026-10-09; mouth.gd).
##
## How it breaks follows its material (owner, 2026-10-09): a liftable bursts into chunks of its own
## picture (break_burst.gd) with that material's particles and sound (BREAK_PARTICLES, BREAK_CUES:
## a pot shatters, a crate splinters, a kettle clangs, a pumpkin splats).
##
## Its feel (gulp_feel.gd, `gulp.feel`): a whoosh streak trails it for its first `throw.streakMs`, and
## the landing puffs dust on the ground and nudges the camera for a heavy material (`land`).
##
## The node sits on the ground point under the flying thing (its shadow is there); the look rides
## above it. Gameplay runs on the physics step, so it pauses with the tree.
##
## Body-shapes rework (docs/godot/BODY_SHAPES.md "The hit"; combat-feel plan section 3; only while
## ReworkMode is on): the break sends each hurtbox in reach one request that carries the contract's
## `hit` (`rework_hit`: class `gulp.throwHit.class` ("thrown": tier 2, never a hold), tag
## `thrown`, the knock along the throw, launch speed `gulp.throwKnockback`, `knock_px`
## from `gulp.throwHit.knockbackPx`) and the `impact` effect instead of the old knockback, so the enemy's
## reaction profile decides what it does (a pot dazes a light enemy, and since it dealt damage the
## daze slides it back `knockbackPx`: EnemyReactions; owner, 2026-11-01). The throw's feel plays once (`gulp.throwHit` through HitJuice.swing_spec and
## GameFeel.play_hit), each target's number at the target; a clink (an immune target) plays
## `combat.chain.clink.hitStopMs` and HitBlocked.
##
## Throw combat (the experiment, docs/godot/THROW_COMBAT.md; only while ThrowMode is on): the thing's
## weight (`gulp.throwCombat.weights`) scales its speed, reach, hit radius and damage
## (`gulp.throwCombat.throwDamage` x material x weight) and picks the hit's class (`thrown`,
## `thrown-medium`, `thrown-heavy`); its effect (`effect_of`: its kind's, else its material's) can
## change the class (freeze: a long stun; sleep: asleep until a damaging hit, even on an invulnerable
## enemy on the ground) or slow the enemy (stick, honey: half pace for `slowMs`; `_show_effect`),
## drawn on the enemy by throw_status_look.gd,
## widen the break (shatter) or fly on through enemies (pierce: it strikes up to `pierceTargets`
## enemies, each once, and breaks on the last, a wall or its end).
##
## What it meets and strikes (rework and throw combat; owner: "nothing should cross walls"): only
## hurtboxes on the height level it was thrown from (the slime's) with no wall between it and them
## (AbilityWorld.hurtboxes_in_reach), each once (`_targets`); so it flies over a lower level's enemy
## and its break never reaches round a wall or up or down a cliff.
##
## Owner: abilities (the rework hit: mouth).

const Services := preload("res://game/shared/services.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const HeldLook := preload("res://game/player/gulp/held_look.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const HitJuice := preload("res://game/feel/hit_juice.gd")

## The rework hit's tags (BODY_SHAPES.md "The hit") and its class when `gulp.throwHit` has none.
const REWORK_TAGS: Array[String] = ["thrown"]
const REWORK_FALLBACK_CLASS := "thrown"
const DAMAGE_TYPES: Array[String] = ["physical"]
const CUE_CLINK := &"HitBlocked"

const LOOK_SIZE_PX := 30.0
## The flight starts at the slime's mouth height and lands on the ground, with a small rise.
const START_HEIGHT_PX := 26.0
const ARC_PX := 14.0
const SPIN_PER_S := 9.0
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)
const SHADOW_SIZE := Vector2(12.0, 5.0)
const BreakBurst := preload("res://game/player/gulp/break_burst.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")
const GooBomb := preload("res://game/scripts/goo_bomb.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const ThrowStatusLook := preload("res://game/throw/throw_status_look.gd")
## Reaction verbs that stun: an effect's look shows while they last (a sleep's while it sleeps).
const STUN_VERBS: Array[String] = ["daze", "knockdown", "stagger", "hold", "sleep"]
## The throw's whoosh streak and the landing's dust and nudge (gulp_feel.gd, `gulp.feel`): the
## streak's colour, its lines this far apart (x their width), the side lines this share of the middle
## one's length, starting this share of the look's size behind its centre.
const GulpFeel := preload("res://game/player/gulp/gulp_feel.gd")
const STREAK_COLOR := Color(1.0, 1.0, 1.0, 0.78)
const STREAK_GAP := 1.7
const STREAK_SIDE_SHARE := 0.65
const STREAK_BEHIND_SHARE := 0.35

## The particles each material adds to its chunks ("essence": a thrown essence's goo).
const BREAK_PARTICLES := {
	"clay": [&"dodge-dust"],
	"glass": [&"hit-spark", &"loot-sparkle"],
	"wood": [&"dodge-dust"],
	"metal": [&"hit-spark"],
	"stone": [&"dodge-dust"],
	"soft": [&"slime-splash"],
	"ice": [&"hit-spark", &"loot-sparkle"],
	"snow": [&"dodge-dust"],
	"crystal": [&"hit-spark", &"loot-sparkle"],
	# A skull or a bone from the skeletons (game/enemy/bone_skull.gd, game/scripts/bone.gd).
	"bone": [&"dodge-dust"],
}
## The global cue each material breaks with (Sound Picker round 5); HitDull until a cue exists.
const BREAK_CUES := {
	"clay": &"BreakClay",
	"glass": &"BreakGlass",
	"wood": &"BreakWood",
	"metal": &"BreakMetal",
	"stone": &"BreakStone",
	"soft": &"BreakSoft",
	"ice": &"BreakIce",
	"snow": &"BreakSoft",
	"crystal": &"BreakGlass",
	"bone": &"BreakWood",
}
const CUE_FALLBACK := &"HitDull"

var _player: Node
var _held: Dictionary = {}
var _direction: Vector2 = Vector2.RIGHT
var _range_px: float = 0.0
var _speed: float = 0.0
var _travelled: float = 0.0
var _look: Node2D
var _done: bool = false
## The whoosh streak (GulpFeel.streak) and the flight's age (simulation ms, the physics steps).
var _streak: Dictionary = {}
var _age_ms: float = 0.0
## Throw combat: the thing's weight and effect, the enemies already struck (area instance id ->
## true) and how many more a piercing throw may strike before it breaks.
var _weight: String = ""
var _effect: String = ""
var _struck: Dictionary = {}
var _pierce_left: int = 0
## The height level it was thrown from (the slime's; AbilityWorld.ANY_LEVEL without elevation).
var _level: int = AbilityWorld.ANY_LEVEL


## Starts the throw of `held` ({"kind", "essence"}) from the ground point `feet` along `direction`.
func launch(player: Node, held: Dictionary, feet: Vector2, direction: Vector2) -> void:
	_player = player
	_held = held.duplicate()
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	_speed = _constant("gulp.throwSpeed")
	_range_px = _constant("gulp.throwRangePx")
	_level = AbilityWorld.body_level(player.get(&"body") as Node2D) if player != null else AbilityWorld.ANY_LEVEL
	if ThrowMode.is_on() and GooBomb.from_held(_held) == null:
		_weight = ThrowMode.weight_of_held(_held)
		_effect = ThrowMode.effect_of(str(_held.get("kind", "")), HeldLook.material_of(_held))
		_speed *= ThrowMode.weight_number(_weight, "speedScale")
		_range_px *= ThrowMode.weight_number(_weight, "rangeScale")
		if _effect == ThrowMode.PIERCE:
			_pierce_left = int(ThrowMode.effect_row(_effect).get("pierceTargets", 1))
	global_position = feet
	z_index = 5
	_look = HeldLook.make(held, LOOK_SIZE_PX)
	add_child(_look)
	_place_look()
	_streak = GulpFeel.streak()
	queue_redraw()
	# A Goo Bomb flies with the throw, ticking (game/scripts/goo_bomb.gd `ride`).
	var bomb := GooBomb.from_held(_held)
	if bomb != null:
		bomb.call(&"ride", self)


func _physics_process(delta: float) -> void:
	if _done:
		return
	# The streak redraws while it shows, and once more to clear.
	if _age_ms <= float(_streak.get("ms", 0.0)):
		queue_redraw()
	_age_ms += delta * 1000.0
	var step := minf(_speed * delta, _range_px - _travelled)
	var from := _air_point()
	var next_ground := global_position + _direction * step
	var next_air := next_ground - Vector2(0.0, _height(minf(1.0, (_travelled + step) / maxf(1.0, _range_px))))
	var reach := AbilityWorld.line_reach(from, next_air, _player_rids())
	if reach.distance_to(next_air) > AbilityWorld.CLEAR_LINE_SLACK_PX:
		_break(reach)
		return
	global_position = next_ground
	_travelled += step
	_place_look()
	var met := _targets(next_air, _constant("gulp.throwHitRadiusPx"))
	if not met.is_empty():
		# Throw combat: a piercing thing strikes what it meets and flies on, up to its count.
		if _pierce_left > 1:
			_pierce_left -= 1
			_strike_rework(next_air, _damage(), str(_held.get("kind", "")), met)
		else:
			_break(next_air)
			return
	if _travelled >= _range_px - 0.01:
		_break(global_position)


func _draw() -> void:
	var points := PackedVector2Array()
	for i in 16:
		var angle := TAU * i / 16.0
		points.append(Vector2(cos(angle) * SHADOW_SIZE.x, sin(angle) * SHADOW_SIZE.y))
	draw_colored_polygon(points, SHADOW)
	_draw_streak()


## The whoosh streak behind the look for its first `gulp.feel.throw.streakMs`: lines trailing back
## along the throw, shrinking and fading as it ends.
func _draw_streak() -> void:
	var life := float(_streak.get("ms", 0.0))
	if life <= 0.0 or _age_ms >= life or _look == null:
		return
	var left := 1.0 - _age_ms / life
	var lines := maxi(1, int(_streak.get("lines", 1)))
	var width := float(_streak.get("width", 2.0))
	var length := float(_streak.get("px", 0.0)) * left
	var back := -_direction
	var across := Vector2(-_direction.y, _direction.x)
	var start := _look.position + back * LOOK_SIZE_PX * STREAK_BEHIND_SHARE
	for i in lines:
		var offset := (float(i) - float(lines - 1) * 0.5) * width * STREAK_GAP
		var middle := absf(offset) < 0.01
		var reach := length * (1.0 if middle else STREAK_SIDE_SHARE)
		var from := start + across * offset
		var color := Color(STREAK_COLOR, STREAK_COLOR.a * left * (1.0 if middle else 0.7))
		draw_line(from, from + back * reach * 0.5, color, width, true)
		draw_line(from + back * reach * 0.5, from + back * reach, Color(color, color.a * 0.5), width * 0.6, true)


func _place_look() -> void:
	if _look == null:
		return
	var t := _travelled / maxf(1.0, _range_px)
	_look.position = Vector2(0.0, -_height(t))
	_look.rotation = _travelled / maxf(1.0, _speed) * SPIN_PER_S


## Height above the ground at flight fraction `t`: from the mouth down to the ground, with a rise.
func _height(t: float) -> float:
	return START_HEIGHT_PX * (1.0 - t) + 4.0 * ARC_PX * t * (1.0 - t)


func _air_point() -> Vector2:
	return global_position - Vector2(0.0, _height(_travelled / maxf(1.0, _range_px)))


func _break(at: Vector2) -> void:
	_done = true
	var kind := str(_held.get("kind", ""))
	# A Goo Bomb never breaks or strikes: it drops whole on the ground under where the throw ended
	# (its end, a wall, the first hurtbox) and ticks on; it blows by its fuse.
	if kind == GooBomb.KIND:
		var bomb := GooBomb.from_held(_held)
		if bomb != null:
			bomb.call(&"land", global_position)
		queue_free()
		return
	var material := HeldLook.material_of(_held)
	if _player != null and is_instance_valid(_player):
		if ThrowMode.is_on():
			_strike_rework(at, _damage(), kind, _targets(at, _break_radius()))
		else:
			var damage := _constant("gulp.throwDamage") * _material_damage(material)
			var radius := _constant("gulp.throwHitRadiusPx")
			if ReworkMode.is_on():
				_strike_rework(at, damage, kind, _targets(at, radius))
			else:
				AbilityWorld.strike_area(_player, at, radius, damage, _constant("gulp.throwKnockback"),
					["thrown", kind], "thrown-" + kind)
	if _look is Sprite2D:
		BreakBurst.burst(get_parent(), at, _look as Sprite2D)
	var feel := Services.feel()
	if feel != null:
		for preset: StringName in BREAK_PARTICLES.get(material, [&"dodge-dust"]):
			feel.particles(preset, at)
		feel.audio_cue(BREAK_CUES.get(material, CUE_FALLBACK))
	# The landing's dust on the ground under it, and a heavy thing's nudge (gulp_feel.gd).
	GulpFeel.landed(at, global_position, material, _direction, BREAK_PARTICLES.get(material, [&"dodge-dust"]))
	queue_free()


## Throw combat: the damage of this throw (`gulp.throwCombat.throwDamage` x its material x its
## weight's and its effect's `damageScale`).
func _damage() -> float:
	var material := HeldLook.material_of(_held)
	return ThrowMode.base_damage() * _material_damage(material) \
		* ThrowMode.weight_number(_weight, "damageScale") \
		* float(ThrowMode.effect_row(_effect).get("damageScale", 1.0))


## Throw combat: the break's radius (`gulp.throwHitRadiusPx` x the weight's and a shatter's
## `radiusScale`).
func _break_radius() -> float:
	return _constant("gulp.throwHitRadiusPx") * ThrowMode.weight_number(_weight, "radiusScale") \
		* float(ThrowMode.effect_row(_effect).get("radiusScale", 1.0))


## The hurtboxes within `radius` of `at` this throw reaches (its own height level, no wall between:
## AbilityWorld.hurtboxes_in_reach) and has not struck yet; none without a live player.
func _targets(at: Vector2, radius: float) -> Array[Area2D]:
	var out: Array[Area2D] = []
	if _player == null or not is_instance_valid(_player):
		return out
	for area: Area2D in AbilityWorld.hurtboxes_in_reach(_player, at, radius, _level, _player_rids()):
		if not _struck.has(area.get_instance_id()):
			out.append(area)
	return out


## The slime's bodies (walls are looked for past them).
func _player_rids() -> Array[RID]:
	var rids: Array[RID] = []
	if _player != null and is_instance_valid(_player):
		rids = _player.call(&"body_rids")
	return rids


## The `hit` a thrown thing carries in the rework mode, pushing along `direction` (unit); throw
## combat names its class (`hit_class_override`).
static func rework_hit(direction: Vector2, hit_class_override: String = "") -> Dictionary:
	var block := _throw_hit_block()
	var hit_class := str(block.get("class", REWORK_FALLBACK_CLASS))
	if not hit_class_override.is_empty():
		hit_class = hit_class_override
	return HitReaction.build_hit(hit_class, {
		"step": 0,
		"last": true,
		"tags": REWORK_TAGS.duplicate(),
		"knock": direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO,
		"launch_speed": _constant("gulp.throwKnockback"),
		"knock_px": float(block.get("knockbackPx", 0.0)),
		"knock_speed_scale": float(block.get("knockbackSpeedScale", 1.0)),
	})


## Rework mode: each of `targets` (`_targets` around `at`: not the player's, not a resource, in
## reach, not struck yet) gets one request with the throw's `hit`; then the feel from the outcomes,
## one per target: {"receiver", "area", "position", "result"} (route()'s result, with the enemy's
## "reaction").
func _strike_rework(at: Vector2, damage: float, kind: String, targets: Array[Area2D]) -> void:
	if targets.is_empty() or _player == null or not is_instance_valid(_player):
		return
	var router := Services.router()
	var attack_area := _player.call(&"get_slam_area") as Area2D if _player.has_method(&"get_slam_area") else null
	if router == null or attack_area == null:
		return
	var outcomes: Array[Dictionary] = []
	var hit := rework_hit(_direction, ThrowMode.hit_class(_weight, _effect) if ThrowMode.is_on() else "")
	var activation := router.begin_activation(_player, [attack_area])
	for area in targets:
		var request := {
			"activation_id": activation,
			"source": _player,
			"attack_area": attack_area,
			"target_area": area,
			"weapon_id": "thrown-" + kind,
			"weapon_tags": ["thrown", kind],
			"damage_types": DAMAGE_TYPES.duplicate(),
			"base_damage": damage,
			"effects": [],
			"impact": {"position": area.global_position, "knock": hit["knock"]},
		}
		var receiver := router.receiver_for_area(area)
		var point := _target_point(receiver, area)
		_struck[area.get_instance_id()] = true
		var result := router.route(HitReaction.attach(request, hit.duplicate(true)))
		outcomes.append({"receiver": receiver, "area": area, "position": point, "result": result})
		_show_effect(receiver, result)
	router.end_activation(activation)
	_play_rework_feel(at, hit, outcomes)


## The throw's feel once (hit-stop, trauma, sparks at the break), then each target's number; a
## clink when nothing took the hit and a target was immune.
func _play_rework_feel(at: Vector2, hit: Dictionary, outcomes: Array[Dictionary]) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	var reactions: Array[Dictionary] = []
	var accepted := 0
	var killed := false
	var clinked := false
	for outcome: Dictionary in outcomes:
		var result: Dictionary = outcome["result"]
		if str(result.get("status", "")) == "accepted":
			accepted += 1
			killed = killed or bool(result.get("defeated", false))
			var reaction: Variant = result.get("reaction")
			if reaction is Dictionary:
				reactions.append(reaction as Dictionary)
		elif str(result.get("reason", "")) == "immune":
			clinked = true
	if accepted == 0:
		if clinked:
			var constants := Services.constants()
			var stop_ms := constants.number("combat.chain.clink.hitStopMs") if constants != null else 0.0
			feel.play_hit({"hit_stop_ms": stop_ms, "sound_cue": CUE_CLINK}, at, _direction)
		return
	var spec := HitJuice.swing_spec(_throw_hit_block(), hit, reactions, 0, accepted, killed)
	spec["number"] = 0
	feel.play_hit(spec, at, _direction)
	for outcome: Dictionary in outcomes:
		var result: Dictionary = outcome["result"]
		var dealt := int(result.get("actual_damage", 0))
		if str(result.get("status", "")) != "accepted" or dealt <= 0:
			continue
		var number := HitJuice.number_spec(dealt, hit)
		number["hit_stop_ms"] = 0.0
		feel.play_hit(number, outcome["position"], _direction)


## Throw combat: a freeze or a sleep that stunned `receiver` shows on it while the stun (the sleep)
## lasts; honey (an effect with `slowMs`; owner, 2026-11-01) that struck it and was not shrugged off
## (armor, a kill, a boss: enemy.gd `apply_tempo` refuses) slows it to `slowScale` of its pace for
## `slowMs` and coats it as long.
func _show_effect(receiver: Object, result: Dictionary) -> void:
	if not ThrowMode.is_on() or _effect.is_empty() or str(result.get("status", "")) != "accepted":
		return
	var reaction: Variant = result.get("reaction")
	if not reaction is Dictionary:
		return
	var verb := str((reaction as Dictionary).get("verb", ""))
	var row := ThrowMode.effect_row(_effect)
	var slow_ms := float(row.get("slowMs", 0.0))
	if slow_ms > 0.0:
		if verb == HitReaction.VERB_ARMOR or bool((reaction as Dictionary).get("killed", false)) \
				or receiver == null or not receiver.has_method(&"apply_tempo"):
			return
		if bool(receiver.call(&"apply_tempo", float(row.get("slowScale", 1.0)), slow_ms)):
			ThrowStatusLook.attach(receiver, _effect, slow_ms)
		return
	if not STUN_VERBS.has(verb):
		return
	var ms := float((reaction as Dictionary).get("stun_ms", 0.0))
	if ms <= 0.0:
		ms = float(ThrowMode.effect_row(_effect).get("lookMs", 0.0))
	ThrowStatusLook.attach(receiver, _effect, ms)


## Where a target's number shows: its centre when it has one, else its hurtbox.
static func _target_point(receiver: Object, area: Area2D) -> Vector2:
	if receiver != null and is_instance_valid(receiver) and receiver.has_method(&"get_centre"):
		var centre: Variant = receiver.call(&"get_centre")
		if centre is Vector2:
			return centre
	return area.global_position


## `gulp.throwHit` (the thrown hit's class and feel numbers); {} when missing.
static func _throw_hit_block() -> Dictionary:
	var constants := Services.constants()
	return constants.dictionary("gulp.throwHit") if constants != null else {}


## `gulp.throwDamageByMaterial[material]`, 1 when the material has no entry.
static func _material_damage(material: String) -> float:
	var constants := Services.constants()
	if constants == null:
		return 1.0
	var table := constants.dictionary("gulp.throwDamageByMaterial")
	return float(table.get(material, 1.0))


static func _constant(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0
