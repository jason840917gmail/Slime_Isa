extends "res://game/scripts/enemy.gd"
class_name PatternedEnemyScript
## The base of the bestiary's patterned enemies (docs/godot/BESTIARY.md; the bestiary rows 5 to 10:
## the Popworm, the Spitcap, the Hopper, the Bramble Boar, the Thorn Guard Statue and the Rook
## Thief). Each of them moves by a pattern of its own instead of the base enemy's chase AI, so this
## script replaces the base step (`_step_enemy`) with:
##
## 1. the defeated path and the hit flash, as the base enemy;
## 2. a reaction stun (`set_hit_stun_until`): the body slides with the stun decay (or stands, when
##    `_slides_when_stunned` says no) and the pattern waits (`_on_stunned` may react);
## 3. else `_step_pattern(now, delta, target, engaged)`: the subclass's phase machine. `engaged` is
##    true while the slime is a live target inside the enemy's arena (`configure_arena`: the
##    Bestiary corner's pens give each enemy its pen), or, without an arena, within its
##    `targeting_radius`.
##
## Everything else is the base enemy's: the hurtbox and the router, hits and their reactions
## (EnemyReactions in the rework mode), death, the energy shard, rewards. The phase (`get_phase`) is
## what the reaction profile's `states` are keyed by (enemy.gd `reaction_phase`).
##
## What the patterns share:
## - **Numbers**: the type's `pattern` block in game/data/enemy-types.json (`pattern(key)`), so the
##   whole enemy is tuned in one place; the base stats (health, speeds, the contact hit) stay the
##   scene's exports and `attributes`, as for every enemy.
## - **Shielded phases** (`_shields(request)`): a phase that cannot be hurt (in the air, asleep,
##   hidden in its cap, charging) refuses every hit with "immune" (a clink), old-style and rework
##   hits alike; `_kill_hit(request)` names the hit that finishes it at once (the seed thrown back,
##   a Heavy Roll).
## - **No hurtbox** (`set_hurtbox(false)`): underground or high in the air nothing finds it.
## - **Not solid** (`set_solid(false)`): the slime passes over a mound or under a flyer.
## - **The look**: the art is a sheet of key poses (`visual.frame`, game/runtime/sheet_sprite.gd)
##   hanging from `pose` (a Node2D), which the patterns lift, bob, squash and lean in code; the
##   reactions' hit motion keeps the Visual's own transform. The sheets face right; `face_x` mirrors
##   them.
##
## Owner: enemy builder.

const GroundShadowLook := preload("res://game/enemy/ground_shadow.gd")
const ReactionProfileScript := preload("res://game/combat/reactions/reaction_profile.gd")
const Hearing := preload("res://game/audio/hearing.gd")
const ENEMY_TYPES_FILE := "enemy-types.json"
const PATTERN_KEY := "pattern"
const SHIELD_REASON := "immune"
const THROWN_TAG := "thrown"
const ROLL_TAG := "roll"
## The tag the Roll's bonk carries while the slime is in the Heavy (Stone) form (player_roll.gd).
const HEAVY_TAG := "heavy"

## The art's parent: the patterns move it (lift, bob, squash); the Visual under it keeps its own
## transform for the hit motion.
@export var pose: Node2D
## The sheet frame shown once it is defeated.
@export var defeated_frame: int = 0

## Payload {"phase": String, "time": float (Services.now_ms())}.
signal phase_changed(payload: Dictionary)

var _phase: String = ""
var _phase_started_at: float = 0.0
## Its old centre where it was placed (set on the first step): where it walks back to.
var _home: Vector2 = Vector2.INF
var _pattern: Dictionary = {}
var _hurtbox_layer: int = 0
var _body_layer: int = 0
var _hurtbox_on: bool = true
var _solid: bool = true
var _contact_ready_at: float = 0.0
var _shadow: GroundShadowLook


func _ready() -> void:
	super()
	_pattern = pattern_block(ReactionProfileScript.type_of(self))
	if damage_area != null:
		_hurtbox_layer = damage_area.collision_layer
	if body != null:
		_body_layer = body.collision_layer


## The phase the pattern is in ("" before its first step).
func get_phase() -> String:
	return _phase


## The phase's start (simulation ms).
func get_phase_started_at() -> float:
	return _phase_started_at


## Its old centre where it was placed (Vector2.INF before its first step).
func get_home() -> Vector2:
	return _home


## Sets where it goes back to when it has nothing to do (old centre).
func set_home(centre: Vector2) -> void:
	_home = centre


# --- the step --------------------------------------------------------------------------------------

