extends RefCounted
## The ground shaking under a heavy blow (the bestiary, docs/godot/BESTIARY.md "Hooks"): a Roll's
## bonk (heavy with the Heavy skin: docs/godot/SKINS.md), and the ground a Heavy Roll rumbles over,
## call `shake`, and every node in GROUP gets `on_ground_shake(at: Vector2, radius: float, heavy:
## bool)`. The Popworm listens (a heavy shake near its mound throws it out of the ground, dazed), and
## so does a loose prize (game/scripts/loose_prize.gd: a heavy shake knocks it down). Later shakers
## call the same function.
##
## Owner: enemy builder.

const GROUP := &"ground_shake_listeners"


## Every listener hears the shake at the ground point `at`, reaching `radius` px.
static func shake(at: Vector2, radius: float, heavy: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or radius <= 0.0:
		return
	for node: Node in tree.get_nodes_in_group(GROUP):
		if is_instance_valid(node) and node.has_method(&"on_ground_shake"):
			node.call(&"on_ground_shake", at, radius, heavy)
