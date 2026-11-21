extends Node2D
## The Bow's arrow (owner, 2026-11-20; BODY_SHAPES.md "The Bow"; numbers `abilities.bow.arrow`): a
## pinch of the slime's goo shaped as an arrow, loosed by bow_sequence.gd. It flies straight along
## the aim at `speed` (760 px/s) for up to `rangePx` (512) and never turns. It stays on the level the
## slime shot from (AbilityWorld.body_level), so nothing crosses walls or cliff faces. Each sub-step
## (no longer than its radius `radiusPx`, so it never skips a thin target) it acts on the first of:
##
## 1. a **Bow target** (group `bow_targets`: crystal lenses, bells, the eyes, the crawler, the flyers,
##    the mole) whose shapes its line passes within `radiusPx` of (its own body or post, and its
##    `damage_area`, at the ground and at the arrow's height), on its level or lower. These are tested
##    first, before the walls, so a lens's post (a static body) never stops the arrow short of its
##    lens. `on_arrow_hit(hit)` answering true spends the arrow there (a lens struck, a bell rung, an
##    eye shattered, a flyer knocked down). Answering false the target is passed over for good; a
##    solid one (its body on the `world` layer) still stops the arrow, against its hurtbox if it has
##    one (step 2) or with a splat;
## 2. an **enemy hurtbox** on its level (not the player's, not a "resource"): one rework hit of its
##    own class `class` ("arrow", combat.hits; never the `thrown` tag, so a bell rings only through
##    `on_arrow_hit` and the throw combat's material effects never apply), `damage` (10) and a short
##    hold (`holdMs`), tags `arrow`, `bow`, weapon id `bow`, through AbilityWorld.strike_targets
##    (as the Lantern's flame), with its number and `feel`; a refused hit (the bars of a barred gate,
##    a shielded back) clinks;
## 3. a **wall**: a static world body (AbilityWorld.line_reach: tiles, the world bounds and bodies
##    under 20 px never block; fences, on their level layers, never do: an arrow flies over a fence),
##    or **higher ground**: a cliff's wall going up from its level, or a top higher than its level
##    (Elevation.top_level_at; the far wall of a ditch or a hole below it does not stop it): it
##    splats there;
## 4. nothing by the end of its range: it drops and splats on the ground.
##
## The node sits on the ground point under the arrow (walls and the elevation are tested there); the
## arrow's picture rides LIFT_PX above it (the slime's centre height) with a small shadow under it.
## Gameplay runs on the physics step (`delta`), so it pauses with the tree.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const Definitions := preload("res://game/player/abilities/ability_definitions.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const HitJuice := preload("res://game/feel/hit_juice.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")

const ARROW_TEXTURE := preload("res://asset/abilities/bow/arrow.webp")
## The group every far target joins (crystal_lens.gd, lash_bell.gd, the bestiary's targets).
const TARGET_GROUP := &"bow_targets"
## The arrow's picture: its length on screen (px) and its height over the ground point (the slime's
## centre, FeetAnchor's 27.56).
const ARROW_LENGTH_PX := 64.0
## The picture's thickness across its flight over its own proportion (owner, 2026-11-20: wider, it
## read too thin at game zoom).
const ARROW_THICKNESS := 2.6
const LIFT_PX := 27.56
## Its shadow on the ground: an ellipse this big, this dark.
const SHADOW_SIZE := Vector2(30.0, 11.0)
const SHADOW_COLOR := Color(0.03, 0.06, 0.02, 0.3)
## The hit's tags and weapon id (BODY_SHAPES.md "The hit").
const TAGS: Array[String] = ["arrow", "bow"]
const WEAPON_ID := "bow"
## The `world` physics layer (bit 1): a target whose body is on it is solid.
const WORLD_MASK := 1
## A target's shapes are sampled along a sub-step every this many px; one farther than NEAR_PX from
## the sub-step is not looked at.
const SAMPLE_PX := 4.0
const NEAR_PX := 200.0
## The strike's centre sits this far back along the aim from the hurtbox it meets.
const STRIKE_BACK_PX := 8.0
const CUE_SPLAT := &"ArrowSplat"
const CUE_CLINK := &"HitBlocked"
const PLACEHOLDER_CUES := {
	CUE_SPLAT: &"BubblePop",
}

