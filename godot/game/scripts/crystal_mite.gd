extends "res://game/enemy/patterned_enemy.gd"
class_name CrystalMiteScript
## Scene script `game.crystal-mite` (the bestiary's row 29, a swarm; docs/godot/BESTIARY.md "Crystal
## Mite"): a tiny golem of pink crystal that the Crystal Colossus throws down. In the Bestiary's pen
## nobody throws them: they drop from above on their own, one per beat.
##
## - **Wait:** up out of sight (no art, no hurtbox, not solid) until the slime is in its pen, then
##   for its beat: the mites take turns, one every `beatMs` (a beat shared by every mite), the first
##   `dropDelayMs` after the slime came in.
## - **Drop** (the tell, `dropTellMs`): a shadow darkens on the ground near the slime (within
##   `scatterPx` of its feet, `arenaInsetPx` inside the pen) and, for the last `fallMs`, the mite
##   falls into it from `dropHeightPx`, curled in a ball. Landing on the slime (within `landHitPx`)
##   it hits for `landDamage`. A slime climbing a wall (the Feral skin; the Colossus's arena) gets a
##   mite dropped straight down the face onto it: its spot is the wall's foot right under the slime,
##   and on the way down it hits the climber above (within `climberHitPx` across, `dropHeightPx`
##   up), which knocks it off the wall (added by the dungeons, 2026-10-17).
## - **Land** (`landedMs`): it shakes itself out.
## - **Run:** at the slime at `runSpeed`; touching it (`contactReachPx`, every `contactCooldownMs`)
##   it hits for `contactDamage` with `knockbackStrength`. With the slime out of its pen it stands.
## - **Any hit** kills it (1 health, the `tiny` weight: every hit launches it and its kill pops);
##   killed, it can drop an energy shard (the reactions' `combat.energyShard` roll).
## The pen's slots cap how many there are at once.
##
## Owner: enemy builder.

const PHASE_WAIT := "wait"
const PHASE_DROP := "drop"
const PHASE_LAND := "land"
const PHASE_RUN := "run"
const FRAME_READY := 0
const FRAME_RUN := 1
const FRAME_BALL := 2
const CUE_LAND := &"DropLand"
const CUE_HIT := &"HitDull"
const DUST := &"dodge-dust"
## Presentation: the run's two-frame stride, the landing squash, the shadows.
const STRIDE_MS := 110.0
const LAND_SQUASH := Vector2(1.25, 0.75)
const SHADOW_SIZE := Vector2(12.0, 4.5)

## The next free beat, shared by every mite (simulation ms).
static var _next_beat_at: float = 0.0

var _drop_at: float = -1.0
var _spot: Vector2 = Vector2.ZERO
var _height: float = 0.0


func _ready() -> void:
	super()
	_transition(PHASE_WAIT, Services.now_ms())
	set_frame(FRAME_BALL)
	set_hurtbox(false)
	set_solid(false)
	_height = pattern("dropHeightPx", 240.0)
	if pose != null:
		pose.visible = false
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE
		shadow.strength = 0.0


