extends "res://game/enemy/patterned_enemy.gd"
class_name WormBulwarkScript
## Scene script `game.worm-bulwark` (the bestiary's row 37, a charger; docs/godot/BESTIARY.md
## "Worm Bulwark"; the owner, 2026-11-21): a hulking worm of Gorge's army in heavy armour behind a big
## iron tower shield. He charges at the slime once he sees it, after a wind-up, and cannot stop
## easily: he runs on well past where the slime stood, skids, and turns round slowly. Dodge him and
## throw at his back.
##
## - **Plod** (idle): he faces the slime behind his shield and plods toward it at `walkSpeed`; while
##   the slime is away he walks home at `homeSpeed`.
## - **Wind-up** (the tell, `windupMs`): once he sees the slime (within `sightPx`, a clear line,
##   `chargeCooldownMs` after his last run) he crouches behind the shield, stamps and glares red.
## - **Charge:** the line from his feet to the slime's is locked at the wind-up's end; he runs it dead
##   straight at `chargeSpeed` for up to `chargeMaxMs`. The slime in his way (`chargeHitPx`) is
##   bowled aside (`chargeDamage`, `chargeKnockback`, mostly sideways: `bowlSideShare`) and he runs
##   on: while he runs and skids the slime's body does not stop his (`_plough`). Anything else that stops him (a wall, the pen's fence, a rock, another enemy) slams his shield
##   into it: **dazed** for `dazedMs`, his back to the slime.
## - **Skid** (`skidMs`): at the run's end he skids on along his line, slowing from
##   `skidSpeedShare` of his charge speed to a stop; he still bowls the slime over early in it.
## - **Turn** (`turnMs`): he turns round slowly toward the slime (after a skid or a daze), then plods.
##
## How he is hurt (`hits` in his type's block of enemy-types.json; owner, 2026-11-21):
## - **The shield** blocks every hit from his front (the clink: the thing bounces off), a hit
##   coming within `shieldDot` of the way he faces; hits from his sides and back land. A thrown
##   thing is judged by the way it flies, any other hit by where the slime stands.
## - **Hits, not damage:** a light hit takes a third of his health, a medium a half, a heavy all of
##   it (`hits.light` 3, `hits.medium` 2, `hits.heavy` 1), whatever the thing is made of. A thrown
##   thing's weight is its hit (a thrown enemy is a medium hit); the shapes' and powers' hits are
##   counted by their tags (`hits.byTag`: the Axe's `cut` light, the Hammer's `crush` and the Goo
##   Bomb's `blast` medium). `hits.roundShield` tags reach round the shield (the Goo Bomb's blast).
## - `hits.clinkTags` never hurt him, from any side (the Spear, arrows, the Lantern's flame, the Roll).
## - His armour shrugs off the blows a knock brings (a wall splat, a bowled enemy, a fall, a danger
##   zone: `take_reaction_damage`): only counted hits wear him down. A hole or deep water still
##   takes him (that blow is all his health). Any other routed blow that hurts deals its own damage.
## - His run and skid are armoured (the reaction profile's `states`): a hit in the back hurts him
##   but does not stop him.
##
## Owner: enemy builder.

const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")