var _player: Node
var _direction: Vector2 = Vector2.RIGHT
var _range_px: float = 512.0
var _speed: float = 760.0
var _radius: float = 7.0
var _travelled: float = 0.0
## The level it flies on (AbilityWorld.ANY_LEVEL without elevation).
var _level: int = AbilityWorld.ANY_LEVEL
var _done: bool = false
## Bow targets that refused it: passed over for the rest of the flight.
var _skipped: Array[Node] = []
## What `line_reach` passes through this step: the slime and every Bow target's own body.
var _exclude: Array[RID] = []
var _sprite: Sprite2D
var _shadow: Sprite2D


static func number(key: String, fallback: float) -> float:
	var constants := Services.constants()
	var raw: Variant = constants.value(Definitions.BOW_CONSTANTS + ".arrow." + key) if constants != null else null
	return float(raw) if (raw is float or raw is int) else fallback


static func value(key: String, fallback: Variant) -> Variant:
	var constants := Services.constants()
	return constants.value(Definitions.BOW_CONSTANTS + ".arrow." + key, fallback) if constants != null else fallback


## Looses the arrow from the slime's feet `feet` along `direction`; it appears `start_px` ahead (at the
## bow), the way there checked as any other step but not counted against its range.
func launch(player: Node, feet: Vector2, direction: Vector2, start_px: float = 0.0) -> void:
	_player = player
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	_range_px = number("rangePx", _range_px)
	_speed = number("speed", _speed)
	_radius = maxf(1.0, number("radiusPx", _radius))
	var body := player.get(&"body") as Node2D if player != null else null
	_level = AbilityWorld.body_level(body)
	global_position = feet
	_shadow = Sprite2D.new()
	_shadow.texture = FireFx.glow_texture()
	_shadow.modulate = SHADOW_COLOR
	# The glow fades out toward its edge: drawn a little bigger than SHADOW_SIZE.
	_shadow.scale = SHADOW_SIZE / 128.0 * 1.6
	_shadow.z_index = -1
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.texture = ARROW_TEXTURE
	var width := float(ARROW_TEXTURE.get_width()) if ARROW_TEXTURE != null else 1.0
	var along := ARROW_LENGTH_PX / maxf(1.0, width)
	_sprite.scale = Vector2(along, along * ARROW_THICKNESS)
	_sprite.position = Vector2(0.0, -LIFT_PX)
	_sprite.rotation = _direction.angle()
	add_child(_sprite)
	if start_px > 0.0:
		_exclude = _exclusions()
		_fly(start_px, false)


## The arrow is still in flight.
func is_flying() -> bool:
	return not _done


func _physics_process(delta: float) -> void:
	if _done:
		return
	_exclude = _exclusions()
	var step := minf(_speed * delta, _range_px - _travelled)
	if step > 0.0 and _fly(step, true):
		return
	if _travelled >= _range_px - 0.01:
		_drop()


## Moves the arrow `distance` along its aim in sub-steps no longer than its radius; true when it ended.
func _fly(distance: float, counts: bool) -> bool:
	var count := maxi(1, ceili(distance / maxf(4.0, _radius)))
	var part := distance / count
	for i in count:
		if _step(global_position, global_position + _direction * part):
			return true
		if counts:
			_travelled += part
	return false


## One sub-step from `from` to `to` (ground points): the Bow targets on the open part of it, then the
## hurtboxes where it gets to, then the wall or the higher ground that stopped it. True when it ended.
func _step(from: Vector2, to: Vector2) -> bool:
	var reach := AbilityWorld.line_reach(from, to, _exclude)
	var blocked := reach.distance_to(to) > AbilityWorld.CLEAR_LINE_SLACK_PX
	if _rises_at(reach):
		reach = from
		blocked = true
	var start := from
	while true:
		var touched := _first_target(start, reach)
		if touched.is_empty():
			break
		var target: Node = touched["target"]
		var at: Vector2 = touched["at"]
		global_position = at
		if bool(target.call(&"on_arrow_hit", _hit_at(at))):
			_end_on_target(at)
			return true
		_skipped.append(target)
		if _is_solid(target):
			if not _strike_hurtboxes(at):
				_splat(at)
			return true
		start = at
	global_position = reach
	if _strike_hurtboxes(reach):
		return true
	if blocked:
		_splat(reach)
		return true
	return false


# --- the targets ---------------------------------------------------------------------------------

## The nearest Bow target the ground line `from`→`to` (or the same line at the arrow's height) passes
## within the arrow's radius of: {"target": Node, "at": the ground point where it touches}, or {}.
func _first_target(from: Vector2, to: Vector2) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}
	var best := {}
	var best_along := INF
	var length := from.distance_to(to)
	for node: Node in tree.get_nodes_in_group(TARGET_GROUP):
		if node in _skipped or not node.is_inside_tree() or node.is_queued_for_deletion() \
				or not node.has_method(&"on_arrow_hit"):
			continue
		var ground := _ground_point(node)
		if _segment_distance(ground, from, to) > NEAR_PX or not _level_open(ground):
			continue
		var along := _touch_along(_holders(node), from, length)
		if along >= 0.0 and along < best_along:
			best_along = along
			best = {"target": node, "at": from + _direction * along}
	return best


