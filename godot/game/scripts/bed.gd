extends Node
class_name BedScript
## Scene script `game.bed` (Phaser `features/scripts/BedScript.ts`; interaction spec 3.5, 6.4).
## A data holder: the interaction controller offers "Sleep" (priority 85) and puts the player to
## sleep with `sleep_request()` (game/rest/sleep_controller.gd): the body lies at the wake point in
## front of the bed while the art shows on the mattress at the sleep point; sleeping heals and
## makes this bed the respawn point.
##
## Owner: interaction.

const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

const GROUP := &"bed"

## JSON `prompt`.
@export var prompt: String = "Sleep"
## JSON `interactRadius` (> 0, else 90).
@export var interact_radius: float = 90.0
## JSON `badgeRise`.
@export var badge_rise: float = 70.0
## JSON `sleepPoint`, local to the bed root: where the art lies.
@export var sleep_point: Vector2 = Vector2(0.0, -30.0)
## JSON `wakePoint`, local to the bed root: where the body is while asleep and on waking.
@export var wake_point: Vector2 = Vector2(0.0, 28.0)


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if prompt.is_empty():
		prompt = "Sleep"
	if not (is_finite(interact_radius) and interact_radius > 0.0):
		interact_radius = 90.0
	if not is_finite(badge_rise):
		badge_rise = 70.0
	if not sleep_point.is_finite():
		sleep_point = Vector2(0.0, -30.0)
	if not wake_point.is_finite():
		wake_point = Vector2(0.0, 28.0)


## Old Phaser position of the bed (its parent).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## The persistence key of the nearest authored instance above the script (e.g.
## "world.slime-home.west-bed"), else its instance id, else the node path.
func bed_id() -> String:
	var node: Node = get_parent()
	while node != null:
		if node.has_meta(&"persistence_key"):
			return str(node.get_meta(&"persistence_key"))
		if node.has_meta(&"instance_id"):
			return str(node.get_meta(&"instance_id"))
		node = node.get_parent()
	return str(get_path())


## {"bed_id", "sleep_point", "wake_point"} with the points in old Phaser world coordinates.
func sleep_request() -> Dictionary:
	var at := origin()
	return {"bed_id": bed_id(), "sleep_point": at + sleep_point, "wake_point": at + wake_point}
