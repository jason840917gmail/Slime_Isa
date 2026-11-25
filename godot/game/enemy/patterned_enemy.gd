extends "res://game/scripts/enemy.gd"
class_name PatternedEnemyScript
## The base of the bestiary's patterned enemies (docs/godot/BESTIARY.md; the bestiary rows 5 to 10:
## the Popworm, the Spitcap, the Hopper, the Bramble Boar, the Thorn Guard Statue and the Rook
## Thief). Each of them moves by a pattern of its own instead of the base enemy's chase AI, so this
## script replaces the base step (`_step_enemy`) with:
##
## 1. the defeated path and the hit flash, as the base enemy;
## 2. a reaction stun (`set_hit_stun_until`): the body slides with the stun decay (or stands, when
##    `_slides_when_stunned` says no) and the pattern waits (`_on_stunned` may react); a sleep
##    throw's sleep renews the stun until a damaging hit wakes it (EnemyReactions `keep_asleep`);
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
##   hits alike, but a sleep throw lands through it while the phase is on the ground (EnemyReactions
##   `sleeps_through`) and a dungeon mechanism's blow in a phase not marked `noSleep` unless the enemy
##   is invulnerable by design (`blow_lands`); `_kill_hit(request)` names the hit
##   that finishes it at once (the seed thrown back, a Heavy Roll).
## - **No hurtbox** (`set_hurtbox(false)`): underground or high in the air nothing finds it.
## - **Not solid** (`set_solid(false)`): the slime passes over a mound or under a flyer.
## - **Airborne** (`set_airborne(true)`, a leap): no body mask, so the slime and the liftable things
##   pass under it; `air_blocked(motion)` is the leap's wall check (walls and water end it).
## - **A leap** (the Hopper, the Bone Leaper, the Squint): `plan_leap(offset)` at the tell picks the
##   landing (`landing_point`), `begin_leap()` takes off (not solid, airborne), `leap_step(t, air_ms,
##   delta)` flies it each step (false once it is over: its time, or a wall or the water ahead) and
##   `end_leap()` lands it (solid, on the ground); `_defeat` lands a leap cut short.
## - **The look**: the art is a sheet of key poses (`visual.frame`, game/runtime/sheet_sprite.gd)
##   hanging from `pose` (a Node2D), which the patterns lift, bob, squash and lean in code; the
##   reactions' hit motion keeps the Visual's own transform. The sheets face right; `face_x` mirrors
##   them.
## - **The walk home** (`_velocity_home(speed, delta)`; owner, 2026-11-21): round what stands in the
##   way instead of a straight line into it (game/enemy/way_around.gd), and a home it cannot reach
##   moves to where it stands. While it walks, its pattern still watches for the slime as before.
##
## Owner: enemy builder.

const GroundShadowLook := preload("res://game/enemy/ground_shadow.gd")
const ReactionProfileScript := preload("res://game/combat/reactions/reaction_profile.gd")
const Hearing := preload("res://game/audio/hearing.gd")
const ENEMY_TYPES_FILE := "enemy-types.json"
const PATTERN_KEY := "pattern"
const SHIELD_REASON := "immune"
const THROWN_TAG := "thrown"
## The tag the Spear's hits carry (its shape's tags, and the old spear weapons).
const SPEAR_TAG := "spear"
const ROLL_TAG := "roll"
## The tag the Roll's bonk carries while the slime is in the Heavy (Stone) form (player_roll.gd).
const HEAVY_TAG := "heavy"
## A walk cycle's frames per facing (`walk_frame`).
const WALK_STEPS := 4
## The physics layer bit of the slime's body (layer 2, "player").
const PLAYER_LAYER_BIT := 2
## The group of the liftable things (LiftableScript's GROUP) a leap passes over.
const LIFTABLE_GROUP := &"liftable"
## How many overlaps `air_blocked` asks the space for.
const AIR_MAX_HITS := 8
## The landing spot is searched back from the leap's end in steps of this many px.
const LANDING_STEP_PX := 4.0

## The art's parent: the patterns move it (lift, bob, squash); the Visual under it keeps its own
## transform for the hit motion.
@export var pose: Node2D
## The sheet frame shown once it is defeated.
@export var defeated_frame: int = 0
## The first frame of its walk cycles (WALK_STEPS frames facing right, mirrored for left, then
## WALK_STEPS walking toward the viewer, then WALK_STEPS walking away; docs/godot/BESTIARY.md
## "The look"); -1: a sheet without them (the pattern sways its standing pose instead).
@export var walk_frame: int = -1
## Presentation: the ground covered per walk frame (px), so the feet keep pace with the body.
@export var walk_step_px: float = 7.0

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
var _airborne: bool = false
var _ground_mask: int = 0
var _contact_ready_at: float = 0.0
var _shadow: GroundShadowLook
var _walked_px: float = 0.0
## A leap (`plan_leap`): from and to (ground points), and the velocity asked of the body last step.
var _leap_origin: Vector2 = Vector2.ZERO
var _leap_goal: Vector2 = Vector2.ZERO
var _leap_asked: Vector2 = Vector2.ZERO


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


