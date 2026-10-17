extends RefCounted
## What the bestiary's light-shy enemies feel of the light (docs/godot/BESTIARY.md "Light and the
## Caverns' rows"): the light sources of the Lantern's contract (group `light_sources`,
## `light_circle() -> Vector3`, game/world/fire/fire_targets.gd; docs/godot/DARKNESS.md) that reach
## a point. The Gloomling shrinks and runs from any of them, the Glint Bat wakes in them, and the
## Shardback's shell turns brittle in fire light (every source but the slime's own ember). It only
## reads the lights: nothing here changes how they work.
##
## Owner: enemy builder.

const FireTargets := preload("res://game/world/fire/fire_targets.gd")

## The slime's ember (its glow in a dark room) and the Lantern's flame, told apart by their scripts
## (paths, not preloads, so this file loads nothing of the player's).
const EMBER_SCRIPT := "res://game/player/abilities/lantern_glow.gd"
const FLAME_SCRIPT := "res://game/player/abilities/lantern_flame.gd"


## How strongly light reaches the global `point` (a body of radius `pad` there): 0 when no light
## reaches it, else up to 1 at a light's centre (the strongest light wins). `fire_only` leaves the
## slime's ember out (candles, braziers, flames, the Goo Bomb's bombs and blasts stay in).
static func light_at(tree: SceneTree, point: Vector2, pad: float = 0.0, fire_only: bool = false) -> float:
	if tree == null:
		return 0.0
	var best := 0.0
	for node: Node in tree.get_nodes_in_group(FireTargets.LIGHT_GROUP):
		if fire_only and is_ember(node):
			continue
		var reach := _reach(node, point, pad)
		if reach > best:
			best = reach
	return best


## True when a Lantern flame in flight lights the global `point` (within its light, grown by `pad`).
static func flame_at(tree: SceneTree, point: Vector2, pad: float = 0.0) -> bool:
	if tree == null:
		return false
	for node: Node in tree.get_nodes_in_group(FireTargets.LIGHT_GROUP):
		if _is_script(node, FLAME_SCRIPT) and _reach(node, point, pad) > 0.0:
			return true
	return false


## The centre of the strongest light reaching `point` (Vector2.INF when none): what a shy thing runs
## from.
static func brightest_from(tree: SceneTree, point: Vector2, pad: float = 0.0) -> Vector2:
	if tree == null:
		return Vector2.INF
	var best := 0.0
	var at := Vector2.INF
	for node: Node in tree.get_nodes_in_group(FireTargets.LIGHT_GROUP):
		var reach := _reach(node, point, pad)
		if reach > best:
			best = reach
			var circle: Vector3 = node.call(&"light_circle")
			at = Vector2(circle.x, circle.y)
	return at


## The slime's ember (lantern_glow.gd).
static func is_ember(node: Node) -> bool:
	return _is_script(node, EMBER_SCRIPT)


static func _reach(node: Node, point: Vector2, pad: float) -> float:
	if node == null or not is_instance_valid(node) or not node.has_method(&"light_circle"):
		return 0.0
	var circle: Variant = node.call(&"light_circle")
	if not (circle is Vector3):
		return 0.0
	var light := circle as Vector3
	if light.z <= 0.0:
		return 0.0
	var reach := light.z + maxf(0.0, pad)
	var distance := Vector2(light.x, light.y).distance_to(point)
	if distance > reach:
		return 0.0
	# Just inside the edge still counts a little.
	return maxf(0.05, 1.0 - distance / reach)


static func _is_script(node: Node, path: String) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var script := node.get_script() as Script
	return script != null and script.resource_path == path
