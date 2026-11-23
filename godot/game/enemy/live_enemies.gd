extends RefCounted
## The living enemies of a place, asked live (docs/godot/DUNGEONS.md "Shutters and room fights").
## Owner, 2026-11-21: "the rule to open the door should be that there are no alive enemies in the
## room. Never count the dead enemies, because I can remove or add enemies and the logic breaks."
## So every piece that opens once a room's enemies are beaten asks this, never a kill count, a
## stored or expected number, or a list of the enemies its scene held when it was made: an enemy
## added to the room in the editor holds the door, one taken out of the scene never does.
##
## - **An enemy:** an EnemyScript (game/scripts/enemy.gd, group "enemy"), whoever put it there: a
##   placed enemy's, a spawn area's, one hatched or called in during the fight (an egg sac's
##   Broodlings), a boss. One the slime carries in its mouth (gulped as ammo: out of the "enemy"
##   group, game/throw/gulpable_enemy.gd) is alive and counts, where it was taken.
## - **Living:** valid, in the tree, not being freed, not defeated (`is_defeated`, true from the
##   killing blow on: a beaten enemy whose body still lies there counts for nothing).
## - **In a place:** its centre (`get_centre`: its body's) inside the rectangle, now.
##
## Owner: enemy builder.

const ENEMY_GROUP := &"enemy"
## Gulpable enemies are suckables (game/throw/gulpable_enemy.gd): their `enemy` may be carried.
const SUCKABLE_GROUP := &"suckable"


## True while `enemy` (an EnemyScript) stands: valid, in the tree, not being freed, not defeated.
static func is_alive(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy.is_inside_tree():
		return false
	if not enemy.has_method(&"is_defeated"):
		return false
	return not bool(enemy.call(&"is_defeated"))


## Where `enemy` stands (world): its body's centre, else its own or its parent's position.
static func centre_of(enemy: Node) -> Vector2:
	var body: Variant = enemy.get(&"body")
	if enemy.has_method(&"get_centre") and is_instance_valid(body) and body is Node2D:
		return enemy.call(&"get_centre") as Vector2
	if enemy is Node2D:
		return (enemy as Node2D).global_position
	var parent := enemy.get_parent()
	return (parent as Node2D).global_position if parent is Node2D else Vector2.INF


## Every living enemy whose centre is inside `area` (world units), now.
static func in_rect(tree: SceneTree, area: Rect2) -> Array[Node]:
	var out: Array[Node] = []
	if tree == null:
		return out
	for enemy: Node in _candidates(tree):
		if is_alive(enemy) and area.has_point(centre_of(enemy)):
			out.append(enemy)
	return out


## True while at least one living enemy stands inside `area` (world units).
static func any_in_rect(tree: SceneTree, area: Rect2) -> bool:
	if tree == null:
		return false
	for enemy: Node in tree.get_nodes_in_group(ENEMY_GROUP):
		if is_alive(enemy) and area.has_point(centre_of(enemy)):
			return true
	for enemy: Node in _carried(tree):
		if is_alive(enemy) and area.has_point(centre_of(enemy)):
			return true
	return false


## The "enemy" group and the carried enemies (each once).
static func _candidates(tree: SceneTree) -> Array[Node]:
	var out: Array[Node] = []
	out.assign(tree.get_nodes_in_group(ENEMY_GROUP))
	for enemy: Node in _carried(tree):
		if not out.has(enemy):
			out.append(enemy)
	return out


## The enemies carried in the slime's mouth (out of the "enemy" group while carried).
static func _carried(tree: SceneTree) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in tree.get_nodes_in_group(SUCKABLE_GROUP):
		var enemy: Variant = node.get(&"enemy")
		if is_instance_valid(enemy) and enemy is Node and (enemy as Node).has_method(&"is_carried") \
				and bool((enemy as Node).call(&"is_carried")):
			out.append(enemy as Node)
	return out
