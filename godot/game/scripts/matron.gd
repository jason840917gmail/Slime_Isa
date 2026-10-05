extends "res://game/scripts/enemy.gd"
class_name MatronScript
## Scene script `game.matron` (Phaser `features/scripts/MatronScript.ts`): the Orb-Weaver Matron,
## the gloop-forest boss. Implements docs/godot/specs/matron.md section 3.
##
## Extends the base enemy as MatronScript extends EnemyScript: every step runs the whole base step
## first (the slime-spider AI, the web spit through the common ranged attack, the arena leash),
## then the phase machine below in `_after_enemy_step`, then the body moves once. Between volleys
## she fights like an orb weaver; every `volley_cadence_ms` she stops, marks `volley_points`
## circles (one on the slime) for `volley_telegraph_ms`, then the webs land: a slime inside a
## circle is hit and each circle becomes a web patch (`effect.<patch_effect_id>`, web_patch.gd).
## She rests `volley_rest_ms` afterwards. Every transition emits `phase_changed({phase, time})`
## (VolleySfx on `volley-telegraph`, SpitSfx on `volley-rest`).
##
## Node: `EnemyScript` under the Matron's CharacterBody2D (feet origin, `depth_anchor (0, 30)`).
## All points are old Phaser positions (`get_centre()` = feet - (0, 30)). Spawned by the
## `gloop-matron-nest` boss camp (boss_camp.gd), which hands it its arena.
##
## Owner: boss port.

const AttackTelegraph := preload("res://game/bosses/attack_telegraph.gd")

const PHASE_FIGHT := "fight"
const PHASE_VOLLEY_TELEGRAPH := "volley-telegraph"
const PHASE_VOLLEY_REST := "volley-rest"
const PHASE_DEAD := "dead"
## MatronScript.ts:78: the volley plays the side attack clip.
const CLIP_VOLLEY := "attack-side"
## MatronScript.ts:69: each volley turns its marks by 0.9 rad.
const VOLLEY_TURN_STEP := 0.9
## MatronScript.ts:53, 101: lower bounds of the telegraph time and the mark radius.
const MIN_VOLLEY_TELEGRAPH_MS := 500.0
const MIN_VOLLEY_RADIUS := 8.0
## MatronScript.ts:96: the landing's camera shake.
const VOLLEY_SHAKE_MS := 80.0
const VOLLEY_SHAKE_INTENSITY := 0.002
## Bosses are hit as enemies and bosses (UniversalSceneWorldController.ts:2199-2201).
const BOSS_RECEIVER_TAGS: Array[String] = ["enemy", "boss"]

## JSON `firstVolleyDelayMs` (3500): from the spawn to the first volley.
@export var first_volley_delay_ms: float = 3500.0
## JSON `volleyCadenceMs` (6500): from the end of a rest to the next volley.
@export var volley_cadence_ms: float = 6500.0
## JSON `volleyTelegraphMs` (900, at least 500).
@export var volley_telegraph_ms: float = 900.0
## JSON `volleyRestMs` (1300).
@export var volley_rest_ms: float = 1300.0
## JSON `volleyPoints` (4): marks per volley, the first on the slime.
@export var volley_points: float = 4.0
## JSON `volleySpread` (170): distance of the other marks from the slime.
@export var volley_spread: float = 170.0
## JSON `volleyRadius` (56, at least 8).
@export var volley_radius: float = 56.0
## JSON `volleyDamage` (20).
@export var volley_damage: float = 20.0
## JSON `volleyKnockbackStrength` (120).
@export var volley_knockback_strength: float = 120.0
## JSON `patchEffectId` ("matron-web-patch"; "" = no patches).
@export var patch_effect_id: String = ""

## Payload {"phase": String, "time": float (Services.now_ms())}.
signal phase_changed(payload: Dictionary)

var _phase: String = PHASE_FIGHT
var _phase_started_at: float = 0.0
var _next_volley_at: float = 0.0
## The marks of the current (or last) volley, old Phaser positions.
var _volley: Array[Vector2] = []
var _volley_sequence: int = 0


## Base `_ready`, then the first volley at now + first_volley_delay_ms (MatronScript.ts:32-35);
## warms the patch effect scene.
func _ready() -> void:
	super()
	_next_volley_at = Services.now_ms() + maxf(1.0, first_volley_delay_ms)
	var world := Services.world()
	if world != null and not patch_effect_id.is_empty():
		world.packed_scene("effect." + patch_effect_id)


## Clears the telegraph, then the base exit (MatronScript.ts:125-128).
func _exit_tree() -> void:
	AttackTelegraph.clear_for(self)
	super()


## "fight", "volley-telegraph", "volley-rest" or "dead".
func get_phase() -> String:
	return _phase


## Gameplay time the current phase started.
func get_phase_started_at() -> float:
	return _phase_started_at


## Gameplay time of the next volley (checked only while fighting).
func get_next_volley_at() -> float:
	return _next_volley_at


## The marks of the current (or last) volley.
func get_volley() -> Array[Vector2]:
	return _volley.duplicate()


## Volleys begun so far.
func get_volley_sequence() -> int:
	return _volley_sequence


