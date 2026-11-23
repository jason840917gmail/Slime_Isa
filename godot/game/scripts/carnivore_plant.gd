extends "res://game/enemy/patterned_enemy.gd"
class_name CarnivorePlantScript
## Scene script `game.carnivore-plant` (the bestiary's row 38; docs/godot/BESTIARY.md "38. Carnivore
## Plant"; the owner, 2026-11-21): a greedy man-eating plant in a big clay pot. She never leaves her
## pot and eats whatever comes near: the slime, and other enemies too. She strikes to either side,
## down toward the viewer and up away from it (her poses for each: `_strike_way`).
##
## - **Reach:** `reach_px` (her placed enemy's "Reach" in the Inspector, drawn round her in the 2D
##   view; 0: her type's `biteRangePx`) is how far her snap takes things (`bite_reach`); she opens at
##   the same share of it as `tellRangePx` is of `biteRangePx` (`tell_reach`), and a thrown enemy is
##   food within as much more as `feedReachPx` is beyond `biteRangePx` (`feed_reach`).
## - **Wait:** she watches from her pot (a slow sway). Anything within her tell reach of her pot (the
##   slime's feet, an enemy's feet) and `recoverMs` after her last bite sets her off.
## - **Open** (the tell, `tellMs`): she rears up, jaws wide, toward it.
## - **Snap** (`snapMs`): her head lunges at the nearest thing within her bite reach (the slime only
##   while it does not roll) and the jaws close on it where her head reaches (`_jaw`):
##   - **an enemy:** it dies where it stood (its rewards fall there; every listener hears its death)
##     and its body slides into her jaws as they close (the base enemy's FATE_EATEN). Then she
##     **eats** it: hauls it back over her pot (`haulMs`), munches it `munches` times (`munchMs`),
##     **swallows** it (`swallowMs`: a bulge down her stem) and **burps** (`burpMs`), and sleeps to
##     **digest** until the world is built again (a chunk built anew, a room entered again).
##   - **the slime:** dragged into her jaws (its own recoil, `pullMs`), hidden there and rooted
##     (`sticky`) while she chews for `holdMs` (`chewDamage` every `chewMs`, none within `chewMs` of
##     the spit), then she **spits** it far back out the way she struck (`spitDamage`, then its own
##     recoil: `spitPx` in `spitFlyMs`) and rests (`recoverMs`).
##   - nothing: she misses and rests `missRecoverMs`.
## - **A thrown thing** (any liftable) puts her to sleep (**doze**) for `dozeMs`; a second one starts
##   the count again. Asleep, dozing or digesting, she bites nothing.
## - **A thrown enemy** (enemies as ammo) is food, but she never catches it in the air: landing within
##   her feed reach of her pot while she is awake, it bounces off her (`feedBouncePx` in
##   `feedBounceMs`, a hop) and lies dazed (`feedDazeMs`) with no landing hit (`catch_thrown`, called
##   by game/throw/gulpable_enemy.gd); `feedPickMs` later she picks it up off the floor: open, snap,
##   eat, digest.
## - **Only fire kills her** (a hit tagged `fire`: the Lantern's flame), in any phase; every other
##   blow (the shapes, the Roll, arrows, the Goo Bomb) clinks. A thrown thing hurts her not at all.
##
## Owner: enemy builder.

const EnemyHitMotion := preload("res://game/feel/enemy_hit_motion.gd")

