extends RefCounted
## What a dungeon mechanism's moving part does to what it sweeps (docs/godot/DUNGEONS.md
## "Mechanisms"; the ram's log, game/dungeon/ram.gd, and the runaway cart,
## game/crystal_mine/ram_cart.gd). `sweep` looks at a rectangle of floor the part passed over this
## step, on the mechanism's own elevation level, and deals with each thing in it once per run
## (`struck` remembers who):
##
## - **A breakable** (group `ram_breakable`: the bricked arch, the rail gate) whose `ram_rect()`
##   (global; else its position) meets the rectangle gets `on_ram_hit(source)`.
## - **A node with the hook** `on_mechanism_hit(kind: StringName, source: Node)` (a boss or a
##   mini-boss: on the hurtbox's receiver or a node above the hurtbox) gets that call INSTEAD of
##   damage; it is returned as "stopped_by" (the cart stops against it; the ram swings on).
## - **The slime** takes `slimeDamage` (true damage) with a knockback of `slimeKnockback` along the
##   knock, through the damage router like any hit: its invulnerability after a hit and a Roll's
##   i-frames refuse it, and then it is passed over for the rest of the run. Ahead of the ram's
##   head `shove_slime` takes it first: across the lane, clear of it before the head arrives.
## - **An enemy** takes `damage` as a rework hit of class `hit.hitClass` (tags `mechanism`, the
##   kind), knocked along the knock through the enemies' own knock system: the knocked-back motion,
##   wall splats, bowling, ledges and hazards (docs/godot/THROW_COMBAT.md "Knocked enemies and the
##   ground"), with the feel of `hit` (hit-stop, trauma, kick, sparks, the big number). A
##   mechanism's blow is **true**: its damage is not scaled by the enemy's armour (no part, phase or
##   knockdown multiplier: the request's `true_damage`; a shut gate's 0 stays), it lands through a
##   phase's shield (the hit's `true_blow`: a sleeping statue, a charge; never a boss, never a phase
##   marked `noSleep`, never an enemy invulnerable by design such as the Prism Eye), and it moves a body that can be moved at least `hit.resistFloor` of the
##   way (the hit's `resist_floor` over the profile's `knockbackScale`; a `knockbackScale` of 0 stays
##   unmovable). game/combat/reactions/hit_reaction.gd and enemy_reactions.gd read these.
##
## The knock: `along` for the ram's enemies (down its lane); for the cart `aside` is on, and each
## thing is knocked across the line, to the side it stands on. The slime always goes aside.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

## What a mechanism breaks.
const GROUP_BREAKABLE := &"ram_breakable"
## The mechanisms a knock target lets go (they call its `rearm()` when they are ready again).
const GROUP_MECHANISMS := &"knock_mechanisms"
const HOOK_BREAK := &"on_ram_hit"
const HOOK_MECHANISM := &"on_mechanism_hit"
const HURTBOX_MASK := 8
const TAG := "mechanism"
const DAMAGE_TYPES: Array[String] = ["physical"]
const KNOCKBACK_EFFECT := "knockback"
## How far above a hurtbox a hooked node is looked for.
const HOOK_DEPTH := 4