const PHASE_PLOD := "plod"
const PHASE_WINDUP := "windup"
const PHASE_CHARGE := "charge"
const PHASE_SKID := "skid"
const PHASE_TURN := "turn"
const PHASE_DAZED := "dazed"
## The sheet's frames (scripts/characters/pack-bestiary-enemies.py "worm-bulwark").
const FRAME_STAND := 0
const FRAME_WINDUP := 1
const FRAME_CHARGE := 2
const FRAME_DOWN := 3
const FRAME_CHARGE_FRONT := 4
const FRAME_CHARGE_BACK := 5
const FRAME_SKID := 6
const FRAME_DAZED := 7
## His type's block of how he is hurt (enemy-types.json `worm-bulwark.hits`).
const HITS_KEY := "hits"
const WEIGHT_LIGHT := "light"
const WEIGHT_MEDIUM := "medium"
const WEIGHT_HEAVY := "heavy"
const THROWN_CLASS := "thrown"
const THROWN_CLASSES := {"thrown": "light", "thrown-medium": "medium", "thrown-heavy": "heavy"}
## Borrowed cues until his own (a Sound Picker round): the boar's scrape, the Roll's launch and bonk,
## the clink of a blocked hit, a landing for the end of his daze.
const CUE_WINDUP := &"BoarScrape"
const CUE_CHARGE := &"RollLaunch"
const CUE_CRASH := &"RollBonk"
const CUE_SHIELD := &"HitBlocked"
const CUE_GET_UP := &"Land"
const DUST := &"dodge-dust"
const SPARKS := &"hit-spark"
## A blocked run: the mover left less than this share of the asked speed.
const BLOCKED_SHARE := 0.5
## Looking up or down when the way he faces is this much more vertical than sideways.
const VERTICAL_LOOK := 1.2
## Presentation: the plod's sway, the wind-up's stamp and red glare, the run's bob and dust, the
## daze's sway and the crash's bounce.
const PLOD_SWAY_RAD := 0.05
const PLOD_SWAY_MS := 160.0
const STAMP_MS := 110.0
const STAMP_PX := 3.0
const STAMP_DUST_MS := 180.0
const GLARE_TINT := Color(1.0, 0.62, 0.55)
const GLARE_PULSE_MS := 70.0
const EYE_RISE_PX := 40.0
const EYE_AHEAD_PX := 12.0
const CHARGE_BOB_PX := 2.0
const CHARGE_BOB_MS := 50.0
const TRAIL_DUST_MS := 80.0
const SKID_DUST_MS := 60.0
const SKID_LEAN_RAD := 0.1
const CRASH_BOUNCE_PX := 10.0
const CRASH_BOUNCE_MS := 240.0
const DAZE_SWAY_RAD := 0.07
const DAZE_SWAY_MS := 220.0

## The way he faces (unit): his shield's side.
var _heading: Vector2 = Vector2.RIGHT
## The run's line (unit), locked at the wind-up's end.
var _dir: Vector2 = Vector2.RIGHT
## The facing a turn starts from.
var _turn_from: Vector2 = Vector2.RIGHT
var _asked: Vector2 = Vector2.ZERO
var _ready_at: float = 0.0
var _dust_at: float = 0.0
var _hits: Dictionary = {}
## The slime's body layer was in his mask before a run took it out (`_plough`).
var _mask_had_player: bool = false
var _ploughing: bool = false


func _ready() -> void:
	super()
	_hits = hits_block(ReactionProfileScript.type_of(self))
	_plod(Services.now_ms())


# --- the pattern -----------------------------------------------------------------------------------

func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_PLOD:
			_step_plod(now, delta, target, engaged, centre, slime)
		PHASE_WINDUP:
			body.velocity = Vector2.ZERO
			_face(slime - centre)
			_windup_look(now, elapsed)
			if not engaged:
				_plod(now)
			elif elapsed >= pattern("windupMs", 800.0):
				# Along the ground: from his feet to the slime's.
				_charge(now, _target_feet(target, slime) - feet())
		PHASE_CHARGE:
			# The last move: did something stop him?
			var blocked := _asked != Vector2.ZERO and body.velocity.length() < _asked.length() * BLOCKED_SHARE
			if engaged:
				_bowl(target)
			if blocked:
				_crash(now)
				return
			if elapsed >= pattern("chargeMaxMs", 1600.0):
				_skid(now)
				return
			_asked = _dir * pattern("chargeSpeed", 280.0)
			body.velocity = _asked
			set_look(absf(sin(now / CHARGE_BOB_MS)) * CHARGE_BOB_PX)
			if now >= _dust_at:
				_dust_at = now + TRAIL_DUST_MS
				_puff(DUST, feet() - _dir * 22.0)
		PHASE_SKID:
			var t := clampf(elapsed / maxf(1.0, pattern("skidMs", 600.0)), 0.0, 1.0)
			var blocked := _asked != Vector2.ZERO and body.velocity.length() < _asked.length() * BLOCKED_SHARE
			if engaged and t < 0.5:
				_bowl(target)
			if t >= 1.0 or blocked:
				_turn(now)
				return
			_asked = _dir * pattern("chargeSpeed", 280.0) * pattern("skidSpeedShare", 0.8) * (1.0 - t)
			body.velocity = _asked
			set_look(0.0, Vector2.ONE, (-SKID_LEAN_RAD if _dir.x >= 0.0 else SKID_LEAN_RAD) * (1.0 - t))
			if now >= _dust_at and t < 0.8:
				_dust_at = now + SKID_DUST_MS
				_puff(DUST, feet() + _dir * 18.0)
		PHASE_TURN:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("turnMs", 900.0)), 0.0, 1.0)
			var goal := (slime - centre) if engaged else (get_home() - centre if get_home() != Vector2.INF else _turn_from)
			if goal.length() > 1.0:
				_heading = _turn_from.slerp(goal.normalized(), t).normalized()
			_show_side(FRAME_STAND)
			set_look(0.0, Vector2.ONE, sin(t * PI) * PLOD_SWAY_RAD)
			if t >= 1.0:
				_ready_at = now + pattern("chargeCooldownMs", 600.0)
				_plod(now)
		PHASE_DAZED:
			body.velocity = Vector2.ZERO
			var bounce := clampf(elapsed / CRASH_BOUNCE_MS, 0.0, 1.0)
			set_look(sin(bounce * PI) * CRASH_BOUNCE_PX, Vector2.ONE, sin(elapsed / DAZE_SWAY_MS) * DAZE_SWAY_RAD)
			if elapsed >= pattern("dazedMs", 1500.0):
				_cue(CUE_GET_UP)
				_turn(now)


