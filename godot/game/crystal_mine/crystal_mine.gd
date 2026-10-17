extends Node
class_name CrystalMine
## The Crystal Mine's world (docs/godot/DUNGEONS.md "The Crystal Mine (built)"): the node `CrystalMine`
## of `world.crystal-mine`. It keeps every placed enemy (game/enemy/placed_enemy.gd, spawned by
## EnemyPopulation, again when its room is entered again: the kit's Dungeon node) to its room: each
## one's arena (EnemyScript.configure_arena) is the camera room it stands in, so it fights while
## the slime is in that room and leaves it alone outside (the Bestiary pens' rule: a Glint Bat's
## swoop, a Watcher Eye's drift and a Gloomling's flight stay in their room).
##
## Pearl 3's glint in the Den (`pearl_glint`, seen from the stair through the Shardback's fight) goes
## once the Pearl (`pearl`) is taken, then and whenever the world is built again.
##
## Owner: dungeons (the Crystal Mine).

const PlacedEnemyScript := preload("res://game/enemy/placed_enemy.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")

## Pearl 3 and its glint (the Den).
@export var pearl: NodePath
@export var pearl_glint: NodePath

## The enemies whose arena was set, by instance id.
var _done := {}


func _ready() -> void:
	var prize := get_node_or_null(pearl)
	if prize == null:
		return
	if prize.has_method(&"is_taken") and bool(prize.call(&"is_taken")):
		_hide_glint()
	elif prize.has_signal(&"taken"):
		prize.connect(&"taken", func(_payload: Dictionary) -> void: _hide_glint())


func _hide_glint() -> void:
	var glint := get_node_or_null(pearl_glint) as CanvasItem
	if glint != null:
		glint.visible = false


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
