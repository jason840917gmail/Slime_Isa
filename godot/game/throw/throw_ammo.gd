extends RefCounted
## Ammo the enemies make (throw-combat experiment, docs/godot/THROW_COMBAT.md; owner, 2026-10-19:
## "enemies whose attacks knock rocks loose make ammo"). Numbers in game-constants.json
## `gulp.throwCombat.ammo`.
##
## - `knock_loose(enemy_type, feet, direction, level)`: an enemy type listed in `rockOnAttack` (the
##   Worm Brawler) knocks a liftable of its `kind` loose with its `chance` at each melee impact,
##   `rockAheadPx` ahead of its feet along the swing, only where a body fits (`_fits`: on the
##   enemy's height level, not a solid tile, clear of the world's static bodies) and unless a
##   liftable already lies within `rockSpacingPx` (no piles); else nothing drops. The rock pops up
##   from the ground and stays until the world is built again, like any liftable.
## - The spent arrows are game/throw/spent_shot.gd (laid by game/scripts/projectile.gd).
##
## Owner: throw combat (experiment).

const Services := preload("res://game/shared/services.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const AbilityTerrain := preload("res://game/player/abilities/ability_terrain.gd")

const LIFTABLE_SCENE_ID := "object.liftable"
const LIFTABLE_GROUP := &"liftable"
## The pop: the look grows from POP_FROM of its size over POP_SECONDS (a presentation tween).
const POP_SECONDS := 0.18
const POP_FROM := 0.3
const POP_DUST := &"dodge-dust"
## The liftable scene's script node, and the meta on a suckable thing that says how many hits it has
## left (a sturdy thing that rebounded: game/throw/throw_rebound.gd; mouth.gd reads it).
const LIFTABLE_SCRIPT_NODE := ^"LiftableScript"
const USES_META := &"throw_uses"


## A melee impact of `enemy_type` standing with its feet at `feet` on height level `level`
## (AbilityWorld.ANY_LEVEL: the ground's at `feet`), swinging toward `direction`; true when a rock
## popped.
static func knock_loose(enemy_type: String, feet: Vector2, direction: Vector2,
		level: int = AbilityWorld.ANY_LEVEL) -> bool:
	if not ThrowMode.is_on():
		return false
	var constants := Services.constants()
	if constants == null:
		return false
	var table: Variant = constants.value("gulp.throwCombat.ammo.rockOnAttack", {})
	var row: Variant = (table as Dictionary).get(enemy_type) if table is Dictionary else null
	if not row is Dictionary or randf() >= float((row as Dictionary).get("chance", 0.0)):
		return false
	var unit := direction.normalized() if direction != Vector2.ZERO else Vector2.DOWN
	var spot := feet + unit * constants.number("gulp.throwCombat.ammo.rockAheadPx")
	if _crowded(spot, constants.number("gulp.throwCombat.ammo.rockSpacingPx")) or not _fits(spot, feet, level):
		return false
	return spawn_liftable(str((row as Dictionary).get("kind", "rock")), spot) != null


## A liftable of `kind` popping up at `spot` (the world's entities root), or null. It is placed
## before it enters the tree, so its look (LiftableScript `variant`, picked from its position) varies.
## `options` (a thrown thing that rebounded and lies there again, throw_rebound.gd): "variant" (its
## look), "weight", "uses" (the hits it has left: the meta USES_META on its LiftableScript, which the
## mouth reads when it sucks it in), "tint" (its Visual's colour, its wear) and "pop": false (it
## lands as it is: no pop, no dust).
static func spawn_liftable(kind: String, spot: Vector2, options: Dictionary = {}) -> Node2D:
	var world := Services.world()
	var parent := world.entities_root() if world != null else null
	if parent == null:
		return null
	var root := world.instantiate_scene(LIFTABLE_SCENE_ID) as Node2D
	if root == null:
		return null
	root.set(&"kind", kind)
	root.set(&"under", "none")
	if options.has("weight") and ThrowMode.WEIGHTS.has(str(options["weight"])):
		root.set(&"weight", str(options["weight"]))
	var script := root.get_node_or_null(LIFTABLE_SCRIPT_NODE)
	if script != null:
		if options.has("variant"):
			script.set(&"variant", int(options["variant"]))
		if options.has("uses"):
			script.set_meta(USES_META, int(options["uses"]))
	root.position = (parent as Node2D).to_local(spot) if parent is Node2D else spot
	parent.add_child(root)
	var visual := root.get_node_or_null(^"Visual") as Node2D
	if visual != null and options.get("tint") is Color:
		visual.modulate = options["tint"]
	if not bool(options.get("pop", true)):
		return root
	if visual != null:
		var size := visual.scale
		visual.scale = size * POP_FROM
		var tween := visual.create_tween()
		tween.tween_property(visual, ^"scale", size, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var feel := Services.feel()
	if feel != null:
		feel.particles(POP_DUST, spot)
	return root


## True when a liftable lies within `radius` of `spot`.
static func _crowded(spot: Vector2, radius: float) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for node: Node in tree.get_nodes_in_group(LIFTABLE_GROUP):
		if node.has_method(&"origin") and ((node.call(&"origin") as Vector2) - spot).length() < radius:
			return true
	return false


## `_fits` for other senders (a thrown thing's landing: thrown_object.gd, throw_rebound.gd).
static func fits(spot: Vector2, feet: Vector2, level: int = AbilityWorld.ANY_LEVEL) -> bool:
	return _fits(spot, feet, level)


## True when a body fits with its feet at `spot`: on the height level of an enemy at `feet`
## (`level`, or the ground's there; Elevation.body_fits) when the world has elevation, not on a
## solid tile, and clear of the world layer's static bodies (AbilityTerrain.is_occupied, a
## slime-sized body standing on `spot`).
static func _fits(spot: Vector2, feet: Vector2, level: int) -> bool:
	var world := Services.world()
	if world == null:
		return false
	if world.elevation != null:
		var on := level if level != AbilityWorld.ANY_LEVEL else world.elevation.level_at(feet)
		if not world.elevation.body_fits(spot, on):
			return false
	var dimensions := world.dimensions()
	if not dimensions.is_empty():
		var tile := float(dimensions["tile_size"])
		if world.is_solid_tile(floori(spot.x / tile), floori(spot.y / tile)):
			return false
	var none: Array[RID] = []
	return not AbilityTerrain.is_occupied(spot - AbilityTerrain.FEET_OFFSET, none)