func _step_enemy(delta: float) -> bool:
	if is_defeated():
		return super(delta)
	var now := Services.now_ms()
	_update_hit_flash(now)
	if _home == Vector2.INF:
		_home = get_centre()
	if now < get_hit_stun_until():
		if _slides_when_stunned():
			var decay := EnemyReactions.slide_decay() if ReworkMode.is_on() else HIT_STUN_VELOCITY_DECAY
			body.velocity *= pow(decay, delta * 60.0)
		else:
			body.velocity = Vector2.ZERO
		_on_stunned(now, delta)
		return true
	var target := _primary_target()
	_step_pattern(now, delta, target, _is_engaged(target))
	return true


## The subclass's phase machine: sets `body.velocity` (the base moves the body after it).
func _step_pattern(_now: float, _delta: float, _target: Dictionary, _engaged: bool) -> void:
	body.velocity = Vector2.ZERO


## One step of a reaction stun (after the slide); nothing by default.
func _on_stunned(_now: float, _delta: float) -> void:
	pass


## Whether a stun slides the body (a knockback, a launch); false for enemies rooted to the spot.
func _slides_when_stunned() -> bool:
	return true


## True while the slime is a live target the pattern goes after: inside the arena when there is
## one (the pen), else within `targeting_radius`.
func _is_engaged(target: Dictionary) -> bool:
	if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return false
	var centre: Vector2 = target.get("centre", get_centre())
	if not _arena.is_empty():
		return BossArena.contains(_arena, centre)
	return get_centre().distance_to(centre) <= targeting_radius


# --- hits ------------------------------------------------------------------------------------------

## A shielded phase refuses every hit but its kill hit ("immune": the sender clinks). The kill hit
## gets through in every phase, past the reaction profile's `states` immunities too (the seed
## thrown back into a hidden Spitcap, a Heavy Roll on a sleeping Statue, the glob thrown back into a
## Pipe Worm's pipe).
func can_receive_damage(input: Dictionary) -> Dictionary:
	if not is_defeated():
		var request: Dictionary = input.get("request", {})
		if _kill_hit(request):
			return {"accepted": true, "reason": ""}
		if _shields(request):
			return {"accepted": false, "reason": SHIELD_REASON}
	return super(input)


## The kill hit takes all that is left.
func mitigate_damage(input: Dictionary) -> float:
	var request: Dictionary = input.get("request", {})
	if _kill_hit(request):
		return maxf(float(input.get("scaled_damage", 0.0)), get_damage_state()["hp"])
	return super(input)


## True when the current phase cannot be hurt by `request`.
func _shields(_request: Dictionary) -> bool:
	return false


## True when `request` finishes it at once.
func _kill_hit(_request: Dictionary) -> bool:
	return false


## The request's `weapon_tags` include `tag`.
static func has_tag(request: Dictionary, tag: String) -> bool:
	var tags: Variant = request.get("weapon_tags", [])
	return tags is Array and (tags as Array).has(tag)


## The request is the Roll's bonk while the slime is Heavy (the Heavy skin: docs/godot/SKINS.md).
static func is_heavy_roll(request: Dictionary) -> bool:
	return has_tag(request, ROLL_TAG) and has_tag(request, HEAVY_TAG)


## One contact hit on the slime when its centre is within `reach` of this enemy's centre, at most
## once per `pattern("contactCooldownMs")`. True when it landed.
func _contact(target: Dictionary, damage: float, knockback: float, reach: float) -> bool:
	var now := Services.now_ms()
	if now < _contact_ready_at or target.is_empty() or damage <= 0.0:
		return false
	var centre: Vector2 = target.get("centre", Vector2.INF)
	if get_centre().distance_to(centre) > reach:
		return false
	_contact_ready_at = now + pattern("contactCooldownMs", 600.0)
	return _route_immediate_attack(target, damage, knockback)


## One hit on the slime from the old-centre point `origin` instead of this enemy's centre (a beam, a
## pickaxe landing, added 2026-10-16 for the Caverns' rows): `_route_immediate_attack`'s request in
## its own activation, knocked away from `origin` (along `knock` when it is given). True when it was
## accepted with damage.
func _route_hit_from(origin: Vector2, target: Dictionary, damage: float, knockback: float,
		knock: Vector2 = Vector2.ZERO) -> bool:
	var router := Services.router()
	if attack_area == null or router == null or body == null or damage <= 0.0:
		return false
	if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return false
	var target_area := target.get("hurtbox") as Area2D
	if target_area == null:
		return false
	var away: Vector2 = target.get("centre", origin) - origin
	var direction := knock.normalized() if knock != Vector2.ZERO else (away.normalized() if away != Vector2.ZERO else Vector2.ZERO)
	var areas: Array[Area2D] = [attack_area]
	var activation_id := router.begin_activation(self, areas)
	var effects: Array[Dictionary] = []
	if knockback > 0.0:
		effects.append({"effect_id": KNOCKBACK_EFFECT_ID, "potency": knockback})
	var result := router.route({
		"activation_id": activation_id,
		"source": self,
		"attack_area": attack_area,
		"target_area": target_area,
		"weapon_id": CONTACT_WEAPON_ID,
		"weapon_tags": CONTACT_WEAPON_TAGS.duplicate(),
		"damage_types": CONTACT_DAMAGE_TYPES.duplicate(),
		"base_damage": damage,
		"effects": effects,
		"impact": {"position": origin, "knock": direction},
	})
	router.end_activation(activation_id)
	return str(result.get("status", "")) == "accepted" and int(result.get("actual_damage", 0)) > 0