func _step_plod(now: float, delta: float, target: Dictionary, engaged: bool, centre: Vector2, slime: Vector2) -> void:
	if not engaged:
		body.velocity = _velocity_home(pattern("homeSpeed", 50.0), delta)
		if body.velocity.length() > WALK_SPEED_THRESHOLD:
			_face(body.velocity)
		_plod_look(now, delta)
		return
	_face(slime - centre)
	var to_slime := slime - centre
	if to_slime.length() > pattern("holdPx", 70.0):
		body.velocity = to_slime.normalized() * pattern("walkSpeed", 50.0)
	else:
		body.velocity = Vector2.ZERO
	_plod_look(now, delta)
	if now >= _ready_at and to_slime.length() <= pattern("sightPx", 260.0) and _sees(target):
		_windup(now)


# --- phases ----------------------------------------------------------------------------------------

func _plod(now: float) -> void:
	_transition(PHASE_PLOD, now)
	_asked = Vector2.ZERO
	_plough(false)
	_calm()


func _windup(now: float) -> void:
	_transition(PHASE_WINDUP, now)
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	_cue(CUE_WINDUP)
	_puff(SPARKS, feet() + Vector2(_heading.x * EYE_AHEAD_PX, -EYE_RISE_PX))


func _charge(now: float, to_slime: Vector2) -> void:
	_dir = to_slime.normalized() if to_slime.length() > 1.0 else _heading
	_heading = _dir
	_asked = Vector2.ZERO
	_transition(PHASE_CHARGE, now)
	_plough(true)
	_calm()
	_show_facing(FRAME_CHARGE)
	_cue(CUE_CHARGE)
	_puff(DUST, feet() - _dir * 16.0)


func _skid(now: float) -> void:
	_transition(PHASE_SKID, now)
	_asked = Vector2.ZERO
	set_frame(FRAME_SKID)
	face_x(_dir.x)


## He turns round toward the slime (or home), slowly.
func _turn(now: float) -> void:
	_transition(PHASE_TURN, now)
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	_plough(false)
	_turn_from = _heading
	set_look(0.0)


## His shield slammed into something: dazed, his back to the slime.
func _crash(now: float) -> void:
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	_transition(PHASE_DAZED, now)
	_plough(false)
	set_frame(FRAME_DAZED)
	face_x(_dir.x)
	_cue(CUE_CRASH)
	_cue(CUE_SHIELD)
	_puff(SPARKS, get_centre() + _dir * 26.0)
	_puff(DUST, feet() + _dir * 20.0)
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("crashShakeMs", 160.0), pattern("crashShakeIntensity", 0.005))


## The slime in his way is bowled aside, mostly sideways (`bowlSideShare`), at most once per
## `contactCooldownMs`; he runs on. True when it landed.
func _bowl(target: Dictionary) -> bool:
	var now := Services.now_ms()
	if now < _contact_ready_at or target.is_empty():
		return false
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", Vector2.INF)
	if centre.distance_to(slime) > pattern("chargeHitPx", 40.0):
		return false
	var side := Vector2(-_dir.y, _dir.x)
	if side.dot(slime - centre) < 0.0:
		side = -side
	var share := clampf(pattern("bowlSideShare", 0.8), 0.0, 1.0)
	var knock := (side * share + _dir * (1.0 - share)).normalized()
	_contact_ready_at = now + pattern("contactCooldownMs", 600.0)
	return _route_hit_from(centre, target, pattern("chargeDamage", 30.0), pattern("chargeKnockback", 340.0), knock)


