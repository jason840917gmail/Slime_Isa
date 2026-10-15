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
## The node sits on the ground point under the flying thing (its shadow is there); the look rides
## above it. Gameplay runs on the physics step, so it pauses with the tree.
##
## Body-shapes rework (docs/godot/BODY_SHAPES.md "The hit"; combat-feel plan section 3; only while
## ReworkMode is on): the break sends each hurtbox in reach one request that carries the contract's
## `hit` (`rework_hit`: class `gulp.throwHit.class` ("thrown": tier 2, never a hold), tag
## `thrown`, the knock along the throw, launch speed `gulp.throwKnockback`) and the `impact` effect
## instead of the old knockback, so the enemy's reaction profile decides what it does (a pot dazes
## a light enemy). The throw's feel plays once (`gulp.throwHit` through HitJuice.swing_spec and
## GameFeel.play_hit), each target's number at the target; a clink (an immune target) plays
## `combat.chain.clink.hitStopMs` and HitBlocked.
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


## Starts the throw of `held` ({"kind", "essence"}) from the ground point `feet` along `direction`.
func launch(player: Node, held: Dictionary, feet: Vector2, direction: Vector2) -> void:
	_player = player
	_held = held.duplicate()
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	_speed = _constant("gulp.throwSpeed")
	_range_px = _constant("gulp.throwRangePx")
	global_position = feet
	z_index = 5
	_look = HeldLook.make(held, LOOK_SIZE_PX)
	add_child(_look)
	_place_look()
	# A Goo Bomb flies with the throw, ticking (game/scripts/goo_bomb.gd `ride`).
	var bomb := GooBomb.from_held(_held)
	if bomb != null:
		bomb.call(&"ride", self)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := minf(_speed * delta, _range_px - _travelled)
	var from := _air_point()
	var next_ground := global_position + _direction * step
	var next_air := next_ground - Vector2(0.0, _height(minf(1.0, (_travelled + step) / maxf(1.0, _range_px))))
	var exclude: Array[RID] = []
	if _player != null and is_instance_valid(_player):
		exclude = _player.call(&"body_rids")
	var reach := AbilityWorld.line_reach(from, next_air, exclude)
	if reach.distance_to(next_air) > 0.5:
		_break(reach)
		return
	global_position = next_ground
	_travelled += step
	_place_look()
	var radius := _constant("gulp.throwHitRadiusPx")
	if _player != null and not AbilityWorld.hurtboxes_at(_player, next_air, radius).is_empty():
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
	var material := LiftableScript.material_of(kind)
	var damage := _constant("gulp.throwDamage") * _material_damage(material)
	if _player != null and is_instance_valid(_player):
		if ReworkMode.is_on():
			_strike_rework(at, damage, kind)
		else:
			AbilityWorld.strike_area(_player, at, _constant("gulp.throwHitRadiusPx"), damage,
				_constant("gulp.throwKnockback"), ["thrown", kind], "thrown-" + kind)
	if _look is Sprite2D:
		BreakBurst.burst(get_parent(), at, _look as Sprite2D)
	var feel := Services.feel()
	if feel != null:
		for preset: StringName in BREAK_PARTICLES.get(material, [&"dodge-dust"]):
			feel.particles(preset, at)
		feel.audio_cue(BREAK_CUES.get(material, CUE_FALLBACK))
	queue_free()


## The `hit` a thrown thing carries in the rework mode, pushing along `direction` (unit).
static func rework_hit(direction: Vector2) -> Dictionary:
	var block := _throw_hit_block()
	var hit_class := str(block.get("class", REWORK_FALLBACK_CLASS))
	return HitReaction.build_hit(hit_class, {
		"step": 0,
		"last": true,
		"tags": REWORK_TAGS.duplicate(),
		"knock": direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO,
		"launch_speed": _constant("gulp.throwKnockback"),
	})


## Rework mode: every hurtbox within `gulp.throwHitRadiusPx` of `at` gets one request with the
## throw's `hit` (AbilityWorld.hurtboxes_at: not the player's, not a resource); then the feel from
## the outcomes, one per target: {"receiver", "area", "position", "result"} (route()'s result, with
## the enemy's "reaction").
func _strike_rework(at: Vector2, damage: float, kind: String) -> void:
	var router := Services.router()
	var attack_area := _player.call(&"get_slam_area") as Area2D if _player.has_method(&"get_slam_area") else null
	if router == null or attack_area == null:
		return
	var targets := AbilityWorld.hurtboxes_at(_player, at, _constant("gulp.throwHitRadiusPx"))
	if targets.is_empty():
		return
	var outcomes: Array[Dictionary] = []
	var hit := rework_hit(_direction)
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
		var result := router.route(HitReaction.attach(request, hit.duplicate(true)))
		outcomes.append({"receiver": receiver, "area": area, "position": point, "result": result})
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