const PHASE_WAIT := "wait"
const PHASE_OPEN := "open"
const PHASE_SNAP := "snap"
const PHASE_EAT := "eat"
const PHASE_CHEW := "chew"
const PHASE_SPIT := "spit"
const PHASE_RECOVER := "recover"
const PHASE_DOZE := "doze"
const PHASE_DIGEST := "digest"
## The sheet's frames (scripts/characters/pack-bestiary-enemies.py "carnivore-plant"); the side poses
## face right (mirrored for left), the down poses face the viewer, the up poses face away.
const FRAME_WAIT := 0
const FRAME_OPEN := 1
const FRAME_SNAP := 2
const FRAME_CHEW := 3
const FRAME_DOZE := 4
const FRAME_DIGEST := 5
const FRAME_SPIT := 6
const FRAME_BURNT := 7
const FRAME_OPEN_DOWN := 8
const FRAME_SNAP_DOWN := 9
const FRAME_OPEN_UP := 10
const FRAME_SNAP_UP := 11
const FRAME_SPIT_DOWN := 12
const FRAME_SPIT_UP := 13
const FRAME_SWALLOW := 14
const FRAME_BURP := 15
## Where her jaws are in the snap and the spit poses, from her pot's foot, in sheet px (facing right,
## down, up; scaled by the Visual's scale), measured on the packed sheet.
const JAW_SNAP_SIDE := Vector2(120.0, -131.0)
const JAW_SNAP_DOWN := Vector2(27.0, 36.0)
const JAW_SNAP_UP := Vector2(-9.0, -208.0)
const JAW_SPIT_SIDE := Vector2(64.0, -127.0)
const JAW_SPIT_DOWN := Vector2(11.0, -25.0)
const JAW_SPIT_UP := Vector2(-2.0, -145.0)
## A victim's feet sit this far under her jaws (its middle in them).
const VICTIM_RISE_PX := 14.0
## She strikes up or down when the target is more below or above her than to her side.
const VERTICAL_SHARE := 1.0
const FIRE_TAG := "fire"
const STICKY := &"sticky"
## The thing thrown at her was an enemy (game/throw/gulpable_enemy.gd KIND): food, not a blow.
const ENEMY_KIND_TAG := "enemy"
## The group game/throw/gulpable_enemy.gd asks to catch a thrown enemy as it lands.
const EATERS_GROUP := &"enemy_eaters"
## Her own cues (the owner's picks of Sound Picker round 14, docs/godot/specs/audio.md section 16).
const CUE_OPEN := &"PlantOpen"
const CUE_SNAP := &"PlantSnap"
const CUE_MUNCH := &"PlantMunch"
const CUE_SWALLOW := &"PlantSwallow"
const CUE_BURP := &"PlantBurp"
const CUE_SPIT := &"PlantSpit"
const CUE_DOZE := &"PlantDoze"
const CUE_BURN := &"PlantBurn"
const DUST := &"dodge-dust"
const SNORE_TEXT := "z"
const BURP_TEXT := "Burp!"
const TEXT_COLOR := &"white"
const TEXT_RISE_PX := 64.0
## Presentation: the wait's sway, the tell's quiver, the haul's recoil, a munch's squash, the
## swallow's stretch and squash, the sleep's breath, a bounce's hop.
const SWAY_RAD := 0.04
const SWAY_MS := 520.0
const QUIVER_PX := 1.5
const QUIVER_MS := 35.0
const HAUL_SQUASH := Vector2(1.14, 0.86)
const MUNCH_SQUASH := 0.12
const SWALLOW_STRETCH := Vector2(0.9, 1.14)
const SWALLOW_SQUASH := Vector2(1.12, 0.9)
const CHEW_SQUASH := 0.06
const CHEW_MS := 110.0
const BREATH_SWELL := 0.05
const BREATH_MS := 900.0
const BOUNCE_HOP_PX := 14.0
const HIDDEN_ALPHA := 0.0

## How far her snap takes things (world px, from her pot to their feet): this plant's reach, set on
## her placed enemy (game/enemy/placed_enemy.gd "Reach") or a pen's `enemy_properties`; 0 keeps her
## type's `biteRangePx`.
@export_range(0.0, 512.0, 1.0, "or_greater") var reach_px: float = 0.0

## The way she strikes and faces: Vector2.RIGHT, LEFT, DOWN or UP.
var _strike_way: Vector2 = Vector2.RIGHT
var _ready_at: float = 0.0
var _doze_until: float = 0.0
var _snore_at: float = 0.0
var _chew_at: float = 0.0
## What the snap took: "slime", "enemy" or "" (a miss).
var _caught: String = ""
var _held: Node = null
var _held_body: PhysicsBody2D = null
## The eating's steps already cued (the munches, the swallow, the burp).
var _eat_cued: int = 0
## A thrown enemy lying where it bounced off her, to pick up `_meal_at` on.
var _meal: Node = null
var _meal_at: float = 0.0


func _ready() -> void:
	super()
	add_to_group(EATERS_GROUP)
	_wait(Services.now_ms())


func _exit_tree() -> void:
	_let_go()
	super()


# --- the pattern -----------------------------------------------------------------------------------