## A fall took it to another level (enemy.gd `settle_at`): its home is where it landed.
func settle_at(centre: Vector2) -> void:
	super(centre)
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
		if ReworkMode.is_on():
			EnemyReactions.keep_asleep(self)
		if _slides_when_stunned():
			var decay := EnemyReactions.slide_decay_of(self) if ReworkMode.is_on() else HIT_STUN_VELOCITY_DECAY
			body.velocity *= pow(decay, delta * 60.0)
		else:
			body.velocity = Vector2.ZERO
		_on_stunned(now, delta)
		return true
	# On its legs in the danger zone a blow put it in, it walks out first (enemy.gd, enemy_hazards.gd).
	if ReworkMode.is_on() and _walk_out_of_zone():
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

## A shielded phase refuses every hit but its kill hit and a sleep throw on the ground
## (EnemyReactions `sleeps_through`: not a boss, not a `noSleep` phase; owner, 2026-11-01)
## ("immune": the sender clinks). The kill hit
## gets through in every phase, past the reaction profile's `states` immunities too (the seed
## thrown back into a hidden Spitcap, a Heavy Roll on a sleeping Statue, the glob thrown back into a
## Pipe Worm's pipe).
func can_receive_damage(input: Dictionary) -> Dictionary:
	if not is_defeated():
		var request: Dictionary = input.get("request", {})
		if _kill_hit(request):
			return {"accepted": true, "reason": ""}
		if _shields(request) and not EnemyReactions.sleeps_through(self, request) \
				and not EnemyReactions.blow_lands(self, request):
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


## Airborne (a leap): the body's mask is off, so it passes over the slime, the other bodies and the
## liftable things lying in the world (the Gulp's suckables). `air_blocked` still stops it at walls
## and water. On the ground the mask comes back as it was.
func set_airborne(on: bool) -> void:
	if body == null or on == _airborne:
		return
	_airborne = on
	if on:
		_ground_mask = body.collision_mask
		body.collision_mask = 0
	else:
		body.collision_mask = _ground_mask


## Airborne: whether the body, moved by `motion`, would meet a wall or water (the ground mask
## without the slime's own body). Liftables and bodies do not count: a leap passes over them.
func air_blocked(motion: Vector2) -> bool:
	return motion != Vector2.ZERO and _meets_solid(motion, _ground_mask, true)


## The tell of a leap: it will go from its feet by `offset` (ground px), landing where its body may
## stand (`landing_point`). Returns the landing point (where a tell's mark goes).
func plan_leap(offset: Vector2) -> Vector2:
	_leap_origin = feet()
	_leap_goal = landing_point(_leap_origin, _leap_origin + offset)
	_leap_asked = Vector2.ZERO
	return _leap_goal


## Takes off: not solid and airborne, so it passes over the slime, the other bodies and the liftable
## things.
func begin_leap() -> void:
	_leap_asked = Vector2.ZERO
	set_solid(false)
	set_airborne(true)


## One step of the leap planned (`t`: the share of its `air_ms` flown): the body flies toward the
## landing. False (the body stopped) once the leap is over: `t` reached 1, or a wall or the water lies
## ahead (`air_blocked`); the caller lands it then (`end_leap`).
func leap_step(t: float, air_ms: float, delta: float) -> bool:
	if t >= 1.0 or air_blocked(_leap_asked * delta):
		body.velocity = Vector2.ZERO
		return false
	_leap_asked = (_leap_goal - _leap_origin) / (maxf(1.0, air_ms) / 1000.0)
	body.velocity = _leap_asked
	return true


## Lands: solid and on the ground again (its mask back). Also on a defeat (`_defeat`), so a leap cut
## short leaves no body passing through walls.
func end_leap() -> void:
	_leap_asked = Vector2.ZERO
	set_solid(true)
	set_airborne(false)


## A leap's landing: the furthest point of `from`→`to` (at most `to`) where the body may stand, going
## back from `to` in steps: no wall, water or liftable thing under its shape there. The slime, the
## other bodies and the liftables it passes over on the way do not count. Call it on the ground,
## with `from` the feet.
func landing_point(from: Vector2, to: Vector2) -> Vector2:
	var steps := maxi(1, ceili(from.distance_to(to) / LANDING_STEP_PX))
	for i in range(steps, -1, -1):
		var at := from.lerp(to, float(i) / float(steps))
		if not _meets_solid(at - feet(), body.collision_mask, false):
			return at
	return from


## True when the body's shape, moved by `motion`, meets something of `mask` (the slime's own body
## and the player aside). With `liftables_pass` the liftable things do not count.
func _meets_solid(motion: Vector2, mask: int, liftables_pass: bool) -> bool:
	var shape_node := _body_shape()
	if shape_node == null:
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	var moved := shape_node.global_transform
	moved.origin += motion
	query.transform = moved
	query.collision_mask = mask & ~PLAYER_LAYER_BIT
	var exclude: Array[RID] = [body.get_rid()]
	query.exclude = exclude
	for hit: Dictionary in body.get_world_2d().direct_space_state.intersect_shape(query, AIR_MAX_HITS):
		if not (liftables_pass and _is_liftable(hit.get("collider"))):
			return true
	return false