## One step of a sweep. `rect` is global; `along` the unit way the part moves; `numbers` the
## mechanism's block of game-constants.json (`dungeon.ram`, `dungeon.ramCart`); `struck` the run's
## memory (instance id -> true), kept by the caller and cleared when a run starts.
## Returns {"hits": how many things it dealt with, "stopped_by": a hooked node or null, "stopped_area":
## the hurtbox it was met by (or null), "broke": how many breakables}. With `defer_hooks` a hooked
## node is only returned (and remembered in `struck`), not called: the caller calls `call_hook` when
## its part touches it.
static func sweep(source: Node2D, attack_area: Area2D, rect: Rect2, along: Vector2, kind: StringName,
		numbers: Dictionary, struck: Dictionary, aside: bool = false, defer_hooks: bool = false) -> Dictionary:
	var out := {"hits": 0, "stopped_by": null, "stopped_area": null, "broke": 0}
	if source == null or not source.is_inside_tree():
		return out
	var level := DungeonState.level_of_node(source)
	# The breakables.
	for node: Node in source.get_tree().get_nodes_in_group(GROUP_BREAKABLE):
		if struck.has(node.get_instance_id()) or not node.has_method(HOOK_BREAK) or not node is Node2D:
			continue
		if not rect.intersects(_rect_of(node as Node2D)) or not _same_level(node as Node2D, level):
			continue
		struck[node.get_instance_id()] = true
		node.call(HOOK_BREAK, source)
		out["broke"] = int(out["broke"]) + 1
		out["hits"] = int(out["hits"]) + 1
	# The bodies with a hurtbox.
	var router := Services.router()
	var world := Services.world()
	if router == null or world == null or not is_instance_valid(world.world_root):
		return out
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, rect.get_center())
	query.collision_mask = HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for found: Dictionary in world.world_root.get_world_2d().direct_space_state.intersect_shape(query, 32):
		var area := found.get("collider") as Area2D
		if area == null or area == attack_area:
			continue
		var receiver := router.receiver_for_area(area)
		if receiver == null or receiver == source or struck.has(receiver.get_instance_id()):
			continue
		if "resource" in router.tags_for_area(area):
			continue
		# a breakable's own hurtbox (it refuses weapons with a line) is not struck: its rectangle is
		# what the part must reach (above)
		if receiver is Node and (receiver as Node).is_in_group(GROUP_BREAKABLE):
			continue
		if AbilityWorld.target_level(area, receiver, level) != level:
			continue
		struck[receiver.get_instance_id()] = true
		out["hits"] = int(out["hits"]) + 1
		var hooked := hook_owner(receiver, area)
		if hooked != null:
			# the cart calls it itself at contact (`defer_hooks`); the ram at once
			if not defer_hooks:
				hooked.call(HOOK_MECHANISM, kind, source)
			if out["stopped_by"] == null:
				out["stopped_by"] = hooked
				out["stopped_area"] = area
			continue
		var knock := along
		if aside or receiver == world.player:
			# the slime always goes aside, off the line (never carried along under the moving part)
			knock = _aside(along, rect.get_center(), area.global_position)
		if receiver == world.player:
			_strike_slime(source, attack_area, area, knock, kind, numbers)
		else:
			_strike_enemy(source, attack_area, area, receiver, knock, kind, numbers)
	return out