## Matron spec 3.2 (MatronScript.ts:37-60), after the base step and before the body moves.
func _after_enemy_step(_delta: float) -> void:
	if is_defeated() or _phase == PHASE_DEAD or body == null:
		return
	var now := Services.now_ms()
	if _phase == PHASE_FIGHT:
		# Never mid-spit; while walking back into her arena she waits.
		if is_returning_to_arena() or now < _next_volley_at or is_attacking():
			return
		var target := _primary_target()
		if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
			return
		begin_volley(now, target["centre"])
		return
	body.velocity = Vector2.ZERO
	if _phase == PHASE_VOLLEY_TELEGRAPH:
		if now - _phase_started_at >= maxf(MIN_VOLLEY_TELEGRAPH_MS, volley_telegraph_ms):
			_land_volley(now)
		return
	if _phase == PHASE_VOLLEY_REST and now - _phase_started_at >= maxf(1.0, volley_rest_ms):
		_next_volley_at = now + maxf(1.0, volley_cadence_ms)
		_transition_to(PHASE_FIGHT, now)


## `beginVolley` (MatronScript.ts:63-81): the marks, one on `at` (the slime's centre) and the rest
## `volley_spread` around it at evenly spaced angles turned by 0.9 rad per volley, clamped into the
## arena; the telegraph (circles plus a shadow at `at`); the side attack clip; phase
## volley-telegraph. False unless fighting.
func begin_volley(now: float, at: Vector2) -> bool:
	if is_defeated() or _phase != PHASE_FIGHT:
		return false
	cancel_attack()
	var count := maxi(1, roundi(volley_points))
	var spread := maxf(0.0, volley_spread)
	var arena := get_arena()
	var turn := fmod(float(_volley_sequence) * VOLLEY_TURN_STEP, TAU)
	var points: Array[Vector2] = [at]
	for index in range(1, count):
		var angle := turn + (float(index - 1) / float(maxi(1, count - 1))) * TAU
		points.append(at + Vector2(cos(angle), sin(angle)) * spread)
	_volley.clear()
	for point: Vector2 in points:
		_volley.append(BossArena.clamp_point(arena, point) if not arena.is_empty() else point)
	_volley_sequence += 1
	AttackTelegraph.show_for(self, volley_shapes(), at)
	_play_animation(CLIP_VOLLEY, true)
	_transition_to(PHASE_VOLLEY_TELEGRAPH, now)
	return true


## The volley's marks as AreaShapes entries: circles of max(8, volley_radius) (MatronScript.ts:100-109).
func volley_shapes() -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var circle := CircleShape2D.new()
	circle.radius = maxf(MIN_VOLLEY_RADIUS, volley_radius)
	for point: Vector2 in _volley:
		shapes.append({"shape": circle, "transform": Transform2D(0.0, point)})
	return shapes


# --- damage receiver (MatronScript.ts:112-123) ------------------------------------------------

## A boss keeps her pattern: hits flash and show their damage but never cancel a volley, stagger
## or shove her.
func _react_to_damage(commit: Dictionary, _is_dead: bool) -> void:
	_show_hit_feedback(commit)


## Clears the telegraph, runs the base defeat, phase dead.
func _defeat() -> void:
	if is_defeated():
		return
	AttackTelegraph.clear_for(self)
	super()
	_transition_to(PHASE_DEAD, Services.now_ms())


# --- base hooks -------------------------------------------------------------------------------

## The common attack (the web spit) runs only while fighting (MatronScript.ts:116).
func _can_run_common_attack() -> bool:
	return _phase == PHASE_FIGHT


func _receiver_tags() -> Array[String]:
	return BOSS_RECEIVER_TAGS


## Bosses are not ordinary enemies, so their damage number rises from their position
## (UniversalSceneWorldController.ts:2039-2045).
func _damage_number_top() -> float:
	return get_centre().y


## Godot deviation (matron spec 4, as for Fatty): the dead body stays for its `die-<facing>` clip;
## Phaser removes it the step it dies.
func _dispose_delay_ms() -> float:
	return _clip_length_ms("die-" + _facing)


# --- phases -------------------------------------------------------------------------------------

## `landVolley` (MatronScript.ts:83-98): clear the telegraph; a slime whose hurtbox overlaps a mark
## takes the volley hit (no impact effect); a web patch on every mark; a small camera shake; rest.
func _land_volley(now: float) -> void:
	AttackTelegraph.clear_for(self)
	var shapes := volley_shapes()
	var target := _primary_target()
	if not target.is_empty() and bool(target.get("active", false)) and _target_overlaps(shapes, target):
		_route_immediate_attack(target, volley_damage, volley_knockback_strength, -1.0, false)
	for point: Vector2 in _volley:
		_spawn_effect_at(patch_effect_id, point)
	_shake_camera(VOLLEY_SHAKE_MS, VOLLEY_SHAKE_INTENSITY)
	_transition_to(PHASE_VOLLEY_REST, now)


func _transition_to(phase: String, now: float) -> void:
	_phase = phase
	_phase_started_at = now
	phase_changed.emit({"phase": phase, "time": now})