func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_WAIT, PHASE_RECOVER:
			set_look(0.0, Vector2.ONE, sin(now / SWAY_MS) * SWAY_RAD)
			var meal := _meal_victim(now)
			if not meal.is_empty():
				_open(now, meal)
			elif now >= _ready_at:
				var victim := _victim(target, engaged, tell_reach())
				if not victim.is_empty():
					_open(now, victim)
				elif _phase == PHASE_RECOVER:
					_wait(now)
		PHASE_OPEN:
			var victim := _meal_victim(now)
			if victim.is_empty():
				victim = _victim(target, engaged, bite_reach())
			if not victim.is_empty():
				_face(victim["feet"])
			_show(FRAME_OPEN, FRAME_OPEN_DOWN, FRAME_OPEN_UP)
			set_look(0.0)
			if pose != null:
				pose.position.x = sin(now / QUIVER_MS) * QUIVER_PX
			if elapsed >= pattern("tellMs", 350.0):
				_snap(now, victim, target)
		PHASE_SNAP:
			set_look(0.0)
			if elapsed >= pattern("snapMs", 200.0):
				match _caught:
					"slime":
						_chew(now)
					"enemy":
						_eat(now)
					_:
						_rest(now, pattern("missRecoverMs", 500.0))
		PHASE_EAT:
			_step_eat(now, elapsed)
		PHASE_CHEW:
			_step_chew(now, target)
		PHASE_SPIT:
			set_look(0.0)
			if elapsed >= pattern("spitMs", 320.0):
				_rest(now, pattern("recoverMs", 900.0))
		PHASE_DOZE:
			_sleep_look(now)
			if now >= _doze_until:
				_wait(now)
				_ready_at = now
		PHASE_DIGEST:
			_sleep_look(now)


## The eating, step by step from the snap's end: haul it back, munch, swallow, burp; then digest.
func _step_eat(now: float, elapsed: float) -> void:
	var haul := pattern("haulMs", 160.0)
	var munch := maxf(1.0, pattern("munchMs", 260.0))
	var munches := maxi(0, int(pattern("munches", 2.0)))
	var swallow := maxf(1.0, pattern("swallowMs", 520.0))
	var burp := pattern("burpMs", 520.0)
	var munch_end := haul + munch * float(munches)
	if elapsed < haul:
		set_frame(FRAME_CHEW)
		set_look(0.0, HAUL_SQUASH.lerp(Vector2.ONE, elapsed / maxf(1.0, haul)))
	elif elapsed < munch_end:
		var k := int((elapsed - haul) / munch)
		var t := fmod(elapsed - haul, munch) / munch
		set_frame(FRAME_CHEW)
		var squash := sin(t * PI) * MUNCH_SQUASH
		set_look(0.0, Vector2(1.0 + squash, 1.0 - squash))
		if _eat_cued <= k:
			_eat_cued = k + 1
			_cue(CUE_MUNCH)
	elif elapsed < munch_end + swallow:
		var t := (elapsed - munch_end) / swallow
		set_frame(FRAME_SWALLOW)
		var shape := Vector2.ONE.lerp(SWALLOW_STRETCH, sin(t * PI * 2.0)) if t < 0.5 else Vector2.ONE.lerp(SWALLOW_SQUASH, sin((t - 0.5) * PI * 2.0))
		set_look(0.0, shape)
		if _eat_cued <= munches:
			_eat_cued = munches + 1
			_cue(CUE_SWALLOW)
	elif elapsed < munch_end + swallow + burp:
		set_frame(FRAME_BURP)
		set_look(0.0, Vector2.ONE.lerp(Vector2(1.06, 0.96), sin((elapsed - munch_end - swallow) / maxf(1.0, burp) * PI)))
		if _eat_cued <= munches + 1:
			_eat_cued = munches + 2
			_cue(CUE_BURP)
			_say(BURP_TEXT)
	else:
		_digest(now)


