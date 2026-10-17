extends Node
class_name RoomArenas
## Keeps every placed enemy of a dungeon world to its room (docs/godot/DUNGEONS.md "The Weaver
## Hollow"): each placed enemy's arena (EnemyScript.configure_arena) is the camera room it stands in
## (game/world/camera_room.gd), so it fights while the slime is in that room and rests outside it:
## an egg sac hatches only for a slime in its room, a Watcher Eye drifts in its own, an enemy never
## chases through a wall into the next room. Enemies spawned again when a room is entered again (the
## kit's Dungeon node) get their arena again. The Crystal Mine's node (game/crystal_mine/crystal_mine.gd)
## does the same for its world.
##
## Owner: world (dungeons).

const PlacedEnemyScript := preload("res://game/enemy/placed_enemy.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")

## The enemies whose arena was set, by instance id.
var _done := {}


func _physics_process(_delta: float) -> void:
	for node: Node in get_tree().get_nodes_in_group(PlacedEnemyScript.GROUP):
		if not is_instance_valid(node) or not (node is PlacedEnemyScript):
			continue
		var enemy: Node = (node as PlacedEnemyScript).get_enemy()
		if enemy == null or _done.has(enemy.get_instance_id()):
			continue
		_done[enemy.get_instance_id()] = true
		var room := room_at((node as Node2D).global_position)
		if room.size != Vector2.ZERO and enemy.has_method(&"configure_arena"):
			enemy.call(&"configure_arena", {"shape": "rectangle", "x": room.position.x, "y": room.position.y,
				"w": room.size.x, "h": room.size.y})


## The camera room holding `point` (Rect2() when none).
func room_at(point: Vector2) -> Rect2:
	for node: Node in get_tree().get_nodes_in_group(CameraRoom.GROUP):
		var rect: Rect2 = node.call(&"rect")
		if rect.has_point(point):
			return rect
	return Rect2()