# --- phases ----------------------------------------------------------------------------------------

func _transition(phase: String, now: float) -> void:
	_phase = phase
	_phase_started_at = now
	phase_changed.emit({"phase": phase, "time": now})


func _elapsed(now: float) -> float:
	return now - _phase_started_at


# --- body, hurtbox, look ---------------------------------------------------------------------------

## The hurtbox on (as authored) or off (nothing finds it: underground, high in the air).
func set_hurtbox(on: bool) -> void:
	if damage_area == null or on == _hurtbox_on:
		return
	_hurtbox_on = on
	damage_area.set_deferred(&"collision_layer", _hurtbox_layer if on else 0)


func is_hurtbox_on() -> bool:
	return _hurtbox_on


## The body solid (as authored: the slime bumps it) or not (the slime passes over or under it).
## Its mask stays: it still keeps to the walls and the pen's fence.
func set_solid(on: bool) -> void:
	if body == null or on == _solid:
		return
	_solid = on
	body.set_deferred(&"collision_layer", _body_layer if on else 0)


func set_frame(index: int) -> void:
	if visual != null and index >= 0 and index < visual.hframes * visual.vframes:
		visual.frame = index


## Mirrors the art (drawn facing right) toward `dx` (< 0: left); 0 keeps it.
func face_x(dx: float) -> void:
	if visual != null and absf(dx) > 0.5:
		visual.flip_h = dx < 0.0


## The pose's lift above the feet (px), its squash (x, y) and its lean (radians).
func set_look(lift: float, squash: Vector2 = Vector2.ONE, lean: float = 0.0) -> void:
	if pose == null:
		return
	pose.position = Vector2(0.0, -lift)
	pose.scale = squash
	pose.rotation = lean


## A soft ellipse on the ground under it (made on first use; added once the body is set up).
func ground_shadow() -> GroundShadowLook:
	if _shadow == null and body != null:
		_shadow = GroundShadowLook.new()
		_shadow.name = "GroundShadow"
		if body.is_node_ready():
			body.add_child(_shadow)
		else:
			body.add_child.call_deferred(_shadow)
	return _shadow


## Velocity toward the old-centre point `point` at `speed`, stopping on it.
func _velocity_toward(point: Vector2, speed: float, delta: float) -> Vector2:
	var offset := point - get_centre()
	var distance := offset.length()
	if distance <= maxf(1.0, speed * maxf(delta, 0.0)):
		return Vector2.ZERO
	return offset / distance * speed


## Plays a global cue, but only where the slime could see this enemy (game/audio/hearing.gd): an
## enemy walking in another camera room or off the screen is silent.
func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null and cue != &"" and Hearing.heard(feet()):
		feel.audio_cue(cue)


func _puff(preset: StringName, at: Vector2) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.particles(preset, at)


## The feet (the root's ground point).
func feet() -> Vector2:
	return body.global_position if body != null else Vector2.ZERO


# --- death -----------------------------------------------------------------------------------------

func _defeat() -> void:
	if is_defeated():
		return
	set_frame(defeated_frame)
	set_look(0.0)
	super()
	_phase = "dead"


func _corpse_fade_ms() -> float:
	return pattern("corpseFadeMs", 0.0)


func _dispose_delay_ms() -> float:
	return pattern("corpseMs", DISPOSE_AFTER_DEFEAT_MS)


## The patterns flip their own art (`face_x`).
func _mirrors_side_facing() -> bool:
	return false


# --- numbers ---------------------------------------------------------------------------------------

## `pattern[key]` of this enemy's type in enemy-types.json, else `fallback`.
func pattern(key: String, fallback: float = 0.0) -> float:
	var value: Variant = _pattern.get(key)
	if value is float or value is int:
		var number := float(value)
		if is_finite(number):
			return number
	return fallback


## The `pattern` block of `type_id` in enemy-types.json ({} when none).
static func pattern_block(type_id: String) -> Dictionary:
	var constants := Services.constants()
	var data: Variant = constants.data_file(ENEMY_TYPES_FILE) if constants != null else null
	var types: Variant = (data as Dictionary).get("types", {}) if data is Dictionary else {}
	var entry: Variant = (types as Dictionary).get(type_id, {}) if types is Dictionary else {}
	var block: Variant = (entry as Dictionary).get(PATTERN_KEY, {}) if entry is Dictionary else {}
	return block if block is Dictionary else {}
