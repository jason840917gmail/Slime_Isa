extends RefCounted
## Ammo the enemies make (throw-combat experiment, docs/godot/THROW_COMBAT.md; owner, 2026-10-19:
## "enemies whose attacks knock rocks loose make ammo"). Numbers in game-constants.json
## `gulp.throwCombat.ammo`.
##
## - `knock_loose(enemy_type, at, direction)`: an enemy type listed in `rockOnAttack` (the Worm
##   Brawler) knocks a liftable of its `kind` loose with its `chance` at each melee impact,
##   `rockAheadPx` ahead of it along the swing, unless a liftable already lies within
##   `rockSpacingPx` (no piles). The rock pops up from the ground and stays until the world is built
##   again, like any liftable.
## - The spent arrows are game/throw/spent_shot.gd (laid by game/scripts/projectile.gd).
##
## Owner: throw combat (experiment).

const Services := preload("res://game/shared/services.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")

const LIFTABLE_SCENE_ID := "object.liftable"
const LIFTABLE_GROUP := &"liftable"
const POP_MS := 0.18
const POP_FROM := 0.3
const POP_DUST := &"dodge-dust"


## A melee impact of `enemy_type` at `at` (its centre) toward `direction`; true when a rock popped.
static func knock_loose(enemy_type: String, at: Vector2, direction: Vector2) -> bool:
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
	var spot := at + unit * constants.number("gulp.throwCombat.ammo.rockAheadPx")
	if _crowded(spot, constants.number("gulp.throwCombat.ammo.rockSpacingPx")):
		return false
	return spawn_liftable(str((row as Dictionary).get("kind", "rock")), spot) != null


## A liftable of `kind` popping up at `spot` (the world's entities root), or null.
static func spawn_liftable(kind: String, spot: Vector2) -> Node2D:
	var world := Services.world()
	var parent := world.entities_root() if world != null else null
	if parent == null:
		return null
	var root := world.instantiate_scene(LIFTABLE_SCENE_ID) as Node2D
	if root == null:
		return null
	root.set(&"kind", kind)
	root.set(&"under", "none")
	parent.add_child(root)
	root.global_position = spot
	var visual := root.get_node_or_null(^"Visual") as Node2D
	if visual != null:
		var size := visual.scale
		visual.scale = size * POP_FROM
		var tween := visual.create_tween()
		tween.tween_property(visual, ^"scale", size, POP_MS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