## The body's first collision shape (the BodyShape child).
func _body_shape() -> CollisionShape2D:
	for child in body.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape != null:
			return child as CollisionShape2D
	return null


## A liftable thing: its root's LiftableScript child is in the liftable group.
static func _is_liftable(collider: Object) -> bool:
	var node := collider as Node
	var script_node := node.get_node_or_null(^"LiftableScript") if node != null else null
	return script_node != null and script_node.is_in_group(LIFTABLE_GROUP)


func set_frame(index: int) -> void:
	if visual != null and index >= 0 and index < visual.hframes * visual.vframes:
		visual.frame = index


## True when its sheet has the walk cycles (`walk_frame`).
func has_walk_frames() -> bool:
	return walk_frame >= 0 and visual != null and walk_frame + WALK_STEPS * 3 <= visual.hframes * visual.vframes


## Shows the walk cycle's frame for the way the body moves (side, mirrored by `face_x`; down; up),
## stepping every `walk_step_px` walked, or `stand` while it stands still. `first`: the cycles'
## first frame (another set than `walk_frame`, as the Bone Thrower's empty-handed walk). False
## (nothing shown) for a sheet without walk cycles.
func show_walk(delta: float, stand: int, first: int = walk_frame) -> bool:
	if not has_walk_frames() or first < 0 or first + WALK_STEPS * 3 > visual.hframes * visual.vframes:
		return false
	var velocity := body.velocity
	if velocity.length() <= WALK_SPEED_THRESHOLD:
		set_frame(stand)
		return true
	_walked_px += velocity.length() * delta
	var step := int(_walked_px / maxf(1.0, walk_step_px)) % WALK_STEPS
	var facing := first
	if absf(velocity.y) > absf(velocity.x):
		facing = first + (WALK_STEPS if velocity.y > 0.0 else WALK_STEPS * 2)
	else:
		face_x(velocity.x)
	set_frame(facing + step)
	return true


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


## Velocity of its walk home at `speed`, stopping on it: round what stands in the way
## (`_velocity_around`), and a home it cannot reach moves to where it stands, as after a fall.
func _velocity_home(speed: float, delta: float) -> Vector2:
	var velocity := _velocity_around(_home, speed, delta)
	if _way != null and _way.is_lost(Services.now_ms()):
		_home = get_centre()
		_way.reset()
		return Vector2.ZERO
	return velocity


## Velocity toward the old-centre point `point` at `speed`, stopping on it, as `_velocity_toward`,
## but round whatever blocks the straight line (game/enemy/way_around.gd: a wall, a rim, water, a
## fence, a rock). For the walks nobody watches the line of: home, to a thing on the ground. The
## steering is the base enemy's `_way` (its territory walk never runs here: this step replaces it).
func _velocity_around(point: Vector2, speed: float, delta: float) -> Vector2:
	var offset := point - get_centre()
	if _way == null:
		_way = WayAround.new()
	if _way_goal == Vector2.INF or _way_goal.distance_to(point) > 1.0:
		_way.reset()
		_way_goal = point
	if offset.length() <= maxf(1.0, speed * maxf(delta, 0.0)):
		_way.reset()
		return Vector2.ZERO
	return _way.heading(body, offset, Services.now_ms()) * speed


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
	end_leap()
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

## `pattern[key]` of this enemy's type in enemy-types.json, else `fallback`, at its tempo (`_paced`).
func pattern(key: String, fallback: float = 0.0) -> float:
	var value: Variant = _pattern.get(key)
	if value is float or value is int:
		var number := float(value)
		if is_finite(number):
			return _paced(key, number)
	return _paced(key, fallback)


## A honey throw's tempo (enemy.gd `apply_tempo`; owner, 2026-11-01: it moves and attacks 50%
## slower) on a pattern number: a time (a key ending in "Ms") lasts 1 / tempo as long and a speed
## ("...Speed", "...DegPerS") runs at tempo, so its walks, wind-ups, rests and leaps all slow down;
## any other number is as it is. A phase timed before the honey keeps its start, so it stretches.
func _paced(key: String, number: float) -> float:
	var pace := tempo()
	if pace >= 1.0:
		return number
	if key.ends_with("Ms"):
		return number / pace
	if key.ends_with("Speed") or key.ends_with("DegPerS"):
		return number * pace
	return number


## The `pattern` block of `type_id` in enemy-types.json ({} when none).
static func pattern_block(type_id: String) -> Dictionary:
	var constants := Services.constants()
	var data: Variant = constants.data_file(ENEMY_TYPES_FILE) if constants != null else null
	var types: Variant = (data as Dictionary).get("types", {}) if data is Dictionary else {}
	var entry: Variant = (types as Dictionary).get(type_id, {}) if types is Dictionary else {}
	var block: Variant = (entry as Dictionary).get(PATTERN_KEY, {}) if entry is Dictionary else {}
	return block if block is Dictionary else {}