## While he runs and skids (`on`) the slime's body is out of his mask: he bowls it aside and runs on,
## and only what is no slime (a wall, a fence, a rock, another enemy) stops him. Off: his mask as it
## was.
func _plough(on: bool) -> void:
	if body == null or on == _ploughing:
		return
	_ploughing = on
	if on:
		_mask_had_player = (body.collision_mask & PLAYER_LAYER_BIT) != 0
		body.collision_mask &= ~PLAYER_LAYER_BIT
	elif _mask_had_player:
		body.collision_mask |= PLAYER_LAYER_BIT


func _defeat() -> void:
	_plough(false)
	super()


## The slime's feet (its body's ground point), else `fallback`.
func _target_feet(target: Dictionary, fallback: Vector2) -> Vector2:
	var player_body := target.get("body") as Node2D
	return player_body.global_position if player_body != null and is_instance_valid(player_body) else fallback


## A clear line to the slime (walls block it, water does not).
func _sees(target: Dictionary) -> bool:
	var world := Services.world()
	if world == null:
		return true
	var exclude: Array[RID] = [body.get_rid()]
	var player_body := target.get("body") as CollisionObject2D
	if player_body != null:
		exclude.append(player_body.get_rid())
	return world.line_of_sight(get_centre(), target.get("centre", get_centre()), exclude)


## A stun in the wind-up cancels the charge.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_WINDUP:
		_plod(now)
		_ready_at = get_hit_stun_until() + pattern("chargeCooldownMs", 600.0)


# --- the look --------------------------------------------------------------------------------------

## He faces `way` (his shield's side); 0 keeps the facing.
func _face(way: Vector2) -> void:
	if way.length() > 1.0:
		_heading = way.normalized()


## True while he looks up or down rather than sideways.
func _looks_vertical() -> bool:
	return absf(_heading.y) > absf(_heading.x) * VERTICAL_LOOK


## The side frame `side` (drawn facing right, mirrored toward the way he faces), or, while he faces
## up or down the screen, his walk's first step toward the viewer (behind his shield) or away from
## it (the sheet has no front or back stand or wind-up of their own: `walk_frame`'s cycles).
func _show_side(side: int) -> void:
	if _looks_vertical() and has_walk_frames():
		set_frame(walk_frame + (WALK_STEPS if _heading.y > 0.0 else WALK_STEPS * 2))
		return
	set_frame(side)
	face_x(_heading.x)


## The side frame `side` (mirrored by `face_x`), or charging toward the viewer behind his shield, or
## from behind, while he runs up or down the screen.
func _show_facing(side: int) -> void:
	if _looks_vertical():
		set_frame(FRAME_CHARGE_FRONT if _heading.y > 0.0 else FRAME_CHARGE_BACK)
	else:
		set_frame(side)
		face_x(_heading.x)


## Plodding: his inching walk (`show_walk`: side, toward the viewer, away) while he moves, else he
## stands facing the slime; a sheet without walks sways its standing pose.
func _plod_look(now: float, delta: float) -> void:
	var walking := body.velocity.length() > WALK_SPEED_THRESHOLD
	if walking and show_walk(delta, FRAME_STAND):
		set_look(0.0)
		return
	_show_side(FRAME_STAND)
	set_look(0.0, Vector2.ONE, sin(now / PLOD_SWAY_MS) * PLOD_SWAY_RAD if walking else 0.0)


## The wind-up: crouched behind the shield, stamping, glaring red.
func _windup_look(now: float, elapsed: float) -> void:
	_show_side(FRAME_WINDUP)
	set_look(absf(sin(elapsed / STAMP_MS)) * STAMP_PX, Vector2(1.04, 0.96))
	if pose != null:
		pose.modulate = Color.WHITE.lerp(GLARE_TINT, 0.5 + 0.5 * sin(now / GLARE_PULSE_MS))
	if now >= _dust_at:
		_dust_at = now + STAMP_DUST_MS
		_puff(DUST, feet() - _heading * 20.0)


## No glare showing.
func _calm() -> void:
	if pose != null:
		pose.modulate = Color.WHITE
	set_look(0.0)


# --- hits ------------------------------------------------------------------------------------------

## The shield's front, the clink tags anywhere, and his kill hit never.
func _shields(request: Dictionary) -> bool:
	if _tagged(request, "clinkTags"):
		return true
	if _tagged(request, "roundShield"):
		return false
	return is_from_front(request)