## The ram's shove (one step of its swing): the slime on `lane` (global; the lane's full width, from
## its rest end to its far end) is knocked across the lane, to the side its feet stand on (down the
## screen, or right, when on the middle line), far enough to stand `slimeClearPx` past the lane's
## edge, at `slimeKnockSpeed` (units/s); it is shoved as soon as the head at `tip` (global, moving
## `speed` units/ms along `along`) would reach its near side in the time that takes, so it is out of
## the lane before the head arrives. Its `slimeBodyPx` counts as its half width. The damage is
## `slimeDamage`, true, through the damage router (its invulnerability and a Roll's i-frames refuse
## it, and then it is passed over for the rest of the swing). Returns true once the slime is dealt
## with (struck or refused).
static func shove_slime(source: Node2D, attack_area: Area2D, lane: Rect2, tip: Vector2, along: Vector2, speed: float,
		kind: StringName, numbers: Dictionary, struck: Dictionary) -> bool:
	var world := Services.world()
	var router := Services.router()
	if source == null or not source.is_inside_tree() or world == null or router == null:
		return false
	var player: Node = world.player
	var body: Node2D = world.player_body
	if player == null or body == null or not is_instance_valid(body) or struck.has(player.get_instance_id()):
		return false
	var feet := body.global_position
	var half_body := float(numbers.get("slimeBodyPx", 22.0))
	if not lane.grow(half_body).has_point(feet):
		return false
	var across := Vector2(-along.y, along.x)
	var middle := lane.get_center()
	var half := absf((lane.size * 0.5).dot(across.abs()))
	var offset := (feet - middle).dot(across)
	var side := 1.0 if offset >= 0.0 else -1.0
	var travel := half + half_body + float(numbers.get("slimeClearPx", 16.0)) - offset * side
	var knock_speed := maxf(1.0, float(numbers.get("slimeKnockSpeed", 1800.0)))
	var clear_ms := maxf(0.0, travel) / knock_speed * 1000.0
	var ahead := (feet - tip).dot(along) - half_body
	if ahead > speed * clear_ms:
		return false
	# its hurtbox, on the mechanism's level
	var area := _player_hurtbox(source, feet, half_body)
	if area == null:
		return false
	struck[player.get_instance_id()] = true
	var knock := across * side
	var activation := router.begin_activation(source, [attack_area])
	var result: Dictionary = router.route({
		"activation_id": activation,
		"source": source,
		"attack_area": attack_area,
		"target_area": area,
		"weapon_id": "%s-%s" % [TAG, kind],
		"weapon_tags": [TAG, String(kind)],
		"damage_types": DAMAGE_TYPES.duplicate(),
		"base_damage": float(numbers.get("slimeDamage", 0.0)),
		"true_damage": true,
		"effects": [],
		"impact": {"position": area.global_position, "knock": knock},
	})
	router.end_activation(activation)
	if str(result.get("status", "")) == "accepted" and travel > 0.0 and player.has_method(&"apply_knockback"):
		player.call(&"apply_knockback", knock, knock_speed, clear_ms)
	return true


## The slime's hurtbox when it is on `source`'s level around `feet`; null otherwise.
static func _player_hurtbox(source: Node2D, feet: Vector2, reach: float) -> Area2D:
	var world := Services.world()
	var router := Services.router()
	if world == null or router == null or not is_instance_valid(world.world_root):
		return null
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE * reach * 4.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, feet)
	query.collision_mask = HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var level := DungeonState.level_of_node(source)
	for found: Dictionary in world.world_root.get_world_2d().direct_space_state.intersect_shape(query, 32):
		var area := found.get("collider") as Area2D
		if area == null or router.receiver_for_area(area) != world.player:
			continue
		if AbilityWorld.target_level(area, world.player, level) == level:
			return area
	return null


## A deferred hook (`sweep`'s `defer_hooks`): `node.on_mechanism_hit(kind, source)` now.
static func call_hook(node: Node, kind: StringName, source: Node) -> void:
	if node != null and is_instance_valid(node) and node.has_method(HOOK_MECHANISM):
		node.call(HOOK_MECHANISM, kind, source)


## The global rectangle around `area`'s enabled collision shapes (each shape's own rectangle through
## its global transform); an empty one at its position when it has none.
static func area_rect(area: Area2D) -> Rect2:
	var out := Rect2(area.global_position, Vector2.ZERO)
	var first := true
	for child: Node in area.get_children():
		var holder := child as CollisionShape2D
		if holder == null or holder.disabled or holder.shape == null:
			continue
		var local := holder.shape.get_rect()
		for corner: Vector2 in [local.position, local.position + Vector2(local.size.x, 0.0),
				local.position + Vector2(0.0, local.size.y), local.end]:
			var point := holder.global_transform * corner
			if first:
				out = Rect2(point, Vector2.ZERO)
				first = false
			else:
				out = out.expand(point)
	return out


## The node that answers `on_mechanism_hit` for a hurtbox: its receiver, else a node above the
## hurtbox (up to HOOK_DEPTH); null when none does.
static func hook_owner(receiver: Object, area: Area2D) -> Node:
	if receiver is Node and (receiver as Node).has_method(HOOK_MECHANISM):
		return receiver as Node
	var at: Node = area.get_parent() if area != null else null
	for i in HOOK_DEPTH:
		if at == null:
			break
		if at.has_method(HOOK_MECHANISM):
			return at
		at = at.get_parent()
	return null