func _step_chew(now: float, target: Dictionary) -> void:
	var player := _held
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")):
		_let_go()
		_rest(now, pattern("recoverMs", 900.0))
		return
	player.call(&"apply_status", STICKY, pattern("holdTickMs", 200.0))
	var squash := sin(now / CHEW_MS) * CHEW_SQUASH
	set_look(0.0, Vector2(1.0 + squash, 1.0 - squash))
	# A chew every `chewMs`, but none within `chewMs` of the spit, so the spit's bite lands too (the
	# slime's hit invulnerability, `character.player.hitInvulnerabilityMs`, would swallow it).
	if now >= _chew_at and _elapsed(now) <= pattern("holdMs", 1200.0) - pattern("chewMs", 550.0):
		_chew_at = now + pattern("chewMs", 550.0)
		_cue(CUE_MUNCH)
		_route_hit_from(feet(), target, pattern("chewDamage", 33.0), 0.0)
	if _elapsed(now) >= pattern("holdMs", 1200.0):
		_spit(now, target)


# --- who she bites ---------------------------------------------------------------------------------

## The nearest thing within `reach` of her pot she can bite: {"kind": "slime" | "enemy", "node",
## "feet"}, {} for none. The slime only while it is a live target (engaged) and not rolling; enemies
## on the ground (`_edible`).
func _victim(target: Dictionary, engaged: bool, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	var at := feet()
	if engaged and _can_catch_slime(target):
		var slime_body := target.get("body") as Node2D
		if slime_body != null:
			var d := slime_body.global_position.distance_to(at)
			if d <= best_d:
				best_d = d
				best = {"kind": "slime", "node": target.get("player"), "feet": slime_body.global_position}
	for node: Node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		if not _edible(node):
			continue
		var enemy_body := node.call(&"get_body") as Node2D
		if enemy_body == null:
			continue
		var d := enemy_body.global_position.distance_to(at)
		if d <= best_d:
			best_d = d
			best = {"kind": "enemy", "node": node, "feet": enemy_body.global_position}
	return best


## The thrown enemy lying where it bounced off her, once `feedPickMs` is up and while it is still
## there to pick up (within `biteRangePx`); {} for none.
func _meal_victim(now: float) -> Dictionary:
	if _meal == null:
		return {}
	if not is_instance_valid(_meal) or not _edible(_meal):
		_meal = null
		return {}
	var meal_body := _meal.call(&"get_body") as Node2D
	if meal_body == null or meal_body.global_position.distance_to(feet()) > bite_reach():
		_meal = null
		return {}
	if now < _meal_at:
		return {}
	return {"kind": "enemy", "node": _meal, "feet": meal_body.global_position}


func _can_catch_slime(target: Dictionary) -> bool:
	var player: Node = target.get("player")
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")):
		return false
	return not bool(player.call(&"is_rolling"))


## An enemy she can eat: alive and in play, on the ground, not a boss, not another plant.
func _edible(node: Node) -> bool:
	if node == self or not is_instance_valid(node) or node is CarnivorePlantScript:
		return false
	if not node.has_method(&"get_body") or not node.has_method(&"is_defeated") or bool(node.call(&"is_defeated")):
		return false
	if node.has_method(&"is_carried") and bool(node.call(&"is_carried")):
		return false
	if node.has_method(&"is_hurtbox_on") and not bool(node.call(&"is_hurtbox_on")):
		return false
	var profile := ReactionProfileScript.for_enemy(node)
	return str(profile.get("weight", "")) != "boss" and not bool(profile.get("flies", false))


## How far her snap takes things: `reach_px`, else her type's `biteRangePx`.
func bite_reach() -> float:
	return reach_px if reach_px > 0.0 else pattern("biteRangePx", 72.0)


## How close something comes before she opens: her bite reach x `tellRangePx` / `biteRangePx`.
func tell_reach() -> float:
	var bite := pattern("biteRangePx", 72.0)
	return bite_reach() * (pattern("tellRangePx", 60.0) / bite if bite > 0.0 else 1.0)


## How close a thrown enemy lands to be food: her bite reach and as much more as `feedReachPx` is
## beyond `biteRangePx`.
func feed_reach() -> float:
	return bite_reach() + maxf(0.0, pattern("feedReachPx", 90.0) - pattern("biteRangePx", 72.0))


## The slime is hers to bite while it is a live target inside her arena (a pen), or anywhere without
## one: her reach, not `targeting_radius`, decides how near it must come.
func _is_engaged(target: Dictionary) -> bool:
	if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return false
	if not _arena.is_empty():
		return BossArena.contains(_arena, target.get("centre", get_centre()))
	return true


# --- phases ----------------------------------------------------------------------------------------

func _wait(now: float) -> void:
	_transition(PHASE_WAIT, now)
	_caught = ""
	_show(FRAME_WAIT, FRAME_WAIT, FRAME_WAIT)
	set_look(0.0)


func _open(now: float, victim: Dictionary) -> void:
	_transition(PHASE_OPEN, now)
	_face(victim["feet"])
	_show(FRAME_OPEN, FRAME_OPEN_DOWN, FRAME_OPEN_UP)
	_cue(CUE_OPEN)


## The jaws shut on the nearest thing in reach (`victim`, {} for a miss), where her head reaches.
func _snap(now: float, victim: Dictionary, target: Dictionary) -> void:
	if pose != null:
		pose.position.x = 0.0
	if not victim.is_empty():
		_face(victim["feet"])
	_transition(PHASE_SNAP, now)
	_show(FRAME_SNAP, FRAME_SNAP_DOWN, FRAME_SNAP_UP)
	_caught = str(victim.get("kind", ""))
	_cue(CUE_SNAP)
	match _caught:
		"slime":
			_grab(target)
		"enemy":
			_take(victim["node"] as Node)
			if victim["node"] == _meal:
				_meal = null
		_:
			_puff(DUST, _jaw(true) + Vector2(0.0, VICTIM_RISE_PX))


## The slime is dragged into her jaws (its own recoil toward them): it passes through her body while
## she holds it.
func _grab(target: Dictionary) -> void:
	_held = target.get("player")
	_held_body = target.get("body") as PhysicsBody2D
	if _held_body != null and body != null:
		body.add_collision_exception_with(_held_body)
	if _held != null and _held_body != null and _held.has_method(&"recoil"):
		var into := _jaw(true) + Vector2(0.0, VICTIM_RISE_PX) - _held_body.global_position
		var pull_ms := maxf(1.0, pattern("pullMs", 160.0))
		if into.length() > 1.0:
			_held.call(&"recoil", into.normalized(), into.length() / (pull_ms / 1000.0), pull_ms)


## `enemy` dies where it stands, quietly (no death puff: she has it), and its body slides into her
## jaws as they close (the base enemy's FATE_EATEN, over the snap).
func _take(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy) or bool(enemy.call(&"is_defeated")):
		return
	var state: Variant = enemy.call(&"get_damage_state")
	var hp := float((state as Dictionary).get("hp", 0.0)) if state is Dictionary else 0.0
	if enemy.has_method(&"cancel_attack"):
		enemy.call(&"cancel_attack")
	EnemyReactions.state_of(enemy).sendoff = true
	if enemy.has_method(&"take_reaction_damage"):
		enemy.call(&"take_reaction_damage", maxf(1.0, hp))
	if bool(enemy.call(&"is_defeated")) and enemy.has_method(&"begin_fate"):
		enemy.call(&"begin_fate", FATE_EATEN, _jaw(true) + Vector2(0.0, VICTIM_RISE_PX), pattern("snapMs", 200.0), true)
	else:
		EnemyReactions.state_of(enemy).sendoff = false


## She has an enemy in her jaws: haul, munch, swallow, burp (`_step_eat`), then digest.
func _eat(now: float) -> void:
	_transition(PHASE_EAT, now)
	_eat_cued = 0
	face_x(_strike_way.x if _strike_way.x != 0.0 else 1.0)
	set_frame(FRAME_CHEW)


func _chew(now: float) -> void:
	_transition(PHASE_CHEW, now)
	set_frame(FRAME_CHEW)
	_chew_at = now + pattern("chewMs", 550.0)
	if _held != null and is_instance_valid(_held):
		_held.call(&"apply_status", STICKY, pattern("holdTickMs", 200.0))
		if _held.has_method(&"set_effect_alpha"):
			_held.call(&"set_effect_alpha", HIDDEN_ALPHA)


## She spits the slime back out the way she struck, far: a bite, then the slime's own recoil
## (`spitPx` in `spitFlyMs`).
func _spit(now: float, target: Dictionary) -> void:
	var player := _held
	_let_go()
	_transition(PHASE_SPIT, now)
	_show(FRAME_SPIT, FRAME_SPIT_DOWN, FRAME_SPIT_UP)
	_cue(CUE_SPIT)
	_route_hit_from(feet(), target, pattern("spitDamage", 21.0), pattern("spitKnockback", 200.0), _strike_way)
	var fly_ms := maxf(1.0, pattern("spitFlyMs", 380.0))
	if player != null and is_instance_valid(player) and player.has_method(&"recoil"):
		player.call(&"recoil", _strike_way, pattern("spitPx", 220.0) / (fly_ms / 1000.0), fly_ms)
	_puff(DUST, _jaw(false) + Vector2(0.0, VICTIM_RISE_PX))


func _rest(now: float, ms: float) -> void:
	_transition(PHASE_RECOVER, now)
	_show(FRAME_WAIT, FRAME_WAIT, FRAME_WAIT)
	_ready_at = now + ms


## A thrown thing: asleep for `dozeMs` (again from now while she dozes).
func _doze(now: float) -> void:
	if _phase == PHASE_DIGEST or _phase == PHASE_EAT:
		return
	_let_go()
	_meal = null
	if pose != null:
		pose.position.x = 0.0
	_doze_until = now + pattern("dozeMs", 5000.0)
	if _phase != PHASE_DOZE:
		_transition(PHASE_DOZE, now)
		set_frame(FRAME_DOZE)
		face_x(_strike_way.x if _strike_way.x != 0.0 else 1.0)
		_cue(CUE_DOZE)
		_snore_at = now + pattern("snoreEveryMs", 900.0) * 0.5


## She ate an enemy: asleep for good, digesting (until the world is built again).
func _digest(now: float) -> void:
	_transition(PHASE_DIGEST, now)
	set_frame(FRAME_DIGEST)
	_snore_at = now + pattern("snoreEveryMs", 900.0)


## A thrown enemy (enemies as ammo) lands at `spot`: awake and within `feedReachPx` of her pot, she
## takes it as food, but not out of the air: it bounces off her and lies dazed on the floor (no
## landing hit), and she picks it up `feedPickMs` later. True when she took it (game/throw/
## gulpable_enemy.gd then skips its landing hit).
func catch_thrown(enemy: Node, spot: Vector2) -> bool:
	if is_defeated() or _phase in [PHASE_DOZE, PHASE_DIGEST, PHASE_CHEW, PHASE_EAT, PHASE_SNAP]:
		return false
	if spot.distance_to(feet()) > feed_reach() or not _edible(enemy) or _meal != null:
		return false
	var now := Services.now_ms()
	var away := spot - feet()
	away = away.normalized() if away.length() > 0.5 else Vector2(-_strike_way.x if _strike_way.x != 0.0 else 1.0, 0.0)
	# It bounces off her, but no further than her bite reaches.
	var room := bite_reach() - 6.0 - spot.distance_to(feet())
	var bounce := clampf(minf(pattern("feedBouncePx", 24.0), room), 0.0, pattern("feedBouncePx", 24.0))
	var bounce_ms := pattern("feedBounceMs", 260.0)
	EnemyReactions.put_down(enemy, pattern("feedDazeMs", 2500.0))
	var enemy_body := enemy.call(&"get_body") as CharacterBody2D
	if enemy_body != null and bounce > 0.0:
		enemy_body.velocity = away * EnemyReactions.speed_for_distance(bounce, bounce_ms)
	var motion := EnemyReactions.motion_of(enemy)
	if motion != null:
		motion.play(EnemyHitMotion.BOUNCE, away, {"hop_px": BOUNCE_HOP_PX, "ms": bounce_ms})
	_meal = enemy
	_meal_at = now + pattern("feedPickMs", 450.0)
	_face(spot)
	return true


## Lets go of the slime: its status, its look and her body's collision with it back.
func _let_go() -> void:
	if _held != null and is_instance_valid(_held):
		var status: Variant = _held.call(&"get_status") if _held.has_method(&"get_status") else null
		if status is Object and (status as Object).has_method(&"remove"):
			(status as Object).call(&"remove", STICKY)
		if _held.has_method(&"set_effect_alpha"):
			_held.call(&"set_effect_alpha", 1.0)
	if _held_body != null and is_instance_valid(_held_body) and body != null and is_instance_valid(body):
		body.remove_collision_exception_with(_held_body)
	_held = null
	_held_body = null


# --- the look --------------------------------------------------------------------------------------

## She turns to `at`: up or down when it is more below or above her than to her side, else to the side.
func _face(at: Vector2) -> void:
	var offset := at - feet()
	if absf(offset.y) > absf(offset.x) * VERTICAL_SHARE and absf(offset.y) > 0.5:
		_strike_way = Vector2.DOWN if offset.y > 0.0 else Vector2.UP
	elif absf(offset.x) > 0.5:
		_strike_way = Vector2.RIGHT if offset.x > 0.0 else Vector2.LEFT


## The frame for the way she faces: `side` (mirrored for left), `down` or `up`.
func _show(side: int, down: int, up: int) -> void:
	if _strike_way == Vector2.DOWN:
		set_frame(down)
		face_x(1.0)
	elif _strike_way == Vector2.UP:
		set_frame(up)
		face_x(1.0)
	else:
		set_frame(side)
		face_x(_strike_way.x)


## Where her jaws are (world) in the snap pose (`snap`) or the spit pose, the way she faces.
func _jaw(snap: bool) -> Vector2:
	var at := JAW_SNAP_SIDE if snap else JAW_SPIT_SIDE
	if _strike_way == Vector2.DOWN:
		at = JAW_SNAP_DOWN if snap else JAW_SPIT_DOWN
	elif _strike_way == Vector2.UP:
		at = JAW_SNAP_UP if snap else JAW_SPIT_UP
	elif _strike_way == Vector2.LEFT:
		at.x = -at.x
	var size := visual.scale if visual != null else Vector2.ONE
	return feet() + at * size


## Asleep (dozing or digesting): a slow breath and a "z" now and then.
func _sleep_look(now: float) -> void:
	var breath := (sin(now / BREATH_MS * TAU) + 1.0) * 0.5 * BREATH_SWELL
	set_look(0.0, Vector2(1.0 + breath * 0.5, 1.0 + breath))
	if now >= _snore_at:
		_snore_at = now + pattern("snoreEveryMs", 900.0)
		_say(SNORE_TEXT)


func _say(text: String) -> void:
	var feel := Services.feel()
	if feel != null and Hearing.heard(feet()):
		feel.floating_text(feet() + Vector2(0.0, -TEXT_RISE_PX), text, TEXT_COLOR, false)


# --- hits ------------------------------------------------------------------------------------------

## Only fire kills her, in any phase.
func _kill_hit(request: Dictionary) -> bool:
	return has_tag(request, FIRE_TAG)


## Every blow but a thrown thing clinks.
func _shields(request: Dictionary) -> bool:
	return not _thrown(request)


## A thrown thing hurts her not at all.
func mitigate_damage(input: Dictionary) -> float:
	var request: Dictionary = input.get("request", {})
	if _kill_hit(request):
		return super(input)
	return 0.0 if _thrown(request) else super(input)


## A thrown thing puts her to sleep (a thrown enemy is food: `catch_thrown`); fire burns her.
func commit_damage(commit: Dictionary) -> void:
	var request: Dictionary = commit.get("request", {})
	var burnt := _kill_hit(request)
	super(commit)
	if burnt:
		_cue(CUE_BURN)
		return
	if not is_defeated() and _thrown(request) and not has_tag(request, ENEMY_KIND_TAG):
		_doze(Services.now_ms())


## A thrown thing: the throw's hit class (thrown, thrown-medium, ...) or the `thrown` tag.
func _thrown(request: Dictionary) -> bool:
	var hit: Variant = request.get("hit")
	if hit is Dictionary and str((hit as Dictionary).get("class", "")).begins_with(THROWN_TAG):
		return true
	return has_tag(request, THROWN_TAG)


## Rooted in her pot: a blow never moves her.
func _slides_when_stunned() -> bool:
	return false


func _defeat() -> void:
	if is_defeated():
		return
	_let_go()
	_meal = null
	super()
	face_x(_strike_way.x if _strike_way.x != 0.0 else 1.0)
	if pose != null:
		pose.position.x = 0.0


## True while she holds the slime in her mouth.
func is_holding() -> bool:
	return _phase == PHASE_CHEW and _held != null


## True while she sleeps (dozing or digesting).
func is_asleep() -> bool:
	return _phase == PHASE_DOZE or _phase == PHASE_DIGEST
