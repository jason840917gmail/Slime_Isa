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
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const HeldLook := preload("res://game/player/gulp/held_look.gd")

const LOOK_SIZE_PX := 30.0
## The flight starts at the slime's mouth height and lands on the ground, with a small rise.
const START_HEIGHT_PX := 26.0
const ARC_PX := 14.0
const SPIN_PER_S := 9.0
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)
const SHADOW_SIZE := Vector2(12.0, 5.0)
const BreakBurst := preload("res://game/player/gulp/break_burst.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")

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
	var material := LiftableScript.material_of(kind)
	var damage := _constant("gulp.throwDamage") * _material_damage(material)
	if _player != null and is_instance_valid(_player):
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
