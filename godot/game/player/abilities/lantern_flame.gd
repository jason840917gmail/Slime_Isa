extends Node2D
## The Lantern's flame (bomb-lantern-and-secrets design section 2; BODY_SHAPES.md "The Lantern"): a
## quick puff of flame just ahead of the mouth (owner, 2026-10-14: about one tile, not a long shot):
## it bursts out along the aim at `abilities.lantern.flame.speed` (900 px/s) for up to `rangePx`
## (72), growing as it goes, burns there for `lingerMs` (150) as it shrinks and fades, and acts on the
## first of:
## - a **fire target** (group `fire_targets`, game/world/fire/fire_targets.gd) whose
##   `receive_fire(hit)` answers true: a candle lit, a deadthorn hedge set on fire, a bomb set off;
## - an **enemy hurtbox** (not the player's, not a resource): one rework hit of class `flame.class`
##   with `flame.damage` (about a third of a Spear jab) and a short hold (`holdMs`), through
##   AbilityWorld.strike_targets as the Slam strikes, with its damage number and `flame.feel`; a
##   target that refuses it (a clink) only gets the embers;
## - a **wall** (a static world body, not a tile, not a small prop): embers;
## - nothing, by the end of its linger: it fizzles into smoke.
## While it flies it is a light source (`light_circle`, `flame.lightRadiusPx`, flickering), so it
## lights a dark room as it goes.
##
## The node sits on the ground point under the flame (walls are tested there, against their feet);
## the look rides `LIFT_PX` above it, at the old centre's height, where hurtboxes and fire targets
## are tested. Gameplay runs on the physics step (`delta`), so it pauses with the tree; the flicker
## of the art and the light is presentation (real time).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const HitJuice := preload("res://game/feel/hit_juice.gd")
const FireTargets := preload("res://game/world/fire/fire_targets.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")

const FLAME_SHEET := preload("res://asset/abilities/lantern/flame-4x1.webp")
const FLAME_FRAMES := 4
const FLAME_FRAME_MS := 70.0
## The sheet is drawn at the art density (128 px per 64-unit cell).
const ART_SCALE := 0.5
## The flame flies at the old centre's height over its ground point (FeetAnchor's 27.56).
const LIFT_PX := 27.56
## The glow behind the flame: its size (px) and warm tint.
const GLOW_PX := 72.0
const GLOW_COLOR := Color(1.0, 0.55, 0.18, 0.75)
const Z := 6
## The puff grows from this share of its size and shrinks to this share as it dies.
const PUFF_START := 0.55
const PUFF_END := 0.4
## The hit's tags (BODY_SHAPES.md "The hit").
const TAGS: Array[String] = ["fire", "lantern"]
const WEAPON_ID := "lantern"
const CUE_HIT := &"HitDull"
const CUE_FIZZLE := &"AbilityDenied"
const EMBERS_ON_HIT := 10
const EMBERS_ON_WALL := 7

var _player: Node
var _direction: Vector2 = Vector2.RIGHT
var _range_px: float = 260.0
var _speed: float = 420.0
var _radius: float = 10.0
var _light_px: float = 90.0
var _travelled: float = 0.0
var _linger_ms: float = 150.0
var _linger_left: float = -1.0
var _done: bool = false
var _sprite: Sprite2D
var _glow: Sprite2D
var _seed: float = 0.0


## Starts the flame at the ground point `feet` (the mouth's ground point) along `direction`.
func launch(player: Node, feet: Vector2, direction: Vector2) -> void:
	_player = player
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	_range_px = FireTargets.lantern_number("flame.rangePx", _range_px)
	_speed = FireTargets.lantern_number("flame.speed", _speed)
	_radius = FireTargets.lantern_number("flame.radiusPx", _radius)
	_light_px = FireTargets.lantern_number("flame.lightRadiusPx", _light_px)
	_linger_ms = FireTargets.lantern_number("flame.lingerMs", _linger_ms)
	_seed = randf() * 100.0
	global_position = feet
	z_index = Z
	add_to_group(FireTargets.LIGHT_GROUP)
	_glow = Sprite2D.new()
	_glow.texture = FireFx.glow_texture()
	_glow.material = FireFx.additive()
	_glow.modulate = GLOW_COLOR
	_glow.scale = Vector2.ONE * (GLOW_PX / 128.0)
	_glow.position = Vector2(0.0, -LIFT_PX)
	add_child(_glow)
	_sprite = Sprite2D.new()
	_sprite.texture = FLAME_SHEET
	_sprite.hframes = FLAME_FRAMES
	_sprite.scale = Vector2.ONE * ART_SCALE
	_sprite.position = Vector2(0.0, -LIFT_PX)
	_sprite.rotation = _direction.angle()
	# The flame's head leads: the art's hot ball sits right of its middle.
	_sprite.offset = Vector2(-10.0, 0.0)
	add_child(_sprite)
	_look(0.0, false)
	# A flame born touching something (point blank) acts at once.
	_check(global_position)


## Light source (game/world/fire/fire_targets.gd): the flame's air point and its flickering light.
func light_circle() -> Vector3:
	if _done:
		return Vector3.ZERO
	var at := global_position - Vector2(0.0, LIFT_PX)
	return Vector3(at.x, at.y, FireTargets.flicker(_light_px, _seed))


func _process(_delta: float) -> void:
	if _sprite != null:
		_sprite.frame = int(float(Time.get_ticks_msec()) / FLAME_FRAME_MS) % FLAME_FRAMES
	if _glow != null:
		_glow.scale = Vector2.ONE * (FireTargets.flicker(GLOW_PX, _seed) / 128.0)