## Across `along`, to the side `point` lies on from `from` (down the screen's side when it is on
## the line).
static func _aside(along: Vector2, from: Vector2, point: Vector2) -> Vector2:
	var across := Vector2(-along.y, along.x)
	var side := (point - from).dot(across)
	return across if side >= 0.0 else -across


static func _rect_of(node: Node2D) -> Rect2:
	if node.has_method(&"ram_rect"):
		return node.call(&"ram_rect")
	return Rect2(node.global_position - Vector2(8.0, 8.0), Vector2(16.0, 16.0))


static func _same_level(node: Node2D, level: int) -> bool:
	var world := Services.world()
	if world == null or world.elevation == null or not is_instance_valid(world.elevation):
		return true
	return DungeonState.level_of_node(node) == level


static func _strike_slime(source: Node2D, attack_area: Area2D, area: Area2D, knock: Vector2, kind: StringName,
		numbers: Dictionary) -> void:
	var router := Services.router()
	var activation := router.begin_activation(source, [attack_area])
	router.route({
		"activation_id": activation,
		"source": source,
		"attack_area": attack_area,
		"target_area": area,
		"weapon_id": "%s-%s" % [TAG, kind],
		"weapon_tags": [TAG, String(kind)],
		"damage_types": DAMAGE_TYPES.duplicate(),
		"base_damage": float(numbers.get("slimeDamage", 0.0)),
		"true_damage": true,
		"effects": [{"effect_id": KNOCKBACK_EFFECT, "potency": float(numbers.get("slimeKnockback", 0.0))}],
		"impact": {"position": area.global_position, "knock": knock},
	})
	router.end_activation(activation)


static func _strike_enemy(source: Node2D, attack_area: Area2D, area: Area2D, receiver: Object, knock: Vector2,
		kind: StringName, numbers: Dictionary) -> void:
	var router := Services.router()
	var feel_block: Dictionary = numbers.get("hit", {}) if numbers.get("hit") is Dictionary else {}
	var hit := HitReaction.build_hit(str(feel_block.get("hitClass", "thrown-heavy")), {
		"step": 0,
		"last": true,
		"tags": [TAG, String(kind)],
		"knock": knock,
		"launch_speed": float(feel_block.get("launchSpeed", 0.0)),
		"knock_px": float(feel_block.get("knockbackPx", 0.0)),
		"knock_speed_scale": float(feel_block.get("knockbackSpeedScale", 1.0)),
		"weight": "heavy",
		"big": true,
		"knock_motion": true,
		"kill_sendoff": true,
		"chains": true,
		"bowl_damage": float(feel_block.get("bowlDamage", 0.0)),
		"true_blow": true,
		"resist_floor": float(feel_block.get("resistFloor", 0.0)),
	})
	var activation := router.begin_activation(source, [attack_area])
	var request := {
		"activation_id": activation,
		"source": source,
		"attack_area": attack_area,
		"target_area": area,
		"weapon_id": "%s-%s" % [TAG, kind],
		"weapon_tags": [TAG, String(kind)],
		"damage_types": DAMAGE_TYPES.duplicate(),
		"base_damage": float(numbers.get("damage", 0.0)),
		"true_damage": true,
		"effects": [],
		"impact": {"position": area.global_position, "knock": knock},
	}
	var result: Dictionary = router.route(HitReaction.attach(request, hit))
	router.end_activation(activation)
	var feel := Services.feel()
	if feel == null or str(result.get("status", "")) != "accepted":
		return
	var at := area.global_position
	if receiver is Node and (receiver as Node).has_method(&"get_centre"):
		at = (receiver as Node).call(&"get_centre")
	feel.play_hit({
		"hit_stop_ms": float(feel_block.get("hitStopMs", 0.0)),
		"trauma": float(feel_block.get("trauma", 0.0)),
		"kick_px": float(feel_block.get("kickPx", 0.0)),
		"sparks": int(feel_block.get("sparks", 0)),
		"number": int(result.get("actual_damage", 0)),
		"number_big": true,
	}, at, knock)