## How far along the line from `from` (`length` px along the aim) it first passes within the
## radius of one of `holders`' shapes, at the ground or at the arrow's height; -1 when it does not.
func _touch_along(holders: Array[CollisionObject2D], from: Vector2, length: float) -> float:
	if holders.is_empty():
		return -1.0
	var count := maxi(1, ceili(length / SAMPLE_PX))
	for i in count + 1:
		var along := length * float(i) / float(count)
		var ground := from + _direction * along
		var air := ground - Vector2(0.0, LIFT_PX)
		for holder in holders:
			if _distance_to_shapes(holder, ground) <= _radius or _distance_to_shapes(holder, air) <= _radius:
				return along
	return -1.0


## The physics objects that stand for a Bow target: the target itself when it is one (a lens), its
## `body` (an enemy's), its `damage_area` (a bell's, an enemy's hurtbox), else its parent's body (a
## script under its post).
static func _holders(node: Node) -> Array[CollisionObject2D]:
	var out: Array[CollisionObject2D] = []
	if node is CollisionObject2D:
		out.append(node as CollisionObject2D)
	for key: StringName in [&"body", &"damage_area"]:
		var held: Variant = node.get(key) if key in node else null
		if held is CollisionObject2D and is_instance_valid(held) and (held as Node).is_inside_tree() \
				and not out.has(held):
			out.append(held as CollisionObject2D)
	if out.is_empty() and node.get_parent() is CollisionObject2D:
		out.append(node.get_parent() as CollisionObject2D)
	return out


## Where a Bow target stands: its body's feet, else its own place, else its parent's.
static func _ground_point(node: Node) -> Vector2:
	var body: Variant = node.get(&"body") if &"body" in node else null
	if body is Node2D and is_instance_valid(body):
		return (body as Node2D).global_position
	if node is Node2D:
		return (node as Node2D).global_position
	var parent := node.get_parent() as Node2D
	return parent.global_position if parent != null else Vector2.INF


## A target whose own body (not its hurtbox) is on the `world` layer: it stops the arrow.
static func _is_solid(node: Node) -> bool:
	for holder in _holders(node):
		if not holder is Area2D and holder.collision_layer & WORLD_MASK != 0:
			return true
	return false


## The `hit` a Bow target gets (its `direction` and `knock` the aim, `position` where it struck).
func _hit_at(ground: Vector2) -> Dictionary:
	var hit := _hit()
	hit["direction"] = _direction
	hit["position"] = ground - Vector2(0.0, LIFT_PX)
	hit["arrow"] = true
	return hit


func _hit() -> Dictionary:
	return HitReaction.build_hit(str(value("class", "arrow")), {
		"step": 0,
		"last": false,
		"shape": "",
		"tags": TAGS.duplicate(),
		"hold_ms": number("holdMs", 220.0),
		"launch_speed": 0.0,
		"knock": _direction,
	})


# --- the hurtboxes -------------------------------------------------------------------------------

## The first enemy hurtbox on its level at the ground point `ground` (tested at the arrow's height)
## takes the arrow's hit. True when one did (the arrow is spent).
func _strike_hurtboxes(ground: Vector2) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var air := ground - Vector2(0.0, LIFT_PX)
	var hurtboxes := AbilityWorld.hurtboxes_at(_player, air, _radius, _level)
	if hurtboxes.is_empty():
		return false
	var first: Array[Area2D] = [hurtboxes[0]]
	_strike(air, first)
	_end()
	return true


func _strike(air: Vector2, targets: Array[Area2D]) -> void:
	var hit := _hit()
	var landed: Array[Dictionary] = []
	# A lambda captures a bool by value: the clinks are counted in an array.
	var clinks: Array[bool] = []
	AbilityWorld.strike_targets(_player, air - _direction * STRIKE_BACK_PX, targets, number("damage", 10.0), 0.0,
		TAGS.duplicate(), WEAPON_ID, hit, func(outcome: Dictionary) -> void:
			var result: Variant = outcome.get("result")
			if not (result is Dictionary):
				return
			if AbilityWorld.is_clink(result):
				clinks.append(true)
			elif str((result as Dictionary).get("status", "")) == "accepted":
				landed.append(outcome))
	var feel := Services.feel()
	if feel == null:
		return
	if landed.is_empty():
		AbilityFx.goo_dust(air)
		if not clinks.is_empty():
			feel.audio_cue(CUE_CLINK)
			feel.particles(&"hit-spark", air)
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
	var step: Variant = value("feel", {})
	var spec := HitJuice.swing_spec(step if step is Dictionary else {}, hit, reactions, damage, landed.size(), killed)
	spec["debris_preset"] = &""
	var at: Vector2 = landed[0].get("position", air)
	feel.play_hit(spec, at, _direction)