func get_height() -> float:
	return _height


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var slime_body := target.get("body") as Node2D
	match _phase:
		PHASE_WAIT:
			if not engaged or slime_body == null:
				_drop_at = -1.0
				body.velocity = Vector2.ZERO
				return
			if _drop_at < 0.0:
				_drop_at = maxf(now + pattern("dropDelayMs", 400.0), _next_beat_at)
				_next_beat_at = _drop_at + pattern("beatMs", 900.0)
			if now >= _drop_at:
				_begin_drop(now, slime_body.global_position)
			body.velocity = Vector2.ZERO
		PHASE_DROP:
			# Unseen up there it moves over its spot first (nothing stops it: it is not solid).
			body.velocity = (_spot - feet()) / maxf(delta, 0.0001)
			var tell := maxf(1.0, pattern("dropTellMs", 750.0))
			var t := clampf(elapsed / tell, 0.0, 1.0)
			var fall_ms := maxf(1.0, pattern("fallMs", 280.0))
			var falling := clampf((elapsed - (tell - fall_ms)) / fall_ms, 0.0, 1.0)
			_height = lerpf(pattern("dropHeightPx", 240.0), 0.0, falling * falling)
			if pose != null:
				pose.visible = falling > 0.0
			var shadow := ground_shadow()
			if shadow != null:
				shadow.strength = t
				shadow.size = SHADOW_SIZE * lerpf(1.6, 1.0, t)
			set_look(_height)
			if t >= 1.0:
				_land(now, target, engaged)
		PHASE_LAND:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("landedMs", 450.0)), 0.0, 1.0)
			set_look(0.0, LAND_SQUASH.lerp(Vector2.ONE, t))
			if t >= 1.0:
				_transition(PHASE_RUN, now)
		PHASE_RUN:
			if engaged and slime_body != null:
				var slime: Vector2 = target.get("centre", get_centre())
				body.velocity = _velocity_toward(slime, pattern("runSpeed", 115.0), delta)
				face_x(slime.x - get_centre().x)
				if show_walk(delta, FRAME_READY):
					set_look(0.0)
				else:
					set_frame(FRAME_RUN if int(now / STRIDE_MS) % 2 == 0 else FRAME_READY)
					set_look(0.0, Vector2.ONE, 0.08 * signf(body.velocity.x))
				_contact(target, _attribute("contactDamage"), _attribute("knockbackStrength"), pattern("contactReachPx", 24.0))
			else:
				body.velocity = Vector2.ZERO
				set_frame(FRAME_READY)
				set_look(0.0)


func _begin_drop(now: float, slime_feet: Vector2) -> void:
	var scatter := pattern("scatterPx", 70.0)
	var angle := randf() * TAU
	_spot = _inside_arena(slime_feet + Vector2(cos(angle), sin(angle) * 0.7) * randf_range(scatter * 0.3, scatter))
	if _slime_climbing():
		# Straight down the face onto the climber: its spot the wall's foot right under it.
		_spot = _inside_arena(slime_feet)
	_transition(PHASE_DROP, now)
	set_frame(FRAME_BALL)
	_height = pattern("dropHeightPx", 240.0)


func _land(now: float, target: Dictionary, engaged: bool) -> void:
	_height = 0.0
	_transition(PHASE_LAND, now)
	set_frame(FRAME_READY)
	set_hurtbox(true)
	set_solid(true)
	if pose != null:
		pose.visible = true
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE
		shadow.strength = 1.0
	_cue(CUE_LAND)
	_puff(DUST, feet())
	var slime_body := target.get("body") as Node2D
	var on_it := slime_body != null and slime_body.global_position.distance_to(feet()) <= pattern("landHitPx", 26.0)
	if engaged and slime_body != null and (on_it or _hits_climber(slime_body.global_position)):
		if _route_hit_from(get_centre() - Vector2(0.0, 1.0), target, pattern("landDamage", 10.0), pattern("landKnockback", 160.0)):
			_cue(CUE_HIT)


## True while the slime climbs a wall (the Feral skin).
static func _slime_climbing() -> bool:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	return player != null and is_instance_valid(player) and player.has_method(&"is_climbing") and bool(player.call(&"is_climbing"))


## True when the slime climbs above this mite's spot (`slime_feet`): the mite fell down the face onto it.
func _hits_climber(slime_feet: Vector2) -> bool:
	if not _slime_climbing():
		return false
	var up := feet().y - slime_feet.y
	var across := absf(slime_feet.x - feet().x)
	return across <= pattern("climberHitPx", 30.0) and up >= -pattern("landHitPx", 26.0) and up <= pattern("dropHeightPx", 240.0)


## A point kept `arenaInsetPx` inside its pen (the point itself without a pen).
func _inside_arena(point: Vector2) -> Vector2:
	if _arena.is_empty():
		return point
	var inset := pattern("arenaInsetPx", 36.0)
	var x := float(_arena.get("x", point.x))
	var y := float(_arena.get("y", point.y))
	var w := float(_arena.get("w", 0.0))
	var h := float(_arena.get("h", 0.0))
	return Vector2(clampf(point.x, x + inset, x + w - inset), clampf(point.y, y + inset, y + h - inset))


## Up in the air, or not yet down: nothing reaches it.
func _shields(_request: Dictionary) -> bool:
	return _phase == PHASE_WAIT or _phase == PHASE_DROP


func _defeat() -> void:
	if is_defeated():
		return
	if pose != null:
		pose.visible = true
	super()