func _physics_process(delta: float) -> void:
	if _done:
		return
	if _linger_left >= 0.0:
		_linger_left -= delta * 1000.0
		_look(clampf(_linger_left / maxf(1.0, _linger_ms), 0.0, 1.0), true)
		if _check(global_position):
			return
		if _linger_left <= 0.0:
			_fizzle()
		return
	var left := _range_px - _travelled
	var step := minf(_speed * delta, left)
	# Sub-steps no longer than the flame's radius, so it never skips a thin target.
	var count := maxi(1, ceili(step / maxf(4.0, _radius)))
	for i in count:
		var next := global_position + _direction * (step / count)
		var exclude: Array[RID] = []
		if _player != null and is_instance_valid(_player):
			exclude = _player.call(&"body_rids")
		var reach := AbilityWorld.line_reach(global_position, next, exclude)
		global_position = reach
		_travelled += step / count
		if _check(reach):
			return
		if reach.distance_to(next) > 0.5:
			_land_on_wall()
			return
	_look(_travelled / maxf(1.0, _range_px), false)
	if _travelled >= _range_px - 0.01:
		_linger_left = _linger_ms


## Tests the fire targets, then the hurtboxes, at the ground point `ground`. True when it stopped.
func _check(ground: Vector2) -> bool:
	var air := ground - Vector2(0.0, LIFT_PX)
	var tree := get_tree()
	var skip: Array = []
	for _try in 4:
		var target := FireTargets.first_touched(tree, air, _radius, skip)
		if target == null:
			target = FireTargets.first_touched(tree, ground, _radius, skip)
		if target == null:
			break
		if bool(target.call(&"receive_fire", _fire_hit(air))):
			_burst(air, EMBERS_ON_HIT)
			_end()
			return true
		skip.append(target)
	if _player == null or not is_instance_valid(_player):
		return false
	var hurtboxes := AbilityWorld.hurtboxes_at(_player, air, _radius)
	if hurtboxes.is_empty():
		return false
	var first: Array[Area2D] = [hurtboxes[0]]
	_strike(air, first)
	_end()
	return true


## The `hit` a fire target gets: the flame's rework hit plus where it is.
func _fire_hit(air: Vector2) -> Dictionary:
	var hit := _hit()
	hit["position"] = air
	hit["fire"] = true
	return hit


func _hit() -> Dictionary:
	return HitReaction.build_hit(str(_flame_value("class", "tap")), {
		"step": 0,
		"last": false,
		"shape": "",
		"tags": TAGS.duplicate(),
		"hold_ms": FireTargets.lantern_number("flame.holdMs", 250.0),
		"launch_speed": 0.0,
		"knock": _direction,
	})


func _strike(air: Vector2, targets: Array[Area2D]) -> void:
	var hit := _hit()
	var landed: Array[Dictionary] = []
	AbilityWorld.strike_targets(_player, air - _direction * 8.0, targets, FireTargets.lantern_number("flame.damage", 5.0),
		0.0, TAGS.duplicate(), WEAPON_ID, hit, func(outcome: Dictionary) -> void:
			var result: Variant = outcome.get("result")
			if not (result is Dictionary):
				return
			if not AbilityWorld.is_clink(result) and str((result as Dictionary).get("status", "")) == "accepted":
				landed.append(outcome))
	_burst(air, EMBERS_ON_HIT)
	var feel := Services.feel()
	if feel == null or landed.is_empty():
		return
	var reactions: Array[Dictionary] = []
	var damage := 0
	var killed := false
	for outcome: Dictionary in landed:
		var result: Dictionary = outcome["result"]
		var reaction: Variant = result.get("reaction")
		if reaction is Dictionary:
			reactions.append(reaction)
		damage = maxi(damage, int(result.get("actual_damage", 0)))
		killed = killed or bool(result.get("defeated", false))
	var step: Variant = _flame_value("feel", {})
	var spec := HitJuice.swing_spec(step if step is Dictionary else {}, hit, reactions, damage, landed.size(), killed)
	spec["debris_preset"] = &""
	var at: Vector2 = landed[0].get("position", air)
	feel.play_hit(spec, at, _direction)


## The puff's size: growing from PUFF_START to 1 while it flies (`t` the share of its range), then
## shrinking and fading while it lingers (`t` the share of the linger left).
func _look(t: float, lingering: bool) -> void:
	var size := lerpf(PUFF_START, 1.0, t) if not lingering else lerpf(PUFF_END, 1.0, t)
	if _sprite != null:
		_sprite.scale = Vector2.ONE * ART_SCALE * size
		_sprite.modulate.a = 1.0 if not lingering else clampf(t * 1.6, 0.0, 1.0)
	if _glow != null:
		_glow.modulate.a = GLOW_COLOR.a * (1.0 if not lingering else t)


func _land_on_wall() -> void:
	_burst(global_position - Vector2(0.0, LIFT_PX), EMBERS_ON_WALL)
	_end()


func _fizzle() -> void:
	FireFx.smoke(global_position - Vector2(0.0, LIFT_PX))
	_end()


func _burst(at: Vector2, count: int) -> void:
	FireFx.embers(at, count, -_direction)


func _end() -> void:
	_done = true
	remove_from_group(FireTargets.LIGHT_GROUP)
	queue_free()


func _flame_value(key: String, fallback: Variant) -> Variant:
	var constants := Services.constants()
	return constants.value("abilities.lantern.flame." + key, fallback) if constants != null else fallback
