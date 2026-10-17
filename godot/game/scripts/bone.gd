extends "res://game/scripts/projectile.gd"
class_name BoneProjectileScript
## Scene script `game.bone` (docs/godot/BESTIARY.md "Bone Thrower"): the Bone Thrower's spinning
## bone, an enemy projectile (game/scripts/projectile.gd) that flies like a boomerang.
##
## - **Out:** launched (game/enemy/enemy_projectiles.gd) along the throw at its speed, it slows down
##   to `turn_share` of it over `range_px` (`setup`, the thrower's `boneRangePx`, `boneTurnShare`).
## - **Back:** then it turns and flies back along the same line (one of the eight the thrower aims
##   along: game/enemy/four_way_aim.gd) to the point it was thrown from, speeding up again, and on to
##   the thrower's hand (its old centre) if the thrower was knocked off that spot; it is caught
##   within `catch_px` of the hand: the thrower is armed again (bone_thrower.gd `bone_back`).
## - It hurts the slime on both legs: each leg is an attack activation of its own (one hit each), and
##   it flies on after a hit.
## - A wall stops it (its last move was blocked) on either leg: it clatters to the ground and breaks,
##   and the thrower is unarmed (`bone_lost`). So does the end of its lifetime, or a thrower that is
##   gone or lies as a bone pile (`drop`).
## - **The Gulp catches it:** while it flies it is in the mouth's `suckable` group
##   (game/player/gulp/mouth.gd); sucked in, it leaves the world without a hit, the mouth holds
##   {"kind": KIND, "texture", "art_px", "material"} (held_look.gd) and the thrower is unarmed for
##   longer (`bone_lost(true)`: its `stolenRegrowMs`). Thrown back (thrown_object.gd), its hit carries the tags `thrown` and KIND.
##
## Owner: enemy builder.

const SUCKABLE_GROUP := &"suckable"
## The held kind and the tag its throw carries.
const KIND := "bone"
const MATERIAL := "bone"
const BONE_TEXTURE := "res://asset/MAPS/enemies/64x64-bone.webp"
## The bone's drawn size in its 64 px picture.
const BONE_ART_PX := 60.0
## Presentation: it spins as it flies; the clatter's dust and sound.
const SPIN_PER_S := 15.0
const DUST := &"dodge-dust"
const CUE_CLATTER := &"BreakWood"
const BreakBurst := preload("res://game/player/gulp/break_burst.gd")

## The Bone Thrower (bone_thrower.gd: `hand_point`, `bone_back`, `bone_lost`), or null.
var _thrower: Node = null
var _range_px: float = 200.0
var _turn_share: float = 0.3
var _catch_px: float = 16.0
var _speed: float = 0.0
var _direction: Vector2 = Vector2.RIGHT
var _start: Vector2 = Vector2.ZERO
var _returning: bool = false
var _return_from: Vector2 = Vector2.ZERO
## On its way back it has reached the point it was thrown from.
var _on_line_end: bool = false


func _enter_tree() -> void:
	add_to_group(SUCKABLE_GROUP)


## Right after the launch: who threw it, how far it flies out, how slow it turns, how close to the
## hand it is caught.
func setup(thrower: Node, range_px: float, turn_share: float, catch_px: float) -> void:
	_thrower = thrower
	_range_px = maxf(1.0, range_px)
	_turn_share = clampf(turn_share, 0.05, 1.0)
	_catch_px = maxf(1.0, catch_px)
	if body != null:
		_speed = body.velocity.length()
		_direction = body.velocity.normalized() if _speed > 0.0 else Vector2.RIGHT
		_start = body.global_position


## True on its way back to the hand.
func is_returning() -> bool:
	return _returning


func _physics_process(delta: float) -> void:
	if not _launched or body == null:
		return
	_age_ms = Services.now_ms() - _launched_at
	if visual != null:
		visual.rotation += SPIN_PER_S * delta * (1.0 if _direction.x >= 0.0 else -1.0)
	if _blocked or _age_ms >= lifetime_ms:
		_clatter()
		return
	if not _returning:
		var t := clampf(_start.distance_to(body.global_position) / _range_px, 0.0, 1.0)
		if t >= 1.0:
			_turn()
		else:
			body.velocity = _direction * _speed * lerpf(1.0, _turn_share, t)
	if _returning:
		var hand := _hand()
		if hand == Vector2.INF:
			_clatter()
			return
		if hand.distance_to(body.global_position) <= _catch_px:
			_caught_back()
			return
		# Back along its own line to where it was thrown, then (a thrower knocked off its spot) to the
		# hand.
		if not _on_line_end and _start.distance_to(body.global_position) <= _catch_px:
			_on_line_end = true
		var goal := hand if _on_line_end else _start
		var span := maxf(1.0, _return_from.distance_to(_start))
		var t := clampf(_return_from.distance_to(body.global_position) / span, 0.0, 1.0)
		body.velocity = (goal - body.global_position).normalized() * _speed * lerpf(_turn_share, 1.0, t)
	_blocked = ArcadeMover.move(body, delta)