## A counted hit takes its share of his full health (a third, a half, all of it); any other blow
## deals its own damage. A hit the base turns to nothing (a shut gate, a sleep throw) stays nothing.
func mitigate_damage(input: Dictionary) -> float:
	var damage := super(input)
	var weight := hit_weight(input.get("request", {}))
	if weight.is_empty() or damage <= 0.0:
		return damage
	var hits: Variant = _hits.get(weight, 0)
	if not (hits is float or hits is int) or float(hits) <= 0.0:
		return damage
	return float(get_damage_state()["max_hp"]) / float(hits)


## The blows a knock brings (EnemyReactions' wall splat and bowling, EnemyHazards' fall and danger
## zones) do not hurt him; one that is all his health (a hole, deep water, a scripted kill) does.
func take_reaction_damage(amount: float) -> int:
	if amount + 0.5 < float(get_damage_state()["hp"]):
		return 0
	return super(amount)


## The weight of the hit in `request` as he counts it ("light", "medium", "heavy"; "" for a blow he
## takes as damage): a thrown thing's own weight (a thrown enemy is medium: its hit class), else the
## first of the request's tags in `hits.byTag`.
func hit_weight(request: Dictionary) -> String:
	var hit := HitReaction.hit_of(request)
	var hit_class := str(hit.get("class", ""))
	if THROWN_CLASSES.has(hit_class):
		return str(THROWN_CLASSES[hit_class])
	if hit_class.begins_with(THROWN_CLASS):
		var weight := str(hit.get("weight", ""))
		return weight if [WEIGHT_LIGHT, WEIGHT_MEDIUM, WEIGHT_HEAVY].has(weight) else WEIGHT_LIGHT
	var by_tag: Variant = _hits.get("byTag", {})
	if by_tag is Dictionary:
		for tag: Variant in by_tag:
			if has_tag(request, str(tag)):
				return str((by_tag as Dictionary)[tag])
	if hit.is_empty() and has_tag(request, THROWN_TAG):
		return WEIGHT_LIGHT
	return ""


## True when the hit in `request` comes at his front: within `shieldDot` of the way he faces. A
## thrown thing by the way it flies (its knock), any other hit by where its sender stands (else
## its impact point, else its knock).
func is_from_front(request: Dictionary) -> bool:
	var hit := HitReaction.hit_of(request)
	var hit_knock: Variant = hit.get("knock")
	var knock: Vector2 = hit_knock if hit_knock is Vector2 else Vector2.ZERO
	if knock == Vector2.ZERO:
		var impact: Variant = request.get("impact", {})
		var impact_knock: Variant = (impact as Dictionary).get("knock") if impact is Dictionary else null
		knock = impact_knock if impact_knock is Vector2 else Vector2.ZERO
	var dot := pattern("shieldDot", 0.35)
	var thrown := str(hit.get("class", "")).begins_with(THROWN_CLASS) or (hit.is_empty() and has_tag(request, THROWN_TAG))
	if not thrown:
		var at: Variant = null
		var source: Variant = request.get("source")
		if is_instance_valid(source) and source is Object and (source as Object).has_method(&"get_centre"):
			at = (source as Object).call(&"get_centre")
		if not at is Vector2 and source is Node2D and is_instance_valid(source):
			at = (source as Node2D).global_position
		if at is Vector2 and (at as Vector2).distance_to(get_centre()) > 1.0:
			return ((at as Vector2) - get_centre()).normalized().dot(_heading) >= dot
	if knock == Vector2.ZERO:
		return false
	return knock.normalized().dot(_heading) <= -dot


## The request carries one of the tags listed under `hits[key]`.
func _tagged(request: Dictionary, key: String) -> bool:
	var tags: Variant = _hits.get(key, [])
	if tags is Array:
		for tag: Variant in tags:
			if has_tag(request, str(tag)):
				return true
	return false


## The way he faces (unit): his shield's side.
func get_facing() -> Vector2:
	return _heading


## The `hits` block of `type_id` in enemy-types.json ({} when none).
static func hits_block(type_id: String) -> Dictionary:
	var constants := Services.constants()
	var data: Variant = constants.data_file(ENEMY_TYPES_FILE) if constants != null else null
	var types: Variant = (data as Dictionary).get("types", {}) if data is Dictionary else {}
	var entry: Variant = (types as Dictionary).get(type_id, {}) if types is Dictionary else {}
	var block: Variant = (entry as Dictionary).get(HITS_KEY, {}) if entry is Dictionary else {}
	return block if block is Dictionary else {}