# --- the world -----------------------------------------------------------------------------------

## The slime's own body and every Bow target's bodies: the line passes through them (a target is
## met by `_first_target`, never as a wall).
func _exclusions() -> Array[RID]:
	var rids: Array[RID] = []
	if _player != null and is_instance_valid(_player):
		rids = _player.call(&"body_rids")
	var tree := get_tree()
	if tree == null:
		return rids
	for node: Node in tree.get_nodes_in_group(TARGET_GROUP):
		for holder in _holders(node):
			if not holder is Area2D:
				rids.append(holder.get_rid())
	return rids


## Higher ground at the ground point `point`: a top above its level, or a cliff's wall going up from
## it (Elevation.top_level_at).
func _rises_at(point: Vector2) -> bool:
	if _level == AbilityWorld.ANY_LEVEL:
		return false
	var world := Services.world()
	var elevation: Node = world.elevation if world != null else null
	if elevation == null or not elevation.has_method(&"top_level_at"):
		return false
	return int(elevation.call(&"top_level_at", point, _level)) > _level


## A target standing at `ground` is on its level or lower (a target up a cliff is out of its reach).
func _level_open(ground: Vector2) -> bool:
	if ground == Vector2.INF:
		return false
	if _level == AbilityWorld.ANY_LEVEL:
		return true
	var world := Services.world()
	var elevation: Node = world.elevation if world != null else null
	if elevation == null:
		return true
	return int(elevation.call(&"level_at", ground, _level)) <= _level


## Distance from `point` to the nearest enabled shape of `holder` (0 inside; INF when it has none):
## rectangles and circles exactly, capsules as their round-ended box, anything else by its rect.
static func _distance_to_shapes(holder: CollisionObject2D, point: Vector2) -> float:
	var best := INF
	for child: Node in holder.get_children():
		var node := child as CollisionShape2D
		if node == null or node.disabled or node.shape == null:
			continue
		var local := node.global_transform.affine_inverse() * point
		var stretch := node.global_transform.get_scale().abs()
		var shape := node.shape
		if shape is CircleShape2D:
			best = minf(best, maxf(0.0, local.length() - (shape as CircleShape2D).radius) * stretch.x)
		elif shape is CapsuleShape2D:
			var capsule := shape as CapsuleShape2D
			var half_line := maxf(0.0, capsule.height / 2.0 - capsule.radius)
			var nearest := Vector2(0.0, clampf(local.y, -half_line, half_line))
			best = minf(best, maxf(0.0, local.distance_to(nearest) - capsule.radius) * maxf(stretch.x, stretch.y))
		else:
			var rect := shape.get_rect()
			var outside := Vector2(maxf(rect.position.x - local.x, local.x - rect.end.x),
				maxf(rect.position.y - local.y, local.y - rect.end.y)).max(Vector2.ZERO)
			best = minf(best, (outside * stretch).length())
	return best


static func _segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	if point == Vector2.INF:
		return INF
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, from, to))


# --- the end -------------------------------------------------------------------------------------

## Spent on a Bow target (it plays its own answer): a little goo where it struck.
func _end_on_target(ground: Vector2) -> void:
	AbilityFx.goo_dust(ground - Vector2(0.0, LIFT_PX))
	_end()


## Against a wall or higher ground: it splats there.
func _splat(ground: Vector2) -> void:
	global_position = ground
	AbilityFx.goo_dust(ground - Vector2(0.0, LIFT_PX))
	_cue(CUE_SPLAT)
	_end()


## Out of range: it drops and splats on the ground.
func _drop() -> void:
	AbilityFx.goo_dust(global_position)
	_cue(CUE_SPLAT)
	_end()


func _end() -> void:
	_done = true
	queue_free()


func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	var root: Node = feel.global_audio()
	if root == null or root.find_child(String(cue), true, false) == null:
		cue = PLACEHOLDER_CUES.get(cue, cue)
	feel.audio_cue(cue)