## The far end: back to the hand, a new activation (it may hit again on the way back).
func _turn() -> void:
	_returning = true
	_return_from = body.global_position
	_end_activation()
	var router := Services.router()
	if router != null and attack_area != null and not _damage.is_empty():
		var areas: Array[Area2D] = [attack_area]
		_activation_id = router.begin_activation(self, areas)


## The thrower's hand (its old centre); INF when it is gone or lies as a pile.
func _hand() -> Vector2:
	if _thrower == null or not is_instance_valid(_thrower) or _thrower.is_queued_for_deletion():
		return Vector2.INF
	if not _thrower.has_method(&"hand_point"):
		return Vector2.INF
	return _thrower.call(&"hand_point")


## Back in the hand: it leaves the world quietly.
func _caught_back() -> void:
	_launched = false
	_end_activation()
	if _thrower != null and is_instance_valid(_thrower) and _thrower.has_method(&"bone_back"):
		_thrower.call(&"bone_back")
	_free_root()


## Stopped (a wall, its lifetime, no thrower to go back to): it breaks where it is.
func _clatter() -> void:
	if not _launched:
		return
	var at := body.global_position if body != null else Vector2.ZERO
	var world := Services.world()
	if world != null and visual is Sprite2D:
		BreakBurst.burst(world.entities_root(), at, visual as Sprite2D)
	var feel := Services.feel()
	if feel != null:
		feel.particles(DUST, at)
		feel.audio_cue(CUE_CLATTER)
	_tell_lost()
	expire()


## Its thrower fell into a bone pile: it drops and breaks, and no one is told.
func drop() -> void:
	_thrower = null
	_clatter()


## Its thrower is gone: the bone flies on and, with no hand to go back to, drops at its turn.
func detach() -> void:
	_thrower = null


func _tell_lost(stolen: bool = false) -> void:
	var thrower := _thrower
	_thrower = null
	if thrower != null and is_instance_valid(thrower) and thrower.has_method(&"bone_lost"):
		thrower.call(&"bone_lost", stolen)


## The base's hit (one request per activation) without expiring: a boomerang flies on.
func on_area_entered(area: Area2D) -> void:
	var router := Services.router()
	if not _launched or _damage.is_empty() or _activation_id <= 0 or router == null or attack_area == null:
		return
	if area == null:
		return
	var targets: Variant = _damage.get("target_areas")
	if targets is Array and not (targets as Array).has(area):
		return
	var flight := body.velocity if body != null else Vector2.ZERO
	var knock := flight.normalized() if flight.length() > 0.0 else Vector2.ZERO
	var effects: Array = []
	var knockback_strength := float(_damage.get("knockback_strength", 0.0))
	if knockback_strength > 0.0:
		effects.append({"effect_id": KNOCKBACK_EFFECT_ID, "potency": knockback_strength})
	var weapon_id := str(_damage.get("weapon_id", ""))
	router.route({
		"activation_id": _activation_id,
		"source": self,
		"attack_area": attack_area,
		"target_area": area,
		"weapon_id": weapon_id if not weapon_id.is_empty() else projectile_id,
		"weapon_tags": _damage.get("weapon_tags", DEFAULT_WEAPON_TAGS.duplicate()),
		"damage_types": _damage.get("damage_types", DEFAULT_DAMAGE_TYPES.duplicate()),
		"base_damage": float(_damage.get("damage", 0.0)),
		"effects": effects,
		"impact": {"position": Vector2.ZERO, "knock": knock},
	})


func _free_root() -> void:
	var root := get_parent()
	if root is CollisionObject2D:
		(root as CollisionObject2D).set_deferred(&"collision_layer", 0)
	if root != null:
		root.queue_free()
	else:
		queue_free()


# --- the mouth's suckable contract (game/player/gulp/mouth.gd) -----------------------------------

func origin() -> Vector2:
	var root := get_parent() as Node2D
	return root.global_position if root != null else Vector2.ZERO


func can_take() -> bool:
	var root := get_parent()
	return is_launched() and root != null and not root.is_queued_for_deletion()


func suck_info() -> Dictionary:
	return {"kind": KIND, "essence": "", "variant": 0, "texture": BONE_TEXTURE, "art_px": BONE_ART_PX,
		"material": MATERIAL}


## Sucked in: it leaves the world without hitting anything, and its thrower is unarmed.
func take() -> void:
	if not is_launched():
		return
	_launched = false
	_end_activation()
	_tell_lost(true)
	_free_root()
